"""H.264 by default, JPEG when PyAV or libx264 is missing."""

import builtins

import pytest

cv2 = pytest.importorskip("cv2")
import numpy as np  # noqa: E402

from host import codec  # noqa: E402

SIZE = (64, 48)
pytest.importorskip("av")


def frames(count):
    for index in range(count):
        frame = np.zeros((SIZE[1], SIZE[0], 3), dtype=np.uint8)
        cv2.circle(frame, (10 + index * 3, 24), 8, (40, 90, 240), -1)
        yield frame


def test_quality_70_is_the_x264_default_crf():
    assert codec.crf_of(70) == 23 and codec.crf_of(100) == 11 and codec.crf_of(1) == 51


def test_h264_frames_decode_at_once_and_look_like_the_input():
    encoder, decoder, note = codec.open_codec("h264", SIZE, 70)
    assert note == "" and encoder.name == "h264" and not encoder.drops_allowed
    for index, frame in enumerate(frames(10)):
        encoded = encoder.encode(frame)
        assert encoded.key_frame == (index == 0)
        picture = decoder.decode(encoded.data)  # Never a frame late: zerolatency and no B-frames
        assert picture.shape == frame.shape and np.abs(picture.astype(int) - frame).mean() < 8


def test_a_key_frame_comes_when_asked():
    encoder = codec.H264Encoder(SIZE, 70)
    kinds = []
    for index, frame in enumerate(frames(6)):
        if index == 3:
            encoder.request_key_frame()
        kinds.append(encoder.encode(frame).key_frame)
    assert kinds == [True, False, False, True, False, False]


def test_h264_needs_an_even_size():
    with pytest.raises(ValueError, match="even"):
        codec.open_codec("h264", (63, 48), 70)


def test_without_pyav_the_camera_falls_back_to_jpeg(monkeypatch):
    real = builtins.__import__

    def no_av(name, *args, **kwargs):
        if name == "av" or name.startswith("av."):
            raise ImportError("no av")
        return real(name, *args, **kwargs)

    monkeypatch.setattr(builtins, "__import__", no_av)
    encoder, decoder, note = codec.open_codec("h264", SIZE, 70)
    assert encoder.name == "jpeg" and "pip install av" in note
    assert encoder.encode(next(frames(1))).data[:2] == b"\xff\xd8"
