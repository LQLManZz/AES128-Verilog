# Merges both 12 Mbaud bitstreams into the open AES-GCM-Libero project and builds each one
# through Verify Timing. Libero keeps results per Design Root, so neither overwrites the other,
# and aes256_uart_wrapper stays available. pf_ccc_120m.tcl must have run first.
#   set REPO C:/path/to/AES_Verilog; source $REPO/uart_integration/common/build_12m.tcl

set common $REPO/uart_integration/common

source $common/link_core.tcl

foreach key_bits {256 128} {
    link_hdl $REPO/uart_integration/aes$key_bits/aes${key_bits}_uart_wrapper.sv
    link_hdl $REPO/uart_integration/aes$key_bits/aes${key_bits}_uart_12m_top.sv
}

foreach name {protocol_pkg uart_rx uart_tx uart_cdc_link packet_parser packet_builder byte_fifo aes_gcm_engine
              aes_uart_cdc_wrapper aes_uart_12m_top} {
    link_hdl $common/$name.sv
}
create_links -sdc $common/aes_uart_12m.sdc
create_links -io_pdc $common/aes_uart_12m.pdc
build_design_hierarchy

foreach key_bits {256 128} {
    set top aes${key_bits}_uart_12m_top::work
    set_root -module $top
    foreach tool {SYNTHESIZE VERIFYTIMING} {
        organize_tool_files -tool $tool -file $common/aes_uart_12m.sdc -module $top -input_type {constraint}
    }
    organize_tool_files -tool {PLACEROUTE} -file $common/aes_uart_12m.sdc -file $common/aes_uart_12m.pdc \
        -module $top -input_type {constraint}

    run_tool -name {SYNTHESIZE}
    run_tool -name {PLACEROUTE}
    run_tool -name {VERIFYTIMING}
    save_project
}
