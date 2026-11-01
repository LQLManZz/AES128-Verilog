"""Runs the host side of the ESP32 bridge against a fake bridge on localhost."""

import socket
import threading

import pytest

from host import esp_link, framing, gcm_model, links
from host.protocol import RESP_BRIDGE_ERR, build_packet, parse_packets

KEY = bytes(range(32))
IV = bytes(range(12))


class FakeBridge:
    """Speaks the firmware's text commands and answers BRIDGE packets with the software model."""

    def __init__(self, status=None):
        self.status = status
        self.server = socket.create_server(("127.0.0.1", 0))
        self.port = self.server.getsockname()[1]
        threading.Thread(target=self._accept, daemon=True).start()

    def _accept(self):
        while True:
            try:
                connection, _ = self.server.accept()
            except OSError:
                return
            threading.Thread(target=self._serve, args=(connection,), daemon=True).start()

    def _serve(self, connection):
        try:
            self._commands(connection)
        except OSError:
            pass  # The test closed its end first

    def _commands(self, connection):
        with connection, connection.makefile("rb") as stream:
            while True:
                line = stream.readline().strip()
                if not line:
                    return
                if line == b"PING":
                    connection.sendall(b"PONG\n")
                elif line == b"INFO":
                    connection.sendall(b"OK mode=ap ch=1 bw=40 rssi=-30\n")
                elif line == b"BRIDGE":
                    connection.sendall(b"OK\n")
                    return self._bridge(connection, stream)
                elif line == b"ECHO":
                    connection.sendall(b"OK\n")
                    while data := stream.read1(1 << 16):
                        connection.sendall(data)
                    return
                elif line.startswith(b"SINK"):
                    stream.read(int(line.split()[1]))
                    connection.sendall(b"OK 1\n")
                elif line.startswith(b"SRC"):
                    connection.sendall(bytes(int(line.split()[1])) + b"OK 1\n")

    def _bridge(self, connection, stream):
        sent = []
        answered = 0
        while header := stream.read(2):
            payload = stream.read(header[1])
            sent.append((header[0], payload))
            if self.status is not None:
                connection.sendall(build_packet(RESP_BRIDGE_ERR, bytes([self.status])))
                continue
            responses = gcm_model.simulate(sent)
            connection.sendall(b"".join(build_packet(*packet) for packet in responses[answered:]))
            answered = len(responses)

    def close(self):
        self.server.close()


@pytest.fixture
def bridge():
    fake = FakeBridge()
    yield fake
    fake.close()


def tx_packets():
    return framing.build_tx(bytes(1000), KEY, IV, bytes(16))


def test_bridge_answers_like_the_uart_path(bridge):
    client = esp_link.EspBridge("127.0.0.1", bridge.port)
    packets = tx_packets()
    assert links.transfer(client, packets) == gcm_model.simulate(packets)
    client.close()


def test_bridge_carries_a_decrypt(bridge):
    client = esp_link.EspBridge("127.0.0.1", bridge.port)
    packets = tx_packets()
    key, messages = framing.split_tx(packets)
    replies = framing.split_rx(links.transfer(client, packets))
    tags = [reply.tag for reply in replies]
    decrypt_tx = framing.build_decrypt_tx(key, messages, [reply.data for reply in replies], tags)
    decrypted = framing.split_rx(links.transfer(client, decrypt_tx))
    framing.check_replies(tags, decrypted)
    client.close()


def test_spi_status_from_the_bridge_is_named():
    fake = FakeBridge(status=0xA1)
    client = esp_link.EspBridge("127.0.0.1", fake.port)
    with pytest.raises(ValueError, match="rx_overflow"):
        links.transfer(client, tx_packets())
    client.close()
    fake.close()


def test_absent_bridge_is_an_os_error():
    with socket.create_server(("127.0.0.1", 0)) as server:
        port = server.getsockname()[1]
    with pytest.raises(OSError, match="ESP32 bridge"):
        esp_link.EspBridge("127.0.0.1", port, timeout=0.5)


def test_wifi_test_measures_all_three_directions(bridge):
    result = esp_link.wifi_test("127.0.0.1", 1, rounds=1, port=bridge.port, timeout=5.0)
    assert "ch=1" in result.info
    assert len(result.ping_ms) == 30
    assert min(result.up_kbs, result.down_kbs, result.duplex_kbs) > 0
    assert len(esp_link.describe(result)) == 5


def test_parse_packets_reads_what_the_bridge_sends():
    assert parse_packets(build_packet(RESP_BRIDGE_ERR, b"\xa1")) == [(RESP_BRIDGE_ERR, b"\xa1")]
