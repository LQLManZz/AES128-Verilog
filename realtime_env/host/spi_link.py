"""Plays a TX stream to the FPGA over SPI, through an FT232H (see INSTRUCTIONS.md)."""

from typing import Callable, List, Optional

from .protocol import BURST_MESSAGES, CMD_START_DECRYPT, CMD_START_ENCRYPT

from . import framing, spi_frames, links
from .packet_file import Packet

READ_BYTES = 512
READ_RETRIES = 1000


class Ft232hLink:
    """One full-duplex exchange per frame. pyftdi drives spi_cs_n around each one."""

    def __init__(self, url: str, frequency: int):
        try:
            from pyftdi.spi import SpiController
        except ImportError as error:
            raise OSError("pyftdi is not installed: pip install pyftdi") from error
        self._controller = SpiController()
        self._controller.configure(url)
        self._port = self._controller.get_port(cs=0, freq=frequency, mode=0)

    def exchange(self, frame: bytes) -> bytes:
        return bytes(self._port.exchange(frame, readlen=len(frame), duplex=True))

    def close(self) -> None:
        self._controller.terminate()


def transfer_spi(link, packets: List[Packet], on_chunk: Optional[Callable[[int], None]] = None,
                 window: int = BURST_MESSAGES, retries: int = READ_RETRIES) -> List[Packet]:
    """Sends up to `window` messages per DATA frame, reading replies on the same clocks.

    Each message answers slightly more than it sends, so READ frames collect the rest.
    """
    decoder = spi_frames.MisoDecoder()

    def exchange(frame: bytes) -> None:
        answer = link.exchange(frame)
        spi_frames.check_status(answer[0])
        decoder.feed(answer, skip_status=True)

    def receive() -> Packet:
        for _ in range(retries):
            if decoder.packets:
                return decoder.packets.pop(0)
            exchange(spi_frames.read_frame(READ_BYTES))
        raise TimeoutError(f"No reply after {retries} read frames")

    link.exchange(spi_frames.CLEAR_FRAME)  # Whatever an aborted run left behind
    responses = []
    chunk = 0
    for group in framing.batches(packets, window):
        exchange(spi_frames.data_frame(group))
        responses += links.read_replies(receive, group, chunk, on_chunk)
        chunk += sum(cmd in (CMD_START_ENCRYPT, CMD_START_DECRYPT) for cmd, _ in group)
    return responses
