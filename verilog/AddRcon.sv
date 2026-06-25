module AddRcon (
    input logic [31:0] word_in,
    input logic [ 3:0] round_index,

    output logic [31:0] word_out
);
  logic [31:0] rcon;
  always_comb begin : RconSelector
    case (round_index)
      4'd0: rcon = 32'h01000000;
      4'd1: rcon = 32'h02000000;
      4'd2: rcon = 32'h04000000;
      4'd3: rcon = 32'h08000000;
      4'd4: rcon = 32'h10000000;
      4'd5: rcon = 32'h20000000;
      4'd6: rcon = 32'h40000000;
      4'd7: rcon = 32'h80000000;
      4'd8: rcon = 32'h1b000000;
      4'd9: rcon = 32'h36000000;
      default: rcon = 32'h01000000;
    endcase
  end

  assign word_out = word_in ^ rcon;
endmodule
