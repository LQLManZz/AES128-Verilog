# High level Block Design
![[256 AESKeyExpansionTopDes.png]]
# Mô tả tín hiệu
| Tín hiệu           | Hướng  | Độ rộng | Mô tả                                       |
| :----------------- | :----- | :------ | :------------------------------------------ |
| `clk`              | Input  | 1 bit   | Xung clock                                  |
| `rst_n`            | Input  | 1 bit   | Reset (tích cực thấp)                       |
| `expansion_en`     | Input  | 1 bit   | Lệnh bắt đầu sinh khóa                      |
| `cipher_key`       | Input  | 256 bit | Khóa gốc ban đầu                            |
| `round_key`        | Output | 128 bit | Số khóa vòng tương ứng với ma trận `[0:14]` |
| `expansion_finish` | Output | 1 bit   | Báo hiệu hoàn tất quá trình sinh khóa       |
# Low level Design
![[256 AESKeyExpansionLowDes.png]]
- [[KE_Counter_Design.md|Thiết kế bộ đếm Counter]] 
