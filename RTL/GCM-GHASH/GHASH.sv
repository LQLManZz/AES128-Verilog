module GHASH (
    input logic clk,
    input logic load,
    input logic ghash_en,
    input logic [127:0] H_key,
    input logic [127:0] data_in,

    output logic [127:0] ghash_out,
    output logic [127:0] ghash_finish
);

endmodule
