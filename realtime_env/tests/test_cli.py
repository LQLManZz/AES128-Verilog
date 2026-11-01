import json

import pytest
from PIL import Image

from host import gcm_model, image_io, links, packet_file
from host.cli import main

KEY = "00112233445566778899aabbccddeeff" * 2
KEY_128 = "00112233445566778899aabbccddeeff"
IV = "cafebabefacedbaddecaf888"
AAD = "feedfacedeadbeeffeedfacedeadbeef"
SIM = ["--link", "uart12m", "--sim", "model"]


@pytest.fixture
def photo(tmp_path):
    input_dir = tmp_path / "input"
    input_dir.mkdir()
    Image.linear_gradient("L").resize((300, 200)).save(input_dir / "photo.png")
    return input_dir / "photo.png"


@pytest.fixture
def color_photo(tmp_path):
    path = tmp_path / "color.png"
    bands = [Image.linear_gradient("L").rotate(angle).resize((64, 48)) for angle in (0, 90, 180)]
    Image.merge("RGB", bands).save(path)
    return path


def run_image(source, tmp_path, *options, key=KEY):
    return main(["image", str(source), "--output-dir", str(tmp_path / "output"), *SIM,
                 "--key", key, "--iv", IV, "--aad", AAD, "--size", "32x24", *options])


def run_raw(tmp_path, *options, key=KEY_128):
    return main(["raw", "--output-dir", str(tmp_path / "output"), *SIM, "--key", key, "--iv", IV, *options])


def test_image_round_trip_restores_every_pixel(photo, tmp_path):
    assert run_image(photo, tmp_path) == 0
    folder = tmp_path / "output" / "photo.png"
    assert image_io.read_pixels(folder / "decrypted.png") == image_io.read_pixels(folder / "preview.png")
    for name in ("tx.bin", "tx.txt", "rx.bin", "tx_dec.bin", "rx_dec.bin", "session.json", "cipher.png"):
        assert (folder / name).exists()


@pytest.mark.parametrize("key", [KEY_128, KEY])
def test_key_length_picks_the_aes_size(photo, tmp_path, key):
    assert run_image(photo, tmp_path, key=key) == 0
    tx = packet_file.read_stream(tmp_path / "output" / "photo.png" / "tx.bin")
    assert tx[0][1] == bytes.fromhex(key)


def test_users_iv_and_aad_reach_the_stream(photo, tmp_path):
    assert run_image(photo, tmp_path) == 0
    tx = packet_file.read_stream(tmp_path / "output" / "photo.png" / "tx.bin")
    assert tx[1] == (0x02, bytes.fromhex(IV))
    assert tx[2] == (0x03, bytes.fromhex(AAD))


def test_image_size_lives_in_session_json_not_in_the_aad(color_photo, tmp_path):
    assert run_image(color_photo, tmp_path) == 0
    session = json.loads((tmp_path / "output" / "color.png" / "session.json").read_text())
    assert (session["width"], session["height"], session["channels"]) == (32, 24, 3)


def test_two_images_never_share_an_iv(photo, color_photo, tmp_path):
    color_photo.rename(photo.with_name("other.png"))
    assert run_image(photo.parent, tmp_path) == 0
    ivs = []
    for name in ("photo.png", "other.png"):
        tx = packet_file.read_stream(tmp_path / "output" / name / "tx.bin")
        ivs += [payload for cmd, payload in tx if cmd == 0x02]
    assert len(set(ivs)) == len(ivs)


def test_ciphertext_image_hides_the_picture(photo, tmp_path):
    assert run_image(photo, tmp_path) == 0
    folder = tmp_path / "output" / "photo.png"
    cipher = image_io.read_pixels(folder / "cipher.png")
    plain = image_io.read_pixels(folder / "preview.png")
    assert len(cipher) == len(plain)
    assert sum(a == b for a, b in zip(cipher, plain)) < len(plain) / 20


def test_tampered_chunk_is_named_and_no_image_is_written(photo, tmp_path, capsys):
    assert run_image(photo, tmp_path, "--tamper-chunk", "1") == 1
    assert "chunk(s): 1" in capsys.readouterr().out
    assert not (tmp_path / "output" / "photo.png" / "decrypted.png").exists()


def test_unreadable_file_is_reported_and_the_rest_keep_going(photo, tmp_path):
    photo.with_name("broken.jpg").write_bytes(b"not an image")
    assert run_image(photo.parent, tmp_path) == 1
    assert (tmp_path / "output" / "photo.png" / "decrypted.png").exists()


def test_empty_input_folder_is_reported(tmp_path):
    empty = tmp_path / "nothing"
    empty.mkdir()
    assert run_image(empty, tmp_path) == 1


@pytest.mark.parametrize("missing", ["--key", "--iv"])
def test_key_and_iv_are_required(photo, tmp_path, missing):
    arguments = ["image", str(photo), *SIM, "--key", KEY, "--iv", IV]
    arguments = [item for index, item in enumerate(arguments)
                 if item != missing and (index == 0 or arguments[index - 1] != missing)]
    with pytest.raises(SystemExit):
        main(arguments)


@pytest.mark.parametrize("flag,value", [("--key", "00ff"), ("--iv", "00ff"), ("--aad", "00" * 241), ("--key", "zz")])
def test_bad_values_are_rejected(photo, tmp_path, flag, value):
    arguments = {"--key": KEY, "--iv": IV, "--aad": AAD, flag: value}
    assert main(["image", str(photo), "--output-dir", str(tmp_path), *SIM,
                 *[item for pair in arguments.items() for item in pair]]) == 1


def test_iv_reuse_warning_is_always_printed(photo, tmp_path, capsys):
    assert run_image(photo, tmp_path) == 0
    assert "chỉ dùng một lần" in capsys.readouterr().out


def test_short_aad_is_padded_with_a_warning(tmp_path, capsys):
    assert run_raw(tmp_path, "--aad", "0011", "--data", "00" * 16) == 0
    assert "AAD được đệm 0" in capsys.readouterr().out


def test_raw_message_matches_nist_test_case_2(tmp_path, capsys):
    arguments = ["raw", *SIM, "--key", "00" * 16, "--iv", "00" * 12, "--data", "00" * 16,
                 "--output-dir", str(tmp_path)]
    assert main(arguments) == 0
    text = capsys.readouterr().out
    assert "0388dace 60b6a392 f328c2b9 71b2fe78" in text
    assert "ab6e47d42cec13bdf53a67b21257bddf" in text


def test_raw_decrypt_checks_the_tag_in_the_ip(tmp_path, capsys):
    common = ["raw", *SIM, "--key", "00" * 16, "--iv", "00" * 12, "--data", "0388dace60b6a392f328c2b971b2fe78",
              "--op", "decrypt", "--output-dir", str(tmp_path)]
    assert main([*common, "--tag", "ab6e47d42cec13bdf53a67b21257bddf"]) == 0
    assert "PASS" in capsys.readouterr().out
    assert main([*common, "--tag", "00" * 16]) == 1
    assert "FAIL" in capsys.readouterr().out


def test_raw_decrypt_needs_a_tag(tmp_path, capsys):
    assert run_raw(tmp_path, "--data", "00" * 16, "--op", "decrypt") == 1
    assert "--tag" in capsys.readouterr().out


def test_raw_needs_exactly_one_input(tmp_path):
    assert run_raw(tmp_path) == 1
    assert run_raw(tmp_path, "--data", "00", "--file", "x") == 1


def test_raw_message_longer_than_one_gcm_message_is_refused(tmp_path, capsys):
    assert run_raw(tmp_path, "--data", "00" * 241) == 1
    assert "--file" in capsys.readouterr().out


@pytest.mark.parametrize("length", [1, 240, 5001])
def test_raw_file_comes_back_byte_for_byte(tmp_path, length, capsys):
    path = tmp_path / "frame.jpg"
    path.write_bytes(bytes(i % 251 for i in range(length)))
    assert run_raw(tmp_path, "--file", str(path), "--aad", AAD) == 0
    assert (tmp_path / "output" / "frame.jpg" / "decrypted.jpg").read_bytes() == path.read_bytes()
    assert "overhead" in capsys.readouterr().out


def test_tampered_raw_file_is_not_written(tmp_path):
    path = tmp_path / "frame.bin"
    path.write_bytes(bytes(1000))
    assert run_raw(tmp_path, "--file", str(path), "--tamper-chunk", "2") == 1
    assert not (tmp_path / "output" / "frame.bin" / "decrypted.bin").exists()


def test_every_link_has_a_preset():
    assert {name: (preset.baud, preset.sclk_mhz) for name, preset in links.LINKS.items()} == {
        "uart2m": (2_000_000, 0.0), "uart12m": (12_000_000, 0.0), "spi40": (0, 40.0), "spi30": (0, 30.0),
    }


def test_rtl_is_refused_for_the_camera(capsys):
    assert main(["camera", "--link", "spi40", "--sim", "rtl", "--key", KEY, "--iv", IV]) == 1
    assert "real time" in capsys.readouterr().out


def test_sample_writes_an_image(tmp_path):
    path = tmp_path / "sample.png"
    assert main(["sample", "-o", str(path), "--size", "16x16"]) == 0
    assert path.exists()


def test_16_bit_png_is_not_clipped_to_white(tmp_path):
    path = tmp_path / "deep.png"
    Image.new("I;16", (8, 8), 32768).save(path)
    assert set(image_io.load_image(path, (8, 8)).tobytes()) == {128}


def test_gray_flag_forces_one_channel(color_photo, tmp_path):
    assert run_image(color_photo, tmp_path, "--gray") == 0
    with Image.open(tmp_path / "output" / "color.png" / "preview.png") as preview:
        assert preview.mode == "L"


def test_color_image_keeps_its_three_channels(color_photo, tmp_path):
    assert run_image(color_photo, tmp_path) == 0
    with Image.open(tmp_path / "output" / "color.png" / "preview.png") as preview:
        assert (preview.mode, preview.size) == ("RGB", (32, 24))


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


def test_model_channel_answers_like_gcm_model():
    packets = [(0x01, bytes(16)), (0x02, bytes(12)), (0x04, bytes(16)), (0x05, b"")]
    assert links.ModelChannel().exchange(packets).responses == gcm_model.simulate(packets)
