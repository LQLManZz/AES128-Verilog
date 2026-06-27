module InvSubBytes(
    input logic [127:0] InvSubBytes_in,
    output logic [127:0] InvSubBytes_out);
    SBoxInv s0 (.byte_in(InvSubBytes_in[127:120]),.byte_out(InvSubBytes_out[127:120]));
    SBoxInv s1 (.byte_in(InvSubBytes_in[119:112]),.byte_out(InvSubBytes_out[119:112]));
    SBoxInv s2 (.byte_in(InvSubBytes_in[111:104]),.byte_out(InvSubBytes_out[111:104]));
    SBoxInv s3 (.byte_in(InvSubBytes_in[103:96]),.byte_out(InvSubBytes_out[103:96]));
    SBoxInv s4 (.byte_in(InvSubBytes_in[95:88]),.byte_out(InvSubBytes_out[95:88]));
    SBoxInv s5 (.byte_in(InvSubBytes_in[87:80]),.byte_out(InvSubBytes_out[87:80]));
    SBoxInv s6 (.byte_in(InvSubBytes_in[79:72]),.byte_out(InvSubBytes_out[79:72]));
    SBoxInv s7 (.byte_in(InvSubBytes_in[71:64]),.byte_out(InvSubBytes_out[71:64]));
    SBoxInv s8 (.byte_in(InvSubBytes_in[63:56]),.byte_out(InvSubBytes_out[63:56]));
    SBoxInv s9 (.byte_in(InvSubBytes_in[55:48]),.byte_out(InvSubBytes_out[55:48]));
    SBoxInv s10 (.byte_in(InvSubBytes_in[47:40]),.byte_out(InvSubBytes_out[47:40]));
    SBoxInv s11 (.byte_in(InvSubBytes_in[39:32]),.byte_out(InvSubBytes_out[39:32]));
    SBoxInv s12 (.byte_in(InvSubBytes_in[31:24]),.byte_out(InvSubBytes_out[31:24]));
    SBoxInv s13 (.byte_in(InvSubBytes_in[23:16]),.byte_out(InvSubBytes_out[23:16]));
    SBoxInv s14 (.byte_in(InvSubBytes_in[15:8]),.byte_out(InvSubBytes_out[15:8]));
    SBoxInv s15 (.byte_in(InvSubBytes_in[7:0]),.byte_out(InvSubBytes_out[7:0]));
endmodule
