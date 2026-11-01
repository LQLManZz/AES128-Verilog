"""Software stand-in for the FPGA: same responses, byte for byte, as aes_gcm_engine.sv.

Ciphertext and tag both follow NIST SP 800-38D, so AES.MODE_GCM computes them directly.
"""

import hmac
from typing import List, Optional, Tuple

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


def open_message(key: bytes, iv: bytes, aad: bytes, cipher_text: bytes, tag: bytes) -> Optional[bytes]:
    """Decrypts and verifies in one pass, for speed. Returns None if the tag does not check out."""
    cipher = AES.new(key, AES.MODE_GCM, nonce=iv)
    cipher.update(aad)
    try:
        return cipher.decrypt_and_verify(cipher_text, tag)
    except ValueError:
        return None


class Engine:
    """Keeps the loaded key and message between packets, as the IP does between bursts."""

    def __init__(self):
        self.key = self.iv = self.aad = self.data = self.tag_ref = b""

    def _clear_message(self) -> None:
        self.aad = self.data = self.tag_ref = b""

    def answer(self, cmd: int, payload: bytes) -> List[Packet]:
        """Returns the responses to one packet."""
        responses = [(CMD_ACKS[cmd], b"")] if cmd in CMD_ACKS else []
        if cmd == CMD_LOAD_KEY:
            self.key = payload
            self._clear_message()
        elif cmd == CMD_LOAD_IV:
            self.iv = payload
            self._clear_message()
        elif cmd == CMD_LOAD_AAD:
            self.aad = payload
        elif cmd == CMD_LOAD_PLAINTEXT:
            self.data = payload
        elif cmd == CMD_LOAD_TAG_REF:
            self.tag_ref = payload
        elif cmd in (CMD_START_ENCRYPT, CMD_START_DECRYPT):
            decrypt = cmd == CMD_START_DECRYPT
            if not self.data or (decrypt and not self.tag_ref):
                return responses + [(RESP_ERR_LEN, bytes([cmd]))]
            output, tag = run_message(self.key, self.iv, self.aad, self.data, decrypt)
            passed = decrypt and hmac.compare_digest(tag, self.tag_ref)
            if passed or not decrypt:
                responses.append((RESP_CIPHERTEXT, output))
            responses.append((RESP_AUTH_TAG, tag))
            if decrypt:
                responses.append((RESP_VERIFY_RESULT, VERIFY_PASS if passed else VERIFY_FAIL))
            self._clear_message()
        else:
            raise ValueError(f"Unexpected opcode 0x{cmd:02X} in TX stream")
        return responses


def simulate(packets: List[Packet]) -> List[Packet]:
    """Answers a host -> FPGA stream the way aes_gcm_engine does."""
    engine = Engine()
    return [response for cmd, payload in packets for response in engine.answer(cmd, payload)]
