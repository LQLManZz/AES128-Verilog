`timescale 1ns / 1ps

module tb_KeyExpansion;

  //----------------------------------------------------------
  // DUT Signals
  //----------------------------------------------------------
  logic clk;
  logic rst_n;
  logic expansion_en;
  logic [127:0] cipher_key;

  logic [127:0] round_key[0:10];
  logic expansion_finish;

  //----------------------------------------------------------
  // DUT
  //----------------------------------------------------------
  KeyExpansion dut (
      .clk(clk),
      .rst_n(rst_n),
      .expansion_en(expansion_en),
      .cipher_key(cipher_key),
      .round_key(round_key),
      .expansion_finish(expansion_finish)
  );

  //----------------------------------------------------------
  // Golden AES-128 Keys (FIPS-197 Appendix A.1)
  //----------------------------------------------------------
  logic [127:0] golden[0:10];

  initial begin

    golden[0]  = 128'h2b7e151628aed2a6abf7158809cf4f3c;
    golden[1]  = 128'ha0fafe1788542cb123a339392a6c7605;
    golden[2]  = 128'hf2c295f27a96b9435935807a7359f67f;
    golden[3]  = 128'h3d80477d4716fe3e1e237e446d7a883b;
    golden[4]  = 128'hef44a541a8525b7fb671253bdb0bad00;
    golden[5]  = 128'hd4d1c6f87c839d87caf2b8bc11f915bc;
    golden[6]  = 128'h6d88a37a110b3efddbf98641ca0093fd;
    golden[7]  = 128'h4e54f70e5f5fc9f384a64fb24ea6dc4f;
    golden[8]  = 128'head27321b58dbad2312bf5607f8d292f;
    golden[9]  = 128'hac7766f319fadc2128d12941575c006e;
    golden[10] = 128'hd014f9a8c9ee2589e13f0cc8b6630ca6;

  end

  //----------------------------------------------------------
  // Clock
  //----------------------------------------------------------
  initial begin
    clk = 0;
    forever #5 clk = ~clk;
  end

  //----------------------------------------------------------
  // Waveform
  //----------------------------------------------------------
  initial begin
    $dumpfile("tb_KeyExpansion.vcd");
    $dumpvars(0, tb_KeyExpansion);

    // Dump toàn bộ DUT
    $dumpvars(1, dut);
  end

  //----------------------------------------------------------
  // Debug Monitor
  //----------------------------------------------------------
  always @(posedge clk) begin

    $display("[%0t] idx=%0d first=%0b finish=%0b", $time, dut.round_index, dut.first_rkey,
             expansion_finish);

    $display("    current_key = %032h", dut.current_key);
    $display("    after_GFunc = %08h", dut.after_GFunction);
    $display("    next_key    = %032h", dut.next_key);

    if (dut.round_index < 10)
      $display("    RK[%0d]      = %032h", dut.round_index + 1, round_key[dut.round_index+1]);

    $display("");

  end

  //----------------------------------------------------------
  // Compare Function
  //----------------------------------------------------------
  task automatic compare_round_keys;

    int errors;

    begin

      errors = 0;

      $display("");
      $display("==============================================");
      $display("CHECKING GENERATED ROUND KEYS");
      $display("==============================================");

      for (int i = 0; i <= 10; i++) begin

        if (round_key[i] !== golden[i]) begin

          $display("[FAIL] RK[%0d]", i);
          $display("Expected : %032h", golden[i]);
          $display("Actual   : %032h", round_key[i]);
          $display("");

          errors++;

        end else begin

          $display("[PASS] RK[%0d] = %032h", i, round_key[i]);

        end

      end

      $display("");
      $display("==============================================");

      if (errors == 0) $display("AES KEY EXPANSION PASSED");
      else $display("AES KEY EXPANSION FAILED (%0d ERRORS)", errors);

      $display("==============================================");
      $display("");

    end

  endtask

  //----------------------------------------------------------
  // Main Test
  //----------------------------------------------------------
  initial begin

    rst_n        = 0;
    expansion_en = 0;

    cipher_key   = 128'h2b7e151628aed2a6abf7158809cf4f3c;

    //------------------------------------------------------
    // Reset
    //------------------------------------------------------
    repeat (4) @(posedge clk);

    rst_n = 1;

    $display("");
    $display("==============================================");
    $display("RESET RELEASED");
    $display("==============================================");

    //------------------------------------------------------
    // Start Expansion
    //------------------------------------------------------
    @(posedge clk);

    expansion_en = 1;

    $display("[%0t] EXPANSION START", $time);

    //------------------------------------------------------
    // Timeout Protection
    //------------------------------------------------------
    fork

      begin : WAIT_FINISH

        wait (expansion_finish);

        @(posedge clk);

        expansion_en = 0;

        $display("[%0t] EXPANSION FINISHED", $time);

        compare_round_keys();

      end

      begin : TIMEOUT

        repeat (50) @(posedge clk);

        $display("");
        $display("==============================================");
        $display("TIMEOUT: expansion_finish NEVER ASSERTED");
        $display("==============================================");

        $fatal;

      end

    join_any

    disable fork;

    //------------------------------------------------------
    // Extra cycles for GTKWave
    //------------------------------------------------------
    repeat (5) @(posedge clk);

    $finish;

  end

endmodule
