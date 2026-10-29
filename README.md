# AES-GCM IP Core (SystemVerilog)

IP phần cứng **AES-GCM** hiệu năng cao dùng kiến trúc pipeline, cung cấp đồng thời **mã hóa** và **xác thực toàn vẹn dữ liệu** theo chuẩn NIST SP 800-38D. Dự án gồm hai biến thể **AES-128-GCM** và **AES-256-GCM**, được phát triển bởi nhóm **VLATsemi** (Trường Đại học Bách Khoa – Đại học Đà Nẵng)

[Tính năng](#tính-năng) · [Thành tựu](#thành-tựu) · [Cấu trúc thư mục](#cấu-trúc-thư-mục) · [Mô phỏng](#mô-phỏng) · [Tài liệu](#tài-liệu) · [Nhóm thực hiện](#nhóm-thực-hiện)

## Tính năng

- Xử lý khối dữ liệu 128 bit, khóa 128/256 bit, IV 96 bit, Authentication Tag 128 bit.
- Hỗ trợ cả mã hóa và giải mã; giải mã có cờ `verify_pass` để phát hiện dữ liệu bị giả mạo.
- AES-CTR pipeline, thông lượng 1 block/chu kỳ clock.
- GHASH với bộ nhân $GF(2^{128})$ kiểu Karatsuba phân cấp, hoàn thành trong 1 chu kỳ.
- S-Box tối ưu diện tích bằng số học trường phức hợp $GF(((2^2)^2)^2)$.
- Cơ chế tái sử dụng khóa (Key Reuse), tiết kiệm chu kỳ giữa các phiên dùng chung khóa.
- FIFO đệm có backpressure, phát hiện tràn bộ đếm CTR 32 bit, Control Unit  FSM.
- Có lớp bọc UART và script Python để chạy thử trên kit FPGA.

## Kiến trúc

```text
          ┌──────────────┐   keystream   ┌─────┐
 Key/IV ─►│ Key Expansion│──► AES-CTR ──►│ XOR │──► data_out
          └──────────────┘  (pipeline)   └──┬──┘
                                            │ Ciphertext
 AAD ─────────────────────────────┐         ▼
                                  └──► GHASH / GF(2^128) ──► Tag ──► verify_pass
                                       (Tag Processing)
                      Control Unit (FSM) điều phối toàn bộ luồng
```

## Thành tựu

**ASIC (Nangate 45nm, OpenROAD Flow Scripts, RTL-to-GDSII)**

| Chỉ số                        | Final                                    |
| ----------------------------- | ---------------------------------------- |
| Tần số mục tiêu               | **400 MHz** (Fmax sau layout: 401.6 MHz) |
| Thông lượng                   | **51.2 Gbps**                            |
| Diện tích khuôn chip          | **294,784 µm² (0.295 mm²)**              |
| Mật độ lõi (core utilization) | **50.1%**                                |
| Setup / Hold WNS              | +0.010 ns / +0.045 ns                    |
| DRC / LVS                     | **0 lỗi (383 rules) / trùng khớp**       |

- Timing closure 100%, GDSII (`6_final.gds`) sẵn sàng tape-out.
- Diện tích silicon giảm 21.6% so với baseline; diện tích logic khoảng 186.6 kGE.

**FPGA (PolarFire SoC Discovery Kit MPFS095T)**: 50 MHz, 35,897 LUTs, 8,233 FFs, thông lượng 6.4 Gbps.

**Kiểm chứng (C golden model qua DPI-C)**

- 14 kịch bản kiểm thử: vector NIST SP 800-38D (TC14, TC16), mã hóa/giải mã liên tiếp, tấn công giả mạo Tag/Ciphertext, Key Reuse, backpressure, tràn counter, reset bất đồng bộ, lan truyền trạng thái X.
- 32/32 giao dịch PASS, 0 mismatch.
- 100% functional coverage, cross coverage và FSM state coverage (11/11 trạng thái); 0 vi phạm SVA.

## Mô phỏng

Dùng EDA Playground: chi tiết xem [`edaplayground/README.md`](edaplayground/README.md).

Để mô phỏng từng khối, biên dịch các file trong `RTL/` cùng testbench tương ứng bằng trình mô phỏng hỗ trợ SystemVerilog (đã kiểm chứng trên QuestaSim).

## Tài liệu

- [Báo cáo khoa học và báo cáo sản phẩm](docs/)
- [Giao thức UART](uart_integration/docs/protocol.md) và [hướng dẫn tích hợp](uart_integration/docs/integration_guide.md)
- Tiêu chuẩn tham chiếu trong [`References/`](References/)

## Nhóm thực hiện

**VLATsemi** – Trường Đại học Bách Khoa – Đại học Đà Nẵng

| Thành viên | Vai trò |
|---|---|
| Châu Quốc Tuấn (nhóm trưởng) | Design Verification |
| Lê Quốc Việt | RTL Design |
| Lê Quang Long | RTL Design |
| Trần Tuấn Anh | Synthesis & STA |
