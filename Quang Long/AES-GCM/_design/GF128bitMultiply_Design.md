# High level Design
![[Module X128 high level.png]]

| Tín hiệu   | Hướng  | Độ rộng | Mô tả                                                 |
| :--------- | :----- | :------ | :---------------------------------------------------- |
| `data_in`  | Input  | 128 bit | Dữ liệu vào để thực hiện phép nhân trên $GF(2^{128})$ |
| `H`        | Input  | 128 bit | Khóa $H=AES(K,0)$                                     |
| `data_out` | Output | 128 bit | Kết quả thực hiện phép nhân trên trường $GF(2^{128})$ |
# Low level Design
![[Module X128 low level.png]]
