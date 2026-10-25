`timescale 1ns / 1ps

module flow_control_logic #(
    // Instruction Set Parameters
    parameter int IS_INST_PC_BITWIDTH           = 32,
    parameter int IS_INST_PC_STEP               = 4,
    parameter int IS_INST_BITWIDTH               = 32,
    parameter int IS_INST_REGS                   = 32,
    parameter int IS_INST_OPERANDS               = 2,
    parameter int IS_INST_IMM                    = 32,

    // Execution Unit Parameters
    parameter int EX_INST_MICROOP_BITWIDTH       = 5,

    // EULSUKDO Structure Parameters
    parameter int STRUCT_DECODE_NEW_INST        = 1,
    parameter int STRUCT_INST_STATE_ENTRIES     = 128,
    parameter int STRUCT_PHYREGS                 = 64,
    parameter int STRUCT_EX_PATH                 = 3,
    parameter int STRUCT_RS_OUT_ENTRY [STRUCT_EX_PATH] = '{1, 1, 1},
    parameter int STRUCT_EX_CORES                = 3,
    parameter int STRUCT_EX_OUT_RESULT [STRUCT_EX_CORES] = '{1, 1, 1},
    parameter int STRUCT_EX_OUT_RESULT_SUM       = 3,
    parameter int STRUCT_PRM_ENTRY_UPDATE        = 3,
    parameter int STRUCT_PRM_ENTRY_BUFFER        = 4,
    parameter int STRUCT_UNALLOCATE_PHYREG       = 4,
    parameter int STRUCT_FLOW_WINDOWS            = 8,
    parameter int STRUCT_FLOW_PC_MAX_RANGE       = 8,

    // Auto-generated Localparams in Parameter section for port declaration usage
    localparam int _BITWIDTH_LOW_STRUCT_PHYREGS         = $clog2(STRUCT_PHYREGS),
    localparam int _BITWIDTH_LOW_STRUCT_FLOW_WINDOWS   = $clog2(STRUCT_FLOW_WINDOWS),
    localparam int _BITWIDTH_LOW_STRUCT_EX_PATH         = $clog2(STRUCT_EX_PATH),
    localparam int _BITWIDTH_LOW_STRUCT_INST_STATE_ENTRIES = $clog2(STRUCT_INST_STATE_ENTRIES),

    localparam int _STRUCT_EX_OUT_RESULT_ALL            = STRUCT_EX_OUT_RESULT_SUM,

    // Composite bitwidths
    localparam int _BITWIDTH_CMB_FLOW_INDEXnPC          = _BITWIDTH_LOW_STRUCT_FLOW_WINDOWS + IS_INST_PC_BITWIDTH,

    // PRM unallocator width
    localparam int PRM_UNALLOCATE_BITWIDTH              = _BITWIDTH_LOW_STRUCT_PHYREGS * STRUCT_UNALLOCATE_PHYREG,

    // Combined Jump/Branch packet width from NEL: [new_pc][branch][jump_reg][jump]
    localparam int NEL_JUMP_BRANCH_PACKET_WIDTH         = 3 + IS_INST_PC_BITWIDTH
) (
    input  wire                                                 clk,
    input  wire                                                 reset_n,

    // Instruction Memory interface
    input  wire [STRUCT_DECODE_NEW_INST-1:0]                    i_im_inst_valid,
    input  wire [STRUCT_DECODE_NEW_INST-1:0]                    i_im_inst_get,
    output reg                                                  o_im_re,
    output wire [_BITWIDTH_CMB_FLOW_INDEXnPC-1:0]               o_im_pc,

    // NEL Jump/Branch interface (i/o_nel_jump_branch_*)
    input  wire                                                 i_nel_jump_branch_valid,
    input  wire [NEL_JUMP_BRANCH_PACKET_WIDTH-1:0]              i_nel_jump_branch_data,

    // NEL newpc interface
    input  wire [STRUCT_DECODE_NEW_INST-1:0]                    i_nel_newpc_valid,
    input  wire [(STRUCT_DECODE_NEW_INST * _BITWIDTH_CMB_FLOW_INDEXnPC)-1:0] i_nel_newpc,

    // NEL Unallocate interface (i/o_nel_unallo_reg_*)
    input  wire [STRUCT_DECODE_NEW_INST-1:0]                    i_nel_unallo_reg_valid,
    input  wire [(STRUCT_DECODE_NEW_INST * _BITWIDTH_LOW_STRUCT_PHYREGS)-1:0] i_nel_unallo_reg_data,

    // PRM Unallocate interface (i/o_prm_unallocate_*)
    output wire [STRUCT_UNALLOCATE_PHYREG-1:0]                   o_prm_unallocate_valid,
    output wire [PRM_UNALLOCATE_BITWIDTH-1:0]                   o_prm_unallocate_phyreg,

    // WBC complete command PC interface (i/o_wbc_pc_*)
    input  wire [_STRUCT_EX_OUT_RESULT_ALL-1:0]                  i_wbc_pc_valid,
    input  wire [(_STRUCT_EX_OUT_RESULT_ALL * _BITWIDTH_CMB_FLOW_INDEXnPC)-1:0] i_wbc_pc_data,

    // WBC Branch resolve interface (i/o_wbc_branch_*)
    input  wire                                                 i_wbc_branch_valid,
    input  wire [(IS_INST_PC_BITWIDTH + 1)-1:0]                 i_wbc_branch_data,

    // NEL stall/block indicator
    input  wire                                                 i_nel_block
);

    // FCL Constants
    localparam int FCL_RB_PC_GAP_MAX = (STRUCT_PHYREGS / 2) * IS_INST_PC_STEP;

    // Unpack Jump/Branch inputs from NEL
    wire                                 nel_jump_inst;
    wire                                 nel_jreg_branch_inst;
    wire                                 nel_branch_inst;
    wire [IS_INST_PC_BITWIDTH-1:0]       nel_jump_branch_pc;

    assign nel_jump_inst        = i_nel_jump_branch_data[0] & i_nel_jump_branch_valid;
    assign nel_jreg_branch_inst = i_nel_jump_branch_data[1] & i_nel_jump_branch_valid;
    assign nel_branch_inst      = i_nel_jump_branch_data[2] & i_nel_jump_branch_valid;
    assign nel_jump_branch_pc   = i_nel_jump_branch_data[3 +: IS_INST_PC_BITWIDTH];

    // Unpack Branch inputs from WBC
    wire                                 wbc2fcl_branch;
    wire [IS_INST_PC_BITWIDTH-1:0]       wbc2fcl_branch_pc;

    assign wbc2fcl_branch        = i_wbc_branch_data[0] & i_wbc_branch_valid;
    assign wbc2fcl_branch_pc     = i_wbc_branch_data[1 +: IS_INST_PC_BITWIDTH];

    // Split WBC completed PCs into FDU compatible format (extract only PC)
    wire [(_STRUCT_EX_OUT_RESULT_ALL * IS_INST_PC_BITWIDTH)-1:0] wbc2fcl_pc_split;
    genvar wb_idx;
    generate
        for (wb_idx = 0; wb_idx < _STRUCT_EX_OUT_RESULT_ALL; wb_idx = wb_idx + 1) begin : gen_wbc_pc_split
            assign wbc2fcl_pc_split[wb_idx * IS_INST_PC_BITWIDTH +: IS_INST_PC_BITWIDTH] = 
                i_wbc_pc_data[wb_idx * _BITWIDTH_CMB_FLOW_INDEXnPC + _BITWIDTH_LOW_STRUCT_FLOW_WINDOWS +: IS_INST_PC_BITWIDTH];
        end
    endgenerate

    // FCL State Machine signals
    reg  [1:0]                                                  state,      state_next;
    reg  [_BITWIDTH_LOW_STRUCT_FLOW_WINDOWS-1:0]                pc_fcpath,  pc_fcpath_next;
    reg  [IS_INST_PC_BITWIDTH-1:0]                              pc_im_req,  pc_im_req_next;
    reg  [IS_INST_PC_BITWIDTH-1:0]                              pc_rb_last, pc_rb_last_next;

    localparam reg [1:0] RESET               = 2'b00;
    localparam reg [1:0] RUN                 = 2'b01;
    localparam reg [1:0] BLOCK_ALLFCPATH_USE = 2'b10;
    localparam reg [1:0] BLOCK_BRANCH        = 2'b11;

    assign o_im_pc = {pc_fcpath, pc_im_req};

    always @(posedge clk or negedge reset_n) begin
        if (reset_n == 1'b0) begin
            state          <= RESET;
            pc_fcpath      <= 0;
            pc_im_req      <= 0;
            pc_rb_last     <= 0;
        end else begin
            state          <= state_next;
            pc_fcpath      <= pc_fcpath_next;
            pc_im_req      <= pc_im_req_next;
            pc_rb_last     <= pc_rb_last_next;
        end
    end

    reg                                                         update_pc_start;
    reg  [IS_INST_PC_BITWIDTH-1:0]                              update_pc_start_addr;
    reg                                                         update_pc_last;
    reg  [IS_INST_PC_BITWIDTH-1:0]                              update_pc_last_addr;

    wire [(_BITWIDTH_LOW_STRUCT_FLOW_WINDOWS * STRUCT_FLOW_WINDOWS)-1:0] available_fcpath_out;
    wire [_BITWIDTH_LOW_STRUCT_FLOW_WINDOWS-1:0]                available_fcpath;
    wire [STRUCT_FLOW_WINDOWS-1:0]                              fc_path_active;
    wire [STRUCT_FLOW_WINDOWS-1:0]                              fc_path_available;

    localparam int _BITWIDTH_DECODE_NEW_INST = (STRUCT_DECODE_NEW_INST > 1) ? $clog2(STRUCT_DECODE_NEW_INST) : 1;
    reg [_BITWIDTH_DECODE_NEW_INST-1:0] last_get_idx;
    always @(*) begin
        last_get_idx = 0;
        for (integer i = 0; i < STRUCT_DECODE_NEW_INST; i = i + 1) begin
            if (i_im_inst_get[i]) begin
                last_get_idx = i[_BITWIDTH_DECODE_NEW_INST-1:0];
            end
        end
    end

    assign available_fcpath = available_fcpath_out[_BITWIDTH_LOW_STRUCT_FLOW_WINDOWS-1:0];

    always @(*) begin
        pc_fcpath_next  = pc_fcpath;
        pc_im_req_next  = pc_im_req;
        pc_rb_last_next = pc_rb_last;

        update_pc_start      = 1'b0;
        update_pc_start_addr = 0;
        update_pc_last       = 1'b0;
        update_pc_last_addr  = 0;

        case (state)
            RESET: begin 
                state_next      = ((&i_im_inst_valid) && (&i_im_inst_get) && !i_nel_block) ? RUN : RESET; 
                o_im_re         = (!i_nel_block) ? 1'b1 : 1'b0;
                update_pc_start = ((&i_im_inst_valid) && (&i_im_inst_get) && !i_nel_block) ? 1'b1 : 1'b0; 
                update_pc_start_addr = 0;
                update_pc_last  = ((&i_im_inst_valid) && (&i_im_inst_get) && !i_nel_block) ? 1'b1 : 1'b0; 
                update_pc_last_addr  = FCL_RB_PC_GAP_MAX;
                pc_im_req_next  = ((&i_im_inst_valid) && (&i_im_inst_get) && !i_nel_block) ? (STRUCT_DECODE_NEW_INST * IS_INST_PC_STEP) : 0; 
                pc_rb_last_next = FCL_RB_PC_GAP_MAX;
            end
            RUN: begin
                state_next = RUN;
                o_im_re = (&i_im_inst_get) & ~i_nel_block;
                
                if (!i_nel_block) begin
                    if (|fc_path_available) begin
                        if (nel_jump_inst) begin
                            pc_fcpath_next      = available_fcpath;
                            pc_im_req_next      = nel_jump_branch_pc;
                            pc_rb_last_next     = nel_jump_branch_pc + FCL_RB_PC_GAP_MAX;

                            update_pc_start      = 1'b1; 
                            update_pc_start_addr = pc_im_req_next;
                            update_pc_last       = 1'b1; 
                            update_pc_last_addr  = pc_rb_last_next;
                        end else begin
                            pc_im_req_next      = ((&i_im_inst_valid) && (&i_im_inst_get)) ? pc_im_req + (STRUCT_DECODE_NEW_INST * IS_INST_PC_STEP) : pc_im_req;
                            if (pc_im_req == pc_rb_last) begin
                                pc_fcpath_next  = available_fcpath;
                                pc_rb_last_next = pc_im_req_next + FCL_RB_PC_GAP_MAX;

                                update_pc_start      = 1'b1; 
                                update_pc_start_addr = pc_im_req_next;
                                update_pc_last       = 1'b1; 
                                update_pc_last_addr  = pc_rb_last_next;
                            end
                        end
                    end else begin
                        state_next = BLOCK_ALLFCPATH_USE;
                        o_im_re    = 1'b0;
                    end

                    if (nel_jreg_branch_inst || nel_branch_inst) begin
                        state_next = BLOCK_BRANCH;
                        o_im_re    = 1'b0;

                        update_pc_last      = 1'b1; 
                        update_pc_last_addr = pc_im_req + (last_get_idx * IS_INST_PC_STEP);
                    end
                end else begin
                    o_im_re = 1'b0;
                end
            end
            BLOCK_ALLFCPATH_USE: begin
                state_next = BLOCK_ALLFCPATH_USE;
                o_im_re    = 1'b0;
                if (|fc_path_available) begin
                    state_next = RUN;
                end
            end
            BLOCK_BRANCH: begin
                state_next = BLOCK_BRANCH;
                o_im_re    = 1'b0;
                if (wbc2fcl_branch) begin
                    state_next      = RUN;
                    pc_fcpath_next  = available_fcpath;
                    pc_im_req_next  = wbc2fcl_branch_pc;
                    pc_rb_last_next = wbc2fcl_branch_pc + FCL_RB_PC_GAP_MAX;

                    update_pc_start      = 1'b1; 
                    update_pc_start_addr = wbc2fcl_branch_pc;
                end
            end
            default: begin
                state_next = RESET;
                o_im_re    = 1'b0;
            end
        endcase
    end

    // Routing and demultiplexing incoming signals based on Flow Index (FCPATH)
    reg  [_BITWIDTH_LOW_STRUCT_FLOW_WINDOWS-1:0]                split_fcpath; 
    reg  [STRUCT_DECODE_NEW_INST-1:0]                           nel_newpc_valid_FCPATH [0:STRUCT_FLOW_WINDOWS-1];
    reg  [(IS_INST_PC_BITWIDTH * STRUCT_DECODE_NEW_INST)-1:0]   nel_newpc_split_FCPATH;
    reg  [_STRUCT_EX_OUT_RESULT_ALL-1:0]                        wbc2fcl_pc_valid_FCPATH [0:STRUCT_FLOW_WINDOWS-1];
    reg  [(_STRUCT_EX_OUT_RESULT_ALL * IS_INST_PC_BITWIDTH)-1:0] wbc2fcl_pc_split_FCPATH;

    always @(*) begin
        // Split new PC requests
        for (integer nel_newpc_idx = 0; nel_newpc_idx < STRUCT_DECODE_NEW_INST; nel_newpc_idx = nel_newpc_idx + 1) begin
            nel_newpc_split_FCPATH[(IS_INST_PC_BITWIDTH * nel_newpc_idx) +: IS_INST_PC_BITWIDTH] = 
                i_nel_newpc[( _BITWIDTH_CMB_FLOW_INDEXnPC * nel_newpc_idx ) +: IS_INST_PC_BITWIDTH];
        end

        // Split WBC complete command PCs
        for (integer wbc2fcl_pc_idx = 0; wbc2fcl_pc_idx < _STRUCT_EX_OUT_RESULT_ALL; wbc2fcl_pc_idx = wbc2fcl_pc_idx + 1) begin
            wbc2fcl_pc_split_FCPATH[(IS_INST_PC_BITWIDTH * wbc2fcl_pc_idx) +: IS_INST_PC_BITWIDTH] = 
                i_wbc_pc_data[( _BITWIDTH_CMB_FLOW_INDEXnPC * wbc2fcl_pc_idx ) + _BITWIDTH_LOW_STRUCT_FLOW_WINDOWS +: IS_INST_PC_BITWIDTH];
        end

        // Route valids to corresponding FDU windows
        for (integer rcpath_split_idx = 0; rcpath_split_idx < STRUCT_FLOW_WINDOWS; rcpath_split_idx = rcpath_split_idx + 1) begin
            nel_newpc_valid_FCPATH[rcpath_split_idx] = 0;
            for (integer nel_newpc_idx = 0; nel_newpc_idx < STRUCT_DECODE_NEW_INST; nel_newpc_idx = nel_newpc_idx + 1) begin
                split_fcpath = i_nel_newpc[( ( _BITWIDTH_CMB_FLOW_INDEXnPC * nel_newpc_idx ) + IS_INST_PC_BITWIDTH ) +: _BITWIDTH_LOW_STRUCT_FLOW_WINDOWS];
                if (split_fcpath == rcpath_split_idx) begin
                    nel_newpc_valid_FCPATH[rcpath_split_idx][nel_newpc_idx] = i_nel_newpc_valid[nel_newpc_idx];
                end
            end

            wbc2fcl_pc_valid_FCPATH[rcpath_split_idx] = 0;
            for (integer wbc2fcl_pc_idx = 0; wbc2fcl_pc_idx < _STRUCT_EX_OUT_RESULT_ALL; wbc2fcl_pc_idx = wbc2fcl_pc_idx + 1) begin
                split_fcpath = i_wbc_pc_data[( ( _BITWIDTH_CMB_FLOW_INDEXnPC * wbc2fcl_pc_idx ) ) +: _BITWIDTH_LOW_STRUCT_FLOW_WINDOWS];
                if (split_fcpath == rcpath_split_idx) begin
                    wbc2fcl_pc_valid_FCPATH[rcpath_split_idx][wbc2fcl_pc_idx] = (i_wbc_pc_valid[wbc2fcl_pc_idx]) ? 1'b1 : 1'b0;
                end
            end
        end
    end

    // Available Flow Paths tracker
    wire [(STRUCT_FLOW_WINDOWS * _BITWIDTH_LOW_STRUCT_FLOW_WINDOWS)-1:0] fc_path_pos_data;
    genvar path_pos_idx;
    generate
        for (path_pos_idx = 0; path_pos_idx < STRUCT_FLOW_WINDOWS; path_pos_idx = path_pos_idx + 1) begin : gen_path_positions
            assign fc_path_pos_data[(_BITWIDTH_LOW_STRUCT_FLOW_WINDOWS * path_pos_idx) +: _BITWIDTH_LOW_STRUCT_FLOW_WINDOWS] = path_pos_idx;
        end
    endgenerate

    position_splitter #(
        .INPUT_ENTRIES(STRUCT_FLOW_WINDOWS),
        .DATA_WIDTH   (_BITWIDTH_LOW_STRUCT_FLOW_WINDOWS)
    ) U_FC_PATH_VALID (
        .valid_position_i(~fc_path_active),
        .position_data_i (fc_path_pos_data),
        .out_position_o  (fc_path_available),
        .data_o          (available_fcpath_out)
    );

    // Freeing Flow Paths tracker
    wire [STRUCT_FLOW_WINDOWS-1:0]                              fc_path_free;
    wire [STRUCT_FLOW_WINDOWS-1:0]                              fc_path_free_ordering_valid;
    wire [(_BITWIDTH_LOW_STRUCT_FLOW_WINDOWS * STRUCT_FLOW_WINDOWS)-1:0] new_free_target_fcpath_out;
    wire [_BITWIDTH_LOW_STRUCT_FLOW_WINDOWS-1:0]                new_free_target_fcpath;
    
    assign new_free_target_fcpath = new_free_target_fcpath_out[_BITWIDTH_LOW_STRUCT_FLOW_WINDOWS-1:0];

    position_splitter #(
        .INPUT_ENTRIES(STRUCT_FLOW_WINDOWS),
        .DATA_WIDTH   (_BITWIDTH_LOW_STRUCT_FLOW_WINDOWS)
    ) U_FC_PATH_FREE (
        .valid_position_i(fc_path_free),
        .position_data_i (fc_path_pos_data),
        .out_position_o  (fc_path_free_ordering_valid),
        .data_o          (new_free_target_fcpath_out)
    );

    reg                                                         free_active, free_active_next;
    reg  [_BITWIDTH_LOW_STRUCT_FLOW_WINDOWS-1:0]                free_target_fcpath, free_target_fcpath_next;
    
    always @(posedge clk or negedge reset_n) begin
        if (reset_n == 1'b0) begin
            free_active        <= 1'b0;
            free_target_fcpath <= 0;
        end else begin
            free_active        <= free_active_next;
            free_target_fcpath <= free_target_fcpath_next;
        end
    end

    always @(*) begin
        if (free_active == 1'b0) begin
            if (|fc_path_free) begin
                free_active_next        = 1'b1;
                free_target_fcpath_next = new_free_target_fcpath;
            end else begin
                free_active_next        = 1'b0;
                free_target_fcpath_next = free_target_fcpath;
            end
        end else begin // free_active == 1'b1
            free_target_fcpath_next = free_target_fcpath;
            if (!fc_path_free[free_target_fcpath]) begin
                free_active_next = 1'b0;
            end else begin
                free_active_next = 1'b1;
            end
        end
    end

    // Instantiate FDUs (Flow Detect Units)
    wire [STRUCT_UNALLOCATE_PHYREG-1:0]                          unallocate_valid [0:STRUCT_FLOW_WINDOWS-1];
    wire [(STRUCT_UNALLOCATE_PHYREG * _BITWIDTH_LOW_STRUCT_PHYREGS)-1:0] unallocate_phyreg [0:STRUCT_FLOW_WINDOWS-1];

    genvar fdu_idx;
    generate
        for (fdu_idx = 0; fdu_idx < STRUCT_FLOW_WINDOWS; fdu_idx = fdu_idx + 1) begin : gen_fdu_instances
            flow_detect_unit #(
                .IS_INST_PC_BITWIDTH         (IS_INST_PC_BITWIDTH),
                .IS_INST_PC_STEP             (IS_INST_PC_STEP),
                .IS_INST_BITWIDTH             (IS_INST_BITWIDTH),
                .IS_INST_REGS                 (IS_INST_REGS),
                .IS_INST_OPERANDS             (IS_INST_OPERANDS),
                .IS_INST_IMM                  (IS_INST_IMM),
                .EX_INST_MICROOP_BITWIDTH     (EX_INST_MICROOP_BITWIDTH),
                .STRUCT_DECODE_NEW_INST      (STRUCT_DECODE_NEW_INST),
                .STRUCT_INST_STATE_ENTRIES   (STRUCT_INST_STATE_ENTRIES),
                .STRUCT_PHYREGS              (STRUCT_PHYREGS),
                .STRUCT_EX_PATH              (STRUCT_EX_PATH),
                .STRUCT_RS_OUT_ENTRY         (STRUCT_RS_OUT_ENTRY),
                .STRUCT_EX_CORES             (STRUCT_EX_CORES),
                .STRUCT_EX_OUT_RESULT        (STRUCT_EX_OUT_RESULT),
                .STRUCT_EX_OUT_RESULT_SUM    (STRUCT_EX_OUT_RESULT_SUM),
                .STRUCT_PRM_ENTRY_UPDATE     (STRUCT_PRM_ENTRY_UPDATE),
                .STRUCT_PRM_ENTRY_BUFFER     (STRUCT_PRM_ENTRY_BUFFER),
                .STRUCT_UNALLOCATE_PHYREG    (STRUCT_UNALLOCATE_PHYREG),
                .STRUCT_FLOW_WINDOWS         (STRUCT_FLOW_WINDOWS),
                .STRUCT_FLOW_PC_MAX_RANGE    (STRUCT_FLOW_PC_MAX_RANGE)
            ) U_FLOW_DETECT_UNIT (
                .clk                    (clk),
                .reset_n                (reset_n),
                .o_entry_active         (fc_path_active[fdu_idx]),
                .o_entry_free           (fc_path_free[fdu_idx]),
                .i_set_start_pc_valid   ((pc_fcpath_next == fdu_idx) ? update_pc_start      : 1'b0),
                .i_set_start_pc         ((pc_fcpath_next == fdu_idx) ? update_pc_start_addr :    0),
                .i_set_last_pc_valid    ((pc_fcpath_next == fdu_idx) ? update_pc_last       : 1'b0),
                .i_set_last_pc          ((pc_fcpath_next == fdu_idx) ? update_pc_last_addr  :    0),
                .i_nel_newpc_valid      (nel_newpc_valid_FCPATH[fdu_idx]),
                .i_nel_newpc            (nel_newpc_split_FCPATH),
                .i_nel_lastreg_valid    (i_nel_unallo_reg_valid),
                .i_nel_lastreg          (i_nel_unallo_reg_data),
                .i_wbc2fcl_done         (wbc2fcl_pc_valid_FCPATH[fdu_idx]),
                .i_wbc2fcl_pc           (wbc2fcl_pc_split_FCPATH),
                .i_unallocate_use       ((free_active && (free_target_fcpath == fdu_idx)) ? 1'b1 : 1'b0),
                .o_prm_unallocate_valid (unallocate_valid[fdu_idx]),
                .o_prm_unallocate_phyreg(unallocate_phyreg[fdu_idx])
            );
        end
    endgenerate

    // Connect final unallocate outputs to PRM
    assign o_prm_unallocate_valid  = unallocate_valid[free_target_fcpath][STRUCT_UNALLOCATE_PHYREG-1:0];
    assign o_prm_unallocate_phyreg = unallocate_phyreg[free_target_fcpath][(STRUCT_UNALLOCATE_PHYREG * _BITWIDTH_LOW_STRUCT_PHYREGS)-1:0];

endmodule
