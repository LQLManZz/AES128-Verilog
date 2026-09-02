module J0_register(
    input logic clk, finish_reset,
    input logic [31:0] CTR_counter,
    input logic [127:0] counter_block,
    output logic [127:0] J0);
    
    always @(posedge clk or posedge finish_reset) begin
        if(finish_reset)
            J0 <= 128'b0;
        else begin
            if(CTR_counter == 32'b0)
                J0 <= counter_block;
        end
    end
endmodule
