#Nguồn[Bài 5 - Tối ưu logic tính S-Box dựa trên biến đổi toán học](https://nguyenquanicd.blogspot.com/2019/10/aes-bai-5-toi-uu-logic-tinh-s-box-dua.html)

## 1. Lý thuyết tổng quan
Để tối ưu tài nguyên cho việc tra cứu bằng SBox, có thể xây dựng SBox theo hướng mạch tổ hợp. Để thực hiện mong đó, cần sử dụng các phép biến đổi toán học:
-  Tính nghịch đảo nhân trong trường hữu hạn $GF(2^8)$. Giá trị 0 có nghịch đảo là 0. Các giá trị khác phải biến đổi để tìm nghịch đảo.
-  Thực hiện biến đổi **Affine** trên $GF(2)$.
Để tra cứu bảng Inverted SBox  (SBox đảo), ta thực hiện phép biến đổi như sau:
- Thực hiện biến đổi **Affine** nghịch đảo trên $GF(2)$.
- Tính nghịch đảo nhân trong trường hữu hạn $GF(2^8)$. Giá trị 0 có nghịch đảo là 0. Các giá trị khác phải biến đổi để tìm nghịch đảo.
Từ đó, ta có **sơ đồ tổng thể*** quá trình chuyển 1 byte dữ liệu trong Word sang 1 byte tương ứng trong SBox như sau:
![[SBoxCombinationalLogic.png]]


| Tín hiệu            | Hướng  | Độ rộng | Mô tả                                                           |
| :------------------ | :----- | :------ | :-------------------------------------------------------------- |
| `byte_a`            | Input  | 8 bit   | Byte đầu vào                                                    |
| `direction_signal`  | Input  | 1 bit   | Tín hiệu điều khiển cho biết cần tra cứu theo SBox hay SBox đảo |
| `byte_a_substitute` | Output | 8 bit   | Byte đầu ra sau khi đã tra cứu giá trị tương ứng trong SBox     |

## 2. Tính nghịch đảo nhân trong trường hữu hạn $GF(2^8)$
Có nhiều cách khác nhau để thực hiện logic tính toán nghịch đảo nhưng một cách được áp dụng rộng rãi là biến đổi giá trị đầu vào từ trường $GF(2^8)$ xuống các trường có bậc thấp hơn như $GF(2^4)$, $GF(2^2)$ và $GF(2)$, gọi là **trường hữu hạn**, để đơn giản hóa mạch logic các phép toán nhân và lũy thừa.
Các đa thức bất kỳ trong **trường hữu hạn** có thể biểu diễn dưới dạng $bx+c$ trong đó $b$ là các phần trọng số cao còn $c$ là phần trọng số thấp, cả b và c đều thuộc trường có bậc thấp hơn so với trường ban đầu. Từ đó, một số nhị phân $a$ có thể được biểu diễn là $a_H \cdot x + a_L$.
VD: Số nhị phân $a=1001_{2}$ có thể biểu diễn dưới dạng $a=10_{2} \cdot x+01_{2}$ với $a_H=10_{2}$ và $a_L=01_{2}$. Ngoài ra, $a_H$ và $a_L$ có thể tiếp tục được biểu diễn như sau:
$$
\begin{align*}
a_{H}=1_{2} \cdot x+0_{2} \\ 
a_{L}=0_{2}\cdot x+1_{2}
\end{align*}
$$
Đây là ý tưởng được dùng để thực hiện các phép toán như cộng, nhân hay bình phương. Bên cạnh đó, quá trình hạ bậc đa thức để tính toán và biến đổi trong trường hỗn hợp sẽ sử dụng các **đa thức bất khả quy** sau đây:
$$\begin{align*}
GF(2^2) \rightarrow GF(2): x^2 + x + 1 \\
GF((2^2)^2) \rightarrow GF(2^2): x^2 + x + \phi \\
GF(((2^2)^2)^2) \rightarrow GF((2^2)^2): x^2 + x + \lambda
\end{align*}
$$
với $\phi=10_{2}$ , $\lambda=1100_{2}$ 
Ví dụ, chúng ta có thể xem $GF(2^8)$ là một **trường mở rộng** bậc 2 của trường cơ sở $GF(2^4)$, có nghĩa là trường $GF((2^4)^2)$. Khi đó, ta có thể ánh xạ các phần tử thuộc trường $GF(2^8)$ sang một phần tử A nào đó thuộc trường $GF((2^4)^2)$ có dạng như sau:
$$A=s\cdot x+t$$
- $s, t \in GF(2^4)$ (là các phần tử 4-bit).
- $x$ là biến đa thức thỏa mãn phương trình tạo trường: $x^2 + x + \lambda = 0$ (với $\lambda \in GF(2^4)$ là một hằng số tối ưu cấu trúc). Từ phương trình này ta có quan hệ: $x^2 = x \oplus \lambda$. 
***Quá trình tìm nghịch đảo nhân $A^{-1}$

Ta cần tìm một phần tử $A^{-1} = s' \cdot x + t'$ (với $s', t' \in GF(2^4)$) sao cho:
$$A \cdot A^{-1} \equiv 1 \pmod{x^2 + x + \lambda}$$
Triển khai nhân phân phối hai đa thức và thay thế $x^2 = x \oplus \lambda$, ta có:
$$\begin{flalign*}
(s \cdot x + t)(s' \cdot x + t') &= s \cdot s' \cdot x^2 + (s \cdot t' \oplus s' \cdot t) x \oplus t \cdot t'  \\
&= s \cdot s' (x \oplus \lambda) \oplus (s \cdot t' \oplus s' \cdot t) x \oplus t \cdot t'  \\
&= (s \cdot s' \oplus s \cdot t' \oplus s' \cdot t) x \oplus (s \cdot s' \cdot \lambda \oplus t \cdot t')  \\
&= 0 \cdot x + 1 
\end{flalign*}$$
Để phương trình trên cân bằng, ta có hệ phương trình sau:
$$\begin{cases}
s \cdot s' \oplus s \cdot t' \oplus s' \cdot t = 0 \implies s' (s \oplus t) = s \cdot t'  (1)\\
s \cdot s' \cdot \lambda \oplus t \cdot t' = 1 (2)
\end{cases}$$
Giải hệ phương trình này bằng đại số thế: Từ (1), ta rút ra:
$$s' = s \cdot t' \cdot (s \oplus t)^{-1}$$
Thế $s'$ vào (2):
$$\begin{flalign*}
s \cdot \left[ s \cdot t' \cdot (s \oplus t)^{-1} \right] \cdot \lambda \oplus t \cdot t' = 1 \\
t' \cdot \left[ s^2 \cdot \lambda \cdot (s \oplus t)^{-1} \oplus t \right] = 1
\end{flalign*}$$
Nhân cả hai vế với $(s \oplus t)$:
$$\begin{align*}
t' \cdot \left[ s^2 \cdot \lambda \oplus t(s \oplus t) \right] = s \oplus t
\end{align*}$$
Đặt nhân tử chung ở vế trái là $\Delta$ với $\Delta \in GF(2^4)$:
$$\Delta = s^2 \cdot \lambda \oplus t ( s \oplus t)$$
Khi đó, ta tìm được công thức tính toán cho hai thành phần $t'$ và $s'$:
$$\begin{align*}
t' \cdot \Delta = s \oplus t \implies
t' = (s \oplus t) \cdot \Delta^{-1}
\end{align*}$$$$s' = s \cdot t' \cdot (s \oplus t)^{-1} \implies s' = s \cdot (s \oplus t) \cdot \Delta^{-1} \cdot (s \oplus t)^{-1} \implies s' = s \cdot \Delta^{-1}$$
Từ đó ta thấy, để tính được nghịch đảo nhân $A^{-1}$ ta cần trải qua các bước sau:
$$\begin{aligned} \text{Bước 1: } & s^2 \quad \\ \text{Bước 2: } & s^2 \cdot \lambda \quad \\ \text{Bước 3: } & s \cdot t \quad  \\ \text{Bước 4: } & t^2 \quad \\ \text{Bước 5: } & \Delta = (s^2 \cdot \lambda) \oplus t(s \oplus t) \quad \\ \text{Bước 6: } & \mathbf{\Delta^{-1}} \quad \\ \text{Bước 7: } & t' = (s \oplus t) \cdot \Delta^{-1} \quad \\ \text{Bước 8: } & s' = s \cdot \Delta^{-1} \quad \end{aligned}$$

### 2.1. Sơ đồ khối
![[NghichDaoNhanGF28.png]]


| Tín hiệu   | Hướng  | Độ rộng | Mô tả                                                                             |
| :--------- | :----- | :------ | :-------------------------------------------------------------------------------- |
| `byte_in`  | Input  | 8 bit   | Byte đầu vào                                                                      |
| `byte_out` | Output | 8 bit   | Nghịch đảo nhân (multiplicative inverse) của byte đầu vào trong trường $GF(2^8)$  |
#### 2.1.1. Khối Imp và ImpInv
Phép tính phần tử nghịch đảo trong trường hỗn hợp không thể được áp dụng trực tiếp vào phần tử trên trường $GF(2^8)$. Nó phải được ánh xạ vào trường hỗn hợp thông qua biến đổi Isomorphic.
Khối Imp (gọi là Isomorphic Mapping) là khối ánh xạ phần tử của trường $GF(2^8)$ vào trong trường hỗn hợp và khối ImpInv (Inverse Isomorphic Mapping) là khối ánh xạ đảo của Imp, chuyển giá trị tính toán về trường $GF(2^8)$.
###### Khối Imp thực hiện phép nhân ma trận sau đây:
$$
\delta \times a = 
\begin{bmatrix}
1 & 0 & 1 & 0 & 0 & 0 & 0 & 0 \\
1 & 1 & 0 & 1 & 1 & 1 & 1 & 0 \\
1 & 0 & 1 & 0 & 1 & 1 & 0 & 0 \\
1 & 0 & 1 & 0 & 1 & 1 & 1 & 0 \\
1 & 1 & 0 & 0 & 0 & 1 & 1 & 0 \\
1 & 0 & 0 & 1 & 1 & 1 & 1 & 0 \\
0 & 1 & 0 & 1 & 0 & 0 & 1 & 0 \\
0 & 1 & 0 & 0 & 0 & 0 & 1 & 1
\end{bmatrix}
\times
\begin{bmatrix}
a_7 \\
a_6 \\
a_5 \\
a_4 \\
a_3 \\
a_2 \\
a_1 \\
a_0
\end{bmatrix} = 
\begin{bmatrix}
a_7 \oplus a_5 \\
a_7 \oplus a_6 \oplus a_4 \oplus a_3 \oplus a_2 \oplus a_1 \\
a_7 \oplus a_5 \oplus a_3 \oplus a_2 \\
a_7 \oplus a_5 \oplus a_3 \oplus a_2 \oplus a_1 \\
a_7 \oplus a_6 \oplus a_2 \oplus a_1 \\
a_7 \oplus a_4 \oplus a_3 \oplus a_2 \oplus a_1 \\
a_6 \oplus a_4 \oplus a_1 \\
a_6 \oplus a_1 \oplus a_0
\end{bmatrix}
$$
###### Khối ImpInv thực hiện phép nhân ma trận sau đây:
$$
\delta^{-1} \times a = \begin{bmatrix} 1 & 1 & 1 & 0 & 0 & 0 & 1 & 0 \\ 0 & 1 & 0 & 0 & 0 & 1 & 0 & 0 \\ 0 & 1 & 1 & 0 & 0 & 0 & 1 & 0 \\ 0 & 1 & 1 & 1 & 0 & 1 & 1 & 0 \\ 0 & 0 & 1 & 1 & 1 & 1 & 1 & 0 \\ 1 & 0 & 0 & 1 & 1 & 1 & 1 & 0 \\ 0 & 0 & 1 & 1 & 0 & 0 & 0 & 0 \\ 0 & 1 & 1 & 1 & 0 & 1 & 0 & 1 \end{bmatrix} \times \begin{bmatrix} a_7 \\ a_6 \\ a_5 \\ a_4 \\ a_3 \\ a_2 \\ a_1 \\ a_0 \end{bmatrix} = \begin{bmatrix} a_7 \oplus a_6 \oplus a_5 \oplus a_1 \\ a_6 \oplus a_2 \\ a_6 \oplus a_5 \oplus a_1 \\ a_6 \oplus a_5 \oplus a_4 \oplus a_2 \oplus a_1 \\ a_5 \oplus a_4 \oplus a_3 \oplus a_2 \oplus a_1 \\ a_7 \oplus a_4 \oplus a_3 \oplus a_2 \oplus a_1 \\ a_5 \oplus a_4 \\ a_6 \oplus a_5 \oplus a_4 \oplus a_2 \oplus a_0 \end{bmatrix}
$$
Thiết kế Module Imp & ImpInv: [[Module Imp & ImpInv Design]] 
#### 2.1.2. Khối S
Khối này dùng để tính bình phương (Square) trong **trường hỗn hợp**.
Ta ánh xạ $s \in GF(2^4)$ xuống trường $GF((2^2)^2)$ là phần tử 
$$\begin{flalign*}
w&=h \cdot x + l \\
w&=(w_{3}w_{2})\cdot x+(w_{1}w_{0})
\end{flalign*}$$
- $l, h \in GF(2^2)$ (là các phần tử 2 bit), ta quy định $h=w_{3}w_{2}$ và $l=w_{1}w_{0}$ 
- $x$ là biến đa thức thỏa mãn phương trình tạo trường: $x^2 + x + \phi = 0$ (với $\phi \in GF(2^2)$ là một hằng số tối ưu cấu trúc). Từ phương trình này ta có quan hệ: $x^2 = x \oplus \phi$ 
Tiến hành bình phương $w$ ta được:
$$\begin{flalign*}
w^2 &= (h \cdot x + l)^2 \\
&= h^2 \cdot x^2 + 2 \cdot h \cdot l \cdot x + l^2 \\
&= h^2(x + \phi) + l^2 \\
&= h^2 \cdot x +(h^2 \cdot \phi + l^2)
\end{flalign*}$$
Lưu ý rằng $2 \cdot h \cdot l \cdot x = h \cdot l \cdot x \oplus h \cdot l \cdot x=0$
Ta lại tiếp tục ánh xạ $h$ và $l$ xuống trường $GF(2)$ tiếp tục thực hiện các phép tính: 
$$h^2=(w_{3}w_{2})^2=(w_{3}\cdot x+w_{2})^2=w_{3}^2\cdot (x+1)+w_{2}^2=w_{3}\cdot x+(w_{3}+w_{2})$$


Thiết kế Module S: [[Module S Design]] 
#### 2.1.3. Khối C
Thiết kế Module C: [[Module C Design]] 
#### 2.1.4. Khối X
Thiết kế Module X: [[Module X Design]] 
#### 2.1.5. Khối Inv
Thiết kế Module Inv: [[Module Inv Design]] 
## 3. Phép biến đổi Affine
### 3.1. Biến đổi Affine
Phép biến đổi **Affine** đã được quy định rõ trong chuẩn AES và thể hiện bằng phép nhân và cộng ma trận như sau (với $y_7, x_7$ là MSB):
$$\begin{bmatrix}
y_7 \\
y_6 \\
y_5 \\
y_4 \\
y_3 \\
y_2 \\
y_1 \\
y_0
\end{bmatrix}
=
\begin{bmatrix}
1 & 1 & 1 & 1 & 1 & 0 & 0 & 0 \\
0 & 1 & 1 & 1 & 1 & 1 & 0 & 0 \\
0 & 0 & 1 & 1 & 1 & 1 & 1 & 0 \\
0 & 0 & 0 & 1 & 1 & 1 & 1 & 1 \\
1 & 0 & 0 & 0 & 1 & 1 & 1 & 1 \\
1 & 1 & 0 & 0 & 0 & 1 & 1 & 1 \\
1 & 1 & 1 & 0 & 0 & 0 & 1 & 1 \\
1 & 1 & 1 & 1 & 0 & 0 & 0 & 1
\end{bmatrix} \times
\begin{bmatrix}
x_7 \\
x_6 \\
x_5 \\
x_4 \\
x_3 \\
x_2 \\
x_1 \\
x_0
\end{bmatrix}
+
\begin{bmatrix}
0 \\
1 \\
1 \\
0 \\
0 \\
0 \\
1 \\
1
\end{bmatrix}$$
Có thể chuyển đổi thành dạng tổng quát như sau:
$$y_i = x_i \oplus x_{(i+4)\bmod 8} \oplus x_{(i+5)\bmod 8} \oplus x_{(i+6)\bmod 8} \oplus x_{(i+7)\bmod 8} \oplus c_i$$
Trong đó, với $0\le i\le 7$ ta có:
- $y_i$ là bit thứ $i$ của byte kết quả sau khi chuyển đổi.
- $x_i$ là bit thứ $i$ của byte đầu vào cần biến đổi.
- $c_i$ là bit thứ $i$ của hằng số $63_{16}=01100011_{2}$.
$$\begin{bmatrix}
y_7 \\
y_6 \\
y_5 \\
y_4 \\
y_3 \\
y_2 \\
y_1 \\
y_0
\end{bmatrix}
= \begin{bmatrix}
x_7 \oplus x_6 \oplus x_5 \oplus x_4 \oplus x_3 \\
x_6 \oplus x_5 \oplus x_4 \oplus x_3 \oplus x_2 \oplus 1 \\
x_5 \oplus x_4 \oplus x_3 \oplus x_2 \oplus x_1 \oplus 1 \\
x_4 \oplus x_3 \oplus x_2 \oplus x_1 \oplus x_0 \\
x_7 \oplus x_3 \oplus x_2 \oplus x_1 \oplus x_0 \\
x_7 \oplus x_6 \oplus x_2 \oplus x_1 \oplus x_0 \\
x_7 \oplus x_6 \oplus x_5 \oplus x_1 \oplus x_0 \oplus 1 \\
x_7 \oplus x_6 \oplus x_5 \oplus x_4 \oplus x_0 \oplus 1
\end{bmatrix}$$
### 3.2. Biến đổi Affine đảo
Phép biến đổi **Affine** nghịch đảo thể hiện bằng phép nhân và cộng ma trận như sau (với $x_7, y_7$ là MSB):
$$\begin{bmatrix}
x_7 \\
x_6 \\
x_5 \\
x_4 \\
x_3 \\
x_2 \\
x_1 \\
x_0
\end{bmatrix}
=
\begin{bmatrix}
0 & 1 & 0 & 1 & 0 & 0 & 1 & 0 \\
0 & 0 & 1 & 0 & 1 & 0 & 0 & 1 \\
1 & 0 & 0 & 1 & 0 & 1 & 0 & 0 \\
0 & 1 & 0 & 0 & 1 & 0 & 1 & 0 \\
0 & 0 & 1 & 0 & 0 & 1 & 0 & 1 \\
1 & 0 & 0 & 1 & 0 & 0 & 1 & 0 \\
0 & 1 & 0 & 0 & 1 & 0 & 0 & 1 \\
1 & 0 & 1 & 0 & 0 & 1 & 0 & 0
\end{bmatrix} \times
\begin{bmatrix}
y_7 \\
y_6 \\
y_5 \\
y_4 \\
y_3 \\
y_2 \\
y_1 \\
y_0
\end{bmatrix}
+
\begin{bmatrix}
0 \\
0 \\
0 \\
0 \\
0 \\
1 \\
0 \\
1
\end{bmatrix}$$
Có thể chuyển đổi thành dạng tổng quát như sau:
$$x_i = y_{(i+2)\bmod 8} \oplus y_{(i+5)\bmod 8} \oplus y_{(i+7)\bmod 8} \oplus d_i$$
Trong đó, với $0\le i\le 7$ ta có:
- $x_i$ là bit thứ $i$ của byte kết quả sau khi chuyển đổi.
- $y_i$ là bit thứ $i$ của byte đầu vào cần biến đổi.
- $d_i$ là bit thứ $i$ của hằng số $05_{16}=00000101_{2}$.
$$\begin{bmatrix}
x_7 \\
x_6 \\
x_5 \\
x_4 \\
x_3 \\
x_2 \\
x_1 \\
x_0
\end{bmatrix}
= \begin{bmatrix}
y_6 \oplus y_4 \oplus y_1 \\
y_5 \oplus y_3 \oplus y_0 \\
y_7 \oplus y_4 \oplus y_2 \\
y_6 \oplus y_3 \oplus y_1 \\
y_5 \oplus y_2 \oplus y_0 \\
y_7 \oplus y_4 \oplus y_1 \oplus 1 \\
y_6 \oplus y_3 \oplus y_0 \\
y_7 \oplus y_5 \oplus y_2 \oplus 1
\end{bmatrix}$$
Thiết kế Module Biến đổi Affine & Biến đổi Affine đảo: [[Module Biến đổi Affine & Biến đổi Affine đảo]] 