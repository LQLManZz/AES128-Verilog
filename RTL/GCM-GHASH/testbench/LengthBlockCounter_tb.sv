`timescale 1ns / 1ps

module LengthBlockCounter_tb;
  logic         clk;
  logic         reset;
  logic         AAD_valid;
  logic         CT_valid;
  logic [127:0] length_block;
  logic         length_block_valid;

  int           error_count;

  LengthBlockCounter dut (
      .clk               (clk),
      .reset             (reset),
      .AAD_valid         (AAD_valid),
      .CT_valid          (CT_valid),
      .length_block_valid(length_block_valid),
      .length_block      (length_block)
  );

  initial begin
    $dumpfile("LengthBlockCounter_tb.vcd");
    $dumpvars(0, LengthBlockCounter_tb);
  end

  always #5 clk = ~clk;

  task automatic check_outputs(
      input logic [127:0] expected_length,
      input logic         expected_valid,
      input string        test_name
  );
    begin
      if ((length_block !== expected_length) || (length_block_valid !== expected_valid)) begin
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
      reset     = 1'b1;
      AAD_valid = 1'b0;
      CT_valid  = 1'b0;
      #1;
      check_outputs(128'h0, 1'b0, "Async reset asserted");
      @(negedge clk);
      reset = 1'b0;
    end
  endtask

  task automatic send_aad_blocks(input int block_count);
    begin
      for (int i = 0; i < block_count; i++) begin
        @(negedge clk);
        AAD_valid = 1'b1;
        CT_valid  = 1'b0;
        @(posedge clk);
        #1;
      end
      @(negedge clk);
      AAD_valid = 1'b0;
      CT_valid  = 1'b0;
    end
  endtask

  task automatic send_ct_blocks(input int block_count);
    begin
      for (int i = 0; i < block_count; i++) begin
        @(negedge clk);
        AAD_valid = 1'b0;
        CT_valid  = 1'b1;
        @(posedge clk);
        #1;
      end
      @(negedge clk);
      AAD_valid = 1'b0;
      CT_valid  = 1'b0;
    end
  endtask

  initial begin
    clk         = 1'b0;
    reset       = 1'b1;
    AAD_valid   = 1'b0;
    CT_valid    = 1'b0;
    error_count = 0;

    // 1. Initial Reset Check
    repeat (2) @(posedge clk);
    #1;
    check_outputs(128'h0, 1'b0, "Initial reset state");

    @(negedge clk);
    reset = 1'b0;

    // 2. AAD only message (1 block = 128 bits)
    send_aad_blocks(1);
    #1;
    check_outputs({64'd128, 64'd0}, 1'b1, "1 AAD block (128 bits AAD, 0 bit CT)");

    // 3. Reset and CT only message (3 blocks = 384 bits)
    apply_reset();
    send_ct_blocks(3);
    #1;
    check_outputs({64'd0, 64'd384}, 1'b1, "3 CT blocks (0 bit AAD, 384 bits CT)");

    // 4. Mixed AAD and CT blocks (2 AAD = 256 bits, 4 CT = 512 bits)
    apply_reset();
    send_aad_blocks(2);
    send_ct_blocks(4);
    #1;
    check_outputs({64'd256, 64'd512}, 1'b1, "Mixed message (256 bits AAD, 512 bits CT)");

    // 5. Simultaneous AAD and CT valid
    apply_reset();
    @(negedge clk);
    AAD_valid = 1'b1;
    CT_valid  = 1'b1;
    @(posedge clk);
    #1;
    @(negedge clk);
    AAD_valid = 1'b0;
    CT_valid  = 1'b0;
    #1;
    check_outputs({64'd128, 64'd128}, 1'b1, "Simultaneous AAD & CT block (128/128 bits)");

    $display("");
    $display("==================================================");
    $display("TEST SUMMARY: LengthBlockCounter");
    $display("Total errors : %0d", error_count);
    $display("==================================================");

    if (error_count == 0) begin
      $display("ALL LENGTH BLOCK COUNTER TESTS PASSED");
    end else begin
      $fatal(1, "%0d LENGTH BLOCK COUNTER TEST(S) FAILED", error_count);
    end

    $finish;
  end
endmodule
