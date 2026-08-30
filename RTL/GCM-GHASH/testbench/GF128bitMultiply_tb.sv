`timescale 1ns / 1ps

//=============================================================================
// Testbench: GF128bitMultiply_tb
//
// Verifies the GF(2^128) Galois Field Multiplier and ReductionBlock.
//
// Bit-Ordering Specification & GCM Reference Equivalence:
// --------------------------------------------------------
// - GCM Standard (NIST SP 800-38D / aes_gcm_golden_appendixB.c):
//     Polynomial X(u) = x_0 + x_1*u + ... + x_127*u^127
//     where x_0 is the MSB (bit 127) and x_127 is the LSB (bit 0).
//     Irreducible polynomial: P(u) = 1 + u + u^2 + u^7 + u^128 (R = 0xE100...00).
//
// - RTL Implementation (GF128bitMultiply.sv):
//     Uses standard mathematical polynomial basis where:
//     bit 0 is x^0 (LSB) and bit 127 is x^127 (MSB).
//     Irreducible polynomial: P(x) = x^128 + x^7 + x^2 + x + 1 (Poly = 0x87).
//
// - Equivalence Relation:
//     RTL_vector = bit_reverse_128(GCM_vector)
//     DUT(bit_reverse_128(A_gcm), bit_reverse_128(B_gcm)) == bit_reverse_128(ghash_mul_c(A_gcm, B_gcm))
//
// Reference: References/aes_gcm_golden_appendixB.c
//            References/nistspecialpublication800-38d.pdf
//=============================================================================
module GF128bitMultiply_tb;

  //-----------------------------------------------------------------------
  // DUT signals
  //-----------------------------------------------------------------------
  logic [127:0] H_reg;
  logic [127:0] data_in;
  logic [127:0] data_out;

  int test_count  = 0;
  int error_count = 0;

  //-----------------------------------------------------------------------
  // DUT instantiation
  //-----------------------------------------------------------------------
  GF128bitMultiply dut (
      .H_reg   (H_reg),
      .data_in (data_in),
      .data_out(data_out)
  );

  //-----------------------------------------------------------------------
  // Waveform dump
  //-----------------------------------------------------------------------
  initial begin
    $dumpfile("GF128bitMultiply_tb.vcd");
    $dumpvars(0, GF128bitMultiply_tb);
  end

  //=======================================================================
  // Utility: 128-bit Bit-Reversal
  //   Maps between GCM bit-order (MSB=x^0) and RTL bit-order (LSB=x^0).
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
  // Model 1: RTL Standard Polynomial Basis Reference
  //   Carryless multiplication + Reduction by P(x) = x^128 + x^7 + x^2 + x + 1
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

  function automatic logic [127:0] rtl_poly_mul_ref(
      input logic [127:0] operand_a,
      input logic [127:0] operand_b
  );
    begin
      return polynomial_reduction(carryless_multiply(operand_a, operand_b));
    end
  endfunction

  //=======================================================================
  // Model 2: Exact Golden C Implementation (from aes_gcm_golden_appendixB.c)
  //   ghash_mul() in GF(2^128) using R = 0xE1000000000000000000000000000000
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
  // Task: run_rtl_test
  //   Tests directly in RTL standard polynomial basis.
  //=======================================================================
  task automatic run_rtl_test(
      input logic [127:0] test_H,
      input logic [127:0] test_data,
      input string        test_name
  );
    logic [255:0] exp_product;
    logic [127:0] exp_result;
    begin
      test_count++;
      H_reg   = test_H;
      data_in = test_data;
      #1;

      exp_product = carryless_multiply(test_H, test_data);
      exp_result  = polynomial_reduction(exp_product);

      $display("--------------------------------------------------");
      $display("Test %0d (RTL Basis): %s", test_count, test_name);
      $display("  H_reg            = %032h", test_H);
      $display("  data_in          = %032h", test_data);
      $display("  DUT product      = %064h (exp: %064h)", dut.X128_result, exp_product);
      $display("  DUT result       = %032h (exp: %032h)", data_out, exp_result);

      if (dut.X128_result !== exp_product) begin
        error_count++;
        $display("  [FAIL] X128 Product mismatch (XOR diff = %064h)",
                 dut.X128_result ^ exp_product);
      end else if (data_out !== exp_result) begin
        error_count++;
        $display("  [FAIL] ReductionBlock result mismatch (XOR diff = %032h)",
                 data_out ^ exp_result);
      end else begin
        $display("  [PASS]");
      end
    end
  endtask

  //=======================================================================
  // Task: run_nist_gcm_test
  //   Takes GCM Appendix B vectors (big-endian), converts to RTL basis
  //   via bit_reverse_128, and validates against Golden C reference.
  //=======================================================================
  task automatic run_nist_gcm_test(
      input logic [127:0] H_gcm,
      input logic [127:0] data_gcm,
      input logic [127:0] expected_Z_gcm,
      input string        test_name
  );
    logic [127:0] H_rtl;
    logic [127:0] data_rtl;
    logic [127:0] golden_c_Z_gcm;
    logic [127:0] exp_Z_rtl;
    logic [127:0] dut_Z_gcm;
    begin
      test_count++;

      // Compute Golden C result in GCM format
      golden_c_Z_gcm = gcm_c_golden_mul(H_gcm, data_gcm);

      // Verify golden C result matches provided expected vector if specified
      if (expected_Z_gcm !== 128'h0 && expected_Z_gcm !== golden_c_Z_gcm) begin
        $display("  [WARNING] Provided Expected (%032h) != Golden C Model (%032h)",
                 expected_Z_gcm, golden_c_Z_gcm);
      end

      // Convert GCM vectors to RTL basis
      H_rtl     = bit_reverse_128(H_gcm);
      data_rtl  = bit_reverse_128(data_gcm);
      exp_Z_rtl = bit_reverse_128(golden_c_Z_gcm);

      // Apply to DUT
      H_reg   = H_rtl;
      data_in = data_rtl;
      #1;

      dut_Z_gcm = bit_reverse_128(data_out);

      $display("--------------------------------------------------");
      $display("Test %0d (NIST GCM Vector): %s", test_count, test_name);
      $display("  [GCM Format] H_gcm   = %032h", H_gcm);
      $display("               D_gcm   = %032h", data_gcm);
      $display("               EXP_gcm = %032h", golden_c_Z_gcm);
      $display("               DUT_gcm = %032h", dut_Z_gcm);
      $display("  [RTL Format] H_rtl   = %032h", H_rtl);
      $display("               D_rtl   = %032h", data_rtl);
      $display("               DUT_out = %032h (exp: %032h)", data_out, exp_Z_rtl);

      if (data_out !== exp_Z_rtl) begin
        error_count++;
        $display("  [FAIL] RTL result mismatch with GCM Golden Model!");
        $display("         XOR diff = %032h", data_out ^ exp_Z_rtl);
      end else begin
        $display("  [PASS] Perfectly matches Golden C Reference (aes_gcm_golden_appendixB.c)");
      end
    end
  endtask

  //=======================================================================
  // Main test sequence
  //=======================================================================
  initial begin
    H_reg       = 128'd0;
    data_in     = 128'd0;
    test_count  = 0;
    error_count = 0;

    #5;

    $display("==========================================================");
    $display(" GF128bitMultiply Testbench");
    $display(" References: NIST SP 800-38D & aes_gcm_golden_appendixB.c");
    $display("==========================================================");

    //====================================================================
    // SECTION 1: Fundamental Mathematical Properties (RTL Basis)
    //====================================================================
    $display("\n>>> SECTION 1: Mathematical Properties (RTL Basis)");

    // 1. Zero property
    run_rtl_test(128'h0, 128'h0, "0 x 0 = 0");
    run_rtl_test(128'h0, 128'h123456789ABCDEF00123456789ABCDEF, "0 x A = 0");
    run_rtl_test(128'h123456789ABCDEF00123456789ABCDEF, 128'h0, "A x 0 = 0");

    // 2. Identity element (x^0 = 1)
    run_rtl_test(128'h1, 128'h1, "1 x 1 = 1");
    run_rtl_test(128'h123456789ABCDEF00123456789ABCDEF, 128'h1, "A x 1 = A");
    run_rtl_test(128'h1, 128'h123456789ABCDEF00123456789ABCDEF, "1 x A = A");

    // 3. Reduction boundary test: x^127 * x = x^128 = x^7 + x^2 + x + 1 (0x87)
    run_rtl_test(128'h80000000000000000000000000000000, 128'h2,
                 "Reduction: x^127 * x = x^128 == x^7 + x^2 + x + 1 (0x87)");

    // 4. Maximum degree test: x^127 * x^127
    run_rtl_test(128'h80000000000000000000000000000000,
                 128'h80000000000000000000000000000000,
                 "Max degree: x^127 * x^127");

    // 5. All ones
    run_rtl_test(128'hFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF,
                 128'hFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF,
                 "All ones: 0xFF...FF x 0xFF...FF");

    // 6. Commutative test (A x B == B x A)
    run_rtl_test(128'h0123456789ABCDEFFEDCBA9876543210,
                 128'hFEDCBA98765432100123456789ABCDEF,
                 "Commutative test A x B");
    run_rtl_test(128'hFEDCBA98765432100123456789ABCDEF,
                 128'h0123456789ABCDEFFEDCBA9876543210,
                 "Commutative test B x A");

    //====================================================================
    // SECTION 2: NIST SP 800-38D Appendix B Vectors (via Golden C Model)
    //====================================================================
    $display("\n>>> SECTION 2: NIST SP 800-38D Appendix B Test Vectors");

    // Vector 1: NIST TC1/TC2 Subkey H
    //   Key = 00...00 -> H = 66e94bd4ef8a2c3b884cfa59ca342b2e
    //   Multiply H with 0 -> 0
    run_nist_gcm_test(128'h66E94BD4EF8A2C3B884CFA59CA342B2E,
                      128'h00000000000000000000000000000000,
                      128'h00000000000000000000000000000000,
                      "NIST TC1/TC2: H x 0 = 0");

    // Vector 2: NIST TC2 Step 1 (H x CT[0])
    //   H     = 66e94bd4ef8a2c3b884cfa59ca342b2e
    //   CT[0] = 0388dace60b6a392f328c2b971b2fe78
    //   Expected Y1 = 5e2ec746917062882c85b0685353deb7
    run_nist_gcm_test(128'h66E94BD4EF8A2C3B884CFA59CA342B2E,
                      128'h0388DACE60B6A392F328C2B971B2FE78,
                      128'h5E2EC746917062882C85B0685353DEB7,
                      "NIST TC2 Step 1: H x CT[0]");

    // Vector 3: NIST TC2 Step 2 (Final GHASH = H x (Y1 ^ Length_Block))
    //   Y1 ^ Len = 5e2ec746917062882c85b0685353deb7 ^ 00...0080 = 5e2ec746917062882c85b0685353de37
    //   Expected GHASH_out = f38cbb1ad69223dcc3457ae5b6b0f885
    run_nist_gcm_test(128'h66E94BD4EF8A2C3B884CFA59CA342B2E,
                      128'h5E2EC746917062882C85B0685353DE37,
                      128'hF38CBB1AD69223DCC3457AE5B6B0F885,
                      "NIST TC2 Step 2: H x (Y1 ^ Len) -> GHASH_out");

    // Vector 4: NIST TC3/TC4 Subkey H
    //   Key = fe...08 -> H = b83b533708bf535d0aa6e52980d53b78
    //   CT[0] = 42831ec2217774244b7221b784d0d49c
    run_nist_gcm_test(128'hB83B533708BF535D0AA6E52980D53B78,
                      128'h42831EC2217774244B7221B784D0D49C,
                      128'h0,
                      "NIST TC3 Step 1: H x CT[0]");

    // Vector 5: NIST TC4 AAD[0]
    //   H      = b83b533708bf535d0aa6e52980d53b78
    //   AAD[0] = feedfacedeadbeeffeedfacedeadbeef
    run_nist_gcm_test(128'hB83B533708BF535D0AA6E52980D53B78,
                      128'hFEEDFACEDEADBEEFFEEDFACEDEADBEEF,
                      128'h0,
                      "NIST TC4 Step 1: H x AAD[0]");

    //====================================================================
    // SECTION 3: Random Stress Testing (50 vectors)
    //====================================================================
    $display("\n>>> SECTION 3: Random Stress Testing (50 Vectors)");

    for (int r = 0; r < 50; r++) begin
      logic [127:0] rand_H;
      logic [127:0] rand_data;

      rand_H    = {$urandom(), $urandom(), $urandom(), $urandom()};
      rand_data = {$urandom(), $urandom(), $urandom(), $urandom()};

      run_nist_gcm_test(rand_H, rand_data, 128'h0,
                        $sformatf("Random Vector #%0d", r + 1));
    end

    //====================================================================
    // Summary
    //====================================================================
    $display("");
    $display("==========================================================");
    $display(" TEST SUMMARY: GF128bitMultiply");
    $display(" Total tests : %0d", test_count);
    $display(" Passed      : %0d", test_count - error_count);
    $display(" Failed      : %0d", error_count);
    $display("==========================================================");

    if (error_count == 0) begin
      $display(" ALL TESTS PASSED (100%% Match with Golden C Reference)");
    end else begin
      $error(" %0d TEST(S) FAILED", error_count);
    end
    $display("==========================================================");

    #10;
    $finish;
  end

endmodule
