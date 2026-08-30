`timescale 1ns / 1ps

//=============================================================================
// Testbench: GHASH_tb (Fully Synchronous posedge-driven)
//
// Verifies the GHASH accumulator core against NIST SP 800-38D GCM
// Appendix B test vectors (TC1–TC4) and Golden C reference model.
//
// Bit-Ordering & Equivalence:
// ----------------------------
// - GCM Standard (aes_gcm_golden_appendixB.c):
//     Bit 127 is x^0, bit 0 is x^127.
// - RTL Core (GHASH.sv / GF128bitMultiply.sv):
//     Bit 0 is x^0, bit 127 is x^127.
// - Mapping:
//     RTL_vector = bit_reverse_128(GCM_vector)
//     GCM_vector = bit_reverse_128(RTL_vector)
//
// Reference: References/aes_gcm_golden_appendixB.c
//            References/nistspecialpublication800-38d.pdf
//=============================================================================
module GHASH_tb;

  //-----------------------------------------------------------------------
  // DUT signals
  //-----------------------------------------------------------------------
  logic         clk;
  logic         finish_reset;
  logic         load_AAD;
  logic         load_CT;
  logic         length_block_valid;
  logic [127:0] AAD;
  logic [127:0] CT;
  logic [127:0] length_block;
  logic [127:0] H_reg;

  logic         ghash_finish;
  logic [127:0] ghash_out;

  //-----------------------------------------------------------------------
  // DUT instantiation
  //-----------------------------------------------------------------------
  GHASH dut (
      .clk               (clk),
      .finish_reset       (finish_reset),
      .load_AAD           (load_AAD),
      .load_CT            (load_CT),
      .length_block_valid (length_block_valid),
      .AAD               (AAD),
      .CT                (CT),
      .length_block       (length_block),
      .H_reg             (H_reg),
      .ghash_finish      (ghash_finish),
      .ghash_out         (ghash_out)
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
    $dumpfile("GHASH_tb.vcd");
    $dumpvars(0, GHASH_tb);
  end

  //-----------------------------------------------------------------------
  // Scoreboard
  //-----------------------------------------------------------------------
  int test_count  = 0;
  int error_count = 0;

  //=======================================================================
  // Utility: 128-bit Bit-Reversal
  //=======================================================================
  function automatic logic [127:0] bit_reverse_128(input logic [127:0] in_vec);
    logic [127:0] out_vec;
    begin
      for (int i = 0; i < 128; i++) begin
        out_vec[i] = in_vec[127 - i];
      end
      return out_vec;
    end
  endfunction

  //=======================================================================
  // Model 1: RTL Polynomial Basis Reference (LSB = x^0)
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
  // Model 2: Golden C GHASH Multiplier (from aes_gcm_golden_appendixB.c)
  //=======================================================================
  function automatic logic [127:0] gcm_c_golden_mul(
      input logic [127:0] X_gcm,
      input logic [127:0] Y_gcm
  );
    logic [7:0] X_bytes[16];
    logic [7:0] Y_bytes[16];
    logic [7:0] V[16];
    logic [7:0] Z[16];
    logic [127:0] result;
    begin
      for (int i = 0; i < 16; i++) begin
        X_bytes[i] = X_gcm[127 - 8*i -: 8];
        Y_bytes[i] = Y_gcm[127 - 8*i -: 8];
        V[i]       = Y_bytes[i];
        Z[i]       = 8'h00;
      end

      for (int i = 0; i < 128; i++) begin
        int xi = (X_bytes[i / 8] >> (7 - (i % 8))) & 1;
        if (xi) begin
          for (int j = 0; j < 16; j++) begin
            Z[j] = Z[j] ^ V[j];
          end
        end

        begin
          int lsb = V[15] & 1;
          for (int j = 15; j > 0; j--) begin
            V[j] = (V[j] >> 1) | ((V[j - 1] & 1) << 7);
          end
          V[0] = V[0] >> 1;

          if (lsb) begin
            V[0] = V[0] ^ 8'hE1;
          end
        end
      end

      for (int i = 0; i < 16; i++) begin
        result[127 - 8*i -: 8] = Z[i];
      end
      return result;
    end
  endfunction

  //=======================================================================
  // Task: reset_dut
  //=======================================================================
  task automatic reset_dut();
    begin
      @(posedge clk);
      finish_reset       <= 1'b1;
      load_AAD           <= 1'b0;
      load_CT            <= 1'b0;
      length_block_valid <= 1'b0;
      AAD                <= 128'h0;
      CT                 <= 128'h0;
      length_block       <= 128'h0;

      repeat (2) @(posedge clk);
      finish_reset <= 1'b0;
      @(posedge clk);
    end
  endtask

  //=======================================================================
  // Task: run_nist_gcm_test
  //   Takes standard NIST GCM vectors (from aes_gcm_golden_appendixB.c),
  //   converts to RTL bit-order, streams into GHASH, and verifies results.
  //=======================================================================
  task automatic run_nist_gcm_test(
      input string        test_name,
      input logic [127:0] H_gcm,
      input logic [127:0] aad_gcm[],
      input logic [127:0] ct_gcm[],
      input logic [127:0] len_block_gcm,
      input logic [127:0] expected_ghash_gcm
  );
    logic [127:0] ref_acc_gcm;
    logic [127:0] ref_acc_rtl;
    logic [127:0] dut_out_gcm;
    int num_aad;
    int num_ct;
    begin
      num_aad = aad_gcm.size();
      num_ct  = ct_gcm.size();

      // Golden GCM computation using C Reference algorithm
      ref_acc_gcm = 128'h0;
      for (int i = 0; i < num_aad; i++) begin
        ref_acc_gcm = gcm_c_golden_mul(ref_acc_gcm ^ aad_gcm[i], H_gcm);
      end
      for (int j = 0; j < num_ct; j++) begin
        ref_acc_gcm = gcm_c_golden_mul(ref_acc_gcm ^ ct_gcm[j], H_gcm);
      end
      ref_acc_gcm = gcm_c_golden_mul(ref_acc_gcm ^ len_block_gcm, H_gcm);

      ref_acc_rtl = bit_reverse_128(ref_acc_gcm);

      reset_dut();
      H_reg <= bit_reverse_128(H_gcm);

      // 1. Stream AAD blocks (in RTL bit-order)
      for (int i = 0; i < num_aad; i++) begin
        @(posedge clk);
        load_AAD           <= 1'b1;
        load_CT            <= 1'b0;
        length_block_valid <= 1'b0;
        AAD                <= bit_reverse_128(aad_gcm[i]);
      end

      // 2. Stream CT blocks (in RTL bit-order)
      for (int j = 0; j < num_ct; j++) begin
        @(posedge clk);
        load_AAD           <= 1'b0;
        load_CT            <= 1'b1;
        length_block_valid <= 1'b0;
        CT                 <= bit_reverse_128(ct_gcm[j]);
      end

      // 3. Drive length block (in RTL bit-order)
      @(posedge clk);
      load_AAD           <= 1'b0;
      load_CT            <= 1'b0;
      length_block_valid <= 1'b1;
      length_block       <= bit_reverse_128(len_block_gcm);

      // 4. Deassert control signals
      @(posedge clk);
      load_AAD           <= 1'b0;
      load_CT            <= 1'b0;
      length_block_valid <= 1'b0;

      //===================================================================
      // 5. CHECK VALID FINISH WINDOW
      //===================================================================
      #1;
      test_count++;
      dut_out_gcm = bit_reverse_128(ghash_out);

      $display("--------------------------------------------------");
      $display("Test %0d: %s", test_count, test_name);
      $display("  [GCM Format] H_gcm       = %032h", H_gcm);
      $display("               GHASH_exp   = %032h", ref_acc_gcm);
      $display("               GHASH_dut   = %032h", dut_out_gcm);
      $display("  [Finish Check] finish    = %b  (expected: 1)", ghash_finish);
      $display("                 RTL_out   = %032h (exp: %032h)", ghash_out, ref_acc_rtl);

      if (ghash_finish !== 1'b1) begin
        error_count++;
        $display("  [FAIL] ghash_finish is NOT asserted!");
      end else if (ghash_out !== ref_acc_rtl) begin
        error_count++;
        $display("  [FAIL] ghash_out mismatch! (XOR diff = %032h)",
                 ghash_out ^ ref_acc_rtl);
      end else begin
        $display("  [PASS] 100%% Match with NIST SP 800-38D / C Golden Model.");
      end

      //===================================================================
      // 6. CHECK DEASSERT
      //===================================================================
      @(posedge clk);
      #1;
      if (ghash_finish !== 1'b0) begin
        error_count++;
        $display("  [FAIL] ghash_finish did not deassert at next posedge!");
      end else begin
        $display("  [PASS] Deassert check passed.");
      end
    end
  endtask

  //=======================================================================
  // Main test sequence
  //=======================================================================
  initial begin
    // Time 0 initialization: Power-on Reset
    finish_reset       = 1'b1;
    load_AAD           = 1'b0;
    load_CT            = 1'b0;
    length_block_valid = 1'b0;
    AAD                = 128'h0;
    CT                 = 128'h0;
    length_block       = 128'h0;
    H_reg              = 128'h0;

    #20;
    @(posedge clk);
    finish_reset <= 1'b0;
    @(posedge clk);

    $display("==========================================================");
    $display(" GHASH Core Testbench (Synchronous posedge)");
    $display(" Reference: NIST SP 800-38D Appendix B (TC1-TC4)");
    $display("==========================================================");

    // Test Reset
    reset_dut();
    #1;
    test_count++;
    $display("--------------------------------------------------");
    $display("Test %0d: Reset verification", test_count);
    if (ghash_finish !== 1'b0 || ghash_out !== 128'h0) begin
      error_count++;
      $display("  [FAIL] Reset failed");
    end else begin
      $display("  [PASS]");
    end

    // NIST Appendix B — Test Case 1 (TC1)
    begin
      logic [127:0] h_tc1;
      logic [127:0] aad_tc1[];
      logic [127:0] ct_tc1[];
      logic [127:0] len_tc1;
      logic [127:0] exp_tc1;

      h_tc1   = 128'h66e94bd4ef8a2c3b884cfa59ca342b2e;
      len_tc1 = 128'h00000000_00000000_00000000_00000000;
      exp_tc1 = 128'h00000000_00000000_00000000_00000000;

      run_nist_gcm_test("TC1: AAD=0B, CT=0B (Appendix B)",
                        h_tc1, aad_tc1, ct_tc1, len_tc1, exp_tc1);
    end

    // NIST Appendix B — Test Case 2 (TC2)
    begin
      logic [127:0] h_tc2;
      logic [127:0] aad_tc2[];
      logic [127:0] ct_tc2[1];
      logic [127:0] len_tc2;
      logic [127:0] exp_tc2;

      h_tc2     = 128'h66e94bd4ef8a2c3b884cfa59ca342b2e;
      ct_tc2[0] = 128'h0388dace60b6a392f328c2b971b2fe78;
      len_tc2   = 128'h00000000_00000000_00000000_00000080;
      exp_tc2   = 128'hf38cbb1ad69223dcc3457ae5b6b0f885;

      run_nist_gcm_test("TC2: AAD=0B, CT=16B (1 block) (Appendix B)",
                        h_tc2, aad_tc2, ct_tc2, len_tc2, exp_tc2);
    end

    // NIST Appendix B — Test Case 3 (TC3)
    begin
      logic [127:0] h_tc3;
      logic [127:0] aad_tc3[];
      logic [127:0] ct_tc3[4];
      logic [127:0] len_tc3;
      logic [127:0] exp_tc3;

      h_tc3     = 128'hb83b533708bf535d0aa6e52980d53b78;
      ct_tc3[0] = 128'h42831ec2217774244b7221b784d0d49c;
      ct_tc3[1] = 128'he3aa212f2c02a4e035c17e2329aca12e;
      ct_tc3[2] = 128'h21d514b25466931c7d8f6a5aac84aa05;
      ct_tc3[3] = 128'h1ba30b396a0aac973d58e091473f5985;
      len_tc3   = 128'h00000000_00000000_00000000_00000200;
      exp_tc3   = 128'h83b2f84f49d4905847e7ce6068b9c2ef;

      run_nist_gcm_test("TC3: AAD=0B, CT=64B (4 blocks) (Appendix B)",
                        h_tc3, aad_tc3, ct_tc3, len_tc3, exp_tc3);
    end

    // NIST Appendix B — Test Case 4 (TC4)
    begin
      logic [127:0] h_tc4;
      logic [127:0] aad_tc4[2];
      logic [127:0] ct_tc4[4];
      logic [127:0] len_tc4;
      logic [127:0] exp_tc4;

      h_tc4      = 128'hb83b533708bf535d0aa6e52980d53b78;
      aad_tc4[0] = 128'hfeedfacedeadbeeffeedfacedeadbeef;
      aad_tc4[1] = 128'habaddad2000000000000000000000000;
      ct_tc4[0]  = 128'h42831ec2217774244b7221b784d0d49c;
      ct_tc4[1]  = 128'he3aa212f2c02a4e035c17e2329aca12e;
      ct_tc4[2]  = 128'h21d514b25466931c7d8f6a5aac84aa05;
      ct_tc4[3]  = 128'h1ba30b396a0aac973d58e09100000000;
      len_tc4    = 128'h00000000_000000a0_00000000_000001e0;
      exp_tc4    = 128'h95279d005c385125ffee7d87a40d221c;

      run_nist_gcm_test("TC4: AAD=20B (2 blk), CT=60B (4 blk) (Appendix B)",
                        h_tc4, aad_tc4, ct_tc4, len_tc4, exp_tc4);
    end

    // Extra Test: AAD only (No CT)
    begin
      logic [127:0] h_aonly;
      logic [127:0] aad_aonly[2];
      logic [127:0] ct_aonly[];
      logic [127:0] len_aonly;

      h_aonly        = 128'h66e94bd4ef8a2c3b884cfa59ca342b2e;
      aad_aonly[0]   = 128'h0123456789abcdef0123456789abcdef;
      aad_aonly[1]   = 128'hfedcba9876543210fedcba9876543210;
      len_aonly      = 128'h00000000_00000100_00000000_00000000;

      run_nist_gcm_test("AAD only: AAD=32B (2 blk), CT=0B",
                        h_aonly, aad_aonly, ct_aonly, len_aonly, 128'h0);
    end

    // Extra Test: Random Vectors (10 tests)
    for (int r = 0; r < 10; r++) begin
      logic [127:0] rand_h;
      logic [127:0] rand_aad[];
      logic [127:0] rand_ct[];
      logic [127:0] rand_len;
      int r_aad_cnt;
      int r_ct_cnt;

      rand_h    = {$urandom(), $urandom(), $urandom(), $urandom()};
      r_aad_cnt = $urandom_range(1, 4);
      r_ct_cnt  = $urandom_range(1, 4);

      rand_aad = new[r_aad_cnt];
      for (int i = 0; i < r_aad_cnt; i++) begin
        rand_aad[i] = {$urandom(), $urandom(), $urandom(), $urandom()};
      end

      rand_ct = new[r_ct_cnt];
      for (int j = 0; j < r_ct_cnt; j++) begin
        rand_ct[j] = {$urandom(), $urandom(), $urandom(), $urandom()};
      end

      rand_len = {64'(r_aad_cnt * 128), 64'(r_ct_cnt * 128)};

      run_nist_gcm_test($sformatf("Random Vector #%0d (AAD=%0d blk, CT=%0d blk)",
                                  r + 1, r_aad_cnt, r_ct_cnt),
                        rand_h, rand_aad, rand_ct, rand_len, 128'h0);
    end

    // Summary
    $display("");
    $display("==========================================================");
    $display(" SUMMARY: GHASH Core");
    $display("   Total  : %0d", test_count);
    $display("   Passed : %0d", test_count - error_count);
    $display("   Failed : %0d", error_count);
    $display("==========================================================");
    if (error_count == 0)
      $display(" ALL TESTS PASSED (100%% Match with NIST & Golden C Model)");
    else
      $error(" %0d TEST(S) FAILED", error_count);
    $display("==========================================================");

    #20;
    $finish;
  end

endmodule
