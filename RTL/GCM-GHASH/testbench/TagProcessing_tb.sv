`timescale 1ns / 1ps

module tb_TagProcessing;
  localparam logic [127:0] H_VALUE = 128'h66e94bd4ef8a2c3b884cfa59ca342b2e;
  localparam logic [127:0] E_VALUE = 128'h182ddde1144b3db22596f23cd218e24c;
  localparam logic [127:0] AAD_BLOCK_0 = 128'hfeedfacedeadbeeffeedfacedeadbeef;
  localparam logic [127:0] AAD_BLOCK_1 = 128'habaddad2000000000000000000000000;
  localparam logic [127:0] CT_BLOCK_0 = 128'h42831ec2217774244b7221b784d0d49c;
  localparam logic [127:0] CT_BLOCK_1 = 128'he3aa212f2c02a4e035c17e2329aca12e;
  localparam logic [127:0] LENGTH_BLOCK = {64'd256, 64'd256};

  logic clk;
  logic rst_n;
  logic finish_reset;
  logic mode;
  logic [127:0] AAD;
  logic [127:0] CT;
  logic [127:0] tag_ref;
  logic [127:0] H;
  logic [127:0] E;
  logic AAD_valid;
  logic CT_valid;
  logic H_valid;
  logic E_valid;
  logic tag_ref_valid;
  logic H_loaded;
  logic [127:0] tag;
  logic tag_valid;
  logic verify_pass;

  logic [127:0] expected_tag;
  int error_count;

  TagProcessing dut (
      .clk(clk),
      .rst_n(rst_n),
      .finish_reset(finish_reset),
      .mode(mode),
      .AAD(AAD),
      .CT(CT),
      .tag_ref(tag_ref),
      .H(H),
      .E(E),
      .AAD_valid(AAD_valid),
      .CT_valid(CT_valid),
      .H_valid(H_valid),
      .E_valid(E_valid),
      .tag_ref_valid(tag_ref_valid),
      .H_loaded(H_loaded),
      .tag(tag),
      .tag_valid(tag_valid),
      .verify_pass(verify_pass)
  );

  always #5 clk = ~clk;

  function automatic logic [255:0] carryless_multiply(input logic [127:0] operand_a,
                                                      input logic [127:0] operand_b);
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

  function automatic logic [127:0] polynomial_reduction(input logic [255:0] product);
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

  function automatic logic [127:0] gf128_reference(input logic [127:0] operand_a,
                                                   input logic [127:0] operand_b);
    begin
      gf128_reference = polynomial_reduction(carryless_multiply(operand_a, operand_b));
    end
  endfunction

  function automatic logic [127:0] calculate_tag;
    logic [127:0] accumulator;
    begin
      accumulator   = 128'h0;
      accumulator   = gf128_reference(accumulator ^ AAD_BLOCK_0, H_VALUE);
      accumulator   = gf128_reference(accumulator ^ AAD_BLOCK_1, H_VALUE);
      accumulator   = gf128_reference(accumulator ^ CT_BLOCK_0, H_VALUE);
      accumulator   = gf128_reference(accumulator ^ CT_BLOCK_1, H_VALUE);
      accumulator   = gf128_reference(accumulator ^ LENGTH_BLOCK, H_VALUE);
      calculate_tag = accumulator ^ E_VALUE;
    end
  endfunction

  task automatic clear_stream_inputs;
    begin
      AAD = 128'h0;
      CT = 128'h0;
      AAD_valid = 1'b0;
      CT_valid = 1'b0;
    end
  endtask

  task automatic load_h_and_e;
    begin
      @(negedge clk);
      H = H_VALUE;
      E = E_VALUE;
      H_valid = 1'b1;
      E_valid = 1'b1;
      @(posedge clk);
      #1;
      if (H_loaded !== 1'b1) begin
        error_count++;
        $display("[FAIL] H load handshake");
      end else begin
        $display("[PASS] H load handshake");
      end
      @(negedge clk);
      H_valid = 1'b0;
      E_valid = 1'b0;
    end
  endtask

  task automatic load_e_and_tag_reference(input logic [127:0] reference_value,
                                          input logic reference_valid);
    begin
      @(negedge clk);
      E = E_VALUE;
      E_valid = 1'b1;
      tag_ref = reference_value;
      tag_ref_valid = reference_valid;
      @(posedge clk);
      #1;
      @(negedge clk);
      E_valid = 1'b0;
      tag_ref_valid = 1'b0;
    end
  endtask

  task automatic send_aad(input logic [127:0] block_data);
    begin
      @(negedge clk);
      AAD = block_data;
      AAD_valid = 1'b1;
      CT = 128'h0;
      CT_valid = 1'b0;
      @(posedge clk);
      #1;
    end
  endtask

  task automatic send_ct(input logic [127:0] block_data);
    begin
      @(negedge clk);
      AAD = 128'h0;
      AAD_valid = 1'b0;
      CT = block_data;
      CT_valid = 1'b1;
      @(posedge clk);
      #1;
    end
  endtask

  task automatic send_message;
    begin
      send_aad(AAD_BLOCK_0);
      send_aad(AAD_BLOCK_1);
      send_ct(CT_BLOCK_0);
      send_ct(CT_BLOCK_1);
    end
  endtask

  task automatic check_final_result(input logic expected_tag_valid,
                                    input logic expected_verify_pass, input string test_name);
    begin
      @(negedge clk);
      clear_stream_inputs();
      #1;
      if (dut.length_block_valid !== 1'b1) begin
        error_count++;
        $display("[FAIL] %s length block pulse", test_name);
      end
      if (dut.length_block !== LENGTH_BLOCK) begin
        error_count++;
        $display("[FAIL] %s length block", test_name);
        $display("Expected length = %032h", LENGTH_BLOCK);
        $display("Actual   length = %032h", dut.length_block);
      end
      @(posedge clk);
      #1;
      if ((tag !== expected_tag) ||
          (tag_valid !== expected_tag_valid) ||
          (verify_pass !== expected_verify_pass) ||
          (dut.final_valid !== 1'b1)) begin
        error_count++;
        $display("[FAIL] %s final result", test_name);
        $display("Expected tag = %032h, tag_valid = %0b, verify_pass = %0b", expected_tag,
                 expected_tag_valid, expected_verify_pass);
        $display("Actual   tag = %032h, tag_valid = %0b, verify_pass = %0b", tag, tag_valid,
                 verify_pass);
      end else begin
        $display("[PASS] %s final result", test_name);
      end
      @(posedge clk);
      #1;
      if ((tag_valid !== 1'b0) || (verify_pass !== 1'b0)) begin
        error_count++;
        $display("[FAIL] %s output pulse width", test_name);
      end else begin
        $display("[PASS] %s output pulse width", test_name);
      end
    end
  endtask

  task automatic reset_message;
    begin
      @(negedge clk);
      finish_reset = 1'b1;
      clear_stream_inputs();
      #1;
      if ((dut.ghash_out !== 128'h0) || (dut.length_block !== 128'h0) || (H_loaded !== 1'b1)) begin
        error_count++;
        $display("[FAIL] Message reset");
      end else begin
        $display("[PASS] Message reset");
      end
      @(negedge clk);
      finish_reset = 1'b0;
    end
  endtask

  initial begin
    clk = 1'b0;
    rst_n = 1'b0;
    finish_reset = 1'b0;
    mode = 1'b0;
    tag_ref = 128'h0;
    H = 128'h0;
    E = 128'h0;
    H_valid = 1'b0;
    E_valid = 1'b0;
    tag_ref_valid = 1'b0;
    error_count = 0;
    clear_stream_inputs();
    expected_tag = calculate_tag();

    repeat (2) @(posedge clk);
    #1;
    if ((H_loaded !== 1'b0) || (tag_valid !== 1'b0) || (verify_pass !== 1'b0)) begin
      error_count++;
      $display("[FAIL] Global reset");
    end else begin
      $display("[PASS] Global reset");
    end

    @(negedge clk);
    rst_n = 1'b1;

    load_h_and_e();
    send_message();
    check_final_result(1'b1, 1'b0, "Encryption");

    reset_message();
    mode = 1'b1;
    load_e_and_tag_reference(expected_tag, 1'b1);
    send_message();
    check_final_result(1'b0, 1'b1, "Decryption valid tag");

    reset_message();
    load_e_and_tag_reference(expected_tag ^ 128'h1, 1'b1);
    send_message();
    check_final_result(1'b0, 1'b0, "Decryption invalid tag");

    if (error_count == 0) begin
      $display("ALL TAG PROCESSING TESTS PASSED");
    end else begin
      $fatal(1, "%0d TAG PROCESSING TEST(S) FAILED", error_count);
    end

    $finish;
  end
endmodule
