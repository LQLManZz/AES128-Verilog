"""Draws the camera window off screen and checks what each panel holds."""

import pytest

cv2 = pytest.importorskip("cv2")
import numpy as np  # noqa: E402

from host import camera, camera_view  # noqa: E402
from host.camera_view import Backlog, FrameResult, Playback, View  # noqa: E402

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
    return View("spi40, AES-256", "Giả lập, không phải kit", SIZE, "Camera trực tiếp")


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
        live = False

        def read(self):
            raise TimeoutError("link lost")

        def peek(self):
            return None

    class Args:
        frames, buffer_frames = 0, 0

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


def result(number, good=True):
    return FrameResult(number, bytes(1000), jpeg_of(filled(0, 0, 200)) if good else None)


def test_playback_keeps_the_pace_of_the_camera():
    playback = Playback(0.1)
    for number in (1, 2, 3):
        playback.push(result(number))
    assert [item.number for item in playback.take(10.0)] == [1]
    assert playback.take(10.05) == []
    assert [item.number for item in playback.take(10.1)] == [2]
    assert [item.number for item in playback.take(10.2)] == [3]
    assert len(playback) == 0


def test_a_late_redraw_keeps_the_beat():
    playback = Playback(0.1)
    for number in (1, 2, 3):
        playback.push(result(number))
    playback.take(10.0)
    assert len(playback.take(10.13)) == 1
    assert len(playback.take(10.2)) == 1  # On 10.2, not 10.23


def test_a_slow_redraw_catches_up_so_the_delay_cannot_grow():
    playback = Playback(0.1)
    for number in range(5):
        playback.push(result(number))
    playback.take(10.0)
    assert len(playback.take(10.35)) == 3


def test_a_gap_in_the_frames_restarts_the_beat():
    playback = Playback(0.1)
    playback.push(result(1))
    playback.take(10.0)
    playback.push(result(2))
    playback.push(result(3))
    assert len(playback.take(20.0)) == 1
    assert len(playback.take(20.05)) == 0


def test_period_zero_releases_everything():
    playback = Playback(0.0)
    playback.push(result(1))
    playback.push(result(2))
    assert len(playback.take(10.0)) == 2


def test_the_window_waits_out_the_frames_it_still_holds(stats, monkeypatch):
    FakeWindow(monkeypatch)
    view = View("t", "b", SIZE, "Camera trực tiếp", 0.0)
    view.publish(result(1))
    view.run(lambda: None, stats, lambda: 0, lambda: False)
    assert view._last_number == 1


def test_a_failure_is_never_skipped_with_a_redraw(view, stats):
    view.publish(result(1, good=False))
    view.publish(result(2))
    view.compose(None, stats, 0)
    assert third_panel(view)[10, 10].tolist() == list(camera_view._FAIL_PANEL)


def test_panels_say_they_are_buffering(view, stats):
    view.compose(None, stats, 0, Backlog(3, 30, 15))
    assert (third_panel(view) != np.array(camera_view._CARD)).any()


def test_buffering_text_goes_once_a_frame_arrives(view, stats):
    view.publish(result(1))
    view.compose(None, stats, 0, Backlog(3, 30, 15))
    assert third_panel(view)[10, 10].tolist() == [0, 0, 200]


def test_buffering_never_counts_backwards(view, stats):
    view.compose(None, stats, 0, Backlog(15, 30, 15))
    view.compose(None, stats, 0, Backlog(14, 30, 15))
    assert view._filled == 15


def test_queue_card_warns_when_full_and_says_when_off(view):
    assert view._queue_card(Backlog(12, 30, 15)) == ("Hàng đợi", "12/30 khung", camera_view._TEXT)
    assert view._queue_card(Backlog(30, 30, 15)) == ("Hàng đợi", "30/30 khung", camera_view._WARN)
    assert view._queue_card(None) == ("Hàng đợi", "Tắt", camera_view._MUTED)


def test_the_delay_is_drawn_from_when_the_frame_was_captured(view, stats, monkeypatch):
    moment = [100.0]
    monkeypatch.setattr(camera_view.time, "perf_counter", lambda: moment[0])
    view.publish(FrameResult(1, bytes(1000), jpeg_of(filled(0, 0, 200)), 99.5))
    view.compose(None, stats, 0)
    assert view._delay_s == pytest.approx(0.5)


def test_numbers_are_drawn_with_no_frame_in_the_window(view, stats):
    stats.record(20.0)
    stats.marks[0] = (0.0, 20.0)
    assert view.compose(None, stats, 0).shape == view.canvas.shape
