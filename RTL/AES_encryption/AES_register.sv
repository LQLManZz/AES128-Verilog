module AES_register(
    input logic clk,rst_n, Valid_in,
    input logic [127:0] data_in,
    output logic [127:0] data_out,
    output logic Valid_out);
    always_ff @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            data_out <= 128'b0;
            Valid_out<= 1'b0;
        end    
        else begin
            Valid_out <= Valid_in;
            if (Valid_in)
                data_out <= data_in;
        end
    end
endmodule
