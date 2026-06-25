module SBoxInv (
    input logic [7:0] byte_in,

    output logic [7:0] byte_out
);
  logic [7:0] after_InvAff;

  InvAffineTransform invaff1 (
      .byte_in (byte_in),
      .byte_out(after_InvAff)
  );
  MultiplicativeInv minv1 (
      .byte_in (after_InvAff),
      .byte_out(byte_out)
  );
endmodule
