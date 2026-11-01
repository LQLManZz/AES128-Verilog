// Keeps the FIFOs of aes_gcm_engine from filling while the client streams without waiting.
//
// transfer() in host/links.py does this over Wi-Fi: 32 messages, then all their replies, then
// the next 32. Doing it here costs no Wi-Fi round trip per burst. No ESP-IDF in this file, so
// tests/test_pace.py can compile it on the PC.

#pragma once

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#define PACE_BURST_MESSAGES 32  // BURST_MESSAGES in host/protocol.py

typedef struct {
    uint8_t cmd;
    bool have_cmd;
    size_t payload_left;
    int messages;       // Started since nothing was in flight
    int awaited;        // Commands whose last reply has not come back
    bool decrypting;
} pace_t;

void pace_reset(pace_t *pace);

// How many of the `length` bytes may go to the FPGA now. It stops right after the command that
// fills a burst, and the rest must be offered again once pace_blocked() turns false.
size_t pace_outgoing(pace_t *pace, const uint8_t *data, size_t length);

// Call with the opcode of every packet that came back from the FPGA.
void pace_reply(pace_t *pace, uint8_t cmd);

bool pace_blocked(const pace_t *pace);
bool pace_awaiting(const pace_t *pace);
