import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))


import pytest  # noqa: E402


@pytest.fixture(autouse=True)
def logs_in_tmp(tmp_path, monkeypatch):
    """Every run writes a log: keep the ones from tests out of realtime_env/logs."""
    monkeypatch.setenv("REALTIME_ENV_LOG_DIR", str(tmp_path / "logs"))
    return tmp_path / "logs"
