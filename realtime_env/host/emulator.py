"""Stands in for a board: the software model answers, on the schedule of the measured link.

The numbers come from wifi-test and the RTL runs in INSTRUCTIONS.md. The IP is not a stage here:
it stayed ahead of the link up to 80 MHz SCLK in simulation, far above every link in LINKS.
Not modelled: ESP32 load while Wi-Fi and SPI run together, Wi-Fi interference, lost connections.
"""

import random
import time
from collections import deque
from dataclasses import dataclass
from typing import Deque, Tuple

from . import gcm_model
from .links import LINKS, Preset
from .packet_file import Packet
from .protocol import parse_packets

_KB = 1024
_SPIN_S = 1e-3      # time.sleep overshoots on Windows, so the last millisecond is a busy wait
_LATE_S = 1e-3      # A burst this far behind its schedule counts as late

# wifi-test with esp32_bridge, firmware window 32 KB
WIFI_UP = 2829 * _KB
WIFI_DOWN = 3278 * _KB
WIFI_TOTAL = 3594 * _KB
WIFI_RTT_MIN_S = 1.5e-3     # Assumed: wifi-test reports only the mean and the maximum
WIFI_RTT_MEAN_S = 2.7e-3
WIFI_RTT_MAX_S = 10.6e-3

USB_RTT_S = 1e-3            # Assumed, never measured: the USB adapters of uart2m, uart12m and spi30

# Wire bytes that carry packets, fitted to the 64x64 image times of the RTL table
_EFFICIENCY = {"uart2m": 0.983, "uart12m": 0.868, "spi40": 0.968, "spi30": 0.965}


class Wifi:
    """The radio is shared: while both directions are busy, they split WIFI_TOTAL."""

    def __init__(self, seed: int):
        self._random = random.Random(seed)
        self._free = {"up": 0.0, "down": 0.0}
        self._rates = {"up": WIFI_UP, "down": WIFI_DOWN}

    def carry(self, ready: float, size: int, direction: str) -> float:
        """Returns when `size` bytes handed over at `ready` have crossed."""
        other = "down" if direction == "up" else "up"
        rate = WIFI_TOTAL / 2 if self._free[other] > ready else self._rates[direction]
        self._free[direction] = max(ready, self._free[direction]) + size / rate
        return self._free[direction]

    def round_trip(self) -> float:
        spread = self._random.expovariate(1 / (WIFI_RTT_MEAN_S - WIFI_RTT_MIN_S))
        return min(WIFI_RTT_MIN_S + spread, WIFI_RTT_MAX_S)


@dataclass(frozen=True)
class Profile:
    """One link as the emulator sees it."""
    rate: float                 # Packet bytes per second on the wire, each way
    wifi: bool = False
    round_trip_s: float = 0.0   # Fixed latency of the host hop, once per burst


def profile_of(link: str, host_hop: bool = True) -> Profile:
    """`host_hop=False` keeps only the part the RTL covers, for checking against the RTL table."""
    preset: Preset = LINKS[link]
    wire = preset.baud / 10 if preset.baud else preset.sclk_mhz * 1e6 / 8
    rate = wire * _EFFICIENCY[link]
    if not host_hop:
        return Profile(rate)
    return Profile(rate, wifi=True) if preset.transport == "esp" else Profile(rate, round_trip_s=USB_RTT_S)


class RealClock:
    def now(self) -> float:
        return time.perf_counter()

    def wait_until(self, moment: float) -> None:
        left = moment - time.perf_counter()
        if left > _SPIN_S:
            time.sleep(left - _SPIN_S)
        while time.perf_counter() < moment:
            time.sleep(0)  # Keeps the window thread running


class VirtualClock:
    """Jumps to each deadline, so the schedule can be checked without the CPU time of the model."""

    def __init__(self):
        self.moment = 0.0

    def now(self) -> float:
        return self.moment

    def wait_until(self, moment: float) -> None:
        self.moment = max(self.moment, moment)


class EmulatedClient:
    """Has the methods of the UART client and of EspBridge, so links.transfer() drives it unchanged."""

    def __init__(self, profile: Profile, seed: int = 1, clock=None):
        self._profile = profile
        self._clock = clock or RealClock()
        self._engine = gcm_model.Engine()
        self._wifi = Wifi(seed) if profile.wifi else None
        self._replies: Deque[Tuple[float, Packet]] = deque()
        self._up_free = 0.0
        self._down_free = 0.0
        self.late = 0

    def _deliver(self, ready: float, size: int, direction: str) -> float:
        """Moves `size` bytes across the Wi-Fi hop when there is one."""
        return self._wifi.carry(ready, size, direction) if self._wifi else ready

    def send_stream(self, data: bytes) -> None:
        now = self._clock.now()
        trip = self._wifi.round_trip() if self._wifi else self._profile.round_trip_s
        for cmd, payload in parse_packets(data):
            size = 2 + len(payload)
            at_bridge = self._deliver(now + trip / 2, size, "up")
            self._up_free = max(at_bridge, self._up_free) + size / self._profile.rate
            for response in self._engine.answer(cmd, payload):
                self._down_free = max(self._up_free, self._down_free) + (2 + len(response[1])) / self._profile.rate
                due = self._deliver(self._down_free, 2 + len(response[1]), "down") + trip / 2
                self._replies.append((due, response))

    def receive_packet(self) -> Packet:
        if not self._replies:
            raise TimeoutError("The emulated IP has no reply pending")
        due, response = self._replies.popleft()
        if not self._replies:  # Only the end of a burst matters: the model answers it all at once
            self.late += self._clock.now() > due + _LATE_S
        self._clock.wait_until(due)
        return response

    def close(self) -> None:
        pass


def open_client(link: str, host_hop: bool = True, seed: int = 1, clock=None) -> EmulatedClient:
    return EmulatedClient(profile_of(link, host_hop), seed, clock)
