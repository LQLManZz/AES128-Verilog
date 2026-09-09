# AES-GCM Hardware Accelerator Multi-Variant Design Review Report

**Document:** Comprehensive RTL Analysis & UART Integration Framework Architecture  
**Author:** Senior FPGA Hardware Architect  
**Target Device:** Microchip PolarFire SoC Discovery Kit (`MPFS095T-1FCSG325E`)  
**Physical Interface:** Host PC (USB Type-C) &rarr; FTDI FT4232HL &rarr; FPGA Fabric Logic  
**Working Directory:** `uart_integration/`  

---

## 1. Architecture Overview

The codebase implements the NIST SP 800-38D standard for Authenticated Encryption with Associated Data (AEAD) in Galois/Counter Mode (GCM). The design is partitioned into:
1. **Cipher Core (CTR Mode):**
   - Stream cipher generation using AES encryption of successive counter blocks ($IV \parallel \text{Counter}$).
   - Generates hash subkey $H = \text{AES}_K(0^{128})$ and pre-counter mask $E = \text{AES}_K(J_0)$.
   - Performs XOR masking between the keystream and plaintext blocks buffered in a 16-depth synchronous FIFO.
2. **Authentication Core (GHASH & Tag Processing):**
   - Accumulates Additional Authenticated Data (AAD), Ciphertext (CT), and the 128-bit length block using Horner's rule over $GF(2^{128})$ with irreducible polynomial $P(x) = x^{128} + x^7 + x^2 + x + 1$.
   - Tag generation ($T = \text{GHASH} \oplus E$) or tag verification ($T == T_{\text{ref}}$).
3. **Control Unit (CU FSM):**
   - 11-state Moore/Mealy machine governing key expansion, $H$ calculation, IV latching, AAD streaming, Plaintext encryption, pipeline drainage, tag calculation, and transaction completion.

---

## 2. Detailed Module Hierarchy

### 2.1 AES-128 Variant Hierarchy (`RTL/AES_GCM.sv`)

```
AES_GCM (RTL/AES_GCM.sv)
├── AES_CTR (RTL/AES-CTR/AES_CTR.sv)
│   ├── FIFO (RTL/AES-CTR/FIFO/FIFO.sv, 129-bit x 16-depth)
│   │   ├── Write_pointer.sv
│   │   ├── Read_pointer.sv
│   │   └── FIFO_memory.sv
│   ├── KeyExpansion (RTL/AES-CTR/Key_Expansion/KeyExpansion.sv, 10 rounds)
│   │   ├── Counter.sv (round_index 0..9, 10 cycles)
│   │   └── GFunction.sv (RotWord, SubWord, AddRcon)
│   ├── counter_generator (RTL/AES-CTR/counter_generator/counter_generator.sv)
│   │   ├── CTR_counter.sv (32-bit counter)
│   │   ├── IV_register.sv (96-bit IV)
│   │   ├── counter_block_generator.sv (IV || CTR)
│   │   ├── J0_register.sv (IV || 0^31 || 1)
│   │   ├── type_generator.sv (data_type 01:H, 10:Keystream, 11:E)
│   │   └── output_unit.sv
│   └── AES_encryption (RTL/AES-CTR/AES_encryption/AES_encryption.sv, 12-cycle pipeline)
│       ├── AES_first_round.sv (AES_register + AddRoundKeys)
│       ├── AES_round.sv x 9 (R1..R9: SubBytes, ShiftRows, MixColumns, AddRoundKeys)
│       ├── AES_last_round.sv (SubBytes, ShiftRows, AddRoundKeys)
│       └── AES_register.sv (Stage 11 output register)
├── TagProcessing (RTL/GCM-GHASH/TagProcessing.sv)
│   ├── LengthBlockCounter.sv (Bit-length accumulator: len(A) || len(C))
│   └── GHASH.sv (Horner Accumulator)
│       └── GF128bitMultiply.sv (Combinational GF(2^128) carryless multiplier)
└── CU (RTL/CU/CU.sv, 11-state FSM controller)
```

### 2.2 AES-256 Variant Hierarchy (`RTL/AES_256_GCM.sv`)

```
AES_GCM [AES-256] (RTL/AES_256_GCM.sv)
├── AES_256_CTR (RTL/AES_256_CTR/AES_256_CTR.sv)
│   ├── FIFO (RTL/AES-CTR/FIFO/FIFO.sv, 129-bit x 16-depth, shared)
│   ├── KeyExpansion_256 (RTL/AES_256_CTR/Key_Expansion_256/KeyExpansion_256.sv, 14 rounds)
│   │   ├── Counter_256.sv (round_index 0..12, 13 cycles)
│   │   ├── SubWord.sv
│   │   └── GFunction_256.sv (AddRcon_256.sv)
│   ├── counter_generator (RTL/AES-CTR/counter_generator/counter_generator.sv, shared)
│   └── AES_256_encryption (RTL/AES_256_CTR/AES_256_encryption.sv, 16-cycle pipeline)
│       ├── AES_first_round.sv (shared)
│       ├── AES_round.sv x 13 (R1..R13, shared)
│       ├── AES_last_round.sv (shared)
│       └── AES_register.sv (Stage 15 output register, shared)
├── TagProcessing (RTL/GCM-GHASH/TagProcessing.sv, shared)
└── CU (RTL/CU/CU.sv, shared)
```

---

## 3. AES-128 Interface Summary

- **File:** `RTL/AES_GCM.sv`
- **Module Name:** `AES_GCM`
- **Cipher Key Width:** 128 bits (`input logic [127:0] cipher_key`)
- **IV Width:** 96 bits (`input logic [95:0] IV`)
- **Key Expansion Latency:** 10 clock cycles (`Counter.sv` counts 0..9)
- **AES Cipher Pipeline Latency:** 12 clock cycles
- **Control Handshakes:**
  - `load_key`, `load_IV`, `mode`, `load_tag_ref`
  - `load_AAD`, `no_AAD`, `AAD_last`
  - `load_data`, `data_in_last`
  - `key_ready`, `IV_ready`, `AAD_ready`, `data_ready`, `tag_ref_ready`
- **Status Outputs:** `tag_valid`, `verify_pass`, `data_valid`, `data_out_last`, `finish`, `CTR_counter_overflow`
- **Data Outputs:** `tag[127:0]`, `data_out[127:0]`

---

## 4. AES-256 Interface Summary

- **File:** `RTL/AES_256_GCM.sv`
- **Module Name:** `AES_GCM` *(Note: Collides with AES-128 top module name)*
- **Cipher Key Width:** Declared as `[127:0] cipher_key` at top-level port, but internally connects to `AES_256_CTR.sv` which expects `[255:0] cipher_key`.
- **IV Width:** 96 bits (`input logic [95:0] IV`)
- **Key Expansion Latency:** 13 clock cycles (`Counter_256.sv` counts 0..12)
- **AES Cipher Pipeline Latency:** 16 clock cycles (14 rounds)
- **Additional Control Ports:**
  - `input logic verify_checked` (fed to `CU.sv`)
  - `output logic verify_done` (from `CU.sv`)

---

## 5. Existing Verification Infrastructure

1. **GHASH & Tag Processing Testbenches:**
   - `RTL/GCM-GHASH/testbench/GF128bitMultiply_tb.sv`
   - `RTL/GCM-GHASH/testbench/GHASH_tb.sv`
   - `RTL/GCM-GHASH/testbench/LengthBlockCounter_tb.sv`
   - `RTL/GCM-GHASH/testbench/TagProcessing_tb.sv` (Validates against NIST SP 800-38D Appendix B Test Cases 1..4)
2. **Key Expansion Testbenches:**
   - `RTL/Key_Expansion_256/testbench_256/KeyExpansion_256_tb.sv` (Validates 256-bit key schedule against NIST FIPS 197 test vectors)
   - Unit testbenches: `tb_AddRcon.sv`, `tb_AffineTransform.sv`, `tb_Counter.sv`, `tb_GFunction.sv`, `tb_InvAffineTransform.sv`, `tb_KeyExpansion.sv`, `tb_MultiplicativeInv.sv`, `tb_SBox.sv`
3. **Reference Software:**
   - `References/aes_gcm_golden_appendixB.c` (Golden C model for NIST Appendix B vectors)

---

## 6. Clock Architecture

- **Single Clock Domain:** All modules in both AES-128 and AES-256 operate on a single synchronous clock (`clk`).
- **Nominal Frequency:** 100.0 MHz (10.0 ns period) in all testbenches.
- **Hardware Clock Source:** 50 MHz onboard oscillator on the PolarFire SoC Discovery Kit, synthesized or conditioned to 100 MHz via FPGA fabric CCC.
- **Rule Compliance:** Zero clock dividers, zero PLLs, zero asynchronous clock domain crossings in UART integration logic.

---

## 7. Reset Architecture

- **Global Asynchronous Reset:** `rst_n` (active-low asynchronous reset).
- **Internal Message Reset:** `finish_reset = (~rst_n) | finish;` (active-high). Resets message-level states and accumulators while preserving subkeys $H$ across transactions.
- **Rule Compliance:** All newly generated integration modules strictly maintain active-low asynchronous reset (`rst_n`).

---

## 8. Integration Risks & Architectural Defects

1. **RTL Defect 1: Port Width Truncation in `RTL/AES_256_GCM.sv`**
   - Port `cipher_key` in `AES_256_GCM.sv` is declared as `[127:0]`, but the instantiated `AES_256_CTR.sv` expects `[255:0]`. Connecting a 128-bit wire to a 256-bit port zero-extends the top 128 bits, corrupting `round_key[0]` and causing encryption failure.
2. **RTL Defect 2: Top-Level Module Name Collision**
   - Both `RTL/AES_GCM.sv` and `RTL/AES_256_GCM.sv` use `module AES_GCM(`. They cannot be compiled simultaneously in the same simulation or synthesis project without a namespace collision.
3. **Pipeline Latency Difference:**
   - AES-128: 12 cycles.
   - AES-256: 16 cycles (+4 cycles).
   - Handshake sequencers must be valid/strobe-driven, not fixed-cycle counters.

---

## 9. Recommended UART Integration Strategy

To fulfill the project objective of building a reusable, scalable framework supporting AES-128, AES-256, and future variants (AES-192, ECB, CTR):
1. **Shared Common Layer (`uart_integration/common/`):**
   - `uart_rx.sv`: Parameterized 8N1 receiver.
   - `uart_tx.sv`: Parameterized 8N1 transmitter.
   - `packet_parser.sv`: Unified binary packet decoder supporting 128-bit, 192-bit, and 256-bit keys.
   - `packet_builder.sv`: Unified packet serializer for ACKs, Ciphertext, and Tags.
   - `protocol_pkg.sv`: SystemVerilog package declaring command opcodes, response opcodes, and constants.
2. **Variant-Specific Wrappers:**
   - `uart_integration/aes128/aes128_uart_wrapper.sv` & `tb_aes128_uart_wrapper.sv`
   - `uart_integration/aes256/aes256_uart_wrapper.sv` & `tb_aes256_uart_wrapper.sv`
3. **Unified Python Host (`uart_integration/python/host.py`):**
   - Single CLI supporting `--mode aes128` and `--mode aes256`.
