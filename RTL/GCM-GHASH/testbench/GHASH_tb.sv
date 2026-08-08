`timescale 1ns / 1ps

module tb_GHASH;
  logic clk;
  logic reset;
  logic ghash_en;
  logic [127:0] AAD;
  logic AAD_valid;
  logic [127:0] CT;
  logic CT_valid;
  logic [127:0] length_block;
  logic length_block_valid;
  logic [127:0] H_reg;
  logic [127:0] ghash_out;

  logic [127:0] expected_ghash;
  int error_count;

  GHASH dut (
      .clk(clk),
      .reset(reset),
      .ghash_en(ghash_en),
      .AAD(AAD),
      .AAD_valid(AAD_valid),
      .CT(CT),
      .CT_valid(CT_valid),
      .length_block(length_block),
      .length_block_valid(length_block_valid),
      .H_reg(H_reg),
      .ghash_out(ghash_out)
  );

  always #5 clk = ~clk;

  function automatic logic [255:0] carryless_multiply(
      input logic [127:0] operand_a,
      input logic [127:0] operand_b
  );
    logic [255:0] product;
    logic [255:0] extended_a;
    begin
      product = 256'h0;
      extended_a = {128'h0, operand_a};
      for (int i = 0; i < 128; i++) begin
        if (operand_b[i]) begin
          product = product ^ (extended_a << i);
        end
      end
      carryless_multiply = product;
    end
  endfunction

  function automatic logic [127:0] polynomial_reduction(
      input logic [255:0] product
  );
    logic [255:0] remainder;
    begin
      remainder = product;
      for (int i = 255; i >= 128; i--) begin
        if (remainder[i]) begin
          remainder[i] = 1'b0;
          remainder[i-121] = remainder[i-121] ^ 1'b1;
          remainder[i-126] = remainder[i-126] ^ 1'b1;
          remainder[i-127] = remainder[i-127] ^ 1'b1;
          remainder[i-128] = remainder[i-128] ^ 1'b1;
        end
      end
      polynomial_reduction = remainder[127:0];
    end
  endfunction

  function automatic logic [127:0] gf128_reference(
      input logic [127:0] operand_a,
      input logic [127:0] operand_b
  );
    begin
      gf128_reference = polynomial_reduction(carryless_multiply(operand_a, operand_b));
    end
  endfunction

  task automatic clear_inputs;
    begin
      AAD = 128'h0;
      AAD_valid = 1'b0;
      CT = 128'h0;
      CT_valid = 1'b0;
      length_block = 128'h0;
      length_block_valid = 1'b0;
      ghash_en = 1'b0;
    end
  endtask

  task automatic check_ghash(input string test_name);
    begin
      if (ghash_out !== expected_ghash) begin
        error_count++;
        $display("[FAIL] %s", test_name);
        $display("Expected GHASH = %032h", expected_ghash);
        $display("Actual   GHASH = %032h", ghash_out);
      end else begin
        $display("[PASS] %s", test_name);
      end
    end
  endtask

  task automatic apply_block(
      input logic [1:0] block_type,
      input logic [127:0] block_data,
      input string test_name
  );
    begin
      @(negedge clk);
      clear_inputs();
      ghash_en = 1'b1;
      case (block_type)
        2'd0: begin
          AAD = block_data;
          AAD_valid = 1'b1;
        end
        2'd1: begin
          CT = block_data;
          CT_valid = 1'b1;
        end
        default: begin
          length_block = block_data;
          length_block_valid = 1'b1;
        end
      endcase
      expected_ghash = gf128_reference(expected_ghash ^ block_data, H_reg);
      @(posedge clk);
      #1;
      check_ghash(test_name);
    end
  endtask

  initial begin
    clk = 1'b0;
    reset = 1'b0;
    H_reg = 128'h66e94bd4ef8a2c3b884cfa59ca342b2e;
    expected_ghash = 128'h0;
    error_count = 0;
    clear_inputs();

    repeat (2) @(posedge clk);
    #1;
    check_ghash("Reset value");

    @(negedge clk);
    reset = 1'b1;

    apply_block(2'd0, 128'hfeedfacedeadbeeffeedfacedeadbeef, "First AAD block");
    apply_block(2'd0, 128'habaddad2000000000000000000000000, "Second AAD block");
    apply_block(2'd1, 128'h42831ec2217774244b7221b784d0d49c, "First CT block");
    apply_block(2'd1, 128'he3aa212f2c02a4e035c17e2329aca12e, "Second CT block");
    apply_block(2'd2, {64'd256, 64'd256}, "Length block");

    @(negedge clk);
    clear_inputs();
    @(posedge clk);
    #1;
    check_ghash("Hold when disabled");

    @(negedge clk);
    AAD = 128'h0123456789abcdeffedcba9876543210;
    CT = 128'hffffffffffffffffffffffffffffffff;
    AAD_valid = 1'b1;
    CT_valid = 1'b1;
    ghash_en = 1'b1;
    expected_ghash = gf128_reference(expected_ghash ^ AAD, H_reg);
    @(posedge clk);
    #1;
    check_ghash("AAD priority over CT");

    @(negedge clk);
    clear_inputs();
    AAD = 128'hffffffffffffffffffffffffffffffff;
    AAD_valid = 1'b1;
    ghash_en = 1'b0;
    @(posedge clk);
    #1;
    check_ghash("Valid input ignored when disabled");

    @(negedge clk);
    reset = 1'b0;
    #1;
    expected_ghash = 128'h0;
    check_ghash("Asynchronous reset");

    if (error_count == 0) begin
      $display("ALL GHASH TESTS PASSED");
    end else begin
      $fatal(1, "%0d GHASH TEST(S) FAILED", error_count);
    end

    $finish;
  end
endmodule
