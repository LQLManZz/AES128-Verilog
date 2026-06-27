    module AES_decryption(
        input logic clk, rst_n,
        input logic decryption_en,
        input logic [127:0] data_in,
        input logic [127:0] round_key [0:10],
        output logic [127:0] data_out,
        output logic decryption_finish);
     
        logic Valid_out0, Valid_out1, Valid_out2, Valid_out3, Valid_out4, Valid_out5, Valid_out6,Valid_out7, Valid_out8, Valid_out9, Valid_out10;
        logic [127:0] data0, data1, data2, data3, data4, data5, data6, data7, data8, data9, data10;
        logic [127:0] ark0, ark1, ark2, ark3, ark4, ark5, ark6, ark7, ark8, ark9;
        logic [127:0] isb1, isb2, isb3, isb4, isb5, isb6, isb7, isb8, isb9, isb10;
        logic [127:0] isr1, isr2, isr3, isr4, isr5, isr6, isr7, isr8, isr9, isr10;
        logic [127:0] imcl1, imcl2, imcl3, imcl4, imcl5, imcl6, imcl7, imcl8, imcl9;
        // state 0
        AES_register reg0 (.clk(clk),.rst_n(rst_n),.Valid_in(decryption_en),.data_in(data_in),
                        .data_out(data0),.Valid_out(Valid_out0));
        AddRoundKeys Arkey0 (.RoundKey(round_key[10]),.AddRoundKeys_in(data0),.AddRoundKeys_out(ark0));
        // state 1
        AES_register reg1 (.clk(clk),.rst_n(rst_n),.Valid_in(Valid_out0),.data_in(ark0),
                        .data_out(data1),.Valid_out(Valid_out1));
        InvShiftRows ISRow1 (.InvShiftRows_in(data1),.InvShiftRows_out(isr1));
        InvSubBytes ISByte1 (.InvSubBytes_in(isr1),.InvSubBytes_out(isb1));
        AddRoundKeys Arkey1 (.RoundKey(round_key[9]),.AddRoundKeys_in(isb1),.AddRoundKeys_out(ark1));
        InvMixColumns IMColumn1 (.InvMixColumns_in(ark1),.InvMixColumns_out(imcl1));
        // state 2
        AES_register reg2 (.clk(clk),.rst_n(rst_n),.Valid_in(Valid_out1),.data_in(imcl1),
                        .data_out(data2),.Valid_out(Valid_out2));
        InvShiftRows ISRow2 (.InvShiftRows_in(data2),.InvShiftRows_out(isr2));
        InvSubBytes ISByte2 (.InvSubBytes_in(isr2),.InvSubBytes_out(isb2));
        AddRoundKeys Arkey2 (.RoundKey(round_key[8]),.AddRoundKeys_in(isb2),.AddRoundKeys_out(ark2));
        InvMixColumns IMColumn2 (.InvMixColumns_in(ark2),.InvMixColumns_out(imcl2));
        // state 3
        AES_register reg3 (.clk(clk),.rst_n(rst_n),.Valid_in(Valid_out2),.data_in(imcl2),
                        .data_out(data3),.Valid_out(Valid_out3));
        InvShiftRows ISRow3 (.InvShiftRows_in(data3),.InvShiftRows_out(isr3));
        InvSubBytes ISByte3 (.InvSubBytes_in(isr3),.InvSubBytes_out(isb3));
        AddRoundKeys Arkey3 (.RoundKey(round_key[7]),.AddRoundKeys_in(isb3),.AddRoundKeys_out(ark3));
        InvMixColumns IMColumn3 (.InvMixColumns_in(ark3),.InvMixColumns_out(imcl3));
        // state 4
        AES_register reg4 (.clk(clk),.rst_n(rst_n),.Valid_in(Valid_out3),.data_in(imcl3),
                        .data_out(data4),.Valid_out(Valid_out4));
        InvShiftRows ISRow4 (.InvShiftRows_in(data4),.InvShiftRows_out(isr4));
        InvSubBytes ISByte4 (.InvSubBytes_in(isr4),.InvSubBytes_out(isb4));
        AddRoundKeys Arkey4 (.RoundKey(round_key[6]),.AddRoundKeys_in(isb4),.AddRoundKeys_out(ark4));
        InvMixColumns IMColumn4 (.InvMixColumns_in(ark4),.InvMixColumns_out(imcl4));
        // state 5
        AES_register reg5 (.clk(clk),.rst_n(rst_n),.Valid_in(Valid_out4),.data_in(imcl4),
                        .data_out(data5),.Valid_out(Valid_out5));
        InvShiftRows ISRow5 (.InvShiftRows_in(data5),.InvShiftRows_out(isr5));
        InvSubBytes ISByte5 (.InvSubBytes_in(isr5),.InvSubBytes_out(isb5));
        AddRoundKeys Arkey5 (.RoundKey(round_key[5]),.AddRoundKeys_in(isb5),.AddRoundKeys_out(ark5));
        InvMixColumns IMColumn5 (.InvMixColumns_in(ark5),.InvMixColumns_out(imcl5));
        // state 6
        AES_register reg6 (.clk(clk),.rst_n(rst_n),.Valid_in(Valid_out5),.data_in(imcl5),
                        .data_out(data6),.Valid_out(Valid_out6));
        InvShiftRows ISRow6 (.InvShiftRows_in(data6),.InvShiftRows_out(isr6));
        InvSubBytes ISByte6 (.InvSubBytes_in(isr6),.InvSubBytes_out(isb6));
        AddRoundKeys Arkey6 (.RoundKey(round_key[4]),.AddRoundKeys_in(isb6),.AddRoundKeys_out(ark6));
        InvMixColumns IMColumn6 (.InvMixColumns_in(ark6),.InvMixColumns_out(imcl6));
        // state 7
        AES_register reg7 (.clk(clk),.rst_n(rst_n),.Valid_in(Valid_out6),.data_in(imcl6),
                        .data_out(data7),.Valid_out(Valid_out7));
        InvShiftRows ISRow7 (.InvShiftRows_in(data7),.InvShiftRows_out(isr7));
        InvSubBytes ISByte7 (.InvSubBytes_in(isr7),.InvSubBytes_out(isb7));
        AddRoundKeys Arkey7 (.RoundKey(round_key[3]),.AddRoundKeys_in(isb7),.AddRoundKeys_out(ark7));
        InvMixColumns IMColumn7 (.InvMixColumns_in(ark7),.InvMixColumns_out(imcl7));
        // state 8
        AES_register reg8 (.clk(clk),.rst_n(rst_n),.Valid_in(Valid_out7),.data_in(imcl7),
                        .data_out(data8),.Valid_out(Valid_out8));
        InvShiftRows ISRow8 (.InvShiftRows_in(data8),.InvShiftRows_out(isr8));
        InvSubBytes ISByte8 (.InvSubBytes_in(isr8),.InvSubBytes_out(isb8));
        AddRoundKeys Arkey8 (.RoundKey(round_key[2]),.AddRoundKeys_in(isb8),.AddRoundKeys_out(ark8));
        InvMixColumns IMColumn8 (.InvMixColumns_in(ark8),.InvMixColumns_out(imcl8));
        // state 9
        AES_register reg9 (.clk(clk),.rst_n(rst_n),.Valid_in(Valid_out8),.data_in(imcl8),
                        .data_out(data9),.Valid_out(Valid_out9));
        InvShiftRows ISRow9 (.InvShiftRows_in(data9),.InvShiftRows_out(isr9));
        InvSubBytes ISByte9 (.InvSubBytes_in(isr9),.InvSubBytes_out(isb9));
        AddRoundKeys Arkey9 (.RoundKey(round_key[1]),.AddRoundKeys_in(isb9),.AddRoundKeys_out(ark9));
        InvMixColumns IMColumn9 (.InvMixColumns_in(ark9),.InvMixColumns_out(imcl9));
        // state 10
        AES_register reg10 (.clk(clk),.rst_n(rst_n),.Valid_in(Valid_out9),.data_in(imcl9),
                        .data_out(data10),.Valid_out(Valid_out10));
        InvShiftRows ISRow10 (.InvShiftRows_in(data10),.InvShiftRows_out(isr10));
        InvSubBytes ISByte10 (.InvSubBytes_in(isr10),.InvSubBytes_out(isb10));
        AddRoundKeys Arkey10 (.RoundKey(round_key[0]),.AddRoundKeys_in(isb10),.AddRoundKeys_out(data_out));
        assign decryption_finish = ~(Valid_out0|Valid_out1|Valid_out2|Valid_out3|Valid_out4|Valid_out5|Valid_out6|Valid_out7|Valid_out8|Valid_out9|Valid_out10);
    endmodule
