![[AES-GCM (2).png]]
# 1. Trường Galois $GF(2^{128})$
Trong AES-GCM, GHASH nhân các block 128 bit trong trường nhị phân $GF(2^{128})$ với đa thức bất khả quy:
$$P(x)=x^{128}+x^7+x^2+x+1$$
Một block 128 bit $A=a_0a_1\dots a_{127}$ được xem là:
$$A(x)=a_0+a_1x+a_2x^2+\dots+a_{127}x^{127}$$
Quy ước GCM là **little-endian theo hệ số đa thức**: bit trái nhất của chuỗi 128 bit là hệ số $x^0$, bit phải nhất là hệ số $x^{127}$. Khi viết RTL phải chốt rõ ánh xạ, ví dụ `block[127] = a_0` hoặc `block[0] = a_0`, rồi đảo bit ở biên module nếu cần.

| Thành phần | Ý nghĩa phần cứng |
|---|---|
| Cộng trong $GF(2^{128})$ | XOR từng bit, không có carry |
| Nhân carry-less | AND tạo tích riêng, XOR cộng các hệ số cùng bậc |
| Tích trung gian | $C(x)=A(x)B(x)=\sum_{i=0}^{254}c_ix^i$ |
| Thu gọn trường | $R(x)=C(x)\bmod P(x)=\sum_{i=0}^{127}r_ix^i$ |

# 2. GHASH chuẩn AES-GCM
Khóa băm phụ:
$$H=AES_K(0^{128})$$
Chuỗi được đưa vào GHASH:
$$X=A\parallel0^v\parallel C\parallel0^u\parallel[len(A)]_{64}\parallel[len(C)]_{64}$$
Trong đó $A$ là AAD, $C$ là ciphertext, $u=(128-(len(C)\bmod128))\bmod128$, $v=(128-(len(A)\bmod128))\bmod128$. Hai trường $[len(A)]_{64}$ và $[len(C)]_{64}$ là độ dài theo bit, mã hóa 64 bit.

Chia $X$ thành các block 128 bit: $X=X_1\parallel X_2\parallel\dots\parallel X_m$. GHASH được tính:
$$Y_0=0^{128}$$
$$Y_i=(Y_{i-1}\oplus X_i)\cdot H,\quad1\le i\le m$$
$$S=Y_m=GHASH_H(X)$$
Biểu thức tương đương để kiểm tra:
$$S=X_1H^m\oplus X_2H^{m-1}\oplus\dots\oplus X_{m-1}H^2\oplus X_mH$$

| Khối dữ liệu | Có padding? | Vai trò |
|---|---:|---|
| AAD $A$ | Có, thêm $0^v$ | Xác thực nhưng không mã hóa |
| Ciphertext $C$ | Có, thêm $0^u$ | Xác thực dữ liệu đã mã hóa |
| Length block | Luôn 128 bit | Chống nhập nhằng giữa các cách chia block |

# 3. Tag Generation
Với pre-counter block $J_0$:
$$J_0=IV\parallel0^{31}\parallel1,\quad\text{khi }len(IV)=96$$
$$J_0=GHASH_H(IV\parallel0^s\parallel0^{64}\parallel[len(IV)]_{64}),\quad\text{khi }len(IV)\ne96$$
Trong đó $s=(128-(len(IV)\bmod128))\bmod128$.

Authentication tag chuẩn:
$$T=MSB_t(AES_K(J_0)\oplus S)$$
Nếu dùng tag đủ 128 bit:
$$T=AES_K(J_0)\oplus S$$

| Khối | Tài nguyên chính | Ghi chú |
|---|---|---|
| `AES_K(J0)` | 1 lõi AES encryption | Có thể dùng lại datapath AES sẵn có |
| XOR tag 128 bit | 128 XOR 2-ngõ vào | Chỉ áp dụng trước khi cắt `MSB_t` |
| Cắt tag `MSB_t` | Dây nối | Không tốn logic nếu chỉ lấy bit |

# 4. Nhân Karatsuba-Ofman
Schoolbook $N$ bit có chi phí AND xấp xỉ $O(N^2)$, tức tăng theo bậc hai. Karatsuba-Ofman giảm số bộ nhân con bằng cách đổi một phần AND lấy XOR.

Với $N$ chẵn:
$$A=A_Hx^{N/2}\oplus A_L,\quad B=B_Hx^{N/2}\oplus B_L$$
Tính ba tích:
$$P_0=A_LB_L,\quad P_1=A_HB_H,\quad P_2=(A_L\oplus A_H)(B_L\oplus B_H)$$
Hạng giữa:
$$A_HB_L\oplus A_LB_H=P_2\oplus P_0\oplus P_1$$
Tích carry-less chưa thu gọn:
$$C=P_1x^N\oplus(P_2\oplus P_0\oplus P_1)x^{N/2}\oplus P_0$$

## 4.1. Bảng tiêu thụ phần cứng của bộ nhân 128 bit
Bảng dưới dùng mô hình đếm cổng trực tiếp: cổng AND 2-ngõ vào, XOR 2-ngõ vào, chưa tính tối ưu của synthesis, chia sẻ biểu thức con, fanout, retiming hoặc pipeline.

| Phương pháp          | Tầng đệ quy | Lá schoolbook |      AND |      XOR | Độ sâu XOR ước lượng | Nhận xét                    |
| -------------------- | ----------: | ------------: | -------: | -------: | -------------------: | --------------------------- |
| Schoolbook trực tiếp |           0 |       128 bit |    16384 |    16129 |                    7 | AND lớn nhất, trễ thấp      |
| Karatsuba T1         |           1 |        64 bit |    12288 |    12415 |                   10 | Giảm 25.0% AND              |
| Karatsuba T2         |           2 |        32 bit |     9216 |     9913 |                   13 | Cân bằng hơn                |
| Karatsuba T3         |           3 |        16 bit |     6912 |     8455 |                   16 | Giảm mạnh AND/XOR           |
| **Karatsuba T4**     |       **4** |     **8 bit** | **5184** | **7969** |               **19** | **Điểm dừng tốt theo XOR**  |
| Karatsuba T5         |           5 |         4 bit |     3888 |     8455 |                   22 | XOR bắt đầu tăng            |
| Karatsuba T6         |           6 |         2 bit |     2916 |     9913 |                   25 | Trễ và XOR tăng rõ          |
| Karatsuba T7         |           7 |         1 bit |     2187 |    12100 |                   28 | AND thấp nhất nhưng XOR cao |

## 4.2. Công thức đếm nhanh
Với schoolbook $K$ bit:
$$AND_{SB}(K)=K^2,\quad XOR_{SB}(K)=(K-1)^2$$
Khi tách bộ nhân $2k$ bit thành 3 bộ nhân $k$ bit:
$$XOR_{KO}(2k)=3(k-1)^2+(8k-4)=3k^2+2k-1$$
So với schoolbook trực tiếp:
$$XOR_{SB}(2k)=(2k-1)^2=4k^2-4k+1$$
Karatsuba giảm XOR khi:
$$3k^2+2k-1<4k^2-4k+1\Leftrightarrow k^2-6k+2>0$$
Với $k$ nguyên dương, điều kiện hữu ích là $k\ge6$. Vì vậy tách 16 bit xuống 8 bit còn lợi, nhưng tách 8 bit xuống 4 bit làm XOR tăng.

# 5. Thu gọn modulo $P(x)$ để tổng hợp phần cứng
Từ $P(x)=0$:
$$x^{128}\equiv x^7+x^2+x+1\pmod{P(x)}$$
Vì vậy:
$$c_ix^i\equiv c_ix^{i-128}(x^7+x^2+x+1),\quad i\ge128$$

## 5.1. Biểu thức vector hai bước
Tách tích trung gian:
$$C(x)=C_L(x)\oplus x^{128}C_H(x)$$
$$C_L(x)=\sum_{i=0}^{127}c_ix^i,\quad C_H(x)=\sum_{i=0}^{126}c_{128+i}x^i$$
Gập bước 1:
$$D(x)=C_L(x)\oplus C_H(x)\oplus xC_H(x)\oplus x^2C_H(x)\oplus x^7C_H(x)$$
Sau bước này chỉ còn tràn ở bậc 128 đến 133. Gọi:
$$Q(x)=\sum_{i=0}^{5}d_{128+i}x^i$$
Biểu thức rút gọn cuối cùng:
$$R(x)=D_{[0:127]}(x)\oplus Q(x)\oplus xQ(x)\oplus x^2Q(x)\oplus x^7Q(x)$$
Đây là dạng thuận tiện để tổng hợp: chỉ cần dây dịch chỉ số và XOR, không cần AND trong khối reduction.

## 5.2. Dạng bit tổng quát
Định nghĩa $c_i=0$ nếu chỉ số ngoài $0\le i\le254$. Với $0\le j\le127$:
$$d_j=c_j\oplus c_{128+j}\oplus c_{127+j}\oplus c_{126+j}\oplus c_{121+j}$$
Sáu bit tràn:
$$d_{128}=c_{249}\oplus c_{254},\quad d_{129}=c_{250},\quad d_{130}=c_{251}$$
$$d_{131}=c_{252},\quad d_{132}=c_{253},\quad d_{133}=c_{254}$$
Gọi $q_i=d_{128+i}$ với $0\le i\le5$, $q_k=0$ nếu $k<0$ hoặc $k>5$:
$$r_j=d_j\oplus q_j\oplus q_{j-1}\oplus q_{j-2}\oplus q_{j-7}$$
Ví dụ:
$$r_0=c_0\oplus c_{128}\oplus c_{249}\oplus c_{254}$$
$$r_1=c_1\oplus c_{128}\oplus c_{129}\oplus c_{249}\oplus c_{250}\oplus c_{254}$$
$$r_2=c_2\oplus c_{128}\oplus c_{129}\oplus c_{130}\oplus c_{249}\oplus c_{250}\oplus c_{251}\oplus c_{254}$$
$$r_3=c_3\oplus c_{129}\oplus c_{130}\oplus c_{131}\oplus c_{250}\oplus c_{251}\oplus c_{252}$$

## 5.3. Bảng tiêu thụ phần cứng của reduction
| Hạng mục | Giá trị | Ghi chú |
|---|---:|---|
| AND | 0 | Reduction chỉ là XOR và nối dây |
| XOR 2-ngõ vào | 527 | Nếu mỗi $r_j$ tổng hợp độc lập |
| Toán hạng XOR tối đa trên một $r_j$ | 8 | Xảy ra ở các bit thấp như $r_2$ |
| Độ sâu XOR cân bằng | 3 | $\lceil\log_2(8)\rceil=3$ |
| Pipeline khuyến nghị | Sau multiplier hoặc sau reduction | Tùy mục tiêu Fmax |

# 6. Ước lượng tài nguyên datapath GHASH/Tag
Các bảng dưới chỉ tính phần logic GHASH/tag, không tính lõi AES tạo $H$ và `AES_K(J0)` nếu lõi AES được dùng lại từ datapath mã hóa.

| Khối | Register | AND | XOR | Nhận xét |
|---|---:|---:|---:|---|
| XOR tiền nhân $(Y_{i-1}\oplus X_i)$ | 0 | 0 | 128 | Có thể đặt trước multiplier |
| Multiplier Karatsuba T4 | 0 | 5184 | 7969 | Tích carry-less 128x128 -> 255 bit |
| Reduction modulo $P(x)$ | 0 | 0 | 527 | 255 bit -> 128 bit |
| Thanh ghi tích lũy $Y_i$ | 128 FF | 0 | 0 | Cập nhật mỗi block |
| XOR tag 128 bit | 0 | 0 | 128 | $AES_K(J0)\oplus S$ |

Tổng logic tổ hợp cho một datapath GHASH 1 block/chu kỳ dùng Karatsuba T4:

| Cấu hình | AND | XOR | FF tối thiểu |
|---|---:|---:|---:|
| GHASH core không tính tag XOR | 5184 | 8624 | 128 |
| GHASH core có tag XOR 128 bit | 5184 | 8752 | 128 |
| Schoolbook + reduction, không tag XOR | 16384 | 16784 | 128 |

So sánh nhanh:

| Cấu hình | AND giảm so với schoolbook | XOR giảm so với schoolbook | Ghi chú |
|---|---:|---:|---|
| Karatsuba T4 + reduction | 68.4% | 48.6% | Tính cả XOR tiền nhân và reduction |
| Karatsuba T4 + reduction + tag XOR | 68.4% | 48.3% | Tag XOR làm chênh lệch nhỏ hơn |
# 7. Kết luận
Các công thức cốt lõi về GHASH, tag 128 bit, Karatsuba và reduction theo $P(x)$ là đúng hướng. Các điểm đã cụ thể hóa để đúng chuẩn AES-GCM và thuận tiện viết RTL:

| Điểm cần đúng | Kết luận |
|---|---|
| Khóa băm phụ | $H=AES_K(0^{128})$ |
| Đầu vào GHASH | $A\parallel0^v\parallel C\parallel0^u\parallel[len(A)]_{64}\parallel[len(C)]_{64}$ |
| Tag chuẩn | $T=MSB_t(AES_K(J_0)\oplus S)$ |
| Quy ước bit | Phải cố định ánh xạ bit chuỗi sang hệ số đa thức |
| Reduction cuối | $R(x)=D_{[0:127]}(x)\oplus Q(x)\oplus xQ(x)\oplus x^2Q(x)\oplus x^7Q(x)$ |
