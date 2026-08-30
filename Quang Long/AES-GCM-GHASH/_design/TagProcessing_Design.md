# High level Design
![[TagProcessing high level.png]]

| Tín hiệu            | Hướng  | Độ rộng | Mô tả                                                           |
| :------------------ | :----- | :------ | :-------------------------------------------------------------- |
| `clk`               | Input  | 1 bit   | Xung clock                                                      |
| `rst_n`             | Input  | 1 bit   | Tín hiệu reset mức thấp                                         |
| `finish_reset`      | Input  | 1 bit   | Tín hiệu reset khi khối AES-CTR hoàn thành quá trình            |
| `load_key`          | Input  | 1 bit   | Cờ báo có Cipherkey mới đi vào                                  |
| `mode`              | Input  | 1 bit   | Lựa chọn giữa chế độ mã hóa hoặc giải mã                        |
| `AAD`               | Input  | 128 bit | Dữ liệu vào (AAD)                                               |
| `CT`                | Input  | 128 bit | Dữ liệu vào (Ciphertext)                                        |
| `tag_ref`           | Input  | 128 bit | Tag tham chiếu, dùng cho chế độ giải mã                         |
| `H`                 | Input  | 128 bit | Khóa $H=AES_{K}(0)$                                             |
| `E`                 | Input  | 128 bit | Khóa $E=AES_{K}(J_{0})$                                         |
| `load_AAD`          | Input  | 1 bit   | Cờ báo AAD hợp lệ                                               |
| `load_CT`           | Input  | 1 bit   | Cờ báo Ciphertext hợp lệ                                        |
| `H_valid`           | Input  | 1 bit   | Cờ báo khóa $H$ hợp lệ                                          |
| `E_valid`           | Input  | 1 bit   | Cờ báo khóa $E$ hợp lệ                                          |
| `load_tag_ref`      | Input  | 1 bit   | Cờ báo `tag_ref` hợp lệ                                         |
| `CT_last`           | Input  | 1 bit   | Cờ báo Ciphertext cuối cùng                                     |
| `H_loaded`          | Output | 1 bit   | Cờ báo đã hoàn tất load khóa $H$                                |
| `tag_ref_loaded`    | Output | 1 bit   | Cờ báo đã hoàn tất load Tag Reference                           |
| `tag`               | Output | 128 bit | Authentication Tag                                              |
| `tag_process_valid` | Output | 1 bit   | Báo hiệu đã hoàn tất quá trình sinh Tag, dùng cho chế độ mã hóa |
| `verify_pass`       | Output | 1 bit   | Cờ báo Tag hợp lệ, dùng cho chế độ giải mã                      |
