"""Compiles the pacing of esp32_bridge on the PC and feeds it the host's real packets."""

import ctypes
import shutil
import subprocess
from pathlib import Path

import pytest

from host import framing, gcm_model
from host.protocol import BURST_MESSAGES, CMD_START_DECRYPT, CMD_START_ENCRYPT, build_packet

SOURCE = Path(__file__).parents[1] / "esp32_bridge" / "src" / "pace.c"
KEY = bytes(range(32))
IV = bytes(range(12))


@pytest.fixture(scope="module")
def library(tmp_path_factory):
    compiler = shutil.which("gcc")
    if compiler is None:
        pytest.skip("gcc not found")
    target = tmp_path_factory.mktemp("pace") / "pace.dll"
    subprocess.run([compiler, "-shared", "-O1", "-Wall", "-Werror", "-o", str(target), str(SOURCE)], check=True)
    loaded = ctypes.CDLL(str(target))
    loaded.pace_outgoing.restype = ctypes.c_size_t
    loaded.pace_outgoing.argtypes = (ctypes.c_void_p, ctypes.c_char_p, ctypes.c_size_t)
    loaded.pace_reply.argtypes = (ctypes.c_void_p, ctypes.c_ubyte)
    loaded.pace_blocked.restype = ctypes.c_bool
    loaded.pace_awaiting.restype = ctypes.c_bool
    return loaded


class Pace:
    def __init__(self, library):
        self._library = library
        self._state = ctypes.create_string_buffer(64)
        library.pace_reset(self._state)

    def offer(self, data):
        return self._library.pace_outgoing(self._state, data, len(data))

    def reply(self, cmd):
        self._library.pace_reply(self._state, cmd)

    @property
    def blocked(self):
        return self._library.pace_blocked(self._state)

    @property
    def awaiting(self):
        return self._library.pace_awaiting(self._state)


@pytest.fixture
def pace(library):
    return Pace(library)


def stream(packets):
    return b"".join(build_packet(cmd, payload) for cmd, payload in packets)


def encrypt_packets(chunks):
    return framing.build_tx(bytes(240 * chunks), KEY, IV, bytes(16))


def decrypt_packets(chunks, wrong_tag=False):
    packets = encrypt_packets(chunks)
    key, messages = framing.split_tx(packets)
    replies = framing.split_rx(gcm_model.simulate(packets))
    tags = [bytes(16) if wrong_tag else reply.tag for reply in replies]
    return framing.build_decrypt_tx(key, messages, [reply.data for reply in replies], tags)


def groups_of(packets):
    return list(framing.batches(packets, BURST_MESSAGES))


def play(pace, packets, step):
    """Walks the stream as the SPI task does, and returns the bytes of each burst sent."""
    data = stream(packets)
    bursts, current, sent = [], b"", 0
    for group in groups_of(packets):
        replies = gcm_model.simulate(packets[:sent + len(group)])[len(gcm_model.simulate(packets[:sent])):]
        sent += len(group)
        size = len(stream(group))
        while len(current) < size:
            taken = pace.offer(data[:step])
            current += data[:taken]
            data = data[taken:]
        bursts.append(current)
        current = b""
        for cmd, _ in replies:
            pace.reply(cmd)
    return bursts, data


def test_bursts_are_the_same_as_the_ones_transfer_sends(pace):
    packets = encrypt_packets(BURST_MESSAGES * 2 + 5)
    bursts, left = play(pace, packets, 1 << 16)
    assert bursts == [stream(group) for group in groups_of(packets)] and not left
    assert not pace.awaiting


@pytest.mark.parametrize("step", (1, 3, 241))
def test_bytes_arriving_in_pieces_change_nothing(pace, step):
    packets = encrypt_packets(BURST_MESSAGES + 3)
    assert play(pace, packets, step)[0] == [stream(group) for group in groups_of(packets)]


def test_nothing_passes_the_end_of_a_burst(pace):
    packets = encrypt_packets(BURST_MESSAGES + 1)
    data = stream(packets)
    taken = pace.offer(data)
    assert taken == len(stream(groups_of(packets)[0]))
    assert data[taken - 2] == CMD_START_ENCRYPT
    assert pace.blocked
    assert pace.offer(data[taken:]) == 0


def test_a_burst_opens_only_after_its_last_reply(pace):
    packets = encrypt_packets(BURST_MESSAGES)
    pace.offer(stream(packets))
    replies = gcm_model.simulate(packets)
    for cmd, _ in replies[:-1]:
        pace.reply(cmd)
    assert pace.blocked and pace.awaiting
    pace.reply(replies[-1][0])
    assert not pace.blocked and not pace.awaiting


@pytest.mark.parametrize("wrong_tag", (False, True))
def test_a_decrypt_ends_with_its_verify_result(pace, wrong_tag):
    packets = decrypt_packets(BURST_MESSAGES, wrong_tag)
    assert sum(cmd == CMD_START_DECRYPT for cmd, _ in packets) == BURST_MESSAGES
    pace.offer(stream(packets))
    replies = gcm_model.simulate(packets)
    for cmd, _ in replies[:-1]:
        pace.reply(cmd)
    assert pace.blocked
    pace.reply(replies[-1][0])
    assert not pace.blocked


def test_an_error_reply_ends_its_command(pace):
    pace.offer(build_packet(0x7F))
    assert pace.awaiting
    pace.reply(0xE0)
    assert not pace.awaiting


def test_a_reply_nobody_waits_for_is_ignored(pace):
    pace.reply(0x81)
    assert not pace.awaiting and not pace.blocked


def test_a_short_stream_never_blocks(pace):
    data = stream(encrypt_packets(3))
    assert pace.offer(data) == len(data)
    assert pace.awaiting and not pace.blocked
