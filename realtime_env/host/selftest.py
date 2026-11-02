"""NIST SP 800-38D vectors, run through any link: `main.py --advanced selftest`."""

from typing import Dict, List

from . import console, framing
from .protocol import (
    CMD_LOAD_AAD, CMD_LOAD_IV, CMD_LOAD_KEY, CMD_LOAD_PLAINTEXT, CMD_LOAD_TAG_REF, CMD_START_DECRYPT,
    CMD_START_ENCRYPT,
)

_TC3_PT = ("d9313225f88406e5a55909c5aff5269a86a7a9531534f7da2e4c303d8a318a72"
           "1c3c0c95956809532fcf0e2449a6b525b16aedf5aa0de657ba637b391aafd255")

# Tags as the RTL returns them, which follow NIST SP 800-38D
VECTORS: Dict[int, List[dict]] = {
    16: [
        {"name": "NIST App.B TC2 (Zero Vector)", "mode": "ENC", "key": "00" * 16, "iv": "00" * 12, "aad": "",
         "data": "00" * 16, "expected_ct": "0388dace60b6a392f328c2b971b2fe78",
         "expected_tag": "ab6e47d42cec13bdf53a67b21257bddf"},
        {"name": "NIST App.B TC3 (64B Stream)", "mode": "ENC", "key": "feffe9928665731c6d6a8f9467308308",
         "iv": "cafebabefacedbaddecaf888", "aad": "", "data": _TC3_PT,
         "expected_ct": "42831ec2217774244b7221b784d0d49ce3aa212f2c02a4e035c17e2329aca12e"
                        "21d514b25466931c7d8f6a5aac84aa051ba30b396a0aac973d58e091473f5985",
         "expected_tag": "4d5c2af327cd64a62cf35abd2ba6fab4"},
        {"name": "AES-128 Decrypt & Verify", "mode": "DEC", "key": "00" * 16, "iv": "00" * 12, "aad": "",
         "data": "0388dace60b6a392f328c2b971b2fe78", "expected_ct": "00" * 16,
         "expected_tag": "ab6e47d42cec13bdf53a67b21257bddf"},
    ],
    32: [
        {"name": "GCM spec TC14 (Zero Vector)", "mode": "ENC", "key": "00" * 32, "iv": "00" * 12, "aad": "",
         "data": "00" * 16, "expected_ct": "cea7403d4d606b6e074ec5d3baf39d18",
         "expected_tag": "d0d1c8a799996bf0265b98b5d48ab919"},
        {"name": "GCM spec TC15 (64B Stream)", "mode": "ENC", "key": "feffe9928665731c6d6a8f9467308308" * 2,
         "iv": "cafebabefacedbaddecaf888", "aad": "", "data": _TC3_PT,
         "expected_ct": "522dc1f099567d07f47f37a32a84427d643a8cdcbfe5c0c97598a2bd2555d1aa"
                        "8cb08e48590dbb3da7b08b1056828838c5f61e6393ba7a0abcc9f662898015ad",
         "expected_tag": "b094dac5d93471bdec1a502270e3cc6c"},
        {"name": "Custom AAD+PT vector 16B", "mode": "ENC", "key": "feffe9928665731c6d6a8f9467308308" * 2,
         "iv": "cafebabefacedbaddecaf888", "aad": "feedfacedeadbeeffeedfacedeadbeef",
         "data": "d9313225f88406e5a55909c5aff5269a", "expected_ct": "522dc1f099567d07f47f37a32a84427d",
         "expected_tag": "03a2864be371e37753a80e8e240ff2f0"},
        {"name": "AES-256 Decrypt & Verify", "mode": "DEC", "key": "feffe9928665731c6d6a8f9467308308" * 2,
         "iv": "cafebabefacedbaddecaf888", "aad": "feedfacedeadbeeffeedfacedeadbeef",
         "data": "522dc1f099567d07f47f37a32a84427d", "expected_ct": "d9313225f88406e5a55909c5aff5269a",
         "expected_tag": "03a2864be371e37753a80e8e240ff2f0"},
    ],
}


def vectors_for(key_bytes: int) -> List[dict]:
    """The vectors with bytes instead of hex, in the shape uart_client.run_self_tests reads."""
    return [{**vector, **{name: bytes.fromhex(vector[name]) if vector[name] else None
                          for name in ("key", "iv", "aad", "data", "expected_ct", "expected_tag")}}
            for vector in VECTORS[key_bytes]]


def packets_of(vector: dict) -> list:
    packets = [(CMD_LOAD_KEY, vector["key"]), (CMD_LOAD_IV, vector["iv"])]
    if vector["aad"]:
        packets.append((CMD_LOAD_AAD, vector["aad"]))
    packets.append((CMD_LOAD_PLAINTEXT, vector["data"]))
    decrypt = vector["mode"] == "DEC"
    if decrypt:
        packets.append((CMD_LOAD_TAG_REF, vector["expected_tag"]))
    packets.append((CMD_START_DECRYPT if decrypt else CMD_START_ENCRYPT, b""))
    return packets


def run(channel, key_bytes: int, report: console.Report) -> int:
    report.section("SELF-TEST NIST", f"AES-{key_bytes * 8}")
    report.field("Nguồn", channel.label, "dim")
    failed = 0
    for vector in vectors_for(key_bytes):
        reply = framing.split_rx(channel.exchange(packets_of(vector), "selftest").responses)[0]
        passed = reply.data == vector["expected_ct"] and reply.tag == vector["expected_tag"]
        if vector["mode"] == "DEC":
            passed = passed and bool(reply.verified)
        failed += not passed
        report.line(f" {vector['name']:<32} {'PASS' if passed else 'FAIL'}   tag {reply.tag.hex()}",
                    "pass" if passed else "fail")
    report.field("Kết quả", f"{len(VECTORS[key_bytes]) - failed}/{len(VECTORS[key_bytes])} PASS",
                 "fail" if failed else "pass")
    return 1 if failed else 0
