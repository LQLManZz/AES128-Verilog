`timescale 1ns / 1ps

module tb_MultiplicativeInv ();
  // Khai báo tín hiệu
  logic [7:0] byte_in;
  logic [7:0] byte_out;

  // Khởi tạo module DUT (Design Under Test)
  MultiplicativeInv dut (
      .byte_in (byte_in),
      .byte_out(byte_out)
  );

  // =========================================================================
  // HÀM KIỂM CHỨNG TOÁN HỌC: Nhân hai số trong trường Galois GF(2^8)
  // Sử dụng đa thức tối giản của AES: m(x) = x^8 + x^4 + x^3 + x + 1 (0x11B)
  // =========================================================================
  function automatic logic [7:0] gf_multiplication(logic [7:0] a, logic [7:0] b);
    logic [7:0] p = 8'b0;
    logic [7:0] hi_bit_set;
    for (int i = 0; i < 8; i++) begin
      if (b[0] == 1'b1) p = p ^ a;  // Nếu bit LSB của b là 1, cộng (XOR) a vào kết quả
      hi_bit_set = a & 8'h80;  // Lưu lại bit MSB của a
      a          = a << 1;  // Dịch trái a (tương đương nhân với x)
      if (hi_bit_set != 8'b0)
        a = a ^ 8'h1b;  // Nếu bit MSB bị tràn, XOR với đa thức rút gọn
      b = b >> 1;  // Dịch phải b để xét bit tiếp theo
    end
    return p;
  endfunction

  // Biến phụ trợ cho quá trình test
  int error_count;
  logic [7:0] check_product;

  initial begin
    // Thiết lập xuất waveform để bạn có thể xem trên GTKWave
    $dumpfile("tb_MultiplicativeInv.vcd");
    $dumpvars(0, tb_MultiplicativeInv);

    error_count = 0;

    $display("=======================================================================");
    $display("STARTING TESTBENCH FOR MULTIPLICATIVE INVERSE (FINDING INVERSE IN GF(2^8))");
    $display("=======================================================================");

    // Quét toàn vẹn (Exhaustive Testing) tất cả 256 trường hợp của byte_in
    for (int i = 0; i < 256; i++) begin
      byte_in = i[7:0];
      #10;  // Đợi tín hiệu lan truyền qua các cổng logic (gate delay)

      // Kiểm tra trường hợp đặc biệt: 0x00
      if (byte_in == 8'h00) begin
        if (byte_out !== 8'h00) begin
          $display(
              "[BOUNDARY ERROR] In = 00 expected 00, but hardware returned %h",
              byte_out);
          error_count++;
        end
      end  // Kiểm tra các trường hợp còn lại: A * A^-1 = 0x01
      else begin
        check_product = gf_multiplication(byte_in, byte_out);
        if (check_product !== 8'h01) begin
          $display("[MATHEMATICAL ERROR] In = %h, Out = %h. GF(2^8) Product = %h (Expected: 01)",
                   byte_in, byte_out, check_product);
          error_count++;
        end
      end
    end

    // In báo cáo tổng kết
    $display("-----------------------------------------------------------------------");
    if (error_count == 0) begin
      $display(
          ">> ALL 256 CASES ARE CORRECT. MODULE WORKS PERFECTLY! <<");
    end else begin
      $display(
          ">> WARNING: DETECTED %0d ERRORS. PLEASE CHECK LOGIC GATES DESIGN! <<",
          error_count);
    end
    $display("=======================================================================");

    $finish;
  end
endmodule
