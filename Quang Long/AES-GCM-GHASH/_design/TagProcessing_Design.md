# High level Design
![[TagProcessing high level.png]]

| Tín hiệu       | Hướng  | Độ rộng | Mô tả                                                |
| :------------- | :----- | :------ | :--------------------------------------------------- |
| `clk`          | Input  | 1 bit   | Xung clock                                           |
| `load`         | Input  | 1 bit   | Khởi tạo giá trị ban đầu                             |
| `ghash_en`     | Input  | 1 bit   | Lệnh bắt đầu tạo khóa băm GHASH                      |
| `data_in`      | Input  | 128 bit | Dữ liệu vào (AAD, Ciphertext, Length Block)          |
| `H_key`        | Input  | 128 bit | Khóa $H=AES(K,0)$                                    |
| `ghash_out`    | Output | 128 bit | Khóa băm GHASH sau khi nhận khối `data_in` cuối cùng |
| `ghash_finish` | Output | 1 bit   | Báo hiệu đã hoàn tất quá trình băm                   |
# FSM 
![[TagProcessing FSM.png]]
# Low level Design 
![[TagProcessing FSM low level.png]]
