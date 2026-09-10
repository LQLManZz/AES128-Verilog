//=============================================================================
// File: aes256_uart_wrapper.sv
// Directory: uart_integration/aes256/
// Description: All-In-One Self-Contained RTL for AES-256-GCM UART Accelerator.
//              Contains the complete synthesizable hardware hierarchy:
//                1. protocol_pkg (SystemVerilog package)
//                2. Low-level GF(2^8) S-Box arithmetic (MultiplicativeInv, AffineTransform)
//                3. Key Expansion & Round Key Generator
//                4. AES Core Encryption Engine (Pipelined Rounds, MixColumns, ShiftRows, SubBytes)
//                5. FIFO Buffers & Counter Generator (FIFO, counter_generator, CTR_counter)
//                6. AES-CTR Datapath
//                7. GCM Tag Processing & GHASH Multiplier (GF128bitMultiply, GHASH, LengthBlockCounter, TagProcessing)
//                8. Control Unit FSM (CU)
//                9. AES-256-GCM Hardware Accelerator Core Top
//               10. UART Physical Layer (uart_rx, uart_tx)
//               11. Packet Parser & Packet Builder (packet_parser, packet_builder)
//               12. AES-256-GCM UART Integration Top Wrapper (aes256_uart_wrapper)
//
// Target: Microchip PolarFire SoC Discovery Kit (MPFS095T-1FCSG325E) / Any FPGA / Simulator
// Ready for standalone simulation with tb_aes256_uart_wrapper.sv without external dependencies.
//=============================================================================

`timescale 1ns / 1ps


//=============================================================================
// SECTION: Protocol Package
// SOURCE: uart_integration/common/protocol_pkg.sv
//=============================================================================
//=============================================================================
// Package: protocol_pkg.sv
// Description: Unified SystemVerilog package declaring command opcodes,
//              response opcodes, error codes, and protocol constants for
//              the AES-GCM UART communication framework.
//=============================================================================


package protocol_pkg;

    // Command Opcodes (Host PC -> FPGA Accelerator)
    typedef enum logic [7:0] {
        CMD_LOAD_KEY       = 8'h01, // 16 bytes (AES-128) or 32 bytes (AES-256)
        CMD_LOAD_IV        = 8'h02, // 12 bytes (96 bits)
        CMD_LOAD_AAD       = 8'h03, // Multiples of 16 bytes
        CMD_LOAD_PLAINTEXT = 8'h04, // Multiples of 16 bytes
        CMD_START_ENCRYPT  = 8'h05  // 0 bytes payload
    } cmd_opcode_t;

    // Response Opcodes (FPGA Accelerator -> Host PC)
    typedef enum logic [7:0] {
        RESP_ACK_KEY       = 8'h81, // 0 bytes payload
        RESP_ACK_IV        = 8'h82, // 0 bytes payload
        RESP_ACK_AAD       = 8'h83, // 0 bytes payload
        RESP_ACK_PLAINTEXT = 8'h84, // 0 bytes payload
        RESP_CIPHERTEXT    = 8'h90, // Multiples of 16 bytes payload
        RESP_AUTH_TAG      = 8'h91, // 16 bytes payload (128 bits)
        RESP_ERR_UNKNOWN   = 8'hE0, // 1 byte payload (faulty opcode)
        RESP_ERR_LEN       = 8'hE1  // 1 byte payload (faulty opcode)
    } resp_opcode_t;

    // Protocol Limits & Sizes
    localparam int IV_BYTES         = 12;  // 96 bits
    localparam int TAG_BYTES        = 16;  // 128 bits
    localparam int BLOCK_BYTES      = 16;  // 128 bits per AES block
    localparam int MAX_BUFFER_BLOCKS = 16;  // 256 bytes burst capacity

endpackage : protocol_pkg


//=============================================================================
// SECTION: Multiplicative Inverse Primitives (Imp, ImpInv, ModuleS, ModuleC, ModuleX, Inv)
// SOURCE: RTL/AES-CTR/SBox/MultiplicativeInv.sv
//=============================================================================
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


//=============================================================================
// SECTION: Affine Transformation
// SOURCE: RTL/AES-CTR/SBox/AffineTransform.sv
//=============================================================================
module AffineTransform (
    input logic [7:0] byte_in,

    output logic [7:0] byte_out
);
  assign byte_out[7] = byte_in[7] ^ byte_in[6] ^ byte_in[5] ^ byte_in[4] ^ byte_in[3];
  assign byte_out[6] = byte_in[6] ^ byte_in[5] ^ byte_in[4] ^ byte_in[3] ^ byte_in[2] ^ 1'b1;
  assign byte_out[5] = byte_in[5] ^ byte_in[4] ^ byte_in[3] ^ byte_in[2] ^ byte_in[1] ^ 1'b1;
  assign byte_out[4] = byte_in[4] ^ byte_in[3] ^ byte_in[2] ^ byte_in[1] ^ byte_in[0];
  assign byte_out[3] = byte_in[7] ^ byte_in[3] ^ byte_in[2] ^ byte_in[1] ^ byte_in[0];
  assign byte_out[2] = byte_in[7] ^ byte_in[6] ^ byte_in[2] ^ byte_in[1] ^ byte_in[0];
  assign byte_out[1] = byte_in[7] ^ byte_in[6] ^ byte_in[5] ^ byte_in[1] ^ byte_in[0] ^ 1'b1;
  assign byte_out[0] = byte_in[7] ^ byte_in[6] ^ byte_in[5] ^ byte_in[4] ^ byte_in[0] ^ 1'b1;
endmodule


//=============================================================================
// SECTION: Composite Galois Field S-Box
// SOURCE: RTL/AES-CTR/SBox/SBox.sv
//=============================================================================
module SBox (
    input logic [7:0] byte_in,

    output logic [7:0] byte_out
);
  logic [7:0] after_mInv;

  MultiplicativeInv minv1 (
      .byte_in (byte_in),
      .byte_out(after_mInv)
  );
  AffineTransform aff1 (
      .byte_in (after_mInv),
      .byte_out(byte_out)
  );
endmodule


//=============================================================================
// SECTION: Key Expansion: RotWord
// SOURCE: RTL/AES-CTR/Key_Expansion/GFunction/RotWord.sv
//=============================================================================
module RotWord (
    input logic [31:0] word_in,

    output logic [31:0] word_out
);
  assign word_out = {word_in[23:0], word_in[31:24]};
endmodule


//=============================================================================
// SECTION: Key Expansion: SubWord
// SOURCE: RTL/AES-CTR/Key_Expansion/GFunction/SubWord.sv
//=============================================================================
module SubWord (
    input logic [31:0] word_in,

    output logic [31:0] word_out
);
  SBox sb1 (
      .byte_in (word_in[31:24]),
      .byte_out(word_out[31:24])
  );
  SBox sb2 (
      .byte_in (word_in[23:16]),
      .byte_out(word_out[23:16])
  );
  SBox sb3 (
      .byte_in (word_in[15:8]),
      .byte_out(word_out[15:8])
  );
  SBox sb4 (
      .byte_in (word_in[7:0]),
      .byte_out(word_out[7:0])
  );
endmodule


//=============================================================================
// SECTION: Key Expansion: AddRcon (256-bit)
// SOURCE: RTL/AES_256_CTR/Key_Expansion_256/GFunction_256/AddRcon_256.sv
//=============================================================================
module AddRcon_256 (
    input logic [31:0] word_in,
    input logic [ 3:0] round_index,

    output logic [31:0] word_out
);
  logic [31:0] rcon;
  always_comb begin : RconSelector
    case (round_index)
      4'd0: rcon = 32'h01000000;
      4'd2: rcon = 32'h02000000;
      4'd4: rcon = 32'h04000000;
      4'd6: rcon = 32'h08000000;
      4'd8: rcon = 32'h10000000;
      4'd10: rcon = 32'h20000000;
      4'd12: rcon = 32'h40000000;
      default: rcon = 32'h01000000;
    endcase
  end

  assign word_out = word_in ^ rcon;
endmodule


//=============================================================================
// SECTION: Key Expansion: Counter (256-bit)
// SOURCE: RTL/AES_256_CTR/Key_Expansion_256/Counter_256.sv
//=============================================================================
module Counter_256 (
    input logic clk,
    input logic rst_n,
    input logic expansion_en,

    output logic rk0,
    output logic rk1,
    output logic sub_only,
    output logic expansion_finish,
    output logic [3:0] round_index
);
  assign rk0 = (round_index == 4'd0);
  assign rk1 = (round_index == 4'd1);
  assign sub_only = (round_index[0] == 1'b1);

  always_ff @(posedge clk, negedge rst_n) begin
    if (!rst_n) begin
      round_index      <= 4'd0;
      expansion_finish <= 1'b0;
    end else if (expansion_finish) begin
      if (!expansion_en) begin
        expansion_finish <= 1'b0;
        round_index      <= 4'd0;
      end
    end else if (expansion_en) begin
      if (round_index == 4'd12) begin
        round_index      <= 4'd0;
        expansion_finish <= 1'b1;
      end else begin
        round_index <= round_index + 1'b1;
      end
    end
  end
endmodule


//=============================================================================
// SECTION: Key Expansion: GFunction (256-bit)
// SOURCE: RTL/AES_256_CTR/Key_Expansion_256/GFunction_256/GFunction_256.sv
//=============================================================================
module GFunction_256 (
    input logic [31:0] word_in,
    input logic [ 3:0] round_index,

    output logic [31:0] word_out
);
  logic [31:0] after_rotword;
  logic [31:0] after_subword;

  RotWord rw1 (
      .word_in (word_in),
      .word_out(after_rotword)
  );
  SubWord sw1 (
      .word_in (after_rotword),
      .word_out(after_subword)
  );
  AddRcon_256 arc1 (
      .word_in(after_subword),
      .round_index(round_index),
      .word_out(word_out)
  );
endmodule


//=============================================================================
// SECTION: Key Expansion: Top (256-bit)
// SOURCE: RTL/AES_256_CTR/Key_Expansion_256/KeyExpansion_256.sv
//=============================================================================
module KeyExpansion_256 (
    input logic clk,
    input logic rst_n,
    input logic expansion_en,
    input logic [255:0] cipher_key,

    output logic [127:0] round_key[0:14],
    output logic expansion_finish
);
  logic [3:0] round_index;
  logic [127:0] current_key;
  logic [127:0] prev_key;
  logic [127:0] next_key;
  logic [31:0] after_GFunction;
  logic [31:0] sub_onlyMUX;
  logic rk0;
  logic rk1;
  logic sub_only;

  always_ff @(posedge clk, negedge rst_n) begin : RoundKeyReg
    if (!rst_n) begin
      integer i;
      for (i = 0; i <= 14; i++) begin
        round_key[i] <= 128'h0;
      end
    end else if (expansion_en) begin
      round_key[0] <= cipher_key[255:128];
      round_key[1] <= cipher_key[127:0];
      case (round_index)
        4'd0: round_key[2] <= next_key;
        4'd1: round_key[3] <= next_key;
        4'd2: round_key[4] <= next_key;
        4'd3: round_key[5] <= next_key;
        4'd4: round_key[6] <= next_key;
        4'd5: round_key[7] <= next_key;
        4'd6: round_key[8] <= next_key;
        4'd7: round_key[9] <= next_key;
        4'd8: round_key[10] <= next_key;
        4'd9: round_key[11] <= next_key;
        4'd10: round_key[12] <= next_key;
        4'd11: round_key[13] <= next_key;
        4'd12: round_key[14] <= next_key;
        default: ;
      endcase
    end
  end
  always_comb begin : PrevKeyMUX
    if (rk0) begin
      prev_key = cipher_key[255:128];
    end else if (rk1) begin
      prev_key = cipher_key[127:0];
    end else begin
      case (round_index)
        4'd2: prev_key = round_key[2];
        4'd3: prev_key = round_key[3];
        4'd4: prev_key = round_key[4];
        4'd5: prev_key = round_key[5];
        4'd6: prev_key = round_key[6];
        4'd7: prev_key = round_key[7];
        4'd8: prev_key = round_key[8];
        4'd9: prev_key = round_key[9];
        4'd10: prev_key = round_key[10];
        4'd11: prev_key = round_key[11];
        4'd12: prev_key = round_key[12];
        default: prev_key = 128'h0;
      endcase
    end
  end
  always_comb begin : CurrentKeyMUX
    if (rk0) begin
      current_key = cipher_key[127:0];
    end else if (rk1) begin
      current_key = round_key[2];
    end else begin
      case (round_index)
        4'd2: current_key = round_key[3];
        4'd3: current_key = round_key[4];
        4'd4: current_key = round_key[5];
        4'd5: current_key = round_key[6];
        4'd6: current_key = round_key[7];
        4'd7: current_key = round_key[8];
        4'd8: current_key = round_key[9];
        4'd9: current_key = round_key[10];
        4'd10: current_key = round_key[11];
        4'd11: current_key = round_key[12];
        4'd12: current_key = round_key[13];
        default: current_key = 128'h0;
      endcase
    end
  end
  always_comb begin : WordGenerator
    if (sub_only) begin
      next_key[127:96] = sub_onlyMUX ^ prev_key[127:96];
    end else begin
      next_key[127:96] = after_GFunction ^ prev_key[127:96];
    end
    next_key[95:64] = next_key[127:96] ^ prev_key[95:64];
    next_key[63:32] = next_key[95:64] ^ prev_key[63:32];
    next_key[31:0]  = next_key[63:32] ^ prev_key[31:0];
  end

  SubWord sw1 (
      .word_in (current_key[31:0]),
      .word_out(sub_onlyMUX)
  );
  Counter_256 cnt1 (
      .clk(clk),
      .rst_n(rst_n),
      .expansion_en(expansion_en),
      .round_index(round_index),
      .rk0(rk0),
      .rk1(rk1),
      .sub_only(sub_only),
      .expansion_finish(expansion_finish)
  );
  GFunction_256 gfunc1 (
      .word_in(current_key[31:0]),
      .round_index(round_index),
      .word_out(after_GFunction)
  );
endmodule


//=============================================================================
// SECTION: MixColumns: Galois Field Multiplier by 2 & 3
// SOURCE: RTL/AES-CTR/AES_encryption/AES_round/MixColumns/MUL_MixColumns.sv
//=============================================================================
module MUL_MixColumns( 
    input logic [7:0] Byte,
    output logic[7:0] Byte_mul2 , Byte_mul3);
    logic [7:0] ByteSL;
    assign ByteSL = Byte << 1;
    assign Byte_mul2 = Byte[7] ? (ByteSL ^ 8'h1b) : ByteSL;
    assign Byte_mul3 = Byte_mul2 ^ Byte;
endmodule


//=============================================================================
// SECTION: MixColumns: Column Processor
// SOURCE: RTL/AES-CTR/AES_encryption/AES_round/MixColumns/MixCol.sv
//=============================================================================
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


//=============================================================================
// SECTION: MixColumns: 128-bit Matrix Processor
// SOURCE: RTL/AES-CTR/AES_encryption/AES_round/MixColumns/MixColumns.sv
//=============================================================================
module MixColumns(
    input logic [127:0] MixColumns_in,
    output logic [127:0] MixColumns_out);
    MixCol Col0 (.Col_in(MixColumns_in[127:96]), .Col_out(MixColumns_out[127:96]));
    MixCol Col1 (.Col_in(MixColumns_in[95:64]), .Col_out(MixColumns_out[95:64]));
    MixCol Col2 (.Col_in(MixColumns_in[63:32]), .Col_out(MixColumns_out[63:32]));
    MixCol Col3 (.Col_in(MixColumns_in[31:0]), .Col_out(MixColumns_out[31:0]));
endmodule


//=============================================================================
// SECTION: ShiftRows: 128-bit Row Permutation
// SOURCE: RTL/AES-CTR/AES_encryption/AES_round/ShiftRows.sv
//=============================================================================
module ShiftRows( 
    input logic [127:0] ShiftRows_in,
    output logic [127:0] ShiftRows_out);
    // row 0
    assign ShiftRows_out[127:120] = ShiftRows_in[127:120] ;
    assign ShiftRows_out[95:88] = ShiftRows_in[95:88] ;
    assign ShiftRows_out[63:56] = ShiftRows_in[63:56] ;
    assign ShiftRows_out[31:24] = ShiftRows_in[31:24] ;
    // row 1
    assign ShiftRows_out[119:112] = ShiftRows_in[87:80] ;
    assign ShiftRows_out[87:80] = ShiftRows_in[55:48] ;
    assign ShiftRows_out[55:48] = ShiftRows_in[23:16] ;
    assign ShiftRows_out[23:16] = ShiftRows_in[119:112] ;
    // row 2
    assign ShiftRows_out[111:104] = ShiftRows_in[47:40] ;
    assign ShiftRows_out[79:72] = ShiftRows_in[15:8] ;
    assign ShiftRows_out[47:40] = ShiftRows_in[111:104] ;
    assign ShiftRows_out[15:8] = ShiftRows_in[79:72] ;
    //row 3
    assign ShiftRows_out[103:96] = ShiftRows_in[7:0] ;
    assign ShiftRows_out[71:64] = ShiftRows_in[103:96] ;
    assign ShiftRows_out[39:32] = ShiftRows_in[71:64] ;
    assign ShiftRows_out[7:0] = ShiftRows_in[39:32] ;
endmodule


//=============================================================================
// SECTION: SubBytes: 16 Parallel S-Boxes
// SOURCE: RTL/AES-CTR/AES_encryption/AES_round/SubBytes.sv
//=============================================================================
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


//=============================================================================
// SECTION: AddRoundKeys: Bitwise XOR
// SOURCE: RTL/AES-CTR/AES_encryption/AES_round/AddRoundKeys.sv
//=============================================================================
module AddRoundKeys(
    input logic  [127:0] RoundKey, AddRoundKeys_in,
    output logic [127:0] AddRoundKeys_out);
    assign AddRoundKeys_out = AddRoundKeys_in ^ RoundKey;
endmodule


//=============================================================================
// SECTION: Pipeline Round Register
// SOURCE: RTL/AES-CTR/AES_encryption/AES_round/AES_register.sv
//=============================================================================
module AES_register(
    input logic clk,rst_n,
    input logic [1:0] data_type_in,
    input logic [127:0] data_in,
    output logic [127:0] data_out,
    output logic [1:0] data_type_out,
    output logic valid);
    
    assign valid = (data_type_in!= 2'b0);
    
    always_ff @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            data_out <= 128'b0;
            data_type_out <= 2'b0;
        end    
        else begin
            data_type_out <= data_type_in;
            if (valid)
                data_out <= data_in;
        end
    end
endmodule


//=============================================================================
// SECTION: AES First Round (Pre-Round AddRoundKeys)
// SOURCE: RTL/AES-CTR/AES_encryption/AES_first_round.sv
//=============================================================================
module AES_first_round(
    input logic clk,rst_n,
    input logic [1:0] data_type_in,
    input logic [127:0] data_in,
    input logic [127:0] round_key,
    output logic [127:0] data_out,
    output logic [1:0] data_type_out,
    output logic valid);
    
    logic [127:0] register_out;
    AES_register AES_reg (.clk(clk),.rst_n(rst_n),.data_type_in(data_type_in),.data_in(data_in),
                    .data_out(register_out),.data_type_out(data_type_out),.valid(valid));
    AddRoundKeys ARK (.RoundKey(round_key),.AddRoundKeys_in(register_out),
                    .AddRoundKeys_out(data_out));
endmodule


//=============================================================================
// SECTION: AES Standard Pipelined Round
// SOURCE: RTL/AES-CTR/AES_encryption/AES_round.sv
//=============================================================================
module AES_round(
    input logic clk,rst_n,
    input logic [1:0] data_type_in,
    input logic [127:0] data_in,
    input logic [127:0] round_key,
    output logic [127:0] data_out,
    output logic [1:0] data_type_out,
    output logic valid);
    
    logic [127:0] register_out;
    AES_register AES_reg (.clk(clk),.rst_n(rst_n),.data_type_in(data_type_in),.data_in(data_in),
                    .data_out(register_out),.data_type_out(data_type_out),.valid(valid));
    logic [127:0] subbyte_out;
    SubBytes SB (.SubBytes_in(register_out),.SubBytes_out(subbyte_out));
    logic [127:0] shiftrow_out;
    ShiftRows SR (.ShiftRows_in(subbyte_out),.ShiftRows_out(shiftrow_out));
    logic [127:0] mixcolumn_out;
    MixColumns MC (.MixColumns_in(shiftrow_out),.MixColumns_out(mixcolumn_out));
    AddRoundKeys ARK (.RoundKey(round_key),.AddRoundKeys_in(mixcolumn_out),
                    .AddRoundKeys_out(data_out));
endmodule


//=============================================================================
// SECTION: AES Last Round (No MixColumns)
// SOURCE: RTL/AES-CTR/AES_encryption/AES_last_round.sv
//=============================================================================
module AES_last_round(
    input logic clk,rst_n,
    input logic [1:0] data_type_in,
    input logic [127:0] data_in,
    input logic [127:0] round_key,
    output logic [127:0] data_out,
    output logic [1:0] data_type_out,
    output logic valid);

    logic [127:0] register_out;
    AES_register AES_reg (.clk(clk),.rst_n(rst_n),.data_type_in(data_type_in),.data_in(data_in),
                    .data_out(register_out),.data_type_out(data_type_out),.valid(valid));
    logic [127:0] subbyte_out;
    SubBytes SB (.SubBytes_in(register_out),.SubBytes_out(subbyte_out));
    logic [127:0] shiftrow_out;
    ShiftRows SR (.ShiftRows_in(subbyte_out),.ShiftRows_out(shiftrow_out));
    AddRoundKeys ARK (.RoundKey(round_key),.AddRoundKeys_in(shiftrow_out),
                    .AddRoundKeys_out(data_out));
endmodule


//=============================================================================
// SECTION: AES-256 14-Round Pipelined Encryption Core
// SOURCE: RTL/AES_256_CTR/AES_256_encryption.sv
//=============================================================================
module AES_256_encryption(
    input logic clk,rst_n,
    input logic [127:0] data_in,
    input logic [127:0] round_key [0:14],
    input logic [1:0] data_type_in,
    output logic [127:0] data_out,
    output logic [1:0] data_type_out,
    output logic data_req, AES_finish);
    
    logic [1:0] data_type [0:14];
    logic [127:0] data [0:14];
    logic valid [0:15];
    // first round
    AES_first_round first_round (.clk(clk),.rst_n(rst_n),.data_type_in(data_type_in),
                                .data_in(data_in),.round_key(round_key[0]),
                                .data_out(data[0]),.data_type_out(data_type[0]),
                                .valid(valid[0]));
    // AES rounds
    AES_round R1 (.clk(clk),.rst_n(rst_n),.data_type_in(data_type[0]),.data_in(data[0]),
                .round_key(round_key[1]),.data_out(data[1]),.data_type_out(data_type[1]),
                .valid(valid[1]));
    
    AES_round R2 (.clk(clk),.rst_n(rst_n),.data_type_in(data_type[1]),.data_in(data[1]),
                .round_key(round_key[2]),.data_out(data[2]),.data_type_out(data_type[2]),
                .valid(valid[2]));
    
    AES_round R3 (.clk(clk),.rst_n(rst_n),.data_type_in(data_type[2]),.data_in(data[2]),
                .round_key(round_key[3]),.data_out(data[3]),.data_type_out(data_type[3]),
                .valid(valid[3]));
    
    AES_round R4 (.clk(clk),.rst_n(rst_n),.data_type_in(data_type[3]),.data_in(data[3]),
                .round_key(round_key[4]),.data_out(data[4]),.data_type_out(data_type[4]),
                .valid(valid[4]));
    
    AES_round R5 (.clk(clk),.rst_n(rst_n),.data_type_in(data_type[4]),.data_in(data[4]),
                .round_key(round_key[5]),.data_out(data[5]),.data_type_out(data_type[5]),
                .valid(valid[5]));
    
    AES_round R6 (.clk(clk),.rst_n(rst_n),.data_type_in(data_type[5]),.data_in(data[5]),
                .round_key(round_key[6]),.data_out(data[6]),.data_type_out(data_type[6]),
                .valid(valid[6]));
    
    AES_round R7 (.clk(clk),.rst_n(rst_n),.data_type_in(data_type[6]),.data_in(data[6]),
                .round_key(round_key[7]),.data_out(data[7]),.data_type_out(data_type[7]),
                .valid(valid[7]));
    
    AES_round R8 (.clk(clk),.rst_n(rst_n),.data_type_in(data_type[7]),.data_in(data[7]),
                .round_key(round_key[8]),.data_out(data[8]),.data_type_out(data_type[8]),
                .valid(valid[8]));
    
    AES_round R9 (.clk(clk),.rst_n(rst_n),.data_type_in(data_type[8]),.data_in(data[8]),
                .round_key(round_key[9]),.data_out(data[9]),.data_type_out(data_type[9]),
                .valid(valid[9]));
    
    AES_round R10 (.clk(clk),.rst_n(rst_n),.data_type_in(data_type[9]),.data_in(data[9]),
                .round_key(round_key[10]),.data_out(data[10]),.data_type_out(data_type[10]),
                .valid(valid[10]));
    AES_round R11 (.clk(clk),.rst_n(rst_n),.data_type_in(data_type[10]),.data_in(data[10]),
                .round_key(round_key[11]),.data_out(data[11]),.data_type_out(data_type[11]),
                .valid(valid[11]));
    
    AES_round R12 (.clk(clk),.rst_n(rst_n),.data_type_in(data_type[11]),.data_in(data[11]),
                .round_key(round_key[12]),.data_out(data[12]),.data_type_out(data_type[12]),
                .valid(valid[12]));
    
    AES_round R13 (.clk(clk),.rst_n(rst_n),.data_type_in(data_type[12]),.data_in(data[12]),
                .round_key(round_key[13]),.data_out(data[13]),.data_type_out(data_type[13]),
                .valid(valid[13]));
    
    //last round
    AES_last_round last_round (.clk(clk),.rst_n(rst_n),.data_type_in(data_type[13]),
                            .data_in(data[13]),.round_key(round_key[14]),.data_out(data[14]),
                            .data_type_out(data_type[14]),.valid(valid[14]));
    // last register
    AES_register reg11 (.clk(clk),.rst_n(rst_n),.data_type_in(data_type[14]),
                        .data_in(data[14]),.data_out(data_out),.data_type_out(data_type_out),
                        .valid(valid[15]));
    assign AES_finish = ~(valid[0]|valid[1]|valid[2]|valid[3]|valid[4]|valid[5]|valid[6]
                        |valid[7]|valid[8]|valid[9]|valid[10]|valid[11]|valid[12]|valid[13]
                        |valid[14]|valid[15]);
    assign data_req = (data_type[14] == 2'b10);
endmodule


//=============================================================================
// SECTION: FIFO Write Pointer
// SOURCE: RTL/AES-CTR/FIFO/Write_pointer.sv
//=============================================================================
module Write_pointer #(
    parameter int PTR_WIDTH = 4)
    (input logic clk, rst_n, w_en,
    output logic [PTR_WIDTH-1:0] w_ptr);
    
    always_ff @ (posedge clk or negedge rst_n) begin
        if(!rst_n)
            w_ptr <= '0;
        else if (w_en) 
            w_ptr <= w_ptr+1'b1;
    end
endmodule


//=============================================================================
// SECTION: FIFO Read Pointer
// SOURCE: RTL/AES-CTR/FIFO/Read_pointer.sv
//=============================================================================
module Read_pointer#(
    parameter int PTR_WIDTH = 4)
    (input logic clk, rst_n,r_en,
    output logic [PTR_WIDTH-1:0] r_ptr);
    always_ff @(posedge clk or negedge rst_n) begin
        if(!rst_n) 
            r_ptr <= '0;
        else if(r_en)
            r_ptr <= r_ptr + 1'b1;
    end
endmodule


//=============================================================================
// SECTION: FIFO Dual-Port Synchronous SRAM
// SOURCE: RTL/AES-CTR/FIFO/FIFO_memory.sv
//=============================================================================
module FIFO_memory#(
    parameter int DATA_SIZE = 128,
    parameter int DEPTH =16,
    parameter int PTR_WIDTH = $clog2(DEPTH)
    )(input logic clk,
    input logic r_en, w_en,
    input logic [PTR_WIDTH-1:0] r_ptr, w_ptr,
    input logic [DATA_SIZE-1:0] data_in,
    output logic [DATA_SIZE-1:0] data_out);
    logic [DATA_SIZE-1:0] memory_array [0:DEPTH-1];
    always_ff @(posedge clk ) begin
        if (w_en)
            memory_array[w_ptr] <= data_in;
        if (r_en)
            data_out <= memory_array[r_ptr];
    end
endmodule


//=============================================================================
// SECTION: FIFO Synchronous Queue Top
// SOURCE: RTL/AES-CTR/FIFO/FIFO.sv
//=============================================================================
module FIFO#(
    parameter int DATA_SIZE = 128,
    parameter int DEPTH = 16,
    parameter int PTR_WIDTH = $clog2(DEPTH)
    )(
    input logic clk, rst_n,
    input logic [DATA_SIZE-1:0] data_in,
    input logic r_en, w_en,
    output logic [DATA_SIZE-1 :0] data_out);
    
    logic [PTR_WIDTH-1:0] w_ptr, r_ptr;
    Write_pointer#(.PTR_WIDTH(PTR_WIDTH)) W_p
                    (.clk(clk),.rst_n(rst_n),.w_en(w_en),.w_ptr(w_ptr));
    Read_pointer #(.PTR_WIDTH(PTR_WIDTH)) R_p 
                    (.clk(clk),.rst_n(rst_n),.r_en(r_en),.r_ptr(r_ptr));
    FIFO_memory #(.DATA_SIZE(DATA_SIZE),.DEPTH(DEPTH),.PTR_WIDTH(PTR_WIDTH)) F_mem
                        (.clk(clk),.r_en(r_en),.w_en(w_en),
                        .r_ptr(r_ptr), .w_ptr(w_ptr), .data_in(data_in),.data_out(data_out));
endmodule


//=============================================================================
// SECTION: 32-bit CTR Counter
// SOURCE: RTL/AES-CTR/counter_generator/CTR_counter.sv
//=============================================================================
module CTR_counter
(   input logic clk, finish_reset,
    input logic counter_en,
    output logic CTR_counter_overflow,
    output logic [31:0] CTR_counter
);
    
    always_ff @( posedge clk or posedge finish_reset) begin
        if(finish_reset)
            CTR_counter <= 32'b0;
        else begin
            if(!CTR_counter_overflow&&counter_en)
                CTR_counter <= CTR_counter+1;
        end
    end
    assign CTR_counter_overflow = (CTR_counter == 32'hff_ff_ff_ff);
endmodule


//=============================================================================
// SECTION: 96-bit IV Latch Register
// SOURCE: RTL/AES-CTR/counter_generator/IV_register.sv
//=============================================================================
module IV_register(
    input logic clk, finish_reset,
    input logic load_IV,
    input logic [95:0] IV,
    output logic IV_loaded,
    output logic [95:0] IV_out
);

    always_ff @(posedge clk or posedge finish_reset) begin
        if(finish_reset) begin
            IV_loaded <= 1'b0;
            IV_out <= 96'b0;
        end
        else begin
            if(load_IV) begin
                IV_out <= IV;
                IV_loaded <= 1'b1;
            end
        end
    end
endmodule


//=============================================================================
// SECTION: 128-bit Counter Block Formatter
// SOURCE: RTL/AES-CTR/counter_generator/counter_block_generator.sv
//=============================================================================
module counter_block_generator(
    input logic [31:0] CTR_counter,
    input logic [95:0] IV_out,
    output logic [127:0] counter_block);
    
    assign counter_block = {IV_out,CTR_counter+32'b1};
endmodule


//=============================================================================
// SECTION: J0 Pre-Counter Block Register
// SOURCE: RTL/AES-CTR/counter_generator/J0_register.sv
//=============================================================================
module J0_register(
    input logic clk, finish_reset,
    input logic [31:0] CTR_counter,
    input logic [127:0] counter_block,
    output logic [127:0] J0);
    
    always @(posedge clk or posedge finish_reset) begin
        if(finish_reset)
            J0 <= 128'b0;
        else begin
            if(CTR_counter == 32'b0)
                J0 <= counter_block;
        end
    end
endmodule


//=============================================================================
// SECTION: Block Type Stream Controller
// SOURCE: RTL/AES-CTR/counter_generator/type_generator.sv
//=============================================================================
module type_generator(
    input logic clk, rst_n,
    input logic load_key,load_data,
    input logic gen_J0,
    output logic [1:0] data_type
    );
    
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n)
            data_type<=  2'b0;
        else begin
            if(load_key)
                data_type <= 2'b01;
            else begin
                if(load_data)
                    data_type <= 2'b10;
                else begin
                    if(gen_J0)
                        data_type <= 2'b11;
                    else
                        data_type <= 2'b00;
                end
            end
        end
    end
endmodule


//=============================================================================
// SECTION: Counter Multiplexer Output Unit
// SOURCE: RTL/AES-CTR/counter_generator/output_unit.sv
//=============================================================================
module output_unit(
    input logic [1:0] data_type,
    input logic [127:0] counter_block,
    input logic [127:0] J0,
    output logic [127:0] data_out
    );
    
    always_comb begin
        case(data_type)
            2'b01: data_out = 128'b0;
            2'b10: data_out = counter_block;
            2'b11: data_out = J0;
            default: data_out = 128'b0;
        endcase
    end
endmodule


//=============================================================================
// SECTION: Counter Generator Top Unit
// SOURCE: RTL/AES-CTR/counter_generator/counter_generator.sv
//=============================================================================
module counter_generator(
    input logic clk,rst_n,
    input logic finish_reset,
    input logic load_key, load_data, 
    input logic gen_J0, load_IV,
    input logic [95:0] IV,
    output logic CTR_counter_overflow, IV_loaded, 
    output logic [1:0] data_type,
    output logic [127:0] data_out
    );

    logic [31:0] CTR_counter;
    CTR_counter coun (.clk(clk),.finish_reset(finish_reset),.counter_en(load_data),
                        .CTR_counter_overflow(CTR_counter_overflow),.CTR_counter(CTR_counter));
    logic [95:0] IV_out;
    IV_register IV_reg (.clk(clk),.load_IV(load_IV),.finish_reset(finish_reset),
                        .IV(IV),.IV_loaded(IV_loaded),.IV_out(IV_out));
    logic [127:0] counter_block;
    counter_block_generator CBG (.CTR_counter(CTR_counter),.IV_out(IV_out),
                                .counter_block(counter_block));
    logic [127:0] J0;
    J0_register J0_reg (.clk(clk),.finish_reset(finish_reset),.counter_block(counter_block),
                        .CTR_counter(CTR_counter),.J0(J0));
    type_generator gentype (.clk(clk),.rst_n(rst_n),.load_key(load_key),.load_data(load_data),
                            .gen_J0(gen_J0),.data_type(data_type));
    output_unit ou (.data_type(data_type),.counter_block(counter_block),.J0(J0),
                    .data_out(data_out));
endmodule


//=============================================================================
// SECTION: AES-256-CTR Datapath Top
// SOURCE: RTL/AES_256_CTR/AES_256_CTR.sv
//=============================================================================
module AES_256_CTR(
    input logic clk, rst_n, finish_reset,
    input logic load_key, load_data, load_IV,
    input logic [127:0] data_in,
    input logic [255:0] cipher_key,
    input logic [95:0] IV,
    input logic expansion_en, mode,
    input logic data_in_last,
    output logic AES_finish, CTR_counter_overflow,
    output logic IV_loaded, expansion_finish,
    output logic [127:0] H, E, data_out, CT,
    output logic data_out_last,
    output logic H_valid, E_valid, data_valid,
    output logic CT_last, CT_valid);
    
    logic gen_J0;
    always_ff @(posedge clk or negedge rst_n) begin
        if(!rst_n)
            gen_J0 <= 1'b0;
        else begin
            gen_J0 <= data_in_last;
        end
    end
    
    logic data_req;
    logic [128:0] FIFO_data_in;
    logic [128:0] FIFO_data;
    assign FIFO_data_in = {data_in_last,data_in};
    FIFO #(.DATA_SIZE(129),.DEPTH(16)) fifo 
            (.clk(clk),.rst_n(rst_n),.data_in(FIFO_data_in),.w_en(load_data),.r_en(data_req),
            .data_out(FIFO_data));
    logic [127:0] round_key [0:14];
    KeyExpansion_256 key_expan (.clk(clk),.rst_n(rst_n),.expansion_en(expansion_en),
                            .cipher_key(cipher_key),.round_key(round_key),
                            .expansion_finish(expansion_finish));
    logic [127:0] AES_data_in;
    logic [1:0] data_type_in;
    counter_generator count_gen (.clk(clk),.rst_n(rst_n),.finish_reset(finish_reset),
                                .gen_J0(gen_J0),.load_key(load_key),.load_data(load_data),
                                .load_IV(load_IV),.IV(IV),.data_type(data_type_in),
                                .data_out(AES_data_in),.IV_loaded(IV_loaded),
                                .CTR_counter_overflow(CTR_counter_overflow));
    logic [127:0] AES_data_out;
    logic [1:0] data_type_out;
    AES_256_encryption AES (.clk(clk),.rst_n(rst_n),.data_in(AES_data_in),.round_key(round_key),
                        .data_type_in(data_type_in),.data_out(AES_data_out),
                        .data_type_out(data_type_out),.data_req(data_req),
                        .AES_finish(AES_finish));
    logic [127:0] keystream;
    logic keystream_valid;
    always_comb begin
        H = 128'b0;
        E = 128'b0;
        keystream = 128'b0;
        H_valid = 1'b0;
        keystream_valid = 1'b0;
        E_valid = 1'b0;
        case(data_type_out)
            2'b01: begin
                H = AES_data_out;
                H_valid = 1'b1;
            end
            2'b10: begin
                keystream = AES_data_out;
                keystream_valid = 1'b1;
            end
            2'b11: begin
                E = AES_data_out;
                E_valid = 1'b1;
            end
            default: begin
                H                = 128'b0;
                E                = 128'b0;
                keystream        = 128'b0;
                H_valid          = 1'b0;
                keystream_valid  = 1'b0;
                E_valid          = 1'b0;
            end
        endcase
    end
    
    always_ff @(posedge clk or negedge rst_n) begin: outReg
        if(!rst_n) begin
            data_valid    <= 1'b0;
            data_out_last <= 1'b0;
            data_out      <= 128'b0;
        end
        else begin
            data_valid <= keystream_valid;
            data_out_last <= FIFO_data[128] & keystream_valid;
            if (keystream_valid)
                data_out <= FIFO_data[127:0] ^ keystream;
            else
                data_out <= 128'b0;
        end
    end

    assign CT = mode? FIFO_data [127:0] : (FIFO_data [127:0] ^ keystream); 
    assign CT_valid = keystream_valid;
    assign CT_last  = keystream_valid & FIFO_data[128];
endmodule


//=============================================================================
// SECTION: Karatsuba GF(2^128) Multiplier & Reduction Block
// SOURCE: RTL/GCM-GHASH/GF128bitMultiply.sv
//=============================================================================
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


//=============================================================================
// SECTION: 64-bit Length Block Counter for AAD and CT
// SOURCE: RTL/GCM-GHASH/LengthBlockCounter.sv
//=============================================================================
module LengthBlockCounter (
    input logic clk,
    input logic finish_reset,
    input logic load_AAD,
    input logic load_CT,
    input logic CT_last,

    output logic         length_block_valid,
    output logic [127:0] length_block
);
  logic [60:0] AAD_cnt;
  logic [60:0] CT_cnt;

  assign length_block = {AAD_cnt, 3'd0, CT_cnt, 3'd0};

  always_ff @(posedge clk, posedge finish_reset) begin : AADCounter
    if (finish_reset) begin
      AAD_cnt <= 61'd0;
    end else if (load_AAD) begin
      AAD_cnt <= AAD_cnt + 61'd16;
    end
  end

  always_ff @(posedge clk, posedge finish_reset) begin : CTCounter
    if (finish_reset) begin
      CT_cnt <= 61'd0;
    end else if (load_CT) begin
      CT_cnt <= CT_cnt + 61'd16;
    end
  end

  always_ff @(posedge clk, posedge finish_reset) begin : LengthBlockValidReg
    if (finish_reset) begin
      length_block_valid <= 1'b0;
    end else begin
      length_block_valid <= CT_last;
    end
  end
endmodule


//=============================================================================
// SECTION: GHASH Authentication Accumulator Core
// SOURCE: RTL/GCM-GHASH/GHASH.sv
//=============================================================================
module GHASH (
    input logic         clk,
    input logic         finish_reset,
    input logic         load_AAD,
    input logic         load_CT,
    input logic         length_block_valid,
    input logic [127:0] AAD,
    input logic [127:0] CT,
    input logic [127:0] length_block,
    input logic [127:0] H_reg,

    output logic         ghash_finish,
    output logic [127:0] ghash_out
);
  logic         ghash_en;
  logic [127:0] data_in;
  logic [127:0] multiply_in;
  logic [127:0] multiply_out;

  always_comb begin : DataInputMUX
    if (load_AAD) begin
      data_in = AAD;
    end else if (load_CT) begin
      data_in = CT;
    end else if (length_block_valid) begin
      data_in = length_block;
    end else begin
      data_in = 128'h0;
    end
  end

  assign ghash_en = (load_AAD ^ load_CT ^ length_block_valid) & !ghash_finish;
  assign multiply_in = ghash_out ^ data_in;

  GF128bitMultiply GFMultiply1 (
      .H_reg(H_reg),
      .data_in(multiply_in),
      .data_out(multiply_out)
  );

  always_ff @(posedge clk, posedge finish_reset) begin : GHASHReg
    if (finish_reset) begin
      ghash_out <= 128'h0;
    end else if (ghash_en) begin
      ghash_out <= multiply_out;
    end
  end

  always_ff @(posedge clk, posedge finish_reset) begin : GHASHfinishReg
    if (finish_reset) begin
      ghash_finish <= 1'b0;
    end else begin
      if (length_block_valid) begin
        ghash_finish <= 1'b1;
      end
    end
  end
endmodule


//=============================================================================
// SECTION: GCM Tag Generation & Decryption Authenticator
// SOURCE: RTL/GCM-GHASH/TagProcessing.sv
//=============================================================================
module TagProcessing (
    input logic         clk,
    input logic         rst_n,
    input logic         finish_reset,
    input logic         load_key,
    input logic         mode,
    input logic [127:0] AAD,
    input logic [127:0] CT,
    input logic [127:0] tag_ref,
    input logic [127:0] H,
    input logic [127:0] E,
    input logic         load_AAD,
    input logic         load_CT,
    input logic         H_valid,
    input logic         E_valid,
    input logic         load_tag_ref,
    input logic         CT_last,

    output logic         H_loaded,
    output logic         tag_ref_loaded,
    output logic [127:0] tag,
    output logic         tag_process_valid,
    output logic         verify_pass
);
  logic         H_reset;
  logic         length_block_valid;
  logic         E_loaded;
  logic         ghash_finish;
  logic [127:0] H_reg;
  logic [127:0] E_reg;
  logic [127:0] tag_ref_reg;
  logic [127:0] length_block;
  logic [127:0] ghash_out;

  assign H_reset = ~rst_n | load_key;
  assign verify_pass = mode && tag_process_valid && (tag == tag_ref_reg);

  always_ff @(posedge clk, posedge finish_reset) begin : TagReg
    if (finish_reset) begin
      tag <= 128'h0;
    end else begin
      if (ghash_finish && E_loaded) begin
        tag <= ghash_out ^ E_reg;
      end else begin
        tag <= 128'h0;
      end
    end
  end

  always_ff @(posedge clk, posedge finish_reset) begin : TagProcessValidReg
    if (finish_reset) begin
      tag_process_valid <= 1'b0;
    end else begin
      tag_process_valid <= ghash_finish & E_loaded;
    end
  end

  always_ff @(posedge clk, posedge H_reset) begin : HLoadedReg
    if (H_reset) begin
      H_loaded <= 1'b0;
    end else if (H_valid && !H_loaded) begin
      H_loaded <= 1'b1;
    end
  end

  always_ff @(posedge clk, posedge H_reset) begin : HKeyReg
    if (H_reset) begin
      H_reg <= 128'h0;
    end else if (H_valid && !H_loaded) begin
      H_reg <= H;
    end
  end

  always_ff @(posedge clk, posedge finish_reset) begin : ELoadedReg
    if (finish_reset) begin
      E_loaded <= 1'b0;
    end else if (E_valid && !E_loaded) begin
      E_loaded <= 1'b1;
    end
  end

  always_ff @(posedge clk, posedge finish_reset) begin : EKeyReg
    if (finish_reset) begin
      E_reg <= 128'h0;
    end else if (E_valid && !E_loaded) begin
      E_reg <= E;
    end
  end

  always_ff @(posedge clk, posedge finish_reset) begin : TagRefLoadedReg
    if (finish_reset) begin
      tag_ref_loaded <= 1'b0;
    end else if (load_tag_ref && !tag_ref_loaded) begin
      tag_ref_loaded <= 1'b1;
    end
  end

  always_ff @(posedge clk, posedge finish_reset) begin : TagReferenceReg
    if (finish_reset) begin
      tag_ref_reg <= 128'h0;
    end else if (load_tag_ref && !tag_ref_loaded) begin
      tag_ref_reg <= tag_ref;
    end
  end

  LengthBlockCounter LengthCounter (
      .clk               (clk),
      .finish_reset      (finish_reset),
      .load_AAD          (load_AAD),
      .load_CT           (load_CT),
      .CT_last           (CT_last),
      .length_block_valid(length_block_valid),
      .length_block      (length_block)
  );

  GHASH GHASHCore (
      .clk               (clk),
      .finish_reset      (finish_reset),
      .load_AAD          (load_AAD),
      .load_CT           (load_CT),
      .length_block_valid(length_block_valid),
      .AAD               (AAD),
      .CT                (CT),
      .length_block      (length_block),
      .H_reg             (H_reg),
      .ghash_finish      (ghash_finish),
      .ghash_out         (ghash_out)
  );
endmodule


//=============================================================================
// SECTION: Main System FSM Control Unit
// SOURCE: RTL/CU/CU.sv
//=============================================================================
module CU(
    input logic clk, rst_n,
    input logic start, load_key,
    input logic expansion_finish,
    input logic H_loaded, IV_loaded,
    input logic tag_ref_loaded, mode,
    input logic load_AAD, no_AAD, AAD_last,
    input logic load_data, data_in_last,
    input logic process_finish, verify_checked,
    input logic CTR_counter_overflow,
    output logic expansion_en,
    output logic finish,
    output logic key_ready, IV_ready,
    output logic tag_ref_ready,
    output logic AAD_ready, data_ready,
    output logic verify_done
    );
    
    typedef enum logic [3:0] {
        IDLE,
        KEY_EXPANSION,
        WAIT_H_CAL,
        WAIT_TAG_REF,
        WAIT_AAD,
        LOAD_AAD,
        WAIT_DATA,
        LOAD_DATA,
        WAIT_PROCESS_FINISH,
        VERIFY_PASS,
        FINISH
        } state;
    state Current, Next;
    // state register
    always_ff @(posedge clk or negedge rst_n) begin
        if(!rst_n)
            Current <= IDLE;
        else
            Current <= Next;
    end
    // next-stage logic
    always_comb begin
        Next = Current;
        case(Current)
            IDLE: begin
                if(start) begin
                    if(load_key)
                        Next = KEY_EXPANSION;
                    else begin
                        if(mode) 
                            Next = WAIT_TAG_REF;
                        else 
                            Next = WAIT_AAD;
                    end
                end
            end
            KEY_EXPANSION: begin
                if(expansion_finish)
                    Next = WAIT_H_CAL;
            end
            WAIT_H_CAL: begin
                if(H_loaded) begin
                    if(IV_loaded) begin
                        if(!tag_ref_loaded&&mode)
                            Next = WAIT_TAG_REF;
                        else
                            Next = WAIT_AAD;
                    end
                    else 
                        Next = FINISH;
                end
            end
            WAIT_TAG_REF: begin
                if(tag_ref_loaded)
                    Next = WAIT_AAD;
            end
            WAIT_AAD: begin
                if(no_AAD)
                    Next = WAIT_DATA;
                else begin
                    if(load_AAD)
                        Next = LOAD_AAD;
                end
            end
            LOAD_AAD: begin
                if(AAD_last)
                    Next = WAIT_DATA;
            end
            WAIT_DATA: begin
                if(load_data)
                    Next = LOAD_DATA;
            end
            LOAD_DATA: begin
                if(data_in_last)
                    Next = WAIT_PROCESS_FINISH;
            end
            WAIT_PROCESS_FINISH: begin
                if(process_finish) begin
                    if (mode) 
                        Next = VERIFY_PASS;
                    else
                        Next = FINISH;
                end
            end
            VERIFY_PASS: begin
                if(verify_checked)
                    Next = FINISH;
            end
            FINISH: begin
                Next = IDLE;
            end
            default: begin
                Next = IDLE;
            end
        endcase
    end
    // output logic stage
    always_comb begin
        expansion_en  = 1'b0;
        finish        = 1'b0;
        key_ready     = 1'b0;
        IV_ready      = 1'b0;
        tag_ref_ready = 1'b0;
        AAD_ready     = 1'b0;
        data_ready    = 1'b0;
        verify_done   = 1'b0;
        case(Current)
            IDLE: begin
                key_ready = 1'b1;
                if(H_loaded)
                    IV_ready = 1'b1;
            end
            KEY_EXPANSION: begin
                expansion_en = 1'b1;
                if(!IV_loaded)
                    IV_ready = 1'b1;
                if (!tag_ref_loaded&&mode)
                    tag_ref_ready = 1'b1;
            end
            WAIT_H_CAL: begin
                if(!IV_loaded)
                    IV_ready = 1'b1;
                if (!tag_ref_loaded&&mode)
                    tag_ref_ready = 1'b1;
            end
            WAIT_TAG_REF: begin
                if (!tag_ref_loaded&&mode)
                    tag_ref_ready = 1'b1;
            end
            WAIT_AAD: begin
                AAD_ready = 1'b1;
            end
            LOAD_AAD: begin
                AAD_ready = 1'b1;
            end
            WAIT_DATA: begin
                data_ready = 1'b1;
            end
            LOAD_DATA: begin
                if (!CTR_counter_overflow)
                    data_ready = 1'b1;
                else
                    data_ready = 1'b0;
            end
            VERIFY_PASS: begin
                verify_done = 1'b1;
            end
            FINISH: begin
                finish = 1'b1;
            end
            default: begin
                expansion_en  = 1'b0;
                finish        = 1'b0;
                key_ready     = 1'b0;
                IV_ready      = 1'b0;
                tag_ref_ready = 1'b0;
                AAD_ready     = 1'b0;
                data_ready    = 1'b0;
                verify_done   = 1'b0;
            end
        endcase
    end
endmodule


//=============================================================================
// SECTION: AES-256-GCM Integrated Accelerator Core
// SOURCE: RTL/AES_256_GCM.sv
//=============================================================================
module AES_256_GCM(
    input logic clk, rst_n,
    input logic load_key, load_IV,
    input logic mode, load_tag_ref,
    input logic load_AAD, no_AAD, AAD_last,
    input logic load_data, data_in_last,
    input logic verify_checked,
    input logic [255:0] cipher_key,
    input logic [127:0] tag_ref,
    input logic [127:0] AAD, data_in,
    input logic [95:0] IV,
    output logic tag_valid, verify_pass,
    output logic CTR_counter_overflow,
    output logic data_valid, data_out_last,
    output logic finish, tag_ref_ready,
    output logic key_ready, IV_ready,
    output logic AAD_ready, data_ready,
    output logic [127:0] tag, data_out,
    output logic verify_done
    );

    logic start, finish_reset;
    assign start = load_key | load_IV;
    assign finish_reset = (~rst_n) | finish;
    
    logic expansion_en, expansion_finish;
    logic AES_finish, IV_loaded;
    logic [127:0] H, E, CT;
    logic H_valid, E_valid, CT_valid;
    logic CT_last;
    
    AES_256_CTR AES (.clk(clk),.rst_n(rst_n),.finish_reset(finish_reset),.load_key(load_key),
                .load_IV(load_IV),.load_data(load_data),.cipher_key(cipher_key),
                .data_in(data_in),.IV(IV),.expansion_en(expansion_en),.mode(mode),
                .data_in_last(data_in_last),.AES_finish(AES_finish),.IV_loaded(IV_loaded),
                .CTR_counter_overflow(CTR_counter_overflow),.expansion_finish(expansion_finish),
                .H(H),.E(E),.data_out(data_out),.CT(CT),.data_out_last(data_out_last),
                .H_valid(H_valid),.E_valid(E_valid),.data_valid(data_valid),.CT_valid(CT_valid),
                .CT_last(CT_last));
    
    logic H_loaded, tag_ref_loaded, tag_process_finish;
    
    TagProcessing tag_pro (.clk(clk),.rst_n(rst_n),.finish_reset(finish_reset),
                            .load_key(load_key),.mode(mode),.AAD(AAD),.CT(CT),
                            .tag_ref(tag_ref),.H(H),.E(E),.load_AAD(load_AAD),
                            .load_CT(CT_valid),.H_valid(H_valid),.E_valid(E_valid),
                            .load_tag_ref(load_tag_ref),.CT_last(CT_last),.H_loaded(H_loaded),
                            .tag_ref_loaded(tag_ref_loaded),.tag(tag),
                            .tag_process_valid(tag_process_finish),.verify_pass(verify_pass));
    
    logic process_finish;
    assign process_finish = AES_finish & tag_process_finish;
    CU cu (.clk(clk),.rst_n(rst_n),.start(start),.load_key(load_key),
            .expansion_finish(expansion_finish),.H_loaded(H_loaded),.IV_loaded(IV_loaded),
            .tag_ref_loaded(tag_ref_loaded),.mode(mode),.load_AAD(load_AAD),.no_AAD(no_AAD),
            .AAD_last(AAD_last),.load_data(load_data),.data_in_last(data_in_last),
            .process_finish(process_finish),.verify_checked(verify_checked),
            .expansion_en(expansion_en),.finish(finish),.key_ready(key_ready),
            .IV_ready(IV_ready),.tag_ref_ready(tag_ref_ready),.AAD_ready(AAD_ready),
            .data_ready(data_ready),.verify_done(verify_done),
            .CTR_counter_overflow(CTR_counter_overflow));
    
    assign tag_valid = (~mode) & tag_process_finish;
endmodule


//=============================================================================
// SECTION: 8N1 UART Receiver with 2-FF Metastability Filter
// SOURCE: uart_integration/common/uart_rx.sv
//=============================================================================
//=============================================================================
// Module: uart_rx.sv
// Directory: uart_integration/common/
// Description: Shared, fully synthesizable, parameterized 8N1 UART Receiver
//              with double-register metastability synchronization and 
//              midpoint bit sampling.
//
// Parameters:
//   CLK_FREQ_HZ : System clock frequency in Hz (default: 100_000_000)
//   BAUD_RATE   : Target baud rate in bps      (default: 115_200)
//=============================================================================


module uart_rx #(
    parameter int CLK_FREQ_HZ = 100_000_000,
    parameter int BAUD_RATE   = 115_200
)(
    input  logic       clk,
    input  logic       rst_n,
    input  logic       rx,
    output logic [7:0] rx_data,
    output logic       rx_valid
);

    localparam int CLKS_PER_BIT = CLK_FREQ_HZ / BAUD_RATE;
    localparam int CTR_WIDTH    = $clog2(CLKS_PER_BIT + 1);

    typedef enum logic [1:0] {
        RX_IDLE,
        RX_START,
        RX_DATA,
        RX_STOP
    } rx_state_t;

    rx_state_t state;
    logic [CTR_WIDTH-1:0] clk_cnt;
    logic [2:0]           bit_idx;
    logic [7:0]           shift_reg;

    // 2-stage input synchronizer to eliminate metastability
    logic rx_sync_stage1;
    logic rx_sync;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rx_sync_stage1 <= 1'b1;
            rx_sync        <= 1'b1;
        end else begin
            rx_sync_stage1 <= rx;
            rx_sync        <= rx_sync_stage1;
        end
    end

    // UART RX State Machine
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state     <= RX_IDLE;
            clk_cnt   <= '0;
            bit_idx   <= '0;
            shift_reg <= 8'h00;
            rx_data   <= 8'h00;
            rx_valid  <= 1'b0;
        end else begin
            rx_valid <= 1'b0; // Default: 1-clock pulse

            case (state)
                RX_IDLE: begin
                    clk_cnt <= '0;
                    bit_idx <= '0;
                    // Detect falling edge of start bit
                    if (rx_sync == 1'b0) begin
                        state   <= RX_START;
                        clk_cnt <= '0;
                    end
                end

                // Sample in the middle of start bit to confirm validity
                RX_START: begin
                    if (clk_cnt == ((CLKS_PER_BIT - 1) / 2)) begin
                        if (rx_sync == 1'b0) begin
                            // Valid start bit confirmed
                            clk_cnt <= '0;
                            state   <= RX_DATA;
                        end else begin
                            // Glitch / false start bit
                            state   <= RX_IDLE;
                        end
                    end else begin
                        clk_cnt <= clk_cnt + 1'b1;
                    end
                end

                // Receive 8 data bits (LSB first)
                RX_DATA: begin
                    if (clk_cnt == (CLKS_PER_BIT - 1)) begin
                        clk_cnt              <= '0;
                        shift_reg[bit_idx]   <= rx_sync;
                        if (bit_idx == 3'd7) begin
                            bit_idx <= '0;
                            state   <= RX_STOP;
                        end else begin
                            bit_idx <= bit_idx + 1'b1;
                        end
                    end else begin
                        clk_cnt <= clk_cnt + 1'b1;
                    end
                end

                // Sample stop bit (must be high)
                RX_STOP: begin
                    if (clk_cnt == (CLKS_PER_BIT - 1)) begin
                        clk_cnt <= '0;
                        state   <= RX_IDLE;
                        if (rx_sync == 1'b1) begin
                            rx_data  <= shift_reg;
                            rx_valid <= 1'b1;
                        end
                    end else begin
                        clk_cnt <= clk_cnt + 1'b1;
                    end
                end

                default: begin
                    state <= RX_IDLE;
                end
            endcase
        end
    end

endmodule


//=============================================================================
// SECTION: 8N1 UART Transmitter
// SOURCE: uart_integration/common/uart_tx.sv
//=============================================================================
//=============================================================================
// Module: uart_tx.sv
// Directory: uart_integration/common/
// Description: Shared, fully synthesizable, parameterized 8N1 UART Transmitter.
//
// Parameters:
//   CLK_FREQ_HZ : System clock frequency in Hz (default: 100_000_000)
//   BAUD_RATE   : Target baud rate in bps      (default: 115_200)
//=============================================================================


module uart_tx #(
    parameter int CLK_FREQ_HZ = 100_000_000,
    parameter int BAUD_RATE   = 115_200
)(
    input  logic       clk,
    input  logic       rst_n,
    input  logic [7:0] tx_data,
    input  logic       tx_start,
    output logic       tx,
    output logic       tx_busy
);

    localparam int CLKS_PER_BIT = CLK_FREQ_HZ / BAUD_RATE;
    localparam int CTR_WIDTH    = $clog2(CLKS_PER_BIT + 1);

    typedef enum logic [1:0] {
        TX_IDLE,
        TX_START,
        TX_DATA,
        TX_STOP
    } tx_state_t;

    tx_state_t state;
    logic [CTR_WIDTH-1:0] clk_cnt;
    logic [2:0]           bit_idx;
    logic [7:0]           shift_reg;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state     <= TX_IDLE;
            clk_cnt   <= '0;
            bit_idx   <= '0;
            shift_reg <= 8'h00;
            tx        <= 1'b1; // Line idle high
            tx_busy   <= 1'b0;
        end else begin
            case (state)
                TX_IDLE: begin
                    tx      <= 1'b1;
                    clk_cnt <= '0;
                    bit_idx <= '0;
                    if (tx_start) begin
                        shift_reg <= tx_data;
                        tx_busy   <= 1'b1;
                        tx        <= 1'b0; // Start bit
                        state     <= TX_START;
                    end else begin
                        tx_busy <= 1'b0;
                    end
                end

                // Transmit Start Bit (0) for 1 bit period
                TX_START: begin
                    tx <= 1'b0;
                    if (clk_cnt == (CLKS_PER_BIT - 1)) begin
                        clk_cnt <= '0;
                        tx      <= shift_reg[0];
                        state   <= TX_DATA;
                    end else begin
                        clk_cnt <= clk_cnt + 1'b1;
                    end
                end

                // Transmit 8 Data Bits (LSB first)
                TX_DATA: begin
                    tx <= shift_reg[bit_idx];
                    if (clk_cnt == (CLKS_PER_BIT - 1)) begin
                        clk_cnt <= '0;
                        if (bit_idx == 3'd7) begin
                            bit_idx <= '0;
                            tx      <= 1'b1; // Stop bit
                            state   <= TX_STOP;
                        end else begin
                            bit_idx <= bit_idx + 1'b1;
                        end
                    end else begin
                        clk_cnt <= clk_cnt + 1'b1;
                    end
                end

                // Transmit Stop Bit (1) for 1 bit period
                TX_STOP: begin
                    tx <= 1'b1;
                    if (clk_cnt == (CLKS_PER_BIT - 1)) begin
                        clk_cnt <= '0;
                        tx_busy <= 1'b0;
                        state   <= TX_IDLE;
                    end else begin
                        clk_cnt <= clk_cnt + 1'b1;
                    end
                end

                default: begin
                    state <= TX_IDLE;
                end
            endcase
        end
    end

endmodule


//=============================================================================
// SECTION: Command Packet Deserializer & Validator
// SOURCE: uart_integration/common/packet_parser.sv
//=============================================================================
//=============================================================================
// Module: packet_parser.sv
// Directory: uart_integration/common/
// Description: Shared binary packet parser for the AES-GCM framework.
//              Deserializes, validates, and decodes binary UART packets.
//
// Packet Format:
//   Byte 0: CMD
//   Byte 1: LENGTH
//   Byte 2..N+1: PAYLOAD (N bytes)
//
// Supported Commands (protocol_pkg):
//   0x01: CMD_LOAD_KEY       (Length: 16 or 32 bytes)
//   0x02: CMD_LOAD_IV        (Length: 12 bytes = 96 bits)
//   0x03: CMD_LOAD_AAD       (Length: Multiples of 16 bytes)
//   0x04: CMD_LOAD_PLAINTEXT (Length: Multiples of 16 bytes)
//   0x05: CMD_START_ENCRYPT  (Length: 0 bytes)
//=============================================================================


import protocol_pkg::*;

module packet_parser (
    input  logic         clk,
    input  logic         rst_n,

    // Interface from uart_rx
    input  logic [7:0]   rx_data,
    input  logic         rx_valid,

    // Command triggers to wrapper
    output logic         cmd_load_key_done,
    output logic [255:0] key_out,
    output logic [5:0]   key_len_bytes,     // 16 or 32

    output logic         cmd_load_iv_done,
    output logic [95:0]  iv_out,

    // Block streaming to wrapper (for AAD & Plaintext)
    output logic         block_valid,
    output logic         block_is_pt,       // 0: AAD block, 1: Plaintext block
    output logic         block_is_last,     // Last block of the packet
    output logic [127:0] block_data,
    output logic [7:0]   total_blocks,      // Number of 16-byte blocks in packet

    // Overall packet completion / trigger
    output logic         cmd_load_aad_done,
    output logic         cmd_load_pt_done,
    output logic         cmd_start_encrypt_done,

    // Error status
    output logic         err_unknown_cmd,
    output logic         err_len_mismatch,
    output logic [7:0]   err_cmd_code
);

    typedef enum logic [2:0] {
        ST_IDLE,
        ST_GET_LEN,
        ST_CHECK_CMD,
        ST_PAYLOAD,
        ST_FINISH
    } parser_state_t;

    parser_state_t state;

    logic [7:0]   cmd_reg;
    logic [7:0]   len_reg;
    logic [7:0]   byte_cnt;
    logic [3:0]   block_byte_cnt;

    logic [255:0] key_shift;
    logic [95:0]  iv_shift;
    logic [127:0] block_shift;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state                  <= ST_IDLE;
            cmd_reg                <= 8'h00;
            len_reg                <= 8'h00;
            byte_cnt               <= 8'h00;
            block_byte_cnt         <= 4'd0;
            key_shift              <= 256'h0;
            iv_shift               <= 96'h0;
            block_shift            <= 128'h0;

            cmd_load_key_done      <= 1'b0;
            key_out                <= 256'h0;
            key_len_bytes          <= 6'd0;

            cmd_load_iv_done       <= 1'b0;
            iv_out                 <= 96'h0;

            block_valid            <= 1'b0;
            block_is_pt            <= 1'b0;
            block_is_last          <= 1'b0;
            block_data             <= 128'h0;
            total_blocks           <= 8'h00;

            cmd_load_aad_done      <= 1'b0;
            cmd_load_pt_done       <= 1'b0;
            cmd_start_encrypt_done <= 1'b0;

            err_unknown_cmd        <= 1'b0;
            err_len_mismatch       <= 1'b0;
            err_cmd_code           <= 8'h00;
        end else begin
            // Default 1-cycle strobes
            cmd_load_key_done      <= 1'b0;
            cmd_load_iv_done       <= 1'b0;
            block_valid            <= 1'b0;
            cmd_load_aad_done      <= 1'b0;
            cmd_load_pt_done       <= 1'b0;
            cmd_start_encrypt_done <= 1'b0;
            err_unknown_cmd        <= 1'b0;
            err_len_mismatch       <= 1'b0;

            case (state)
                ST_IDLE: begin
                    byte_cnt       <= 8'h00;
                    block_byte_cnt <= 4'd0;
                    if (rx_valid) begin
                        cmd_reg <= rx_data;
                        state   <= ST_GET_LEN;
                    end
                end

                ST_GET_LEN: begin
                    if (rx_valid) begin
                        len_reg  <= rx_data;
                        byte_cnt <= 8'h00;
                        state    <= ST_CHECK_CMD;
                    end
                end

                ST_CHECK_CMD: begin
                    // Validate command and length compatibility
                    case (cmd_reg)
                        CMD_LOAD_KEY: begin // 16 or 32 bytes
                            if (len_reg == 8'd16 || len_reg == 8'd32) begin
                                key_len_bytes <= len_reg[5:0];
                                key_shift     <= 256'h0;
                                state         <= ST_PAYLOAD;
                            end else begin
                                err_len_mismatch <= 1'b1;
                                err_cmd_code     <= cmd_reg;
                                state            <= ST_IDLE;
                            end
                        end

                        CMD_LOAD_IV: begin // 12 bytes = 96 bits
                            if (len_reg == 8'd12) begin
                                iv_shift <= 96'h0;
                                state    <= ST_PAYLOAD;
                            end else begin
                                err_len_mismatch <= 1'b1;
                                err_cmd_code     <= cmd_reg;
                                state            <= ST_IDLE;
                            end
                        end

                        CMD_LOAD_AAD: begin // Multiple of 16 bytes
                            if ((len_reg[3:0] == 4'd0) && (len_reg > 8'd0)) begin
                                total_blocks   <= len_reg >> 4;
                                block_byte_cnt <= 4'd0;
                                state          <= ST_PAYLOAD;
                            end else begin
                                err_len_mismatch <= 1'b1;
                                err_cmd_code     <= cmd_reg;
                                state            <= ST_IDLE;
                            end
                        end

                        CMD_LOAD_PLAINTEXT: begin // Multiple of 16 bytes
                            if ((len_reg[3:0] == 4'd0) && (len_reg > 8'd0)) begin
                                total_blocks   <= len_reg >> 4;
                                block_byte_cnt <= 4'd0;
                                state          <= ST_PAYLOAD;
                            end else begin
                                err_len_mismatch <= 1'b1;
                                err_cmd_code     <= cmd_reg;
                                state            <= ST_IDLE;
                            end
                        end

                        CMD_START_ENCRYPT: begin // Length must be 0
                            if (len_reg == 8'd0) begin
                                cmd_start_encrypt_done <= 1'b1;
                                state                  <= ST_IDLE;
                            end else begin
                                err_len_mismatch <= 1'b1;
                                err_cmd_code     <= cmd_reg;
                                state            <= ST_IDLE;
                            end
                        end

                        default: begin
                            err_unknown_cmd <= 1'b1;
                            err_cmd_code    <= cmd_reg;
                            state           <= ST_IDLE;
                        end
                    endcase
                end

                ST_PAYLOAD: begin
                    if (rx_valid) begin
                        byte_cnt <= byte_cnt + 1'b1;

                        case (cmd_reg)
                            CMD_LOAD_KEY: begin // Accumulate Key
                                key_shift <= {key_shift[247:0], rx_data};
                                if (byte_cnt + 1'b1 == len_reg) begin
                                    if (len_reg == 8'd16) begin
                                        // 128-bit key in lower 128 bits
                                        key_out <= {128'h0, key_shift[119:0], rx_data};
                                    end else begin
                                        // 256-bit key
                                        key_out <= {key_shift[247:0], rx_data};
                                    end
                                    cmd_load_key_done <= 1'b1;
                                    state             <= ST_IDLE;
                                end
                            end

                            CMD_LOAD_IV: begin // Accumulate IV
                                iv_shift <= {iv_shift[87:0], rx_data};
                                if (byte_cnt + 1'b1 == 8'd12) begin
                                    iv_out           <= {iv_shift[87:0], rx_data};
                                    cmd_load_iv_done <= 1'b1;
                                    state            <= ST_IDLE;
                                end
                            end

                            CMD_LOAD_AAD, CMD_LOAD_PLAINTEXT: begin // AAD or Plaintext Blocks
                                block_shift <= {block_shift[119:0], rx_data};
                                if (block_byte_cnt == 4'd15) begin
                                    block_byte_cnt <= 4'd0;
                                    block_valid    <= 1'b1;
                                    block_is_pt    <= (cmd_reg == CMD_LOAD_PLAINTEXT);
                                    block_data     <= {block_shift[119:0], rx_data};
                                    block_is_last  <= (byte_cnt + 1'b1 == len_reg);

                                    if (byte_cnt + 1'b1 == len_reg) begin
                                        if (cmd_reg == CMD_LOAD_AAD) cmd_load_aad_done <= 1'b1;
                                        else                        cmd_load_pt_done  <= 1'b1;
                                        state <= ST_IDLE;
                                    end
                                end else begin
                                    block_byte_cnt <= block_byte_cnt + 1'b1;
                                end
                            end

                            default: begin
                                state <= ST_IDLE;
                            end
                        endcase
                    end
                end

                default: begin
                    state <= ST_IDLE;
                end
            endcase
        end
    end

endmodule


//=============================================================================
// SECTION: Response Packet Serializer & Transmitter
// SOURCE: uart_integration/common/packet_builder.sv
//=============================================================================
//=============================================================================
// Module: packet_builder.sv
// Directory: uart_integration/common/
// Description: Shared response packet builder and serializer for the AES-GCM 
//              framework. Formats response packets (ACKs, Ciphertext, Tag, Errors)
//              and serializes them byte-by-byte through uart_tx.
//
// Response Opcodes (protocol_pkg):
//   0x81: RESP_ACK_KEY        (Length: 0)
//   0x82: RESP_ACK_IV         (Length: 0)
//   0x83: RESP_ACK_AAD        (Length: 0)
//   0x84: RESP_ACK_PLAINTEXT  (Length: 0)
//   0x90: RESP_CIPHERTEXT     (Length: N bytes)
//   0x91: RESP_AUTH_TAG       (Length: 16 bytes)
//   0xE0: RESP_ERR_UNKNOWN    (Length: 1 byte)
//   0xE1: RESP_ERR_LEN        (Length: 1 byte)
//=============================================================================


import protocol_pkg::*;

module packet_builder (
    input  logic         clk,
    input  logic         rst_n,

    // Trigger signals from wrapper
    input  logic         send_ack_key,
    input  logic         send_ack_iv,
    input  logic         send_ack_aad,
    input  logic         send_ack_pt,

    input  logic         send_ciphertext,
    input  logic [7:0]   ct_len_bytes,
    output logic [3:0]   ct_block_sel,
    input  logic [127:0] ct_block_data,

    input  logic         send_auth_tag,
    input  logic [127:0] tag_data,

    input  logic         send_err_unknown,
    input  logic         send_err_len,
    input  logic [7:0]   err_code_in,

    // Interface to uart_tx
    output logic [7:0]   tx_data,
    output logic         tx_start,
    input  logic         tx_busy,

    // Status
    output logic         builder_busy,
    output logic         packet_sent
);

    typedef enum logic [1:0] {
        ST_IDLE,
        ST_SEND_BYTE,
        ST_WAIT_BUSY,
        ST_WAIT_FREE
    } builder_state_t;

    builder_state_t state;

    logic [7:0]   cmd_reg;
    logic [7:0]   len_reg;
    logic [8:0]   total_bytes;      // Header (2 bytes) + Payload
    logic [8:0]   byte_idx;         // Index of current byte to send (0 .. total_bytes - 1)

    logic [127:0] tag_reg;
    logic [7:0]   err_code_reg;

    // Determine current block selection for ciphertext readout
    // Payload byte index = byte_idx - 2. Block index = (byte_idx - 2) / 16.
    logic [7:0] payload_idx;
    assign payload_idx  = (byte_idx >= 9'd2) ? (byte_idx[7:0] - 8'd2) : 8'd0;
    assign ct_block_sel = payload_idx[7:4];

    // Select byte to transmit based on current byte index
    logic [7:0] current_tx_byte;
    always_comb begin
        if (byte_idx == 9'd0) begin
            current_tx_byte = cmd_reg;
        end else if (byte_idx == 9'd1) begin
            current_tx_byte = len_reg;
        end else begin
            // Payload bytes
            case (cmd_reg)
                RESP_CIPHERTEXT: begin
                    // Big-endian byte indexing within selected 128-bit block
                    current_tx_byte = ct_block_data[127 - 8*payload_idx[3:0] -: 8];
                end

                RESP_AUTH_TAG: begin
                    current_tx_byte = tag_reg[127 - 8*payload_idx[3:0] -: 8];
                end

                RESP_ERR_UNKNOWN, RESP_ERR_LEN: begin
                    current_tx_byte = err_code_reg;
                end

                default: begin
                    current_tx_byte = 8'h00;
                end
            endcase
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state        <= ST_IDLE;
            cmd_reg      <= 8'h00;
            len_reg      <= 8'h00;
            total_bytes  <= 9'd0;
            byte_idx     <= 9'd0;
            tag_reg      <= 128'h0;
            err_code_reg <= 8'h00;
            tx_data      <= 8'h00;
            tx_start     <= 1'b0;
            builder_busy <= 1'b0;
            packet_sent  <= 1'b0;
        end else begin
            tx_start    <= 1'b0;
            packet_sent <= 1'b0;

            case (state)
                ST_IDLE: begin
                    builder_busy <= 1'b0;
                    byte_idx     <= 9'd0;

                    if (send_ack_key) begin
                        cmd_reg      <= RESP_ACK_KEY;
                        len_reg      <= 8'h00;
                        total_bytes  <= 9'd2;
                        builder_busy <= 1'b1;
                        state        <= ST_SEND_BYTE;
                    end else if (send_ack_iv) begin
                        cmd_reg      <= RESP_ACK_IV;
                        len_reg      <= 8'h00;
                        total_bytes  <= 9'd2;
                        builder_busy <= 1'b1;
                        state        <= ST_SEND_BYTE;
                    end else if (send_ack_aad) begin
                        cmd_reg      <= RESP_ACK_AAD;
                        len_reg      <= 8'h00;
                        total_bytes  <= 9'd2;
                        builder_busy <= 1'b1;
                        state        <= ST_SEND_BYTE;
                    end else if (send_ack_pt) begin
                        cmd_reg      <= RESP_ACK_PLAINTEXT;
                        len_reg      <= 8'h00;
                        total_bytes  <= 9'd2;
                        builder_busy <= 1'b1;
                        state        <= ST_SEND_BYTE;
                    end else if (send_ciphertext) begin
                        cmd_reg      <= RESP_CIPHERTEXT;
                        len_reg      <= ct_len_bytes;
                        total_bytes  <= 9'd2 + {1'b0, ct_len_bytes};
                        builder_busy <= 1'b1;
                        state        <= ST_SEND_BYTE;
                    end else if (send_auth_tag) begin
                        cmd_reg      <= RESP_AUTH_TAG;
                        len_reg      <= 8'd16;
                        tag_reg      <= tag_data;
                        total_bytes  <= 9'd18; // 2 + 16
                        builder_busy <= 1'b1;
                        state        <= ST_SEND_BYTE;
                    end else if (send_err_unknown) begin
                        cmd_reg      <= RESP_ERR_UNKNOWN;
                        len_reg      <= 8'd1;
                        err_code_reg <= err_code_in;
                        total_bytes  <= 9'd3;
                        builder_busy <= 1'b1;
                        state        <= ST_SEND_BYTE;
                    end else if (send_err_len) begin
                        cmd_reg      <= RESP_ERR_LEN;
                        len_reg      <= 8'd1;
                        err_code_reg <= err_code_in;
                        total_bytes  <= 9'd3;
                        builder_busy <= 1'b1;
                        state        <= ST_SEND_BYTE;
                    end
                end

                ST_SEND_BYTE: begin
                    if (!tx_busy) begin
                        tx_data  <= current_tx_byte;
                        tx_start <= 1'b1;
                        state    <= ST_WAIT_BUSY;
                    end
                end

                ST_WAIT_BUSY: begin
                    if (tx_busy) begin
                        state <= ST_WAIT_FREE;
                    end
                end

                ST_WAIT_FREE: begin
                    if (!tx_busy) begin
                        if (byte_idx + 1'b1 == total_bytes) begin
                            packet_sent  <= 1'b1;
                            builder_busy <= 1'b0;
                            state        <= ST_IDLE;
                        end else begin
                            byte_idx <= byte_idx + 1'b1;
                            state    <= ST_SEND_BYTE;
                        end
                    end
                end

                default: begin
                    state <= ST_IDLE;
                end
            endcase
        end
    end

endmodule


//=============================================================================
// SECTION: AES-256 UART Wrapper Top-Level DUT
// SOURCE: uart_integration/aes256/aes256_uart_wrapper.sv
//=============================================================================
//=============================================================================
// Module: aes256_uart_wrapper.sv
// Directory: uart_integration/aes256/
// Description: Dedicated UART integration wrapper connecting physical UART
//              pins to the AES-256-GCM hardware accelerator (RTL/AES_256_GCM.sv).
//
// Target: Microchip PolarFire SoC Discovery Kit (MPFS095T-1FCSG325E)
//
// Features:
//   - Connects full 256-bit key (reg_key[255:0]) to AES_256_GCM
//   - Connects verify_checked and verify_done ports
//   - Instantiates shared common UART components (uart_rx, uart_tx, parser, builder)
//   - Strobe/handshake driven (absorbs 16-cycle pipeline latency automatically)
//=============================================================================


import protocol_pkg::*;

module aes256_uart_wrapper #(
    parameter int CLK_FREQ_HZ = 100_000_000,
    parameter int BAUD_RATE   = 115_200
)(
    input  logic clk,
    input  logic rst_n,

    // Serial physical pins
    input  logic uart_rx,
    output logic uart_tx,

    // Status diagnostics
    output logic led_busy,
    output logic led_done
);

    //-------------------------------------------------------------------------
    // Internal Signals: UART Physical Layer
    //-------------------------------------------------------------------------
    logic [7:0] rx_byte;
    logic       rx_byte_valid;

    logic [7:0] tx_byte;
    logic       tx_byte_start;
    logic       tx_byte_busy;

    //-------------------------------------------------------------------------
    // Internal Signals: Packet Parser
    //-------------------------------------------------------------------------
    logic         parser_cmd_load_key_done;
    logic [255:0] parser_key;
    logic [5:0]   parser_key_len;

    logic         parser_cmd_load_iv_done;
    logic [95:0]  parser_iv;

    logic         parser_block_valid;
    logic         parser_block_is_pt;
    logic         parser_block_is_last;
    logic [127:0] parser_block_data;
    logic [7:0]   parser_total_blocks;

    logic         parser_cmd_load_aad_done;
    logic         parser_cmd_load_pt_done;
    logic         parser_cmd_start_encrypt_done;

    logic         parser_err_unknown;
    logic         parser_err_len;
    logic [7:0]   parser_err_code;

    //-------------------------------------------------------------------------
    // Internal Signals: Packet Builder
    //-------------------------------------------------------------------------
    logic         builder_send_ack_key;
    logic         builder_send_ack_iv;
    logic         builder_send_ack_aad;
    logic         builder_send_ack_pt;

    logic         builder_send_ciphertext;
    logic [7:0]   builder_ct_len_bytes;
    logic [3:0]   builder_ct_block_sel;
    logic [127:0] builder_ct_block_data;

    logic         builder_send_auth_tag;
    logic [127:0] builder_tag_data;

    logic         builder_send_err_unknown;
    logic         builder_send_err_len;
    logic [7:0]   builder_err_code;

    logic         builder_busy;
    logic         builder_packet_sent;

    //-------------------------------------------------------------------------
    // Internal Signals: AES-256 Core Interface
    //-------------------------------------------------------------------------
    logic         aes_load_key;
    logic         aes_load_iv;
    logic         aes_mode;
    logic         aes_load_tag_ref;
    logic         aes_load_aad;
    logic         aes_no_aad;
    logic         aes_aad_last;
    logic         aes_load_data;
    logic         aes_data_in_last;
    logic         aes_verify_checked;
    logic [255:0] aes_cipher_key;
    logic [127:0] aes_tag_ref;
    logic [127:0] aes_aad_in;
    logic [127:0] aes_data_in;
    logic [95:0]  aes_iv_in;

    logic         aes_tag_valid;
    logic         aes_verify_pass;
    logic         aes_ctr_overflow;
    logic         aes_data_valid;
    logic         aes_data_out_last;
    logic         aes_finish;
    logic         aes_tag_ref_ready;
    logic         aes_key_ready;
    logic         aes_iv_ready;
    logic         aes_aad_ready;
    logic         aes_data_ready;
    logic [127:0] aes_tag_out;
    logic [127:0] aes_data_out;
    logic         aes_verify_done;

    //-------------------------------------------------------------------------
    // Internal Data Storage Buffers
    //-------------------------------------------------------------------------
    logic [255:0] reg_key;
    logic [5:0]   reg_key_len;
    logic [95:0]  reg_iv;

    logic [127:0] mem_aad [0:MAX_BUFFER_BLOCKS-1];
    logic [3:0]   cnt_aad_blocks;

    logic [127:0] mem_pt  [0:MAX_BUFFER_BLOCKS-1];
    logic [3:0]   cnt_pt_blocks;

    logic [127:0] mem_ct  [0:MAX_BUFFER_BLOCKS-1];
    logic [3:0]   cnt_ct_captured;

    logic [127:0] reg_tag;
    logic         reg_tag_captured;

    // Readout multiplexer for packet builder
    assign builder_ct_block_data = mem_ct[builder_ct_block_sel];
    assign builder_tag_data      = reg_tag;

    // Fixed configuration for encryption
    assign aes_mode           = 1'b0; // 0 = Encryption
    assign aes_load_tag_ref   = 1'b0;
    assign aes_tag_ref        = 128'h0;
    assign aes_verify_checked = 1'b0;

    //-------------------------------------------------------------------------
    // Wrapper Orchestration State Machine
    //-------------------------------------------------------------------------
    typedef enum logic [3:0] {
        WRAP_IDLE,
        WRAP_START_KEY_IV,
        WRAP_WAIT_AAD_READY,
        WRAP_STREAM_AAD,
        WRAP_WAIT_DATA_READY,
        WRAP_STREAM_PT,
        WRAP_WAIT_PIPELINE,
        WRAP_SEND_CT,
        WRAP_WAIT_CT_SENT,
        WRAP_SEND_TAG,
        WRAP_WAIT_TAG_SENT
    } wrap_state_t;

    wrap_state_t wrap_state;

    logic [3:0] cur_aad_idx;
    logic [3:0] cur_pt_idx;

    //-------------------------------------------------------------------------
    // Common Module Instantiations
    //-------------------------------------------------------------------------

    uart_rx #(
        .CLK_FREQ_HZ(CLK_FREQ_HZ),
        .BAUD_RATE  (BAUD_RATE)
    ) u_rx (
        .clk     (clk),
        .rst_n   (rst_n),
        .rx      (uart_rx),
        .rx_data (rx_byte),
        .rx_valid(rx_byte_valid)
    );

    uart_tx #(
        .CLK_FREQ_HZ(CLK_FREQ_HZ),
        .BAUD_RATE  (BAUD_RATE)
    ) u_tx (
        .clk     (clk),
        .rst_n   (rst_n),
        .tx_data (tx_byte),
        .tx_start(tx_byte_start),
        .tx      (uart_tx),
        .tx_busy (tx_byte_busy)
    );

    packet_parser u_parser (
        .clk                   (clk),
        .rst_n                 (rst_n),
        .rx_data               (rx_byte),
        .rx_valid              (rx_byte_valid),
        .cmd_load_key_done     (parser_cmd_load_key_done),
        .key_out               (parser_key),
        .key_len_bytes         (parser_key_len),
        .cmd_load_iv_done      (parser_cmd_load_iv_done),
        .iv_out                (parser_iv),
        .block_valid           (parser_block_valid),
        .block_is_pt           (parser_block_is_pt),
        .block_is_last         (parser_block_is_last),
        .block_data            (parser_block_data),
        .total_blocks          (parser_total_blocks),
        .cmd_load_aad_done     (parser_cmd_load_aad_done),
        .cmd_load_pt_done      (parser_cmd_load_pt_done),
        .cmd_start_encrypt_done(parser_cmd_start_encrypt_done),
        .err_unknown_cmd       (parser_err_unknown),
        .err_len_mismatch      (parser_err_len),
        .err_cmd_code          (parser_err_code)
    );

    packet_builder u_builder (
        .clk             (clk),
        .rst_n           (rst_n),
        .send_ack_key    (builder_send_ack_key),
        .send_ack_iv     (builder_send_ack_iv),
        .send_ack_aad    (builder_send_ack_aad),
        .send_ack_pt     (builder_send_ack_pt),
        .send_ciphertext (builder_send_ciphertext),
        .ct_len_bytes    (builder_ct_len_bytes),
        .ct_block_sel    (builder_ct_block_sel),
        .ct_block_data   (builder_ct_block_data),
        .send_auth_tag   (builder_send_auth_tag),
        .tag_data        (builder_tag_data),
        .send_err_unknown(builder_send_err_unknown),
        .send_err_len    (builder_send_err_len),
        .err_code_in     (builder_err_code),
        .tx_data         (tx_byte),
        .tx_start        (tx_byte_start),
        .tx_busy         (tx_byte_busy),
        .builder_busy    (builder_busy),
        .packet_sent     (builder_packet_sent)
    );

    // Existing AES-256 GCM Core (RTL/AES_256_GCM.sv)
    AES_256_GCM u_aes256_gcm (
        .clk                  (clk),
        .rst_n                (rst_n),
        .load_key             (aes_load_key),
        .load_IV              (aes_load_iv),
        .mode                 (aes_mode),
        .load_tag_ref         (aes_load_tag_ref),
        .load_AAD             (aes_load_aad),
        .no_AAD               (aes_no_aad),
        .AAD_last             (aes_aad_last),
        .load_data            (aes_load_data),
        .data_in_last         (aes_data_in_last),
        .verify_checked       (aes_verify_checked),
        .cipher_key           (aes_cipher_key),
        .tag_ref              (aes_tag_ref),
        .AAD                  (aes_aad_in),
        .data_in              (aes_data_in),
        .IV                   (aes_iv_in),
        .tag_valid            (aes_tag_valid),
        .verify_pass          (aes_verify_pass),
        .CTR_counter_overflow (aes_ctr_overflow),
        .data_valid           (aes_data_valid),
        .data_out_last        (aes_data_out_last),
        .finish               (aes_finish),
        .tag_ref_ready        (aes_tag_ref_ready),
        .key_ready            (aes_key_ready),
        .IV_ready             (aes_iv_ready),
        .AAD_ready            (aes_aad_ready),
        .data_ready           (aes_data_ready),
        .tag                  (aes_tag_out),
        .data_out             (aes_data_out),
        .verify_done          (aes_verify_done)
    );

    //-------------------------------------------------------------------------
    // Packet Parser Handshake & Buffer Latching
    //-------------------------------------------------------------------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            reg_key          <= 256'h0;
            reg_key_len      <= 6'd0;
            reg_iv           <= 96'h0;
            cnt_aad_blocks   <= 4'd0;
            cnt_pt_blocks    <= 4'd0;

            builder_send_ack_key     <= 1'b0;
            builder_send_ack_iv      <= 1'b0;
            builder_send_ack_aad     <= 1'b0;
            builder_send_ack_pt      <= 1'b0;
            builder_send_err_unknown <= 1'b0;
            builder_send_err_len     <= 1'b0;
            builder_err_code         <= 8'h00;
        end else begin
            builder_send_ack_key     <= 1'b0;
            builder_send_ack_iv      <= 1'b0;
            builder_send_ack_aad     <= 1'b0;
            builder_send_ack_pt      <= 1'b0;
            builder_send_err_unknown <= 1'b0;
            builder_send_err_len     <= 1'b0;

            if (parser_cmd_load_key_done) begin
                reg_key              <= parser_key;
                reg_key_len          <= parser_key_len;
                builder_send_ack_key <= 1'b1;
            end

            if (parser_cmd_load_iv_done) begin
                reg_iv              <= parser_iv;
                builder_send_ack_iv <= 1'b1;
            end

            if (parser_block_valid) begin
                if (!parser_block_is_pt) begin
                    mem_aad[cnt_aad_blocks] <= parser_block_data;
                    cnt_aad_blocks          <= cnt_aad_blocks + 1'b1;
                end else begin
                    mem_pt[cnt_pt_blocks]   <= parser_block_data;
                    cnt_pt_blocks           <= cnt_pt_blocks + 1'b1;
                end
            end

            if (parser_cmd_load_aad_done) builder_send_ack_aad <= 1'b1;
            if (parser_cmd_load_pt_done)  builder_send_ack_pt  <= 1'b1;

            if (parser_err_unknown) begin
                builder_send_err_unknown <= 1'b1;
                builder_err_code         <= parser_err_code;
            end
            if (parser_err_len) begin
                builder_send_err_len <= 1'b1;
                builder_err_code     <= parser_err_code;
            end

            if (wrap_state == WRAP_WAIT_TAG_SENT && builder_packet_sent) begin
                cnt_aad_blocks <= 4'd0;
                cnt_pt_blocks  <= 4'd0;
            end
        end
    end

    //-------------------------------------------------------------------------
    // Capture Outputs from AES-256 Core
    //-------------------------------------------------------------------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cnt_ct_captured  <= 4'd0;
            reg_tag          <= 128'h0;
            reg_tag_captured <= 1'b0;
            for (int i = 0; i < MAX_BUFFER_BLOCKS; i++) begin
                mem_ct[i] <= 128'h0;
            end
        end else begin
            if (wrap_state == WRAP_START_KEY_IV) begin
                cnt_ct_captured  <= 4'd0;
                reg_tag_captured <= 1'b0;
            end

            if (aes_data_valid) begin
                mem_ct[cnt_ct_captured] <= aes_data_out;
                cnt_ct_captured         <= cnt_ct_captured + 1'b1;
            end

            if (aes_tag_valid) begin
                reg_tag          <= aes_tag_out;
                reg_tag_captured <= 1'b1;
            end
        end
    end

    //-------------------------------------------------------------------------
    // Hardware Accelerator Orchestration FSM
    //-------------------------------------------------------------------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wrap_state              <= WRAP_IDLE;
            aes_load_key            <= 1'b0;
            aes_load_iv             <= 1'b0;
            aes_load_aad            <= 1'b0;
            aes_no_aad              <= 1'b0;
            aes_aad_last            <= 1'b0;
            aes_load_data           <= 1'b0;
            aes_data_in_last        <= 1'b0;
            aes_cipher_key          <= 256'h0;
            aes_iv_in               <= 96'h0;
            aes_aad_in              <= 128'h0;
            aes_data_in             <= 128'h0;
            cur_aad_idx             <= 4'd0;
            cur_pt_idx              <= 4'd0;
            builder_send_ciphertext <= 1'b0;
            builder_ct_len_bytes    <= 8'h00;
            builder_send_auth_tag   <= 1'b0;
            led_busy                <= 1'b0;
            led_done                <= 1'b0;
        end else begin
            aes_load_key            <= 1'b0;
            aes_load_iv             <= 1'b0;
            aes_load_aad            <= 1'b0;
            aes_no_aad              <= 1'b0;
            aes_aad_last            <= 1'b0;
            aes_load_data           <= 1'b0;
            aes_data_in_last        <= 1'b0;
            builder_send_ciphertext <= 1'b0;
            builder_send_auth_tag   <= 1'b0;
            led_done                <= 1'b0;

            case (wrap_state)
                WRAP_IDLE: begin
                    led_busy    <= 1'b0;
                    cur_aad_idx <= 4'd0;
                    cur_pt_idx  <= 4'd0;

                    if (parser_cmd_start_encrypt_done) begin
                        led_busy       <= 1'b1;
                        // AES-256 receives full 256-bit key
                        aes_cipher_key <= reg_key;
                        aes_iv_in      <= reg_iv;
                        aes_load_key   <= 1'b1;
                        aes_load_iv    <= 1'b1;
                        wrap_state     <= WRAP_START_KEY_IV;
                    end
                end

                WRAP_START_KEY_IV: begin
                    wrap_state <= WRAP_WAIT_AAD_READY;
                end

                WRAP_WAIT_AAD_READY: begin
                    if (aes_aad_ready) begin
                        if (cnt_aad_blocks == 4'd0) begin
                            aes_no_aad <= 1'b1;
                            wrap_state <= WRAP_WAIT_DATA_READY;
                        end else begin
                            cur_aad_idx  <= 4'd0;
                            aes_aad_in   <= mem_aad[0];
                            aes_load_aad <= 1'b1;
                            if (cnt_aad_blocks == 4'd1) begin
                                aes_aad_last <= 1'b1;
                                wrap_state   <= WRAP_WAIT_DATA_READY;
                            end else begin
                                cur_aad_idx <= 4'd1;
                                wrap_state  <= WRAP_STREAM_AAD;
                            end
                        end
                    end
                end

                WRAP_STREAM_AAD: begin
                    aes_aad_in   <= mem_aad[cur_aad_idx];
                    aes_load_aad <= 1'b1;
                    if (cur_aad_idx + 1'b1 == cnt_aad_blocks) begin
                        aes_aad_last <= 1'b1;
                        wrap_state   <= WRAP_WAIT_DATA_READY;
                    end else begin
                        cur_aad_idx <= cur_aad_idx + 1'b1;
                    end
                end

                WRAP_WAIT_DATA_READY: begin
                    if (aes_data_ready) begin
                        cur_pt_idx    <= 4'd0;
                        aes_data_in   <= mem_pt[0];
                        aes_load_data <= 1'b1;
                        if (cnt_pt_blocks == 4'd1) begin
                            aes_data_in_last <= 1'b1;
                            wrap_state       <= WRAP_WAIT_PIPELINE;
                        end else begin
                            cur_pt_idx <= 4'd1;
                            wrap_state <= WRAP_STREAM_PT;
                        end
                    end
                end

                WRAP_STREAM_PT: begin
                    aes_data_in   <= mem_pt[cur_pt_idx];
                    aes_load_data <= 1'b1;
                    if (cur_pt_idx + 1'b1 == cnt_pt_blocks) begin
                        aes_data_in_last <= 1'b1;
                        wrap_state       <= WRAP_WAIT_PIPELINE;
                    end else begin
                        cur_pt_idx <= cur_pt_idx + 1'b1;
                    end
                end

                WRAP_WAIT_PIPELINE: begin
                    if ((cnt_ct_captured == cnt_pt_blocks) && reg_tag_captured) begin
                        wrap_state <= WRAP_SEND_CT;
                    end
                end

                WRAP_SEND_CT: begin
                    builder_send_ciphertext <= 1'b1;
                    builder_ct_len_bytes    <= {cnt_pt_blocks, 4'd0};
                    wrap_state              <= WRAP_WAIT_CT_SENT;
                end

                WRAP_WAIT_CT_SENT: begin
                    if (builder_packet_sent) begin
                        wrap_state <= WRAP_SEND_TAG;
                    end
                end

                WRAP_SEND_TAG: begin
                    builder_send_auth_tag <= 1'b1;
                    wrap_state            <= WRAP_WAIT_TAG_SENT;
                end

                WRAP_WAIT_TAG_SENT: begin
                    if (builder_packet_sent) begin
                        led_busy   <= 1'b0;
                        led_done   <= 1'b1;
                        wrap_state <= WRAP_IDLE;
                    end
                end

                default: begin
                    wrap_state <= WRAP_IDLE;
                end
            endcase
        end
    end

endmodule
