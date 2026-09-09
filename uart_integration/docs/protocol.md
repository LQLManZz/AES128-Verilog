# AES-GCM UART Binary Communication Protocol Specification

**Document Version:** 1.0  
**Target Hardware:** PolarFire SoC Discovery Kit (MPFS095T-1FCSG325E)  
**Interface:** USB Type-C &rarr; FT4232HL USB-UART &rarr; FPGA Fabric UART  

---

## 1. Physical Layer Configuration

The UART physical layer connects the host PC application via the FT4232HL USB-to-UART bridge directly to FPGA fabric logic pins.

| Parameter | Setting | Description |
|---|---|---|
| **Baud Rate** | Configurable (Default: `115,200` bps) | Configurable via RTL parameter `BAUD_RATE` |
| **Data Bits** | `8` | 1 byte per frame |
| **Parity** | `None` (N) | No parity bit |
| **Stop Bits** | `1` | 1 stop bit |
| **Flow Control** | `None` | Software packet handshaking via ACK |
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
| `0x03` | **`LOAD_AAD`** | $16 \times M$ Bytes ($M \ge 1$) | Loads Additional Authenticated Data in multiples of 16-byte blocks. |
| `0x04` | **`LOAD_PLAINTEXT`**| $16 \times P$ Bytes ($P \ge 1$) | Loads Plaintext data in multiples of 16-byte blocks (up to 256 bytes). |
| `0x05` | **`START_ENCRYPT`** | 0 Bytes | Triggers hardware AES-GCM encryption accelerator execution. |

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
- **Payload:** Multiples of 16 bytes (16 to 256 bytes per burst).
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

---

## 4. Response Set (FPGA Accelerator &rarr; Host PC)

| Opcode | Name | Payload Length | Description |
|---|---|---|---|
| `0x81` | **`ACK_KEY`** | 0 Bytes | Confirms successful receipt and latching of Cipher Key. |
| `0x82` | **`ACK_IV`** | 0 Bytes | Confirms successful receipt and latching of IV. |
| `0x83` | **`ACK_AAD`** | 0 Bytes | Confirms successful receipt and buffering of AAD. |
| `0x84` | **`ACK_PLAINTEXT`** | 0 Bytes | Confirms successful receipt and buffering of Plaintext. |
| `0x90` | **`CIPHERTEXT`** | $16 \times P$ Bytes | Encrypted ciphertext corresponding to input plaintext blocks. |
| `0x91` | **`AUTH_TAG`** | 16 Bytes (128 bits) | Final 128-bit NIST SP 800-38D Authentication Tag. |
| `0xE0` | **`ERR_UNKNOWN_CMD`**| 1 Byte | Error: Received opcode is unassigned. Payload contains bad opcode. |
| `0xE1` | **`ERR_LEN_MISMATCH`**| 2 Bytes | Error: Packet length does not match command requirement. |

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
- `0x06` - `LOAD_TAG_REF` (For future Decryption/Authentication mode)
- `0x07` - `START_DECRYPT` (For future Decryption verification)
- `0x92` - `VERIFY_RESULT` (Status byte: `0x01` = PASS, `0x00` = FAIL)
- `0xA0..0xAF` - Diagnostic and performance counter readout.
