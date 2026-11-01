"""Answers a TX stream with the real RTL: replays the session in QuestaSim, bit by bit."""

import os
import re
import subprocess
from dataclasses import dataclass
from pathlib import Path
from typing import List, Tuple

from .protocol import BURST_MESSAGES, DEFAULT_BAUD_RATE, parse_packets

from . import framing, gcm_model, spi_frames, links
from .packet_file import Packet

REPO_ROOT = Path(__file__).resolve().parents[2]
RUN_ROOT = REPO_ROOT / "realtime_env" / "output" / "rtl_sim"
DEFAULT_QUESTA = Path(r"C:\Microchip\Libero_SoC_2026.1\Libero_SoC\QuestaSim_Pro\win64")
TESTBENCH = "tb_aes256_stream"
SIM_TIMEOUT_S = 3600
READ_MARGIN = 512  # Replies trail the data by about one message

_compiled = set()


@dataclass
class SimConfig:
    link: str = "spi"  # "spi" or "uart"
    sclk_mhz: float = 40.0
    baud: int = DEFAULT_BAUD_RATE
    window: int = BURST_MESSAGES
    uart_clk_mhz: float = 0.0  # Non-zero: UART on its own clock, as in aes_uart_12m_top

    def describe(self) -> str:
        if self.link == "spi":
            return f"SPI mode 0, SCLK {self.sclk_mhz:g} MHz"
        uart_clock = f", UART clock {self.uart_clk_mhz:g} MHz" if self.uart_clk_mhz else ""
        return f"UART 8N1, {self.baud:,} baud{uart_clock}"


@dataclass
class SimResult:
    responses: List[Packet]
    elapsed_s: float
    frames: int
    statuses: List[int]


def questa_tool(name: str) -> Path:
    tool = Path(os.environ.get("QUESTA_BIN", DEFAULT_QUESTA)) / f"{name}.exe"
    if not tool.exists():
        raise OSError(f"QuestaSim not found at {tool}: set QUESTA_BIN to its win64 folder")
    return tool


def _run(tool: str, *args: str) -> str:
    done = subprocess.run([str(questa_tool(tool)), *args], cwd=REPO_ROOT, capture_output=True, text=True,
                          encoding="utf-8", errors="replace", timeout=SIM_TIMEOUT_S, check=False)
    if done.returncode != 0:
        raise OSError(f"{tool} failed:\n{(done.stdout + done.stderr)[-2000:]}")
    return done.stdout


def _compile(key_bits: int) -> str:
    """Builds the library for one key size, once per run of the program."""
    library = (RUN_ROOT / f"work_{key_bits}").relative_to(REPO_ROOT).as_posix()
    if key_bits in _compiled:
        return library
    RUN_ROOT.mkdir(parents=True, exist_ok=True)
    _run("vlib", library)
    common = "realtime_env/rtl/common"
    core = f"{common}/aes{key_bits}_core_files.f"
    variant_dir = f"realtime_env/rtl/aes{key_bits}"
    _run("vlog", "-quiet", "-sv", "-work", library, "-f", core)
    _run("vlog", "-quiet", "-sv", "-work", library, f"{common}/protocol_pkg.sv")
    for name in ("uart_rx", "uart_tx", "uart_cdc_link", "packet_parser", "packet_builder", "byte_fifo", "spi_link",
                 "aes_gcm_engine", "aes_uart_cdc_wrapper"):
        _run("vlog", "-quiet", "-sv", "-work", library, f"{common}/{name}.sv")
    for link in ("uart", "spi"):
        _run("vlog", "-quiet", "-sv", "-work", library, f"{variant_dir}/aes{key_bits}_{link}_wrapper.sv")
    _run("vlog", "-quiet", "-sv", "-work", library, f"realtime_env/rtl/aes256/{TESTBENCH}.sv")
    _compiled.add(key_bits)
    return library


def plan_frames(packets: List[Packet], config: SimConfig) -> List[Tuple[bytes, int]]:
    """Lays the session out as (frame bytes, expected reply bytes), using the model's answer sizes."""
    expected = gcm_model.simulate(packets)
    frames = [(spi_frames.CLEAR_FRAME, 0)] if config.link == "spi" else []
    position = 0
    for group in framing.batches(packets, config.window):
        answers = len(_group_answers(group, expected, position))
        reply = spi_frames.reply_bytes(expected[position:position + answers])
        position += answers
        if config.link == "spi":
            data = spi_frames.data_frame(group)
            frames.append((data, 0))
            frames.append((spi_frames.read_frame(max(reply - len(data), 0) + READ_MARGIN), 0))
        else:
            frames.append((spi_frames.data_frame(group)[1:], reply))
    return frames


def _group_answers(group: List[Packet], expected: List[Packet], position: int) -> List[Packet]:
    """Returns the model's answers to this group: one per load, and through the tag for a START."""
    pending = iter(expected[position:])
    answers = []
    for cmd, _ in group:
        answers += links.read_reply(lambda: next(pending), cmd)
    return answers


def _write_stimulus(path: Path, frames: List[Tuple[bytes, int]]) -> None:
    with path.open("w", encoding="ascii") as stimulus:
        for frame, reply in frames:
            stimulus.write(f"{len(frame)} {reply} {frame.hex(' ')}\n")


def _read_answers(path: Path, config: SimConfig) -> Tuple[List[Packet], List[int]]:
    decoder = spi_frames.MisoDecoder()
    raw = bytearray()
    statuses = []
    for line in path.read_text(encoding="ascii").splitlines():
        answer = bytes.fromhex(line.split(" ", 1)[1]) if " " in line else b""
        if config.link == "spi":
            statuses.append(answer[0])
            decoder.feed(answer, skip_status=True)
        else:
            raw += answer
    return (decoder.packets if config.link == "spi" else parse_packets(bytes(raw))), statuses


def run_stream(packets: List[Packet], name: str, config: SimConfig) -> SimResult:
    """Replays `packets` on the RTL and returns what came back."""
    key_bits = len(framing.split_tx(packets)[0]) * 8
    library = _compile(key_bits)
    run_dir = RUN_ROOT / name
    run_dir.mkdir(parents=True, exist_ok=True)
    stimulus = run_dir / "mosi.hex"
    answers = run_dir / "miso.hex"
    answers.unlink(missing_ok=True)
    frames = plan_frames(packets, config)
    _write_stimulus(stimulus, frames)

    log = _run("vsim", "-c", "-t", "1ps", "-lib", library, TESTBENCH, "-voptargs=+acc=npr",
               f"-gUSE_SPI={int(config.link == 'spi')}", f"-gKEY_BITS={key_bits}",
               f"-gSCLK_PS={round(1e6 / config.sclk_mhz)}", f"-gBAUD_RATE={config.baud}",
               f"-gUART_CLK_HZ={round(config.uart_clk_mhz * 1e6)}",
               f"+stim={stimulus.relative_to(REPO_ROOT).as_posix()}",
               f"+out={answers.relative_to(REPO_ROOT).as_posix()}",
               "-do", "run -all; quit -f")
    (run_dir / "vsim.log").write_text(log, encoding="utf-8")
    done = re.search(r"STREAM_DONE elapsed_ns=(\d+)", log)
    if not done:
        raise OSError(f"Simulation stopped early:\n{log[-2000:]}")

    responses, statuses = _read_answers(answers, config)
    for status in statuses:
        spi_frames.check_status(status)
    return SimResult(responses, int(done.group(1)) * 1e-9, len(frames), statuses)
