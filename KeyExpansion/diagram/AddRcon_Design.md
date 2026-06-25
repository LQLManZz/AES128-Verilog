# Module AddRcon Design

**Liên kết:** [[Key Expansion.md|Tài liệu thuật toán]] | [[Inverted Key Expansion.md|Tài liệu thuật toán đảo]] | [[KeyExpansion_Design|Thiết kế Top Level]]

## 1. Chức năng
Module `Rcon` (Round Constant) cung cấp một từ 32-bit hằng số cho mỗi vòng lặp. 
Định dạng: `Rcon[i] = [RC[i], 8'h00, 8'h00, 8'h00]`.

## 2. Top-level Block Design
![[Module RCon high level.png]]
## 3. Mô tả tín hiệu
| Tín hiệu      | Hướng  | Độ rộng | Mô tả                        |
| :------------ | :----- | :------ | :--------------------------- |
| `round_index` | Input  | 4 bit   | Chỉ số vòng lặp              |
| `word_in`     | Input  | 32 bit  | Word cần được XOR với Rcon   |
| `word_out`    | Output | 32 bit  | Kết quả sau khi XOR với Rcon |

## 4. Bảng giá trị RC (Hex)
| Round | round_index | RC [i] | Rcon [i] |
| :---- | ----------- | :----- | :------- |
| 1     | `4'd0`      | 01     | 01000000 |
| 2     | `4'd1`      | 02     | 02000000 |
| 3     | `4'd2`      | 04     | 04000000 |
| 4     | `4'd3`      | 08     | 08000000 |
| 5     | `4'd4`      | 10     | 10000000 |
| 6     | `4'd5`      | 20     | 20000000 |
| 7     | `4'd6`      | 40     | 40000000 |
| 8     | `4'd7`      | 80     | 80000000 |
| 9     | `4'd8`      | 1B     | 1B000000 |
| 10    | `4'd9`      | 36     | 36000000 |
## 5. Low-level Block Design
![[Module RCon low level.png]]