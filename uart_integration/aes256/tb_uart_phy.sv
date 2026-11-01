//=============================================================================
// Testbench: tb_uart_phy.sv
// Directory: uart_integration/aes256/
// Description: Checks uart_cdc_link at 12 Mbaud on a 120 MHz UART clock with a
//              50 MHz system clock: exact TX bit lengths, then every byte value
//              looped through both clock crossings, back to back, with the
//              host baud rate exact and 2% off.
//=============================================================================

`timescale 1ns / 1ps

module tb_uart_phy #(
    parameter int UART_CLK_HZ = 120_000_000,
    parameter int BAUD_RATE   = 12_000_000
);

    localparam time     CLK_PERIOD      = 20ns;
    localparam realtime UART_CLK_PERIOD = 1s / real'(UART_CLK_HZ);  // A time would round to whole ns
    localparam int      CLKS_PER_BIT    = UART_CLK_HZ / BAUD_RATE;
    localparam realtime BIT_PERIOD      = 1s / real'(BAUD_RATE);
    localparam time     REPLY_LIMIT     = 1ms;

    logic clk = 1'b0;
    logic clk_uart = 1'b0;
    logic rst_n = 1'b0;
    logic uart_rx = 1'b1;
    logic uart_tx;

    logic [7:0] rx_data;
    logic       rx_valid;
    logic [7:0] tx_data = 8'h00;
    logic       tx_start = 1'b0;
    logic       tx_busy;

    logic [7:0] loop_queue[$];  // Bytes waiting to go back out
    logic [7:0] received[$];    // Bytes seen on uart_tx
    int         rx_count = 0;
    int         uart_clocks = 0;
    int         errors = 0;

    always #(CLK_PERIOD / 2) clk = ~clk;
    always #(UART_CLK_PERIOD / 2) clk_uart = ~clk_uart;
    always @(posedge clk_uart) uart_clocks++;

    uart_cdc_link #(
        .UART_CLK_HZ(UART_CLK_HZ),
        .BAUD_RATE  (BAUD_RATE)
    ) dut (
        .clk       (clk),
        .rst_n     (rst_n),
        .clk_uart  (clk_uart),
        .rst_uart_n(rst_n),
        .uart_rx   (uart_rx),
        .uart_tx   (uart_tx),
        .rx_data   (rx_data),
        .rx_valid  (rx_valid),
        .tx_data   (tx_data),
        .tx_start  (tx_start),
        .tx_busy   (tx_busy)
    );

    // Same handshake as packet_builder: start, wait for busy, wait for free
    always @(posedge clk) begin
        if (rx_valid) begin
            loop_queue.push_back(rx_data);
            rx_count++;
        end
    end

    initial forever begin
        @(posedge clk);
        if (loop_queue.size() != 0 && !tx_busy) begin
            tx_data  <= loop_queue.pop_front();
            tx_start <= 1'b1;
            @(posedge clk);
            tx_start <= 1'b0;
            do @(posedge clk); while (!tx_busy);
            do @(posedge clk); while (tx_busy);
        end
    end

    initial forever begin
        logic [7:0] data;
        @(negedge uart_tx);
        #(BIT_PERIOD / 2);
        for (int i = 0; i < 8; i++) begin
            #(BIT_PERIOD);
            data[i] = uart_tx;
        end
        #(BIT_PERIOD);
        if (uart_tx !== 1'b1) begin
            $display("  [ERROR] Framing error on uart_tx");
            errors++;
        end
        received.push_back(data);
    end

    task automatic uart_send(input logic [7:0] data, input realtime bit_period);
        uart_rx = 1'b0;
        #(bit_period);
        for (int i = 0; i < 8; i++) begin
            uart_rx = data[i];
            #(bit_period);
        end
        uart_rx = 1'b1;
        #(bit_period);
    endtask

    // 8'h55 has an edge on every bit boundary from the start bit to the stop bit
    task automatic check_bit_lengths();
        int last;
        fork
            uart_send(8'h55, BIT_PERIOD);
            begin
                @(negedge uart_tx);
                last = uart_clocks;
                for (int i = 0; i < 9; i++) begin
                    @(uart_tx);
                    if (uart_clocks - last != CLKS_PER_BIT) begin
                        $display("  [ERROR] Bit %0d of the frame lasted %0d clocks, expected %0d",
                                 i, uart_clocks - last, CLKS_PER_BIT);
                        errors++;
                    end
                    last = uart_clocks;
                end
            end
        join
        wait_for_replies(1);
        received.delete();
    endtask

    task automatic wait_for_replies(input int count);
        time limit = $time + REPLY_LIMIT;
        while (received.size() < count && $time < limit) #100ns;
    endtask

    task automatic loop_all_bytes(input string name, input real speed);
        int mismatches = 0;
        int start_count = rx_count;
        for (int i = 0; i < 256; i++) uart_send(8'(i), BIT_PERIOD / speed);
        wait_for_replies(256);
        if (rx_count - start_count != 256 || received.size() != 256) begin
            $display("  [ERROR] %s: sent 256, crossed %0d, returned %0d",
                     name, rx_count - start_count, received.size());
            errors++;
        end
        foreach (received[i]) if (received[i] !== 8'(i)) mismatches++;
        if (mismatches != 0) begin
            $display("  [ERROR] %s: %0d bytes differ", name, mismatches);
            errors++;
        end
        $display("  %s: %0d bytes crossed, %0d returned, %0d differ",
                 name, rx_count - start_count, received.size(), mismatches);
        received.delete();
    endtask

    initial begin
        #(CLK_PERIOD * 10);
        rst_n = 1'b1;
        #(CLK_PERIOD * 20);

        check_bit_lengths();
        loop_all_bytes("exact baud", 1.0);
        loop_all_bytes("host +2%", 1.02);
        loop_all_bytes("host -2%", 0.98);

        if (errors != 0) $fatal(1, "tb_uart_phy: %0d errors", errors);
        $display("tb_uart_phy: all checks passed");
        $finish;
    end

endmodule
