import pytest
from host.protocol import (
    CMD_LOAD_IV, CMD_LOAD_KEY, CMD_LOAD_PLAINTEXT, CMD_LOAD_TAG_REF, CMD_START_DECRYPT,
    CMD_START_ENCRYPT, RESP_ACK_IV, RESP_ACK_KEY, RESP_ACK_PLAINTEXT, RESP_ACK_TAG_REF,
    RESP_AUTH_TAG, RESP_CIPHERTEXT, RESP_ERR_LEN, RESP_VERIFY_RESULT, VERIFY_FAIL, VERIFY_PASS,
)

from host import gcm_model

PT_64 = bytes.fromhex("d9313225f88406e5a55909c5aff5269a86a7a9531534f7da2e4c303d8a318a72"
                      "1c3c0c95956809532fcf0e2449a6b525b16aedf5aa0de657ba637b391aafd255")
KEY_128 = bytes.fromhex("feffe9928665731c6d6a8f9467308308")
IV = bytes.fromhex("cafebabefacedbaddecaf888")
AAD = bytes.fromhex("feedfacedeadbeeffeedfacedeadbeef")

# Tags as returned by the RTL, which follow NIST SP 800-38D (see uart_client.py run_self_tests).
NIST_VECTORS = [
    ("TC2", bytes(16), bytes(12), b"", bytes(16), "ab6e47d42cec13bdf53a67b21257bddf"),
    ("TC3", KEY_128, IV, b"", PT_64, "4d5c2af327cd64a62cf35abd2ba6fab4"),
    ("TC14", bytes(32), bytes(12), b"", bytes(16), "d0d1c8a799996bf0265b98b5d48ab919"),
    ("TC15", KEY_128 * 2, IV, b"", PT_64, "b094dac5d93471bdec1a502270e3cc6c"),
    ("custom_aad", KEY_128 * 2, IV, AAD, PT_64[:16], "03a2864be371e37753a80e8e240ff2f0"),
]


@pytest.mark.parametrize("name,key,iv,aad,plaintext,tag", NIST_VECTORS, ids=[v[0] for v in NIST_VECTORS])
def test_tag_matches_nist_vectors(name, key, iv, aad, plaintext, tag):
    _, computed = gcm_model.run_message(key, iv, aad, plaintext)
    assert computed.hex() == tag


def test_ciphertext_matches_published_nist_tc3():
    ciphertext, _ = gcm_model.run_message(KEY_128, IV, b"", PT_64)
    assert ciphertext.hex() == ("42831ec2217774244b7221b784d0d49ce3aa212f2c02a4e035c17e2329aca12e"
                                "21d514b25466931c7d8f6a5aac84aa051ba30b396a0aac973d58e091473f5985")


def test_decrypt_recovers_plaintext_with_the_same_tag():
    ciphertext, tag = gcm_model.run_message(KEY_128, IV, AAD, PT_64)
    plaintext, decrypt_tag = gcm_model.run_message(KEY_128, IV, AAD, ciphertext, decrypt=True)
    assert plaintext == PT_64
    assert decrypt_tag == tag


def decrypt_stream(ciphertext, tag_ref):
    packets = [(CMD_LOAD_KEY, KEY_128), (CMD_LOAD_IV, IV), (CMD_LOAD_PLAINTEXT, ciphertext)]
    if tag_ref is not None:
        packets.append((CMD_LOAD_TAG_REF, tag_ref))
    return packets + [(CMD_START_DECRYPT, b"")]


ACKS = [(RESP_ACK_KEY, b""), (RESP_ACK_IV, b""), (RESP_ACK_PLAINTEXT, b"")]


def test_decrypt_with_the_right_tag_releases_the_plaintext():
    ciphertext, tag = gcm_model.run_message(KEY_128, IV, b"", PT_64)
    assert gcm_model.simulate(decrypt_stream(ciphertext, tag)) == ACKS + [
        (RESP_ACK_TAG_REF, b""), (RESP_CIPHERTEXT, PT_64), (RESP_AUTH_TAG, tag),
        (RESP_VERIFY_RESULT, VERIFY_PASS),
    ]


def test_decrypt_with_a_wrong_tag_withholds_the_plaintext():
    ciphertext, tag = gcm_model.run_message(KEY_128, IV, b"", PT_64)
    assert gcm_model.simulate(decrypt_stream(ciphertext, bytes(16))) == ACKS + [
        (RESP_ACK_TAG_REF, b""), (RESP_AUTH_TAG, tag), (RESP_VERIFY_RESULT, VERIFY_FAIL),
    ]


def test_decrypt_without_a_tag_ref_is_refused():
    ciphertext, _ = gcm_model.run_message(KEY_128, IV, b"", PT_64)
    assert gcm_model.simulate(decrypt_stream(ciphertext, None)) == ACKS + [
        (RESP_ERR_LEN, bytes([CMD_START_DECRYPT])),
    ]


def test_tag_ref_does_not_carry_over_to_the_next_message():
    ciphertext, tag = gcm_model.run_message(KEY_128, IV, b"", PT_64)
    responses = gcm_model.simulate(decrypt_stream(ciphertext, tag) + [
        (CMD_LOAD_IV, IV), (CMD_LOAD_PLAINTEXT, ciphertext), (CMD_START_DECRYPT, b"")])
    assert responses[-1] == (RESP_ERR_LEN, bytes([CMD_START_DECRYPT]))


def test_start_without_data_is_refused():
    assert gcm_model.simulate([(CMD_LOAD_KEY, KEY_128), (CMD_LOAD_IV, IV), (CMD_START_ENCRYPT, b"")])[-1] == (
        RESP_ERR_LEN, bytes([CMD_START_ENCRYPT]))
