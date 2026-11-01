# Timing constraints for aes256_uart_wrapper / aes128_uart_wrapper.
# clk: 50 MHz oscillator on R18, used directly with no PLL.

create_clock -name {clk} -period 20.000 [get_ports {clk}]

set_false_path -from [get_ports {rst_n uart_rx}]
set_false_path -to   [get_ports {uart_tx}]
