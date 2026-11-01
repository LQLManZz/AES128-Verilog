//=============================================================================
// Module: aes128_spi_wrapper.sv
// Directory: realtime_env/rtl/aes128/
// Description: SPI bitstream top: connects the physical SPI pins to the
//              AES-128-GCM engine (common/aes_gcm_engine.sv).
//
// Target: Microchip PolarFire SoC Discovery Kit (MPFS095T-1FCSG325E)
//=============================================================================

`timescale 1ns / 1ps

module aes128_spi_wrapper #(
    parameter int CLK_FREQ_HZ = 50_000_000
)(
    input  logic clk,
    input  logic rst_n,

    // SPI physical pins (mode 0, MSB first)
    input  logic spi_sclk,
    input  logic spi_cs_n,
    input  logic spi_mosi,
    output logic spi_miso,

    // Status diagnostics
    output logic       led_busy,
    output logic       led_done,
    output logic [4:0] led_unused
);

    logic [7:0] rx_byte;
    logic       rx_byte_valid;
    logic       rx_overflow;

    logic [7:0] tx_byte;
    logic       tx_byte_start;
    logic       tx_byte_busy;

    logic       engine_rst_n;

    spi_link u_link (
        .clk         (clk),
        .rst_n       (rst_n),
        .spi_sclk    (spi_sclk),
        .spi_cs_n    (spi_cs_n),
        .spi_mosi    (spi_mosi),
        .spi_miso    (spi_miso),
        .rx_data     (rx_byte),
        .rx_valid    (rx_byte_valid),
        .rx_overflow (rx_overflow),
        .tx_data     (tx_byte),
        .tx_start    (tx_byte_start),
        .tx_busy     (tx_byte_busy),
        .engine_rst_n(engine_rst_n)
    );

    aes_gcm_engine #(
        .KEY_BITS   (128),
        .CLK_FREQ_HZ(CLK_FREQ_HZ)
    ) u_engine (
        .clk        (clk),
        .rst_n      (engine_rst_n),
        .rx_data    (rx_byte),
        .rx_valid   (rx_byte_valid),
        .rx_overflow(rx_overflow),
        .tx_data    (tx_byte),
        .tx_start   (tx_byte_start),
        .tx_busy    (tx_byte_busy),
        .led_busy   (led_busy),
        .led_done   (led_done),
        .led_unused (led_unused)
    );

endmodule
