//=============================================================================
// Module: aes128_uart_wrapper.sv
// Directory: uart_integration/aes128/
// Description: Dedicated UART integration wrapper connecting physical UART
//              pins to the AES-128-GCM hardware accelerator (RTL/AES_GCM.sv).
//
// Target: Microchip PolarFire SoC Discovery Kit (MPFS095T-1FCSG325E)
//
// Features:
//   - Connects 128-bit key (reg_key[127:0]) to AES_GCM
//   - Instantiates shared common UART components (uart_rx, uart_tx, parser, builder)
//   - Strobe/handshake driven (absorbs 12-cycle pipeline latency automatically)
//=============================================================================

`timescale 1ns / 1ps

import protocol_pkg::*;

module aes128_uart_wrapper #(
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
    // Internal Signals: AES-128 Core Interface
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
    logic [127:0] aes_cipher_key;
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
    assign aes_mode         = 1'b0; // 0 = Encryption
    assign aes_load_tag_ref = 1'b0;
    assign aes_tag_ref      = 128'h0;

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

    // Existing AES-128 GCM Core (RTL/AES_GCM.sv)
    AES_GCM u_aes128_gcm (
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
        .data_out             (aes_data_out)
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
    // Capture Outputs from AES-128 Core
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
            aes_cipher_key          <= 128'h0;
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
                        // AES-128 receives lower 128 bits of key
                        aes_cipher_key <= reg_key[127:0];
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
