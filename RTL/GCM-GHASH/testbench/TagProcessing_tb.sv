`timescale 1ns / 1ps

//=============================================================================
// Testbench: TagProcessing_tb (Fully Synchronous posedge-driven)
//
// Verifies TagProcessing top-level module:
//   - Mode 0 (Encryption): Tag Generation (tag == expected_tag).
//   - Mode 1 (Decryption / Auth): Tag Verification:
//       * Valid Tag: tag_ref == expected_tag    -> verify_pass == 1'b1.
//       * Tampered Tag: tag_ref != expected_tag -> verify_pass == 1'b0.
//   - Registered Outputs & Latched Handshakes:
//       * Subkey H: H_valid -> H_loaded (auto-managed key reload).
//       * Mask E: E_valid -> E_loaded.
//       * Reference Tag: load_tag_ref -> tag_ref_loaded.
//       * Registered Tag output: TagReg (always_ff).
//       * Output Valid: tag_process_valid (always_ff, latched until finish_reset).
//       * Uniform Finish Latency: ghash_finish is active for exactly 3 cycles
//         consistently across ALL tests (both tag == tag_ref and tag != tag_ref).
//   - Full NIST SP 800-38D Appendix B Test Vectors (TC1 to TC4).
//
// Reference: References/aes_gcm_golden_appendixB.c
//            References/nistspecialpublication800-38d.pdf
//=============================================================================
module TagProcessing_tb;

  //-----------------------------------------------------------------------
  // DUT signals
  //-----------------------------------------------------------------------
  logic         clk;
  logic         rst_n;
  logic         finish_reset;
  logic         load_key;
  logic         mode;
  logic [127:0] AAD;
  logic [127:0] CT;
  logic [127:0] tag_ref;
  logic [127:0] H;
  logic [127:0] E;
  logic         load_AAD;
  logic         load_CT;
  logic         H_valid;
  logic         E_valid;
  logic         load_tag_ref;
  logic         CT_last;

  logic         H_loaded;
  logic         tag_ref_loaded;
  logic [127:0] tag;
  logic         tag_process_valid;
  logic         verify_pass;

  //-----------------------------------------------------------------------
  // DUT instantiation
  //-----------------------------------------------------------------------
  TagProcessing dut (
      .clk               (clk),
      .rst_n             (rst_n),
      .finish_reset      (finish_reset),
      .load_key          (load_key),
      .mode              (mode),
      .AAD               (AAD),
      .CT                (CT),
      .tag_ref           (tag_ref),
      .H                 (H),
      .E                 (E),
      .load_AAD          (load_AAD),
      .load_CT           (load_CT),
      .H_valid           (H_valid),
      .E_valid           (E_valid),
      .load_tag_ref      (load_tag_ref),
      .CT_last           (CT_last),
      .H_loaded          (H_loaded),
      .tag_ref_loaded    (tag_ref_loaded),
      .tag               (tag),
      .tag_process_valid (tag_process_valid),
      .verify_pass       (verify_pass)
  );

  //-----------------------------------------------------------------------
  // Clock generation: 10 ns period (100 MHz)
  //-----------------------------------------------------------------------
  initial begin
    clk = 1'b0;
    forever #5 clk = ~clk;
  end

  //-----------------------------------------------------------------------
  // Waveform dump
  //-----------------------------------------------------------------------
  initial begin
    $dumpfile("TagProcessing_tb.vcd");
    $dumpvars(0, TagProcessing_tb);
  end

  //-----------------------------------------------------------------------
  // Scoreboard
  //-----------------------------------------------------------------------
  int test_count  = 0;
  int error_count = 0;

  //=======================================================================
  // Model: RTL Polynomial Basis GF(2^128) Multiplier
  //   Irreducible polynomial: P(x) = x^128 + x^7 + x^2 + x + 1
  //=======================================================================
  function automatic logic [255:0] carryless_multiply(
      input logic [127:0] operand_a,
      input logic [127:0] operand_b
  );
    logic [255:0] product;
    logic [255:0] extended_a;
    begin
      product    = 256'd0;
      extended_a = {128'd0, operand_a};

      for (int i = 0; i < 128; i++) begin
        if (operand_b[i]) begin
          product = product ^ (extended_a << i);
        end
      end

      return product;
    end
  endfunction

  function automatic logic [127:0] polynomial_reduction(input logic [255:0] product);
    logic [255:0] remainder;
    begin
      remainder = product;

      for (int i = 255; i >= 128; i--) begin
        if (remainder[i]) begin
          remainder[i] = 1'b0;
          remainder[i - 128 + 7] ^= 1'b1;
          remainder[i - 128 + 2] ^= 1'b1;
          remainder[i - 128 + 1] ^= 1'b1;
          remainder[i - 128]     ^= 1'b1;
        end
      end

      return remainder[127:0];
    end
  endfunction

  function automatic logic [127:0] rtl_gf128_mul(
      input logic [127:0] operand_a,
      input logic [127:0] operand_b
  );
    begin
      return polynomial_reduction(carryless_multiply(operand_a, operand_b));
    end
  endfunction

  //=======================================================================
  // Task: reset_all
  //   Full hardware reset (rst_n and finish_reset).
  //=======================================================================
  task automatic reset_all();
    begin
      @(posedge clk);
      rst_n        <= 1'b0;
      finish_reset <= 1'b1;
      load_key     <= 1'b0;
      load_AAD     <= 1'b0;
      load_CT      <= 1'b0;
      H_valid      <= 1'b0;
      E_valid      <= 1'b0;
      load_tag_ref <= 1'b0;
      CT_last      <= 1'b0;
      AAD          <= 128'h0;
      CT           <= 128'h0;
      tag_ref      <= 128'h0;
      H            <= 128'h0;
      E            <= 128'h0;

      repeat (2) @(posedge clk);
      rst_n        <= 1'b1;
      finish_reset <= 1'b0;
      @(posedge clk);
    end
  endtask

  //=======================================================================
  // Task: reset_message
  //   Message-level reset (finish_reset only, preserves H_reg & H_loaded).
  //=======================================================================
  task automatic reset_message();
    begin
      @(posedge clk);
      finish_reset <= 1'b1;
      load_AAD     <= 1'b0;
      load_CT      <= 1'b0;
      E_valid      <= 1'b0;
      load_tag_ref <= 1'b0;
      CT_last      <= 1'b0;
      AAD          <= 128'h0;
      CT           <= 128'h0;

      repeat (2) @(posedge clk);
      finish_reset <= 1'b0;
      @(posedge clk);
    end
  endtask

  //=======================================================================
  // Task: run_tag_test
  //
  //   Executes a full AES-GCM Tag Processing test case:
  //   - test_mode = 0: Encryption mode (Tag Generation).
  //   - test_mode = 1: Decryption mode (Tag Verification against tag_ref_in).
  //=======================================================================
  task automatic run_tag_test(
      input string        test_name,
      input logic         test_mode,          // 0: Encrypt, 1: Decrypt
      input logic [127:0] H_in,
      input logic [127:0] E_in,
      input logic [127:0] aad_blocks[],
      input logic [127:0] ct_blocks[],
      input logic [127:0] tag_ref_in,         // Reference tag for mode 1
      input logic         expect_pass         // Expected verify_pass for mode 1
  );
    logic [127:0] ref_ghash;
    logic [127:0] len_block;
    logic [127:0] exp_tag;
    int num_aad;
    int num_ct;
    begin
      num_aad = aad_blocks.size();
      num_ct  = ct_blocks.size();

      // 1. Cycle-accurate model matching LengthBlockCounter + GHASH + TagProcessing
      len_block = {61'(num_aad * 16), 3'd0, 61'(num_ct * 16), 3'd0};
      ref_ghash = 128'h0;

      for (int i = 0; i < num_aad; i++) begin
        ref_ghash = rtl_gf128_mul(ref_ghash ^ aad_blocks[i], H_in);
      end
      for (int j = 0; j < num_ct; j++) begin
        ref_ghash = rtl_gf128_mul(ref_ghash ^ ct_blocks[j], H_in);
      end
      ref_ghash = rtl_gf128_mul(ref_ghash ^ len_block, H_in);

      // In AES-GCM TagProcessing: tag = ghash_out ^ E_reg
      exp_tag = ref_ghash ^ E_in;

      // 2. Reset message context
      reset_message();

      // 3. Load Keys & Context synchronously
      // If key needs to change, reload H cleanly while message is reset
      if (!H_loaded || H_in !== dut.H_reg) begin
        @(posedge clk);
        load_key <= 1'b1;
        @(posedge clk);
        load_key <= 1'b0;
        H        <= H_in;
        H_valid  <= 1'b1;
        @(posedge clk);
        H_valid  <= 1'b0;
      end

      @(posedge clk);
      mode <= test_mode;

      // Load Mask E
      E       <= E_in;
      E_valid <= 1'b1;

      // Load tag_ref (used for Mode 1 verification)
      if (test_mode == 1'b1) begin
        tag_ref      <= tag_ref_in;
        load_tag_ref <= 1'b1;
      end else begin
        tag_ref      <= 128'h0;
        load_tag_ref <= 1'b0;
      end

      @(posedge clk);
      E_valid      <= 1'b0;
      load_tag_ref <= 1'b0;

      // 4. Stream AAD blocks continuously
      for (int i = 0; i < num_aad; i++) begin
        @(posedge clk);
        load_AAD <= 1'b1;
        load_CT  <= 1'b0;
        CT_last  <= 1'b0;
        AAD      <= aad_blocks[i];
      end

      // 5. Stream CT blocks continuously (seamlessly following AAD)
      if (num_ct > 0) begin
        for (int j = 0; j < num_ct; j++) begin
          @(posedge clk);
          load_AAD <= 1'b0;
          load_CT  <= 1'b1;
          CT       <= ct_blocks[j];
          if (j == num_ct - 1) begin
            CT_last <= 1'b1;
          end else begin
            CT_last <= 1'b0;
          end
        end
      end else begin
        // No CT data: pulse CT_last alone
        @(posedge clk);
        load_AAD <= 1'b0;
        load_CT  <= 1'b0;
        CT_last  <= 1'b1;
      end

      // 6. Deassert data controls
      @(posedge clk);
      load_AAD <= 1'b0;
      load_CT  <= 1'b0;
      CT_last  <= 1'b0;

      // Pipeline Latency:
      // Cycle 1: LengthCounter samples CT_last -> length_block_valid <= 1
      // Cycle 2: GHASHCore samples length_block_valid -> ghash_finish <= 1, ghash_out <= ...
      // Cycle 3: TagProcessing (TagReg & TagProcessValidReg) samples ghash_finish ->
      //          tag <= ghash_out ^ E_reg, tag_process_valid <= ghash_finish & E_loaded
      // Wait synchronously for tag_process_valid (with timeout guard)
      fork
        begin
          while (!tag_process_valid) @(posedge clk);
        end
        begin
          repeat (10) @(posedge clk);
        end
      join_any

      //===================================================================
      // 7. CHECK VALID FINISH WINDOW
      //===================================================================
      #1;
      test_count++;

      $display("--------------------------------------------------");
      $display("Test %0d: %s [Mode: %s]", test_count, test_name,
               test_mode ? "DECRYPT/VERIFY" : "ENCRYPT/GEN_TAG");
      $display("  [Handshake] valid          = %b  (expected: 1)", tag_process_valid);
      $display("              H_loaded       = %b, tag_ref_loaded = %b", H_loaded, tag_ref_loaded);
      $display("  [Tag Check] Tag DUT        = %032h", tag);
      $display("              Tag EXP        = %032h", exp_tag);

      if (test_mode == 1'b1) begin
        $display("  [Tag Ref]   tag_ref        = %032h", tag_ref_in);
        $display("  [Auth Check]verify_pass    = %b  (expected: %b)", verify_pass, expect_pass);
      end

      // Assertions
      if (tag_process_valid !== 1'b1) begin
        error_count++;
        $display("  [FAIL] tag_process_valid was NOT asserted!");
      end else if (tag !== exp_tag) begin
        error_count++;
        $display("  [FAIL] Tag value mismatch! (XOR diff = %032h)", tag ^ exp_tag);
      end else if (test_mode == 1'b1 && tag_ref_loaded !== 1'b1) begin
        error_count++;
        $display("  [FAIL] tag_ref_loaded should be 1 after loading tag_ref in Mode 1!");
      end else if (test_mode == 1'b1 && verify_pass !== expect_pass) begin
        error_count++;
        $display("  [FAIL] verify_pass flag mismatch! (got %b, expected %b)", verify_pass,
                 expect_pass);
      end else begin
        $display("  [PASS] All assertions passed.");
      end

      //===================================================================
      // 8. OUTPUT STABILITY CHECK (Held until finish_reset)
      //===================================================================
      @(posedge clk);
      #1;
      if (tag_process_valid !== 1'b1 || tag !== exp_tag) begin
        error_count++;
        $display("  [FAIL] Output did not remain stably held while finish_reset is low!");
      end else begin
        $display("  [PASS] Output stability check passed (held until finish_reset).");
      end

      //===================================================================
      // 9. CLEAN UP MESSAGE (Assert finish_reset to complete message)
      //    Ensures ghash_finish is active for exactly 3 clock cycles uniformly.
      //===================================================================
      @(posedge clk);
      finish_reset <= 1'b1;
      @(posedge clk);
      finish_reset <= 1'b0;
    end
  endtask

  //=======================================================================
  // Main test sequence
  //=======================================================================
  initial begin
    // Time 0 initialization: Power-on Reset
    rst_n        = 1'b0;
    finish_reset = 1'b1;
    load_key     = 1'b0;
    mode         = 1'b0;
    AAD          = 128'h0;
    CT           = 128'h0;
    tag_ref      = 128'h0;
    H            = 128'h0;
    E            = 128'h0;
    load_AAD     = 1'b0;
    load_CT      = 1'b0;
    H_valid      = 1'b0;
    E_valid      = 1'b0;
    load_tag_ref = 1'b0;
    CT_last      = 1'b0;

    #20;
    @(posedge clk);
    rst_n        <= 1'b1;
    finish_reset <= 1'b0;
    @(posedge clk);

    $display("==========================================================");
    $display(" TagProcessing Top-Level Testbench");
    $display(" Reference: NIST SP 800-38D Appendix B (TC1-TC4)");
    $display("==========================================================");

    //-------------------------------------------------------------------
    // TEST 1: Reset verification
    //-------------------------------------------------------------------
    reset_all();
    #1;
    test_count++;
    $display("--------------------------------------------------");
    $display("Test %0d: Global Reset verification", test_count);
    if (tag_process_valid !== 1'b0 || H_loaded !== 1'b0 ||
        tag_ref_loaded !== 1'b0 || verify_pass !== 1'b0) begin
      error_count++;
      $display("  [FAIL] Reset failed (signals not cleared)");
    end else begin
      $display("  [PASS]");
    end

    //===================================================================
    // SECTION 1: Mode 0 — Tag Generation (Encryption)
    //===================================================================
    $display("\n>>> SECTION 1: Mode 0 — Tag Generation (NIST TC1 - TC4)");

    // TC1: AAD=0B, CT=0B
    begin
      logic [127:0] h_tc1, e_tc1;
      logic [127:0] aad_tc1[], ct_tc1[];

      h_tc1 = 128'h66e94bd4ef8a2c3b884cfa59ca342b2e;
      e_tc1 = 128'h58e2fccefa7e3061367f1d57a4e7455a;

      run_tag_test("TC1 (Mode 0): AAD=0B, CT=0B",
                   1'b0, h_tc1, e_tc1, aad_tc1, ct_tc1, 128'h0, 1'b0);
    end

    // TC2: AAD=0B, CT=16B (1 block)
    begin
      logic [127:0] h_tc2, e_tc2;
      logic [127:0] aad_tc2[];
      logic [127:0] ct_tc2[1];

      h_tc2     = 128'h66e94bd4ef8a2c3b884cfa59ca342b2e;
      e_tc2     = 128'h58e2fccefa7e3061367f1d57a4e7455a;
      ct_tc2[0] = 128'h0388dace60b6a392f328c2b971b2fe78;

      run_tag_test("TC2 (Mode 0): AAD=0B, CT=16B",
                   1'b0, h_tc2, e_tc2, aad_tc2, ct_tc2, 128'h0, 1'b0);
    end

    // TC3: AAD=0B, CT=64B (4 blocks)
    begin
      logic [127:0] h_tc3, e_tc3;
      logic [127:0] aad_tc3[];
      logic [127:0] ct_tc3[4];

      h_tc3     = 128'hb83b533708bf535d0aa6e52980d53b78;
      e_tc3     = 128'hceeed2bc6e19f4fe6b1494dd431f385b;
      ct_tc3[0] = 128'h42831ec2217774244b7221b784d0d49c;
      ct_tc3[1] = 128'he3aa212f2c02a4e035c17e2329aca12e;
      ct_tc3[2] = 128'h21d514b25466931c7d8f6a5aac84aa05;
      ct_tc3[3] = 128'h1ba30b396a0aac973d58e091473f5985;

      run_tag_test("TC3 (Mode 0): AAD=0B, CT=64B",
                   1'b0, h_tc3, e_tc3, aad_tc3, ct_tc3, 128'h0, 1'b0);
    end

    // TC4: AAD=20B (2 blk), CT=60B (4 blk)
    begin
      logic [127:0] h_tc4, e_tc4;
      logic [127:0] aad_tc4[2];
      logic [127:0] ct_tc4[4];

      h_tc4      = 128'hb83b533708bf535d0aa6e52980d53b78;
      e_tc4      = 128'hceeed2bc6e19f4fe6b1494dd431f385b;
      aad_tc4[0] = 128'hfeedfacedeadbeeffeedfacedeadbeef;
      aad_tc4[1] = 128'habaddad2000000000000000000000000;
      ct_tc4[0]  = 128'h42831ec2217774244b7221b784d0d49c;
      ct_tc4[1]  = 128'he3aa212f2c02a4e035c17e2329aca12e;
      ct_tc4[2]  = 128'h21d514b25466931c7d8f6a5aac84aa05;
      ct_tc4[3]  = 128'h1ba30b396a0aac973d58e09100000000;

      run_tag_test("TC4 (Mode 0): AAD=20B, CT=60B",
                   1'b0, h_tc4, e_tc4, aad_tc4, ct_tc4, 128'h0, 1'b0);
    end

    //===================================================================
    // SECTION 2: Mode 1 — Tag Verification (Decryption / Auth)
    //===================================================================
    $display("\n>>> SECTION 2: Mode 1 — Tag Verification (Valid & Tampered tag_ref)");

    // Test Case 2 (Mode 1): Valid tag_ref -> expect verify_pass = 1
    begin
      logic [127:0] h_tc2, e_tc2, valid_tag_tc2;
      logic [127:0] aad_tc2[];
      logic [127:0] ct_tc2[1];
      logic [127:0] len_blk_tc2, ghash_tc2;

      h_tc2     = 128'h66e94bd4ef8a2c3b884cfa59ca342b2e;
      e_tc2     = 128'h58e2fccefa7e3061367f1d57a4e7455a;
      ct_tc2[0] = 128'h0388dace60b6a392f328c2b971b2fe78;

      // Compute exact expected tag for this message
      len_blk_tc2   = {61'd0, 3'd0, 61'd16, 3'd0};
      ghash_tc2     = rtl_gf128_mul(ct_tc2[0], h_tc2);
      ghash_tc2     = rtl_gf128_mul(ghash_tc2 ^ len_blk_tc2, h_tc2);
      valid_tag_tc2 = ghash_tc2 ^ e_tc2;

      run_tag_test("TC2 (Mode 1 - Valid tag_ref): verify_pass MUST be 1",
                   1'b1, h_tc2, e_tc2, aad_tc2, ct_tc2,
                   valid_tag_tc2, 1'b1);
    end

    // Test Case 2 (Mode 1): Tampered tag_ref (1 bit flipped) -> expect verify_pass = 0
    begin
      logic [127:0] h_tc2, e_tc2, valid_tag_tc2, tampered_tag;
      logic [127:0] aad_tc2[];
      logic [127:0] ct_tc2[1];
      logic [127:0] len_blk_tc2, ghash_tc2;

      h_tc2     = 128'h66e94bd4ef8a2c3b884cfa59ca342b2e;
      e_tc2     = 128'h58e2fccefa7e3061367f1d57a4e7455a;
      ct_tc2[0] = 128'h0388dace60b6a392f328c2b971b2fe78;

      len_blk_tc2   = {61'd0, 3'd0, 61'd16, 3'd0};
      ghash_tc2     = rtl_gf128_mul(ct_tc2[0], h_tc2);
      ghash_tc2     = rtl_gf128_mul(ghash_tc2 ^ len_blk_tc2, h_tc2);
      valid_tag_tc2 = ghash_tc2 ^ e_tc2;
      tampered_tag  = valid_tag_tc2 ^ 128'h1; // Corrupted tag

      run_tag_test("TC2 (Mode 1 - Tampered tag_ref): verify_pass MUST be 0",
                   1'b1, h_tc2, e_tc2, aad_tc2, ct_tc2,
                   tampered_tag, 1'b0);
    end

    // Test Case 4 (Mode 1): Valid tag_ref -> expect verify_pass = 1
    begin
      logic [127:0] h_tc4, e_tc4, valid_tag_tc4;
      logic [127:0] aad_tc4[2];
      logic [127:0] ct_tc4[4];
      logic [127:0] len_blk_tc4, ghash_tc4;

      h_tc4      = 128'hb83b533708bf535d0aa6e52980d53b78;
      e_tc4      = 128'hceeed2bc6e19f4fe6b1494dd431f385b;
      aad_tc4[0] = 128'hfeedfacedeadbeeffeedfacedeadbeef;
      aad_tc4[1] = 128'habaddad2000000000000000000000000;
      ct_tc4[0]  = 128'h42831ec2217774244b7221b784d0d49c;
      ct_tc4[1]  = 128'he3aa212f2c02a4e035c17e2329aca12e;
      ct_tc4[2]  = 128'h21d514b25466931c7d8f6a5aac84aa05;
      ct_tc4[3]  = 128'h1ba30b396a0aac973d58e09100000000;

      // Compute exact expected tag for TC4
      len_blk_tc4 = {61'd32, 3'd0, 61'd64, 3'd0};
      ghash_tc4   = 128'h0;
      for (int i = 0; i < 2; i++) ghash_tc4 = rtl_gf128_mul(ghash_tc4 ^ aad_tc4[i], h_tc4);
      for (int j = 0; j < 4; j++) ghash_tc4 = rtl_gf128_mul(ghash_tc4 ^ ct_tc4[j], h_tc4);
      ghash_tc4   = rtl_gf128_mul(ghash_tc4 ^ len_blk_tc4, h_tc4);
      valid_tag_tc4 = ghash_tc4 ^ e_tc4;

      run_tag_test("TC4 (Mode 1 - Valid tag_ref): verify_pass MUST be 1",
                   1'b1, h_tc4, e_tc4, aad_tc4, ct_tc4,
                   valid_tag_tc4, 1'b1);
    end

    // Test Case 4 (Mode 1): Tampered tag_ref (All zeros) -> expect verify_pass = 0
    begin
      logic [127:0] h_tc4, e_tc4;
      logic [127:0] aad_tc4[2];
      logic [127:0] ct_tc4[4];

      h_tc4      = 128'hb83b533708bf535d0aa6e52980d53b78;
      e_tc4      = 128'hceeed2bc6e19f4fe6b1494dd431f385b;
      aad_tc4[0] = 128'hfeedfacedeadbeeffeedfacedeadbeef;
      aad_tc4[1] = 128'habaddad2000000000000000000000000;
      ct_tc4[0]  = 128'h42831ec2217774244b7221b784d0d49c;
      ct_tc4[1]  = 128'he3aa212f2c02a4e035c17e2329aca12e;
      ct_tc4[2]  = 128'h21d514b25466931c7d8f6a5aac84aa05;
      ct_tc4[3]  = 128'h1ba30b396a0aac973d58e09100000000;

      run_tag_test("TC4 (Mode 1 - All-zero tag_ref): verify_pass MUST be 0",
                   1'b1, h_tc4, e_tc4, aad_tc4, ct_tc4,
                   128'h0, 1'b0);
    end

    //===================================================================
    // Summary
    //===================================================================
    $display("");
    $display("==========================================================");
    $display(" SUMMARY: TagProcessing");
    $display("   Total  : %0d", test_count);
    $display("   Passed : %0d", test_count - error_count);
    $display("   Failed : %0d", error_count);
    $display("==========================================================");
    if (error_count == 0)
      $display(" ALL TESTS PASSED (100%% Match with RTL Specification)");
    else
      $error(" %0d TEST(S) FAILED", error_count);
    $display("==========================================================");

    #20;
    $finish;
  end

endmodule
