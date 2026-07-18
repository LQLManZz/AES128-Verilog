![[AES-GCM (2).png]]
# 1. Trường Galois $GF(2^{128})$
Trường Galois hữu hạn $GF(2^{128})$ là không gian toán học chứa các phần tử dưới dạng các đa thức có hệ số nhị phân $\{0, 1\}$ với cấp tối đa là 127:
$$A(x) = a_0 + a_1 x + a_2 x^2 + \dots + a_{127} x^{127}$$
Trong đó $a_i \in \{0, 1\}$.
*   **Phép cộng (XOR):** Phép cộng giữa hai phần tử đa thức trong trường $GF(2^{128})$ tương đương với phép toán **XOR** từng bit tương ứng. Không có bit nhớ (carry) trong phép cộng này.
*   **Phép nhân (Carry-less Multiplication):** Phép nhân hai phần tử đa thức được thực hiện mà không có phần nhớ thông thường (carryless). Kết quả thu được là một đa thức tích có bậc tối đa là 254.
*   **Đa thức bất khả quy (Irreducible Polynomial):** Để tích của hai phần tử vẫn nằm trong trường $GF(2^{128})$, ta phải lấy số dư của đa thức tích cho đa thức bất khả quy tiêu chuẩn:
$$P(x) = x^{128} + x^7 + x^2 + x + 1$$
Mọi phép nhân trong GHASH đều được thu gọn theo modulo $P(x)$.
# 2. Thuật toán băm GHASH 
Hàm băm GHASH xử lý một chuỗi đầu vào gồm $m$ khối dữ liệu bổ sung AAD ($A_1 \dots A_m$), $n$ khối Ciphertext ($C_1 \dots C_n$), cùng khối thông tin độ dài Length block ($Len$). Phép toán được định nghĩa như sau:
1.  **Khởi tạo:** Thanh ghi tích lũy $X_0 = 0^{128}$.
2.  **Tính toán với các khối AAD ($i = 1 \dots m$):
$$X_i = (X_{i-1} \oplus A_i) \cdot H \pmod{P(x)}$$
3.  **Tính toán với các khối Ciphertext ($j = 1 \dots n$):     
$$X_{m+j} = (X_{m+j-1} \oplus C_j) \cdot H \pmod{P(x)}$$
4.  **Tính toán với khối Length Block:** Biểu diễn dưới dạng ghép cặp hai số nguyên 64-bit gồm độ dài bit của AAD và độ dài bit của Ciphertext: $Len = Len(A) \parallel Len(C)$.
$$X_{m+n+1} = (X_{m+n} \oplus [Len(A) \parallel Len(C)]) \cdot H \pmod{P(x)}$$
Tất cả các phép nhân dấu chấm ($\cdot$) trong công thức trên là phép nhân đa thức trong trường $GF(2^{128})$. Trong GCM thực tế, block cuối có thể không đủ 128 bit và phải được nối thêm các bit 0.
# 3. Authentication Tag
Để bảo vệ khóa băm phụ $H$ khỏi các cuộc tấn công khôi phục khóa từ kết quả băm, kết quả GHASH được XOR với $AES_K(J_0)$ để tạo tag xác thực của GCM. GHASH không được sử dụng như một hàm băm mật mã độc lập; các giá trị trung gian và khóa băm phụ $H$ phải được giữ bí mật:
$$Tag = X_{m+n+1} \oplus AES(K,J_0)$$
# 4. Thuật toán nhân Karatsuba-Ofman
Phép nhân hai đa thức 128-bit trong trường $GF(2^{128})$ là phép toán tốn kém tài nguyên nhất trong module GHASH. Nếu sử dụng phương pháp nhân truyền thống (Schoolbook Multiplication), độ phức tạp về tài nguyên phần cứng sẽ tăng theo cấp bậc hai $O(N^2)$. Thuật toán **Karatsuba-Ofman** được áp dụng để giải quyết bài toán tối ưu diện tích này bằng cách giảm số lượng bộ nhân song song.
## 4.1. Nguyên lý toán học trong trường $GF(2)$
Xét hai đa thức $A(x)$ và $B(x)$ có bậc tối đa là $N-1$ (với $N$ chẵn). Ta chia đôi mỗi đa thức thành hai phần có độ rộng $N/2$:
$$A(x) = A_H(x) \cdot x^{N/2} \oplus A_L(x)$$
$$B(x) = B_H(x) \cdot x^{N/2} \oplus B_L(x)$$
Trong đó $A_H, B_H$ là phần bậc cao (High) và $A_L, B_L$ là phần bậc thấp (Low).

Tích của hai đa thức $C(x) = A(x) \cdot B(x)$ được khai triển như sau:
$$C(x) = (A_H \cdot B_H) \cdot x^N \oplus \left[ (A_H \cdot B_L) \oplus (A_L \cdot B_H) \right] \cdot x^{N/2} \oplus (A_L \cdot B_L)$$

Thông thường, ta cần **4 bộ nhân** có kích thước $N/2$ để tính các tích thành phần:
1. $P_{HH} = A_H \cdot B_H$
2. $P_{HL} = A_H \cdot B_L$
3. $P_{LH} = A_L \cdot B_H$
4. $P_{LL} = A_L \cdot B_L$

Với thuật toán Karatsuba-Ofman, ta tính toán **3 tích thành phần** sau:
*   $P_0 = A_L \cdot B_L$
*   $P_1 = A_H \cdot B_H$
*   $P_2 = (A_L \oplus A_H) \cdot (B_L \oplus B_H)$

Khi đó, thành phần hạng tử ở giữa được tính gián tiếp dựa trên $P_0, P_1, P_2$:
$$(A_H \cdot B_L) \oplus (A_L \cdot B_H) = P_2 \oplus P_0 \oplus P_1$$

*Chứng minh:*
Trong trường nhị phân $GF(2)$, phép cộng và phép trừ đều tương đương với phép toán **XOR** ($\oplus$), do đó:
$$P_2 = (A_L \oplus A_H)(B_L \oplus B_H) = (A_L \cdot B_L) \oplus (A_L \cdot B_H) \oplus (A_H \cdot B_L) \oplus (A_H \cdot B_H)$$
$$P_2 = P_0 \oplus (A_L \cdot B_H \oplus A_H \cdot B_L) \oplus P_1$$
$$\Rightarrow A_L \cdot B_H \oplus A_H \cdot B_L = P_2 \oplus P_0 \oplus P_1$$

Như vậy, tích cuối cùng $C(x)$ bậc 254 được tổng hợp bằng công thức:
$$C(x) = P_1 \cdot x^N \oplus (P_2 \oplus P_0 \oplus P_1) \cdot x^{N/2} \oplus P_0$$
Tích có bậc không vượt quá 254 và cần 255 hệ số. Trong phần cứng, kết quả được lưu trên bus 256 bit để thuận tiện ghép các tích thành phần, $C[255]$ luôn bằng 0.

**Biểu diễn nhị phân 256 bit

Phép nhân với $x^k$ tương đương dịch trái $k$ bit:
$$
C=(P_{1}\ll 128) \oplus (P_{M} \ll 64) \oplus P_{0}​​
$$
Với $P_{M}=P_{2} \oplus P_{1} \oplus P_{0}$ 
Nếu mở rộng mỗi số hạng thành 256 bit:
$$\begin{align*}
P_1 x^{128} &= \underbrace{P_1}_{128\text{ bit}} \underbrace{0 \dots 0}_{128\text{ bit}} \\
P_M x^{64} &= \underbrace{0 \dots 0}_{64} \underbrace{P_M}_{128} \underbrace{0 \dots 0}_{64} \\
P_0 &= \underbrace{0 \dots 0}_{128} \underbrace{P_0}_{128}
\end{align*}$$
Do đó:$$
C= \{P_1,128'h0\} \oplus \{64'h0,P_M,64'h0\} \oplus \{128'h0,P_0\}$$
Vì vậy bốn khối 64 bit của kết quả là:
$$\begin{flalign*}
C[255:192] &= P_{1}[127:64] \\
C[191:128] &= P_{1}[63:0] \oplus P_{M}[127:64] \\
C[127:64] &= P_{0}[127:64] \oplus P_{M}[63:0] \\
C[63:0] &= P_{0}[63:0]
\end{flalign*}
$$​​
## 4.2. Đệ quy phân cấp
Đối với phần tử 128-bit ($N = 128$), thuật toán có thể được thiết kế theo cấu trúc phân tầng đệ quy:
1. **Tầng 1 (128-bit):** Phân rã thành **3 bộ nhân đa thức 64-bit**.
2. **Tầng 2 (64-bit):** Mỗi bộ nhân 64-bit tiếp tục được phân rã thành **3 bộ nhân đa thức 32-bit** (tổng cộng $3 \times 3 = 9$ bộ nhân 32-bit).
3. **Tầng 3 (32-bit):** Mỗi bộ nhân 32-bit tiếp tục được phân rã thành **3 bộ nhân đa thức 16-bit** (tổng cộng $9 \times 3 = 27$ bộ nhân 16-bit).
4. **Tầng 4 (16-bit):** Mỗi bộ nhân 16-bit tiếp tục được phân rã thành **3 bộ nhân đa thức 8-bit** (tổng cộng $27 \times 3 = 81$ bộ nhân 8-bit).
Quá trình đệ quy này dừng lại ở mức thiết kế cơ bản phù hợp (ví dụ: các bộ nhân 16-bit hoặc 8-bit được thiết kế theo dạng Schoolbook song song trực tiếp).
## 4.3. Thiết kế bộ nhân 8 bit
Phép nhân 8 bit hoạt động theo quy tắc carry-less:
$$P=A\times B$$
Ta có thể biểu diễn:
$$P = A\times B_0 + (A\times B_1)\ll1 + (A\times B_2)\ll2 +\cdots+ (A\times B_7)\ll7$$
Trong đó $B_{i}$ là từng bit của $B$.
- Nếu $B[i]=1$, ta XOR $A \ll i$.
- Nếu $B[i]=0$, tích riêng bằng 0.
Ví dụ về một phép nhân 8 bit giữa $a=00000011_{2}$ và $b=00000011_{2}$:
$$
\begin{array}{c@{\;}*{16}{c}} &0&0&0&0&0&0&0&0&0&0&0&0&0&0&1&1\\ \times &0&0&0&0&0&0&0&0&0&0&0&0&0&0&1&1\\ \hline &0&0&0&0&0&0&0&0&0&0&0&0&0&0&1&1\\ &0&0&0&0&0&0&0&0&0&0&0&0&0&1&1&0\\ &0&0&0&0&0&0&0&0&0&0&0&0&0&0&0&0\\ &0&0&0&0&0&0&0&0&0&0&0&0&0&0&0&0\\ &0&0&0&0&0&0&0&0&0&0&0&0&0&0&0&0\\ &0&0&0&0&0&0&0&0&0&0&0&0&0&0&0&0\\ &0&0&0&0&0&0&0&0&0&0&0&0&0&0&0&0\\ &0&0&0&0&0&0&0&0&0&0&0&0&0&0&0&0\\ \hline &0&0&0&0&0&0&0&0&0&0&0&0&0&1&0&1 \end{array}
$$
## 4.4. Đánh giá tài nguyên phần cứng
Để chứng minh cụ thể sự đánh đổi tài nguyên giữa cổng AND và cổng XOR qua từng tầng đệ quy Karatsuba (với kích thước cơ sở giảm dần từ 128-bit xuống 1-bit), ta có bảng số liệu tính toán được tính toán dưới đây:

| Phương pháp nhân (Kích thước cơ sở $M$) | Số tầng đệ quy ($L$) | Số lượng cổng AND | Số lượng cổng XOR | Độ sâu trễ XOR (Logic Depth) | Nhận xét                                                                           |
| :-------------------------------------- | :------------------: | :---------------: | :---------------: | :--------------------------: | :--------------------------------------------------------------------------------- |
| **Schoolbook (128-bit)**                |         $0$          |      $16384$      |      $16129$      |             $7$              | Diện tích AND cực lớn, đường trễ tối thiểu.                                        |
| **Karatsuba Tầng 1 (64-bit)**           |         $1$          |      $12288$      |      $12415$      |             $10$             | Giảm 25.0% AND, giảm 23.0% XOR. Trễ tăng nhẹ.                                      |
| **Karatsuba Tầng 2 (32-bit)**           |         $2$          |      $9216$       |      $9913$       |             $13$             | Giảm 43.8% AND, giảm 38.5% XOR. Trễ tăng vừa phải.                                 |
| **Karatsuba Tầng 3 (16-bit)**           |         $3$          |      $6912$       |      $8455$       |             $16$             | Giảm 57.8% AND, giảm 47.6% XOR.                                                    |
| **Karatsuba Tầng 4 (8-bit)**            |         $4$          |      $5184$       |     **7969**      |             $19$             | **Điểm tối ưu:** Số cổng XOR đạt mức cực tiểu (giảm 50.6% XOR, giảm 68.4% AND).    |
| **Karatsuba Tầng 5 (4-bit)**            |         $5$          |      $3888$       |      $8455$       |             $22$             | AND tiếp tục giảm, nhưng XOR bắt đầu **tăng ngược lại** (+486 cổng so với Tầng 4). |
| **Karatsuba Tầng 6 (2-bit)**            |         $6$          |      $2916$       |      $9913$       |             $25$             | XOR tăng mạnh (+1944 cổng so với Tầng 4). Trễ rất lớn.                             |
| **Karatsuba Tầng 7 (1-bit)**            |         $7$          |      $2187$       |      $12100$      |             $28$             | Số cổng AND tối thiểu, nhưng XOR bùng nổ. Trễ gấp 4 lần Schoolbook.                |
Bộ nhân cơ sở 8 bit đạt số cổng XOR nhỏ nhất và có logic depth thấp hơn bộ nhân cơ sở 4 bit. Tuy nhiên, điểm tối ưu diện tích phụ thuộc vào tỷ lệ diện tích giữa cổng XOR và cổng AND trong thư viện công nghệ.

**Phân tích và Chứng minh Toán học về Sự đánh đổi (Trade-off)

Trong trường Galois $GF(2)$, bộ nhân Schoolbook kích thước $K$-bit có số lượng cổng logic là:
* $\text{AND}_{\text{Schoolbook}}(K) = K^2$
* $\text{XOR}_{\text{Schoolbook}}(K) = (K-1)^2$

Khi áp dụng thuật toán Karatsuba-Ofman để phân rã bộ nhân $2k$-bit thành 3 bộ nhân $k$-bit, ta cần:
* 3 bộ nhân $k$-bit.
* Chi phí XOR phát sinh thêm (Overhead): 
  * Giai đoạn chuẩn bị toán hạng đầu vào: $(A_L \oplus A_H)$ và $(B_L \oplus B_H)$ tốn $2 \times k = 2k$ cổng XOR.
  * Giai đoạn ghép tích đầu ra: $C(x) = P_1 \cdot x^{2k} \oplus (P_2 \oplus P_0 \oplus P_1) \cdot x^k \oplus P_0$ tốn $3 \times (2k) - 4 = 6k - 4$ cổng XOR.
  * Tổng chi phí XOR phát sinh tại mỗi bước phân rã: $\text{Overhead}_{\text{XOR}} = 2k + (6k - 4) = 8k - 4$ cổng XOR.

Nếu dừng đệ quy ở mức $k$-bit (sử dụng bộ nhân Schoolbook cho cơ sở $k$-bit), tổng số cổng XOR của bộ nhân $2k$-bit Karatsuba là:
$$\text{XOR}_{\text{Karatsuba}}(2k) = 3 \times \text{XOR}_{\text{Schoolbook}}(k) + \text{Overhead}_{\text{XOR}} = 3(k-1)^2 + 8k - 4 = 3k^2 + 2k - 1$$

So sánh lượng cổng XOR của Karatsuba với Schoolbook trực tiếp trên khối $2k$-bit:
$$\text{XOR}_{\text{Schoolbook}}(2k) = (2k-1)^2 = 4k^2 - 4k + 1$$

Bộ nhân Karatsuba chỉ tiết kiệm được cổng XOR so với Schoolbook khi và chỉ khi:
$$\text{XOR}_{\text{Karatsuba}}(2k) < \text{XOR}_{\text{Schoolbook}}(2k)$$
$$\Leftrightarrow 3k^2 + 2k - 1 < 4k^2 - 4k + 1$$
$$\Leftrightarrow k^2 - 6k + 2 > 0$$
Giải bất phương trình trên với $k$ nguyên dương:
* Các nghiệm của phương trình $k^2 - 6k + 2 = 0$ là $k \approx 5.65$ và $k \approx 0.35$.
* Vì vậy, bất phương trình thỏa mãn khi $k > 5.65$ (tức là $k \ge 6$).
* Ngược lại, nếu $k \le 5$ (tức là khi phân rã xuống mức cơ sở $4$-bit, $2$-bit hoặc $1$-bit), việc phân rã Karatsuba sẽ làm **tăng** số lượng cổng XOR so với việc giữ nguyên bộ nhân Schoolbook.
**Minh chứng cụ thể ở các mức chuyển đổi cơ sở:
* **Từ 16-bit xuống 8-bit ($k = 8 \ge 6$):**
  * Bộ nhân Schoolbook 16-bit cần: $(16-1)^2 = 225$ cổng XOR.
  * Bộ nhân Karatsuba 16-bit (dùng cơ sở 8-bit Schoolbook) cần: $3 \times (8-1)^2 + (8 \times 8 - 4) = 3 \times 49 + 60 = 207$ cổng XOR.
  * **Kết quả:** Tiết kiệm được $225 - 207 = 18$ cổng XOR cho mỗi bộ nhân 16-bit. Do đó, tổng số cổng XOR toàn mạch 128-bit giảm xuống mức tối thiểu là **7969** tại Tầng 4.
* **Từ 8-bit xuống 4-bit ($k = 4 \le 5$):**
  * Bộ nhân Schoolbook 8-bit cần: $(8-1)^2 = 49$ cổng XOR.
  * Bộ nhân Karatsuba 8-bit (dùng cơ sở 4-bit Schoolbook) cần: $3 \times (4-1)^2 + (8 \times 4 - 4) = 3 \times 9 + 28 = 55$ cổng XOR.
  * **Kết quả:** Ta bị **tốn thêm** $55 - 49 = 6$ cổng XOR cho mỗi bộ nhân 8-bit được phân rã. Vì ở Tầng 4 có 81 bộ nhân 8-bit, việc chuyển sang Tầng 5 làm tăng tổng số cổng XOR toàn mạch thêm $81 \times 6 = 486$ cổng (tăng từ 7969 lên 8455).
# 5. Khối thu gọn Modulo (Reduction Block)
Sau khi bộ nhân Karatsuba thực hiện nhân hai phần tử 128-bit, ta thu được một đa thức tích $C(x)$ rộng 256 bit. Để kết quả nằm trong trường $GF(2^{128})$, đa thức tích này cần được thu gọn theo modulo đa thức bất khả quy:
$$P(x) = x^{128} + x^7 + x^2 + x + 1$$
## 5.1. Nguyên lý hoạt động
Vì phép toán được thực hiện trong trường $GF(2)$, ta có tính chất:
$$P(x) \equiv 0 \pmod{P(x)} \Rightarrow x^{128} \equiv x^7 + x^2 + x + 1 \pmod{P(x)}$$
Do đó, bất kỳ hạng tử bậc cao $c_i x^i$ (với $i \ge 128$) nào cũng có thể được quy đổi về các bậc thấp hơn bằng cách nhân với đa thức thu gọn:
$$c_i x^i \equiv c_i x^{i-128} (x^7 + x^2 + x + 1) \pmod{P(x)}$$
Quá trình thu gọn này được thiết kế hoàn toàn bằng mạch logic tổ hợp (combinational logic) song song, thực hiện gập các bit bậc cao $c_{128} \dots c_{254}$ về vùng bộ nhớ 128-bit thấp hơn ($c_0 \dots c_{127}$). Mạch thực thi gồm 2 bước gập chính:
1. **Gập bước 1:** Đưa các bit từ $c_{128} \dots c_{254}$ về dải bậc từ $0 \dots 133$ bằng cách dịch và XOR các phiên bản của nửa cao $C_H(x)$.
2. **Gập bước 2:** Thu gọn nốt các bit tràn từ bậc $128 \dots 133$ (chỉ gồm 6 bit) về dải từ $0 \dots 12$.

Tiến hành thu gọn đa thức $C(x)$ , đầu tiên ta viết dưới dạng như sau:
$$C(x)=C_L(x)+x^{128}C_H(x)$$
Trong đó:
$$C_L=C[127:0], \qquad C_H=C[255:128]$$
Ta có **đa thức bất khả quy** $P(x)$ trong trường $GF(2)$:
$$\begin{flalign*}
&P(x)=x^{128}+x^7+x^2+x+1=0 \\ \\
&x^{128}\equiv x^7+x^2+x+1\pmod{P(x)}
\end{flalign*}$$
Do đó:
$$x^{128}C_H(x) \equiv C_H(x)x^7 \oplus C_H(x)x^2 \oplus C_H(x)x \oplus C_H(x)$$
Suy ra bước rút gọn đầu tiên:
$$\begin{flalign*}
&T(x)=C_L(x) \oplus C_H(x) \oplus C_H(x)x \oplus C_H(x)x^2 \oplus C_H(x)x^7​ \\ \\
&T=C_L \oplus C_H \oplus(C_H\ll1) \oplus(C_H\ll2) \oplus(C_H\ll7)
\end{flalign*}$$
Tuy nhiên, $T$ có thể rộng tới 135 bit, nên đây ta phải tiến hành thêm một bước gập nữa để ép giá trị cuối về 128 bit.
Ta tiếp tục viết $T(x)$ dưới dạng như sau:
$$T(x)=T_L(x)+x^{128}T_H(x)$$
Trong đó:
$$T_L=T[127:0], \qquad T_H=T[134:128]$$
Tiếp tục thực hiện biến đổi giống như ở trên, ta được:
$$\begin{flalign*}
&x^{128}T_H(x) \equiv T_H(x)x^7 \oplus T_H(x)x^2 \oplus T_H(x)x \oplus T_H(x) \\ \\
&R(x)=T_L(x) \oplus T_H(x) \oplus T_H(x)x \oplus T_H(x)x^2 \oplus T_H(x)x^7​ \\ \\
&R=T_L \oplus T_H \oplus(T_H\ll1) \oplus(T_H\ll2) \oplus(T_H\ll7)
\end{flalign*}$$
Biểu thức $R$ chính là **đầu ra cuối cùng** của khối rút gọn.
## 5.2. Đánh giá tài nguyên và Độ trễ phần cứng
Do đa thức tối giản $P(x)$ là đa thức thưa (sparse polynomial - chỉ có 5 số hạng), cấu trúc thu gọn cực kỳ tối ưu về mặt tài nguyên phần cứng:
1. **Số lượng cổng AND:** **0 cổng**.
   * Việc nhân với đa thức $P(x)$ cố định thực chất chỉ là việc nối dây (routing) và XOR các đường tín hiệu với nhau, không cần sử dụng cổng AND hay các bộ nhân linh hoạt.
2. **Số lượng cổng XOR:** Chỉ tiêu tốn **527 cổng XOR** nhị phân đối với mạch triển khai song song trực tiếp (naive parallel). Số cổng này có thể giảm thêm nếu áp dụng kỹ thuật chia sẻ biểu thức con trùng lặp (Common Sub-expression Sharing).
3. **Độ sâu trễ logic (Logic Depth):** 
   * Số lượng toán hạng đầu vào tối đa cho bất kỳ phương trình bit đầu ra $r_j$ nào chỉ là **8** toán hạng (xảy ra ở các bit thấp như $r_1, r_2$).
   * Khi sử dụng cây XOR nhị phân để cộng 8 số hạng này, độ trễ lan truyền tối đa chỉ là:
$$\text{Depth}_{\text{reduction}} = \lceil \log_2(8) \rceil = \mathbf{3 \text{ tầng trễ XOR}}$$
