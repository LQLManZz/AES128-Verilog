"""The camera window: live camera, ciphertext and decrypted image side by side.

Text goes through Pillow because cv2.putText has no Vietnamese. Colors are BGR throughout, and
Pillow is only handed those arrays, so it needs no conversion.
"""

import time
from collections import deque
from dataclasses import dataclass
from typing import Callable, List, NamedTuple, Optional, Tuple

import cv2
import numpy as np
from PIL import Image, ImageDraw, ImageFont

_WINDOW = "AES-GCM realtime"
_PANEL_HEIGHT = 360
_GAP = 8
_HEADER_HEIGHT = 40
_CAPTION_HEIGHT = 26
_METRIC_HEIGHT = 62
_REDRAW_MS = 30         # About a camera's frame rate, drawing included: faster only takes CPU from the link
_TEXT_PERIOD_S = 0.25   # Redrawing text is the slow part, and numbers that change faster are unreadable
_FAIL_HOLD_S = 0.5      # One failed frame must stay on screen long enough to be seen
_RECENT_S = 3.0         # The slowest frame in use takes about 2.2 s, so the numbers never fall to 0 between frames
_QUIT_KEYS = (ord("q"), 27)
_CIPHER_TAIL = 24 * 1024  # Ciphertext bytes the middle panel shows: an H.264 frame alone fills only a few cells

_BACKGROUND = (34, 32, 30)
_CARD = (48, 45, 42)
_TEXT = (235, 235, 235)
_MUTED = (170, 165, 160)
_GOOD = (113, 204, 46)
_BAD = (74, 75, 226)
_WARN = (39, 159, 239)
_FAIL_PANEL = (29, 29, 90)

_FONTS = ("segoeui.ttf", "arial.ttf", "DejaVuSans.ttf")


def load_font(size: int):
    for name in _FONTS:
        try:
            return ImageFont.truetype(name, size)
        except OSError:
            pass
    return ImageFont.load_default(size)


@dataclass
class FrameResult:
    number: int
    cipher: bytes
    plain: Optional[bytes]  # The encoded frame, None when a tag failed: nothing of it may reach the screen
    captured_at: float = 0.0  # perf_counter() when the frame left the camera, 0 when unknown
    picture: Optional[np.ndarray] = None  # Decoded by the pipeline; None means decode `plain` as JPEG here
    key_frame: bool = True
    waiting: bool = False  # Tag passed, but H.264 waits for a key frame after an earlier failure


class Backlog(NamedTuple):
    waiting: int
    capacity: int
    preroll: int


class Playback:
    """Releases frames at the pace of the camera.

    Without it a link faster than the camera would empty the send queue, and the delay the user
    chose would melt away within seconds. A period of 0 releases everything at once.
    """

    def __init__(self, period_s: float):
        self._period = period_s
        self._frames = deque()
        self._next = 0.0
        self._restart = False

    def __len__(self) -> int:
        return len(self._frames)

    def push(self, result: FrameResult) -> None:
        self._restart = self._restart or not self._frames
        self._frames.append(result)

    def take(self, now: float) -> List[FrameResult]:
        """Only a gap in the frames restarts the beat: a slow redraw catches up, or the delay would grow."""
        if self._restart:
            self._restart = False
            self._next = max(self._next, now)
        due = []
        while self._frames and now >= self._next:
            due.append(self._frames.popleft())
            self._next += self._period
        return due


def cipher_panel(cipher: bytes, size: Tuple[int, int]) -> np.ndarray:
    """Shows the real ciphertext bytes as RGB cells, as cipher.png does for raw pixels.

    A JPEG holds far fewer bytes than the picture has pixels, so the cells are large.
    """
    width, height = size
    columns = max(int((len(cipher) / 3 * width / height) ** 0.5), 1)
    rows = max(len(cipher) // (3 * columns), 1)
    cells = np.frombuffer(cipher[:rows * columns * 3], dtype=np.uint8).reshape(rows, columns, 3)
    return cv2.resize(cells, size, interpolation=cv2.INTER_NEAREST)


class View:
    def __init__(self, title: str, badge: str, frame_size: Tuple[int, int], source_name: str, period_s: float = 0.0):
        self._title = title
        self._badge = badge
        self._source_name = source_name
        self._panel = (frame_size[0] * _PANEL_HEIGHT // frame_size[1], _PANEL_HEIGHT)
        self._width = 3 * self._panel[0] + 4 * _GAP
        self._panels_top = _HEADER_HEIGHT + _CAPTION_HEIGHT
        self._metrics_top = self._panels_top + _PANEL_HEIGHT + _GAP
        height = self._metrics_top + _METRIC_HEIGHT + _GAP
        self.canvas = np.full((height, self._width, 3), _BACKGROUND, dtype=np.uint8)
        self._fonts = {size: load_font(size) for size in (13, 15, 19, 34)}

        self._playback = Playback(period_s)
        self._shown: Optional[FrameResult] = None
        self._cipher_tail = bytearray()
        self._waiting = False
        self._cipher = self._empty_panel()
        self._plain = self._empty_panel()
        self._last_number = 0
        self._delay_s: Optional[float] = None
        self._failed_number = 0
        self._failed_until = 0.0
        self._filled = 0
        self._text_at = 0.0

    def publish(self, result: FrameResult) -> None:
        """Called by the decrypt stage."""
        self._playback.push(result)

    def _empty_panel(self) -> np.ndarray:
        return np.full((self._panel[1], self._panel[0], 3), _CARD, dtype=np.uint8)

    def _write(self, image: np.ndarray, position: Tuple[int, int], text: str, size: int, color=_TEXT, anchor="la") -> None:
        layer = Image.fromarray(image)
        ImageDraw.Draw(layer).text(position, text, font=self._fonts[size], fill=color, anchor=anchor)
        image[:] = np.asarray(layer)

    def _take_results(self, now: float) -> None:
        due = self._playback.take(now)
        if not due:
            return
        for result in due:  # A redraw may skip frames, but never a failed one
            self._cipher_tail += result.cipher
            if result.plain is None:
                self._failed_number = result.number
                self._failed_until = now + _FAIL_HOLD_S
                self._text_at = 0.0  # The numbers must not keep saying PASS beside a failed frame
        del self._cipher_tail[:-_CIPHER_TAIL]
        result = due[-1]
        self._shown = result
        self._last_number = result.number
        self._delay_s = now - result.captured_at if result.captured_at else None
        self._cipher = cipher_panel(bytes(self._cipher_tail), self._panel)
        self._waiting = result.waiting
        if result.plain is None or result.waiting:
            self._plain = None
            return
        plain = result.picture
        if plain is None:
            plain = cv2.imdecode(np.frombuffer(result.plain, dtype=np.uint8), cv2.IMREAD_COLOR)
        self._plain = cv2.resize(plain, self._panel, interpolation=cv2.INTER_AREA)

    def _buffering_panel(self, backlog: Backlog) -> np.ndarray:
        self._filled = max(self._filled, backlog.waiting)  # The queue shrinks once sending starts
        panel = self._empty_panel()
        middle = (self._panel[0] // 2, self._panel[1] // 2)
        self._write(panel, middle, f"Đang đệm {min(self._filled, backlog.preroll)}/{backlog.preroll}", 19, _MUTED, "mm")
        return panel

    def _third_panel(self, now: float) -> Tuple[np.ndarray, tuple]:
        if now >= self._failed_until and self._plain is not None:
            return self._plain, _GOOD if self._shown else _CARD
        panel = np.full((self._panel[1], self._panel[0], 3), _FAIL_PANEL, dtype=np.uint8)
        middle = (self._panel[0] // 2, self._panel[1] // 2)
        self._write(panel, (middle[0], middle[1] - 22), "TAG FAIL", 34, _TEXT, "mm")
        detail = "chờ khung I" if self._waiting and now >= self._failed_until else "không xuất plaintext"
        self._write(panel, (middle[0], middle[1] + 20), f"Khung {self._failed_number}: {detail}", 15, _TEXT, "mm")
        return panel, _BAD

    @staticmethod
    def _throughput_card(recent) -> Tuple[str, str, tuple]:
        """Bytes sent to the IP per second, framing included: UART 12 Mbaud tops out at 1.2 MB/s each way."""
        return "Thông lượng", f"{recent.mbps:.2f} MB/s", _TEXT

    def _draw_text(self, stats, dropped: int, backlog: Optional[Backlog]) -> None:
        top = self.canvas[:self._panels_top]
        top[:] = _BACKGROUND
        self._write(top, (_GAP + 4, 9), "AES-GCM realtime", 19)
        self._write(top, (self._width - _GAP - 4, 12), self._title, 15, _MUTED, "ra")
        self._write(top, (_GAP + 190, 12), self._badge, 15, _WARN)
        size_kb = len(self._shown.cipher) / 1024 if self._shown else 0
        kind = "" if self._shown is None else (" (I)" if self._shown.key_frame else " (P)")
        delay = "" if self._delay_s is None else f", trễ {self._delay_s:.2f} s"
        stats.display_delay_s = self._delay_s
        captions = (f"{self._source_name}, bỏ {dropped} khung", f"Ciphertext, khung {self._last_number}{kind}, {size_kb:.1f} KB",
                    f"Sau giải mã, khung {self._last_number}{delay}")
        for index, caption in enumerate(captions):
            self._write(top, (_GAP + index * (self._panel[0] + _GAP), _HEADER_HEIGHT + 3), caption, 15, _MUTED)

        bottom = self.canvas[self._metrics_top:]
        bottom[:] = _BACKGROUND
        recent = stats.recent(_RECENT_S)
        cards = (("Xử lý", f"{recent.fps:.1f} fps", _TEXT),
                 ("Trễ p95", "--" if recent.rtt_p95 is None else f"{recent.rtt_p95:.1f} ms", _TEXT),
                 self._throughput_card(recent),
                 ("Tag", f"{stats.failed} khung lỗi" if stats.failed else "PASS, 0 lỗi", _BAD if stats.failed else _GOOD))
        card_width = (self._width - 5 * _GAP) // 4
        for index, (label, value, color) in enumerate(cards):
            left = _GAP + index * (card_width + _GAP)
            bottom[:_METRIC_HEIGHT, left:left + card_width] = _CARD
            self._write(bottom, (left + 12, 7), label, 13, _MUTED)
            self._write(bottom, (left + 12, 27), value, 19, color)

    def compose(self, live: Optional[np.ndarray], stats, dropped: int, backlog: Optional[Backlog] = None) -> np.ndarray:
        """Draws the current state. `live` never waits for the link."""
        now = time.perf_counter()
        self._take_results(now)
        if now - self._text_at >= _TEXT_PERIOD_S:
            self._text_at = now
            self._draw_text(stats, dropped, backlog)

        first = self._empty_panel() if live is None else cv2.resize(live, self._panel, interpolation=cv2.INTER_AREA)
        second, (third, border) = self._cipher, self._third_panel(now)
        if self._shown is None and backlog is not None:
            second = third = self._buffering_panel(backlog)
        for index, panel in enumerate((first, second, third)):
            left = _GAP + index * (self._panel[0] + _GAP)
            self.canvas[self._panels_top:self._panels_top + self._panel[1], left:left + self._panel[0]] = panel
        left = _GAP + 2 * (self._panel[0] + _GAP)
        corner = (left + self._panel[0] - 1, self._panels_top + self._panel[1] - 1)
        cv2.rectangle(self.canvas, (left, self._panels_top), corner, border, 2)
        return self.canvas

    def run(self, peek: Callable, stats, dropped: Callable[[], int], running: Callable[[], bool],
            backlog: Callable[[], Optional[Backlog]] = lambda: None) -> None:
        """Runs on the main thread until the last frame is shown, or the user presses q, Esc or the X button."""
        cv2.namedWindow(_WINDOW, cv2.WINDOW_NORMAL | cv2.WINDOW_KEEPRATIO)
        cv2.resizeWindow(_WINDOW, self.canvas.shape[1], self.canvas.shape[0])
        try:
            while running() or len(self._playback):
                started = time.perf_counter()
                cv2.imshow(_WINDOW, self.compose(peek(), stats, dropped(), backlog()))
                spent_ms = (time.perf_counter() - started) * 1e3
                key = cv2.waitKey(max(_REDRAW_MS - int(spent_ms), 1)) & 0xFF
                if key in _QUIT_KEYS or cv2.getWindowProperty(_WINDOW, cv2.WND_PROP_VISIBLE) < 1:
                    break
        finally:
            cv2.destroyAllWindows()
