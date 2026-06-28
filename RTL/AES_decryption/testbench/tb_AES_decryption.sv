`timescale 1ns/1ps

module tb_AES_decryption;

    //-----------------------------------------
    // Testbench signals
    //-----------------------------------------
    logic clk;
    logic rst_n;
    logic decryption_en;

    logic [127:0] data_in;
    logic [127:0] round_key [0:10];

    // Alias để xem waveform
    logic [127:0] rk0;
    logic [127:0] rk1;
    logic [127:0] rk2;
    logic [127:0] rk3;
    logic [127:0] rk4;
    logic [127:0] rk5;
    logic [127:0] rk6;
    logic [127:0] rk7;
    logic [127:0] rk8;
    logic [127:0] rk9;
    logic [127:0] rk10;

    logic [127:0] data_out;
    logic decryption_finish;

    //-----------------------------------------
    // DUT
    //-----------------------------------------
    AES_decryption dut(
        .clk(clk),
        .rst_n(rst_n),
        .decryption_en(decryption_en),
        .data_in(data_in),
        .round_key(round_key),
        .data_out(data_out),
        .decryption_finish(decryption_finish)
    );

    //-----------------------------------------
    // Clock
    //-----------------------------------------
    initial clk = 0;
    always #5 clk = ~clk;

    //-----------------------------------------
    // Waveform
    //-----------------------------------------
    initial begin
        $dumpfile("wave.vcd");
        $dumpvars(0, tb_AES_decryption);
    end

    //-----------------------------------------
    // Test
    //-----------------------------------------
    initial begin

        //-----------------------------
        // Reset
        //-----------------------------
        rst_n = 0;
        decryption_en = 0;
        data_in = 0;

        #20;
        rst_n = 1;

        //-----------------------------
        // Ciphertext
        //-----------------------------
        data_in = 128'h8b1ec3c231a4e479236c14325d897978;

        //-----------------------------
        // Round Keys
        //-----------------------------
        rk0  = 128'h000102030405060708090A0B0C0D0E0F;
        rk1  = 128'h11111111111111111111111111111111;
        rk2  = 128'h22222222222222222222222222222222;
        rk3  = 128'h33333333333333333333333333333333;
        rk4  = 128'h44444444444444444444444444444444;
        rk5  = 128'h55555555555555555555555555555555;
        rk6  = 128'h66666666666666666666666666666666;
        rk7  = 128'h77777777777777777777777777777777;
        rk8  = 128'h88888888888888888888888888888888;
        rk9  = 128'h99999999999999999999999999999999;
        rk10 = 128'hAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA;

        // Copy vào mảng truyền cho DUT
        round_key[0]  = rk0;
        round_key[1]  = rk1;
        round_key[2]  = rk2;
        round_key[3]  = rk3;
        round_key[4]  = rk4;
        round_key[5]  = rk5;
        round_key[6]  = rk6;
        round_key[7]  = rk7;
        round_key[8]  = rk8;
        round_key[9]  = rk9;
        round_key[10] = rk10;

        //-----------------------------
        // Start Decryption
        //-----------------------------
        @(posedge clk);
        decryption_en = 1'b1;

        @(posedge clk);
        decryption_en = 1'b0;

        //-----------------------------
        // Wait Finish
        //-----------------------------
        wait(decryption_finish);

        @(posedge clk);

        $display("------------------------------------");
        $display("Ciphertext : %h", data_in);
        $display("Plaintext  : %h", data_out);
        $display("------------------------------------");

        if (data_out == 128'h00112233445566778899AABBCCDDEEFF)
            $display("PASS");
        else
            $display("FAIL");

        // Giữ waveform thêm một chút
        #100;
        $finish;

    end

endmodule
