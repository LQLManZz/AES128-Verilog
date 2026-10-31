module GHASH (
    input logic         clk,
    input logic         finish_reset,
    input logic         load_AAD,
    input logic         load_CT,
    input logic         length_block_valid,
    input logic [127:0] AAD,
    input logic [127:0] CT,
    input logic [127:0] length_block,
    input logic [127:0] H_reg,

    output logic         ghash_finish,
    output logic [127:0] ghash_out
);
  logic         ghash_en;
  logic [127:0] data_in;
  logic [127:0] multiply_in;
  logic [127:0] multiply_out;
  logic [127:0] H_nist;
  logic [127:0] multiply_in_nist;
  logic [127:0] multiply_out_nist;

  genvar i;
  generate
    for (i = 0; i < 128; i++) begin : BitReverse
      assign H_nist[i]           = H_reg[127-i];
      assign multiply_in_nist[i] = multiply_in[127-i];
      assign multiply_out[i]     = multiply_out_nist[127-i];
    end
  endgenerate

  always_comb begin : DataInputMUX
    if (load_AAD) begin
      data_in = AAD;
    end else if (load_CT) begin
      data_in = CT;
    end else if (length_block_valid) begin
      data_in = length_block;
    end else begin
      data_in = 128'h0;
    end
  end

  assign ghash_en = (load_AAD ^ load_CT ^ length_block_valid) & !ghash_finish;
  assign multiply_in = ghash_out ^ data_in;

  GF128bitMultiply GFMultiply1 (
      .H_reg(H_nist),
      .data_in(multiply_in_nist),
      .data_out(multiply_out_nist)
  );

  always_ff @(posedge clk, posedge finish_reset) begin : GHASHReg
    if (finish_reset) begin
      ghash_out <= 128'h0;
    end else if (ghash_en) begin
      ghash_out <= multiply_out;
    end
  end

  always_ff @(posedge clk, posedge finish_reset) begin : GHASHfinishReg
    if (finish_reset) begin
      ghash_finish <= 1'b0;
    end else begin
      if (length_block_valid) begin
        ghash_finish <= 1'b1;
      end
    end
  end
endmodule
