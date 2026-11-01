# Merges both 12 Mbaud bitstreams into the open AES-GCM-Libero project and builds each one
# through Verify Timing. pf_ccc_120m.tcl must have run first.
#   set REPO C:/path/to/AES_Verilog; source $REPO/realtime_env/rtl/common/build_12m.tcl

set rtl $REPO/realtime_env/rtl
set common $rtl/common

source $common/link_core.tcl

foreach key_bits {256 128} {
    link_hdl $rtl/aes$key_bits/aes${key_bits}_uart_wrapper.sv
    link_hdl $rtl/aes$key_bits/aes${key_bits}_uart_12m_top.sv
}

foreach name {protocol_pkg uart_rx uart_tx uart_cdc_link packet_parser packet_builder byte_fifo aes_gcm_engine
              aes_uart_cdc_wrapper aes_uart_12m_top} {
    link_hdl $common/$name.sv
}
link_constraints $common/aes_uart_12m.sdc $common/aes_uart_12m.pdc
build_design_hierarchy

foreach key_bits {256 128} {
    build_root aes${key_bits}_uart_12m_top::work $common/aes_uart_12m.sdc $common/aes_uart_12m.pdc
}
