"""Command line of realtime_env: UART 12 Mbaud by default, everything else behind --advanced."""

import argparse
import os
import platform
import sys
import time
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable, List, Optional, Tuple

from . import codec, console, esp_link, framing, gcm_model, image_io, links, menu, packet_file, run_log, selftest
from .packet_file import Packet
from .protocol import (
    BURST_MESSAGES, CMD_LOAD_AAD, CMD_LOAD_IV, CMD_LOAD_KEY, CMD_LOAD_PLAINTEXT, CMD_LOAD_TAG_REF,
    CMD_START_DECRYPT, CMD_START_ENCRYPT, MAX_DATA_BLOCKS, MAX_DATA_BYTES,
)

APP_ROOT = Path(__file__).resolve().parents[1]
KEY_SIZES = (16, 32)
TAG_BYTES = 16
IMAGE_SUFFIXES = {".png", ".jpg", ".jpeg", ".bmp", ".webp", ".tif", ".tiff", ".gif"}
IV_WARNING = "[!] Mỗi cặp key + IV chỉ dùng một lần: lặp lại sẽ phá an toàn GCM. Hãy đổi IV sau mỗi lần chạy."
ADVANCED = "--advanced"
DEFAULT_LINK = "uart12m"
DEFAULT_QUALITY = 70
LOG_DIR_ENV = "REALTIME_ENV_LOG_DIR"  # Tests point this at a temporary folder
LOCKED_COMMANDS = ("selftest", "wifi-test", "sample")
# Everything the plain menu can ask for. Any other option needs --advanced
OPEN_OPTIONS = {"--link", "--sim", "--key", "--iv", "--aad", "-p", "--port", "--size", "--quality",
                "--fpga-decrypt", "--fps", "--data", "--file", "--op", "--tag"}
OPEN_SIMS = (None, "model")
LOGGED_COMMANDS = ("raw", "image", "camera", "selftest")


@dataclass
class Secrets:
    """Key, IV and AAD exactly as the user gave them, after block padding."""
    key: bytes
    iv: bytes
    aad: bytes


def parse_size(text: str) -> Tuple[int, int]:
    try:
        width, height = (int(part) for part in text.lower().split("x"))
    except ValueError:
        raise argparse.ArgumentTypeError(f"expected WIDTHxHEIGHT, got {text!r}")
    if not (0 < width < 65536 and 0 < height < 65536):
        raise argparse.ArgumentTypeError(f"size out of range: {text!r}")
    return width, height


def parse_hex(text: str, name: str, sizes: Optional[Iterable[int]] = None) -> bytes:
    cleaned = text.replace(" ", "").replace(":", "").replace("0x", "")
    try:
        data = bytes.fromhex(cleaned)
    except ValueError:
        raise ValueError(f"{name} is not valid hex: {text!r}") from None
    if sizes is not None and len(data) not in tuple(sizes):
        wanted = " or ".join(map(str, sizes))
        raise ValueError(f"{name} must be {wanted} bytes, got {len(data)}")
    return data


def read_secrets(args: argparse.Namespace, report: console.Report) -> Secrets:
    key = parse_hex(args.key, "Key", KEY_SIZES)
    iv = parse_hex(args.iv, "IV", (framing.IV_BYTES,))
    aad = parse_hex(args.aad, "AAD")
    if len(aad) > MAX_DATA_BYTES:
        raise ValueError(f"AAD must be at most {MAX_DATA_BYTES} bytes, got {len(aad)}")
    padded = framing.zero_pad(aad)
    if padded != aad:
        report.line(f"[!] AAD được đệm 0 từ {len(aad)} lên {len(padded)} byte: tag khác tag của AAD gốc.", "fail")
    report.line(IV_WARNING, "fail")
    return Secrets(key, iv, padded)


def link_options(args: argparse.Namespace) -> links.Options:
    return links.Options(args.window, args.port, args.timeout, args.esp_host, args.ftdi_url, args.paced)


def answer_stream(packets: List[Packet], name: str, channel, report: console.Report) -> List[Packet]:
    """Runs a stream through the channel, reporting the speed and checking it against the model."""
    report.field("Nguồn", channel.label, "dim")
    result = channel.exchange(packets, name)
    payload = sum(len(message.data) for message in framing.split_tx(packets)[1])
    note = f"{result.note}, " if result.note else ""
    rate = payload / max(result.elapsed_s, 1e-9) / 1e6
    report.field("Truyền", f"{note}{result.elapsed_s * 1e3:.2f} ms, {rate:.2f} MB/s payload")
    run_log.event("link", f"{name}: {len(packets)} gói, tx {framing.wire_bytes(packets)} B, "
                          f"rx {framing.wire_bytes(result.responses)} B, {result.elapsed_s * 1e3:.2f} ms, "
                          f"{rate:.3f} MB/s payload")
    if not channel.is_model:
        differences = links.compare_with_model(packets, result.responses)
        if differences:
            for line in differences[:links.MAX_REPORTED_DIFFERENCES]:
                report.line(f"[!] {line}", "fail")
            raise ValueError(f"Link answer differs from the software model in {len(differences)} check(s)")
    return result.responses


def report_overhead(packets: List[Packet], responses: List[Packet], data_bytes: int, report: console.Report) -> None:
    sent, received = framing.wire_bytes(packets), framing.wire_bytes(responses)
    extra = (sent + received) / (2 * data_bytes) - 1
    report.field("Đường dây", f"{sent} B đi, {received} B về, overhead {extra * 100:.1f}%")


def decrypt_and_verify(key: bytes, messages: List[framing.Message], encrypted: List[framing.Reply], folder: Path,
                       channel, report: console.Report) -> List[framing.Reply]:
    """Runs the ciphertext through START_DECRYPT and raises unless the IP verifies every tag."""
    expected_tags = [reply.tag for reply in encrypted]
    decrypt_tx = framing.build_decrypt_tx(key, messages, [reply.data for reply in encrypted], expected_tags)
    packet_file.write_stream(decrypt_tx, folder / "tx_dec", "START_DECRYPT stream")

    report.section("DECRYPT", "xác thực tag ngay trong IP")
    responses = answer_stream(decrypt_tx, f"{folder.name}_dec", channel, report)
    packet_file.write_stream(responses, folder / "rx_dec", "IP responses to tx_dec")
    decrypted = framing.split_rx(responses)

    rows = []
    failed = []
    for index, (want, reply) in enumerate(zip(expected_tags, decrypted)):
        passed = bool(reply.verified) and want == reply.tag
        failed += [] if passed else [index]
        note = "PASS" if passed else "FAIL, IP không xuất plaintext"
        rows.append((f"{index:<6} {want.hex():<33} {reply.tag.hex():<33} {note}", "pass" if passed else "fail"))
    report.chunk_table(f"{'chunk':<6} {'TAG-REF':<33} {'TAG tính được':<33} VERIFY", rows, failed)
    report.field("VERIFY", f"{sum(bool(reply.verified) for reply in decrypted)}/{len(decrypted)} PASS",
                 "fail" if failed else "pass")
    framing.check_replies(expected_tags, decrypted)
    return decrypted


def report_secrets(secrets: Secrets, report: console.Report) -> None:
    report.field("KEY", f"{console.grouped(secrets.key)}   (AES-{len(secrets.key) * 8}, gửi rõ, chỉ dùng key demo)")
    report.field("IV", f"{console.grouped(secrets.iv)}   (chunk đầu, 32 bit cuối tăng theo chunk)")
    report.field("AAD", console.grouped(secrets.aad) if secrets.aad else "(không có)")


def encrypt_rows(messages: List[framing.Message], replies: List[framing.Reply]) -> List[Tuple[str, str]]:
    return [(f"{index:<6} {message.iv.hex():<26} {f'{len(message.aad)} B' if message.aad else '-':<5} {reply.tag.hex()}", "")
            for index, (message, reply) in enumerate(zip(messages, replies))]


def run_image(image: Path, args: argparse.Namespace, secrets: Secrets, channel, report: console.Report) -> None:
    """ENCODE, send, DECODE and DECRYPT one image. Raises unless every pixel comes back."""
    picture = image_io.load_image(image, args.size, args.fit, args.gray)
    width, height = picture.size
    channels = len(picture.getbands())
    pixels = picture.tobytes()
    folder = args.output_dir / image.name
    folder.mkdir(parents=True, exist_ok=True)
    (folder / "decrypted.png").unlink(missing_ok=True)  # A failed run must not leave an older image behind
    picture.save(folder / "preview.png")

    packets = framing.build_tx(pixels, secrets.key, secrets.iv, secrets.aad, args.chunk_blocks)
    key, messages = framing.split_tx(packets)
    layout = framing.Layout(len(pixels), len(messages), args.chunk_blocks, width, height, channels)
    layout.save(folder / "session.json")
    depth = f"{'RGB' if channels == 3 else 'gray'}8"
    packet_file.write_stream(packets, folder / "tx", f"{image.name} | {width}x{height} {depth} | {layout.chunks} chunks")

    report.section("ENCODE", image.name)
    report.field("Ảnh", f"{width}x{height} {depth}, {len(pixels)} B, sha256 {console.digest(pixels)}")
    report.field("AES", f"AES-{len(key) * 8}-GCM, {layout.chunks} chunk, {layout.chunk_blocks} block/chunk")
    report_secrets(secrets, report)

    report.section("SIMULATE" if args.sim else "SEND", "mã hoá")
    responses = answer_stream(packets, f"{folder.name}_enc", channel, report)
    report_overhead(packets, responses, len(pixels), report)
    if args.tamper_chunk is not None:
        responses = framing.flip_ciphertext(responses, args.tamper_chunk)
        report.line(f"[!] Cố ý lật 1 bit ciphertext của chunk {args.tamper_chunk} trước khi giải mã", "fail")
    packet_file.write_stream(responses, folder / "rx", "IP responses to tx")
    encrypted = framing.split_rx(responses)
    report.chunk_table(f"{'chunk':<6} {'IV':<26} {'AAD':<5} TAG", encrypt_rows(messages, encrypted))

    report.section("DECODE", "ảnh mã")
    cipher = framing.join_chunks(layout, [reply.data for reply in encrypted])
    image_io.save_image(cipher, width, height, channels, folder / "cipher.png")
    report.field("Ảnh", f"{folder / 'cipher.png'}: sha256 {console.digest(cipher)}")
    report.pictures([("preview.png (ảnh gốc)", folder / "preview.png"), ("cipher.png (ảnh mã)", folder / "cipher.png")])

    decrypted = decrypt_and_verify(key, messages, encrypted, folder, channel, report)
    restored = framing.join_chunks(layout, [reply.data for reply in decrypted])
    image_io.save_image(restored, width, height, channels, folder / "decrypted.png")
    report.pictures([("decrypted.png (ảnh giải mã)", folder / "decrypted.png")])
    if restored != pixels:
        raise ValueError("decrypted image differs from preview.png")
    report.line(f"[+] {image.name}: round trip OK, pixel giống hệt ảnh gốc, all {layout.chunks} tags verified", "pass")


def image_paths(sources: List[Path]) -> List[Path]:
    paths = []
    for source in sources:
        if source.is_dir():
            paths += sorted(p for p in source.iterdir() if p.suffix.lower() in IMAGE_SUFFIXES)
        else:
            paths.append(source)
    return paths


def image_mode(args: argparse.Namespace) -> int:
    images = image_paths(args.images or [APP_ROOT / "input"])
    if not images:
        print("[!] No images to process")
        return 1

    args.output_dir.mkdir(parents=True, exist_ok=True)
    first = console.Report(args.show_chunks)
    secrets = read_secrets(args, first)
    channel = links.open_channel(args.link, args.sim, link_options(args), secrets.key)
    suffix = "_tamper" if args.tamper_chunk is not None else ""
    failed = 0
    iv = secrets.iv
    try:
        for index, image in enumerate(images):
            report = first if index == 0 else console.Report(args.show_chunks)
            current = Secrets(secrets.key, iv, secrets.aad)
            try:
                run_image(image, args, current, channel, report)
                chunks = framing.Layout.load(args.output_dir / image.name / "session.json").chunks
                iv = framing.advance_iv(iv, chunks)  # Several images under one key must not share an IV
            except (ValueError, OSError, TimeoutError) as error:
                report.line(f"[!] {image.name}: {error}", "fail")
                failed += 1
            folder = args.output_dir / image.name
            if folder.is_dir():
                report.save_png(folder / f"console_{args.sim or args.link}{suffix}.png")
    finally:
        channel.close()
    return 1 if failed else 0


def raw_packets(secrets: Secrets, data: bytes, tag: bytes, decrypt: bool) -> List[Packet]:
    packets = [(CMD_LOAD_KEY, secrets.key), (CMD_LOAD_IV, secrets.iv)]
    if secrets.aad:
        packets.append((CMD_LOAD_AAD, secrets.aad))
    packets.append((CMD_LOAD_PLAINTEXT, data))
    if decrypt:
        packets.append((CMD_LOAD_TAG_REF, tag))
    packets.append((CMD_START_DECRYPT if decrypt else CMD_START_ENCRYPT, b""))
    return packets


def raw_message(args: argparse.Namespace, secrets: Secrets, channel, report: console.Report) -> int:
    """Sends exactly one GCM message built from the values on the command line."""
    data = parse_hex(args.data, "Data")
    if not data or len(data) > MAX_DATA_BYTES:
        raise ValueError(f"Data must be 1..{MAX_DATA_BYTES} bytes for one message, got {len(data)}: use --file for more")
    padded = framing.zero_pad(data)
    if padded != data:
        report.line(f"[!] Dữ liệu được đệm 0 từ {len(data)} lên {len(padded)} byte: tag khác tag của dữ liệu gốc.", "fail")
    decrypt = args.op == "decrypt"
    if decrypt and args.tag is None:
        raise ValueError("Decrypt needs --tag, the expected tag")
    tag = parse_hex(args.tag, "Tag", (TAG_BYTES,)) if decrypt else b""

    report.section("RAW", args.op)
    report_secrets(secrets, report)
    report.field("Dữ liệu", console.grouped(padded))
    if decrypt:
        report.field("TAG-REF", tag.hex())
    packets = raw_packets(secrets, padded, tag, decrypt)
    reply = framing.split_rx(answer_stream(packets, "raw", channel, report))[0]
    report.field("Kết quả", console.grouped(reply.data) if reply.data else "(IP không xuất dữ liệu)")
    report.field("TAG", reply.tag.hex())
    if decrypt:
        report.field("VERIFY", "PASS" if reply.verified else "FAIL", "pass" if reply.verified else "fail")
        return 0 if reply.verified else 1
    return 0


def raw_file(args: argparse.Namespace, secrets: Secrets, channel, report: console.Report) -> int:
    """Encrypts and decrypts any binary file, and compares every byte."""
    path = Path(args.file)
    data = path.read_bytes()
    folder = args.output_dir / path.name
    folder.mkdir(parents=True, exist_ok=True)
    result = folder / f"decrypted{path.suffix}"
    result.unlink(missing_ok=True)  # A failed run must not leave an older file behind

    packets = framing.build_tx(data, secrets.key, secrets.iv, secrets.aad, args.chunk_blocks)
    key, messages = framing.split_tx(packets)
    layout = framing.Layout(len(data), len(messages), args.chunk_blocks)
    layout.save(folder / "session.json")
    packet_file.write_stream(packets, folder / "tx", f"{path.name} | {layout.chunks} chunks")

    report.section("ENCODE", path.name)
    report.field("File", f"{len(data)} B, sha256 {console.digest(data)}, {layout.chunks} chunk")
    report_secrets(secrets, report)

    report.section("SIMULATE" if args.sim else "SEND", "mã hoá")
    responses = answer_stream(packets, f"{folder.name}_enc", channel, report)
    report_overhead(packets, responses, len(data), report)
    if args.tamper_chunk is not None:
        responses = framing.flip_ciphertext(responses, args.tamper_chunk)
        report.line(f"[!] Cố ý lật 1 bit ciphertext của chunk {args.tamper_chunk} trước khi giải mã", "fail")
    packet_file.write_stream(responses, folder / "rx", "IP responses to tx")
    encrypted = framing.split_rx(responses)
    report.chunk_table(f"{'chunk':<6} {'IV':<26} {'AAD':<5} TAG", encrypt_rows(messages, encrypted))

    decrypted = decrypt_and_verify(key, messages, encrypted, folder, channel, report)
    restored = framing.join_chunks(layout, [reply.data for reply in decrypted])
    if restored != data:
        raise ValueError("Decrypted file differs from the original")
    result.write_bytes(restored)
    report.line(f"[+] {result}: khớp từng byte, all {layout.chunks} tags verified", "pass")
    return 0


def raw_mode(args: argparse.Namespace) -> int:
    if bool(args.data) == bool(args.file):
        raise ValueError("Give exactly one of --data and --file")
    report = console.Report(args.show_chunks)
    secrets = read_secrets(args, report)
    args.output_dir.mkdir(parents=True, exist_ok=True)
    channel = links.open_channel(args.link, args.sim, link_options(args), secrets.key)
    try:
        return (raw_file if args.file else raw_message)(args, secrets, channel, report)
    finally:
        channel.close()


def camera_mode(args: argparse.Namespace) -> int:
    from . import camera  # Needs OpenCV, the other modes do not

    if args.sim == "rtl":
        raise ValueError("Camera needs real time: use --sim emu or model, or no --sim for the hardware")
    if (args.realtime or args.loop) and not args.source:
        raise ValueError("--realtime and --loop replay a video: give --source")
    if args.loop and args.no_window and not args.frames:
        raise ValueError("--loop with --no-window would never end: give --frames")
    if args.fps < 0:
        raise ValueError("--fps cannot be negative")
    if args.fps and args.source and not args.realtime:
        raise ValueError("--fps limits a live source: add --realtime to replay the video")
    report = console.Report()
    secrets = read_secrets(args, report)
    channel = links.open_channel(args.link, args.sim, link_options(args), secrets.key)
    try:
        return camera.run(args, secrets, channel, report)
    finally:
        channel.close()


def selftest_mode(args: argparse.Namespace) -> int:
    key_bytes = args.aes // 8
    report = console.Report()
    channel = links.open_channel(args.link, args.sim, link_options(args), bytes(key_bytes))
    try:
        return selftest.run(channel, key_bytes, report)
    finally:
        channel.close()


def wifi_test_mode(args: argparse.Namespace) -> int:
    result = esp_link.wifi_test(args.esp_host, args.mb, args.rounds, spi_load=args.spi_load)
    lines = esp_link.describe(result)
    print("\n".join(lines))
    if args.out:
        args.out.write_text("\n".join(lines) + "\n", encoding="utf-8")
    return 0


def add_link_options(parser: argparse.ArgumentParser) -> None:
    parser.add_argument("--link", choices=list(links.LINKS), default=DEFAULT_LINK,
                        help=f"Link to the IP (default: {DEFAULT_LINK}; others need {ADVANCED})")
    parser.add_argument("--sim", choices=["model", "rtl", "emu"],
                        help=f"Replace the hardware: software model, QuestaSim, or the model on the measured timing "
                             f"of the link (rtl and emu need {ADVANCED})")
    parser.add_argument("--window", type=int, default=BURST_MESSAGES,
                        help=f"Messages sent before reading their replies, 1 = stop-and-wait (default: {BURST_MESSAGES})")
    parser.add_argument("--paced", action="store_true",
                        help="spi40 only: the ESP32 paces the bursts, so the PC waits for Wi-Fi once per frame. Not yet proven on the kit")
    parser.add_argument("-p", "--port", help="Serial port for uart2m and uart12m (default: auto-detect)")
    parser.add_argument("-t", "--timeout", type=float, default=3.0, help="Reply timeout in seconds (default: 3.0)")
    parser.add_argument("--esp-host", default="192.168.4.1", help="ESP32 bridge address for spi40 (default: 192.168.4.1)")
    parser.add_argument("--ftdi-url", default="ftdi://ftdi:232h/1", help="pyftdi URL for spi30 (default: ftdi://ftdi:232h/1)")


def add_common_options(parser: argparse.ArgumentParser) -> None:
    add_link_options(parser)
    parser.add_argument("--key", required=True, help="Key in hex, 16 or 32 bytes: picks AES-128 or AES-256")
    parser.add_argument("--iv", required=True, help="IV in hex, 12 bytes. Use a new one for every run")
    parser.add_argument("--aad", default="", help="AAD in hex, up to 240 bytes (default: none)")


def add_output_options(parser: argparse.ArgumentParser) -> None:
    parser.add_argument("--chunk-blocks", type=int, default=MAX_DATA_BLOCKS, metavar=f"1..{MAX_DATA_BLOCKS}",
                        help=f"16-byte blocks per GCM message (default: {MAX_DATA_BLOCKS})")
    parser.add_argument("--tamper-chunk", type=int, metavar="N", help="Flip a ciphertext bit in chunk N before decrypting")
    parser.add_argument("--show-chunks", type=int, default=3, help="First and last chunks to print (default: 3)")
    parser.add_argument("--output-dir", type=Path, default=APP_ROOT / "output", help="Output folder (default: output/)")


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="main.py", description=f"AES-GCM IP over UART 12 Mbaud. No command: menu. {ADVANCED} unlocks the other "
                                    f"links, simulators and options, in the menu and here.")
    parser.add_argument(ADVANCED, action="store_true", help="Unlock every link, simulator, option and command")
    commands = parser.add_subparsers(dest="command")

    raw_cmd = commands.add_parser("raw", help="One message from your own values, or one binary file")
    add_common_options(raw_cmd)
    add_output_options(raw_cmd)
    raw_cmd.add_argument("--data", help=f"Data in hex, up to {MAX_DATA_BYTES} bytes: one GCM message")
    raw_cmd.add_argument("--file", help="Any file: chunked, encrypted, decrypted and compared byte for byte")
    raw_cmd.add_argument("--op", choices=["encrypt", "decrypt"], default="encrypt", help="For --data (default: encrypt)")
    raw_cmd.add_argument("--tag", help="Expected tag in hex, for --op decrypt")

    image_cmd = commands.add_parser("image", help="Encrypt and decrypt images, with console evidence")
    image_cmd.add_argument("images", nargs="*", type=Path, help="Image files or folders (default: input/)")
    add_common_options(image_cmd)
    add_output_options(image_cmd)
    image_cmd.add_argument("--size", type=parse_size, default=(256, 256), help="Size WIDTHxHEIGHT (default: 256x256)")
    image_cmd.add_argument("--fit", choices=["crop", "pad"], default="crop", help="Match the aspect ratio (default: crop)")
    image_cmd.add_argument("--gray", action="store_true", help="Force one channel (default: keep color as RGB)")

    camera_cmd = commands.add_parser("camera", help="Realtime: the PC compresses JPEG, the IP encrypts")
    add_common_options(camera_cmd)
    camera_cmd.add_argument("--size", type=parse_size, default=(640, 480), help="Frame size WIDTHxHEIGHT (default: 640x480)")
    camera_cmd.add_argument("--quality", type=int, default=DEFAULT_QUALITY,
                            help=f"Quality 1..100, CRF 51-0.4q for H.264 (default: {DEFAULT_QUALITY}, CRF 23)")
    camera_cmd.add_argument("--codec", choices=codec.CODECS, default="h264",
                            help="Frame codec: h264 sends 5-10x fewer bytes, jpeg keeps every frame on its own (default: h264)")
    camera_cmd.add_argument("--fpga-decrypt", action="store_true", help="Decrypt and verify in the IP too: about half the frame rate")
    camera_cmd.add_argument("--source", help="Video file instead of the camera")
    camera_cmd.add_argument("--camera-index", type=int, default=0, help="Camera number (default: 0)")
    camera_cmd.add_argument("--frames", type=int, default=0, help="Stop after N frames (default: until q or end of file)")
    camera_cmd.add_argument("--no-window", action="store_true", help="Do not open a window")
    camera_cmd.add_argument("--realtime", action="store_true", help="Play --source at its own frame rate, dropping late frames as a camera does")
    camera_cmd.add_argument("--loop", action="store_true", help="Restart --source when it ends")
    camera_cmd.add_argument("--tamper-every", type=int, default=0, metavar="N", help="Flip a ciphertext bit in every Nth frame before decrypting")
    camera_cmd.add_argument("--fps", type=float, default=0.0, metavar="N",
                            help="Live source: send at most N frames per second (default: all the camera gives)")

    selftest_cmd = commands.add_parser("selftest", help="NIST vectors through the link")
    add_link_options(selftest_cmd)
    selftest_cmd.add_argument("--aes", type=int, choices=(128, 256), default=256, help="Key size (default: 256)")

    sample_cmd = commands.add_parser("sample", help="Write a color test image")
    sample_cmd.add_argument("-o", "--output", type=Path, default=APP_ROOT / "input" / "color_test.png")
    sample_cmd.add_argument("--size", type=parse_size, default=(256, 256), help="Image size WIDTHxHEIGHT (default: 256x256)")

    wifi_cmd = commands.add_parser("wifi-test", help="Measure the Wi-Fi hop to the ESP32 bridge")
    wifi_cmd.add_argument("--esp-host", default="192.168.4.1", help="ESP32 address (default: 192.168.4.1)")
    wifi_cmd.add_argument("--mb", type=int, default=4, help="Megabytes per run (default: 4)")
    wifi_cmd.add_argument("--rounds", type=int, default=3, help="Runs, keeping the best (default: 3)")
    wifi_cmd.add_argument("--spi-load", action="store_true", help="Keep SPI running at 40 MHz during the test. The FPGA need not be connected")
    wifi_cmd.add_argument("--out", type=Path, help="Also write the result to this file")
    return parser


def locked_by(args: argparse.Namespace, argv: List[str]) -> Optional[str]:
    """Names what in this command line needs --advanced, or returns None."""
    if args.command in LOCKED_COMMANDS:
        return f"Lệnh {args.command}"
    for token in argv:
        option = token.split("=", 1)[0]
        if option.startswith("-") and option not in OPEN_OPTIONS and not option.lstrip("-").replace(".", "").isdigit():
            return option
    if getattr(args, "link", DEFAULT_LINK) != DEFAULT_LINK:
        return f"--link {args.link}"
    if getattr(args, "sim", None) not in OPEN_SIMS:
        return f"--sim {args.sim}"
    if args.command == "camera" and args.codec != "h264":
        return f"--codec {args.codec}"
    return None


def log_dir() -> Path:
    return Path(os.environ.get(LOG_DIR_ENV) or APP_ROOT / "logs")


def describe_run(args: argparse.Namespace) -> str:
    values = {name: (str(value) if isinstance(value, Path) else value) for name, value in vars(args).items()
              if name != "command" and value not in (None, False, "")}
    return ", ".join(f"{name}={value}" for name, value in values.items())


def start_log(args: argparse.Namespace, argv: List[str]) -> None:
    columns = run_log.FRAME_COLUMNS if args.command == "camera" else None
    log = run_log.start(log_dir(), args.command, getattr(args, "link", DEFAULT_LINK), columns)
    preset = links.LINKS[args.link]
    speed = f"{preset.baud} baud" if preset.baud else f"SCLK {preset.sclk_mhz} MHz"
    run_log.info("start", "main.py " + " ".join(argv))
    run_log.info("link", f"{args.link}: {preset.label}, {speed}, chạy trên {args.sim or 'phần cứng'}")
    run_log.info("args", describe_run(args))
    run_log.info("host", f"Python {platform.python_version()}, {platform.platform()}")
    print(f"[log] {log.path}")


def dispatch(args: argparse.Namespace) -> int:
    if args.command == "raw":
        return raw_mode(args)
    if args.command == "image":
        return image_mode(args)
    if args.command == "camera":
        return camera_mode(args)
    if args.command == "selftest":
        return selftest_mode(args)
    if args.command == "wifi-test":
        return wifi_test_mode(args)
    image_io.make_sample(args.output, args.size)
    print(f"[+] {args.output}")
    return 0


def run_command(argv: List[str], advanced: bool) -> int:
    """Runs one command line, logging it. --advanced may stand anywhere in `argv`."""
    advanced = advanced or ADVANCED in argv
    argv = [token for token in argv if token != ADVANCED]
    try:
        args = build_parser().parse_args(argv)
    except SystemExit as stop:  # argparse has printed why
        return int(stop.code or 0)
    reason = None if advanced else locked_by(args, argv)
    if reason:
        print(f"[!] {reason} cần {ADVANCED}: python main.py {ADVANCED} ...")
        return 2
    logged = args.command in LOGGED_COMMANDS
    code = 1
    try:
        if logged:
            start_log(args, ([ADVANCED] if advanced else []) + argv)
        code = dispatch(args)
    except (ValueError, OSError, TimeoutError) as error:
        print(f"[!] {error}")
        run_log.error("run", error)
    except KeyboardInterrupt:
        print("[!] Đã dừng")
        run_log.event("stop", "Ctrl+C")
    finally:
        if logged:
            run_log.info("end", f"mã thoát {code}")
            run_log.finish()
    return code


def main(argv: Optional[List[str]] = None) -> int:
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8")

    argv = sys.argv[1:] if argv is None else argv
    advanced = ADVANCED in argv
    rest = [token for token in argv if token != ADVANCED]
    if not rest:
        return menu.run_menu(input, lambda arguments: run_command(arguments, advanced), advanced)
    return run_command(rest, advanced)
