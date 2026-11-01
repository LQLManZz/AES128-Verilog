"""The menu only builds a command line, so it is tested through what it builds."""

import pytest

from host import menu
from host.cli import main

KEY = "00" * 16
IV = "00" * 12


def answers(*replies):
    queue = list(replies)
    return lambda prompt: queue.pop(0)


def test_raw_message_answers_become_arguments():
    arguments = menu.ask_arguments(answers("1", "2", "2", "", "00ff", "", KEY, IV, "aa"))
    assert arguments == ["raw", "--data", "00ff", "--link", "uart12m", "--sim", "model",
                         "--key", KEY, "--iv", IV, "--aad", "aa"]


def test_raw_decrypt_asks_for_the_tag():
    arguments = menu.ask_arguments(answers("1", "3", "1", "", "00ff", "ab" * 16, KEY, IV, ""))
    assert arguments == ["raw", "--data", "00ff", "--op", "decrypt", "--tag", "ab" * 16,
                         "--link", "spi40", "--key", KEY, "--iv", IV]


def test_image_keeps_the_defaults_on_enter():
    arguments = menu.ask_arguments(answers("2", "4", "3", "", "", KEY, IV, ""))
    assert arguments == ["image", "--link", "spi30", "--sim", "rtl", "--key", KEY, "--iv", IV]


def test_camera_offers_no_rtl_and_can_decrypt_on_the_fpga():
    arguments = menu.ask_arguments(answers("3", "3", "1", "1280x720", "70", "y", KEY, IV, ""))
    assert arguments == ["camera", "--size", "1280x720", "--quality", "70", "--fpga-decrypt",
                         "--link", "spi40", "--key", KEY, "--iv", IV]


def test_a_wrong_number_is_asked_again(capsys):
    assert menu.choose(answers("9", "x", "2"), "Tiêu đề", [("a", "A"), ("b", "B")]) == "b"
    assert "Nhập số" in capsys.readouterr().out


def test_key_cannot_be_left_empty():
    assert menu.required(answers("", " ", "ff"), "Key: ") == "ff"


def test_no_arguments_opens_the_menu(monkeypatch, tmp_path, capsys):
    replies = answers("1", "1", "2", "", "00" * 16, "", KEY, IV, "")
    monkeypatch.setattr("builtins.input", replies)
    monkeypatch.chdir(tmp_path)
    assert main([]) == 0
    assert "0388dace 60b6a392" in capsys.readouterr().out
