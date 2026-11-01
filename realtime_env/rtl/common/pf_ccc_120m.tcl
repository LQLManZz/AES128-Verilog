# Generates PF_CCC_120M, the PLL of aes_uart_12m_top: 50 MHz from R18 to 120 MHz for the UART.
# Run inside the Libero project: source realtime_env/rtl/common/pf_ccc_120m.tcl

create_and_configure_core -core_vlnv {Actel:SgCore:PF_CCC:*} -component_name {PF_CCC_120M} -params {\
"PLL_IN_FREQ_0:50" \
"GL0_0_IS_USED:true" \
"GL0_0_OUT_FREQ:120" \
"GL0_0_FABCLK_USED:true"}
