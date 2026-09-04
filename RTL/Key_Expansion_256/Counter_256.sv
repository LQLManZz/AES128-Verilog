module Counter_256 (
    input logic clk,
    input logic rst_n,
    input logic expansion_en,

    output logic rk0,
    output logic rk1,
    output logic sub_only,
    output logic expansion_finish,
    output logic [3:0] round_index
);
  assign rk0 = (round_index == 4'd0);
  assign rk1 = (round_index == 4'd1);
  assign sub_only = (round_index[0] == 1'b1);

  always_ff @(posedge clk, negedge rst_n) begin
    if (!rst_n) begin
      round_index      <= 4'd0;
      expansion_finish <= 1'b0;
    end else if (expansion_finish) begin
      if (!expansion_en) begin
        expansion_finish <= 1'b0;
        round_index      <= 4'd0;
      end
    end else if (expansion_en) begin
      if (round_index == 4'd12) begin
        round_index      <= 4'd0;
        expansion_finish <= 1'b1;
      end else begin
        round_index <= round_index + 1'b1;
      end
    end
  end
endmodule
