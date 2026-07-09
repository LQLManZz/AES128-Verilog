# High level Design
![[../../_media/Module X128 high level.png]]

| Tín hiệu    | Hướng  | Độ rộng | Mô tả                                       |
| :---------- | :----- | :------ | :------------------------------------------ |
| `clk`       | Input  | 1 bit   | Xung clock                                  |
| `rst_n`     | Input  | 1 bit   | Reset (tích cực thấp)                       |
| `ghash_en`  | Input  | 1 bit   | Lệnh bắt đầu tạo GHASH                      |
| `data_in`   | Input  | 128 bit | Dữ liệu vào (AAD, Ciphertext, Length Block) |
| `H`         | Input  | 128 bit | Khóa $H=AES(K,0)$                           |
| `ghash_out` | Output | 128 bit | GHASH đầu ra                                |
# Low level Design

