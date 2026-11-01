//=============================================================================
// Testbench: tb_aes256_uart_wrapper.sv
// Directory: realtime_env/rtl/aes256/
// Description: Self-checking testbench for aes256_uart_wrapper.
//              Simulates bit-accurate UART communication across physical pins,
//              decodes responses, and validates against the AES-256 test cases TC14 & TC15
//              of gcm-spec.pdf Appendix B.
//=============================================================================

`timescale 1ns / 1ps

import protocol_pkg::*;

module tb_aes256_uart_wrapper;

    localparam time CLK_PERIOD  = 20ns;
    localparam int  CLK_FREQ_HZ = 50_000_000;
    localparam int  BAUD_RATE   = 10_000_000; // Accelerated for fast simulation
    localparam time BIT_PERIOD  = 1s / BAUD_RATE;

    logic clk;
    logic rst_n;
    logic uart_rx;
    logic uart_tx;
    logic led_busy;
    logic led_done;
    logic [4:0] led_unused;

    int test_count  = 0;
    int error_count = 0;

    aes256_uart_wrapper #(
        .CLK_FREQ_HZ(CLK_FREQ_HZ),
        .BAUD_RATE  (BAUD_RATE)
    ) dut (
        .clk        (clk),
        .rst_n      (rst_n),
        .uart_rx    (uart_rx),
        .uart_tx    (uart_tx),
        .led_busy   (led_busy),
        .led_done   (led_done),
        .led_unused (led_unused)
    );

    initial begin
        clk = 1'b0;
        forever #(CLK_PERIOD / 2) clk = ~clk;
    end

    initial begin
        if ($test$plusargs("dump")) begin
            $dumpfile("tb_aes256_uart_wrapper.vcd");
            $dumpvars(0, tb_aes256_uart_wrapper);
        end
    end

    // UART Bit-level Transmitter Task
    task automatic uart_tx_byte(input logic [7:0] data);
        begin
            uart_rx <= 1'b0; // Start
            #(BIT_PERIOD);
            for (int i = 0; i < 8; i++) begin
                uart_rx <= data[i];
                #(BIT_PERIOD);
            end
            uart_rx <= 1'b1; // Stop
            #(BIT_PERIOD);
        end
    endtask

    // Packet Sender
    task automatic send_packet(input logic [7:0] cmd, input logic [7:0] payload[]);
        begin
            int len;
            len = payload.size();
            uart_tx_byte(cmd);
            uart_tx_byte(8'(len));
            for (int i = 0; i < len; i++) begin
                uart_tx_byte(payload[i]);
            end
        end
    endtask

    // UART Bit-level Receiver Monitor Task
    task automatic uart_rx_byte(output logic [7:0] data, input time timeout = 5ms);
        time start_time;
        begin
            start_time = $time;
            while (uart_tx !== 1'b0) begin
                if (($time - start_time) > timeout) begin
                    $display("  [ERROR] Timeout waiting for UART start bit on uart_tx!");
                    error_count++;
                    return;
                end
                #1ns;
            end

            #(BIT_PERIOD / 2);
            if (uart_tx !== 1'b0) begin
                $display("  [ERROR] False start bit on uart_tx!");
                error_count++;
                return;
            end

            for (int i = 0; i < 8; i++) begin
                #(BIT_PERIOD);
                data[i] = uart_tx;
            end

            #(BIT_PERIOD);
            if (uart_tx !== 1'b1) begin
                $display("  [ERROR] Framing error: Missing stop bit!");
                error_count++;
            end
            #(BIT_PERIOD / 2);
        end
    endtask

    // Packet Receiver
    task automatic receive_packet(output logic [7:0] resp_cmd, output logic [7:0] resp_payload[]);
        logic [7:0] cmd_b;
        logic [7:0] len_b;
        begin
            uart_rx_byte(cmd_b);
            uart_rx_byte(len_b);
            resp_cmd = cmd_b;
            resp_payload = new[len_b];
            for (int i = 0; i < len_b; i++) begin
                uart_rx_byte(resp_payload[i]);
            end
        end
    endtask

    // Verify ACK
    task automatic verify_ack(input string name, input logic [7:0] expected_ack);
        logic [7:0] r_cmd;
        logic [7:0] r_payload[];
        begin
            test_count++;
            receive_packet(r_cmd, r_payload);
            if (r_cmd === expected_ack && r_payload.size() == 0) begin
                $display("  [PASS] %s: Received ACK (0x%02h)", name, r_cmd);
            end else begin
                $display("  [FAIL] %s: Expected ACK 0x%02h, got 0x%02h (len=%0d)",
                         name, expected_ack, r_cmd, r_payload.size());
                error_count++;
            end
        end
    endtask

    // Fails unless the next packet is exactly `expected_cmd` carrying `expected`
    task automatic expect_packet(input string name, input logic [7:0] expected_cmd,
                                 input logic [7:0] expected[], input time timeout = 5ms);
        logic [7:0] cmd_b;
        logic [7:0] len_b;
        logic [7:0] payload[];
        begin
            test_count++;
            uart_rx_byte(cmd_b, timeout);
            uart_rx_byte(len_b);
            payload = new[$isunknown(len_b) ? 0 : len_b];
            for (int i = 0; i < payload.size(); i++) uart_rx_byte(payload[i]);
            if (cmd_b === expected_cmd && payload == expected) begin
                $display("  [PASS] %s: Received 0x%02h (%0d bytes)", name, cmd_b, len_b);
            end else begin
                $display("  [FAIL] %s: Expected 0x%02h (%0d bytes), got 0x%02h (%0d bytes)",
                         name, expected_cmd, expected.size(), cmd_b, len_b);
                error_count++;
            end
        end
    endtask

    // Loads a message for decryption, with `tag` as the reference when `use_tag` is set
    task automatic load_decrypt(input logic [7:0] key[], input logic [7:0] iv[], input logic [7:0] ct[],
                                input logic [7:0] tag[], input bit use_tag);
        begin
            send_packet(CMD_LOAD_KEY, key);
            verify_ack("LOAD_KEY (decrypt)", RESP_ACK_KEY);
            send_packet(CMD_LOAD_IV, iv);
            verify_ack("LOAD_IV (decrypt)", RESP_ACK_IV);
            send_packet(CMD_LOAD_PLAINTEXT, ct);
            verify_ack("LOAD_PLAINTEXT (decrypt)", RESP_ACK_PLAINTEXT);
            if (use_tag) begin
                send_packet(CMD_LOAD_TAG_REF, tag);
                verify_ack("LOAD_TAG_REF", RESP_ACK_TAG_REF);
            end
        end
    endtask

    initial begin
        uart_rx = 1'b1;
        rst_n   = 1'b0;

        $display("==========================================================");
        $display(" AES-256-GCM UART Wrapper Self-Checking Testbench");
        $display(" Reference: gcm-spec.pdf Appendix B (TC14 & TC15)");
        $display(" Clock: %0d MHz, Baud: %0d bps", CLK_FREQ_HZ/1_000_000, BAUD_RATE);
        $display("==========================================================");

        #(CLK_PERIOD * 10);
        @(posedge clk);
        rst_n <= 1'b1;
        #(CLK_PERIOD * 20);

        //-------------------------------------------------------------
        // Test 1: gcm-spec.pdf Appendix B - Test Case 14 (AES-256, 16B PT)
        // Key:  32 zero bytes
        // IV:   12 zero bytes
        // PT:   16 zero bytes
        // Exp CT:  cea7403d4d606b6e074ec5d3baf39d18
        // Exp TAG: d0d1c8a799996bf0265b98b5d48ab919
        //-------------------------------------------------------------
        $display("\n>>> TEST 1: GCM spec Appendix B - Test Case 14 (256-bit Key, 16B PT)");
        begin
            logic [7:0] key_tc14[32];
            logic [7:0] iv_tc14[12];
            logic [7:0] pt_tc14[16];
            logic [7:0] exp_ct_tc14[16] = '{
                8'hce,8'ha7,8'h40,8'h3d,8'h4d,8'h60,8'h6b,8'h6e,
                8'h07,8'h4e,8'hc5,8'hd3,8'hba,8'hf3,8'h9d,8'h18
            };
            logic [7:0] exp_tag_tc14[16] = '{
                8'hd0,8'hd1,8'hc8,8'ha7,8'h99,8'h99,8'h6b,8'hf0,
                8'h26,8'h5b,8'h98,8'hb5,8'hd4,8'h8a,8'hb9,8'h19
            };
            logic [7:0] empty_payload[];
            logic [7:0] rx_cmd;
            logic [7:0] rx_ct[];
            logic [7:0] rx_tag[];

            for (int i = 0; i < 32; i++) key_tc14[i] = 8'h00;
            for (int i = 0; i < 12; i++) iv_tc14[i]  = 8'h00;
            for (int i = 0; i < 16; i++) pt_tc14[i]  = 8'h00;

            // Load 32-byte (256-bit) Key
            send_packet(CMD_LOAD_KEY, key_tc14);
            verify_ack("LOAD_KEY (TC14 - 256-bit)", RESP_ACK_KEY);

            send_packet(CMD_LOAD_IV, iv_tc14);
            verify_ack("LOAD_IV (TC14)", RESP_ACK_IV);

            send_packet(CMD_LOAD_PLAINTEXT, pt_tc14);
            verify_ack("LOAD_PLAINTEXT (TC14)", RESP_ACK_PLAINTEXT);

            empty_payload = new[0];
            send_packet(CMD_START_ENCRYPT, empty_payload);

            test_count++;
            receive_packet(rx_cmd, rx_ct);
            if (rx_cmd === RESP_CIPHERTEXT && rx_ct.size() == 16) begin
                int ct_match = 1;
                for (int i = 0; i < 16; i++) if (rx_ct[i] !== exp_ct_tc14[i]) ct_match = 0;
                if (ct_match) $display("  [PASS] CIPHERTEXT (TC14) matched GCM spec vector.");
                else begin
                    $display("  [FAIL] CIPHERTEXT (TC14) content mismatch!");
                    error_count++;
                end
            end else begin
                $display("  [FAIL] Expected CIPHERTEXT (0x90), got 0x%02h", rx_cmd);
                error_count++;
            end

            test_count++;
            receive_packet(rx_cmd, rx_tag);
            if (rx_cmd === RESP_AUTH_TAG && rx_tag.size() == 16) begin
                int tag_match = 1;
                for (int i = 0; i < 16; i++) if (rx_tag[i] !== exp_tag_tc14[i]) tag_match = 0;
                if (tag_match) $display("  [PASS] AUTH_TAG (TC14) matched GCM spec vector.");
                else begin
                    $display("  [FAIL] AUTH_TAG (TC14) content mismatch!");
                    error_count++;
                end
            end else begin
                $display("  [FAIL] Expected AUTH_TAG (0x91), got 0x%02h", rx_cmd);
                error_count++;
            end
        end

        //-------------------------------------------------------------
        // Test 2: gcm-spec.pdf Appendix B - Test Case 15 (256-bit Key, 64B PT)
        // Key:  feffe9928665731c6d6a8f9467308308feffe9928665731c6d6a8f9467308308
        // IV:   cafebabefacedbaddecaf888
        // PT:   d9313225f88406e5a55909c5aff5269a86a7a9531534f7da2e4c303d8a318a72...
        // Exp CT:  522dc1f099567d07f47f37a32a84427d643a8cdcbfe5c0c97598a2bd2555d1aa...
        // Exp TAG: b094dac5d93471bdec1a502270e3cc6c
        //-------------------------------------------------------------
        $display("\n>>> TEST 2: GCM spec Appendix B - Test Case 15 (256-bit Key, 64B PT)");
        begin
            logic [7:0] key_tc15[32] = '{
                8'hfe,8'hff,8'he9,8'h92,8'h86,8'h65,8'h73,8'h1c,
                8'h6d,8'h6a,8'h8f,8'h94,8'h67,8'h30,8'h83,8'h08,
                8'hfe,8'hff,8'he9,8'h92,8'h86,8'h65,8'h73,8'h1c,
                8'h6d,8'h6a,8'h8f,8'h94,8'h67,8'h30,8'h83,8'h08
            };
            logic [7:0] iv_tc15[12] = '{
                8'hca,8'hfe,8'hba,8'hbe,8'hfa,8'hce,8'hdb,8'had,8'hde,8'hca,8'hf8,8'h88
            };
            logic [7:0] pt_tc15[64] = '{
                8'hd9,8'h31,8'h32,8'h25,8'hf8,8'h84,8'h06,8'he5,8'ha5,8'h59,8'h09,8'hc5,8'haf,8'hf5,8'h26,8'h9a,
                8'h86,8'ha7,8'ha9,8'h53,8'h15,8'h34,8'hf7,8'hda,8'h2e,8'h4c,8'h30,8'h3d,8'h8a,8'h31,8'h8a,8'h72,
                8'h1c,8'h3c,8'h0c,8'h95,8'h95,8'h68,8'h09,8'h53,8'h2f,8'hcf,8'h0e,8'h24,8'h49,8'ha6,8'hb5,8'h25,
                8'hb1,8'h6a,8'hed,8'hf5,8'haa,8'h0d,8'he6,8'h57,8'hba,8'h63,8'h7b,8'h39,8'h1a,8'haf,8'hd2,8'h55
            };
            logic [7:0] exp_ct_tc15[64] = '{
                8'h52,8'h2d,8'hc1,8'hf0,8'h99,8'h56,8'h7d,8'h07,8'hf4,8'h7f,8'h37,8'ha3,8'h2a,8'h84,8'h42,8'h7d,
                8'h64,8'h3a,8'h8c,8'hdc,8'hbf,8'he5,8'hc0,8'hc9,8'h75,8'h98,8'ha2,8'hbd,8'h25,8'h55,8'hd1,8'haa,
                8'h8c,8'hb0,8'h8e,8'h48,8'h59,8'h0d,8'hbb,8'h3d,8'ha7,8'hb0,8'h8b,8'h10,8'h56,8'h82,8'h88,8'h38,
                8'hc5,8'hf6,8'h1e,8'h63,8'h93,8'hba,8'h7a,8'h0a,8'hbc,8'hc9,8'hf6,8'h62,8'h89,8'h80,8'h15,8'had
            };
            logic [7:0] exp_tag_tc15[16] = '{
                8'hb0,8'h94,8'hda,8'hc5,8'hd9,8'h34,8'h71,8'hbd,
                8'hec,8'h1a,8'h50,8'h22,8'h70,8'he3,8'hcc,8'h6c
            };
            logic [7:0] empty_payload[];
            logic [7:0] rx_cmd;
            logic [7:0] rx_ct[];
            logic [7:0] rx_tag[];

            send_packet(CMD_LOAD_KEY, key_tc15);
            verify_ack("LOAD_KEY (TC15 - 256-bit)", RESP_ACK_KEY);

            send_packet(CMD_LOAD_IV, iv_tc15);
            verify_ack("LOAD_IV (TC15)", RESP_ACK_IV);

            send_packet(CMD_LOAD_PLAINTEXT, pt_tc15);
            verify_ack("LOAD_PLAINTEXT (TC15)", RESP_ACK_PLAINTEXT);

            empty_payload = new[0];
            send_packet(CMD_START_ENCRYPT, empty_payload);

            test_count++;
            receive_packet(rx_cmd, rx_ct);
            if (rx_cmd === RESP_CIPHERTEXT && rx_ct.size() == 64) begin
                int ct_match = 1;
                for (int i = 0; i < 64; i++) if (rx_ct[i] !== exp_ct_tc15[i]) ct_match = 0;
                if (ct_match) $display("  [PASS] CIPHERTEXT (TC15 - 64B) matched GCM spec vector.");
                else begin
                    $display("  [FAIL] CIPHERTEXT (TC15 - 64B) content mismatch!");
                    error_count++;
                end
            end else begin
                $display("  [FAIL] Expected CIPHERTEXT (0x90), got 0x%02h", rx_cmd);
                error_count++;
            end

            test_count++;
            receive_packet(rx_cmd, rx_tag);
            if (rx_cmd === RESP_AUTH_TAG && rx_tag.size() == 16) begin
                int tag_match = 1;
                for (int i = 0; i < 16; i++) if (rx_tag[i] !== exp_tag_tc15[i]) tag_match = 0;
                if (tag_match) $display("  [PASS] AUTH_TAG (TC15) matched GCM spec vector.");
                else begin
                    $display("  [FAIL] AUTH_TAG (TC15) content mismatch!");
                    error_count++;
                end
            end else begin
                $display("  [FAIL] Expected AUTH_TAG (0x91), got 0x%02h", rx_cmd);
                error_count++;
            end
        end

        //-------------------------------------------------------------
        // Tests 3-5: authenticated decryption inside the IP (TC15)
        //-------------------------------------------------------------
        begin
            automatic logic [7:0] key_tc15[] = '{
                8'hfe,8'hff,8'he9,8'h92,8'h86,8'h65,8'h73,8'h1c,
                8'h6d,8'h6a,8'h8f,8'h94,8'h67,8'h30,8'h83,8'h08,
                8'hfe,8'hff,8'he9,8'h92,8'h86,8'h65,8'h73,8'h1c,
                8'h6d,8'h6a,8'h8f,8'h94,8'h67,8'h30,8'h83,8'h08
            };
            automatic logic [7:0] iv_tc15[] = '{
                8'hca,8'hfe,8'hba,8'hbe,8'hfa,8'hce,8'hdb,8'had,8'hde,8'hca,8'hf8,8'h88
            };
            automatic logic [7:0] pt_tc15[] = '{
                8'hd9,8'h31,8'h32,8'h25,8'hf8,8'h84,8'h06,8'he5,8'ha5,8'h59,8'h09,8'hc5,8'haf,8'hf5,8'h26,8'h9a,
                8'h86,8'ha7,8'ha9,8'h53,8'h15,8'h34,8'hf7,8'hda,8'h2e,8'h4c,8'h30,8'h3d,8'h8a,8'h31,8'h8a,8'h72,
                8'h1c,8'h3c,8'h0c,8'h95,8'h95,8'h68,8'h09,8'h53,8'h2f,8'hcf,8'h0e,8'h24,8'h49,8'ha6,8'hb5,8'h25,
                8'hb1,8'h6a,8'hed,8'hf5,8'haa,8'h0d,8'he6,8'h57,8'hba,8'h63,8'h7b,8'h39,8'h1a,8'haf,8'hd2,8'h55
            };
            automatic logic [7:0] ct_tc15[] = '{
                8'h52,8'h2d,8'hc1,8'hf0,8'h99,8'h56,8'h7d,8'h07,8'hf4,8'h7f,8'h37,8'ha3,8'h2a,8'h84,8'h42,8'h7d,
                8'h64,8'h3a,8'h8c,8'hdc,8'hbf,8'he5,8'hc0,8'hc9,8'h75,8'h98,8'ha2,8'hbd,8'h25,8'h55,8'hd1,8'haa,
                8'h8c,8'hb0,8'h8e,8'h48,8'h59,8'h0d,8'hbb,8'h3d,8'ha7,8'hb0,8'h8b,8'h10,8'h56,8'h82,8'h88,8'h38,
                8'hc5,8'hf6,8'h1e,8'h63,8'h93,8'hba,8'h7a,8'h0a,8'hbc,8'hc9,8'hf6,8'h62,8'h89,8'h80,8'h15,8'had
            };
            automatic logic [7:0] tag_tc15[] = '{
                8'hb0,8'h94,8'hda,8'hc5,8'hd9,8'h34,8'h71,8'hbd,
                8'hec,8'h1a,8'h50,8'h22,8'h70,8'he3,8'hcc,8'h6c
            };
            logic [7:0] bad_tag[];
            logic [7:0] empty_payload[];
            automatic logic [7:0] code_decrypt[] = '{CMD_START_DECRYPT};
            automatic logic [7:0] code_key[]     = '{CMD_LOAD_KEY};
            automatic logic [7:0] code_pt[]      = '{CMD_LOAD_PLAINTEXT};
            automatic logic [7:0] code_odd[]     = '{8'h7F};
            automatic logic [7:0] verdict_pass[] = '{8'h01};
            automatic logic [7:0] verdict_fail[] = '{8'h00};
            automatic logic [7:0] short_key[]    = new[16];
            automatic logic [7:0] odd_payload[]  = '{8'h01, 8'h02, 8'h03};

            empty_payload = new[0];
            bad_tag = tag_tc15;
            bad_tag[15] ^= 8'h01;

            $display("\n>>> TEST 3: Decrypt with the right tag releases the plaintext");
            load_decrypt(key_tc15, iv_tc15, ct_tc15, tag_tc15, 1'b1);
            send_packet(CMD_START_DECRYPT, empty_payload);
            expect_packet("Recovered PLAINTEXT", RESP_CIPHERTEXT, pt_tc15);
            expect_packet("Computed AUTH_TAG", RESP_AUTH_TAG, tag_tc15);
            expect_packet("VERIFY_RESULT PASS", RESP_VERIFY_RESULT, verdict_pass);

            $display("\n>>> TEST 4: Decrypt with a wrong tag withholds the plaintext");
            load_decrypt(key_tc15, iv_tc15, ct_tc15, bad_tag, 1'b1);
            send_packet(CMD_START_DECRYPT, empty_payload);
            expect_packet("Computed AUTH_TAG, no plaintext", RESP_AUTH_TAG, tag_tc15);
            expect_packet("VERIFY_RESULT FAIL", RESP_VERIFY_RESULT, verdict_fail);

            $display("\n>>> TEST 5: Decrypt without LOAD_TAG_REF is refused");
            load_decrypt(key_tc15, iv_tc15, ct_tc15, tag_tc15, 1'b0);
            send_packet(CMD_START_DECRYPT, empty_payload);
            expect_packet("ERR_LEN for START_DECRYPT", RESP_ERR_LEN, code_decrypt);

            $display("\n>>> TEST 6: A packet cut short times out, then the link still works");
            uart_tx_byte(CMD_LOAD_PLAINTEXT);
            uart_tx_byte(8'd16);
            uart_tx_byte(8'hAA);
            expect_packet("ERR_TIMEOUT for LOAD_PLAINTEXT", RESP_ERR_TIMEOUT, code_pt, 20ms);
            send_packet(CMD_LOAD_IV, iv_tc15);
            verify_ack("LOAD_IV after the timeout", RESP_ACK_IV);

            $display("\n>>> TEST 7: A key of the wrong length is refused");
            send_packet(CMD_LOAD_KEY, short_key);
            expect_packet("ERR_LEN for a 16-byte key", RESP_ERR_LEN, code_key);

            $display("\n>>> TEST 8: An unknown opcode's payload is skipped");
            fork // The error follows the header, while the payload is still being sent
                send_packet(8'h7F, odd_payload);
                expect_packet("ERR_UNKNOWN", RESP_ERR_UNKNOWN, code_odd);
            join
            send_packet(CMD_LOAD_IV, iv_tc15);
            verify_ack("LOAD_IV after the unknown opcode", RESP_ACK_IV);
        end

        // Summary
        #(CLK_PERIOD * 100);
        $display("\n==========================================================");
        $display(" VERIFICATION SUMMARY: aes256_uart_wrapper");
        $display("   Total Checks : %0d", test_count);
        $display("   Passed       : %0d", test_count - error_count);
        $display("   Failed       : %0d", error_count);
        $display("==========================================================");

        if (error_count == 0) $display(" *** ALL AES-256 TESTS PASSED SUCCESSFULLY ***\n");
        else                  $error(" *** %0d VERIFICATION FAILURE(S) DETECTED ***\n", error_count);

        #(CLK_PERIOD * 50);
        $finish;
    end

endmodule
