"""Runs the camera loop on a short video file against the software model."""

import pytest

cv2 = pytest.importorskip("cv2")
import numpy as np  # noqa: E402

from host import camera, framing, gcm_model  # noqa: E402
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


def test_cipher_panel_is_square_and_colored():
    assert camera.cipher_panel(bytes(1000), 90).shape == (90, 90, 3)


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
