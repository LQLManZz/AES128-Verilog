module KeyExpansion (
    input logic clk,
    input logic rst_n,
    input logic expansion_en,
    input logic [127:0] cipher_key,

    output logic [127:0] round_key[0:10],
    output logic expansion_finish,
    output logic expansion_error
);
  logic [3:0] round_index;
  logic [127:0] current_key;
  logic [127:0] next_key;
  logic [31:0] after_GFunction;
  logic first_rkey;

  always_ff @(posedge clk, negedge rst_n) begin : RoundKeyReg
    if (!rst_n) begin
      integer i;
      for (i = 0; i <= 10; i++) begin
        round_key[i] <= 128'h0;
      end
    end else if (expansion_en) begin
      round_key[0] <= cipher_key;
      case (round_index)
        4'd0: round_key[1] <= next_key;
        4'd1: round_key[2] <= next_key;
        4'd2: round_key[3] <= next_key;
        4'd3: round_key[4] <= next_key;
        4'd4: round_key[5] <= next_key;
        4'd5: round_key[6] <= next_key;
        4'd6: round_key[7] <= next_key;
        4'd7: round_key[8] <= next_key;
        4'd8: round_key[9] <= next_key;
        4'd9: round_key[10] <= next_key;
        default: ;
      endcase
    end
  end
  always_comb begin : FirstRoundKeyMUX
    if (first_rkey) begin
      current_key = cipher_key;
    end else begin
      case (round_index)
        4'd0: current_key = round_key[0];
        4'd1: current_key = round_key[1];
        4'd2: current_key = round_key[2];
        4'd3: current_key = round_key[3];
        4'd4: current_key = round_key[4];
        4'd5: current_key = round_key[5];
        4'd6: current_key = round_key[6];
        4'd7: current_key = round_key[7];
        4'd8: current_key = round_key[8];
        4'd9: current_key = round_key[9];
        default: current_key = 128'h0;
      endcase
    end
  end

  assign expansion_error = (expansion_en == 1'b0) & (expansion_finish == 1'b0) & (round_index != 4'd0);

  assign next_key[127:96] = after_GFunction ^ current_key[127:96];
  assign next_key[95:64] = next_key[127:96] ^ current_key[95:64];
  assign next_key[63:32] = next_key[95:64] ^ current_key[63:32];
  assign next_key[31:0] = next_key[63:32] ^ current_key[31:0];

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
