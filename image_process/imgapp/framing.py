"""Splits an image into GCM messages that fit the UART protocol, and joins them back."""

import hmac
import secrets
import struct
from dataclasses import dataclass
from typing import List, Optional, Tuple

from uart_protocol import (
    BLOCK_BYTES, CMD_ACKS, CMD_LOAD_AAD, CMD_LOAD_IV, CMD_LOAD_KEY, CMD_LOAD_PLAINTEXT,
    CMD_START_DECRYPT, CMD_START_ENCRYPT, MAX_DATA_BLOCKS, RESP_AUTH_TAG, RESP_CIPHERTEXT,
    RESP_NAMES,
)

from .packet_file import Packet

MAGIC = b"AGI1"
_HEADER = struct.Struct(">4sHHBBHI")  # Exactly one 16-byte AAD block


class TagMismatch(ValueError):
    def __init__(self, chunks: List[int]):
        super().__init__(f"Authentication failed in chunk(s): {', '.join(map(str, chunks))}")
        self.chunks = chunks


@dataclass(frozen=True)
class ImageHeader:
    width: int
    height: int
    channels: int
    chunk_blocks: int
    chunks: int
    byte_len: int

    def pack(self) -> bytes:
        return _HEADER.pack(MAGIC, self.width, self.height, self.channels,
                            self.chunk_blocks, self.chunks, self.byte_len)

    @classmethod
    def unpack(cls, block: bytes) -> "ImageHeader":
        if len(block) != _HEADER.size or block[:len(MAGIC)] != MAGIC:
            raise ValueError("Stream has no image header in its first AAD block")
        return cls(*_HEADER.unpack(block)[1:])


@dataclass
class Message:
    """One GCM message, bounded by a START command."""
    iv: bytes
    aad: bytes
    data: bytes
    start: int


def build_tx(pixels: bytes, width: int, height: int, key: bytes,
             chunk_blocks: int = MAX_DATA_BLOCKS, session: Optional[bytes] = None) -> List[Packet]:
    """Builds the host -> FPGA packet stream for one grayscale image."""
    if not 1 <= chunk_blocks <= MAX_DATA_BLOCKS:
        raise ValueError(f"chunk_blocks must be 1..{MAX_DATA_BLOCKS}, got {chunk_blocks}")
    if width * height != len(pixels):
        raise ValueError(f"Expected {width * height} pixel bytes, got {len(pixels)}")

    chunk_bytes = chunk_blocks * BLOCK_BYTES
    pieces = [pixels[i:i + chunk_bytes] for i in range(0, len(pixels), chunk_bytes)]
    header = ImageHeader(width, height, 1, chunk_blocks, len(pieces), len(pixels))
    session = session or secrets.token_bytes(8)

    packets = [(CMD_LOAD_KEY, key)]
    for index, piece in enumerate(pieces):
        packets.append((CMD_LOAD_IV, session + index.to_bytes(4, "big")))
        if index == 0:
            packets.append((CMD_LOAD_AAD, header.pack()))
        padding = -len(piece) % BLOCK_BYTES  # The core only takes whole blocks
        packets.append((CMD_LOAD_PLAINTEXT, piece + bytes(padding)))
        packets.append((CMD_START_ENCRYPT, b""))
    return packets


def split_tx(packets: List[Packet]) -> Tuple[bytes, List[Message]]:
    """Returns the key and the GCM messages held in a host -> FPGA stream."""
    key = b""
    messages = []
    iv = aad = data = b""
    for cmd, payload in packets:
        if cmd == CMD_LOAD_KEY:
            key = payload
        elif cmd == CMD_LOAD_IV:
            iv = payload
        elif cmd == CMD_LOAD_AAD:
            aad = payload
        elif cmd == CMD_LOAD_PLAINTEXT:
            data = payload
        elif cmd in (CMD_START_ENCRYPT, CMD_START_DECRYPT):
            messages.append(Message(iv, aad, data, cmd))
            aad = b""  # The wrapper clears its AAD count after each message
        else:
            raise ValueError(f"Unexpected opcode 0x{cmd:02X} in TX stream")
    if not key or not messages:
        raise ValueError("TX stream has no key or no message")
    return key, messages


def split_rx(packets: List[Packet]) -> List[Tuple[bytes, bytes]]:
    """Returns (data, tag) for each message in an FPGA -> host stream."""
    results = []
    data = None
    for cmd, payload in packets:
        if cmd in CMD_ACKS.values():
            continue
        if cmd == RESP_CIPHERTEXT:
            data = payload
        elif cmd == RESP_AUTH_TAG and data is not None:
            results.append((data, payload))
            data = None
        else:
            raise ValueError(f"Unexpected response 0x{cmd:02X} ({RESP_NAMES.get(cmd, 'UNKNOWN')}) in RX stream")
    return results


def join_pixels(header: ImageHeader, chunks: List[bytes]) -> bytes:
    if len(chunks) != header.chunks:
        raise ValueError(f"Expected {header.chunks} chunks, got {len(chunks)}")
    pixels = b"".join(chunks)[:header.byte_len]
    if len(pixels) != header.byte_len:
        raise ValueError(f"Expected {header.byte_len} pixel bytes, got {len(pixels)}")
    return pixels


def build_decrypt_tx(key: bytes, messages: List[Message], ciphertexts: List[bytes]) -> List[Packet]:
    """Builds the stream that sends the ciphertext back through START_DECRYPT."""
    if len(messages) != len(ciphertexts):
        raise ValueError(f"Expected {len(messages)} ciphertext chunks, got {len(ciphertexts)}")
    packets = [(CMD_LOAD_KEY, key)]
    for message, ciphertext in zip(messages, ciphertexts):
        packets.append((CMD_LOAD_IV, message.iv))
        if message.aad:
            packets.append((CMD_LOAD_AAD, message.aad))
        packets.append((CMD_LOAD_PLAINTEXT, ciphertext))
        packets.append((CMD_START_DECRYPT, b""))
    return packets


def check_tags(expected: List[bytes], computed: List[bytes]) -> None:
    bad = [i for i, (want, got) in enumerate(zip(expected, computed)) if not hmac.compare_digest(want, got)]
    if bad:
        raise TagMismatch(bad)
