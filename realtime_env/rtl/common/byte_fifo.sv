//=============================================================================
// Module: byte_fifo.sv
// Directory: realtime_env/rtl/common/
// Description: Single-clock byte FIFO with first-word fall-through. The read
//              is registered so the memory infers as PolarFire block RAM.
//              rd_data is valid while empty is low; rd_en moves to the next byte.
//=============================================================================

`timescale 1ns / 1ps

module byte_fifo #(
    parameter int DEPTH = 2048
)(
    input  logic       clk,
    input  logic       rst_n,

    input  logic [7:0] wr_data,
    input  logic       wr_en,      // Ignored while full
    output logic       full,

    output logic [7:0] rd_data,
    input  logic       rd_en,      // Only while empty is low
    output logic       empty
);

    localparam int ADDR_WIDTH = $clog2(DEPTH);

    logic [7:0]            mem [0:DEPTH-1];
    logic [ADDR_WIDTH-1:0] wr_ptr;
    logic [ADDR_WIDTH-1:0] rd_ptr, rd_ptr_next;
    logic [ADDR_WIDTH:0]   count;
    logic                  rd_valid;
    logic                  do_write;

    assign full        = (count == DEPTH);
    assign empty       = !rd_valid;
    assign do_write    = wr_en && !full;
    assign rd_ptr_next = rd_ptr + rd_en;

    always_ff @(posedge clk) begin
        if (do_write) mem[wr_ptr] <= wr_data;
        rd_data <= mem[rd_ptr_next];
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wr_ptr   <= '0;
            rd_ptr   <= '0;
            count    <= '0;
            rd_valid <= 1'b0;
        end else begin
            if (do_write) wr_ptr <= wr_ptr + 1'b1;
            rd_ptr   <= rd_ptr_next;
            count    <= count + do_write - rd_en;
            // A byte written on this edge is not readable until the next one
            rd_valid <= (count - rd_en) != 0;
        end
    end

endmodule
