"""Software stand-in for the FPGA: same responses, byte for byte, as aes*_uart_wrapper.sv.

Ciphertext and tag both follow NIST SP 800-38D, so AES.MODE_GCM computes them directly.
"""

from typing import List, Tuple

from Crypto.Cipher import AES
from uart_protocol import (
    CMD_ACKS, CMD_LOAD_AAD, CMD_LOAD_IV, CMD_LOAD_KEY, CMD_LOAD_PLAINTEXT,
    CMD_START_DECRYPT, CMD_START_ENCRYPT, RESP_AUTH_TAG, RESP_CIPHERTEXT,
)

from .packet_file import Packet


def run_message(key: bytes, iv: bytes, aad: bytes, data: bytes, decrypt: bool = False) -> Tuple[bytes, bytes]:
    """Runs one GCM message and returns (output data, tag)."""
    cipher = AES.new(key, AES.MODE_GCM, nonce=iv)
    cipher.update(aad)
    if decrypt:
        # PyCryptodome refuses digest() after decrypt(), so re-encrypt to feed GHASH the ciphertext.
        output = AES.new(key, AES.MODE_CTR, nonce=iv, initial_value=2).decrypt(data)
        cipher.encrypt(output)
    else:
        output = cipher.encrypt(data)
    return output, cipher.digest()


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
