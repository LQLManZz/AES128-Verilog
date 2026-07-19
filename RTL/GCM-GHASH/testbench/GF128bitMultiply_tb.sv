`timescale 1ns / 1ps

module tb_GF128bitMultiply;

  logic [127:0] H_key;
  logic [127:0] data_in;
  logic [127:0] data_out;

  logic [255:0] expected_product;
  logic [127:0] expected_result;

  int test_count;
  int error_count;

  GF128bitMultiply dut (
      .H_key   (H_key),
      .data_in (data_in),
      .data_out(data_out)
  );

  /*
   * Phép nhân không nhớ trên GF(2).
   *
   * Mỗi bit data_in[i] bằng 1 sẽ tạo ra một bản sao
   * của H_key được dịch trái i bit.
   *
   * Các tích riêng được cộng bằng XOR.
   */
  function automatic logic [255:0] carryless_multiply(input logic [127:0] operand_a,
                                                      input logic [127:0] operand_b);

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


  /*
   * Rút gọn đa thức 256-bit về 128-bit theo:
   *
   * P(x) = x^128 + x^7 + x^2 + x + 1
   *
   * Do đó:
   *
   * x^128 = x^7 + x^2 + x + 1
   *
   * Với bit bậc i, i >= 128:
   *
   * x^i = x^(i-121) + x^(i-126)
   *       + x^(i-127) + x^(i-128)
   */
  function automatic logic [127:0] polynomial_reduction(input logic [255:0] product);

    logic [255:0] remainder;

    begin
      remainder = product;

      /*
       * Phải xử lý từ bit cao xuống bit thấp vì quá trình
       * rút gọn có thể tạo ra những bit mới bên dưới.
       */
      for (int i = 255; i >= 128; i--) begin
        if (remainder[i]) begin
          /*
           * Xóa thành phần x^i.
           */
          remainder[i] = 1'b0;

          /*
           * x^i mod P(x):
           *
           * x^(i-128) * (x^7 + x^2 + x + 1)
           */
          remainder[i-128+7] ^= 1'b1;
          remainder[i-128+2] ^= 1'b1;
          remainder[i-128+1] ^= 1'b1;
          remainder[i-128] ^= 1'b1;
        end
      end

      return remainder[127:0];
    end
  endfunction


  /*
   * Hàm tính kết quả GF(2^128) hoàn chỉnh.
   */
  function automatic logic [127:0] gf128_reference(input logic [127:0] operand_a,
                                                   input logic [127:0] operand_b);

    logic [255:0] raw_product;

    begin
      raw_product = carryless_multiply(operand_a, operand_b);
      return polynomial_reduction(raw_product);
    end
  endfunction


  /*
   * Task thực hiện một test case.
   */
  task automatic run_test(input logic [127:0] test_H, input logic [127:0] test_data,
                          input string test_name);

    logic [255:0] reference_product;
    logic [127:0] reference_result;

    begin
      test_count++;

      H_key   = test_H;
      data_in = test_data;

      /*
       * Đợi mạch tổ hợp ổn định.
       */
      #1;

      reference_product = carryless_multiply(test_H, test_data);
      reference_result  = polynomial_reduction(reference_product);

      $display("");
      $display("--------------------------------------------------");
      $display("Test %0d: %s", test_count, test_name);
      $display("H_key            = %032h", test_H);
      $display("data_in          = %032h", test_data);
      $display("Expected product = %064h", reference_product);
      $display("DUT product      = %064h", dut.X128_result);
      $display("Expected result  = %032h", reference_result);
      $display("DUT result       = %032h", data_out);

      /*
       * So sánh bằng !== để phát hiện cả giá trị X và Z.
       */
      if (dut.X128_result !== reference_product) begin
        error_count++;

        $display("[FAIL] Khối X128 cho kết quả không đúng.");
        $display("       Product XOR difference = %064h", dut.X128_result ^ reference_product);
      end else if (data_out !== reference_result) begin
        error_count++;

        $display("[FAIL] Khối ReductionBlock cho kết quả không đúng.");
        $display("       Result XOR difference = %032h", data_out ^ reference_result);
      end else begin
        $display("[PASS]");
      end
    end
  endtask


  initial begin
    H_key            = 128'd0;
    data_in          = 128'd0;
    test_count       = 0;
    error_count      = 0;
    expected_product = 256'd0;
    expected_result  = 128'd0;

    #5;

    /*
     * Các test case cơ bản.
     */
    run_test(128'h00000000000000000000000000000000, 128'h00000000000000000000000000000000, "0 x 0");

    run_test(128'h00000000000000000000000000000001, 128'h00000000000000000000000000000001, "1 x 1");

    run_test(128'h123456789ABCDEF00123456789ABCDEF, 128'h00000000000000000000000000000001, "A x 1");

    run_test(128'h00000000000000000000000000000001, 128'h123456789ABCDEF00123456789ABCDEF, "1 x B");

    run_test(128'h80000000000000000000000000000000, 128'h00000000000000000000000000000002,
             "Test reduction x^127 x x");

    run_test(128'hFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF, 128'hFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF,
             "All ones");

    run_test(128'h0123456789ABCDEFFEDCBA9876543210, 128'hFEDCBA98765432100123456789ABCDEF,
             "Fixed pattern");

    run_test(128'h66E94BD4EF8A2C3B884CFA59CA342B2E, 128'h0388DACE60B6A392F328C2B971B2FE78,
             "AES-GCM-like test data");

    /*
     * Test tính giao hoán:
     *
     * A x B phải bằng B x A.
     */
    run_test(128'h0123456789ABCDEFFEDCBA9876543210, 128'h00112233445566778899AABBCCDDEEFF,
             "Commutative test A x B");

    run_test(128'h00112233445566778899AABBCCDDEEFF, 128'h0123456789ABCDEFFEDCBA9876543210,
             "Commutative test B x A");

    /*
     * Test ngẫu nhiên.
     */
    for (int test_index = 0; test_index < 100; test_index++) begin
      logic [127:0] random_H;
      logic [127:0] random_data;

      random_H = {$urandom(), $urandom(), $urandom(), $urandom()};

      random_data = {$urandom(), $urandom(), $urandom(), $urandom()};

      run_test(random_H, random_data, $sformatf("Random test %0d", test_index));
    end

    $display("");
    $display("==================================================");
    $display("TEST SUMMARY");
    $display("Total tests : %0d", test_count);
    $display("Passed      : %0d", test_count - error_count);
    $display("Failed      : %0d", error_count);
    $display("==================================================");

    if (error_count == 0) begin
      $display("ALL TESTS PASSED");
    end else begin
      $error("%0d TEST(S) FAILED", error_count);
    end

    $finish;
  end

endmodule
