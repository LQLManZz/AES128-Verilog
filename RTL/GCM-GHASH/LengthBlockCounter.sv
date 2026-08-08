module LengthBlockCTR (
    input logic clk,
    input logic reset,
    input logic AAD_valid,
    input logic CT_valid,

    output logic [127:0] length_block,
    output logic length_block_valid
);
  logic [60:0] AAD_cnt;
  logic [60:0] CT_cnt;
  logic end_detect;
  logic end_detect_reg;

  assign length_block = {AAD_cnt, 3'd0, CT_cnt, 3'd0};
  assign end_detect = !AAD_valid && !CT_valid && (length_block != 128'h0);
  assign length_block_valid = end_detect && !end_detect_reg;

  always_ff @(posedge clk, negedge reset) begin : AADCounter
    if (!reset) begin
      AAD_cnt <= 61'd0;
    end else if (AAD_valid) begin
      AAD_cnt <= AAD_cnt + 61'd16;
    end
  end

  always_ff @(posedge clk, negedge reset) begin : CTCounter
    if (!reset) begin
      CT_cnt <= 61'd0;
    end else if (CT_valid) begin
      CT_cnt <= CT_cnt + 61'd16;
    end
  end

  always_ff @(posedge clk, negedge reset) begin : EndDetectReg
    if (!reset) begin
      end_detect_reg <= 1'b0;
    end else begin
      end_detect_reg <= end_detect;
    end
  end
endmodule
