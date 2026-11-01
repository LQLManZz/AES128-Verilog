"""Realtime camera: the PC compresses JPEG, the IP encrypts, and the frame comes back verified."""

import threading
import time
from dataclasses import dataclass, field
from typing import Callable, List, Optional, Tuple

import cv2
import numpy as np

from . import camera_view, console, framing, gcm_model
from .camera_view import FrameResult
from .protocol import MAX_DATA_BLOCKS

_STOP_WAIT_S = 5.0
_BADGES = {None: "Phần cứng", "model": "Software model, không phải kit", "emu": "Giả lập, không phải kit"}


class ReplayCapture:
    """A video file with the read() of a camera: paced at its own fps, and restarted if asked."""

    def __init__(self, capture: "cv2.VideoCapture", realtime: bool, loop: bool):
        self._capture = capture
        self._period = 1 / (capture.get(cv2.CAP_PROP_FPS) or 30) if realtime else 0.0
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

    def __init__(self, capture: "cv2.VideoCapture"):
        self._capture = capture
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
    if not source:
        return LiveSource(capture)
    replay = ReplayCapture(capture, realtime, loop)
    return LiveSource(replay) if realtime else FileSource(replay)


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


@dataclass
class Stats:
    started: float = field(default_factory=time.perf_counter)
    frames: int = 0
    frame_bytes: int = 0
    wire_bytes: int = 0
    failed: int = 0
    round_trips_ms: List[float] = field(default_factory=list)

    @property
    def elapsed(self) -> float:
        return max(time.perf_counter() - self.started, 1e-9)

    @property
    def fps(self) -> float:
        return self.frames / self.elapsed

    @property
    def wire_kbs(self) -> float:
        return self.wire_bytes / 1024 / self.elapsed

    def rtt_percentile(self, percent: int) -> float:
        return float(np.percentile(self.round_trips_ms, percent)) if self.round_trips_ms else 0.0


def decrypt_on_fpga(key: bytes, messages: List[framing.Message], encrypted: List[framing.Reply], channel,
                    stats: Stats) -> List[bytes]:
    expected = [reply.tag for reply in encrypted]
    packets = framing.build_decrypt_tx(key, messages, [reply.data for reply in encrypted], expected)
    responses = channel.exchange(packets, "camera_dec").responses
    stats.wire_bytes += framing.wire_bytes(packets) + framing.wire_bytes(responses)
    decrypted = framing.split_rx(responses)
    framing.check_replies(expected, decrypted)
    return [reply.data for reply in decrypted]


def report_summary(stats: Stats, source, where: str, channel, report: console.Report) -> None:
    report.section("TỔNG KẾT", where)
    report.field("Khung", f"{stats.frames} khung, {stats.failed} khung lỗi tag, {source.dropped} khung bỏ")
    report.field("Tốc độ", f"{stats.fps:.1f} fps, {stats.wire_kbs:.0f} KB/s trên đường truyền")
    if stats.frames:
        report.field("Kích thước", f"{stats.frame_bytes / stats.frames / 1024:.1f} KB/khung JPEG")
    report.field("RTT", f"trung bình {np.mean(stats.round_trips_ms or [0]):.1f} ms, p95 {stats.rtt_percentile(95):.1f} ms")
    late = getattr(channel, "late", 0)
    if late:
        report.field("Giả lập", f"{late} burst trễ hơn lịch: máy tính chậm hơn đường truyền đang giả lập", "fail")


def process_frames(args, secrets, channel, source, stats: Stats, publish: Callable[[FrameResult], None],
                   stopped: Callable[[], bool]) -> None:
    """Sends every frame through the link. Runs on its own thread when there is a window."""
    iv = secrets.iv
    while not stopped() and (not args.frames or stats.frames < args.frames):
        frame = source.read()
        if frame is None:
            break
        started = time.perf_counter()
        jpeg = compress(frame, args.size, args.quality)
        packets = framing.build_tx(jpeg, secrets.key, iv, secrets.aad)
        key, messages = framing.split_tx(packets)
        responses = channel.exchange(packets, "camera").responses
        stats.wire_bytes += framing.wire_bytes(packets) + framing.wire_bytes(responses)
        iv = framing.advance_iv(iv, len(messages))  # Stays unique across frames
        if args.tamper_every and (stats.frames + 1) % args.tamper_every == 0:
            responses = framing.flip_ciphertext(responses, 0)
        encrypted = framing.split_rx(responses)

        layout = framing.Layout(len(jpeg), len(messages), MAX_DATA_BLOCKS)
        cipher = framing.join_chunks(layout, [reply.data for reply in encrypted])
        try:
            if args.fpga_decrypt:
                chunks = decrypt_on_fpga(key, messages, encrypted, channel, stats)
            else:
                chunks = decrypt_on_pc(key, messages, encrypted)
            restored = framing.join_chunks(layout, chunks)
            if restored != jpeg:
                raise framing.TagMismatch([0])
        except framing.TagMismatch:
            stats.failed += 1
            restored = None

        stats.round_trips_ms.append((time.perf_counter() - started) * 1e3)
        stats.frames += 1
        stats.frame_bytes += len(jpeg)
        publish(FrameResult(stats.frames, cipher, restored))


def run_with_window(args, secrets, channel, source, stats: Stats, view: camera_view.View) -> None:
    """Keeps the window on the main thread, where OpenCV needs it, and the link on another."""
    stop = threading.Event()
    failures = []

    def work() -> None:
        try:
            process_frames(args, secrets, channel, source, stats, view.publish, stop.is_set)
        except Exception as error:  # Raised again below, on the thread that reports it
            failures.append(error)

    worker = threading.Thread(target=work, daemon=True)
    worker.start()
    view.run(source.peek, stats, lambda: source.dropped, worker.is_alive)
    stop.set()
    worker.join(timeout=_STOP_WAIT_S)
    if failures:
        raise failures[0]


def run(args, secrets, channel, report: console.Report) -> int:
    source = open_source(args.source, args.camera_index, args.realtime, args.loop)
    where = "FPGA mã hoá, FPGA giải mã" if args.fpga_decrypt else "FPGA mã hoá, PC giải mã"
    report.section("CAMERA", where)
    report.field("Nguồn", channel.label, "dim")
    report.field("Khung", f"{args.size[0]}x{args.size[1]}, JPEG q{args.quality}")
    report.field("IV đầu", secrets.iv.hex())
    if not args.no_window:
        report.line("Nhấn q, Esc hoặc nút X trên cửa sổ để dừng.", "dim")

    stats = Stats()
    try:
        if args.no_window:
            process_frames(args, secrets, channel, source, stats, lambda result: None, lambda: False)
        else:
            title = f"{args.link}, AES-{len(secrets.key) * 8}, {where}"
            run_with_window(args, secrets, channel, source, stats, camera_view.View(title, _BADGES[args.sim], args.size))
    finally:
        source.close()
        report_summary(stats, source, where, channel, report)
    return 1 if stats.failed or not stats.frames else 0
