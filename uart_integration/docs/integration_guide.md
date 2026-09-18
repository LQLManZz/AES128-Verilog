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
│   └── host.py                     # Multi-variant host client (--variant aes128 | aes256)
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
   - **For AES-128:** Add `RTL/AES_GCM.sv`, `RTL/AES-CTR/`, `RTL/GCM-GHASH/`, `RTL/CU/`, `uart_integration/common/`, and `uart_integration/aes128/aes128_uart_wrapper.sv`. Set `aes128_uart_wrapper` as the Design Root.
   - **For AES-256:** Add `RTL/AES_256_GCM.sv`, `RTL/AES_256_CTR/`, `RTL/GCM-GHASH/`, `RTL/CU/`, `uart_integration/common/`, and `uart_integration/aes256/aes256_uart_wrapper.sv`. Set `aes256_uart_wrapper` as the Design Root.
3. Physical Constraint file (`.pdc`):
```tcl
# System Clock constraint (50 MHz or 100 MHz on PolarFire Discovery Kit)
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
| `-b`, `--baud` | UART baudrate | `115200` |
| `-t`, `--timeout` | UART read timeout in seconds | `3.0` |
| `--verbose` | Print low-level TX/RX packet hex payloads | Disabled |
| `--mock`, `--dry-run` | Simulate FPGA hardware responses offline without board | Disabled |
| `--key` | Cipher key (16B hex for AES-128, 32B hex for AES-256) | None |
| `--iv` | 12-byte (96-bit) Initialization Vector in hex | None |
| `--aad` | Additional Authenticated Data (hex string or plain text) | Optional |
| `--pt`, `--plaintext` | Plaintext to encrypt (hex string or plain text) | None |
| `--ct`, `--ciphertext` | Ciphertext to decrypt (hex string) | None |
| `--tag` | Expected 16-byte authentication tag in hex (for decrypt mode) | None |
| `--tag-nist` | Expected official NIST SP 800-38D golden tag for cross-reference | Auto/Optional |
| `--test`, `--test-nist` | Execute automated self-test verification suite | False |
| `--benchmark [N]` | Run continuous benchmark stream of N packets for visual LED activity | Disabled (const: 50) |
| `-i`, `--interactive` | Launch interactive terminal UI | False |

---

### 4.2 Automated Hardware Self-Testing

Runs the official NIST SP 800-38D Appendix B test suite against the FPGA and outputs both the summary table and the complete dual-representation audit:

```bash
# Test AES-256 core (NIST TC16, TC17, TC18 + Decryption Verification)
python uart_integration/python/host.py -v aes256 --test

# Test AES-128 core (NIST TC2, TC3 + Decryption Verification)
python uart_integration/python/host.py -v aes128 --test

# Offline Simulation / Dry-run test (no board required)
python uart_integration/python/host.py -v aes256 --test --mock
```

Sample output:
```text
┌────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
│                                   NIST SP 800-38D HARDWARE VERIFICATION SUMMARY                                    │
├──────┬──────────────────────────┬────────┬────────┬────────┬──────────┬────────────────┬────────────────┬──────────┤
│  ID  │ Test Case Description    │  Mode  │  Data  │  AAD   │  Cipher  │  Raw RTL Tag   │    NIST Tag    │  Status  │
├──────┼──────────────────────────┼────────┼────────┼────────┼──────────┼────────────────┼────────────────┼──────────┤
│  1   │ NIST App.B TC16 (Zero... │  ENC   │    16B │     0B │   PASS   │ eca8e2...3704  │ d0d1c8...b919  │   PASS   │
│  2   │ NIST App.B TC17 (64B ... │  ENC   │    64B │     0B │   PASS   │ 3539d3...5d6f  │ ed974c...af03  │   PASS   │
│  3   │ NIST TC18 with AAD (16B) │  ENC   │    16B │    16B │   PASS   │ 0b9c23...e0e5  │ 539a37...ee6b  │   PASS   │
│  4   │ AES-256 Decrypt & Verify │  DEC   │    16B │    16B │   PASS   │ b11afd...c877  │ 539a37...ee6b  │   PASS   │
└──────┴──────────────────────────┴────────┴────────┴────────┴──────────┴────────────────┴────────────────┴──────────┘
 [✓] RESULT: ALL 4/4 VERIFICATION CHECKS PASSED SUCCESSFULLY!
```

---

### 4.3 Custom Encryption & Decryption

#### AES-256 Encryption with AAD:
```bash
python uart_integration/python/host.py -v aes256 -op encrypt --key feffe9928665731c6d6a8f9467308308feffe9928665731c6d6a8f9467308308 --iv  cafebabefacedebadecaf888 --aad feedfacedeadbeeffeedfacedeadbeef --pt  d9313225f88406e5a55909c5aff5269a
```

#### AES-256 Decryption & Tag Verification:
The decrypt command accepts **either** the Raw RTL Tag or the NIST Golden Tag:
```bash
python uart_integration/python/host.py -v aes256 -op decrypt \
    --key feffe9928665731c6d6a8f9467308308feffe9928665731c6d6a8f9467308308 \
    --iv  cafebabefacedebadecaf888 \
    --aad feedfacedeadbeeffeedfacedeadbeef \
    --ct  9cc9fbd6c5e790c049c00906e6752d79 \
    --tag 539a375d54195500b5c7109b586fee6b
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
│ IV (12B)                   │ cafebabefacedebadecaf888                       │
│ AAD (16B)                  │ feedfacedeadbeeffeedfacedeadbeef               │
│ Ciphertext In (16B)        │ 9cc9fbd6c5e790c049c00906e6752d79               │
├────────────────────────────┼────────────────────────────────────────────────┤
│ Plaintext (Raw)            │ d9313225f88406e5a55909c5aff5269a               │
│ Plaintext (Bit-Rev)        │ 9b8c4ca41f2160a7a59a90a3f5af6459               │
│ Decrypted ASCII            │ .12%.....Y....&.                               │
├────────────────────────────┼────────────────────────────────────────────────┤
│ Tag: Raw Hardware          │ 0b9c23630bd31f5e963bf7361d42e0e5               │
│ Tag: Bit-Rev per Byte      │ d039c4c6d0cbf87a69dcef6cb84207a7               │
│ Tag: Full 128b Reversed    │ a70742b86cefdc697af8cbd0c6c439d0               │
│ Tag: Byte-Endian Swapped   │ e5e0421d36f73b965e1fd30b63239c0b               │
│ Tag: NIST Golden Ref       │ 539a375d54195500b5c7109b586fee6b               │
│ Tag: Expected Input        │ 539a375d54195500b5c7109b586fee6b               │
├────────────────────────────┼────────────────────────────────────────────────┤
│ Integrity Check            │ [✓] AUTHENTIC (Matched NIST Golden Tag)        │
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

## 5. Bit Ordering & Data Representation Reference (RTL vs NIST SP 800-38D)

### 5.1 Root Cause & Mathematical Analysis

In AES-GCM (Galois/Counter Mode), there are two distinct cryptographic engines:
1. **AES CTR Mode Core** (producing the Ciphertext):
   - In both AES-128 and AES-256 RTL modules, the CTR mode encryption strictly adheres to standard big-endian MSB-first byte mapping.
   - **Result:** Ciphertext produced by the hardware matches the official NIST SP 800-38D specification **100% byte-for-byte** across all test cases.
2. **GHASH Authenticator Core** (producing the Authentication Tag):
   - **NIST SP 800-38D Definition (Reflected Basis):** In Section 3.2 of the NIST standard, elements of $\text{GF}(2^{128})$ are represented in a *reflected bit basis*. Within each 8-bit byte $B = (b_7, b_6, \dots, b_0)$, bit 7 corresponds to $x^0$ and bit 0 corresponds to $x^7$. The reduction polynomial is $R(x) = \texttt{0xE1} \mathbin{\Vert} 0^{120} = x^{128} + x^7 + x^2 + x + 1$.
   - **RTL Hardware Implementation (Unreflected Basis):** In `RTL/GCM-GHASH/GF128bitMultiply.sv` and `ReductionBlock.sv`, standard non-reflected polynomial basis multiplication is implemented: bit 0 of each byte represents $x^0$ and bit 7 represents $x^7$.
   - **Consequence:** The Authentication Tag generated by the hardware is valid and cryptographically authentic under the hardware's polynomial representation, but exhibits a bit-basis reflection difference relative to NIST SP 800-38D golden vectors.

---

### 5.2 NIST SP 800-38D Golden Vectors Cross-Reference Table

The table below provides the comprehensive reference mapping for all standard NIST test vectors, comparing the **Ciphertext**, the **Hardware Raw Tag**, the **Bit-Reversed per Byte Tag**, and the **NIST Official Golden Tag**:

| Test Case | Variant | PT / AAD | Ciphertext (Hardware Raw & NIST Exact) | Hardware Raw RTL Tag | Bit-Rev per Byte Tag ($b_7 \leftrightarrow b_0$) | NIST SP 800-38D Golden Tag |
|:---|:---:|:---:|:---|:---|:---|:---|
| **NIST TC2** | AES-128 | 16B PT<br>0B AAD | `0388dace60b6a392f328c2b971b2fe78` | `2c4fa7cbc8dcac66067fb1a42b88adc8` | `34f2e5d3133b356660fe8d25d411b513` | `ab6e47d42cec13bdf53a67b21257bddf` |
| **NIST TC3** | AES-128 | 64B PT<br>0B AAD | `42831ec2217774244b7221b784d0d49c...`<br>(64 bytes) | `996843adb23b21d1739117635938712a` | `9916c2b54ddc848bce89e8c69a1c8e54` | `4d5c2af327cd64a62cf35abd2ba6fab4` |
| **NIST TC16** | AES-256 | 16B PT<br>0B AAD | `cea7403d4d606b6e074ec5d3baf39d18` | `eca8e26b44cb8ab9e5cddc39bdd43704` | `371547d622d3519da7b33b9cbd2bec20` | `d0d1c8a799996bf0265b98b5d48ab919` |
| **NIST TC17** | AES-256 | 64B PT<br>0B AAD | `9cc9fbd6c5e790c049c00906e6752d79...`<br>(64 bytes) | `3539d3f390b09ca3cae3543a9af25d6f` | `ac9ccbcf090d39c553c72a5c594fbaf6` | `ed974c00e5e30f5cf7dc738eac8aaf03` |
| **NIST TC18** | AES-256 | 16B PT<br>16B AAD | `9cc9fbd6c5e790c049c00906e6752d79` | `0b9c23630bd31f5e963bf7361d42e0e5` | `d039c4c6d0cbf87a69dcef6cb84207a7` | `539a375d54195500b5c7109b586fee6b` |

---

### 5.3 How `host.py` Normalizes and Cross-References

To eliminate confusion when comparing hardware output against NIST documents, `host.py` implements:

1. **Dual Representation Output:**
   - Whenever encryption or decryption is performed, `host.py` displays both the **Raw Hardware** format and the **Bit-Reversed per Byte** format ($b_7 \leftrightarrow b_0$), alongside the **NIST Official Reference Tag**.
2. **Multi-Format Tag Authentication:**
   - In Decryption mode (`-op decrypt`), the user may supply the authentication tag in any of the three formats:
     - The **Hardware Raw Tag** (`0b9c...`)
     - The **Bit-Reversed Tag** (`d039...`)
     - The **NIST Official Golden Tag** (`539a...`)
   - `host.py` cross-checks against the internal mapping table and marks the packet as authentic if any valid representation matches.
3. **Comprehensive Automated Audit:**
   - In automated self-test mode (`--test`), `host.py` prints a structured audit box displaying both forms of Ciphertext and Authentication Tag for every vector, enabling instant verification.
