"""Runs the camera loop on a short video file against the software model."""

import time

import pytest

cv2 = pytest.importorskip("cv2")
import numpy as np  # noqa: E402

from host import camera, framing, gcm_model, links  # noqa: E402
from host.cli import main  # noqa: E402

KEY = bytes(range(32))
IV = bytes(range(12))
AAD = bytes(16)
SIZE = (64, 48)


@pytest.fixture
def video(tmp_path):
    path = tmp_path / "clip.avi"
    writer = cv2.VideoWriter(str(path), cv2.VideoWriter_fourcc(*"MJPG"), 10, SIZE)
    assert writer.isOpened()
    for index in range(6):
        writer.write(np.full((SIZE[1], SIZE[0], 3), index * 40, dtype=np.uint8))
    writer.release()
    return path


def run(video, *options):
    return main(["camera", "--link", "spi40", "--sim", "model", "--key", KEY.hex(), "--iv", IV.hex(),
                 "--aad", AAD.hex(), "--source", str(video), "--size", "64x48", "--no-window", *options])


def test_default_decrypts_on_the_pc(video, capsys):
    assert run(video) == 0
    text = capsys.readouterr().out
    assert "6 khung, 0 khung lỗi tag" in text and "FPGA mã hoá, PC giải mã" in text


def test_fpga_decrypt_goes_through_the_link_twice(video, capsys, monkeypatch):
    exchanges = []
    real = gcm_model.simulate

    def counted(packets):
        exchanges.append(packets)
        return real(packets)

    monkeypatch.setattr(gcm_model, "simulate", counted)
    assert run(video, "--fpga-decrypt") == 0
    assert len(exchanges) == 12
    assert "FPGA mã hoá, FPGA giải mã" in capsys.readouterr().out


def test_frames_limit_stops_early(video, capsys):
    assert run(video, "--frames", "2") == 0
    assert "2 khung," in capsys.readouterr().out


def test_ivs_never_repeat_across_frames(video, monkeypatch):
    seen = []
    real = gcm_model.simulate

    def recording(packets):
        seen.extend(payload for cmd, payload in packets if cmd == 0x02)
        return real(packets)

    monkeypatch.setattr(gcm_model, "simulate", recording)
    assert run(video) == 0
    assert len(seen) == len(set(seen)) > 6


def test_missing_video_is_reported(tmp_path, capsys):
    assert run(tmp_path / "none.avi") == 1
    assert "Cannot open" in capsys.readouterr().out


def test_tag_that_does_not_match_is_refused():
    packets = framing.build_tx(bytes(100), KEY, IV)
    key, messages = framing.split_tx(packets)
    replies = framing.split_rx(gcm_model.simulate(packets))
    assert camera.decrypt_on_pc(key, messages, replies) == [bytes(112)]  # 100 bytes, padded
    with pytest.raises(framing.TagMismatch):
        camera.decrypt_on_pc(key, messages, [replies[0]._replace(tag=bytes(16))])


def test_compress_gives_a_jpeg():
    frame = np.zeros((48, 64, 3), dtype=np.uint8)
    assert camera.compress(frame, (32, 24), 50)[:2] == b"\xff\xd8"


def process(video, fpga_decrypt=False, tamper_every=0):
    class Args:
        size, quality, frames = SIZE, 50, 0

    class Secrets:
        key, iv, aad = KEY, IV, AAD

    Args.fpga_decrypt, Args.tamper_every = fpga_decrypt, tamper_every
    results = []
    stats = camera.Stats()
    source = camera.open_source(str(video), 0)
    camera.process_frames(Args, Secrets, links.ModelChannel(), source, stats, results.append, lambda: False)
    source.close()
    return results, stats


def test_decrypt_on_the_fpga_counts_both_trips(video):
    assert process(video, fpga_decrypt=True)[1].wire_bytes > 1.5 * process(video)[1].wire_bytes


def test_tamper_every_fails_only_those_frames(video, capsys):
    assert run(video, "--tamper-every", "3") == 1
    assert "6 khung, 2 khung lỗi tag" in capsys.readouterr().out


def test_tamper_every_also_fails_in_the_ip(video, capsys):
    assert run(video, "--tamper-every", "3", "--fpga-decrypt") == 1
    assert "6 khung, 2 khung lỗi tag" in capsys.readouterr().out


def test_failed_frame_publishes_no_plaintext(video):
    results = process(video, tamper_every=2)[0]
    assert [result.jpeg is None for result in results] == [False, True] * 3
    assert all(result.cipher for result in results)
    assert results[0].jpeg[:2] == b"\xff\xd8"


def test_emu_runs_the_camera_on_the_link_schedule(video, capsys):
    assert main(["camera", "--link", "uart2m", "--sim", "emu", "--key", KEY.hex(), "--iv", IV.hex(),
                 "--source", str(video), "--size", "64x48", "--no-window"]) == 0
    text = capsys.readouterr().out
    assert "giả lập theo số đo, không phải phần cứng" in text and "6 khung, 0 khung lỗi tag" in text


def test_realtime_needs_a_video(capsys):
    assert main(["camera", "--link", "spi40", "--sim", "emu", "--key", KEY.hex(), "--iv", IV.hex(), "--realtime"]) == 1
    assert "--source" in capsys.readouterr().out


def test_loop_without_window_needs_a_frame_limit(video, capsys):
    assert run(video, "--loop") == 1
    assert "--frames" in capsys.readouterr().out


def test_loop_restarts_the_video(video, capsys):
    assert run(video, "--loop", "--frames", "15") == 0
    assert "15 khung," in capsys.readouterr().out


def test_realtime_source_drops_frames_a_slow_link_cannot_take(video):
    source = camera.open_source(str(video), 0, realtime=True)
    frames = 0
    while source.read() is not None:
        frames += 1
        time.sleep(0.25)  # The clip runs at 10 fps
    source.close()
    assert source.dropped >= 2 and frames + source.dropped == 6


def test_peek_leaves_the_frame_for_read():
    class Capture:
        frames = [np.full((2, 2, 3), 7, dtype=np.uint8)]

        def read(self):
            return (True, self.frames.pop(0)) if self.frames else (False, None)

        def release(self):
            pass

    source = camera.LiveSource(Capture())
    source._thread.join(timeout=2.0)
    assert source.peek()[0, 0, 0] == 7
    assert source.read()[0, 0, 0] == 7
    assert source.peek()[0, 0, 0] == 7
    source.close()


def test_live_source_keeps_only_the_newest_frame():
    class Capture:
        def __init__(self):
            self.frames = [np.full((2, 2, 3), value, dtype=np.uint8) for value in range(3)]

        def read(self):
            return (True, self.frames.pop(0)) if self.frames else (False, None)

        def release(self):
            pass

    source = camera.LiveSource(Capture())
    source._thread.join(timeout=2.0)
    assert source.read()[0, 0, 0] == 2
    assert source.dropped == 2
    source.close()
