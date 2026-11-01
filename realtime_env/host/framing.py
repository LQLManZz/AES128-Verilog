"""Splits data into GCM messages that fit the packet protocol, and joins them back."""

import hmac
import json
from dataclasses import asdict, dataclass
from pathlib import Path
from typing import Iterator, List, NamedTuple, Optional, Tuple

from .packet_file import Packet
from .protocol import (
    BLOCK_BYTES, CMD_ACKS, CMD_LOAD_AAD, CMD_LOAD_IV, CMD_LOAD_KEY, CMD_LOAD_PLAINTEXT,
    CMD_LOAD_TAG_REF, CMD_START_DECRYPT, CMD_START_ENCRYPT, MAX_DATA_BLOCKS, MAX_DATA_BYTES,
    RESP_AUTH_TAG, RESP_CIPHERTEXT, RESP_NAMES, RESP_VERIFY_RESULT, VERIFY_PASS,
)

IV_BYTES = 12
_COUNTER_OFFSET = 8  # The last 32 bits of the IV count chunks
_COUNTER_LIMIT = 1 << 32


class TagMismatch(ValueError):
    def __init__(self, chunks: List[int]):
        super().__init__(f"Authentication failed in chunk(s): {', '.join(map(str, chunks))}")
        self.chunks = chunks


@dataclass(frozen=True)
class Layout:
    """How a run split its data. Lives in session.json: it never crosses the link."""
    byte_len: int
    chunks: int
    chunk_blocks: int
    width: int = 0
    height: int = 0
    channels: int = 0

    def save(self, path: Path) -> None:
        path.write_text(json.dumps(asdict(self), indent=2) + "\n", encoding="utf-8")

    @classmethod
    def load(cls, path: Path) -> "Layout":
        return cls(**json.loads(path.read_text(encoding="utf-8")))


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


def zero_pad(data: bytes) -> bytes:
    """Fills the last block: the core only takes whole blocks."""
    return data + bytes(-len(data) % BLOCK_BYTES)


def advance_iv(iv: bytes, count: int) -> bytes:
    """Returns the IV `count` chunks later, counting in its last 32 bits."""
    counter = int.from_bytes(iv[_COUNTER_OFFSET:], "big") + count
    if counter >= _COUNTER_LIMIT:
        raise ValueError(f"The last 32 bits of IV {iv.hex()} overflow after {count} chunks: choose a lower IV")
    return iv[:_COUNTER_OFFSET] + counter.to_bytes(IV_BYTES - _COUNTER_OFFSET, "big")


def chunk_count(byte_len: int, chunk_blocks: int = MAX_DATA_BLOCKS) -> int:
    return -(-byte_len // (chunk_blocks * BLOCK_BYTES))


def build_tx(data: bytes, key: bytes, iv: bytes, aad: bytes = b"",
             chunk_blocks: int = MAX_DATA_BLOCKS) -> List[Packet]:
    """Builds the host -> FPGA stream for one piece of data.

    The IV is the first chunk's, the AAD goes with the first chunk only.
    """
    if not 1 <= chunk_blocks <= MAX_DATA_BLOCKS:
        raise ValueError(f"chunk_blocks must be 1..{MAX_DATA_BLOCKS}, got {chunk_blocks}")
    if len(iv) != IV_BYTES:
        raise ValueError(f"IV must be {IV_BYTES} bytes, got {len(iv)}")
    if len(aad) % BLOCK_BYTES or len(aad) > MAX_DATA_BYTES:
        raise ValueError(f"AAD must be whole 16-byte blocks, at most {MAX_DATA_BYTES} bytes, got {len(aad)}")
    if not data:
        raise ValueError("There is no data to send")

    chunk_bytes = chunk_blocks * BLOCK_BYTES
    pieces = [data[i:i + chunk_bytes] for i in range(0, len(data), chunk_bytes)]
    advance_iv(iv, len(pieces) - 1)  # Refuses the whole stream, not just its tail
    packets = [(CMD_LOAD_KEY, key)]
    for index, piece in enumerate(pieces):
        packets.append((CMD_LOAD_IV, advance_iv(iv, index)))
        if index == 0 and aad:
            packets.append((CMD_LOAD_AAD, aad))
        packets.append((CMD_LOAD_PLAINTEXT, zero_pad(piece)))
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


def join_chunks(layout: Layout, chunks: List[bytes]) -> bytes:
    """Puts the chunks back together and removes the padding."""
    if len(chunks) != layout.chunks:
        raise ValueError(f"Expected {layout.chunks} chunks, got {len(chunks)}")
    data = b"".join(chunks)[:layout.byte_len]
    if len(data) != layout.byte_len:
        raise ValueError(f"Expected {layout.byte_len} bytes, got {len(data)}")
    return data


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


def flip_ciphertext(responses: List[Packet], chunk: int) -> List[Packet]:
    """Flips one ciphertext bit, as a corrupted link or an attacker would."""
    seen = -1
    changed = list(responses)
    for index, (cmd, payload) in enumerate(changed):
        seen += cmd == RESP_CIPHERTEXT
        if cmd == RESP_CIPHERTEXT and seen == chunk:
            changed[index] = (cmd, bytes([payload[0] ^ 1]) + payload[1:])
            return changed
    raise ValueError(f"RX stream has no chunk {chunk}")


def wire_bytes(packets: List[Packet]) -> int:
    """Bytes these packets occupy on the link."""
    return sum(2 + len(payload) for _, payload in packets)


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
