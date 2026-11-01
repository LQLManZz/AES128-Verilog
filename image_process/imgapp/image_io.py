"""Image file <-> raw 8-bit pixel bytes: one sample for gray, interleaved R, G, B for color."""

import math
from array import array
from pathlib import Path
from typing import Tuple

from PIL import Image, ImageChops, ImageOps

_GRAY_MODES = ("1", "L", "LA", "La")
_PIXEL_MODES = {1: "L", 3: "RGB"}


def pixel_mode(channels: int) -> str:
    if channels not in _PIXEL_MODES:
        raise ValueError(f"Unsupported number of channels: {channels}")
    return _PIXEL_MODES[channels]


def _scale_to_8_bit(img: Image.Image) -> Image.Image:
    """Maps integer and float samples onto 0..255, because a plain convert("L") clips them."""
    is_float = img.mode == "F"
    # getextrema() can miss a NaN, so every sample has to be checked
    if is_float and not all(map(math.isfinite, array("f", img.tobytes()))):
        raise ValueError("Image holds non-finite samples (NaN or infinity)")

    low, high = img.getextrema()
    if not is_float and low >= 0 and high < 65536:
        return img.point(lambda value: value * (1 / 256)).convert("L")
    if is_float and low >= 0 and high <= 1:
        low, high = 0.0, 1.0  # Already normalised, so a dim image stays dim

    scale = 255 / (high - low) if high > low else 0
    offset = -low * scale
    return img.convert("F").point(lambda value: value * scale + offset).convert("L")


def _to_8_bit(img: Image.Image, gray: bool) -> Image.Image:
    if img.mode.startswith("I") or img.mode == "F":
        return _scale_to_8_bit(img)
    mode = "L" if gray or img.mode in _GRAY_MODES else "RGB"
    if img.has_transparency_data:
        rgba = img.convert("RGBA")
        white = Image.new("RGBA", rgba.size, "white")
        return Image.alpha_composite(white, rgba).convert(mode)
    return img.convert(mode)


def load_image(path: Path, size: Tuple[int, int], fit: str = "crop", gray: bool = False) -> Image.Image:
    """Reads an image file and returns it at 8 bits per channel and exactly `size`.

    A gray file stays one channel and a color file becomes RGB, unless `gray` forces one channel.
    """
    with Image.open(path) as img:
        converted = _to_8_bit(ImageOps.exif_transpose(img), gray)
    if fit == "crop":
        return ImageOps.fit(converted, size, Image.Resampling.LANCZOS)
    return ImageOps.pad(converted, size, Image.Resampling.LANCZOS, color=0)


def make_sample(path: Path, size: Tuple[int, int]) -> None:
    """Writes a color test image: three crossing gradients with a band of pure colors."""
    gradient = Image.linear_gradient("L").resize(size)
    across = gradient.rotate(90)
    picture = Image.merge("RGB", (gradient, across, ImageChops.invert(gradient)))
    width, height = size
    colors = ("red", "lime", "blue", "yellow", "cyan", "magenta", "white", "black")
    bar = max(width // len(colors), 1)
    for index, color in enumerate(colors):
        left = index * bar
        picture.paste(color, (left, height // 3, left + bar, height // 2))
    path.parent.mkdir(parents=True, exist_ok=True)
    picture.save(path)


def read_pixels(path: Path) -> bytes:
    with Image.open(path) as img:
        return img.tobytes()


def save_image(pixels: bytes, width: int, height: int, channels: int, path: Path) -> None:
    Image.frombytes(pixel_mode(channels), (width, height), pixels).save(path)
