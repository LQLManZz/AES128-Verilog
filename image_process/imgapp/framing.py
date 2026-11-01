"""Splits an image into GCM messages that fit the packet protocol, and joins them back."""

import hmac
import secrets
import struct
from dataclasses import dataclass
from typing import Iterator, List, NamedTuple, Optional, Tuple

from uart_protocol import (
    BLOCK_BYTES, CMD_ACKS, CMD_LOAD_AAD, CMD_LOAD_IV, CMD_LOAD_KEY, CMD_LOAD_PLAINTEXT,
    CMD_LOAD_TAG_REF, CMD_START_DECRYPT, CMD_START_ENCRYPT, MAX_DATA_BLOCKS, RESP_AUTH_TAG,
    RESP_CIPHERTEXT, RESP_NAMES, RESP_VERIFY_RESULT, VERIFY_PASS,
)

from .packet_file import Packet

MAGIC = b"AGI1"
_HEADER = struct.Struct(">4sHHBBHI")  # Exactly one 16-byte AAD block
_MAX_CHUNKS = 0xFFFF  # ImageHeader.chunks is 16-bit


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
    tag_ref: bytes = b""


class Reply(NamedTuple):
    """What the IP answered to one message. A failed decrypt has no data."""
    data: bytes
    tag: bytes
    verified: Optional[bool] = None  # None after an encrypt


def build_tx(pixels: bytes, width: int, height: int, key: bytes,
             chunk_blocks: int = MAX_DATA_BLOCKS, session: Optional[bytes] = None,
             channels: int = 1) -> List[Packet]:
    """Builds the host -> FPGA packet stream for one image of 8-bit samples."""
    if not 1 <= chunk_blocks <= MAX_DATA_BLOCKS:
        raise ValueError(f"chunk_blocks must be 1..{MAX_DATA_BLOCKS}, got {chunk_blocks}")
    if width * height * channels != len(pixels):
        raise ValueError(f"Expected {width * height * channels} pixel bytes, got {len(pixels)}")

    chunk_bytes = chunk_blocks * BLOCK_BYTES
    pieces = [pixels[i:i + chunk_bytes] for i in range(0, len(pixels), chunk_bytes)]
    if len(pieces) > _MAX_CHUNKS:
        raise ValueError(f"Image needs {len(pieces)} chunks, the header holds {_MAX_CHUNKS}: raise --chunk-blocks")
    header = ImageHeader(width, height, channels, chunk_blocks, len(pieces), len(pixels))
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
    iv = aad = data = tag_ref = b""
    for cmd, payload in packets:
        if cmd == CMD_LOAD_KEY:
            key = payload
        elif cmd == CMD_LOAD_IV:
            iv = payload
        elif cmd == CMD_LOAD_AAD:
            aad = payload
        elif cmd == CMD_LOAD_PLAINTEXT:
            data = payload
        elif cmd == CMD_LOAD_TAG_REF:
            tag_ref = payload
        elif cmd in (CMD_START_ENCRYPT, CMD_START_DECRYPT):
            messages.append(Message(iv, aad, data, cmd, tag_ref))
            aad = tag_ref = b""  # The engine clears these after each message
        else:
            raise ValueError(f"Unexpected opcode 0x{cmd:02X} in TX stream")
    if not key or not messages:
        raise ValueError("TX stream has no key or no message")
    return key, messages


def split_rx(packets: List[Packet]) -> List[Reply]:
    """Returns one Reply for each message in an FPGA -> host stream."""
    replies = []
    data = None
    for cmd, payload in packets:
        if cmd in CMD_ACKS.values():
            continue
        if cmd == RESP_CIPHERTEXT and data is None:
            data = payload
        elif cmd == RESP_AUTH_TAG:
            replies.append(Reply(data or b"", payload))
            data = None
        elif cmd == RESP_VERIFY_RESULT and replies and data is None and replies[-1].verified is None:
            replies[-1] = replies[-1]._replace(verified=payload == VERIFY_PASS)
        else:
            raise ValueError(f"Unexpected response 0x{cmd:02X} ({RESP_NAMES.get(cmd, 'UNKNOWN')}) in RX stream")
    if data is not None:
        raise ValueError("RX stream ends with data that has no tag")
    for index, reply in enumerate(replies):
        if not reply.data and reply.verified is not False:
            raise ValueError(f"Chunk {index} has a tag but no data")
    return replies


def join_pixels(header: ImageHeader, chunks: List[bytes]) -> bytes:
    if len(chunks) != header.chunks:
        raise ValueError(f"Expected {header.chunks} chunks, got {len(chunks)}")
    pixels = b"".join(chunks)[:header.byte_len]
    if len(pixels) != header.byte_len:
        raise ValueError(f"Expected {header.byte_len} pixel bytes, got {len(pixels)}")
    return pixels


def build_decrypt_tx(key: bytes, messages: List[Message], ciphertexts: List[bytes],
                     tags: List[bytes]) -> List[Packet]:
    """Builds the stream that sends the ciphertext back through START_DECRYPT, tag by tag."""
    if not len(messages) == len(ciphertexts) == len(tags):
        raise ValueError(f"Expected {len(messages)} ciphertext chunks and tags, "
                         f"got {len(ciphertexts)} and {len(tags)}")
    packets = [(CMD_LOAD_KEY, key)]
    for message, ciphertext, tag in zip(messages, ciphertexts, tags):
        packets.append((CMD_LOAD_IV, message.iv))
        if message.aad:
            packets.append((CMD_LOAD_AAD, message.aad))
        packets.append((CMD_LOAD_PLAINTEXT, ciphertext))
        packets.append((CMD_LOAD_TAG_REF, tag))
        packets.append((CMD_START_DECRYPT, b""))
    return packets


def check_replies(expected_tags: List[bytes], replies: List[Reply]) -> None:
    """Accepts a decrypt only if the IP verified every chunk and its tags agree with the host's."""
    if len(expected_tags) != len(replies):
        raise ValueError(f"Expected {len(expected_tags)} replies, got {len(replies)}")
    bad = [index for index, (want, reply) in enumerate(zip(expected_tags, replies))
           if not reply.verified or not hmac.compare_digest(want, reply.tag)]
    if bad:
        raise TagMismatch(bad)


def batches(packets: List[Packet], window: int) -> Iterator[List[Packet]]:
    """Groups a stream so each group holds at most `window` messages.

    A window of 1 means stop-and-wait, so every packet then travels on its own.
    """
    group = []
    started = 0
    for packet in packets:
        group.append(packet)
        started += packet[0] in (CMD_START_ENCRYPT, CMD_START_DECRYPT)
        if window == 1 or started == window:
            yield group
            group = []
            started = 0
    if group:
        yield group
