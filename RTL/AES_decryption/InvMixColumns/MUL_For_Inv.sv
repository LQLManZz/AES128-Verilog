module MUL_For_Inv(
    input logic [7:0] Byte,
    output logic [7:0] Byte_mul9, Byte_mul11, Byte_mul13, Byte_mul14 );
    logic [7:0] Byte_mul2, Byte_mul4, Byte_mul8;
    MULX_MixColumns MUL0 (.Byte(Byte), .Byte_mul2(Byte_mul2));
    MULX_MixColumns MUL1 (.Byte(Byte_mul2), .Byte_mul2(Byte_mul4));
    MULX_MixColumns MUL2 (.Byte(Byte_mul4), .Byte_mul2(Byte_mul8));
    assign Byte_mul9 = Byte_mul8 ^ Byte;
    assign Byte_mul11 = Byte_mul9 ^ Byte_mul2;
    assign Byte_mul13 = Byte_mul9 ^ Byte_mul4;
    assign Byte_mul14 = Byte_mul8 ^ Byte_mul4 ^ Byte_mul2;
endmodule
