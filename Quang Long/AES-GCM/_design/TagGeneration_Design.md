# High level Design
![[../../_media/TagGen high level.png]]

| Tín hiệu    | Hướng  | Độ rộng | Mô tả                              |
| :---------- | :----- | :------ | :--------------------------------- |
| `clk`       | Input  | 1 bit   | Xung clock                         |
| `rst_n`     | Input  | 1 bit   | Reset (tích cực thấp)              |
| `tagen_en`  | Input  | 1 bit   | Lệnh bắt đầu tạo Tag               |
| `data_in`   | Input  | 128 bit | Khóa băm cuối cùng ở module GHASH  |
| `E_key`     | Input  | 128 bit | Khóa $E=AES(K,J_{0})$              |
| `tag`       | Output | 128 bit | Authentication Tag (Nhãn xác thực) |
| `tag_ready` | Output | 1 bit   | Báo hiệu hoàn tất tạo Tag          |
# Low level Design
![[../../_media/TagGen low level.png]]
