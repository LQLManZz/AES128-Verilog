"""Runs the real serial path of host.py against a fake port answered by the software model."""

import pytest
import serial as pyserial
from PIL import Image
from uart_protocol import (
    CMD_LOAD_PLAINTEXT, CMD_START_DECRYPT, CMD_START_ENCRYPT, RESP_ERR_LEN,
    VERIFY_FAIL, VERIFY_PASS, build_packet, parse_packets,
)

from imgapp import framing, gcm_model, image_io, packet_file, uart_link
from imgapp.__main__ import main

KEY = bytes(range(32))


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


def test_window_one_is_stop_and_wait():
    serial = FakeSerial()
    uart_link.transfer(make_client(serial), tx_packets(), window=1)
    assert all(count == 1 and unread == 0 for count, unread in serial.writes)


def test_burst_writes_a_whole_window_at_once():
    serial = FakeSerial()
    packets = tx_packets()  # 7 messages
    assert uart_link.transfer(make_client(serial), packets, window=4) == gcm_model.simulate(packets)
    assert len(serial.writes) == 2
    assert all(unread == 0 for _, unread in serial.writes)  # Every window is read before the next


def test_decrypt_with_a_wrong_tag_comes_back_without_data():
    packets = tx_packets()
    key, messages = framing.split_tx(packets)
    replies = framing.split_rx(gcm_model.simulate(packets))
    tags = [reply.tag for reply in replies]
    tags[1] = bytes(16)
    decrypt_tx = framing.build_decrypt_tx(key, messages, [reply.data for reply in replies], tags)

    decrypted = framing.split_rx(uart_link.transfer(make_client(FakeSerial()), decrypt_tx))
    assert [reply.verified for reply in decrypted] == [True, False] + [True] * 5
    assert decrypted[1].data == b""


def test_port_failure_is_an_os_error(monkeypatch):
    def refuse(*args, **kwargs):
        raise pyserial.SerialException("busy")

    monkeypatch.setattr(pyserial, "Serial", refuse)
    with pytest.raises(OSError, match="COM99"):
        uart_link.open_client(KEY, "COM99", 2_000_000, 1.0)


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


def test_compare_flags_a_short_board_answer():
    packets = tx_packets()
    responses = gcm_model.simulate(packets)
    differences = uart_link.compare_with_model(packets, responses[:-4])  # The last chunk's four replies
    assert differences == ["board answered 6 chunks, model 7"]


def test_compare_flags_a_different_verify_result():
    packets = tx_packets()
    key, messages = framing.split_tx(packets)
    replies = framing.split_rx(gcm_model.simulate(packets))
    decrypt_tx = framing.build_decrypt_tx(key, messages, [r.data for r in replies], [r.tag for r in replies])
    responses = gcm_model.simulate(decrypt_tx)
    assert responses[-1] == (0x92, VERIFY_PASS)
    responses[-1] = (0x92, VERIFY_FAIL)
    assert uart_link.compare_with_model(decrypt_tx, responses) == ["chunk 6: verify differs (board FAIL, model PASS)"]


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


def test_send_can_fall_back_to_stop_and_wait(tx_path, board):
    assert main(["send", str(tx_path), "--window", "1"]) == 0
    assert all(count == 1 for count, _ in board.writes)


def test_tampered_board_answer_is_rejected(tx_path, board):
    folder = tx_path.parent
    assert main(["send", str(tx_path)]) == 0
    assert main(["decrypt", str(tx_path), str(folder / "rx.bin")]) == 0
    assert main(["send", str(folder / "tx_dec.bin")]) == 0

    rx_dec = bytearray((folder / "rx_dec.bin").read_bytes())
    rx_dec[-1] ^= 1  # The last VERIFY_RESULT
    (folder / "rx_dec.bin").write_bytes(rx_dec)

    result = folder / "board.png"
    assert main(["decrypt", str(tx_path), str(folder / "rx.bin"),
                 "--rx-dec", str(folder / "rx_dec.bin"), "-o", str(result)]) == 1
    assert not result.exists()
