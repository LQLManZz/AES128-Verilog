"""Realtime camera: the PC compresses JPEG, the IP encrypts, and the frame comes back verified."""

import hmac
import threading
import time
from dataclasses import dataclass, field
from typing import List, Optional, Tuple

import cv2
import numpy as np

from . import console, framing, gcm_model
from .protocol import MAX_DATA_BLOCKS

_WINDOW = "AES-GCM realtime"
_QUIT_KEY = ord("q")
_PANEL_HEIGHT = 360
_TEXT_COLOR = (0, 255, 0)


class LiveSource:
    """Keeps only the newest camera frame: a late frame is dropped, as a real camera would."""

    def __init__(self, capture: "cv2.VideoCapture"):
        self._capture = capture
        self._condition = threading.Condition()
        self._frame = None
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
                    self._frame = frame
                self._condition.notify()

    def read(self) -> Optional[np.ndarray]:
        with self._condition:
            while self._frame is None and self._running:
                self._condition.wait(timeout=1.0)
            frame, self._frame = self._frame, None
        return frame

    def close(self) -> None:
        self._running = False
        self._thread.join(timeout=2.0)
        self._capture.release()


class FileSource:
    """Plays a video file frame by frame, dropping nothing."""

    dropped = 0

    def __init__(self, capture: "cv2.VideoCapture"):
        self._capture = capture

    def read(self) -> Optional[np.ndarray]:
        ok, frame = self._capture.read()
        return frame if ok else None

    def close(self) -> None:
        self._capture.release()


def open_source(source: Optional[str], index: int):
    capture = cv2.VideoCapture(source if source else index)
    if not capture.isOpened():
        raise OSError(f"Cannot open {'video ' + source if source else f'camera {index}'}")
    return FileSource(capture) if source else LiveSource(capture)


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
        data, tag = gcm_model.run_message(key, message.iv, message.aad, reply.data, decrypt=True)
        if not hmac.compare_digest(tag, reply.tag):
            raise framing.TagMismatch([index])
        chunks.append(data)
    return chunks


def decrypt_on_fpga(key: bytes, messages: List[framing.Message], encrypted: List[framing.Reply], channel) -> List[bytes]:
    expected = [reply.tag for reply in encrypted]
    packets = framing.build_decrypt_tx(key, messages, [reply.data for reply in encrypted], expected)
    decrypted = framing.split_rx(channel.exchange(packets, "camera_dec").responses)
    framing.check_replies(expected, decrypted)
    return [reply.data for reply in decrypted]


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


def cipher_panel(cipher: bytes, height: int) -> np.ndarray:
    """Shows the ciphertext as noise, the way the link sees it."""
    side = max(int(len(cipher) ** 0.5), 1)
    noise = np.frombuffer(cipher[:side * side], dtype=np.uint8).reshape(side, side)
    return cv2.cvtColor(cv2.resize(noise, (height, height), interpolation=cv2.INTER_NEAREST), cv2.COLOR_GRAY2BGR)


def scaled(frame: np.ndarray, height: int) -> np.ndarray:
    return cv2.resize(frame, (frame.shape[1] * height // frame.shape[0], height), interpolation=cv2.INTER_AREA)


def show(original: np.ndarray, cipher: bytes, jpeg: bytes, stats: Stats) -> bool:
    """Draws one frame. Returns False when the user asks to stop."""
    plain = cv2.imdecode(np.frombuffer(jpeg, dtype=np.uint8), cv2.IMREAD_COLOR)
    panels = [scaled(original, _PANEL_HEIGHT), cipher_panel(cipher, _PANEL_HEIGHT), scaled(plain, _PANEL_HEIGHT)]
    view = np.hstack(panels)
    text = (f"{stats.fps:.1f} fps  {stats.wire_kbs:.0f} KB/s  RTT p95 {stats.rtt_percentile(95):.0f} ms  "
            f"tag FAIL {stats.failed}")
    cv2.putText(view, text, (10, 24), cv2.FONT_HERSHEY_SIMPLEX, 0.6, _TEXT_COLOR, 2)
    cv2.imshow(_WINDOW, view)
    return (cv2.waitKey(1) & 0xFF) != _QUIT_KEY


def report_summary(stats: Stats, source, where: str, report: console.Report) -> None:
    report.section("TỔNG KẾT", where)
    report.field("Khung", f"{stats.frames} khung, {stats.failed} khung lỗi tag, {source.dropped} khung bỏ")
    report.field("Tốc độ", f"{stats.fps:.1f} fps, {stats.wire_kbs:.0f} KB/s trên đường truyền")
    if stats.frames:
        report.field("Kích thước", f"{stats.frame_bytes / stats.frames / 1024:.1f} KB/khung JPEG")
    report.field("RTT", f"trung bình {np.mean(stats.round_trips_ms or [0]):.1f} ms, p95 {stats.rtt_percentile(95):.1f} ms")


def run(args, secrets, channel, report: console.Report) -> int:
    source = open_source(args.source, args.camera_index)
    where = "FPGA mã hoá, FPGA giải mã" if args.fpga_decrypt else "FPGA mã hoá, PC giải mã"
    report.section("CAMERA", where)
    report.field("Nguồn", channel.label, "dim")
    report.field("Khung", f"{args.size[0]}x{args.size[1]}, JPEG q{args.quality}")
    report.field("IV đầu", secrets.iv.hex())
    if not args.no_window:
        report.line("Nhấn q trong cửa sổ để dừng.", "dim")

    stats = Stats()
    iv = secrets.iv
    try:
        while not args.frames or stats.frames < args.frames:
            frame = source.read()
            if frame is None:
                break
            jpeg = compress(frame, args.size, args.quality)
            started = time.perf_counter()
            packets = framing.build_tx(jpeg, secrets.key, iv, secrets.aad)
            key, messages = framing.split_tx(packets)
            result = channel.exchange(packets, "camera")
            encrypted = framing.split_rx(result.responses)
            stats.wire_bytes += framing.wire_bytes(packets) + framing.wire_bytes(result.responses)
            iv = framing.advance_iv(iv, len(messages))  # Stays unique across frames

            layout = framing.Layout(len(jpeg), len(messages), MAX_DATA_BLOCKS)
            cipher = framing.join_chunks(layout, [reply.data for reply in encrypted])
            try:
                if args.fpga_decrypt:
                    chunks = decrypt_on_fpga(key, messages, encrypted, channel)
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
            if restored and not args.no_window and not show(frame, cipher, restored, stats):
                break
    finally:
        source.close()
        if not args.no_window:
            cv2.destroyAllWindows()
        report_summary(stats, source, where, report)
    return 1 if stats.failed or not stats.frames else 0
