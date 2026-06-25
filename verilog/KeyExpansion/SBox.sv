module SBox (
    input logic [7:0] byte_in,

    output logic [7:0] byte_out
);
  logic [7:0] after_mInv;

  MultiplicativeInv minv1 (
      .byte_in (byte_in),
      .byte_out(after_mInv)
  );
  AffineTransform aff1 (
      .byte_in (after_mInv),
      .byte_out(byte_out)
  );
endmodule
