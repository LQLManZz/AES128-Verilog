"""Menu shown when main.py runs without a command: few words, UART 12 Mbaud, round after round.

Each round asks only what that mode needs, builds the same command line you could type, and runs
it. `--advanced` adds the other links, the simulators and the extra options, as on the command line.
"""

import re
from dataclasses import dataclass, field
from typing import Callable, List, Optional, Sequence, Set, Tuple

from .links import LINKS

DEFAULTS = {"size": "640x480", "quality": "70", "fps": "0", "image_size": "256x256"}
PROMPTS = {
    "header": "AES-GCM | {link} | {port}",
    "pick": "> ",
    "link": "Đường truyền [1 UART 12M, 2 UART 2M, 3 SPI 40 ESP32, 4 SPI 30 FT232H] (1): ",
    "run_on": "Chạy trên [1 FPGA, 2 Sim] (1): ",
    "run_on_advanced": "Chạy trên [1 FPGA, 2 Sim, 3 Giả lập emu{rtl}] (1): ",
    "size": "Độ phân giải WxH ({def}): ",
    "quality": "Chất lượng 1..100 ({def}): ",
    "fpga": "FPGA giải mã? y/N: ",
    "fps": "fps tối đa ({def} = camera default): ",
    "codec": "Codec [1 H.264, 2 JPEG] (1): ",
    "source": "Video thay camera (trống = camera): ",
    "tamper": "Lật bit mỗi N khung (0 = tắt): ",
    "paced": "ESP32 tự điều phối burst? y/N: ",
    "image": "Ảnh/thư mục: ",
    "image_size": "Kích thước WxH ({def}): ",
    "raw": "File/Raw hex: ",
    "tag": "Tag-Reference (trống = mã hoá): ",
    "aes": "AES [1 128, 2 256] (2): ",
    "key": "Cipherkey hex: ",
    "iv": "IV hex: ",
    "aad": "AAD hex (trống): ",
    "port": "Cổng COM: ",
    "again": "Enter để về menu ",
}
MODES = (("camera", "Camera"), ("image", "Img"), ("raw", "Raw text"))
ADVANCED_MODES = (("selftest", "Self-test NIST"),)
EXIT_LABEL = "Exit"
LINK_ORDER = ("uart12m", "uart2m", "spi40", "spi30")
SIM_ORDER = ("", "model", "emu", "rtl")
_HEX = re.compile(r"^[0-9a-fA-F]+$")
_SIZE = re.compile(r"^\d{1,5}x\d{1,5}$", re.IGNORECASE)

Ask = Callable[[str], str]


@dataclass
class Session:
    advanced: bool = False
    link: str = "uart12m"
    port: Optional[str] = None  # Channel D of the kit, found or typed once per session
    found: bool = False
    used: Set[Tuple[str, str]] = field(default_factory=set)  # (key, first 8 bytes of IV): the counter is the rest


def find_kit_port() -> Optional[str]:
    """Channel D of the Discovery Kit, or None when it is not plugged in or pyserial is missing."""
    try:
        from serial.tools import list_ports
    except ImportError:
        return None
    from .uart_client import KIT_UART_CHANNEL, KIT_USB_ID
    for port in list_ports.comports():
        if (port.vid, port.pid) == KIT_USB_ID and (port.serial_number or "").endswith(KIT_UART_CHANNEL):
            return port.device
    return None


def clean_hex(text: str) -> str:
    return text.replace(" ", "").replace(":", "").lower()


def ask_until(ask: Ask, prompt: str, check: Callable[[str], Optional[str]], default: str = "") -> str:
    """Asks until `check` returns no complaint; Enter takes `default`."""
    while True:
        answer = ask(prompt).strip() or default
        complaint = check(answer)
        if complaint is None:
            return answer
        print(f"[!] {complaint}")


def ask_number(ask: Ask, prompt: str, count: int, default: str = "1") -> int:
    answer = ask_until(ask, prompt, lambda a: None if a.isdigit() and 1 <= int(a) <= count
                       else f"Nhập số từ 1 đến {count}", default)
    return int(answer)


def ask_yes(ask: Ask, prompt: str) -> bool:
    return ask_until(ask, prompt, lambda a: None if a.lower() in ("y", "n") else "Nhập y hoặc n", "n").lower() == "y"


def hex_check(sizes: Sequence[int], name: str, optional: bool = False) -> Callable[[str], Optional[str]]:
    def check(answer: str) -> Optional[str]:
        text = clean_hex(answer)
        if not text:
            return None if optional else "Giá trị này là bắt buộc"
        if not _HEX.match(text) or len(text) % 2:
            return f"{name} phải là hex"
        if len(text) // 2 not in sizes:
            return f"{name} phải {' hoặc '.join(map(str, sizes))} byte, đang có {len(text) // 2}"
        return None
    return check


def size_check(answer: str) -> Optional[str]:
    return None if _SIZE.match(answer) else "Nhập dạng WxH, ví dụ 640x480"


def fps_check(answer: str) -> Optional[str]:
    try:
        return None if float(answer) >= 0 else "fps không được âm"
    except ValueError:
        return "Nhập một số"


def quality_check(answer: str) -> Optional[str]:
    return None if answer.isdigit() and 1 <= int(answer) <= 100 else "Nhập số từ 1 đến 100"


def header(session: Session) -> str:
    preset = LINKS[session.link]
    if preset.transport == "uart":
        where = f"{session.port} (kênh D)" if session.found else (session.port or "chưa thấy kit")
    else:
        where = "192.168.4.1" if preset.transport == "esp" else "FT232H"
    return PROMPTS["header"].format(link=preset.label, port=where)


def menu_items(session: Session) -> List[Tuple[str, str]]:
    return list(MODES) + (list(ADVANCED_MODES) if session.advanced else [])


def ask_mode(ask: Ask, session: Session) -> Optional[str]:
    items = menu_items(session)
    print(" " + "   ".join(f"{number} {label}" for number, (_, label) in enumerate(items, 1)) + f"   0 {EXIT_LABEL}")
    choices = {str(number): mode for number, (mode, _) in enumerate(items, 1)}
    answer = ask_until(ask, PROMPTS["pick"], lambda a: None if a in choices or a == "0" else "Chọn một số trong menu")
    return choices.get(answer)


def ask_sim(ask: Ask, session: Session, mode: str) -> str:
    if not session.advanced:
        return SIM_ORDER[ask_number(ask, PROMPTS["run_on"], 2) - 1]
    rtl = mode != "camera"  # The camera needs real time
    prompt = PROMPTS["run_on_advanced"].format(rtl=", 4 RTL" if rtl else "")
    return SIM_ORDER[ask_number(ask, prompt, 4 if rtl else 3) - 1]


def link_arguments(ask: Ask, session: Session, sim: str) -> List[str]:
    arguments = ["--link", session.link] + (["--sim", sim] if sim else [])
    preset = LINKS[session.link]
    if preset.transport == "uart" and not sim:
        if session.port is None:
            session.port = ask_until(ask, PROMPTS["port"],
                                     lambda a: None if re.match(r"^(com\d+|/dev/\S+)$", a, re.IGNORECASE)
                                     else "Nhập dạng COMx, ví dụ COM12").upper().replace("/DEV/", "/dev/")
        arguments += ["-p", session.port]
    if preset.transport == "esp" and sim in ("", "emu") and session.advanced and ask_yes(ask, PROMPTS["paced"]):
        arguments.append("--paced")
    return arguments


def camera_arguments(ask: Ask, session: Session) -> List[str]:
    arguments = []
    size = ask_until(ask, PROMPTS["size"].format(**{"def": DEFAULTS["size"]}), size_check, DEFAULTS["size"])
    quality = ask_until(ask, PROMPTS["quality"].format(**{"def": DEFAULTS["quality"]}), quality_check,
                        DEFAULTS["quality"])
    arguments += ["--size", size] if size != DEFAULTS["size"] else []
    arguments += ["--quality", quality] if quality != DEFAULTS["quality"] else []
    arguments += ["--fpga-decrypt"] if ask_yes(ask, PROMPTS["fpga"]) else []
    fps = ask_until(ask, PROMPTS["fps"].format(**{"def": DEFAULTS["fps"]}), fps_check, DEFAULTS["fps"])
    arguments += ["--fps", fps] if float(fps) > 0 else []
    if session.advanced:
        arguments += ["--codec", "jpeg"] if ask_number(ask, PROMPTS["codec"], 2) == 2 else []
        video = ask(PROMPTS["source"]).strip()
        arguments += ["--source", video, "--realtime", "--loop"] if video else []
        tamper = ask_until(ask, PROMPTS["tamper"], lambda a: None if a.isdigit() else "Nhập số từ 0", "0")
        arguments += ["--tamper-every", tamper] if int(tamper) else []
    return arguments


def image_arguments(ask: Ask) -> List[str]:
    path = ask(PROMPTS["image"]).strip()
    size = ask_until(ask, PROMPTS["image_size"].format(**{"def": DEFAULTS["image_size"]}), size_check,
                     DEFAULTS["image_size"])
    return ([path] if path else []) + (["--size", size] if size != DEFAULTS["image_size"] else [])


def raw_arguments(ask: Ask) -> List[str]:
    answer = ask_until(ask, PROMPTS["raw"], lambda a: None if a else "Giá trị này là bắt buộc")
    data = clean_hex(answer)
    if not (_HEX.match(data) and len(data) % 2 == 0):
        return ["--file", answer]
    tag = ask_until(ask, PROMPTS["tag"], hex_check((16,), "Tag-Reference", optional=True))
    return ["--data", data] + (["--op", "decrypt", "--tag", clean_hex(tag)] if tag else [])


def secret_arguments(ask: Ask, session: Session) -> Tuple[List[str], Tuple[str, str]]:
    key = clean_hex(ask_until(ask, PROMPTS["key"], hex_check((16, 32), "Cipherkey")))
    while True:
        iv = clean_hex(ask_until(ask, PROMPTS["iv"], hex_check((12,), "IV")))
        if (key, iv[:16]) not in session.used:
            break
        print("[!] Key này đã chạy với IV cùng 8 byte đầu trong phiên: các bộ đếm IV sẽ trùng. Đổi 8 byte đầu của IV.")
    aad = clean_hex(ask_until(ask, PROMPTS["aad"], hex_check(range(1, 241), "AAD", optional=True)))
    return ["--key", key, "--iv", iv] + (["--aad", aad] if aad else []), (key, iv[:16])


def ask_round(ask: Ask, session: Session) -> Optional[Tuple[List[str], Optional[Tuple[str, str]]]]:
    """One round: the command line to run and the key + IV it uses, or None to exit."""
    mode = ask_mode(ask, session)
    if mode is None:
        return None
    if mode == "selftest":
        sim = ask_sim(ask, session, mode)
        aes = "128" if ask_number(ask, PROMPTS["aes"], 2, "2") == 1 else "256"
        return ["selftest", "--aes", aes] + link_arguments(ask, session, sim), None
    sim = ask_sim(ask, session, mode)
    if mode == "camera":
        options = camera_arguments(ask, session)
    elif mode == "image":
        options = image_arguments(ask)
    else:
        options = raw_arguments(ask)
    arguments = [mode, *options, *link_arguments(ask, session, sim)]
    secrets, pair = secret_arguments(ask, session)
    return arguments + secrets, pair


def run_menu(ask: Ask, execute: Callable[[List[str]], int], advanced: bool = False,
             find_port: Callable[[], Optional[str]] = find_kit_port) -> int:
    """Rounds until Exit. Returns the exit code of the last run."""
    session = Session(advanced)
    code = 0
    try:
        if advanced:
            print("Chế độ mở rộng: mọi đường truyền, chế độ chạy và tuỳ chọn")
            session.link = LINK_ORDER[ask_number(ask, PROMPTS["link"], 4) - 1]
        if LINKS[session.link].transport == "uart":
            session.port = find_port()
            session.found = session.port is not None
        while True:
            print(header(session))
            chosen = ask_round(ask, session)
            if chosen is None:
                return code
            arguments, pair = chosen
            code = execute(arguments)
            if pair:
                session.used.add(pair)
            ask(PROMPTS["again"])
            print()
    except (EOFError, KeyboardInterrupt):
        print()
        return code
