//=============================================================================
// Module: spi_link.sv
// Directory: realtime_env/rtl/common/
// Description: SPI slave link layer (mode 0, MSB first) for aes_gcm_engine.
//              The shift registers run on spi_sclk, so SCLK may exceed clk / 4.
//              Whole bytes cross into clk through toggle synchronizers, which
//              is safe while a byte lasts longer than about 100 ns (SCLK < 70 MHz).
//
// Frame (one spi_cs_n low period):
//   First MOSI byte: OP_DATA  the next MOSI bytes go to the engine
//                    OP_READ  the next MOSI bytes are ignored
//                    OP_CLEAR on spi_cs_n rising: resets the engine and both FIFOs
//   First MISO byte: STATUS = {4'hA, 1'b0, bad_op, tx_overflow, rx_overflow}
//   Next MISO bytes: responses from the TX FIFO, 8'h00 when it is empty
//=============================================================================

`timescale 1ns / 1ps

module spi_link #(
    parameter int TX_FIFO_DEPTH = 2048
)(
    input  logic       clk,
    input  logic       rst_n,

    // SPI physical pins
    input  logic       spi_sclk,
    input  logic       spi_cs_n,
    input  logic       spi_mosi,
    output logic       spi_miso,

    // Bytes to the engine
    output logic [7:0] rx_data,
    output logic       rx_valid,
    input  logic       rx_overflow,

    // Bytes from the engine
    input  logic [7:0] tx_data,
    input  logic       tx_start,
    output logic       tx_busy,

    // Reset for the engine: rst_n released synchronously, or an OP_CLEAR frame
    output logic       engine_rst_n
);

    localparam logic [7:0] OP_DATA  = 8'hA5;
    localparam logic [7:0] OP_READ  = 8'h5A;
    localparam logic [7:0] OP_CLEAR = 8'hC3;

    //-------------------------------------------------------------------------
    // spi_sclk domain
    //-------------------------------------------------------------------------
    logic [2:0] bit_cnt;
    logic       first_byte;
    logic [6:0] mosi_shift;
    logic [7:0] sclk_byte;      // Stable for 8 SCLK periods after rx_toggle flips
    logic       sclk_is_op;
    logic       rx_toggle;
    logic       tx_toggle;
    logic [7:0] miso_byte;
    logic       miso_reg;

    logic [7:0] status_hold;    // clk domain, frozen while spi_cs_n is low
    logic [7:0] tx_hold;        // clk domain, settled long before the byte boundary

    always_ff @(posedge spi_sclk or posedge spi_cs_n) begin
        if (spi_cs_n) begin
            bit_cnt    <= 3'd0;
            first_byte <= 1'b1;
        end else begin
            bit_cnt <= bit_cnt + 1'b1;
            if (bit_cnt == 3'd7) first_byte <= 1'b0;
        end
    end

    always_ff @(posedge spi_sclk or negedge rst_n) begin
        if (!rst_n) begin
            mosi_shift <= 7'd0;
            sclk_byte  <= 8'h00;
            sclk_is_op <= 1'b0;
            rx_toggle  <= 1'b0;
            tx_toggle  <= 1'b0;
            miso_byte  <= 8'h00;
        end else begin
            mosi_shift <= {mosi_shift[5:0], spi_mosi};
            if (bit_cnt == 3'd7) begin
                sclk_byte  <= {mosi_shift, spi_mosi};
                sclk_is_op <= first_byte;
                rx_toggle  <= ~rx_toggle;
                miso_byte  <= tx_hold;
            end
            // Counted once the master has taken the first bit: a byte loaded at
            // the end of a frame is never shifted out, so it must not be lost.
            if ((bit_cnt == 3'd0) && !first_byte) tx_toggle <= ~tx_toggle;
        end
    end

    // The next bit leaves on the edge the master samples, which gives the round
    // trip a whole SCLK period: clock-to-out is the master's hold time.
    always_ff @(posedge spi_sclk or posedge spi_cs_n) begin
        if (spi_cs_n)             miso_reg <= 1'b1;     // STATUS[7]: needs no SCLK edge
        else if (bit_cnt == 3'd7) miso_reg <= tx_hold[7];
        else if (first_byte)      miso_reg <= status_hold[3'd6 - bit_cnt];
        else                      miso_reg <= miso_byte[3'd6 - bit_cnt];
    end

    assign spi_miso = miso_reg;

    //-------------------------------------------------------------------------
    // clk domain: synchronizers
    //-------------------------------------------------------------------------
    logic [2:0] rx_sync;
    logic [2:0] tx_sync;
    logic [3:0] cs_sync;
    logic       byte_event, taken_event, frame_high, frame_end;

    assign byte_event  = rx_sync[2] ^ rx_sync[1];
    assign taken_event = tx_sync[2] ^ tx_sync[1];
    assign frame_high  = cs_sync[1];
    // One cycle behind byte_event, so the frame's last byte is seen first
    assign frame_end   = (cs_sync[3:2] == 2'b01);

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rx_sync <= 3'd0;
            tx_sync <= 3'd0;
            cs_sync <= 4'hF;
        end else begin
            rx_sync <= {rx_sync[1:0], rx_toggle};
            tx_sync <= {tx_sync[1:0], tx_toggle};
            cs_sync <= {cs_sync[2:0], spi_cs_n};
        end
    end

    //-------------------------------------------------------------------------
    // clk domain: frame decoding
    //-------------------------------------------------------------------------
    logic [7:0] frame_op;
    logic       rx_overflow_flag;
    logic       tx_overflow_flag;
    logic       bad_op_flag;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            engine_rst_n <= 1'b0;
            frame_op     <= OP_READ;
            rx_data      <= 8'h00;
            rx_valid     <= 1'b0;
        end else begin
            engine_rst_n <= !(frame_end && (frame_op == OP_CLEAR));
            rx_valid     <= 1'b0;

            if (byte_event) begin
                if (sclk_is_op) begin
                    frame_op <= sclk_byte;
                end else if (frame_op == OP_DATA) begin
                    rx_data  <= sclk_byte;
                    rx_valid <= 1'b1;
                end
            end

            if (frame_end) frame_op <= OP_READ;
        end
    end

    logic op_rejected;
    assign op_rejected = byte_event && sclk_is_op &&
                         (sclk_byte != OP_DATA) && (sclk_byte != OP_READ) && (sclk_byte != OP_CLEAR);

    //-------------------------------------------------------------------------
    // clk domain: TX path
    //-------------------------------------------------------------------------
    logic [7:0] fifo_byte;
    logic       fifo_empty;
    logic       fifo_full;
    logic       fifo_read;
    logic       hold_valid;
    logic       tx_start_d;

    // uart_tx style handshake: busy for a cycle after each byte, longer while full
    assign tx_busy = tx_start_d | fifo_full;

    byte_fifo #(
        .DEPTH(TX_FIFO_DEPTH)
    ) u_tx_fifo (
        .clk    (clk),
        .rst_n  (engine_rst_n),
        .wr_data(tx_data),
        .wr_en  (tx_start),
        .full   (fifo_full),
        .rd_data(fifo_byte),
        .rd_en  (fifo_read),
        .empty  (fifo_empty)
    );

    // tx_hold only changes right after the master took a byte, or between
    // frames, so the byte-boundary sample in the spi_sclk domain never sees it move.
    assign fifo_read = !fifo_empty && (taken_event || (frame_high && !hold_valid));

    always_ff @(posedge clk or negedge engine_rst_n) begin
        if (!engine_rst_n) begin
            tx_hold          <= 8'h00;
            hold_valid       <= 1'b0;
            tx_start_d       <= 1'b0;
            status_hold      <= 8'hA0;
            rx_overflow_flag <= 1'b0;
            tx_overflow_flag <= 1'b0;
            bad_op_flag      <= 1'b0;
        end else begin
            tx_start_d <= tx_start;

            if (fifo_read) begin
                tx_hold    <= fifo_byte;
                hold_valid <= 1'b1;
            end else if (taken_event) begin
                tx_hold    <= 8'h00;
                hold_valid <= 1'b0;
            end

            if (rx_overflow) rx_overflow_flag <= 1'b1;
            if (fifo_full)   tx_overflow_flag <= 1'b1;
            if (op_rejected) bad_op_flag      <= 1'b1;

            if (frame_high) begin
                status_hold <= {4'hA, 1'b0, bad_op_flag, tx_overflow_flag, rx_overflow_flag};
            end
        end
    end

endmodule
