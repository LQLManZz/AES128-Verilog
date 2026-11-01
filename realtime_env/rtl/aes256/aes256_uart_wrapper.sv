//=============================================================================
// Module: aes256_uart_wrapper.sv
// Directory: realtime_env/rtl/aes256/
// Description: UART bitstream top: connects the physical UART pins to the
//              AES-256-GCM engine (common/aes_gcm_engine.sv).
//
// Target: Microchip PolarFire SoC Discovery Kit (MPFS095T-1FCSG325E)
//
// BAUD_RATE should divide CLK_FREQ_HZ exactly: 1, 2 or 5 Mbaud at 50 MHz.
//=============================================================================

`timescale 1ns / 1ps

module aes256_uart_wrapper #(
    parameter int CLK_FREQ_HZ = 50_000_000,
    parameter int BAUD_RATE   = 2_000_000
)(
    input  logic clk,
    input  logic rst_n,

    // Serial physical pins
    input  logic uart_rx,
    output logic uart_tx,

    // Status diagnostics
    output logic       led_busy,
    output logic       led_done,
    output logic [4:0] led_unused
);

    logic [7:0] rx_byte;
    logic       rx_byte_valid;

    logic [7:0] tx_byte;
    logic       tx_byte_start;
    logic       tx_byte_busy;

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

    aes_gcm_engine #(
        .KEY_BITS   (256),
        .CLK_FREQ_HZ(CLK_FREQ_HZ)
    ) u_engine (
        .clk        (clk),
        .rst_n      (rst_n),
        .rx_data    (rx_byte),
        .rx_valid   (rx_byte_valid),
        .rx_overflow(),
        .tx_data    (tx_byte),
        .tx_start   (tx_byte_start),
        .tx_busy    (tx_byte_busy),
        .led_busy   (led_busy),
        .led_done   (led_done),
        .led_unused (led_unused)
    );

endmodule
