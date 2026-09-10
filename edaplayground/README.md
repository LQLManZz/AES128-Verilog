# EDA Playground Simulation Guide

Thư mục này chứa các file RTL và Testbench độc lập hoàn toàn (All-in-One Standalone) để bạn có thể sao chép trực tiếp lên [EDA Playground](https://www.edaplayground.com/) hoặc chạy mô phỏng nhanh bằng 1 câu lệnh mà không cần phụ thuộc vào bất kỳ file nào khác trong project.

---

## 1. Cấu trúc thư mục

```text
edaplayground/
|-- aes128/
|   |-- aes128_uart_wrapper.sv      # Toan bo RTL AES-128-GCM + UART (Dan vao khung 'design.sv')
|   +-- tb_aes128_uart_wrapper.sv   # Testbench tu kiem tra NIST vectors (Dan vao khung 'testbench.sv')
|-- aes256/
|   |-- aes256_uart_wrapper.sv      # Toan bo RTL AES-256-GCM + UART (Dan vao khung 'design.sv')
|   +-- tb_aes256_uart_wrapper.sv   # Testbench tu kiem tra NIST vectors (Dan vao khung 'testbench.sv')
|-- aes128_uart_wrapper.sv          # Ban sao tien loi o root thu muc
|-- aes256_uart_wrapper.sv          # Ban sao tien loi o root thu muc
|-- tb_aes128_uart_wrapper.sv       # Ban sao tien loi o root thu muc
|-- tb_aes256_uart_wrapper.sv       # Ban sao tien loi o root thu muc
+-- README.md
```

---

## 2. Hướng dẫn thiết lập trên EDA Playground

### Mô phỏng AES-128:
1. Mở [EDA Playground](https://www.edaplayground.com/).
2. Chọn công cụ mô phỏng ở khung bên trái:
   - **Simulator:** `Aldec Riviera Pro` hoặc `Synopsys VCS` hoặc `Cadence Xcelium` (khuyến nghị chọn Riviera Pro hoặc Synopsys VCS).
   - **Top entity:** Để trống hoặc đặt `tb_aes128_uart_wrapper`.
   - **Run options:** Thêm `+access+r` (nếu dùng Riviera) hoặc `-timescale=1ns/1ps`.
3. Khung **`design.sv`**: Sao chép toàn bộ nội dung file `aes128/aes128_uart_wrapper.sv`.
4. Khung **`testbench.sv`**: Sao chép toàn bộ nội dung file `aes128/tb_aes128_uart_wrapper.sv`.
5. Bấm **Run**. Kết quả PASS 100% sẽ hiển thị ở log console.

---

### Mô phỏng AES-256:
1. Tương tự, trên [EDA Playground](https://www.edaplayground.com/):
2. Khung **`design.sv`**: Sao chép toàn bộ nội dung file `aes256/aes256_uart_wrapper.sv`.
3. Khung **`testbench.sv`**: Sao chép toàn bộ nội dung file `aes256/tb_aes256_uart_wrapper.sv`.
4. Bấm **Run**.
