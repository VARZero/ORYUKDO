`timescale 1ns / 1ps
//
//`include "../memories.sv"
//`include "../position_splitter.sv"

module flow_control_logic #(
    // Dynamic Schedular Description
    parameter DECODE_NEW_INST   = 1,
    parameter PHYREG_NUM        = 64,
    parameter IST_ENTRY_NUM     = 128,
    parameter EX_PATH_NUM       = 3,
    parameter PRM_ENTRY_BUFFER  = 4,
    parameter RS_ENTRY_NUM      = 16,
    parameter RS_PUSH_WIDTH     = 3,
    parameter FCL_RB_NUM        = 8,
    parameter FCL_PC_GAP        = 4,
    parameter UNALLOCATE_PHYREG = 4,

    // Instruction Field Description
    parameter INST_PC_WIDTH                 = 32,
    parameter INST_BITWIDTH                 = 32,
    parameter INST_OPCODE_WIDTH             = 7,
    parameter INST_OPTIONAL_OPCODE_WIDTH    = 10,
    parameter INST_IMM_WIDTH                = 32,
    parameter INST_NUM_OF_LOGICAL_REGISTER  = 32,
    parameter INST_OPREANDS                 = 2,

    // Internal Field Description (Decoder Compiler (or Human) Generate)
    parameter MICROOP_WIDTH                 = 5, // Micro-OP is not contained information of EX_PATH

    // (Autogenerate) Elements
    localparam BITWIDTH_EX_PATH_NUM                     = $clog2(EX_PATH_NUM),
    localparam BITWIDTH_PHYREG_NUM                      = $clog2(PHYREG_NUM),
    localparam BITWIDTH_IST_ENTRY_NUM                   = $clog2(IST_ENTRY_NUM),
    localparam BITWIDTH_INST_NUM_OF_OGICAL_REGISTER     = $clog2(INST_NUM_OF_LOGICAL_REGISTER),
    localparam BITWIDTH_FCL_RB_NUM                      = $clog2(FCL_RB_NUM),

    localparam BITWIDTH_FCL_PC_WIDTH                    = BITWIDTH_FCL_RB_NUM + INST_PC_WIDTH,
    
    localparam FCL_RB_PC_GAP_MAX                        = (PHYREG_NUM/2)*FCL_PC_GAP
) (
    input  wire                  clk,
    input  wire                  reset_n,

    // New Entry Logic
        // <- Get instruction
    input  wire [DECODE_NEW_INST-1:0]                         i_im_inst_get,
        // <- Block
    input  wire                                               i_nel_block,
        // <- Jump Instruction Input
    input  wire                                               i_nel_jump_inst,
    input  wire                                               i_nel_jreg_branch_inst,
    input  wire [INST_PC_WIDTH-1:0]                           i_nel_jump_branch_pc,
        // <- Allocate Registers input
    input  wire [DECODE_NEW_INST-1:0]                         i_nel_newpc_valid,
    input  wire [(BITWIDTH_FCL_PC_WIDTH*DECODE_NEW_INST)-1:0] i_nel_newpc,
    input  wire [DECODE_NEW_INST-1:0]                         i_nel_lastreg_valid,
    input  wire [(BITWIDTH_PHYREG_NUM*DECODE_NEW_INST)-1:0]   i_nel_lastreg,

    // Physical Register Mapper
        // -> Unallocate Registers Output
    output wire [UNALLOCATE_PHYREG-1:0]                       o_prm_unallocate_valid,
    output wire [(BITWIDTH_PHYREG_NUM*UNALLOCATE_PHYREG)-1:0] o_prm_unallocate_phyreg,

    // Write Back Concatenation
        // <- PC Input
    input  wire [EX_PATH_NUM-1:0]                             i_wbc2fcl_done,
    input  wire [(EX_PATH_NUM*BITWIDTH_FCL_PC_WIDTH)-1:0]     i_wbc2fcl_pc,
    input  wire                                               i_wbc2fcl_branch,
    input  wire [INST_PC_WIDTH-1:0]                           i_wbc2fcl_branch_pc,

    // Instruction Memory
        // -> New PC Output
    input  wire [DECODE_NEW_INST-1:0]                         i_im_inst_valid,
    output reg                                                o_im_re, // read enable
    output wire [BITWIDTH_FCL_PC_WIDTH-1:0]                   o_im_pc
);
    wire [(FCL_RB_NUM*BITWIDTH_FCL_RB_NUM)-1:0] available_fcpath_out;
    wire [BITWIDTH_FCL_RB_NUM-1:0]              available_fcpath;
    wire [FCL_RB_NUM-1:0]                       fc_path_active, fc_path_available;

    reg  [1:0]                     state,      state_next;
    reg  [BITWIDTH_FCL_RB_NUM-1:0] pc_fcpath,  pc_fcpath_next;
    reg  [INST_PC_WIDTH-1:0]       pc_im_req,  pc_im_req_next;
    reg  [INST_PC_WIDTH-1:0]       pc_rb_last, pc_rb_last_next;

    localparam RESET               = 2'b00;
    localparam RUN                 = 2'b01;
    localparam BLOCK_ALLFCPATH_USE = 2'b10;
    localparam BLOCK_BRANCH        = 2'b11;

    assign o_im_pc = {pc_fcpath, pc_im_req};
    assign available_fcpath = available_fcpath_out[BITWIDTH_FCL_RB_NUM-1:0];

    always @(posedge clk or negedge reset_n) begin // Registers
        if (reset_n == 1'b0) begin
            state          <= RESET;
            pc_fcpath      <= 0;
            pc_im_req      <= 0;
            pc_rb_last     <= 0;
        end
        else begin
            state          <= state_next;
            pc_fcpath      <= pc_fcpath_next;
            pc_im_req      <= pc_im_req_next;
            pc_rb_last     <= pc_rb_last_next;
        end
    end

    reg                     update_pc_start;
    reg [INST_PC_WIDTH-1:0] update_pc_start_addr;
    reg                     update_pc_last;
    reg [INST_PC_WIDTH-1:0] update_pc_last_addr;
    always @(*) begin
        pc_fcpath_next  = pc_fcpath;
        pc_im_req_next  = pc_im_req;
        pc_rb_last_next = pc_rb_last;

        update_pc_start      = 1'b0;
        update_pc_start_addr = 0;
        update_pc_last       = 1'b0;
        update_pc_last_addr  = 0;

        case(state)
            RESET: begin 
                state_next      = (i_im_inst_valid && i_im_inst_get && !i_nel_block)? RUN : RESET; 
                o_im_re         = (!i_nel_block)? 1'b1 : 1'b0;
                update_pc_start = (i_im_inst_valid && i_im_inst_get && !i_nel_block)? 1'b1 : 1'b0; update_pc_start_addr = 0;
                update_pc_last  = (i_im_inst_valid && i_im_inst_get && !i_nel_block)? 1'b1 : 1'b0; update_pc_last_addr  = FCL_RB_PC_GAP_MAX;
                pc_im_req_next  = (i_im_inst_valid && i_im_inst_get && !i_nel_block)? FCL_PC_GAP : 0; 
                pc_rb_last_next = FCL_RB_PC_GAP_MAX;
            end
            RUN  : begin
                state_next = RUN;
                o_im_re = &i_im_inst_get & ~i_nel_block;
                if (!i_nel_block) begin
                    if ( |fc_path_available ) begin
                        if (i_nel_jump_inst) begin
                            pc_fcpath_next      = available_fcpath;
                            pc_im_req_next      = i_nel_jump_branch_pc;
                            pc_rb_last_next     = i_nel_jump_branch_pc + FCL_RB_PC_GAP_MAX;

                            update_pc_start = 1'b1; 
                            update_pc_start_addr = pc_im_req_next;
                            update_pc_last  = 1'b1; 
                            update_pc_last_addr  = pc_rb_last_next;
                        end
                        else begin
                            pc_im_req_next      = (i_im_inst_valid && i_im_inst_get)? pc_im_req + FCL_PC_GAP : pc_im_req;
                            if ( pc_im_req == pc_rb_last ) begin
                                pc_fcpath_next  = available_fcpath;
                                pc_rb_last_next = pc_im_req + (FCL_PC_GAP + FCL_RB_PC_GAP_MAX);

                                update_pc_start = 1'b1; 
                                update_pc_start_addr = pc_im_req_next;
                                update_pc_last  = 1'b1; 
                                update_pc_last_addr  = pc_rb_last_next;
                            end
                        end
                    end
                    else begin
                        state_next = BLOCK_ALLFCPATH_USE;
                        o_im_re = 1'b0;
                    end

                    // Wait Branch Result (Yes.. It doesn't have branch prediction)
                    if (i_nel_jreg_branch_inst) begin
                        state_next = BLOCK_BRANCH;
                        o_im_re = 1'b0;

                        update_pc_last  = 1'b1; 
                        update_pc_last_addr  = pc_im_req;
                    end
                end
                else begin
                    o_im_re = 1'b0;
                end
            end
            BLOCK_ALLFCPATH_USE: begin
                state_next = BLOCK_ALLFCPATH_USE;
                o_im_re = 1'b0;
                if ( |fc_path_available ) begin
                    state_next      = RUN;
                end
            end
            BLOCK_BRANCH: begin
                state_next = BLOCK_BRANCH;
                o_im_re = 1'b0;
                if (i_wbc2fcl_branch) begin
                    state_next      = RUN;
                    pc_fcpath_next  = available_fcpath;
                    pc_im_req_next  = i_wbc2fcl_branch_pc;
                    pc_rb_last_next = i_wbc2fcl_branch_pc + FCL_RB_PC_GAP_MAX;

                    update_pc_start = 1'b1; 
                    update_pc_start_addr = i_wbc2fcl_branch_pc;
                end
            end
        endcase
    end

    reg [BITWIDTH_FCL_RB_NUM-1:0]             split_fcpath; 
    reg [DECODE_NEW_INST-1:0]                 nel_newpc_valid_FCPATH[0:FCL_RB_NUM-1];
    reg [(INST_PC_WIDTH*DECODE_NEW_INST)-1:0] nel_newpc_split_FCPATH;
    reg [EX_PATH_NUM-1:0]                     wbc2fcl_pc_valid_FCPATH[0:FCL_RB_NUM-1];
    reg [(EX_PATH_NUM*INST_PC_WIDTH)-1:0]     wbc2fcl_pc_split_FCPATH;
    integer rcpath_split_idx, nel_newpc_idx, wbc2fcl_pc_idx;
    always @(*) begin
        for (nel_newpc_idx = 0; nel_newpc_idx < DECODE_NEW_INST; nel_newpc_idx = nel_newpc_idx+1) begin
            nel_newpc_split_FCPATH[(INST_PC_WIDTH*nel_newpc_idx) +: INST_PC_WIDTH] 
                = i_nel_newpc[ (BITWIDTH_FCL_PC_WIDTH*nel_newpc_idx) +: INST_PC_WIDTH];
        end
        for (wbc2fcl_pc_idx = 0; wbc2fcl_pc_idx < EX_PATH_NUM; wbc2fcl_pc_idx = wbc2fcl_pc_idx+1) begin
            wbc2fcl_pc_split_FCPATH[(INST_PC_WIDTH*wbc2fcl_pc_idx) +: INST_PC_WIDTH] 
                = i_wbc2fcl_pc[(BITWIDTH_FCL_PC_WIDTH*wbc2fcl_pc_idx) +: INST_PC_WIDTH];
        end
        for (rcpath_split_idx = 0; rcpath_split_idx < FCL_RB_NUM; rcpath_split_idx = rcpath_split_idx+1) begin
            nel_newpc_valid_FCPATH[rcpath_split_idx] = 0;
            for (nel_newpc_idx = 0; nel_newpc_idx < DECODE_NEW_INST; nel_newpc_idx = nel_newpc_idx+1) begin
                split_fcpath 
                    = i_nel_newpc[( (BITWIDTH_FCL_PC_WIDTH*nel_newpc_idx) + INST_PC_WIDTH ) +: BITWIDTH_FCL_RB_NUM];
                if (split_fcpath == rcpath_split_idx)
                    nel_newpc_valid_FCPATH[rcpath_split_idx][nel_newpc_idx] = 1'b1;
            end

            wbc2fcl_pc_valid_FCPATH[rcpath_split_idx] = 0;
            for (wbc2fcl_pc_idx = 0; wbc2fcl_pc_idx < EX_PATH_NUM; wbc2fcl_pc_idx = wbc2fcl_pc_idx+1) begin
                split_fcpath 
                    = i_wbc2fcl_pc[( (BITWIDTH_FCL_PC_WIDTH*wbc2fcl_pc_idx) + INST_PC_WIDTH ) +: BITWIDTH_FCL_RB_NUM];
                if (split_fcpath == rcpath_split_idx)
                    wbc2fcl_pc_valid_FCPATH[rcpath_split_idx][wbc2fcl_pc_idx] = (i_wbc2fcl_done[wbc2fcl_pc_idx])? 1'b1 : 1'b0;
            end
        end
    end

    wire [(FCL_RB_NUM*BITWIDTH_FCL_RB_NUM)-1:0] fc_path_pos_data;
    genvar path_pos_idx;
    generate
        for (path_pos_idx = 0; path_pos_idx < FCL_RB_NUM; path_pos_idx = path_pos_idx+1) begin
            assign fc_path_pos_data[(BITWIDTH_FCL_RB_NUM*path_pos_idx) +: BITWIDTH_FCL_RB_NUM] = path_pos_idx;
        end
    endgenerate
    position_splitter #(
        .INPUT_ENTRIES(FCL_RB_NUM),
        .DATA_WIDTH   (BITWIDTH_FCL_RB_NUM)
    ) U_FC_PATH_VALID (
    	.valid_position_i(~fc_path_active),
    	.position_data_i (fc_path_pos_data),
    	.out_position_o  (fc_path_available),
    	.data_o          (available_fcpath_out)
    );

    wire [FCL_RB_NUM-1:0]                              fc_path_free, fc_path_free_ordering_valid;
    wire [UNALLOCATE_PHYREG-1:0]                       unallocate_valid [0:FCL_RB_NUM-1];
    wire [(BITWIDTH_PHYREG_NUM*UNALLOCATE_PHYREG)-1:0] unallocate_phyreg[0:FCL_RB_NUM-1];
    wire [(FCL_RB_NUM*BITWIDTH_FCL_RB_NUM)-1:0]        new_free_target_fcpath_out;
    wire [BITWIDTH_FCL_RB_NUM-1:0]                     new_free_target_fcpath;
    
    assign new_free_target_fcpath = new_free_target_fcpath_out[BITWIDTH_FCL_RB_NUM-1:0];

    position_splitter #(
        .INPUT_ENTRIES(FCL_RB_NUM),
        .DATA_WIDTH   (BITWIDTH_FCL_RB_NUM)
    ) U_FC_PATH_FREE (
    	.valid_position_i(fc_path_free),
    	.position_data_i (fc_path_pos_data),
    	.out_position_o  (fc_path_free_ordering_valid),
    	.data_o          (new_free_target_fcpath_out)
    );

    reg                           free_active, free_active_next;
    reg [BITWIDTH_FCL_RB_NUM-1:0] free_target_fcpath, free_target_fcpath_next;
    always @(posedge clk or negedge reset_n) begin
        if (reset_n == 1'b0) begin
            free_active        <= 1'b0;
            free_target_fcpath <= 0;
        end
        else begin
            free_active        <= free_active_next;
            free_target_fcpath <= free_target_fcpath_next;
        end
    end
    always @(*) begin
        if (free_active == 1'b0) begin
            if (|fc_path_free) begin
                free_active_next = 1'b1;
                free_target_fcpath_next = new_free_target_fcpath;
            end
            else begin
                free_active_next = 1'b0;
                free_target_fcpath_next = free_target_fcpath;
            end
        end
        else begin // free_active == 1'b1
            free_target_fcpath_next = free_target_fcpath;

            if (!fc_path_free[free_target_fcpath]) begin
                free_active_next = 1'b0;
            end
            else begin
                free_active_next = 1'b1;
            end
        end
    end

    genvar fdu_fcpath_idx;
    generate
        for (fdu_fcpath_idx = 0; fdu_fcpath_idx < FCL_RB_NUM; fdu_fcpath_idx = fdu_fcpath_idx+1) begin
            flow_detect_unit #(
                .DECODE_NEW_INST   (DECODE_NEW_INST),
                .PHYREG_NUM        (PHYREG_NUM),
                .UNALLOCATE_PHYREG (UNALLOCATE_PHYREG),
                .INST_PC_WIDTH     (INST_PC_WIDTH)
            ) U_FLOW_DETECT_UNIT (
                .clk                    (clk),
                .reset_n                (reset_n),
                .o_entry_active         (fc_path_active[fdu_fcpath_idx]),
                .o_entry_free           (fc_path_free[fdu_fcpath_idx]),
                .i_set_start_pc_valid   ( (pc_fcpath_next == fdu_fcpath_idx)? update_pc_start      : 1'b0 ),
                .i_set_start_pc         ( (pc_fcpath_next == fdu_fcpath_idx)? update_pc_start_addr :    0 ),
                .i_set_last_pc_valid    ( (pc_fcpath_next == fdu_fcpath_idx)? update_pc_last       : 1'b0 ),
                .i_set_last_pc          ( (pc_fcpath_next == fdu_fcpath_idx)? update_pc_last_addr  :    0 ),
                .i_nel_newpc_valid      (nel_newpc_valid_FCPATH[fdu_fcpath_idx]),
                .i_nel_newpc            (nel_newpc_split_FCPATH),
                .i_nel_lastreg_valid    (i_nel_lastreg_valid),
                .i_nel_lastreg          (i_nel_lastreg),
                .i_wbc2fcl_done         (wbc2fcl_pc_valid_FCPATH[fdu_fcpath_idx]),
                .i_wbc2fcl_pc           (wbc2fcl_pc_split_FCPATH),
                .i_unallocate_use       ( (free_active && (free_target_fcpath == fdu_fcpath_idx))? 1'b1 : 1'b0 ),
                .o_prm_unallocate_valid (unallocate_valid[fdu_fcpath_idx]),
                .o_prm_unallocate_phyreg(unallocate_phyreg[fdu_fcpath_idx])
            );
        end
    endgenerate

    assign o_prm_unallocate_valid  = unallocate_valid[free_target_fcpath][UNALLOCATE_PHYREG-1:0];
    assign o_prm_unallocate_phyreg = unallocate_phyreg[free_target_fcpath][(BITWIDTH_PHYREG_NUM*UNALLOCATE_PHYREG)-1:0];

endmodule

module flow_detect_unit #(
    parameter DECODE_NEW_INST               = 1,
    parameter PHYREG_NUM                    = 64,
    parameter UNALLOCATE_PHYREG             = 4,
    parameter INST_PC_WIDTH                 = 32,
    parameter EX_PATH_NUM                   = 3,

    localparam MAX_PC_RANGE                 = PHYREG_NUM/2,
    localparam BITWIDTH_PC_RANGE            = $clog2(MAX_PC_RANGE),
    localparam BITWIDTH_PHYREG_NUM          = $clog2(PHYREG_NUM)
) (
    input  wire                  clk,
    input  wire                  reset_n,

    // Flow Control Logic
        // <- Entry Valid input
    // input  wire                                               i_entry_force_deactive,
        // -> Entry Valid output
    output reg                                                o_entry_active,
    output reg                                                o_entry_free,
        // <- PC Input
    input  wire                                               i_set_start_pc_valid,
    input  wire [INST_PC_WIDTH-1:0]                           i_set_start_pc,
    input  wire                                               i_set_last_pc_valid,
    input  wire [INST_PC_WIDTH-1:0]                           i_set_last_pc,
        // <- Allocate Registers input
    input  wire [DECODE_NEW_INST-1:0]                         i_nel_newpc_valid,
    input  wire [(INST_PC_WIDTH*DECODE_NEW_INST)-1:0]         i_nel_newpc,
    input  wire [DECODE_NEW_INST-1:0]                         i_nel_lastreg_valid,
    input  wire [(BITWIDTH_PHYREG_NUM*DECODE_NEW_INST)-1:0]   i_nel_lastreg,

    // Write Back Concatenation
        // <- PC Input
    input  wire [EX_PATH_NUM-1:0]                             i_wbc2fcl_done,
    input  wire [(EX_PATH_NUM*INST_PC_WIDTH)-1:0]             i_wbc2fcl_pc,
    
    // Physical Register Mapper
        // -> Unallocate Registers Output
    input  wire                                               i_unallocate_use,
    output wire [UNALLOCATE_PHYREG-1:0]                       o_prm_unallocate_valid,
    output wire [(BITWIDTH_PHYREG_NUM*UNALLOCATE_PHYREG)-1:0] o_prm_unallocate_phyreg
);
    reg  [BITWIDTH_PC_RANGE-1:0] entry_done_range_sum;
    reg  [INST_PC_WIDTH-1:0] split_wb_pc[0:EX_PATH_NUM-1];
    wire [(UNALLOCATE_PHYREG*2)-1:0] phyreg_unallocate_valid;
    wire [(BITWIDTH_PHYREG_NUM*(UNALLOCATE_PHYREG*2))-1:0] phyreg_unallocate;
    wire [INST_PC_WIDTH-1:0]                           new_range_sub_pc;

    integer target_pc;

    // Register Variables
    reg [1:0]                  state,     state_next;
    reg [INST_PC_WIDTH-1:0]    pc_start,  pc_start_next;
    reg [INST_PC_WIDTH-1:0]    pc_last,   pc_last_next;
    reg [BITWIDTH_PC_RANGE:0]  range_cnt, range_cnt_next;
    reg [BITWIDTH_PC_RANGE:0]  range,     range_next;
    
    // FSM
    localparam UNACTIVE  = 2'b00;
    localparam ACTIVE    = 2'b01;
    localparam WAIT_FREE = 2'b10;
    localparam FREE      = 2'b11;

    // Registers
    always @(posedge clk or negedge reset_n) begin
        if (reset_n == 1'b0) begin
            state     <= UNACTIVE;
            pc_start  <= 0;
            pc_last   <= 0;
            range_cnt <= 0;
            range     <= 0;
        end
        else begin
            state     <= state_next;
            pc_start  <= pc_start_next;
            pc_last   <= pc_last_next;
            range_cnt <= range_cnt_next;
            range     <= range_next;
        end
    end

    // State Transition
    always @(*) begin
        case(state)
            UNACTIVE : begin
                if (i_set_start_pc_valid) state_next = ACTIVE;
                else                      state_next = UNACTIVE;
            end
            ACTIVE   : begin
                if (!i_set_last_pc_valid && (range_cnt == range)) state_next = WAIT_FREE;
                else                         state_next = ACTIVE;
            end
            WAIT_FREE: begin
                if (!i_unallocate_use) state_next = FREE;
                else                   state_next = WAIT_FREE;
            end
            FREE     : begin
                if (!(|phyreg_unallocate_valid)) state_next = UNACTIVE;
                else                             state_next = FREE;
            end
            default  : begin
                state_next = UNACTIVE;
            end
        endcase
    end

    // State Operations
    integer target_push_catch;
    reg [DECODE_NEW_INST-1:0]   push_valid;
    reg [UNALLOCATE_PHYREG-1:0] pop_get;
    always @(*) begin
        entry_done_range_sum = 0;
        for (target_pc = 0; target_pc < EX_PATH_NUM; target_pc = target_pc+1) begin
            split_wb_pc[target_pc] = i_wbc2fcl_pc[(INST_PC_WIDTH*target_pc) +: INST_PC_WIDTH];
            if (i_wbc2fcl_done[target_pc]) begin
                if ( (split_wb_pc[target_pc] >= pc_start) && (split_wb_pc[target_pc] <= pc_last) ) begin
                    entry_done_range_sum = entry_done_range_sum+1;
                end
            end
        end

        case(state)
            UNACTIVE: begin
                push_valid = 0;
                pop_get    = 0;
                if (i_set_start_pc_valid) begin
                    pc_start_next   = i_set_start_pc;
                    pc_last_next    = i_set_start_pc+(MAX_PC_RANGE << 2);
                    range_cnt_next  = 0;
                    range_next      = MAX_PC_RANGE;
                end
                else begin
                    pc_start_next   = 0;
                    pc_last_next    = 0;
                    range_cnt_next  = 0;
                    range_next      = 0;
                end
            end
            ACTIVE  : begin
                for (target_push_catch = 0; target_push_catch < DECODE_NEW_INST; target_push_catch = target_push_catch+1) begin
                    push_valid[target_push_catch] 
                        = ( (i_nel_newpc[(INST_PC_WIDTH*target_push_catch) +: INST_PC_WIDTH] >= pc_start) 
                            && (i_nel_newpc[(INST_PC_WIDTH*target_push_catch) +: INST_PC_WIDTH] <= pc_last) )? 
                                    i_nel_newpc_valid & i_nel_lastreg_valid : 1'b0;
                end
                pop_get         = 0;
                pc_start_next   = pc_start;
                pc_last_next    = (i_set_last_pc_valid)? i_set_last_pc : pc_last;
                range_cnt_next  = range_cnt + entry_done_range_sum;
                range_next      = (i_set_last_pc_valid)? new_range_sub_pc[BITWIDTH_PC_RANGE+1:2] : range;
            end
            WAIT_FREE: begin
                push_valid      = 0;
                pc_start_next   = 0;
                pop_get         = 0;
                pc_last_next    = 0;
                range_cnt_next  = 0;
                range_next      = 0;
            end
            FREE    : begin
                push_valid      = 0;
                pop_get         = {UNALLOCATE_PHYREG{1'b1}};
                pc_start_next   = 0;
                pc_last_next    = 0;
                range_cnt_next  = 0;
                range_next      = 0;
            end
            default : begin
                push_valid = 0;
                pc_start_next   = 0;
                pop_get         = 0;
                pc_last_next    = 0;
                range_cnt_next  = 0;
                range_next      = 0;
            end
        endcase
    end

    // State Output
    always @(*) begin
        case(state)
            UNACTIVE : begin
                o_entry_active  = 1'b0;
                o_entry_free    = 1'b0;
            end
            ACTIVE   : begin
                o_entry_active  = 1'b1;
                o_entry_free    = 1'b0;
            end
            WAIT_FREE: begin
                o_entry_active  = 1'b1;
                o_entry_free    = 1'b1;
            end
            FREE     : begin
                o_entry_active  = 1'b1;
                o_entry_free    = 1'b1;
            end
            default : begin
                o_entry_active  = 1'b0;
                o_entry_free    = 1'b0;
            end
        endcase
    end

    assign new_range_sub_pc = i_set_last_pc-pc_start;

    assign o_prm_unallocate_valid = (state == FREE)? phyreg_unallocate_valid[UNALLOCATE_PHYREG-1:0] : 0;
    assign o_prm_unallocate_phyreg = phyreg_unallocate[(BITWIDTH_PHYREG_NUM*UNALLOCATE_PHYREG)-1:0];

    fifo_ordering_position #(
        .PUSH_DATA      (DECODE_NEW_INST+1),
        .POP_DATA       (UNALLOCATE_PHYREG*2),
        .ENTRY_WIDTH    (BITWIDTH_PHYREG_NUM),
        .FIFO_DEPTH     ( (PHYREG_NUM/ (UNALLOCATE_PHYREG*2) )+1 )
    ) U_END_PHYREG_STORE (
    	.clk                (clk),
    	.reset_n            (reset_n),
    	.push_valid_i       ({1'b0, push_valid}),
    	.push_data_i        ({{BITWIDTH_PHYREG_NUM{1'b0}}, i_nel_lastreg}),
    	.pop_get_i          ({{UNALLOCATE_PHYREG{1'b0}}, pop_get}),
    	.pop_valid_o        (phyreg_unallocate_valid),
    	.pop_data_o         (phyreg_unallocate),
    	.push_available_o   ()
    );

endmodule
