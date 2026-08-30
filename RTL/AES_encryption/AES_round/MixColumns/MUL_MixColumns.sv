module MUL_MixColumns( 
    input logic [7:0] Byte,
    output logic[7:0] Byte_mul2 , Byte_mul3);
    logic [7:0] ByteSL;
    assign ByteSL = Byte << 1;
    assign Byte_mul2 = Byte[7] ? (ByteSL ^ 8'h1b) : ByteSL;
    assign Byte_mul3 = Byte_mul2 ^ Byte;
endmodule
