`timescale 1ns / 1ps

`ifndef POSITION_SPLITER
`define POSITION_SPLITER

// =============================================================================
// 💡 gather_position_rom (Refactored: prefix-sum combinatorial logic)
//    - Replaced the $2^N$ distributed ROM lookup logic with a pure
//      combinational prefix-sum scan loop to avoid synthesis timeout/overflow.
// =============================================================================
module gather_position_rom #(
	parameter VALID_WIDTH = 4,
	localparam ONE_POSITION_WIDTH = $clog2(VALID_WIDTH),
	localparam OUT_WIDTH = VALID_WIDTH * ONE_POSITION_WIDTH
) (
	input  wire [VALID_WIDTH-1:0] full_valid_i,
	output reg  [VALID_WIDTH-1:0] out_valid_o,
	output reg  [OUT_WIDTH-1:0]   gather_positions_o
);

	integer now_position;
	integer now_pos;
	integer valid_cnt;
	integer i;
	reg [VALID_WIDTH-1:0] cnt_valid;

	always @(*) begin
		gather_positions_o = 0;
		for (now_position = 0; now_position < VALID_WIDTH; now_position = now_position + 1) begin
            if (full_valid_i[now_position]) begin
                valid_cnt = 0;
                for (now_pos = 0; now_pos < now_position; now_pos = now_pos + 1) begin
                    if (full_valid_i[now_pos]) begin
                        valid_cnt = valid_cnt + 1;
                    end
                end
                gather_positions_o[(now_position * ONE_POSITION_WIDTH) +: ONE_POSITION_WIDTH] = valid_cnt[ONE_POSITION_WIDTH-1:0];
            end
		end
	end

    always @(*) begin
		cnt_valid = 0; 
        out_valid_o = 0;
        for (i = 0; i < VALID_WIDTH; i = i+1) begin
            if (full_valid_i[i]) cnt_valid = cnt_valid + 1;
        end
		for (i = 0; i < VALID_WIDTH; i = i+1) begin
            if (cnt_valid > i) out_valid_o[i] = 1'b1;
        end
    end
endmodule

// =============================================================================
// 💡 position_demux (Bypassed from original)
// =============================================================================
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

// =============================================================================
// 💡 position_splitter (Bypassed from original)
// =============================================================================
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

// =============================================================================
// 💡 fifo_ordering_position (Bypassed from original)
// =============================================================================
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

// =============================================================================
// 💡 allocator (Refactored: 1-cycle bitmap-based allocator)
//    - Replaced the slow FSM/sequential push logic with a parallel
//      bitmap-based free_list tracker to enable immediate startup/reset.
// =============================================================================
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
    // 1-cycle instant ready
    assign init_done = 1'b1;

    reg [NUM_OF_ENTRIES-1:0] free_list, free_list_next;
    
    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            free_list <= {NUM_OF_ENTRIES{1'b1}};
        end else begin
            free_list <= free_list_next;
        end
    end

    // Constant array of register indexes for splitter
    wire [(NUM_OF_ENTRIES * ENTRY_NUM_WIDTH)-1:0] entries_const;
    genvar idx;
    generate
        for (idx = 0; idx < NUM_OF_ENTRIES; idx = idx + 1) begin : gen_const_entries
            assign entries_const[idx * ENTRY_NUM_WIDTH +: ENTRY_NUM_WIDTH] = idx[ENTRY_NUM_WIDTH-1:0];
        end
    endgenerate

    // Gather available registers to LSB order
    wire [NUM_OF_ENTRIES-1:0] free_list_aligned_valid;
    wire [(NUM_OF_ENTRIES * ENTRY_NUM_WIDTH)-1:0] free_list_aligned_entries;

    position_splitter #(
        .INPUT_ENTRIES(NUM_OF_ENTRIES),
        .DATA_WIDTH   (ENTRY_NUM_WIDTH)
    ) U_FREE_LIST_SPLITTER (
        .valid_position_i(free_list),
        .position_data_i (entries_const),
        .out_position_o  (free_list_aligned_valid),
        .data_o          (free_list_aligned_entries)
    );

    assign allocate_valid_o = free_list_aligned_valid[ALLOCATES-1:0];
    assign allocate_entries_o = free_list_aligned_entries[(ALLOCATES * ENTRY_NUM_WIDTH)-1:0];

    // Compute next state free_list
    reg [NUM_OF_ENTRIES-1:0] free_list_allocated_mask;
    integer i;
    always @(*) begin
        free_list_allocated_mask = 0;
        for (i = 0; i < ALLOCATES; i = i + 1) begin
            if (allocate_valid_o[i] && allocating_i[i]) begin
                free_list_allocated_mask[allocate_entries_o[i * ENTRY_NUM_WIDTH +: ENTRY_NUM_WIDTH]] = 1'b1;
            end
        end

        free_list_next = free_list & ~free_list_allocated_mask;

        for (i = 0; i < UNALLOCATES; i = i + 1) begin
            if (unallocate_valid_i[i]) begin
                free_list_next[unallocate_entries_i[i * ENTRY_NUM_WIDTH +: ENTRY_NUM_WIDTH]] = 1'b1;
            end
        end
    end
endmodule

// =============================================================================
// 💡 allocator_start_one (Refactored: 1-cycle bitmap-based allocator, starting at 1)
//    - Same as allocator, but index 0 is permanently disabled to map to x0 (zero).
// =============================================================================
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
    assign init_done = 1'b1;

    reg [NUM_OF_ENTRIES-1:0] free_list, free_list_next;
    
    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            free_list <= { {NUM_OF_ENTRIES-1{1'b1}}, 1'b0 }; // Disable register 0
        end else begin
            free_list <= free_list_next;
        end
    end

    wire [(NUM_OF_ENTRIES * ENTRY_NUM_WIDTH)-1:0] entries_const;
    genvar idx;
    generate
        for (idx = 0; idx < NUM_OF_ENTRIES; idx = idx + 1) begin : gen_const_entries
            assign entries_const[idx * ENTRY_NUM_WIDTH +: ENTRY_NUM_WIDTH] = idx[ENTRY_NUM_WIDTH-1:0];
        end
    endgenerate

    wire [NUM_OF_ENTRIES-1:0] free_list_aligned_valid;
    wire [(NUM_OF_ENTRIES * ENTRY_NUM_WIDTH)-1:0] free_list_aligned_entries;

    position_splitter #(
        .INPUT_ENTRIES(NUM_OF_ENTRIES),
        .DATA_WIDTH   (ENTRY_NUM_WIDTH)
    ) U_FREE_LIST_SPLITTER (
        .valid_position_i(free_list),
        .position_data_i (entries_const),
        .out_position_o  (free_list_aligned_valid),
        .data_o          (free_list_aligned_entries)
    );

    assign allocate_valid_o = free_list_aligned_valid[ALLOCATES-1:0];
    assign allocate_entries_o = free_list_aligned_entries[(ALLOCATES * ENTRY_NUM_WIDTH)-1:0];

    reg [NUM_OF_ENTRIES-1:0] free_list_allocated_mask;
    integer i;
    always @(*) begin
        free_list_allocated_mask = 0;
        for (i = 0; i < ALLOCATES; i = i + 1) begin
            if (allocate_valid_o[i] && allocating_i[i]) begin
                free_list_allocated_mask[allocate_entries_o[i * ENTRY_NUM_WIDTH +: ENTRY_NUM_WIDTH]] = 1'b1;
            end
        end

        free_list_next = free_list & ~free_list_allocated_mask;

        for (i = 0; i < UNALLOCATES; i = i + 1) begin
            if (unallocate_valid_i[i]) begin
                free_list_next[unallocate_entries_i[i * ENTRY_NUM_WIDTH +: ENTRY_NUM_WIDTH]] = 1'b1;
            end
        end
        free_list_next[0] = 1'b0; // Always keep index 0 disabled (mapped to x0)
    end
endmodule

`endif
