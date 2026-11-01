# realtime_env

Môi trường chạy IP AES-GCM trên PolarFire SoC Discovery Kit: RTL tích hợp, host Python và firmware ESP32-S3 nằm chung một chỗ. Một script duy nhất, bốn đường truyền, ba chế độ xử lý. Key, IV và AAD luôn do người dùng đưa vào.

Hướng dẫn build, nối dây và bring-up nằm trong [INSTRUCTIONS.md](INSTRUCTIONS.md). Định dạng lệnh nằm trong [docs/protocol.md](docs/protocol.md).

## Cấu trúc

```
realtime_env/
├── main.py          Điểm vào duy nhất
├── host/            Python: giao thức, đường truyền, ảnh, camera, menu
├── rtl/             common/ (engine, link, constraint, script build), aes128/, aes256/, legacy/
├── esp32_bridge/    Firmware cầu nối Wi-Fi sang SPI
├── docs/            Giao thức, kiến trúc
├── tests/           pytest
├── input/           Ảnh đầu vào, gitignore
└── output/          Kết quả, gitignore
```

## Cài đặt

```bash
pip install -r realtime_env/requirements.txt
```

## Cách chạy

Chạy không tham số để menu hỏi từng bước:

```bash
python realtime_env/main.py
```

Hoặc đưa đủ tham số:

```bash
python realtime_env/main.py raw --link uart12m --key <hex> --iv <hex> --aad <hex> --data <hex>
```

```bash
python realtime_env/main.py raw --link spi40 --key <hex> --iv <hex> --file frame.jpg
```

```bash
python realtime_env/main.py image photo.png --link spi40 --key <hex> --iv <hex> --aad <hex> --size 64x64
```

```bash
python realtime_env/main.py camera --link spi40 --key <hex> --iv <hex> --size 640x480 --quality 50
```

### Đường truyền

| `--link` | Tốc độ RTL mô phỏng | Phần cứng |
|---|---|---|
| `uart2m` | 0,17 MB/s | Adapter USB-UART ở J6 |
| `uart12m` | 0,91 MB/s | USB-C J4 |
| `spi30` | 3,16 MB/s | FT232H ở J5 |
| `spi40` | 4,22 MB/s | ESP32-S3 ở J5, PC nối qua Wi-Fi |

Thêm `--sim model` để chạy software model, `--sim rtl` để chạy QuestaSim đúng tốc độ của link đó, không cần phần cứng.

Tốc độ trên là đoạn tới FPGA với host lý tưởng. Với `spi40`, đoạn Wi-Fi chậm hơn nhiều: xem mục 10 của [INSTRUCTIONS.md](INSTRUCTIONS.md).

### Chế độ xử lý

| Lệnh | Việc làm |
|---|---|
| `raw --data` | Đúng một message GCM từ giá trị bạn đưa, tối đa 240 byte. `--op decrypt --tag <hex>` để giải mã có `VERIFY` |
| `raw --file` | File nhị phân bất kỳ: chia chunk, mã hoá, giải mã, so từng byte |
| `image` | Ảnh hoặc thư mục ảnh, in từng bước và lưu `console_<link>.png` |
| `camera` | PC nén JPEG, FPGA mã hoá, PC giải mã. `--fpga-decrypt` cho FPGA giải mã và kiểm tag, fps còn khoảng một nửa. `--source <video>` thay camera |

## Key, IV và AAD

| Giá trị | Quy tắc |
|---|---|
| `--key` | Bắt buộc, 16 hoặc 32 byte, quyết định AES-128 hay AES-256. Phải khớp bitstream |
| `--iv` | Bắt buộc, 12 byte. `raw --data` dùng nguyên giá trị. Các chế độ còn lại: đây là IV của chunk đầu, 32 bit cuối tăng 1 cho mỗi chunk |
| `--aad` | Tuỳ chọn, tối đa 240 byte. Với `image`, `camera`, `raw --file` đi cùng chunk đầu của mỗi ảnh hoặc khung |

- **Không dùng lại cùng key và IV.** GCM mất an toàn nếu lặp. Chương trình cảnh báo nhưng không tự đổi IV của bạn, nên mỗi lần chạy phải đưa IV mới.
- **Lõi chỉ nhận block 16 byte.** AAD và dữ liệu lẻ được đệm 0 kèm cảnh báo, nên tag khác tag của chuẩn trên dữ liệu chưa đệm.
- **Kích thước ảnh và độ dài** nằm trong `session.json` cạnh `tx.bin`, không đi qua đường truyền.
- **Key đi rõ trên đường truyền** và được in ra console. Chỉ dùng key demo.

## Kết quả

Mỗi ảnh hoặc file có một thư mục trong `output/`:

| File | Nội dung |
|---|---|
| `preview.png`, `cipher.png`, `decrypted.png` | Ảnh gốc, ảnh mã, ảnh giải mã |
| `tx.bin`, `rx.bin`, `tx.txt`, `rx.txt` | Packet gửi đi và nhận về khi mã hoá |
| `tx_dec.*`, `rx_dec.*` | Packet khi giải mã |
| `session.json` | Kích thước và cách chia chunk |
| `console_<link>.png` | Ảnh của đúng log vừa in |

`decrypted.png` chỉ được ghi khi IP xác thực đủ mọi chunk.

## Kiểm thử

```bash
python -m pytest realtime_env/tests -q
```

Test NIST trực tiếp trên board qua UART, chạy từ trong `realtime_env/`:

```bash
python -m host.uart_client --test -v aes256 -p COM4 -b 12000000
```
