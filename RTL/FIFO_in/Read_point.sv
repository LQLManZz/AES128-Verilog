module Read_point#(
    parameter int  DEPTH =16,
    parameter int PTR_WIDTH = $clog2(DEPTH)
    )(input logic clk, rst_n,r_in_en,
    output logic [PTR_WIDTH:0] r_ptr);
    always_ff @(posedge clk or negedge rst_n) begin
        if(!rst_n) 
            r_ptr <= '0;
        else if(r_in_en)
            r_ptr <= r_ptr + 1'b1;
    end
endmodule
