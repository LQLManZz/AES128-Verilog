module GFunction_256 (
    input logic [31:0] word_in,
    input logic [ 3:0] round_index,

    output logic [31:0] word_out
);
  logic [31:0] after_rotword;
  logic [31:0] after_subword;

  RotWord rw1 (
      .word_in (word_in),
      .word_out(after_rotword)
  );
  SubWord sw1 (
      .word_in (after_rotword),
      .word_out(after_subword)
  );
  AddRcon_256 arc1 (
      .word_in(after_subword),
      .round_index(round_index),
      .word_out(word_out)
  );
endmodule
