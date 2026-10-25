`timescale 1ns / 1ps
module tb_fifo_ordering_position_big_POP();

	parameter PUSH_DATA = 4;
	parameter POP_DATA = 7;
	parameter ENTRY_WIDTH = 16;
	parameter FIFO_DEPTH = 128;
    
	reg  clk;
	reg  reset_n;
	reg  [PUSH_DATA-1:0] push_valid_i;
	reg  [(PUSH_DATA * ENTRY_WIDTH)-1:0] push_data_i;
	reg  [POP_DATA-1:0] pop_get_i;
	wire [POP_DATA-1:0] pop_valid_o;
	wire [(POP_DATA * ENTRY_WIDTH)-1:0] pop_data_o;
	wire push_available_o;

    always #5 clk = ~clk;
    
    fifo_ordering_position #(
    	.PUSH_DATA   (PUSH_DATA),
    	.POP_DATA    (POP_DATA),
    	.ENTRY_WIDTH (ENTRY_WIDTH),
    	.FIFO_DEPTH  (FIFO_DEPTH)
    ) dut (
    	.clk              (clk),
    	.reset_n          (reset_n),
    	.push_valid_i     (push_valid_i),
    	.push_data_i      (push_data_i),
    	.pop_get_i        (pop_get_i),
    	.pop_valid_o      (pop_valid_o),
    	.pop_data_o       (pop_data_o),
    	.push_available_o (push_available_o)
    );

    parameter TARGET_TIMES = 512;
	localparam FIFO_IO_ENTRIES = (PUSH_DATA > POP_DATA)? PUSH_DATA : POP_DATA;
	localparam ENTRIES = FIFO_IO_ENTRIES * FIFO_DEPTH;

    reg [ENTRY_WIDTH-1:0] pop_data;

    initial begin
        #0;
        clk = 0;
        reset_n = 0;
        push_valid_i = 0;
        push_data_i = 0;
        pop_get_i = 0;

        repeat(3) @(negedge clk);
        reset_n = 1;
        repeat(3) @(negedge clk);

        // All Write
        for (integer write_entry = 0; write_entry < ENTRIES; 
             write_entry = write_entry + PUSH_DATA) begin
            
            push_valid_i = {PUSH_DATA{1'b1}};

            for (integer write_field = 1; 
                 write_field <= PUSH_DATA; 
                 write_field = write_field+1) begin
            
                push_data_i[(ENTRY_WIDTH * (write_field-1) ) +: ENTRY_WIDTH] 
                    = (write_entry + write_field);

                if ( (write_entry + write_field) > ENTRIES ) begin
                    push_valid_i[(write_field-1)] = 1'b0;
                end
            end
            @(negedge clk);
        end
        push_valid_i = {PUSH_DATA{1'b0}};

        repeat(3) @(negedge clk);

        // All Read
        for (integer read_entry = 0; read_entry < ENTRIES; 
             read_entry = read_entry + POP_DATA) begin
        
            pop_get_i = {POP_DATA{1'b1}};

            for (integer read_field = 1; 
                 read_field <= POP_DATA; 
                 read_field = read_field+1) begin
                
                pop_data = pop_data_o[(ENTRY_WIDTH * (read_field-1) ) +: ENTRY_WIDTH];

                if ( !(&pop_valid_o) ) begin
                    pop_get_i = {POP_DATA{1'b0}};
                    while( ~(&pop_valid_o) ) @(negedge clk);
                    pop_get_i = {POP_DATA{1'b1}};
                end

                if ( (read_entry + read_field) > ENTRIES ) begin
                    pop_get_i[(read_field-1)] = 1'b0;
                end
                else begin
                    if ( (read_entry + read_field) == pop_data ) begin
                        $display("PASS: expect-%h real-%h", (read_entry + read_field), pop_data);
                    end
                    else begin
                        $display("FAIL: expect-%h real-%h", (read_entry + read_field), pop_data);
                    end
                end
            end

            @(negedge clk);
        end 

        repeat(3) @(negedge clk);
        $finish;
    end

endmodule

`timescale 1ns / 1ps
module tb_fifo_ordering_position_big_PUSH();

	parameter PUSH_DATA = 7;
	parameter POP_DATA = 4;
	parameter ENTRY_WIDTH = 16;
	parameter FIFO_DEPTH = 128;
    
	reg  clk;
	reg  reset_n;
	reg  [PUSH_DATA-1:0] push_valid_i;
	reg  [(PUSH_DATA * ENTRY_WIDTH)-1:0] push_data_i;
	reg  [POP_DATA-1:0] pop_get_i;
	wire [POP_DATA-1:0] pop_valid_o;
	wire [(POP_DATA * ENTRY_WIDTH)-1:0] pop_data_o;
	wire push_available_o;

    always #5 clk = ~clk;
    
    fifo_ordering_position #(
    	.PUSH_DATA   (PUSH_DATA),
    	.POP_DATA    (POP_DATA),
    	.ENTRY_WIDTH (ENTRY_WIDTH),
    	.FIFO_DEPTH  (FIFO_DEPTH)
    ) dut (
    	.clk              (clk),
    	.reset_n          (reset_n),
    	.push_valid_i     (push_valid_i),
    	.push_data_i      (push_data_i),
    	.pop_get_i        (pop_get_i),
    	.pop_valid_o      (pop_valid_o),
    	.pop_data_o       (pop_data_o),
    	.push_available_o (push_available_o)
    );

    parameter TARGET_TIMES = 512;
	localparam FIFO_IO_ENTRIES = (PUSH_DATA > POP_DATA)? PUSH_DATA : POP_DATA;
	localparam ENTRIES = FIFO_IO_ENTRIES * FIFO_DEPTH;

    reg [ENTRY_WIDTH-1:0] pop_data;

    initial begin
        #0;
        clk = 0;
        reset_n = 0;
        push_valid_i = 0;
        push_data_i = 0;
        pop_get_i = 0;

        repeat(3) @(negedge clk);
        reset_n = 1;
        repeat(3) @(negedge clk);

        // All Write
        for (integer write_entry = 0; write_entry < ENTRIES; 
             write_entry = write_entry + PUSH_DATA) begin
            
            push_valid_i = {PUSH_DATA{1'b1}};

            for (integer write_field = 1; 
                 write_field <= PUSH_DATA; 
                 write_field = write_field+1) begin
            
                push_data_i[(ENTRY_WIDTH * (write_field-1) ) +: ENTRY_WIDTH] 
                    = (write_entry + write_field);

                if ( (write_entry + write_field) > ENTRIES ) begin
                    push_valid_i[(write_field-1)] = 1'b0;
                end
            end
            @(negedge clk);
        end
        push_valid_i = {PUSH_DATA{1'b0}};

        repeat(3) @(negedge clk);

        // All Read
        for (integer read_entry = 0; read_entry < ENTRIES; 
             read_entry = read_entry + POP_DATA) begin
        
            pop_get_i = {POP_DATA{1'b1}};

            for (integer read_field = 1; 
                 read_field <= POP_DATA; 
                 read_field = read_field+1) begin
                
                pop_data = pop_data_o[(ENTRY_WIDTH * (read_field-1) ) +: ENTRY_WIDTH];

                if ( !(&pop_valid_o) ) begin
                    pop_get_i = {POP_DATA{1'b0}};
                    while( ~(&pop_valid_o) ) @(negedge clk);
                    pop_get_i = {POP_DATA{1'b1}};
                end

                if ( (read_entry + read_field) > ENTRIES ) begin
                    pop_get_i[(read_field-1)] = 1'b0;
                end
                else begin
                    if ( (read_entry + read_field) == pop_data ) begin
                        $display("PASS: expect-%h real-%h", (read_entry + read_field), pop_data);
                    end
                    else begin
                        $display("FAIL: expect-%h real-%h", (read_entry + read_field), pop_data);
                    end
                end
            end

            @(negedge clk);
        end 

        repeat(3) @(negedge clk);
        $finish;
    end

endmodule

