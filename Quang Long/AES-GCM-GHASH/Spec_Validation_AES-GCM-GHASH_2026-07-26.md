# AES-GCM-GHASH — Specification Validation

Ngày đánh giá: 2026-07-26
Phạm vi: `Quang Long/AES-GCM-GHASH/_design`

## 1. Kết luận tổng quan

Thiết kế có cách phân rã module rõ ràng và datapath GHASH cơ bản đúng theo công thức tích lũy `(Y ⊕ X) × H`. Các bảng tín hiệu phần lớn bám sát hình high-level; `TagGeneration` là XOR tổ hợp đơn giản; bộ đếm độ dài dùng hai trường 64 bit và nhận số bit hợp lệ của từng block.

Tuy nhiên, đặc tả **chưa sẵn sàng để triển khai RTL tích hợp**. Ba vấn đề chặn chính là:

1. `GHASHInput` chốt `data_in` bằng thanh ghi trong cùng cạnh mà FSM assert `ghash_en`; thanh ghi GHASH vì vậy sử dụng `data_in` cũ, không phải block đang ở trạng thái `LOAD_*`.
2. `LOAD_LENGTH_BLOCK` không có điều kiện điều khiển khả dụng: `lenblk_valid` vừa là output chỉ bật ở chính trạng thái này, vừa được dùng để chọn đi vào trạng thái này từ `GHASH_PROCESSING`.
3. Counter độ dài cập nhật trực tiếp theo `AAD_valid/CT_valid`, không theo cùng sự kiện block được GHASH chấp nhận; đặc tả valid không quy định pulse, hold hay handshake nên có nguy cơ đếm lặp hoặc lệch với accumulator.

Các điểm trên có thể làm GHASH và Tag sai ngay cả khi bộ nhân `GF(2^128)` đúng theo quy ước bit nội bộ.

## 2. Phạm vi và giả định

### 2.1. Tài liệu chính

- [`GF128bitMultiply_Design.md`](_design/GF128bitMultiply_Design.md)
- [`GHASHInput_Design.md`](_design/GHASHInput_Design.md)
- [`GHASH_Design.md`](_design/GHASH_Design.md)
- [`TagGeneration_Design.md`](_design/TagGeneration_Design.md)
- [`TagProcessing_Design.md`](_design/TagProcessing_Design.md)

Các hình PNG được năm tài liệu trên tham chiếu đã được kiểm tra trực tiếp. RTL và testbench trong [`../../RTL/GCM-GHASH`](../../RTL/GCM-GHASH) chỉ được dùng làm bằng chứng đối chiếu, không được coi là nguồn chuẩn thay cho thiết kế.

### 2.2. Quy ước bit nội bộ

Đánh giá chấp nhận quy ước nội bộ do người thiết kế lựa chọn:

```text
block[i] ↔ hệ số x^i
```

Quy ước này không bị coi là lỗi. Yêu cầu duy nhất ở giai đoạn này là các sơ đồ, RTL, testbench và waveform nội bộ phải nhất quán. Việc chuyển representation tại biên tương thích AES-GCM chuẩn có thể thực hiện sau.

### 2.3. Giới hạn đánh giá

- Tag được giả định cố định 128 bit.
- `H_key = AES_K(0^128)` và `E_key = AES_K(J0)` được cung cấp từ khối bên ngoài.
- Không giả định nguồn dữ liệu tự zero-pad hoặc giữ valid theo một giao thức chưa được viết trong đặc tả.

## 3. Điểm thiết kế hợp lý

### 3.1. Phân rã module rõ ràng

Thiết kế tách riêng phép nhân trường, chọn/đếm đầu vào, accumulator GHASH, tạo Tag và FSM điều khiển. Ranh giới chức năng này thuận lợi cho unit test và synthesis độc lập.

### 3.2. Cấu trúc GHASH cơ bản đúng

Sơ đồ `GHASH low level` thể hiện:

```text
next_ghash = (ghash_out XOR data_in) × H_key
```

và mux feedback giữ accumulator khi `ghash_en = 0`. Reset đưa accumulator về `128'h0`, phù hợp giá trị khởi tạo `Y0` của GHASH.

### 3.3. Length Block có đúng cấu trúc độ rộng

`LenBlkCounter` dùng `AAD_cnt[63:0]` và `CT_cnt[63:0]`, sau đó ghép:

```text
length_block = {AAD_cnt[63:0], CT_cnt[63:0]}
```

Việc cộng `AAD_valid_bits` và `CT_valid_bits` cho phép biểu diễn block cuối không đủ 128 bit về mặt độ dài.

### 3.4. Priority AAD nhất quán trong hai sơ đồ low-level

Khi `AAD_valid` và `CT_valid` cùng bằng 1:

- FSM ưu tiên `LOAD_AAD`.
- Counter CT chỉ tăng với `!AAD_valid && CT_valid`.

Hai khối vì vậy dùng cùng priority AAD.

### 3.5. `TagGeneration` có datapath tối giản

Hai hình của `TagGeneration` và bảng tín hiệu cùng mô tả phép XOR tổ hợp:

```text
tag = ghash_out XOR E_key
```

Không suy tính hợp lệ của Tag từ giá trị dữ liệu.

## 4. Phát hiện nghiêm trọng

### C-01 — `ghash_en` lệch một chu kỳ so với block được chốt

**Ảnh hưởng:** `GHASHInput`, `GHASH`, `TagProcessingFSM`

**Bằng chứng:**

- `GHASHInput high level` có thanh ghi 128 bit sau mux `data_type`; `data_in` chỉ đổi tại cạnh clock.
- Decoder FSM assert `data_type` và `ghash_en` đồng thời tại `LOAD_AAD`, `LOAD_CT` và `LOAD_LENGTH_BLOCK`.
- `GHASH` cũng chốt accumulator tại cạnh clock khi `ghash_en = 1`.

Tại cạnh kết thúc `LOAD_AAD`, thanh ghi `GHASHInput` mới chốt `AAD_block`, nhưng thanh ghi GHASH chỉ nhìn thấy giá trị `data_in` từ chu kỳ trước. Sang `GHASH_PROCESSING`, `ghash_en = 0` và `data_type` trở về `00`, nên block vừa chốt không được đưa vào accumulator.

**Tác động:** GHASH có thể nhân block 0 hoặc block cũ; kết quả băm và Tag sai.

**Khuyến nghị:** Chọn một phương án và ghi timing rõ theo cạnh clock:

- Giữ thanh ghi `GHASHInput`, assert `ghash_en` ở `GHASH_PROCESSING`; hoặc
- Bỏ thanh ghi `GHASHInput`, đưa mux tổ hợp trực tiếp tới GHASH và assert `ghash_en` ở `LOAD_*`; hoặc
- Dùng handshake pipeline với `input_reg_valid` rồi chỉ cập nhật accumulator khi valid đã qua thanh ghi.

### C-02 — `LOAD_LENGTH_BLOCK` không thể được chọn bằng logic hiện tại

**Ảnh hưởng:** `TagProcessingFSM`

**Bằng chứng:**

- Decoder assert `lenblk_valid` chỉ khi `current_state = 3'b011` (`LOAD_LENGTH_BLOCK`).
- Mux next-state ở `current_state = 3'b100` (`GHASH_PROCESSING`) dùng `lenblk_valid` để chọn giữa `LOAD_LENGTH_BLOCK` và `TAG_GENERATION`.
- `lenblk_valid` không xuất hiện như một input độc lập của FSM high-level.

Khi đang ở `GHASH_PROCESSING`, decoder không assert `lenblk_valid`, nên nhánh `LOAD_LENGTH_BLOCK` không có điều kiện để được chọn. Nếu không có AAD/CT, mạch đi tới `TAG_GENERATION` và bỏ qua Length Block.

**Tác động:** GHASH thiếu block `{len(A), len(C)}`, làm Tag sai.

**Khuyến nghị:** Thay điều kiện bằng một fact độc lập, ví dụ `length_pending`, `end_of_message`, hoặc cờ phase đã đăng ký. `lenblk_valid` nên chỉ là output báo block length đang được phát, không đồng thời là nguyên nhân để đi vào chính trạng thái đó.

### C-03 — Counter và accumulator không dùng chung sự kiện accept

**Ảnh hưởng:** `LenBlkCounter`, `TagProcessingFSM`, giao diện nguồn

**Bằng chứng:**

- Counter AAD tăng ở mọi cạnh có `AAD_valid = 1`.
- Counter CT tăng ở mọi cạnh có `!AAD_valid && CT_valid`.
- Accumulator chỉ cập nhật ở cạnh có `ghash_en = 1`.
- Đặc tả không định nghĩa `AAD_valid/CT_valid` là pulse một chu kỳ hay được giữ tới khi dữ liệu được accept.

Nếu nguồn giữ `AAD_valid` qua `IDLE → LOAD_AAD → GHASH_PROCESSING`, counter có thể tăng nhiều lần cho một block trong khi GHASH chỉ dự kiến xử lý một lần. Nếu nguồn chỉ pulse ở `IDLE`, block lại không được giữ tới chu kỳ `LOAD_AAD`.

**Tác động:** `length_block` không phản ánh đúng dữ liệu GHASH đã xử lý.

**Khuyến nghị:** Định nghĩa một sự kiện duy nhất:

```text
accept = in_valid && in_ready
```

Counter, thanh ghi input và logic tiến trạng thái phải cùng dùng `accept`. Nếu không hỗ trợ backpressure, vẫn cần `block_accept` nội bộ một chu kỳ và quy định chính xác thời gian giữ dữ liệu.

## 5. Phát hiện mức cao

### H-01 — Thiếu tín hiệu kết thúc message và kết thúc phase

**Ảnh hưởng:** giao diện `TagProcessing`, FSM

`AAD_valid/CT_valid` chỉ cho biết block tại một thời điểm, không cho biết đã hết AAD hay hết Ciphertext. Một khoảng trống valid trong `GHASH_PROCESSING` hiện có thể bị hiểu là kết thúc dữ liệu. Thiết kế cũng không thể khởi chạy message có AAD và CT đều rỗng.

**Khuyến nghị:** Bổ sung `msg_start` và `in_last`, hoặc truyền trước `aad_len_bits/ct_len_bits`. Quy định rõ chuyển phase AAD → CT và cấm quay lại AAD sau khi đã nhận CT.

### H-02 — Không có khởi tạo theo từng message

**Ảnh hưởng:** accumulator GHASH và hai counter

Các thanh ghi chỉ được xóa bằng `rst_n`. Hai message liên tiếp sẽ kế thừa accumulator và độ dài nếu hệ thống không reset toàn cục giữa các message.

**Khuyến nghị:** Thêm `msg_start/ghash_init` để xóa đồng bộ accumulator và counter. Ghi rõ khả năng accept block đầu tiên cùng chu kỳ khởi tạo.

### H-03 — `valid_bits` không tạo zero-padding

**Ảnh hưởng:** block AAD/CT cuối

`AAD_valid_bits/CT_valid_bits` chỉ đi vào counter; toàn bộ 128 bit của bus dữ liệu vẫn được băm. Các bit không hợp lệ khác 0 sẽ làm sai GHASH.

**Khuyến nghị:** Yêu cầu upstream zero-fill hoặc tạo mask trong `GHASHInput`. Do dùng quy ước bit nội bộ, phải ghi rõ vùng bit hợp lệ nằm ở đầu nào của bus.

### H-04 — Miền giá trị `valid_bits` chưa được quy định

**Ảnh hưởng:** `GHASHInput`, counter

Bus 8 bit biểu diễn 0–255 nhưng block chỉ rộng 128 bit. Chưa xác định ý nghĩa của 0, giá trị 129–255, hoặc việc block không cuối có được nhỏ hơn 128 hay không.

**Khuyến nghị:** Quy định `1..128` cho block được accept, `128` cho block đầy đủ và assertion từ chối giá trị lớn hơn 128. Nếu hỗ trợ dữ liệu theo byte, cân nhắc `valid_bytes[4:0]` hoặc `keep[15:0]`.

### H-05 — Interface high-level và low-level của FSM không đồng nhất

**Ảnh hưởng:** `TagProcessingFSM`

Trong hình `TagProcessing high level`, FSM có input `clk`, `rst_n`, `ghash_ready`; không có input `AAD_valid` hay `CT_valid`. Hình low-level lại dùng `AAD_valid/CT_valid` cho next-state và không dùng `ghash_ready`. Module GHASH riêng cũng không xuất `ghash_ready`.

**Khuyến nghị:** Xóa `ghash_ready` nếu datapath cố định một chu kỳ, hoặc định nghĩa và nối nó xuyên suốt nếu GHASH nhiều chu kỳ. Bổ sung `AAD_valid/CT_valid` vào interface FSM high-level nếu chúng là input thật.

### H-06 — Luồng giải mã chưa xác định trách nhiệm kiểm tra Tag

**Ảnh hưởng:** mode giải mã

Thiết kế chọn `FIFO_CT` khi giải mã và xuất Tag tính được, nhưng không có `tag_in`, phép so sánh hay `auth_ok/auth_fail`. Có thể việc so sánh thuộc module ngoài, nhưng ranh giới trách nhiệm chưa được mô tả.

**Khuyến nghị:** Hoặc bổ sung đường kiểm tra Tag, hoặc ghi rõ `TagProcessing` chỉ tính `computed_tag` và module nào chịu trách nhiệm so sánh/không phát hành plaintext khi xác thực thất bại. Theo NIST SP 800-38D, authenticated decryption phải trả plaintext hoặc `FAIL` tùy kết quả Tag.

### H-07 — Latency và throughput chưa được đặc tả

**Ảnh hưởng:** toàn datapath

Không có timing contract cho thanh ghi `GHASHInput`, multiplier tổ hợp và accumulator. Bộ nhân X128 cùng reduction có đường tổ hợp lớn, nhưng chưa có mục tiêu clock, pipeline hoặc số block/chu kỳ.

**Khuyến nghị:** Bổ sung timing diagram và bảng latency/throughput. Chốt trước kiến trúc một chu kỳ hay nhiều chu kỳ rồi mới hoàn thiện FSM.

## 6. Phát hiện mức trung bình và thấp

### M-01 — `mode` và `data_type` thiếu bảng encoding

Chưa ghi rõ `mode=0/1`. Các giá trị `data_type` chỉ được suy ra từ mux. Nên định nghĩa enum: `IDLE=00`, `AAD=01`, `CT=10`, `LENGTH=11` và ENC/DEC tương ứng.

### M-02 — `ghash_out` bị mô tả như khóa

Trong `GHASH_Design.md`, `ghash_out` được gọi là “khóa băm GHASH”. `H_key` mới là hash subkey; `ghash_out` là accumulator/kết quả GHASH. Nên sửa thuật ngữ để tránh nhầm dữ liệu trạng thái với khóa.

### M-03 — Output `tag_ready` là pulse, không phải ready/valid handshake

Tên `tag_ready` thường diễn tả khả năng consumer nhận dữ liệu, nhưng bảng FSM dùng nó như xung hoàn tất từ producer. Nếu chỉ là xung một chu kỳ, tên `tag_done` hoặc `tag_valid_pulse` rõ hơn. Nếu consumer có thể stall, cần `tag_valid/tag_ready` hai chiều và giữ Tag ổn định.

### M-04 — Link hình phụ thuộc Obsidian

Các wiki-link không có đường dẫn như `![[Module X128 high level.png]]` phụ thuộc khả năng tìm file toàn vault của Obsidian. Markdown renderer thông thường có thể không hiển thị. Nên dùng link tương đối chuẩn.

### L-01 — Sơ đồ FSM high-level không ghi điều kiện chuyển

State graph cho thấy topology nhưng không có nhãn điều kiện hoặc priority. Bảng trạng thái và low-level mux phải gánh toàn bộ thông tin. Nên thêm nhãn cho các nhánh quan trọng để review trực quan dễ hơn.

## 7. Nhất quán giữa các artifact

| Hạng mục | Kết quả | Ghi chú |
|---|---|---|
| `GF128bitMultiply` table ↔ hình | Đạt | Cổng ngoài và độ rộng khớp |
| `GHASHInput` table ↔ hình high-level | Đạt | Tên, hướng, độ rộng và `rst_n` khớp |
| `GHASHInput` high ↔ low | Một phần | Low-level làm rõ counter; latency thanh ghi `data_in` chưa được ghi trong tài liệu |
| `GHASH` table ↔ hình riêng | Đạt | Không có `ghash_ready`; ghi chú trong tài liệu phản ánh đúng |
| `TagGeneration` table ↔ hình | Đạt | XOR tổ hợp, ba cổng khớp |
| `TagProcessing` table ↔ cổng ngoài | Đạt | Bảng có đủ `AAD_valid/CT_valid` như cổng ngoài top-level |
| FSM high-level ↔ FSM low-level | Không đạt | High-level thiếu `AAD_valid/CT_valid`, thừa `ghash_ready` |
| Bảng FSM ↔ decoder/mux low-level | Một phần | State/output khớp; nguồn `lenblk_valid` không tạo được transition hợp lệ |
| Design ↔ `GHASH.sv` | Không đạt | RTL dùng `load`, `ghash_finish[127:0]`, thân module trống |
| Design ↔ `TagGeneration.sv` | Không đạt | RTL còn `tagen_en/tag_ready` và tên input `data_in` |
| Design ↔ testbench | Chưa đủ | `GF128bitMultiply_tb.sv` có nội dung; `GHASH_tb.sv` không có test quan sát được |

## 8. Thứ tự xử lý đề xuất

1. Chốt timing pipeline giữa thanh ghi `GHASHInput` và accumulator; sửa vị trí assert `ghash_en`.
2. Thay `lenblk_valid` trong next-state bằng cờ `length_pending/end_of_message` độc lập.
3. Định nghĩa sự kiện `block_accept` dùng chung cho data register, counter và accumulator.
4. Bổ sung ranh giới message/phase và khởi tạo theo từng message.
5. Chốt zero-padding và miền hợp lệ của `valid_bits`.
6. Đồng bộ interface FSM high/low và quyết định có cần `ghash_ready` hay không.
7. Mô tả trách nhiệm xác thực Tag trong mode giải mã.
8. Đồng bộ RTL/testbench với đặc tả sau khi các quyết định trên được chốt.
9. Đo timing/synthesis rồi quyết định pipeline bộ nhân.

## 9. Kế hoạch kiểm thử

### 9.1. Timing và accept

- Một block AAD: chứng minh block tại `LOAD_AAD` chính là toán hạng của lần cập nhật GHASH.
- Hai block liên tiếp: không mất, lặp hoặc đảo block.
- Chèn khoảng trống giữa hai block: không tự kết thúc message nếu chưa có end marker.
- Giữ valid nhiều chu kỳ: counter và accumulator chỉ cập nhật một lần cho mỗi block.

### 9.2. Length Block

- AAD/CT đầy đủ 128 bit: counter tăng đúng 128.
- Block cuối có 1, 8, 127 và 128 bit hợp lệ.
- AAD rỗng, CT rỗng và cả hai rỗng.
- Kiểm tra trực tiếp block `{AAD_cnt, CT_cnt}` trước khi GHASH.
- `valid_bits` bằng 0, 129 và 255 phải bị từ chối hoặc có hành vi được đặc tả.

### 9.3. FSM

- `IDLE` giữ vô hạn khi không có request.
- AAD được ưu tiên khi hai valid cùng bật.
- Không nhận AAD sau khi đã chuyển sang CT.
- `LOAD_LENGTH_BLOCK` phải reachable đúng một lần mỗi message.
- Mọi message hợp lệ cuối cùng phải tới `FINISH`.
- Hai message liên tiếp không cần reset toàn cục.

### 9.4. Assertions

```text
counter_update == block_accept
ghash_update   == block_accept_or_length_accept
valid_bits <= 128 khi accept
data_in ổn định tại cạnh ghash_update
mỗi message có đúng một length_accept
H_key và E_key ổn định trong transaction
```

### 9.5. Công cụ

- Lint và compile top-level sau khi đồng bộ cổng.
- Unit test độc lập cho multiplier theo quy ước `block[i] ↔ x^i`.
- Test trạng thái trung gian GHASH, không chỉ Tag cuối.
- Synthesis để đo critical path multiplier/reduction.
- Sau khi thêm lớp đổi representation, chạy vector AES-GCM chuẩn ở biên hệ thống.

## 10. Tiêu chí nghiệm thu

- Timing diagram chỉ rõ cạnh accept, cạnh cập nhật accumulator và cạnh Tag hợp lệ.
- Data register, counter và accumulator dùng cùng một sự kiện accept hoặc pipeline-valid được chứng minh.
- `LOAD_LENGTH_BLOCK` reachable đúng một lần và không phụ thuộc output của chính trạng thái đó.
- Có start/end message và reset trạng thái theo từng message.
- Partial block được zero-pad theo quy ước bit đã công bố.
- Mọi bảng cổng/FSM khớp hình high-level và low-level.
- RTL compile được với đúng interface trong đặc tả.
- Regression bao phủ empty, partial, multi-block, gap, repeated message và invalid protocol.
- Trách nhiệm so sánh Tag khi giải mã được định nghĩa và kiểm thử.

## 11. Nguồn

- Các đặc tả và sơ đồ trong [`_design`](_design)
- RTL/testbench đối chiếu trong [`../../RTL/GCM-GHASH`](../../RTL/GCM-GHASH)
- [NIST SP 800-38D — Galois/Counter Mode (GCM) and GMAC](https://doi.org/10.6028/NIST.SP.800-38D), mục 6.4, 7.1 và 7.2
