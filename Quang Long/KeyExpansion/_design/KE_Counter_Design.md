# High level Design
![[../../_media/KECounter High.png]]

| Tín hiệu           | Hướng  | Độ rộng | Mô tả                                                     |
| :----------------- | :----- | :------ | :-------------------------------------------------------- |
| `clk`              | Input  | 1 bit   | Xung clock                                                |
| `rst_n`            | Input  | 1 bit   | Reset (tích cực thấp)                                     |
| `expansion_en`     | Input  | 1 bit   | Lệnh bắt đầu đếm                                          |
| `first_rkey`       | Output | 1 bit   | Báo hiệu vòng đầu tiên, cho `cipher_key` đi vào sinh khóa |
| `round_index`      | Output | 4 bit   | Chỉ số vòng                                               |
| `expansion_finish` | Output | 1 bit   | Báo hiệu hoàn tất quá trình mở rộng                       |
# Low level Design
![[../../_media/KECounter Low.png]]
