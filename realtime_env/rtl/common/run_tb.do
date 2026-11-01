# Compiles and runs one self-checking testbench in QuestaSim, from the repository root:
#   vsim -c -do "set KEY_BITS 256; set TB tb_aes256_uart_wrapper; do realtime_env/rtl/common/run_tb.do"
# The generated library goes to RUN_DIR (default realtime_env/output/rtl_sim/tb).

onerror {quit -code 1 -f}
if {![info exists RUN_DIR]} {set RUN_DIR realtime_env/output/rtl_sim/tb}
set SRC realtime_env/rtl/aes$KEY_BITS
set LIB $RUN_DIR/work_$KEY_BITS
file delete -force $LIB
file mkdir $RUN_DIR
vlib $LIB

vlog -quiet -sv -work $LIB -f realtime_env/rtl/common/aes${KEY_BITS}_core_files.f
vlog -quiet -sv -work $LIB realtime_env/rtl/common/protocol_pkg.sv
foreach name {uart_rx uart_tx uart_cdc_link packet_parser packet_builder byte_fifo spi_link aes_gcm_engine aes_uart_cdc_wrapper} {
    vlog -quiet -sv -work $LIB realtime_env/rtl/common/$name.sv
}
vlog -quiet -sv -work $LIB $SRC/aes${KEY_BITS}_uart_wrapper.sv $SRC/aes${KEY_BITS}_spi_wrapper.sv $SRC/$TB.sv

vsim -quiet -c -t 1ps -lib $LIB -voptargs=+acc=npr $TB
run -all
quit -f
