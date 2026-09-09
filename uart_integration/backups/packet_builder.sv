//=============================================================================
// Module: packet_builder.sv
// Description: Formats response packets (ACKs, Ciphertext, Tag, Errors)
//              and serializes them byte-by-byte through uart_tx.
//
// Response Opcodes:
//   0x81: ACK_KEY        (Length: 0)
//   0x82: ACK_IV         (Length: 0)
//   0x83: ACK_AAD        (Length: 0)
//   0x84: ACK_PLAINTEXT  (Length: 0)
//   0x90: CIPHERTEXT     (Length: N bytes)
//   0x91: AUTH_TAG       (Length: 16 bytes)
//   0xE0: ERR_UNKNOWN    (Length: 1 byte)
//   0xE1: ERR_LEN        (Length: 1 byte)
//=============================================================================

`timescale 1ns / 1ps

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
                8'h90: begin // CIPHERTEXT
                    // Big-endian byte indexing within selected 128-bit block
                    current_tx_byte = ct_block_data[127 - 8*payload_idx[3:0] -: 8];
                end

                8'h91: begin // AUTH_TAG
                    current_tx_byte = tag_reg[127 - 8*payload_idx[3:0] -: 8];
                end

                8'hE0, 8'hE1: begin // Error packets
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
                        cmd_reg      <= 8'h81;
                        len_reg      <= 8'h00;
                        total_bytes  <= 9'd2;
                        builder_busy <= 1'b1;
                        state        <= ST_SEND_BYTE;
                    end else if (send_ack_iv) begin
                        cmd_reg      <= 8'h82;
                        len_reg      <= 8'h00;
                        total_bytes  <= 9'd2;
                        builder_busy <= 1'b1;
                        state        <= ST_SEND_BYTE;
                    end else if (send_ack_aad) begin
                        cmd_reg      <= 8'h83;
                        len_reg      <= 8'h00;
                        total_bytes  <= 9'd2;
                        builder_busy <= 1'b1;
                        state        <= ST_SEND_BYTE;
                    end else if (send_ack_pt) begin
                        cmd_reg      <= 8'h84;
                        len_reg      <= 8'h00;
                        total_bytes  <= 9'd2;
                        builder_busy <= 1'b1;
                        state        <= ST_SEND_BYTE;
                    end else if (send_ciphertext) begin
                        cmd_reg      <= 8'h90;
                        len_reg      <= ct_len_bytes;
                        total_bytes  <= 9'd2 + {1'b0, ct_len_bytes};
                        builder_busy <= 1'b1;
                        state        <= ST_SEND_BYTE;
                    end else if (send_auth_tag) begin
                        cmd_reg      <= 8'h91;
                        len_reg      <= 8'd16;
                        tag_reg      <= tag_data;
                        total_bytes  <= 9'd18; // 2 + 16
                        builder_busy <= 1'b1;
                        state        <= ST_SEND_BYTE;
                    end else if (send_err_unknown) begin
                        cmd_reg      <= 8'hE0;
                        len_reg      <= 8'd1;
                        err_code_reg <= err_code_in;
                        total_bytes  <= 9'd3;
                        builder_busy <= 1'b1;
                        state        <= ST_SEND_BYTE;
                    end else if (send_err_len) begin
                        cmd_reg      <= 8'hE1;
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
                    // Wait for uart_tx to latch the start pulse and raise tx_busy
                    if (tx_busy) begin
                        state <= ST_WAIT_FREE;
                    end
                end

                ST_WAIT_FREE: begin
                    // Wait for uart_tx to complete transmitting this byte
                    if (!tx_busy) begin
                        if (byte_idx + 1'b1 == total_bytes) begin
                            // Finished entire packet
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
