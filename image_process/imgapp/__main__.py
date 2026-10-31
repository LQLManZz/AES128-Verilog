"""Command line: image -> UART packet files -> simulated FPGA -> image."""

import argparse
import secrets
import sys
import time
from pathlib import Path
from typing import List, Optional, Tuple

from uart_protocol import MAX_DATA_BLOCKS

from . import framing, gcm_model, image_io, packet_file, uart_link

APP_ROOT = Path(__file__).resolve().parents[1]
KEY_BYTES = {"aes128": 16, "aes256": 32}
IMAGE_SUFFIXES = {".png", ".jpg", ".jpeg", ".bmp", ".webp", ".tif", ".tiff", ".gif"}


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


def encode(image: Path, out_root: Path, args: argparse.Namespace) -> Path:
    gray = image_io.load_gray(image, args.size, args.fit)
    width, height = gray.size
    pixels = gray.tobytes()
    out_dir = out_root / image.name
    out_dir.mkdir(parents=True, exist_ok=True)
    gray.save(out_dir / "preview.png")

    key = choose_key(args.key, args.variant)
    packets = framing.build_tx(pixels, width, height, key, args.chunk_blocks)
    header = read_header(framing.split_tx(packets)[1])
    title = (f"{image.name} | key={len(key) * 8}-bit (demo only: sent in clear) | "
             f"{width}x{height} gray8 | {header.chunks} chunks | {len(pixels)} B")
    packet_file.write_stream(packets, out_dir / "tx", title)
    print(f"[+] {out_dir / 'tx.txt'}: {title}")
    return out_dir / "tx.bin"


def rx_base_for(tx_path: Path) -> Path:
    return tx_path.with_name(tx_path.stem.replace("tx", "rx", 1))


def simulate(tx_path: Path) -> Path:
    responses = gcm_model.simulate(packet_file.read_stream(tx_path))
    rx_base = rx_base_for(tx_path)
    packet_file.write_stream(responses, rx_base, f"Simulated FPGA responses to {tx_path.name}")
    print(f"[+] {rx_base.with_suffix('.txt')}: {len(responses)} packets")
    return rx_base.with_suffix(".bin")


def send(tx_path: Path, port: Optional[str], baud: int, timeout: float) -> int:
    """Plays a TX stream to the board, saves its replies and checks them against the model."""
    packets = packet_file.read_stream(tx_path)
    key, messages = framing.split_tx(packets)
    client = uart_link.open_client(key, port, baud, timeout)
    try:
        def show_progress(chunk: int) -> None:
            print(f"\r[*] {client.port} @ {client.baudrate}: chunk {chunk}/{len(messages)}", end="", flush=True)

        started = time.perf_counter()
        responses = uart_link.transfer(client, packets, show_progress)
        elapsed = time.perf_counter() - started
    finally:
        print()
        client.close()

    rx_base = rx_base_for(tx_path)
    packet_file.write_stream(responses, rx_base, f"FPGA responses to {tx_path.name} on {client.port} @ {client.baudrate}")
    data_bytes = sum(len(message.data) for message in messages)
    print(f"[+] {rx_base.with_suffix('.txt')}: {elapsed:.2f} s, {data_bytes / 1024 / elapsed:.1f} KiB/s")

    differences = uart_link.compare_with_model(packets, responses)
    if differences:
        for line in differences[:uart_link.MAX_REPORTED_DIFFERENCES]:
            print(f"[!] {line}")
        print(f"[!] Board differs from the software model in {len(differences)} check(s)")
        return 1
    print("[+] Board output matches the software model")
    return 0


def decode(tx_path: Path, rx_path: Optional[Path], output: Optional[Path]) -> Path:
    """Rebuilds an image from the TX payloads, or from the RX payloads to view the ciphertext."""
    _, messages = framing.split_tx(packet_file.read_stream(tx_path))
    header = read_header(messages)
    if rx_path:
        chunks = [data for data, _ in framing.split_rx(packet_file.read_stream(rx_path))]
    else:
        chunks = [message.data for message in messages]
    pixels = framing.join_pixels(header, chunks)
    output = output or tx_path.with_name("cipher.png" if rx_path else "decoded.png")
    image_io.save_gray(pixels, header.width, header.height, output)
    print(f"[+] {output}: {header.width}x{header.height}")
    return output


def decrypt(tx_path: Path, rx_path: Path, output: Optional[Path], rx_dec_path: Optional[Path] = None) -> Path:
    """Runs the ciphertext through START_DECRYPT and writes the image only if every tag matches.

    Uses the software model unless rx_dec_path holds the board's answer to tx_dec.
    """
    output = output or tx_path.with_name("decrypted.png")
    output.unlink(missing_ok=True)  # A failed run must not leave an older image behind

    key, messages = framing.split_tx(packet_file.read_stream(tx_path))
    header = read_header(messages)
    encrypted = framing.split_rx(packet_file.read_stream(rx_path))
    ciphertexts = [data for data, _ in encrypted]
    expected_tags = [tag for _, tag in encrypted]

    decrypt_tx = framing.build_decrypt_tx(key, messages, ciphertexts)
    packet_file.write_stream(decrypt_tx, tx_path.with_name("tx_dec"), f"START_DECRYPT stream for {tx_path.name}")
    responses = packet_file.read_stream(rx_dec_path) if rx_dec_path else gcm_model.simulate(decrypt_tx)
    decrypted = framing.split_rx(responses)
    framing.check_tags(expected_tags, [tag for _, tag in decrypted])

    pixels = framing.join_pixels(header, [data for data, _ in decrypted])
    image_io.save_gray(pixels, header.width, header.height, output)
    print(f"[+] {output}: all {header.chunks} tags verified")
    return output


def run(args: argparse.Namespace) -> int:
    images = sorted(p for p in args.input_dir.iterdir() if p.suffix.lower() in IMAGE_SUFFIXES)
    if not images:
        print(f"[!] No images in {args.input_dir}")
        return 1

    failed = 0
    for image in images:
        try:
            tx_path = encode(image, args.output_dir, args)
            rx_path = simulate(tx_path)
            decode(tx_path, rx_path, None)
            result = decrypt(tx_path, rx_path, None)
            if image_io.read_pixels(result) != image_io.read_pixels(tx_path.with_name("preview.png")):
                raise ValueError("decrypted image differs from preview.png")
            print(f"[+] {image.name}: round trip OK")
        except (ValueError, OSError) as error:
            print(f"[!] {image.name}: {error}")
            failed += 1
    return 1 if failed else 0


def add_image_options(parser: argparse.ArgumentParser) -> None:
    parser.add_argument("--size", type=parse_size, default=(256, 256), help="Output size WIDTHxHEIGHT (default: 256x256)")
    parser.add_argument("--fit", choices=["crop", "pad"], default="crop", help="Match the aspect ratio by cropping or padding (default: crop)")
    parser.add_argument("-v", "--variant", choices=list(KEY_BYTES), default="aes256", help="AES core variant (default: aes256)")
    parser.add_argument("--key", help="Cipher key in hex (default: random)")
    parser.add_argument("--chunk-blocks", type=int, default=MAX_DATA_BLOCKS, metavar=f"1..{MAX_DATA_BLOCKS}",
                        help=f"16-byte blocks per GCM message (default: {MAX_DATA_BLOCKS})")
    parser.add_argument("--output-dir", type=Path, default=APP_ROOT / "output", help="Output folder (default: output/)")


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(prog="imgapp", description="Grayscale image <-> AES-GCM UART packet streams")
    commands = parser.add_subparsers(dest="command", required=True)

    run_cmd = commands.add_parser("run", help="Encode, simulate and decrypt every image in input/")
    run_cmd.add_argument("--input-dir", type=Path, default=APP_ROOT / "input", help="Input folder (default: input/)")
    add_image_options(run_cmd)

    encode_cmd = commands.add_parser("encode", help="Image -> tx.txt, tx.bin, preview.png")
    encode_cmd.add_argument("image", type=Path)
    add_image_options(encode_cmd)

    simulate_cmd = commands.add_parser("simulate", help="Answer a TX stream like the FPGA -> rx.txt, rx.bin")
    simulate_cmd.add_argument("tx", type=Path)

    send_cmd = commands.add_parser("send", help="Send a TX stream to the FPGA over UART -> rx.txt, rx.bin")
    send_cmd.add_argument("tx", type=Path)
    send_cmd.add_argument("-p", "--port", help="Serial COM port, e.g. COM4 (default: auto-detect)")
    send_cmd.add_argument("-b", "--baud", type=int, default=115200, help="UART baud rate (default: 115200)")
    send_cmd.add_argument("-t", "--timeout", type=float, default=3.0, help="UART response timeout in seconds (default: 3.0)")

    decode_cmd =commands.add_parser("decode", help="TX stream -> image, or RX stream -> ciphertext image")
    decode_cmd.add_argument("tx", type=Path)
    decode_cmd.add_argument("--rx", type=Path, help="Show this RX stream's payload instead of the TX payload")
    decode_cmd.add_argument("-o", "--output", type=Path)

    decrypt_cmd = commands.add_parser("decrypt", help="Decrypt an RX stream and verify its tags -> image")
    decrypt_cmd.add_argument("tx", type=Path)
    decrypt_cmd.add_argument("rx", type=Path)
    decrypt_cmd.add_argument("--rx-dec", type=Path, help="Use the board's answer to tx_dec instead of the software model")
    decrypt_cmd.add_argument("-o", "--output", type=Path)
    return parser


def main(argv: Optional[List[str]] = None) -> int:
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8")

    args = build_parser().parse_args(argv)
    try:
        if args.command == "run":
            return run(args)
        if args.command == "encode":
            encode(args.image, args.output_dir, args)
        elif args.command == "simulate":
            simulate(args.tx)
        elif args.command == "send":
            return send(args.tx, args.port, args.baud, args.timeout)
        elif args.command == "decode":
            decode(args.tx, args.rx, args.output)
        elif args.command == "decrypt":
            decrypt(args.tx, args.rx, args.output, args.rx_dec)
    except (ValueError, OSError) as error:
        print(f"[!] {error}")
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
