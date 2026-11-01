"""Plays a TX stream to the real FPGA through AesGcmUartClient from host.py."""

import sys
from typing import Callable, List, Optional

from uart_protocol import (
    BURST_MESSAGES, CMD_ACKS, CMD_NAMES, CMD_START_DECRYPT, CMD_START_ENCRYPT, RESP_AUTH_TAG,
    RESP_CIPHERTEXT, RESP_NAMES, RESP_VERIFY_RESULT, build_packet,
)

from . import framing, gcm_model
from .packet_file import Packet

_ENCRYPT_RESPONSES = (RESP_CIPHERTEXT, RESP_AUTH_TAG)
_DECRYPT_RESPONSES = (RESP_CIPHERTEXT, RESP_AUTH_TAG, RESP_VERIFY_RESULT)
_REJECTED_RESPONSES = (RESP_AUTH_TAG, RESP_VERIFY_RESULT)  # The IP withheld the plaintext
_RX_BUFFER_BYTES = 1 << 16  # Must hold a whole window of replies while the host is still writing
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
    client = load_client_class()(port=port, baudrate=baud, timeout=timeout, variant=variant)
    if hasattr(client.ser, "set_buffer_size"):  # Windows only
        client.ser.set_buffer_size(rx_size=_RX_BUFFER_BYTES)
    return client


def read_reply(receive: Callable[[], Packet], cmd: int) -> List[Packet]:
    """Reads the complete answer to one command through `receive`."""
    if cmd in CMD_ACKS:
        expected = (CMD_ACKS[cmd],)
    else:
        expected = _DECRYPT_RESPONSES if cmd == CMD_START_DECRYPT else _ENCRYPT_RESPONSES

    responses = []
    while len(responses) < len(expected):
        got, data = receive()
        if cmd == CMD_START_DECRYPT and not responses and got == RESP_AUTH_TAG:
            expected = _REJECTED_RESPONSES
        want = expected[len(responses)]
        if got != want:
            raise ValueError(f"expected {RESP_NAMES[want]}, received "
                             f"{RESP_NAMES.get(got, 'UNKNOWN')} (0x{got:02X}) {data.hex()}")
        responses.append((got, data))
    return responses


def read_replies(receive: Callable[[], Packet], group: List[Packet], first_chunk: int = 0,
                 on_chunk: Optional[Callable[[int], None]] = None) -> List[Packet]:
    """Reads the answers to a group of commands, naming the chunk and command that failed."""
    responses = []
    chunk = first_chunk
    for cmd, _ in group:
        try:
            responses += read_reply(receive, cmd)
        except (ValueError, TimeoutError) as error:
            raise type(error)(f"Chunk {chunk}, {CMD_NAMES[cmd]}: {error}") from error
        if cmd in (CMD_START_ENCRYPT, CMD_START_DECRYPT):
            chunk += 1
            if on_chunk:
                on_chunk(chunk)
    return responses


def transfer(client, packets: List[Packet], on_chunk: Optional[Callable[[int], None]] = None,
             window: int = BURST_MESSAGES) -> List[Packet]:
    """Sends up to `window` messages at once, then reads all their answers.

    The RX FIFO of aes_gcm_engine holds what arrives while a message is running, so the
    host has no need to wait for each ACK. A window of 1 is stop-and-wait, for debugging.
    """
    responses = []
    chunk = 0
    for group in framing.batches(packets, window):
        client.send_stream(b"".join(build_packet(cmd, payload) for cmd, payload in group))
        replies = read_replies(client.receive_packet, group, chunk, on_chunk)
        chunk += sum(cmd in (CMD_START_ENCRYPT, CMD_START_DECRYPT) for cmd, _ in group)
        responses += replies
    return responses


def compare_with_model(packets: List[Packet], responses: List[Packet]) -> List[str]:
    """Lists every chunk where the board and the software model disagree."""
    expected = framing.split_rx(gcm_model.simulate(packets))
    actual = framing.split_rx(responses)
    if len(expected) != len(actual):
        return [f"board answered {len(actual)} chunks, model {len(expected)}"]

    def verdict(reply: framing.Reply) -> str:
        return "PASS" if reply.verified else "FAIL"

    differences = []
    for chunk, (want, got) in enumerate(zip(expected, actual)):
        if got.data != want.data:
            differences.append(f"chunk {chunk}: data differs")
        if got.tag != want.tag:
            differences.append(f"chunk {chunk}: tag differs (board {got.tag.hex()}, model {want.tag.hex()})")
        if got.verified != want.verified:
            differences.append(f"chunk {chunk}: verify differs (board {verdict(got)}, model {verdict(want)})")
    return differences
