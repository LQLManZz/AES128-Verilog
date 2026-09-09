# AES-GCM Multi-Variant FPGA UART Integration Architecture

**Hardware Target:** PolarFire SoC Discovery Kit (`MPFS-DISCO-KIT` / `MPFS095T-1FCSG325E`)  
**Host Connection:** USB Type-C &rarr; FT4232HL Quad High-Speed USB-UART Bridge &rarr; FPGA Fabric Logic  
**Framework Root:** `uart_integration/`  

---

## 1. Multi-Variant System Architecture

The integration architecture decouples host UART communication into:
1. **A Shared Common Layer (`uart_integration/common/`):**
   - Transceivers (`uart_rx.sv`, `uart_tx.sv`).
   - Packet decoder and length validator (`packet_parser.sv`).
   - Response packet serializer (`packet_builder.sv`).
   - Protocol definitions and opcodes (`protocol_pkg.sv`).
2. **Variant-Specific Wrappers:**
   - **AES-128:** `uart_integration/aes128/aes128_uart_wrapper.sv` wrapping `RTL/AES_GCM.sv`.
   - **AES-256:** `uart_integration/aes256/aes256_uart_wrapper.sv` wrapping `RTL/AES_256_GCM.sv`.

```
                      +-------------------------------------------------------------------------------+
                      |                              POLARFIRE SOC FPGA FABRIC                        |
                      |                                                                               |
                      |  +---------------+                                     +-------------------+  |
                      |  |    UART RX    |                                     |      UART TX      |  |
                      |  | (uart_rx.sv)  |                                     |  (uart_tx.sv)     |  |
                      |  +-------+-------+                                     +---------^---------+  |
                      |          | [rx_data, rx_valid]                                   | [tx_data,  |
                      |          v                                                       |  tx_start] |
                      |  +---------------+                                     +---------+---------+  |
                      |  | PACKET PARSER |                                     |  PACKET BUILDER   |  |
                      |  | (parser.sv)   |                                     |  (builder.sv)     |  |
                      |  +-------+-------+                                     +---------^---------+  |
                      |          |                                                       |            |
+------------------+  |          | [Decoded CMD, Key (128/256), IV, AAD, PT]             | [Response  |
|  HOST PC PYTHON  |  |          |                                                       |  Packets]  |
|   APPLICATION    |  |          v                                                       |            |
|    (host.py)     |  |  +---------------------------------------------------------------+---------+  |
|  [--mode aes128  |  |  |             aes128_uart_wrapper.sv  OR  aes256_uart_wrapper.sv          |  |
|   --mode aes256] |  |  +---------------------------------+---------------------------------------+  |
|        ^         |  |                                    | Handshakes, Control & Streaming          |
|        |         |  |                                    v                                          |
|  [USB Virtual    |  |  +-------------------------------------------------------------------------+  |
|    COM Port]     |  |  |           TARGET HARDWARE ACCELERATOR (AES_GCM / AES_256_GCM)           |  |
|        |         |  |  |  +---------------------+   +--------------------+   +----------------+  |  |
|        v         |  |  |  |  CTR Datapath       |   | TagProcessing      |   | Control Unit   |  |  |
|    FT4232HL      |  |  |  |  (12 / 16 cycles)   |   | (GHASH & GF128Mul) |   | (CU FSM)       |  |  |
|  USB-to-UART     |  |  |  +---------------------+   +--------------------+   +----------------+  |  |
|      Bridge      |  |  +-------------------------------------------------------------------------+  |
+--------+---------+  +-------------------------------------------------------------------------------+
         |
 [Physical Pins]
```

---

## 2. Shared Common Infrastructure (`uart_integration/common/`)

### 2.1 `protocol_pkg.sv`
Declares standardized SystemVerilog package containing:
- Command opcodes (`CMD_LOAD_KEY = 0x01` through `CMD_START_ENCRYPT = 0x05`).
- Response opcodes (`RESP_ACK_KEY = 0x81`, `RESP_CIPHERTEXT = 0x90`, `RESP_AUTH_TAG = 0x91`).
- Common buffer sizes (`MAX_BUFFER_BLOCKS = 16`).

### 2.2 `uart_rx.sv` (Receiver)
- Parameterized clock and baud rate (`CLK_FREQ_HZ`, `BAUD_RATE`).
- 8N1 format (1 start bit, 8 data bits LSB first, 1 stop bit).
- 2-stage input synchronizer to eliminate metastability.
- Midpoint bit sampling at cycle `(CLKS_PER_BIT - 1) / 2`.

### 2.3 `uart_tx.sv` (Transmitter)
- Parameterized clock and baud rate.
- 8N1 format (1 start bit, 8 data bits LSB first, 1 stop bit).
- Inputs: `tx_data[7:0]`, `tx_start`. Outputs: `tx`, `tx_busy`.

### 2.4 `packet_parser.sv` (Unified Decoder)
- Deserializes `[CMD, LENGTH, PAYLOAD...]`.
- Validates lengths:
  - `CMD_LOAD_KEY` (0x01): Accepts either 16 bytes (AES-128) or 32 bytes (AES-256).
  - `CMD_LOAD_IV` (0x02): 12 bytes (96 bits).
  - `CMD_LOAD_AAD` (0x03) & `CMD_LOAD_PLAINTEXT` (0x04): Multiples of 16 bytes.
  - `CMD_START_ENCRYPT` (0x05): 0 bytes.
- Streams 128-bit big-endian blocks directly into wrapper buffer memories.

### 2.5 `packet_builder.sv` (Unified Builder)
- Formats response packets:
  - Header: `[RESP_CMD, LENGTH]`.
  - ACKs (`0x81`..`0x84`): Length 0.
  - `CIPHERTEXT` (`0x90`): $16 \times P$ bytes.
  - `AUTH_TAG` (`0x91`): 16 bytes (128 bits).
  - Errors (`0xE0`, `0xE1`): Diagnostic error opcode.
- Serializes bytes onto `uart_tx` handshaking with `tx_busy`.

---

## 3. Variant Wrappers Comparison & Handshake Mapping

| Feature | `aes128_uart_wrapper.sv` | `aes256_uart_wrapper.sv` |
|---|---|---|
| **Target Top Module** | `AES_GCM` (`RTL/AES_GCM.sv`) | `AES_256_GCM` (`RTL/AES_256_GCM.sv`) |
| **Key Input Port** | `cipher_key[127:0]` | `cipher_key[255:0]` |
| **Key Schedule** | 10 rounds (10 cycles) | 14 rounds (13 cycles) |
| **Cipher Pipeline** | 10 rounds (12 cycles) | 14 rounds (16 cycles) |
| **Verification Handshakes** | Unconnected in mode 0 | `verify_checked = 1'b0`, `verify_done` observed |
| **AAD Handshake** | `load_AAD`, `no_AAD`, `AAD_last` | Identical Handshake |
| **PT Handshake** | `load_data`, `data_in_last` | Identical Handshake |
| **CT & Tag Handshake** | `data_valid`, `tag_valid` | Identical Handshake |
| **Buffer Capacity** | 16 blocks (256 bytes) AAD/PT | 16 blocks (256 bytes) AAD/PT |

---

## 4. Clocking and Reset Architecture

- **Single Clock Domain:** Single synchronous clock (`clk`, 100 MHz nominal).
- **Zero Clock Crossing:** All modules share the exact same clock edge, eliminating FIFO synchronizers and metastability risks.
- **Master Reset:** Active-low asynchronous reset (`rst_n`).
- **Transaction Reset:** Internal `finish_reset = (~rst_n) | finish;` resets message states between successive encryptions while preserving expanded subkeys $H$.
