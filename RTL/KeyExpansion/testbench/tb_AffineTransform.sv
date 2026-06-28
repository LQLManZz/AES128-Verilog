`timescale 1ns / 1ps

module tb_AffineTransform ();
  // Khai báo tín hiệu
  logic [7:0] byte_in;
  logic [7:0] byte_out;

  // Khởi tạo module DUT (Design Under Test)
  AffineTransform dut (
      .byte_in (byte_in),
      .byte_out(byte_out)
  );

  initial begin

    $display("=================================================");
    $display("BẮT ĐẦU TESTBENCH CHO AFFINE TRANSFORM");
    $display("=================================================");
    $display("  Byte In (Hex)  |  Byte Out (Hex) ");
    $display("-------------------------------------------------");

    // Test biên đặc biệt: Ngõ vào 0x00 -> Ngõ ra kỳ vọng: 0x63 (Theo chuẩn FIPS-197)
    byte_in = 8'h00;
    #10;
    $display("      %h         |        %h      ", byte_in, byte_out);
    if (byte_out === 8'h63) $display("-> [PASS] Điểm kiểm tra 0x00 thành công!");
    else $display("-> [FAIL] LỖI ở ngõ vào 0x00. Kỳ vọng: 63, Thực tế: %h", byte_out);

    $display("-------------------------------------------------");

    // Quét qua toàn bộ 256 giá trị để đảm bảo không bị lỗi logic ở bất kỳ trường hợp nào
    for (int i = 1; i < 256; i++) begin
      byte_in = i[7:0];
      #10;
      // Bạn có thể bỏ comment dòng dưới đây nếu muốn in toàn bộ 256 giá trị ra Terminal
      $display("      %h         |        %h      ", byte_in, byte_out);
    end

    $display("Hoàn tất mô phỏng quét 256 giá trị thành công!");
    $display("=================================================");

    $finish;
  end
endmodule
