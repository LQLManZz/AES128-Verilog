# Hướng dẫn realtime_env

Tài liệu này dành cho build bitstream, nối dây và đưa lên PolarFire SoC Discovery Kit. Cách dùng script nằm trong [README.md](README.md), định dạng lệnh nằm trong [docs/protocol.md](docs/protocol.md).

**Trạng thái:** code đã qua mô phỏng RTL trong QuestaSim, sáu Design Root đã qua Verify Timing. **Chưa tạo bitstream, chưa nạp board, chưa chạy thử toàn chuỗi ESP32 tới FPGA.** Xem mục 9 và 10.

```
spi40:    PC ─ Wi-Fi ─► ESP32-S3 ─► spi_link (miền SCLK) ─┐
          (host/esp_link.py)  (J5) ◄─ TX FIFO ◄───────────┤
spi30:    PC ─ USB ─► FT232H ─────► spi_link ─────────────┤
                                                          ├─ aes_gcm_engine: RX FIFO ─► parser ─► FSM + lõi GCM ─► builder
uart2m:   USB-UART ─► uart_rx, uart_tx ───────────────────┤
          (J6, E14/E15)                                   │
uart12m:  FT4232HL kênh D ─► uart_rx, uart_tx (120 MHz) ─► uart_cdc_link ─┘
          (J4, W21/Y21)
```

## 1. Mô phỏng trước khi đụng phần cứng

Cần `pip install -r realtime_env/requirements.txt` và QuestaSim đi kèm Libero. Nếu Libero không nằm ở `C:\Microchip\Libero_SoC_2026.1`, đặt biến môi trường `QUESTA_BIN` trỏ tới thư mục `QuestaSim_Pro\win64`.

```bash
python realtime_env/main.py sample -o realtime_env/input/color_test.png --size 64x64
```

```bash
python realtime_env/main.py image realtime_env/input/color_test.png --link spi40 --sim rtl --size 64x64 --key 603deb1015ca71be2b73aef0857d77811f352c073b6108d72d9810a30914dff4 --iv cafebabefacedbad00000001 --aad feedfacedeadbeeffeedfacedeadbeef
```

Đổi `--link` thành `spi30`, `uart12m`, `uart2m` để mô phỏng đúng tốc độ của từng link. Thêm `--tamper-chunk 7` để xem IP từ chối chunk bị sửa. Mô phỏng 256×256 mất vài phút.

| Bước | In ra |
|---|---|
| ENCODE | Kích thước, SHA-256, KEY, IV, AAD |
| SIMULATE hoặc SEND | Nguồn trả lời, STATUS, thời gian, overhead, IV, AAD và TAG từng chunk |
| DECODE | `cipher.png` cạnh `preview.png` |
| DECRYPT | TAG-REF, TAG tính được và VERIFY từng chunk, rồi ảnh giải mã |

`--show-chunks N` đổi số chunk đầu và cuối được in. Chunk `FAIL` luôn được in.

Testbench tự kiểm tra, chạy từ gốc repo:

```bash
"C:\Microchip\Libero_SoC_2026.1\Libero_SoC\QuestaSim_Pro\win64\vsim.exe" -c -do "set KEY_BITS 256; set TB tb_aes256_uart_wrapper; do realtime_env/rtl/common/run_tb.do"
```

```bash
"C:\Microchip\Libero_SoC_2026.1\Libero_SoC\QuestaSim_Pro\win64\vsim.exe" -c -do "set KEY_BITS 128; set TB tb_aes128_uart_wrapper; do realtime_env/rtl/common/run_tb.do"
```

```bash
"C:\Microchip\Libero_SoC_2026.1\Libero_SoC\QuestaSim_Pro\win64\vsim.exe" -c -do "set KEY_BITS 256; set TB tb_uart_phy; do realtime_env/rtl/common/run_tb.do"
```

## 2. Chọn bitstream

Mỗi link cần bitstream riêng. Constraint nằm trong `realtime_env/rtl/common/`.

| `--link` | Design Root AES-256 | Design Root AES-128 | Constraint |
|---|---|---|---|
| `spi40`, `spi30` | `aes256_spi_wrapper` | `aes128_spi_wrapper` | `aes_spi.pdc`, `aes_spi.sdc` |
| `uart12m` | `aes256_uart_12m_top` | `aes128_uart_12m_top` | `aes_uart_12m.pdc`, `aes_uart_12m.sdc` |
| `uart2m` | `aes256_uart_wrapper` | `aes128_uart_wrapper` | `aes_uart.pdc`, `aes_uart.sdc` |

Host phải khớp bitstream: key 32 byte cho AES-256, 16 byte cho AES-128. Key sai độ dài bị trả `ERR_LEN_MISMATCH`.

## 3. Build trong Libero

Project `AES-GCM-Libero/` đã chứa lõi 128 và 256 cùng sáu root trên. Project bị gitignore nên không có trong commit. Hai file `SubWord.sv` giống hệt nhau nên project chỉ link `RTL/Key_Expansion_256/SubWord.sv`, vì một tên module chỉ link được một lần. Libero lưu kết quả theo root, trong `designer/<root>/` và `synthesis/<root>.vm`.

Để có bitstream:

1. Đặt Design Root theo bảng ở mục 2.
2. Chạy Generate FPGA Array Data, Generate Bitstream.
3. Nạp bằng FlashPro5 trên kit theo Appendix A của User Guide.

**Dựng lại từ đầu**, trong Project > Execute Script, từng dòng một:

```tcl
set REPO C:/path/to/AES_Verilog
```

```tcl
source $REPO/realtime_env/rtl/common/pf_ccc_120m.tcl
```

```tcl
source $REPO/realtime_env/rtl/common/build_12m.tcl
```

```tcl
source $REPO/realtime_env/rtl/common/build_spi.tcl
```

```tcl
source $REPO/realtime_env/rtl/common/build_2m.tcl
```

Mỗi script tự thêm file, gán constraint và chạy hai key size tới Verify Timing, khoảng 15 phút. Kết quả thay đổi nhẹ theo từng lần place and route, nên sau mỗi lần build cần kiểm tra:

- Không có slack âm ở mọi clock.
- `clk` và `spi_sclk` nằm trên global trong `<root>_glb_net_report.xml`.
- `byte_fifo` ra LSRAM: 2 khối ở dòng SPI.

`uart12m` giữ IP ở 50 MHz, chỉ UART chạy 120 MHz từ PF_CCC. Tốc độ chậm hơn chỉ cần đổi `BAUD_RATE` của root, vì 120 MHz chia chẵn cho 12, 8, 6, 4, 3, 2 và 1 Mbaud. FT4232HL không hỗ trợ 7, 9, 10, 11 Mbaud.

Ở root 50 MHz, baud nên chia chẵn 50 MHz:

| Baud | Chia | Sai số | Ghi chú |
|---|---|---|---|
| 1 000 000 | 50 | 0 | Hầu hết adapter |
| 2 000 000 | 25 | 0 | `uart2m` |
| 3 000 000 | 16,67 | 4,2% | Tránh |
| 5 000 000 | 10 | 0 | Cần adapter hi-speed; bộ chia phía adapter có thể lệch khoảng 1% |
| 12 000 000 | 4,17 | 4,2% | Vượt ngưỡng ±3% của FTDI, phải dùng `uart12m` |

## 4. Nối dây

**Đối chiếu schematic của kit trước khi cắm dây.** Bảng chân trong User Guide bị lệch cột khi đọc, và tên tín hiệu J5 suy ra từ thứ tự chuẩn mikroBUS. J45 phải đóng 1-2 để Bank 1 chạy 3,3 V.

**SPI**, ESP32-S3 N16R8 cho `spi40` hoặc FT232H cho `spi30`. FT4232HL trên kit không dùng được vì kênh D nối fabric không có MPSSE:

| Tín hiệu | J5 | Chân FPGA | ESP32-S3 | FT232H |
|---|---|---|---|---|
| CS | 3 | C16 | GPIO10 | D3 |
| SCK | 4 | E17 | GPIO12 | D0 |
| MISO | 5 | A18 | GPIO13 | D2 |
| MOSI | 6 | E11 | GPIO11 | D1 |
| GND | 8 | GND | GND | GND |

Dây dưới 10 cm, không nối nguồn giữa hai mạch. Bốn chân GPIO này là IO_MUX của SPI2. Không dùng GPIO33-37 vì PSRAM chiếm. Module thẻ SD trong `test/` đang nối đúng bốn chân đó, nên khi nối FPGA phải tháo module SD.

**`uart12m`**, không cần nối dây hay adapter. Cáp USB-C ở J4 vừa cấp nguồn vừa là đường dữ liệu: `UART_D` của FT4232HL nối W21 (FPGA RX) và Y21 (FPGA TX) ở Bank 0, 1,8 V, theo reference design của Microchip. Chân lấy từ `MPFS_DISCOVERY_UARTS.pdc` và FIR demo của Microchip, chưa đối chiếu schematic.

Windows tạo nhiều cổng COM. Kênh D thường là cổng số lớn nhất nhưng không đảm bảo, nên thử `--test` trên từng cổng. Nên đặt latency timer 1 ms trong Device Manager > Port Settings > Advanced. `UART_D` không có RTS/CTS, nên không có flow control phần cứng. Giữ `--window` mặc định.

**`uart2m`**, cần adapter USB-UART ngoài:

| Tín hiệu | J6 | Chân FPGA | Adapter |
|---|---|---|---|
| `uart_rx` | 3 | E14 | TX |
| `uart_tx` | 4 | E15 | RX |
| GND | 8 | GND | GND |

## 5. Cài FT232H cho `spi30`

`pyftdi` cần driver libusb, không dùng được với driver VCP của FTDI:

1. Cắm FT232H, mở [Zadig](https://zadig.akeo.ie), chọn thiết bị FT232H và cài **WinUSB**. Chỉ làm với FT232H, không làm với cổng của kit.
2. Kiểm tra:

```bash
python -c "from pyftdi.ftdi import Ftdi; Ftdi.show_devices()"
```

URL thường là `ftdi://ftdi:232h/1`, đổi bằng `--ftdi-url`.

## 6. Firmware ESP32-S3 cho `spi40`

Firmware nằm trong `esp32_bridge/`, dùng ESP-IDF qua PlatformIO. Lần build đầu tự tải ESP-IDF và toolchain.

1. Sao chép `src/secrets.h.example` thành `src/secrets.h`, đặt tên và mật khẩu AP. File này bị gitignore.
2. Build và nạp, chạy trong `realtime_env/esp32_bridge/`:

```bash
C:\Users\long5\.platformio\penv\Scripts\pio.exe run -t upload
```

3. Nhấn RESET trên board.
4. Nối Wi-Fi PC vào AP vừa đặt. PC sẽ mất Internet trong lúc nối AP này.
5. Đo riêng đoạn Wi-Fi:

```bash
python realtime_env/main.py wifi-test --out wifi_idf_result.txt
```

ESP32 là đường ống byte: PC gửi cùng packet như UART, ESP32 gói vào frame SPI, bỏ STATUS và số 0 rỗng rồi trả packet về. STATUS khác `0xA0` về PC bằng packet `0xEF`.

**Không dùng PSRAM.** Đệm 32 KB nằm trong RAM nội, đủ cho một burst 32 message, khoảng 8,6 KB. DMA qua PSRAM dùng chung băng thông MSPI nên có thể mất dữ liệu.

**`input_delay_ns` phải để 0.** FPGA phát MISO ngay tại cạnh lên mà master lấy mẫu, nên master lấy mẫu trễ sẽ đọc nhầm bit sau.

## 7. Bring-up

Sau khi nạp, `led_done` phải nháy 1 Hz. Nếu không nháy, kiểm tra clock và reset.

Dùng `raw` với vector NIST trước, vì kết quả đã biết. Ví dụ AES-128 TC2, đúng khi ciphertext là `0388dace...` và tag là `ab6e47d4...`:

```bash
python realtime_env/main.py raw --link uart12m -p COM4 --key 00000000000000000000000000000000 --iv 000000000000000000000000 --data 00000000000000000000000000000000
```

Với UART, chạy thêm test NIST từ trong `realtime_env/`:

```bash
python -m host.uart_client --test -v aes256 -p COM4 -b 12000000
```

Sau đó thử ảnh nhỏ với `--window 1`, nếu khớp model thì bỏ cờ này:

```bash
python realtime_env/main.py image realtime_env/input/color_test.png --link uart12m -p COM4 --size 64x64 --window 1 --key <hex> --iv <hex>
```

Với `uart12m`, nếu lỗi thì đo W21 và Y21 bằng oscilloscope, rồi build lại ở 8 hoặc 6 Mbaud.

Với `spi40`, `spi30`, kiểm tra STATUS đầu tiên bằng lệnh `raw`. Nếu 40 MHz lỗi, hạ `SCLK_HZ` trong `esp32_bridge/src/main.c` xuống 26 666 667 Hz rồi nạp lại.

Khi đã chạy ổn, thay số mô phỏng trong README bằng số đo trên board.

## 8. Xử lý lỗi

| Dấu hiệu | Nguyên nhân thường gặp | Cách xử lý |
|---|---|---|
| `SPI slave is not answering` | MISO treo, sai chân, chưa nạp SPI, thiếu GND | Đo MISO, kiểm tra mục 4 |
| `Cannot reach the ESP32 bridge` | PC chưa nối AP, chưa nhấn RESET | Kiểm tra Wi-Fi, `--esp-host` |
| `rx_overflow` | Host gửi vượt RX FIFO | Giảm `--window` |
| `tx_overflow` | TX FIFO đầy vì host đọc chậm | Giảm `--window` |
| `bad_op` | Lệch bit SPI, sai mode, dây dài | Giảm SCLK, kiểm tra mode 0 |
| Timeout UART | Sai cổng, sai baud, chưa reset | Kiểm tra `-p`, nhấn reset |
| `ERR_TIMEOUT` (`0xE2`) | Packet đứt giữa chừng | Tự phục hồi, gửi lại |
| `ERR_LEN_MISMATCH` (`0xE1`) cho `LOAD_KEY` | Key không khớp bitstream | Đổi key hoặc bitstream |
| `VERIFY FAIL` | Ciphertext, IV, AAD hoặc tag đã bị đổi | Kiểm tra đường truyền, xem chunk được báo |
| Chỉ lệch tag so với model | Bitstream build từ RTL cũ, trước khi sửa GHASH | Build lại |

Mỗi kết nối SPI bắt đầu bằng frame `CLEAR`, nên bỏ dở phiên trước không cần reset tay.

## 9. Đã và chưa kiểm chứng

Kết quả mô phỏng RTL ngày 01/11/2026 qua `main.py`, ảnh RGB tổng hợp, clock 50 MHz, key, IV và AAD do người dùng đưa. Thời gian là một lượt mã hoá, tính cả frame đọc phản hồi còn lại. Tốc độ tính theo payload, host lý tưởng.

| `--link` | Ảnh | Chunk | Mã hoá | Tốc độ | VERIFY | Pixel |
|---|---|---|---|---|---|---|
| `spi40` | 64×64 | 52 | 2,91 ms | 4,22 MB/s | 52/52 | Khớp |
| `spi30` | 64×64 | 52 | 3,89 ms | 3,16 MB/s | 52/52 | Khớp |
| `uart12m` | 64×64 | 52 | 13,52 ms | 0,91 MB/s | 52/52 | Khớp |
| `uart2m` | 64×64 | 52 | 71,62 ms | 0,17 MB/s | 52/52 | Khớp |

**Đã kiểm chứng**

- AES-256 trên RTL: vector TC14, TC15; giải mã tag đúng, tag sai không ra plaintext, thiếu `LOAD_TAG_REF`, packet đứt, khoá sai độ dài, opcode lạ (`tb_aes256_uart_wrapper`, 32/32).
- AES-128 trên RTL: TC2, TC3, giải mã TC2 (`tb_aes128_uart_wrapper`, 17/17); ảnh 32×32 qua `spi40` và `uart12m`, 13/13 chunk.
- `raw --file` với file JPEG qua `spi40`, khớp từng byte, 5/5 chunk.
- Cố ý lật 1 bit ciphertext ở chunk 7: IP báo `FAIL` đúng chunk đó và `decrypted.png` không được ghi.
- Mọi frame SPI đều có STATUS `0xA0`, tức không overflow.
- Host: 180 test pytest, gồm cổng serial giả, SPI giả, cầu nối ESP32 giả, menu và camera từ file video.
- UART 12 Mbaud trên RTL: mọi bit TX đúng 10 clock, đủ 256 byte qua hai miền clock khi host đúng baud và lệch ±2% (`tb_uart_phy`).
- Libero 2026.1, post-layout, ba corner, `MPFS095T-1FCSG325E`:

| Root | 4LUT | DFF | LSRAM | Setup `clk` (ns) | Setup clock link (ns) | Hold nhỏ nhất (ns) |
|---|---|---|---|---|---|---|
| `aes256_uart_wrapper` | 33 438 | 8 723 | 1 | +12,353 | | +0,028 |
| `aes128_uart_wrapper` | 26 526 | 7 178 | 1 | +12,301 | | +0,043 |
| `aes256_uart_12m_top` | 33 412 | 8 736 | 1 | +10,176 | `clk_uart` +6,251 | +0,066 |
| `aes128_uart_12m_top` | 26 551 | 7 191 | 1 | +9,809 | `clk_uart` +6,374 | +0,026 |
| `aes256_spi_wrapper` | 33 504 | 8 812 | 2 | +11,585 | `spi_sclk` +2,309 | +0,056 |
| `aes128_spi_wrapper` | 26 595 | 7 268 | 2 | +12,152 | `spi_sclk` +1,638 | +0,053 |

Cả sáu root không có slack âm ở cả setup và hold, độ phủ constraint 99,99%. `clk` chạy 50 MHz, `clk_uart` 120 MHz, `spi_sclk` 40 MHz.

**Chưa kiểm chứng**

- Toàn chuỗi ESP32-S3 tới FPGA: chưa nối J5. Code bóc MISO trong firmware không có test tự động, phải kiểm khi bring-up.
- Input và output delay trong `aes_spi.sdc` là giả định, nên slack ở trên không phải số đo trên board.
- `camera` với camera thật và phần cứng thật. Mới chạy với file video trên software model.
- `Ft232hLink` với FT232H thật; `uart2m`, `uart12m` với board thật.
- Mọi số tốc độ trên phần cứng.
- 12 Mbaud trên đường FT4232HL tới W21/Y21: không đọc được schematic nên chưa biết có level shifter không.
- Metastability, độ trễ I/O và nhiễu dây, những thứ mô phỏng RTL không thể hiện.
- Sơ đồ chân J5, J6, W21, Y21 so với schematic của kit.

## 10. Giới hạn SCLK và throughput

**Mức chọn: `spi40`, full-duplex 40 MHz, IP giữ 50 MHz.** ESP32-S3 có các mức 80, 40, 26,67 và 20 MHz, giả định nguồn clock 80 MHz. Firmware in tần số thật lúc khởi động và trong lệnh `INFO`.

MISO được phát ngay tại cạnh lên mà master lấy mẫu, nên vòng đi về có cả một chu kỳ SCLK thay vì nửa chu kỳ. Clock-to-out tối thiểu 3,94 ns chính là hold cho master.

| Tầng | Giới hạn | Nguồn số |
|---|---|---|
| CDC trong `spi_link` | Đạt tới 80 MHz, thiếu chunk từ 83,3 MHz | Mô phỏng 64×64, thiết kế ghi 70 MHz để chừa biên |
| MISO, giả định 5 ns cho master và dây | Khoảng 83 MHz | Tính từ SmartTime |
| MOSI, giả định input delay 8 ns | Khoảng 49 MHz | Tính từ SmartTime. Muốn 80 MHz thì input delay phải dưới khoảng 4 ns |

**Toàn chuỗi `spi40` đang bị chặn ở Wi-Fi, không phải SPI hay IP.** Số đo trong [BAO_CAO_NGHIEM_THU.md](../test/BAO_CAO_NGHIEM_THU.md), firmware Arduino cửa sổ TCP 5,76 KB:

| Đường PC tới ESP32 | PC → board | board → PC | Hai chiều cùng lúc |
|---|---|---|---|
| USB-CDC | 230 KB/s | 250 KB/s | Chưa đo |
| Wi-Fi qua router | 532 KB/s | 538 KB/s | Chưa đo |
| Wi-Fi AP | 934 KB/s | 997 KB/s | 1 024-1 127 KB/s tổng |

`esp32_bridge` dùng cửa sổ 32 KB. Espressif công bố TCP khoảng 60 Mbit/s ở cấu hình này, đo trong buồng chắn với router, nên số thật trên PC của bạn phải đo bằng `wifi-test`.

<!-- WIFI -->

**Số khung/giây theo tổng băng thông hai chiều**, tính cả overhead 9%, mã hoá và trả về:

| Tổng hai chiều | JPEG 640×480 q50 (16 KB) | JPEG 1280×720 q50 (39 KB) | Raw RGB 256×256 (192 KB) |
|---|---|---|---|
| 1,05 MB/s (đo với firmware Arduino) | khoảng 31 fps | khoảng 13 fps | khoảng 2,6 fps |
| 3 MB/s (giả định) | khoảng 86 fps | khoảng 35 fps | khoảng 7 fps |
| 5 MB/s (giả định) | khoảng 143 fps | khoảng 59 fps | khoảng 12 fps |

`--fpga-decrypt` chia đôi các số trên. Camera laptop chỉ khoảng 27 fps. Nếu tổng hai chiều vượt khoảng 8 MB/s thì SPI 40 MHz mới thành nút thắt, lúc đó mới cần xét 80 MHz.

Từ PC, ESP32-S3 không phải đường nhanh nhất. Ảnh RGB 256×256 qua `spi30` khoảng 0,06 s, `uart12m` khoảng 0,22 s, `spi40` khoảng 0,4 s với số Wi-Fi hiện có. Giá trị của `spi40` là không dây.
