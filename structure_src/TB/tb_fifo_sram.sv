`timescale 1ns / 1ps

module tb_fifo_sram();

    parameter ENTRIES   = 16;
    parameter REG_WIDTH = 32;

    reg                  clk;
    reg                  reset_n;
    reg                  i_read_get;
    reg                  i_write_we;
    reg  [REG_WIDTH-1:0] i_write_data;
    wire [REG_WIDTH-1:0] o_read_data;
    wire                 o_empty;
    wire                 o_full;

    fifo_sram #(
        .ENTRIES    (ENTRIES),
        .REG_WIDTH  (REG_WIDTH)      
    ) dut (
        .clk            (clk),
        .reset_n        (reset_n),
        .i_read_get     (i_read_get),
        .i_write_we     (i_write_we),
        .i_write_data   (i_write_data),
        .o_read_data    (o_read_data),
        .o_empty        (o_empty),
        .o_full         (o_full)
    );

    always #5 clk = ~clk;

    parameter TARGET_TIMES = 512;
    logic [REG_WIDTH-1:0] compare_fifo[0:ENTRIES-1];

    shortint acc_type = 0; // 0 POP Only / 1 PUSH Only / 2 PP
    shortint fifo_cnt = 0;
    shortint fifo_cnt_now = 0;
    shortint push_position = 0;
    shortint pop_position = 0;

    initial begin
        #0;
        clk = 0;
        reset_n = 0;
        i_read_get = 0;
        i_write_we = 0;
        i_write_data = 0;

        repeat(3) @(negedge clk);
        reset_n = 1;
        repeat(3) @(negedge clk);

        for (integer acc_times = 0; acc_times < TARGET_TIMES; acc_times = acc_times+1) begin
            acc_type = $urandom % 3;
            case(acc_type)
                'd0: begin
                    // POP Only
                        // Get
                    if (o_empty) begin
                        if (fifo_cnt == 0) begin
                            $display("[%t] PASS: FIFO IS EMPTY", $time);
                        end
                        else begin
                            $display("[%t] FAIL: WHY FIFO IS EMPTY ?????", $time);
                        end
                        @(negedge clk);
                    end
                    else begin
                        i_read_get = 1'b1;
                        @(negedge clk);
                        if (compare_fifo[pop_position] === o_read_data) begin
                            $display("[%t] PASS: POP DATA IS SAME expect=%h real=%h", 
                                     $time, compare_fifo[pop_position], o_read_data);
                        end
                        else begin
                            $display("[%t] FAIL: POP DATA IS SAME expect=%h real=%h", 
                                     $time, compare_fifo[pop_position], o_read_data);
                        end
                        pop_position = pop_position+1; fifo_cnt = fifo_cnt-1;
                        if (pop_position == 16) pop_position = 0;
                    end
                    i_read_get = 1'b0;
                end
                'd1: begin
                    // PUSH Only
                        // Req
                    if (o_full) begin
                        $display("[%t] FIFO IS FULL: PUSH IS IGNORE", $time);
                    end
                    else begin
                        i_write_we = 1'b1;
                        i_write_data = $urandom;
                        compare_fifo[push_position] = i_write_data;
                        push_position = push_position+1; fifo_cnt = fifo_cnt+1;
                        if (push_position == 16) push_position = 0; 
                        $display("[%t] PUSH: %h", $time, i_write_data);
                    end

                    @(negedge clk);
                    i_write_we = 1'b0;
                    i_write_data = 0;
                end
                'd2: begin
                    // PP
                    fifo_cnt_now = fifo_cnt;
                    if (o_full) begin
                         $display("[%t] FIFO IS FULL: PUSH IS IGNORE", $time);
                    end
                    else begin
                        i_write_we = 1'b1;
                        i_write_data = $urandom;
                        compare_fifo[push_position] = i_write_data;
                        push_position = push_position+1; fifo_cnt = fifo_cnt+1;
                        if (push_position == 16) push_position = 0; 
                        $display("[%t] PUSH: %h", $time, i_write_data);
                    end
                    
                        // Get
                    if (o_empty) begin
                        if (fifo_cnt_now == 0) begin
                            $display("[%t] PASS: FIFO IS EMPTY", $time);
                        end
                        else begin
                            $display("[%t] FAIL: WHY FIFO IS EMPTY ?????", $time);
                        end
                        @(negedge clk);
                    end
                    else begin
                        i_read_get = 1'b1;
                        @(negedge clk);
                        if (compare_fifo[pop_position] === o_read_data) begin
                            $display("[%t] PASS: POP DATA IS SAME expect=%h real=%h", 
                                     $time, compare_fifo[pop_position], o_read_data);
                        end
                        else begin
                            $display("[%t] FAIL: POP DATA IS SAME expect=%h real=%h", 
                                     $time, compare_fifo[pop_position], o_read_data);
                        end
                        pop_position = pop_position+1; fifo_cnt = fifo_cnt-1;
                        if (pop_position == 16) pop_position = 0;
                    end
                    i_read_get = 1'b0;
                    i_write_we = 1'b0;
                    i_write_data = 0;
                end
            endcase
        end

        repeat(3) @(negedge clk);
        $finish;
    end

endmodule
