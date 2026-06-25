# High level Design 
![[KErkArray High.png]]

| Tín hiệu          | Hướng  | Độ rộng | Mô tả                                       |
| :---------------- | :----- | :------ | :------------------------------------------ |
| `clk`             | Input  | 1 bit   | Xung clock                                  |
| `rst_n`           | Input  | 1 bit   | Reset (tích cực thấp)                       |
| `expansion_en`    | Input  | 1 bit   | Lệnh bắt đầu ghi vào thanh ghi              |
| `cipher_key`      | Input  | 128 bit | Khóa gốc ban đầu                            |
| `rkey`            | Output | 128 bit | Số khóa vòng tương ứng với ma trận `[0:10]` |
| `round_key[0:10]` | Output | 128 bit | 10 khóa vòng được lưu trữ                   |
# Low level Design
![[KErkArray Low.png]]
