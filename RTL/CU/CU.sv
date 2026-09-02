module CU(
    input logic clk, rst_n,
    input logic start, load_key,
    input logic expansion_finish,
    input logic H_loaded, IV_loaded,
    input logic tag_ref_loaded, mode,
    input logic load_AAD, no_AAD, AAD_last,
    input logic load_data, data_in_last,
    input logic process_finish, verify_checked,
    input logic CTR_counter_overflow,
    output logic expansion_en,
    output logic finish,
    output logic key_ready, IV_ready,
    output logic tag_ref_ready,
    output logic AAD_ready, data_ready,
    output logic verify_done
    );
    
    typedef enum logic [3:0] {
        IDLE,
        KEY_EXPANSION,
        WAIT_H_CAL,
        WAIT_TAG_REF,
        WAIT_AAD,
        LOAD_AAD,
        WAIT_DATA,
        LOAD_DATA,
        WAIT_PROCESS_FINISH,
        VERIFY_PASS,
        FINISH
        } state;
    state Current, Next;
    // state register
    always_ff @(posedge clk or negedge rst_n) begin
        if(!rst_n)
            Current <= IDLE;
        else
            Current <= Next;
    end
    // next-stage logic
    always_comb begin
        Next = Current;
        case(Current)
            IDLE: begin
                if(start) begin
                    if(load_key)
                        Next = KEY_EXPANSION;
                    else begin
                        if(mode) 
                            Next = WAIT_TAG_REF;
                        else 
                            Next = WAIT_AAD;
                    end
                end
            end
            KEY_EXPANSION: begin
                if(expansion_finish)
                    Next = WAIT_H_CAL;
            end
            WAIT_H_CAL: begin
                if(H_loaded) begin
                    if(IV_loaded) begin
                        if(!tag_ref_loaded&&mode)
                            Next = WAIT_TAG_REF;
                        else
                            Next = WAIT_AAD;
                    end
                    else 
                        Next = FINISH;
                end
            end
            WAIT_TAG_REF: begin
                if(tag_ref_loaded)
                    Next = WAIT_AAD;
            end
            WAIT_AAD: begin
                if(no_AAD)
                    Next = WAIT_DATA;
                else begin
                    if(load_AAD)
                        Next = LOAD_AAD;
                end
            end
            LOAD_AAD: begin
                if(AAD_last)
                    Next = WAIT_DATA;
            end
            WAIT_DATA: begin
                if(load_data)
                    Next = LOAD_DATA;
            end
            LOAD_DATA: begin
                if(data_in_last)
                    Next = WAIT_PROCESS_FINISH;
            end
            WAIT_PROCESS_FINISH: begin
                if(process_finish) begin
                    if (mode) 
                        Next = VERIFY_PASS;
                    else
                        Next = FINISH;
                end
            end
            VERIFY_PASS: begin
                if(verify_checked)
                    Next = FINISH;
            end
            FINISH: begin
                Next = IDLE;
            end
            default: begin
                Next = IDLE;
            end
        endcase
    end
    // output logic stage
    always_comb begin
        expansion_en  = 1'b0;
        finish        = 1'b0;
        key_ready     = 1'b0;
        IV_ready      = 1'b0;
        tag_ref_ready = 1'b0;
        AAD_ready     = 1'b0;
        data_ready    = 1'b0;
        verify_done   = 1'b0;
        case(Current)
            IDLE: begin
                key_ready = 1'b1;
                if(H_loaded)
                    IV_ready = 1'b1;
            end
            KEY_EXPANSION: begin
                expansion_en = 1'b1;
                if(!IV_loaded)
                    IV_ready = 1'b1;
                if (!tag_ref_loaded&&mode)
                    tag_ref_ready = 1'b1;
            end
            WAIT_H_CAL: begin
                if(!IV_loaded)
                    IV_ready = 1'b1;
                if (!tag_ref_loaded&&mode)
                    tag_ref_ready = 1'b1;
            end
            WAIT_TAG_REF: begin
                if (!tag_ref_loaded&&mode)
                    tag_ref_ready = 1'b1;
            end
            WAIT_AAD: begin
                AAD_ready = 1'b1;
            end
            LOAD_AAD: begin
                AAD_ready = 1'b1;
            end
            WAIT_DATA: begin
                data_ready = 1'b1;
            end
            LOAD_DATA: begin
                if (!CTR_counter_overflow)
                    data_ready = 1'b1;
                else
                    data_ready = 1'b0;
            end
            VERIFY_PASS: begin
                verify_done = 1'b1;
            end
            FINISH: begin
                finish = 1'b1;
            end
            default: begin
                expansion_en  = 1'b0;
                finish        = 1'b0;
                key_ready     = 1'b0;
                IV_ready      = 1'b0;
                tag_ref_ready = 1'b0;
                AAD_ready     = 1'b0;
                data_ready    = 1'b0;
                verify_done   = 1'b0;
            end
        endcase
    end
endmodule
