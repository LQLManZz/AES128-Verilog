module InvAffineTransform (
    input logic [7:0] byte_in,

    output logic [7:0] byte_out
);
  assign byte_out[7] = byte_in[6] ^ byte_in[4] ^ byte_in[1];
  assign byte_out[6] = byte_in[5] ^ byte_in[3] ^ byte_in[0];
  assign byte_out[5] = byte_in[7] ^ byte_in[4] ^ byte_in[2];
  assign byte_out[4] = byte_in[6] ^ byte_in[3] ^ byte_in[1];
  assign byte_out[3] = byte_in[5] ^ byte_in[2] ^ byte_in[0];
  assign byte_out[2] = byte_in[7] ^ byte_in[4] ^ byte_in[1] ^ 1'b1;
  assign byte_out[1] = byte_in[6] ^ byte_in[3] ^ byte_in[0];
  assign byte_out[0] = byte_in[7] ^ byte_in[5] ^ byte_in[2] ^ 1'b1;
endmodule
