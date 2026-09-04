module GF128bitMultiply (
    input logic [127:0] H_reg,
    input logic [127:0] data_in,

    output logic [127:0] data_out
);
  logic [255:0] X128_result;

  X128 Product (
      .H_reg(H_reg),
      .data_in(data_in),
      .data_out(X128_result)
  );

  ReductionBlock RB (
      .data_in (X128_result),
      .data_out(data_out)
  );
endmodule

module X8 (
    input logic [7:0] data_in1,
    input logic [7:0] data_in2,

    output logic [15:0] data_out
);
  wire [15:0] product0 = {8'd0, data_in1} & {16{data_in2[0]}};
  wire [15:0] product1 = {7'd0, data_in1, 1'd0} & {16{data_in2[1]}};
  wire [15:0] product2 = {6'd0, data_in1, 2'd0} & {16{data_in2[2]}};
  wire [15:0] product3 = {5'd0, data_in1, 3'd0} & {16{data_in2[3]}};
  wire [15:0] product4 = {4'd0, data_in1, 4'd0} & {16{data_in2[4]}};
  wire [15:0] product5 = {3'd0, data_in1, 5'd0} & {16{data_in2[5]}};
  wire [15:0] product6 = {2'd0, data_in1, 6'd0} & {16{data_in2[6]}};
  wire [15:0] product7 = {1'd0, data_in1, 7'd0} & {16{data_in2[7]}};

  assign data_out = product0 ^ product1
                    ^ product2 ^ product3
                    ^ product4 ^ product5
                    ^ product6 ^ product7;
endmodule

module X16 (
    input logic [15:0] data_in1,
    input logic [15:0] data_in2,

    output logic [31:0] data_out
);
  logic [15:0] P0_result, P1_result, P2_result;
  wire [ 7:0] data_in1_P2 = data_in1[15:8] ^ data_in1[7:0];
  wire [ 7:0] data_in2_P2 = data_in2[15:8] ^ data_in2[7:0];
  wire [15:0] Pm = P0_result ^ P1_result ^ P2_result;

  X8 P1 (
      .data_in1(data_in1[15:8]),
      .data_in2(data_in2[15:8]),
      .data_out(P1_result)
  );
  X8 P0 (
      .data_in1(data_in1[7:0]),
      .data_in2(data_in2[7:0]),
      .data_out(P0_result)
  );
  X8 P2 (
      .data_in1(data_in1_P2),
      .data_in2(data_in2_P2),
      .data_out(P2_result)
  );

  assign data_out[31:24] = P1_result[15:8];
  assign data_out[23:16] = P1_result[7:0] ^ Pm[15:8];
  assign data_out[15:8]  = P0_result[15:8] ^ Pm[7:0];
  assign data_out[7:0]   = P0_result[7:0];
endmodule

module X32 (
    input logic [31:0] data_in1,
    input logic [31:0] data_in2,

    output logic [63:0] data_out
);
  logic [31:0] P0_result, P1_result, P2_result;
  wire [15:0] data_in1_P2 = data_in1[31:16] ^ data_in1[15:0];
  wire [15:0] data_in2_P2 = data_in2[31:16] ^ data_in2[15:0];
  wire [31:0] Pm = P0_result ^ P1_result ^ P2_result;

  X16 P1 (
      .data_in1(data_in1[31:16]),
      .data_in2(data_in2[31:16]),
      .data_out(P1_result)
  );
  X16 P0 (
      .data_in1(data_in1[15:0]),
      .data_in2(data_in2[15:0]),
      .data_out(P0_result)
  );
  X16 P2 (
      .data_in1(data_in1_P2),
      .data_in2(data_in2_P2),
      .data_out(P2_result)
  );

  assign data_out[63:48] = P1_result[31:16];
  assign data_out[47:32] = P1_result[15:0] ^ Pm[31:16];
  assign data_out[31:16] = P0_result[31:16] ^ Pm[15:0];
  assign data_out[15:0]  = P0_result[15:0];
endmodule

module X64 (
    input logic [63:0] data_in1,
    input logic [63:0] data_in2,

    output logic [127:0] data_out
);
  logic [63:0] P0_result, P1_result, P2_result;
  wire [31:0] data_in1_P2 = data_in1[63:32] ^ data_in1[31:0];
  wire [31:0] data_in2_P2 = data_in2[63:32] ^ data_in2[31:0];
  wire [63:0] Pm = P0_result ^ P1_result ^ P2_result;

  X32 P1 (
      .data_in1(data_in1[63:32]),
      .data_in2(data_in2[63:32]),
      .data_out(P1_result)
  );
  X32 P0 (
      .data_in1(data_in1[31:0]),
      .data_in2(data_in2[31:0]),
      .data_out(P0_result)
  );
  X32 P2 (
      .data_in1(data_in1_P2),
      .data_in2(data_in2_P2),
      .data_out(P2_result)
  );

  assign data_out[127:96] = P1_result[63:32];
  assign data_out[95:64]  = P1_result[31:0] ^ Pm[63:32];
  assign data_out[63:32]  = P0_result[63:32] ^ Pm[31:0];
  assign data_out[31:0]   = P0_result[31:0];
endmodule

module X128 (
    input logic [127:0] H_reg,
    input logic [127:0] data_in,

    output logic [255:0] data_out
);
  logic [127:0] P0_result, P1_result, P2_result;
  wire [ 63:0] data_in1_P2 = H_reg[127:64] ^ H_reg[63:0];
  wire [ 63:0] data_in2_P2 = data_in[127:64] ^ data_in[63:0];
  wire [127:0] Pm = P0_result ^ P1_result ^ P2_result;

  X64 P1 (
      .data_in1(H_reg[127:64]),
      .data_in2(data_in[127:64]),
      .data_out(P1_result)
  );
  X64 P0 (
      .data_in1(H_reg[63:0]),
      .data_in2(data_in[63:0]),
      .data_out(P0_result)
  );
  X64 P2 (
      .data_in1(data_in1_P2),
      .data_in2(data_in2_P2),
      .data_out(P2_result)
  );

  assign data_out[255:192] = P1_result[127:64];
  assign data_out[191:128] = P1_result[63:0] ^ Pm[127:64];
  assign data_out[127:64]  = P0_result[127:64] ^ Pm[63:0];
  assign data_out[63:0]    = P0_result[63:0];
endmodule

module ReductionBlock (
    input logic [255:0] data_in,

    output logic [127:0] data_out
);
  wire [134:0] xor_1 = {7'd0, data_in[127:0]}
                        ^ {7'd0, data_in[255:128]}
                        ^ {6'd0, data_in[255:128], 1'd0}
                        ^ {5'd0, data_in[255:128], 2'd0}
                        ^ {data_in[255:128], 7'd0};

  assign data_out = xor_1[127:0]
                    ^ {121'd0, xor_1[134:128]}
                    ^ {120'd0, xor_1[134:128], 1'd0}
                    ^ {119'd0, xor_1[134:128], 2'd0}
                    ^ {114'd0, xor_1[134:128], 7'd0};
endmodule
