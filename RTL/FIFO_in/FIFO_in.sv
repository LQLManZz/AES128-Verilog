module FIFO_in#(
    parameter int DEPTH =16,
    parameter int PTR_WIDTH = $clog2(DEPTH)
    )(
    input logic clk, rst_n,
    input logic [127:0] data_in,
    input logic r_in_en, w_in_en,
    output logic [127:0] data_out,
    output logic empty, full);
    
    logic [PTR_WIDTH:0] w_ptr, r_ptr;
    Write_point W_p (.clk(clk), .rst_n(rst_n),.r_in_en(r_in_en), .w_in_en(w_in_en),
                    .full(full), .w_ptr(w_ptr));
    Read_point R_p (.clk(clk), .rst_n(rst_n), .r_in_en(r_in_en), .r_ptr(r_ptr));
    FIFO_memory F_mem (.clk(clk), .r_in_en(r_in_en), .w_in_en(w_in_en),
                        .r_ptr(r_ptr), .w_ptr(w_ptr), .data_in(data_in),
                        .data_out(data_out));
    Flag_generate F_gen (.r_ptr(r_ptr), .w_ptr(w_ptr), .empty(empty), .full(full));
endmodule
