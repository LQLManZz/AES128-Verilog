module AES_register(
    input logic clk,rst_n,
    input logic [1:0] data_type_in,
    input logic [127:0] data_in,
    output logic [127:0] data_out,
    output logic [1:0] data_type_out,
    output logic valid);
    
    assign valid = (data_type_in!= 2'b0);
    
    always_ff @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            data_out <= 128'b0;
            data_type_out <= 2'b0;
        end    
        else begin
            data_type_out <= data_type_in;
            if (valid)
                data_out <= data_in;
        end
    end
endmodule
