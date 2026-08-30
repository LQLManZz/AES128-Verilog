module MixColumns(
    input logic [127:0] MixColumns_in,
    output logic [127:0] MixColumns_out);
    MixCol Col0 (.Col_in(MixColumns_in[127:96]), .Col_out(MixColumns_out[127:96]));
    MixCol Col1 (.Col_in(MixColumns_in[95:64]), .Col_out(MixColumns_out[95:64]));
    MixCol Col2 (.Col_in(MixColumns_in[63:32]), .Col_out(MixColumns_out[63:32]));
    MixCol Col3 (.Col_in(MixColumns_in[31:0]), .Col_out(MixColumns_out[31:0]));
endmodule
