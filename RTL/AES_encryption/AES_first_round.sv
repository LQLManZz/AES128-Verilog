module AES_first_round(
    input logic clk,rst_n,
    input logic [1:0] data_type_in,
    input logic [127:0] data_in,
    input logic [127:0] round_key,
    output logic [127:0] data_out,
    output logic [1:0] data_type_out,
    output logic valid);
    
    logic [127:0] register_out;
    AES_register AES_reg (.clk(clk),.rst_n(rst_n),.data_type_in(data_type_in),.data_in(data_in),
                    .data_out(register_out),.data_type_out(data_type_out),.valid(valid));
    AddRoundKeys ARK (.RoundKey(round_key),.AddRoundKeys_in(register_out),
                    .AddRoundKeys_out(data_out));
endmodule
