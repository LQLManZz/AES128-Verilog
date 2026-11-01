"""SPI framing of spi_link.sv: the frame opcodes, the status byte and the MISO stream."""

from typing import List

from .protocol import build_packet

from .packet_file import Packet

OP_DATA = 0xA5
OP_READ = 0x5A
OP_CLEAR = 0xC3
CLEAR_FRAME = bytes([OP_CLEAR])

STATUS_OK = 0xA0
_STATUS_MARK_MASK = 0xF0
_STATUS_FLAGS = ((0x01, "rx_overflow"), (0x02, "tx_overflow"), (0x04, "bad_op"))


def data_frame(packets: List[Packet]) -> bytes:
    return bytes([OP_DATA]) + b"".join(build_packet(cmd, payload) for cmd, payload in packets)


def read_frame(count: int) -> bytes:
    return bytes([OP_READ]) + bytes(count)


def reply_bytes(responses: List[Packet]) -> int:
    """Returns how many bytes these responses occupy on MISO."""
    return sum(2 + len(payload) for _, payload in responses)


def check_status(status: int) -> None:
    if status & _STATUS_MARK_MASK != STATUS_OK:
        raise ValueError(f"SPI slave is not answering: status byte 0x{status:02X}")
    flags = [name for mask, name in _STATUS_FLAGS if status & mask]
    if flags:
        raise ValueError(f"SPI status 0x{status:02X}: {', '.join(flags)}")


class MisoDecoder:
    """Rebuilds packets from MISO, skipping the idle zeros between them.

    A payload may hold zeros, so only a zero where an opcode is due counts as idle.
    """

    def __init__(self):
        self._buffer = bytearray()
        self.packets: List[Packet] = []

    def feed(self, data: bytes, skip_status: bool = False) -> None:
        self._buffer += data[1:] if skip_status else data
        position = 0
        while position < len(self._buffer):
            if self._buffer[position] == 0:
                position += 1
                continue
            if position + 2 > len(self._buffer):
                break
            end = position + 2 + self._buffer[position + 1]
            if end > len(self._buffer):
                break
            self.packets.append((self._buffer[position], bytes(self._buffer[position + 2:end])))
            position = end
        del self._buffer[:position]
