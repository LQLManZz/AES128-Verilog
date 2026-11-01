#!/usr/bin/env python3
"""Runs the AES-GCM IP over UART or SPI. Without arguments it asks through a menu."""

import sys

from host.cli import main

if __name__ == "__main__":
    sys.exit(main())
