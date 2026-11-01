"""The step-by-step console report and the backends behind `simulate`, `decrypt` and `run`."""

import pytest
from PIL import Image

from imgapp import console, framing, gcm_model, image_io, packet_file, rtl_sim, spi_frames, spi_link
from imgapp.__main__ import main

KEY = "00112233445566778899aabbccddeeff" * 2


@pytest.fixture
def input_dir(tmp_path):
    folder = tmp_path / "input"
    folder.mkdir()
    image_io.make_sample(folder / "sample.png", (64, 48))
    return folder


def run(input_dir, tmp_path, *options):
    return main(["run", "--input-dir", str(input_dir), "--output-dir", str(tmp_path / "output"),
                 "--size", "32x24", "--key", KEY, *options])


def test_sample_image_uses_all_three_channels(tmp_path):
    path = tmp_path / "sample.png"
    assert main(["sample", "-o", str(path), "--size", "64x64"]) == 0
    with Image.open(path) as img:
        assert img.mode == "RGB" and img.size == (64, 64)
        assert len(img.getcolors(maxcolors=65536)) > 100


def test_every_step_is_shown_with_its_values(input_dir, tmp_path, capsys):
    assert run(input_dir, tmp_path) == 0
    text = capsys.readouterr().out
    for step in ("ENCODE", "SIMULATE", "DECODE", "DECRYPT"):
        assert f"═══ {step}" in text
    assert "00112233 44556677" in text          # KEY
    assert "41474931" in text                   # AAD starts with "AGI1"
    assert "w=32 h=24 ch=3" in text             # AAD decoded
    assert "TAG-REF" in text and "PASS" in text
    assert "software model" in text


def test_tags_are_printed_in_full(input_dir, tmp_path, capsys):
    assert run(input_dir, tmp_path) == 0
    text = capsys.readouterr().out
    rx = packet_file.read_stream(tmp_path / "output" / "sample.png" / "rx.bin")
    tag = next(payload for cmd, payload in rx if cmd == 0x91)
    assert tag.hex() in text
    assert text.count(tag.hex()) >= 3           # SIMULATE, and both DECRYPT columns


def test_run_saves_the_console_as_a_picture(input_dir, tmp_path):
    assert run(input_dir, tmp_path) == 0
    path = tmp_path / "output" / "sample.png" / "console_model.png"
    with Image.open(path) as picture:
        assert picture.width > 600 and picture.height > 400


def test_show_chunks_limits_the_table(input_dir, tmp_path, capsys):
    assert run(input_dir, tmp_path, "--show-chunks", "1") == 0
    assert "…" in capsys.readouterr().out


def test_tampered_chunk_fails_inside_the_ip(input_dir, tmp_path, capsys):
    assert run(input_dir, tmp_path, "--tamper-chunk", "1") == 1
    text = capsys.readouterr().out
    assert "FAIL" in text and "chunk(s): 1" in text
    folder = tmp_path / "output" / "sample.png"
    assert not (folder / "decrypted.png").exists()
    assert (folder / "console_model_tamper.png").exists()


def fake_rtl(packets, name, config):
    assert config.link == "spi" and config.sclk_mhz == 15
    return rtl_sim.SimResult(gcm_model.simulate(packets), 1e-3, 3, [0xA0])


def test_rtl_backend_is_labelled_and_compared_with_the_model(input_dir, tmp_path, capsys, monkeypatch):
    monkeypatch.setattr(rtl_sim, "run_stream", fake_rtl)
    assert run(input_dir, tmp_path, "--backend", "rtl-spi", "--sclk-mhz", "15") == 0
    text = capsys.readouterr().out
    assert "RTL QuestaSim" in text and "SCLK 15 MHz" in text
    assert "1.00 ms" in text and "STATUS 0xA0" in text


def test_rtl_answer_that_differs_from_the_model_fails(input_dir, tmp_path, capsys, monkeypatch):
    def wrong(packets, name, config):
        responses = gcm_model.simulate(packets)
        return rtl_sim.SimResult([(cmd, bytes(16) if cmd == 0x91 else data) for cmd, data in responses],
                                 1e-3, 3, [0xA0])

    monkeypatch.setattr(rtl_sim, "run_stream", wrong)
    assert run(input_dir, tmp_path, "--backend", "rtl-spi") == 1
    assert "differs from the software model" in capsys.readouterr().out


def test_spi_send_saves_the_board_answer(input_dir, tmp_path, capsys, monkeypatch):
    class Link:
        def __init__(self, url, frequency):
            assert frequency == 15_000_000

        def close(self):
            pass

    def transfer(link, packets, on_chunk=None, window=32):
        return gcm_model.simulate(packets)

    monkeypatch.setattr(spi_link, "Ft232hLink", Link)
    monkeypatch.setattr(spi_link, "transfer_spi", transfer)
    out = tmp_path / "output"
    assert main(["encode", str(input_dir / "sample.png"), "--output-dir", str(out), "--size", "16x16"]) == 0
    tx = out / "sample.png" / "tx.bin"
    assert main(["spi-send", str(tx), "--sclk-mhz", "15"]) == 0
    assert tx.with_name("rx.bin").exists()
    assert "matches the software model" in capsys.readouterr().out


def test_picks_keep_failed_chunks_in_view():
    assert console.pick_chunks(10, 1, {5}) == [0, None, 5, None, 9]
    assert console.pick_chunks(3, 3, set()) == [0, 1, 2]


def session(messages):
    pixels = bytes(240 * messages)
    return framing.build_tx(pixels, 240, messages, bytes(32), channels=1)


def test_spi_session_clears_first_and_reads_past_every_reply():
    packets = session(5)
    frames = rtl_sim.plan_frames(packets, rtl_sim.SimConfig("spi", window=2))
    assert frames[0] == (spi_frames.CLEAR_FRAME, 0)
    assert [frame[0] for frame, _ in frames[1:]] == [spi_frames.OP_DATA, spi_frames.OP_READ] * 3
    clocked = sum(len(frame) - 1 for frame, _ in frames)
    assert clocked >= spi_frames.reply_bytes(gcm_model.simulate(packets))


def test_uart_session_waits_for_each_bursts_replies():
    packets = session(5)
    frames = rtl_sim.plan_frames(packets, rtl_sim.SimConfig("uart", window=2))
    assert len(frames) == 3
    assert sum(reply for _, reply in frames) == spi_frames.reply_bytes(gcm_model.simulate(packets))
    assert b"".join(frame for frame, _ in frames)[0] == 0x01  # LOAD_KEY, with no frame opcode
