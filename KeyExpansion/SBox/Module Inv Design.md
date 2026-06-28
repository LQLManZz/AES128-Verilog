**Liên kết:** [[SBox trong mạch tổ hợp|Tài liệu SBox]]

## 1. Chức năng
Module thực hiện tính nghịch đảo nhân trong trường $GF(2^4)$.

## 2. High level Block Design
![[Module Inv high level.png]]

## 3. Mô tả tín hiệu
| Tín hiệu   | Hướng  | Độ rộng | Mô tả                                         |
| :--------- | :----- | :------ | :-------------------------------------------- |
| `data_in`  | Input  | 4 bit   | Phần tử đầu vào trong $GF(2^4)$               |
| `data_out` | Output | 4 bit   | Nghịch đảo nhân của `data_in` trong $GF(2^4)$ |
## 4. Low level Block Design
![[Module Inv low level.png]]
