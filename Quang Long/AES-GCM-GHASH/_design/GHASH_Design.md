# High level Design
![[../../_media/GHASH high level.png]]

| Tín hiệu      | Hướng  | Độ rộng | Mô tả                                                                |
| :------------ | :----- | :------ | :------------------------------------------------------------------- |
| `clk`         | Input  | 1 bit   | Xung clock                                                           |
| `rst_n`       | Input  | 1 bit   | Reset mức thấp                                                       |
| `ghash_en`    | Input  | 1 bit   | Lệnh bắt đầu tạo khóa băm GHASH                                      |
| `data_in`     | Input  | 128 bit | Dữ liệu vào (AAD, Ciphertext, Length Block)                          |
| `H_key`       | Input  | 128 bit | Khóa $H=AES(K,0)$                                                    |
| `ghash_out`   | Output | 128 bit | Khóa băm GHASH sau khi nhận khối `data_in` cuối cùng                 |

> [!NOTE]
> Bảng trên bám theo các cổng trong hình `GHASH high level`. Tín hiệu `ghash_ready` không xuất hiện trong hình high-level hoặc low-level riêng của `GHASH`, nhưng lại được vẽ là đầu ra của `GHASH` trong hình `TagProcessing high level`; hai sơ đồ này hiện chưa thống nhất.

# Low level Design 
![[../../_media/GHASH low level.png]]
