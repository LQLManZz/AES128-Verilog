`timescale 1ns / 1ps

//=============================================================================
// Testbench: LengthBlockCounter_tb (Fully Synchronous posedge-driven)
//
// Timing & Handshake Protocol (All synchronous to @(posedge clk)):
//
// 1. Power-on Reset:
//    - finish_reset is asserted immediately at t = 0 (finish_reset = 1'b1)
//      to trigger the asynchronous reset posedge, clearing 'x' to 0 from t = 0.
//
// 2. Driving with Non-Blocking Assignments (<=):
//    - All inputs (load_AAD, load_CT, CT_last) are updated synchronously
//      at @(posedge clk) using '<=', matching real hardware behavior.
//    - AAD stream transitions seamlessly into CT stream on consecutive clocks.
//
// 3. Sampling & Valid Window:
//    - Cycle N   (posedge): Last CT block is driven (load_CT <= 1, CT_last <= 1).
//    - Cycle N+1 (posedge): RTL registers sample load_CT=1, CT_last=1:
//                             - CT_cnt <= CT_cnt + 16
//                             - length_block_valid <= 1
//                           TB sets CT_last <= 0, load_CT <= 0.
//                           Right after this posedge (#1), length_block_valid is 1.
//    - Cycle N+2 (posedge): RTL registers sample CT_last=0:
//                             - length_block_valid <= 0 (1-cycle pulse).
//
// Reference: References/aes_gcm_golden_appendixB.c
//            References/nistspecialpublication800-38d.pdf
//=============================================================================
module LengthBlockCounter_tb;

  //-----------------------------------------------------------------------
  // DUT signals
  //-----------------------------------------------------------------------
  logic         clk;
  logic         finish_reset;
  logic         load_AAD;
  logic         load_CT;
  logic         CT_last;

  logic         length_block_valid;
  logic [127:0] length_block;

  //-----------------------------------------------------------------------
  // DUT instantiation
  //-----------------------------------------------------------------------
  LengthBlockCounter dut (
      .clk               (clk),
      .finish_reset      (finish_reset),
      .load_AAD          (load_AAD),
      .load_CT           (load_CT),
      .CT_last           (CT_last),
      .length_block_valid(length_block_valid),
      .length_block      (length_block)
  );

  //-----------------------------------------------------------------------
  // Clock: 10 ns period (100 MHz)
  //-----------------------------------------------------------------------
  initial begin
    clk = 1'b0;
    forever #5 clk = ~clk;
  end

  //-----------------------------------------------------------------------
  // Waveform dump
  //-----------------------------------------------------------------------
  initial begin
    $dumpfile("LengthBlockCounter_tb.vcd");
    $dumpvars(0, LengthBlockCounter_tb);
  end

  //-----------------------------------------------------------------------
  // Scoreboard
  //-----------------------------------------------------------------------
  int test_count = 0;
  int error_count = 0;

  //=======================================================================
  // Task: reset_dut
  //   Asserts finish_reset for 2 clock cycles then deasserts synchronously.
  //=======================================================================
  task automatic reset_dut();
    begin
      @(posedge clk);
      finish_reset <= 1'b1;
      load_AAD     <= 1'b0;
      load_CT      <= 1'b0;
      CT_last      <= 1'b0;

      repeat (2) @(posedge clk);
      finish_reset <= 1'b0;
      @(posedge clk);
    end
  endtask

  //=======================================================================
  // Task: run_gcm_case
  //
  //   Drives AAD and CT data synchronously on @(posedge clk) using '<='.
  //   Transitions seamlessly from AAD to CT without any idle cycles.
  //=======================================================================
  task automatic run_gcm_case(input string test_name, input int aad_blocks, input int ct_blocks);
    logic [ 63:0] aad_bits;
    logic [ 63:0] ct_bits;
    logic [127:0] expected_block;
    begin
      aad_bits       = 64'(aad_blocks) * 64'd128;
      ct_bits        = 64'(ct_blocks) * 64'd128;
      expected_block = {aad_bits, ct_bits};

      reset_dut();

      // 1. Drive AAD blocks continuously on posedge clk
      for (int i = 0; i < aad_blocks; i++) begin
        @(posedge clk);
        load_AAD <= 1'b1;
        load_CT  <= 1'b0;
        CT_last  <= 1'b0;
      end

      // 2. Drive CT blocks continuously on posedge clk (seamlessly following AAD)
      if (ct_blocks > 0) begin
        for (int j = 0; j < ct_blocks; j++) begin
          @(posedge clk);
          load_AAD <= 1'b0;
          load_CT  <= 1'b1;
          if (j == ct_blocks - 1) begin
            CT_last <= 1'b1;  // Asserted on the last CT block
          end else begin
            CT_last <= 1'b0;
          end
        end
      end else begin
        // No CT blocks: pulse CT_last alone on posedge clk
        @(posedge clk);
        load_AAD <= 1'b0;
        load_CT  <= 1'b0;
        CT_last  <= 1'b1;
      end

      // 3. Deassert all control signals on next posedge clk
      @(posedge clk);
      load_AAD <= 1'b0;
      load_CT  <= 1'b0;
      CT_last  <= 1'b0;

      //===================================================================
      // 4. CHECK VALID WINDOW (Current posedge just sampled the last CT_last=1)
      //    At this moment, length_block_valid == 1 and length_block is valid.
      //===================================================================
      #1;  // Small delta delay after clock edge for NBA updates to settle
      test_count++;
      $display("--------------------------------------------------");
      $display("Test %0d: %s", test_count, test_name);
      $display("  [Assert Check] length_block_valid = %b  (expected: 1)", length_block_valid);
      $display("                 length_block       = %032h", length_block);
      $display("                 expected           = %032h", expected_block);

      if (length_block_valid !== 1'b1) begin
        error_count++;
        $display("  [FAIL] length_block_valid is NOT asserted in the valid window!");
      end else if (length_block !== expected_block) begin
        error_count++;
        $display("  [FAIL] length_block value mismatch! (XOR diff = %032h)",
                 length_block ^ expected_block);
      end else begin
        $display("  [PASS] Assert check passed.");
      end

      //===================================================================
      // 5. CHECK DEASSERT (Wait for next posedge clk)
      //    Since CT_last <= 0 was driven at step 3, valid-FF must latch 0 now.
      //===================================================================
      @(posedge clk);
      #1;
      if (length_block_valid !== 1'b0) begin
        error_count++;
        $display("  [FAIL] length_block_valid did not deassert at next posedge!");
      end else begin
        $display("  [PASS] Deassert check passed.");
      end
    end
  endtask

  //=======================================================================
  // Main test sequence
  //=======================================================================
  initial begin
    // Time 0 initialization: Assert asynchronous reset immediately
    // to trigger posedge finish_reset at t = 0, eliminating 'x' states.
    finish_reset = 1'b1;
    load_AAD     = 1'b0;
    load_CT      = 1'b0;
    CT_last      = 1'b0;

    // Hold initial reset for 20 ns then release
    #20;
    @(posedge clk);
    finish_reset <= 1'b0;
    @(posedge clk);

    $display("==========================================================");
    $display(" LengthBlockCounter Testbench (Synchronous posedge)");
    $display(" Reference: NIST SP 800-38D Appendix B (TC1-TC4)");
    $display("==========================================================");

    // Test Reset Verification
    reset_dut();
    #1;
    test_count++;
    $display("--------------------------------------------------");
    $display("Test %0d: Reset verification", test_count);
    if (length_block_valid !== 1'b0 || length_block !== 128'h0) begin
      error_count++;
      $display("  [FAIL] Reset failed");
    end else begin
      $display("  [PASS]");
    end

    // NIST SP 800-38D Appendix B vectors
    run_gcm_case("TC1: AAD=0B (0 blk), CT=0B (0 blk)", 0, 0);
    run_gcm_case("TC2: AAD=0B (0 blk), CT=16B (1 blk)", 0, 1);
    run_gcm_case("TC3: AAD=0B (0 blk), CT=64B (4 blk)", 0, 4);
    run_gcm_case("TC4: AAD=20B (2 blk), CT=60B (4 blk)", 2, 4);

    // Additional boundary & stress cases
    run_gcm_case("AAD only: AAD=32B (2 blk), CT=0B", 2, 0);
    run_gcm_case("Single block: AAD=16B (1 blk), CT=16B (1 blk)", 1, 1);
    run_gcm_case("Large msg: AAD=128B (8 blk), CT=192B (12 blk)", 8, 12);
    run_gcm_case("Back-to-back 1: AAD=16B, CT=32B", 1, 2);
    run_gcm_case("Back-to-back 2: AAD=48B, CT=16B", 3, 1);

    // Summary
    $display("");
    $display("==========================================================");
    $display(" SUMMARY: LengthBlockCounter");
    $display("   Total  : %0d", test_count);
    $display("   Passed : %0d", test_count - error_count);
    $display("   Failed : %0d", error_count);
    $display("==========================================================");
    if (error_count == 0) $display(" ALL TESTS PASSED");
    else $error(" %0d TEST(S) FAILED", error_count);
    $display("==========================================================");

    #20;
    $finish;
  end

endmodule
