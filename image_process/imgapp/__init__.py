"""Grayscale image <-> AES-GCM UART packet streams."""

import sys
from pathlib import Path

# The packet protocol lives next to host.py so both demos share one copy.
sys.path.append(str(Path(__file__).resolve().parents[2] / "uart_integration" / "python"))
