`timescale 1ns/1ps

module tb_FIFO_in;

    //-----------------------------------------
    // Signals
    //-----------------------------------------
    logic clk;
    logic rst_n;

    logic [127:0] data_in;
    logic r_in_en;
    logic w_in_en;

    logic [127:0] data_out;
    logic empty;
    logic full;

    //-----------------------------------------
    // DUT
    //-----------------------------------------
    FIFO_in dut(
        .clk(clk),
        .rst_n(rst_n),
        .data_in(data_in),
        .r_in_en(r_in_en),
        .w_in_en(w_in_en),
        .data_out(data_out),
        .empty(empty),
        .full(full)
    );

    //-----------------------------------------
    // Clock
    //-----------------------------------------
    initial clk = 0;
    always #5 clk = ~clk;

    //-----------------------------------------
    // Waveform
    //-----------------------------------------
    initial begin
        $dumpfile("wave.vcd");
        $dumpvars(0, tb_FIFO_in);
    end

    //-----------------------------------------
    // Test
    //-----------------------------------------
    integer tx_data;

    initial begin

        //-----------------------------
        // Reset
        //-----------------------------
        rst_n   = 0;
        w_in_en = 0;
        r_in_en = 0;
        data_in = 0;
        tx_data = 1;

        #20;
        rst_n = 1;

        //-------------------------------------------------
        // STAGE 1: WRITE 5
        //-------------------------------------------------
        $display("\n========== STAGE 1 : WRITE 5 ==========");

        w_in_en = 1;
        r_in_en = 0;

        repeat(5) begin
            @ (posedge clk);
            data_in = tx_data;
            tx_data = tx_data + 1;
        end

        //-------------------------------------------------
        // STAGE 2: READ + WRITE 5 cycles
        //-------------------------------------------------
        $display("\n========== STAGE 2 : READ + WRITE ==========");

        w_in_en = 1;
        r_in_en = 1;

        repeat(5) begin
            @ (posedge clk);
            data_in = tx_data;
            tx_data = tx_data + 1;
        end

        //-------------------------------------------------
        // STAGE 3 + 4 FIXED:
        // WRITE until FULL, FULL lên là bật READ ngay
        //-------------------------------------------------
        $display("\n========== STAGE 3-4 : WRITE UNTIL FULL THEN READ ==========");

        r_in_en = 0;
        w_in_en = 1;

        fork
            begin : WRITE_BLOCK
                while (!full) begin
                    @ (posedge clk);
                    data_in = tx_data;
                    tx_data = tx_data + 1;
                end
            end

            begin : FULL_DETECT
                wait(full == 1);
                #0;
                r_in_en = 1;
            end
        join

        $display("FULL asserted at time %0t", $time);

        //-------------------------------------------------
        // STAGE 5: READ + WRITE 5 cycles
        //-------------------------------------------------
        $display("\n========== STAGE 5 : READ + WRITE ==========");

        repeat(5) begin
            @ (posedge clk);
            data_in = tx_data;
            tx_data = tx_data + 1;
        end

        //-------------------------------------------------
        // STAGE 6: READ until EMPTY (UPDATED FOR IMMEDIATE DEASSERTION)
        //-------------------------------------------------
        $display("\n========== STAGE 6 : READ UNTIL EMPTY ==========");

        w_in_en = 0;
        r_in_en = 1;

        // Đợi cho đến khi tín hiệu empty lên 1 ở bất kỳ thời điểm nào
        wait(empty == 1); 
        #0; // Delta delay nhỏ để đảm bảo trạng thái ổn định trước khi hạ r_in_en
        r_in_en = 0;

        $display("EMPTY asserted at time %0t", $time);

        #30;
        $finish;

    end

    //-----------------------------------------
    // Monitor
    //-----------------------------------------
    always @(posedge clk) begin
        $display("T=%0t | W=%b R=%b | FULL=%b EMPTY=%b | IN=%0d | OUT=%0d",
                $time,
                w_in_en,
                r_in_en,
                full,
                empty,
                data_in,
                data_out);
    end

endmodule
