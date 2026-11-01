import pytest
from host.protocol import (
    CMD_LOAD_AAD, CMD_LOAD_IV, CMD_LOAD_KEY, CMD_LOAD_PLAINTEXT, CMD_LOAD_TAG_REF,
    CMD_START_DECRYPT, CMD_START_ENCRYPT, MAX_DATA_BYTES, RESP_ACK_IV, RESP_AUTH_TAG,
    RESP_CIPHERTEXT, RESP_ERR_LEN, RESP_VERIFY_RESULT, VERIFY_FAIL, VERIFY_PASS,
)

from host import framing, packet_file

KEY = bytes(range(32))
IV = bytes(range(12))
AAD = bytes(range(32))


def stream(width, height, chunk_blocks=15, aad=AAD):
    pixels = bytes(i % 251 for i in range(width * height))
    return pixels, framing.build_tx(pixels, KEY, IV, aad, chunk_blocks)


def layout_of(data, messages, chunk_blocks=15):
    return framing.Layout(len(data), len(messages), chunk_blocks)


def ivs(packets):
    return [payload for cmd, payload in packets if cmd == CMD_LOAD_IV]


@pytest.mark.parametrize("width,height", [(256, 256), (17, 3), (1, 1), (100, 73)])
@pytest.mark.parametrize("chunk_blocks", [1, 4, 15])
def test_pixels_survive_the_round_trip(width, height, chunk_blocks):
    pixels, packets = stream(width, height, chunk_blocks)
    key, messages = framing.split_tx(packets)

    assert key == KEY
    assert framing.join_chunks(layout_of(pixels, messages), [m.data for m in messages]) == pixels


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


def test_first_chunk_uses_the_users_iv_and_the_count_runs_in_the_last_32_bits():
    _, packets = stream(32, 15)
    assert ivs(packets) == [IV, IV[:8] + (int.from_bytes(IV[8:], "big") + 1).to_bytes(4, "big")]


def test_ivs_never_repeat_when_a_second_stream_continues_the_count():
    data = bytes(1000)
    first = framing.build_tx(data, KEY, IV)
    chunks = framing.chunk_count(len(data))
    second = framing.build_tx(data, KEY, framing.advance_iv(IV, chunks))
    all_ivs = ivs(first) + ivs(second)
    assert len(set(all_ivs)) == len(all_ivs) == 2 * chunks


def test_aad_goes_with_the_first_chunk_only():
    _, packets = stream(32, 15)
    _, messages = framing.split_tx(packets)
    assert [m.aad for m in messages] == [AAD, b""]


def test_no_aad_means_no_load_aad_packet():
    _, packets = stream(16, 1, aad=b"")
    assert CMD_LOAD_AAD not in [cmd for cmd, _ in packets]


@pytest.mark.parametrize("aad", [bytes(5), bytes(256)])
def test_aad_that_the_core_cannot_take_is_rejected(aad):
    with pytest.raises(ValueError, match="AAD"):
        framing.build_tx(bytes(16), KEY, IV, aad)


def test_iv_must_be_12_bytes():
    with pytest.raises(ValueError, match="12 bytes"):
        framing.build_tx(bytes(16), KEY, bytes(8))


def test_iv_counter_overflow_is_refused_before_anything_is_sent():
    near_end = bytes(8) + b"\xff\xff\xff\xff"
    with pytest.raises(ValueError, match="overflow"):
        framing.build_tx(bytes(32), KEY, near_end, chunk_blocks=1)


def test_empty_data_is_rejected():
    with pytest.raises(ValueError, match="no data"):
        framing.build_tx(b"", KEY, IV)


@pytest.mark.parametrize("length", [1, 15, 16, 17, 240, 241, 1000])
def test_binary_data_of_any_length_survives_the_padding(length):
    data = bytes(i % 251 + 1 for i in range(length))
    _, messages = framing.split_tx(framing.build_tx(data, KEY, IV))
    assert len(messages) == framing.chunk_count(length)
    assert framing.join_chunks(layout_of(data, messages), [m.data for m in messages]) == data


def test_layout_survives_session_json(tmp_path):
    layout = framing.Layout(12288, 52, 15, 64, 64, 3)
    layout.save(tmp_path / "session.json")
    assert framing.Layout.load(tmp_path / "session.json") == layout


def test_256_square_uses_274_chunks():
    _, packets = stream(256, 256)
    _, messages = framing.split_tx(packets)
    assert len(messages) == 274


def test_missing_chunk_is_rejected():
    _, packets = stream(64, 64)
    _, messages = framing.split_tx(packets)
    with pytest.raises(ValueError, match="chunks"):
        framing.join_chunks(framing.Layout(64 * 64, len(messages), 15), [m.data for m in messages[:-1]])


def test_invalid_chunk_blocks_is_rejected():
    with pytest.raises(ValueError, match="chunk_blocks"):
        framing.build_tx(bytes(16), KEY, IV, chunk_blocks=16)


def test_fpga_error_response_is_reported():
    with pytest.raises(ValueError, match="ERR_LEN_MISMATCH"):
        framing.split_rx([(RESP_ERR_LEN, b"\x04")])


def test_txt_and_bin_hold_the_same_packets(tmp_path):
    _, packets = stream(40, 40)
    packet_file.write_stream(packets, tmp_path / "tx", "title")
    assert packet_file.read_stream(tmp_path / "tx.bin") == packets
    assert packet_file.read_stream(tmp_path / "tx.txt") == packets


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
