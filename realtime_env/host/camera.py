"""Realtime camera: the PC compresses JPEG, the IP encrypts, and the frame comes back verified."""

import bisect
import threading
import time
from dataclasses import dataclass, field
from typing import Callable, List, NamedTuple, Optional, Tuple

import cv2
import numpy as np

from . import camera_view, console, framing, gcm_model
from .camera_view import Backlog, FrameResult
from .pipeline import FrameQueue, Stages
from .protocol import MAX_DATA_BLOCKS

_STOP_WAIT_S = 5.0
_STOP_POLL_S = 0.02
_MIN_QUEUE = 2         # Lets a stage start the next frame while the one after it works
_DEFAULT_FPS = 30       # What a camera means when it reports 0
_BADGES = {None: "Phần cứng", "model": "Software model, không phải kit", "emu": "Giả lập, không phải kit"}


class ReplayCapture:
    """A video file with the read() of a camera: paced at its own fps, and restarted if asked."""

    def __init__(self, capture: "cv2.VideoCapture", realtime: bool, loop: bool):
        self._capture = capture
        self._period = 1 / (capture.get(cv2.CAP_PROP_FPS) or _DEFAULT_FPS) if realtime else 0.0
        self._loop = loop
        self._next = time.perf_counter()

    def read(self) -> Tuple[bool, Optional[np.ndarray]]:
        wait = self._next - time.perf_counter()
        if wait > 0:
            time.sleep(wait)
        self._next = max(self._next, time.perf_counter()) + self._period
        ok, frame = self._capture.read()
        if not ok and self._loop:
            self._capture.set(cv2.CAP_PROP_POS_FRAMES, 0)
            ok, frame = self._capture.read()
        return ok, frame

    def release(self) -> None:
        self._capture.release()


class LiveSource:
    """Keeps only the newest camera frame: a late frame is dropped, as a real camera would."""

    live = True

    def __init__(self, capture: "cv2.VideoCapture", fps: float = _DEFAULT_FPS):
        self._capture = capture
        self.fps = fps
        self._condition = threading.Condition()
        self._frame = None
        self._newest = None
        self._running = True
        self.dropped = 0
        self._thread = threading.Thread(target=self._grab, daemon=True)
        self._thread.start()

    def _grab(self) -> None:
        while self._running:
            ok, frame = self._capture.read()
            with self._condition:
                if not ok:
                    self._running = False
                else:
                    self.dropped += self._frame is not None
                    self._frame = self._newest = frame
                self._condition.notify()

    def read(self) -> Optional[np.ndarray]:
        with self._condition:
            while self._frame is None and self._running:
                self._condition.wait(timeout=1.0)
            frame, self._frame = self._frame, None
        return frame

    def peek(self) -> Optional[np.ndarray]:
        """The newest frame for the window, leaving it for read()."""
        return self._newest

    def close(self) -> None:
        self._running = False
        self._thread.join(timeout=2.0)
        self._capture.release()


class FileSource:
    """Plays a video file frame by frame, dropping nothing."""

    live = False
    dropped = 0

    def __init__(self, capture: "ReplayCapture"):
        self._capture = capture
        self._newest = None

    def read(self) -> Optional[np.ndarray]:
        ok, frame = self._capture.read()
        if ok:
            self._newest = frame
        return frame if ok else None

    def peek(self) -> Optional[np.ndarray]:
        return self._newest

    def close(self) -> None:
        self._capture.release()


def open_source(source: Optional[str], index: int, realtime: bool = False, loop: bool = False):
    capture = cv2.VideoCapture(source if source else index)
    if not capture.isOpened():
        raise OSError(f"Cannot open {'video ' + source if source else f'camera {index}'}")
    fps = capture.get(cv2.CAP_PROP_FPS) or _DEFAULT_FPS
    if not source:
        return LiveSource(capture, fps)
    replay = ReplayCapture(capture, realtime, loop)
    return LiveSource(replay, fps) if realtime else FileSource(replay)


def compress(frame: np.ndarray, size: Tuple[int, int], quality: int) -> bytes:
    resized = cv2.resize(frame, size, interpolation=cv2.INTER_AREA)
    ok, jpeg = cv2.imencode(".jpg", resized, [cv2.IMWRITE_JPEG_QUALITY, quality])
    if not ok:
        raise ValueError("JPEG compression failed")
    return jpeg.tobytes()


def decrypt_on_pc(key: bytes, messages: List[framing.Message], encrypted: List[framing.Reply]) -> List[bytes]:
    """Decrypts in software, refusing the frame if any tag from the IP does not check out."""
    chunks = []
    for index, (message, reply) in enumerate(zip(messages, encrypted)):
        data = gcm_model.open_message(key, message.iv, message.aad, reply.data, reply.tag)
        if data is None:
            raise framing.TagMismatch([index])
        chunks.append(data)
    return chunks


class Recent(NamedTuple):
    fps: float
    rtt_p95: Optional[float]  # None when no frame finished in that time


@dataclass
class Stats:
    started: float = field(default_factory=time.perf_counter)
    frames: int = 0
    frame_bytes: int = 0
    wire_bytes: int = 0
    failed: int = 0
    dropped: int = 0
    marks: List[Tuple[float, float]] = field(default_factory=list)  # (finished, ms). Only ever appended, so the window reads it unlocked

    ended: float = 0.0  # Set with the last frame: the window may go on showing what it holds

    @property
    def elapsed(self) -> float:
        return max((self.ended or time.perf_counter()) - self.started, 1e-9)

    @property
    def fps(self) -> float:
        return self.frames / self.elapsed

    @property
    def wire_kbs(self) -> float:
        return self.wire_bytes / 1024 / self.elapsed

    @property
    def round_trips_ms(self) -> List[float]:
        return [milliseconds for _, milliseconds in self.marks]

    def rtt_percentile(self, percent: int) -> float:
        return float(np.percentile(self.round_trips_ms, percent)) if self.marks else 0.0

    def record(self, milliseconds: float) -> None:
        self.marks.append((time.perf_counter(), milliseconds))

    def recent(self, seconds: float) -> Recent:
        """The last `seconds` only, for the window: a slow patch must show at once."""
        first = bisect.bisect_left(self.marks, (time.perf_counter() - seconds,))
        latest = [milliseconds for _, milliseconds in self.marks[first:]]
        return Recent(len(latest) / min(seconds, self.elapsed), float(np.percentile(latest, 95)) if latest else None)


def decrypt_on_fpga(key: bytes, messages: List[framing.Message], encrypted: List[framing.Reply], channel,
                    stats: Stats) -> List[bytes]:
    expected = [reply.tag for reply in encrypted]
    packets = framing.build_decrypt_tx(key, messages, [reply.data for reply in encrypted], expected)
    responses = channel.exchange(packets, "camera_dec").responses
    stats.wire_bytes += framing.wire_bytes(packets) + framing.wire_bytes(responses)
    decrypted = framing.split_rx(responses)
    framing.check_replies(expected, decrypted)
    return [reply.data for reply in decrypted]


def report_summary(stats: Stats, where: str, channel, report: console.Report) -> None:
    report.section("TỔNG KẾT", where)
    report.field("Khung", f"{stats.frames} khung, {stats.failed} khung lỗi tag, {stats.dropped} khung bỏ")
    report.field("Tốc độ", f"{stats.fps:.1f} fps, {stats.wire_kbs:.0f} KB/s trên đường truyền")
    if stats.frames:
        report.field("Kích thước", f"{stats.frame_bytes / stats.frames / 1024:.1f} KB/khung JPEG")
    report.field("RTT", f"trung bình {np.mean(stats.round_trips_ms or [0]):.1f} ms, p95 {stats.rtt_percentile(95):.1f} ms")
    late = getattr(channel, "late", 0)
    if late:
        report.field("Giả lập", f"{late} burst trễ hơn lịch: máy tính chậm hơn đường truyền đang giả lập", "fail")


@dataclass
class Compressed:
    jpeg: bytes
    captured_at: float


@dataclass
class Encrypted:
    frame: Compressed
    key: bytes
    messages: List[framing.Message]
    replies: List[framing.Reply]
    chunks: Optional[List[bytes]] = None  # Set by the link stage when the IP decrypted the frame


class FrameStream:
    """Compresses, sends and decrypts on three threads, so a frame costs only the slowest of them.

    With a live source nothing goes to the IP until `buffer_frames` wait to be sent. The IP then
    falls behind the camera by that much, and a late frame leaves the oldest one out of the queue.
    """

    def __init__(self, args, secrets, channel, source, stats: Stats, publish: Callable[[FrameResult], None]):
        self._args, self._secrets, self._channel = args, secrets, channel
        self._source, self._stats, self._publish = source, stats, publish
        self.preroll = args.buffer_frames if source.live else 0
        self._outgoing = FrameQueue(max(2 * self.preroll, _MIN_QUEUE), drop_oldest=source.live)
        self._returned = FrameQueue(_MIN_QUEUE, drop_oldest=False)
        self._stages = Stages([self._compress_stage, self._link_stage, self._decrypt_stage], self.stop)

    @property
    def dropped(self) -> int:
        # The camera keeps overwriting frames after the last one was taken: those were never due
        return self._stats.dropped if self._stats.ended else self._source.dropped + self._outgoing.dropped

    def backlog(self) -> Optional[Backlog]:
        return Backlog(len(self._outgoing), self._outgoing.capacity, self.preroll) if self.preroll else None

    def _compress_stage(self) -> None:
        while not self._outgoing.closed:
            frame = self._source.read()
            if frame is None:
                break
            captured_at = time.perf_counter()
            self._outgoing.put(Compressed(compress(frame, self._args.size, self._args.quality), captured_at))
        self._outgoing.close()

    def _link_stage(self) -> None:
        args, secrets = self._args, self._secrets
        iv = secrets.iv
        sent = 0
        self._outgoing.wait_until_holding(self.preroll)
        self._stats.started = time.perf_counter()  # Filling the buffer is not processing
        while not args.frames or sent < args.frames:
            frame = self._outgoing.get()
            if frame is None:
                break
            packets = framing.build_tx(frame.jpeg, secrets.key, iv, secrets.aad)  # Here, so a dropped frame uses no IV
            key, messages = framing.split_tx(packets)
            responses = self._channel.exchange(packets, "camera").responses
            self._stats.wire_bytes += framing.wire_bytes(packets) + framing.wire_bytes(responses)
            iv = framing.advance_iv(iv, len(messages))  # Stays unique across frames
            sent += 1
            if args.tamper_every and sent % args.tamper_every == 0:
                responses = framing.flip_ciphertext(responses, 0)
            encrypted = Encrypted(frame, key, messages, framing.split_rx(responses))
            if args.fpga_decrypt:  # On this thread: the link takes one exchange at a time
                encrypted.chunks = self._decrypt_in_ip(encrypted)
            self._returned.put(encrypted)
        self._outgoing.abort()
        self._returned.close()

    def _decrypt_in_ip(self, encrypted: Encrypted) -> Optional[List[bytes]]:
        try:
            return decrypt_on_fpga(encrypted.key, encrypted.messages, encrypted.replies, self._channel, self._stats)
        except framing.TagMismatch:
            return None

    def _decrypt_stage(self) -> None:
        stats = self._stats
        while True:
            encrypted = self._returned.get()
            if encrypted is None:
                break
            jpeg = encrypted.frame.jpeg
            layout = framing.Layout(len(jpeg), len(encrypted.messages), MAX_DATA_BLOCKS)
            cipher = framing.join_chunks(layout, [reply.data for reply in encrypted.replies])
            restored = self._restore(encrypted, layout)
            if restored is None:
                stats.failed += 1
            stats.record((time.perf_counter() - encrypted.frame.captured_at) * 1e3)
            stats.frames += 1
            stats.frame_bytes += len(jpeg)
            self._publish(FrameResult(stats.frames, cipher, restored, encrypted.frame.captured_at))
        stats.dropped = self.dropped
        stats.ended = time.perf_counter()

    def _restore(self, encrypted: Encrypted, layout: framing.Layout) -> Optional[bytes]:
        try:
            chunks = encrypted.chunks
            if not self._args.fpga_decrypt:
                chunks = decrypt_on_pc(encrypted.key, encrypted.messages, encrypted.replies)
        except framing.TagMismatch:
            return None
        restored = framing.join_chunks(layout, chunks) if chunks is not None else None
        return restored if restored == encrypted.frame.jpeg else None

    def start(self) -> None:
        self._stages.start()

    def alive(self) -> bool:
        return self._stages.alive()

    def stop(self) -> None:
        self._outgoing.abort()
        self._returned.abort()

    def finish(self) -> None:
        """Waits for the stages, then raises what stopped them, if anything did."""
        self._stages.join(_STOP_WAIT_S)
        if self._stages.failure:
            raise self._stages.failure


def process_frames(args, secrets, channel, source, stats: Stats, publish: Callable[[FrameResult], None]) -> None:
    """Sends every frame through the link, with no window."""
    stream = FrameStream(args, secrets, channel, source, stats, publish)
    stream.start()
    while stream.alive():
        time.sleep(_STOP_POLL_S)
    stream.finish()


def run_with_window(args, secrets, channel, source, stats: Stats, view: camera_view.View) -> None:
    """Keeps the window on the main thread, where OpenCV needs it, and the stages on theirs."""
    stream = FrameStream(args, secrets, channel, source, stats, view.publish)
    stream.start()
    view.run(source.peek, stats, lambda: stream.dropped, stream.alive, stream.backlog)
    stream.stop()
    stream.finish()


def describe_work(args) -> str:
    engine = "Software model" if args.sim else "FPGA"
    return f"{engine} mã hoá, {engine if args.fpga_decrypt else 'PC'} giải mã"


def source_name(args) -> str:
    if not args.source:
        return "Camera trực tiếp"
    return "Video thời gian thực" if args.realtime else "Video từng khung"


def open_view(args, title: str, source) -> camera_view.View:
    period = 1 / source.fps if source.live and args.buffer_frames else 0.0
    return camera_view.View(title, _BADGES[args.sim], args.size, source_name(args), period)


def run(args, secrets, channel, report: console.Report) -> int:
    source = open_source(args.source, args.camera_index, args.realtime, args.loop)
    where = describe_work(args)
    report.section("CAMERA", where)
    report.field("Nguồn", channel.label, "dim")
    report.field("Khung", f"{args.size[0]}x{args.size[1]}, JPEG q{args.quality}")
    report.field("IV đầu", secrets.iv.hex())
    if not args.no_window:
        report.line("Nhấn q, Esc hoặc nút X trên cửa sổ để dừng.", "dim")

    stats = Stats()
    try:
        if args.no_window:
            process_frames(args, secrets, channel, source, stats, lambda result: None)
        else:
            run_with_window(args, secrets, channel, source, stats,
                            open_view(args, f"{args.link}, AES-{len(secrets.key) * 8}, {where}", source))
    finally:
        source.close()
        report_summary(stats, where, channel, report)
    return 1 if stats.failed or not stats.frames else 0
