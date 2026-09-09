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

`timescale 1ns / 1ps

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
