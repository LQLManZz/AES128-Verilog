module MultiplicativeInv (
    input logic [7:0] byte_in,

    output logic [7:0] byte_out
);
  logic [7:0] byte_in_imp;
  logic [7:0] byte_in_inv;

  logic [3:0] byte_in_imp_S;
  logic [3:0] byte_in_imp_C;
  logic [3:0] XOR_byte_in_imp;
  logic [3:0] byte_in_imp_X;
  logic [3:0] XOR_to_Inv;
  logic [3:0] InvOut;

  assign XOR_byte_in_imp = byte_in_imp[7:4] ^ byte_in_imp[3:0];
  assign XOR_to_Inv = byte_in_imp_C ^ byte_in_imp_X;

  Imp imp1 (
      .byte_in (byte_in),
      .byte_out(byte_in_imp)
  );
  ModuleS s1 (
      .data_in (byte_in_imp[7:4]),
      .data_out(byte_in_imp_S)
  );
  ModuleC c1 (
      .data_in (byte_in_imp_S),
      .data_out(byte_in_imp_C)
  );
  ModuleX x1 (
      .data_in1(byte_in_imp[3:0]),
      .data_in2(XOR_byte_in_imp),
      .data_out(byte_in_imp_X)
  );
  Inv inv1 (
      .data_in (XOR_to_Inv),
      .data_out(InvOut)
  );
  ModuleX x2 (
      .data_in1(InvOut),
      .data_in2(byte_in_imp[7:4]),
      .data_out(byte_in_inv[7:4])
  );
  ModuleX x3 (
      .data_in1(InvOut),
      .data_in2(XOR_byte_in_imp),
      .data_out(byte_in_inv[3:0])
  );
  ImpInv impinv1 (
      .byte_in (byte_in_inv),
      .byte_out(byte_out)
  );
endmodule

module Imp (
    input logic [7:0] byte_in,

    output logic [7:0] byte_out
);
  assign byte_out[7] = byte_in[7] ^ byte_in[5];
  assign byte_out[6] = byte_in[7] ^ byte_in[6] ^ byte_in[4] ^ byte_in[3] ^ byte_in[2] ^ byte_in[1];
  assign byte_out[5] = byte_in[7] ^ byte_in[5] ^ byte_in[3] ^ byte_in[2];
  assign byte_out[4] = byte_in[7] ^ byte_in[5] ^ byte_in[3] ^ byte_in[2] ^ byte_in[1];
  assign byte_out[3] = byte_in[7] ^ byte_in[6] ^ byte_in[2] ^ byte_in[1];
  assign byte_out[2] = byte_in[7] ^ byte_in[4] ^ byte_in[3] ^ byte_in[2] ^ byte_in[1];
  assign byte_out[1] = byte_in[6] ^ byte_in[4] ^ byte_in[1];
  assign byte_out[0] = byte_in[6] ^ byte_in[1] ^ byte_in[0];
endmodule

module ImpInv (
    input logic [7:0] byte_in,

    output logic [7:0] byte_out
);
  assign byte_out[7] = byte_in[7] ^ byte_in[6] ^ byte_in[5] ^ byte_in[1];
  assign byte_out[6] = byte_in[6] ^ byte_in[2];
  assign byte_out[5] = byte_in[6] ^ byte_in[5] ^ byte_in[1];
  assign byte_out[4] = byte_in[6] ^ byte_in[5] ^ byte_in[4] ^ byte_in[2] ^ byte_in[1];
  assign byte_out[3] = byte_in[5] ^ byte_in[4] ^ byte_in[3] ^ byte_in[2] ^ byte_in[1];
  assign byte_out[2] = byte_in[7] ^ byte_in[4] ^ byte_in[3] ^ byte_in[2] ^ byte_in[1];
  assign byte_out[1] = byte_in[5] ^ byte_in[4];
  assign byte_out[0] = byte_in[6] ^ byte_in[5] ^ byte_in[4] ^ byte_in[2] ^ byte_in[0];
endmodule

module ModuleS (
    input logic [3:0] data_in,

    output logic [3:0] data_out
);
  assign data_out[3] = data_in[3];
  assign data_out[2] = data_in[3] ^ data_in[2];
  assign data_out[1] = data_in[2] ^ data_in[1];
  assign data_out[0] = data_in[3] ^ data_in[1] ^ data_in[0];
endmodule

module ModuleC (
    input logic [3:0] data_in,

    output logic [3:0] data_out
);
  assign data_out[3] = data_in[2] ^ data_in[0];
  assign data_out[2] = data_in[3] ^ data_in[2] ^ data_in[1] ^ data_in[0];
  assign data_out[1] = data_in[3];
  assign data_out[0] = data_in[2];
endmodule

module ModuleX (
    input logic [3:0] data_in1,
    input logic [3:0] data_in2,

    output logic [3:0] data_out
);
  assign data_out[3] = (data_in1[3] & data_in2[3]) 
                    ^ (data_in1[3] & data_in2[2]) ^ (data_in1[2] & data_in2[3])
                    ^ (data_in1[3] & data_in2[1]) ^ (data_in1[1] & data_in2[3])
                    ^ (data_in1[3] & data_in2[0]) ^ (data_in1[0] & data_in2[3])
                    ^ (data_in1[2] & data_in2[1]) ^ (data_in1[1] & data_in2[2]);
  assign data_out[2] = (data_in1[3] & data_in2[3]) ^ (data_in1[2] & data_in2[2])
                    ^ (data_in1[3] & data_in2[1]) ^ (data_in1[1] & data_in2[3])
                    ^ (data_in1[2] & data_in2[0]) ^ (data_in1[0] & data_in2[2]);
  assign data_out[1] = (data_in1[3] & data_in2[2]) ^ (data_in1[2] & data_in2[3])
                    ^ (data_in1[2] & data_in2[2]) ^ (data_in1[1] & data_in2[1])
                    ^ (data_in1[1] & data_in2[0]) ^ (data_in1[0] & data_in2[1]);
  assign data_out[0] = (data_in1[3] & data_in2[3]) ^ (data_in1[1] & data_in2[1]) ^ (data_in1[0] & data_in2[0])
                    ^ (data_in1[3] & data_in2[2]) ^ (data_in1[2] & data_in2[3]);
endmodule

module Inv (
    input logic [3:0] data_in,

    output logic [3:0] data_out
);
  always_comb begin : InvSelectorForDelta
    case (data_in)
      4'h0: data_out = 4'h0;
      4'h1: data_out = 4'h1;
      4'h2: data_out = 4'h3;
      4'h3: data_out = 4'h2;
      4'h4: data_out = 4'hf;
      4'h5: data_out = 4'hc;
      4'h6: data_out = 4'h9;
      4'h7: data_out = 4'hb;
      4'h8: data_out = 4'ha;
      4'h9: data_out = 4'h6;
      4'ha: data_out = 4'h8;
      4'hb: data_out = 4'h7;
      4'hc: data_out = 4'h5;
      4'hd: data_out = 4'he;
      4'he: data_out = 4'hd;
      4'hf: data_out = 4'h4;
      default: data_out = 4'h0;
    endcase
  end
endmodule
