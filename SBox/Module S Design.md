**Liên kết:** [[SBox trong mạch tổ hợp|Tài liệu SBox]]

## 1. Chức năng
Module thực hiện phép tính bình phương (Square) trong trường $GF(2^4)$. Đây là một thành phần trong quá trình tính nghịch đảo nhân $GF(2^8)$.

## 2. High level Block Design
![[Module S high level.png]]

## 3. Mô tả tín hiệu
| Tín hiệu   | Hướng  | Độ rộng | Mô tả                                      |
| :--------- | :----- | :------ | :----------------------------------------- |
| `data_in`  | Input  | 4 bit   | Dữ liệu đầu vào trong trường $GF(2^4)$     |
| `data_out` | Output | 4 bit   | Kết quả bình phương trong trường $GF(2^4)$ |

