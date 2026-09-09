//=============================================================================
// Module: uart_tx.sv
// Description: Fully synthesizable, parameterized 8N1 UART Transmitter.
//
// Parameters:
//   CLK_FREQ_HZ : System clock frequency in Hz (default: 100_000_000)
//   BAUD_RATE   : Target baud rate in bps      (default: 115_200)
//=============================================================================

`timescale 1ns / 1ps

module uart_tx #(
    parameter int CLK_FREQ_HZ = 100_000_000,
    parameter int BAUD_RATE   = 115_200
)(
    input  logic       clk,
    input  logic       rst_n,
    input  logic [7:0] tx_data,
    input  logic       tx_start,
    output logic       tx,
    output logic       tx_busy
);

    localparam int CLKS_PER_BIT = CLK_FREQ_HZ / BAUD_RATE;
    localparam int CTR_WIDTH    = $clog2(CLKS_PER_BIT + 1);

    typedef enum logic [1:0] {
        TX_IDLE,
        TX_START,
        TX_DATA,
        TX_STOP
    } tx_state_t;

    tx_state_t state;
    logic [CTR_WIDTH-1:0] clk_cnt;
    logic [2:0]           bit_idx;
    logic [7:0]           shift_reg;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state     <= TX_IDLE;
            clk_cnt   <= '0;
            bit_idx   <= '0;
            shift_reg <= 8'h00;
            tx        <= 1'b1; // Line idle high
            tx_busy   <= 1'b0;
        end else begin
            case (state)
                TX_IDLE: begin
                    tx      <= 1'b1;
                    clk_cnt <= '0;
                    bit_idx <= '0;
                    if (tx_start) begin
                        shift_reg <= tx_data;
                        tx_busy   <= 1'b1;
                        tx        <= 1'b0; // Start bit
                        state     <= TX_START;
                    end else begin
                        tx_busy <= 1'b0;
                    end
                end

                // Transmit Start Bit (0) for 1 bit period
                TX_START: begin
                    tx <= 1'b0;
                    if (clk_cnt == (CLKS_PER_BIT - 1)) begin
                        clk_cnt <= '0;
                        tx      <= shift_reg[0];
                        state   <= TX_DATA;
                    end else begin
                        clk_cnt <= clk_cnt + 1'b1;
                    end
                end

                // Transmit 8 Data Bits (LSB first)
                TX_DATA: begin
                    tx <= shift_reg[bit_idx];
                    if (clk_cnt == (CLKS_PER_BIT - 1)) begin
                        clk_cnt <= '0;
                        if (bit_idx == 3'd7) begin
                            bit_idx <= '0;
                            tx      <= 1'b1; // Stop bit
                            state   <= TX_STOP;
                        end else begin
                            bit_idx <= bit_idx + 1'b1;
                        end
                    end else begin
                        clk_cnt <= clk_cnt + 1'b1;
                    end
                end

                // Transmit Stop Bit (1) for 1 bit period
                TX_STOP: begin
                    tx <= 1'b1;
                    if (clk_cnt == (CLKS_PER_BIT - 1)) begin
                        clk_cnt <= '0;
                        tx_busy <= 1'b0;
                        state   <= TX_IDLE;
                    end else begin
                        clk_cnt <= clk_cnt + 1'b1;
                    end
                end

                default: begin
                    state <= TX_IDLE;
                end
            endcase
        end
    end

endmodule
