#!/usr/bin/env python3
"""
===============================================================================
AES-GCM Multi-Variant FPGA UART Host Interface Application
===============================================================================
Target Hardware: PolarFire SoC Discovery Kit (MPFS095T-1FCSG325E)
Interface:       FT4232HL USB-to-UART Bridge -> FPGA Fabric Logic
Requirements:    pyserial (pip install pyserial)

Supported Modes:
  --mode aes128 : AES-128-GCM (16-byte key)
  --mode aes256 : AES-256-GCM (32-byte key)

Protocol Definition:
  [Host -> FPGA]:
    0x01 = CMD_LOAD_KEY       (Length: 16 for AES-128, 32 for AES-256)
    0x02 = CMD_LOAD_IV        (Length: 12)
    0x03 = CMD_LOAD_AAD       (Length: 16*M)
    0x04 = CMD_LOAD_PLAINTEXT (Length: 16*P)
    0x05 = CMD_START_ENCRYPT  (Length: 0)

  [FPGA -> Host]:
    0x81 = RESP_ACK_KEY
    0x82 = RESP_ACK_IV
    0x83 = RESP_ACK_AAD
    0x84 = RESP_ACK_PLAINTEXT
    0x90 = RESP_CIPHERTEXT
    0x91 = RESP_AUTH_TAG
    0xE0 = RESP_ERR_UNKNOWN
    0xE1 = RESP_ERR_LEN
===============================================================================
"""

import sys
import time
import argparse
import serial
import serial.tools.list_ports

# Protocol Command & Response Opcodes
CMD_LOAD_KEY       = 0x01
CMD_LOAD_IV        = 0x02
CMD_LOAD_AAD       = 0x03
CMD_LOAD_PLAINTEXT = 0x04
CMD_START_ENCRYPT  = 0x05

RESP_ACK_KEY       = 0x81
RESP_ACK_IV        = 0x82
RESP_ACK_AAD       = 0x83
RESP_ACK_PLAINTEXT = 0x84
RESP_CIPHERTEXT    = 0x90
RESP_AUTH_TAG      = 0x91
RESP_ERR_UNKNOWN   = 0xE0
RESP_ERR_LEN       = 0xE1

RESP_NAMES = {
    RESP_ACK_KEY:       "ACK_KEY",
    RESP_ACK_IV:        "ACK_IV",
    RESP_ACK_AAD:       "ACK_AAD",
    RESP_ACK_PLAINTEXT: "ACK_PLAINTEXT",
    RESP_CIPHERTEXT:    "CIPHERTEXT",
    RESP_AUTH_TAG:      "AUTH_TAG",
    RESP_ERR_UNKNOWN:   "ERR_UNKNOWN_CMD",
    RESP_ERR_LEN:       "ERR_LEN_MISMATCH"
}


class AesGcmUartClient:
    """Manages serial communication and packet protocol with AES-GCM FPGA."""

    def __init__(self, port: str = None, baudrate: int = 115200, timeout: float = 3.0, mode: str = "aes128"):
        self.baudrate = baudrate
        self.timeout  = timeout
        self.mode     = mode.lower()
        self.port     = port or self.auto_detect_port()
        print(f"[*] Opening serial port: {self.port} at {self.baudrate} baud (Mode: {self.mode.upper()})...")
        self.ser = serial.Serial(self.port, self.baudrate, timeout=self.timeout)
        self.ser.reset_input_buffer()
        self.ser.reset_output_buffer()
        time.sleep(0.1)

    @staticmethod
    def auto_detect_port() -> str:
        """Attempts to discover FTDI FT4232HL or generic USB serial adapter."""
        ports = list(serial.tools.list_ports.comports())
        if not ports:
            print("[-] No serial/COM ports discovered on system!")
            sys.exit(1)

        print("[*] Available Serial Ports:")
        for p in ports:
            print(f"    - {p.device}: {p.description} [{p.hwid}]")

        for p in ports:
            desc = (p.description or "").lower()
            hwid = (p.hwid or "").lower()
            if "ftdi" in desc or "ft4232" in desc or "polarfire" in desc or "0403:6011" in hwid:
                print(f"[+] Auto-selected port: {p.device} ({p.description})")
                return p.device

        print(f"[!] Using first available port: {ports[0].device}")
        return ports[0].device

    def close(self):
        """Closes active serial connection."""
        if self.ser and self.ser.is_open:
            self.ser.close()
            print("[*] Serial port closed.")

    def send_packet(self, cmd: int, payload: bytes = b""):
        """Encodes and transmits [CMD, LENGTH, PAYLOAD...]."""
        length = len(payload)
        if length > 255:
            raise ValueError(f"Payload length exceeds 255 bytes limit ({length})")
        packet = bytes([cmd, length]) + payload
        self.ser.write(packet)
        self.ser.flush()

    def receive_packet(self, timeout_sec: float = None) -> tuple[int, bytes]:
        """Reads and decodes a response packet: returns (resp_cmd, payload_bytes)."""
        old_timeout = self.ser.timeout
        if timeout_sec is not None:
            self.ser.timeout = timeout_sec

        try:
            header = self.ser.read(2)
            if len(header) < 2:
                raise TimeoutError(f"Timeout waiting for response packet header (got {len(header)} bytes)")
            resp_cmd = header[0]
            length   = header[1]
            payload  = self.ser.read(length) if length > 0 else b""
            if len(payload) < length:
                raise TimeoutError(f"Timeout reading payload: expected {length} bytes, got {len(payload)}")
            return resp_cmd, payload
        finally:
            self.ser.timeout = old_timeout

    def load_key(self, key_bytes: bytes):
        """Sends LOAD_KEY (0x01) and waits for ACK_KEY (0x81)."""
        expected_len = 32 if self.mode == "aes256" else 16
        if len(key_bytes) != expected_len:
            raise ValueError(f"For {self.mode.upper()}, AES key must be {expected_len} bytes, got {len(key_bytes)}")
        print(f"[->] LOAD_KEY ({len(key_bytes)} bytes): {key_bytes.hex()}")
        self.send_packet(CMD_LOAD_KEY, key_bytes)
        resp, _ = self.receive_packet()
        if resp != RESP_ACK_KEY:
            raise RuntimeError(f"Unexpected response to LOAD_KEY: 0x{resp:02X} ({RESP_NAMES.get(resp, 'UNKNOWN')})")
        print(f"[<-] ACK_KEY (0x{resp:02X}) confirmed.")

    def load_iv(self, iv_bytes: bytes):
        """Sends LOAD_IV (0x02) and waits for ACK_IV (0x82)."""
        if len(iv_bytes) != 12:
            raise ValueError(f"IV must be exactly 12 bytes (96 bits), got {len(iv_bytes)}")
        print(f"[->] LOAD_IV (12 bytes): {iv_bytes.hex()}")
        self.send_packet(CMD_LOAD_IV, iv_bytes)
        resp, _ = self.receive_packet()
        if resp != RESP_ACK_IV:
            raise RuntimeError(f"Unexpected response to LOAD_IV: 0x{resp:02X} ({RESP_NAMES.get(resp, 'UNKNOWN')})")
        print(f"[<-] ACK_IV (0x{resp:02X}) confirmed.")

    def load_aad(self, aad_bytes: bytes):
        """Sends LOAD_AAD (0x03) and waits for ACK_AAD (0x83)."""
        if len(aad_bytes) % 16 != 0 or len(aad_bytes) == 0:
            raise ValueError(f"AAD must be a non-zero multiple of 16 bytes, got {len(aad_bytes)}")
        print(f"[->] LOAD_AAD ({len(aad_bytes)} bytes): {aad_bytes.hex()}")
        self.send_packet(CMD_LOAD_AAD, aad_bytes)
        resp, _ = self.receive_packet()
        if resp != RESP_ACK_AAD:
            raise RuntimeError(f"Unexpected response to LOAD_AAD: 0x{resp:02X} ({RESP_NAMES.get(resp, 'UNKNOWN')})")
        print(f"[<-] ACK_AAD (0x{resp:02X}) confirmed.")

    def load_plaintext(self, pt_bytes: bytes):
        """Sends LOAD_PLAINTEXT (0x04) and waits for ACK_PLAINTEXT (0x84)."""
        if len(pt_bytes) % 16 != 0 or len(pt_bytes) == 0:
            raise ValueError(f"Plaintext must be a non-zero multiple of 16 bytes, got {len(pt_bytes)}")
        print(f"[->] LOAD_PLAINTEXT ({len(pt_bytes)} bytes): {pt_bytes.hex()}")
        self.send_packet(CMD_LOAD_PLAINTEXT, pt_bytes)
        resp, _ = self.receive_packet()
        if resp != RESP_ACK_PLAINTEXT:
            raise RuntimeError(f"Unexpected response to LOAD_PLAINTEXT: 0x{resp:02X} ({RESP_NAMES.get(resp, 'UNKNOWN')})")
        print(f"[<-] ACK_PLAINTEXT (0x{resp:02X}) confirmed.")

    def start_encrypt(self) -> tuple[bytes, bytes]:
        """Triggers START_ENCRYPT (0x05) and collects Ciphertext and Tag."""
        print(f"[->] START_ENCRYPT (0x05)")
        self.send_packet(CMD_START_ENCRYPT, b"")

        resp_ct, ct_data = self.receive_packet()
        if resp_ct != RESP_CIPHERTEXT:
            raise RuntimeError(f"Expected CIPHERTEXT (0x90), got 0x{resp_ct:02X} ({RESP_NAMES.get(resp_ct, 'UNKNOWN')})")
        print(f"[<-] CIPHERTEXT ({len(ct_data)} bytes): {ct_data.hex()}")

        resp_tag, tag_data = self.receive_packet()
        if resp_tag != RESP_AUTH_TAG:
            raise RuntimeError(f"Expected AUTH_TAG (0x91), got 0x{resp_tag:02X} ({RESP_NAMES.get(resp_tag, 'UNKNOWN')})")
        print(f"[<-] AUTH_TAG   ({len(tag_data)} bytes): {tag_data.hex()}")

        return ct_data, tag_data


def run_nist_self_tests(client: AesGcmUartClient):
    """Executes official NIST SP 800-38D Appendix B test vectors matching current mode."""
    print("\n" + "=" * 75)
    print(f" NIST SP 800-38D Hardware Verification Suite [{client.mode.upper()}]")
    print("=" * 75)

    if client.mode == "aes128":
        test_cases = [
            {
                "name": "NIST Appendix B - Test Case 2 (16B PT, AES-128)",
                "key": bytes.fromhex("00000000000000000000000000000000"),
                "iv":  bytes.fromhex("000000000000000000000000"),
                "aad": None,
                "pt":  bytes.fromhex("00000000000000000000000000000000"),
                "expected_ct":  bytes.fromhex("0388dace60b6a392f328c2b971b2fe78"),
                "expected_tag": bytes.fromhex("ab6e47d42cec13bdf53a67b21257bddf")
            },
            {
                "name": "NIST Appendix B - Test Case 3 (64B PT, AES-128)",
                "key": bytes.fromhex("feffe9928665731c6d6a8f9467308308"),
                "iv":  bytes.fromhex("cafebabefacedebadecaf888"),
                "aad": None,
                "pt":  bytes.fromhex("d9313225f88406e5a55909c5aff5269a86a7a9531534f7da2e4c303d8a318a72"
                                     "1c3c0c95956809532fcf0e2449a6b525b16aedf5aa0de657ba637b391aafd255"),
                "expected_ct":  bytes.fromhex("42831ec2217774244b7221b784d0d49ce3aa212f2c02a4e035c17e2329aca12e"
                                              "21d514b25466931c7d8f6a5aac84aa051ba30b396a0aac973d58e091473f5985"),
                "expected_tag": bytes.fromhex("4d5c2af327cd64a62cf35abd2ba6fab4")
            }
        ]
    else: # aes256
        test_cases = [
            {
                "name": "NIST Appendix B - Test Case 16 (16B PT, AES-256)",
                "key": bytes.fromhex("0000000000000000000000000000000000000000000000000000000000000000"),
                "iv":  bytes.fromhex("000000000000000000000000"),
                "aad": None,
                "pt":  bytes.fromhex("00000000000000000000000000000000"),
                "expected_ct":  bytes.fromhex("cea7403d4d606b6e074ec5d3baf39d18"),
                "expected_tag": bytes.fromhex("d0d1c8a799996bf0265b98b5d48ab919")
            },
            {
                "name": "NIST Appendix B - Test Case 17 (64B PT, AES-256)",
                "key": bytes.fromhex("feffe9928665731c6d6a8f9467308308feffe9928665731c6d6a8f9467308308"),
                "iv":  bytes.fromhex("cafebabefacedebadecaf888"),
                "aad": None,
                "pt":  bytes.fromhex("d9313225f88406e5a55909c5aff5269a86a7a9531534f7da2e4c303d8a318a72"
                                     "1c3c0c95956809532fcf0e2449a6b525b16aedf5aa0de657ba637b391aafd255"),
                "expected_ct":  bytes.fromhex("522dc1f099567d07f47f37a32a84427d643a8cdcbfe5c0c97598a2bd2555d3aa"
                                              "8cb1d83705d8f801de0477274ff73f56302dd5d1dfcd1f50244db54296041b46"),
                "expected_tag": bytes.fromhex("a34988770c1e0d2949cb9e7b30c8400f")
            }
        ]

    passed = 0
    for i, tc in enumerate(test_cases, 1):
        print(f"\n--- Running Test {i}: {tc['name']} ---")
        client.load_key(tc["key"])
        client.load_iv(tc["iv"])
        if tc["aad"]:
            client.load_aad(tc["aad"])
        client.load_plaintext(tc["pt"])
        ct, tag = client.start_encrypt()

        ct_ok  = (ct == tc["expected_ct"])
        tag_ok = (tag == tc["expected_tag"])

        print(f"  Result CT : {'PASS' if ct_ok else 'FAIL'}")
        if not ct_ok:
            print(f"    Expected: {tc['expected_ct'].hex()}")
            print(f"    Received: {ct.hex()}")

        print(f"  Result TAG: {'PASS' if tag_ok else 'FAIL'}")
        if not tag_ok:
            print(f"    Expected: {tc['expected_tag'].hex()}")
            print(f"    Received: {tag.hex()}")

        if ct_ok and tag_ok:
            print(f"[PASS] {tc['name']} verified successfully!")
            passed += 1
        else:
            print(f"[FAIL] {tc['name']} mismatch!")

    print("\n" + "=" * 75)
    print(f" SUMMARY: {passed} / {len(test_cases)} tests passed for {client.mode.upper()}.")
    print("=" * 75)


def main():
    parser = argparse.ArgumentParser(description="AES-GCM Multi-Variant FPGA UART Host Client")
    parser.add_argument("-m", "--mode", type=str, choices=["aes128", "aes256"], default="aes128",
                        help="AES accelerator target variant (default: aes128)")
    parser.add_argument("-p", "--port", type=str, default=None, help="Serial COM port (e.g. COM3 or /dev/ttyUSB0)")
    parser.add_argument("-b", "--baud", type=int, default=115200, help="UART baud rate (default: 115200)")
    parser.add_argument("-t", "--timeout", type=float, default=3.0, help="Response timeout in seconds (default: 3.0)")
    parser.add_argument("--test-nist", action="store_true", help="Run automated NIST SP 800-38D verification")
    parser.add_argument("--key", type=str, help="Encryption key in hex (16B for aes128, 32B for aes256)")
    parser.add_argument("--iv", type=str, help="96-bit Initialization Vector in hex")
    parser.add_argument("--aad", type=str, default="", help="Additional Authenticated Data in hex (Optional)")
    parser.add_argument("--pt", type=str, help="Plaintext in hex (multiple of 16 bytes)")

    args = parser.parse_args()

    client = AesGcmUartClient(port=args.port, baudrate=args.baud, timeout=args.timeout, mode=args.mode)

    try:
        if args.test_nist or not (args.key and args.iv and args.pt):
            run_nist_self_tests(client)
        else:
            key_b = bytes.fromhex(args.key)
            iv_b  = bytes.fromhex(args.iv)
            pt_b  = bytes.fromhex(args.pt)
            aad_b = bytes.fromhex(args.aad) if args.aad else b""

            client.load_key(key_b)
            client.load_iv(iv_b)
            if aad_b:
                client.load_aad(aad_b)
            client.load_plaintext(pt_b)
            ct, tag = client.start_encrypt()

            print("\n" + "=" * 60)
            print(f" ENCRYPTION RESULT [{args.mode.upper()}]")
            print("=" * 60)
            print(f"Ciphertext: {ct.hex()}")
            print(f"Auth Tag:   {tag.hex()}")
            print("=" * 60)
    finally:
        client.close()


if __name__ == "__main__":
    main()
