module counter_generator(
    input logic clk,rst_n,
    input logic finish_reset,
    input logic load_key, load_data, 
    input logic gen_J0, load_IV,
    input logic [95:0] IV,
    output logic CTR_counter_overflow, IV_loaded, 
    output logic [1:0] data_type,
    output logic [127:0] data_out
    );

    logic [31:0] CTR_counter;
    CTR_counter coun (.clk(clk),.finish_reset(finish_reset),.counter_en(load_data),
                        .CTR_counter_overflow(CTR_counter_overflow),.CTR_counter(CTR_counter));
    logic [95:0] IV_out;
    IV_register IV_reg (.clk(clk),.load_IV(load_IV),.finish_reset(finish_reset),
                        .IV(IV),.IV_loaded(IV_loaded),.IV_out(IV_out));
    logic [127:0] counter_block;
    counter_block_generator CBG (.CTR_counter(CTR_counter),.IV_out(IV_out),
                                .counter_block(counter_block));
    logic [127:0] J0;
    J0_register J0_reg (.clk(clk),.finish_reset(finish_reset),.counter_block(counter_block),
                        .CTR_counter(CTR_counter),.J0(J0));
    type_generator gentype (.clk(clk),.rst_n(rst_n),.load_key(load_key),.load_data(load_data),
                            .gen_J0(gen_J0),.data_type(data_type));
    output_unit ou (.data_type(data_type),.counter_block(counter_block),.J0(J0),
                    .data_out(data_out));
endmodule
