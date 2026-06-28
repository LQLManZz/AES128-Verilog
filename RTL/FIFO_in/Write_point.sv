module Write_point #(
    parameter int DEPTH =16,
    parameter int PTR_WIDTH = $clog2(DEPTH)
    )(input logic clk, rst_n, w_in_en, r_in_en, full,
    output logic [PTR_WIDTH:0] w_ptr);
    logic w_inc;
    assign w_inc = w_in_en&(~full|r_in_en);
    always_ff @ (posedge clk or negedge rst_n) begin
        if(!rst_n)
            w_ptr <= '0;
        else if (w_inc) 
            w_ptr <= w_ptr+1'b1;
    end
endmodule
