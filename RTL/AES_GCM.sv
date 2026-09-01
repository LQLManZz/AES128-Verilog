module AES_GCM(
    input logic clk, rst_n,
    input logic load_key, load_IV,
    input logic mode, load_tag_ref,
    input logic load_AAD, no_AAD, AAD_last,
    input logic load_data, data_in_last,
    input logic [127:0] cipher_key, tag_ref,
    input logic [127:0] AAD, data_in,
    input logic [95:0] IV,
    output logic tag_valid, verify_pass,
    output logic CTR_counter_overflow,
    output logic data_valid, data_out_last,
    output logic finish, tag_ref_ready,
    output logic key_ready, IV_ready,
    output logic AAD_ready, data_ready,
    output logic [127:0] tag, data_out
    );

    logic start, finish_reset;
    assign start = load_key | load_IV;
    assign finish_reset = (~rst_n) | finish;
    
    logic expansion_en, expansion_finish;
    logic AES_finish, IV_loaded;
    logic [127:0] H, E, CT;
    logic H_valid, E_valid, CT_valid;
    logic CT_last;
    
    AES_CTR AES (.clk(clk),.rst_n(rst_n),.finish_reset(finish_reset),.load_key(load_key),
                .load_IV(load_IV),.load_data(load_data),.cipher_key(cipher_key),
                .data_in(data_in),.IV(IV),.expansion_en(expansion_en),.mode(mode),
                .data_in_last(data_in_last),.AES_finish(AES_finish),.IV_loaded(IV_loaded),
                .CTR_counter_overflow(CTR_counter_overflow),.expansion_finish(expansion_finish),
                .H(H),.E(E),.data_out(data_out),.CT(CT),.data_out_last(data_out_last),
                .H_valid(H_valid),.E_valid(E_valid),.data_valid(data_valid),.CT_valid(CT_valid),
                .CT_last(CT_last));
    
    logic H_loaded, tag_ref_loaded, tag_process_finish;
    
    TagProcessing tag_pro (.clk(clk),.rst_n(rst_n),.finish_reset(finish_reset),
                            .load_key(load_key),.mode(mode),.AAD(AAD),.CT(CT),
                            .tag_ref(tag_ref),.H(H),.E(E),.load_AAD(load_AAD),
                            .load_CT(CT_valid),.H_valid(H_valid),.E_valid(E_valid),
                            .load_tag_ref(load_tag_ref),.CT_last(CT_last),.H_loaded(H_loaded),
                            .tag_ref_loaded(tag_ref_loaded),.tag(tag),
                            .tag_process_valid(tag_process_finish),.verify_pass(verify_pass));
    
    logic process_finish;
    assign process_finish = AES_finish & tag_process_finish;
    CU cu (.clk(clk),.rst_n(rst_n),.start(start),.load_key(load_key),
            .expansion_finish(expansion_finish),.H_loaded(H_loaded),.IV_loaded(IV_loaded),
            .tag_ref_loaded(tag_ref_loaded),.mode(mode),.load_AAD(load_AAD),.no_AAD(no_AAD),
            .AAD_last(AAD_last),.load_data(load_data),.data_in_last(data_in_last),
            .process_finish(process_finish),.expansion_en(expansion_en),.finish(finish),
            .key_ready(key_ready),.IV_ready(IV_ready),.tag_ref_ready(tag_ref_ready),
            .AAD_ready(AAD_ready),.data_ready(data_ready));
    
    assign tag_valid = (~mode) & tag_process_finish;
endmodule
