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
    assert set(image_io.load_image(path, (8, 8)).tobytes()) == {128}


@pytest.fixture
def color_photo(tmp_path):
    path = tmp_path / "color.png"
    bands = [Image.linear_gradient("L").rotate(angle).resize((64, 48)) for angle in (0, 90, 180)]
    Image.merge("RGB", bands).save(path)
    return path


def test_color_image_keeps_its_three_channels(color_photo, tmp_path):
    folder = encoded(color_photo, tmp_path, "--size", "32x24")
    with Image.open(folder / "preview.png") as preview:
        assert (preview.mode, preview.size) == ("RGB", (32, 24))
    assert "32x24 RGB8" in (folder / "tx.txt").read_text(encoding="utf-8").splitlines()[0]


def test_gray_flag_forces_one_channel(color_photo, tmp_path):
    folder = encoded(color_photo, tmp_path, "--size", "32x24", "--gray")
    with Image.open(folder / "preview.png") as preview:
        assert preview.mode == "L"


def test_color_round_trip_restores_every_channel(color_photo, tmp_path):
    folder = simulated(color_photo, tmp_path, "--size", "32x24")
    assert main(["decrypt", str(folder / "tx.bin"), str(folder / "rx.bin")]) == 0
    assert main(["decode", str(folder / "tx.bin"), "--rx", str(folder / "rx.bin")]) == 0
    assert main(["decode", str(folder / "tx.bin")]) == 0
    pixels = image_io.read_pixels(folder / "preview.png")
    assert len(pixels) == 32 * 24 * 3
    assert image_io.read_pixels(folder / "decrypted.png") == pixels
    assert image_io.read_pixels(folder / "decoded.png") == pixels
    assert len(image_io.read_pixels(folder / "cipher.png")) == len(pixels)


@pytest.mark.parametrize("source", ["P", "CMYK"])
def test_other_color_modes_become_rgb(tmp_path, source):
    path = tmp_path / "other.tiff"
    Image.new("RGB", (4, 4), (200, 30, 10)).convert(source).save(path)
    assert image_io.load_image(path, (4, 4)).mode == "RGB"


def test_transparent_color_lands_on_white(tmp_path):
    path = tmp_path / "alpha.png"
    Image.new("RGBA", (2, 2), (255, 0, 0, 0)).save(path)
    assert image_io.load_image(path, (2, 2)).getpixel((0, 0)) == (255, 255, 255)


def test_unknown_channel_count_is_rejected():
    with pytest.raises(ValueError, match="channels"):
        image_io.pixel_mode(2)


def tiff_row(tmp_path, mode, values):
    path = tmp_path / "row.tiff"
    img = Image.new(mode, (len(values), 1))
    img.putdata(values)
    img.save(path)
    return path


@pytest.mark.parametrize("mode,values,expected", [
    ("F", [0.0, 0.5, 1.0], [0, 127, 255]),         # Normalised floats use the full 0..1 scale
    ("F", [0.2, 0.6], [51, 153]),                  # ...so a dim image stays dim
    ("F", [-1.0, 0.0, 1.0], [0, 127, 255]),        # Other ranges stretch to fit
    ("F", [0.0, 500.0, 1000.0], [0, 127, 255]),
    ("I", [0, 2 ** 30, 2 ** 31 - 1], [0, 127, 255]),
    ("I", [0, 32768, 65535], [0, 128, 255]),       # 16-bit data in a 32-bit file
    ("F", [5.0, 5.0], [0, 0]),                     # Flat image has no range to stretch
])
def test_high_depth_tiff_keeps_its_tones(tmp_path, mode, values, expected):
    pixels = image_io.load_image(tiff_row(tmp_path, mode, values), (len(values), 1)).tobytes()
    assert [abs(a - b) <= 1 for a, b in zip(pixels, expected)] == [True] * len(expected)


@pytest.mark.parametrize("bad", [float("inf"), float("-inf"), float("nan")])
def test_non_finite_tiff_is_rejected(tmp_path, bad):
    with pytest.raises(ValueError, match="finite"):
        image_io.load_image(tiff_row(tmp_path, "F", [0.0, bad, 1.0]), (3, 1))
