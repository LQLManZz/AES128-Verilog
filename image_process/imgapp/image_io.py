"""Image file <-> raw 8-bit grayscale pixel bytes."""

import math
from array import array
from pathlib import Path
from typing import Tuple

from PIL import Image, ImageOps


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


def _to_gray(img: Image.Image) -> Image.Image:
    if img.mode.startswith("I") or img.mode == "F":
        return _scale_to_8_bit(img)
    if img.has_transparency_data:
        rgba = img.convert("RGBA")
        white = Image.new("RGBA", rgba.size, "white")
        return Image.alpha_composite(white, rgba).convert("L")
    return img.convert("L")


def load_gray(path: Path, size: Tuple[int, int], fit: str = "crop") -> Image.Image:
    """Reads an image file and returns it as a grayscale image of exactly `size`."""
    with Image.open(path) as img:
        gray = _to_gray(ImageOps.exif_transpose(img))
    if fit == "crop":
        return ImageOps.fit(gray, size, Image.Resampling.LANCZOS)
    return ImageOps.pad(gray, size, Image.Resampling.LANCZOS, color=0)


def read_pixels(path: Path) -> bytes:
    with Image.open(path) as img:
        return img.convert("L").tobytes()


def save_gray(pixels: bytes, width: int, height: int, path: Path) -> None:
    Image.frombytes("L", (width, height), pixels).save(path)
