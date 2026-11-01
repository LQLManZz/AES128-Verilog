"""Step-by-step console report, also saved as a picture of exactly what was printed."""

import hashlib
import os
import sys
from pathlib import Path
from typing import Iterable, List, Optional, Sequence, Set, Tuple

from PIL import Image, ImageDraw, ImageFont

_FONT_CANDIDATES = (r"C:\Windows\Fonts\consola.ttf", "DejaVuSansMono.ttf")
_FONT_SIZE = 16
_LINE_HEIGHT = 20
_MARGIN = 16
_SECTION_WIDTH = 78
_TERMINAL_PICTURE_WIDTH = 28
_PICTURE_SIZE = 256
_BACKGROUND = (12, 12, 12)
_STYLES = {
    "": (204, 204, 204),
    "title": (97, 214, 214),
    "pass": (35, 209, 139),
    "fail": (241, 76, 76),
    "dim": (140, 140, 140),
}
_ANSI = {"title": "96", "pass": "92", "fail": "91", "dim": "90"}


def grouped(data: bytes) -> str:
    """Hex in groups of 8 digits, like a hardware register dump."""
    text = data.hex()
    return " ".join(text[i:i + 8] for i in range(0, len(text), 8))


def digest(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()[:16]


def pick_chunks(count: int, show: int, keep: Set[int]) -> List[Optional[int]]:
    """Returns the chunks to print, first and last `show` plus `keep`; None marks a gap."""
    wanted = sorted({*range(min(show, count)), *range(max(count - show, 0), count), *keep})
    picked: List[Optional[int]] = []
    for index in wanted:
        if picked and picked[-1] != index - 1:
            picked.append(None)
        picked.append(index)
    return picked


class Report:
    """Prints each line as it happens and remembers it for save_png()."""

    def __init__(self, show_chunks: int = 3):
        self.show_chunks = show_chunks
        self.items: List[Tuple[str, object, str]] = []
        # Running an empty command is the documented way to enable ANSI on Windows consoles
        self._colors = sys.stdout.isatty() and os.system("") == 0

    def line(self, text: str = "", style: str = "") -> None:
        self.items.append(("text", text, style))
        code = _ANSI.get(style)
        print(f"\x1b[{code}m{text}\x1b[0m" if code and self._colors else text)

    def section(self, title: str, detail: str = "") -> None:
        self.line()
        left = f"═══ {title} "
        right = f" {detail}" if detail else ""
        self.line(left + "═" * max(_SECTION_WIDTH - len(left) - len(right), 3) + right, "title")

    def field(self, label: str, value: str, style: str = "") -> None:
        self.line(f" {label:<10} {value}", style)

    def chunk_table(self, header: str, rows: Sequence[Tuple[str, str]], keep: Iterable[int] = ()) -> None:
        """Prints (text, style) rows, one per chunk, leaving out the middle of long tables."""
        self.line(f" {header}", "dim")
        for index in pick_chunks(len(rows), self.show_chunks, set(keep)):
            if index is None:
                self.line(" …", "dim")
            else:
                text, style = rows[index]
                self.line(f" {text}", style)

    def pictures(self, named: Sequence[Tuple[str, Path]]) -> None:
        loaded = []
        for label, path in named:
            with Image.open(path) as image:
                loaded.append((label, image.convert("RGB")))
        self.items.append(("pictures", loaded, ""))
        if self._colors:
            self._print_pictures(loaded)

    def _print_pictures(self, loaded: Sequence[Tuple[str, Image.Image]]) -> None:
        print(" " + "  ".join(f"{label:<{_TERMINAL_PICTURE_WIDTH}}" for label, _ in loaded))
        size = (_TERMINAL_PICTURE_WIDTH, _TERMINAL_PICTURE_WIDTH // 2 * 2)
        small = [image.resize(size, Image.Resampling.BILINEAR) for _, image in loaded]
        for row in range(0, size[1], 2):
            cells = []
            for image in small:
                for column in range(size[0]):
                    top = image.getpixel((column, row))
                    bottom = image.getpixel((column, row + 1))
                    cells.append("\x1b[38;2;{};{};{}m\x1b[48;2;{};{};{}m▀".format(*top, *bottom))
                cells.append("\x1b[0m  ")
            print(" " + "".join(cells))

    def save_png(self, path: Path) -> None:
        font = _load_font()
        cell = font.getlength("M")
        widest = max((len(item) for kind, item, _ in self.items if kind == "text"), default=0)
        strips = [item for kind, item, _ in self.items if kind == "pictures"]
        strip_width = max((len(strip) * (_PICTURE_SIZE + _MARGIN) for strip in strips), default=0)
        height = _MARGIN * 2
        for kind, item, _ in self.items:
            height += _LINE_HEIGHT if kind == "text" else _PICTURE_SIZE + _LINE_HEIGHT * 2

        canvas = Image.new("RGB", (int(max(widest * cell, strip_width)) + _MARGIN * 2, height), _BACKGROUND)
        draw = ImageDraw.Draw(canvas)
        top = _MARGIN
        for kind, item, style in self.items:
            if kind == "text":
                draw.text((_MARGIN, top), item, font=font, fill=_STYLES[style])
                top += _LINE_HEIGHT
                continue
            left = _MARGIN
            for label, image in item:
                draw.text((left, top), label, font=font, fill=_STYLES["dim"])
                scaled = image.resize((_PICTURE_SIZE, _PICTURE_SIZE), Image.Resampling.NEAREST)
                canvas.paste(scaled, (left, top + _LINE_HEIGHT))
                left += _PICTURE_SIZE + _MARGIN
            top += _PICTURE_SIZE + _LINE_HEIGHT * 2
        canvas.save(path)


def _load_font() -> ImageFont.FreeTypeFont:
    for candidate in _FONT_CANDIDATES:
        try:
            return ImageFont.truetype(candidate, _FONT_SIZE)
        except OSError:
            continue
    return ImageFont.load_default(_FONT_SIZE)
