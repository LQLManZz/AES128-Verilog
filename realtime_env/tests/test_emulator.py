"""Checks the emulated links: same bytes as the model, and the schedule of the measured links."""

import pytest

from host import emulator, framing, gcm_model, links
from host.emulator import Profile, VirtualClock
from host.protocol import BURST_MESSAGES

KEY = bytes(range(32))
IV = bytes(range(12))
PICTURE = bytes(64 * 64 * 3)  # The size of the RTL table in INSTRUCTIONS.md
RTL_MS = {"spi40": 2.91, "spi30": 3.89, "uart12m": 13.52, "uart2m": 71.62}


def timed(link, data=PICTURE, host_hop=False, seed=1, window=BURST_MESSAGES):
    clock = VirtualClock()
    client = emulator.open_client(link, host_hop, seed, clock)
    responses = links.transfer(client, framing.build_tx(data, KEY, IV), window=window)
    return clock.moment, responses


@pytest.mark.parametrize("link", RTL_MS)
def test_schedule_matches_the_rtl_table(link):
    assert timed(link)[0] * 1e3 == pytest.approx(RTL_MS[link], rel=0.10)


@pytest.mark.parametrize("link", RTL_MS)
def test_answers_are_the_software_model_byte_for_byte(link):
    data = bytes(range(256)) * 3
    packets = framing.build_tx(data, KEY, IV)
    assert timed(link, data)[1] == gcm_model.simulate(packets)


def test_key_stays_loaded_across_bursts():
    data = bytes(240 * 3 * BURST_MESSAGES)
    assert timed("spi40", data)[1] == gcm_model.simulate(framing.build_tx(data, KEY, IV))


def test_wifi_is_the_narrow_part_of_spi40():
    assert timed("spi40", host_hop=True)[0] > 2 * timed("spi40", host_hop=False)[0]


def test_uart_gains_only_the_usb_latency_per_burst():
    bursts = 2  # 52 chunks in bursts of 32
    with_usb, without = timed("uart2m", host_hop=True)[0], timed("uart2m", host_hop=False)[0]
    assert with_usb - without == pytest.approx(bursts * emulator.USB_RTT_S, rel=0.01)


def test_every_burst_waits_a_round_trip():
    data = bytes(240 * BURST_MESSAGES)
    client = emulator.EmulatedClient(Profile(1e12, round_trip_s=1e-3), clock=VirtualClock())
    stream = framing.build_tx(data, KEY, IV)
    links.transfer(client, stream, window=8)
    assert client._clock.moment == pytest.approx(4e-3, rel=0.01)


def test_wifi_alone_keeps_each_direction_under_its_measured_rate():
    wifi = emulator.Wifi(1)
    assert wifi.carry(0.0, emulator.WIFI_UP, "up") == pytest.approx(1.0)
    wifi = emulator.Wifi(1)
    assert wifi.carry(0.0, emulator.WIFI_DOWN, "down") == pytest.approx(1.0)


def test_wifi_both_ways_stays_under_the_measured_total():
    wifi = emulator.Wifi(1)
    half = emulator.WIFI_TOTAL // 2
    up = wifi.carry(0.0, half, "up")
    down = wifi.carry(0.0, half, "down")
    assert max(up, down) >= 0.999


def test_round_trips_stay_within_the_measurement():
    wifi = emulator.Wifi(1)
    trips = [wifi.round_trip() for _ in range(5000)]
    assert min(trips) >= emulator.WIFI_RTT_MIN_S
    assert max(trips) <= emulator.WIFI_RTT_MAX_S
    assert sum(trips) / len(trips) == pytest.approx(emulator.WIFI_RTT_MEAN_S, rel=0.05)


def test_the_same_seed_repeats_the_same_schedule():
    assert timed("spi40", host_hop=True, seed=7)[0] == timed("spi40", host_hop=True, seed=7)[0]


def test_another_seed_changes_the_latency():
    assert timed("spi40", host_hop=True, seed=1)[0] != timed("spi40", host_hop=True, seed=2)[0]


def test_a_full_burst_both_ways_takes_the_measured_total():
    data = bytes(240 * BURST_MESSAGES)
    packets = framing.build_tx(data, KEY, IV)
    clock = VirtualClock()
    client = emulator.open_client("spi40", clock=clock)
    links.transfer(client, packets)
    bytes_both_ways = framing.wire_bytes(packets) + framing.wire_bytes(gcm_model.simulate(packets))
    transfer_time = clock.moment - emulator.WIFI_RTT_MAX_S
    assert bytes_both_ways / clock.moment < emulator.WIFI_TOTAL
    assert bytes_both_ways / max(transfer_time, 1e-3) > emulator.WIFI_TOTAL * 0.8


def test_bursts_behind_schedule_are_counted():
    class Slow(VirtualClock):
        def now(self):
            return self.moment + 1.0

    client = emulator.EmulatedClient(Profile(1e12), clock=Slow())
    links.transfer(client, framing.build_tx(bytes(16), KEY, IV))
    assert client.late > 0


def test_channel_says_it_is_not_hardware():
    channel = links.open_channel("spi40", "emu", links.Options(), KEY)
    assert "không phải phần cứng" in channel.label
    assert channel.is_model


def test_channel_answers_through_transfer():
    channel = links.open_channel("spi40", "emu", links.Options(), KEY)
    packets = framing.build_tx(bytes(32), KEY, IV)
    assert channel.exchange(packets).responses == gcm_model.simulate(packets)


def test_no_pending_reply_is_a_timeout():
    with pytest.raises(TimeoutError):
        emulator.EmulatedClient(Profile(1e6), clock=VirtualClock()).receive_packet()
