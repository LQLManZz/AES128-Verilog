#include "pace.h"

#define CMD_START_ENCRYPT 0x05
#define CMD_START_DECRYPT 0x07
#define RESP_CIPHERTEXT 0x90
#define RESP_AUTH_TAG 0x91

void pace_reset(pace_t *pace) {
    *pace = (pace_t){0};
}

bool pace_blocked(const pace_t *pace) {
    return pace->messages >= PACE_BURST_MESSAGES;
}

bool pace_awaiting(const pace_t *pace) {
    return pace->awaited > 0;
}

size_t pace_outgoing(pace_t *pace, const uint8_t *data, size_t length) {
    size_t taken = 0;
    while (taken < length && !pace_blocked(pace)) {
        if (pace->payload_left) {
            size_t left = length - taken;
            size_t step = left < pace->payload_left ? left : pace->payload_left;
            taken += step;
            pace->payload_left -= step;
        } else if (!pace->have_cmd) {
            pace->cmd = data[taken++];
            pace->have_cmd = true;
        } else {
            pace->payload_left = data[taken++];
            pace->have_cmd = false;
            pace->awaited++;
            if (pace->cmd == CMD_START_ENCRYPT || pace->cmd == CMD_START_DECRYPT) pace->messages++;
            if (pace->cmd == CMD_START_DECRYPT) pace->decrypting = true;
        }
    }
    return taken;
}

// A command ends with its ACK, an error, or the last packet of its answer: the tag when
// encrypting, the verify result when decrypting. See read_reply() in host/links.py.
void pace_reply(pace_t *pace, uint8_t cmd) {
    if (cmd == RESP_CIPHERTEXT || (cmd == RESP_AUTH_TAG && pace->decrypting) || !pace->awaited) return;
    if (--pace->awaited == 0) {
        pace->messages = 0;
        pace->decrypting = false;
    }
}
