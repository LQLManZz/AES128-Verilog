# Merges both SPI bitstreams into the open AES-GCM-Libero project and builds each one
# through Verify Timing. The same bitstream serves the ESP32-S3 (40 MHz) and the FT232H (30 MHz).
#   set REPO C:/path/to/AES_Verilog; source $REPO/realtime_env/rtl/common/build_spi.tcl

set rtl $REPO/realtime_env/rtl
set common $rtl/common

source $common/link_core.tcl

foreach key_bits {256 128} {
    link_hdl $rtl/aes$key_bits/aes${key_bits}_spi_wrapper.sv
}

foreach name {protocol_pkg packet_parser packet_builder byte_fifo spi_link aes_gcm_engine} {
    link_hdl $common/$name.sv
}
link_constraints $common/aes_spi.sdc $common/aes_spi.pdc
build_design_hierarchy

foreach key_bits {256 128} {
    build_root aes${key_bits}_spi_wrapper::work $common/aes_spi.sdc $common/aes_spi.pdc
}
