#backlink [[NIST.FIPS.197_specs.pdf]] | [[Key Expansion.md]]

Thuật toán Sinh Khóa Vòng Đảo (Inverted Key Expansion)
## 1. Một số thuật ngữ và ký hiệu sử dụng

- **InvKeyExpansion:** Quá trình tính ngược lại các khóa vòng từ khóa vòng cuối cùng (ví dụ: từ Round Key 10 về Round Key 0 trong AES-128).
- **Word (Từ):** Một chuỗi gồm 32 bit (tương đương 4 byte).
- $W_n$**:** Khóa vòng thứ $n$. Gồm 4 word $[W_n[0], W_n[1], W_n[2], W_n[3]]$.
- **Rcon (Round Constant):** Hằng số vòng dùng trong quá trình sinh khóa. Trong InvKeyExpansion, thứ tự sử dụng Rcon sẽ ngược so với KeyExpansion.

## 2. Hàm iG trong InvKeyExpansion
Quá trình tính ngược khóa sử dụng các hàm tương tự như KeyExpansion nhưng áp dụng trên các word đã được tính toán ở bước trung gian.

### 2.1. Hàm `RotWord()`
Thiết kế: [[diagram/RotWord_Design.md|Thiết kế Module RotWord]]
Thực hiện phép dịch vòng trái các byte trong một word.
$$RotWord([a_0, a_1, a_2, a_3]) = [a_1, a_2, a_3, a_0]$$

### 2.2. Hàm `SubWord()`
Thiết kế: [[diagram/SubWord_Design.md|Thiết kế Module SubWord]]
Áp dụng bảng thay thế S-Box cho từng byte của word.
$$SubWord([a_0, a_1, a_2, a_3]) = [SBox(a_0), SBox(a_1), SBox(a_2), SBox(a_3)]$$

### 2.3. Hằng số `Rcon`
Thiết kế: [[diagram/Rcon_Design.md|Thiết kế Module Rcon]]
Là module cung cấp hằng số `Rcon` tương ứng với vòng đang tính trong quá trình sinh khóa ngược. Thứ tự sử dụng Rcon sẽ ngược lại so với quá trình mã hóa.


**Bảng giá trị Rcon cho AES-128 trong quá trình InvKeyExpansion:**

| Lần tính | Khóa đích ($n-1$) | Rcon sử dụng (Hex) | Tương ứng |
| :------- | :---------------- | :----------------- | :-------- |
| 1        | Round Key 9       | `36000000`         | Rcon[10]  |
| 2        | Round Key 8       | `1b000000`         | Rcon[9]   |
| 3        | Round Key 7       | `80000000`         | Rcon[8]   |
| 4        | Round Key 6       | `40000000`         | Rcon[7]   |
| 5        | Round Key 5       | `20000000`         | Rcon[6]   |
| 6        | Round Key 4       | `10000000`         | Rcon[5]   |
| 7        | Round Key 3       | `08000000`         | Rcon[4]   |
| 8        | Round Key 2       | `04000000`         | Rcon[3]   |
| 9        | Round Key 1       | `02000000`         | Rcon[2]   |
| 10       | Cipher Key (0)    | `01000000`         | Rcon[1]   |

## 3. Thuật toán và Công thức (AES-128)
![[AESInvKeyExpansion.png]]
Để tính khóa vòng thứ $n-1$ từ khóa vòng thứ $n$ ($n \ge 1$):

1. **Tính các word trung gian:**
   - $W_{n-1}[0] = W_n[0] \oplus W_n[1]$
   - $W_{n-1}[1] = W_n[1] \oplus W_n[2]$
   - $W_{n-1}[2] = W_n[2] \oplus W_n[3]$

2. **Tính word cuối cùng ($W_{n-1}[3]$) sử dụng hàm phi tuyến:**
   - $temp = SubWord(RotWord(W_{n-1}[0])) \oplus InvRcon$
   - $W_{n-1}[3] = W_n[3] \oplus temp$

_(Lưu ý: Công thức trên dựa trên thiết kế cụ thể trong project này, nơi word 3 là MSB và word 0 là LSB của khóa vòng)._

## 4. Ví dụ minh họa (AES-128)

Giả sử ta có **Round Key 1** (từ ví dụ trong Key Expansion):
- $W_1[0] = \text{a0fafe17}$
- $W_1[1] = \text{88542cb1}$
- $W_1[2] = \text{23a33939}$
- $W_1[3] = \text{2a6c7605}$

Ta sẽ tính ngược lại **Cipher Key (Round Key 0)**:

### Bước 1: Tính các word $W_0[0], W_0[1], W_0[2]$
- $W_0[0] = W_1[0] \oplus W_1[1] = \text{a0fafe17} \oplus \text{88542cb1} = \text{28aed2a6}$
- $W_0[1] = W_1[1] \oplus W_1[2] = \text{88542cb1} \oplus \text{23a33939} = \text{abf71588}$
- $W_0[2] = W_1[2] \oplus W_1[3] = \text{23a33939} \oplus \text{2a6c7605} = \text{09cf4f3c}$

### Bước 2: Tính word cuối cùng $W_0[3]$
Sử dụng $InvRcon[10] = \text{01000000}$ cho bước tính Cipher Key từ Round Key 1:
1. Lấy $W_0[2] = \text{09cf4f3c}$ (tương ứng với word có chỉ số cao nhất trong các word vừa tính).
2. **RotWord:** `cf 4f 3c 09`
3. **SubWord:** `8a 84 eb 01`
4. **XOR với InvRcon:** `8a84eb01` $\oplus$ `01000000` = `8b84eb01`
5. **Kết quả:** $W_0[3] = W_1[0] \oplus \text{8b84eb01} = \text{a0fafe17} \oplus \text{8b84eb01} = \text{2b7e1516}$

**Kết quả thu được Cipher Key:**
`2b7e1516 28aed2a6 abf71588 09cf4f3c` (Hoàn toàn khớp với khóa ban đầu!)

## 5. Thiết kế Module
- [[diagram/InvKeyExpansion_Top_Design.md|Thiết kế Module InvKeyExpansion (Top Level)]]
- [[diagram/RotWord_Design.md|Thiết kế Module RotWord]] (Dùng chung)
- [[diagram/SubWord_Design.md|Thiết kế Module SubWord]] (Dùng chung)
- [[diagram/Rcon_Design.md|Thiết kế Module Rcon]] (Dùng chung với logic chọn chỉ số đảo)