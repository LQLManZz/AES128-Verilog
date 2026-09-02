module CTR_counter
(   input logic clk, finish_reset,
    input logic counter_en,
    output logic CTR_counter_overflow,
    output logic [31:0] CTR_counter
);
    
    always_ff @( posedge clk or posedge finish_reset) begin
        if(finish_reset)
            CTR_counter <= 32'b0;
        else begin
            if(!CTR_counter_overflow&&counter_en)
                CTR_counter <= CTR_counter+1;
        end
    end
    assign CTR_counter_overflow = (CTR_counter == 32'hff_ff_ff_ff);
endmodule

