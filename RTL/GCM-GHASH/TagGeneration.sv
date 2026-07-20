module TagGeneration (
    input logic tagen_en,
    input logic [127:0] E_key,
    input logic [127:0] data_in,

    output logic [127:0] tag,
    output logic tag_ready
);
  wire [127:0] ghash_out = tagen_en ? data_in : 128'h0;

  assign tag = ghash_out ^ E_key;
  assign tag_ready = (tag != 128'h0);
endmodule
