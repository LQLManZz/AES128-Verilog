"""The queues, and the three stages of the camera running against the software model."""

import threading
import time

import pytest

cv2 = pytest.importorskip("cv2")
import numpy as np  # noqa: E402

from host import camera, links  # noqa: E402
from host.pipeline import FrameQueue, Stages  # noqa: E402

KEY = bytes(range(32))
IV = bytes(range(12))
SIZE = (64, 48)
LIMIT_S = 5.0


class Secrets:
    key, iv, aad = KEY, IV, b""


def arguments(buffer_frames=0, frames=0, fpga_decrypt=False, tamper_every=0):
    class Args:
        size, quality = SIZE, 50

    Args.buffer_frames, Args.frames = buffer_frames, frames
    Args.fpga_decrypt, Args.tamper_every = fpga_decrypt, tamper_every
    return Args


class Frames:
    """A source with a fixed number of frames, each a different gray."""

    fps = 30

    def __init__(self, count, live=True, pause_s=0.0):
        self.live = live
        self.dropped = 0
        self._left = list(range(count))
        self._pause_s = pause_s

    def read(self):
        if self._pause_s:
            time.sleep(self._pause_s)
        return np.full((SIZE[1], SIZE[0], 3), self._left.pop(0) * 2, dtype=np.uint8) if self._left else None


class Recording(links.ModelChannel):
    def __init__(self, delay_s=0.0, fails_at=None):
        self.exchanges = []
        self.seen_when_sending = []
        self._delay_s = delay_s
        self._fails_at = fails_at
        self.stream = None

    def exchange(self, packets, name="", on_chunk=None):
        backlog = self.stream.backlog()
        self.seen_when_sending.append(backlog.waiting if backlog else 0)
        self.exchanges.append(packets)
        if len(self.exchanges) == self._fails_at:
            raise TimeoutError("link lost")
        time.sleep(self._delay_s)
        return super().exchange(packets, name, on_chunk)


def stream_of(args, channel, source, stats, results):
    stream = camera.FrameStream(args, Secrets, channel, source, stats, results.append)
    channel.stream = stream
    stream.start()
    deadline = time.perf_counter() + LIMIT_S
    while stream.alive() and time.perf_counter() < deadline:
        time.sleep(0.005)
    assert not stream.alive()
    stream.finish()
    return stream


def test_a_full_queue_drops_its_oldest_item():
    queue = FrameQueue(2, drop_oldest=True)
    for item in "abc":
        queue.put(item)
    assert queue.dropped == 1 and queue.get() == "b" and queue.get() == "c"


def test_a_full_blocking_queue_waits_and_loses_nothing():
    queue = FrameQueue(1, drop_oldest=False)
    queue.put("a")
    writer = threading.Thread(target=queue.put, args=("b",))
    writer.start()
    time.sleep(0.05)
    assert writer.is_alive()
    assert queue.get() == "a"
    writer.join(timeout=LIMIT_S)
    assert queue.get() == "b" and queue.dropped == 0


def test_a_closed_queue_still_gives_what_it_holds():
    queue = FrameQueue(2, drop_oldest=False)
    queue.put("a")
    queue.close()
    queue.put("b")
    assert queue.get() == "a" and queue.get() is None


def test_abort_frees_a_waiting_writer_and_empties_the_queue():
    queue = FrameQueue(1, drop_oldest=False)
    queue.put("a")
    writer = threading.Thread(target=queue.put, args=("b",))
    writer.start()
    queue.abort()
    writer.join(timeout=LIMIT_S)
    assert not writer.is_alive() and queue.get() is None


def test_closing_releases_a_wait_for_more_items():
    queue = FrameQueue(4, drop_oldest=False)
    waiter = threading.Thread(target=queue.wait_until_holding, args=(3,))
    waiter.start()
    queue.close()
    waiter.join(timeout=LIMIT_S)
    assert not waiter.is_alive()


def test_the_first_error_stops_the_other_stages():
    stop = threading.Event()

    def broken():
        raise ValueError("first")

    stages = Stages([broken, stop.wait], stop.set)
    stages.start()
    stages.join(LIMIT_S)
    assert not stages.alive() and str(stages.failure) == "first"


def test_nothing_is_sent_until_the_buffer_is_full():
    channel, results = Recording(), []
    stream_of(arguments(buffer_frames=4), channel, Frames(6, pause_s=0.005), camera.Stats(), results)
    assert channel.seen_when_sending[0] >= 3  # The first frame already left the queue
    assert len(results) == 6


def test_a_clip_shorter_than_the_buffer_is_still_sent():
    results = []
    stream_of(arguments(buffer_frames=10), Recording(), Frames(3), camera.Stats(), results)
    assert len(results) == 3


def test_frames_keep_their_order():
    results = []
    stream_of(arguments(), Recording(), Frames(8, live=False), camera.Stats(), results)
    assert [result.number for result in results] == list(range(1, 9))
    means = [cv2.imdecode(np.frombuffer(result.jpeg, np.uint8), cv2.IMREAD_GRAYSCALE).mean() for result in results]
    assert means == sorted(means)


def test_a_slow_link_loses_the_oldest_frames_of_a_live_source():
    stats, results = camera.Stats(), []
    stream = stream_of(arguments(buffer_frames=1), Recording(delay_s=0.03), Frames(12), stats, results)
    assert stream.dropped > 0 and stats.dropped == stream.dropped
    assert len(results) + stream.dropped == 12


def test_a_slow_link_loses_nothing_of_a_file():
    results = []
    stream = stream_of(arguments(buffer_frames=1), Recording(delay_s=0.01), Frames(6, live=False), camera.Stats(), results)
    assert stream.dropped == 0 and len(results) == 6


def test_dropped_frames_use_no_iv_and_no_iv_repeats():
    channel = Recording(delay_s=0.02)
    stream_of(arguments(buffer_frames=1), channel, Frames(12), camera.Stats(), [])
    ivs = [payload for packets in channel.exchanges for cmd, payload in packets if cmd == 0x02]
    assert len(ivs) == len(set(ivs))
    counters = [int.from_bytes(iv[8:], "big") for iv in ivs]
    assert counters == list(range(counters[0], counters[0] + len(counters)))


def test_tamper_counts_the_frames_sent():
    stats, results = camera.Stats(), []
    stream_of(arguments(tamper_every=2), Recording(), Frames(6, live=False), stats, results)
    assert [result.jpeg is None for result in results] == [False, True] * 3 and stats.failed == 3


def test_frame_limit_stops_a_source_that_never_ends():
    class Endless(Frames):
        def read(self):
            return np.zeros((SIZE[1], SIZE[0], 3), dtype=np.uint8)

    results = []
    stream_of(arguments(frames=4), Recording(), Endless(0, live=False), camera.Stats(), results)
    assert len(results) == 4


@pytest.mark.parametrize("fpga_decrypt", (False, True))
def test_an_error_on_the_link_ends_every_stage(fpga_decrypt):
    channel = Recording(fails_at=3)
    stream = camera.FrameStream(arguments(fpga_decrypt=fpga_decrypt), Secrets, channel, Frames(50, live=False),
                                camera.Stats(), lambda result: None)
    channel.stream = stream
    stream.start()
    deadline = time.perf_counter() + LIMIT_S
    while stream.alive() and time.perf_counter() < deadline:
        time.sleep(0.005)
    assert not stream.alive()
    with pytest.raises(TimeoutError, match="link lost"):
        stream.finish()


def test_stopping_frees_a_link_stage_still_filling_the_buffer():
    class Waiting(Frames):
        def read(self):
            time.sleep(0.01)
            return np.zeros((SIZE[1], SIZE[0], 3), dtype=np.uint8)

    stream = camera.FrameStream(arguments(buffer_frames=10 ** 6), Secrets, Recording(), Waiting(0),
                                camera.Stats(), lambda result: None)
    stream.start()
    stream.stop()
    stream.finish()
    assert not stream.alive()


def test_a_camera_running_on_after_the_last_frame_drops_nothing_more():
    source, stats = Frames(4, live=False), camera.Stats()
    stream = stream_of(arguments(frames=4), Recording(), source, stats, [])
    source.dropped = 50  # What LiveSource counts while the window shows out its buffer
    assert stream.dropped == stats.dropped == 0


def test_filling_the_buffer_does_not_count_as_processing():
    stats = camera.Stats()
    stream_of(arguments(buffer_frames=3), Recording(), Frames(3, pause_s=0.1), stats, [])
    assert stats.elapsed < 0.2


def test_results_carry_when_the_frame_was_captured():
    before = time.perf_counter()
    results = []
    stream_of(arguments(), Recording(), Frames(1, live=False), camera.Stats(), results)
    assert before <= results[0].captured_at <= time.perf_counter()

