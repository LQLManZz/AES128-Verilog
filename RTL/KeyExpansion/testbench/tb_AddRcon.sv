`timescale 1ns / 1ps

module tb_AddRcon ();
  // Khai báo tín hiệu đầu vào và đầu ra
  logic [31:0] word_in;
  logic [ 3:0] round_index;
  logic [31:0] word_out;

  // Khởi tạo module AddRcon (Design Under Test - DUT)
  AddRcon dut (
      .word_in(word_in),
      .round_index(round_index),
      .word_out(word_out)
  );

  initial begin
    $display("==================================================================");
    $display("BẮT ĐẦU TESTBENCH CHO MODULE ADDRCON");
    $display("==================================================================");
    $display("Round Index |   Word In  |  Word Out  | Rcon trích xuất (XOR)");
    $display("------------------------------------------------------------------");

    // Test case 1: Cố định một word_in, quét qua tất cả các round_index (từ 0 đến 9)
    word_in = 32'h12345678;

    for (int i = 0; i <= 9; i++) begin
      round_index = i[3:0];
      #10;  // Đợi một khoảng thời gian để mạch tổ hợp xử lý xong

      // Để kiểm chứng Rcon có đúng không, ta lấy byte cao nhất của ngõ vào XOR với ngõ ra
      $display("%11d | %h | %h | %h", round_index, word_in, word_out,
               (word_in[31:24] ^ word_out[31:24]));
    end

    $display("------------------------------------------------------------------");

    // Test case 2: Kiểm tra một vài trường hợp biên (Corner cases)

    // Biên 1: Tất cả các bit đều là 1 (FFFFFFFF) ở Round 9 (Rcon = 8'h1b)
    // FF ^ 1B = E4 -> Đầu ra kỳ vọng: E4FFFFFF
    #10;
    word_in = 32'hFFFFFFFF;
    round_index = 4'd8;
    #10;
    if (word_out === 32'hE4FFFFFF)
      $display("Test biên 1 (Round 9,  In=FFFFFFFF) -> PASS (Output = %h)", word_out);
    else $display("Test biên 1 (Round 9,  In=FFFFFFFF) -> FAIL (Output = %h)", word_out);

    // Biên 2: Tất cả các bit đều là 0 (00000000) ở Round 10 (Rcon = 8'h36)
    // 00 ^ 36 = 36 -> Đầu ra kỳ vọng: 36000000
    #10;
    word_in = 32'h00000000;
    round_index = 4'd9;
    #10;
    if (word_out === 32'h36000000)
      $display("Test biên 2 (Round 10, In=00000000) -> PASS (Output = %h)", word_out);
    else $display("Test biên 2 (Round 10, In=00000000) -> FAIL (Output = %h)", word_out);

    $display("==================================================================");

    // Kết thúc mô phỏng
    $finish;
  end
endmodule
