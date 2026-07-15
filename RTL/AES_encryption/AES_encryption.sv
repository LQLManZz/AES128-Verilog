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
    logic [127:0] ark [0:10];
    logic [127:0] sb [1:10];
    logic [127:0] sr [1:10];
    logic [127:0] mc [1:9];
    logic valid [0:11];
    // state 0
    AES_register reg0 (.clk(clk),.rst_n(rst_n),.data_type_in(data_type_in),.data_in(data_in),
                    .data_out(data[0]),.data_type_out(data_type[0]),.valid(valid[0]));
    AddRoundKeys Arkey0 (.RoundKey(round_key[0]),.AddRoundKeys_in(data[0]),
                        .AddRoundKeys_out(ark[0]));
    // state 1
    AES_register reg1 (.clk(clk),.rst_n(rst_n),.data_type_in(data_type[0]),.data_in(ark[0]),
                    .data_out(data[1]),.data_type_out(data_type[1]),.valid(valid[1]));
    SubBytes Sbyte1 (.SubBytes_in(data[1]),.SubBytes_out(sb[1]));
    ShiftRows SRow1 (.ShiftRows_in(sb[1]),.ShiftRows_out(sr[1]));
    MixColumns Mcolumn1 (.MixColumns_in(sr[1]),.MixColumns_out(mc[1]));
    AddRoundKeys Arkey1 (.RoundKey(round_key[1]),.AddRoundKeys_in(mc[1]),
                        .AddRoundKeys_out(ark[1]));
    // state 2
    AES_register reg2 (.clk(clk),.rst_n(rst_n),.data_type_in(data_type[1]),.data_in(ark[1]),
                    .data_out(data[2]),.data_type_out(data_type[2]),.valid(valid[2]));
    SubBytes Sbyte2 (.SubBytes_in(data[2]),.SubBytes_out(sb[2]));
    ShiftRows SRow2 (.ShiftRows_in(sb[2]),.ShiftRows_out(sr[2]));
    MixColumns Mcolumn2 (.MixColumns_in(sr[2]),.MixColumns_out(mc[2]));
    AddRoundKeys Arkey2 (.RoundKey(round_key[2]),.AddRoundKeys_in(mc[2]),
                        .AddRoundKeys_out(ark[2]));
    // state 3
    AES_register reg3 (.clk(clk),.rst_n(rst_n),.data_type_in(data_type[2]),.data_in(ark[2]),
                    .data_out(data[3]),.data_type_out(data_type[3]),.valid(valid[3]));
    SubBytes Sbyte3 (.SubBytes_in(data[3]),.SubBytes_out(sb[3]));
    ShiftRows SRow3 (.ShiftRows_in(sb[3]),.ShiftRows_out(sr[3]));
    MixColumns Mcolumn3 (.MixColumns_in(sr[3]),.MixColumns_out(mc[3]));
    AddRoundKeys Arkey3 (.RoundKey(round_key[3]),.AddRoundKeys_in(mc[3]),
                        .AddRoundKeys_out(ark[3]));
    // state 4
    AES_register reg4 (.clk(clk),.rst_n(rst_n),.data_type_in(data_type[3]),.data_in(ark[3]),
                    .data_out(data[4]),.data_type_out(data_type[4]),.valid(valid[4]));
    SubBytes Sbyte4 (.SubBytes_in(data[4]),.SubBytes_out(sb[4]));
    ShiftRows SRow4 (.ShiftRows_in(sb[4]),.ShiftRows_out(sr[4]));
    MixColumns Mcolumn4 (.MixColumns_in(sr[4]),.MixColumns_out(mc[4]));
    AddRoundKeys Arkey4 (.RoundKey(round_key[4]),.AddRoundKeys_in(mc[4]),
                        .AddRoundKeys_out(ark[4]));
    // state 5
    AES_register reg5 (.clk(clk),.rst_n(rst_n),.data_type_in(data_type[4]),.data_in(ark[4]),
                    .data_out(data[5]),.data_type_out(data_type[5]),.valid(valid[5]));
    SubBytes Sbyte5 (.SubBytes_in(data[5]),.SubBytes_out(sb[5]));
    ShiftRows SRow5 (.ShiftRows_in(sb[5]),.ShiftRows_out(sr[5]));
    MixColumns Mcolumn5 (.MixColumns_in(sr[5]),.MixColumns_out(mc[5]));
    AddRoundKeys Arkey5 (.RoundKey(round_key[5]),.AddRoundKeys_in(mc[5]),
                        .AddRoundKeys_out(ark[5]));
    // state 6
    AES_register reg6 (.clk(clk),.rst_n(rst_n),.data_type_in(data_type[5]),.data_in(ark[5]),
                    .data_out(data[6]),.data_type_out(data_type[6]),.valid(valid[6]));
    SubBytes Sbyte6 (.SubBytes_in(data[6]),.SubBytes_out(sb[6]));
    ShiftRows SRow6 (.ShiftRows_in(sb[6]),.ShiftRows_out(sr[6]));
    MixColumns Mcolumn6 (.MixColumns_in(sr[6]),.MixColumns_out(mc[6]));
    AddRoundKeys Arkey6 (.RoundKey(round_key[6]),.AddRoundKeys_in(mc[6]),
                        .AddRoundKeys_out(ark[6]));
    // state 7
    AES_register reg7 (.clk(clk),.rst_n(rst_n),.data_type_in(data_type[6]),.data_in(ark[6]),
                    .data_out(data[7]),.data_type_out(data_type[7]),.valid(valid[7]));
    SubBytes Sbyte7 (.SubBytes_in(data[7]),.SubBytes_out(sb[7]));
    ShiftRows SRow7 (.ShiftRows_in(sb[7]),.ShiftRows_out(sr[7]));
    MixColumns Mcolumn7 (.MixColumns_in(sr[7]),.MixColumns_out(mc[7]));
    AddRoundKeys Arkey7 (.RoundKey(round_key[7]),.AddRoundKeys_in(mc[7]),
                        .AddRoundKeys_out(ark[7]));
    // state 8
    AES_register reg8 (.clk(clk),.rst_n(rst_n),.data_type_in(data_type[7]),.data_in(ark[7]),
                    .data_out(data[8]),.data_type_out(data_type[8]),.valid(valid[8]));
    SubBytes Sbyte8 (.SubBytes_in(data[8]),.SubBytes_out(sb[8]));
    ShiftRows SRow8 (.ShiftRows_in(sb[8]),.ShiftRows_out(sr[8]));
    MixColumns Mcolumn8 (.MixColumns_in(sr[8]),.MixColumns_out(mc[8]));
    AddRoundKeys Arkey8 (.RoundKey(round_key[8]),.AddRoundKeys_in(mc[8]),
                        .AddRoundKeys_out(ark[8]));
    // state 9
    AES_register reg9 (.clk(clk),.rst_n(rst_n),.data_type_in(data_type[8]),.data_in(ark[8]),
                    .data_out(data[9]),.data_type_out(data_type[9]),.valid(valid[9]));
    SubBytes Sbyte9 (.SubBytes_in(data[9]),.SubBytes_out(sb[9]));
    ShiftRows SRow9 (.ShiftRows_in(sb[9]),.ShiftRows_out(sr[9]));
    MixColumns Mcolumn9 (.MixColumns_in(sr[9]),.MixColumns_out(mc[9]));
    AddRoundKeys Arkey9 (.RoundKey(round_key[9]),.AddRoundKeys_in(mc[9]),
                        .AddRoundKeys_out(ark[9]));
    // state 10
    AES_register reg10 (.clk(clk),.rst_n(rst_n),.data_type_in(data_type[9]),.data_in(ark[9]),
                    .data_out(data[10]),.data_type_out(data_type[10]),.valid(valid[10]));
    SubBytes Sbyte10 (.SubBytes_in(data[10]),.SubBytes_out(sb[10]));
    ShiftRows SRow10 (.ShiftRows_in(sb[10]),.ShiftRows_out(sr[10]));
    AddRoundKeys Arkey10 (.RoundKey(round_key[10]),.AddRoundKeys_in(sr[10]),
                        .AddRoundKeys_out(ark[10]));
    // last register
    AES_register reg11 (.clk(clk),.rst_n(rst_n),.data_type_in(data_type[10]),.data_in(ark[10]),
                        .data_out(data_out),.data_type_out(data_type_out),.valid(valid[11]));
    assign AES_finish = ~(valid[0]|valid[1]|valid[2]|valid[3]|valid[4]|valid[5]|valid[6]|valid[7]|valid[8]|valid[9]|valid[10]|valid[11]);
    assign data_req = (data_type[10] == 2'b10);
endmodule
