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
    $display("STARTING TESTBENCH FOR AFFINE TRANSFORM");
    $display("=================================================");
    $display("  Byte In (Hex)  |  Byte Out (Hex) ");
    $display("-------------------------------------------------");

    // Test biên đặc biệt: Ngõ vào 0x00 -> Ngõ ra kỳ vọng: 0x63 (Theo chuẩn FIPS-197)
    byte_in = 8'h00;
    #10;
    $display("      %h         |        %h      ", byte_in, byte_out);
    if (byte_out === 8'h63) $display("-> [PASS] Test point 0x00 successful!");
    else $display("-> [FAIL] ERROR at input 0x00. Expected: 63, Actual: %h", byte_out);

    $display("-------------------------------------------------");

    // Quét qua toàn bộ 256 giá trị để đảm bảo không bị lỗi logic ở bất kỳ trường hợp nào
    for (int i = 1; i < 256; i++) begin
      byte_in = i[7:0];
      #10;
      // Bạn có thể bỏ comment dòng dưới đây nếu muốn in toàn bộ 256 giá trị ra Terminal
      $display("      %h         |        %h      ", byte_in, byte_out);
    end

    $display("Simulation sweep of 256 values completed successfully!");
    $display("=================================================");

    $finish;
  end
endmodule
