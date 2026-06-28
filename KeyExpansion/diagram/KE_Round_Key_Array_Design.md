# High level Design 
![[KErkArray High.png]]

| Tín hiệu       | Hướng  | Độ rộng | Mô tả                                                          |
| :------------- | :----- | :------ | :------------------------------------------------------------- |
| `clk`          | Input  | 1 bit   | Xung clock                                                     |
| `rst_n`        | Input  | 1 bit   | Reset (tích cực thấp)                                          |
| `expansion_en` | Input  | 1 bit   | Lệnh bắt đầu ghi vào thanh ghi                                 |
| `cipher_key`   | Input  | 128 bit | Khóa gốc ban đầu                                               |
| `round_index`  | Input  | 4 bit   | Chỉ số vòng                                                    |
| `rkey`         | Output | 128 bit | Khóa vòng tương ứng với `round_index` để ghi vào tệp thanh ghi |
| `round_key`    | Output | 128 bit | Khóa vòng cần lấy ra                                           |
# Low level Design
![[KErkArray Low.png]]
