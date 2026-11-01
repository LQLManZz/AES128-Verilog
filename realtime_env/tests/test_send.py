"""Runs the real serial path of uart_client.py against a fake port answered by the software model."""

import pytest
import serial as pyserial
from PIL import Image
from host.protocol import (
    CMD_LOAD_PLAINTEXT, CMD_START_DECRYPT, CMD_START_ENCRYPT, RESP_ERR_LEN,
    VERIFY_FAIL, VERIFY_PASS, build_packet, parse_packets,
)

from host import framing, gcm_model, image_io, links, packet_file
from host.cli import main

KEY = bytes(range(32))
IV = bytes(range(12))
ARGS = ["--link", "uart12m", "--key", KEY.hex(), "--iv", IV.hex(), "--size", "40x40"]


class FakeSerial:
    """Answers each packet as it is written and records how much was unanswered at each write."""

    is_open = True

    def __init__(self, transform=lambda packet: packet):
        self.transform = transform
        self.sent = []
        self.answered = 0
        self.incoming = b""
        self.writes = []

    def write(self, data):
        written = parse_packets(data)
        self.writes.append((len(written), len(self.incoming)))
        self.sent += written
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
    client = links.load_client_class()(mock=True)
    client.mock = False
    client.ser = serial
    return client


def tx_packets(width=40, height=40):
    pixels = bytes(i % 251 for i in range(width * height))
    return framing.build_tx(pixels, KEY, IV, bytes(16))


@pytest.fixture
def board(monkeypatch):
    """Routes a hardware link to a fake board; set board.transform to inject a fault."""
    serial = FakeSerial()

    def open_fake_client(key, port, baud, timeout):
        serial.sent, serial.answered, serial.incoming = [], 0, b""
        return make_client(serial)

    monkeypatch.setattr(links, "open_client", open_fake_client)
    return serial


@pytest.fixture
def photo(tmp_path):
    Image.linear_gradient("L").save(tmp_path / "photo.png")
    return tmp_path / "photo.png"


def run_image(photo, tmp_path, *options):
    return main(["image", str(photo), "--output-dir", str(tmp_path / "output"), *ARGS, *options])


def test_transfer_returns_what_the_simulator_returns():
    packets = tx_packets()
    responses = links.transfer(make_client(FakeSerial()), packets)
    assert responses == gcm_model.simulate(packets)


def test_key_is_loaded_only_once():
    packets = tx_packets()
    serial = FakeSerial()
    links.transfer(make_client(serial), packets)
    assert [cmd for cmd, _ in serial.sent].count(1) == 1


def test_window_one_is_stop_and_wait():
    serial = FakeSerial()
    links.transfer(make_client(serial), tx_packets(), window=1)
    assert all(count == 1 and unread == 0 for count, unread in serial.writes)


def test_burst_writes_a_whole_window_at_once():
    serial = FakeSerial()
    packets = tx_packets()  # 7 messages
    assert links.transfer(make_client(serial), packets, window=4) == gcm_model.simulate(packets)
    assert len(serial.writes) == 2
    assert all(unread == 0 for _, unread in serial.writes)  # Every window is read before the next


def test_decrypt_with_a_wrong_tag_comes_back_without_data():
    packets = tx_packets()
    key, messages = framing.split_tx(packets)
    replies = framing.split_rx(gcm_model.simulate(packets))
    tags = [reply.tag for reply in replies]
    tags[1] = bytes(16)
    decrypt_tx = framing.build_decrypt_tx(key, messages, [reply.data for reply in replies], tags)

    decrypted = framing.split_rx(links.transfer(make_client(FakeSerial()), decrypt_tx))
    assert [reply.verified for reply in decrypted] == [True, False] + [True] * 5
    assert decrypted[1].data == b""


def test_port_failure_is_an_os_error(monkeypatch):
    def refuse(*args, **kwargs):
        raise pyserial.SerialException("busy")

    monkeypatch.setattr(pyserial, "Serial", refuse)
    with pytest.raises(OSError, match="COM99"):
        links.open_client(KEY, "COM99", 2_000_000, 1.0)


def test_progress_reports_every_chunk():
    seen = []
    links.transfer(make_client(FakeSerial()), tx_packets(), seen.append)
    assert seen == [1, 2, 3, 4, 5, 6, 7]


def test_fpga_error_names_the_chunk():
    def reject_plaintext(packet):
        return build_packet(RESP_ERR_LEN, bytes([CMD_LOAD_PLAINTEXT])) if packet[0] == 0x84 else packet

    with pytest.raises(ValueError, match="Chunk 0, LOAD_PLAINTEXT.*ERR_LEN_MISMATCH"):
        links.transfer(make_client(FakeSerial(reject_plaintext)), tx_packets())


def test_silent_board_times_out_with_the_chunk():
    with pytest.raises(TimeoutError, match="Chunk 0, LOAD_KEY"):
        links.transfer(make_client(FakeSerial(lambda packet: b"")), tx_packets())


def test_compare_flags_data_and_tag_separately():
    packets = tx_packets()
    responses = gcm_model.simulate(packets)
    tag_at = next(i for i, (cmd, _) in enumerate(responses) if cmd == 0x91)
    responses[tag_at] = (0x91, bytes(16))
    differences = links.compare_with_model(packets, responses)
    assert len(differences) == 1 and differences[0].startswith("chunk 0: tag differs")


def test_compare_flags_a_short_board_answer():
    packets = tx_packets()
    responses = gcm_model.simulate(packets)
    differences = links.compare_with_model(packets, responses[:-4])  # The last chunk's four replies
    assert differences == ["board answered 6 chunks, model 7"]


def test_compare_flags_a_different_verify_result():
    packets = tx_packets()
    key, messages = framing.split_tx(packets)
    replies = framing.split_rx(gcm_model.simulate(packets))
    decrypt_tx = framing.build_decrypt_tx(key, messages, [r.data for r in replies], [r.tag for r in replies])
    responses = gcm_model.simulate(decrypt_tx)
    assert responses[-1] == (0x92, VERIFY_PASS)
    responses[-1] = (0x92, VERIFY_FAIL)
    assert links.compare_with_model(decrypt_tx, responses) == ["chunk 6: verify differs (board FAIL, model PASS)"]


def test_hardware_writes_the_same_rx_files_as_the_model(photo, tmp_path, board):
    assert run_image(photo, tmp_path, "--sim", "model") == 0
    folder = tmp_path / "output" / "photo.png"
    modelled = (folder / "rx.bin").read_bytes()

    assert run_image(photo, tmp_path, "--port", "COM99") == 0
    assert (folder / "rx.bin").read_bytes() == modelled


def test_board_that_differs_from_the_model_is_reported(photo, tmp_path, board, capsys):
    def flip_ciphertext(packet):
        return packet[:2] + bytes([packet[2] ^ 1]) + packet[3:] if packet[0] == 0x90 else packet

    board.transform = flip_ciphertext
    assert run_image(photo, tmp_path) == 1
    assert "chunk 0: data differs" in capsys.readouterr().out


def test_timeout_is_reported_as_a_failed_command(photo, tmp_path, board, capsys):
    board.transform = lambda packet: b""
    assert run_image(photo, tmp_path) == 1
    assert "Chunk 0, LOAD_KEY" in capsys.readouterr().out


def test_full_board_round_trip_restores_the_image(photo, tmp_path, board):
    assert run_image(photo, tmp_path) == 0
    folder = tmp_path / "output" / "photo.png"
    commands = [cmd for cmd, _ in packet_file.read_stream(folder / "tx_dec.bin")]
    assert CMD_START_DECRYPT in commands and CMD_START_ENCRYPT not in commands
    assert image_io.read_pixels(folder / "decrypted.png") == image_io.read_pixels(folder / "preview.png")


def test_board_can_fall_back_to_stop_and_wait(photo, tmp_path, board):
    assert run_image(photo, tmp_path, "--window", "1") == 0
    assert all(count == 1 for count, _ in board.writes)
