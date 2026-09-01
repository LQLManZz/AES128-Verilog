module MixCol( 
    input logic [31:0] Col_in,
    output logic [31:0] Col_out);
    logic [7:0] Byte0_mul2, Byte0_mul3;
    logic [7:0] Byte1_mul2, Byte1_mul3;
    logic [7:0] Byte2_mul2, Byte2_mul3;
    logic [7:0] Byte3_mul2, Byte3_mul3;
    MUL_MixColumns mul0 (.Byte(Col_in[31:24]), .Byte_mul2(Byte0_mul2),.Byte_mul3(Byte0_mul3));
    MUL_MixColumns mul1 (.Byte(Col_in[23:16]), .Byte_mul2(Byte1_mul2),.Byte_mul3(Byte1_mul3));
    MUL_MixColumns mul2 (.Byte(Col_in[15:8]), .Byte_mul2(Byte2_mul2),.Byte_mul3(Byte2_mul3));
    MUL_MixColumns mul3 (.Byte(Col_in[7:0]), .Byte_mul2(Byte3_mul2),.Byte_mul3(Byte3_mul3));
    assign Col_out[31:24] = Byte0_mul2^Byte1_mul3^Col_in[15:8]^Col_in[7:0];
    assign Col_out[23:16] = Byte1_mul2^Byte2_mul3^Col_in[31:24]^Col_in[7:0];
    assign Col_out[15:8] = Byte2_mul2^Byte3_mul3^Col_in[31:24]^Col_in[23:16];
    assign Col_out[7:0] = Byte3_mul2^Byte0_mul3^Col_in[15:8]^Col_in[23:16];
endmodule
