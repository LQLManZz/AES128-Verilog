module Counter (
    input logic clk,
    input logic rst_n,
    input logic expansion_en,

    output logic first_rkey,
    output logic expansion_finish,
    output logic [3:0] round_index
);
  assign first_rkey = (round_index == 4'd0);
  // assign expansion_finish = (round_index == 4'd9);

  always_ff @(posedge clk, negedge rst_n) begin : CounterFF
    if (!rst_n) begin
      round_index      <= 4'd0;
      expansion_finish <= 1'b0;
    end else begin
      if (expansion_en) begin
        if (round_index == 4'd9) begin
          round_index      <= 4'd0;
          expansion_finish <= 1'b1;
        end else begin
          round_index <= round_index + 1'b1;
          expansion_finish <= 1'b0;
        end
      end else begin
        round_index <= round_index;
        expansion_finish <= expansion_finish;
      end
    end
  end
endmodule
