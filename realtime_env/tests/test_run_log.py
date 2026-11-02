"""Every run leaves a log in logs/: header, events, frames, the console and the end."""

import csv

import pytest

from host import run_log
from host.cli import main

KEY = "00" * 16
IV = "00" * 12


def only_log(folder, pattern="*.log"):
    found = sorted(folder.glob(pattern))
    assert len(found) == 1, found
    return found[0]


def test_a_run_writes_its_command_key_events_console_and_end(logs_in_tmp, tmp_path, monkeypatch):
    monkeypatch.chdir(tmp_path)
    assert main(["raw", "--sim", "model", "--data", "00" * 16, "--key", KEY, "--iv", IV]) == 0
    text = only_log(logs_in_tmp, "*_raw_uart12m.log").read_text(encoding="utf-8")
    assert text.startswith(run_log.KEY_WARNING)
    assert f"--key {KEY}" in text  # In full, as chosen for the demo
    assert "EVENT   link     raw: 4 gói" in text
    assert "CONSOLE" in text and "0388dace 60b6a392" in text
    assert "INFO    end      mã thoát 0" in text
    assert run_log.active() is None


def test_an_error_is_logged_with_its_traceback(logs_in_tmp, tmp_path, monkeypatch):
    monkeypatch.chdir(tmp_path)
    assert main(["raw", "--sim", "model", "--data", "00" * 300, "--key", KEY, "--iv", IV]) == 1
    text = only_log(logs_in_tmp).read_text(encoding="utf-8")
    assert "ERROR   run      ValueError: Data must be" in text and "TRACE" in text and "mã thoát 1" in text


def test_a_locked_command_writes_no_log(logs_in_tmp):
    assert main(["camera", "--link", "spi40", "--key", KEY, "--iv", IV]) == 2
    assert not logs_in_tmp.exists() or not list(logs_in_tmp.iterdir())


def test_two_runs_in_one_second_keep_both_logs(tmp_path):
    first = run_log.start(tmp_path, "raw", "uart12m")
    second = run_log.start(tmp_path, "raw", "uart12m")
    run_log.finish()
    assert first.path != second.path and first.path.exists() and second.path.exists()


def test_nothing_is_written_when_no_run_is_open():
    run_log.finish()
    run_log.event("x", "y")
    run_log.frame({"frame": 1})
    run_log.error("x", ValueError("y"))
    assert run_log.active() is None


def test_the_camera_writes_a_csv_row_per_frame(logs_in_tmp, tmp_path):
    cv2 = pytest.importorskip("cv2")
    import numpy as np

    video = tmp_path / "clip.avi"
    writer = cv2.VideoWriter(str(video), cv2.VideoWriter_fourcc(*"MJPG"), 10, (64, 48))
    for index in range(5):
        writer.write(np.full((48, 64, 3), index * 40, dtype=np.uint8))
    writer.release()
    assert main(["--advanced", "camera", "--sim", "model", "--source", str(video), "--size", "64x48",
                 "--no-window", "--key", KEY, "--iv", IV]) == 0
    rows = list(csv.DictReader(only_log(logs_in_tmp, "*_frames.csv").open(encoding="utf-8")))
    assert [row["frame"] for row in rows] == ["1", "2", "3", "4", "5"]
    assert all(row["tag"] == "PASS" and int(row["tx_bytes"]) > int(row["encoded_bytes"]) for row in rows)
    text = only_log(logs_in_tmp, "*_camera_uart12m.log").read_text(encoding="utf-8")
    assert text.count("FRAME") == 5 and "EVENT   camera" in text and "EVENT   stop" in text
