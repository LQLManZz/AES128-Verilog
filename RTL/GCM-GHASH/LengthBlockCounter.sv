module LengthBlockCounter (
    input logic clk,
    input logic finish_reset,
    input logic load_AAD,
    input logic load_CT,
    input logic CT_last,

    output logic         length_block_valid,
    output logic [127:0] length_block
);
  logic [60:0] AAD_cnt;
  logic [60:0] CT_cnt;

  assign length_block = {AAD_cnt, 3'd0, CT_cnt, 3'd0};

  always_ff @(posedge clk, posedge finish_reset) begin : AADCounter
    if (finish_reset) begin
      AAD_cnt <= 61'd0;
    end else if (load_AAD) begin
      AAD_cnt <= AAD_cnt + 61'd16;
    end
  end

  always_ff @(posedge clk, posedge finish_reset) begin : CTCounter
    if (finish_reset) begin
      CT_cnt <= 61'd0;
    end else if (load_CT) begin
      CT_cnt <= CT_cnt + 61'd16;
    end
  end

  always_ff @(posedge clk, posedge finish_reset) begin : LengthBlockValidReg
    if (finish_reset) begin
      length_block_valid <= 1'b0;
    end else begin
      length_block_valid <= CT_last;
    end
  end
endmodule
