# Merges both 2 Mbaud UART bitstreams into the open AES-GCM-Libero project and builds each
# one through Verify Timing. These roots use the mikroBUS UART on J6 and need an external adapter.
#   set REPO C:/path/to/AES_Verilog; source $REPO/realtime_env/rtl/common/build_2m.tcl

set rtl $REPO/realtime_env/rtl
set common $rtl/common

source $common/link_core.tcl

foreach key_bits {256 128} {
    link_hdl $rtl/aes$key_bits/aes${key_bits}_uart_wrapper.sv
}

foreach name {protocol_pkg uart_rx uart_tx packet_parser packet_builder byte_fifo aes_gcm_engine} {
    link_hdl $common/$name.sv
}
link_constraints $common/aes_uart.sdc $common/aes_uart.pdc
build_design_hierarchy

foreach key_bits {256 128} {
    build_root aes${key_bits}_uart_wrapper::work $common/aes_uart.sdc $common/aes_uart.pdc
}
