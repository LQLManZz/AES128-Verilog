module Write_pointer #(
    parameter int PTR_WIDTH = 4)
    (input logic clk, rst_n, w_en,
    output logic [PTR_WIDTH-1:0] w_ptr);
    
    always_ff @ (posedge clk or negedge rst_n) begin
        if(!rst_n)
            w_ptr <= '0;
        else if (w_en) 
            w_ptr <= w_ptr+1'b1;
    end
endmodule
