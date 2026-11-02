"""Realtime camera: the PC compresses JPEG, the IP encrypts, and the frame comes back verified."""

import bisect
import threading
import time
from dataclasses import dataclass, field
from typing import Callable, List, NamedTuple, Optional, Tuple

import cv2
import numpy as np

from . import camera_view, codec, console, framing, gcm_model, run_log
from .camera_view import Backlog, FrameResult
from .codec import compress  # noqa: F401  (kept here for callers of the JPEG path)
from .pipeline import FrameQueue, Stages
from .protocol import MAX_DATA_BLOCKS

_STOP_WAIT_S = 5.0
_STOP_POLL_S = 0.02
_MIN_QUEUE = 2         # Lets a stage start the next frame while the one after it works
BUFFER_FRAMES = 2       # Held before the first send: about 66 ms at 30 fps, enough to even out the link
_STAT_PERIOD_S = 1.0    # A STAT line in the log this often
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

    def __init__(self, capture: "cv2.VideoCapture", fps: float = _DEFAULT_FPS, limit: float = 0.0):
        self._capture = capture
        self.fps = min(fps, limit) if limit else fps
        self._period = 1 / limit if limit else 0.0
        self._next = time.perf_counter()
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
                    self.dropped += self._frame is not None and not self._period  # Under --fps it is meant
                    self._frame = self._newest = frame
                self._condition.notify()

    def read(self) -> Optional[np.ndarray]:
        wait = self._next - time.perf_counter()
        if wait > 0:
            time.sleep(wait)
        self._next = max(self._next, time.perf_counter()) + self._period
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


def open_source(source: Optional[str], index: int, realtime: bool = False, loop: bool = False, limit: float = 0.0):
    capture = cv2.VideoCapture(source if source else index)
    if not capture.isOpened():
        raise OSError(f"Cannot open {'video ' + source if source else f'camera {index}'}")
    fps = capture.get(cv2.CAP_PROP_FPS) or _DEFAULT_FPS
    if not source:
        return LiveSource(capture, fps, limit)
    replay = ReplayCapture(capture, realtime, loop)
    return LiveSource(replay, fps, limit) if realtime else FileSource(replay)


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
    mbps: float = 0.0         # Bytes sent to the IP per second, framing included, in MB/s


@dataclass
class Stats:
    started: float = field(default_factory=time.perf_counter)
    frames: int = 0
    frame_bytes: int = 0
    wire_bytes: int = 0
    failed: int = 0
    dropped: int = 0
    waiting: int = 0  # Frames that passed their tag but came while the decoder waited for a key frame
    marks: List[Tuple[float, float, int]] = field(default_factory=list)  # (finished, ms, tx bytes). Only ever appended, so the window reads it unlocked
    display_delay_s: Optional[float] = None  # Set by the window: how far the shown frame lags the camera

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
        return [mark[1] for mark in self.marks]

    @property
    def sent_mbps(self) -> float:
        return sum(mark[2] for mark in self.marks) / 1e6 / self.elapsed

    def rtt_percentile(self, percent: int) -> float:
        return float(np.percentile(self.round_trips_ms, percent)) if self.marks else 0.0

    def record(self, milliseconds: float, sent_bytes: int = 0) -> None:
        self.marks.append((time.perf_counter(), milliseconds, sent_bytes))

    def recent(self, seconds: float) -> Recent:
        """The last `seconds` only, for the window: a slow patch must show at once."""
        first = bisect.bisect_left(self.marks, (time.perf_counter() - seconds,))
        latest = self.marks[first:]
        span = min(seconds, self.elapsed)
        p95 = float(np.percentile([mark[1] for mark in latest], 95)) if latest else None
        return Recent(len(latest) / span, p95, sum(mark[2] for mark in latest) / 1e6 / span)


def decrypt_on_fpga(key: bytes, messages: List[framing.Message], encrypted: List[framing.Reply], channel,
                    stats: Stats, wire: Optional[List[int]] = None) -> List[bytes]:
    """`wire`, when given, collects the bytes sent and received, for the frame log."""
    expected = [reply.tag for reply in encrypted]
    packets = framing.build_decrypt_tx(key, messages, [reply.data for reply in encrypted], expected)
    responses = channel.exchange(packets, "camera_dec").responses
    sent, received = framing.wire_bytes(packets), framing.wire_bytes(responses)
    stats.wire_bytes += sent + received
    if wire is not None:
        wire[0] += sent
        wire[1] += received
    decrypted = framing.split_rx(responses)
    framing.check_replies(expected, decrypted)
    return [reply.data for reply in decrypted]


def report_summary(stats: Stats, where: str, channel, report: console.Report, codec_name: str = "jpeg") -> None:
    report.section("TỔNG KẾT", where)
    report.field("Khung", f"{stats.frames} khung, {stats.failed} khung lỗi tag, {stats.dropped} khung bỏ")
    if stats.waiting:
        report.field("Chờ I", f"{stats.waiting} khung đúng tag, không hiện vì đang chờ khung I sau khung lỗi")
    report.field("Tốc độ", f"{stats.fps:.1f} fps, thông lượng {stats.sent_mbps:.2f} MB/s, "
                           f"{stats.wire_kbs:.0f} KB/s cả hai chiều")
    if stats.frames:
        report.field("Kích thước", f"{stats.frame_bytes / stats.frames / 1024:.1f} KB/khung {codec_name.upper()}")
    report.field("RTT", f"trung bình {np.mean(stats.round_trips_ms or [0]):.1f} ms, p95 {stats.rtt_percentile(95):.1f} ms")
    late = getattr(channel, "late", 0)
    if late:
        report.field("Giả lập", f"{late} burst trễ hơn lịch: máy tính chậm hơn đường truyền đang giả lập", "fail")


@dataclass
class Compressed:
    data: bytes
    captured_at: float
    key_frame: bool = True
    encode_ms: float = 0.0


@dataclass
class Encrypted:
    frame: Compressed
    key: bytes
    messages: List[framing.Message]
    replies: List[framing.Reply]
    chunks: Optional[List[bytes]] = None  # Set by the link stage when the IP decrypted the frame
    link_ms: float = 0.0
    wire: List[int] = field(default_factory=lambda: [0, 0])  # Bytes sent and received for this frame


class FrameStream:
    """Compresses, sends and decrypts on three threads, so a frame costs only the slowest of them.

    With a live source nothing goes to the IP until `buffer_frames` wait to be sent. The IP then
    falls behind the camera by that much. With JPEG a late frame leaves the oldest one out of the
    queue; H.264 frames depend on each other, so there the queue waits and the camera drops instead.
    """

    def __init__(self, args, secrets, channel, source, stats: Stats, publish: Callable[[FrameResult], None]):
        self._args, self._secrets, self._channel = args, secrets, channel
        self._source, self._stats, self._publish = source, stats, publish
        self.encoder, self._decoder, self.codec_note = codec.open_codec(
            getattr(args, "codec", "jpeg"), args.size, args.quality, getattr(source, "fps", 0) or 30)
        self.preroll = getattr(args, "buffer_frames", BUFFER_FRAMES) if source.live else 0
        drop = source.live and self.encoder.drops_allowed
        self._outgoing = FrameQueue(max(2 * self.preroll, _MIN_QUEUE), drop_oldest=drop)
        self._returned = FrameQueue(_MIN_QUEUE, drop_oldest=False)
        self._stages = Stages([self._compress_stage, self._link_stage, self._decrypt_stage], self.stop)
        self._waiting_key = False
        self._stat_at = 0.0

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
            encoded = self.encoder.encode(frame)
            if encoded is None:  # The encoder holds this frame back; never with zerolatency
                continue
            self._outgoing.put(Compressed(encoded.data, captured_at, encoded.key_frame, encoded.encode_ms))
        self._outgoing.close()

    def _link_stage(self) -> None:
        args, secrets = self._args, self._secrets
        iv = secrets.iv
        sent = 0
        if self.preroll:
            run_log.event("buffer", f"chờ đủ {self.preroll} khung")
        self._outgoing.wait_until_holding(self.preroll)
        if self.preroll:
            run_log.event("buffer", f"đủ {self.preroll} khung, bắt đầu truyền")
        self._stats.started = time.perf_counter()  # Filling the buffer is not processing
        self._stat_at = self._stats.started
        while not args.frames or sent < args.frames:
            frame = self._outgoing.get()
            if frame is None:
                break
            packets = framing.build_tx(frame.data, secrets.key, iv, secrets.aad)  # Here, so a dropped frame uses no IV
            key, messages = framing.split_tx(packets)
            started = time.perf_counter()
            responses = self._channel.exchange(packets, "camera").responses
            link_ms = (time.perf_counter() - started) * 1e3
            wire = [framing.wire_bytes(packets), framing.wire_bytes(responses)]
            self._stats.wire_bytes += wire[0] + wire[1]
            iv = framing.advance_iv(iv, len(messages))  # Stays unique across frames
            sent += 1
            if args.tamper_every and sent % args.tamper_every == 0:
                responses = framing.flip_ciphertext(responses, 0)
            encrypted = Encrypted(frame, key, messages, framing.split_rx(responses), link_ms=link_ms, wire=wire)
            if args.fpga_decrypt:  # On this thread: the link takes one exchange at a time
                started = time.perf_counter()
                encrypted.chunks = self._decrypt_in_ip(encrypted)
                encrypted.link_ms += (time.perf_counter() - started) * 1e3
            self._returned.put(encrypted)
        self._outgoing.abort()
        self._returned.close()

    def _decrypt_in_ip(self, encrypted: Encrypted) -> Optional[List[bytes]]:
        try:
            return decrypt_on_fpga(encrypted.key, encrypted.messages, encrypted.replies, self._channel, self._stats,
                                   encrypted.wire)
        except framing.TagMismatch:
            return None

    def _decrypt_stage(self) -> None:
        stats = self._stats
        while True:
            encrypted = self._returned.get()
            if encrypted is None:
                break
            frame = encrypted.frame
            layout = framing.Layout(len(frame.data), len(encrypted.messages), MAX_DATA_BLOCKS)
            cipher = framing.join_chunks(layout, [reply.data for reply in encrypted.replies])
            restored = self._restore(encrypted, layout)
            picture, decode_ms, tag = None, 0.0, "PASS"
            if restored is None:
                tag = "FAIL"
                stats.failed += 1
                run_log.event("tag", f"khung {stats.frames + 1}: TAG FAIL, không hiển thị plaintext")
                if not self.encoder.drops_allowed:
                    self._waiting_key = True
                    self.encoder.request_key_frame()
            elif self._waiting_key and not frame.key_frame:
                tag = "PASS, chờ khung I"
                stats.waiting += 1
            else:
                if self._waiting_key:
                    run_log.event("codec", f"khung {stats.frames + 1}: khung I, hình hiện lại")
                self._waiting_key = False
                started = time.perf_counter()
                picture = self._decoder.decode(restored)
                decode_ms = (time.perf_counter() - started) * 1e3
            latency_ms = (time.perf_counter() - frame.captured_at) * 1e3
            stats.record(latency_ms, encrypted.wire[0])
            stats.frames += 1
            stats.frame_bytes += len(frame.data)
            self._log_frame(encrypted, layout, tag, decode_ms, latency_ms)
            self._publish(FrameResult(stats.frames, cipher, restored, frame.captured_at, picture, frame.key_frame,
                                      waiting=restored is not None and picture is None))
        stats.dropped = self.dropped
        stats.ended = time.perf_counter()

    def _log_frame(self, encrypted: Encrypted, layout: framing.Layout, tag: str, decode_ms: float,
                   latency_ms: float) -> None:
        if run_log.active() is None:
            return
        stats, frame = self._stats, encrypted.frame
        link_s = max(encrypted.link_ms / 1e3, 1e-9)
        run_log.frame({
            "frame": stats.frames, "type": "I" if frame.key_frame else "P",
            "t_capture_s": round(frame.captured_at - stats.started, 3), "encoded_bytes": len(frame.data),
            "chunks": layout.chunks, "tx_bytes": encrypted.wire[0], "rx_bytes": encrypted.wire[1],
            "encode_ms": round(frame.encode_ms, 2), "link_ms": round(encrypted.link_ms, 2),
            "decode_ms": round(decode_ms, 2), "latency_ms": round(latency_ms, 1),
            "link_mbps": round(encrypted.wire[0] / link_s / 1e6, 3), "tag": tag, "dropped_total": self.dropped})
        now = time.perf_counter()
        if now - self._stat_at >= _STAT_PERIOD_S:
            self._stat_at = now
            recent = stats.recent(_STAT_PERIOD_S)
            shown = "" if stats.display_delay_s is None else f" | trễ hiển thị {stats.display_delay_s:.2f} s"
            p95 = "--" if recent.rtt_p95 is None else f"{recent.rtt_p95:.1f} ms"
            run_log.stat("1s", f"{recent.fps:.1f} fps | {recent.mbps:.3f} MB/s | p95 {p95} | lỗi tag {stats.failed} | "
                               f"bỏ {self.dropped} | hàng đợi {len(self._outgoing)}/{self._outgoing.capacity}{shown}")

    def _restore(self, encrypted: Encrypted, layout: framing.Layout) -> Optional[bytes]:
        try:
            chunks = encrypted.chunks
            if not self._args.fpga_decrypt:
                chunks = decrypt_on_pc(encrypted.key, encrypted.messages, encrypted.replies)
        except framing.TagMismatch:
            return None
        restored = framing.join_chunks(layout, chunks) if chunks is not None else None
        return restored if restored == encrypted.frame.data else None

    def start(self) -> None:
        if self.codec_note:
            run_log.event("codec", self.codec_note)
        self._stages.start()

    def alive(self) -> bool:
        return self._stages.alive()

    def stop(self) -> None:
        self._outgoing.abort()
        self._returned.abort()

    def finish(self) -> None:
        """Waits for the stages, then raises what stopped them, if anything did."""
        self._stages.join(_STOP_WAIT_S)
        self.encoder.close()
        if self._stages.failure:
            raise self._stages.failure


def process_frames(args, secrets, channel, source, stats: Stats, publish: Callable[[FrameResult], None]) -> FrameStream:
    """Sends every frame through the link, with no window."""
    stream = FrameStream(args, secrets, channel, source, stats, publish)
    stream.start()
    while stream.alive():
        time.sleep(_STOP_POLL_S)
    stream.finish()
    return stream


def run_with_window(args, secrets, channel, source, stats: Stats, view: camera_view.View) -> FrameStream:
    """Keeps the window on the main thread, where OpenCV needs it, and the stages on theirs."""
    stream = FrameStream(args, secrets, channel, source, stats, view.publish)
    stream.start()
    view.run(source.peek, stats, lambda: stream.dropped, stream.alive, stream.backlog)
    if stream.alive():
        run_log.event("stop", "người dùng đóng cửa sổ")
    stream.stop()
    stream.finish()
    return stream


def describe_work(args) -> str:
    engine = "Software model" if args.sim else "FPGA"
    return f"{engine} mã hoá, {engine if args.fpga_decrypt else 'PC'} giải mã"


def source_name(args) -> str:
    if not args.source:
        return "Camera trực tiếp"
    return "Video thời gian thực" if args.realtime else "Video từng khung"


def open_view(args, title: str, source) -> camera_view.View:
    buffered = getattr(args, "buffer_frames", BUFFER_FRAMES)
    period = 1 / source.fps if source.live and buffered else 0.0
    return camera_view.View(title, _BADGES[args.sim], args.size, source_name(args), period)


def run(args, secrets, channel, report: console.Report) -> int:
    source = open_source(args.source, args.camera_index, args.realtime, args.loop, args.fps)
    rate = f", {source.fps:.1f} fps" if getattr(source, "fps", 0) else ""
    run_log.event("camera", f"{source_name(args)}: {args.source or f'camera {args.camera_index}'}{rate}")
    where = describe_work(args)
    wanted = getattr(args, "codec", "jpeg")
    report.section("CAMERA", where)
    report.field("Nguồn", channel.label, "dim")
    quality = f"CRF {codec.crf_of(args.quality)}" if wanted == "h264" else f"q{args.quality}"
    report.field("Khung", f"{args.size[0]}x{args.size[1]}, {wanted.upper()} chất lượng {args.quality} ({quality})")
    report.field("IV đầu", secrets.iv.hex())
    if not args.no_window:
        report.line("Nhấn q, Esc hoặc nút X trên cửa sổ để dừng.", "dim")

    stats = Stats()
    used = wanted
    try:
        if args.no_window:
            stream = process_frames(args, secrets, channel, source, stats, lambda result: None)
        else:
            title = f"{args.link}, AES-{len(secrets.key) * 8}, {where}, {wanted.upper()}"
            stream = run_with_window(args, secrets, channel, source, stats, open_view(args, title, source))
        used = stream.encoder.name
        if stream.codec_note:
            report.line(f"[!] {stream.codec_note}", "fail")
    finally:
        source.close()
        report_summary(stats, where, channel, report, used)
    run_log.event("stop", f"{stats.frames} khung, {stats.failed} lỗi tag, {stats.dropped} bỏ")
    return 1 if stats.failed or not stats.frames else 0
