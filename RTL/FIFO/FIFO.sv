module FIFO#(
    parameter int DATA_SIZE = 128,
    parameter int DEPTH = 16,
    parameter int PTR_WIDTH = $clog2(DEPTH)
    )(
    input logic clk, rst_n,
    input logic [DATA_SIZE-1:0] data_in,
    input logic r_en, w_en,
    output logic [DATA_SIZE-1 :0] data_out,
    output logic empty, full);
    
    logic [PTR_WIDTH:0] w_ptr, r_ptr;
    Write_pointer#(.PTR_WIDTH(PTR_WIDTH)) W_p
                    (.clk(clk),.rst_n(rst_n),.r_en(r_en),.w_en(w_en),
                    .full(full),.w_ptr(w_ptr));
    Read_pointer #(.PTR_WIDTH(PTR_WIDTH)) R_p 
                    (.clk(clk),.rst_n(rst_n),.r_en(r_en),.r_ptr(r_ptr));
    FIFO_memory #(.DATA_SIZE(DATA_SIZE),.DEPTH(DEPTH),.PTR_WIDTH(PTR_WIDTH)) F_mem
                        (.clk(clk),.r_en(r_en),.w_en(w_en),
                        .r_ptr(r_ptr), .w_ptr(w_ptr), .data_in(data_in),.data_out(data_out));
    Flag_generator #(.PTR_WIDTH(PTR_WIDTH)) F_gen 
    (.r_ptr(r_ptr), .w_ptr(w_ptr), .empty(empty), .full(full));
endmodule
