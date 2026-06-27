module KErkArray (
    input logic clk,
    input logic rst_n,
    input logic expansion_en,
    input logic [3:0] round_index,
    input logic [127:0] cipher_key,
    input logic [127:0] rkey,

    output logic [127:0] round_key
);
  logic [127:0] rkArray[0:10];
  integer i;

  always_ff @(posedge clk, negedge rst_n) begin : WriteReg
    if (!rst_n) begin
      for (i = 0; i <= 10; i++) begin
        rkArray[i] <= 128'h0;
      end
    end else if (expansion_en) begin
      rkArray[round_index] <= rkey;
    end
  end

  always_comb begin : ReadLogic
    if (round_index <= 4'd10) begin
      round_key = rkArray[round_index];
    end else begin
      round_key = 128'h0;
    end
  end
endmodule
