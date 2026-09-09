//=============================================================================
// Testbench: tb_aes256_uart_wrapper.sv
// Directory: uart_integration/aes256/
// Description: Self-checking testbench for aes256_uart_wrapper.
//              Simulates bit-accurate UART communication across physical pins,
//              decodes responses, and validates against official NIST SP 800-38D
//              AES-256-GCM Appendix B Test Cases (TC16 & TC17).
//=============================================================================

`timescale 1ns / 1ps

import protocol_pkg::*;

module tb_aes256_uart_wrapper;

    localparam time CLK_PERIOD  = 10ns;
    localparam int  CLK_FREQ_HZ = 100_000_000;
    localparam int  BAUD_RATE   = 10_000_000; // Accelerated for fast simulation
    localparam time BIT_PERIOD  = 1s / BAUD_RATE;

    logic clk;
    logic rst_n;
    logic uart_rx;
    logic uart_tx;
    logic led_busy;
    logic led_done;

    int test_count  = 0;
    int error_count = 0;

    aes256_uart_wrapper #(
        .CLK_FREQ_HZ(CLK_FREQ_HZ),
        .BAUD_RATE  (BAUD_RATE)
    ) dut (
        .clk     (clk),
        .rst_n   (rst_n),
        .uart_rx (uart_rx),
        .uart_tx (uart_tx),
        .led_busy(led_busy),
        .led_done(led_done)
    );

    initial begin
        clk = 1'b0;
        forever #(CLK_PERIOD / 2) clk = ~clk;
    end

    initial begin
        $dumpfile("tb_aes256_uart_wrapper.vcd");
        $dumpvars(0, tb_aes256_uart_wrapper);
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

    initial begin
        uart_rx = 1'b1;
        rst_n   = 1'b0;

        $display("==========================================================");
        $display(" AES-256-GCM UART Wrapper Self-Checking Testbench");
        $display(" Reference: NIST SP 800-38D Appendix B (TC16 & TC17)");
        $display(" Clock: %0d MHz, Baud: %0d bps", CLK_FREQ_HZ/1_000_000, BAUD_RATE);
        $display("==========================================================");

        #(CLK_PERIOD * 10);
        @(posedge clk);
        rst_n <= 1'b1;
        #(CLK_PERIOD * 20);

        //-------------------------------------------------------------
        // Test 1: NIST SP 800-38D Appendix B - Test Case 16 (AES-256, 16B PT)
        // Key:  32 zero bytes
        // IV:   12 zero bytes
        // PT:   16 zero bytes
        // Exp CT:  cea7403d4d606b6e074ec5d3baf39d18
        // Exp TAG: d0d1c8a799996bf0265b98b5d48ab919
        //-------------------------------------------------------------
        $display("\n>>> TEST 1: NIST Appendix B - Test Case 16 (256-bit Key, 16B PT)");
        begin
            logic [7:0] key_tc16[32];
            logic [7:0] iv_tc16[12];
            logic [7:0] pt_tc16[16];
            logic [7:0] exp_ct_tc16[16] = '{
                8'hce,8'ha7,8'h40,8'h3d,8'h4d,8'h60,8'h6b,8'h6e,
                8'h07,8'h4e,8'hc5,8'hd3,8'hba,8'hf3,8'h9d,8'h18
            };
            logic [7:0] exp_tag_tc16[16] = '{
                8'hd0,8'hd1,8'hc8,8'ha7,8'h99,8'h99,8'h6b,8'hf0,
                8'h26,8'h5b,8'h98,8'hb5,8'hd4,8'h8a,8'hb9,8'h19
            };
            logic [7:0] empty_payload[];
            logic [7:0] rx_cmd;
            logic [7:0] rx_ct[];
            logic [7:0] rx_tag[];

            for (int i = 0; i < 32; i++) key_tc16[i] = 8'h00;
            for (int i = 0; i < 12; i++) iv_tc16[i]  = 8'h00;
            for (int i = 0; i < 16; i++) pt_tc16[i]  = 8'h00;

            // Load 32-byte (256-bit) Key
            send_packet(CMD_LOAD_KEY, key_tc16);
            verify_ack("LOAD_KEY (TC16 - 256-bit)", RESP_ACK_KEY);

            send_packet(CMD_LOAD_IV, iv_tc16);
            verify_ack("LOAD_IV (TC16)", RESP_ACK_IV);

            send_packet(CMD_LOAD_PLAINTEXT, pt_tc16);
            verify_ack("LOAD_PLAINTEXT (TC16)", RESP_ACK_PLAINTEXT);

            empty_payload = new[0];
            send_packet(CMD_START_ENCRYPT, empty_payload);

            test_count++;
            receive_packet(rx_cmd, rx_ct);
            if (rx_cmd === RESP_CIPHERTEXT && rx_ct.size() == 16) begin
                int ct_match = 1;
                for (int i = 0; i < 16; i++) if (rx_ct[i] !== exp_ct_tc16[i]) ct_match = 0;
                if (ct_match) $display("  [PASS] CIPHERTEXT (TC16) matched NIST specification.");
                else begin
                    $display("  [FAIL] CIPHERTEXT (TC16) content mismatch!");
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
                for (int i = 0; i < 16; i++) if (rx_tag[i] !== exp_tag_tc16[i]) tag_match = 0;
                if (tag_match) $display("  [PASS] AUTH_TAG (TC16) matched NIST specification.");
                else begin
                    $display("  [FAIL] AUTH_TAG (TC16) content mismatch!");
                    error_count++;
                end
            end else begin
                $display("  [FAIL] Expected AUTH_TAG (0x91), got 0x%02h", rx_cmd);
                error_count++;
            end
        end

        //-------------------------------------------------------------
        // Test 2: NIST SP 800-38D Appendix B - Test Case 17 (256-bit Key, 64B PT)
        // Key:  feffe9928665731c6d6a8f9467308308feffe9928665731c6d6a8f9467308308
        // IV:   cafebabefacedebadecaf888
        // PT:   d9313225f88406e5a55909c5aff5269a86a7a9531534f7da2e4c303d8a318a72...
        // Exp CT:  522dc1f099567d07f47f37a32a84427d643a8cdcbfe5c0c97598a2bd2555d3aa...
        // Exp TAG: a34988770c1e0d2949cb9e7b30c8400f
        //-------------------------------------------------------------
        $display("\n>>> TEST 2: NIST Appendix B - Test Case 17 (256-bit Key, 64B PT)");
        begin
            logic [7:0] key_tc17[32] = '{
                8'hfe,8'hff,8'he9,8'h92,8'h86,8'h65,8'h73,8'h1c,
                8'h6d,8'h6a,8'h8f,8'h94,8'h67,8'h30,8'h83,8'h08,
                8'hfe,8'hff,8'he9,8'h92,8'h86,8'h65,8'h73,8'h1c,
                8'h6d,8'h6a,8'h8f,8'h94,8'h67,8'h30,8'h83,8'h08
            };
            logic [7:0] iv_tc17[12] = '{
                8'hca,8'hfe,8'hba,8'hbe,8'hfa,8'hce,8'hdb,8'had,8'hde,8'hca,8'hf8,8'h88
            };
            logic [7:0] pt_tc17[64] = '{
                8'hd9,8'h31,8'h32,8'h25,8'hf8,8'h84,8'h06,8'he5,8'ha5,8'h59,8'h09,8'hc5,8'haf,8'hf5,8'h26,8'h9a,
                8'h86,8'ha7,8'ha9,8'h53,8'h15,8'h34,8'hf7,8'hda,8'h2e,8'h4c,8'h30,8'h3d,8'h8a,8'h31,8'h8a,8'h72,
                8'h1c,8'h3c,8'h0c,8'h95,8'h95,8'h68,8'h09,8'h53,8'h2f,8'hcf,8'h0e,8'h24,8'h49,8'ha6,8'hb5,8'h25,
                8'hb1,8'h6a,8'hed,8'hf5,8'haa,8'h0d,8'he6,8'h57,8'hba,8'h63,8'h7b,8'h39,8'h1a,8'haf,8'hd2,8'h55
            };
            logic [7:0] exp_ct_tc17[64] = '{
                8'h52,8'h2d,8'hc1,8'hf0,8'h99,8'h56,8'h7d,8'h07,8'hf4,8'h7f,8'h37,8'ha3,8'h2a,8'h84,8'h42,8'h7d,
                8'h64,8'h3a,8'h8c,8'hdc,8'hbf,8'he5,8'hc0,8'hc9,8'h75,8'h98,8'ha2,8'hbd,8'h25,8'h55,8'hd3,8'haa,
                8'h8c,8'hb1,8'hd8,8'h37,8'h05,8'hd8,8'hf8,8'h01,8'hde,8'h04,8'h77,8'h27,8'h4f,8'hf7,8'h3f,8'h56,
                8'h30,8'h2d,8'hd5,8'hd1,8'hdf,8'hcd,8'h1f,8'h50,8'h24,8'h4d,8'hb5,8'h42,8'h96,8'h04,8'h1b,8'h46
            };
            logic [7:0] exp_tag_tc17[16] = '{
                8'ha3,8'h49,8'h88,8'h77,8'h0c,8'h1e,8'h0d,8'h29,
                8'h49,8'hcb,8'h9e,8'h7b,8'h30,8'hc8,8'h40,8'h0f
            };
            logic [7:0] empty_payload[];
            logic [7:0] rx_cmd;
            logic [7:0] rx_ct[];
            logic [7:0] rx_tag[];

            send_packet(CMD_LOAD_KEY, key_tc17);
            verify_ack("LOAD_KEY (TC17 - 256-bit)", RESP_ACK_KEY);

            send_packet(CMD_LOAD_IV, iv_tc17);
            verify_ack("LOAD_IV (TC17)", RESP_ACK_IV);

            send_packet(CMD_LOAD_PLAINTEXT, pt_tc17);
            verify_ack("LOAD_PLAINTEXT (TC17)", RESP_ACK_PLAINTEXT);

            empty_payload = new[0];
            send_packet(CMD_START_ENCRYPT, empty_payload);

            test_count++;
            receive_packet(rx_cmd, rx_ct);
            if (rx_cmd === RESP_CIPHERTEXT && rx_ct.size() == 64) begin
                int ct_match = 1;
                for (int i = 0; i < 64; i++) if (rx_ct[i] !== exp_ct_tc17[i]) ct_match = 0;
                if (ct_match) $display("  [PASS] CIPHERTEXT (TC17 - 64B) matched NIST specification.");
                else begin
                    $display("  [FAIL] CIPHERTEXT (TC17 - 64B) content mismatch!");
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
                for (int i = 0; i < 16; i++) if (rx_tag[i] !== exp_tag_tc17[i]) tag_match = 0;
                if (tag_match) $display("  [PASS] AUTH_TAG (TC17) matched NIST specification.");
                else begin
                    $display("  [FAIL] AUTH_TAG (TC17) content mismatch!");
                    error_count++;
                end
            end else begin
                $display("  [FAIL] Expected AUTH_TAG (0x91), got 0x%02h", rx_cmd);
                error_count++;
            end
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
