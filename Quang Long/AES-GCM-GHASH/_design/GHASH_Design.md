# High level Design
![[../../_media/GHASH high level.png]]

| Tín hiệu             | Hướng  | Độ rộng | Mô tả                                     |
| :------------------- | :----- | :------ | :---------------------------------------- |
| `clk`                | Input  | 1 bit   | Xung clock                                |
| `finish_reset`       | Input  | 1 bit   | Tín hiệu reset đặc biệt, tích cực mức cao |
| `AAD`                | Input  | 128 bit | Dữ liệu vào (AAD)                         |
| `AAD_valid`          | Input  | 1 bit   | Cờ báo AAD hợp lệ                         |
| `CT`                 | Input  | 128 bit | Dữ liệu vào (Ciphertext)                  |
| `CT_valid`           | Input  | 1 bit   | Cờ báo Ciphertext hợp lệ                  |
| `length_block`       | Input  | 128 bit | Dữ liệu vào (Length Block)                |
| `length_block_valid` | Input  | 1 bit   | Cờ báo Length Block hợp lệ                |
| `H_reg`              | Input  | 128 bit | Khóa $H=AES(K,0)$                         |
| `ghash_out`          | Output | 128 bit | Kết quả băm GHASH                         |
| `ghash_finish`       | Output | 1 bit   | Cờ báo kết quả băm GHASH cuối cùng        |
# Low level Design 
![[../../_media/GHASH low level.png]]
