#backlink [[NIST.FIPS.197_specs.pdf]] | [[Inverted Key Expansion.md]]
[Link video ví dụ](https://www.youtube.com/watch?v=gP4PqVGudtg)
Thuật toán Sinh Khóa Vòng (Key Expansion)
## 1. Một số thuật ngữ và ký hiệu sử dụng

- **Word (Từ):** Một chuỗi gồm 32 bit (tương đương 4 byte), tương ứng với các cột của State Block. Quá trình sinh khóa của AES hoạt động chủ yếu trên các word.
- **Cipher Key (**$K$**):** Khóa bí mật ban đầu do người dùng cung cấp, thường được tạo ra bởi các cơ chế đặc thù. Độ dài của $K$ có thể là 128, 192 hoặc 256 bit.
- **Round Key:** Khóa vòng, được trích xuất từ mảng khóa mở rộng. Mỗi Khóa vòng luôn có kích thước 128 bit (tương đương 4 word).
- $N_k$**:** Số lượng word của Khóa mật mã ban đầu.
    - AES-128: $N_k = 4$  
    - AES-192: $N_k = 6$  
    - AES-256: $N_k = 8$  
- $N_r$**:** Số lượng vòng lặp (Rounds) tương ứng với độ dài khóa.
    - AES-128: $N_r = 10$  
    - AES-192: $N_r = 12$  
    - AES-256: $N_r = 14$  
- $N_b$**:** Kích thước khối dữ liệu (State Block size) tính bằng word. Với chuẩn AES, $N_b$ luôn luôn bằng $4$ (128 bit).
- **Mảng** $W$**:** Mảng tuyến tính chứa các word của khóa sau khi mở rộng. Tổng số word cần thiết lập là $N_b \times (N_r + 1)$. Ví dụ: AES-128 cần $4 \times 11 = 44$ words (từ $W[0]$ đến $W[43]$).
## 2. Hàm G trong Key Expansion
Để đảm bảo tính phi tuyến tính và chống lại các rủi ro thám mã, thuật toán sinh khóa sử dụng hàm G gồm 3 hàm con tác động lên một word 4-byte $[a_0, a_1, a_2, a_3]$:
### 2.1. Hàm `RotWord()`

Thực hiện phép dịch vòng trái các byte trong một word.
$$RotWord([a_0, a_1, a_2, a_3]) = [a_1, a_2, a_3, a_0]$$
### 2.2. Hàm `SubWord()`
Nhận đầu vào là một word 4-byte và áp dụng độc lập bảng thay thế S-Box của AES cho từng byte để tạo ra một word mới. Đây là bước cung cấp tính phi tuyến cho khóa.
$$SubWord([a_0, a_1, a_2, a_3]) = [SBox(a_0), SBox(a_1), SBox(a_2), SBox(a_3)]$$
[Tra cứu bảng SBox](https://docs.google.com/spreadsheets/d/1B7bFCWHM951GlbzD5aeAdbtgTKTDbiDaLbq5svjwcV0/edit?usp=sharing)
![[SBox.png|624]]
Để tối ưu về mặt tài nguyên, cần thực hiện việc tra cứu SBox thông qua phương pháp mạch tổ hợp:
[[SBox trong mạch tổ hợp]]
### 2.3. Mảng hằng số `Rcon[]` (Round Constant)
Là một mảng các word hằng số, được sử dụng để loại bỏ tính đối xứng trong quá trình sinh khóa. Giá trị của `Rcon` tại chỉ số $i$ được định nghĩa:
$$Rcon[i] = [RC_i, 00, 00, 00]$$
#### 2.3.1. Cách tính $RC_i$ bằng toán học trong trường GF($2^8$)
Thay vì phải lưu trữ cả một bảng hằng số, $RC_i$ thực chất được tính đệ quy dựa trên quy tắc nhân với đa thức $x$ (có giá trị Hex tương ứng là `02`) trong trường Galois hữu hạn GF($2^8$). Đa thức bất khả quy (irreducible polynomial) tiêu chuẩn của hệ mã hóa AES là $m(x) = x^8 + x^4 + x^3 + x + 1$ (tương đương với giá trị Hex `11B`).

**Công thức tổng quát:**

- $RC_1 = \text{01}$  
- $RC_i = \text{02} \bullet RC_{i-1}$ (với $i > 1$)

**Quy tắc thao tác bit (Bitwise) cực nhanh để thực hiện phép nhân với `02`:**

Giả sử ta cần tính giá trị $\text{02} \bullet Y$:

1. Dịch trái $Y$ đi 1 bit (Tương đương `Y << 1`).
    
2. **Nếu bit cao nhất của** $Y$ **(trước khi dịch) là `0`:** Kết quả chính là giá trị thu được ở bước 1.
    
3. **Nếu bit cao nhất của** $Y$ **(trước khi dịch) là `1`** (tức là $Y \ge \text{80}$ trong mã Hex): Ta lấy kết quả của bước 1 thực hiện phép toán XOR với `1B` (Đây là phần dư của đa thức $m(x)$).
    

**Ví dụ minh họa chi tiết:**

- **Tính** $RC_8$ **từ** $RC_7$**:** Biết $RC_7 = \text{40}$ (Hệ nhị phân: `0100 0000`). Bit cao nhất là `0`.
    
    - Dịch trái 1 bit: `1000 0000` (Hex: $\text{80}$).
        
    - Vậy $RC_8 = \text{80}$.
        
- **Tính** $RC_9$ **từ** $RC_8$**:** Biết $RC_8 = \text{80}$ (Hệ nhị phân: `1000 0000`). **Bit cao nhất là `1`**.
    
    - Dịch trái 1 bit: `0000 0000` (Bị tràn bit thứ 8).
        
    - Vì bit cao nhất ban đầu là `1`, ta bù lại bằng cách lấy `0000 0000` $\oplus$ `0001 1011` (chính là số `1B` Hex).
        
    - Kết quả: `0001 1011` (Hex: $\text{1B}$). Vậy $RC_9 = \text{1B}$.
        
- **Tính** $RC_{10}$ **từ** $RC_9$**:** Biết $RC_9 = \text{1B}$ (Hệ nhị phân: `0001 1011`). Bit cao nhất là `0`.
    
    - Dịch trái 1 bit: `0011 0110` (Hex: $\text{36}$).
        
    - Vậy $RC_{10} = \text{36}$.
        
Chính quy luật "cắt ngọn và XOR với `1B`" này khiến cho các hằng số Rcon biến đổi một cách phi tuyến tính và rất khó đoán, giúp phá vỡ mọi tính lặp đối xứng.
![[RCon AES-128.png]]

**Ứng dụng:** Kết quả của quá trình mở rộng khóa (Round Keys) sẽ được đưa trực tiếp vào [[diagram/AddRoundKey_Design.md|Module AddRoundKey]] để thực hiện mã hóa dữ liệu.
## 3. Lưu đồ thuật toán và Công thức sinh khóa (Key Expansion Algorithm) (AES-128)

![[media/AES Key Expansion.png]]

- [[KeyExpansion_Design|Thiết kế Module KeyExpansion (Top Level)]]
- [[diagram/RotWord_Design.md|Thiết kế Module RotWord]]
- [[diagram/SubWord_Design.md|Thiết kế Module SubWord]]
- [[AddRcon_Design|Thiết kế Module Rcon]]
- [[KE_Control_Unit_Design|Thiết kế Control Unit]]

Thuật toán điền các giá trị vào mảng $W[0 ... N_b \times (N_r + 1) - 1]$. Quy trình được chia làm 2 giai đoạn:
### Giai đoạn 1: Nạp khóa ban đầu

$N_k$ word đầu tiên của mảng $W$ chính là Khóa bí mật ban đầu $K$ được nạp trực tiếp vào.
Với $0 \le i < N_k$:
$$W[i] = K[4i, 4i+1, 4i+2, 4i+3]$$
### Giai đoạn 2: Mở rộng khóa

Với $i \ge N_k$, mỗi word $W[i]$ được tính toán dựa trên word ngay trước nó $W[i-1]$ và word ở vị trí $W[i-N_k]$.

Giả sử $temp = W[i-1]$:

1. **Nếu chỉ số** $i$ **là bội số của** $N_k$ **(**$i \pmod{N_k} == 0$**):**  $$temp = SubWord(RotWord(temp)) \oplus Rcon[i/N_k]$$
2. **Chỉ dành riêng cho AES-256 (**$N_k = 8$**) và** $i \pmod{N_k} == 4$**:**$$temp = SubWord(temp)$$
3. **Tính giá trị cuối cùng cho** $W[i]$**:**   $$W[i] = W[i - N_k] \oplus temp$$

_(Ghi chú: Tại sao AES-256 lại cần điều kiện số 2? Trong AES-128 (_$N_k=4$_), các hàm phi tuyến tính (`RotWord`, `SubWord`, `Rcon`) được gọi cứ sau mỗi 4 word. Nhưng với AES-256 (_$N_k=8$_), khoảng cách giữa các lần gọi hàm này bị nới rộng ra thành 8 word. Điều này có nghĩa là có một đoạn dài gồm 7 word liên tiếp chỉ được tính bằng phép XOR tuyến tính đơn giản (_$W[i] = W[i-8] \oplus W[i-1]$_). Quá nhiều phép tính tuyến tính liên tiếp sẽ làm suy yếu thuật toán, mở đường cho các tin tặc sử dụng phương pháp "Tấn công khóa liên quan" (Related-key attack). Do đó, những nhà thiết kế AES đã chèn thêm một phép `SubWord` ngay tại điểm giữa chu kỳ (tại vị trí_ $i \pmod 8 == 4$_). Việc này đảm bảo rằng không có word nào cách xa bước biến đổi phi tuyến quá 4 vị trí, giúp duy trì mức độ khuếch tán và xáo trộn (diffusion & confusion) cực cao)._

## 4. Ví dụ minh họa thực tế (AES-128)

**Tham số:** $N_k = 4$, $N_r = 10$. Tổng cộng cần 44 words (Từ $W[0]$ đến $W[43]$).

**Khóa bí mật ban đầu (Dạng Hex, 16 byte):** 
$$\begin{pmatrix}
2b &7e &15 &16  \\
28 &ae &d2 &a6  \\
ab &f7 &15 &88  \\
09 &cf &4f &3c
\end{pmatrix}$$
### Bước 1: Nạp khóa ban đầu ($i = 0$ đến $3$)

Khóa ban đầu được chia thành 4 word và điền thẳng vào mảng:

- $W[0] = \text{2b7e1516}$  
    
- $W[1] = \text{28aed2a6}$  
    
- $W[2] = \text{abf71588}$  
    
- $W[3] = \text{09cf4f3c}$  
    

_(Tại đây,_ $W[0]$ _đến_ $W[3]$ _tạo thành Round Key 0)._

### Bước 2: Tính $W[4]$ ($i = 4$)

Vì $i = 4$, và $4 \pmod{N_k} = 4 \pmod 4 = 0$ -> Thỏa mãn điều kiện sử dụng các hàm biến đổi phức tạp.

- Lấy $temp = W[i-1] = W[3] = \text{09cf4f3c}$  
    
- **RotWord(temp):** Dịch vòng trái 1 byte:
    
    `cf 4f 3c 09`
    
- **SubWord(...):** Đưa từng byte qua bảng S-box:
    
    SBox(cf) = `8a`, SBox(4f) = `84`, SBox(3c) = `eb`, SBox(09) = `01`
    
    => Kết quả: `8a84eb01`
    
- **XOR với Rcon:** Vì $i/N_k = 4/4 = 1$, ta dùng $Rcon[1] = \text{01000000}$.
    
    $\text{8a84eb01} \oplus \text{01000000} = \text{8b84eb01}$ (Đây là giá trị $temp$ mới)
    
- **Tính** $W[4]$**:** $W[i] = W[i-N_k] \oplus temp \Rightarrow W[4] = W[0] \oplus temp$  
    
    $$W[4] = \text{2b7e1516} \oplus \text{8b84eb01} = \text{a0fafe17}$$

### Bước 3: Tính $W[5]$ ($i = 5$)

Vì $i = 5$, và $5 \pmod 4 \ne 0$ -> Không cần biến đổi phức tạp.

- Lấy $temp = W[4] = \text{a0fafe17}$  
    
- **Tính** $W[5]$**:** $W[5] = W[1] \oplus temp$  
    
    $$W[5] = \text{28aed2a6} \oplus \text{a0fafe17} = \text{88542cb1}$$
### Bước 4: Tính $W[6]$ và $W[7]$ tương tự

- $W[6] = W[2] \oplus W[5] = \text{abf71588} \oplus \text{88542cb1} = \text{23a33939}$  
    
- $W[7] = W[3] \oplus W[6] = \text{09cf4f3c} \oplus \text{23a33939} = \text{2a6c7605}$  
    
**Kết quả sau vòng lặp đầu tiên:**

Bốn từ mới sinh ra $W[4], W[5], W[6], W[7]$ sẽ được ghép lại tạo thành **Round Key 1**:
$$\begin{pmatrix}
a0 &fa &fe &17  \\
88 &54 &2c &b1  \\
23 &a3 &39 &39  \\
2a &6c &76 &05
\end{pmatrix}$$

Thuật toán cứ tiếp tục lặp lại các bước trên (cứ mỗi 4 word lại dùng `RotWord`, `SubWord`, và `Rcon` một lần) cho đến khi tính đủ đến $W[43]$. Các nhóm 4 word liên tiếp này sẽ được đưa vào hàm `AddRoundKey` trong quá trình mã hóa/giải mã chính của AES.