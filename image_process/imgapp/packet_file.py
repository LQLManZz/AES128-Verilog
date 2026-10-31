"""Reads and writes packet streams as .bin (raw UART bytes) and .txt (hex, one packet per line)."""

from pathlib import Path
from typing import List, Tuple

from uart_protocol import (
    CMD_NAMES, CMD_START_DECRYPT, CMD_START_ENCRYPT, RESP_AUTH_TAG, RESP_NAMES,
    build_packet, parse_packets,
)

Packet = Tuple[int, bytes]

_CHUNK_ENDS = (CMD_START_ENCRYPT, CMD_START_DECRYPT, RESP_AUTH_TAG)


def _format_lines(packets: List[Packet]) -> List[str]:
    lines = []
    chunk = 0
    for cmd, payload in packets:
        name = CMD_NAMES.get(cmd) or RESP_NAMES.get(cmd, "UNKNOWN")
        lines.append(f"{build_packet(cmd, payload).hex(' ').upper()}  # {name} chunk {chunk}")
        if cmd in _CHUNK_ENDS:
            chunk += 1
    return lines


def write_stream(packets: List[Packet], base: Path, title: str) -> None:
    """Writes base.bin and base.txt."""
    base.with_suffix(".bin").write_bytes(b"".join(build_packet(cmd, payload) for cmd, payload in packets))
    text = [f"# {title}", *_format_lines(packets)]
    base.with_suffix(".txt").write_text("\n".join(text) + "\n", encoding="utf-8")


def read_stream(path: Path) -> List[Packet]:
    """Reads a stream back from either .bin or .txt."""
    if path.suffix.lower() == ".bin":
        return parse_packets(path.read_bytes())
    lines = path.read_text(encoding="utf-8").splitlines()
    return parse_packets(bytes.fromhex(" ".join(line.split("#")[0] for line in lines)))
