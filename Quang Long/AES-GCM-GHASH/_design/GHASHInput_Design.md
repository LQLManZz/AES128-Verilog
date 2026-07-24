# High level Design
![[GHASHInput high level.png]]

| Tín hiệu    | Hướng  | Độ rộng | Mô tả                                                 |
| :---------- | :----- | :------ | :---------------------------------------------------- |
| `clk`       | Input  | 1 bit   | Xung clock                                            |
| `rst`       | Input  | 1 bit   | Khởi tạo giá trị ban đầu                              |
| `mode`      | Input  | 1 bit   | Lựa chọn chế độ mã hóa hoặc giải mã                   |
| `data_type` | Input  | 2 bit   | Chọn loại dữ liệu vào (AAD, Ciphertext, Length Block) |
| `AAD_block` | Input  | 128 bit | Dữ liệu AAD                                           |
| `AAD_valid` | Input  | 1 bit   | Cờ báo AAD hợp lệ                                     |
| `CTR_CT`    | Input  | 128 bit | Dữ liệu Ciphertext lấy từ CTR khi mã hóa              |
| `FIFO_CT`   | Input  | 128 bit | Dữ liệu Ciphertext lấy từ FIFO khi giải mã            |
| `CT_valid`  | Input  | 1 bit   | Cờ báo Ciphertext hợp lệ                              |
| `data_in`   | Output | 128 bit | Dữ liệu đầu vào của GHASH                             |
# Low level Design 
![[GHASHInput low level.png]]
