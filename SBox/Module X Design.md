**Liên kết:** [[SBox trong mạch tổ hợp.md|Tài liệu SBox]]
## 1. Chức năng
Module thực hiện phép nhân giữa hai phần tử trong trường $GF(2^4)$.

## 2. High level Block Design
![[Module X high level.png]]

## 3. Mô tả tín hiệu
| Tín hiệu | Hướng | Độ rộng | Mô tả |
| :--- | :--- | :--- | :--- |
| `data_a` | Input | 4 bit | Phần tử thứ nhất trong $GF(2^4)$ |
| `data_b` | Input | 4 bit | Phần tử thứ hai trong $GF(2^4)$ |
| `data_out` | Output | 4 bit | Kết quả $data\_a \times data\_b$ trong $GF(2^4)$ |

## 4. Đặc điểm thiết kế
- Triển khai thuật toán nhân trong trường hữu hạn $GF(2^4)$.
- Tối ưu hóa cho diện tích và tốc độ thông qua mạch tổ hợp.
