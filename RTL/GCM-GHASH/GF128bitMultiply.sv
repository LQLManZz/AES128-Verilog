module GF128bitMultiply (
    input logic [127:0] H_key,
    input logic [127:0] data_in,

    output logic [127:0] data_out
);

endmodule

module X8 (
    input logic [7:0] data_in1,
    input logic [7:0] data_in2,

    output logic [15:0] data_out
);
    
endmodule

module X16 (
    input logic [15:0] data_in1,
    input logic [15:0] data_in2,

    output logic [31:0] data_out
);
    
endmodule

module X32 (
    input logic [31:0] data_in1,
    input logic [31:0] data_in2,

    output logic [63:0] data_out
);
    
endmodule

module X64 (
    input logic [63:0] data_in1,
    input logic [63:0] data_in2,

    output logic [127:0] data_out
);
    
endmodule

module X128 (
    input logic [127:0] data_in1,
    input logic [127:0] data_in2,

    output logic [255:0] data_out
);
    
endmodule

module ReductionBlock (
    input logic [255:0] data_in,

    output logic [127:0] data_out
);
    
endmodule