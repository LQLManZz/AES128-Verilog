**Liên kết:** [[SBox trong mạch tổ hợp|Tài liệu SBox]]
## 1. Chức năng
Module thực hiện phép nhân giữa hai phần tử trong trường $GF(2^4)$.

## 2. High level Block Design
![[Module X high level.png]]

## 3. Mô tả tín hiệu
| Tín hiệu   | Hướng  | Độ rộng | Mô tả                            |
| :--------- | :----- | :------ | :------------------------------- |
| `data_in1` | Input  | 4 bit   | Phần tử thứ nhất trong $GF(2^4)$ |
| `data_in2` | Input  | 4 bit   | Phần tử thứ hai trong $GF(2^4)$  |
| `data_out` | Output | 4 bit   | Kết quả nhân trong $GF(2^4)$     |
## 4. Low level Block Design
![[Module X low level.png]]
