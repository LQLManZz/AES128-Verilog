module SubWord (
    input logic [31:0] word_in,

    output logic [31:0] word_out
);
  logic [31:0] after_mInv;

  MultiplicativeInv minv1 (
      .byte_in (word_in[31:24]),
      .byte_out(after_mInv[31:24])
  );
  MultiplicativeInv minv2 (
      .byte_in (word_in[23:16]),
      .byte_out(after_mInv[23:16])
  );
  MultiplicativeInv minv3 (
      .byte_in (word_in[15:8]),
      .byte_out(after_mInv[15:8])
  );
  MultiplicativeInv minv4 (
      .byte_in (word_in[7:0]),
      .byte_out(after_mInv[7:0])
  );

  AffineTransform aff1 (
      .byte_in (after_mInv[31:24]),
      .byte_out(word_out[31:24])
  );
  AffineTransform aff2 (
      .byte_in (after_mInv[23:16]),
      .byte_out(word_out[23:16])
  );
  AffineTransform aff3 (
      .byte_in (after_mInv[15:8]),
      .byte_out(word_out[15:8])
  );
  AffineTransform aff4 (
      .byte_in (after_mInv[7:0]),
      .byte_out(word_out[7:0])
  );
endmodule
