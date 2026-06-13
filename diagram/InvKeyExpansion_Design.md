# Module InvKeyExpansion Top Design

**Liên kết:** [[Inverted Key Expansion.md|Tài liệu thuật toán]] | [[RotWord_Design.md|Thiết kế RotWord]] | [[SubWord_Design.md|Thiết kế SubWord]] | [[InvRcon_Design.md|Thiết kế InvRcon]]

## 1. Chức năng
Module quản lý toàn bộ quá trình tính ngược khóa vòng (AES-128) phục vụ cho giải mã.

## 2. High level Block Design
![[InvKeyExpansionTop.png]]

## 3. Mô tả tín hiệu
| Tín hiệu         | Hướng  | Độ rộng | Mô tả                                           |
| :--------------- | :----- | :------ | :---------------------------------------------- |
| `clk`            | Input  | 1 bit   | Xung clock hệ thống                             |
| `rst_n`          | Input  | 1 bit   | Reset hệ thống (tích cực thấp)                  |
| `start`          | Input  | 1 bit   | Lệnh bắt đầu tính toán                          |
| `curr_round_key` | Input  | 128 bit | Khóa vòng hiện tại                              |
| `round_idx`      | Input  | 4 bit   | Chỉ số vòng (để xác định hằng số Rcon cần dùng) |
| `prev_round_key` | Output | 128 bit | Khóa vòng trước đó                              |
| `ready`          | Output | 1 bit   | Báo hiệu hoàn tất quá trình tính toán           |

## 4. Mô tả vận hành
1. **Khởi tạo:** Chờ tín hiệu `start` và nạp `curr_round_key`.
2. **Chu kỳ tính ngược:**
    - Tính các word trung gian: $W_{n-1}[0], W_{n-1}[1], W_{n-1}[2]$ bằng phép XOR tuyến tính.
    - Tính word phi tuyến $W_{n-1}[3]$ bằng cách sử dụng $SubWord(RotWord(W_{n-1}[0])) \oplus InvRcon$ và XOR với $W_n[3]$.
3. **Kết thúc:** Xuất `prev_round_key` và bật tín hiệu `ready`.
