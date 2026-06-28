module KeyExpansion (
    input logic clk,
    input logic rst_n,
    input logic expansion_en,
    input logic [127:0] cipher_key,

    output logic [127:0] rkey,
    output logic expansion_finish
);
  logic [3:0] round_index;
  logic [127:0] current_key;
  logic [127:0] next_key;
  logic [31:0] after_GFunction;
  logic first_rkey;

  always_ff @(posedge clk, negedge rst_n) begin : RoundKeyReg
    if (!rst_n) begin
      rkey <= 128'h0;
    end else begin
      rkey <= current_key;
    end
  end
  always_comb begin : FirstRoundKeyMUX
    if (first_rkey) begin
      current_key = cipher_key;
    end else begin
      current_key = rkey;
    end
  end

  assign next_key[127:96] = after_GFunction ^ current_key[127:96];
  assign next_key[95:64]  = next_key[127:96] ^ current_key[95:64];
  assign next_key[63:32]  = next_key[95:64] ^ current_key[63:32];
  assign next_key[31:0]   = next_key[63:32] ^ current_key[31:0];

  KECounter cnt1 (
      .clk(clk),
      .rst_n(rst_n),
      .expansion_en(expansion_en),
      .round_index(round_index),
      .first_rkey(first_rkey),
      .expansion_finish(expansion_finish)
  );
  GFunction gfunc1 (
      .word_in(current_key[127:96]),
      .round_index(round_index),
      .word_out(after_GFunction)
  );
  KErkArray rkArr1 (
      .clk(clk),
      .expansion_en(expansion_en),
      .round_index(round_index),
      .cipher_key(cipher_key),
      .rkey(rkey)
  );
endmodule
