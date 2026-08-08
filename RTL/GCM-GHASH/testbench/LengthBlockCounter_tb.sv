`timescale 1ns / 1ps

module tb_LengthBlockCTR;
  logic clk;
  logic reset;
  logic AAD_valid;
  logic CT_valid;
  logic [127:0] length_block;
  logic length_block_valid;

  int error_count;

  LengthBlockCTR dut (
      .clk(clk),
      .reset(reset),
      .AAD_valid(AAD_valid),
      .CT_valid(CT_valid),
      .length_block(length_block),
      .length_block_valid(length_block_valid)
  );

  always #5 clk = ~clk;

  task automatic check_outputs(
      input logic [127:0] expected_length,
      input logic expected_valid,
      input string test_name
  );
    begin
      if ((length_block !== expected_length) ||
          (length_block_valid !== expected_valid)) begin
        error_count++;
        $display("[FAIL] %s", test_name);
        $display("Expected length = %032h, valid = %0b", expected_length, expected_valid);
        $display("Actual   length = %032h, valid = %0b", length_block, length_block_valid);
      end else begin
        $display("[PASS] %s", test_name);
      end
    end
  endtask

  task automatic apply_reset;
    begin
      @(negedge clk);
      reset = 1'b0;
      AAD_valid = 1'b0;
      CT_valid = 1'b0;
      #1;
      check_outputs(128'h0, 1'b0, "Reset asserted");
      @(negedge clk);
      reset = 1'b1;
    end
  endtask

  task automatic send_aad_blocks(input int block_count);
    begin
      for (int i = 0; i < block_count; i++) begin
        @(negedge clk);
        AAD_valid = 1'b1;
        CT_valid = 1'b0;
        @(posedge clk);
        #1;
      end
    end
  endtask

  task automatic send_ct_blocks(input int block_count);
    begin
      for (int i = 0; i < block_count; i++) begin
        @(negedge clk);
        AAD_valid = 1'b0;
        CT_valid = 1'b1;
        @(posedge clk);
        #1;
      end
    end
  endtask

  task automatic finish_message(
      input logic [127:0] expected_length,
      input string test_name
  );
    begin
      @(negedge clk);
      AAD_valid = 1'b0;
      CT_valid = 1'b0;
      #1;
      check_outputs(expected_length, 1'b1, $sformatf("%s valid pulse", test_name));
      @(posedge clk);
      #1;
      check_outputs(expected_length, 1'b0, $sformatf("%s valid cleared", test_name));
      @(posedge clk);
      #1;
      check_outputs(expected_length, 1'b0, $sformatf("%s counter held", test_name));
    end
  endtask

  initial begin
    clk = 1'b0;
    reset = 1'b0;
    AAD_valid = 1'b0;
    CT_valid = 1'b0;
    error_count = 0;

    repeat (2) @(posedge clk);
    #1;
    check_outputs(128'h0, 1'b0, "Initial reset");

    @(negedge clk);
    reset = 1'b1;

    send_aad_blocks(1);
    check_outputs({64'd128, 64'd0}, 1'b0, "One AAD block");
    finish_message({64'd128, 64'd0}, "AAD-only message");

    apply_reset();
    send_ct_blocks(3);
    check_outputs({64'd0, 64'd384}, 1'b0, "Three CT blocks");
    finish_message({64'd0, 64'd384}, "CT-only message");

    apply_reset();
    send_aad_blocks(2);
    send_ct_blocks(4);
    check_outputs({64'd256, 64'd512}, 1'b0, "Mixed AAD and CT blocks");
    finish_message({64'd256, 64'd512}, "Mixed message");

    apply_reset();
    @(negedge clk);
    AAD_valid = 1'b1;
    CT_valid = 1'b1;
    @(posedge clk);
    #1;
    check_outputs({64'd128, 64'd128}, 1'b0, "Simultaneous AAD and CT valid");
    finish_message({64'd128, 64'd128}, "Simultaneous-valid message");

    if (error_count == 0) begin
      $display("ALL LENGTH BLOCK COUNTER TESTS PASSED");
    end else begin
      $fatal(1, "%0d LENGTH BLOCK COUNTER TEST(S) FAILED", error_count);
    end

    $finish;
  end
endmodule
