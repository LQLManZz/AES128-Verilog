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
    $display("STARTING TESTBENCH FOR INVERSE AFFINE TRANSFORM");
    $display("=================================================");
    $display("  Byte In (Hex)  |  Byte Out (Hex) ");
    $display("-------------------------------------------------");

    // Test biên đặc biệt: Ngõ vào 0x63 -> Ngõ ra kỳ vọng: 0x00 (Đảo của Affine)
    byte_in = 8'h63;
    #10;
    $display("      %h         |        %h      ", byte_in, byte_out);
    if (byte_out === 8'h00) $display("-> [PASS] Test point 0x63 successful!");
    else $display("-> [FAIL] ERROR at input 0x63. Expected: 00, Actual: %h", byte_out);

    $display("-------------------------------------------------");

    // Quét qua các trường hợp còn lại
    for (int i = 0; i < 256; i++) begin
      if (i == 'h63) continue;  // Bỏ qua giá trị 0x63 đã test ở trên

      byte_in = i[7:0];
      #10;
      // Bỏ comment dòng dưới để hiển thị tất cả
      $display("      %h         |        %h      ", byte_in, byte_out);
    end

    $display("Simulation sweep of 256 values completed successfully!");
    $display("=================================================");

    $finish;
  end
endmodule
