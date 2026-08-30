# High level Design
![[LengthBlockCTR high level.png]]

| Tín hiệu             | Hướng  | Độ rộng | Mô tả                                     |
| :------------------- | :----- | :------ | :---------------------------------------- |
| `clk`                | Input  | 1 bit   | Xung clock                                |
| `finish_reset`       | Input  | 1 bit   | Tín hiệu reset đặc biệt, tích cực mức cao |
| `load_AAD`           | Input  | 1 bit   | Cờ báo AAD hợp lệ                         |
| `load_CT`            | Input  | 1 bit   | Cờ báo Ciphertext hợp lệ                  |
| `CT_last`            | Input  | 1 bit   | Cờ báo Ciphertext cuối cùng               |
| `length_block`       | Output | 128 bit | Length Block AAD \|\| Ciphertext          |
| `length_block_valid` | Output | 1 bit   | Cờ báo Length Block hợp lệ                |
# Low level Design
![[LengthBlockCTR low level.png]]

>[!important] Giả định rằng tất cả các AAD được truyền vào đều có 128 bit hợp lệ.
