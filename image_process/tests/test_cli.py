import pytest
from PIL import Image

from imgapp import image_io
from imgapp.__main__ import main


@pytest.fixture
def photo(tmp_path):
    input_dir = tmp_path / "input"
    input_dir.mkdir()
    gradient = Image.linear_gradient("L").resize((300, 200))
    gradient.save(input_dir / "photo.png")
    return input_dir / "photo.png"


def encoded(photo, tmp_path, *options):
    out = tmp_path / "output"
    assert main(["encode", str(photo), "--output-dir", str(out), *options]) == 0
    return out / photo.name


def simulated(photo, tmp_path, *options):
    folder = encoded(photo, tmp_path, *options)
    assert main(["simulate", str(folder / "tx.bin")]) == 0
    return folder


def test_encode_resizes_to_exact_gray_image(photo, tmp_path):
    folder = encoded(photo, tmp_path, "--size", "64x48")
    with Image.open(folder / "preview.png") as preview:
        assert (preview.mode, preview.size) == ("L", (64, 48))
    assert (folder / "tx.txt").exists() and (folder / "tx.bin").exists()


def test_decode_from_txt_matches_preview(photo, tmp_path):
    folder = encoded(photo, tmp_path, "--size", "64x48")
    assert main(["decode", str(folder / "tx.txt")]) == 0
    assert image_io.read_pixels(folder / "decoded.png") == image_io.read_pixels(folder / "preview.png")


@pytest.mark.parametrize("variant", ["aes128", "aes256"])
def test_decrypt_restores_the_image(photo, tmp_path, variant):
    folder = simulated(photo, tmp_path, "--size", "64x48", "-v", variant)
    assert main(["decrypt", str(folder / "tx.bin"), str(folder / "rx.bin")]) == 0
    assert image_io.read_pixels(folder / "decrypted.png") == image_io.read_pixels(folder / "preview.png")
    assert (folder / "tx_dec.txt").exists()


def test_ciphertext_image_hides_the_picture(photo, tmp_path):
    folder = simulated(photo, tmp_path, "--size", "64x48")
    assert main(["decode", str(folder / "tx.bin"), "--rx", str(folder / "rx.bin")]) == 0
    cipher = image_io.read_pixels(folder / "cipher.png")
    plain = image_io.read_pixels(folder / "preview.png")
    assert len(cipher) == len(plain)
    assert sum(a == b for a, b in zip(cipher, plain)) < len(plain) / 20


def test_tampered_chunk_is_named_and_no_image_is_written(photo, tmp_path, capsys):
    folder = simulated(photo, tmp_path, "--size", "64x48")
    assert main(["decrypt", str(folder / "tx.bin"), str(folder / "rx.bin")]) == 0

    rx = bytearray((folder / "rx.bin").read_bytes())
    # ACK_KEY + ACK_IV + ACK_AAD + ACK_PT, then CIPHERTEXT header, 240 data bytes, 18-byte tag
    second_chunk = 8 + 2 + 240 + 18
    rx[second_chunk + 4 + 2 + 5] ^= 0x01  # Past ACK_IV, ACK_PT and the CIPHERTEXT header
    (folder / "rx.bin").write_bytes(rx)

    assert main(["decrypt", str(folder / "tx.bin"), str(folder / "rx.bin")]) == 1
    assert "chunk(s): 1" in capsys.readouterr().out
    assert not (folder / "decrypted.png").exists()


def test_run_processes_every_image_in_the_folder(photo, tmp_path):
    Image.new("RGBA", (50, 90), (255, 0, 0, 128)).save(photo.with_name("alpha.png"))
    out = tmp_path / "output"
    assert main(["run", "--input-dir", str(photo.parent), "--output-dir", str(out), "--size", "32x32"]) == 0
    for name in ("photo.png", "alpha.png"):
        assert (out / name / "decrypted.png").exists()


def test_run_reports_an_unreadable_file_and_keeps_going(photo, tmp_path):
    photo.with_name("broken.jpg").write_bytes(b"not an image")
    out = tmp_path / "output"
    assert main(["run", "--input-dir", str(photo.parent), "--output-dir", str(out), "--size", "32x32"]) == 1
    assert (out / "photo.png" / "decrypted.png").exists()


def test_empty_input_folder_is_reported(tmp_path):
    assert main(["run", "--input-dir", str(tmp_path)]) == 1


def test_wrong_key_length_is_rejected(photo, tmp_path):
    assert main(["encode", str(photo), "--output-dir", str(tmp_path), "--key", "00ff"]) == 1


def test_16_bit_png_is_not_clipped_to_white(tmp_path):
    path = tmp_path / "deep.png"
    Image.new("I;16", (8, 8), 32768).save(path)
    assert set(image_io.load_gray(path, (8, 8)).tobytes()) == {128}
