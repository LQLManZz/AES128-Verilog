module tb_SBoxInv;
  logic [7:0] byte_in;
  logic [7:0] byte_out;

  // Instantiate DUT
  SBoxInv dut (
      .byte_in (byte_in),
      .byte_out(byte_out)
  );

  // Generate VCD waveform
  initial begin
    $dumpfile("SBoxInv_waveform.vcd");
    $dumpvars(0, tb_SBoxInv);
  end

  // Test stimulus
  initial begin
    $display("=== AES Inverse S-Box Testbench ===");
    $display("Time\t byte_in\t byte_out");
    $display("--------------------------------");

    // Test some known inverse S-Box values
    test_vector(8'h00, 8'h52);  // S^{-1}(00) = 52
    test_vector(8'h01, 8'h09);
    test_vector(8'h53, 8'h01);  // S(01) = 53 → S^{-1}(53) = 01
    test_vector(8'h7C, 8'h7F);
    test_vector(8'h63, 8'h7C);  // S(7C) = 63 → S^{-1}(63) = 7C

    // More test cases
    test_vector(8'h2F, 8'h8D);
    test_vector(8'h8D, 8'h2F);
    test_vector(8'hFF, 8'h16);
    test_vector(8'h16, 8'hFF);

    // Sweep all 256 values (optional, uncomment if needed)
    // for (int i = 0; i < 256; i++) begin
    //     test_vector(i[7:0], 8'hXX); // Expected value not checked
    // end

    #50;
    $display("Test completed.");
    $finish;
  end

  // Task to apply test vector and display result
  task automatic test_vector(input logic [7:0] in, input logic [7:0] expected);
    byte_in = in;
    #10;
    $display(
        "%0t\t %h\t\t %h\t %s", $time, byte_in, byte_out,
        (expected !== 8'hXX && byte_out === expected) ? "[PASS]" : (expected === 8'hXX ? "" : "[FAIL]"));
  endtask

endmodule
