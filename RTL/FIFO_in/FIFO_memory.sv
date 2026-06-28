module FIFO_memory#(
    parameter int DEPTH =16,
    parameter int PTR_WIDTH = $clog2(DEPTH)
    )(input logic clk,
    input logic r_in_en, w_in_en,
    input logic [PTR_WIDTH:0] r_ptr, w_ptr,
    input logic [127:0] data_in,
    output logic [127:0] data_out);
    logic [127:0] memory_array [0:DEPTH-1];
    always_ff @(posedge clk ) begin
        if (w_in_en)
            memory_array[w_ptr[PTR_WIDTH-1:0]] <= data_in;
        if (r_in_en)
            data_out <= memory_array[r_ptr[PTR_WIDTH-1:0]];
    end
endmodule
