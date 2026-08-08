# High level Design
![[LengthBlockCTR high level.png]]

| Tín hiệu             | Hướng  | Độ rộng | Mô tả                                                            |
| :------------------- | :----- | :------ | :--------------------------------------------------------------- |
| `clk`                | Input  | 1 bit   | Xung clock                                                       |
| `reset`              | Input  | 1 bit   | Tín hiệu reset đặc biệt khi `finish_reset` hoặc `rst_n` được bật |
| `AAD_valid`          | Input  | 1 bit   | Cờ báo AAD hợp lệ                                                |
| `CT_valid`           | Input  | 1 bit   | Cờ báo Ciphertext hợp lệ                                         |
| `length_block`       | Output | 128 bit | Length Block AAD \|\| Ciphertext                                 |
| `length_block_valid` | Ouput  | 1 bit   | Cờ báo Length Block hợp lệ                                       |
# Low level Design
![[LengthBlockCTR low level.png]]

>[!important] Giả định rằng tất cả các AAD được truyền vào đều có 128 bit hợp lệ.
