//=============================================================================
// Module: uart_rx.sv
// Directory: uart_integration/common/
// Description: Shared, fully synthesizable, parameterized 8N1 UART Receiver
//              with double-register metastability synchronization and 
//              midpoint bit sampling.
//
// Parameters:
//   CLK_FREQ_HZ : System clock frequency in Hz (default: 100_000_000)
//   BAUD_RATE   : Target baud rate in bps      (default: 115_200)
//=============================================================================

`timescale 1ns / 1ps

module uart_rx #(
    parameter int CLK_FREQ_HZ = 100_000_000,
    parameter int BAUD_RATE   = 115_200
)(
    input  logic       clk,
    input  logic       rst_n,
    input  logic       rx,
    output logic [7:0] rx_data,
    output logic       rx_valid
);

    localparam int CLKS_PER_BIT = CLK_FREQ_HZ / BAUD_RATE;
    localparam int CTR_WIDTH    = $clog2(CLKS_PER_BIT + 1);

    typedef enum logic [1:0] {
        RX_IDLE,
        RX_START,
        RX_DATA,
        RX_STOP
    } rx_state_t;

    rx_state_t state;
    logic [CTR_WIDTH-1:0] clk_cnt;
    logic [2:0]           bit_idx;
    logic [7:0]           shift_reg;

    // 2-stage input synchronizer to eliminate metastability
    logic rx_sync_stage1;
    logic rx_sync;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rx_sync_stage1 <= 1'b1;
            rx_sync        <= 1'b1;
        end else begin
            rx_sync_stage1 <= rx;
            rx_sync        <= rx_sync_stage1;
        end
    end

    // UART RX State Machine
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state     <= RX_IDLE;
            clk_cnt   <= '0;
            bit_idx   <= '0;
            shift_reg <= 8'h00;
            rx_data   <= 8'h00;
            rx_valid  <= 1'b0;
        end else begin
            rx_valid <= 1'b0; // Default: 1-clock pulse

            case (state)
                RX_IDLE: begin
                    clk_cnt <= '0;
                    bit_idx <= '0;
                    // Detect falling edge of start bit
                    if (rx_sync == 1'b0) begin
                        state   <= RX_START;
                        clk_cnt <= '0;
                    end
                end

                // Sample in the middle of start bit to confirm validity
                RX_START: begin
                    if (clk_cnt == ((CLKS_PER_BIT - 1) / 2)) begin
                        if (rx_sync == 1'b0) begin
                            // Valid start bit confirmed
                            clk_cnt <= '0;
                            state   <= RX_DATA;
                        end else begin
                            // Glitch / false start bit
                            state   <= RX_IDLE;
                        end
                    end else begin
                        clk_cnt <= clk_cnt + 1'b1;
                    end
                end

                // Receive 8 data bits (LSB first)
                RX_DATA: begin
                    if (clk_cnt == (CLKS_PER_BIT - 1)) begin
                        clk_cnt              <= '0;
                        shift_reg[bit_idx]   <= rx_sync;
                        if (bit_idx == 3'd7) begin
                            bit_idx <= '0;
                            state   <= RX_STOP;
                        end else begin
                            bit_idx <= bit_idx + 1'b1;
                        end
                    end else begin
                        clk_cnt <= clk_cnt + 1'b1;
                    end
                end

                // Sample stop bit (must be high)
                RX_STOP: begin
                    if (clk_cnt == (CLKS_PER_BIT - 1)) begin
                        clk_cnt <= '0;
                        state   <= RX_IDLE;
                        if (rx_sync == 1'b1) begin
                            rx_data  <= shift_reg;
                            rx_valid <= 1'b1;
                        end
                    end else begin
                        clk_cnt <= clk_cnt + 1'b1;
                    end
                end

                default: begin
                    state <= RX_IDLE;
                end
            endcase
        end
    end

endmodule
