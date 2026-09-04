`timescale 1ns / 1ps

module Counter_tb;
  // ─── DUT signals ───────────────────────────────────────────
  logic       clk;
  logic       rst_n;
  logic       expansion_en;
  logic       first_rkey;
  logic       expansion_finish;
  logic [3:0] round_index;

  // ─── DUT instantiation ─────────────────────────────────────
  Counter dut (
      .clk             (clk),
      .rst_n           (rst_n),
      .expansion_en    (expansion_en),
      .first_rkey      (first_rkey),
      .expansion_finish(expansion_finish),
      .round_index     (round_index)
  );

  // ─── Clock: 10 ns period (100 MHz) ─────────────────────────
  initial clk = 0;
  always #5 clk = ~clk;

  // ─── Waveform dump ─────────────────────────────────────────
  initial begin
    $dumpfile("counter_wave.vcd");
    $dumpvars(0, Counter_tb);
  end

  // ─── Task: chờ N chu kỳ clock ──────────────────────────────
  task automatic wait_cycles(input int n);
    repeat (n) @(posedge clk);
    #1;  // setup time offset để đọc giá trị sau clk edge
  endtask

  // ─── Task: kiểm tra giá trị và in kết quả ──────────────────
  task automatic check(input string test_name, input logic [3:0] exp_idx, input logic exp_first,
                       input logic exp_finish);
    if (round_index !== exp_idx || first_rkey !== exp_first || expansion_finish !== exp_finish) begin
      $display(
          "FAIL [%0t] %s | round_index=%0d(exp %0d) first_rkey=%b(exp %b) expansion_finish=%b(exp %b)",
          $time, test_name, round_index, exp_idx, first_rkey, exp_first, expansion_finish,
          exp_finish);
    end else begin
      $display("PASS [%0t] %s | round_index=%0d first_rkey=%b expansion_finish=%b", $time,
               test_name, round_index, first_rkey, expansion_finish);
    end
  endtask

  // ─── Stimulus ──────────────────────────────────────────────
  initial begin
    // ── 1. Khởi tạo ──────────────────────────────────────────
    rst_n        = 1;
    expansion_en = 0;

    // ── 2. Assert reset ──────────────────────────────────────
    @(negedge clk);
    rst_n = 0;
    wait_cycles(3);
    check("After reset", 4'd0, 1'b1, 1'b0);

    // ── 3. Deassert reset, en vẫn = 0 ────────────────────────
    @(negedge clk);
    rst_n = 1;
    wait_cycles(2);
    check("RST released, en=0", 4'd0, 1'b1, 1'b0);

    // ── 4. Enable expansion, chạy đủ 10 round (0→9) ─────────
    $display("\n--- Running full expansion (10 rounds) ---");
    @(negedge clk);
    expansion_en = 1;

    // Round 0: first_rkey phải = 1
    wait_cycles(1);
    check("Round 0 (first_rkey=1)", 4'd1, 1'b1, 1'b0);

    // Round 1→8
    repeat (8) begin
      @(posedge clk);
      #1;
      $display("  round_index=%0d first_rkey=%b expansion_finish=%b", round_index, first_rkey,
               expansion_finish);
    end

    // Round 9: sau edge này → index reset về 0, finish = 1
    wait_cycles(1);
    check("After round 9 (finish)", 4'd0, 1'b1, 1'b1);

    // ── 5. Giữ en=1: vòng thứ 2 bắt đầu, finish phải clear ──
    $display("\n--- Cycle 2 starting ---");
    wait_cycles(1);
    check("Round 0 v2 (finish cleared)", 4'd1, 1'b1, 1'b0);

    // ── 6. Pause giữa chừng: deassert en ─────────────────────
    $display("\n--- Pausing expansion_en mid-run ---");
    wait_cycles(2);
    @(negedge clk);
    expansion_en = 0;
    wait_cycles(3);
    $display("  [Paused] round_index=%0d (must remain unchanged)", round_index);

    // Resume
    @(negedge clk);
    expansion_en = 1;
    wait_cycles(1);
    $display("  [Resumed] round_index=%0d", round_index);

    // ── 7. Reset giữa chừng ───────────────────────────────────
    $display("\n--- Resetting mid-run ---");
    wait_cycles(3);
    @(negedge clk);
    rst_n = 0;
    wait_cycles(2);
    check("Mid-run reset", 4'd0, 1'b1, 1'b0);
    @(negedge clk);
    rst_n = 1;

    // ── 8. Kết thúc ──────────────────────────────────────────
    wait_cycles(5);
    $display("\n=== Simulation done ===");
    $finish;
  end

  // ─── Timeout watchdog ──────────────────────────────────────
  initial begin
    #10000;
    $display("TIMEOUT - simulation hung");
    $finish;
  end

endmodule
