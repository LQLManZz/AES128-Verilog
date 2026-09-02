module IV_register(
    input logic clk, finish_reset,
    input logic load_IV,
    input logic [95:0] IV,
    output logic IV_loaded,
    output logic [95:0] IV_out
);

    always_ff @(posedge clk or posedge finish_reset) begin
        if(finish_reset) begin
            IV_loaded <= 1'b0;
            IV_out <= 96'b0;
        end
        else begin
            if(load_IV) begin
                IV_out <= IV;
                IV_loaded <= 1'b1;
            end
        end
    end
endmodule
