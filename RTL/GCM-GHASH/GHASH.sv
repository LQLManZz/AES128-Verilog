module GHASH (
    input logic clk,
    input logic reset,
    input logic AAD_valid,
    input logic CT_valid,
    input logic length_block_valid,
    input logic [127:0] AAD,
    input logic [127:0] CT,
    input logic [127:0] length_block,
    input logic [127:0] H_reg,

    output logic ghash_finish,
    output logic [127:0] ghash_out
);
  logic ghash_en;
  logic [127:0] data_in;
  logic [127:0] multiply_in;
  logic [127:0] multiply_out;

  always_comb begin : DataInputMUX
    if (AAD_valid) begin
      data_in = AAD;
    end else if (CT_valid) begin
      data_in = CT;
    end else if (length_block_valid) begin
      data_in = length_block;
    end else begin
      data_in = 128'h0;
    end
  end

  assign ghash_en = (AAD_valid ^ CT_valid ^ length_block_valid) & !ghash_finish;

  assign multiply_in = ghash_out ^ data_in;

  GF128bitMultiply GFMultiply1 (
      .H_reg(H_reg),
      .data_in(multiply_in),
      .data_out(multiply_out)
  );

  always_ff @(posedge clk, posedge reset) begin : GHASHReg
    if (reset) begin
      ghash_out <= 128'h0;
    end else if (ghash_en) begin
      ghash_out <= multiply_out;
    end
  end

  always_ff @(posedge clk, posedge reset) begin : GHASHfinishReg
    if (reset) begin
      ghash_finish <= 1'b0;
    end else begin
      ghash_finish <= length_block_valid;
    end
  end
endmodule
