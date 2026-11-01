import pytest
from uart_protocol import (
    CMD_LOAD_AAD, CMD_LOAD_IV, CMD_LOAD_KEY, CMD_LOAD_PLAINTEXT, CMD_LOAD_TAG_REF,
    CMD_START_DECRYPT, CMD_START_ENCRYPT, MAX_DATA_BYTES, RESP_ACK_IV, RESP_AUTH_TAG,
    RESP_CIPHERTEXT, RESP_ERR_LEN, RESP_VERIFY_RESULT, VERIFY_FAIL, VERIFY_PASS,
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


@pytest.mark.parametrize("chunk_blocks", [1, 15])
def test_rgb_pixels_survive_the_round_trip(chunk_blocks):
    pixels = bytes(i % 251 for i in range(17 * 3 * 3))
    packets = framing.build_tx(pixels, 17, 3, KEY, chunk_blocks, channels=3)
    _, messages = framing.split_tx(packets)
    header = framing.ImageHeader.unpack(messages[0].aad)

    assert header.channels == 3
    assert framing.join_pixels(header, [m.data for m in messages]) == pixels


def test_pixel_count_must_match_the_channels():
    with pytest.raises(ValueError, match="pixel bytes"):
        framing.build_tx(bytes(16), 16, 1, KEY, channels=3)


def test_image_with_too_many_chunks_is_rejected():
    width = 0x10000 * 16
    with pytest.raises(ValueError, match="chunk"):
        framing.build_tx(bytes(width), width, 1, KEY, chunk_blocks=1)


def test_rx_stream_cut_after_the_data_is_rejected():
    with pytest.raises(ValueError, match="no tag"):
        framing.split_rx([(RESP_CIPHERTEXT, bytes(16))])


def test_tag_without_data_needs_a_failed_verify():
    with pytest.raises(ValueError, match="no data"):
        framing.split_rx([(RESP_AUTH_TAG, bytes(16))])


def test_split_rx_reads_encrypt_and_decrypt_replies():
    tag = bytes(range(16))
    replies = framing.split_rx([
        (RESP_ACK_IV, b""), (RESP_CIPHERTEXT, b"a" * 16), (RESP_AUTH_TAG, tag),
        (RESP_CIPHERTEXT, b"b" * 16), (RESP_AUTH_TAG, tag), (RESP_VERIFY_RESULT, VERIFY_PASS),
        (RESP_AUTH_TAG, tag), (RESP_VERIFY_RESULT, VERIFY_FAIL),
    ])
    assert replies == [
        framing.Reply(b"a" * 16, tag, None),
        framing.Reply(b"b" * 16, tag, True),
        framing.Reply(b"", tag, False),
    ]


def test_decrypt_stream_loads_each_tag_as_tag_ref():
    _, packets = stream(32, 15)
    key, messages = framing.split_tx(packets)
    tags = [bytes([i]) * 16 for i in range(len(messages))]
    decrypt_tx = framing.build_decrypt_tx(key, messages, [m.data for m in messages], tags)

    assert [cmd for cmd, _ in decrypt_tx] == [
        CMD_LOAD_KEY,
        CMD_LOAD_IV, CMD_LOAD_AAD, CMD_LOAD_PLAINTEXT, CMD_LOAD_TAG_REF, CMD_START_DECRYPT,
        CMD_LOAD_IV, CMD_LOAD_PLAINTEXT, CMD_LOAD_TAG_REF, CMD_START_DECRYPT,
    ]
    assert [m.tag_ref for m in framing.split_tx(decrypt_tx)[1]] == tags


def test_check_replies_needs_one_reply_per_chunk():
    tag = bytes(16)
    with pytest.raises(ValueError, match="Expected 2 replies, got 1"):
        framing.check_replies([tag, tag], [framing.Reply(b"x", tag, True)])


def test_check_replies_names_every_failed_chunk():
    tag = bytes(16)
    other = bytes([1]) * 16
    replies = [framing.Reply(b"x", tag, True), framing.Reply(b"", tag, False), framing.Reply(b"x", other, True)]
    with pytest.raises(framing.TagMismatch) as error:
        framing.check_replies([tag, tag, tag], replies)
    assert error.value.chunks == [1, 2]


@pytest.mark.parametrize("window,sizes", [(1, [1] * 8), (1000, [8]), (2, [8])])
def test_batches_keep_every_packet_in_order(window, sizes):
    _, packets = stream(32, 15)
    groups = list(framing.batches(packets, window))
    assert [len(group) for group in groups] == sizes
    assert [packet for group in groups for packet in group] == packets


def test_batches_cap_the_messages_in_flight():
    _, packets = stream(32, 30)  # 4 messages
    groups = list(framing.batches(packets, 3))
    starts = [sum(cmd == CMD_START_ENCRYPT for cmd, _ in group) for group in groups]
    assert starts == [3, 1]
