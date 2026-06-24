## 1. Cách thức hoạt động

Như đã biết, thuật toán AES xử lý dữ liệu theo từng khối 128-bit (16 byte). Khối dữ liệu này được xếp thành một lưới $4 \times 4$ gọi là **State Matrix (Ma trận trạng thái)**.

Tại bước AddRoundKey, cần có hai thành phần:

1. **State Matrix hiện tại:** Dữ liệu đang trong quá trình bị mã hóa.
    
2. **Round Key (Khóa vòng):** Một ma trận $4 \times 4$ khác chứa khóa phụ 128-bit. Cần lưu ý, đây không phải là khóa gốc ban đầu, mà là một "chìa khóa con" được sinh ra từ khóa gốc thông qua quá trình _Key Expansion_.
    

**Hành động:** Thuật toán sẽ lấy từng byte của Ma trận trạng thái, đối chiếu với byte ở vị trí tương ứng của Khóa vòng và thực hiện phép XOR. Công thức toán học tổng quát: $$State'[i, j] = State[i, j] \oplus RoundKey[i, j]$$ _(với_ $0 \le i \le 3$ _và_ $0 \le j \le 3$_)_

## 2. Thiết kế tổng quan (High-Level Design)

**Xem chi tiết sơ đồ:** [[AddRoundKey_Design]]
## 3. Vị trí của AddRoundKey trong toàn bộ quy trình

![[AES.png]]

Bước này xuất hiện ở 3 nơi trong quy trình mã hóa:

1. **Vòng đầu tiên (Initial Round):** Ngay khi nhận dữ liệu thô (Plaintext), thao tác đầu tiên được thực hiện là AddRoundKey với khóa gốc ban đầu để che giấu dữ liệu ngay lập tức trước khi bắt đầu các biến đổi phức tạp.
    
2. **Các vòng lặp chính (Main Rounds):** Nằm ở cuối mỗi vòng.
    
3. **Vòng cuối cùng (Final Round):** Nằm ở bước cuối cùng để khóa chặt bản mã (Ciphertext) trước khi trả ra kết quả.
    
## 4. Tại sao AddRoundKey lại quan trọng đến vậy?

- **Tính bảo mật (Tiêm khóa bí mật):** Các bước như SubBytes hay ShiftRows dù có phức tạp đến đâu thì cũng là các biến đổi cố định không có khóa. Nếu không có AddRoundKey, bất kỳ ai rành thuật toán đều có thể tính ngược lại. AddRoundKey chính là bước tiêm "sự bí mật" (khóa) vào dữ liệu.
    
- **Tính khả nghịch (Dễ dàng giải mã):** Phép XOR có một đặc tính kỳ diệu: Nếu $A \oplus K = C$, thì $C \oplus K = A$. Nghĩa là khi giải mã (Decryption), hệ thống chỉ cần thực hiện lại thao tác XOR bản mã với chính Khóa vòng đó một lần nữa là dữ liệu ban đầu sẽ lộ diện. Không cần thiết kế một hàm toán học ngược phức tạp nào khác cho bước này.