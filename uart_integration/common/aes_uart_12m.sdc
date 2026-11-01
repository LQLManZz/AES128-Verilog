# Timing constraints for aes256_uart_12m_top / aes128_uart_12m_top.
# clk: 50 MHz oscillator on R18, the same as the other bitstreams.
# clk_uart: 120 MHz from PF_CCC_120M. The two only meet in the synchronizers of uart_cdc_link.

create_clock -name {clk} -period 20.000 [get_ports {clk}]
create_generated_clock -name {clk_uart} -multiply_by 12 -divide_by 5 \
    -source [get_pins {u_top/u_ccc/PF_CCC_120M_0/pll_inst_0/REF_CLK_0}] \
    [get_pins {u_top/u_ccc/PF_CCC_120M_0/pll_inst_0/OUT0}]

set_clock_groups -name {uart_domains} -asynchronous -group [get_clocks {clk}] -group [get_clocks {clk_uart}]

set_false_path -from [get_ports {rst_n uart_rx}]
set_false_path -to   [get_ports {uart_tx}]
