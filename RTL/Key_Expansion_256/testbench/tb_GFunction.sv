`timescale 1ns / 1ps

module tb_GFunction ();
  // Khai báo các tín hiệu kết nối
  logic [31:0] word_in;
  logic [ 3:0] round_index;
  logic [31:0] word_out;

  // Khởi tạo Design Under Test (DUT)
  GFunction dut (
      .word_in(word_in),
      .round_index(round_index),
      .word_out(word_out)
  );

  initial begin
    // -------------------------------------------------------------
    // TẠO WAVEFORM CHO GTKWAVE
    // -------------------------------------------------------------
    $dumpfile("tb_GFunction.vcd");
    $dumpvars(0, tb_GFunction);

    $display("===============================================================");
    $display("                 STARTING G-FUNCTION TESTBENCH                  ");
    $display("===============================================================");

    // =============================================================
    // TEST CASE 1: KNOWN ANSWER TEST (Chuẩn AES-128 FIPS 197)
    // =============================================================
    // Lấy ví dụ tạo Key vòng 1. Word cuối cùng của Key gốc là 09cf4f3c.
    // - RotWord:    cf4f3c09
    // - SubWord:    8a84eb01
    // - AddRcon(1): 8a ^ 01 = 8b -> Kết quả cuối: 8b84eb01
    $display("[TEST 1: STANDARD AES VECTOR] Calculate Round 1 Key");
    word_in = 32'h09cf4f3c;
    round_index = 4'd0;
    #10;

    $display("Round: %0d | In: %h | Out: %h", round_index, word_in, word_out);
    if (word_out === 32'h8b84eb01) $display(" -> [PASS] Matches standard AES-128!");
    else $display(" -> [FAIL] Error! Expected result is 8b84eb01");
    $display("---------------------------------------------------------------");

    // =============================================================
    // TEST CASE 2: CORNER CASES (Trường hợp biên: Toàn 0)
    // =============================================================
    $display("[TEST 2: ALL-ZERO BOUNDARY] Sweep through all 10 rounds");
    word_in = 32'h00000000;
    for (int i = 0; i <= 9; i++) begin
      round_index = i[3:0];
      #10;
      $display("Round %0d | In: %h | Out: %h", round_index, word_in, word_out);
    end
    $display("---------------------------------------------------------------");

    // =============================================================
    // TEST CASE 3: CORNER CASES (Trường hợp biên: Toàn 1 / FFFFFFFF)
    // =============================================================
    $display("[TEST 3: ALL-ONE BOUNDARY] Sweep through all 10 rounds");
    word_in = 32'hFFFFFFFF;
    for (int i = 0; i <= 9; i++) begin
      round_index = i[3:0];
      #10;
      $display("Round %0d | In: %h | Out: %h", round_index, word_in, word_out);
    end
    $display("---------------------------------------------------------------");

    // =============================================================
    // TEST CASE 4: RANDOMIZED TESTING (Dữ liệu ngẫu nhiên)
    // =============================================================
    $display("[TEST 4: RANDOM DATA] Random test for 10 rounds");
    for (int i = 0; i <= 9; i++) begin
      word_in = $urandom();  // Tạo 32-bit ngẫu nhiên
      round_index = i[3:0];
      #10;
      $display("Round %0d | In: %h | Out: %h", round_index, word_in, word_out);
    end

    $display("===============================================================");
    $display("                      SIMULATION FINISHED                      ");
    $display("===============================================================");

    $finish;
  end
endmodule
