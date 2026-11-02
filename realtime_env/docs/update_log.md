# UART Integration Revision & Update Log

---

## Update Entry: 2026-09-09 — Initial Analysis & AES-256 RTL Detection
- **Date:** 2026-09-09
- **RTL Revision Detected:** Commits `03480cb` .. `6874c9a` (AES-256-GCM Integration)
- **Changed Files:**
  - `uart_integration/docs/update_report.md` (Created)
  - `uart_integration/update_report.md` (Created)
  - `uart_integration/docs/update_log.md` (Created)
- **Reason:** Project analysis and incremental update preparation for newly added AES-256 RTL modules (`AES_256_GCM.sv`, `AES_256_CTR.sv`, `AES_256_encryption.sv`).
- **Impact Summary:**
  - Identified 2 critical defects in `RTL/AES_256_GCM.sv` (128-bit key declaration bug and module name collision with `RTL/AES_GCM.sv`).
  - Proposed multi-variant architecture.

---

## Update Entry: 2026-09-09 — Multi-Variant Architecture & RTL Bug Fixes
- **Date:** 2026-09-09
- **Changed Files:**
  - `RTL/AES_256_GCM.sv` (Corrected module name to `AES_256_GCM` and key width to `[255:0] cipher_key`)
  - `uart_integration/common/protocol_pkg.sv` (Created)
  - `uart_integration/common/uart_rx.sv` (Created)
  - `uart_integration/common/uart_tx.sv` (Created)
  - `uart_integration/common/packet_parser.sv` (Created)
  - `uart_integration/common/packet_builder.sv` (Created)
  - `uart_integration/aes128/aes128_uart_wrapper.sv` (Created)
  - `uart_integration/aes128/tb_aes128_uart_wrapper.sv` (Created)
  - `uart_integration/aes256/aes256_uart_wrapper.sv` (Created)
  - `uart_integration/aes256/tb_aes256_uart_wrapper.sv` (Created)
  - `uart_integration/python/host.py` (Updated to support `--mode aes128` and `--mode aes256`)
  - `uart_integration/docs/architecture.md` (Updated)
  - `uart_integration/docs/integration_guide.md` (Updated)
  - `uart_integration/docs/design_review_report.md` (Created)
  - `uart_integration/docs/variant_compatibility_matrix.md` (Created)
  - `uart_integration/backups/` (Created backups of previous revisions)
- **Reason:** User approval received to correct RTL defects with minimal editing and implement the scalable multi-variant integration framework.
- **RTL Revision Detected:** Corrected `RTL/AES_256_GCM.sv`.
- **Impact Summary:**
  - Both AES-128 and AES-256 hardware accelerators are fully supported with dedicated wrappers.
  - Zero code duplication achieved via shared `common/` UART infrastructure.
  - Self-checking verification environments generated for both variants against official NIST SP 800-38D test vectors.
  - Host Python client supports seamless switching between variants.

---

## Update Entry: 2026-11-03 — Menu tập trung UART 12 Mbaud, `--advanced`, H.264, log mỗi lần chạy
- **Date:** 2026-11-03
- **Kế hoạch:** `realtime_env/docs/menu_redesign_plan.md`. Bản sao trước khi sửa: `backups/realtime_env_2026-11-03_pre_menu_redesign/` ở gốc repo.
- **Changed Files:**
  - `realtime_env/host/menu.py` (viết lại: menu vòng lặp, ít chữ, UART 12 Mbaud, tự tìm kênh D, chặn lặp key + IV)
  - `realtime_env/host/cli.py` (`--advanced` khoá cả menu lẫn dòng lệnh, `--link` mặc định `uart12m`, `--quality` mặc định 70, `--codec`, lệnh `selftest`, bỏ `--buffer-frames`, log mỗi lần chạy)
  - `realtime_env/host/camera.py` (đệm cố định 2 khung, H.264, chờ khung IDR sau lỗi tag, log từng khung và mỗi giây)
  - `realtime_env/host/camera_view.py` (ô `Thông lượng` thay `Hàng đợi`, ciphertext 24 KB gần nhất, `chờ khung I`)
  - `realtime_env/host/codec.py` (Created: H.264 qua PyAV/libx264, JPEG dự phòng)
  - `realtime_env/host/run_log.py` (Created: `logs/*.log` và `*_frames.csv`)
  - `realtime_env/host/selftest.py` (Created: vector NIST dùng chung với `uart_client.py`)
  - `realtime_env/host/uart_client.py` (bỏ menu tương tác `-i`, dùng vector từ `selftest.py`)
  - `realtime_env/host/console.py`, `realtime_env/host/links.py` (chép console và sự kiện mở cổng vào log)
  - `realtime_env/tests/` (`test_menu.py` viết lại; thêm `test_codec.py`, `test_run_log.py`; các test dùng link khác hoặc giả lập thêm `--advanced`)
  - `realtime_env/requirements.txt` (thêm `av`), `realtime_env/.gitignore` (thêm `logs/`)
  - `realtime_env/README.md`, `realtime_env/INSTRUCTIONS.md`, `realtime_env/docs/integration_guide.md`
- **Reason:** Hàng đợi camera ở 12 Mbaud gần như luôn 0/30: đường truyền nhanh hơn camera, bộ đệm 15 khung chỉ làm hình trễ khoảng 0,5 s. Người dùng muốn menu đơn giản cho UART 12 Mbaud, H.264 nếu có lợi hơn JPEG, và log đầy đủ khi chạy demo trên kit.
- **Impact Summary:**
  - Không có `--advanced`, chỉ dùng được UART 12 Mbaud trên FPGA hoặc software model, với các tuỳ chọn menu thường hỏi.
  - Camera mặc định H.264 chất lượng 70 (CRF 23): ít byte hơn JPEG 5–9 lần trên clip thử; chưa đo trên kit.
  - Log ghi key ở dạng rõ theo yêu cầu; `logs/` không vào git.
  - 332 test pytest đạt.
