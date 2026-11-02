"""One log file per run in logs/: header, events, every frame, a line per second and the console.

The camera also gets a CSV beside the log, one row per frame, for plotting. Only one run is open at
a time, so the rest of host/ writes through the module functions without passing the log around;
with no run open they do nothing, which keeps tests and library use quiet.

The key is written in full, as asked for the demo: never share a log made with a real key.
"""

import csv
import threading
import time
import traceback
from datetime import datetime
from pathlib import Path
from typing import Dict, Iterable, Optional

FRAME_COLUMNS = ("frame", "type", "t_capture_s", "encoded_bytes", "chunks", "tx_bytes", "rx_bytes",
                 "encode_ms", "link_ms", "decode_ms", "latency_ms", "link_mbps", "tag", "dropped_total")
KEY_WARNING = "# Cảnh báo: file này ghi key ở dạng rõ. Không chia sẻ log của một key thật."

_active: Optional["RunLog"] = None


class RunLog:
    def __init__(self, folder: Path, mode: str, link: str, csv_columns: Optional[Iterable[str]] = None):
        folder.mkdir(parents=True, exist_ok=True)
        stamp = datetime.now().strftime("%Y%m%d_%H%M%S")
        base = folder / f"{stamp}_{mode}_{link}"
        suffix = 1
        while base.with_suffix(".log").exists():  # Two runs in the same second keep both logs
            suffix += 1
            base = folder / f"{stamp}_{mode}_{link}_{suffix}"
        self.path = base.with_suffix(".log")
        self.csv_path: Optional[Path] = None
        self._lock = threading.Lock()
        self._file = open(self.path, "w", encoding="utf-8", buffering=1)
        self._file.write(KEY_WARNING + "\n")
        self._csv_file = None
        self._csv = None
        if csv_columns:
            self.csv_path = base.parent / f"{base.name}_frames.csv"
            self._csv_file = open(self.csv_path, "w", encoding="utf-8", newline="")
            self._csv = csv.DictWriter(self._csv_file, fieldnames=list(csv_columns))
            self._csv.writeheader()

    def write(self, kind: str, topic: str, text: str) -> None:
        stamp = datetime.now().strftime("%H:%M:%S.%f")[:-3]
        with self._lock:
            if not self._file.closed:
                self._file.write(f"{stamp} {kind:<7} {topic:<8} {text}\n")

    def row(self, values: Dict[str, object]) -> None:
        with self._lock:
            if self._csv is not None and not self._csv_file.closed:
                self._csv.writerow(values)

    def close(self) -> None:
        with self._lock:
            self._file.close()
            if self._csv_file:
                self._csv_file.close()


def start(folder: Path, mode: str, link: str, csv_columns: Optional[Iterable[str]] = None) -> RunLog:
    """Opens the log of this run, closing any run left open."""
    global _active
    finish()
    _active = RunLog(folder, mode, link, csv_columns)
    return _active


def active() -> Optional[RunLog]:
    return _active


def finish() -> None:
    global _active
    if _active is not None:
        _active.close()
        _active = None


def _write(kind: str, topic: str, text: str) -> None:
    if _active is not None:
        _active.write(kind, topic, text)


def info(topic: str, text: str) -> None:
    _write("INFO", topic, text)


def event(topic: str, text: str) -> None:
    _write("EVENT", topic, text)


def stat(topic: str, text: str) -> None:
    _write("STAT", topic, text)


def console(text: str) -> None:
    if text.strip():
        _write("CONSOLE", "", text)


def error(topic: str, error_: BaseException) -> None:
    """The message, then the traceback indented under it."""
    if _active is None:
        return
    _active.write("ERROR", topic, f"{type(error_).__name__}: {error_}")
    for line in traceback.format_exception(type(error_), error_, error_.__traceback__):
        for part in line.rstrip("\n").split("\n"):
            _active.write("TRACE", "", part)


def frame(values: Dict[str, object]) -> None:
    """One camera frame: a FRAME line in the log and a row in the CSV."""
    if _active is None:
        return
    _active.row(values)
    text = (f"#{values['frame']} {values['type']} | {values['encoded_bytes']} B | {values['chunks']} chunk | "
            f"tx {values['tx_bytes']} B rx {values['rx_bytes']} B | nén {values['encode_ms']} ms | "
            f"link {values['link_ms']} ms ({values['link_mbps']} MB/s) | giải nén {values['decode_ms']} ms | "
            f"chụp→giải mã {values['latency_ms']} ms | tag {values['tag']} | bỏ {values['dropped_total']}")
    _active.write("FRAME", "", text)


def elapsed_ms(started: float) -> float:
    return round((time.perf_counter() - started) * 1e3, 2)
