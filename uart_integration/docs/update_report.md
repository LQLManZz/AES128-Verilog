# RTL Change Analysis & UART Integration Impact Report (Incremental Update)

**Date:** 2026-09-09  
**Target Device:** Microchip PolarFire SoC Discovery Kit (`MPFS095T-1FCSG325E`)  
**Previous Baseline:** AES-128-GCM (`RTL/AES_GCM.sv`, 10-round AES, 12-cycle latency, 128-bit key)  
**Current RTL Revision Detected:** Commits `03480cb` .. `6874c9a` (AES-256-GCM Integration)  

---

## 1. Summary of RTL Changes

### 1.1 New Modules Added
1. **[`RTL/AES_256_GCM.sv`](file:///C:/Users/long5/Documents/TKVM/__ProjectHOC__/AES_Verilog/RTL/AES_256_GCM.sv)** (Commit `03480cb`):
   - Created to integrate AES-256 with the existing `TagProcessing` and `CU` modules.
   - Instantiates `AES_256_CTR` instead of `AES_CTR`.
   - Adds ports `input logic verify_checked` and `output logic verify_done`.
   - Connects `.verify_checked(verify_checked)`, `.verify_done(verify_done)`, and `.CTR_counter_overflow(CTR_counter_overflow)` to the Control Unit `CU cu`.
2. **[`RTL/AES_256_CTR/AES_256_CTR.sv`](file:///C:/Users/long5/Documents/TKVM/__ProjectHOC__/AES_Verilog/RTL/AES_256_CTR/AES_256_CTR.sv)** (Commit `06a733d`):
   - Integrates 256-bit key schedule [`KeyExpansion_256`](file:///C:/Users/long5/Documents/TKVM/__ProjectHOC__/AES_Verilog/RTL/AES_256_CTR/Key_Expansion_256/KeyExpansion_256.sv) (`round_key[0:14]`) with the new [`AES_256_encryption`](file:///C:/Users/long5/Documents/TKVM/__ProjectHOC__/AES_Verilog/RTL/AES_256_CTR/AES_256_encryption.sv) 14-round cipher engine.
   - Port `cipher_key` is 256 bits: `input logic [255:0] cipher_key`.
3. **[`RTL/AES_256_CTR/AES_256_encryption.sv`](file:///C:/Users/long5/Documents/TKVM/__ProjectHOC__/AES_Verilog/RTL/AES_256_CTR/AES_256_encryption.sv)** (Commit `40b0114`):
   - Implements full 14-round AES-256 cipher pipeline (`first_round`, `R1` through `R13`, `last_round`, `reg11`).
   - Pipeline latency: 16 clock cycles (previously 12 clock cycles in AES-128).

### 1.2 Renamed & Reorganized Modules
- `RTL/Key_Expansion_256/` files were moved into `RTL/AES_256_CTR/Key_Expansion_256/`:
  - `KeyExpansion_256.sv` $\rightarrow$ `RTL/AES_256_CTR/Key_Expansion_256/KeyExpansion_256.sv`
  - `Counter_256.sv` $\rightarrow$ `RTL/AES_256_CTR/Key_Expansion_256/Counter_256.sv`
  - `GFunction_256.sv` $\rightarrow$ `RTL/AES_256_CTR/Key_Expansion_256/GFunction_256/GFunction_256.sv`
  - `AddRcon_256.sv` $\rightarrow$ `RTL/AES_256_CTR/Key_Expansion_256/GFunction_256/AddRcon_256.sv`

### 1.3 Latency & Timing Changes
- **Key Expansion Latency:** `Counter_256.sv` counts `round_index` from 0 to 12 (13 cycles) to compute 15 round keys (`round_key[0:14]`), asserting `expansion_finish` on cycle 13. (Previously 10 cycles).
- **Encryption Pipeline Latency:** Increased from 12 clock cycles to 16 clock cycles (+4 cycles).

---

## 2. Impact Analysis on UART Integration Layer

| Component | Status | Impact & Compatibility Assessment |
|---|---|---|
| **`uart_rx.sv`** | **No modification required** | Physical layer deserializer; baud timing and 8N1 framing remain completely unaffected. |
| **`uart_tx.sv`** | **No modification required** | Physical layer serializer; remains completely unaffected. |
| **`packet_parser.sv`** | **No modification required** | Already designed with forward compatibility: `CMD 0x01` (`LOAD_KEY`) accepts both 16-byte (128-bit) and 32-byte (256-bit) payloads. `key_out` is already a full 256-bit register (`[255:0]`). |
| **`packet_builder.sv`** | **No modification required** | Packet formatting for ACKs, multi-block ciphertext, tag, and errors remains 100% compliant. |
| **`aes_uart_wrapper.sv`** | **Modification required** | 1. Must connect all 256 bits of `reg_key[255:0]` to the top module.<br>2. Must drive the new port `verify_checked` (tie to `1'b0` for encryption) and observe `verify_done`.<br>3. Must adapt to the resolved top-level module name (`AES_256_GCM` or updated `AES_GCM`). |
| **`tb_aes_uart_wrapper.sv`**| **Modification required** | Add official **NIST SP 800-38D AES-256-GCM** test vectors (Appendix B Test Case 15 / 16 / 17) to validate 256-bit key encryption. |
| **`host.py`** | **No modification required** | Already accepts 32-byte hex keys (`--key`) and sends 256-bit `LOAD_KEY` packets. Add AES-256 test cases to `--test-nist`. |
| **`architecture.md`** | **Documentation update** | Document the 14-round AES-256 pipeline, 16-cycle latency, and updated module hierarchy. |

---

## 3. Discovered RTL Defects & Risk Assessment

### 3.1 Defect 1: Port Width Discrepancy in [`RTL/AES_256_GCM.sv`](file:///C:/Users/long5/Documents/TKVM/__ProjectHOC__/AES_Verilog/RTL/AES_256_GCM.sv)
- **Problem:** In [`RTL/AES_256_GCM.sv`](file:///C:/Users/long5/Documents/TKVM/__ProjectHOC__/AES_Verilog/RTL/AES_256_GCM.sv) line 8:
  ```systemverilog
  input logic [127:0] cipher_key, tag_ref,
  ```
  However, on line 31-32, it connects this port directly to `AES_256_CTR`:
  ```systemverilog
  AES_256_CTR AES (..., .cipher_key(cipher_key), ...);
  ```
  In [`RTL/AES_256_CTR/AES_256_CTR.sv`](file:///C:/Users/long5/Documents/TKVM/__ProjectHOC__/AES_Verilog/RTL/AES_256_CTR/AES_256_CTR.sv) line 5:
  ```systemverilog
  input logic [255:0] cipher_key,
  ```
  Because `cipher_key` in `AES_256_GCM.sv` is declared as only 128-bit wide (`[127:0]`), the upper 128 bits of the key (`cipher_key[255:128]`) will be zero-extended! In `KeyExpansion_256`:
  `round_key[0] <= cipher_key[255:128];`
  This causes `round_key[0]` to become `128'h0` instead of the upper half of the 256-bit key!
- **Action Required:** Fix line 8 of `RTL/AES_256_GCM.sv` to declare `input logic [255:0] cipher_key;` (Requesting user approval).

### 3.2 Defect 2: Module Name Collision (`AES_GCM`)
- **Problem:** Both [`RTL/AES_GCM.sv`](file:///C:/Users/long5/Documents/TKVM/__ProjectHOC__/AES_Verilog/RTL/AES_GCM.sv) (line 1) and [`RTL/AES_256_GCM.sv`](file:///C:/Users/long5/Documents/TKVM/__ProjectHOC__/AES_Verilog/RTL/AES_256_GCM.sv) (line 1) define `module AES_GCM(`.
  Compiling both files in Libero SoC or any SystemVerilog simulator causes a fatal error: `Module 'AES_GCM' already declared`.
- **Action Required:** Rename module in [`RTL/AES_256_GCM.sv`](file:///C:/Users/long5/Documents/TKVM/__ProjectHOC__/AES_Verilog/RTL/AES_256_GCM.sv) to `module AES_256_GCM(` (Requesting user approval).

---

## 4. Required Modifications Summary (Awaiting User Approval)

1. **RTL Approval Request:**
   - Authorize renaming `module AES_GCM(` in [`RTL/AES_256_GCM.sv`](file:///C:/Users/long5/Documents/TKVM/__ProjectHOC__/AES_Verilog/RTL/AES_256_GCM.sv) to `module AES_256_GCM(`.
   - Authorize updating `cipher_key` in [`RTL/AES_256_GCM.sv`](file:///C:/Users/long5/Documents/TKVM/__ProjectHOC__/AES_Verilog/RTL/AES_256_GCM.sv) to `input logic [255:0] cipher_key`.
2. **UART Wrapper Update (`aes_uart_wrapper.sv`):**
   - Create backup in `uart_integration/backups/aes_uart_wrapper_previous_revision.sv`.
   - Instantiate `AES_256_GCM`.
   - Connect full 256-bit `reg_key` to `.cipher_key(reg_key)`.
   - Connect `.verify_checked(1'b0)` and `.verify_done()`.
3. **Testbench Update (`tb_aes_uart_wrapper.sv`):**
   - Create backup in `uart_integration/backups/tb_aes_uart_wrapper_previous_revision.sv`.
   - Update verification tests with NIST SP 800-38D Appendix B Test Case 16 (AES-256-GCM official test vector).
4. **Documentation & Versioning Update:**
   - Append update entry in `uart_integration/docs/update_log.md`.
   - Update `architecture.md` and `integration_guide.md`.
