# Hướng dẫn: UART, SPI và ảnh màu trên AES-GCM

Tài liệu này dành cho bước tiếp theo: chạy mô phỏng, build bitstream, nối dây và đưa lên PolarFire SoC Discovery Kit. Định dạng lệnh và phản hồi nằm trong [protocol.md](../uart_integration/docs/protocol.md).

**Trạng thái:** code hoàn chỉnh và đã qua mô phỏng RTL trong QuestaSim. Dòng UART 12 Mbaud và dòng SPI đã qua Synthesize, Place and Route và Verify Timing. Dòng UART 2 Mbaud chưa build lại. **Chưa có firmware ESP32-S3, chưa tạo bitstream, chưa nạp board.** Xem mục 9 và 10.

## 1. Có gì mới

- **Ba dòng bitstream riêng.** Mỗi lần dùng một giao thức cố định: UART 12 Mbaud qua cổng USB-C J4, UART trên J6, hoặc SPI trên J5.
- **Ảnh màu.** Ảnh màu được giữ RGB 8-bit mỗi kênh, ảnh xám giữ một kênh. `--gray` ép về một kênh.
- **Xác thực trong IP.** `LOAD_TAG_REF` đưa tag mong đợi vào lõi. Tag sai thì IP không trả plaintext.
- **Tốc độ.** UART mặc định 2 Mbaud, tới 12 Mbaud với root `aes256_uart_12m_top` hoặc `aes128_uart_12m_top`, gửi burst 32 message. SPI full-duplex 40 MHz với master ESP32-S3, hoặc tới 30 MHz với FT232H.
- **Chịu lỗi.** RX FIFO 2048 byte, parser không mất byte, packet đứt giữa chừng tự huỷ sau 10 ms, opcode lạ được bỏ qua cả payload.

```
Dòng SPI:   ESP32  ─► spi_link (miền SCLK) ─┐
            (J5)   ◄─ TX FIFO ◄─────────────┤
                                            ├─ aes_gcm_engine: RX FIFO ─► parser ─► FSM + lõi GCM ─► builder
Dòng UART:  USB-UART ─► uart_rx ────────────┤
            (E14/E15) ◄─ uart_tx ◄──────────┘

Dòng 12 Mbaud:  FT4232HL kênh D ─► uart_rx, uart_tx (120 MHz) ─► uart_cdc_link ─► aes_gcm_engine (50 MHz)
                (W21/Y21)
```

## 2. Chạy mô phỏng và xem ảnh console

Cần `pip install -r image_process/requirements.txt` và QuestaSim đi kèm Libero. Nếu Libero không nằm ở `C:\Microchip\Libero_SoC_2026.1`, đặt biến môi trường `QUESTA_BIN` trỏ tới thư mục `QuestaSim_Pro\win64`.

Chạy từ trong thư mục `image_process/`:

```bash
python -m imgapp sample -o input/color_test.png --size 64x64
```

```bash
python -m imgapp run --size 64x64 --backend model
```

```bash
python -m imgapp run --size 64x64 --backend rtl-spi --sclk-mhz 40
```

```bash
python -m imgapp run --size 64x64 --backend rtl-uart --baud 2000000
```

```bash
python -m imgapp run --size 64x64 --backend rtl-uart --baud 12000000 --uart-clk-mhz 120
```

```bash
python -m imgapp run --size 64x64 --backend rtl-spi --tamper-chunk 7
```

`run` xử lý mọi ảnh trong `input/`. Kết quả ở `output/<tên_ảnh>/`, trong đó có `console_<backend>.png` là ảnh của đúng log vừa in, và `console_<backend>_tamper.png` cho lần chạy cố ý sửa ciphertext.

| Bước | In ra |
|---|---|
| ENCODE | Kích thước, SHA-256 của pixel, KEY, phần ngẫu nhiên của IV, AAD ở dạng hex và đã giải nghĩa |
| SIMULATE | Backend, link, STATUS, thời gian mô phỏng, IV, AAD và TAG từng chunk |
| DECODE | `cipher.png` cạnh `preview.png` |
| DECRYPT | TAG-REF, TAG tính được và VERIFY từng chunk, rồi ảnh giải mã |

`--show-chunks N` đổi số chunk đầu và cuối được in. Chunk `FAIL` luôn được in.

Mô phỏng 256×256 mất vài phút. `simulate` và `decrypt` nhận `--backend` như `run`, nên có thể chạy từng bước.

Testbench tự kiểm tra, chạy từ gốc repo:

```bash
"C:\Microchip\Libero_SoC_2026.1\Libero_SoC\QuestaSim_Pro\win64\vsim.exe" -c -do "set KEY_BITS 256; set TB tb_aes256_uart_wrapper; do uart_integration/common/run_tb.do"
```

```bash
"C:\Microchip\Libero_SoC_2026.1\Libero_SoC\QuestaSim_Pro\win64\vsim.exe" -c -do "set KEY_BITS 128; set TB tb_aes128_uart_wrapper; do uart_integration/common/run_tb.do"
```

```bash
"C:\Microchip\Libero_SoC_2026.1\Libero_SoC\QuestaSim_Pro\win64\vsim.exe" -c -do "set KEY_BITS 256; set TB tb_uart_phy; do uart_integration/common/run_tb.do"
```

## 3. Chọn bitstream

| Bitstream | Design Root | Lõi | Constraint trong `uart_integration/common/` |
|---|---|---|---|
| SPI AES-256 | `aes256_spi_wrapper` | `RTL/AES_256_GCM.sv` | `aes_spi.pdc`, `aes_spi.sdc` |
| SPI AES-128 | `aes128_spi_wrapper` | `RTL/AES_GCM.sv` | `aes_spi.pdc`, `aes_spi.sdc` |
| UART AES-256 | `aes256_uart_wrapper` | `RTL/AES_256_GCM.sv` | `aes_uart.pdc`, `aes_uart.sdc` |
| UART AES-128 | `aes128_uart_wrapper` | `RTL/AES_GCM.sv` | `aes_uart.pdc`, `aes_uart.sdc` |
| UART 12 Mbaud AES-256 | `aes256_uart_12m_top` | `RTL/AES_256_GCM.sv` | `aes_uart_12m.pdc`, `aes_uart_12m.sdc` |
| UART 12 Mbaud AES-128 | `aes128_uart_12m_top` | `RTL/AES_GCM.sv` | `aes_uart_12m.pdc`, `aes_uart_12m.sdc` |

Host phải khớp bitstream: khoá 32 byte cho AES-256, 16 byte cho AES-128. Khoá sai độ dài bị trả `ERR_LEN_MISMATCH`.

## 4. Build trong Libero

Project `AES-GCM-Libero/` đã chứa lõi 128 và 256 cùng các root UART và SPI. Hai file `SubWord.sv` giống hệt nhau nên project chỉ link `RTL/Key_Expansion_256/SubWord.sv`, vì một tên module chỉ link được một lần. Libero lưu kết quả theo root, trong `designer/<root>/` và `synthesis/<root>.vm`, nên đổi Design Root không làm mất bản kia.

Các root `aes256_spi_wrapper`, `aes128_spi_wrapper`, `aes256_uart_12m_top`, `aes128_uart_12m_top` đã qua Verify Timing, trong đó `aes256_spi_wrapper` đang là Design Root. Để có bitstream:

1. Đặt Design Root theo bảng ở mục 3.
2. Chạy Generate FPGA Array Data, Generate Bitstream.
3. Nạp bằng FlashPro5 trên kit theo Appendix A của User Guide.

**Dựng lại dòng SPI**, trong Project > Execute Script, từng dòng một:

```tcl
set REPO C:/path/to/AES_Verilog
```

```tcl
source $REPO/uart_integration/common/build_spi.tcl
```

Script tự thêm file, gán constraint và chạy cả hai key size tới Verify Timing, khoảng 15 phút. Kết quả thay đổi nhẹ theo từng lần place and route, nên sau mỗi lần build cần kiểm tra lại:

- Không có slack âm ở `clk` và `spi_sclk`.
- `clk` và `spi_sclk` nằm trên global trong `<root>_glb_net_report.xml`.
- `byte_fifo` ra LSRAM: 2 khối ở dòng SPI.

Root `aes256_uart_wrapper` và `aes128_uart_wrapper` chưa build lại. Cần dùng thì gán `aes_uart.pdc`, `aes_uart.sdc` trong Constraint Manager rồi chạy Synthesize, Place and Route, Verify Timing.

Baud khác mặc định thì đặt `BAUD_RATE` trong top-level parameter. Ở các wrapper 50 MHz, giá trị nên chia chẵn 50 MHz:

| Baud | Chia | Sai số | Ghi chú |
|---|---|---|---|
| 1 000 000 | 50 | 0 | Hầu hết adapter |
| 2 000 000 | 25 | 0 | Mặc định |
| 3 000 000 | 16,67 | 4,2% | Tránh |
| 5 000 000 | 10 | 0 | Cần adapter hi-speed; bộ chia phía adapter có thể lệch khoảng 1% |
| 12 000 000 | 4,17 | 4,2% | Vượt ngưỡng ±3% của FTDI, phải dùng root 12 Mbaud |

**Dòng 12 Mbaud** đã có sẵn trong `AES-GCM-Libero/`. Để tạo bitstream, đặt Design Root là `aes256_uart_12m_top` hoặc `aes128_uart_12m_top`, rồi chạy Generate FPGA Array Data và Generate Bitstream như mục 4.

Để dựng lại từ đầu, chạy trong Project > Execute Script, từng dòng một:

```tcl
set REPO C:/path/to/AES_Verilog
```

```tcl
source $REPO/uart_integration/common/pf_ccc_120m.tcl
```

```tcl
source $REPO/uart_integration/common/build_12m.tcl
```

Script tự thêm file, gán constraint và chạy cả hai key size tới Verify Timing, khoảng 15 phút.

IP giữ 50 MHz, chỉ UART chạy 120 MHz từ PF_CCC. Tốc độ chậm hơn chỉ cần đổi `BAUD_RATE` của root, vì 120 MHz chia chẵn cho 12, 8, 6, 4, 3, 2 và 1 Mbaud. FT4232HL không hỗ trợ 7, 9, 10, 11 Mbaud.

## 5. Nối dây

**Đối chiếu schematic của kit trước khi cắm dây.** Bảng chân trong User Guide bị lệch cột khi đọc, và tên tín hiệu J5 suy ra từ thứ tự chuẩn mikroBUS. J45 phải đóng 1-2 để Bank 1 chạy 3,3 V.

**SPI**, master là ESP32-S3 N16R8. FT232H hoặc cáp C232HM dùng được thay thế, tới 30 MHz. FT4232HL trên kit không dùng được vì kênh D nối fabric không có MPSSE:

| Tín hiệu | J5 | Chân FPGA | ESP32-S3 | FT232H |
|---|---|---|---|---|
| CS | 3 | C16 | GPIO10 | D3 |
| SCK | 4 | E17 | GPIO12 | D0 |
| MISO | 5 | A18 | GPIO13 | D2 |
| MOSI | 6 | E11 | GPIO11 | D1 |
| GND | 8 | GND | GND | GND |

Bốn chân GPIO này là IO_MUX của SPI2. Không dùng GPIO33-37 vì PSRAM chiếm. Module thẻ SD trong `test/` đang nối đúng bốn chân đó, nên khi nối FPGA phải tháo module SD hoặc chuyển nó sang SPI3 ở chân khác.

**UART 12 Mbaud**, không cần nối dây hay adapter. Cáp USB-C ở J4 vừa cấp nguồn vừa là đường dữ liệu: `UART_D` của FT4232HL nối W21 (FPGA RX) và Y21 (FPGA TX) ở Bank 0, 1,8 V, theo reference design của Microchip. Chân lấy từ `MPFS_DISCOVERY_UARTS.pdc` và FIR demo của Microchip, chưa đối chiếu schematic.

Windows tạo nhiều cổng COM. Kênh D thường là cổng số lớn nhất nhưng không đảm bảo, nên thử `host.py --test` trên từng cổng. Nên đặt latency timer 1 ms trong Device Manager > Port Settings > Advanced.

`UART_D` không có RTS/CTS trong constraint của Microchip, nên không có flow control phần cứng. Giữ `--window` mặc định.

**UART trên J6**, giữ chân E14/E15 của project hiện tại, cần adapter USB-UART ngoài:

| Tín hiệu | J6 | Chân FPGA | Adapter |
|---|---|---|---|
| `uart_rx` | 3 | E14 | TX |
| `uart_tx` | 4 | E15 | RX |
| GND | 8 | GND | GND |

Dây dưới 10 cm, không nối nguồn giữa hai mạch.

## 6. Cài host cho SPI

`pyftdi` cần driver libusb, không dùng được với driver VCP của FTDI:

1. Cắm FT232H, mở [Zadig](https://zadig.akeo.ie), chọn thiết bị FT232H và cài **WinUSB**. Chỉ làm với FT232H, không làm với cổng của kit.
2. Kiểm tra:

```bash
python -c "from pyftdi.ftdi import Ftdi; Ftdi.show_devices()"
```

URL thường là `ftdi://ftdi:232h/1`.

## 7. Bring-up

Sau khi nạp, `led_done` phải nháy 1 Hz. Nếu không nháy, kiểm tra clock và reset.

**UART:**

```bash
python ../uart_integration/python/host.py --test -v aes256 -p COM4
```

```bash
python -m imgapp encode input/color_test.png --size 64x64
```

```bash
python -m imgapp send output/color_test.png/tx.bin -p COM4 --window 1
```

Nếu khớp model, bỏ `--window 1` để chạy burst.

**UART 12 Mbaud**, như trên nhưng thêm `-b 12000000`:

```bash
python ../uart_integration/python/host.py --test -v aes256 -p COM4 -b 12000000
```

```bash
python -m imgapp send output/color_test.png/tx.bin -p COM4 -b 12000000 --window 1
```

Nếu lỗi, đo W21 và Y21 bằng oscilloscope, rồi thử 8 hoặc 6 Mbaud.

**SPI**, tăng dần `--sclk-mhz` và chỉ đi tiếp khi `spi-send` báo khớp model:

```bash
python -m imgapp spi-send output/color_test.png/tx.bin --sclk-mhz 7.5
```

```bash
python -m imgapp spi-send output/color_test.png/tx.bin --sclk-mhz 15
```

```bash
python -m imgapp spi-send output/color_test.png/tx.bin --sclk-mhz 30
```

**Giải mã trên board**, thay `spi-send` bằng `send` nếu dùng UART:

```bash
python -m imgapp decrypt output/color_test.png/tx.bin output/color_test.png/rx.bin
```

```bash
python -m imgapp spi-send output/color_test.png/tx_dec.bin --sclk-mhz 15
```

```bash
python -m imgapp decrypt output/color_test.png/tx.bin output/color_test.png/rx.bin --rx-dec output/color_test.png/rx_dec.bin
```

Lệnh đầu tạo `tx_dec.bin`. Lệnh cuối chỉ ghi ảnh khi IP xác thực đủ mọi chunk. Khi đã chạy ổn, hãy ghi lại tốc độ `spi-send` in ra để thay các số tính toán.

## 8. Xử lý lỗi

| Dấu hiệu | Nguyên nhân thường gặp | Cách xử lý |
|---|---|---|
| `SPI slave is not answering` | MISO treo, sai chân, chưa nạp SPI, thiếu GND | Đo MISO, kiểm tra mục 5 |
| `rx_overflow` | Host gửi vượt RX FIFO | Giảm `--window` |
| `tx_overflow` | TX FIFO đầy vì host đọc chậm | Giảm `--window` |
| `bad_op` | Lệch bit SPI, sai mode, dây dài | Giảm SCLK, kiểm tra mode 0 |
| Timeout UART | Sai cổng, sai baud, chưa reset | Kiểm tra `-p`, `-b`, nhấn reset |
| `ERR_TIMEOUT` (`0xE2`) | Packet đứt giữa chừng | Tự phục hồi, gửi lại |
| `ERR_LEN_MISMATCH` (`0xE1`) cho `LOAD_KEY` | Khoá không khớp bitstream | Dùng đúng `-v` khi encode |
| `ERR_LEN_MISMATCH` cho `START_DECRYPT` | Thiếu `LOAD_TAG_REF` | Tạo lại `tx_dec` bằng lệnh `decrypt` |
| `VERIFY FAIL` | Ciphertext, IV, AAD hoặc tag đã bị đổi | Kiểm tra đường truyền, xem chunk được báo |
| Chỉ lệch tag so với model | Bitstream build từ RTL cũ, trước khi sửa GHASH | Build lại |

Mỗi lần `spi-send` bắt đầu bằng frame `CLEAR`, nên bỏ dở phiên trước không cần reset tay. Key đi rõ và được in ra console, nên chỉ dùng key demo.

## 9. Đã và chưa kiểm chứng

Kết quả mô phỏng RTL ngày 01/11/2026, ảnh RGB tổng hợp, clock 50 MHz. Thời gian là thời gian mô phỏng cho một lượt mã hoá, tính cả frame đọc phần phản hồi còn lại. Tốc độ tính theo payload.

| Link | Ảnh | Chunk | Mã hoá | Tốc độ | VERIFY | Pixel |
|---|---|---|---|---|---|---|
| SPI 40 MHz | 256×256 | 820 | 45,93 ms | 4,28 MB/s | 820/820 | Khớp |
| SPI 40 MHz | 64×64 | 52 | 2,91 ms | 4,22 MB/s | 52/52 | Khớp |
| SPI 26,67 MHz | 64×64 | 52 | 4,37 ms | 2,81 MB/s | 52/52 | Khớp |
| UART 12 Mbaud | 64×64 | 52 | 13,52 ms | 0,91 MB/s | 52/52 | Khớp |
| UART 5 Mbaud | 64×64 | 52 | 29,33 ms | 0,42 MB/s | 52/52 | Khớp |
| UART 2 Mbaud | 64×64 | 52 | 71,62 ms | 0,17 MB/s | 52/52 | Khớp |

Các số này là giới hạn của đường truyền với host lý tưởng. FT232H, USB và adapter thực tế sẽ chậm hơn, nên cần đo lại trên board.

**Đã kiểm chứng**

- AES-256 trên RTL: vector TC14, TC15; giải mã tag đúng, tag sai không ra plaintext, thiếu `LOAD_TAG_REF`, packet đứt, khoá sai độ dài, opcode lạ (`tb_aes256_uart_wrapper`, 32/32).
- AES-128 trên RTL: TC2, TC3, giải mã TC2 (`tb_aes128_uart_wrapper`, 17/17); ảnh 32×32 qua SPI và UART, 13/13 chunk.
- 1 đến 3 block, có và không có AAD, trên cả hai key size.
- Cố ý lật 1 bit ciphertext ở chunk 7: IP báo `FAIL` đúng chunk đó và `decrypted.png` không được ghi.
- Mọi frame SPI đều có STATUS `0xA0`, tức không overflow, ở 26,67, 39,7 và 40 MHz. AES-128 ảnh 32×32 ở 40 MHz đạt 13/13.
- Host: 125 test pytest, gồm thiết bị serial và SPI giả.
- UART 12 Mbaud trên RTL: mọi bit TX đúng 10 clock, đủ 256 byte qua hai miền clock khi host đúng baud và lệch ±2% (`tb_uart_phy`); ảnh RGB 64×64 trên cả AES-256 và AES-128, 52/52 chunk.
- UART 12 Mbaud trong Libero 2026.1, post-layout, ba corner, `MPFS095T-1FCSG325E`:

| Root | LUT | FF | LSRAM | Setup `clk` (20 ns) | Setup `clk_uart` (8,333 ns) | Hold nhỏ nhất |
|---|---|---|---|---|---|---|
| `aes256_uart_12m_top` | 33 412 | 8 736 | 1 | +10,176 ns | +6,251 ns | +0,066 ns |
| `aes128_uart_12m_top` | 26 551 | 7 191 | 1 | +9,809 ns | +6,374 ns | +0,026 ns |

  Độ phủ constraint 99,99%, phần còn lại chỉ là `led_busy` và `led_done`. Chu kỳ `clk` tối thiểu khoảng 10 ns, tức khoảng 100 MHz, và thay đổi theo từng lần place and route. Root `aes256_uart_wrapper` và `aes128_uart_wrapper` có trong project nhưng chưa build lại với RTL hiện tại.

- SPI trong Libero 2026.1, post-layout, ba corner, `spi_sclk` 25 ns (40 MHz):

| Root | LUT | FF | LSRAM | Setup `clk` | Setup `spi_sclk` | Hold nhỏ nhất | SCLK tới MISO |
|---|---|---|---|---|---|---|---|
| `aes256_spi_wrapper` | 33 504 | 8 812 | 2 | +11,585 ns | +2,309 ns | +0,056 ns | 3,94-7,06 ns |
| `aes128_spi_wrapper` | 26 595 | 7 268 | 2 | +12,152 ns | +1,638 ns | +0,053 ns | 3,94-7,04 ns |

  `clk` và `spi_sclk` đều lên global, E17 là `CLKIN_S_8`. Độ phủ constraint 99,99%. `miso_reg` nằm ở fabric, không vào I/O register. Setup `spi_sclk` nhỏ nhất là đường MOSI, phụ thuộc giả định input delay 8 ns trong SDC; đường MISO còn +12,9 ns.

**Chưa kiểm chứng**

- Tổng hợp và timing của `aes256_uart_wrapper`, `aes128_uart_wrapper`.
- Toàn bộ đường ESP32-S3 tới FPGA: chưa có firmware, chưa nối J5. Input và output delay trong `aes_spi.sdc` là giả định, nên slack ở trên không phải số đo trên board.
- `Ft232hLink` và lệnh `spi-send` với FT232H thật; `send` với board thật.
- Mọi số tốc độ trên phần cứng.
- 12 Mbaud trên đường FT4232HL tới W21/Y21: không đọc được schematic nên chưa biết có level shifter không.
- Metastability, độ trễ I/O và nhiễu dây, những thứ mô phỏng RTL không thể hiện.
- Sơ đồ chân J5, J6, W21, Y21 so với schematic của kit.

## 10. Giới hạn SCLK và định hướng ESP32-S3

**Mức chọn: 40 MHz full-duplex, IP giữ 50 MHz.** ESP32-S3 có các mức 80, 40, 26,67 và 20 MHz, giả định nguồn clock 80 MHz. Firmware phải đọc lại bằng `spi_device_get_actual_freq()`.

MISO được phát ngay tại cạnh lên mà master lấy mẫu, nên vòng đi về có cả một chu kỳ SCLK thay vì nửa chu kỳ. Clock-to-out tối thiểu 3,94 ns chính là hold cho master. Vì vậy firmware nên để `input_delay_ns = 0`: master lấy mẫu trễ quá sẽ đọc nhầm bit sau.

| Tầng | Giới hạn | Nguồn số |
|---|---|---|
| CDC trong `spi_link` | Đạt tới 80 MHz, thiếu chunk từ 83,3 MHz | Mô phỏng 64×64, thiết kế ghi 70 MHz để chừa biên |
| MISO, giả định 5 ns cho master và dây | Khoảng 83 MHz | Tính từ SmartTime, 20 ns chưa chạy riêng |
| MOSI, giả định input delay 8 ns | Khoảng 49 MHz | Tính từ SmartTime. Muốn 80 MHz thì input delay phải dưới khoảng 4 ns |

Lên 80 MHz không làm nhanh thêm đường nào đang có, vì nút thắt nằm ở phía trước ESP32. Số đo thật trong [BAO_CAO_NGHIEM_THU.md](../test/BAO_CAO_NGHIEM_THU.md):

| Đường PC tới ESP32 | PC → board | board → PC | Hai chiều cùng lúc |
|---|---|---|---|
| USB-CDC | 230 KB/s | 250 KB/s | Chưa đo |
| Wi-Fi qua router | 532 KB/s | 538 KB/s | Chưa đo |
| Wi-Fi AP | 934 KB/s | 997 KB/s | 1 024-1 127 KB/s tổng |

So sánh ảnh RGB 256×256, khoảng 211 KB đi và 225 KB về:

| Đường từ PC | Thời gian | Nguồn số |
|---|---|---|
| FT232H 30 MHz | khoảng 0,06 s | Mô phỏng trước khi đổi cạnh MISO |
| UART 12 Mbaud qua J4 | khoảng 0,22 s | Quy đổi từ mô phỏng, chưa chạy board |
| ESP32-S3 Wi-Fi AP | khoảng 0,4 s | Tính từ số đo, chưa gồm FPGA |
| ESP32-S3 USB-CDC | khoảng 1,9 s | Tính từ số đo |

ESP32-S3 không phải đường nhanh nhất từ PC. Giá trị của nó là không dây, và có thể tự chạy với thẻ SD.

**Định hướng firmware, chưa làm:**

- Nhận dữ liệu qua Wi-Fi AP, giữ USB để debug.
- Trao đổi liên tục, không nạp hết rồi mới gửi. Trên Wi-Fi AP, ảnh trên mất khoảng 0,4 s nếu liên tục và khoảng 0,5 s nếu nạp hết.
- Đệm vòng cỡ một burst 32 message, khoảng 8,6 KB, trong RAM nội. PSRAM chưa từng được kiểm tra trên board, và DMA PSRAM dùng chung băng thông MSPI nên có thể mất dữ liệu. Chỉ dùng chế độ nạp hết để self-test tốc độ SPI.
- Dùng driver `spi_master` với DMA, không dùng thư viện Arduino SPI theo từng byte: mức 1,55 MB/s ở bài SD do thư viện và CPU giới hạn.
- Realtime cần mã hoá luồng JPEG, vì raw RGB 256×256 chỉ khoảng 2,3 khung/giây. `imgapp` hiện chỉ mã hoá pixel raw.
