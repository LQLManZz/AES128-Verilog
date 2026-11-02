"""Frame codecs of the camera: H.264 by default, JPEG as the fallback.

H.264 sends 5 to 10 times fewer bytes than JPEG at the same quality, but its frames depend on the
ones before. So no encoded frame may be dropped, and after a frame fails its tag the decoder waits
for the next key frame, which the encoder is asked to make at once. Intra refresh spreads the
periodic key frame over many frames, so no single frame is large enough to stall the link.
"""

import time
from dataclasses import dataclass
from fractions import Fraction
from typing import Optional, Tuple

import cv2
import numpy as np

CODECS = ("h264", "jpeg")
_DEFAULT_FPS = 30


@dataclass
class Encoded:
    data: bytes
    key_frame: bool
    encode_ms: float = 0.0


def crf_of(quality: int) -> int:
    """Maps the 1..100 quality of the menu onto x264 CRF: 70 gives 23, the x264 default."""
    return max(0, min(51, round(51 - 0.4 * quality)))


def compress(frame: np.ndarray, size: Tuple[int, int], quality: int) -> bytes:
    resized = cv2.resize(frame, size, interpolation=cv2.INTER_AREA)
    ok, jpeg = cv2.imencode(".jpg", resized, [cv2.IMWRITE_JPEG_QUALITY, quality])
    if not ok:
        raise ValueError("JPEG compression failed")
    return jpeg.tobytes()


class JpegEncoder:
    name = "jpeg"
    drops_allowed = True  # Every JPEG stands alone

    def __init__(self, size: Tuple[int, int], quality: int):
        self._size, self._quality = size, quality

    def encode(self, frame: np.ndarray) -> Optional[Encoded]:
        started = time.perf_counter()
        data = compress(frame, self._size, self._quality)
        return Encoded(data, True, (time.perf_counter() - started) * 1e3)

    def request_key_frame(self) -> None:
        pass

    def close(self) -> None:
        pass


class JpegDecoder:
    def decode(self, data: bytes) -> Optional[np.ndarray]:
        return cv2.imdecode(np.frombuffer(data, dtype=np.uint8), cv2.IMREAD_COLOR)


class H264Encoder:
    name = "h264"
    drops_allowed = False

    def __init__(self, size: Tuple[int, int], quality: int, fps: float = _DEFAULT_FPS):
        import av
        from av.video.frame import PictureType

        width, height = size
        if width % 2 or height % 2:
            raise ValueError(f"H.264 needs an even frame size, got {width}x{height}")
        rate = Fraction(max(round(fps or _DEFAULT_FPS), 1))
        context = av.CodecContext.create("libx264", "w")
        context.width, context.height = width, height
        context.pix_fmt = "yuv420p"
        context.framerate = rate
        context.time_base = 1 / rate
        # One refresh sweep per second: a lost frame heals within a second even without a key frame
        context.options = {"preset": "ultrafast", "tune": "zerolatency", "crf": str(crf_of(quality)),
                           "forced-idr": "1",
                           "x264-params": f"keyint={int(rate)}:bframes=0:intra-refresh=1:repeat-headers=1"}
        self._av, self._key_type = av, PictureType.I
        self._context = context
        self._size = size
        self._pts = 0
        self._want_key = False

    def encode(self, frame: np.ndarray) -> Optional[Encoded]:
        started = time.perf_counter()
        resized = cv2.resize(frame, self._size, interpolation=cv2.INTER_AREA)
        picture = self._av.VideoFrame.from_ndarray(resized, format="bgr24").reformat(format="yuv420p")
        picture.pts = self._pts
        self._pts += 1
        if self._want_key:
            self._want_key = False
            picture.pict_type = self._key_type
        packets = self._context.encode(picture)
        data = b"".join(bytes(packet) for packet in packets)
        if not data:
            return None
        return Encoded(data, any(packet.is_keyframe for packet in packets), (time.perf_counter() - started) * 1e3)

    def request_key_frame(self) -> None:
        """Called from the decrypt stage: the next frame becomes an IDR the decoder can start from."""
        self._want_key = True

    def close(self) -> None:
        pass


class H264Decoder:
    def __init__(self):
        import av
        self._av = av
        self._context = av.CodecContext.create("h264", "r")

    def decode(self, data: bytes) -> Optional[np.ndarray]:
        try:
            frames = self._context.decode(self._av.Packet(data))
        except self._av.FFmpegError:
            return None
        return frames[-1].to_ndarray(format="bgr24") if frames else None


def open_codec(name: str, size: Tuple[int, int], quality: int, fps: float = _DEFAULT_FPS):
    """Returns (encoder, decoder, note). Without PyAV or libx264, H.264 falls back to JPEG and says why."""
    if name == "h264":
        try:
            return H264Encoder(size, quality, fps), H264Decoder(), ""
        except ImportError:
            note = "Không có PyAV (pip install av), dùng JPEG"
        except Exception as error:  # av raises its own errors when libx264 is missing
            if isinstance(error, ValueError) and "even" in str(error):
                raise
            note = f"Không mở được bộ nén H.264 ({error}), dùng JPEG"
        return JpegEncoder(size, quality), JpegDecoder(), note
    if name == "jpeg":
        return JpegEncoder(size, quality), JpegDecoder(), ""
    raise ValueError(f"Unknown codec {name!r}")
