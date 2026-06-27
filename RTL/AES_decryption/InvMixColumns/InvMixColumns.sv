module InvMixColumns(
    input logic [127:0] InvMixColumns_in,
    output logic [127:0] InvMixColumns_out);
    InvMixCol InvCol0 (.InvCol_in(InvMixColumns_in[127:96]),
                        .InvCol_out(InvMixColumns_out[127:96]));
    InvMixCol InvCol1 (.InvCol_in(InvMixColumns_in[95:64]),
                        .InvCol_out(InvMixColumns_out[95:64]));
    InvMixCol InvCol2 (.InvCol_in(InvMixColumns_in[63:32]),
                        .InvCol_out(InvMixColumns_out[63:32]));
    InvMixCol InvCol3 (.InvCol_in(InvMixColumns_in[31:0]),.InvCol_out(InvMixColumns_out[31:0]));
endmodule
