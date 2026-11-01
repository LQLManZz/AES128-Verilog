//=============================================================================
// Module: aes_gcm_engine.sv
// Directory: realtime_env/rtl/common/
// Description: Link-independent AES-GCM engine shared by the UART and SPI
//              wrappers. Queues incoming bytes, parses packets, drives the
//              hardware accelerator and builds the responses.
//
// Target: Microchip PolarFire SoC Discovery Kit (MPFS095T-1FCSG325E)
//
// Features:
//   - KEY_BITS selects RTL/AES_GCM.sv (128) or RTL/AES_256_GCM.sv (256)
//   - RX FIFO lets the host send several messages without waiting for ACKs
//   - Verifies LOAD_TAG_REF inside the IP and withholds a failed plaintext
//   - Strobe/handshake driven (absorbs the pipeline latency automatically)
//=============================================================================

`timescale 1ns / 1ps

import protocol_pkg::*;

module aes_gcm_engine #(
    parameter int KEY_BITS    = 256,
    parameter int CLK_FREQ_HZ = 50_000_000
)(
    input  logic clk,
    input  logic rst_n,

    // Bytes from the link layer
    input  logic [7:0] rx_data,
    input  logic       rx_valid,
    output logic       rx_overflow,

    // Bytes to the link layer
    output logic [7:0] tx_data,
    output logic       tx_start,
    input  logic       tx_busy,

    // Status diagnostics
    output logic       led_busy,
    output logic       led_done,
    output logic [4:0] led_unused
);

    localparam int RX_FIFO_DEPTH = 2048;

    //-------------------------------------------------------------------------
    // Internal Signals: RX Queue
    //-------------------------------------------------------------------------
    logic [7:0] fifo_byte;
    logic       fifo_empty;
    logic       fifo_full;
    logic       parser_rx_ready;
    logic       parser_rx_valid;
    logic       engine_ready;

    //-------------------------------------------------------------------------
    // Internal Signals: Packet Parser
    //-------------------------------------------------------------------------
    logic         parser_cmd_load_key_done;
    logic [255:0] parser_key;
    logic [5:0]   parser_key_len;

    logic         parser_cmd_load_iv_done;
    logic [95:0]  parser_iv;

    logic         parser_cmd_load_tag_ref_done;
    logic [127:0] parser_tag_ref;

    logic         parser_block_valid;
    logic         parser_block_is_pt;
    logic         parser_block_is_last;
    logic [127:0] parser_block_data;
    logic [7:0]   parser_total_blocks;

    logic         parser_cmd_load_aad_done;
    logic         parser_cmd_load_pt_done;
    logic         parser_cmd_start_encrypt_done;
    logic         parser_cmd_start_decrypt_done;

    logic         parser_err_unknown;
    logic         parser_err_len;
    logic         parser_err_timeout;
    logic [7:0]   parser_err_code;

    //-------------------------------------------------------------------------
    // Internal Signals: Packet Builder
    //-------------------------------------------------------------------------
    logic         builder_send_ack_key;
    logic         builder_send_ack_iv;
    logic         builder_send_ack_aad;
    logic         builder_send_ack_pt;
    logic         builder_send_ack_tag_ref;

    logic         builder_send_ciphertext;
    logic [7:0]   builder_ct_len_bytes;
    logic [3:0]   builder_ct_block_sel;
    logic [127:0] builder_ct_block_data;

    logic         builder_send_auth_tag;
    logic [127:0] builder_tag_data;

    logic         builder_send_verify;

    logic         builder_send_err_unknown;
    logic         builder_send_err_len;
    logic         builder_send_err_timeout;
    logic [7:0]   builder_err_code;

    logic         builder_busy;
    logic         builder_packet_sent;

    //-------------------------------------------------------------------------
    // Internal Signals: AES Core Interface
    //-------------------------------------------------------------------------
    logic                aes_load_key;
    logic                aes_load_iv;
    logic                aes_mode;
    logic                aes_load_tag_ref;
    logic                aes_load_aad;
    logic                aes_no_aad;
    logic                aes_aad_last;
    logic                aes_load_data;
    logic                aes_data_in_last;
    logic                aes_verify_checked;
    logic [KEY_BITS-1:0] aes_cipher_key;
    logic [127:0]        aes_tag_ref;
    logic [127:0]        aes_aad_in;
    logic [127:0]        aes_data_in;
    logic [95:0]         aes_iv_in;

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
    logic [95:0]  reg_iv;

    logic [127:0] reg_tag_ref;
    logic         reg_tag_ref_valid;

    logic [127:0] mem_aad [0:MAX_BUFFER_BLOCKS-1];
    logic [3:0]   cnt_aad_blocks;

    logic [127:0] mem_pt  [0:MAX_BUFFER_BLOCKS-1];
    logic [3:0]   cnt_pt_blocks;

    logic [127:0] mem_ct  [0:MAX_BUFFER_BLOCKS-1];
    logic [3:0]   cnt_ct_captured;

    logic [127:0] reg_tag;
    logic         reg_tag_captured;
    logic         reg_verify_pass;

    // Readout multiplexer for packet builder
    assign builder_ct_block_data = mem_ct[builder_ct_block_sel];
    assign builder_tag_data      = reg_tag;

    // Dynamic configuration for encryption (mode=0) and decryption (mode=1)
    logic reg_aes_mode;
    logic reg_load_tag_ref;
    logic reg_verify_checked;
    logic tag_ref_sent;

    assign aes_mode           = reg_aes_mode;
    assign aes_load_tag_ref   = reg_load_tag_ref;
    assign aes_tag_ref        = reg_tag_ref;
    assign aes_verify_checked = reg_verify_checked;

    //-------------------------------------------------------------------------
    // Wrapper Orchestration State Machine
    //-------------------------------------------------------------------------
    typedef enum logic [3:0] {
        WRAP_IDLE,
        WRAP_START_KEY_IV,
        WRAP_WAIT_AAD_READY,
        WRAP_STREAM_AAD,
        WRAP_HOLD_AAD_LAST,
        WRAP_WAIT_DATA_READY,
        WRAP_STREAM_PT,
        WRAP_HOLD_PT_LAST,
        WRAP_WAIT_PIPELINE,
        WRAP_SEND_CT,
        WRAP_WAIT_CT_SENT,
        WRAP_SEND_TAG,
        WRAP_WAIT_TAG_SENT,
        WRAP_SEND_VERIFY,
        WRAP_WAIT_VERIFY_SENT
    } wrap_state_t;

    wrap_state_t wrap_state;

    logic [3:0] cur_aad_idx;
    logic [3:0] cur_pt_idx;

    // The core needs at least one block, and decryption needs a tag to verify.
    logic start_requested, start_refused, message_done, key_len_bad;
    assign start_requested = parser_cmd_start_encrypt_done | parser_cmd_start_decrypt_done;
    assign start_refused   = start_requested && (wrap_state == WRAP_IDLE) &&
                             ((cnt_pt_blocks == 4'd0) || (parser_cmd_start_decrypt_done && !reg_tag_ref_valid));
    assign message_done    = builder_packet_sent &&
                             (((wrap_state == WRAP_WAIT_TAG_SENT) && !reg_aes_mode) ||
                              (wrap_state == WRAP_WAIT_VERIFY_SENT));
    assign key_len_bad     = parser_cmd_load_key_done && (parser_key_len != KEY_BITS / 8);

    //-------------------------------------------------------------------------
    // RX Queue: a new command must not overtake the message or response in
    // progress, because LOAD_IV clears the counters and the builder has no queue.
    //-------------------------------------------------------------------------
    assign engine_ready    = (wrap_state == WRAP_IDLE) && !builder_busy;
    assign parser_rx_valid = !fifo_empty && parser_rx_ready && engine_ready;
    assign rx_overflow     = rx_valid && fifo_full;

    byte_fifo #(
        .DEPTH(RX_FIFO_DEPTH)
    ) u_rx_fifo (
        .clk    (clk),
        .rst_n  (rst_n),
        .wr_data(rx_data),
        .wr_en  (rx_valid),
        .full   (fifo_full),
        .rd_data(fifo_byte),
        .rd_en  (parser_rx_valid),
        .empty  (fifo_empty)
    );

    //-------------------------------------------------------------------------
    // Common Module Instantiations
    //-------------------------------------------------------------------------
    packet_parser #(
        .TIMEOUT_CYCLES(CLK_FREQ_HZ / 100)
    ) u_parser (
        .clk                   (clk),
        .rst_n                 (rst_n),
        .rx_data               (fifo_byte),
        .rx_valid              (parser_rx_valid),
        .rx_ready              (parser_rx_ready),
        .cmd_load_key_done     (parser_cmd_load_key_done),
        .key_out               (parser_key),
        .key_len_bytes         (parser_key_len),
        .cmd_load_iv_done      (parser_cmd_load_iv_done),
        .iv_out                (parser_iv),
        .cmd_load_tag_ref_done (parser_cmd_load_tag_ref_done),
        .tag_ref_out           (parser_tag_ref),
        .block_valid           (parser_block_valid),
        .block_is_pt           (parser_block_is_pt),
        .block_is_last         (parser_block_is_last),
        .block_data            (parser_block_data),
        .total_blocks          (parser_total_blocks),
        .cmd_load_aad_done     (parser_cmd_load_aad_done),
        .cmd_load_pt_done      (parser_cmd_load_pt_done),
        .cmd_start_encrypt_done(parser_cmd_start_encrypt_done),
        .cmd_start_decrypt_done(parser_cmd_start_decrypt_done),
        .err_unknown_cmd       (parser_err_unknown),
        .err_len_mismatch      (parser_err_len),
        .err_timeout           (parser_err_timeout),
        .err_cmd_code          (parser_err_code)
    );

    packet_builder u_builder (
        .clk             (clk),
        .rst_n           (rst_n),
        .send_ack_key    (builder_send_ack_key),
        .send_ack_iv     (builder_send_ack_iv),
        .send_ack_aad    (builder_send_ack_aad),
        .send_ack_pt     (builder_send_ack_pt),
        .send_ack_tag_ref(builder_send_ack_tag_ref),
        .send_ciphertext (builder_send_ciphertext),
        .ct_len_bytes    (builder_ct_len_bytes),
        .ct_block_sel    (builder_ct_block_sel),
        .ct_block_data   (builder_ct_block_data),
        .send_auth_tag   (builder_send_auth_tag),
        .tag_data        (builder_tag_data),
        .send_verify     (builder_send_verify),
        .verify_pass_in  (reg_verify_pass),
        .send_err_unknown(builder_send_err_unknown),
        .send_err_len    (builder_send_err_len),
        .send_err_timeout(builder_send_err_timeout),
        .err_code_in     (builder_err_code),
        .tx_data         (tx_data),
        .tx_start        (tx_start),
        .tx_busy         (tx_busy),
        .builder_busy    (builder_busy),
        .packet_sent     (builder_packet_sent)
    );

    // Existing GCM cores (RTL/AES_GCM.sv, RTL/AES_256_GCM.sv)
    generate
        if (KEY_BITS == 256) begin : gen_aes256
            AES_256_GCM u_gcm (
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
        end else begin : gen_aes128
            AES_GCM u_gcm (
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
        end
    endgenerate

    //-------------------------------------------------------------------------
    // Packet Parser Handshake & Buffer Latching
    //-------------------------------------------------------------------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            reg_key           <= 256'h0;
            reg_iv            <= 96'h0;
            reg_tag_ref       <= 128'h0;
            reg_tag_ref_valid <= 1'b0;
            cnt_aad_blocks    <= 4'd0;
            cnt_pt_blocks     <= 4'd0;

            builder_send_ack_key     <= 1'b0;
            builder_send_ack_iv      <= 1'b0;
            builder_send_ack_aad     <= 1'b0;
            builder_send_ack_pt      <= 1'b0;
            builder_send_ack_tag_ref <= 1'b0;
            builder_send_err_unknown <= 1'b0;
            builder_send_err_len     <= 1'b0;
            builder_send_err_timeout <= 1'b0;
            builder_err_code         <= 8'h00;
        end else begin
            builder_send_ack_key     <= 1'b0;
            builder_send_ack_iv      <= 1'b0;
            builder_send_ack_aad     <= 1'b0;
            builder_send_ack_pt      <= 1'b0;
            builder_send_ack_tag_ref <= 1'b0;
            builder_send_err_unknown <= 1'b0;
            builder_send_err_len     <= 1'b0;
            builder_send_err_timeout <= 1'b0;

            if (parser_cmd_load_key_done) begin
                cnt_aad_blocks    <= 4'd0;
                cnt_pt_blocks     <= 4'd0;
                reg_tag_ref_valid <= 1'b0;
                if (key_len_bad) begin
                    builder_send_err_len <= 1'b1;
                    builder_err_code     <= CMD_LOAD_KEY;
                end else begin
                    reg_key              <= parser_key;
                    builder_send_ack_key <= 1'b1;
                end
            end

            if (parser_cmd_load_iv_done) begin
                reg_iv              <= parser_iv;
                cnt_aad_blocks      <= 4'd0;
                cnt_pt_blocks       <= 4'd0;
                reg_tag_ref_valid   <= 1'b0;
                builder_send_ack_iv <= 1'b1;
            end

            if (parser_cmd_load_tag_ref_done) begin
                reg_tag_ref              <= parser_tag_ref;
                reg_tag_ref_valid        <= 1'b1;
                builder_send_ack_tag_ref <= 1'b1;
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

            if (start_refused) begin
                builder_send_err_len <= 1'b1;
                builder_err_code     <= parser_cmd_start_decrypt_done ? CMD_START_DECRYPT : CMD_START_ENCRYPT;
            end

            if (parser_err_unknown) begin
                builder_send_err_unknown <= 1'b1;
                builder_err_code         <= parser_err_code;
            end
            if (parser_err_len) begin
                builder_send_err_len <= 1'b1;
                builder_err_code     <= parser_err_code;
            end
            if (parser_err_timeout) begin
                builder_send_err_timeout <= 1'b1;
                builder_err_code         <= parser_err_code;
            end

            if (message_done) begin
                cnt_aad_blocks    <= 4'd0;
                cnt_pt_blocks     <= 4'd0;
                reg_tag_ref_valid <= 1'b0;
            end
        end
    end

    //-------------------------------------------------------------------------
    // Capture Outputs from AES Core
    //-------------------------------------------------------------------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cnt_ct_captured  <= 4'd0;
            reg_tag          <= 128'h0;
            reg_tag_captured <= 1'b0;
            reg_verify_pass  <= 1'b0;
            for (int i = 0; i < MAX_BUFFER_BLOCKS; i++) begin
                mem_ct[i] <= 128'h0;
            end
        end else begin
            if (wrap_state == WRAP_START_KEY_IV) begin
                cnt_ct_captured  <= 4'd0;
                reg_tag_captured <= 1'b0;
                reg_verify_pass  <= 1'b0;
            end

            if (aes_data_valid) begin
                mem_ct[cnt_ct_captured] <= aes_data_out;
                cnt_ct_captured         <= cnt_ct_captured + 1'b1;
            end

            if (aes_tag_valid || (reg_aes_mode && aes_verify_done)) begin
                reg_tag          <= aes_tag_out;
                reg_tag_captured <= 1'b1;
            end

            if (aes_verify_pass) reg_verify_pass <= 1'b1;
        end
    end

    //-------------------------------------------------------------------------
    // Hardware Accelerator Orchestration FSM
    //-------------------------------------------------------------------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wrap_state              <= WRAP_IDLE;
            reg_aes_mode            <= 1'b0;
            reg_load_tag_ref        <= 1'b0;
            reg_verify_checked      <= 1'b0;
            tag_ref_sent            <= 1'b0;
            aes_load_key            <= 1'b0;
            aes_load_iv             <= 1'b0;
            aes_load_aad            <= 1'b0;
            aes_no_aad              <= 1'b0;
            aes_aad_last            <= 1'b0;
            aes_load_data           <= 1'b0;
            aes_data_in_last        <= 1'b0;
            aes_cipher_key          <= '0;
            aes_iv_in               <= 96'h0;
            aes_aad_in              <= 128'h0;
            aes_data_in             <= 128'h0;
            cur_aad_idx             <= 4'd0;
            cur_pt_idx              <= 4'd0;
            builder_send_ciphertext <= 1'b0;
            builder_ct_len_bytes    <= 8'h00;
            builder_send_auth_tag   <= 1'b0;
            builder_send_verify     <= 1'b0;
        end else begin
            aes_load_key            <= 1'b0;
            aes_load_iv             <= 1'b0;
            reg_load_tag_ref        <= 1'b0;
            reg_verify_checked      <= 1'b0;
            aes_load_aad            <= 1'b0;
            aes_no_aad              <= 1'b0;
            aes_aad_last            <= 1'b0;
            aes_load_data           <= 1'b0;
            aes_data_in_last        <= 1'b0;
            builder_send_ciphertext <= 1'b0;
            builder_send_auth_tag   <= 1'b0;
            builder_send_verify     <= 1'b0;

            case (wrap_state)
                WRAP_IDLE: begin
                    cur_aad_idx  <= 4'd0;
                    cur_pt_idx   <= 4'd0;
                    tag_ref_sent <= 1'b0;

                    if (start_requested && !start_refused) begin
                        // 0 = Encryption, 1 = Decryption
                        reg_aes_mode   <= parser_cmd_start_decrypt_done;
                        aes_cipher_key <= reg_key[KEY_BITS-1:0];
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
                    // In Decryption mode, satisfy CU's WAIT_TAG_REF handshake
                    if (reg_aes_mode && aes_tag_ref_ready && !tag_ref_sent) begin
                        reg_load_tag_ref <= 1'b1;
                        tag_ref_sent     <= 1'b1;
                    end

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
                                wrap_state   <= WRAP_HOLD_AAD_LAST;
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

                WRAP_HOLD_AAD_LAST: begin
                    aes_load_aad <= 1'b0;
                    aes_aad_last <= 1'b1;
                    wrap_state   <= WRAP_WAIT_DATA_READY;
                end

                WRAP_WAIT_DATA_READY: begin
                    if (aes_data_ready) begin
                        cur_pt_idx    <= 4'd0;
                        aes_data_in   <= mem_pt[0];
                        aes_load_data <= 1'b1;
                        if (cnt_pt_blocks == 4'd1) begin
                            aes_data_in_last <= 1'b1;
                            wrap_state       <= WRAP_HOLD_PT_LAST;
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

                WRAP_HOLD_PT_LAST: begin
                    aes_load_data    <= 1'b0;
                    aes_data_in_last <= 1'b1;
                    wrap_state       <= WRAP_WAIT_PIPELINE;
                end

                WRAP_WAIT_PIPELINE: begin
                    if (reg_aes_mode && aes_verify_done) begin
                        reg_verify_checked <= 1'b1;
                    end
                    if ((cnt_ct_captured == cnt_pt_blocks) && reg_tag_captured) begin
                        // A failed decrypt never leaves the IP
                        wrap_state <= (reg_aes_mode && !reg_verify_pass) ? WRAP_SEND_TAG : WRAP_SEND_CT;
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
                        wrap_state <= reg_aes_mode ? WRAP_SEND_VERIFY : WRAP_IDLE;
                    end
                end

                WRAP_SEND_VERIFY: begin
                    builder_send_verify <= 1'b1;
                    wrap_state          <= WRAP_WAIT_VERIFY_SENT;
                end

                WRAP_WAIT_VERIFY_SENT: begin
                    if (builder_packet_sent) begin
                        wrap_state <= WRAP_IDLE;
                    end
                end

                default: begin
                    wrap_state <= WRAP_IDLE;
                end
            endcase
        end
    end

    //-------------------------------------------------------------------------
    // Diagnostic 1 Hz Heartbeat Generator & Status Diagnostics
    // - led_busy (Pin T18): High when FPGA is actively calculating encryption
    // - led_done (Pin V17):
    //     * In WRAP_IDLE: Pulses as a 1.0 Hz Heartbeat (0.5s ON, 0.5s OFF)
    //       verifying clock frequency and reset release on the FPGA.
    //     * On packet completion: Stays solid ON while the last response leaves.
    //-------------------------------------------------------------------------
    localparam int HEARTBEAT_HALF_PERIOD = CLK_FREQ_HZ / 2;
    logic [31:0] heartbeat_cnt;
    logic        heartbeat_toggle;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            heartbeat_cnt    <= 32'd0;
            heartbeat_toggle <= 1'b0;
        end else begin
            if (heartbeat_cnt >= HEARTBEAT_HALF_PERIOD - 1) begin
                heartbeat_cnt    <= 32'd0;
                heartbeat_toggle <= ~heartbeat_toggle;
            end else begin
                heartbeat_cnt    <= heartbeat_cnt + 1'b1;
            end
        end
    end

    always_comb begin
        led_busy   = (wrap_state != WRAP_IDLE);
        led_done   = (wrap_state == WRAP_IDLE) ? heartbeat_toggle
                                               : ((wrap_state == WRAP_WAIT_TAG_SENT) || (wrap_state == WRAP_WAIT_VERIFY_SENT));
        led_unused = 5'b00000; // Actively drive remaining onboard LEDs (LED3..LED7) LOW (OFF)
    end

endmodule
