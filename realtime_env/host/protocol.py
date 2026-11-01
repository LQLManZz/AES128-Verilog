#!/usr/bin/env python3
"""
===============================================================================
 AES-GCM Hardware Accelerator - UART Packet Protocol
===============================================================================
 Single source of the packet protocol for everything under host/.
 Keep it free of third-party imports.
 Specification: realtime_env/docs/protocol.md
===============================================================================
"""

from typing import List, Tuple

# =============================================================================
# Protocol Command & Response Opcodes
# =============================================================================
CMD_LOAD_KEY       = 0x01  # Length: 16 (AES-128) or 32 (AES-256)
CMD_LOAD_IV        = 0x02  # Length: 12 (96 bits)
CMD_LOAD_AAD       = 0x03  # Length: Multiples of 16 (16..240 bytes)
CMD_LOAD_PLAINTEXT = 0x04  # Length: Multiples of 16 (16..240 bytes)
CMD_START_ENCRYPT  = 0x05  # Length: 0 (Encryption mode)
CMD_LOAD_TAG_REF   = 0x06  # Length: 16 (expected tag, required before START_DECRYPT)
CMD_START_DECRYPT  = 0x07  # Length: 0 (Decryption mode)

RESP_ACK_KEY       = 0x81
RESP_ACK_IV        = 0x82
RESP_ACK_AAD       = 0x83
RESP_ACK_PLAINTEXT = 0x84
RESP_ACK_TAG_REF   = 0x85
RESP_CIPHERTEXT    = 0x90
RESP_AUTH_TAG      = 0x91
RESP_VERIFY_RESULT = 0x92  # Length: 1, see VERIFY_PASS / VERIFY_FAIL
RESP_ERR_UNKNOWN   = 0xE0
RESP_ERR_LEN       = 0xE1
RESP_ERR_TIMEOUT   = 0xE2  # Length: 1, the packet's opcode: it stopped arriving halfway
RESP_BRIDGE_ERR    = 0xEF  # Length: 1, the SPI status byte. Sent by esp32_bridge, never by the IP

VERIFY_PASS = b"\x01"
VERIFY_FAIL = b"\x00"  # The IP withholds the plaintext, so no RESP_CIPHERTEXT comes first

CMD_NAMES = {
    CMD_LOAD_KEY:       "LOAD_KEY",
    CMD_LOAD_IV:        "LOAD_IV",
    CMD_LOAD_AAD:       "LOAD_AAD",
    CMD_LOAD_PLAINTEXT: "LOAD_PLAINTEXT",
    CMD_START_ENCRYPT:  "START_ENCRYPT",
    CMD_LOAD_TAG_REF:   "LOAD_TAG_REF",
    CMD_START_DECRYPT:  "START_DECRYPT"
}

RESP_NAMES = {
    RESP_BRIDGE_ERR: "BRIDGE_SPI_STATUS",
    RESP_ACK_KEY:       "ACK_KEY",
    RESP_ACK_IV:        "ACK_IV",
    RESP_ACK_AAD:       "ACK_AAD",
    RESP_ACK_PLAINTEXT: "ACK_PLAINTEXT",
    RESP_ACK_TAG_REF:   "ACK_TAG_REF",
    RESP_CIPHERTEXT:    "CIPHERTEXT",
    RESP_AUTH_TAG:      "AUTH_TAG",
    RESP_VERIFY_RESULT: "VERIFY_RESULT",
    RESP_ERR_UNKNOWN:   "ERR_UNKNOWN_CMD",
    RESP_ERR_LEN:       "ERR_LEN_MISMATCH",
    RESP_ERR_TIMEOUT:   "ERR_TIMEOUT"
}

CMD_ACKS = {
    CMD_LOAD_KEY:       RESP_ACK_KEY,
    CMD_LOAD_IV:        RESP_ACK_IV,
    CMD_LOAD_AAD:       RESP_ACK_AAD,
    CMD_LOAD_PLAINTEXT: RESP_ACK_PLAINTEXT,
    CMD_LOAD_TAG_REF:   RESP_ACK_TAG_REF
}

# =============================================================================
# Protocol Limits
# =============================================================================
BLOCK_BYTES     = 16
MAX_DATA_BLOCKS = 15   # LENGTH is 8-bit and cnt_pt_blocks is 4-bit, so 16 blocks wrap to 0
MAX_DATA_BYTES  = MAX_DATA_BLOCKS * BLOCK_BYTES

DEFAULT_BAUD_RATE = 2_000_000  # Divides 50 MHz exactly (see BAUD_RATE in the UART wrappers)
BURST_MESSAGES    = 32         # Messages in flight: keeps both FIFOs of aes_gcm_engine from filling


# =============================================================================
# Packet Framing: [CMD] [LENGTH] [PAYLOAD ...]
# =============================================================================
def build_packet(cmd: int, payload: bytes = b"") -> bytes:
    length = len(payload)
    if length > 255:
        raise ValueError(f"Payload length ({length} B) exceeds maximum of 255 bytes")
    return bytes([cmd, length]) + payload


def parse_packets(stream: bytes) -> List[Tuple[int, bytes]]:
    """Splits a raw byte stream into (cmd, payload) pairs."""
    packets = []
    pos = 0
    while pos < len(stream):
        if pos + 2 > len(stream):
            raise ValueError(f"Truncated packet header at byte {pos}")
        cmd, length = stream[pos], stream[pos + 1]
        payload = stream[pos + 2:pos + 2 + length]
        if len(payload) < length:
            raise ValueError(f"Truncated payload at byte {pos}: expected {length} bytes, got {len(payload)}")
        packets.append((cmd, payload))
        pos += 2 + length
    return packets
