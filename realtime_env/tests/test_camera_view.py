"""Draws the camera window off screen and checks what each panel holds."""

import pytest

cv2 = pytest.importorskip("cv2")
import numpy as np  # noqa: E402

from host import camera, camera_view  # noqa: E402
from host.camera_view import FrameResult, View  # noqa: E402

SIZE = (64, 48)


def jpeg_of(frame):
    return cv2.imencode(".png", frame)[1].tobytes()  # Lossless, so panels can be compared exactly


def filled(blue, green, red):
    return np.full((SIZE[1], SIZE[0], 3), (blue, green, red), dtype=np.uint8)


def third_panel(view):
    top = view._panels_top + 20
    left = camera_view._GAP + 2 * (view._panel[0] + camera_view._GAP) + 20
    return view.canvas[top:top + view._panel[1] - 40, left:left + view._panel[0] - 40]


@pytest.fixture
def view():
    return View("spi40, AES-256", "Giả lập, không phải kit", SIZE)


@pytest.fixture
def stats():
    return camera.Stats()


def test_cipher_panel_shows_the_real_bytes_as_rgb_cells():
    cipher = bytes(range(256)) * 4
    panel = camera_view.cipher_panel(cipher, (160, 120))
    assert panel.shape == (120, 160, 3)
    assert panel[0, 0].tolist() == [0, 1, 2]


def test_cipher_panel_keeps_the_shape_of_the_frame():
    panel = camera_view.cipher_panel(bytes(16000), (480, 360))
    assert panel.shape == (360, 480, 3)


def test_window_starts_empty_without_a_camera_frame(view, stats):
    assert view.compose(None, stats, 0).shape == view.canvas.shape


def test_decrypted_panel_shows_what_came_back_not_the_camera(view, stats):
    view.publish(FrameResult(1, bytes(1000), jpeg_of(filled(0, 0, 200))))
    view.compose(filled(200, 0, 0), stats, 0)
    assert third_panel(view)[10, 10].tolist() == [0, 0, 200]


def test_failed_tag_shows_no_plaintext(view, stats):
    secret = (10, 200, 30)
    view.publish(FrameResult(1, bytes(1000), jpeg_of(filled(*secret))))
    view.compose(filled(*secret), stats, 0)
    view.publish(FrameResult(2, bytes(1000), None))
    view.compose(filled(*secret), stats, 0)
    panel = third_panel(view)
    assert not (panel == secret).all(axis=2).any()
    assert panel[10, 10].tolist() == list(camera_view._FAIL_PANEL)


def test_failure_stays_on_screen_after_the_next_good_frame(view, stats):
    view.publish(FrameResult(1, bytes(1000), None))
    view.compose(None, stats, 0)
    view.publish(FrameResult(2, bytes(1000), jpeg_of(filled(0, 0, 200))))
    view.compose(None, stats, 0)
    assert third_panel(view)[10, 10].tolist() == list(camera_view._FAIL_PANEL)


def test_good_frame_returns_after_the_failure_hold(view, stats, monkeypatch):
    moment = [100.0]
    monkeypatch.setattr(camera_view.time, "perf_counter", lambda: moment[0])
    view.publish(FrameResult(1, bytes(1000), None))
    view.compose(None, stats, 0)
    view.publish(FrameResult(2, bytes(1000), jpeg_of(filled(0, 0, 200))))
    view.compose(None, stats, 0)
    moment[0] += camera_view._FAIL_HOLD_S + 0.1
    view.compose(None, stats, 0)
    assert third_panel(view)[10, 10].tolist() == [0, 0, 200]


def test_vietnamese_text_is_drawn(view, stats):
    before = view.canvas.copy()
    view.compose(None, stats, 0)
    header = view.canvas[:view._panels_top]
    assert (header != before[:view._panels_top]).any()


def test_font_falls_back_when_none_is_installed(monkeypatch):
    monkeypatch.setattr(camera_view, "_FONTS", ("no-such-font.ttf",))
    assert camera_view.load_font(13) is not None


class FakeWindow:
    """Records what View.run() asks of OpenCV, on a machine with no display."""

    def __init__(self, monkeypatch, keys=(), visible=1):
        self.keys = list(keys)
        self.visible = visible
        self.shown = 0
        self.closed = False
        for name, action in (("namedWindow", lambda *_: None), ("resizeWindow", lambda *_: None),
                             ("imshow", self.imshow), ("waitKey", self.wait), ("destroyAllWindows", self.close),
                             ("getWindowProperty", lambda *_: self.visible)):
            monkeypatch.setattr(camera_view.cv2, name, action)

    def imshow(self, *_):
        self.shown += 1

    def wait(self, _):
        return self.keys.pop(0) if self.keys else -1

    def close(self):
        self.closed = True


@pytest.mark.parametrize("key", (ord("q"), 27))
def test_q_and_esc_stop_the_window(view, stats, monkeypatch, key):
    window = FakeWindow(monkeypatch, keys=(-1, key))
    view.run(lambda: None, stats, lambda: 0, lambda: True)
    assert window.shown == 2 and window.closed


def test_the_close_button_stops_the_window(view, stats, monkeypatch):
    window = FakeWindow(monkeypatch, visible=0)
    view.run(lambda: None, stats, lambda: 0, lambda: True)
    assert window.shown == 1 and window.closed


def test_the_window_closes_when_the_work_ends(view, stats, monkeypatch):
    window = FakeWindow(monkeypatch)
    view.run(lambda: None, stats, lambda: 0, lambda: False)
    assert window.shown == 0 and window.closed


def test_an_error_on_the_link_reaches_the_main_thread(view, stats, monkeypatch):
    FakeWindow(monkeypatch)

    class Source:
        dropped = 0

        def read(self):
            raise TimeoutError("link lost")

        def peek(self):
            return None

    class Args:
        frames = 0

    class Secrets:
        iv = bytes(12)

    with pytest.raises(TimeoutError, match="link lost"):
        camera.run_with_window(Args, Secrets, None, Source(), stats, view)


def test_a_failure_updates_the_numbers_at_once(view, stats):
    view.compose(None, stats, 0)
    captions = view.canvas[:view._panels_top].copy()
    numbers = view.canvas[view._metrics_top:].copy()
    stats.failed = 1
    view.publish(FrameResult(7, bytes(1000), None))
    view.compose(None, stats, 0)
    assert (view.canvas[:view._panels_top] != captions).any()
    assert (view.canvas[view._metrics_top:] != numbers).any()


def test_only_the_newest_result_is_drawn(view, stats):
    view.publish(FrameResult(1, bytes(1000), jpeg_of(filled(0, 0, 10))))
    view.publish(FrameResult(2, bytes(1000), jpeg_of(filled(0, 0, 200))))
    view.compose(None, stats, 0)
    assert third_panel(view)[10, 10].tolist() == [0, 0, 200]
