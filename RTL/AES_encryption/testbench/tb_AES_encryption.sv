`timescale 1ns/1ps

module tb_AES_encryption;

logic clk;
logic rst_n;

logic [127:0] data_in;
logic [127:0] round_key [0:10];
logic [1:0] data_type_in;

logic [127:0] data_out;
logic [1:0] data_type_out;
logic data_req;
logic AES_finish;

AES_encryption dut(
    .clk(clk),
    .rst_n(rst_n),
    .data_in(data_in),
    .round_key(round_key),
    .data_type_in(data_type_in),
    .data_out(data_out),
    .data_type_out(data_type_out),
    .data_req(data_req),
    .AES_finish(AES_finish)
);

//////////////////////////////////////////////////////
// Clock
//////////////////////////////////////////////////////

initial begin
    clk = 0;
    forever #5 clk = ~clk;
end

//////////////////////////////////////////////////////
// Test vector
//////////////////////////////////////////////////////

logic [127:0] key;
logic [95:0]  IV;

initial begin

    //--------------------------------------------
    // AES-128 key
    //--------------------------------------------
    key = 128'h2b7e151628aed2a6abf7158809cf4f3c;

    //--------------------------------------------
    // 96-bit IV
    //--------------------------------------------
    IV = 96'hcafebabefacedbaddecaf888;

    //--------------------------------------------
    // Chỉ để test pipeline.
    // Sau này thay bằng key expansion thật.
    //--------------------------------------------
    round_key[0]  = key;
    round_key[1]  = key ^ 128'h00000000000000000000000000000001;
    round_key[2]  = key ^ 128'h00000000000000000000000000000002;
    round_key[3]  = key ^ 128'h00000000000000000000000000000003;
    round_key[4]  = key ^ 128'h00000000000000000000000000000004;
    round_key[5]  = key ^ 128'h00000000000000000000000000000005;
    round_key[6]  = key ^ 128'h00000000000000000000000000000006;
    round_key[7]  = key ^ 128'h00000000000000000000000000000007;
    round_key[8]  = key ^ 128'h00000000000000000000000000000008;
    round_key[9]  = key ^ 128'h00000000000000000000000000000009;
    round_key[10] = key ^ 128'h0000000000000000000000000000000A;

    //--------------------------------------------
    // Reset
    //--------------------------------------------
    rst_n = 0;
    data_in = 0;
    data_type_in = 2'b00;

    repeat(3) @(posedge clk);

    rst_n = 1;

    /////////////////////////////////////////////////////////
    // H = AES(K,0)
    /////////////////////////////////////////////////////////

    @(posedge clk);
    data_in      <= 128'h0;
    data_type_in <= 2'b01;

    /////////////////////////////////////////////////////////
    // Counter = 2
    /////////////////////////////////////////////////////////

    @(posedge clk);
    data_in      <= {IV,32'h00000002};
    data_type_in <= 2'b10;

    /////////////////////////////////////////////////////////
    // Counter = 3
    /////////////////////////////////////////////////////////

    @(posedge clk);
    data_in      <= {IV,32'h00000003};
    data_type_in <= 2'b10;

    /////////////////////////////////////////////////////////
    // Counter = 4
    /////////////////////////////////////////////////////////

    @(posedge clk);
    data_in      <= {IV,32'h00000004};
    data_type_in <= 2'b10;

    /////////////////////////////////////////////////////////
    // J0
    /////////////////////////////////////////////////////////

    @(posedge clk);
    data_in      <= {IV,32'h00000001};
    data_type_in <= 2'b11;

    /////////////////////////////////////////////////////////
    // Không còn dữ liệu
    /////////////////////////////////////////////////////////

    @(posedge clk);
    data_in <= 0;
    data_type_in <= 2'b00;

    repeat(20) @(posedge clk);

    $finish;

end

//////////////////////////////////////////////////////
// Monitor
//////////////////////////////////////////////////////

always @(posedge clk) begin

    $display("time=%0t", $time);
    $display("type_in=%b  type_out=%b  req=%b  finish=%b",
             data_type_in,
             data_type_out,
             data_req,
             AES_finish);

    if(data_type_out!=2'b00) begin
        $display("Output = %032h",data_out);
    end

end

//////////////////////////////////////////////////////
// Dump
//////////////////////////////////////////////////////

initial begin
    $dumpfile("AES_encryption.vcd");
    $dumpvars(0,tb_AES_encryption);
end

endmodule
