module SubWord (
    input logic [31:0] word_in,

    output logic [31:0] word_out
);
  SBox sb1 (
      .byte_in (word_in[31:24]),
      .byte_out(word_out[31:24])
  );
  SBox sb2 (
      .byte_in (word_in[23:16]),
      .byte_out(word_out[23:16])
  );
  SBox sb3 (
      .byte_in (word_in[15:8]),
      .byte_out(word_out[15:8])
  );
  SBox sb4 (
      .byte_in (word_in[7:0]),
      .byte_out(word_out[7:0])
  );
endmodule
