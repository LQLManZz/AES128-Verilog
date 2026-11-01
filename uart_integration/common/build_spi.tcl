# Merges both SPI bitstreams into the open AES-GCM-Libero project and builds each one
# through Verify Timing. Libero keeps results per Design Root, so the UART roots stay intact.
#   set REPO C:/path/to/AES_Verilog; source $REPO/uart_integration/common/build_spi.tcl

set common $REPO/uart_integration/common

source $common/link_core.tcl

foreach key_bits {256 128} {
    link_hdl $REPO/uart_integration/aes$key_bits/aes${key_bits}_spi_wrapper.sv
}

foreach name {protocol_pkg packet_parser packet_builder byte_fifo spi_link aes_gcm_engine} {
    link_hdl $common/$name.sv
}
catch {create_links -sdc $common/aes_spi.sdc}
catch {create_links -io_pdc $common/aes_spi.pdc}
build_design_hierarchy

foreach key_bits {256 128} {
    set top aes${key_bits}_spi_wrapper::work
    set_root -module $top
    foreach tool {SYNTHESIZE VERIFYTIMING} {
        organize_tool_files -tool $tool -file $common/aes_spi.sdc -module $top -input_type {constraint}
    }
    organize_tool_files -tool {PLACEROUTE} -file $common/aes_spi.sdc -file $common/aes_spi.pdc \
        -module $top -input_type {constraint}

    run_tool -name {SYNTHESIZE}
    run_tool -name {PLACEROUTE}
    run_tool -name {VERIFYTIMING}
    save_project
}
