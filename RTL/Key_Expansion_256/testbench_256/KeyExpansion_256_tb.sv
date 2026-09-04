`timescale 1ns / 1ps

//=============================================================================
// Testbench: KeyExpansion_256_tb (Fully Synchronous posedge-driven)
//
// Verifies AES-256 Key Expansion (KeyExpansion_256.sv) against official
// NIST FIPS 197 specification test vectors:
//   - Test 1: Global Reset Verification (rst_n active-low)
//   - Test 2: NIST FIPS 197 Appendix A.3 (256-bit Key Expansion Example)
//   - Test 3: NIST FIPS 197 Appendix C.3 (AES-256 Cipher Example Vector)
//   - Test 4: All-Zero 256-bit Key Vector
//   - Test 5: Back-to-Back Key Expansion (Consecutive Keys)
//   - Test 6: Handshake & Deassertion Verification (expansion_finish)
//
// Bit & Byte Ordering Specification (NIST FIPS 197 Big-Endian):
// -------------------------------------------------------------
// - cipher_key[255:0] = {w[0], w[1], w[2], w[3], w[4], w[5], w[6], w[7]}
//     * cipher_key[255:224] = w[0] (Byte 0 at [255:248], Byte 3 at [231:224])
//     * cipher_key[223:192] = w[1]
//     * cipher_key[191:160] = w[2]
//     * cipher_key[159:128] = w[3]
//     * cipher_key[127:96]  = w[4]
//     * cipher_key[95:64]   = w[5]
//     * cipher_key[63:32]   = w[6]
//     * cipher_key[31:0]    = w[7] (Byte 28 at [31:24], Byte 31 at [7:0])
// - round_key[r][127:0] = {w[4r], w[4r+1], w[4r+2], w[4r+3]} (r = 0..14)
//
// References:
//   - References/NIST.FIPS.197_specs.pdf (Section 5.2, Appendix A.3, Appendix C.3)
//=============================================================================
module KeyExpansion_256_tb;

  //-----------------------------------------------------------------------
  // DUT signals
  //-----------------------------------------------------------------------
  logic         clk;
  logic         rst_n;
  logic         expansion_en;
  logic [255:0] cipher_key;

  logic [127:0] round_key[0:14];
  logic         expansion_finish;

  //-----------------------------------------------------------------------
  // DUT Instantiation
  //-----------------------------------------------------------------------
  KeyExpansion_256 dut (
      .clk             (clk),
      .rst_n           (rst_n),
      .expansion_en    (expansion_en),
      .cipher_key      (cipher_key),
      .round_key       (round_key),
      .expansion_finish(expansion_finish)
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
    $dumpfile("KeyExpansion_256_tb.vcd");
    $dumpvars(0, KeyExpansion_256_tb);
  end

  //-----------------------------------------------------------------------
  // Scoreboard counters
  //-----------------------------------------------------------------------
  int test_count  = 0;
  int error_count = 0;

  //=======================================================================
  // NIST FIPS 197 AES S-Box Look-Up Table
  //=======================================================================
  function automatic logic [7:0] sbox_lut(input logic [7:0] in_byte);
    logic [7:0] sbox_table[0:255] = '{
      8'h63, 8'h7c, 8'h77, 8'h7b, 8'hf2, 8'h6b, 8'h6f, 8'hc5, 8'h30, 8'h01, 8'h67, 8'h2b, 8'hfe, 8'hd7, 8'hab, 8'h76,
      8'hca, 8'h82, 8'hc9, 8'h7d, 8'hfa, 8'h59, 8'h47, 8'hf0, 8'had, 8'hd4, 8'ha2, 8'haf, 8'h9c, 8'ha4, 8'h72, 8'hc0,
      8'hb7, 8'hfd, 8'h93, 8'h26, 8'h36, 8'h3f, 8'hf7, 8'hcc, 8'h34, 8'ha5, 8'he5, 8'hf1, 8'h71, 8'hd8, 8'h31, 8'h15,
      8'h04, 8'hc7, 8'h23, 8'hc3, 8'h18, 8'h96, 8'h05, 8'h9a, 8'h07, 8'h12, 8'h80, 8'he2, 8'heb, 8'h27, 8'hb2, 8'h75,
      8'h09, 8'h83, 8'h2c, 8'h1a, 8'h1b, 8'h6e, 8'h5a, 8'ha0, 8'h52, 8'h3b, 8'hd6, 8'hb3, 8'h29, 8'he3, 8'h2f, 8'h84,
      8'h53, 8'hd1, 8'h00, 8'hed, 8'h20, 8'hfc, 8'hb1, 8'h5b, 8'h6a, 8'hcb, 8'hbe, 8'h39, 8'h4a, 8'h4c, 8'h58, 8'hcf,
      8'hd0, 8'hef, 8'haa, 8'hfb, 8'h43, 8'h4d, 8'h33, 8'h85, 8'h45, 8'hf9, 8'h02, 8'h7f, 8'h50, 8'h3c, 8'h9f, 8'ha8,
      8'h51, 8'ha3, 8'h40, 8'h8f, 8'h92, 8'h9d, 8'h38, 8'hf5, 8'hbc, 8'hb6, 8'hda, 8'h21, 8'h10, 8'hff, 8'hf3, 8'hd2,
      8'hcd, 8'h0c, 8'h13, 8'hec, 8'h5f, 8'h97, 8'h44, 8'h17, 8'hc4, 8'ha7, 8'h7e, 8'h3d, 8'h64, 8'h5d, 8'h19, 8'h73,
      8'h60, 8'h81, 8'h4f, 8'hdc, 8'h22, 8'h2a, 8'h90, 8'h88, 8'h46, 8'hee, 8'hb8, 8'h14, 8'hde, 8'h5e, 8'h0b, 8'hdb,
      8'he0, 8'h32, 8'h3a, 8'h0a, 8'h49, 8'h06, 8'h24, 8'h5e, 8'hc2, 8'hd3, 8'hac, 8'h62, 8'h91, 8'h95, 8'he4, 8'h79,
      8'he7, 8'hc8, 8'h37, 8'h6d, 8'h8d, 8'hd5, 8'h4e, 8'ha9, 8'h6c, 8'h56, 8'hf4, 8'hea, 8'h65, 8'h7a, 8'hae, 8'h08,
      8'hba, 8'h78, 8'h25, 8'h2e, 8'h1c, 8'ha6, 8'hb4, 8'hc6, 8'he8, 8'hdd, 8'h74, 8'h1f, 8'h4b, 8'hbd, 8'h8b, 8'h8a,
      8'h70, 8'h3e, 8'hb5, 8'h66, 8'h48, 8'h03, 8'hf6, 8'h0e, 8'h61, 8'h35, 8'h57, 8'hb9, 8'h86, 8'hc1, 8'h1d, 8'h9e,
      8'he1, 8'hf8, 8'h98, 8'h11, 8'h69, 8'hd9, 8'h8e, 8'h94, 8'h9b, 8'h1e, 8'h87, 8'he9, 8'hce, 8'h55, 8'h28, 8'hdf,
      8'h8c, 8'ha1, 8'h89, 8'h0d, 8'hbf, 8'he6, 8'h42, 8'h68, 8'h41, 8'h99, 8'h2d, 8'h0f, 8'hb0, 8'h54, 8'hbb, 8'h16
    };
    return sbox_table[in_byte];
  endfunction

  function automatic logic [31:0] subword_func(input logic [31:0] word_in);
    return {sbox_lut(word_in[31:24]), sbox_lut(word_in[23:16]),
            sbox_lut(word_in[15:8]),  sbox_lut(word_in[7:0])};
  endfunction

  function automatic logic [31:0] rotword_func(input logic [31:0] word_in);
    return {word_in[23:0], word_in[31:24]};
  endfunction

  function automatic logic [31:0] rcon_lut(input int step);
    case (step)
      1:  return 32'h01000000;
      2:  return 32'h02000000;
      3:  return 32'h04000000;
      4:  return 32'h08000000;
      5:  return 32'h10000000;
      6:  return 32'h20000000;
      7:  return 32'h40000000;
      default: return 32'h01000000;
    endcase
  endfunction

  //=======================================================================
  // Golden Model: Official NIST FIPS 197 AES-256 Key Expansion Algorithm
  //=======================================================================
  function automatic void fips197_aes256_key_expansion(
      input  logic [255:0] cipher_key_in,
      output logic [127:0] exp_round_keys[0:14]
  );
    logic [31:0] w[0:59];
    logic [31:0] temp;
    int rcon_step;

    // 1. Initial 8 words (Nk = 8) directly from cipher_key
    w[0] = cipher_key_in[255:224];
    w[1] = cipher_key_in[223:192];
    w[2] = cipher_key_in[191:160];
    w[3] = cipher_key_in[159:128];
    w[4] = cipher_key_in[127:96];
    w[5] = cipher_key_in[95:64];
    w[6] = cipher_key_in[63:32];
    w[7] = cipher_key_in[31:0];

    // 2. Expand words w[8] to w[59] (total 60 words for 15 round keys)
    rcon_step = 1;
    for (int i = 8; i < 60; i++) begin
      temp = w[i - 1];
      if (i % 8 == 0) begin
        temp = subword_func(rotword_func(temp)) ^ rcon_lut(rcon_step);
        rcon_step++;
      end else if (i % 8 == 4) begin
        temp = subword_func(temp);
      end
      w[i] = w[i - 8] ^ temp;
    end

    // 3. Assemble 15 round keys (4 words each)
    for (int r = 0; r <= 14; r++) begin
      exp_round_keys[r] = {w[4 * r], w[4 * r + 1], w[4 * r + 2], w[4 * r + 3]};
    end
  endfunction

  //=======================================================================
  // Task: reset_dut
  //   Executes a clean asynchronous reset pulse.
  //=======================================================================
  task automatic reset_dut();
    begin
      @(posedge clk);
      rst_n        <= 1'b0;
      expansion_en <= 1'b0;
      cipher_key   <= 256'h0;
      repeat (2) @(posedge clk);
      rst_n <= 1'b1;
      @(posedge clk);
    end
  endtask

  //=======================================================================
  // Task: run_key_expansion_test
  //
  //   Executes a full 256-bit Key Expansion test:
  //   1. Applies cipher_key synchronously.
  //   2. Asserts expansion_en.
  //   3. Waits for expansion_finish (expected 13 cycles).
  //   4. Verifies all 15 round keys [0:14] against NIST FIPS 197 Golden Model.
  //   5. Deasserts expansion_en and checks finish handshake drops to 0.
  //=======================================================================
  task automatic run_key_expansion_test(
      input string        test_name,
      input logic [255:0] key_input,
      input logic [127:0] expected_round_keys[0:14]
  );
    logic [127:0] model_round_keys[0:14];
    int mismatch_count;
    int wait_cycles;
    begin
      test_count++;
      mismatch_count = 0;

      // Compute Golden Model reference
      fips197_aes256_key_expansion(key_input, model_round_keys);

      $display("--------------------------------------------------------------------------------");
      $display("Test %0d: %s", test_count, test_name);
      $display("  [Cipher Key] 256'h%064h", key_input);

      // 1. Drive inputs synchronously at posedge clk
      @(posedge clk);
      cipher_key   <= key_input;
      expansion_en <= 1'b1;

      // 2. Wait for expansion_finish with timeout guard (max 20 clock cycles)
      wait_cycles = 0;
      while (!expansion_finish && wait_cycles < 20) begin
        @(posedge clk);
        wait_cycles++;
      end

      #1; // Sample shortly after clock edge

      // 3. Check handshake flag
      if (!expansion_finish) begin
        error_count++;
        $display("  [FAIL] expansion_finish TIMEOUT! Did not assert after %0d cycles.", wait_cycles);
      end else begin
        $display("  [Handshake] expansion_finish asserted at cycle %0d (Expected: ~13 cycles).", wait_cycles);
      end

      // 4. Detailed Round Key Verification (Rounds 0 to 14)
      $display("  --- Round Keys Verification (NIST FIPS 197 Reference) ---");
      for (int r = 0; r <= 14; r++) begin
        logic [127:0] golden_ref;
        golden_ref = (expected_round_keys[r] !== 128'h0) ? expected_round_keys[r] : model_round_keys[r];

        if (round_key[r] === golden_ref) begin
          $display("  [PASS] rk[%2d] = %032h (Match)", r, round_key[r]);
        end else begin
          mismatch_count++;
          error_count++;
          $display("  [FAIL] rk[%2d] mismatch!", r);
          $display("         DUT: %032h", round_key[r]);
          $display("         EXP: %032h", golden_ref);
          $display("         XOR: %032h", round_key[r] ^ golden_ref);
        end
      end

      if (mismatch_count == 0) begin
        $display("  => 100%% MATCH for all 15 round keys with NIST FIPS 197.");
      end else begin
        $display("  => %0d / 15 round keys MISMATCHED.", mismatch_count);
      end

      // 5. Deassert expansion_en and verify expansion_finish clears
      @(posedge clk);
      expansion_en <= 1'b0;
      @(posedge clk);
      #1;
      if (expansion_finish !== 1'b0) begin
        error_count++;
        $display("  [FAIL] expansion_finish did not deassert when expansion_en = 0!");
      end else begin
        $display("  [PASS] expansion_finish cleanly deasserted when expansion_en = 0.");
      end
    end
  endtask

  //=======================================================================
  // Main Test Sequence
  //=======================================================================
  initial begin
    // Time 0 Power-on Initialization
    clk          = 1'b0;
    rst_n        = 1'b0;
    expansion_en = 1'b0;
    cipher_key   = 256'h0;

    #20;
    @(posedge clk);
    rst_n <= 1'b1;
    @(posedge clk);

    $display("================================================================================");
    $display(" AES-256 Key Expansion Testbench (KeyExpansion_256_tb)");
    $display(" References: NIST FIPS 197 Specification (Appendix A.3 & C.3)");
    $display("================================================================================");

    //-------------------------------------------------------------------
    // TEST 1: Global Reset Verification
    //-------------------------------------------------------------------
    begin
      int reset_error = 0;
      test_count++;
      $display("--------------------------------------------------------------------------------");
      $display("Test %0d: Global Reset Verification (rst_n = 0)", test_count);

      reset_dut();
      #1;
      if (expansion_finish !== 1'b0) begin
        reset_error++;
        $display("  [FAIL] expansion_finish is NOT 0 after reset!");
      end

      for (int r = 0; r <= 14; r++) begin
        if (round_key[r] !== 128'h0) begin
          reset_error++;
          $display("  [FAIL] round_key[%0d] is NOT 0 after reset (got %032h)!", r, round_key[r]);
        end
      end

      if (reset_error == 0) begin
        $display("  [PASS] All registers and handshake signals cleanly cleared by reset.");
      end else begin
        error_count++;
      end
    end

    //-------------------------------------------------------------------
    // TEST 2: NIST FIPS 197 Appendix A.3 (256-bit Key Expansion Example)
    //
    // Cipher Key = 60 3d eb 10 15 ca 71 be 2b 73 ae f0 85 7d 77 81
    //              1f 35 2c 07 3b 61 08 d7 2d 98 10 a3 09 14 df f4
    //-------------------------------------------------------------------
    begin
      logic [255:0] key_a3;
      logic [127:0] rk_a3[0:14];

      key_a3 = 256'h603deb10_15ca71be_2b73aef0_857d7781_1f352c07_3b6108d7_2d9810a3_0914dff4;

      // Official Golden Vectors from FIPS 197 Appendix A.3 (pages 30-32)
      rk_a3[ 0] = 128'h603deb10_15ca71be_2b73aef0_857d7781;
      rk_a3[ 1] = 128'h1f352c07_3b6108d7_2d9810a3_0914dff4;
      rk_a3[ 2] = 128'h9ba35411_8e6925af_a51a8b5f_2067fcde;
      rk_a3[ 3] = 128'ha8b09c1a_93d194cd_be49846e_b75d5b9a;
      rk_a3[ 4] = 128'hd59aecb8_5bf3c917_fee94248_de8ebe96;
      rk_a3[ 5] = 128'hb5a9328a_2678a647_98312229_2f6c79b3;
      rk_a3[ 6] = 128'h812c81ad_dadf48ba_24360af2_fab8b464;
      rk_a3[ 7] = 128'h98c5bfc9_bebd198e_268c3ba7_09e04214;
      rk_a3[ 8] = 128'h68007bac_b2df3316_96e939e4_6c518d80;
      rk_a3[ 9] = 128'hc814e204_76a9fb8a_5025c02d_59c58239;
      rk_a3[10] = 128'hde136967_6ccc5a71_fa256395_9674ee15;
      rk_a3[11] = 128'h5886ca5d_2e2f31d7_7e0af1fa_27cf73c3;
      rk_a3[12] = 128'h749c47ab_18501dda_e2757e4f_7401905a;
      rk_a3[13] = 128'hcafaaae3_e4d59b34_9adf6ace_bd10190d;
      rk_a3[14] = 128'hfe4890d1_e6188d0b_046df344_706c631e;

      run_key_expansion_test("NIST FIPS 197 Appendix A.3 Example", key_a3, rk_a3);
    end

    //-------------------------------------------------------------------
    // TEST 3: NIST FIPS 197 Appendix C.3 (AES-256 Example Vectors)
    //
    // KEY = 00 01 02 03 04 05 06 07 08 09 0a 0b 0c 0d 0e 0f
    //       10 11 12 13 14 15 16 17 18 19 1a 1b 1c 1d 1e 1f
    //-------------------------------------------------------------------
    begin
      logic [255:0] key_c3;
      logic [127:0] rk_c3[0:14];

      key_c3 = 256'h00010203_04050607_08090a0b_0c0d0e0f_10111213_14151617_18191a1b_1c1d1e1f;

      // Official Golden Vectors from FIPS 197 Appendix C.3 (pages 42-46)
      rk_c3[ 0] = 128'h00010203_04050607_08090a0b_0c0d0e0f;
      rk_c3[ 1] = 128'h10111213_14151617_18191a1b_1c1d1e1f;
      rk_c3[ 2] = 128'ha573c29f_a176c498_a97fce93_a572c09c;
      rk_c3[ 3] = 128'h1651a8cd_0244beda_1a5da4c1_0640bade;
      rk_c3[ 4] = 128'hae87dff0_0ff11b68_a68ed5fb_03fc1567;
      rk_c3[ 5] = 128'h6de1f148_6fa54f92_75f8eb53_73b8518d;
      rk_c3[ 6] = 128'hc656827f_c9a79917_6f294cec_6cd5598b;
      rk_c3[ 7] = 128'h3de23a75_524775e7_27bf9eb4_5407cf39;
      rk_c3[ 8] = 128'h0bdc905f_c27b0948_ad5245a4_c1871c2f;
      rk_c3[ 9] = 128'h45f5a660_17b2d387_300d4d33_640a820a;
      rk_c3[10] = 128'h7ccff71c_beb4fe54_13e6bbf0_d261a7df;
      rk_c3[11] = 128'hf01af8fe_e7a82b79_d7a5664a_b3afe440;
      rk_c3[12] = 128'h25a6fe71_9b120025_88f4bbd5_5a951c0a;
      rk_c3[13] = 128'h4e306499_a9984fe0_7e3d29aa_cd92cdea;
      rk_c3[14] = 128'h2a1b79cc_b10979e9_39fdc23c_6368de36;

      run_key_expansion_test("NIST FIPS 197 Appendix C.3 Example", key_c3, rk_c3);
    end

    //-------------------------------------------------------------------
    // TEST 4: All-Zero 256-bit Key Vector (Corner Case)
    //-------------------------------------------------------------------
    begin
      logic [255:0] key_zeros;
      logic [127:0] rk_zeros[0:14];

      key_zeros = 256'h0;

      rk_zeros[ 0] = 128'h00000000_00000000_00000000_00000000;
      rk_zeros[ 1] = 128'h00000000_00000000_00000000_00000000;
      rk_zeros[ 2] = 128'h62636363_62636363_62636363_62636363;
      rk_zeros[ 3] = 128'haafbfbfb_aafbfbfb_aafbfbfb_aafbfbfb;
      rk_zeros[ 4] = 128'h6f6c6ccf_0d0f0fac_6f6c6ccf_0d0f0fac;
      rk_zeros[ 5] = 128'h7d8d8d6a_d7767691_7d8d8d6a_d7767691;
      rk_zeros[ 6] = 128'h5354edc1_5e5be26d_31378ea2_3c38810e;
      rk_zeros[ 7] = 128'h968a81c1_41fcf750_3c717a3a_eb070cab;
      rk_zeros[ 8] = 128'h9eaa8f28_c0f16d45_f1c6e3e7_cdfe62e9;
      rk_zeros[ 9] = 128'h2b312bdf_6acddc8f_56bca6b5_bdbbaa1e;
      rk_zeros[10] = 128'h6406fd52_a4f79017_553173f0_98cf1119;
      rk_zeros[11] = 128'h6dbba90b_07767584_51cad331_ec71792f;
      rk_zeros[12] = 128'he7b0e89c_4347788b_16760b7b_8eb91a62;
      rk_zeros[13] = 128'h74ed0ba1_739b7e25_2251ad14_ce20d43b;
      rk_zeros[14] = 128'h10f80a17_53bf729c_45c979e7_cb706385;

      run_key_expansion_test("All-Zero 256-bit Key Vector", key_zeros, rk_zeros);
    end

    //-------------------------------------------------------------------
    // TEST 5: Back-to-Back Key Expansion (Consecutive Key Streams)
    //-------------------------------------------------------------------
    begin
      logic [255:0] key_b2b;
      logic [127:0] rk_dummy[0:14];

      for (int i = 0; i <= 14; i++) rk_dummy[i] = 128'h0;

      key_b2b = 256'h01234567_89abcdef_fedcba98_76543210_00112233_44556677_8899aabb_ccddeeff;
      run_key_expansion_test("Back-to-Back Consecutive Expansion #1", key_b2b, rk_dummy);

      key_b2b = 256'hffffffff_eeeeeeee_dddddddd_cccccccc_bbbbbbbb_aaaaaaaa_99999999_88888888;
      run_key_expansion_test("Back-to-Back Consecutive Expansion #2", key_b2b, rk_dummy);
    end

    //===================================================================
    // Test Summary
    //===================================================================
    $display("");
    $display("================================================================================");
    $display(" SUMMARY: KeyExpansion_256 Verification");
    $display("   Total Tests  : %0d", test_count);
    $display("   Total Errors : %0d", error_count);
    $display("================================================================================");
    if (error_count == 0) begin
      $display(" ALL TESTS PASSED (100%% Compliance with NIST FIPS 197)");
    end else begin
      $error(" %0d ERROR(S) ENCOUNTERED during verification against NIST FIPS 197!", error_count);
    end
    $display("================================================================================");

    #50;
    $finish;
  end

endmodule
