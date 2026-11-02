# Kế hoạch thiết kế lại menu, tập trung UART 12 Mbaud (2026-11-03)

Trạng thái: **xong 03/11/2026, chờ đo trên kit**. Bản sao trước khi sửa: `../backups/realtime_env_2026-11-03_pre_menu_redesign/` (ngoài realtime_env để pytest không gom nhầm).

## Quyết định đã chốt

| Mục | Quyết định |
|---|---|
| Kiểu menu | Ít chữ, chỉ hỏi điều cần chọn hoặc nhập, mặc định UART 12 Mbaud |
| Mở khoá | `--advanced`, khoá cả menu lẫn dòng lệnh |
| Menu chính | `1 Camera   2 Img   3 Raw text   0 Exit`, thêm `4 Self-test NIST` khi `--advanced` |
| Chạy trên | `[1 FPGA, 2 Sim]`, `--advanced` mở thêm giả lập emu và RTL |
| Sau khi chạy | Quay lại menu |
| Key, IV | Nhập mỗi lần, chặn lặp lại cặp key + IV trong cùng phiên |
| Bộ đệm camera | Cố định 2 khung, bỏ `--buffer-frames` |
| Codec camera | H.264 mặc định (x264 ultrafast, zerolatency, không B-frame, intra-refresh, khung I khi lỗi tag), JPEG dự phòng qua `--advanced --codec jpeg` |
| Chất lượng | Thang 1..100, mặc định 70, quy đổi sang CRF cho H.264 |
| Cửa sổ camera | 4 ô: Xử lý, Trễ p95, Thông lượng, Tag |
| `uart_client.py` | Bỏ menu cũ, self-test chuyển sang `main.py --advanced selftest` |
| Log | `logs/<thời gian>_<chế độ>_<link>.log` + `_frames.csv`: sự kiện, từng khung, mỗi giây, console, tổng kết. Key ghi đầy đủ, `logs/` không vào git |

## Lời nhắc

```
AES-GCM | UART 12 Mbaud | COM12 (kênh D)
 1 Camera   2 Img   3 Raw text   0 Exit
> 
Chạy trên [1 FPGA, 2 Sim] (1): 
Độ phân giải WxH (640x480): 
Chất lượng 1..100 (70): 
FPGA giải mã? y/N: 
fps tối đa (0 = camera default): 
Ảnh/thư mục: 
Kích thước WxH (256x256): 
File/Raw hex: 
Tag-Reference (trống = mã hoá): 
Cipherkey hex: 
IV hex: 
AAD hex (trống): 
Cổng COM: 
Enter để về menu 
```

## Tiến độ

- [x] 0. Lưu kế hoạch
- [x] 1. `host/run_log.py`, nối log vào mọi chế độ
- [x] 2. `host/cli.py`: `--advanced`, mặc định uart12m, `selftest`, bỏ `--buffer-frames`
- [x] 3. `host/menu.py` viết lại
- [x] 4. `host/camera.py` + `host/codec.py`: đệm 2 khung, H.264
- [x] 5. `host/camera_view.py`: ô Thông lượng, ciphertext cuộn, chờ khung I
- [x] 6. `host/uart_client.py`: bỏ menu cũ
- [x] 7. Tests (332 passed)
- [x] 8. Tài liệu
- [x] 9. Kiểm tra cuối: transcript menu thường, menu --advanced, dòng lệnh bị khoá, selftest, camera H.264 và JPEG từ video qua Sim, ảnh cửa sổ docs/camera_window_h264*.png
