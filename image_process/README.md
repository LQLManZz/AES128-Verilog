# image_process

Biến ảnh thành luồng gói UART cho IP AES-GCM trên PolarFire SoC Discovery Kit, rồi dịch ngược về ảnh.

App chạy được theo hai cách: với mô hình phần mềm trả về đúng ciphertext và tag theo NIST SP 800-38D như RTL, hoặc với board thật qua lệnh `send`. **Lệnh `send` mới được kiểm thử với cổng serial giả, chưa chạy trên board.**

## Hai cách demo

| | Hex trực tiếp | Xử lý ảnh |
|---|---|---|
| Thư mục | `uart_integration/python/host.py` | `image_process/` |
| Dữ liệu vào | Chuỗi hex hoặc text | File ảnh |
| Kích thước | Một message, tối đa 240 byte | Không giới hạn, tự chia khúc |
| Truyền qua board | Có | Có, qua lệnh `send` |

Hai thư mục độc lập về chức năng nhưng dùng chung một bản giao thức là `uart_integration/python/uart_protocol.py`. Không copy file này sang đây. Vì vậy `image_process/` cần nằm cạnh `uart_integration/`.

## Cài đặt

```bash
pip install -r image_process/requirements.txt
```

## Cách dùng nhanh

1. Bỏ ảnh vào `image_process/input/` (png, jpg, jpeg, bmp, webp, tiff, gif).
2. Chạy từ trong thư mục `image_process/`:

```bash
python -m imgapp run
```

Kết quả nằm trong `output/<tên_ảnh>/`:

| File | Nội dung |
|---|---|
| `tx.txt`, `tx.bin` | Luồng gửi xuống FPGA, dạng hex và dạng byte thô |
| `preview.png` | Ảnh grayscale sẽ được gửi |
| `rx.txt`, `rx.bin` | Phản hồi của FPGA mô phỏng |
| `cipher.png` | Ciphertext hiển thị thành ảnh nhiễu |
| `tx_dec.txt`, `tx_dec.bin` | Luồng giải mã, gửi ciphertext qua `START_DECRYPT` |
| `decrypted.png` | Ảnh sau giải mã, chỉ được ghi khi mọi tag đều đúng |

## Từng bước

```bash
python -m imgapp encode input/anh.png
python -m imgapp simulate output/anh.png/tx.bin
python -m imgapp decode output/anh.png/tx.bin
python -m imgapp decode output/anh.png/tx.bin --rx output/anh.png/rx.bin
python -m imgapp decrypt output/anh.png/tx.bin output/anh.png/rx.bin
```

Các lệnh đọc được cả `.txt` lẫn `.bin`.

| Tùy chọn của `encode` và `run` | Ý nghĩa | Mặc định |
|---|---|---|
| `--size WxH` | Kích thước ảnh | `256x256` |
| `--fit crop\|pad` | Cắt hoặc thêm viền để đúng tỉ lệ | `crop` |
| `-v aes128\|aes256` | Phiên bản IP | `aes256` |
| `--key HEX` | Key, bỏ trống thì sinh ngẫu nhiên | ngẫu nhiên |
| `--chunk-blocks N` | Số block 16 byte mỗi khúc, từ 1 đến 15 | `15` |
| `--output-dir PATH` | Thư mục kết quả | `output/` |

`run` có thêm `--input-dir PATH`.

## Chạy trên board

Cần nạp bitstream của wrapper trước. `--baud` phải khớp `BAUD_RATE` lúc tổng hợp (mặc định 115200). Nên ghi rõ `--port`, vì FT4232HL tạo 4 cổng COM và tự dò có thể chọn nhầm.

**Mã hóa trên board:**

```bash
python -m imgapp encode input/anh.png --size 64x64 --chunk-blocks 1
python -m imgapp send output/anh.png/tx.bin --port COM4
python -m imgapp decode output/anh.png/tx.bin --rx output/anh.png/rx.bin
```

**Giải mã trên board:**

```bash
python -m imgapp decrypt output/anh.png/tx.bin output/anh.png/rx.bin
python -m imgapp send output/anh.png/tx_dec.bin --port COM4
python -m imgapp decrypt output/anh.png/tx.bin output/anh.png/rx.bin --rx-dec output/anh.png/rx_dec.bin
```

Lệnh `decrypt` đầu tiên tạo `tx_dec.bin` bằng mô hình phần mềm. Lệnh cuối mới dùng kết quả của board. Nếu chạy lệnh đầu với `rx.bin` do board gửi về mà tag lệch mô hình, lệnh sẽ báo lỗi nhưng `tx_dec.bin` vẫn được tạo, nên vẫn gửi được xuống board.

`send` ghi đè `rx.txt` và `rx.bin` của mô phỏng, in thời gian và tốc độ đo được, rồi so từng khúc với mô hình phần mềm. Nếu có khác biệt, lệnh báo rõ khúc nào lệch dữ liệu, khúc nào lệch tag, và thoát với mã lỗi.

**Thứ tự thử khi lên board lần đầu.** Khúc 240 byte chưa từng chạy trên phần cứng, nên tăng dần `--chunk-blocks` và chỉ đi tiếp khi `send` báo khớp mô hình:

| Lần | `--chunk-blocks` | Payload mỗi khúc | Ý nghĩa |
|---|---|---|---|
| 1 | `1` | 16 byte | Cùng cỡ với vector TC2, TC14 đã kiểm thử |
| 2 | `4` | 64 byte | Cỡ lớn nhất đã kiểm thử |
| 3 | `15` | 240 byte | Cỡ mặc định, chưa kiểm thử |

**Khi gặp lỗi:**

- **Timeout:** kiểm tra cổng COM, baud rate và nút reset. Lỗi có ghi khúc và lệnh đang chạy. Nếu dừng giữa chừng, nên reset FPGA trước khi gửi lại, và không có file `rx` nào được ghi.
- **Lệch dữ liệu:** ciphertext của board khác chuẩn, cần xem lại lõi hoặc đường truyền.
- **Chỉ lệch tag:** ciphertext vẫn đúng nhưng tag khác mô hình. Tag của mô hình do PyCryptodome tính theo NIST SP 800-38D. Hãy kiểm tra bitstream đã được tổng hợp từ RTL hiện tại: bản cũ chưa đảo bit trong GHASH nên cho tag khác NIST (ví dụ `2c4fa7cb...` thay vì `ab6e47d4...` ở TC2).

## Định dạng luồng dữ liệu

Mỗi message GCM chứa tối đa 240 byte, nên một ảnh được chia thành nhiều khúc:

```
LOAD_KEY                                                     (1 lần)
Khúc 0: LOAD_IV, LOAD_AAD (header), LOAD_PLAINTEXT, START_ENCRYPT
Khúc i: LOAD_IV, LOAD_PLAINTEXT, START_ENCRYPT
```

Mỗi dòng trong file txt là một gói, phần sau `#` là chú thích:

```
02 0C ...            # LOAD_IV chunk 0
04 F0 12 A3 ...      # LOAD_PLAINTEXT chunk 0
05 00                # START_ENCRYPT chunk 0
```

- **Header ảnh:** 16 byte trong AAD của khúc đầu, gồm `"AGI1"`, width, height, channels, chunk_blocks, chunks, byte_len. Toàn bộ số theo big-endian.
- **IV:** 8 byte ngẫu nhiên của lần encode, nối với số thứ tự khúc 4 byte. Mỗi khúc phải có IV riêng, vì trùng IV với cùng key sẽ phá vỡ GCM.
- **Đệm:** khúc cuối được đệm 0 cho đủ block. `byte_len` trong header giữ độ dài thật.

## Lưu ý

- **Key không được bảo vệ.** Key nằm trong `tx.txt`, `tx.bin` và đi không mã hóa qua UART theo thiết kế giao thức. Chỉ dùng key demo. `output/` đã được gitignore.
- **Tag khớp NIST.** `GHASH.sv` đảo 128 bit quanh bộ nhân GF(2^128) nên tag trùng với thư viện GCM chuẩn, giống ciphertext. `gcm_model.py` dùng `AES.MODE_GCM` trực tiếp.
- **Ảnh 16-bit, 32-bit và float được co về 8-bit.** Dữ liệu số nguyên trong khoảng 0–65535 chia theo thang 16-bit, float trong khoảng 0–1 giữ nguyên độ sáng. Các khoảng khác được giãn theo giá trị nhỏ nhất và lớn nhất của ảnh. Ảnh có `NaN` hoặc vô cực bị từ chối.
- **TIFF nhiều trang chỉ lấy trang đầu.**
- **Khúc 240 byte chưa chạy trên board.** Vector lớn nhất đã kiểm thử là 64 byte. Nếu board gặp lỗi, dùng `--chunk-blocks 4`.

## Tốc độ truyền dự kiến

Đây là **số tính toán, chưa đo trên board**, giả định khúc 240 byte và FTDI latency timer 1 ms.

| Ảnh gray 8-bit | Số khúc | 115200 | 921600 | 2 Mbaud |
|---|---|---|---|---|
| 64×64 | 18 | 0,9 s | 0,2 s | 0,1 s |
| 128×128 | 69 | 3,3 s | 0,6 s | 0,4 s |
| 256×256 | 274 | 13,2 s | 2,4 s | 1,5 s |
| 512×512 | 1093 | 52,8 s | 9,5 s | 6,1 s |

Khuyến nghị dùng 256×256 ở 921600 baud, hoặc 128×128 nếu giữ bitstream 115200.

- **Latency timer:** mặc định 16 ms, làm chậm gần gấp đôi ở 115200. Đổi trong Device Manager > Port Settings > Advanced.
- **Baud rate:** ở clock 50 MHz, 1 Mbaud và 2 Mbaud chia chẵn. Tránh 3 Mbaud vì sai số 4,2%.

## Kiểm thử

Chạy từ thư mục gốc của repo:

```bash
pytest image_process/tests
```
