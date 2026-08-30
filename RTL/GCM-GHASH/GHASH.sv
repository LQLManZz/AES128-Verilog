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
      .H_reg(H_reg),
      .data_in(multiply_in),
      .data_out(multiply_out)
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
      ghash_finish <= length_block_valid;
    end
  end
endmodule
