//=============================================================================
// Package: protocol_pkg.sv
// Description: Unified SystemVerilog package declaring command opcodes,
//              response opcodes, error codes, and protocol constants for
//              the AES-GCM UART communication framework.
//=============================================================================

`timescale 1ns / 1ps

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
