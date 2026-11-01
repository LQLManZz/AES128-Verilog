"""The links to the IP: what each --link means, and one way to exchange packets over any of them."""

import time
from dataclasses import dataclass
from typing import Callable, List, Optional

from . import framing, gcm_model
from .packet_file import Packet
from .protocol import (
    BURST_MESSAGES, CMD_ACKS, CMD_NAMES, CMD_START_DECRYPT, CMD_START_ENCRYPT, RESP_AUTH_TAG,
    RESP_CIPHERTEXT, RESP_NAMES, RESP_VERIFY_RESULT, build_packet,
)

_ENCRYPT_RESPONSES = (RESP_CIPHERTEXT, RESP_AUTH_TAG)
_DECRYPT_RESPONSES = (RESP_CIPHERTEXT, RESP_AUTH_TAG, RESP_VERIFY_RESULT)
_REJECTED_RESPONSES = (RESP_AUTH_TAG, RESP_VERIFY_RESULT)  # The IP withheld the plaintext
_RX_BUFFER_BYTES = 1 << 16  # Must hold a whole window of replies while the host is still writing
MAX_REPORTED_DIFFERENCES = 5


@dataclass(frozen=True)
class Preset:
    """One --link choice."""
    label: str
    transport: str  # "uart", "esp" or "ft232h"
    baud: int = 0
    uart_clk_mhz: float = 0.0  # Non-zero: UART on its own clock, as in aes_uart_12m_top
    sclk_mhz: float = 0.0


LINKS = {
    "uart2m": Preset("UART 2 Mbaud", "uart", baud=2_000_000),
    "uart12m": Preset("UART 12 Mbaud", "uart", baud=12_000_000, uart_clk_mhz=120.0),
    "spi40": Preset("SPI 40 MHz qua ESP32-S3", "esp", sclk_mhz=40.0),
    "spi30": Preset("SPI 30 MHz qua FT232H", "ft232h", sclk_mhz=30.0),
}


@dataclass
class Options:
    """Where the hardware of a link is."""
    window: int = BURST_MESSAGES
    port: Optional[str] = None
    timeout: float = 3.0
    esp_host: str = "192.168.4.1"
    ftdi_url: str = "ftdi://ftdi:232h/1"


@dataclass
class Exchange:
    responses: List[Packet]
    elapsed_s: float
    note: str = ""


def load_client_class() -> type:
    # Imported here because uart_client.py exits when pyserial is missing.
    from .uart_client import AesGcmUartClient
    return AesGcmUartClient


def open_client(key: bytes, port: Optional[str], baud: int, timeout: float):
    variant = "aes128" if len(key) == 16 else "aes256"
    client = load_client_class()(port=port, baudrate=baud, timeout=timeout, variant=variant)
    if hasattr(client.ser, "set_buffer_size"):  # Windows only
        client.ser.set_buffer_size(rx_size=_RX_BUFFER_BYTES)
    return client


def read_reply(receive: Callable[[], Packet], cmd: int) -> List[Packet]:
    """Reads the complete answer to one command through `receive`."""
    if cmd in CMD_ACKS:
        expected = (CMD_ACKS[cmd],)
    else:
        expected = _DECRYPT_RESPONSES if cmd == CMD_START_DECRYPT else _ENCRYPT_RESPONSES

    responses = []
    while len(responses) < len(expected):
        got, data = receive()
        if cmd == CMD_START_DECRYPT and not responses and got == RESP_AUTH_TAG:
            expected = _REJECTED_RESPONSES
        want = expected[len(responses)]
        if got != want:
            raise ValueError(f"expected {RESP_NAMES[want]}, received "
                             f"{RESP_NAMES.get(got, 'UNKNOWN')} (0x{got:02X}) {data.hex()}")
        responses.append((got, data))
    return responses


def read_replies(receive: Callable[[], Packet], group: List[Packet], first_chunk: int = 0,
                 on_chunk: Optional[Callable[[int], None]] = None) -> List[Packet]:
    """Reads the answers to a group of commands, naming the chunk and command that failed."""
    responses = []
    chunk = first_chunk
    for cmd, _ in group:
        try:
            responses += read_reply(receive, cmd)
        except (ValueError, TimeoutError) as error:
            raise type(error)(f"Chunk {chunk}, {CMD_NAMES[cmd]}: {error}") from error
        if cmd in (CMD_START_ENCRYPT, CMD_START_DECRYPT):
            chunk += 1
            if on_chunk:
                on_chunk(chunk)
    return responses


def transfer(client, packets: List[Packet], on_chunk: Optional[Callable[[int], None]] = None,
             window: int = BURST_MESSAGES) -> List[Packet]:
    """Sends up to `window` messages at once, then reads all their answers.

    The RX FIFO of aes_gcm_engine holds what arrives while a message is running, so the
    host has no need to wait for each ACK. A window of 1 is stop-and-wait, for debugging.
    Any client with send_stream() and receive_packet() works: a serial port or the ESP32 bridge.
    """
    responses = []
    chunk = 0
    for group in framing.batches(packets, window):
        client.send_stream(b"".join(build_packet(cmd, payload) for cmd, payload in group))
        replies = read_replies(client.receive_packet, group, chunk, on_chunk)
        chunk += sum(cmd in (CMD_START_ENCRYPT, CMD_START_DECRYPT) for cmd, _ in group)
        responses += replies
    return responses


def compare_with_model(packets: List[Packet], responses: List[Packet]) -> List[str]:
    """Lists every chunk where the board and the software model disagree."""
    expected = framing.split_rx(gcm_model.simulate(packets))
    actual = framing.split_rx(responses)
    if len(expected) != len(actual):
        return [f"board answered {len(actual)} chunks, model {len(expected)}"]

    def verdict(reply: framing.Reply) -> str:
        return "PASS" if reply.verified else "FAIL"

    differences = []
    for chunk, (want, got) in enumerate(zip(expected, actual)):
        if got.data != want.data:
            differences.append(f"chunk {chunk}: data differs")
        if got.tag != want.tag:
            differences.append(f"chunk {chunk}: tag differs (board {got.tag.hex()}, model {want.tag.hex()})")
        if got.verified != want.verified:
            differences.append(f"chunk {chunk}: verify differs (board {verdict(got)}, model {verdict(want)})")
    return differences


class ModelChannel:
    label = "software model (gcm_model), không phải RTL"
    is_model = True

    def exchange(self, packets: List[Packet], name: str = "", on_chunk=None) -> Exchange:
        started = time.perf_counter()
        responses = gcm_model.simulate(packets)
        return Exchange(responses, time.perf_counter() - started)

    def close(self) -> None:
        pass


class RtlChannel:
    is_model = False

    def __init__(self, preset: Preset, window: int):
        from . import rtl_sim  # It imports this module
        self._rtl_sim = rtl_sim
        link = "uart" if preset.transport == "uart" else "spi"
        self._config = rtl_sim.SimConfig(link, preset.sclk_mhz or rtl_sim.SimConfig.sclk_mhz,
                                         preset.baud or rtl_sim.SimConfig.baud, window, preset.uart_clk_mhz)
        self.label = f"RTL QuestaSim, không phải board | {self._config.describe()}, burst {window} message"

    def exchange(self, packets: List[Packet], name: str = "rtl", on_chunk=None) -> Exchange:
        result = self._rtl_sim.run_stream(packets, name, self._config)
        status = f"STATUS 0x{result.statuses[-1]:02X} | " if result.statuses else ""
        return Exchange(result.responses, result.elapsed_s, f"{status}{result.frames} frame, thời gian mô phỏng")

    def close(self) -> None:
        pass


class HardwareChannel:
    """A real board. `send` plays one stream through `client`, which is closed with the channel."""

    is_model = False

    def __init__(self, label: str, client, send: Callable):
        self.label = f"phần cứng | {label}"
        self._client = client
        self._send = send

    def exchange(self, packets: List[Packet], name: str = "", on_chunk=None) -> Exchange:
        started = time.perf_counter()
        responses = self._send(self._client, packets, on_chunk)
        return Exchange(responses, time.perf_counter() - started, "thời gian thật")

    def close(self) -> None:
        self._client.close()


class EmulatedChannel:
    """The software model behind the real transfer(), answering on the schedule of the link."""

    is_model = True  # The bytes are the model's, so comparing against it proves nothing

    def __init__(self, preset: Preset, client, window: int):
        self.label = f"giả lập theo số đo, không phải phần cứng | {preset.label}, burst {window} message"
        self._client = client
        self._window = window

    @property
    def late(self) -> int:
        return self._client.late

    def exchange(self, packets: List[Packet], name: str = "", on_chunk=None) -> Exchange:
        started = time.perf_counter()
        responses = transfer(self._client, packets, on_chunk, self._window)
        return Exchange(responses, time.perf_counter() - started, "thời gian giả lập")

    def close(self) -> None:
        pass


def open_channel(link: str, sim: Optional[str], options: Options, key: bytes):
    """Opens what --link and --sim name. `key` only tells the UART client its key size."""
    preset = LINKS[link]
    if sim == "model":
        return ModelChannel()
    if sim == "rtl":
        return RtlChannel(preset, options.window)
    if sim == "emu":
        from . import emulator  # It imports this module
        return EmulatedChannel(preset, emulator.open_client(link), options.window)

    def play(client, packets, on_chunk):
        return transfer(client, packets, on_chunk, options.window)

    if preset.transport == "uart":
        client = open_client(key, options.port, preset.baud, options.timeout)
        return HardwareChannel(f"{preset.label}, {client.port}", client, play)
    if preset.transport == "esp":
        from . import esp_link
        client = esp_link.EspBridge(options.esp_host, timeout=options.timeout)
        return HardwareChannel(f"{preset.label}, {options.esp_host}", client, play)

    from . import spi_link
    client = spi_link.Ft232hLink(options.ftdi_url, int(preset.sclk_mhz * 1e6))

    def play_spi(ftdi, packets, on_chunk):
        return spi_link.transfer_spi(ftdi, packets, on_chunk, options.window)

    return HardwareChannel(f"{preset.label}, {options.ftdi_url}", client, play_spi)
