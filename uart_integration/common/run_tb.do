# Compiles and runs one self-checking testbench in QuestaSim, from the repository root:
#   vsim -c -do "set KEY_BITS 256; set TB tb_aes256_uart_wrapper; do uart_integration/common/run_tb.do"
# The generated library goes to RUN_DIR (default image_process/output/rtl_sim/tb).

onerror {quit -code 1 -f}
if {![info exists RUN_DIR]} {set RUN_DIR image_process/output/rtl_sim/tb}
set SRC uart_integration/aes$KEY_BITS
set LIB $RUN_DIR/work_$KEY_BITS
file delete -force $LIB
file mkdir $RUN_DIR
vlib $LIB

vlog -quiet -sv -work $LIB -f uart_integration/common/aes${KEY_BITS}_core_files.f
vlog -quiet -sv -work $LIB uart_integration/common/protocol_pkg.sv
foreach name {uart_rx uart_tx uart_cdc_link packet_parser packet_builder byte_fifo spi_link aes_gcm_engine aes_uart_cdc_wrapper} {
    vlog -quiet -sv -work $LIB uart_integration/common/$name.sv
}
vlog -quiet -sv -work $LIB $SRC/aes${KEY_BITS}_uart_wrapper.sv $SRC/aes${KEY_BITS}_spi_wrapper.sv $SRC/$TB.sv

vsim -quiet -c -t 1ps -lib $LIB -voptargs=+acc=npr $TB
run -all
quit -f
