`timescale 1ns / 1ps

module GHASH_tb;
  logic         clk;
  logic         reset;
  logic         AAD_valid;
  logic         CT_valid;
  logic         length_block_valid;
  logic [127:0] AAD;
  logic [127:0] CT;
  logic [127:0] length_block;
  logic [127:0] H_reg;
  logic         ghash_finish;
  logic [127:0] ghash_out;

  logic [127:0] expected_ghash;
  int           error_count;

  GHASH dut (
      .clk               (clk),
      .reset             (reset),
      .AAD_valid         (AAD_valid),
      .CT_valid          (CT_valid),
      .length_block_valid(length_block_valid),
      .AAD               (AAD),
      .CT                (CT),
      .length_block      (length_block),
      .H_reg             (H_reg),
      .ghash_finish      (ghash_finish),
      .ghash_out         (ghash_out)
  );

  initial begin
    $dumpfile("GHASH_tb.vcd");
    $dumpvars(0, GHASH_tb);
  end

  always #5 clk = ~clk;

  function automatic logic [255:0] carryless_multiply(
      input logic [127:0] operand_a,
      input logic [127:0] operand_b
  );
    logic [255:0] product;
    logic [255:0] extended_a;
    begin
      product    = 256'h0;
      extended_a = {128'h0, operand_a};
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
          remainder[i-128+7] ^= 1'b1;
          remainder[i-128+2] ^= 1'b1;
          remainder[i-128+1] ^= 1'b1;
          remainder[i-128]   ^= 1'b1;
        end
      end
      return remainder[127:0];
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
      AAD                = 128'h0;
      AAD_valid          = 1'b0;
      CT                 = 128'h0;
      CT_valid           = 1'b0;
      length_block       = 128'h0;
      length_block_valid = 1'b0;
    end
  endtask

  task automatic check_ghash(
      input string test_name,
      input logic  expected_finish = 1'b0
  );
    begin
      if (ghash_out !== expected_ghash || ghash_finish !== expected_finish) begin
        error_count++;
        $display("[FAIL] %s", test_name);
        $display("Expected GHASH  = %032h, finish = %0b", expected_ghash, expected_finish);
        $display("Actual   GHASH  = %032h, finish = %0b", ghash_out, ghash_finish);
      end else begin
        $display("[PASS] %s", test_name);
      end
    end
  endtask

  task automatic apply_block(
      input logic [  1:0] block_type,
      input logic [127:0] block_data,
      input string        test_name
  );
    begin
      @(negedge clk);
      clear_inputs();
      case (block_type)
        2'd0: begin
          AAD       = block_data;
          AAD_valid = 1'b1;
        end
        2'd1: begin
          CT       = block_data;
          CT_valid = 1'b1;
        end
        default: begin
          length_block       = block_data;
          length_block_valid = 1'b1;
        end
      endcase
      expected_ghash = gf128_reference(expected_ghash ^ block_data, H_reg);
      @(posedge clk);
      #1;
      check_ghash(test_name, (block_type == 2'd2) ? 1'b1 : 1'b0);
    end
  endtask

  task automatic apply_reset;
    begin
      @(negedge clk);
      reset = 1'b1;
      clear_inputs();
      #1;
      expected_ghash = 128'h0;
      check_ghash("Asynchronous reset check", 1'b0);
      @(negedge clk);
      reset = 1'b0;
    end
  endtask

  initial begin
    clk            = 1'b0;
    reset          = 1'b1;
    H_reg          = 128'h66e94bd4ef8a2c3b884cfa59ca342b2e;
    expected_ghash = 128'h0;
    error_count    = 0;
    clear_inputs();

    // 1. Check reset state
    repeat (2) @(posedge clk);
    #1;
    check_ghash("Initial reset state", 1'b0);

    @(negedge clk);
    reset = 1'b0;

    // 2. Stream blocks through GHASH
    apply_block(2'd0, 128'hfeedfacedeadbeeffeedfacedeadbeef, "First AAD block");
    apply_block(2'd0, 128'habaddad2000000000000000000000000, "Second AAD block");
    apply_block(2'd1, 128'h42831ec2217774244b7221b784d0d49c, "First CT block");
    apply_block(2'd1, 128'he3aa212f2c02a4e035c17e2329aca12e, "Second CT block");
    apply_block(2'd2, {64'd256, 64'd256}, "Length block (finish asserted)");

    // 3. Test holding value after finish
    @(negedge clk);
    clear_inputs();
    @(posedge clk);
    #1;
    check_ghash("Hold output when ghash_finish is 1", 1'b0);

    // 4. Test async reset
    apply_reset();

    // 5. Test second message after reset
    apply_block(2'd0, 128'h0123456789abcdeffedcba9876543210, "Post-reset AAD block");
    apply_block(2'd1, 128'hfedcba98765432100123456789abcdef, "Post-reset CT block");
    apply_block(2'd2, {64'd128, 64'd128}, "Post-reset Length block");

    $display("");
    $display("==================================================");
    $display("TEST SUMMARY: GHASH");
    $display("Total errors : %0d", error_count);
    $display("==================================================");

    if (error_count == 0) begin
      $display("ALL GHASH TESTS PASSED");
    end else begin
      $fatal(1, "%0d GHASH TEST(S) FAILED", error_count);
    end

    $finish;
  end
endmodule
