"""Command line: image -> packet files -> FPGA (model, RTL or board) -> image."""

import argparse
import secrets
import sys
import time
from pathlib import Path
from typing import List, Optional, Tuple

from uart_protocol import (
    BURST_MESSAGES, CMD_LOAD_AAD, CMD_LOAD_KEY, DEFAULT_BAUD_RATE, MAX_DATA_BLOCKS, RESP_CIPHERTEXT,
)

from . import console, framing, gcm_model, image_io, packet_file, rtl_sim, spi_link, uart_link

APP_ROOT = Path(__file__).resolve().parents[1]
KEY_BYTES = {"aes128": 16, "aes256": 32}
IMAGE_SUFFIXES = {".png", ".jpg", ".jpeg", ".bmp", ".webp", ".tif", ".tiff", ".gif"}
BACKENDS = {"model": None, "rtl-spi": "spi", "rtl-uart": "uart"}


def parse_size(text: str) -> Tuple[int, int]:
    try:
        width, height = (int(part) for part in text.lower().split("x"))
    except ValueError:
        raise argparse.ArgumentTypeError(f"expected WIDTHxHEIGHT, got {text!r}")
    if not (0 < width < 65536 and 0 < height < 65536):
        raise argparse.ArgumentTypeError(f"size out of range: {text!r}")
    return width, height


def choose_key(key_hex: Optional[str], variant: str) -> bytes:
    if key_hex is None:
        return secrets.token_bytes(KEY_BYTES[variant])
    key = bytes.fromhex(key_hex)
    if len(key) != KEY_BYTES[variant]:
        raise ValueError(f"{variant} needs a {KEY_BYTES[variant]}-byte key, got {len(key)} bytes")
    return key


def read_header(messages: List[framing.Message]) -> framing.ImageHeader:
    return framing.ImageHeader.unpack(messages[0].aad)


def sim_config(args: argparse.Namespace) -> Optional[rtl_sim.SimConfig]:
    link = BACKENDS[args.backend]
    return link and rtl_sim.SimConfig(link, args.sclk_mhz, args.baud, args.window, args.uart_clk_mhz)


def answer_stream(packets: List[packet_file.Packet], name: str, config: Optional[rtl_sim.SimConfig],
                  report: console.Report) -> List[packet_file.Packet]:
    """Answers a TX stream with the model or the RTL, reporting which one it was."""
    if config is None:
        report.field("Nguồn", "software model (gcm_model), không phải RTL", "dim")
        return gcm_model.simulate(packets)

    report.field("Nguồn", "RTL QuestaSim, không phải board", "dim")
    report.field("Link", f"{config.describe()}, burst {config.window} message")
    result = rtl_sim.run_stream(packets, name, config)
    payload = sum(len(message.data) for message in framing.split_tx(packets)[1])
    status = f"STATUS 0x{result.statuses[-1]:02X} | " if result.statuses else ""
    report.field("Mô phỏng", f"{status}{result.frames} frame, {result.elapsed_s * 1e3:.2f} ms thời gian mô phỏng, "
                             f"{payload / result.elapsed_s / 1e6:.2f} MB/s payload")
    differences = uart_link.compare_with_model(packets, result.responses)
    if differences:
        for line in differences[:uart_link.MAX_REPORTED_DIFFERENCES]:
            report.line(f"[!] {line}", "fail")
        raise ValueError(f"RTL differs from the software model in {len(differences)} check(s)")
    return result.responses


def encode(image: Path, out_root: Path, args: argparse.Namespace, report: console.Report) -> Path:
    picture = image_io.load_image(image, args.size, args.fit, args.gray)
    width, height = picture.size
    channels = len(picture.getbands())
    pixels = picture.tobytes()
    out_dir = out_root / image.name
    out_dir.mkdir(parents=True, exist_ok=True)
    picture.save(out_dir / "preview.png")

    key = choose_key(args.key, args.variant)
    packets = framing.build_tx(pixels, width, height, key, args.chunk_blocks, channels=channels)
    messages = framing.split_tx(packets)[1]
    header = read_header(messages)
    depth = f"{'RGB' if channels == 3 else 'gray'}8"
    title = (f"{image.name} | key={len(key) * 8}-bit (demo only: sent in clear) | "
             f"{width}x{height} {depth} | {header.chunks} chunks | {len(pixels)} B")
    packet_file.write_stream(packets, out_dir / "tx", title)

    report.section("ENCODE", image.name)
    report.field("Ảnh", f"{width}x{height} {depth}, {len(pixels)} B, sha256 {console.digest(pixels)}")
    report.field("AES", f"AES-{len(key) * 8}-GCM, {header.chunks} chunk, {header.chunk_blocks} block/chunk")
    report.field("KEY", f"{console.grouped(key)}   (demo: gửi rõ)")
    report.field("IV", f"{console.grouped(messages[0].iv[:8])} + số thứ tự chunk 32 bit")
    report.field("AAD", console.grouped(messages[0].aad))
    report.field("", console.describe_aad(header))
    report.field("TX", f"{out_dir / 'tx.txt'}, tx.bin: {len(packets)} packet")
    return out_dir / "tx.bin"


def rx_base_for(tx_path: Path) -> Path:
    return tx_path.with_name(tx_path.stem.replace("tx", "rx", 1))


def simulate(tx_path: Path, config: Optional[rtl_sim.SimConfig], report: console.Report) -> Path:
    packets = packet_file.read_stream(tx_path)
    report.section("SIMULATE", "mã hoá")
    responses = answer_stream(packets, f"{tx_path.parent.name}_enc", config, report)
    rx_base = rx_base_for(tx_path)
    packet_file.write_stream(responses, rx_base, f"FPGA responses to {tx_path.name}")

    messages = framing.split_tx(packets)[1]
    replies = framing.split_rx(responses)
    report.chunk_table(f"{'chunk':<6} {'IV':<26} {'AAD':<5} TAG", [
        (f"{index:<6} {message.iv.hex():<26} {f'{len(message.aad)} B' if message.aad else '-':<5} {reply.tag.hex()}", "")
        for index, (message, reply) in enumerate(zip(messages, replies))])
    report.field("RX", f"{rx_base.with_suffix('.txt')}, rx.bin: {len(responses)} packet")
    return rx_base.with_suffix(".bin")


def save_board_answer(tx_path: Path, packets: List[packet_file.Packet], responses: List[packet_file.Packet],
                      elapsed: float, label: str) -> int:
    """Saves what the board answered and checks it against the model."""
    rx_base = rx_base_for(tx_path)
    packet_file.write_stream(responses, rx_base, f"FPGA responses to {tx_path.name} on {label}")
    data_bytes = sum(len(message.data) for message in framing.split_tx(packets)[1])
    print(f"[+] {rx_base.with_suffix('.txt')}: {elapsed:.2f} s, {data_bytes / 1024 / elapsed:.1f} KiB/s")

    differences = uart_link.compare_with_model(packets, responses)
    if differences:
        for line in differences[:uart_link.MAX_REPORTED_DIFFERENCES]:
            print(f"[!] {line}")
        print(f"[!] Board differs from the software model in {len(differences)} check(s)")
        return 1
    print("[+] Board output matches the software model")
    return 0


def send(tx_path: Path, port: Optional[str], baud: int, timeout: float, window: int = BURST_MESSAGES) -> int:
    """Plays a TX stream to the board over UART."""
    packets = packet_file.read_stream(tx_path)
    key, messages = framing.split_tx(packets)
    client = uart_link.open_client(key, port, baud, timeout)
    try:
        def show_progress(chunk: int) -> None:
            print(f"\r[*] {client.port} @ {client.baudrate}: chunk {chunk}/{len(messages)}", end="", flush=True)

        started = time.perf_counter()
        responses = uart_link.transfer(client, packets, show_progress, window)
        elapsed = time.perf_counter() - started
    finally:
        print()
        client.close()
    return save_board_answer(tx_path, packets, responses, elapsed, f"{client.port} @ {client.baudrate}")


def spi_send(tx_path: Path, url: str, sclk_mhz: float, window: int) -> int:
    """Plays a TX stream to the board over SPI, through an FT232H."""
    packets = packet_file.read_stream(tx_path)
    messages = framing.split_tx(packets)[1]
    link = spi_link.Ft232hLink(url, int(sclk_mhz * 1e6))
    try:
        def show_progress(chunk: int) -> None:
            print(f"\r[*] {url} @ {sclk_mhz:g} MHz: chunk {chunk}/{len(messages)}", end="", flush=True)

        started = time.perf_counter()
        responses = spi_link.transfer_spi(link, packets, show_progress, window)
        elapsed = time.perf_counter() - started
    finally:
        print()
        link.close()
    return save_board_answer(tx_path, packets, responses, elapsed, f"{url} @ {sclk_mhz:g} MHz")


def decode(tx_path: Path, rx_path: Optional[Path], output: Optional[Path], report: console.Report) -> Path:
    """Rebuilds an image from the TX payloads, or from the RX payloads to view the ciphertext."""
    _, messages = framing.split_tx(packet_file.read_stream(tx_path))
    header = read_header(messages)
    if rx_path:
        chunks = [reply.data for reply in framing.split_rx(packet_file.read_stream(rx_path))]
    else:
        chunks = [message.data for message in messages]
    pixels = framing.join_pixels(header, chunks)
    output = output or tx_path.with_name("cipher.png" if rx_path else "decoded.png")
    image_io.save_image(pixels, header.width, header.height, header.channels, output)

    report.section("DECODE", "ảnh mã" if rx_path else "ảnh từ TX")
    report.field("Ảnh", f"{output}: {header.width}x{header.height}, sha256 {console.digest(pixels)}")
    preview = tx_path.with_name("preview.png")
    if rx_path and preview.exists():
        report.pictures([("preview.png (ảnh gốc)", preview), ("cipher.png (ảnh mã)", output)])
    return output


def decrypt(tx_path: Path, rx_path: Path, output: Optional[Path], report: console.Report,
            rx_dec_path: Optional[Path] = None, config: Optional[rtl_sim.SimConfig] = None) -> Path:
    """Runs the ciphertext through START_DECRYPT and writes the image only if the IP verifies every tag.

    Uses the software model or the RTL unless rx_dec_path holds the board's answer to tx_dec.
    """
    output = output or tx_path.with_name("decrypted.png")
    output.unlink(missing_ok=True)  # A failed run must not leave an older image behind

    key, messages = framing.split_tx(packet_file.read_stream(tx_path))
    header = read_header(messages)
    encrypted = framing.split_rx(packet_file.read_stream(rx_path))
    expected_tags = [reply.tag for reply in encrypted]

    decrypt_tx = framing.build_decrypt_tx(key, messages, [reply.data for reply in encrypted], expected_tags)
    packet_file.write_stream(decrypt_tx, tx_path.with_name("tx_dec"), f"START_DECRYPT stream for {tx_path.name}")

    report.section("DECRYPT", "xác thực tag ngay trong IP")
    if rx_dec_path:
        report.field("Nguồn", f"câu trả lời của board: {rx_dec_path}", "dim")
        responses = packet_file.read_stream(rx_dec_path)
    else:
        responses = answer_stream(decrypt_tx, f"{tx_path.parent.name}_dec", config, report)
        packet_file.write_stream(responses, tx_path.with_name("rx_dec"), f"FPGA responses to {tx_path.name}")
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

    pixels = framing.join_pixels(header, [reply.data for reply in decrypted])
    image_io.save_image(pixels, header.width, header.height, header.channels, output)
    report.field("Ảnh", f"{output}: sha256 {console.digest(pixels)}, all {header.chunks} tags verified")
    report.pictures([("decrypted.png (ảnh giải mã)", output)])
    return output


def tamper(rx_path: Path, chunk: int) -> None:
    """Flips one ciphertext bit, as a corrupted link or an attacker would."""
    responses = packet_file.read_stream(rx_path)
    seen = -1
    for index, (cmd, payload) in enumerate(responses):
        seen += cmd == RESP_CIPHERTEXT
        if cmd == RESP_CIPHERTEXT and seen == chunk:
            responses[index] = (cmd, bytes([payload[0] ^ 1]) + payload[1:])
            packet_file.write_stream(responses, rx_path.with_suffix(""), f"Tampered chunk {chunk}")
            return
    raise ValueError(f"RX stream has no chunk {chunk}")


def run_image(image: Path, args: argparse.Namespace, config: Optional[rtl_sim.SimConfig],
              report: console.Report) -> None:
    tx_path = encode(image, args.output_dir, args, report)
    rx_path = simulate(tx_path, config, report)
    decode(tx_path, rx_path, None, report)
    if args.tamper_chunk is not None:
        tamper(rx_path, args.tamper_chunk)
        report.line()
        report.line(f"[!] Cố ý lật 1 bit ciphertext của chunk {args.tamper_chunk} trước khi giải mã", "fail")
    result = decrypt(tx_path, rx_path, None, report, config=config)
    if image_io.read_pixels(result) != image_io.read_pixels(tx_path.with_name("preview.png")):
        raise ValueError("decrypted image differs from preview.png")
    report.line(f"[+] {image.name}: round trip OK, pixel giống hệt ảnh gốc", "pass")


def run(args: argparse.Namespace) -> int:
    images = sorted(p for p in args.input_dir.iterdir() if p.suffix.lower() in IMAGE_SUFFIXES)
    if not images:
        print(f"[!] No images in {args.input_dir}")
        return 1

    config = sim_config(args)
    suffix = "_tamper" if args.tamper_chunk is not None else ""
    failed = 0
    for image in images:
        report = console.Report(args.show_chunks)
        try:
            run_image(image, args, config, report)
        except (ValueError, OSError) as error:
            report.line(f"[!] {image.name}: {error}", "fail")
            failed += 1
        folder = args.output_dir / image.name
        if folder.is_dir():
            report.save_png(folder / f"console_{args.backend}{suffix}.png")
    return 1 if failed else 0


def add_image_options(parser: argparse.ArgumentParser) -> None:
    parser.add_argument("--size", type=parse_size, default=(256, 256), help="Output size WIDTHxHEIGHT (default: 256x256)")
    parser.add_argument("--fit", choices=["crop", "pad"], default="crop", help="Match the aspect ratio by cropping or padding (default: crop)")
    parser.add_argument("-v", "--variant", choices=list(KEY_BYTES), default="aes256", help="AES core variant (default: aes256)")
    parser.add_argument("--key", help="Cipher key in hex (default: random)")
    parser.add_argument("--chunk-blocks", type=int, default=MAX_DATA_BLOCKS, metavar=f"1..{MAX_DATA_BLOCKS}",
                        help=f"16-byte blocks per GCM message (default: {MAX_DATA_BLOCKS})")
    parser.add_argument("--gray", action="store_true", help="Force one channel (default: keep color as RGB)")
    parser.add_argument("--output-dir", type=Path, default=APP_ROOT / "output", help="Output folder (default: output/)")


def add_window_option(parser: argparse.ArgumentParser) -> None:
    parser.add_argument("--window", type=int, default=BURST_MESSAGES,
                        help=f"Messages sent before reading their replies, 1 = stop-and-wait (default: {BURST_MESSAGES})")


def add_backend_options(parser: argparse.ArgumentParser) -> None:
    parser.add_argument("--backend", choices=list(BACKENDS), default="model",
                        help="What answers the stream: software model or RTL in QuestaSim (default: model)")
    parser.add_argument("--sclk-mhz", type=float, default=40.0, help="SPI clock for rtl-spi (default: 40)")
    parser.add_argument("--baud", type=int, default=DEFAULT_BAUD_RATE, help=f"Baud rate for rtl-uart (default: {DEFAULT_BAUD_RATE})")
    parser.add_argument("--uart-clk-mhz", type=float, default=0.0,
                        help="Run the UART of rtl-uart on its own clock, e.g. 120 for 12 Mbaud (default: same clock as the IP)")
    add_window_option(parser)


def add_report_options(parser: argparse.ArgumentParser) -> None:
    parser.add_argument("--show-chunks", type=int, default=3, help="First and last chunks to print (default: 3)")


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(prog="imgapp", description="8-bit image <-> AES-GCM packet streams")
    commands = parser.add_subparsers(dest="command", required=True)

    run_cmd = commands.add_parser("run", help="Encode, simulate, decode and decrypt every image in input/")
    run_cmd.add_argument("--input-dir", type=Path, default=APP_ROOT / "input", help="Input folder (default: input/)")
    run_cmd.add_argument("--tamper-chunk", type=int, metavar="N", help="Flip a ciphertext bit in chunk N before decrypting")
    add_image_options(run_cmd)
    add_backend_options(run_cmd)
    add_report_options(run_cmd)

    sample_cmd = commands.add_parser("sample", help="Write a color test image")
    sample_cmd.add_argument("-o", "--output", type=Path, default=APP_ROOT / "output" / "samples" / "color_test.png")
    sample_cmd.add_argument("--size", type=parse_size, default=(256, 256), help="Image size WIDTHxHEIGHT (default: 256x256)")

    encode_cmd = commands.add_parser("encode", help="Image -> tx.txt, tx.bin, preview.png")
    encode_cmd.add_argument("image", type=Path)
    add_image_options(encode_cmd)

    simulate_cmd = commands.add_parser("simulate", help="Answer a TX stream like the FPGA -> rx.txt, rx.bin")
    simulate_cmd.add_argument("tx", type=Path)
    add_backend_options(simulate_cmd)
    add_report_options(simulate_cmd)

    send_cmd = commands.add_parser("send", help="Send a TX stream to the FPGA over UART -> rx.txt, rx.bin")
    send_cmd.add_argument("tx", type=Path)
    send_cmd.add_argument("-p", "--port", help="Serial COM port, e.g. COM4 (default: auto-detect)")
    send_cmd.add_argument("-b", "--baud", type=int, default=DEFAULT_BAUD_RATE, help=f"UART baud rate (default: {DEFAULT_BAUD_RATE})")
    send_cmd.add_argument("-t", "--timeout", type=float, default=3.0, help="UART response timeout in seconds (default: 3.0)")
    add_window_option(send_cmd)

    spi_cmd = commands.add_parser("spi-send", help="Send a TX stream to the FPGA over SPI (FT232H) -> rx.txt, rx.bin")
    spi_cmd.add_argument("tx", type=Path)
    spi_cmd.add_argument("--url", default="ftdi://ftdi:232h/1", help="pyftdi URL of the FT232H (default: ftdi://ftdi:232h/1)")
    spi_cmd.add_argument("--sclk-mhz", type=float, default=15.0, help="SPI clock (default: 15)")
    add_window_option(spi_cmd)

    decode_cmd = commands.add_parser("decode", help="TX stream -> image, or RX stream -> ciphertext image")
    decode_cmd.add_argument("tx", type=Path)
    decode_cmd.add_argument("--rx", type=Path, help="Show this RX stream's payload instead of the TX payload")
    decode_cmd.add_argument("-o", "--output", type=Path)

    decrypt_cmd = commands.add_parser("decrypt", help="Decrypt an RX stream, verifying its tags in the IP -> image")
    decrypt_cmd.add_argument("tx", type=Path)
    decrypt_cmd.add_argument("rx", type=Path)
    decrypt_cmd.add_argument("--rx-dec", type=Path, help="Use the board's answer to tx_dec instead of the backend")
    decrypt_cmd.add_argument("-o", "--output", type=Path)
    add_backend_options(decrypt_cmd)
    add_report_options(decrypt_cmd)
    return parser


def main(argv: Optional[List[str]] = None) -> int:
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8")

    args = build_parser().parse_args(argv)
    report = console.Report(getattr(args, "show_chunks", 3))
    try:
        if args.command == "run":
            return run(args)
        if args.command == "sample":
            image_io.make_sample(args.output, args.size)
            print(f"[+] {args.output}")
        elif args.command == "encode":
            encode(args.image, args.output_dir, args, report)
        elif args.command == "simulate":
            simulate(args.tx, sim_config(args), report)
        elif args.command == "send":
            return send(args.tx, args.port, args.baud, args.timeout, args.window)
        elif args.command == "spi-send":
            return spi_send(args.tx, args.url, args.sclk_mhz, args.window)
        elif args.command == "decode":
            decode(args.tx, args.rx, args.output, report)
        elif args.command == "decrypt":
            decrypt(args.tx, args.rx, args.output, report, args.rx_dec, sim_config(args))
    except (ValueError, OSError) as error:
        print(f"[!] {error}")
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
