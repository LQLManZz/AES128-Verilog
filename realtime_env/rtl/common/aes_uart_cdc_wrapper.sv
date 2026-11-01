//=============================================================================
// Module: aes_uart_cdc_wrapper.sv
// Directory: realtime_env/rtl/common/
// Description: UART top with two clocks: the AES-GCM engine stays on clk and
//              the UART runs on clk_uart, which must divide BAUD_RATE exactly.
//              Bare of any PLL so it simulates without vendor primitives:
//              aes_uart_12m_top.sv adds the clock for the board.
//
// Target: Microchip PolarFire SoC Discovery Kit (MPFS095T-1FCSG325E)
//=============================================================================

`timescale 1ns / 1ps

module aes_uart_cdc_wrapper #(
    parameter int KEY_BITS    = 256,
    parameter int CLK_FREQ_HZ = 50_000_000,
    parameter int UART_CLK_HZ = 120_000_000,
    parameter int BAUD_RATE   = 12_000_000
)(
    input  logic clk,
    input  logic clk_uart,
    input  logic rst_n,

    // Serial physical pins
    input  logic uart_rx,
    output logic uart_tx,

    // Status diagnostics
    output logic       led_busy,
    output logic       led_done,
    output logic [4:0] led_unused
);

    logic [1:0] rst_sync;
    logic [1:0] rst_uart_sync;

    logic [7:0] rx_byte;
    logic       rx_byte_valid;

    logic [7:0] tx_byte;
    logic       tx_byte_start;
    logic       tx_byte_busy;

    // Each domain leaves reset on its own clock
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) rst_sync <= 2'b00;
        else        rst_sync <= {rst_sync[0], 1'b1};
    end

    always_ff @(posedge clk_uart or negedge rst_n) begin
        if (!rst_n) rst_uart_sync <= 2'b00;
        else        rst_uart_sync <= {rst_uart_sync[0], 1'b1};
    end

    uart_cdc_link #(
        .UART_CLK_HZ(UART_CLK_HZ),
        .BAUD_RATE  (BAUD_RATE)
    ) u_link (
        .clk       (clk),
        .rst_n     (rst_sync[1]),
        .clk_uart  (clk_uart),
        .rst_uart_n(rst_uart_sync[1]),
        .uart_rx   (uart_rx),
        .uart_tx   (uart_tx),
        .rx_data   (rx_byte),
        .rx_valid  (rx_byte_valid),
        .tx_data   (tx_byte),
        .tx_start  (tx_byte_start),
        .tx_busy   (tx_byte_busy)
    );

    aes_gcm_engine #(
        .KEY_BITS   (KEY_BITS),
        .CLK_FREQ_HZ(CLK_FREQ_HZ)
    ) u_engine (
        .clk        (clk),
        .rst_n      (rst_sync[1]),
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
