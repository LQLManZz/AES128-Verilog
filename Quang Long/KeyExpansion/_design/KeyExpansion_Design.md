# Module KeyExpansion High Level

**Liên kết:** [[../Key Expansion.md|Tài liệu thuật toán]] | [[RotWord_Design.md|Thiết kế RotWord]] | [[SubWord_Design.md|Thiết kế SubWord]] | [[AddRcon_Design.md|Thiết kế Rcon]] | [[../../_media/Module AddRoundKey high level.png|Thiết kế AddRoundKey]]

## 1. Chức năng
Module quản lý toàn bộ quá trình mở rộng khóa (AES-128).

## 2. Top-level Block Design
![[../../_media/Module Key Expansion high level.png]]

## 3. Mô tả tín hiệu
| Tín hiệu           | Hướng  | Độ rộng | Mô tả                                       |
| :----------------- | :----- | :------ | :------------------------------------------ |
| `clk`              | Input  | 1 bit   | Xung clock                                  |
| `rst_n`            | Input  | 1 bit   | Reset (tích cực thấp)                       |
| `expansion_en`     | Input  | 1 bit   | Lệnh bắt đầu sinh khóa                      |
| `cipher_key`       | Input  | 128 bit | Khóa gốc ban đầu                            |
| `round_key`        | Output | 128 bit | Số khóa vòng tương ứng với ma trận `[0:10]` |
| `expansion_finish` | Output | 1 bit   | Báo hiệu hoàn tất quá trình sinh khóa       |
# Module KeyExpansion Low Level

![[../../_media/AESKeyExpansionLowDes.png]]
![[../../_media/KECounter Low.png]]

- [[KE_Counter_Design.md|Thiết kế bộ đếm Counter]] 
