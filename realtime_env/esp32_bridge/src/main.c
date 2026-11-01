// Wi-Fi to SPI bridge between host/esp_link.py and aes*_spi_wrapper on the FPGA.
//
// One TCP client on port 5001, one text command per line:
//   PING          -> PONG
//   INFO          -> OK mode=ap ch=.. bw=.. stations=.. rssi=.. heap=.. sclk=..
//   SINK <bytes>  -> reads <bytes>, replies "OK <ms>"
//   SRC <bytes>   -> sends <bytes>, then "OK <ms>"
//   ECHO          -> "OK", then every byte received goes straight back
//   BRIDGE        -> "OK", then packets flow to the FPGA until the client leaves
//
// In BRIDGE the board is a byte pipe: the client writes the same [CMD][LEN][payload] packets
// as over UART. Frames, the STATUS byte and idle zeros stay on this side of the link, as in
// host/spi_frames.py. A bad STATUS reaches the client as packet 0xEF.

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "driver/spi_master.h"
#include "esp_event.h"
#include "esp_heap_caps.h"
#include "esp_log.h"
#include "esp_mac.h"
#include "esp_netif.h"
#include "esp_timer.h"
#include "esp_wifi.h"
#include "freertos/FreeRTOS.h"
#include "freertos/semphr.h"
#include "freertos/stream_buffer.h"
#include "freertos/task.h"
#include "lwip/sockets.h"
#include "nvs_flash.h"

#include "secrets.h"

#define TAG "bridge"

#define AP_CHANNEL 1
#define AP_MAX_CLIENTS 2
#define TCP_PORT 5001
#define LINE_BYTES 64
#define BLOCK_BYTES 16384

#define PIN_CS 10
#define PIN_MOSI 11
#define PIN_SCLK 12
#define PIN_MISO 13
#define SCLK_HZ 40000000
#define FRAME_BYTES 8700    // One burst of 32 messages, plus the frame opcode
#define READ_BYTES 512      // Clocked while waiting for replies

#define OP_DATA 0xA5
#define OP_READ 0x5A
#define OP_CLEAR 0xC3
#define STATUS_OK 0xA0
#define RESP_BRIDGE_ERR 0xEF
#define IDLE_READS 64       // Empty READ frames before the SPI task rests
#define RING_BYTES (32 * 1024)

static spi_device_handle_t spi;
static StreamBufferHandle_t to_fpga;
static StreamBufferHandle_t to_client;
static SemaphoreHandle_t spi_idle;
static volatile bool bridging;
static uint8_t *block;

// Rebuilds packets from MISO, like spi_frames.MisoDecoder: a zero where an opcode is due is idle.
static struct {
    uint8_t packet[2 + 255];
    size_t have;
    size_t need;
} miso;

static void send_to_client(const uint8_t *data, size_t length) {
    while (length && bridging) {
        size_t sent = xStreamBufferSend(to_client, data, length, pdMS_TO_TICKS(100));
        data += sent;
        length -= sent;
    }
}

// Returns true if the bytes held any part of a packet.
static bool decode_miso(const uint8_t *data, size_t length) {
    bool active = false;
    for (size_t i = 0; i < length; i++) {
        if (miso.have == 0 && data[i] == 0) continue;
        active = true;
        miso.packet[miso.have++] = data[i];
        if (miso.have == 2) miso.need = 2 + miso.packet[1];
        if (miso.have >= 2 && miso.have == miso.need) {
            send_to_client(miso.packet, miso.have);
            miso.have = 0;
        }
    }
    return active;
}

static void spi_frame(const uint8_t *tx, uint8_t *rx, size_t length) {
    spi_transaction_t transaction = {.length = length * 8, .rxlength = length * 8, .tx_buffer = tx, .rx_buffer = rx};
    ESP_ERROR_CHECK(spi_device_polling_transmit(spi, &transaction));
}

static void report_status(uint8_t status) {
    const uint8_t packet[] = {RESP_BRIDGE_ERR, 1, status};
    send_to_client(packet, sizeof packet);
}

// Runs one frame at a time on its own core, so Wi-Fi never stalls the SPI clock.
static void spi_task(void *unused) {
    uint8_t *tx = heap_caps_malloc(FRAME_BYTES, MALLOC_CAP_DMA);
    uint8_t *rx = heap_caps_malloc(FRAME_BYTES, MALLOC_CAP_DMA);
    configASSERT(tx && rx);

    for (;;) {
        xSemaphoreGive(spi_idle);
        while (!bridging) vTaskDelay(pdMS_TO_TICKS(5));
        xSemaphoreTake(spi_idle, 0);

        tx[0] = OP_CLEAR;
        spi_frame(tx, rx, 1);
        miso.have = 0;

        int idle = IDLE_READS;
        while (bridging) {
            size_t length = xStreamBufferReceive(to_fpga, tx + 1, FRAME_BYTES - 1, idle < IDLE_READS ? 0 : pdMS_TO_TICKS(1));
            if (length) {
                tx[0] = OP_DATA;
                idle = 0;
            } else if (idle < IDLE_READS) {
                tx[0] = OP_READ;
                memset(tx + 1, 0, READ_BYTES);
                length = READ_BYTES;
            } else {
                continue;
            }

            spi_frame(tx, rx, length + 1);
            if (rx[0] != STATUS_OK) report_status(rx[0]);
            idle = decode_miso(rx + 1, length) ? 0 : idle + 1;
        }
    }
}

// Sends what the SPI task decoded. The socket stays open only while bridging.
static void client_task(void *argument) {
    int sock = (int)argument;
    while (bridging) {
        size_t length = xStreamBufferReceive(to_client, block, BLOCK_BYTES, pdMS_TO_TICKS(50));
        if (length && send(sock, block, length, 0) < 0) break;
    }
    bridging = false;
    vTaskDelete(NULL);
}

static void run_bridge(int sock) {
    xStreamBufferReset(to_fpga);
    xStreamBufferReset(to_client);
    bridging = true;
    xTaskCreatePinnedToCore(client_task, "client", 4096, (void *)sock, 5, NULL, 0);

    uint8_t *incoming = malloc(BLOCK_BYTES);
    configASSERT(incoming);
    for (;;) {
        int got = recv(sock, incoming, BLOCK_BYTES, 0);
        if (got <= 0 || !bridging) break;
        const uint8_t *data = incoming;
        while (got > 0 && bridging) {
            size_t taken = xStreamBufferSend(to_fpga, data, got, pdMS_TO_TICKS(100));
            data += taken;
            got -= taken;
        }
    }
    free(incoming);
    bridging = false;
    xSemaphoreTake(spi_idle, pdMS_TO_TICKS(1000));  // The next client must not share a frame
}

static bool read_line(int sock, char *line) {
    for (size_t used = 0; used < LINE_BYTES - 1; used++) {
        if (recv(sock, line + used, 1, 0) <= 0) return false;
        if (line[used] == '\n') {
            line[used] = 0;
            return true;
        }
    }
    return false;
}

static void reply(int sock, const char *text) {
    send(sock, text, strlen(text), 0);
}

static void reply_ok_ms(int sock, int64_t started) {
    char line[LINE_BYTES];
    snprintf(line, sizeof line, "OK %lld\n", (esp_timer_get_time() - started) / 1000);
    reply(sock, line);
}

static void do_info(int sock) {
    uint8_t channel = 0;
    wifi_second_chan_t second = WIFI_SECOND_CHAN_NONE;
    wifi_bandwidth_t width = WIFI_BW_HT20;
    wifi_sta_list_t stations = {0};
    int actual_khz = 0;
    esp_wifi_get_channel(&channel, &second);
    esp_wifi_get_bandwidth(WIFI_IF_AP, &width);
    esp_wifi_ap_get_sta_list(&stations);
    spi_device_get_actual_freq(spi, &actual_khz);

    char line[128];
    snprintf(line, sizeof line, "OK mode=ap ch=%u bw=%d stations=%d rssi=%d heap=%u sclk=%d\n", channel,
             width == WIFI_BW_HT40 ? 40 : 20, stations.num, stations.num ? stations.sta[0].rssi : 0,
             (unsigned)esp_get_free_heap_size(), actual_khz * 1000);
    reply(sock, line);
}

static void do_sink(int sock, unsigned left) {
    int64_t started = esp_timer_get_time();
    while (left) {
        int got = recv(sock, block, left < BLOCK_BYTES ? left : BLOCK_BYTES, 0);
        if (got <= 0) return;
        left -= got;
    }
    reply_ok_ms(sock, started);
}

static void do_src(int sock, unsigned left) {
    int64_t started = esp_timer_get_time();
    while (left) {
        int sent = send(sock, block, left < BLOCK_BYTES ? left : BLOCK_BYTES, 0);
        if (sent <= 0) return;
        left -= sent;
    }
    reply_ok_ms(sock, started);
}

static void do_echo(int sock) {
    reply(sock, "OK\n");
    for (;;) {
        int got = recv(sock, block, BLOCK_BYTES, 0);
        if (got <= 0) return;
        for (int offset = 0; offset < got;) {
            int sent = send(sock, block + offset, got - offset, 0);
            if (sent <= 0) return;
            offset += sent;
        }
    }
}

static void serve(int sock) {
    int on = 1;
    setsockopt(sock, IPPROTO_TCP, TCP_NODELAY, &on, sizeof on);

    char line[LINE_BYTES];
    unsigned count;
    while (read_line(sock, line)) {
        if (!strcmp(line, "PING")) {
            reply(sock, "PONG\n");
        } else if (!strcmp(line, "INFO")) {
            do_info(sock);
        } else if (sscanf(line, "SINK %u", &count) == 1) {
            do_sink(sock, count);
        } else if (sscanf(line, "SRC %u", &count) == 1) {
            do_src(sock, count);
        } else if (!strcmp(line, "ECHO")) {
            do_echo(sock);
            return;
        } else if (!strcmp(line, "BRIDGE")) {
            reply(sock, "OK\n");
            run_bridge(sock);
            return;
        } else {
            reply(sock, "ERR unknown command\n");
        }
    }
}

static void server_task(void *unused) {
    struct sockaddr_in address = {.sin_family = AF_INET, .sin_port = htons(TCP_PORT), .sin_addr.s_addr = htonl(INADDR_ANY)};
    int listener = socket(AF_INET, SOCK_STREAM, IPPROTO_TCP);
    int on = 1;
    setsockopt(listener, SOL_SOCKET, SO_REUSEADDR, &on, sizeof on);
    ESP_ERROR_CHECK(bind(listener, (struct sockaddr *)&address, sizeof address));
    ESP_ERROR_CHECK(listen(listener, 1));

    for (;;) {
        int sock = accept(listener, NULL, NULL);
        if (sock < 0) continue;
        ESP_LOGI(TAG, "client connected");
        serve(sock);
        close(sock);
        ESP_LOGI(TAG, "client left");
    }
}

static void start_wifi(void) {
    ESP_ERROR_CHECK(nvs_flash_init());
    ESP_ERROR_CHECK(esp_netif_init());
    ESP_ERROR_CHECK(esp_event_loop_create_default());
    esp_netif_create_default_wifi_ap();

    wifi_init_config_t init = WIFI_INIT_CONFIG_DEFAULT();
    ESP_ERROR_CHECK(esp_wifi_init(&init));
    wifi_config_t config = {.ap = {.ssid = AP_SSID, .password = AP_PASS, .ssid_len = strlen(AP_SSID),
                                   .channel = AP_CHANNEL, .authmode = WIFI_AUTH_WPA2_PSK,
                                   .max_connection = AP_MAX_CLIENTS}};
    ESP_ERROR_CHECK(esp_wifi_set_mode(WIFI_MODE_AP));
    ESP_ERROR_CHECK(esp_wifi_set_config(WIFI_IF_AP, &config));
    ESP_ERROR_CHECK(esp_wifi_set_bandwidth(WIFI_IF_AP, WIFI_BW_HT40));
    ESP_ERROR_CHECK(esp_wifi_start());
    ESP_ERROR_CHECK(esp_wifi_set_ps(WIFI_PS_NONE));
}

static void start_spi(void) {
    spi_bus_config_t bus = {.mosi_io_num = PIN_MOSI, .miso_io_num = PIN_MISO, .sclk_io_num = PIN_SCLK,
                            .quadwp_io_num = -1, .quadhd_io_num = -1, .max_transfer_sz = FRAME_BYTES};
    ESP_ERROR_CHECK(spi_bus_initialize(SPI2_HOST, &bus, SPI_DMA_CH_AUTO));

    // The FPGA launches MISO on the edge the master samples, so the delay stays 0: see INSTRUCTIONS.md.
    spi_device_interface_config_t device = {.mode = 0, .clock_speed_hz = SCLK_HZ, .spics_io_num = PIN_CS,
                                            .queue_size = 1, .input_delay_ns = 0};
    ESP_ERROR_CHECK(spi_bus_add_device(SPI2_HOST, &device, &spi));

    int actual_khz = 0;
    spi_device_get_actual_freq(spi, &actual_khz);
    ESP_LOGI(TAG, "SCLK %d kHz, full-duplex limit %d Hz", actual_khz, spi_get_freq_limit(false, 0));
}

void app_main(void) {
    block = malloc(BLOCK_BYTES);
    to_fpga = xStreamBufferCreate(RING_BYTES, 1);
    to_client = xStreamBufferCreate(RING_BYTES, 1);
    spi_idle = xSemaphoreCreateBinary();
    configASSERT(block && to_fpga && to_client && spi_idle);
    memset(block, 0xA5, BLOCK_BYTES);

    start_spi();
    start_wifi();
    xTaskCreatePinnedToCore(spi_task, "spi", 4096, NULL, 10, NULL, 1);
    xTaskCreatePinnedToCore(server_task, "server", 6144, NULL, 5, NULL, 0);
    ESP_LOGI(TAG, "AP \"%s\", 192.168.4.1:%d", AP_SSID, TCP_PORT);
}
