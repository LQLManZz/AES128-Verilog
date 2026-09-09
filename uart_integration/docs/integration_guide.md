# AES-GCM FPGA Multi-Variant Integration & Simulation Guide

**Board:** PolarFire SoC Discovery Kit (`MPFS-DISCO-KIT` / `MPFS095T-1FCSG325E`)  
**Target Toolchain:** Microchip Libero SoC v2023.2+ or ModelSim / QuestaSim / Icarus Verilog  
**Location:** `uart_integration/`  

---

## 1. Directory Structure

```
uart_integration/
│
├── common/
│   ├── protocol_pkg.sv             # Common SystemVerilog package
│   ├── uart_rx.sv                  # Shared 8N1 UART receiver
│   ├── uart_tx.sv                  # Shared 8N1 UART transmitter
│   ├── packet_parser.sv            # Shared binary packet decoder
│   └── packet_builder.sv           # Shared response serializer
│
├── aes128/
│   ├── aes128_uart_wrapper.sv      # Dedicated AES-128 integration wrapper
│   └── tb_aes128_uart_wrapper.sv   # Self-checking testbench for AES-128
│
├── aes256/
│   ├── aes256_uart_wrapper.sv      # Dedicated AES-256 integration wrapper
│   └── tb_aes256_uart_wrapper.sv   # Self-checking testbench for AES-256
│
├── python/
│   └── host.py                     # Multi-variant host client (--mode aes128 | aes256)
│
├── docs/
│   ├── architecture.md
│   ├── protocol.md
│   ├── integration_guide.md
│   ├── update_log.md
│   ├── design_review_report.md
│   └── variant_compatibility_matrix.md
│
└── backups/                        # Safety archives of previous revisions
```

---

## 2. Simulation Instructions

### 2.1 Simulating AES-128 Variant (`work.tb_aes128_uart_wrapper`)

#### ModelSim / QuestaSim:
```bash
vlib work

# Compile Core RTL
vlog -sv ../RTL/AES-CTR/SBox/*.sv
vlog -sv ../RTL/AES-CTR/Key_Expansion/GFunction/*.sv
vlog -sv ../RTL/AES-CTR/Key_Expansion/*.sv
vlog -sv ../RTL/AES-CTR/FIFO/*.sv
vlog -sv ../RTL/AES-CTR/counter_generator/*.sv
vlog -sv ../RTL/AES-CTR/AES_encryption/AES_round/MixColumns/*.sv
vlog -sv ../RTL/AES-CTR/AES_encryption/AES_round/*.sv
vlog -sv ../RTL/AES-CTR/AES_encryption/*.sv
vlog -sv ../RTL/AES-CTR/*.sv
vlog -sv ../RTL/GCM-GHASH/*.sv
vlog -sv ../RTL/CU/*.sv
vlog -sv ../RTL/AES_GCM.sv

# Compile Shared Common Layer & AES-128 Wrapper
vlog -sv common/protocol_pkg.sv
vlog -sv common/uart_rx.sv
vlog -sv common/uart_tx.sv
vlog -sv common/packet_parser.sv
vlog -sv common/packet_builder.sv
vlog -sv aes128/aes128_uart_wrapper.sv
vlog -sv aes128/tb_aes128_uart_wrapper.sv

# Run Simulation
vsim -c -do "run -all; quit" work.tb_aes128_uart_wrapper
```

### 2.2 Simulating AES-256 Variant (`work.tb_aes256_uart_wrapper`)

#### ModelSim / QuestaSim:
```bash
vlib work

# Compile Shared Core RTL Components
vlog -sv ../RTL/AES-CTR/SBox/*.sv
vlog -sv ../RTL/AES-CTR/FIFO/*.sv
vlog -sv ../RTL/AES-CTR/counter_generator/*.sv
vlog -sv ../RTL/AES-CTR/AES_encryption/AES_round/MixColumns/*.sv
vlog -sv ../RTL/AES-CTR/AES_encryption/AES_round/*.sv
vlog -sv ../RTL/GCM-GHASH/*.sv
vlog -sv ../RTL/CU/*.sv

# Compile AES-256 Specific Core RTL
vlog -sv ../RTL/AES_256_CTR/Key_Expansion_256/GFunction_256/*.sv
vlog -sv ../RTL/AES_256_CTR/Key_Expansion_256/*.sv
vlog -sv ../RTL/AES_256_CTR/*.sv
vlog -sv ../RTL/AES_256_GCM.sv

# Compile Shared Common Layer & AES-256 Wrapper
vlog -sv common/protocol_pkg.sv
vlog -sv common/uart_rx.sv
vlog -sv common/uart_tx.sv
vlog -sv common/packet_parser.sv
vlog -sv common/packet_builder.sv
vlog -sv aes256/aes256_uart_wrapper.sv
vlog -sv aes256/tb_aes256_uart_wrapper.sv

# Run Simulation
vsim -c -do "run -all; quit" work.tb_aes256_uart_wrapper
```

---

## 3. Microchip Libero SoC Synthesis (PolarFire SoC Discovery Kit)

1. Open or create a Libero SoC project targeted to `MPFS095T-1FCSG325E`.
2. Add the required RTL files for your chosen target variant:
   - For AES-128: Add `RTL/AES_GCM.sv`, `RTL/AES-CTR/`, `RTL/GCM-GHASH/`, `RTL/CU/`, `uart_integration/common/`, and `uart_integration/aes128/aes128_uart_wrapper.sv`. Set `aes128_uart_wrapper` as the Design Root.
   - For AES-256: Add `RTL/AES_256_GCM.sv`, `RTL/AES_256_CTR/`, `RTL/GCM-GHASH/`, `RTL/CU/`, `uart_integration/common/`, and `uart_integration/aes256/aes256_uart_wrapper.sv`. Set `aes256_uart_wrapper` as the Design Root.
3. Constraint file (.pdc):
```tcl
# Clock constraint (100 MHz)
create_clock -period 10.000 [get_ports clk]

# Pin constraints for PolarFire SoC Discovery Kit
set_io -port_name clk      -pin_name <PIN_CLK>  -fixed true -io_std LVCMOS18
set_io -port_name rst_n    -pin_name <PIN_RST>  -fixed true -io_std LVCMOS18
set_io -port_name uart_rx  -pin_name <PIN_RX>   -fixed true -io_std LVCMOS33
set_io -port_name uart_tx  -pin_name <PIN_TX>   -fixed true -io_std LVCMOS33
set_io -port_name led_busy -pin_name <PIN_LED1> -fixed true -io_std LVCMOS33
set_io -port_name led_done -pin_name <PIN_LED2> -fixed true -io_std LVCMOS33
```
4. Run **Synthesize**, **Place and Route**, and **Generate Bitstream**. Program via FlashPro Express.

---

## 4. Python Host Application Usage

```bash
pip install pyserial
```

### Automated Self-Testing Against Hardware:
```bash
# Test AES-128 (NIST Appendix B Test Cases 2 & 3)
python uart_integration/python/host.py --mode aes128 --test-nist

# Test AES-256 (NIST Appendix B Test Cases 16 & 17)
python uart_integration/python/host.py --mode aes256 --test-nist
```

### Custom Encryption:
```bash
# AES-128
python uart_integration/python/host.py --mode aes128 \
    --key 00000000000000000000000000000000 \
    --iv  000000000000000000000000 \
    --pt  00000000000000000000000000000000

# AES-256
python uart_integration/python/host.py --mode aes256 \
    --key 0000000000000000000000000000000000000000000000000000000000000000 \
    --iv  000000000000000000000000 \
    --pt  00000000000000000000000000000000
```
