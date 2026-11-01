//=============================================================================
// Module: aes256_uart_12m_top.sv
// Directory: realtime_env/rtl/aes256/
// Description: AES-256 Design Root of the 12 Mbaud bitstream. Libero keeps its
//              results per root, so the two key sizes can share a project.
//
// Target: Microchip PolarFire SoC Discovery Kit (MPFS095T-1FCSG325E)
//=============================================================================

`timescale 1ns / 1ps

module aes256_uart_12m_top #(
    parameter int BAUD_RATE = 12_000_000
)(
    input  logic clk,
    input  logic rst_n,

    // FT4232HL channel D
    input  logic uart_rx,
    output logic uart_tx,

    // Status diagnostics
    output logic       led_busy,
    output logic       led_done,
    output logic [4:0] led_unused
);

    aes_uart_12m_top #(
        .KEY_BITS (256),
        .BAUD_RATE(BAUD_RATE)
    ) u_top (
        .clk       (clk),
        .rst_n     (rst_n),
        .uart_rx   (uart_rx),
        .uart_tx   (uart_tx),
        .led_busy  (led_busy),
        .led_done  (led_done),
        .led_unused(led_unused)
    );

endmodule
