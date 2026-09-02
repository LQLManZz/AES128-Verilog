module type_generator(
    input logic clk, rst_n,
    input logic load_key,load_data,
    input logic gen_J0,
    output logic [1:0] data_type
    );
    
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n)
            data_type<=  2'b0;
        else begin
            if(load_key)
                data_type <= 2'b01;
            else begin
                if(load_data)
                    data_type <= 2'b10;
                else begin
                    if(gen_J0)
                        data_type <= 2'b11;
                    else
                        data_type <= 2'b00;
                end
            end
        end
    end
endmodule
