module AddRoundKeys(
    input logic  [127:0] RoundKey, AddRoundKeys_in,
    output logic [127:0] AddRoundKeys_out);
    assign AddRoundKeys_out = AddRoundKeys_in ^ RoundKey;
endmodule
