# High level Design

![[TagProcessing high level.png]]

| Tín hiệu         | Hướng  | Độ rộng | Mô tả                                                        |
| :--------------- | :----- | :------ | :----------------------------------------------------------- |
| `clk`            | Input  | 1 bit   | Xung clock                                                   |
| `rst_n`          | Input  | 1 bit   | Tín hiệu reset mức thấp                                      |
| `mode`           | Input  | 1 bit   | Lựa chọn giữa chế độ mã hóa hoặc giải mã                     |
| `AAD_block`      | Input  | 128 bit | Dữ liệu vào (AAD)                                            |
| `CTR_CT`         | Input  | 128 bit | Dữ liệu vào (Ciphertext) lấy từ CTR, phục vụ chế độ mã hóa   |
| `FIFO_CT`        | Input  | 128 bit | Dữ liệu vào (Ciphertext) lấy từ FIFO, phục vụ chế độ giải mã |
| `H_key`          | Input  | 128 bit | Khóa $H=AES_{K}(0)$                                          |
| `E_key`          | Input  | 128 bit | Khóa $E=AES_{K}(J_{0})$                                      |
| `AAD_valid_bits` | Input  | 8 bit   | Số bits hợp lệ của AAD                                       |
| `CT_valid_bits`  | Input  | 8 bit   | Số bits hợp lệ của Ciphertext                                |
| `AAD_valid`      | Input  | 1 bit   | Cờ báo AAD hợp lệ                                            |
| `CT_valid`       | Input  | 1 bit   | Cờ báo Ciphertext hợp lệ                                     |
| `tag`            | Output | 128 bit | Authentication Tag                                           |
| `tag_ready`      | Output | 1 bit   | Báo hiệu đã hoàn tất quá trình sinh Tag                      |

# FSM

![[TagProcessing FSM.png]]

| Trạng thái hiện tại | Mã trạng thái | Hoạt động và tín hiệu điều khiển                                                                                     | Trạng thái tiếp theo | Điều kiện chuyển trạng thái                                          |
| :------------------ | :-----------: | :------------------------------------------------------------------------------------------------------------------- | :------------------- | :------------------------------------------------------------------- |
| `IDLE`              |   `3'b000`    | Chờ dữ liệu; hạ `lenblk_valid`, `ghash_en` và `tag_ready`; đặt `data_type = 2'b00`.                                  | `LOAD_AAD`           | `AAD_valid = 1'b1`.                                                  |
| ↳                   |               |                                                                                                                      | `LOAD_CT`            | `AAD_valid = 1'b0` và `CT_valid = 1'b1`.                             |
| ↳                   |               |                                                                                                                      | `IDLE`               | `AAD_valid = 1'b0` và `CT_valid = 1'b0`.                             |
| `LOAD_AAD`          |   `3'b001`    | Đưa `AAD_block` đến `GHASHInput`; đặt `data_type = 2'b01` và `ghash_en = 1'b1`.                                     | `GHASH_PROCESSING`   | Chuyển trạng thái ở chu kỳ kế tiếp.                                  |
| `LOAD_CT`           |   `3'b010`    | Chọn `CTR_CT` khi mã hóa hoặc `FIFO_CT` khi giải mã; đặt `data_type = 2'b10` và `ghash_en = 1'b1`.                  | `GHASH_PROCESSING`   | Chuyển trạng thái ở chu kỳ kế tiếp.                                  |
| `LOAD_LENGTH_BLOCK` |   `3'b011`    | Ghép `length_block = {len(AAD), len(C)}` rồi đưa đến `GHASHInput`; đặt `data_type = 2'b11`, `lenblk_valid = 1'b1` và `ghash_en = 1'b1`. | `GHASH_PROCESSING`   | Chuyển trạng thái ở chu kỳ kế tiếp.                                  |
| `GHASH_PROCESSING`  |   `3'b100`    | Hạ `ghash_en`; chọn khối dữ liệu tiếp theo hoặc chuyển sang sinh Tag.                                                | `LOAD_AAD`           | `AAD_valid = 1'b1`.                                                  |
| ↳                   |               |                                                                                                                      | `LOAD_CT`            | `AAD_valid = 1'b0` và `CT_valid = 1'b1`.                             |
| ↳                   |               |                                                                                                                      | `LOAD_LENGTH_BLOCK`  | `AAD_valid = 1'b0`, `CT_valid = 1'b0` và `lenblk_valid = 1'b1`.      |
| ↳                   |               |                                                                                                                      | `TAG_GENERATION`     | `AAD_valid = 1'b0`, `CT_valid = 1'b0` và `lenblk_valid = 1'b0`.      |
| `TAG_GENERATION`    |   `3'b101`    | Giữ kết quả GHASH cuối cùng ổn định; tính `tag = ghash_out ^ E_key`.                                                 | `FINISH`             | Chuyển trạng thái ở chu kỳ kế tiếp.                                  |
| `FINISH`            |   `3'b110`    | Giữ `tag` hợp lệ và đặt `tag_ready = 1'b1` trong một chu kỳ để báo hoàn tất.                                         | `IDLE`               | Hoàn tất xung báo `tag_ready`; trở về trạng thái chờ ở chu kỳ kế tiếp. |

> [!NOTE]
> Bảng trên bám theo logic chuyển trạng thái trong hình low-level. Tín hiệu `ghash_ready` có trên giao diện `TagProcessingFSM` ở hình high-level nhưng chưa được sử dụng trong mạch next-state của hình low-level. Tín hiệu `lenblk_valid` cũng đang được thể hiện vừa là điều kiện chọn trạng thái kế tiếp, vừa là đầu ra của bộ giải mã trạng thái; nguồn hoặc đường hồi tiếp của tín hiệu này cần được xác định rõ khi hiện thực RTL.

# Low level Design

![[TagProcessing FSM low level.png]]
