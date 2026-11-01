//=============================================================================
// Module: packet_parser.sv
// Directory: uart_integration/common/
// Description: Shared binary packet parser for the AES-GCM framework.
//              Deserializes, validates, and decodes binary packets from the
//              UART or SPI link. The byte source must honour rx_ready.
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
//   0x06: CMD_LOAD_TAG_REF   (Length: 16 bytes)
//   0x07: CMD_START_DECRYPT  (Length: 0 bytes)
//
// A rejected packet's payload is skipped, so the next packet still parses.
// A packet that stops arriving is dropped after TIMEOUT_CYCLES.
//=============================================================================

`timescale 1ns / 1ps

import protocol_pkg::*;

module packet_parser #(
    parameter int TIMEOUT_CYCLES = 500_000 // 10 ms at 50 MHz
)(
    input  logic         clk,
    input  logic         rst_n,

    // Interface from the link layer
    input  logic [7:0]   rx_data,
    input  logic         rx_valid,
    output logic         rx_ready,          // Low when an offered byte would be lost

    // Command triggers to wrapper
    output logic         cmd_load_key_done,
    output logic [255:0] key_out,
    output logic [5:0]   key_len_bytes,     // 16 or 32

    output logic         cmd_load_iv_done,
    output logic [95:0]  iv_out,

    output logic         cmd_load_tag_ref_done,
    output logic [127:0] tag_ref_out,

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
    output logic         cmd_start_decrypt_done,

    // Error status
    output logic         err_unknown_cmd,
    output logic         err_len_mismatch,
    output logic         err_timeout,
    output logic [7:0]   err_cmd_code
);

    typedef enum logic [2:0] {
        ST_IDLE,
        ST_GET_LEN,
        ST_CHECK_CMD,
        ST_PAYLOAD,
        ST_SETTLE_0,   // Two cycles for the strobes to reach the wrapper FSM and
        ST_SETTLE_1    // the builder, so the next packet sees them as busy
    } parser_state_t;

    parser_state_t state;

    logic [7:0]   cmd_reg;
    logic [7:0]   len_reg;
    logic [7:0]   byte_cnt;
    logic [3:0]   block_byte_cnt;
    logic         discard;           // Skipping the payload of a rejected packet

    logic [255:0] key_shift;
    logic [95:0]  iv_shift;
    logic [127:0] block_shift;

    localparam int TIMEOUT_WIDTH = $clog2(TIMEOUT_CYCLES + 1);
    logic [TIMEOUT_WIDTH-1:0] idle_cnt;

    assign rx_ready = (state == ST_IDLE) || (state == ST_GET_LEN) || (state == ST_PAYLOAD);

    // Validate command and length compatibility
    logic cmd_known, len_ok;
    always_comb begin
        cmd_known = 1'b1;
        case (cmd_reg)
            CMD_LOAD_KEY:                       len_ok = (len_reg == 8'd16) || (len_reg == 8'd32);
            CMD_LOAD_IV:                        len_ok = (len_reg == 8'd12);
            CMD_LOAD_TAG_REF:                   len_ok = (len_reg == 8'd16);
            CMD_LOAD_AAD, CMD_LOAD_PLAINTEXT:   len_ok = (len_reg[3:0] == 4'd0) && (len_reg > 8'd0);
            CMD_START_ENCRYPT, CMD_START_DECRYPT: len_ok = (len_reg == 8'd0);
            default: begin
                cmd_known = 1'b0;
                len_ok    = 1'b0;
            end
        endcase
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state                  <= ST_IDLE;
            cmd_reg                <= 8'h00;
            len_reg                <= 8'h00;
            byte_cnt               <= 8'h00;
            block_byte_cnt         <= 4'd0;
            discard                <= 1'b0;
            idle_cnt               <= '0;
            key_shift              <= 256'h0;
            iv_shift               <= 96'h0;
            block_shift            <= 128'h0;

            cmd_load_key_done      <= 1'b0;
            key_out                <= 256'h0;
            key_len_bytes          <= 6'd0;

            cmd_load_iv_done       <= 1'b0;
            iv_out                 <= 96'h0;

            cmd_load_tag_ref_done  <= 1'b0;
            tag_ref_out            <= 128'h0;

            block_valid            <= 1'b0;
            block_is_pt            <= 1'b0;
            block_is_last          <= 1'b0;
            block_data             <= 128'h0;
            total_blocks           <= 8'h00;

            cmd_load_aad_done      <= 1'b0;
            cmd_load_pt_done       <= 1'b0;
            cmd_start_encrypt_done <= 1'b0;
            cmd_start_decrypt_done <= 1'b0;

            err_unknown_cmd        <= 1'b0;
            err_len_mismatch       <= 1'b0;
            err_timeout            <= 1'b0;
            err_cmd_code           <= 8'h00;
        end else begin
            // Default 1-cycle strobes
            cmd_load_key_done      <= 1'b0;
            cmd_load_iv_done       <= 1'b0;
            cmd_load_tag_ref_done  <= 1'b0;
            block_valid            <= 1'b0;
            cmd_load_aad_done      <= 1'b0;
            cmd_load_pt_done       <= 1'b0;
            cmd_start_encrypt_done <= 1'b0;
            cmd_start_decrypt_done <= 1'b0;
            err_unknown_cmd        <= 1'b0;
            err_len_mismatch       <= 1'b0;
            err_timeout            <= 1'b0;

            case (state)
                ST_IDLE: begin
                    byte_cnt       <= 8'h00;
                    block_byte_cnt <= 4'd0;
                    discard        <= 1'b0;
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
                    if (!len_ok) begin
                        err_unknown_cmd  <= !cmd_known;
                        err_len_mismatch <= cmd_known;
                        err_cmd_code     <= cmd_reg;
                        discard          <= 1'b1;
                        state            <= (len_reg == 8'd0) ? ST_SETTLE_0 : ST_PAYLOAD;
                    end else if (len_reg == 8'd0) begin
                        cmd_start_encrypt_done <= (cmd_reg == CMD_START_ENCRYPT);
                        cmd_start_decrypt_done <= (cmd_reg == CMD_START_DECRYPT);
                        state                  <= ST_SETTLE_0;
                    end else begin
                        if (cmd_reg == CMD_LOAD_KEY) key_len_bytes <= len_reg[5:0];
                        total_blocks <= len_reg >> 4;
                        state        <= ST_PAYLOAD;
                    end
                end

                ST_PAYLOAD: begin
                    if (rx_valid) begin
                        byte_cnt <= byte_cnt + 1'b1;

                        if (discard) begin
                            if (byte_cnt + 1'b1 == len_reg) state <= ST_SETTLE_0;
                        end else begin
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
                                        state             <= ST_SETTLE_0;
                                    end
                                end

                                CMD_LOAD_IV: begin // Accumulate IV
                                    iv_shift <= {iv_shift[87:0], rx_data};
                                    if (byte_cnt + 1'b1 == 8'd12) begin
                                        iv_out           <= {iv_shift[87:0], rx_data};
                                        cmd_load_iv_done <= 1'b1;
                                        state            <= ST_SETTLE_0;
                                    end
                                end

                                CMD_LOAD_TAG_REF: begin // Accumulate the expected tag
                                    block_shift <= {block_shift[119:0], rx_data};
                                    if (byte_cnt + 1'b1 == 8'd16) begin
                                        tag_ref_out           <= {block_shift[119:0], rx_data};
                                        cmd_load_tag_ref_done <= 1'b1;
                                        state                 <= ST_SETTLE_0;
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
                                            state <= ST_SETTLE_0;
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
                end

                ST_SETTLE_0: state <= ST_SETTLE_1;
                ST_SETTLE_1: state <= ST_IDLE;

                default: begin
                    state <= ST_IDLE;
                end
            endcase

            // A packet cut short must not swallow the one after it
            if ((state == ST_GET_LEN) || (state == ST_PAYLOAD)) begin
                idle_cnt <= rx_valid ? '0 : idle_cnt + 1'b1;
                if (!rx_valid && (idle_cnt == TIMEOUT_CYCLES - 1)) begin
                    err_timeout  <= 1'b1;
                    err_cmd_code <= cmd_reg;
                    state        <= ST_SETTLE_0;
                end
            end else begin
                idle_cnt <= '0;
            end
        end
    end

endmodule
