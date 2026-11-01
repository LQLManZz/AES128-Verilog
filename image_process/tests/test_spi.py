"""Runs the SPI host path against a model of spi_link answered by the software model."""

import pytest
from uart_protocol import RESP_ACK_KEY, RESP_ACK_IV, build_packet, parse_packets

from imgapp import framing, gcm_model, spi_frames, spi_link

KEY = bytes(range(32))
STATUS_OK = 0xA0


def tx_packets(width=40, height=40):
    pixels = bytes(i % 251 for i in range(width * height))
    return framing.build_tx(pixels, width, height, KEY)


class FakeLink:
    """Behaves like spi_link.sv: a status byte, then whatever the TX FIFO holds."""

    def __init__(self, status=STATUS_OK, latency=0):
        self.status = status
        self.latency = latency  # Idle bytes before each reply starts
        self.sent = bytearray()
        self.queue = bytearray()
        self.answered = 0
        self.frames = []

    def exchange(self, frame):
        self.frames.append(frame)
        answer = bytearray([self.status])
        if frame[0] == spi_frames.OP_DATA:
            self.sent += frame[1:]
        for _ in frame[1:]:
            answer.append(self.queue.pop(0) if self.queue else 0)
        self._answer()
        return bytes(answer)

    def _answer(self):
        packets = []
        data = bytes(self.sent)
        position = 0
        while position + 2 <= len(data) and position + 2 + data[position + 1] <= len(data):
            packets.append((data[position], data[position + 2:position + 2 + data[position + 1]]))
            position += 2 + data[position + 1]
        responses = gcm_model.simulate(packets)
        for packet in responses[self.answered:]:
            self.queue += bytes(self.latency) + build_packet(*packet)
        self.answered = len(responses)


def test_data_frame_starts_with_the_opcode():
    frame = spi_frames.data_frame([(0x05, b"")])
    assert frame == bytes([spi_frames.OP_DATA, 0x05, 0x00])


def test_read_frame_clocks_the_requested_bytes():
    assert spi_frames.read_frame(4) == bytes([spi_frames.OP_READ]) + bytes(4)


def test_clear_frame_is_a_single_byte():
    assert spi_frames.CLEAR_FRAME == bytes([spi_frames.OP_CLEAR])


def test_reply_size_covers_each_command():
    assert spi_frames.reply_bytes([(0x81, b""), (0x90, bytes(16)), (0x91, bytes(16))]) == 2 + 18 + 18


def test_decoder_skips_idle_bytes_between_packets():
    decoder = spi_frames.MisoDecoder()
    decoder.feed(bytes([0xA0, 0, 0, RESP_ACK_KEY, 0, 0, RESP_ACK_IV, 0]), skip_status=True)
    assert decoder.packets == [(RESP_ACK_KEY, b""), (RESP_ACK_IV, b"")]


def test_decoder_keeps_zero_bytes_inside_a_payload():
    decoder = spi_frames.MisoDecoder()
    decoder.feed(build_packet(0x91, bytes(16)))
    assert decoder.packets == [(0x91, bytes(16))]


def test_decoder_reassembles_a_packet_split_across_frames():
    decoder = spi_frames.MisoDecoder()
    wire = build_packet(0x91, bytes(range(16)))
    decoder.feed(wire[:5])
    assert decoder.packets == []
    decoder.feed(wire[5:])
    assert decoder.packets == [(0x91, bytes(range(16)))]


@pytest.mark.parametrize("status,message", [
    (0xFF, "not answering"), (0x00, "not answering"),
    (0xA1, "rx_overflow"), (0xA2, "tx_overflow"), (0xA4, "bad_op"),
])
def test_bad_status_is_reported(status, message):
    with pytest.raises(ValueError, match=message):
        spi_frames.check_status(status)


def test_transfer_returns_what_the_simulator_returns():
    packets = tx_packets()
    assert spi_link.transfer_spi(FakeLink(), packets) == gcm_model.simulate(packets)


def test_transfer_clears_the_link_first():
    link = FakeLink()
    spi_link.transfer_spi(link, tx_packets())
    assert link.frames[0] == spi_frames.CLEAR_FRAME


def test_transfer_waits_for_slow_replies():
    packets = tx_packets()
    assert spi_link.transfer_spi(FakeLink(latency=400), packets) == gcm_model.simulate(packets)


def test_transfer_caps_the_messages_in_a_frame():
    link = FakeLink()
    spi_link.transfer_spi(link, tx_packets(200, 200), window=4)
    data_frames = [frame for frame in link.frames if frame[0] == spi_frames.OP_DATA]
    assert all(sum(cmd == 0x05 for cmd, _ in parse_packets(frame[1:])) <= 4 for frame in data_frames)


def test_transfer_reports_progress():
    seen = []
    spi_link.transfer_spi(FakeLink(), tx_packets(), seen.append)
    assert seen == [1, 2, 3, 4, 5, 6, 7]


def test_silent_slave_is_reported():
    with pytest.raises(ValueError, match="not answering"):
        spi_link.transfer_spi(FakeLink(status=0xFF), tx_packets())


def test_missing_replies_raise_a_timeout():
    class Mute(FakeLink):
        def _answer(self):
            pass

    with pytest.raises(TimeoutError, match="Chunk 0, LOAD_KEY"):
        spi_link.transfer_spi(Mute(), tx_packets(), retries=2)


def test_ft232h_link_needs_pyftdi(monkeypatch):
    monkeypatch.setitem(__import__("sys").modules, "pyftdi.spi", None)
    with pytest.raises(OSError, match="pyftdi"):
        spi_link.Ft232hLink("ftdi://ftdi:232h/1", 15_000_000)
