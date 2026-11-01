"""Software stand-in for the FPGA: same responses, byte for byte, as aes_gcm_engine.sv.

Ciphertext and tag both follow NIST SP 800-38D, so AES.MODE_GCM computes them directly.
"""

import hmac
from typing import List, Tuple

from Crypto.Cipher import AES
from .protocol import (
    CMD_ACKS, CMD_LOAD_AAD, CMD_LOAD_IV, CMD_LOAD_KEY, CMD_LOAD_PLAINTEXT, CMD_LOAD_TAG_REF,
    CMD_START_DECRYPT, CMD_START_ENCRYPT, RESP_AUTH_TAG, RESP_CIPHERTEXT, RESP_ERR_LEN,
    RESP_VERIFY_RESULT, VERIFY_FAIL, VERIFY_PASS,
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
    """Answers a host -> FPGA stream the way aes_gcm_engine does."""
    key = iv = aad = data = tag_ref = b""
    responses = []
    for cmd, payload in packets:
        if cmd in CMD_ACKS:
            responses.append((CMD_ACKS[cmd], b""))
        if cmd == CMD_LOAD_KEY:
            key = payload
            aad = data = tag_ref = b""
        elif cmd == CMD_LOAD_IV:
            iv = payload
            aad = data = tag_ref = b""
        elif cmd == CMD_LOAD_AAD:
            aad = payload
        elif cmd == CMD_LOAD_PLAINTEXT:
            data = payload
        elif cmd == CMD_LOAD_TAG_REF:
            tag_ref = payload
        elif cmd in (CMD_START_ENCRYPT, CMD_START_DECRYPT):
            decrypt = cmd == CMD_START_DECRYPT
            if not data or (decrypt and not tag_ref):
                responses.append((RESP_ERR_LEN, bytes([cmd])))
                continue
            output, tag = run_message(key, iv, aad, data, decrypt)
            passed = decrypt and hmac.compare_digest(tag, tag_ref)
            if passed or not decrypt:
                responses.append((RESP_CIPHERTEXT, output))
            responses.append((RESP_AUTH_TAG, tag))
            if decrypt:
                responses.append((RESP_VERIFY_RESULT, VERIFY_PASS if passed else VERIFY_FAIL))
            aad = data = tag_ref = b""
        else:
            raise ValueError(f"Unexpected opcode 0x{cmd:02X} in TX stream")
    return responses
