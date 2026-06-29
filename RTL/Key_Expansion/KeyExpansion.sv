module KeyExpansion (
    input logic clk,
    input logic rst_n,
    input logic expansion_en,
    input logic [127:0] cipher_key,

    output logic [127:0] round_key[0:10],
    output logic expansion_finish
);
  logic [3:0] round_index;
  logic [127:0] current_key;
  logic [127:0] next_key;
  logic [31:0] after_GFunction;
  logic first_rkey;

  assign round_key[0] = cipher_key;

  always_ff @(posedge clk, negedge rst_n) begin : RoundKeyReg
    if (!rst_n) begin
      round_key[round_index+1] <= 128'h0;
    end else begin
      round_key[round_index+1] <= next_key;
    end
  end
  always_comb begin : FirstRoundKeyMUX
    if (first_rkey) begin
      current_key = cipher_key;
    end else begin
      current_key = round_key[round_index];
    end
  end

  assign next_key[127:96] = after_GFunction ^ current_key[127:96];
  assign next_key[95:64]  = next_key[127:96] ^ current_key[95:64];
  assign next_key[63:32]  = next_key[95:64] ^ current_key[63:32];
  assign next_key[31:0]   = next_key[63:32] ^ current_key[31:0];

  Counter cnt1 (
      .clk(clk),
      .rst_n(rst_n),
      .expansion_en(expansion_en),
      .round_index(round_index),
      .first_rkey(first_rkey),
      .expansion_finish(expansion_finish)
  );
  GFunction gfunc1 (
      .word_in(current_key[31:0]),
      .round_index(round_index),
      .word_out(after_GFunction)
  );
endmodule
