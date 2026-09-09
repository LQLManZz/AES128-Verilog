//=============================================================================
// Testbench: tb_aes_uart_wrapper.sv
// Description: Fully self-checking testbench for aes_uart_wrapper.
//              Simulates bit-accurate UART communication across physical pins,
//              decodes responses, and validates against NIST SP 800-38D vectors.
//=============================================================================

`timescale 1ns / 1ps

module tb_aes_uart_wrapper;

    // Simulation Clock Parameters (100 MHz clock)
    localparam time CLK_PERIOD     = 10ns;
    localparam int  CLK_FREQ_HZ    = 100_000_000;
    // Accelerated baud rate for rapid simulation turnaround
    localparam int  BAUD_RATE      = 10_000_000; 
    localparam time BIT_PERIOD     = 1s / BAUD_RATE; // 100ns = 10 clock cycles

    // DUT Signals
    logic clk;
    logic rst_n;
    logic uart_rx;
    logic uart_tx;
    logic led_busy;
    logic led_done;

    // Testbench Scoreboard Counters
    int test_count  = 0;
    int error_count = 0;

    // DUT Instantiation
    aes_uart_wrapper #(
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

    // 100 MHz Clock Generation
    initial begin
        clk = 1'b0;
        forever #(CLK_PERIOD / 2) clk = ~clk;
    end

    // Waveform Dump
    initial begin
        $dumpfile("tb_aes_uart_wrapper.vcd");
        $dumpvars(0, tb_aes_uart_wrapper);
    end

    //-------------------------------------------------------------------------
    // Task: Transmit 1 Byte via UART (8N1, LSB First)
    //-------------------------------------------------------------------------
    task automatic uart_tx_byte(input logic [7:0] data);
        begin
            // Start Bit (0)
            uart_rx <= 1'b0;
            #(BIT_PERIOD);

            // 8 Data Bits (LSB First)
            for (int i = 0; i < 8; i++) begin
                uart_rx <= data[i];
                #(BIT_PERIOD);
            end

            // Stop Bit (1)
            uart_rx <= 1'b1;
            #(BIT_PERIOD);
        end
    endtask

    //-------------------------------------------------------------------------
    // Task: Send Full Binary Packet [CMD, LENGTH, PAYLOAD...]
    //-------------------------------------------------------------------------
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

    //-------------------------------------------------------------------------
    // Task: Receive 1 Byte via UART (8N1 Monitor on uart_tx)
    //-------------------------------------------------------------------------
    task automatic uart_rx_byte(output logic [7:0] data, input time timeout = 5ms);
        time start_time;
        begin
            start_time = $time;
            // Wait for falling edge of Start Bit
            while (uart_tx !== 1'b0) begin
                if (($time - start_time) > timeout) begin
                    $display("  [ERROR] Timeout waiting for UART start bit on uart_tx!");
                    error_count++;
                    return;
                end
                #1ns;
            end

            // Sample in the middle of Start Bit
            #(BIT_PERIOD / 2);
            if (uart_tx !== 1'b0) begin
                $display("  [ERROR] False start bit detected on uart_tx!");
                error_count++;
                return;
            end

            // Sample 8 Data Bits (LSB First)
            for (int i = 0; i < 8; i++) begin
                #(BIT_PERIOD);
                data[i] = uart_tx;
            end

            // Sample Stop Bit
            #(BIT_PERIOD);
            if (uart_tx !== 1'b1) begin
                $display("  [ERROR] Framing error: Missing stop bit on uart_tx!");
                error_count++;
            end

            // Hold remainder of stop bit
            #(BIT_PERIOD / 2);
        end
    endtask

    //-------------------------------------------------------------------------
    // Task: Receive Full Response Packet from DUT
    //-------------------------------------------------------------------------
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

    //-------------------------------------------------------------------------
    // Task: Verify Expected ACK Packet
    //-------------------------------------------------------------------------
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

    //-------------------------------------------------------------------------
    // Main Verification Flow
    //-------------------------------------------------------------------------
    initial begin
        // Initialize line
        uart_rx = 1'b1;
        rst_n   = 1'b0;

        $display("==========================================================");
        $display(" AES-GCM UART Integration Self-Checking Testbench");
        $display(" Target: PolarFire SoC Discovery Kit Architecture");
        $display(" Clock: %0d MHz, Baud: %0d bps", CLK_FREQ_HZ/1_000_000, BAUD_RATE);
        $display("==========================================================");

        // Global Reset
        #(CLK_PERIOD * 10);
        @(posedge clk);
        rst_n <= 1'b1;
        #(CLK_PERIOD * 20);

        //=====================================================================
        // TEST CASE 1: NIST SP 800-38D Appendix B - Test Case 2
        // Key:  16 zero bytes
        // IV:   12 zero bytes
        // AAD:  None (0 bytes)
        // PT:   16 zero bytes
        // Exp CT:  0388dace60b6a392f328c2b971b2fe78
        // Exp TAG: ab6e47d42cec13bdf53a67b21257bddf
        //=====================================================================
        $display("\n>>> TEST 1: NIST Appendix B - Test Case 2 (16-byte PT, No AAD)");
        begin
            logic [7:0] key_tc2[16];
            logic [7:0] iv_tc2[12];
            logic [7:0] pt_tc2[16];
            logic [7:0] exp_ct_tc2[16] = '{
                8'h03,8'h88,8'hda,8'hce,8'h60,8'hb6,8'ha3,8'h92,
                8'hf3,8'h28,8'hc2,8'hb9,8'h71,8'hb2,8'hfe,8'h78
            };
            logic [7:0] exp_tag_tc2[16] = '{
                8'hab,8'h6e,8'h47,8'hd4,8'h2c,8'hec,8'h13,8'hbd,
                8'hf5,8'h3a,8'h67,8'hb2,8'h12,8'h57,8'hbd,8'hdf
            };
            logic [7:0] empty_payload[];
            logic [7:0] rx_cmd;
            logic [7:0] rx_ct[];
            logic [7:0] rx_tag[];

            for (int i = 0; i < 16; i++) key_tc2[i] = 8'h00;
            for (int i = 0; i < 12; i++) iv_tc2[i]  = 8'h00;
            for (int i = 0; i < 16; i++) pt_tc2[i]  = 8'h00;

            // 1. Load Key
            send_packet(8'h01, key_tc2);
            verify_ack("LOAD_KEY (TC2)", 8'h81);

            // 2. Load IV
            send_packet(8'h02, iv_tc2);
            verify_ack("LOAD_IV (TC2)", 8'h82);

            // 3. Load Plaintext
            send_packet(8'h04, pt_tc2);
            verify_ack("LOAD_PLAINTEXT (TC2)", 8'h84);

            // 4. Start Encryption
            empty_payload = new[0];
            send_packet(8'h05, empty_payload);

            // 5. Verify Ciphertext Packet (0x90)
            test_count++;
            receive_packet(rx_cmd, rx_ct);
            if (rx_cmd === 8'h90 && rx_ct.size() == 16) begin
                int ct_match = 1;
                for (int i = 0; i < 16; i++) begin
                    if (rx_ct[i] !== exp_ct_tc2[i]) ct_match = 0;
                end
                if (ct_match) begin
                    $display("  [PASS] CIPHERTEXT (TC2) matched NIST specification:");
                    $write("         CT = ");
                    for (int i = 0; i < 16; i++) $write("%02x", rx_ct[i]);
                    $write("\n");
                end else begin
                    $display("  [FAIL] CIPHERTEXT (TC2) content mismatch!");
                    error_count++;
                end
            end else begin
                $display("  [FAIL] Expected CIPHERTEXT packet 0x90, got 0x%02h", rx_cmd);
                error_count++;
            end

            // 6. Verify Authentication Tag Packet (0x91)
            test_count++;
            receive_packet(rx_cmd, rx_tag);
            if (rx_cmd === 8'h91 && rx_tag.size() == 16) begin
                int tag_match = 1;
                for (int i = 0; i < 16; i++) begin
                    if (rx_tag[i] !== exp_tag_tc2[i]) tag_match = 0;
                end
                if (tag_match) begin
                    $display("  [PASS] AUTH_TAG (TC2) matched NIST specification:");
                    $write("         TAG = ");
                    for (int i = 0; i < 16; i++) $write("%02x", rx_tag[i]);
                    $write("\n");
                end else begin
                    $display("  [FAIL] AUTH_TAG (TC2) content mismatch!");
                    error_count++;
                end
            end else begin
                $display("  [FAIL] Expected AUTH_TAG packet 0x91, got 0x%02h", rx_cmd);
                error_count++;
            end
        end

        //=====================================================================
        // TEST CASE 2: NIST SP 800-38D Appendix B - Test Case 3
        // Multi-block: 64-byte plaintext (4 blocks)
        // Key:  feffe9928665731c6d6a8f9467308308
        // IV:   cafebabefacedebadecaf888
        // AAD:  None (0 bytes)
        // Exp CT: 42831ec2217774244b7221b784d0d49c...
        // Exp TAG: 4d5c2af327cd64a62cf35abd2ba6fab4
        //=====================================================================
        $display("\n>>> TEST 2: NIST Appendix B - Test Case 3 (64-byte Multi-block PT)");
        begin
            logic [7:0] key_tc3[16] = '{
                8'hfe,8'hff,8'he9,8'h92,8'h86,8'h65,8'h73,8'h1c,
                8'h6d,8'h6a,8'h8f,8'h94,8'h67,8'h30,8'h83,8'h08
            };
            logic [7:0] iv_tc3[12] = '{
                8'hca,8'hfe,8'hba,8'hbe,8'hfa,8'hce,8'hdb,8'had,8'hde,8'hca,8'hf8,8'h88
            };
            logic [7:0] pt_tc3[64] = '{
                8'hd9,8'h31,8'h32,8'h25,8'hf8,8'h84,8'h06,8'he5,8'ha5,8'h59,8'h09,8'hc5,8'haf,8'hf5,8'h26,8'h9a,
                8'h86,8'ha7,8'ha9,8'h53,8'h15,8'h34,8'hf7,8'hda,8'h2e,8'h4c,8'h30,8'h3d,8'h8a,8'h31,8'h8a,8'h72,
                8'h1c,8'h3c,8'h0c,8'h95,8'h95,8'h68,8'h09,8'h53,8'h2f,8'hcf,8'h0e,8'h24,8'h49,8'ha6,8'hb5,8'h25,
                8'hb1,8'h6a,8'hed,8'hf5,8'haa,8'h0d,8'he6,8'h57,8'hba,8'h63,8'h7b,8'h39,8'h1a,8'haf,8'hd2,8'h55
            };
            logic [7:0] exp_ct_tc3[64] = '{
                8'h42,8'h83,8'h1e,8'hc2,8'h21,8'h77,8'h74,8'h24,8'h4b,8'h72,8'h21,8'hb7,8'h84,8'hd0,8'hd4,8'h9c,
                8'he3,8'haa,8'h21,8'h2f,8'h2c,8'h02,8'ha4,8'he0,8'h35,8'hc1,8'h7e,8'h23,8'h29,8'hac,8'ha1,8'h2e,
                8'h21,8'hd5,8'h14,8'hb2,8'h54,8'h66,8'h93,8'h1c,8'h7d,8'h8f,8'h6a,8'h5a,8'hac,8'h84,8'haa,8'h05,
                8'h1b,8'ha3,8'h0b,8'h39,8'h6a,8'h0a,8'hac,8'h97,8'h3d,8'h58,8'he0,8'h91,8'h47,8'h3f,8'h59,8'h85
            };
            logic [7:0] exp_tag_tc3[16] = '{
                8'h4d,8'h5c,8'h2a,8'hf3,8'h27,8'hcd,8'h64,8'ha6,
                8'h2c,8'hf3,8'h5a,8'hbd,8'h2b,8'ha6,8'hfa,8'hb4
            };
            logic [7:0] empty_payload[];
            logic [7:0] rx_cmd;
            logic [7:0] rx_ct[];
            logic [7:0] rx_tag[];

            // 1. Load Key
            send_packet(8'h01, key_tc3);
            verify_ack("LOAD_KEY (TC3)", 8'h81);

            // 2. Load IV
            send_packet(8'h02, iv_tc3);
            verify_ack("LOAD_IV (TC3)", 8'h82);

            // 3. Load Plaintext (64 bytes = 4 blocks)
            send_packet(8'h04, pt_tc3);
            verify_ack("LOAD_PLAINTEXT (TC3)", 8'h84);

            // 4. Start Encryption
            empty_payload = new[0];
            send_packet(8'h05, empty_payload);

            // 5. Verify 64-byte Ciphertext Packet
            test_count++;
            receive_packet(rx_cmd, rx_ct);
            if (rx_cmd === 8'h90 && rx_ct.size() == 64) begin
                int ct_match = 1;
                for (int i = 0; i < 64; i++) begin
                    if (rx_ct[i] !== exp_ct_tc3[i]) ct_match = 0;
                end
                if (ct_match) begin
                    $display("  [PASS] CIPHERTEXT (TC3 - 64B) matched NIST specification.");
                end else begin
                    $display("  [FAIL] CIPHERTEXT (TC3 - 64B) content mismatch!");
                    error_count++;
                end
            end else begin
                $display("  [FAIL] Expected CIPHERTEXT packet 0x90 with 64B, got cmd 0x%02h (len=%0d)",
                         rx_cmd, rx_ct.size());
                error_count++;
            end

            // 6. Verify Authentication Tag Packet
            test_count++;
            receive_packet(rx_cmd, rx_tag);
            if (rx_cmd === 8'h91 && rx_tag.size() == 16) begin
                int tag_match = 1;
                for (int i = 0; i < 16; i++) begin
                    if (rx_tag[i] !== exp_tag_tc3[i]) tag_match = 0;
                end
                if (tag_match) begin
                    $display("  [PASS] AUTH_TAG (TC3) matched NIST specification:");
                    $write("         TAG = ");
                    for (int i = 0; i < 16; i++) $write("%02x", rx_tag[i]);
                    $write("\n");
                end else begin
                    $display("  [FAIL] AUTH_TAG (TC3) content mismatch!");
                    error_count++;
                end
            end else begin
                $display("  [FAIL] Expected AUTH_TAG packet 0x91, got 0x%02h", rx_cmd);
                error_count++;
            end
        end

        //=====================================================================
        // Summary
        //=====================================================================
        #(CLK_PERIOD * 100);
        $display("\n==========================================================");
        $display(" VERIFICATION SUMMARY: aes_uart_wrapper");
        $display("   Total Checks : %0d", test_count);
        $display("   Passed       : %0d", test_count - error_count);
        $display("   Failed       : %0d", error_count);
        $display("==========================================================");

        if (error_count == 0) begin
            $display(" *** ALL TESTS PASSED SUCCESSFULLY ***");
        end else begin
            $error(" *** %0d VERIFICATION FAILURE(S) DETECTED ***", error_count);
        end
        $display("==========================================================\n");

        #(CLK_PERIOD * 50);
        $finish;
    end

endmodule
