module AES_encryption(
    input logic clk,rst_n,
    input logic encryption_en,
    input logic [127:0] data_in,
    input logic [127:0] round_key [0:10],
    output logic [127:0] data_out,
    output logic encryption_finish);
    
    logic Valid_out0, Valid_out1, Valid_out2, Valid_out3, Valid_out4, Valid_out5, Valid_out6;
    logic Valid_out7, Valid_out8, Valid_out9, Valid_out10;
    logic [127:0] data0, data1, data2, data3, data4, data5, data6, data7, data8, data9, data10;
    logic [127:0] ark0, ark1, ark2, ark3, ark4, ark5, ark6, ark7, ark8, ark9;
    logic [127:0] sb1, sb2, sb3, sb4, sb5, sb6, sb7, sb8, sb9, sb10;
    logic [127:0] sr1, sr2, sr3, sr4, sr5, sr6, sr7, sr8, sr9, sr10;
    logic [127:0] mcl1, mcl2, mcl3, mcl4, mcl5, mcl6, mcl7, mcl8, mcl9;
    // state 0
    AES_register reg0 (.clk(clk),.rst_n(rst_n),.Valid_in(encryption_en),.data_in(data_in),
                    .data_out(data0),.Valid_out(Valid_out0));
    AddRoundKeys Arkey0 (.RoundKey(round_key[0]),.AddRoundKeys_in(data0),.AddRoundKeys_out(ark0));
    // state 1
    AES_register reg1 (.clk(clk),.rst_n(rst_n),.Valid_in(Valid_out0),.data_in(ark0),
                    .data_out(data1),.Valid_out(Valid_out1));
    SubBytes Sbyte1 (.SubBytes_in(data1),.SubBytes_out(sb1));
    ShiftRows SRow1 (.ShiftRows_in(sb1),.ShiftRows_out(sr1));
    MixColumns Mcolumn1 (.MixColumns_in(sr1),.MixColumns_out(mcl1));
    AddRoundKeys Arkey1 (.RoundKey(round_key[1]),.AddRoundKeys_in(mcl1),.AddRoundKeys_out(ark1));
    // state 2
    AES_register reg2 (.clk(clk),.rst_n(rst_n),.Valid_in(Valid_out1),.data_in(ark1),
                    .data_out(data2),.Valid_out(Valid_out2));
    SubBytes Sbyte2 (.SubBytes_in(data2),.SubBytes_out(sb2));
    ShiftRows SRow2 (.ShiftRows_in(sb2),.ShiftRows_out(sr2));
    MixColumns Mcolumn2 (.MixColumns_in(sr2),.MixColumns_out(mcl2));
    AddRoundKeys Arkey2 (.RoundKey(round_key[2]),.AddRoundKeys_in(mcl2),.AddRoundKeys_out(ark2));
    // state 3
    AES_register reg3 (.clk(clk),.rst_n(rst_n),.Valid_in(Valid_out2),.data_in(ark2),
                    .data_out(data3),.Valid_out(Valid_out3));
    SubBytes Sbyte3 (.SubBytes_in(data3),.SubBytes_out(sb3));
    ShiftRows SRow3 (.ShiftRows_in(sb3),.ShiftRows_out(sr3));
    MixColumns Mcolumn3 (.MixColumns_in(sr3),.MixColumns_out(mcl3));
    AddRoundKeys Arkey3 (.RoundKey(round_key[3]),.AddRoundKeys_in(mcl3),.AddRoundKeys_out(ark3));
    // state 4
    AES_register reg4 (.clk(clk),.rst_n(rst_n),.Valid_in(Valid_out3),.data_in(ark3),
                    .data_out(data4),.Valid_out(Valid_out4));
    SubBytes Sbyte4 (.SubBytes_in(data4),.SubBytes_out(sb4));
    ShiftRows SRow4 (.ShiftRows_in(sb4),.ShiftRows_out(sr4));
    MixColumns Mcolumn4 (.MixColumns_in(sr4),.MixColumns_out(mcl4));
    AddRoundKeys Arkey4 (.RoundKey(round_key[4]),.AddRoundKeys_in(mcl4),.AddRoundKeys_out(ark4));
    // state 5
    AES_register reg5 (.clk(clk),.rst_n(rst_n),.Valid_in(Valid_out4),.data_in(ark4),
                    .data_out(data5),.Valid_out(Valid_out5));
    SubBytes Sbyte5 (.SubBytes_in(data5),.SubBytes_out(sb5));
    ShiftRows SRow5 (.ShiftRows_in(sb5),.ShiftRows_out(sr5));
    MixColumns Mcolumn5 (.MixColumns_in(sr5),.MixColumns_out(mcl5));
    AddRoundKeys Arkey5 (.RoundKey(round_key[5]),.AddRoundKeys_in(mcl5),.AddRoundKeys_out(ark5));
    // state 6
    AES_register reg6 (.clk(clk),.rst_n(rst_n),.Valid_in(Valid_out5),.data_in(ark5),
                    .data_out(data6),.Valid_out(Valid_out6));
    SubBytes Sbyte6 (.SubBytes_in(data6),.SubBytes_out(sb6));
    ShiftRows SRow6 (.ShiftRows_in(sb6),.ShiftRows_out(sr6));
    MixColumns Mcolumn6 (.MixColumns_in(sr6),.MixColumns_out(mcl6));
    AddRoundKeys Arkey6 (.RoundKey(round_key[6]),.AddRoundKeys_in(mcl6),.AddRoundKeys_out(ark6));
    // state 7
    AES_register reg7 (.clk(clk),.rst_n(rst_n),.Valid_in(Valid_out6),.data_in(ark6),
                    .data_out(data7),.Valid_out(Valid_out7));
    SubBytes Sbyte7 (.SubBytes_in(data7),.SubBytes_out(sb7));
    ShiftRows SRow7 (.ShiftRows_in(sb7),.ShiftRows_out(sr7));
    MixColumns Mcolumn7 (.MixColumns_in(sr7),.MixColumns_out(mcl7));
    AddRoundKeys Arkey7 (.RoundKey(round_key[7]),.AddRoundKeys_in(mcl7),.AddRoundKeys_out(ark7));
    // state 8
    AES_register reg8 (.clk(clk),.rst_n(rst_n),.Valid_in(Valid_out7),.data_in(ark7),
                    .data_out(data8),.Valid_out(Valid_out8));
    SubBytes Sbyte8 (.SubBytes_in(data8),.SubBytes_out(sb8));
    ShiftRows SRow8 (.ShiftRows_in(sb8),.ShiftRows_out(sr8));
    MixColumns Mcolumn8 (.MixColumns_in(sr8),.MixColumns_out(mcl8));
    AddRoundKeys Arkey8 (.RoundKey(round_key[8]),.AddRoundKeys_in(mcl8),.AddRoundKeys_out(ark8));
    // state 9
    AES_register reg9 (.clk(clk),.rst_n(rst_n),.Valid_in(Valid_out8),.data_in(ark8),
                    .data_out(data9),.Valid_out(Valid_out9));
    SubBytes Sbyte9 (.SubBytes_in(data9),.SubBytes_out(sb9));
    ShiftRows SRow9 (.ShiftRows_in(sb9),.ShiftRows_out(sr9));
    MixColumns Mcolumn9 (.MixColumns_in(sr9),.MixColumns_out(mcl9));
    AddRoundKeys Arkey9 (.RoundKey(round_key[9]),.AddRoundKeys_in(mcl9),.AddRoundKeys_out(ark9));
    // state 10
    AES_register reg10 (.clk(clk),.rst_n(rst_n),.Valid_in(Valid_out9),.data_in(ark9),
                    .data_out(data10),.Valid_out(Valid_out10));
    SubBytes Sbyte10 (.SubBytes_in(data10),.SubBytes_out(sb10));
    ShiftRows SRow10 (.ShiftRows_in(sb10),.ShiftRows_out(sr10));
    AddRoundKeys Arkey10 (.RoundKey(round_key[10]),.AddRoundKeys_in(sr10),.AddRoundKeys_out(data_out));
    assign encryption_finish = ~(Valid_out0|Valid_out1|Valid_out2|Valid_out3|Valid_out4|Valid_out5|Valid_out6|Valid_out7|Valid_out8|Valid_out9|Valid_out10);
endmodule
