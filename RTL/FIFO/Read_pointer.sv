module Read_pointer#(
    parameter int PTR_WIDTH = 4)
    (input logic clk, rst_n,r_en,
    output logic [PTR_WIDTH:0] r_ptr);
    always_ff @(posedge clk or negedge rst_n) begin
        if(!rst_n) 
            r_ptr <= '0;
        else if(r_en)
            r_ptr <= r_ptr + 1'b1;
    end
endmodule
