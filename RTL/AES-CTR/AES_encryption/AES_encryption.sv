module AES_encryption(
    input logic clk,rst_n,
    input logic [127:0] data_in,
    input logic [127:0] round_key [0:10],
    input logic [1:0] data_type_in,
    output logic [127:0] data_out,
    output logic [1:0] data_type_out,
    output logic data_req, AES_finish);
    
    logic [1:0] data_type [0:10];
    logic [127:0] data [0:10];
    logic valid [0:11];
    // first round
    AES_first_round first_round (.clk(clk),.rst_n(rst_n),.data_type_in(data_type_in),
                                .data_in(data_in),.round_key(round_key[0]),
                                .data_out(data[0]),.data_type_out(data_type[0]),
                                .valid(valid[0]));
    // AES rounds
    AES_round R1 (.clk(clk),.rst_n(rst_n),.data_type_in(data_type[0]),.data_in(data[0]),
                .round_key(round_key[1]),.data_out(data[1]),.data_type_out(data_type[1]),
                .valid(valid[1]));
    
    AES_round R2 (.clk(clk),.rst_n(rst_n),.data_type_in(data_type[1]),.data_in(data[1]),
                .round_key(round_key[2]),.data_out(data[2]),.data_type_out(data_type[2]),
                .valid(valid[2]));
    
    AES_round R3 (.clk(clk),.rst_n(rst_n),.data_type_in(data_type[2]),.data_in(data[2]),
                .round_key(round_key[3]),.data_out(data[3]),.data_type_out(data_type[3]),
                .valid(valid[3]));
    
    AES_round R4 (.clk(clk),.rst_n(rst_n),.data_type_in(data_type[3]),.data_in(data[3]),
                .round_key(round_key[4]),.data_out(data[4]),.data_type_out(data_type[4]),
                .valid(valid[4]));
    
    AES_round R5 (.clk(clk),.rst_n(rst_n),.data_type_in(data_type[4]),.data_in(data[4]),
                .round_key(round_key[5]),.data_out(data[5]),.data_type_out(data_type[5]),
                .valid(valid[5]));
    
    AES_round R6 (.clk(clk),.rst_n(rst_n),.data_type_in(data_type[5]),.data_in(data[5]),
                .round_key(round_key[6]),.data_out(data[6]),.data_type_out(data_type[6]),
                .valid(valid[6]));
    
    AES_round R7 (.clk(clk),.rst_n(rst_n),.data_type_in(data_type[6]),.data_in(data[6]),
                .round_key(round_key[7]),.data_out(data[7]),.data_type_out(data_type[7]),
                .valid(valid[7]));
    
    AES_round R8 (.clk(clk),.rst_n(rst_n),.data_type_in(data_type[7]),.data_in(data[7]),
                .round_key(round_key[8]),.data_out(data[8]),.data_type_out(data_type[8]),
                .valid(valid[8]));
    
    AES_round R9 (.clk(clk),.rst_n(rst_n),.data_type_in(data_type[8]),.data_in(data[8]),
                .round_key(round_key[9]),.data_out(data[9]),.data_type_out(data_type[9]),
                .valid(valid[9]));
    //last round
    AES_last_round last_round (.clk(clk),.rst_n(rst_n),.data_type_in(data_type[9]),
                            .data_in(data[9]),.round_key(round_key[10]),.data_out(data[10]),
                            .data_type_out(data_type[10]),.valid(valid[10]));
    // last register
    AES_register reg11 (.clk(clk),.rst_n(rst_n),.data_type_in(data_type[10]),
                        .data_in(data[10]),.data_out(data_out),.data_type_out(data_type_out),
                        .valid(valid[11]));
    assign AES_finish = ~(valid[0]|valid[1]|valid[2]|valid[3]|valid[4]|valid[5]|valid[6]
                        |valid[7]|valid[8]|valid[9]|valid[10]|valid[11]);
    assign data_req = (data_type[10] == 2'b10);
endmodule
