`timescale 1ns / 1ps

module tb_InvAffineTransform ();
  // Khai báo tín hiệu
  logic [7:0] byte_in;
  logic [7:0] byte_out;

  // Khởi tạo module DUT (Design Under Test)
  InvAffineTransform dut (
      .byte_in (byte_in),
      .byte_out(byte_out)
  );

  initial begin

    $display("=================================================");
    $display("BẮT ĐẦU TESTBENCH CHO INVERSE AFFINE TRANSFORM");
    $display("=================================================");
    $display("  Byte In (Hex)  |  Byte Out (Hex) ");
    $display("-------------------------------------------------");

    // Test biên đặc biệt: Ngõ vào 0x63 -> Ngõ ra kỳ vọng: 0x00 (Đảo của Affine)
    byte_in = 8'h63;
    #10;
    $display("      %h         |        %h      ", byte_in, byte_out);
    if (byte_out === 8'h00) $display("-> [PASS] Điểm kiểm tra 0x63 thành công!");
    else $display("-> [FAIL] LỖI ở ngõ vào 0x63. Kỳ vọng: 00, Thực tế: %h", byte_out);

    $display("-------------------------------------------------");

    // Quét qua các trường hợp còn lại
    for (int i = 0; i < 256; i++) begin
      if (i == 'h63) continue;  // Bỏ qua giá trị 0x63 đã test ở trên

      byte_in = i[7:0];
      #10;
      // Bỏ comment dòng dưới để hiển thị tất cả
      $display("      %h         |        %h      ", byte_in, byte_out);
    end

    $display("Hoàn tất mô phỏng quét 256 giá trị thành công!");
    $display("=================================================");

    $finish;
  end
endmodule
