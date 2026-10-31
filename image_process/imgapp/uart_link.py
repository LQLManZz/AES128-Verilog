"""Plays a TX stream to the real FPGA through AesGcmUartClient from host.py."""

import sys
from typing import Callable, List, Optional

from uart_protocol import (
    CMD_ACKS, CMD_NAMES, CMD_START_DECRYPT, CMD_START_ENCRYPT, RESP_AUTH_TAG,
    RESP_CIPHERTEXT, RESP_NAMES,
)

from . import framing, gcm_model
from .packet_file import Packet

_RESULT_RESPONSES = (RESP_CIPHERTEXT, RESP_AUTH_TAG)
MAX_REPORTED_DIFFERENCES = 5


def load_client_class() -> type:
    # host.cpython-312.pyc is tracked in git, so this import must not rewrite it.
    # Imported here because host.py exits when pyserial is missing.
    previous = sys.dont_write_bytecode
    sys.dont_write_bytecode = True
    try:
        from host import AesGcmUartClient
    finally:
        sys.dont_write_bytecode = previous
    return AesGcmUartClient


def open_client(key: bytes, port: Optional[str], baud: int, timeout: float):
    variant = "aes128" if len(key) == 16 else "aes256"
    return load_client_class()(port=port, baudrate=baud, timeout=timeout, variant=variant)


def transfer(client, packets: List[Packet],
             on_chunk: Optional[Callable[[int], None]] = None) -> List[Packet]:
    """Sends one packet at a time and waits for its full answer.

    packet_builder.sv has no queue, so a command sent before the previous reply
    is finished can lose its response and hang the wrapper.
    """
    responses = []
    chunk = 0
    for cmd, payload in packets:
        is_start = cmd in (CMD_START_ENCRYPT, CMD_START_DECRYPT)
        expected = _RESULT_RESPONSES if is_start else (CMD_ACKS[cmd],)
        try:
            client.send_packet(cmd, payload)
            for want in expected:
                got, data = client.receive_packet()
                if got != want:
                    raise ValueError(f"expected {RESP_NAMES[want]}, received "
                                     f"{RESP_NAMES.get(got, 'UNKNOWN')} (0x{got:02X}) {data.hex()}")
                responses.append((got, data))
        except (ValueError, TimeoutError) as error:
            raise type(error)(f"Chunk {chunk}, {CMD_NAMES[cmd]}: {error}") from error
        if is_start:
            chunk += 1
            if on_chunk:
                on_chunk(chunk)
    return responses


def compare_with_model(packets: List[Packet], responses: List[Packet]) -> List[str]:
    """Lists every chunk where the board and the software model disagree."""
    expected = framing.split_rx(gcm_model.simulate(packets))
    actual = framing.split_rx(responses)
    differences = []
    for chunk, ((want_data, want_tag), (got_data, got_tag)) in enumerate(zip(expected, actual)):
        if got_data != want_data:
            differences.append(f"chunk {chunk}: data differs")
        if got_tag != want_tag:
            differences.append(f"chunk {chunk}: tag differs (board {got_tag.hex()}, model {want_tag.hex()})")
    return differences
