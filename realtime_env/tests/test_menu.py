"""The menu builds the command lines you could type, so it is tested through what it builds."""

import pytest

from host import menu
from host.cli import main

KEY = "00" * 16
IV = "00" * 12
IV2 = "11" * 12


def answers(*replies):
    queue = list(replies)

    def ask(prompt):
        if not queue:
            raise EOFError
        return queue.pop(0)
    return ask


def one_round(*replies, advanced=False, port="COM12"):
    """Runs the menu on `replies` and returns the command lines it would have run."""
    ran = []
    menu.run_menu(answers(*replies), lambda arguments: ran.append(arguments) or 0, advanced, lambda: port)
    return ran


def test_header_names_the_link_and_the_kit_port(capsys):
    one_round("0")
    assert "AES-GCM | UART 12 Mbaud | COM12 (kênh D)" in capsys.readouterr().out


def test_header_says_when_the_kit_is_missing(capsys):
    one_round("0", port=None)
    assert "chưa thấy kit" in capsys.readouterr().out


def test_plain_menu_offers_three_modes_and_exit(capsys):
    one_round("0")
    assert " 1 Camera   2 Img   3 Raw text   0 Exit" in capsys.readouterr().out


def test_camera_keeps_the_defaults_on_enter():
    ran = one_round("1", "", "", "", "", "", KEY, IV, "", "")
    assert ran == [["camera", "--link", "uart12m", "-p", "COM12", "--key", KEY, "--iv", IV]]


def test_camera_options_and_the_sim():
    ran = one_round("1", "2", "1280x720", "50", "y", "15", KEY, IV, "aa" * 16, "")
    assert ran == [["camera", "--size", "1280x720", "--quality", "50", "--fpga-decrypt", "--fps", "15",
                    "--link", "uart12m", "--sim", "model", "--key", KEY, "--iv", IV, "--aad", "aa" * 16]]


def test_img_asks_path_and_size():
    ran = one_round("2", "2", "photo.png", "64x64", KEY, IV, "", "")
    assert ran == [["image", "photo.png", "--size", "64x64", "--link", "uart12m", "--sim", "model",
                    "--key", KEY, "--iv", IV]]


def test_raw_hex_with_a_tag_decrypts():
    ran = one_round("3", "2", "00 ff" * 8, "ab" * 16, KEY, IV, "", "")
    assert ran == [["raw", "--data", "00ff" * 8, "--op", "decrypt", "--tag", "ab" * 16, "--link", "uart12m",
                    "--sim", "model", "--key", KEY, "--iv", IV]]


def test_raw_that_is_not_hex_is_a_file():
    ran = one_round("3", "2", "notes.txt", KEY, IV, "", "")
    assert ran[0][:3] == ["raw", "--file", "notes.txt"]


def test_wrong_answers_are_asked_again(capsys):
    ran = one_round("9", "1", "3", "", "640x", "", "", "x", "", "", "", "ab", KEY, "00", IV, "zz", "", "")
    out = capsys.readouterr().out
    for complaint in ("Chọn một số", "Nhập số từ 1 đến 2", "WxH", "Nhập y hoặc n", "bắt buộc", "16 hoặc 32 byte",
                      "12 byte", "AAD phải là hex"):
        assert complaint in out
    assert ran == [["camera", "--link", "uart12m", "-p", "COM12", "--key", KEY, "--iv", IV]]


def test_the_port_is_asked_once_when_the_kit_is_missing():
    ran = one_round("3", "1", "00ff", "", "com7", KEY, IV, "", "", "3", "1", "00ff", "", KEY, IV2, "", "",
                    port=None)
    assert [arguments[arguments.index("-p") + 1] for arguments in ran] == ["COM7", "COM7"]


def test_the_sim_needs_no_port():
    assert "-p" not in one_round("3", "2", "00ff", "", KEY, IV, "", "", port=None)[0]


def test_the_menu_comes_back_after_each_run_and_refuses_a_reused_iv(capsys):
    ran = one_round("3", "2", "00ff", "", KEY, IV, "", "",
                    "3", "2", "00ff", "", KEY, "00" * 11 + "05", IV2, "", "", "0")
    assert len(ran) == 2 and ran[1][-1] == IV2
    assert "Đổi 8 byte đầu của IV" in capsys.readouterr().out


def test_advanced_unlocks_links_simulators_and_selftest(capsys):
    ran = one_round("3", "1", "3", "", "", "", "", "2", "clip.avi", "3", "y", KEY, IV, "", "",
                    "4", "2", "1", "", advanced=True)
    assert "4 Self-test NIST" in capsys.readouterr().out
    assert ran[0] == ["camera", "--codec", "jpeg", "--source", "clip.avi", "--realtime", "--loop",
                      "--tamper-every", "3", "--link", "spi40", "--sim", "emu", "--paced", "--key", KEY, "--iv", IV]
    assert ran[1] == ["selftest", "--aes", "128", "--link", "spi40", "--sim", "model"]


def test_advanced_offers_rtl_except_for_the_camera(capsys):
    ran = one_round("1", "2", "4", "", "", KEY, IV, "", "", advanced=True)
    assert ran[0][-6:-4] == ["--sim", "rtl"]


def test_no_arguments_opens_the_menu_and_runs_the_command(monkeypatch, tmp_path, capsys):
    replies = answers("3", "2", "00" * 16, "", KEY, IV, "", "", "0")
    monkeypatch.setattr("builtins.input", replies)
    monkeypatch.setattr(menu, "find_kit_port", lambda: None)
    monkeypatch.setattr(menu.run_menu, "__defaults__", (False, lambda: None))
    monkeypatch.chdir(tmp_path)
    assert main([]) == 0
    assert "0388dace 60b6a392" in capsys.readouterr().out


@pytest.mark.parametrize("arguments, locked", [
    (["camera", "--link", "spi40", "--key", KEY, "--iv", IV], "--link spi40"),
    (["camera", "--sim", "emu", "--key", KEY, "--iv", IV], "--sim emu"),
    (["camera", "--codec", "jpeg", "--key", KEY, "--iv", IV], "--codec"),
    (["camera", "--no-window", "--key", KEY, "--iv", IV], "--no-window"),
    (["raw", "--data", "00", "--output-dir", "x", "--key", KEY, "--iv", IV], "--output-dir"),
    (["selftest"], "Lệnh selftest"),
    (["sample"], "Lệnh sample"),
])
def test_the_command_line_is_locked_too(arguments, locked, capsys):
    assert main(arguments) == 2
    assert f"{locked} cần --advanced" in capsys.readouterr().out


def test_the_plain_command_line_runs_without_advanced(capsys, tmp_path, monkeypatch):
    monkeypatch.chdir(tmp_path)
    assert main(["raw", "--sim", "model", "--data", "00" * 16, "--key", KEY, "--iv", IV]) == 0
    assert "0388dace 60b6a392" in capsys.readouterr().out


def test_advanced_may_stand_after_the_command(capsys):
    assert main(["selftest", "--sim", "model", "--advanced"]) == 0
    assert "4/4 PASS" in capsys.readouterr().out
