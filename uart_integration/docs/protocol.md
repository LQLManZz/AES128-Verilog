# AES-GCM Binary Communication Protocol Specification (UART and SPI)

**Document Version:** 2.0  
**Target Hardware:** PolarFire SoC Discovery Kit (MPFS095T-1FCSG325E)  
**Interface:** one bitstream per link: UART on mikroBUS J6, or SPI on mikroBUS J5  

---

## 1. Physical Layer Configuration

The packets below are the same on both links. See section 7 for the SPI framing. The UART bitstream uses the settings in this table on pins E14/E15. The 12 Mbaud bitstreams (`aes256_uart_12m_top`, `aes128_uart_12m_top`) use the same settings on W21/Y21, FT4232HL channel D through the USB-C port.

| Parameter | Setting | Description |
|---|---|---|
| **Baud Rate** | Configurable (Default: `2,000,000` bps) | RTL parameter `BAUD_RATE`; use a value that divides 50 MHz exactly, or 120 MHz in `aes_uart_12m_top` (default `12,000,000` bps) |
| **Data Bits** | `8` | 1 byte per frame |
| **Parity** | `None` (N) | No parity bit |
| **Stop Bits** | `1` | 1 stop bit |
| **Flow Control** | `None` | The host keeps at most 32 messages in flight; the RX FIFO absorbs them |
| **Bit Order** | `LSB First` | Standard UART transmission order |
| **Byte Endianness** | `Big-Endian (MSB First)` | High byte transmitted first for cryptographic vectors |

---

## 2. Frame & Packet Structure

All communications follow a strictly framed binary packet structure. There are no variable-length delimiters; packet boundaries are governed by the `LENGTH` byte.

### 2.1 Packet Format

```
+---------------+----------------+--------------------------------------+
|  Byte 0 (CMD) | Byte 1 (LENGTH)| Byte 2 .. N+1 (PAYLOAD [0..N-1])     |
+---------------+----------------+--------------------------------------+
|  Command ID   | Payload Length | Actual data payload (0 to 255 bytes) |
|    (8-bit)    |    (8-bit)     |                                      |
+---------------+----------------+--------------------------------------+
```

- **`CMD` (1 Byte):** Identifies packet command type or response code.
- **`LENGTH` (1 Byte):** Unsigned 8-bit integer specifying number of bytes in `PAYLOAD` ($0 \le N \le 255$).
- **`PAYLOAD` ($N$ Bytes):** Command parameters or response data. Omitted if $N = 0$.

---

## 3. Command Set (Host PC &rarr; FPGA Accelerator)

| Opcode | Name | Payload Length | Description |
|---|---|---|---|
| `0x01` | **`LOAD_KEY`** | 16 or 32 Bytes | Loads AES Cipher Key (16 bytes for AES-128, 32 bytes for AES-256). |
| `0x02` | **`LOAD_IV`** | 12 Bytes (96 bits) | Loads NIST SP 800-38D standard 96-bit Initialization Vector. |
| `0x03` | **`LOAD_AAD`** | $16 \times M$ Bytes ($1 \le M \le 15$) | Loads Additional Authenticated Data in multiples of 16-byte blocks (up to 240 bytes). |
| `0x04` | **`LOAD_PLAINTEXT`**| $16 \times P$ Bytes ($1 \le P \le 15$) | Loads Plaintext data in multiples of 16-byte blocks (up to 240 bytes). |
| `0x05` | **`START_ENCRYPT`** | 0 Bytes | Triggers hardware AES-GCM encryption accelerator execution. |
| `0x06` | **`LOAD_TAG_REF`** | 16 Bytes | Loads the expected tag. Required before `START_DECRYPT`, cleared after each message. |
| `0x07` | **`START_DECRYPT`** | 0 Bytes | Triggers hardware AES-GCM decryption. The data loaded by `LOAD_PLAINTEXT` is treated as ciphertext. |

> **Message size limit:** each `START_*` runs one independent GCM message of at most 15 blocks (240 bytes), although the wrapper buffers hold 16. `LENGTH` is 8-bit and cannot encode 256, and the 4-bit `cnt_pt_blocks` counter wraps to 0 at 16 blocks. Longer data must be split into several messages, each with its own IV and tag. `uart_protocol.py` exposes this limit as `MAX_DATA_BYTES`.

### 3.1 Command Details

#### `0x01` - `LOAD_KEY`
- **Format:** `[0x01] [0x10 or 0x20] [Key Bytes ...]`
- **Payload:** 16 bytes (AES-128: 128-bit key) or 32 bytes (AES-256: 256-bit key).
- **Behavior:** Hardware latches key bytes into key register.
- **Expected Response:** `ACK_KEY` (`0x81`).

#### `0x02` - `LOAD_IV`
- **Format:** `[0x02] [0x0C] [IV Bytes ...]`
- **Payload:** Exactly 12 bytes (`96` bits).
- **Behavior:** Hardware latches IV into the 96-bit IV register for counter initialization ($J_0$).
- **Expected Response:** `ACK_IV` (`0x82`).

#### `0x03` - `LOAD_AAD`
- **Format:** `[0x03] [LENGTH] [AAD Bytes ...]`
- **Payload:** Multiples of 16 bytes (e.g., 16, 32, 48 bytes).
- **Behavior:** Hardware buffers AAD blocks. If no AAD is needed for a session, the host simply omits sending `LOAD_AAD`.
- **Expected Response:** `ACK_AAD` (`0x83`).

#### `0x04` - `LOAD_PLAINTEXT`
- **Format:** `[0x04] [LENGTH] [Plaintext Bytes ...]`
- **Payload:** Multiples of 16 bytes (16 to 240 bytes per burst).
- **Behavior:** Hardware buffers Plaintext blocks into input buffer.
- **Expected Response:** `ACK_PLAINTEXT` (`0x84`).

#### `0x05` - `START_ENCRYPT`
- **Format:** `[0x05] [0x00]`
- **Payload:** 0 bytes.
- **Behavior:** Initiates hardware AES-GCM state machine:
  1. Expands key and calculates hash subkey $H = AES_K(0^{128})$.
  2. Processes AAD blocks through GHASH (or triggers `no_AAD`).
  3. Encrypts Plaintext blocks in CTR mode and accumulates Ciphertext in GHASH.
  4. Encrypts $J_0$ to generate mask $E = AES_K(J_0)$.
  5. Computes authentication tag $T = \text{GHASH} \oplus E$.
- **Expected Responses:**
  1. `CIPHERTEXT` (`0x90`) with encrypted data payload.
  2. `AUTH_TAG` (`0x91`) with 16-byte authentication tag payload.

#### `0x07` - `START_DECRYPT`
- **Format:** `[0x07] [0x00]`
- **Payload:** 0 bytes.
- **Behavior:** Runs the same sequence on the loaded ciphertext and verifies the tag inside the IP against `LOAD_TAG_REF`. Without `LOAD_TAG_REF` it answers `ERR_LEN_MISMATCH` with `0x07`.
- **Expected Responses when the tag matches:**
  1. `CIPHERTEXT` (`0x90`) carrying the recovered plaintext.
  2. `AUTH_TAG` (`0x91`) with the computed 16-byte tag.
  3. `VERIFY_RESULT` (`0x92`) with `0x01`.
- **Expected Responses when it does not:** the plaintext is withheld.
  1. `AUTH_TAG` (`0x91`) with the computed 16-byte tag.
  2. `VERIFY_RESULT` (`0x92`) with `0x00`.

---

## 4. Response Set (FPGA Accelerator &rarr; Host PC)

| Opcode | Name | Payload Length | Description |
|---|---|---|---|
| `0x81` | **`ACK_KEY`** | 0 Bytes | Confirms successful receipt and latching of Cipher Key. |
| `0x82` | **`ACK_IV`** | 0 Bytes | Confirms successful receipt and latching of IV. |
| `0x83` | **`ACK_AAD`** | 0 Bytes | Confirms successful receipt and buffering of AAD. |
| `0x84` | **`ACK_PLAINTEXT`** | 0 Bytes | Confirms successful receipt and buffering of Plaintext. |
| `0x85` | **`ACK_TAG_REF`** | 0 Bytes | Expected tag loaded. |
| `0x90` | **`CIPHERTEXT`** | $16 \times P$ Bytes | Encrypted ciphertext corresponding to input plaintext blocks. |
| `0x91` | **`AUTH_TAG`** | 16 Bytes (128 bits) | Final 128-bit NIST SP 800-38D Authentication Tag. |
| `0x92` | **`VERIFY_RESULT`** | 1 Byte | Ends a decryption: `0x01` tag matched, `0x00` tag did not match and no plaintext was sent. |
| `0xE0` | **`ERR_UNKNOWN_CMD`**| 1 Byte | Error: Received opcode is unassigned. Payload contains bad opcode. |
| `0xE1` | **`ERR_LEN_MISMATCH`**| 1 Byte | Error: Packet length does not match command requirement. Payload contains the rejected opcode. |
| `0xE2` | **`ERR_TIMEOUT`** | 1 Byte | The packet with this opcode stopped arriving for 10 ms and was dropped. |

---

## 5. Transaction Sequence Diagram

```
Host PC Application                              FPGA aes_uart_wrapper
       |                                                    |
       |--------------- 0x01 LOAD_KEY (16B) --------------->|
       |<-------------- 0x81 ACK_KEY (0B) ------------------|
       |                                                    |
       |--------------- 0x02 LOAD_IV (12B) ---------------->|
       |<-------------- 0x82 ACK_IV (0B) -------------------|
       |                                                    |
       |--- [Optional] 0x03 LOAD_AAD (16*M B) ------------->|
       |<-- [Optional] 0x83 ACK_AAD (0B) -------------------|
       |                                                    |
       |------------ 0x04 LOAD_PLAINTEXT (16*P B) ---------->|
       |<----------- 0x84 ACK_PLAINTEXT (0B) ---------------|
       |                                                    |
       |------------- 0x05 START_ENCRYPT (0B) ------------->|
       |                                                    | [AES Core Processes:
       |                                                    |  H Calc -> CTR -> GHASH -> Tag]
       |                                                    |
       |<------------ 0x90 CIPHERTEXT (16*P B) -------------|
       |<------------ 0x91 AUTH_TAG (16B) ------------------|
       |                                                    |
```

---

## 6. Extensibility

The protocol opcodes are allocated with wide ranges reserved for future expansion:
- `0xA0..0xAF` - Diagnostic and performance counter readout.

---

## 7. SPI Framing

SPI is mode 0, MSB first. One frame is one `spi_cs_n` low period, and its first byte selects what the frame does:

| First MOSI byte | Name | Effect |
|---|---|---|
| `0xA5` | `DATA` | The following MOSI bytes are packet bytes for the engine |
| `0x5A` | `READ` | The following MOSI bytes are ignored |
| `0xC3` | `CLEAR` | When `spi_cs_n` rises: resets the engine, both FIFOs and the status flags |

The slave changes MISO on the rising SCLK edge, the same edge the master samples, so the master has a whole period for the round trip. The master must sample on that edge, with no added input delay.

The first MISO byte is the status byte `{4'hA, 1'b0, bad_op, tx_overflow, rx_overflow}`. Its high nibble stays `0xA`, so a stuck or absent slave shows up immediately. The flags are sticky until `CLEAR`.

The following MISO bytes are response packets from the TX FIFO, in every frame type, and `0x00` when it is empty. No response opcode is `0x00`, so the host skips zeros where an opcode is due and never inside a payload.

Each message answers about 6 bytes more than it sends and replies trail the data by about one message, so a `DATA` frame carries at most 32 messages and `READ` frames collect the rest.
