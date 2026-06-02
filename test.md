kakajam
```
// =====================================================================
// 1. KHAI BÁO MODULE, THAM SỐ VÀ CỔNG
// =====================================================================
module Verilog_CheatSheet #(
    parameter P_WIDTH = 8,          // Tham số có thể ghi đè khi gọi module
    localparam L_MAX = 255          // Hằng số nội bộ, KHÔNG thể ghi đè
)(
    input  wire                 clk,        // Cổng vào 1 bit
    input  wire [P_WIDTH-1:0]   in_bus,     // Cổng vào nhiều bit (Bus)
    output reg  [P_WIDTH-1:0]   out_bus,    // Cổng ra kiểu reg (dùng trong always)
    inout  wire                 io_pin      // Cổng 2 chiều
);

// =====================================================================
// 2. KHAI BÁO KIỂU DỮ LIỆU VÀ BỘ NHỚ
// =====================================================================
    wire        w_flag;                     // Dây dẫn đơn
    wire [7:0]  w_vector;                   // Dây dẫn bus 8 bit
    
    reg         r_bit;                      // Biến lưu trữ 1 bit
    reg  [15:0] r_word;                     // Biến lưu trữ 16 bit
    
    integer     i;                          // Kiểu số nguyên (thường dùng cho vòng lặp)
    genvar      g;                          // Biến đếm dùng riêng cho khối generate
    
    // Khai báo mảng 2 chiều (Bộ nhớ / RAM / ROM / FIFO)
    reg [7:0]   r_memory [0:63];            // Mảng gồm 64 phần tử, mỗi phần tử 8 bit

// =====================================================================
// 3. TOÁN TỬ (OPERATORS) - MÔ HÌNH DATAFLOW
// =====================================================================
    // a. Toán tử số học (Arithmetic)
    wire [7:0] w_add = in_bus + 1'b1;       // Cộng
    wire [7:0] w_sub = in_bus - 1'b1;       // Trừ
    wire [7:0] w_mul = in_bus * 2;          // Nhân
    wire [7:0] w_div = in_bus / 2;          // Chia
    wire [7:0] w_mod = in_bus % 2;          // Chia lấy dư (Modulo)
    wire [7:0] w_exp = in_bus ** 2;         // Lũy thừa (Verilog-2001)

    // b. Toán tử thao tác Bit (Bitwise) - Tác động lên từng bit tương ứng
    wire [7:0] w_b_and  = in_bus & r_word[7:0]; // AND
    wire [7:0] w_b_or   = in_bus | r_word[7:0]; // OR
    wire [7:0] w_b_xor  = in_bus ^ r_word[7:0]; // XOR
    wire [7:0] w_b_not  = ~in_bus;              // Đảo bit (NOT)
    wire [7:0] w_b_xnor = in_bus ~^ r_word[7:0];// XNOR (hoặc ^~)

    // c. Toán tử Logic (Logical) - Trả về 1 (True) hoặc 0 (False)
    wire w_l_and = (in_bus > 0) && (r_bit == 1);  // AND logic
    wire w_l_or  = (in_bus == 0) || (r_bit == 0); // OR logic
    wire w_l_not = !(in_bus);                     // Phủ định logic

    // d. Toán tử Thu gọn (Reduction) - Gom 1 bus thành 1 bit
    wire w_r_and  = &in_bus;                // AND tất cả các bit của in_bus với nhau
    wire w_r_or   = |in_bus;                // OR tất cả các bit
    wire w_r_xor  = ^in_bus;                // XOR tất cả các bit (Kiểm tra Parity)

    // e. Toán tử Dịch (Shift)
    wire [7:0] w_shl  = in_bus << 2;        // Dịch trái logic (nhồi 0 vào phải)
    wire [7:0] w_shr  = in_bus >> 2;        // Dịch phải logic (nhồi 0 vào trái)
    wire [7:0] w_ashl = in_bus <<< 2;       // Dịch trái số học
    wire [7:0] w_ashr = in_bus >>> 2;       // Dịch phải số học (giữ nguyên bit dấu)

    // f. Toán tử Quan hệ & So sánh (Relational & Equality)
    wire w_gt  = (in_bus > 5);              // Lớn hơn
    wire w_lt  = (in_bus < 5);              // Nhỏ hơn
    wire w_gte = (in_bus >= 5);             // Lớn hơn hoặc bằng
    wire w_lte = (in_bus <= 5);             // Nhỏ hơn hoặc bằng
    wire w_eq  = (in_bus == 5);             // Bằng logic
    wire w_neq = (in_bus != 5);             // Khác logic
    wire w_ceq = (in_bus === 8'bx);         // Bằng tuyệt đối (xét cả bit x và z)
    wire w_cne = (in_bus !== 8'bz);         // Khác tuyệt đối

    // g. Toán tử Ghép nối & Nhân bản (Concatenation & Replication)
    wire [15:0] w_concat = {in_bus, 8'b1010_0000}; // Ghép 2 bus thành 1 bus lớn
    wire [15:0] w_repl   = {4{in_bus[3:0]}};       // Lặp lại 4 lần cụm 4 bit

    // h. Toán tử Điều kiện (Ternary)
    wire w_mux = (in_bus > 10) ? 1'b1 : 1'b0; // Nếu đúng chọn vế trái, sai chọn vế phải

// =====================================================================
// 4. MÔ HÌNH CẤU TRÚC (STRUCTURAL MODELING) - CỔNG CƠ BẢN
// =====================================================================
    // Cú pháp: tên_cổng tên_thể_hiện (ngõ_ra, ngõ_vào_1, ngõ_vào_2...);
    and  U1 (w_flag, in_bus[0], in_bus[1]);
    or   U2 (w_vector[0], in_bus[2], in_bus[3]);
    nand U3 (w_vector[1], in_bus[4], in_bus[5]);
    nor  U4 (w_vector[2], in_bus[6], in_bus[7]);
    xor  U5 (w_vector[3], in_bus[0], in_bus[7]);
    xnor U6 (w_vector[4], in_bus[1], in_bus[6]);
    not  U7 (w_vector[5], in_bus[0]);
    buf  U8 (w_vector[6], in_bus[1]);

    // Tristate Buffer (Đệm 3 trạng thái cho cổng inout)
    bufif1 U9 (io_pin, out_bus[0], r_bit); // Xuất ra io_pin nếu r_bit = 1, ngược lại High-Z

// =====================================================================
// 5. MÔ HÌNH HÀNH VI (BEHAVIORAL MODELING)
// =====================================================================
    
    // a. Mạch tổ hợp với if-else và case
    always @(*) begin
        // Phép gán Blocking (=) cho mạch tổ hợp
        r_word = 16'd0; 
        
        // Cấu trúc if - else if - else
        if (in_bus == 8'hFF) begin
            r_bit = 1'b1;
        end else if (in_bus == 8'h00) begin
            r_bit = 1'b0;
        end else begin
            r_bit = w_flag;
        end

        // Cấu trúc Case
        case (in_bus[1:0])
            2'b00: r_word[0] = 1'b1;
            2'b01: r_word[1] = 1'b1;
            2'b10: r_word[2] = 1'b1;
            2'b11: r_word[3] = 1'b1;
            default: r_word = 16'd0; // Luôn phải có default để tránh sinh ra chốt (latch)
        endcase

        // Casex: Bỏ qua các bit 'x' và 'z' khi so sánh
        casex (in_bus)
            8'b1xxx_xxxx: r_word[4] = 1'b1; // Bắt bit MSB bằng 1, các bit khác không quan tâm
            default: r_word[4] = 1'b0;
        endcase

        // Casez: Bỏ qua các bit 'z' (?) khi so sánh
        casez (in_bus)
            8'b01??_????: r_word[5] = 1'b1;
            default: r_word[5] = 1'b0;
        endcase
    end

    // b. Mạch tuần tự với Vòng lặp for
    always @(posedge clk) begin
        // Phép gán Non-blocking (<=) cho mạch tuần tự
        // Vòng lặp for tổng hợp được thành phần cứng (nhân bản logic)
        for (i = 0; i < P_WIDTH; i = i + 1) begin
            out_bus[i] <= in_bus[i] ^ r_bit;
        end
    end

// =====================================================================
// 6. CÁC CẤU TRÚC NÂNG CAO
// =====================================================================
    
    // a. Khối Generate (Dùng để nhân bản module/khối logic hàng loạt khi biên dịch)
    generate
        for (g = 0; g < 4; g = g + 1) begin : GEN_BLOCK_NAME
            // Sẽ sinh ra 4 lệnh assign độc lập
            assign w_vector[g+4] = in_bus[g] & clk;
        end
    endgenerate

    // b. Hàm (Function) - Trả về 1 giá trị, thực thi tức thời (Mạch tổ hợp)
    function [7:0] reverse_bits;
        input [7:0] data_in;
        integer k;
        begin
            for (k = 0; k < 8; k = k + 1) begin
                reverse_bits[k] = data_in[7-k];
            end
        end
    endfunction

    // c. Tác vụ (Task) - Có thể có nhiều ngõ ra, ngõ vào (Thường dùng chia nhỏ code)
    task add_and_shift;
        input  [7:0] a;
        input  [7:0] b;
        output [7:0] res;
        begin
            res = (a + b) << 1;
        end
    endtask

endmodule
```