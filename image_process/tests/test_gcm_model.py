import pytest
from Crypto.Cipher import AES

from imgapp import gcm_model

PT_64 = bytes.fromhex("d9313225f88406e5a55909c5aff5269a86a7a9531534f7da2e4c303d8a318a72"
                      "1c3c0c95956809532fcf0e2449a6b525b16aedf5aa0de657ba637b391aafd255")
KEY_128 = bytes.fromhex("feffe9928665731c6d6a8f9467308308")
IV = bytes.fromhex("cafebabefacedebadecaf888")
AAD = bytes.fromhex("feedfacedeadbeeffeedfacedeadbeef")

NIST_IV = bytes.fromhex("cafebabefacedbaddecaf888")

# Raw RTL tags, from run_self_tests() in uart_integration/python/host.py.
# TC3's tag came from this model, so it only guards the two files against drifting apart.
RTL_VECTORS = [
    ("TC2", bytes(16), bytes(12), b"", bytes(16), "2c4fa7cbc8dcac66067fb1a42b88adc8"),
    ("TC3", KEY_128, NIST_IV, b"", PT_64, "892029877346acb76c60979458277c8d"),
    ("TC16", bytes(32), bytes(12), b"", bytes(16), "eca8e26b44cb8ab9e5cddc39bdd43704"),
    ("TC17", KEY_128 * 2, IV, b"", PT_64, "3539d3f390b09ca3cae3543a9af25d6f"),
    ("TC18", KEY_128 * 2, IV, AAD, PT_64[:16], "0b9c23630bd31f5e963bf7361d42e0e5"),
]


@pytest.mark.parametrize("name,key,iv,aad,plaintext,tag", RTL_VECTORS, ids=[v[0] for v in RTL_VECTORS])
def test_tag_matches_rtl_vectors(name, key, iv, aad, plaintext, tag):
    _, computed = gcm_model.run_message(key, iv, aad, plaintext)
    assert computed.hex() == tag


@pytest.mark.parametrize("name,key,iv,aad,plaintext,tag", RTL_VECTORS, ids=[v[0] for v in RTL_VECTORS])
def test_ciphertext_matches_nist_gcm(name, key, iv, aad, plaintext, tag):
    cipher = AES.new(key, AES.MODE_GCM, nonce=iv)
    cipher.update(aad)
    ciphertext, _ = gcm_model.run_message(key, iv, aad, plaintext)
    assert ciphertext == cipher.encrypt(plaintext)


def test_ciphertext_matches_published_nist_tc3():
    ciphertext, _ = gcm_model.run_message(KEY_128, NIST_IV, b"", PT_64)
    assert ciphertext.hex() == ("42831ec2217774244b7221b784d0d49ce3aa212f2c02a4e035c17e2329aca12e"
                                "21d514b25466931c7d8f6a5aac84aa051ba30b396a0aac973d58e091473f5985")


def test_decrypt_recovers_plaintext_with_the_same_tag():
    ciphertext, tag = gcm_model.run_message(KEY_128, IV, AAD, PT_64)
    plaintext, decrypt_tag = gcm_model.run_message(KEY_128, IV, AAD, ciphertext, decrypt=True)
    assert plaintext == PT_64
    assert decrypt_tag == tag
