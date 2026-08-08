module GHASH (
    input logic clk,
    input logic reset,
    input logic ghash_en,
    input logic [127:0] AAD,
    input logic AAD_valid,
    input logic [127:0] CT,
    input logic CT_valid,
    input logic [127:0] length_block,
    input logic length_block_valid,
    input logic [127:0] H_reg,

    output logic [127:0] ghash_out
);
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

  assign multiply_in = ghash_out ^ data_in;

  GF128bitMultiply GFMultiply (
      .H_reg(H_reg),
      .data_in(multiply_in),
      .data_out(multiply_out)
  );

  always_ff @(posedge clk, negedge reset) begin : GHASHReg
    if (!reset) begin
      ghash_out <= 128'h0;
    end else if (ghash_en) begin
      ghash_out <= multiply_out;
    end
  end
endmodule
