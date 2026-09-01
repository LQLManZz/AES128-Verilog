module AES_CTR(
    input logic clk, rst_n, finish_reset,
    input logic load_key, load_data, load_IV,
    input logic [127:0] cipher_key, data_in,
    input logic [95:0] IV,
    input logic expansion_en, mode,
    input logic data_in_last,
    output logic AES_finish, CTR_counter_overflow,
    output logic IV_loaded, expansion_finish,
    output logic [127:0] H, E, data_out, CT,
    output logic data_out_last,
    output logic H_valid, E_valid, data_valid,
    output logic CT_last, CT_valid);
    
    logic gen_J0;
    always_ff @(posedge clk or negedge rst_n) begin
        if(!rst_n)
            gen_J0 <= 1'b0;
        else begin
            gen_J0 <= data_in_last;
        end
    end
    
    logic data_req;
    logic [128:0] FIFO_data_in;
    logic [128:0] FIFO_data;
    assign FIFO_data_in = {data_in_last,data_in};
    FIFO #(.DATA_SIZE(129),.DEPTH(16)) fifo 
            (.clk(clk),.rst_n(rst_n),.data_in(FIFO_data_in),.w_en(load_data),.r_en(data_req),
            .data_out(FIFO_data));
    logic [127:0] round_key [0:10];
    KeyExpansion key_expan (.clk(clk),.rst_n(rst_n),.expansion_en(expansion_en),
                            .cipher_key(cipher_key),.round_key(round_key),
                            .expansion_finish(expansion_finish));
    logic [127:0] AES_data_in;
    logic [1:0] data_type_in;
    counter_generator count_gen (.clk(clk),.rst_n(rst_n),.finish_reset(finish_reset),
                                .gen_J0(gen_J0),.load_key(load_key),.load_data(load_data),
                                .load_IV(load_IV),.IV(IV),.data_type(data_type_in),
                                .data_out(AES_data_in),.IV_loaded(IV_loaded),
                                .CTR_counter_overflow(CTR_counter_overflow));
    logic [127:0] AES_data_out;
    logic [1:0] data_type_out;
    AES_encryption AES (.clk(clk),.rst_n(rst_n),.data_in(AES_data_in),.round_key(round_key),
                        .data_type_in(data_type_in),.data_out(AES_data_out),
                        .data_type_out(data_type_out),.data_req(data_req),
                        .AES_finish(AES_finish));
    logic [127:0] keystream;
    always_comb begin
        H = 128'b0;
        E = 128'b0;
        keystream = 128'b0;
        H_valid = 1'b0;
        data_valid = 1'b0;
        E_valid = 1'b0;
        case(data_type_out)
            2'b01: begin
                H = AES_data_out;
                H_valid = 1'b1;
            end
            2'b10: begin
                keystream = AES_data_out;
                data_valid = 1'b1;
            end
            2'b11: begin
                E = AES_data_out;
                E_valid = 1'b1;
            end
            default: begin
                H = 128'b0;
                E = 128'b0;
                keystream = 128'b0;
                H_valid = 1'b0;
                data_valid = 1'b0;
                E_valid = 1'b0;
            end
        endcase
    end
    assign data_out = FIFO_data [127:0] ^ keystream;
    assign data_out_last = data_valid & FIFO_data [128];
    assign CT = mode? FIFO_data : data_out; 
    assign CT_valid = data_valid;
    assign CT_last  = data_out_last;
endmodule
