# AES-128-GCM vs AES-256-GCM Hardware Variant Compatibility Matrix

**Document Version:** 1.0  
**Target Device:** Microchip PolarFire SoC Discovery Kit (`MPFS095T-1FCSG325E`)  
**Source RTL Compared:** `RTL/AES_GCM.sv` (AES-128) vs `RTL/AES_256_GCM.sv` (AES-256)  

---

## 1. Feature & Interface Comparison Matrix

| Architectural Feature | AES-128-GCM (`RTL/AES_GCM.sv`) | AES-256-GCM (`RTL/AES_256_GCM.sv`) | Compatibility / Integration Note |
|---|---|---|---|
| **Source File Location** | `RTL/AES_GCM.sv` | `RTL/AES_256_GCM.sv` | Distinct files in `RTL/` |
| **Top Module Name** | `AES_GCM` | `AES_GCM` *(Collision!)* | **Defect:** Requires renaming `RTL/AES_256_GCM.sv` to `AES_256_GCM` to avoid compile collision. |
| **Cipher Engine Module** | `AES_CTR` | `AES_256_CTR` | Different submodule instances |
| **AES Rounds** | 10 rounds | 14 rounds | AES specification standard |
| **Key Schedule Module** | `KeyExpansion.sv` | `KeyExpansion_256.sv` | 10 round keys vs 15 round keys |
| **Key Expansion Latency** | **10 clock cycles** (`round_index`: 0..9) | **13 clock cycles** (`round_index`: 0..12) | AES-256 requires 3 additional cycles for key schedule |
| **Cipher Pipeline Latency** | **12 clock cycles** | **16 clock cycles** | AES-256 pipeline is 4 cycles longer |
| **Cipher Key Port Width** | `[127:0] cipher_key` | `[127:0] cipher_key` *(Defect!)* | **Defect:** `AES_256_GCM.sv` port is declared as `[127:0]`, but internal `AES_256_CTR` expects `[255:0]`. |
| **IV Port Width** | `[95:0] IV` (12 bytes) | `[95:0] IV` (12 bytes) | **Identical** (NIST SP 800-38D standard 96-bit IV) |
| **AAD Input Interface** | `[127:0] AAD`, `load_AAD`, `no_AAD`, `AAD_last` | `[127:0] AAD`, `load_AAD`, `no_AAD`, `AAD_last` | **Identical** handshake and port widths |
| **Plaintext Input Interface** | `[127:0] data_in`, `load_data`, `data_in_last` | `[127:0] data_in`, `load_data`, `data_in_last` | **Identical** handshake and port widths |
| **Ciphertext Output Interface**| `[127:0] data_out`, `data_valid`, `data_out_last` | `[127:0] data_out`, `data_valid`, `data_out_last` | **Identical** handshake and port widths |
| **Authentication Tag Interface**| `[127:0] tag`, `tag_valid` | `[127:0] tag`, `tag_valid` | **Identical** handshake and port widths |
| **Decryption Reference Tag** | `[127:0] tag_ref`, `load_tag_ref`, `verify_pass` | `[127:0] tag_ref`, `load_tag_ref`, `verify_pass` | **Identical** |
| **New Verification Ports** | Not present / unconnected | `input verify_checked`, `output verify_done` | **Difference:** Added in AES-256 for mode 1 verification |
| **Start Signal** | `load_key \| load_IV` (Internal `start`) | `load_key \| load_IV` (Internal `start`) | **Identical** trigger logic |
| **Ready Handshake Signals** | `key_ready`, `IV_ready`, `tag_ref_ready`, `AAD_ready`, `data_ready` | `key_ready`, `IV_ready`, `tag_ref_ready`, `AAD_ready`, `data_ready` | **Identical** handshake signals driven by `CU.sv` |
| **Done / Finish Signal** | `finish` (1-cycle pulse) | `finish` (1-cycle pulse) | **Identical** |
| **Clock Domain** | Single `clk` (100 MHz nominal) | Single `clk` (100 MHz nominal) | **Identical** |
| **Reset Convention** | Active-low asynchronous `rst_n` | Active-low asynchronous `rst_n` | **Identical** |
| **Internal Context Reset** | `finish_reset = (~rst_n) \| finish;` | `finish_reset = (~rst_n) \| finish;` | **Identical** |
| **Input FIFO Structure** | Synchronous FIFO (129-bit x 16-depth) | Synchronous FIFO (129-bit x 16-depth) | **Identical** shared module `RTL/AES-CTR/FIFO/` |

---

## 2. Structural Architecture & Handshake Timing Comparison

### 2.1 Key Expansion & Subkey Calculation Timing
```
Event                       AES-128 Latency              AES-256 Latency
-----------------------------------------------------------------------------------
Assert load_key + load_IV   T0                           T0
Key Expansion Running       T1 .. T10 (10 cycles)        T1 .. T13 (13 cycles)
expansion_finish Asserts    T10                          T13
H Subkey Calculation       T1 .. T12 (in AES pipeline)  T1 .. T16 (in AES pipeline)
H_loaded Asserts            T12                          T16
CU enters WAIT_AAD          T12 (AAD_ready = 1)          T16 (AAD_ready = 1)
```

### 2.2 Plaintext Encryption Pipeline Timing
```
Event                       AES-128 Latency              AES-256 Latency
-----------------------------------------------------------------------------------
Assert load_data            Cycle N                      Cycle N
First Ciphertext Emerges    Cycle N + 12                 Cycle N + 16
data_valid Asserts          Cycle N + 12                 Cycle N + 16
gen_J0 Enters Pipeline      Cycle N + 1 (after last PT)  Cycle N + 1 (after last PT)
E Mask Valid (E_loaded)     Cycle N + 13                 Cycle N + 17
Tag Valid (tag_valid)       Cycle N + 14                 Cycle N + 18
finish Pulse                Cycle N + 15                 Cycle N + 19
```

---

## 3. Key Findings for Multi-Variant UART Wrapper Design

1. **Protocol Uniformity:**
   Because both variants share the exact same binary packet format (`CMD`, `LENGTH`, `PAYLOAD`), the exact same UART physical transceivers (`uart_rx.sv`, `uart_tx.sv`), and the exact same packet builder/parser logic, the common layer in `uart_integration/common/` can be **100% shared with zero code duplication**.
2. **Dynamic Handshake Tolerance:**
   Because the wrapper designs utilize event-driven handshakes (`aes_aad_ready`, `aes_data_ready`, `aes_data_valid`, `aes_tag_valid`) rather than hardcoded cycle delay counters, the wrappers natively absorb the 4-cycle latency difference between AES-128 and AES-256 without any race conditions or timing hazards.
3. **Variant-Specific Adaptations:**
   - `aes128_uart_wrapper.sv`: Wires 128-bit key (`reg_key[127:0]`) to `AES_GCM`.
   - `aes256_uart_wrapper.sv`: Wires full 256-bit key (`reg_key[255:0]`) to `AES_256_GCM`, ties `verify_checked` to `1'b0`, and observes `verify_done`.
