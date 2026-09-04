# High level Design
![[256 KECounter High.png]]

| Tín hiệu           | Hướng  | Độ rộng | Mô tả                                                              |
| :----------------- | :----- | :------ | :----------------------------------------------------------------- |
| `clk`              | Input  | 1 bit   | Xung clock                                                         |
| `rst_n`            | Input  | 1 bit   | Reset (tích cực thấp)                                              |
| `expansion_en`     | Input  | 1 bit   | Lệnh bắt đầu đếm                                                   |
| `rk0`              | Output | 1 bit   | Báo hiệu vòng đầu tiên, cho `cipher_key[255:128]` đi vào sinh khóa |
| `rk1`              | Output | 1 bit   | Báo hiệu vòng thứ hai, cho `cipher_key[127:0]` đi vào sinh khóa    |
| `sub_only`         | Output | 1 bit   | Cờ chuyển sang hàm SubWord()                                       |
| `round_index`      | Output | 4 bit   | Chỉ số vòng                                                        |
| `expansion_finish` | Output | 1 bit   | Báo hiệu hoàn tất quá trình mở rộng                                |
# Low level Design
![[256 KECounter Low.png]]
