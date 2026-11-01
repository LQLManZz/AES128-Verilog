//=============================================================================
// Module: uart_cdc_link.sv
// Directory: realtime_env/rtl/common/
// Description: Runs uart_rx and uart_tx on their own clock and presents the
//              same byte interface as those modules in the clk domain.
//
// Bytes are far apart compared with both clocks (833 ns at 12 Mbaud), so one
// toggle crossing each way is enough: the data is stable long before the
// strobe arrives, and packet_builder waits for tx_busy to rise and fall.
//=============================================================================

`timescale 1ns / 1ps

module uart_cdc_link #(
    parameter int UART_CLK_HZ = 120_000_000,
    parameter int BAUD_RATE   = 12_000_000
)(
    input  logic       clk,
    input  logic       rst_n,
    input  logic       clk_uart,
    input  logic       rst_uart_n,

    // Serial physical pins
    input  logic       uart_rx,
    output logic       uart_tx,

    // Byte interface in the clk domain
    output logic [7:0] rx_data,
    output logic       rx_valid,
    input  logic [7:0] tx_data,
    input  logic       tx_start,
    output logic       tx_busy
);

    logic       rx_valid_uart;
    logic       rx_toggle;
    logic [2:0] rx_toggle_sync;

    logic       tx_toggle;
    logic [2:0] tx_toggle_sync;
    logic       tx_start_uart;
    logic       tx_busy_uart;
    logic       tx_busy_sync;

    uart_rx #(
        .CLK_FREQ_HZ(UART_CLK_HZ),
        .BAUD_RATE  (BAUD_RATE)
    ) u_rx (
        .clk     (clk_uart),
        .rst_n   (rst_uart_n),
        .rx      (uart_rx),
        .rx_data (rx_data),
        .rx_valid(rx_valid_uart)
    );

    uart_tx #(
        .CLK_FREQ_HZ(UART_CLK_HZ),
        .BAUD_RATE  (BAUD_RATE)
    ) u_tx (
        .clk     (clk_uart),
        .rst_n   (rst_uart_n),
        .tx_data (tx_data),
        .tx_start(tx_start_uart),
        .tx      (uart_tx),
        .tx_busy (tx_busy_uart)
    );

    // RX strobe: clk_uart to clk
    always_ff @(posedge clk_uart or negedge rst_uart_n) begin
        if (!rst_uart_n) rx_toggle <= 1'b0;
        else if (rx_valid_uart) rx_toggle <= ~rx_toggle;
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) rx_toggle_sync <= 3'b000;
        else        rx_toggle_sync <= {rx_toggle_sync[1:0], rx_toggle};
    end

    assign rx_valid = rx_toggle_sync[2] ^ rx_toggle_sync[1];

    // TX strobe: clk to clk_uart
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) tx_toggle <= 1'b0;
        else if (tx_start) tx_toggle <= ~tx_toggle;
    end

    always_ff @(posedge clk_uart or negedge rst_uart_n) begin
        if (!rst_uart_n) tx_toggle_sync <= 3'b000;
        else             tx_toggle_sync <= {tx_toggle_sync[1:0], tx_toggle};
    end

    assign tx_start_uart = tx_toggle_sync[2] ^ tx_toggle_sync[1];

    // TX busy: clk_uart to clk
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            tx_busy_sync <= 1'b0;
            tx_busy      <= 1'b0;
        end else begin
            tx_busy_sync <= tx_busy_uart;
            tx_busy      <= tx_busy_sync;
        end
    end

endmodule
