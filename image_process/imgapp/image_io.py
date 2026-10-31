"""Image file <-> raw 8-bit grayscale pixel bytes."""

from pathlib import Path
from typing import Tuple

from PIL import Image, ImageOps


def _to_gray(img: Image.Image) -> Image.Image:
    if img.mode.startswith("I"):
        # 16-bit samples would clip to white in a plain convert("L")
        return img.point(lambda value: value * (1 / 256)).convert("L")
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
