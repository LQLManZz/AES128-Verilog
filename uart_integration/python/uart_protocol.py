#!/usr/bin/env python3
"""
===============================================================================
 AES-GCM Hardware Accelerator - UART Packet Protocol
===============================================================================
 Single source of the packet protocol for both host demos:
   - uart_integration/python/host.py (direct hex over UART)
   - image_process/ (image processing over UART)
 Keep it free of third-party imports so either side can load it on its own.
 Specification: uart_integration/docs/protocol.md
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
CMD_START_DECRYPT  = 0x07  # Length: 0 (Decryption mode)

RESP_ACK_KEY       = 0x81
RESP_ACK_IV        = 0x82
RESP_ACK_AAD       = 0x83
RESP_ACK_PLAINTEXT = 0x84
RESP_CIPHERTEXT    = 0x90
RESP_AUTH_TAG      = 0x91
RESP_ERR_UNKNOWN   = 0xE0
RESP_ERR_LEN       = 0xE1

CMD_NAMES = {
    CMD_LOAD_KEY:       "LOAD_KEY",
    CMD_LOAD_IV:        "LOAD_IV",
    CMD_LOAD_AAD:       "LOAD_AAD",
    CMD_LOAD_PLAINTEXT: "LOAD_PLAINTEXT",
    CMD_START_ENCRYPT:  "START_ENCRYPT",
    CMD_START_DECRYPT:  "START_DECRYPT"
}

RESP_NAMES = {
    RESP_ACK_KEY:       "ACK_KEY",
    RESP_ACK_IV:        "ACK_IV",
    RESP_ACK_AAD:       "ACK_AAD",
    RESP_ACK_PLAINTEXT: "ACK_PLAINTEXT",
    RESP_CIPHERTEXT:    "CIPHERTEXT",
    RESP_AUTH_TAG:      "AUTH_TAG",
    RESP_ERR_UNKNOWN:   "ERR_UNKNOWN_CMD",
    RESP_ERR_LEN:       "ERR_LEN_MISMATCH"
}

CMD_ACKS = {
    CMD_LOAD_KEY:       RESP_ACK_KEY,
    CMD_LOAD_IV:        RESP_ACK_IV,
    CMD_LOAD_AAD:       RESP_ACK_AAD,
    CMD_LOAD_PLAINTEXT: RESP_ACK_PLAINTEXT
}

# =============================================================================
# Protocol Limits
# =============================================================================
BLOCK_BYTES     = 16
MAX_DATA_BLOCKS = 15   # LENGTH is 8-bit and cnt_pt_blocks is 4-bit, so 16 blocks wrap to 0
MAX_DATA_BYTES  = MAX_DATA_BLOCKS * BLOCK_BYTES


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
