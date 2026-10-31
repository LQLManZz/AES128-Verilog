"""Software stand-in for the FPGA: same responses, byte for byte, as aes*_uart_wrapper.sv.

The ciphertext follows NIST SP 800-38D. The tag does not: RTL/GCM-GHASH multiplies in
the unreflected polynomial basis, so GHASH is rebuilt here instead of using AES.MODE_GCM.
"""

from typing import List, Tuple

from Crypto.Cipher import AES
from uart_protocol import (
    BLOCK_BYTES, CMD_ACKS, CMD_LOAD_AAD, CMD_LOAD_IV, CMD_LOAD_KEY, CMD_LOAD_PLAINTEXT,
    CMD_START_DECRYPT, CMD_START_ENCRYPT, RESP_AUTH_TAG, RESP_CIPHERTEXT,
)

from .packet_file import Packet

_REDUCTION = (1 << 128) | 0x87  # x^128 + x^7 + x^2 + x + 1


def _gf_multiply(a: int, b: int) -> int:
    product = 0
    for bit in range(128):
        if (b >> bit) & 1:
            product ^= a << bit
    for bit in range(254, 127, -1):
        if (product >> bit) & 1:
            product ^= _REDUCTION << (bit - 128)
    return product


def rtl_tag(key: bytes, iv: bytes, aad: bytes, ciphertext: bytes) -> bytes:
    cipher = AES.new(key, AES.MODE_ECB)
    h = int.from_bytes(cipher.encrypt(bytes(BLOCK_BYTES)), "big")
    ghash = 0
    for data in (aad, ciphertext):
        for i in range(0, len(data), BLOCK_BYTES):
            ghash = _gf_multiply(ghash ^ int.from_bytes(data[i:i + BLOCK_BYTES], "big"), h)
    length_block = (len(aad) * 8) << 64 | (len(ciphertext) * 8)
    ghash = _gf_multiply(ghash ^ length_block, h)
    mask = int.from_bytes(cipher.encrypt(iv + b"\x00\x00\x00\x01"), "big")
    return (ghash ^ mask).to_bytes(BLOCK_BYTES, "big")


def run_message(key: bytes, iv: bytes, aad: bytes, data: bytes, decrypt: bool = False) -> Tuple[bytes, bytes]:
    """Runs one GCM message and returns (output data, tag)."""
    output = AES.new(key, AES.MODE_CTR, nonce=iv, initial_value=2).encrypt(data)
    return output, rtl_tag(key, iv, aad, data if decrypt else output)


def simulate(packets: List[Packet]) -> List[Packet]:
    """Answers a host -> FPGA stream the way the UART wrapper does."""
    key = iv = aad = data = b""
    responses = []
    for cmd, payload in packets:
        if cmd in CMD_ACKS:
            responses.append((CMD_ACKS[cmd], b""))
        if cmd == CMD_LOAD_KEY:
            key = payload
        elif cmd == CMD_LOAD_IV:
            iv = payload
        elif cmd == CMD_LOAD_AAD:
            aad = payload
        elif cmd == CMD_LOAD_PLAINTEXT:
            data = payload
        elif cmd in (CMD_START_ENCRYPT, CMD_START_DECRYPT):
            output, tag = run_message(key, iv, aad, data, decrypt=cmd == CMD_START_DECRYPT)
            responses.append((RESP_CIPHERTEXT, output))
            responses.append((RESP_AUTH_TAG, tag))
            aad = b""
        else:
            raise ValueError(f"Unexpected opcode 0x{cmd:02X} in TX stream")
    return responses
