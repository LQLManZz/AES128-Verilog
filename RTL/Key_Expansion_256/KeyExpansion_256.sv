module KeyExpansion_256 (
    input logic clk,
    input logic rst_n,
    input logic expansion_en,
    input logic [255:0] cipher_key,

    output logic [127:0] round_key[0:14],
    output logic expansion_finish
);
  logic [3:0] round_index;
  logic [127:0] current_key;
  logic [127:0] next_key;
  logic [31:0] after_GFunction;
  logic [31:0] sub_onlyMUX;
  logic rk0;
  logic rk1;
  logic sub_only;

  always_ff @(posedge clk, negedge rst_n) begin : RoundKeyReg
    if (!rst_n) begin
      integer i;
      for (i = 0; i <= 14; i++) begin
        round_key[i] <= 128'h0;
      end
    end else if (expansion_en) begin
      round_key[0] <= cipher_key[255:128];
      round_key[1] <= cipher_key[127:0];
      case (round_index)
        4'd0: round_key[2] <= next_key;
        4'd1: round_key[3] <= next_key;
        4'd2: round_key[4] <= next_key;
        4'd3: round_key[5] <= next_key;
        4'd4: round_key[6] <= next_key;
        4'd5: round_key[7] <= next_key;
        4'd6: round_key[8] <= next_key;
        4'd7: round_key[9] <= next_key;
        4'd8: round_key[10] <= next_key;
        4'd9: round_key[11] <= next_key;
        4'd10: round_key[12] <= next_key;
        4'd11: round_key[13] <= next_key;
        4'd12: round_key[14] <= next_key;
        default: ;
      endcase
    end
  end
  always_comb begin : FirstRoundKeyMUX
    if (rk0) begin
      current_key = cipher_key[255:128];
    end else if (rk1) begin
      current_key = cipher_key[127:0];
    end else begin
      case (round_index)
        4'd2: current_key = round_key[2];
        4'd3: current_key = round_key[3];
        4'd4: current_key = round_key[4];
        4'd5: current_key = round_key[5];
        4'd6: current_key = round_key[6];
        4'd7: current_key = round_key[7];
        4'd8: current_key = round_key[8];
        4'd9: current_key = round_key[9];
        4'd10: current_key = round_key[10];
        4'd11: current_key = round_key[11];
        4'd12: current_key = round_key[12];
        default: current_key = 128'h0;
      endcase
    end
  end

  always_comb begin : WordGenerator
    if (sub_only) begin
      next_key[127:96] = sub_onlyMUX ^ current_key[127:96];
    end else begin
      next_key[127:96] = after_GFunction ^ current_key[127:96];
    end
    next_key[95:64] = next_key[127:96] ^ current_key[95:64];
    next_key[63:32] = next_key[95:64] ^ current_key[63:32];
    next_key[31:0]  = next_key[63:32] ^ current_key[31:0];
  end

  SubWord sw1 (
      .word_in (current_key[31:0]),
      .word_out(sub_onlyMUX)
  );
  Counter_256 cnt1 (
      .clk(clk),
      .rst_n(rst_n),
      .expansion_en(expansion_en),
      .round_index(round_index),
      .rk0(rk0),
      .rk1(rk1),
      .sub_only(sub_only),
      .expansion_finish(expansion_finish)
  );
  GFunction_256 gfunc1 (
      .word_in(current_key[31:0]),
      .round_index(round_index),
      .word_out(after_GFunction)
  );
endmodule
