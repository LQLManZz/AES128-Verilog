import pytest
from uart_protocol import (
    CMD_LOAD_AAD, CMD_LOAD_IV, CMD_LOAD_KEY, CMD_LOAD_PLAINTEXT, CMD_START_ENCRYPT,
    MAX_DATA_BYTES, RESP_ERR_LEN,
)

from imgapp import framing, packet_file

KEY = bytes(range(32))


def stream(width, height, chunk_blocks=15):
    pixels = bytes(i % 251 for i in range(width * height))
    return pixels, framing.build_tx(pixels, width, height, KEY, chunk_blocks)


def ivs(packets):
    return [payload for cmd, payload in packets if cmd == CMD_LOAD_IV]


@pytest.mark.parametrize("width,height", [(256, 256), (17, 3), (1, 1), (100, 73)])
@pytest.mark.parametrize("chunk_blocks", [1, 4, 15])
def test_pixels_survive_the_round_trip(width, height, chunk_blocks):
    pixels, packets = stream(width, height, chunk_blocks)
    key, messages = framing.split_tx(packets)
    header = framing.ImageHeader.unpack(messages[0].aad)

    assert key == KEY
    assert (header.width, header.height, header.channels) == (width, height, 1)
    assert framing.join_pixels(header, [m.data for m in messages]) == pixels


@pytest.mark.parametrize("width,height", [(256, 256), (17, 3)])
def test_every_packet_is_valid_for_the_hardware(width, height):
    _, packets = stream(width, height)
    for cmd, payload in packets:
        assert len(payload) <= 32 if cmd == CMD_LOAD_KEY else len(payload) <= MAX_DATA_BYTES
        if cmd in (CMD_LOAD_AAD, CMD_LOAD_PLAINTEXT):
            assert payload and len(payload) % 16 == 0
        if cmd == CMD_LOAD_IV:
            assert len(payload) == 12
        if cmd == CMD_START_ENCRYPT:
            assert payload == b""


def test_stream_follows_protocol_order():
    _, packets = stream(32, 15)  # 480 bytes = two full chunks
    assert [cmd for cmd, _ in packets] == [
        CMD_LOAD_KEY,
        CMD_LOAD_IV, CMD_LOAD_AAD, CMD_LOAD_PLAINTEXT, CMD_START_ENCRYPT,
        CMD_LOAD_IV, CMD_LOAD_PLAINTEXT, CMD_START_ENCRYPT,
    ]


def test_ivs_never_repeat_within_or_across_encodes():
    _, first = stream(256, 256)
    _, second = stream(256, 256)
    all_ivs = ivs(first) + ivs(second)
    assert len(all_ivs) == 548
    assert len(set(all_ivs)) == len(all_ivs)


def test_256_square_uses_274_chunks():
    _, packets = stream(256, 256)
    _, messages = framing.split_tx(packets)
    assert len(messages) == 274


def test_missing_chunk_is_rejected():
    _, packets = stream(64, 64)
    _, messages = framing.split_tx(packets)
    header = framing.ImageHeader.unpack(messages[0].aad)
    with pytest.raises(ValueError, match="chunks"):
        framing.join_pixels(header, [m.data for m in messages[:-1]])


def test_invalid_chunk_blocks_is_rejected():
    with pytest.raises(ValueError, match="chunk_blocks"):
        framing.build_tx(bytes(16), 16, 1, KEY, chunk_blocks=16)


def test_fpga_error_response_is_reported():
    with pytest.raises(ValueError, match="ERR_LEN_MISMATCH"):
        framing.split_rx([(RESP_ERR_LEN, b"\x04")])


def test_txt_and_bin_hold_the_same_packets(tmp_path):
    _, packets = stream(40, 40)
    packet_file.write_stream(packets, tmp_path / "tx", "title")
    assert packet_file.read_stream(tmp_path / "tx.bin") == packets
    assert packet_file.read_stream(tmp_path / "tx.txt") == packets
