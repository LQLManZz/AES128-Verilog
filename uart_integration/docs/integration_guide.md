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
│   ├── host.py                     # Multi-variant host client (--variant aes128 | aes256)
│   └── uart_protocol.py            # Packet protocol shared with image_process/
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

The sibling folder `image_process/` is the second demo path: it turns grayscale images into the same UART packet stream. It imports `python/uart_protocol.py` directly, so both demos always share one copy of the protocol.

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
   - **For AES-128:** Add `RTL/AES_GCM.sv`, `RTL/AES-CTR/`, `RTL/GCM-GHASH/`, `RTL/CU/`, `uart_integration/common/`, and `uart_integration/aes128/aes128_uart_wrapper.sv`. Set `aes128_uart_wrapper` as the Design Root.
   - **For AES-256:** Add `RTL/AES_256_GCM.sv`, `RTL/AES_256_CTR/`, `RTL/GCM-GHASH/`, `RTL/CU/`, `uart_integration/common/`, and `uart_integration/aes256/aes256_uart_wrapper.sv`. Set `aes256_uart_wrapper` as the Design Root.
3. Physical Constraint file (`.pdc`):
```tcl
# System Clock constraint (50 MHz on PolarFire Discovery Kit)
create_clock -period 20.000 [get_ports clk]

# Pin constraints for PolarFire SoC Discovery Kit
set_io -port_name clk      -pin_name <PIN_CLK>  -fixed true -io_std LVCMOS18
set_io -port_name rst_n    -pin_name <PIN_RST>  -fixed true -io_std LVCMOS18
set_io -port_name uart_rx  -pin_name <PIN_RX>   -fixed true -io_std LVCMOS33
set_io -port_name uart_tx  -pin_name <PIN_TX>   -fixed true -io_std LVCMOS33

# Status LEDs (PolarFire SoC Discovery Kit LEDs are active-low)
set_io -port_name led_busy -pin_name <PIN_LED1> -fixed true -io_std LVCMOS33
set_io -port_name led_done -pin_name <PIN_LED2> -fixed true -io_std LVCMOS33
```
> [!NOTE]
> Trên PolarFire SoC Discovery Kit, các đèn LED không sử dụng (LED3..LED7 tương ứng các chân `U20`, `U21`, `AA18`, `V16`, `U15`) cần được gán cố định mức logic 0 (`1'b0`) ở đầu ra để tắt hoàn toàn, tránh tình trạng đèn tự sáng khi cấp nguồn. Module wrapper đã tích hợp sẵn bus `led_unused = 5'b00000`.

4. Run **Synthesize**, **Place and Route**, and **Generate Bitstream**. Program the device via FlashPro Express.

---

## 4. Python Host Application Usage

Install prerequisites:
```bash
pip install pyserial
```

The host CLI utility is located at `uart_integration/python/host.py`.

### 4.1 CLI Argument Reference

| Argument | Description | Default |
|:---|:---|:---:|
| `-v`, `--variant` | Core variant: `aes128` or `aes256` | `aes256` |
| `-op`, `--operation` | Operation mode: `test`, `encrypt`, `decrypt`, `interactive` | `test` |
| `-p`, `--port` | Serial COM port (e.g., `COM4` or `/dev/ttyUSB0`) | Auto-detect |
| `-b`, `--baud` | UART baudrate | `2000000` |
| `-t`, `--timeout` | UART read timeout in seconds | `3.0` |
| `--verbose` | Print low-level TX/RX packet hex payloads | Disabled |
| `--mock`, `--dry-run` | Simulate FPGA hardware responses offline without board | Disabled |
| `--key` | Cipher key (16B hex for AES-128, 32B hex for AES-256) | None |
| `--iv` | 12-byte (96-bit) Initialization Vector in hex | None |
| `--aad` | Additional Authenticated Data (hex string or plain text) | Optional |
| `--pt`, `--plaintext` | Plaintext to encrypt (hex string or plain text) | None |
| `--ct`, `--ciphertext` | Ciphertext to decrypt (hex string) | None |
| `--tag` | Expected 16-byte authentication tag in hex, required for decrypt mode | None |
| `--test`, `--test-nist` | Execute automated self-test verification suite | False |
| `--benchmark [N]` | Run continuous benchmark stream of N packets for visual LED activity | Disabled (const: 50) |
| `-i`, `--interactive` | Launch interactive terminal UI | False |

---

### 4.2 Automated Hardware Self-Testing

Runs the official NIST SP 800-38D Appendix B test suite against the FPGA and outputs a summary table and a per-vector audit. Hardware output is compared byte-for-byte with the NIST SP 800-38D values, with no bit reversal:

```bash
# Test AES-256 core (GCM spec TC14, TC15, custom AAD vector + Decryption Verification)
python uart_integration/python/host.py -v aes256 --test

# Test AES-128 core (NIST TC2, TC3 + Decryption Verification)
python uart_integration/python/host.py -v aes128 --test

# Offline Simulation / Dry-run test (no board required)
python uart_integration/python/host.py -v aes256 --test --mock
```

Sample output:
```text
┌──────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
│                                NIST SP 800-38D HARDWARE VERIFICATION SUMMARY                                 │
├──────┬──────────────────────────┬────────┬────────┬────────┬──────────┬────────────────┬──────────┬──────────┤
│  ID  │ Test Case Description    │  Mode  │  Data  │  AAD   │  Cipher  │    Auth Tag    │   Tag    │  Status  │
├──────┼──────────────────────────┼────────┼────────┼────────┼──────────┼────────────────┼──────────┼──────────┤
│  1   │ GCM spec TC14 (Zero... │  ENC   │    16B │     0B │   PASS   │ d0d1c8...b919  │   PASS   │   PASS   │
│  2   │ GCM spec TC15 (64B ... │  ENC   │    64B │     0B │   PASS   │ ed974c...af03  │   PASS   │   PASS   │
│  3   │ Custom AAD+PT vector 16B │  ENC   │    16B │    16B │   PASS   │ 539a37...ee6b  │   PASS   │   PASS   │
│  4   │ AES-256 Decrypt & Verify │  DEC   │    16B │    16B │   PASS   │ 539a37...ee6b  │   PASS   │   PASS   │
└──────┴──────────────────────────┴────────┴────────┴────────┴──────────┴────────────────┴──────────┴──────────┘
 [✓] RESULT: ALL 4/4 VERIFICATION CHECKS PASSED SUCCESSFULLY!
```

---

### 4.3 Custom Encryption & Decryption

#### AES-256 Encryption with AAD:
```bash
python uart_integration/python/host.py -v aes256 -op encrypt --key feffe9928665731c6d6a8f9467308308feffe9928665731c6d6a8f9467308308 --iv  cafebabefacedbaddecaf888 --aad feedfacedeadbeeffeedfacedeadbeef --pt  d9313225f88406e5a55909c5aff5269a
```

#### AES-256 Decryption & Tag Verification:
The decrypt command loads `--tag` with `LOAD_TAG_REF`, so the IP verifies it and releases the plaintext only on a match (NIST SP 800-38D byte order):
```bash
python uart_integration/python/host.py -v aes256 -op decrypt \
    --key feffe9928665731c6d6a8f9467308308feffe9928665731c6d6a8f9467308308 \
    --iv  cafebabefacedbaddecaf888 \
    --aad feedfacedeadbeeffeedfacedeadbeef \
    --ct  522dc1f099567d07f47f37a32a84427d \
    --tag 03a2864be371e37753a80e8e240ff2f0
```

Output report:
```text
┌─────────────────────────────────────────────────────────────────────────────┐
│                  AES-GCM HARDWARE REPORT [AES256 - DECRYPT]                 │
├────────────────────────────┬────────────────────────────────────────────────┤
│ Operation                  │ DECRYPT                                        │
│ Hardware Variant           │ AES256                                         │
│ UART Port & Baud           │ COM4 @ 115200 bps                              │
│ Round-Trip Latency         │ 22.48 ms                                       │
├────────────────────────────┼────────────────────────────────────────────────┤
│ Key (32B)                  │ feffe9928665731c6d6a8f9467308308feffe9... (32B) │
│ IV (12B)                   │ cafebabefacedbaddecaf888                       │
│ AAD (16B)                  │ feedfacedeadbeeffeedfacedeadbeef               │
│ Ciphertext In (16B)        │ 522dc1f099567d07f47f37a32a84427d               │
├────────────────────────────┼────────────────────────────────────────────────┤
│ Plaintext                  │ d9313225f88406e5a55909c5aff5269a               │
│ Decrypted ASCII            │ .12%.....Y....&.                               │
├────────────────────────────┼────────────────────────────────────────────────┤
│ Auth Tag                   │ 03a2864be371e37753a80e8e240ff2f0               │
│ Tag: Expected Input        │ 03a2864be371e37753a80e8e240ff2f0               │
├────────────────────────────┼────────────────────────────────────────────────┤
│ Integrity Check            │ [✓] AUTHENTIC (Tag Matched)                    │
└────────────────────────────┴────────────────────────────────────────────────┘
```

---

### 4.4 Continuous Activity Benchmark (Quan sát trực quan trạng thái phần cứng)

Vì tốc độ tính toán phần cứng AES-GCM rất nhanh (~800 ns cho mỗi khối 16 byte), mắt thường không thể quan sát kịp một lần mã hóa đơn lẻ. Tính năng `--benchmark` cho phép truyền một luồng liên tục $N$ gói tin xuống FPGA, giúp mắt thường quan sát dễ dàng:
- **Đèn LED UART RX/TX** trên kit nhấp nháy liên hồi theo luồng dữ liệu.
- **Đèn `led_busy` (chân `T18`)** trên FPGA sáng liên tục trong suốt quá trình xử lý luồng.
- **Màn hình terminal** hiển thị thanh tiến trình động theo thời gian thực kèm tốc độ thông lượng:

```bash
# Chạy benchmark 100 gói tin liên tục để quan sát đèn LED trên kit
python uart_integration/python/host.py -v aes256 --benchmark 100
```

---

## 5. Bit Ordering & Data Representation (NIST SP 800-38D)

### 5.1 Bit Ordering in the RTL

AES-GCM has two engines, and both follow NIST SP 800-38D byte-for-byte on every port:
1. **AES CTR Mode Core** (Ciphertext): standard big-endian, MSB-first byte mapping.
2. **GHASH Core** (Authentication Tag): NIST Section 6.3 represents a block $X = x_0 x_1 \dots x_{127}$ as a polynomial with $x_0$ (the leftmost bit, bit 127 of a SystemVerilog vector) as the coefficient of $x^0$. `RTL/GCM-GHASH/GF128bitMultiply.sv` multiplies in the plain polynomial basis (bit 0 is $x^0$, reduction polynomial $x^{128} + x^7 + x^2 + x + 1$), so `RTL/GCM-GHASH/GHASH.sv` bit-reverses all 128 bits of the subkey $H$, of each multiplier input and of the product. This is wiring only and costs no logic.

Because of this, `H`, `AAD`, `CT`, the length block, `ghash_out` and the final `tag` use the same bit order as the NIST test vectors. No bit reversal is needed on the host.

> **Hardware built from older RTL.** Before this change the GHASH core did not reverse the bits, so the tag differed from NIST (for example `2c4fa7cb...` instead of `ab6e47d4...` for TC2). A bitstream synthesized from that RTL still returns those tags and must be rebuilt from the current RTL.

---

### 5.2 NIST SP 800-38D Reference Vectors

Ciphertext and tag returned by the hardware equal the following values:

| Test Case | Variant | PT / AAD | Ciphertext | Authentication Tag |
|:---|:---:|:---:|:---|:---|
| **NIST TC2** | AES-128 | 16B PT<br>0B AAD | `0388dace60b6a392f328c2b971b2fe78` | `ab6e47d42cec13bdf53a67b21257bddf` |
| **NIST TC3** | AES-128 | 64B PT<br>0B AAD | `42831ec2217774244b7221b784d0d49c...`<br>(64 bytes) | `4d5c2af327cd64a62cf35abd2ba6fab4` |
| **GCM spec TC14** | AES-256 | 16B PT<br>0B AAD | `cea7403d4d606b6e074ec5d3baf39d18` | `d0d1c8a799996bf0265b98b5d48ab919` |
| **GCM spec TC15** | AES-256 | 64B PT<br>0B AAD | `522dc1f099567d07f47f37a32a84427d...`<br>(64 bytes) | `b094dac5d93471bdec1a502270e3cc6c` |
| **Custom AAD vector** | AES-256 | 16B PT<br>16B AAD | `522dc1f099567d07f47f37a32a84427d` | `03a2864be371e37753a80e8e240ff2f0` |

The tags were cross-checked against the PyCryptodome `AES.MODE_GCM` implementation.

---

### 5.3 What `host.py` Does

1. **Direct display:** the ciphertext/plaintext and the tag are printed exactly as received from the FPGA.
2. **Tag verification:** in decrypt mode (`-op decrypt`), the IP compares its tag with `--tag`, and the host checks that `VERIFY_RESULT` agrees.
3. **Self-test audit:** `--test` prints a summary table and, for every vector, the hardware tag next to the NIST reference tag.
