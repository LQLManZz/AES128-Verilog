module LengthBlockCounter (
    input logic clk,
    input logic finish_reset,
    input logic AAD_valid,
    input logic CT_valid,

    output logic         length_block_valid,
    output logic [127:0] length_block
);
  logic [60:0] AAD_cnt;
  logic [60:0] CT_cnt;
  logic        condition;

  assign length_block = {AAD_cnt, 3'd0, CT_cnt, 3'd0};
  assign condition = !(AAD_valid && CT_valid && (length_block == 128'h0));

  always_ff @(posedge clk, posedge finish_reset) begin : AADCounter
    if (finish_reset) begin
      AAD_cnt <= 61'd0;
    end else if (AAD_valid) begin
      AAD_cnt <= AAD_cnt + 61'd16;
    end
  end

  always_ff @(posedge clk, posedge finish_reset) begin : CTCounter
    if (finish_reset) begin
      CT_cnt <= 61'd0;
    end else if (CT_valid) begin
      CT_cnt <= CT_cnt + 61'd16;
    end
  end

  always_ff @(posedge clk, posedge finish_reset) begin : LengthBlockValidReg
    if (finish_reset) begin
      length_block_valid <= 1'b0;
    end else begin
      length_block_valid <= condition;
    end
  end
endmodule
