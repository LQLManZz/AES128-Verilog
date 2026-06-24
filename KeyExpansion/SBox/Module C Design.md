**Liên kết:** [[SBox trong mạch tổ hợp|Tài liệu SBox]]

## 1. Chức năng
Module thực hiện phép nhân với hằng số $\lambda$ trong trường $GF(2^4)$. Đây là hằng số được sử dụng để hạ bậc từ $GF(2^8)$ xuống $GF(2^4)$.

## 2. High level Block Design
![[Module C high level.png]]

## 3. Mô tả tín hiệu
| Tín hiệu | Hướng | Độ rộng | Mô tả |
| :--- | :--- | :--- | :--- |
| `data_in` | Input | 4 bit | Dữ liệu đầu vào trong trường $GF(2^4)$ |
| `data_out` | Output | 4 bit | Kết quả sau khi nhân với hằng số $\lambda$ |
## 4. Low level Block Design
![[Module C low level.png]]
