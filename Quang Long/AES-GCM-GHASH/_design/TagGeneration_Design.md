# High level Design
![[../../_media/TagGen high level.png]]

| Tín hiệu    | Hướng  | Độ rộng | Mô tả                              |
| :---------- | :----- | :------ | :--------------------------------- |
| `ghash_out` | Input  | 128 bit | Khóa băm cuối cùng ở module GHASH  |
| `E_key`     | Input  | 128 bit | Khóa $E=AES(K,J_{0})$              |
| `tag`       | Output | 128 bit | Authentication Tag (Nhãn xác thực) |
# Low level Design
![[../../_media/TagGen low level.png]]
