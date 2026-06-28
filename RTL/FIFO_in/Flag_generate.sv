module Flag_generate#(
    parameter int DEPTH =16,
    parameter int PTR_WIDTH = $clog2(DEPTH)
    )(input logic [PTR_WIDTH:0] r_ptr, w_ptr,
    output logic empty,full);
    logic addr_compare, MSB_compare;
    assign addr_compare = (r_ptr[PTR_WIDTH-1:0]==w_ptr[PTR_WIDTH-1:0]);
    assign MSB_compare = (r_ptr[PTR_WIDTH] == w_ptr[PTR_WIDTH]);
    assign empty = addr_compare & MSB_compare;
    assign full = addr_compare & (~MSB_compare);
endmodule
