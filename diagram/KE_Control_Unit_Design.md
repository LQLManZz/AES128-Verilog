# CU FSM
![[AESKeyExpansion-CU_FSM.png]]

| Trạng thái        | Mô tả                                                                                 |
| :---------------- | :------------------------------------------------------------------------------------ |
| `IDLE`            | Khi không có tín hiệu `expansion_en` và `expansion_finish` được trả về 0              |
| `LOAD_CIPHER_KEY` | Nhận tín hiệu `expansion_en`, nạp cipher key vào mảng W thành `Word[0]` đến `Word[3]` |
| `KEY_EXPAND`      | Bắt đầu quá trình sinh khóa, tạo bộ đếm `cnt`, duy trì đến khi `cnt = 39`             |
| `FINISH`          | Kết thúc quá trình sinh khóa, trả về tín hiệu `expansion_finish`                      |

# CU High level Design
![[AESKeyExpansion-CU_High.png]]

| Tín hiệu           | Hướng  | Độ rộng | Mô tả                                 |
| :----------------- | :----- | :------ | :------------------------------------ |
| `clk`              | Input  | 1 bit   | Xung clock hệ thống                   |
| `rst_n`            | Input  | 1 bit   | Reset hệ thống (tích cực thấp)        |
| `expansion_en`     | Input  | 1 bit   | Lệnh bắt đầu sinh khóa                |
| `expansion_finish` | Output | 1 bit   | Báo hiệu hoàn tất quá trình sinh khóa |
| `round_index`      | Output | 4 bit   | Cho biết số vòng hiện tại             |
| `first_round_key`  | Output | 1 bit   | Báo hiệu vòng đầu tiên của sinh khóa  |
| `round_first_word` | Output | 1 bit   | Báo hiệu word đầu tiên của một khóa   |

# CU Low level Design
![[AESKeyExpansion-CU_Low.png]]