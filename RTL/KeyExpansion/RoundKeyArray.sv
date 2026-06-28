module RoundKeyArray (
    input logic clk,
    input logic expansion_en,
    input logic [3:0] round_index,
    input logic [3:0] read_round,
    input logic [127:0] cipher_key,
    input logic [127:0] rkey,

    output logic [127:0] round_key
);
  logic [127:0] rkArray[0:10];
  integer i;

  always_ff @(posedge clk) begin : WriteReg
    if (expansion_en) begin
      rkArray[round_index] <= rkey;
    end
  end

  always_comb begin : ReadLogic
    if (round_index <= 4'd10) begin
      round_key = rkArray[read_round];
    end else begin
      round_key = 128'h0;
    end
  end
endmodule
