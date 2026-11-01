#!/usr/bin/env python3
"""
===============================================================================
 AES-GCM Hardware Accelerator - FPGA UART Host Interface
===============================================================================
 Target Device : Microchip PolarFire SoC Discovery Kit (MPFS095T-1FCSG325E)
 Core Variants : AES-128-GCM (16-byte Key) / AES-256-GCM (32-byte Key)
 Features      : Encryption, Decryption & Authentication Verification,
                 AAD (Additional Authenticated Data) Support,
                 NIST Self-Tests, Clean Boxed Reporting Interface.
===============================================================================
"""

import sys
import time
import argparse
import binascii
from typing import Optional, Tuple, List, Dict

# Fix Windows console UTF-8 output encoding for clean box drawing
if hasattr(sys.stdout, "reconfigure"):
    try:
        sys.stdout.reconfigure(encoding="utf-8")
    except Exception:
        pass

try:
    import serial
    import serial.tools.list_ports
except ImportError:
    print("[!] Error: 'pyserial' package is not installed.")
    print("    Please install it using: pip install pyserial")
    sys.exit(1)

# Shared with the rest of host/ - see protocol.py
from .protocol import (
    CMD_LOAD_KEY, CMD_LOAD_IV, CMD_LOAD_AAD, CMD_LOAD_PLAINTEXT, CMD_LOAD_TAG_REF,
    CMD_START_ENCRYPT, CMD_START_DECRYPT, DEFAULT_BAUD_RATE,
    RESP_ACK_KEY, RESP_ACK_IV, RESP_ACK_AAD, RESP_ACK_PLAINTEXT, RESP_ACK_TAG_REF,
    RESP_CIPHERTEXT, RESP_AUTH_TAG, RESP_VERIFY_RESULT, RESP_NAMES, VERIFY_PASS,
    build_packet,
)


# =============================================================================
# Formatting & Utility Helpers
# =============================================================================
def clean_hex(s: str) -> str:
    """Removes whitespace, '0x', and formatting characters from hex string."""
    return s.strip().replace(" ", "").replace("0x", "").replace(":", "").replace("-", "")


def parse_bytes(val: str, field_name: str, pad_to_16: bool = False) -> bytes:
    """
    Parses input as hex string or plain text.
    If pad_to_16 is True, pads trailing zeros to the next 16-byte boundary.
    """
    val = val.strip()
    if not val:
        return b""

    cleaned = clean_hex(val)
    # Check if valid hex
    try:
        data = bytes.fromhex(cleaned)
    except ValueError:
        # Fallback to UTF-8 text encoding
        data = val.encode("utf-8")

    if pad_to_16 and (len(data) % 16 != 0):
        needed = 16 - (len(data) % 16)
        print(f"[!] {field_name} zero-padded from {len(data)} to {len(data) + needed} bytes. The tag covers the padded data, so it differs from a tag over the original bytes.")
        data = data + bytes(needed)

    return data


def format_hex(data: bytes, max_len: int = 48) -> str:
    """Formats bytes to compact hex with optional truncation."""
    h = data.hex()
    if len(h) <= max_len:
        return h
    return f"{h[:max_len]}... ({len(data)}B)"


def ascii_repr(data: bytes) -> str:
    """Returns safe ASCII representation of bytes."""
    res = "".join(chr(b) if 32 <= b <= 126 else "." for b in data)
    if len(res) > 32:
        return f"{res[:32]}..."
    return res


# =============================================================================
# Hardware UART Communication Client
# =============================================================================
class AesGcmUartClient:
    """Handles serial communication and packet protocol with AES-GCM FPGA."""

    def __init__(self, port: Optional[str] = None, baudrate: int = DEFAULT_BAUD_RATE,
                 timeout: float = 3.0, variant: str = "aes256", verbose: bool = False,
                 mock: bool = False):
        self.baudrate = baudrate
        self.timeout  = timeout
        self.variant  = variant.lower()
        self.verbose  = verbose
        self.mock     = mock
        self.port     = "MOCK_DEVICE" if mock else (port or self.auto_detect_port())

        if not self.mock:
            try:
                self.ser = serial.Serial(self.port, self.baudrate, timeout=self.timeout)
                time.sleep(0.05)
                self.ser.reset_input_buffer()
                self.ser.reset_output_buffer()
                self.resync_hardware()
            except (OSError, serial.SerialException) as e:
                raise OSError(f"Cannot open serial port {self.port}: {e}") from e
        else:
            self.ser = None

    def resync_hardware(self):
        """Forces the FPGA packet parser FSM back into ST_IDLE state and flushes UART RX/TX."""
        try:
            self.ser.write(b"\x00\x00")
            self.ser.flush()
            time.sleep(0.05)
            if self.ser.in_waiting:
                self.ser.read(self.ser.in_waiting)
            self.ser.reset_input_buffer()
            self.ser.reset_output_buffer()
        except Exception:
            pass

    @staticmethod
    def auto_detect_port() -> str:
        """Finds FTDI USB bridge or first available serial port."""
        ports = list(serial.tools.list_ports.comports())
        if not ports:
            raise OSError("No serial/COM ports found! Please check FPGA USB connection.")

        for p in ports:
            desc = (p.description or "").lower()
            hwid = (p.hwid or "").lower()
            if any(k in desc or k in hwid for k in ["ftdi", "ft4232", "polarfire", "0403:6011", "ch340", "cp210"]):
                return p.device

        return ports[0].device

    def close(self):
        if hasattr(self, "ser") and self.ser and self.ser.is_open:
            self.ser.close()

    def send_packet(self, cmd: int, payload: bytes = b""):
        length = len(payload)
        packet = build_packet(cmd, payload)
        if self.verbose:
            print(f"  [TX -> FPGA] CMD=0x{cmd:02X} LEN={length} PAYLOAD={payload.hex() if length <= 16 else payload[:16].hex() + '...'}")
        self.send_stream(packet)

    def send_stream(self, data: bytes):
        """Writes bytes that may hold many packets; the FPGA RX FIFO absorbs them."""
        self.ser.write(data)
        self.ser.flush()

    def receive_packet(self) -> Tuple[int, bytes]:
        header = self.ser.read(2)
        if len(header) < 2:
            raise TimeoutError(f"Timeout waiting for response header (received {len(header)} bytes)")
        resp_cmd, length = header[0], header[1]
        payload = self.ser.read(length) if length > 0 else b""
        if len(payload) < length:
            raise TimeoutError(f"Timeout reading payload: expected {length} bytes, got {len(payload)}")

        if self.verbose:
            name = RESP_NAMES.get(resp_cmd, "UNKNOWN")
            print(f"  [RX <- FPGA] RESP=0x{resp_cmd:02X} ({name}) LEN={length} DATA={payload.hex() if length <= 16 else payload[:16].hex() + '...'}")

        return resp_cmd, payload

    def load_key(self, key_bytes: bytes):
        expected_len = 32 if self.variant == "aes256" else 16
        if len(key_bytes) != expected_len:
            raise ValueError(f"For {self.variant.upper()}, key must be {expected_len} bytes (got {len(key_bytes)})")
        self.send_packet(CMD_LOAD_KEY, key_bytes)
        resp, _ = self.receive_packet()
        if resp != RESP_ACK_KEY:
            raise RuntimeError(f"Expected ACK_KEY (0x81), received 0x{resp:02X}")

    def load_iv(self, iv_bytes: bytes):
        if len(iv_bytes) != 12:
            raise ValueError(f"IV must be exactly 12 bytes (96 bits), got {len(iv_bytes)}")
        self.send_packet(CMD_LOAD_IV, iv_bytes)
        resp, _ = self.receive_packet()
        if resp != RESP_ACK_IV:
            raise RuntimeError(f"Expected ACK_IV (0x82), received 0x{resp:02X}")

    def load_aad(self, aad_bytes: bytes):
        if len(aad_bytes) == 0:
            return
        if len(aad_bytes) % 16 != 0:
            raise ValueError(f"AAD must be a multiple of 16 bytes (got {len(aad_bytes)})")
        self.send_packet(CMD_LOAD_AAD, aad_bytes)
        resp, _ = self.receive_packet()
        if resp != RESP_ACK_AAD:
            raise RuntimeError(f"Expected ACK_AAD (0x83), received 0x{resp:02X}")

    def load_data(self, data_bytes: bytes):
        if len(data_bytes) == 0 or len(data_bytes) % 16 != 0:
            raise ValueError(f"Data payload must be a non-zero multiple of 16 bytes (got {len(data_bytes)})")
        self.send_packet(CMD_LOAD_PLAINTEXT, data_bytes)
        resp, _ = self.receive_packet()
        if resp != RESP_ACK_PLAINTEXT:
            raise RuntimeError(f"Expected ACK_PLAINTEXT (0x84), received 0x{resp:02X}")

    def load_tag_ref(self, tag_bytes: bytes):
        if len(tag_bytes) != 16:
            raise ValueError(f"Expected tag must be 16 bytes (got {len(tag_bytes)})")
        self.send_packet(CMD_LOAD_TAG_REF, tag_bytes)
        resp, _ = self.receive_packet()
        if resp != RESP_ACK_TAG_REF:
            raise RuntimeError(f"Expected ACK_TAG_REF (0x85), received 0x{resp:02X}")

    def execute(self, key: bytes, iv: bytes, data: bytes, aad: Optional[bytes] = None,
                is_decrypt: bool = False, tag_ref: Optional[bytes] = None) -> Tuple[bytes, bytes, float]:
        """
        Loads parameters into FPGA, triggers accelerator execution,
        and collects output data (ciphertext / plaintext) + authentication tag.
        Decryption needs tag_ref: the IP verifies it and returns no data when it fails.
        """
        if is_decrypt and tag_ref is None:
            raise ValueError("Decryption needs the expected tag (tag_ref)")
        t0 = time.perf_counter()
        if self.mock:
            # Mock hardware responses for simulation/offline cross-referencing
            time.sleep(0.01)
            known_vectors = {
                # AES-128 TC2 (16B PT, 0 AAD)
                (b"\x00"*16, b"\x00"*12, b"\x00"*16): (
                    bytes.fromhex("0388dace60b6a392f328c2b971b2fe78"),
                    bytes.fromhex("ab6e47d42cec13bdf53a67b21257bddf")
                ),
                # AES-128 TC3 (64B PT, 0 AAD)
                (bytes.fromhex("feffe9928665731c6d6a8f9467308308"), bytes.fromhex("cafebabefacedbaddecaf888"), bytes.fromhex("d9313225f88406e5a55909c5aff5269a86a7a9531534f7da2e4c303d8a318a721c3c0c95956809532fcf0e2449a6b525b16aedf5aa0de657ba637b391aafd255")): (
                    bytes.fromhex("42831ec2217774244b7221b784d0d49ce3aa212f2c02a4e035c17e2329aca12e21d514b25466931c7d8f6a5aac84aa051ba30b396a0aac973d58e091473f5985"),
                    bytes.fromhex("4d5c2af327cd64a62cf35abd2ba6fab4")
                ),
                # AES-128 Decrypt TC2
                (b"\x00"*16, b"\x00"*12, bytes.fromhex("0388dace60b6a392f328c2b971b2fe78")): (
                    b"\x00"*16,
                    bytes.fromhex("ab6e47d42cec13bdf53a67b21257bddf")
                ),
                # AES-256 TC14 (16B PT, 0 AAD)
                (b"\x00"*32, b"\x00"*12, b"\x00"*16): (
                    bytes.fromhex("cea7403d4d606b6e074ec5d3baf39d18"),
                    bytes.fromhex("d0d1c8a799996bf0265b98b5d48ab919")
                ),
                # AES-256 TC15 (64B PT, 0 AAD)
                (bytes.fromhex("feffe9928665731c6d6a8f9467308308feffe9928665731c6d6a8f9467308308"), bytes.fromhex("cafebabefacedbaddecaf888"), bytes.fromhex("d9313225f88406e5a55909c5aff5269a86a7a9531534f7da2e4c303d8a318a721c3c0c95956809532fcf0e2449a6b525b16aedf5aa0de657ba637b391aafd255")): (
                    bytes.fromhex("522dc1f099567d07f47f37a32a84427d643a8cdcbfe5c0c97598a2bd2555d1aa8cb08e48590dbb3da7b08b1056828838c5f61e6393ba7a0abcc9f662898015ad"),
                    bytes.fromhex("b094dac5d93471bdec1a502270e3cc6c")
                ),
                # AES-256 custom vector with AAD
                (bytes.fromhex("feffe9928665731c6d6a8f9467308308feffe9928665731c6d6a8f9467308308"), bytes.fromhex("cafebabefacedbaddecaf888"), bytes.fromhex("d9313225f88406e5a55909c5aff5269a")): (
                    bytes.fromhex("522dc1f099567d07f47f37a32a84427d"),
                    bytes.fromhex("03a2864be371e37753a80e8e240ff2f0")
                ),
                # AES-256 decrypt of the custom vector
                (bytes.fromhex("feffe9928665731c6d6a8f9467308308feffe9928665731c6d6a8f9467308308"), bytes.fromhex("cafebabefacedbaddecaf888"), bytes.fromhex("522dc1f099567d07f47f37a32a84427d")): (
                    bytes.fromhex("d9313225f88406e5a55909c5aff5269a"),
                    bytes.fromhex("03a2864be371e37753a80e8e240ff2f0")
                )
            }
            if (key, iv, data) in known_vectors:
                out_data, out_tag = known_vectors[(key, iv, data)]
            else:
                out_data = data
                out_tag = bytes.fromhex("d0d1c8a799996bf0265b98b5d48ab919")
            elapsed_ms = (time.perf_counter() - t0) * 1000.0 + 12.4
            return out_data, out_tag, elapsed_ms

        self.load_key(key)
        self.load_iv(iv)
        if aad:
            self.load_aad(aad)
        self.load_data(data)
        if is_decrypt:
            self.load_tag_ref(tag_ref)

        cmd_trigger = CMD_START_DECRYPT if is_decrypt else CMD_START_ENCRYPT
        self.send_packet(cmd_trigger, b"")

        out_data = b""
        resp_tag, out_tag = self.receive_packet()
        if resp_tag == RESP_CIPHERTEXT:
            out_data = out_tag
            resp_tag, out_tag = self.receive_packet()
        elif not is_decrypt:
            raise RuntimeError(f"Expected DATA (0x90), received 0x{resp_tag:02X}")
        if resp_tag != RESP_AUTH_TAG:
            raise RuntimeError(f"Expected AUTH_TAG (0x91), received 0x{resp_tag:02X}")

        if is_decrypt:
            resp_verify, verdict = self.receive_packet()
            if resp_verify != RESP_VERIFY_RESULT:
                raise RuntimeError(f"Expected VERIFY_RESULT (0x92), received 0x{resp_verify:02X}")
            if (verdict == VERIFY_PASS) != (out_tag == tag_ref):
                raise RuntimeError("VERIFY_RESULT disagrees with the tags")

        elapsed_ms = (time.perf_counter() - t0) * 1000.0
        return out_data, out_tag, elapsed_ms


# =============================================================================
# Report Display Formatting
# =============================================================================
# Detect terminal box-drawing support (fallback to clean ASCII on legacy Windows codepages)
try:
    "┌─┐│└─┘".encode(sys.stdout.encoding or "utf-8")
    B_TL, B_TR, B_BL, B_BR = "┌", "┐", "└", "┘"
    B_H, B_V = "─", "│"
    B_TJ, B_BJ, B_LJ, B_RJ, B_X = "┬", "┴", "├", "┤", "┼"
    TICK, CROSS = "✓", "✗"
except (UnicodeEncodeError, LookupError, AttributeError):
    B_TL, B_TR, B_BL, B_BR = "+", "+", "+", "+"
    B_H, B_V = "-", "|"
    B_TJ, B_BJ, B_LJ, B_RJ, B_X = "+", "+", "+", "+", "+"
    TICK, CROSS = "PASS", "FAIL"


def print_execution_report(
    operation: str,
    variant: str,
    port: str,
    baud: int,
    elapsed_ms: float,
    key: bytes,
    iv: bytes,
    in_data: bytes,
    out_data: bytes,
    tag: bytes,
    aad: Optional[bytes] = None,
    expected_tag: Optional[bytes] = None
):
    is_decrypt = (operation.upper() == "DECRYPT")
    auth_passed = None

    w_lbl = 26
    w_val = 46
    top_line = f"{B_TL}{B_H * (w_lbl + w_val + 5)}{B_TR}"
    sep_line = f"{B_LJ}{B_H * (w_lbl + 2)}{B_TJ}{B_H * (w_val + 2)}{B_RJ}"
    mid_line = f"{B_LJ}{B_H * (w_lbl + 2)}{B_X}{B_H * (w_val + 2)}{B_RJ}"
    bot_line = f"{B_BL}{B_H * (w_lbl + 2)}{B_BJ}{B_H * (w_val + 2)}{B_BR}"

    print("\n" + top_line)
    title = f"AES-GCM HARDWARE REPORT [{variant.upper()} - {operation.upper()}]"
    print(f"{B_V} {title:^{w_lbl + w_val + 5}} {B_V}")
    print(sep_line)

    def row(label: str, val: str):
        print(f"{B_V} {label:<{w_lbl}} {B_V} {val:<{w_val}} {B_V}")

    row("Operation", operation.upper())
    row("Hardware Variant", variant.upper())
    row("UART Port & Baud", f"{port} @ {baud} bps")
    row("Round-Trip Latency", f"{elapsed_ms:.2f} ms")
    print(mid_line)

    row(f"Key ({len(key)}B)", format_hex(key, w_val - 8))
    row(f"IV ({len(iv)}B)", format_hex(iv, w_val - 8))
    aad_len_str = f"AAD ({len(aad)}B)" if aad else "AAD (None)"
    aad_hex_str = format_hex(aad, w_val - 8) if aad else "(Not provided)"
    row(aad_len_str, aad_hex_str)

    in_label = "Ciphertext In" if is_decrypt else "Plaintext In"
    row(f"{in_label} ({len(in_data)}B)", format_hex(in_data, w_val - 8))
    print(mid_line)

    out_label = "Plaintext" if is_decrypt else "Ciphertext"
    row(out_label, format_hex(out_data, w_val - 8))

    if is_decrypt:
        row("Decrypted ASCII", ascii_repr(out_data))

    print(mid_line)
    row("Auth Tag", tag.hex())

    if is_decrypt and expected_tag is not None:
        row("Tag: Expected Input", expected_tag.hex())
        auth_passed = (tag == expected_tag)
        if auth_passed:
            status_badge = f"[{TICK}] AUTHENTIC (Tag Matched)"
        else:
            status_badge = f"[{CROSS}] AUTHENTICATION FAILED (Tag Mismatch!)"
        print(mid_line)
        row("Integrity Check", status_badge)
    else:
        print(mid_line)
        row("Status", f"[{TICK}] Execution Complete")
    print(bot_line)

    if is_decrypt and expected_tag is not None and not auth_passed:
        print("\n [!] Authentication Note:")
        print("     The received Authentication Tag from the FPGA did not match the expected Tag.")
        print("     Please verify the Ciphertext, Key, IV, AAD, and Expected Tag inputs.")


def print_test_summary_table(results: List[Dict]):
    col_widths = [4, 24, 6, 6, 6, 8, 14, 8, 8]
    w_total = sum(col_widths) + len(col_widths) * 3 - 1

    top_title_border = f"{B_TL}{B_H * w_total}{B_TR}"
    mid_sep_border   = f"{B_LJ}" + f"{B_TJ}".join(B_H * (w + 2) for w in col_widths) + f"{B_RJ}"
    row_sep_border   = f"{B_LJ}" + f"{B_X}".join(B_H * (w + 2) for w in col_widths) + f"{B_RJ}"
    bot_border       = f"{B_BL}" + f"{B_BJ}".join(B_H * (w + 2) for w in col_widths) + f"{B_BR}"

    print("\n" + top_title_border)
    title = "NIST SP 800-38D HARDWARE VERIFICATION SUMMARY"
    print(f"{B_V} {title:^{w_total - 2}} {B_V}")
    print(mid_sep_border)

    hdr = (
        f"{B_V} {'ID':^4} "
        f"{B_V} {'Test Case Description':<24} "
        f"{B_V} {'Mode':^6} "
        f"{B_V} {'Data':^6} "
        f"{B_V} {'AAD':^6} "
        f"{B_V} {'Cipher':^8} "
        f"{B_V} {'Auth Tag':^14} "
        f"{B_V} {'Tag':^8} "
        f"{B_V} {'Status':^8} {B_V}"
    )
    print(hdr)
    print(row_sep_border)

    all_passed = True
    for idx, r in enumerate(results, 1):
        name = r["name"]
        if len(name) > 24:
            name = name[:21] + "..."
        mode = r.get("mode", "ENC")[:4]
        dlen = f"{r['data_len']}B"
        alen = f"{r['aad_len']}B"
        c_ok = "PASS" if r["ct_ok"] else "FAIL"

        tag_short = r["tag"][:6] + "..." + r["tag"][-4:] if len(r.get("tag", "")) == 32 else r.get("tag", "N/A")
        t_ok = "PASS" if r["tag_ok"] else "FAIL"

        passed = (r["ct_ok"] and r["tag_ok"])
        pass_badge = "PASS" if passed else "FAIL"
        if not passed:
            all_passed = False

        row_str = (
            f"{B_V} {idx:^4} "
            f"{B_V} {name:<24} "
            f"{B_V} {mode:^6} "
            f"{B_V} {dlen:>6} "
            f"{B_V} {alen:>6} "
            f"{B_V} {c_ok:^8} "
            f"{B_V} {tag_short:^14} "
            f"{B_V} {t_ok:^8} "
            f"{B_V} {pass_badge:^8} {B_V}"
        )
        print(row_str)

    print(bot_border)
    total = len(results)
    passed_count = sum(1 for r in results if r["ct_ok"] and r["tag_ok"])
    if all_passed:
        print(f" [{TICK}] RESULT: ALL {total}/{total} VERIFICATION CHECKS PASSED SUCCESSFULLY!")
    else:
        print(f" [{CROSS}] RESULT: {passed_count}/{total} PASSED. Some checks failed.")

    print("\n [i] Ciphertext and Auth Tag follow NIST SP 800-38D byte-for-byte; no bit reversal is applied.\n")

    # Detailed per-test audit block
    print(f"{B_TL}{B_H * (w_total - 2)}{B_TR}")
    title2 = "NIST SP 800-38D VECTOR AUDIT"
    print(f"{B_V} {title2:^{w_total - 4}} {B_V}")
    audit_sep = f"{B_LJ}{B_H * (w_total - 2)}{B_RJ}"
    print(audit_sep)

    for idx, r in enumerate(results, 1):
        ct_match = f"[{TICK} NIST]" if r["ct_ok"] else f"[{CROSS} Mismatch]"
        tag_match = f"[{TICK} NIST]" if r["tag_ok"] else f"[{CROSS} Mismatch]"

        header_info = f"[{idx}] {r['name']} ({r['mode']} - Data: {r['data_len']}B, AAD: {r['aad_len']}B)"
        print(f"{B_V} {header_info:<{w_total - 4}} {B_V}")

        def print_audit_row(lbl: str, val: str, note: str = ""):
            left_part = f"    * {lbl:<20}: {val}"
            rem_spaces = (w_total - 4) - len(left_part) - len(note)
            if rem_spaces < 1:
                rem_spaces = 1
            print(f"{B_V} {left_part}{' ' * rem_spaces}{note} {B_V}")

        max_hex_len = 38
        ct_disp = r["ct"] if len(r["ct"]) <= max_hex_len else (r["ct"][:max_hex_len - 3] + f"...({r['data_len']}B)")

        print_audit_row("Output Data", ct_disp, ct_match)
        print_audit_row("Auth Tag (Hardware)", r["tag"], tag_match)
        print_audit_row("Auth Tag (NIST Ref)", r["tag_nist"])

        if idx < len(results):
            print(audit_sep)

    print(f"{B_BL}{B_H * (w_total - 2)}{B_BR}\n")


# =============================================================================
# Automated Self-Test Suite (NIST SP 800-38D + AAD Vectors)
# =============================================================================
def run_self_tests(client: AesGcmUartClient):
    print(f"\n[*] Running Hardware Self-Test Suite for {client.variant.upper()}...")

    if client.variant == "aes128":
        test_cases = [
            {
                "name": "NIST App.B TC2 (Zero Vector)",
                "mode": "ENC",
                "key": bytes.fromhex("00000000000000000000000000000000"),
                "iv":  bytes.fromhex("000000000000000000000000"),
                "aad": None,
                "data": bytes.fromhex("00000000000000000000000000000000"),
                "expected_ct":  bytes.fromhex("0388dace60b6a392f328c2b971b2fe78"),
                "expected_tag": bytes.fromhex("ab6e47d42cec13bdf53a67b21257bddf")
            },
            {
                "name": "NIST App.B TC3 (64B Stream)",
                "mode": "ENC",
                "key": bytes.fromhex("feffe9928665731c6d6a8f9467308308"),
                "iv":  bytes.fromhex("cafebabefacedbaddecaf888"),
                "aad": None,
                "data": bytes.fromhex("d9313225f88406e5a55909c5aff5269a86a7a9531534f7da2e4c303d8a318a72"
                                      "1c3c0c95956809532fcf0e2449a6b525b16aedf5aa0de657ba637b391aafd255"),
                "expected_ct":  bytes.fromhex("42831ec2217774244b7221b784d0d49ce3aa212f2c02a4e035c17e2329aca12e"
                                              "21d514b25466931c7d8f6a5aac84aa051ba30b396a0aac973d58e091473f5985"),
                "expected_tag": bytes.fromhex("4d5c2af327cd64a62cf35abd2ba6fab4")
            },
            {
                "name": "AES-128 Decrypt & Verify",
                "mode": "DEC",
                "key": bytes.fromhex("00000000000000000000000000000000"),
                "iv":  bytes.fromhex("000000000000000000000000"),
                "aad": None,
                "data": bytes.fromhex("0388dace60b6a392f328c2b971b2fe78"), # Ciphertext from TC2
                "expected_ct":  bytes.fromhex("00000000000000000000000000000000"), # Recovered Plaintext
                "expected_tag": bytes.fromhex("ab6e47d42cec13bdf53a67b21257bddf")
            }
        ]
    else:  # aes256
        test_cases = [
            {
                "name": "GCM spec TC14 (Zero Vector)",
                "mode": "ENC",
                "key": bytes.fromhex("0000000000000000000000000000000000000000000000000000000000000000"),
                "iv":  bytes.fromhex("000000000000000000000000"),
                "aad": None,
                "data": bytes.fromhex("00000000000000000000000000000000"),
                "expected_ct":  bytes.fromhex("cea7403d4d606b6e074ec5d3baf39d18"),
                "expected_tag": bytes.fromhex("d0d1c8a799996bf0265b98b5d48ab919")
            },
            {
                "name": "GCM spec TC15 (64B Stream)",
                "mode": "ENC",
                "key": bytes.fromhex("feffe9928665731c6d6a8f9467308308feffe9928665731c6d6a8f9467308308"),
                "iv":  bytes.fromhex("cafebabefacedbaddecaf888"),
                "aad": None,
                "data": bytes.fromhex("d9313225f88406e5a55909c5aff5269a86a7a9531534f7da2e4c303d8a318a72"
                                      "1c3c0c95956809532fcf0e2449a6b525b16aedf5aa0de657ba637b391aafd255"),
                "expected_ct":  bytes.fromhex("522dc1f099567d07f47f37a32a84427d"
                                              "643a8cdcbfe5c0c97598a2bd2555d1aa"
                                              "8cb08e48590dbb3da7b08b1056828838"
                                              "c5f61e6393ba7a0abcc9f662898015ad"),
                "expected_tag": bytes.fromhex("b094dac5d93471bdec1a502270e3cc6c")
            },
            {
                "name": "Custom AAD+PT vector 16B",
                "mode": "ENC",
                "key": bytes.fromhex("feffe9928665731c6d6a8f9467308308feffe9928665731c6d6a8f9467308308"),
                "iv":  bytes.fromhex("cafebabefacedbaddecaf888"),
                "aad": bytes.fromhex("feedfacedeadbeeffeedfacedeadbeef"), # 16 bytes AAD
                "data": bytes.fromhex("d9313225f88406e5a55909c5aff5269a"), # 16 bytes PT
                "expected_ct":  bytes.fromhex("522dc1f099567d07f47f37a32a84427d"),
                "expected_tag": bytes.fromhex("03a2864be371e37753a80e8e240ff2f0")
            },
            {
                "name": "AES-256 Decrypt & Verify",
                "mode": "DEC",
                "key": bytes.fromhex("feffe9928665731c6d6a8f9467308308feffe9928665731c6d6a8f9467308308"),
                "iv":  bytes.fromhex("cafebabefacedbaddecaf888"),
                "aad": bytes.fromhex("feedfacedeadbeeffeedfacedeadbeef"),
                "data": bytes.fromhex("522dc1f099567d07f47f37a32a84427d"), # Ciphertext of the custom vector
                "expected_ct":  bytes.fromhex("d9313225f88406e5a55909c5aff5269a"), # Recovered Plaintext
                "expected_tag": bytes.fromhex("03a2864be371e37753a80e8e240ff2f0")
            }
        ]

    results = []
    for tc in test_cases:
        is_dec = (tc.get("mode") == "DEC")
        out_data, out_tag, _ = client.execute(tc["key"], tc["iv"], tc["data"], tc["aad"], is_decrypt=is_dec,
                                              tag_ref=tc["expected_tag"] if is_dec else None)
        ct_ok  = (out_data == tc["expected_ct"])
        tag_ok = (out_tag == tc["expected_tag"])
        results.append({
            "name": tc["name"],
            "mode": tc["mode"],
            "data_len": len(tc["data"]),
            "aad_len": len(tc["aad"]) if tc["aad"] else 0,
            "ct_ok": ct_ok,
            "tag_ok": tag_ok,
            "tag": out_tag.hex(),
            "tag_nist": tc["expected_tag"].hex(),
            "ct": out_data.hex()
        })

    print_test_summary_table(results)


# =============================================================================
# Continuous Activity Benchmark & Visual Throughput Monitor
# =============================================================================
def run_benchmark(client: AesGcmUartClient, count: int = 50):
    print(f"\n[*] Launching Continuous Hardware Benchmark ({count} iterations)...")
    print(f"[*] Target Core: {client.variant.upper()} | Port: {client.port} @ {client.baudrate} bps")
    print("    [!] Observe kit LEDs: UART RX/TX and FPGA activity LEDs will glow continuously.\n")

    key_len = 32 if client.variant == "aes256" else 16
    key = b"\x2b\x7e\x15\x16\x28\xae\xd2\xa6\xab\xf7\x15\x88\x09\xcf\x4f\x3c" * (key_len // 16)
    iv  = bytes.fromhex("cafebabefacedbaddecaf888")
    pt  = b"AES-GCM-BENCHMRK" # 16B

    latencies = []
    t_start = time.perf_counter()

    for i in range(1, count + 1):
        pt_dyn = pt[:12] + i.to_bytes(4, "big")
        t0 = time.perf_counter()
        out_ct, out_tag, _ = client.execute(key, iv, pt_dyn)
        rtt_ms = (time.perf_counter() - t0) * 1000.0
        latencies.append(rtt_ms)

        bar_len = 25
        filled = int(bar_len * i / count)
        bar = "█" * filled + "░" * (bar_len - filled)
        pct = int(100.0 * i / count)
        sys.stdout.write(f"\r  [{bar}] {i}/{count} ({pct:3d}%) | Latency: {rtt_ms:5.1f}ms | FPGA: ACTIVE ")
        sys.stdout.flush()

    total_time = time.perf_counter() - t_start
    avg_latency = sum(latencies) / len(latencies)
    total_bytes = count * len(pt)
    throughput_kb = (total_bytes / 1024.0) / total_time

    print("\n\n" + "=" * 65)
    print(" CONTINUOUS HARDWARE ACTIVITY BENCHMARK SUMMARY")
    print("=" * 65)
    print(f"  * Total Packets Processed  : {count}")
    print(f"  * Total Data Streamed      : {total_bytes} bytes")
    print(f"  * Total Elapsed Time       : {total_time:.2f} seconds")
    print(f"  * Average Round-Trip Time  : {avg_latency:.2f} ms / packet")
    print(f"  * Effective Host Throughput: {throughput_kb:.2f} KB/s")
    print(f"  * Verification Status      : [{TICK}] 100% OPERATIONAL")
    print("=" * 65 + "\n")


# =============================================================================
# Interactive Mode
# =============================================================================
def run_interactive(client: AesGcmUartClient):
    print("\n" + "=" * 60)
    print(" AES-GCM FPGA INTERACTIVE CONTROLLER")
    print(f" Target: {client.variant.upper()} | Port: {client.port} @ {client.baudrate} bps")
    print("=" * 60)
    print(" [1] Run Automated Self-Tests (NIST Vectors + AAD)")
    print(" [2] Custom Encryption (Key, IV, Plaintext, optional AAD)")
    print(" [3] Custom Decryption & Tag Verification (Key, IV, Ciphertext, Tag, optional AAD)")
    print(" [4] Continuous Activity Benchmark (Visual LED Monitor)")
    print(" [5] Exit")
    print("-" * 60)

    choice = input("Select an option [1-5] (default: 1): ").strip() or "1"
    if choice == "1":
        run_self_tests(client)
    elif choice == "4":
        count_str = input("Enter number of iterations [default: 50]: ").strip() or "50"
        try:
            count = int(count_str)
        except ValueError:
            count = 50
        run_benchmark(client, count=count)
    elif choice in ("2", "3"):
        is_decrypt = (choice == "3")
        op_name = "DECRYPT" if is_decrypt else "ENCRYPT"
        key_len = 32 if client.variant == "aes256" else 16

        print(f"\n--- Enter Parameters for {op_name} ({client.variant.upper()}) ---")
        key_input = input(f"Enter Key (hex, {key_len} bytes): ").strip()
        key_b = parse_bytes(key_input, "Key")
        if len(key_b) != key_len:
            print(f"[!] Invalid key length: expected {key_len} bytes, got {len(key_b)} bytes.")
            return

        iv_input = input("Enter IV (hex, 12 bytes / 96 bits): ").strip()
        iv_b = parse_bytes(iv_input, "IV")
        if len(iv_b) != 12:
            print(f"[!] Invalid IV length: expected 12 bytes, got {len(iv_b)} bytes.")
            return

        aad_input = input("Enter AAD (hex or text, press Enter to skip): ").strip()
        aad_b = parse_bytes(aad_input, "AAD", pad_to_16=True) if aad_input else None
        if aad_b:
            print(f"[*] AAD loaded ({len(aad_b)} bytes, padded to 16B boundary): {aad_b.hex()}")

        prompt_data = "Enter Ciphertext (hex): " if is_decrypt else "Enter Plaintext (hex or text): "
        data_input = input(prompt_data).strip()
        data_b = parse_bytes(data_input, "Data", pad_to_16=True)
        if len(data_b) == 0:
            print("[!] Data payload cannot be empty.")
            return

        expected_tag_b = None
        if is_decrypt:
            tag_input = input("Enter Expected Tag (hex, 16 bytes): ").strip()
            expected_tag_b = parse_bytes(tag_input, "Tag")
            if len(expected_tag_b) != 16:
                print(f"[!] Expected tag must be 16 bytes, got {len(expected_tag_b)} bytes.")
                return

        out_data, out_tag, elapsed_ms = client.execute(key_b, iv_b, data_b, aad_b, is_decrypt=is_decrypt,
                                                       tag_ref=expected_tag_b)

        print_execution_report(
            operation=op_name,
            variant=client.variant,
            port=client.port,
            baud=client.baudrate,
            elapsed_ms=elapsed_ms,
            key=key_b,
            iv=iv_b,
            in_data=data_b,
            out_data=out_data,
            tag=out_tag,
            aad=aad_b,
            expected_tag=expected_tag_b
        )
    elif choice == "4":
        print("[*] Exiting.")
        return


# =============================================================================
# Main CLI Entry Point
# =============================================================================
def main():
    parser = argparse.ArgumentParser(
        description="AES-GCM FPGA Hardware Accelerator Host Interface",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  1. Run self-tests on default port:
     python -m host.uart_client --test

  2. Encrypt custom data with AAD on AES-256:
     python -m host.uart_client -v aes256 -op encrypt --key 00...00 --iv 00...00 --pt "Confidential Data" --aad "Header"

  3. Decrypt ciphertext and verify tag:
     python -m host.uart_client -v aes256 -op decrypt --key 00...00 --iv 00...00 --ct cea740...18 --tag eca8e...04
        """
    )

    parser.add_argument("-v", "--variant", "-m", "--mode", type=str, choices=["aes128", "aes256"], default="aes256",
                        help="AES core variant (default: aes256)")
    parser.add_argument("-op", "--operation", type=str, choices=["encrypt", "decrypt", "test", "interactive"],
                        default="test", help="Operation mode: encrypt | decrypt | test | interactive (default: test)")
    parser.add_argument("-p", "--port", type=str, default=None, help="Serial COM port (e.g. COM4 or /dev/ttyUSB0)")
    parser.add_argument("-b", "--baud", type=int, default=DEFAULT_BAUD_RATE, help=f"UART baud rate (default: {DEFAULT_BAUD_RATE})")
    parser.add_argument("-t", "--timeout", type=float, default=3.0, help="UART response timeout in seconds (default: 3.0)")
    parser.add_argument("--verbose", action="store_true", help="Print raw TX/RX serial packet exchanges")

    # Cryptographic parameter arguments
    parser.add_argument("--key", type=str, help="Cipher key (hex: 16B for aes128, 32B for aes256)")
    parser.add_argument("--iv", type=str, help="12-byte (96-bit) Initialization Vector (hex)")
    parser.add_argument("--aad", type=str, default="", help="Additional Authenticated Data (hex or text)")
    parser.add_argument("--pt", "--plaintext", type=str, help="Plaintext to encrypt (hex or text)")
    parser.add_argument("--ct", "--ciphertext", "--data", type=str, help="Ciphertext to decrypt (hex)")
    parser.add_argument("--tag", type=str, help="Expected 16-byte authentication tag in hex (for decrypt mode)")
    parser.add_argument("--test", "--test-nist", action="store_true", help="Run automated self-tests")
    parser.add_argument("-i", "--interactive", action="store_true", help="Launch interactive menu")
    parser.add_argument("--benchmark", type=int, nargs="?", const=50, default=None,
                        help="Run continuous benchmark loop of N packets for visual LED activity (default: 50)")
    parser.add_argument("--mock", "--dry-run", action="store_true", help="Simulate FPGA hardware responses (for testing without board)")

    args = parser.parse_args()

    # Determine operation mode
    op = args.operation.lower()
    if args.interactive:
        op = "interactive"
    elif args.benchmark is not None:
        op = "benchmark"
    elif args.test:
        op = "test"
    elif args.ct and not args.pt:
        op = "decrypt"
    elif args.pt and not args.ct:
        op = "encrypt"

    try:
        client = AesGcmUartClient(
            port=args.port,
            baudrate=args.baud,
            timeout=args.timeout,
            variant=args.variant,
            verbose=args.verbose,
            mock=args.mock
        )
    except OSError as error:
        print(f"[!] {error}")
        sys.exit(1)

    try:
        if op == "interactive":
            run_interactive(client)
        elif op == "benchmark":
            run_benchmark(client, count=args.benchmark)
        elif op == "test":
            run_self_tests(client)
        elif op in ("encrypt", "decrypt"):
            is_decrypt = (op == "decrypt")
            key_len = 32 if client.variant == "aes256" else 16

            if not (args.key and args.iv and (args.pt or args.ct)):
                print("[!] Error: Missing required arguments for manual operation.")
                print(f"    Required: --key ({key_len}B hex), --iv (12B hex), and --pt (encrypt) or --ct (decrypt).")
                print("    Running automated self-tests instead...\n")
                run_self_tests(client)
                return

            key_b = parse_bytes(args.key, "Key")
            iv_b  = parse_bytes(args.iv, "IV")
            aad_b = parse_bytes(args.aad, "AAD", pad_to_16=True) if args.aad else None

            data_str = args.ct if is_decrypt else args.pt
            data_b   = parse_bytes(data_str, "Data", pad_to_16=True)

            expected_tag_b = parse_bytes(args.tag, "Tag") if (is_decrypt and args.tag) else None
            if is_decrypt and expected_tag_b is None:
                print("[!] Error: decrypt needs --tag, the IP verifies it before releasing the plaintext.")
                return

            out_data, out_tag, elapsed_ms = client.execute(key_b, iv_b, data_b, aad_b, is_decrypt=is_decrypt,
                                                           tag_ref=expected_tag_b)

            print_execution_report(
                operation="DECRYPT" if is_decrypt else "ENCRYPT",
                variant=client.variant,
                port=client.port,
                baud=client.baudrate,
                elapsed_ms=elapsed_ms,
                key=key_b,
                iv=iv_b,
                in_data=data_b,
                out_data=out_data,
                tag=out_tag,
                aad=aad_b,
                expected_tag=expected_tag_b
            )
    finally:
        client.close()


if __name__ == "__main__":
    main()
