module InvMixCol( 
    input logic [31:0] InvCol_in,
    output logic [31:0] InvCol_out);
    logic [7:0] Byte0_mul9, Byte0_mul11, Byte0_mul13, Byte0_mul14;
    logic [7:0] Byte1_mul9, Byte1_mul11, Byte1_mul13, Byte1_mul14;
    logic [7:0] Byte2_mul9, Byte2_mul11, Byte2_mul13, Byte2_mul14;
    logic [7:0] Byte3_mul9, Byte3_mul11, Byte3_mul13, Byte3_mul14;
    MUL_For_Inv mul0 (.Byte(InvCol_in[31:24]),.Byte_mul9(Byte0_mul9),.Byte_mul11(Byte0_mul11),
                    .Byte_mul13(Byte0_mul13),.Byte_mul14(Byte0_mul14));
    MUL_For_Inv mul1 (.Byte(InvCol_in[23:16]),.Byte_mul9(Byte1_mul9),.Byte_mul11(Byte1_mul11),
                    .Byte_mul13(Byte1_mul13),.Byte_mul14(Byte1_mul14));
    MUL_For_Inv mul2 (.Byte(InvCol_in[15:8]),.Byte_mul9(Byte2_mul9),.Byte_mul11(Byte2_mul11),
                    .Byte_mul13(Byte2_mul13),.Byte_mul14(Byte2_mul14));
    MUL_For_Inv mul3 (.Byte(InvCol_in[7:0]),.Byte_mul9(Byte3_mul9),.Byte_mul11(Byte3_mul11),
                    .Byte_mul13(Byte3_mul13),.Byte_mul14(Byte3_mul14));
    assign InvCol_out [31:24] = Byte0_mul14 ^ Byte1_mul11 ^ Byte2_mul13 ^ Byte3_mul9;
    assign InvCol_out [23:16] = Byte0_mul9 ^ Byte1_mul14 ^ Byte2_mul11 ^ Byte3_mul13;
    assign InvCol_out [15:8] = Byte0_mul13 ^ Byte1_mul9 ^ Byte2_mul14 ^ Byte3_mul11;
    assign InvCol_out [7:0] = Byte0_mul11 ^ Byte1_mul13 ^ Byte2_mul9 ^ Byte3_mul14;
endmodule
