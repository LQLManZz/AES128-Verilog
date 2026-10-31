"""Runs the real serial path of host.py against a fake port answered by the software model."""

import pytest
from PIL import Image
from uart_protocol import (
    CMD_LOAD_PLAINTEXT, CMD_START_DECRYPT, CMD_START_ENCRYPT, RESP_ERR_LEN,
    build_packet, parse_packets,
)

from imgapp import framing, gcm_model, image_io, packet_file, uart_link
from imgapp.__main__ import main

KEY = bytes(range(32))


class FakeSerial:
    """Answers each packet as it is written, and fails if a START overtakes the ACK before it."""

    is_open = True

    def __init__(self, transform=lambda packet: packet):
        self.transform = transform
        self.sent = []
        self.answered = 0
        self.incoming = b""

    def write(self, data):
        assert self.incoming == b"", "host sent a packet before reading the previous reply"
        self.sent += parse_packets(data)
        responses = gcm_model.simulate(self.sent)
        for packet in responses[self.answered:]:
            self.incoming += self.transform(build_packet(*packet))
        self.answered = len(responses)

    def flush(self):
        pass

    def read(self, count):
        data, self.incoming = self.incoming[:count], self.incoming[count:]
        return data

    def close(self):
        pass


def make_client(serial):
    client = uart_link.load_client_class()(mock=True)
    client.mock = False
    client.ser = serial
    return client


def tx_packets(width=40, height=40):
    pixels = bytes(i % 251 for i in range(width * height))
    return framing.build_tx(pixels, width, height, KEY)


@pytest.fixture
def board(monkeypatch):
    """Routes `imgapp send` to a fake board; set board.transform to inject a fault."""
    serial = FakeSerial()

    def open_fake_client(key, port, baud, timeout):
        serial.sent, serial.answered, serial.incoming = [], 0, b""
        return make_client(serial)

    monkeypatch.setattr(uart_link, "open_client", open_fake_client)
    return serial


@pytest.fixture
def tx_path(tmp_path):
    Image.linear_gradient("L").save(tmp_path / "photo.png")
    out = tmp_path / "output"
    assert main(["encode", str(tmp_path / "photo.png"), "--output-dir", str(out), "--size", "40x40"]) == 0
    return out / "photo.png" / "tx.bin"


def test_transfer_returns_what_the_simulator_returns():
    packets = tx_packets()
    responses = uart_link.transfer(make_client(FakeSerial()), packets)
    assert responses == gcm_model.simulate(packets)


def test_key_is_loaded_only_once():
    packets = tx_packets()
    serial = FakeSerial()
    uart_link.transfer(make_client(serial), packets)
    assert [cmd for cmd, _ in serial.sent].count(1) == 1


def test_start_waits_for_the_plaintext_ack():
    # FakeSerial rejects any write while a reply is unread
    uart_link.transfer(make_client(FakeSerial()), tx_packets())


def test_progress_reports_every_chunk():
    seen = []
    uart_link.transfer(make_client(FakeSerial()), tx_packets(), seen.append)
    assert seen == [1, 2, 3, 4, 5, 6, 7]


def test_fpga_error_names_the_chunk():
    def reject_plaintext(packet):
        return build_packet(RESP_ERR_LEN, bytes([CMD_LOAD_PLAINTEXT])) if packet[0] == 0x84 else packet

    with pytest.raises(ValueError, match="Chunk 0, LOAD_PLAINTEXT.*ERR_LEN_MISMATCH"):
        uart_link.transfer(make_client(FakeSerial(reject_plaintext)), tx_packets())


def test_silent_board_times_out_with_the_chunk():
    with pytest.raises(TimeoutError, match="Chunk 0, LOAD_KEY"):
        uart_link.transfer(make_client(FakeSerial(lambda packet: b"")), tx_packets())


def test_compare_flags_data_and_tag_separately():
    packets = tx_packets()
    responses = gcm_model.simulate(packets)
    tag_at = next(i for i, (cmd, _) in enumerate(responses) if cmd == 0x91)
    responses[tag_at] = (0x91, bytes(16))
    differences = uart_link.compare_with_model(packets, responses)
    assert len(differences) == 1 and differences[0].startswith("chunk 0: tag differs")


def test_send_writes_the_same_rx_files_as_simulate(tx_path, board, capsys):
    assert main(["simulate", str(tx_path)]) == 0
    simulated = (tx_path.with_name("rx.bin")).read_bytes()

    assert main(["send", str(tx_path), "--port", "COM99"]) == 0
    assert tx_path.with_name("rx.bin").read_bytes() == simulated
    assert "matches the software model" in capsys.readouterr().out


def test_send_reports_a_board_that_differs_from_the_model(tx_path, board, capsys):
    def flip_ciphertext(packet):
        return packet[:2] + bytes([packet[2] ^ 1]) + packet[3:] if packet[0] == 0x90 else packet

    board.transform = flip_ciphertext
    assert main(["send", str(tx_path)]) == 1
    output = capsys.readouterr().out
    assert "chunk 0: data differs" in output


def test_timeout_is_reported_as_a_failed_command(tx_path, board, capsys):
    board.transform = lambda packet: b""
    assert main(["send", str(tx_path)]) == 1
    assert "Chunk 0, LOAD_KEY" in capsys.readouterr().out
    assert not tx_path.with_name("rx.bin").exists()


def test_full_board_round_trip_restores_the_image(tx_path, board):
    folder = tx_path.parent
    assert main(["send", str(tx_path)]) == 0
    assert main(["decrypt", str(tx_path), str(folder / "rx.bin")]) == 0
    assert main(["send", str(folder / "tx_dec.bin")]) == 0
    assert CMD_START_DECRYPT in [cmd for cmd, _ in packet_file.read_stream(folder / "tx_dec.bin")]
    assert CMD_START_ENCRYPT not in [cmd for cmd, _ in packet_file.read_stream(folder / "tx_dec.bin")]

    result = folder / "board.png"
    assert main(["decrypt", str(tx_path), str(folder / "rx.bin"),
                 "--rx-dec", str(folder / "rx_dec.bin"), "-o", str(result)]) == 0
    assert image_io.read_pixels(result) == image_io.read_pixels(folder / "preview.png")


def test_tampered_board_answer_is_rejected(tx_path, board):
    folder = tx_path.parent
    assert main(["send", str(tx_path)]) == 0
    assert main(["decrypt", str(tx_path), str(folder / "rx.bin")]) == 0
    assert main(["send", str(folder / "tx_dec.bin")]) == 0

    rx_dec = bytearray((folder / "rx_dec.bin").read_bytes())
    rx_dec[-1] ^= 1  # Last byte of the last AUTH_TAG
    (folder / "rx_dec.bin").write_bytes(rx_dec)

    result = folder / "board.png"
    assert main(["decrypt", str(tx_path), str(folder / "rx.bin"),
                 "--rx-dec", str(folder / "rx_dec.bin"), "-o", str(result)]) == 1
    assert not result.exists()
