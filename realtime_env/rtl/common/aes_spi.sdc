# Timing constraints for aes256_spi_wrapper / aes128_spi_wrapper.
# clk: 50 MHz oscillator on R18. spi_sclk: 40 MHz from an ESP32-S3 (80 MHz / 2).
# The I/O delays below are assumptions about the master and the wiring, not measurements.

create_clock -name {clk}      -period 20.000 [get_ports {clk}]
create_clock -name {spi_sclk} -period 25.000 [get_ports {spi_sclk}]

# Bytes cross through toggle synchronizers; the data is stable for several SCLK periods.
set_clock_groups -name {clk_vs_sclk} -asynchronous -group [get_clocks {clk}] -group [get_clocks {spi_sclk}]

# Mode 0: the master launches MOSI on the falling edge and the FPGA samples on the rising one.
set_input_delay -clock {spi_sclk} -clock_fall -max 8.0 [get_ports {spi_mosi}]
set_input_delay -clock {spi_sclk} -clock_fall -min 0.0 [get_ports {spi_mosi}]

# The FPGA launches MISO on the rising edge and the master samples on the next rising one.
# 5 ns covers the master's setup time and the wiring: measure and adjust at bring-up.
set_output_delay -clock {spi_sclk} -max 5.0 [get_ports {spi_miso}]
set_output_delay -clock {spi_sclk} -min 0.0 [get_ports {spi_miso}]

# spi_cs_n is an asynchronous frame marker, synchronized before use.
set_false_path -from [get_ports {rst_n spi_cs_n}]
