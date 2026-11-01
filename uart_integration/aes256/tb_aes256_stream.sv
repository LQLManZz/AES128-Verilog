//=============================================================================
// Testbench: tb_aes256_stream.sv
// Directory: uart_integration/aes256/
// Description: Plays a recorded host session against the SPI or UART wrapper
//              at bit level. image_process/imgapp/rtl_sim.py generates the
//              stimulus and checks the answers against the software model.
//
// +stim=<file>: one "frame" per line: <byte count> <expected reply bytes> <hex bytes>
//   USE_SPI=1: a frame is one spi_cs_n low period, the reply count is ignored.
//   USE_SPI=0: a frame is a burst of UART bytes, then waits for that many replies.
// +out=<file>: one line per frame: <byte count> <hex bytes received>
//=============================================================================

`timescale 1ns / 1ps

module tb_aes256_stream #(
    parameter bit USE_SPI   = 1'b1,
    parameter int KEY_BITS  = 256,
    parameter int SCLK_PS   = 33_333,   // Deliberately not a multiple of the 20 ns clock
    parameter int BAUD_RATE = 2_000_000,
    parameter int UART_CLK_HZ = 0       // Non-zero: UART on its own clock (aes_uart_cdc_wrapper)
);

    localparam int  CLK_FREQ_HZ = 50_000_000;
    localparam time CLK_PERIOD  = 20ns;
    localparam realtime SCLK_HALF  = SCLK_PS * 1ps / 2.0;  // A time would round to whole ns
    localparam realtime BIT_PERIOD = 1s / real'(BAUD_RATE);
    localparam time REPLY_LIMIT = 200ms;

    logic clk = 1'b0;
    logic clk_uart = 1'b0;
    logic rst_n = 1'b0;
    logic spi_sclk = 1'b0;
    logic spi_cs_n = 1'b1;
    logic spi_mosi = 1'b0;
    logic spi_miso;
    logic uart_rx = 1'b1;
    logic uart_tx;
    logic led_busy;
    logic led_done;
    logic [4:0] led_unused;

    always #(CLK_PERIOD / 2) clk = ~clk;

    generate
        if (USE_SPI && KEY_BITS == 256) begin : gen_dut
            aes256_spi_wrapper #(.CLK_FREQ_HZ(CLK_FREQ_HZ)) dut (.*);
        end else if (USE_SPI) begin : gen_dut
            aes128_spi_wrapper #(.CLK_FREQ_HZ(CLK_FREQ_HZ)) dut (.*);
        end else if (UART_CLK_HZ != 0) begin : gen_dut
            localparam realtime UART_CLK_HALF = 0.5s / real'(UART_CLK_HZ);
            always #(UART_CLK_HALF) clk_uart = ~clk_uart;
            aes_uart_cdc_wrapper #(
                .KEY_BITS(KEY_BITS), .CLK_FREQ_HZ(CLK_FREQ_HZ), .UART_CLK_HZ(UART_CLK_HZ), .BAUD_RATE(BAUD_RATE)
            ) dut (.*);
        end else if (KEY_BITS == 256) begin : gen_dut
            aes256_uart_wrapper #(.CLK_FREQ_HZ(CLK_FREQ_HZ), .BAUD_RATE(BAUD_RATE)) dut (.*);
        end else begin : gen_dut
            aes128_uart_wrapper #(.CLK_FREQ_HZ(CLK_FREQ_HZ), .BAUD_RATE(BAUD_RATE)) dut (.*);
        end
    endgenerate

    logic [7:0] received[$];   // UART replies not written out yet
    int         replies_seen = 0;

    // Mode 0: the master samples MISO and drives MOSI around the rising edge
    task automatic spi_byte(input logic [7:0] mosi, output logic [7:0] miso);
        for (int i = 7; i >= 0; i--) begin
            spi_mosi = mosi[i];
            #(SCLK_HALF);
            miso[i]  = spi_miso;
            spi_sclk = 1'b1;
            #(SCLK_HALF);
            spi_sclk = 1'b0;
        end
    endtask

    task automatic uart_send(input logic [7:0] data);
        uart_rx = 1'b0;
        #(BIT_PERIOD);
        for (int i = 0; i < 8; i++) begin
            uart_rx = data[i];
            #(BIT_PERIOD);
        end
        uart_rx = 1'b1;
        #(BIT_PERIOD);
    endtask

    if (!USE_SPI) begin : gen_uart_monitor
        initial forever begin
            logic [7:0] data;
            @(negedge uart_tx);
            #(BIT_PERIOD / 2);
            for (int i = 0; i < 8; i++) begin
                #(BIT_PERIOD);
                data[i] = uart_tx;
            end
            #(BIT_PERIOD);
            assert (uart_tx === 1'b1) else $fatal(1, "Framing error on uart_tx");
            received.push_back(data);
            replies_seen++;
        end
    end

    initial begin
        string stim_path, out_path;
        int    stim, out, count, expected, want_total, scanned;
        time   started;

        if (!$value$plusargs("stim=%s", stim_path) || !$value$plusargs("out=%s", out_path))
            $fatal(1, "+stim and +out are required");
        stim = $fopen(stim_path, "r");
        out  = $fopen(out_path, "w");
        if (stim == 0 || out == 0) $fatal(1, "Cannot open the stimulus or the output file");

        #(CLK_PERIOD * 10);
        @(posedge clk);
        rst_n <= 1'b1;
        #(CLK_PERIOD * 20);
        started = $time;
        want_total = 0;

        while ($fscanf(stim, "%d %d", count, expected) == 2) begin
            logic [7:0] sent[];
            logic [7:0] answer[];
            sent = new[count];
            for (int i = 0; i < count; i++) begin
                scanned = $fscanf(stim, "%x", sent[i]);
                if (scanned != 1) $fatal(1, "Stimulus ends inside a frame");
            end

            if (USE_SPI) begin
                answer = new[count];
                spi_cs_n = 1'b0;
                #(SCLK_HALF);
                for (int i = 0; i < count; i++) spi_byte(sent[i], answer[i]);
                #(SCLK_HALF);
                spi_cs_n = 1'b1;
                #(SCLK_HALF * 4);
                if ($isunknown(answer[0])) $fatal(1, "spi_miso is unknown");
            end else begin
                for (int i = 0; i < count; i++) uart_send(sent[i]);
                want_total += expected;
                begin
                    automatic time limit = $time + REPLY_LIMIT;
                    while (replies_seen < want_total && $time < limit) #1us;
                end
                if (replies_seen < want_total)
                    $fatal(1, "UART: %0d of %0d reply bytes arrived", replies_seen, want_total);
                answer = new[received.size()];
                foreach (answer[i]) answer[i] = received.pop_front();
            end

            $fwrite(out, "%0d", answer.size());
            foreach (answer[i]) $fwrite(out, " %02x", answer[i]);
            $fwrite(out, "\n");
        end

        $fclose(out);
        $fclose(stim);
        $display("STREAM_DONE elapsed_ns=%0d", $time - started);
        $finish;
    end

endmodule
