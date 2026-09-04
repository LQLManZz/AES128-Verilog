module TagProcessing (
    input logic         clk,
    input logic         rst_n,
    input logic         finish_reset,
    input logic         load_key,
    input logic         mode,
    input logic [127:0] AAD,
    input logic [127:0] CT,
    input logic [127:0] tag_ref,
    input logic [127:0] H,
    input logic [127:0] E,
    input logic         load_AAD,
    input logic         load_CT,
    input logic         H_valid,
    input logic         E_valid,
    input logic         load_tag_ref,
    input logic         CT_last,

    output logic         H_loaded,
    output logic         tag_ref_loaded,
    output logic [127:0] tag,
    output logic         tag_process_valid,
    output logic         verify_pass
);
  logic         H_reset;
  logic         length_block_valid;
  logic         E_loaded;
  logic         ghash_finish;
  logic [127:0] H_reg;
  logic [127:0] E_reg;
  logic [127:0] tag_ref_reg;
  logic [127:0] length_block;
  logic [127:0] ghash_out;

  assign H_reset = ~rst_n | load_key;
  assign verify_pass = mode && tag_process_valid && (tag == tag_ref_reg);

  always_ff @(posedge clk, posedge finish_reset) begin : TagReg
    if (finish_reset) begin
      tag <= 128'h0;
    end else begin
      if (ghash_finish && E_loaded) begin
        tag <= ghash_out ^ E_reg;
      end else begin
        tag <= 128'h0;
      end
    end
  end

  always_ff @(posedge clk, posedge finish_reset) begin : TagProcessValidReg
    if (finish_reset) begin
      tag_process_valid <= 1'b0;
    end else begin
      tag_process_valid <= ghash_finish & E_loaded;
    end
  end

  always_ff @(posedge clk, posedge H_reset) begin : HLoadedReg
    if (H_reset) begin
      H_loaded <= 1'b0;
    end else if (H_valid && !H_loaded) begin
      H_loaded <= 1'b1;
    end
  end

  always_ff @(posedge clk, posedge H_reset) begin : HKeyReg
    if (H_reset) begin
      H_reg <= 128'h0;
    end else if (H_valid && !H_loaded) begin
      H_reg <= H;
    end
  end

  always_ff @(posedge clk, posedge finish_reset) begin : ELoadedReg
    if (finish_reset) begin
      E_loaded <= 1'b0;
    end else if (E_valid && !E_loaded) begin
      E_loaded <= 1'b1;
    end
  end

  always_ff @(posedge clk, posedge finish_reset) begin : EKeyReg
    if (finish_reset) begin
      E_reg <= 128'h0;
    end else if (E_valid && !E_loaded) begin
      E_reg <= E;
    end
  end

  always_ff @(posedge clk, posedge finish_reset) begin : TagRefLoadedReg
    if (finish_reset) begin
      tag_ref_loaded <= 1'b0;
    end else if (load_tag_ref && !tag_ref_loaded) begin
      tag_ref_loaded <= 1'b1;
    end
  end

  always_ff @(posedge clk, posedge finish_reset) begin : TagReferenceReg
    if (finish_reset) begin
      tag_ref_reg <= 128'h0;
    end else if (load_tag_ref && !tag_ref_loaded) begin
      tag_ref_reg <= tag_ref;
    end
  end

  LengthBlockCounter LengthCounter (
      .clk               (clk),
      .finish_reset      (finish_reset),
      .load_AAD          (load_AAD),
      .load_CT           (load_CT),
      .CT_last           (CT_last),
      .length_block_valid(length_block_valid),
      .length_block      (length_block)
  );

  GHASH GHASHCore (
      .clk               (clk),
      .finish_reset      (finish_reset),
      .load_AAD          (load_AAD),
      .load_CT           (load_CT),
      .length_block_valid(length_block_valid),
      .AAD               (AAD),
      .CT                (CT),
      .length_block      (length_block),
      .H_reg             (H_reg),
      .ghash_finish      (ghash_finish),
      .ghash_out         (ghash_out)
  );
endmodule
