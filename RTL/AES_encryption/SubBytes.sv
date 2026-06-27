module SubBytes(
    input logic [127:0] SubBytes_in,
    output logic [127:0] SubBytes_out);
    SBox Sbyte0 (.byte_in(SubBytes_in[127:120]),.byte_out(SubBytes_out[127:120]));
    SBox Sbyte1 (.byte_in(SubBytes_in[119:112]),.byte_out(SubBytes_out[119:112]));
    SBox Sbyte2 (.byte_in(SubBytes_in[111:104]),.byte_out(SubBytes_out[111:104]));
    SBox Sbyte3 (.byte_in(SubBytes_in[103:96]),.byte_out(SubBytes_out[103:96]));
    SBox Sbyte4 (.byte_in(SubBytes_in[95:88]),.byte_out(SubBytes_out[95:88]));
    SBox Sbyte5 (.byte_in(SubBytes_in[87:80]),.byte_out(SubBytes_out[87:80]));
    SBox Sbyte6 (.byte_in(SubBytes_in[79:72]),.byte_out(SubBytes_out[79:72]));
    SBox Sbyte7 (.byte_in(SubBytes_in[71:64]),.byte_out(SubBytes_out[71:64]));
    SBox Sbyte8 (.byte_in(SubBytes_in[63:56]),.byte_out(SubBytes_out[63:56]));
    SBox Sbyte9 (.byte_in(SubBytes_in[55:48]),.byte_out(SubBytes_out[55:48]));
    SBox Sbyte10 (.byte_in(SubBytes_in[47:40]),.byte_out(SubBytes_out[47:40]));
    SBox Sbyte11 (.byte_in(SubBytes_in[39:32]),.byte_out(SubBytes_out[39:32]));
    SBox Sbyte12 (.byte_in(SubBytes_in[31:24]),.byte_out(SubBytes_out[31:24]));
    SBox Sbyte13 (.byte_in(SubBytes_in[23:16]),.byte_out(SubBytes_out[23:16]));
    SBox Sbyte14 (.byte_in(SubBytes_in[15:8]),.byte_out(SubBytes_out[15:8]));
    SBox Sbyte15 (.byte_in(SubBytes_in[7:0]),.byte_out(SubBytes_out[7:0]));
endmodule
