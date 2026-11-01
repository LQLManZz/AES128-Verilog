"""Talks to esp32_bridge over Wi-Fi: the same packets as UART, and the throughput test."""

import socket
import statistics
import threading
import time
from dataclasses import dataclass
from typing import List, Tuple

from . import spi_frames
from .protocol import RESP_BRIDGE_ERR

PORT = 5001
_SOCKET_BUFFER = 1 << 20
_BLOCK = 1 << 16
_PINGS = 30


class _Socket:
    """A TCP connection that reads whole lines and exact byte counts."""

    def __init__(self, host: str, port: int, timeout: float):
        try:
            self.sock = socket.create_connection((host, port), timeout=timeout)
        except OSError as error:
            raise OSError(f"Cannot reach the ESP32 bridge at {host}:{port}: {error}") from error
        self.sock.settimeout(timeout)
        self.sock.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
        self.sock.setsockopt(socket.SOL_SOCKET, socket.SO_RCVBUF, _SOCKET_BUFFER)
        self.sock.setsockopt(socket.SOL_SOCKET, socket.SO_SNDBUF, _SOCKET_BUFFER)
        self.pending = bytearray()

    def _fill(self) -> None:
        try:
            data = self.sock.recv(_BLOCK)
        except socket.timeout as error:
            raise TimeoutError("Timeout waiting for the ESP32 bridge") from error
        if not data:
            raise OSError("The ESP32 bridge closed the connection")
        self.pending += data

    def read(self, count: int) -> bytes:
        while len(self.pending) < count:
            self._fill()
        data = bytes(self.pending[:count])
        del self.pending[:count]
        return data

    def line(self) -> str:
        while b"\n" not in self.pending:
            self._fill()
        end = self.pending.index(b"\n")
        text = self.pending[:end].decode("ascii", "replace").strip()
        del self.pending[:end + 1]
        return text

    def command(self, text: str) -> str:
        self.sock.sendall(text.encode("ascii") + b"\n")
        return self.line()


class EspBridge:
    """Packet stream to the FPGA behind the bridge, with the methods of the UART client."""

    def __init__(self, host: str, port: int = PORT, timeout: float = 3.0):
        self._socket = _Socket(host, port, timeout)
        answer = self._socket.command("BRIDGE")
        if answer != "OK":
            raise OSError(f"The ESP32 refused bridge mode: {answer}")

    def send_stream(self, data: bytes) -> None:
        self._socket.sock.sendall(data)

    def receive_packet(self) -> Tuple[int, bytes]:
        cmd, length = self._socket.read(2)
        payload = self._socket.read(length)
        if cmd == RESP_BRIDGE_ERR:
            spi_frames.check_status(payload[0])
            raise ValueError(f"The ESP32 bridge reported status 0x{payload[0]:02X}")
        return cmd, payload

    def close(self) -> None:
        self._socket.sock.close()


@dataclass
class WifiResult:
    info: str
    ping_ms: List[float]
    up_kbs: float
    down_kbs: float
    duplex_kbs: float  # Both directions added together: what decides the frame rate


def _sink(link: _Socket, count: int) -> float:
    started = time.perf_counter()
    link.sock.sendall(b"SINK %d\n" % count)
    block = bytes(_BLOCK)
    for offset in range(0, count, _BLOCK):
        link.sock.sendall(block[:min(_BLOCK, count - offset)])
    link.line()
    return count / 1024 / (time.perf_counter() - started)


def _source(link: _Socket, count: int) -> float:
    started = time.perf_counter()
    link.sock.sendall(b"SRC %d\n" % count)
    link.read(count)
    link.line()
    return count / 1024 / (time.perf_counter() - started)


def _echo(host: str, port: int, count: int, timeout: float) -> float:
    link = _Socket(host, port, timeout)
    try:
        if link.command("ECHO") != "OK":
            raise OSError("The ESP32 refused ECHO")

        def send() -> None:
            block = bytes(_BLOCK)
            for offset in range(0, count, _BLOCK):
                link.sock.sendall(block[:min(_BLOCK, count - offset)])

        started = time.perf_counter()
        sender = threading.Thread(target=send, daemon=True)
        sender.start()
        link.read(count)
        sender.join()
        return 2 * count / 1024 / (time.perf_counter() - started)
    finally:
        link.sock.close()


def wifi_test(host: str, megabytes: int = 4, rounds: int = 3, port: int = PORT, timeout: float = 30.0) -> WifiResult:
    """Measures the Wi-Fi hop alone, keeping the best round like tools/wifitool.py did."""
    count = megabytes * 1024 * 1024
    link = _Socket(host, port, timeout)
    try:
        info = link.command("INFO")
        pings = []
        for _ in range(_PINGS):
            started = time.perf_counter()
            link.command("PING")
            pings.append((time.perf_counter() - started) * 1e3)
        up = max(_sink(link, count) for _ in range(rounds))
        down = max(_source(link, count) for _ in range(rounds))
    finally:
        link.sock.close()
    duplex = max(_echo(host, port, count, timeout) for _ in range(rounds))
    return WifiResult(info, pings, up, down, duplex)


def describe(result: WifiResult) -> List[str]:
    return [
        f"board: {result.info}",
        f"ping: avg {statistics.mean(result.ping_ms):.1f} ms, max {max(result.ping_ms):.1f} ms",
        f"PC -> board: {result.up_kbs:.0f} KB/s",
        f"board -> PC: {result.down_kbs:.0f} KB/s",
        f"hai chiều cùng lúc: {result.duplex_kbs:.0f} KB/s tổng",
    ]
