`timescale 1ns / 1ps

module SBox_tb;

  // ─── DUT signals ─────────────────────────────────────────────
  logic [7:0] byte_in;
  logic [7:0] byte_out;

  // ─── DUT instantiation ───────────────────────────────────────
  SBox dut (
      .byte_in (byte_in),
      .byte_out(byte_out)
  );

  // ─── Waveform dump ───────────────────────────────────────────
  initial begin
    $dumpfile("sbox_wave.vcd");
    $dumpvars(0, SBox_tb);
  end

  // ─── AES S-Box golden reference (FIPS 197) ───────────────────
  logic [7:0] sbox_ref[0:255] = '{
      // 0x00 - 0x0F
      8'h63,
      8'h7c,
      8'h77,
      8'h7b,
      8'hf2,
      8'h6b,
      8'h6f,
      8'hc5,
      8'h30,
      8'h01,
      8'h67,
      8'h2b,
      8'hfe,
      8'hd7,
      8'hab,
      8'h76,
      // 0x10 - 0x1F
      8'hca,
      8'h82,
      8'hc9,
      8'h7d,
      8'hfa,
      8'h59,
      8'h47,
      8'hf0,
      8'had,
      8'hd4,
      8'ha2,
      8'haf,
      8'h9c,
      8'ha4,
      8'h72,
      8'hc0,
      // 0x20 - 0x2F
      8'hb7,
      8'hfd,
      8'h93,
      8'h26,
      8'h36,
      8'h3f,
      8'hf7,
      8'hcc,
      8'h34,
      8'ha5,
      8'he5,
      8'hf1,
      8'h71,
      8'hd8,
      8'h31,
      8'h15,
      // 0x30 - 0x3F
      8'h04,
      8'hc7,
      8'h23,
      8'hc3,
      8'h18,
      8'h96,
      8'h05,
      8'h9a,
      8'h07,
      8'h12,
      8'h80,
      8'he2,
      8'heb,
      8'h27,
      8'hb2,
      8'h75,
      // 0x40 - 0x4F
      8'h09,
      8'h83,
      8'h2c,
      8'h1a,
      8'h1b,
      8'h6e,
      8'h5a,
      8'ha0,
      8'h52,
      8'h3b,
      8'hd6,
      8'hb3,
      8'h29,
      8'he3,
      8'h2f,
      8'h84,
      // 0x50 - 0x5F
      8'h53,
      8'hd1,
      8'h00,
      8'hed,
      8'h20,
      8'hfc,
      8'hb1,
      8'h5b,
      8'h6a,
      8'hcb,
      8'hbe,
      8'h39,
      8'h4a,
      8'h4c,
      8'h58,
      8'hcf,
      // 0x60 - 0x6F
      8'hd0,
      8'hef,
      8'haa,
      8'hfb,
      8'h43,
      8'h4d,
      8'h33,
      8'h85,
      8'h45,
      8'hf9,
      8'h02,
      8'h7f,
      8'h50,
      8'h3c,
      8'h9f,
      8'ha8,
      // 0x70 - 0x7F
      8'h51,
      8'ha3,
      8'h40,
      8'h8f,
      8'h92,
      8'h9d,
      8'h38,
      8'hf5,
      8'hbc,
      8'hb6,
      8'hda,
      8'h21,
      8'h10,
      8'hff,
      8'hf3,
      8'hd2,
      // 0x80 - 0x8F
      8'hcd,
      8'h0c,
      8'h13,
      8'hec,
      8'h5f,
      8'h97,
      8'h44,
      8'h17,
      8'hc4,
      8'ha7,
      8'h7e,
      8'h3d,
      8'h64,
      8'h5d,
      8'h19,
      8'h73,
      // 0x90 - 0x9F
      8'h60,
      8'h81,
      8'h4f,
      8'hdc,
      8'h22,
      8'h2a,
      8'h90,
      8'h88,
      8'h46,
      8'hee,
      8'hb8,
      8'h14,
      8'hde,
      8'h5e,
      8'h0b,
      8'hdb,
      // 0xA0 - 0xAF
      8'he0,
      8'h32,
      8'h3a,
      8'h0a,
      8'h49,
      8'h06,
      8'h24,
      8'h5c,
      8'hc2,
      8'hd3,
      8'hac,
      8'h62,
      8'h91,
      8'h95,
      8'he4,
      8'h79,
      // 0xB0 - 0xBF
      8'he7,
      8'hc8,
      8'h37,
      8'h6d,
      8'h8d,
      8'hd5,
      8'h4e,
      8'ha9,
      8'h6c,
      8'h56,
      8'hf4,
      8'hea,
      8'h65,
      8'h7a,
      8'hae,
      8'h08,
      // 0xC0 - 0xCF
      8'hba,
      8'h78,
      8'h25,
      8'h2e,
      8'h1c,
      8'ha6,
      8'hb4,
      8'hc6,
      8'he8,
      8'hdd,
      8'h74,
      8'h1f,
      8'h4b,
      8'hbd,
      8'h8b,
      8'h8a,
      // 0xD0 - 0xDF
      8'h70,
      8'h3e,
      8'hb5,
      8'h66,
      8'h48,
      8'h03,
      8'hf6,
      8'h0e,
      8'h61,
      8'h35,
      8'h57,
      8'hb9,
      8'h86,
      8'hc1,
      8'h1d,
      8'h9e,
      // 0xE0 - 0xEF
      8'he1,
      8'hf8,
      8'h98,
      8'h11,
      8'h69,
      8'hd9,
      8'h8e,
      8'h94,
      8'h9b,
      8'h1e,
      8'h87,
      8'he9,
      8'hce,
      8'h55,
      8'h28,
      8'hdf,
      // 0xF0 - 0xFF
      8'h8c,
      8'ha1,
      8'h89,
      8'h0d,
      8'hbf,
      8'he6,
      8'h42,
      8'h68,
      8'h41,
      8'h99,
      8'h2d,
      8'h0f,
      8'hb0,
      8'h54,
      8'hbb,
      8'h16
  };

  // ─── Counters ─────────────────────────────────────────────────
  int pass_count = 0;
  int fail_count = 0;

  // ─── Task: kiểm tra 1 giá trị ─────────────────────────────────
  task automatic check(input logic [7:0] in, input logic [7:0] exp);
    byte_in = in;
    #10;
    if (byte_out === exp) begin
      pass_count++;
      // Bỏ comment dòng dưới nếu muốn log từng case
      // $display("PASS | in=0x%02X | out=0x%02X", in, byte_out);
    end else begin
      fail_count++;
      $display("FAIL | in=0x%02X | got=0x%02X | exp=0x%02X", in, byte_out, exp);
    end
  endtask

  // ─── Stimulus ─────────────────────────────────────────────────
  initial begin
    byte_in = 8'h00;
    #5;

    // ── Test 1: Edge cases nổi bật ──────────────────────────────
    $display("=== Edge Case Tests ===");

    // 0x00 → 0x63 (giá trị đặc biệt: mInv(0)=0, affine ra 0x63)
    byte_in = 8'h00;
    #10;
    $display("in=0x00 | out=0x%02X | exp=0x63 | %s", byte_out,
             (byte_out === 8'h63) ? "PASS" : "FAIL");

    // 0x01 → 0x7C (mInv(1)=1)
    byte_in = 8'h01;
    #10;
    $display("in=0x01 | out=0x%02X | exp=0x7C | %s", byte_out,
             (byte_out === 8'h7c) ? "PASS" : "FAIL");

    // 0xFF → 0x16
    byte_in = 8'hff;
    #10;
    $display("in=0xFF | out=0x%02X | exp=0x16 | %s", byte_out,
             (byte_out === 8'h16) ? "PASS" : "FAIL");

    // 0x53 → 0xED (ví dụ trong FIPS 197)
    byte_in = 8'h53;
    #10;
    $display("in=0x53 | out=0x%02X | exp=0xED | %s", byte_out,
             (byte_out === 8'hed) ? "PASS" : "FAIL");

    // ── Test 2: Exhaustive — tất cả 256 giá trị ─────────────────
    $display("\n=== Exhaustive Test (256 values) ===");
    for (int i = 0; i < 256; i++) begin
      check(8'(i), sbox_ref[i]);
    end

    // ── Tóm tắt ─────────────────────────────────────────────────
    $display("\n=== RESULT: %0d / 256 PASS | %0d FAIL ===", pass_count, fail_count);

    if (fail_count == 0) $display(">>> SBox implementation CORRECT <<<");
    else $display(">>> SBox implementation has ERRORS <<<");

    #20;
    $finish;
  end

  // ─── Timeout watchdog ─────────────────────────────────────────
  initial begin
    #100000;
    $display("TIMEOUT");
    $finish;
  end

endmodule
