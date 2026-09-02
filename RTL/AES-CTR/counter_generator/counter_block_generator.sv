module counter_block_generator(
    input logic [31:0] CTR_counter,
    input logic [95:0] IV_out,
    output logic [127:0] counter_block);
    
    assign counter_block = {IV_out,CTR_counter+32'b1};
endmodule
