"""Menu shown when main.py runs without arguments: asks for the same options as the command line."""

from typing import Callable, List, Sequence, Tuple

from .links import LINKS

MODES = (("raw", "Gửi raw key, IV, AAD, dữ liệu"), ("image", "Xử lý ảnh"), ("camera", "Camera realtime"))
SIMS = (("", "Phần cứng thật"), ("model", "Software model"), ("rtl", "Mô phỏng RTL (QuestaSim)"))


def choose(ask: Callable[[str], str], title: str, options: Sequence[Tuple[str, str]]) -> str:
    print(title)
    for number, (_, label) in enumerate(options, 1):
        print(f"  {number}. {label}")
    while True:
        answer = ask("Chọn: ").strip()
        if answer.isdigit() and 1 <= int(answer) <= len(options):
            return options[int(answer) - 1][0]
        print(f"Nhập số từ 1 đến {len(options)}")


def required(ask: Callable[[str], str], prompt: str) -> str:
    while True:
        answer = ask(prompt).strip()
        if answer:
            return answer
        print("Giá trị này là bắt buộc")


def ask_mode_options(ask: Callable[[str], str], mode: str) -> List[str]:
    if mode == "raw":
        path = ask("File nhị phân (Enter để nhập dữ liệu hex): ").strip()
        if path:
            return ["--file", path]
        options = ["--data", required(ask, "Dữ liệu hex: ")]
        tag = ask("Tag mong đợi để giải mã (Enter để mã hoá): ").strip()
        return options + (["--op", "decrypt", "--tag", tag] if tag else [])
    if mode == "image":
        path = ask("Ảnh hoặc thư mục (Enter để dùng input/): ").strip()
        size = ask("Kích thước WxH (Enter để dùng 256x256): ").strip()
        return ([path] if path else []) + (["--size", size] if size else [])

    size = ask("Kích thước khung WxH (Enter để dùng 640x480): ").strip()
    quality = ask("Chất lượng JPEG 1..100 (Enter để dùng 50): ").strip()
    fpga = ask("Giải mã trên FPGA? y/N: ").strip().lower() == "y"
    return ((["--size", size] if size else []) + (["--quality", quality] if quality else [])
            + (["--fpga-decrypt"] if fpga else []))


def ask_arguments(ask: Callable[[str], str]) -> List[str]:
    """Returns the command line that the answers stand for."""
    mode = choose(ask, "Chế độ xử lý", MODES)
    link = choose(ask, "Đường truyền", [(name, preset.label) for name, preset in LINKS.items()])
    sims = [option for option in SIMS if not (mode == "camera" and option[0] == "rtl")]
    sim = choose(ask, "Chạy trên", sims)
    arguments = [mode, *ask_mode_options(ask, mode), "--link", link]
    arguments += ["--sim", sim] if sim else []
    arguments += ["--key", required(ask, "Key hex (16 hoặc 32 byte): ")]
    arguments += ["--iv", required(ask, "IV hex (12 byte, mỗi lần chạy một giá trị mới): ")]
    aad = ask("AAD hex (Enter nếu không có): ").strip()
    return arguments + (["--aad", aad] if aad else [])
