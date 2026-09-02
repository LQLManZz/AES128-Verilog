module output_unit(
    input logic [1:0] data_type,
    input logic [127:0] counter_block,
    input logic [127:0] J0,
    output logic [127:0] data_out
    );
    
    always_comb begin
        case(data_type)
            2'b01: data_out = 128'b0;
            2'b10: data_out = counter_block;
            2'b11: data_out = J0;
            default: data_out = 128'b0;
        endcase
    end
endmodule
