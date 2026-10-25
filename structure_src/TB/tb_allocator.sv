`timescale 1ns / 1ps
module tb_allocator();

	parameter NUM_OF_ENTRIES = 64;
    parameter UNALLOCATES = 4;
    parameter ALLOCATES = 7;
	parameter ENTRY_NUM_WIDTH = $clog2(NUM_OF_ENTRIES);
    
    reg  clk;
    reg  reset_n;
    reg  [UNALLOCATES-1:0] unallocate_valid_i;
    reg  [(UNALLOCATES * ENTRY_NUM_WIDTH)-1:0] unallocate_entries_i;
    reg  [ALLOCATES-1:0] allocating_i;
	wire [ALLOCATES-1:0] allocate_valid_o;
    wire [(ALLOCATES * ENTRY_NUM_WIDTH)-1:0] allocate_entries_o;
	wire init_done;
    
    always #5 clk = ~clk;

    allocator #(
    	.NUM_OF_ENTRIES (NUM_OF_ENTRIES),
        .UNALLOCATES    (UNALLOCATES),
        .ALLOCATES      (ALLOCATES)
    ) dut (
        .clk                    (clk),
        .reset_n                (reset_n),
        .unallocate_valid_i     (unallocate_valid_i),
        .unallocate_entries_i   (unallocate_entries_i),
        .allocating_i           (allocating_i),
    	.allocate_valid_o       (allocate_valid_o),
        .allocate_entries_o     (allocate_entries_o),
    	.init_done              (init_done)
    );

    reg [ENTRY_NUM_WIDTH-1:0] allocate_value[0:NUM_OF_ENTRIES-1];
    integer idx;
    
    initial begin
        #0;
        clk = 0;
        reset_n = 0;
        unallocate_valid_i = 0;
        unallocate_entries_i = 0;
        allocating_i = 0;

        repeat(3) @(negedge clk);
        reset_n = 1;
        repeat(3) @(negedge clk);

        while (!init_done) @(negedge clk);

        idx = 0;

        allocating_i = {ALLOCATES{1'b1}};
        while (|allocate_valid_o) begin
            for(integer target_pos = 0; target_pos < ALLOCATES; target_pos = target_pos+1) begin
                if (allocate_valid_o[target_pos]) begin
                    allocate_value[idx] = allocate_entries_o[(ENTRY_NUM_WIDTH*target_pos) +: ENTRY_NUM_WIDTH];
                    idx = idx+1;
                end
            end
            @(negedge clk);
        end

        allocating_i = {ALLOCATES{1'b0}};
        @(negedge clk);


        repeat(3) @(negedge clk);
        $finish;
    end

endmodule
