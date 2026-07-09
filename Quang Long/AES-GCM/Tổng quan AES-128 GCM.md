![[../_media/AES-GCM.png]]

Trong thế giới an toàn thông tin hiện đại, việc bảo vệ dữ liệu truyền tải qua mạng không chỉ dừng lại ở việc "xáo trộn" thông tin để kẻ xấu không đọc được (**Confidentiality - Tính bảo mật**), mà còn phải đảm bảo dữ liệu đó không bị thay đổi hay giả mạo trên đường truyền (**Integrity & Authentication - Tính toàn vẹn và xác thực**).
Để giải quyết đồng thời hai bài toán này một cách tối ưu nhất, hệ mã hóa **AES-GCM** (Advanced Encryption Standard - Galois/Counter Mode) đã ra đời và nhanh chóng trở thành tiêu chuẩn vàng được áp dụng rộng rãi trong các giao thức mạng phổ biến như TLS 1.2/1.3, IPsec (VPN), SSH và các hệ thống lưu trữ đám mây.
## 1. AEAD và ưu điểm AES-GCM

Trước khi GCM xuất hiện, để đạt được cả tính bảo mật lẫn tính xác thực, các kỹ sư thường phải kết hợp thủ công một thuật toán mã hóa khối (như AES-CBC) với một thuật toán băm xác thực tin nhắn (như HMAC-SHA256). Phương pháp này gọi là **Encrypt-then-MAC** hoặc **MAC-then-Encrypt**.
Tuy nhiên, việc ghép nối thủ công hai thuật toán độc lập này thường dẫn đến các lỗ hổng bảo mật nghiêm trọng (chẳng hạn như các cuộc tấn công padding oracle như POODLE, Lucky 13) và làm suy giảm hiệu năng hệ thống đáng kể do phải xử lý dữ liệu qua hai lượt tuần tự.
**AES-GCM** thuộc nhóm thuật toán **AEAD** (_Authenticated Encryption with Associated Data_ - Mã hóa xác thực đi kèm dữ liệu bổ sung). AEAD giải quyết triệt để vấn đề trên bằng cách tích hợp cả hai chức năng vào trong một lượt xử lý duy nhất (Single-pass):
- **Mã hóa (Encryption)**: Chuyển Plaintext (bản rõ) thành Ciphertext (bản mã).
- **Xác thực (Authentication)**: Sinh ra một mã xác thực (Authentication Tag - ) để bảo vệ tính toàn vẹn của cả Ciphertext và AAD (Additional Authenticated Data - Dữ liệu bổ sung không mã hóa, ví dụ: IP header trong gói tin mạng, thông tin định tuyến).
## 2. AES-128-GCM
### 2.1. Chế độ CTR (Counter Mode) - Đóng vai trò mã hóa
Chế độ CTR biến thuật toán mã hóa khối AES vốn có kích thước khối cố định 128-bit thành một **mã hóa dòng (Stream Cipher)**.
Thay vì mã hóa trực tiếp Plaintext, lõi AES-128 sẽ tiến hành mã hóa một chuỗi các giá trị bộ đếm (Counter) tăng dần kết hợp với một giá trị dùng một lần (**IV/Nonce** - Initialization Vector / Number Used Once) để tạo ra một dòng khóa ngẫu nhiên (**Keystream**). Sau đó, dòng khóa này được đem XOR trực tiếp với Plaintext để cho ra Ciphertext.
- **Ưu điểm:** Không cần bù đệm dữ liệu (Padding) cho đủ kích thước khối, hỗ trợ truy cập ngẫu nhiên (Random Access) và có thể song song hóa hoàn toàn quá trình mã hóa/giải mã.
### 2.2. Hàm băm GHASH (Galois Hash) - Đóng vai trò xác thực
Để tạo mã xác thực $T$, GCM sử dụng hàm băm vạn năng **GHASH** hoạt động dựa trên các phép toán nhân đa thức trong trường số hữu hạn Galois $GF(2^{128})$ với đa thức bất khả quy tiêu chuẩn:
$$P(x) = x^{128} + x^7 + x^2 + x + 1$$
Hàm GHASH nhận đầu vào là khóa băm phụ $H$ (được sinh ra bằng cách mã hóa một khối toàn bit $0$ bằng Cipher key: $H = AES(K,0)$, kết hợp với dữ liệu bổ sung (AAD) và Ciphertext để tính toán ra thẻ xác thực $T$.
## 3. Luồng Hoạt Động Chi Tiết Của Thuật Toán
#### Bước 1: Khởi tạo khóa băm phụ $H$ và bộ đếm $J_0$  

- Khóa băm phụ: $H = AES(K,0)$  
    
- Bộ đếm khởi tạo $J_0$ được tạo từ Initialization Vector (IV). Thông thường, tiêu chuẩn khuyến nghị độ dài IV là 96-bit.
    
    - Nếu IV dài đúng 96-bit: $J_0 = IV \parallel 0^{31}1$ (ghép thêm 31 bit 0 và 1 bit 1 ở cuối).
        
    - Nếu IV có độ dài khác 96-bit: $J_0 = \text{GHASH}(H,IV)$  
#### Bước 2: Mã hóa dữ liệu bằng chế độ CTR
Bộ đếm sẽ tăng dần sau mỗi khối ($inc(J)$). Dòng khóa được tạo ra và XOR với các khối Plaintext $P_1, P_2, \dots, P_n$:
$$C_i = P_i \oplus E_K(inc(J_{i-1}))$$
Khối Plaintext cuối cùng nếu không đủ 128 bit sẽ chỉ XOR với phần tương ứng của Keystream mà không cần thêm bit đệm (No padding).
#### Bước 3: Tính toán mã xác thực bằng hàm GHASH
Hàm GHASH tính toán tích lũy dựa trên lược đồ Horner trong trường Galois $GF(2^{128})$:

1. **Khởi tạo:** Thanh ghi băm ban đầu $X_0 = 0^{128}$  
    
2. **Xử lý các khối dữ liệu bổ sung AAD (**$A_1, A_2, \dots, A_m$**):
    $$X_i = (X_{i-1} \oplus A_i) \cdot H \quad (\text{với } i = 1 \dots m)$$
3. **Xử lý tiếp các khối bản mã Ciphertext (**$C_1, C_2, \dots, C_n$**):
    $$X_{m+j} = (X_{m+j-1} \oplus C_j) \cdot H \quad (\text{với } j = 1 \dots n)$$
4. **Khối độ dài cuối cùng (Length Block):** Hệ thống ghép độ dài của $A$ và $C$ (tính theo số bit, biểu diễn dưới dạng hai số nguyên 64-bit) thành một khối 128-bit $Len(A) \parallel Len(C)$:
    $$X_{\text{cuối}} = (X_{m+n} \oplus [Len(A) \parallel Len(C)]) \cdot H$$
#### Bước 4: Tạo thẻ xác thực cuối cùng ($Tag - T$)
Để bảo vệ khóa băm phụ $H$ khỏi việc bị dò ngược từ kết quả băm, kết quả $X_{\text{cuối}}$ từ GHASH sẽ được đem XOR với Keystream được tạo ra từ chính bộ đếm gốc $J_0$:
$$T = \text{MSB}_t(X_{\text{cuối}} \oplus E_K(J_0))$$
_(Trong đó,_ $\text{MSB}_t$ _là phép lấy_ $t$ _bit có trọng số lớn nhất làm thẻ xác thực, với_ $t$ _thường là 128 bit theo khuyến nghị)._
## 4. Hiệu suất AES-GCM
Một trong những lý do lớn nhất giúp AES-128-GCM thống trị các giao thức mạng tốc độ cao là khả năng **tối ưu hóa phần cứng vượt trội**.
- **Tính toán song song:** Vì CTR mode không có sự phụ thuộc lẫn nhau giữa các khối dữ liệu khi mã hóa, phần cứng có thể thiết kế theo kiến trúc đường ống (Pipeline) để mã hóa nhiều khối cùng lúc.
- **Phép nhân trường Galois tối ưu:** Hàm GHASH dựa trên phép nhân đa thức nhị phân. Các nhà sản xuất vi xử lý lớn như Intel, AMD và ARM đã tích hợp sẵn tập lệnh chuyên biệt cho việc này. Ví dụ, trên kiến trúc x86 là chỉ thị **PCLMULQDQ** (Carry-less Multiplication), cho phép thực hiện phép nhân đa thức 64-bit chỉ trong 1-2 chu kỳ xung nhịp, giúp tăng tốc độ xử lý GCM lên gấp hàng chục lần so với cài đặt bằng phần mềm thuần túy (Table-driven).
## 5. Thảm Họa Tái Sử Dụng Nonce (The Nonce-Reuse Disaster)
Dù là một "siêu anh hùng" về hiệu năng và độ an toàn, AES-GCM lại có một **điểm yếu chí tử**bắt nguồn từ bản chất toán học của nó. Lỗ hổng này được gọi là **"Forbidden Attack"** (Tấn công bị cấm).
#### Hậu quả 1: Lộ thông tin Plaintext (Mất tính bảo mật)
Vì GCM dựa trên chế độ CTR (mã hóa dòng), nếu bạn mã hóa hai thông điệp khác nhau ($P_1$ và $P_2$) bằng **cùng một khóa** $K$ **và cùng một số** $IV/Nonce$, dòng khóa sinh ra ($KS$) sẽ hoàn toàn trùng khớp:
$$C_1 = P_1 \oplus KS \quad \text{và} \quad C_2 = P_2 \oplus KS$$
Kẻ tấn công chỉ cần lấy hai bản mã thu được XOR với nhau:
$$C_1 \oplus C_2 = (P_1 \oplus KS) \oplus (P_2 \oplus KS) = P_1 \oplus P_2$$
Khi có được kết quả $P_1 \oplus P_2$, việc khôi phục lại nội dung gốc của cả hai thông điệp trở nên cực kỳ dễ dàng bằng các kỹ thuật phân tích ngôn ngữ tự nhiên.
#### Hậu quả 2: Giả mạo gói tin (Mất hoàn toàn tính xác thực)
Về mặt toán học, hàm GHASH có cấu trúc dạng đa thức:
$$\text{Tag} = (A \cdot H^3 \oplus C \cdot H^2 \oplus \text{Len} \cdot H) \oplus E_K(J_0)$$
Nếu hai thông điệp khác nhau được mã hóa với cùng một cặp Key/Nonce, giá trị mặt nạ $E_K(J_0)$ là như nhau. Kẻ tấn công có thể thiết lập một phương trình đa thức và dễ dàng tìm ra nghiệm chính là **khóa băm phụ** $H$.
Một khi $H$ bị lộ, kẻ tấn công hoàn toàn có thể tự tính toán ra mã xác thực $T$ hợp lệ cho bất kỳ thông điệp giả mạo nào mà chúng muốn gửi đi. **Hệ thống bảo mật hoàn toàn bị sụp đổ.**

> **Quy tắc bất di bất dịch:** Đối với một khóa $K$ cụ thể, không bao giờ được phép tái sử dụng giá trị IV/Nonce. Hãy sử dụng bộ đếm tăng dần, hoặc bộ sinh số ngẫu nhiên chuẩn mật mã học để sinh IV.
## 6. So Sánh Nhanh: AES-128-GCM vs Các Thuật Toán Khác

| **Tiêu chí**            | **AES-128-GCM**                           | **ChaCha20-Poly1305**                                                   | **AES-128-CBC + HMAC**            |
| ----------------------- | ----------------------------------------- | ----------------------------------------------------------------------- | --------------------------------- |
| **Loại thuật toán**     | AEAD (Khối + Galois)                      | AEAD (Dòng + Poly1305)                                                  | Kết hợp thủ công                  |
| **Độ an toàn**          | Rất cao                                   | Rất cao                                                                 | Trung bình (Dễ lỗi cấu hình)      |
| **Hiệu năng phần cứng** | **Cực tốt** (Nhờ AES-NI, PCLMULQDQ)       | Tốt                                                                     | Kém (CBC không thể song song hóa) |
| **Hiệu năng phần mềm**  | Khá tốt                                   | **Xuất sắc** (Phù hợp thiết bị di động/IoT không có tăng tốc phần cứng) | Trung bình                        |
| **Độ nhạy cảm với IV**  | **Cực kỳ nhạy cảm** (Lộ key nếu trùng IV) | Nhạy cảm                                                                | Nhạy cảm trung bình               |
## 7. Kết Luận và Khuyến Nghị Triển Khai
AES-128-GCM hiện vẫn là một trong những giải pháp mật mã học tốt nhất hiện nay nhờ sự cân bằng hoàn hảo giữa tính bảo mật, tính toàn vẹn và hiệu năng xử lý. Để triển khai AES-128-GCM an toàn trong thực tế, các nhà phát triển cần tuân thủ nghiêm ngặt các nguyên tắc sau:

1. **Quản lý IV nghiêm ngặt:** Đảm bảo mỗi IV được sử dụng là độc nhất vô nhị cho mỗi phiên mã hóa dưới cùng một khóa. Khuyến nghị sử dụng độ dài IV chuẩn là **96-bit**.
    
2. **Không rút ngắn thẻ xác thực quá mức:** Tiêu chuẩn cho phép rút ngắn thẻ xác thực xuống 64 hoặc 32 bit để tiết kiệm băng thông, nhưng điều này làm tăng đáng kể tỷ lệ kẻ tấn công đoán mò thành công thẻ xác thực. Hãy luôn giữ độ dài thẻ mặc định là **128-bit** trừ khi có ràng buộc cực kỳ khắt khe về phần cứng.
    
3. **Tận dụng thư viện chuẩn và phần cứng:** Tránh việc tự viết lại thuật toán từ đầu (Roll your own crypto). Hãy sử dụng các thư viện uy tín như OpenSSL, BoringSSL hoặc các thư viện phần cứng chính thức của nhà sản xuất chip để tránh các lỗ hổng tấn công kênh kề (Side-channel attacks) liên quan đến thời gian phản hồi của bộ nhớ đệm (Cache-timing).
