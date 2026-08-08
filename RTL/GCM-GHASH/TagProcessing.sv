module TagProcessing (
    input logic clk,
    input logic rst_n,
    input logic finish_reset,
    input logic mode,
    input logic [127:0] AAD,
    input logic [127:0] CT,
    input logic [127:0] tag_ref,
    input logic [127:0] H,
    input logic [127:0] E,
    input logic AAD_valid,
    input logic CT_valid,
    input logic H_valid,
    input logic E_valid,
    input logic tag_ref_valid,

    output logic H_loaded,
    output logic [127:0] tag,
    output logic tag_valid,
    output logic verify_pass
);
  logic reset;
  logic ghash_en;
  logic length_block_valid;
  logic final_valid;
  logic [127:0] H_reg;
  logic [127:0] E_reg;
  logic [127:0] tag_ref_reg;
  logic [127:0] length_block;
  logic [127:0] ghash_out;

  assign reset = rst_n && !finish_reset;
  assign ghash_en = AAD_valid || CT_valid || length_block_valid;
  assign tag = ghash_out ^ E_reg;
  assign tag_valid = final_valid && !mode;
  assign verify_pass = final_valid && mode && (tag == tag_ref_reg);

  always_ff @(posedge clk, negedge rst_n) begin : HLoadedReg
    if (!rst_n) begin
      H_loaded <= 1'b0;
    end else if (H_valid && !H_loaded) begin
      H_loaded <= 1'b1;
    end
  end

  always_ff @(posedge clk, negedge rst_n) begin : HKeyReg
    if (!rst_n) begin
      H_reg <= 128'h0;
    end else if (H_valid && !H_loaded) begin
      H_reg <= H;
    end
  end

  always_ff @(posedge clk, negedge reset) begin : EKeyReg
    if (!reset) begin
      E_reg <= 128'h0;
    end else if (E_valid) begin
      E_reg <= E;
    end
  end

  always_ff @(posedge clk, negedge rst_n) begin : TagReferenceReg
    if (!rst_n) begin
      tag_ref_reg <= 128'h0;
    end else if (tag_ref_valid) begin
      tag_ref_reg <= tag_ref;
    end
  end

  always_ff @(posedge clk, negedge reset) begin : FinalValidReg
    if (!reset) begin
      final_valid <= 1'b0;
    end else begin
      final_valid <= length_block_valid;
    end
  end

  LengthBlockCTR LengthCounter (
      .clk(clk),
      .reset(reset),
      .AAD_valid(AAD_valid),
      .CT_valid(CT_valid),
      .length_block(length_block),
      .length_block_valid(length_block_valid)
  );

  GHASH GHASHCore (
      .clk(clk),
      .reset(reset),
      .ghash_en(ghash_en),
      .AAD(AAD),
      .AAD_valid(AAD_valid),
      .CT(CT),
      .CT_valid(CT_valid),
      .length_block(length_block),
      .length_block_valid(length_block_valid),
      .H_reg(H_reg),
      .ghash_out(ghash_out)
  );
endmodule
