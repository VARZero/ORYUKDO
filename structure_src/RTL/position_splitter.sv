`timescale 1ns / 1ps

`ifndef POSITION_SPLITER
`define POSITION_SPLITER

//`include "memories.sv"

module gather_position_rom #(
	parameter VALID_WIDTH = 4,
	localparam ONE_POSITION_WIDTH = $clog2(VALID_WIDTH),
	localparam ROM_ADDR_WIDTH = 2 ** VALID_WIDTH,
	localparam OUT_WIDTH = VALID_WIDTH * ONE_POSITION_WIDTH
) (
	input  wire [VALID_WIDTH-1:0] full_valid_i,
	output reg  [VALID_WIDTH-1:0] out_valid_o,
	output wire [OUT_WIDTH-1:0]   gather_positions_o
);

	function [31:0] gather_position_digit(
		input [31:0] full_valid,
		integer check_width
	);
		integer now_pos, valid_cnt;

        if (~full_valid[check_width]) return 0;

		// 현재 Position까지 몇개의 Valid가 있었는지..
		valid_cnt = 0;
		for (now_pos = 0; now_pos < check_width; now_pos = now_pos + 1) begin
			if (full_valid[now_pos]) begin
				valid_cnt = valid_cnt + 1;
			end
		end

		return valid_cnt; 
	endfunction

    (* rom_style = "distributed" *)
	reg [OUT_WIDTH-1:0] gather_position_rom[0:ROM_ADDR_WIDTH-1];
	reg [OUT_WIDTH-1:0] gather_position_rom_entry;
	reg [31:0] gather_position_entry;
	integer now_position, now_valid;

	initial begin
		for (now_valid = 0; now_valid < ROM_ADDR_WIDTH; now_valid = now_valid + 1) begin
			for (now_position = 0; now_position < VALID_WIDTH; now_position = now_position + 1) begin
				gather_position_entry = gather_position_digit(now_valid, now_position);
				gather_position_rom_entry[(now_position * ONE_POSITION_WIDTH) +: ONE_POSITION_WIDTH] 
					= gather_position_entry[ONE_POSITION_WIDTH-1:0];
			end
            gather_position_rom[now_valid] = gather_position_rom_entry;
		end
	end

	reg [VALID_WIDTH-1:0] cnt_valid;
    always @(*) begin
		cnt_valid = 0; out_valid_o = 0;
        for (integer i = 0; i < VALID_WIDTH; i = i+1) begin
            if (full_valid_i[i]) cnt_valid = cnt_valid+1;
        end
		for (integer i = 0; i < VALID_WIDTH; i = i+1) begin
            if (cnt_valid > i) out_valid_o[i] = 1'b1;
        end
    end

	assign gather_positions_o = gather_position_rom[full_valid_i];
endmodule

`timescale 1ns / 1ps
module position_demux #(
	parameter DATA_WIDTH = 32,
	parameter DESTINATIONS = 4,
	localparam DESTINATIONS_BIT_WIDTH = $clog2(DESTINATIONS),
	localparam MUX_OUT_WIDTH = DATA_WIDTH * DESTINATIONS
) (
	input [DATA_WIDTH-1:0] data_in,
	input [DESTINATIONS_BIT_WIDTH-1:0] dst_i,
	output reg [MUX_OUT_WIDTH-1:0] data_out
);
	always @(*) begin
		data_out = 0;
		data_out[(DATA_WIDTH * dst_i) +: DATA_WIDTH] = data_in;
	end
endmodule

`timescale 1ns / 1ps
module position_splitter #(
	parameter INPUT_ENTRIES = 5,
	parameter DATA_WIDTH = 32,
	parameter BIT_WIDTH_INPUT_ENTRIES = $clog2(INPUT_ENTRIES)
) (
	input [INPUT_ENTRIES-1:0] valid_position_i,
	input [(INPUT_ENTRIES*DATA_WIDTH)-1:0] position_data_i,
	output [INPUT_ENTRIES-1:0] out_position_o,
	output [(INPUT_ENTRIES*DATA_WIDTH)-1:0] data_o
);
	localparam SEL_ENTRY_WIDTH = $clog2(INPUT_ENTRIES);
	localparam MUX_SEL_WIDTH = SEL_ENTRY_WIDTH * INPUT_ENTRIES;
	localparam MUX_OUT_WIDTH = INPUT_ENTRIES * DATA_WIDTH;

	wire [MUX_SEL_WIDTH-1:0] mux_sel;
    wire [INPUT_ENTRIES-1:0] out_valid;
	wire [MUX_OUT_WIDTH-1:0] mux_out[INPUT_ENTRIES];
    reg  [MUX_OUT_WIDTH-1:0] mux_out_oring;

	gather_position_rom #(
		.VALID_WIDTH 		(INPUT_ENTRIES)
	) U_POSITION_ROM (
		.full_valid_i		(valid_position_i),
        .out_valid_o        (out_valid),
		.gather_positions_o	(mux_sel)
	);

	genvar mux_i;
	generate
		for(mux_i = 0; mux_i < INPUT_ENTRIES; mux_i = mux_i + 1) begin
			position_demux #(
				.DATA_WIDTH		(DATA_WIDTH),
				.DESTINATIONS	(INPUT_ENTRIES)
			) U_POSITION_DEMUX (
				.data_in	(position_data_i[(mux_i * DATA_WIDTH) +: DATA_WIDTH]),
				.dst_i		(mux_sel[(mux_i * SEL_ENTRY_WIDTH) +: SEL_ENTRY_WIDTH]),
				.data_out	(mux_out[mux_i])
			);
			
		end
	endgenerate

    always @(*) begin
		mux_out_oring = 0;
        for (integer i = 0; i < INPUT_ENTRIES; i = i+1) begin
            mux_out_oring = (valid_position_i[i])? 
				(mux_out_oring | mux_out[i]) : mux_out_oring;
        end
    end

    assign out_position_o = out_valid;
    assign data_o = mux_out_oring;

endmodule

`timescale 1ns / 1ps
module fifo_ordering_position #(
	parameter PUSH_DATA = 4,
	parameter POP_DATA = 7,
	parameter ENTRY_WIDTH = 32,
	parameter FIFO_DEPTH = 128
) (
	input clk,
	input reset_n,
	input [PUSH_DATA-1:0] push_valid_i,
	input [(PUSH_DATA * ENTRY_WIDTH)-1:0] push_data_i,
	input [POP_DATA-1:0] pop_get_i,
	output [POP_DATA-1:0] pop_valid_o,
	output [(POP_DATA * ENTRY_WIDTH)-1:0] pop_data_o,
	output push_available_o
);
	localparam FIFO_IO_ENTRIES = (PUSH_DATA > POP_DATA)? PUSH_DATA : POP_DATA;
	localparam FIFO_WIDTH = FIFO_IO_ENTRIES * ENTRY_WIDTH;
	localparam READY_PUSH_PS_ENTRIES = FIFO_IO_ENTRIES + PUSH_DATA;
	localparam READY_PUSH_PS_WIDTH = FIFO_WIDTH + (PUSH_DATA * ENTRY_WIDTH);
	localparam READY_POP_PS_ENTRIES = FIFO_IO_ENTRIES + POP_DATA;
	localparam READY_POP_PS_WIDTH = FIFO_WIDTH + (POP_DATA * ENTRY_WIDTH);
	localparam READY_PUSH_EMPTY_ENTRIES_SPACE = FIFO_IO_ENTRIES - PUSH_DATA;
	localparam READY_PUSH_EMPTY_WIDTH = READY_PUSH_EMPTY_ENTRIES_SPACE * ENTRY_WIDTH;

	// Registers
	reg  [READY_PUSH_PS_ENTRIES-1:0] push_fifoready_valid_reg;
	reg  [READY_PUSH_PS_WIDTH-1:0] push_fifoready_data_reg;
	reg  [READY_POP_PS_ENTRIES-1:0] pop_out_valid_reg;
	reg  [READY_POP_PS_WIDTH-1:0] pop_out_data_reg;

	// for U_PS_PUSH and U_PS_PUSH_2_FIFO
	wire [PUSH_DATA-1:0] push_ordering_valid;
	wire [(PUSH_DATA * ENTRY_WIDTH)-1:0] push_ordering_data;

	// update U_PS_PUSH_2_FIFO
	// for U_PS_PUSH_2_FIFO and U_INTERNAL_FIFO
	wire [READY_PUSH_PS_ENTRIES-1:0] push_fifoready_valid;
	wire [READY_PUSH_PS_WIDTH-1:0] push_fifoready_data;
	reg  [READY_PUSH_PS_ENTRIES-1:0] push_fifoready_new_valid;
	reg  [READY_PUSH_PS_WIDTH-1:0] push_fifoready_new_data;
	reg	 push_fifo_we;
	reg  [FIFO_WIDTH-1:0] push_fifo_data;

	// for U_INTERNAL_FIFO and U_PS_FIFO_2_OUT
	wire fifo_empty, fifo_full;
	wire [FIFO_WIDTH-1:0] pop_fifoout_data;
	wire [READY_POP_PS_ENTRIES-1:0] pop_out_new_valid;
	wire [READY_POP_PS_WIDTH-1:0] pop_out_new_data;
	reg  fifo_get_position;
	reg  [READY_POP_PS_ENTRIES-1:0] pop_out_valid;
	reg  [READY_POP_PS_WIDTH-1:0] pop_out_data;

	always @(*) begin // comb logic
		// PUSH SECTION
			// FIFO 부분 채워졌는지 결정
		push_fifo_we = &( push_fifoready_valid_reg[FIFO_IO_ENTRIES-1:0] );
		push_fifo_data = push_fifoready_data_reg[FIFO_WIDTH-1:0];

		if (push_fifo_we) begin // FIFO 부분 채워짐
			push_fifoready_new_valid = {push_ordering_valid, {READY_PUSH_EMPTY_ENTRIES_SPACE{1'b0}},
										push_fifoready_valid_reg[READY_PUSH_PS_ENTRIES-1:FIFO_IO_ENTRIES] };
			push_fifoready_new_data = {push_ordering_data, {READY_PUSH_EMPTY_WIDTH{1'b0}},
									   push_fifoready_data_reg[READY_PUSH_PS_WIDTH-1:FIFO_WIDTH] };
		end
		else begin // FIFO 부분 아직 안채워짐
			push_fifoready_new_valid = {push_ordering_valid, 
										push_fifoready_valid_reg[FIFO_IO_ENTRIES-1:0]};
			push_fifoready_new_data  = {push_ordering_data, 
										push_fifoready_data_reg[FIFO_WIDTH-1:0]};
		end

		// POP SECTION
		if ( ( |pop_out_valid_reg[READY_POP_PS_ENTRIES-1:POP_DATA] ) ) begin

			// 가져온것이 아직 남아있는 경우나 기존데이터가 다 나가지 않는 경우이거나 비어있지 않은 경우: 유지
			fifo_get_position = 0;
			pop_out_valid = pop_out_valid_reg;
			pop_out_data = pop_out_data_reg;
		end
		else begin
			// 새로 보충해야 하는 경우
			if (~fifo_empty) begin // FIFO의 데이터가 있는 경우
				fifo_get_position = 1'b1;
				pop_out_valid = {{FIFO_IO_ENTRIES{1'b1}}, pop_out_valid_reg[POP_DATA-1:0]};
				pop_out_data = {pop_fifoout_data, pop_out_data_reg[(POP_DATA * ENTRY_WIDTH)-1:0]};
			end
			else begin // FIFO에 데이터가 없는 경우
				fifo_get_position = 0;
				pop_out_valid = {push_fifoready_valid_reg[FIFO_IO_ENTRIES-1:0], 
								 pop_out_valid_reg[POP_DATA-1:0]};
				pop_out_data  = {push_fifo_data[FIFO_WIDTH-1:0], 
								 pop_out_data_reg[(POP_DATA * ENTRY_WIDTH)-1:0]};

				// PUSH 부분에서 FIFO 부분은 지우기, 단 Push Register에 있는 경우
				if ( |push_fifoready_valid_reg ) begin
					push_fifo_we = 0;

					push_fifoready_new_valid = {push_ordering_valid, {POP_DATA{1'b0}}};
					push_fifoready_new_data = {push_ordering_data, {(POP_DATA * ENTRY_WIDTH){1'b0}}};
				end
			end
		end
        pop_out_valid = pop_out_valid & ( ~({{FIFO_IO_ENTRIES{1'b0}}, pop_get_i} & pop_out_valid) );
	end

	// Registers Modeling
	always @(posedge clk or negedge reset_n) begin
		if (reset_n == 1'b0) begin
			push_fifoready_valid_reg <= 0;
			push_fifoready_data_reg <= 0;
			pop_out_valid_reg <= 0;
			pop_out_data_reg <= 0;
		end
		else begin
			push_fifoready_valid_reg <= push_fifoready_valid;
			push_fifoready_data_reg <= push_fifoready_data;
			pop_out_valid_reg <= pop_out_new_valid;
			pop_out_data_reg <= pop_out_new_data;
		end
	end

	position_splitter #(
		.INPUT_ENTRIES(PUSH_DATA),
		.DATA_WIDTH(ENTRY_WIDTH)
	) U_PS_PUSH (
		.valid_position_i	(push_valid_i),
		.position_data_i    (push_data_i),
		.out_position_o		(push_ordering_valid),
		.data_o				(push_ordering_data)
	);

	position_splitter #(
		.INPUT_ENTRIES(READY_PUSH_PS_ENTRIES),
		.DATA_WIDTH(ENTRY_WIDTH)
	) U_PS_PUSH_2_FIFO (
		.valid_position_i	(push_fifoready_new_valid),
		.position_data_i	(push_fifoready_new_data),
		.out_position_o		(push_fifoready_valid),
		.data_o				(push_fifoready_data)
	);

	// FIFO는 한 FIFO 라인이 모두 채워지면 그때 저장함
    fifo_sram #(
		.ENTRIES(FIFO_DEPTH), 
		.REG_WIDTH(FIFO_WIDTH)
	) U_INTERNAL_FIFO (
        .clk                 (clk),
        .reset_n             (reset_n),
        .i_read_get          (fifo_get_position),
        .i_write_we          (push_fifo_we),
        .i_write_data        (push_fifo_data),
        .o_read_data         (pop_fifoout_data),
        .o_empty             (fifo_empty),
        .o_full              (fifo_full)
    );

	position_splitter #(
		.INPUT_ENTRIES(READY_POP_PS_ENTRIES),
		.DATA_WIDTH(ENTRY_WIDTH)
	) U_PS_FIFO_2_OUT (
		.valid_position_i	(pop_out_valid),
		.position_data_i	(pop_out_data),
		.out_position_o		(pop_out_new_valid),
		.data_o				(pop_out_new_data)
	);

	assign push_available_o = ~fifo_full;

	assign pop_valid_o = pop_out_valid_reg[POP_DATA-1:0];
	assign pop_data_o = pop_out_data_reg[(POP_DATA*ENTRY_WIDTH)-1:0];

endmodule

// allocate value start 0
`timescale 1ns / 1ps
module allocator #(
	parameter NUM_OF_ENTRIES = 64,
    parameter UNALLOCATES = 4,
    parameter ALLOCATES = 7,
	parameter ENTRY_NUM_WIDTH = $clog2(NUM_OF_ENTRIES)
) (
    input clk,
    input reset_n,
    input [UNALLOCATES-1:0] unallocate_valid_i,
    input [(UNALLOCATES * ENTRY_NUM_WIDTH)-1:0] unallocate_entries_i,
    input [ALLOCATES-1:0] allocating_i,
	output [ALLOCATES-1:0] allocate_valid_o,
    output [(ALLOCATES * ENTRY_NUM_WIDTH)-1:0] allocate_entries_o,
	output init_done
);
	localparam ALLOCATING_FIFO_WIDTH_ENTRIES = (UNALLOCATES > ALLOCATES)? UNALLOCATES : ALLOCATES;
	localparam ALLOCATING_FIFO_DEPTH = (NUM_OF_ENTRIES / ALLOCATING_FIFO_WIDTH_ENTRIES) 
										+ ( ((NUM_OF_ENTRIES % ALLOCATING_FIFO_WIDTH_ENTRIES) > 0)? 1 : 0 );
	localparam UNALLOCATING_FIFO_LAST_ENTRIES = NUM_OF_ENTRIES % UNALLOCATES;

	// Initializer FSM
		// State
	localparam INIT = 1'b0;
	localparam ALLOCATING = 1'b1;

		// State, Counter Register
	reg state, state_next;
	reg [ENTRY_NUM_WIDTH:0] entry_cnt, entry_cnt_next;
	always @(posedge clk or negedge reset_n) begin
		if (reset_n == 1'b0) begin
			state <= 0;
			entry_cnt <= 0;
		end
		else begin
			state <= state_next;
			entry_cnt <= entry_cnt_next;
		end
	end

		// State Transition
	always @(*) begin
		case (state)
			INIT: begin
				if (entry_cnt >= NUM_OF_ENTRIES) begin
					state_next = ALLOCATING;
				end
				else begin
					state_next = INIT;
				end
				entry_cnt_next = entry_cnt + UNALLOCATES;
			end
			ALLOCATING: begin state_next = ALLOCATING; entry_cnt_next = 0; end
		endcase
	end

		// State Output
	integer position;
	reg [UNALLOCATES-1:0] unallocate_valid_in_fifo;
    reg [(UNALLOCATES * ENTRY_NUM_WIDTH)-1:0] unallocate_entries_in_fifo;
	always @(*) begin
		case (state)
			INIT: begin
                unallocate_entries_in_fifo = 0;
				if (entry_cnt == ( (NUM_OF_ENTRIES-UNALLOCATING_FIFO_LAST_ENTRIES) ) ) begin
					unallocate_valid_in_fifo = { {(UNALLOCATES-UNALLOCATING_FIFO_LAST_ENTRIES){1'b0}},
												 {UNALLOCATING_FIFO_LAST_ENTRIES{1'b1}} };
				end
				else begin
					unallocate_valid_in_fifo = {UNALLOCATES{1'b1}};
				end
				for (position = 0; position < UNALLOCATES; position = position + 1) begin
                    if ((entry_cnt + position) > (NUM_OF_ENTRIES-1)) begin
                        unallocate_entries_in_fifo[(ENTRY_NUM_WIDTH*position) +: ENTRY_NUM_WIDTH] = 0;
                    end
                    else begin
        				unallocate_entries_in_fifo[(ENTRY_NUM_WIDTH*position) +: ENTRY_NUM_WIDTH] = entry_cnt + position;
                    end
				end
			end
			ALLOCATING: begin 
				unallocate_valid_in_fifo = unallocate_valid_i; 
				unallocate_entries_in_fifo = unallocate_entries_i; 
			end
		endcase
	end

	assign init_done = (state == ALLOCATING)? 1'b1 : 1'b0;

    fifo_ordering_position #(
    	.PUSH_DATA		(UNALLOCATES),
    	.POP_DATA		(ALLOCATES),
    	.ENTRY_WIDTH	(ENTRY_NUM_WIDTH),
    	.FIFO_DEPTH		(ALLOCATING_FIFO_DEPTH)
    ) U_ALLOCATING_FIFO (
    	.clk			 (clk),
    	.reset_n		 (reset_n),
    	.push_valid_i	 (unallocate_valid_in_fifo),
    	.push_data_i	 (unallocate_entries_in_fifo),
    	.pop_get_i		 (allocating_i),
		.pop_valid_o	 (allocate_valid_o),
    	.pop_data_o		 (allocate_entries_o),
		.push_available_o()
    );

endmodule

// allocate value start 1
`timescale 1ns / 1ps
module allocator_start_one #(
	parameter NUM_OF_ENTRIES = 64,
    parameter UNALLOCATES = 4,
    parameter ALLOCATES = 7,
	parameter ENTRY_NUM_WIDTH = $clog2(NUM_OF_ENTRIES)
) (
    input clk,
    input reset_n,
    input [UNALLOCATES-1:0] unallocate_valid_i,
    input [(UNALLOCATES * ENTRY_NUM_WIDTH)-1:0] unallocate_entries_i,
    input [ALLOCATES-1:0] allocating_i,
	output [ALLOCATES-1:0] allocate_valid_o,
    output [(ALLOCATES * ENTRY_NUM_WIDTH)-1:0] allocate_entries_o,
	output init_done
);
	localparam ALLOCATING_FIFO_WIDTH_ENTRIES = (UNALLOCATES > ALLOCATES)? UNALLOCATES : ALLOCATES;
	localparam ALLOCATING_FIFO_DEPTH = (NUM_OF_ENTRIES / ALLOCATING_FIFO_WIDTH_ENTRIES) 
										+ ( ((NUM_OF_ENTRIES % ALLOCATING_FIFO_WIDTH_ENTRIES) > 0)? 1 : 0 );
	localparam UNALLOCATING_FIFO_LAST_ENTRIES = (NUM_OF_ENTRIES-1) % UNALLOCATES;

	// Initializer FSM
		// State
	localparam INIT = 1'b0;
	localparam ALLOCATING = 1'b1;

		// State, Counter Register
	reg state, state_next;
	reg [ENTRY_NUM_WIDTH:0] entry_cnt, entry_cnt_next;
	always @(posedge clk or negedge reset_n) begin
		if (reset_n == 1'b0) begin
			state <= 0;
			entry_cnt <= 1;
		end
		else begin
			state <= state_next;
			entry_cnt <= entry_cnt_next;
		end
	end

		// State Transition
	always @(*) begin
		case (state)
			INIT: begin
				if (entry_cnt >= (NUM_OF_ENTRIES-1)) begin
					state_next = ALLOCATING;
				end
				else begin
					state_next = INIT;
				end
				entry_cnt_next = entry_cnt + UNALLOCATES;
			end
			ALLOCATING: begin state_next = ALLOCATING; entry_cnt_next = 0; end
		endcase
	end

		// State Output
	integer position;
	reg [UNALLOCATES-1:0] unallocate_valid_in_fifo;
    reg [(UNALLOCATES * ENTRY_NUM_WIDTH)-1:0] unallocate_entries_in_fifo;
	always @(*) begin
		case (state)
			INIT: begin
                unallocate_entries_in_fifo = 0;
				if (entry_cnt >= (NUM_OF_ENTRIES-1)) unallocate_valid_in_fifo = 0; 
				else if (entry_cnt == ( (NUM_OF_ENTRIES-UNALLOCATING_FIFO_LAST_ENTRIES) )) begin
					unallocate_valid_in_fifo = { {(UNALLOCATES-UNALLOCATING_FIFO_LAST_ENTRIES){1'b0}},
												 {UNALLOCATING_FIFO_LAST_ENTRIES{1'b1}} };
				end
				else begin
					unallocate_valid_in_fifo = {UNALLOCATES{1'b1}};
				end
				for (position = 0; position < UNALLOCATES; position = position + 1) begin
                    if ((entry_cnt + position) > NUM_OF_ENTRIES) begin
                        unallocate_entries_in_fifo[(ENTRY_NUM_WIDTH*position) +: ENTRY_NUM_WIDTH] = 0;
                    end
                    else begin
        				unallocate_entries_in_fifo[(ENTRY_NUM_WIDTH*position) +: ENTRY_NUM_WIDTH] = entry_cnt + position;
                    end
				end
			end
			ALLOCATING: begin 
				unallocate_valid_in_fifo = unallocate_valid_i; 
				unallocate_entries_in_fifo = unallocate_entries_i; 
			end
		endcase
	end

	assign init_done = (state == ALLOCATING)? 1'b1 : 1'b0;

    fifo_ordering_position #(
    	.PUSH_DATA		(UNALLOCATES),
    	.POP_DATA		(ALLOCATES),
    	.ENTRY_WIDTH	(ENTRY_NUM_WIDTH),
    	.FIFO_DEPTH		(ALLOCATING_FIFO_DEPTH)
    ) U_ALLOCATING_FIFO (
    	.clk			(clk),
    	.reset_n		(reset_n),
    	.push_valid_i	(unallocate_valid_in_fifo),
    	.push_data_i	(unallocate_entries_in_fifo),
    	.pop_get_i		(allocating_i),
		.pop_valid_o	(allocate_valid_o),
    	.pop_data_o		(allocate_entries_o)
    );

endmodule

`endif
