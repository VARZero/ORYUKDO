`timescale 1ns / 1ps

module tb_position_splitter();

	parameter  INPUT_ENTRIES = 5;
	parameter  DATA_WIDTH    = 32;

	localparam BIT_WIDTH_INPUT_ENTRIES = $clog2(INPUT_ENTRIES);
    
    reg                                   clk; // Check Sampling Plot

	reg  [INPUT_ENTRIES-1:0]              valid_position_i;
	reg  [(INPUT_ENTRIES*DATA_WIDTH)-1:0] position_data_i;
	wire [INPUT_ENTRIES-1:0]              out_position_o;
	wire [(INPUT_ENTRIES*DATA_WIDTH)-1:0] data_o;

    reg  [(INPUT_ENTRIES*DATA_WIDTH)-1:0] check_data;

    position_splitter #(
    	.INPUT_ENTRIES (INPUT_ENTRIES),
    	.DATA_WIDTH    (DATA_WIDTH)
    ) dut (
    	.valid_position_i (valid_position_i),
    	.position_data_i  (position_data_i),
    	.out_position_o   (out_position_o),
    	.data_o           (data_o)
    );

    always #5 clk = ~clk;

    integer check_valids;

    initial begin
        #0;
        clk = 0;
        valid_position_i = 0;
        position_data_i = 0;
        
        repeat(3) @(negedge clk);

        for (integer valid_pos = 0; 
             valid_pos < (2**INPUT_ENTRIES); valid_pos = valid_pos+1) begin
        
            // Create check data
            for (integer create_c_data = 0; 
                 create_c_data < INPUT_ENTRIES;
                 create_c_data = create_c_data+1) begin

                check_data[(DATA_WIDTH*create_c_data) +: DATA_WIDTH]
                    = $urandom;
            end

            // Input insert
            valid_position_i = valid_pos;
            position_data_i = check_data;
            
            @(posedge clk); #1; // Monitor
            check_valids = 0;
            // Check
            for (integer check_c_data = 0; 
                 check_c_data < INPUT_ENTRIES;
                 check_c_data = check_c_data+1) begin

                if (~out_position_o[check_c_data]) begin
                    continue;
                end

                for (; check_valids < INPUT_ENTRIES; check_valids = check_valids+1) begin
                    if (valid_position_i[check_valids]) break;
                end
                if (check_valids >= INPUT_ENTRIES) break;

                if ( data_o[(DATA_WIDTH*check_c_data) +: DATA_WIDTH]
                     === check_data[(DATA_WIDTH*check_valids) +: DATA_WIDTH] ) begin
                
                    $display("%t = PASS! position[%d] = 0x%08h", $time, check_c_data,
                             data_o[(DATA_WIDTH*check_c_data) +: DATA_WIDTH]);
                end
                else begin
                    $display("%t = FAIL! position[%d] = 0x%08h / target [%d] 0x%08h", 
                             $time, check_c_data, data_o[(DATA_WIDTH*check_c_data) +: DATA_WIDTH], 
                             check_valids, check_data[(DATA_WIDTH*check_valids) +: DATA_WIDTH] );
                end

                check_valids = check_valids+1;
            end

            @(negedge clk);
        end
        
        repeat(3) @(negedge clk);
        $finish;
    end

endmodule
