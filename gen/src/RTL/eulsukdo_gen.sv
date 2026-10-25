`timescale 1ns / 1ps

module eulsukdo_gen #(
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
    parameter int STRUCT_RS_OUT_ENTRY_SUM        = 3,
    parameter int STRUCT_PRM_ENTRY_UPDATE        = 3,
    parameter int STRUCT_PRM_ENTRY_BUFFER        = 4,
    parameter int STRUCT_UNALLOCATE_PHYREG       = 4,
    parameter int STRUCT_FLOW_WINDOWS            = 8,
    parameter int STRUCT_FLOW_PC_MAX_RANGE       = 8,

    // Auto-generated Localparams in Parameter section for port declaration usage
    localparam _BITWIDTH_LOW_STRUCT_FLOW_WINDOWS = $clog2(STRUCT_FLOW_WINDOWS),
    localparam _BITWIDTH_LOW_STRUCT_PHYREGS      = $clog2(STRUCT_PHYREGS),
    localparam _BITWIDTH_LOW_STRUCT_EX_PATH      = $clog2(STRUCT_EX_PATH),
    localparam _BITWIDTH_LOW_STRUCT_INST_STATE_ENTRIES = $clog2(STRUCT_INST_STATE_ENTRIES),
    localparam _BITWIDTH_LOW_IS_INST_REGS        = $clog2(IS_INST_REGS),
    localparam _STRUCT_EX_OUT_RESULT_ALL         = STRUCT_EX_OUT_RESULT_SUM,
    localparam _STRUCT_RS_OUT_ENTRY_ALL          = STRUCT_RS_OUT_ENTRY_SUM,

    // Composite Bitwidths (LSB to MSB ordering combined with 'n')
    localparam _BITWIDTH_CMB_FLOW_INDEXnPC       = _BITWIDTH_LOW_STRUCT_FLOW_WINDOWS + IS_INST_PC_BITWIDTH
) (
    input  wire                                                 clk,
    input  wire                                                 reset_n,

    // Instruction Memory Interface (i/o_im_inst_*)
    input  wire [STRUCT_DECODE_NEW_INST-1:0]                    i_im_inst_valid,
    input  wire [(STRUCT_DECODE_NEW_INST*IS_INST_BITWIDTH)-1:0] i_im_inst,
    output wire [STRUCT_DECODE_NEW_INST-1:0]                    o_im_inst_get,
    output wire [(STRUCT_DECODE_NEW_INST*IS_INST_BITWIDTH)-1:0] o_dec_inst,

    // Instruction Memory PC Output (i/o_im_pc_*)
    output wire                                                 o_im_pc_valid, // equivalent to o_im_re / o_im_re
    output wire [_BITWIDTH_CMB_FLOW_INDEXnPC-1:0]               o_im_pc,

    // Decoded Signals Interface from external ISA Decoder (i_dec_*)
    input  wire [(STRUCT_DECODE_NEW_INST * _BITWIDTH_LOW_IS_INST_REGS)-1:0] i_dec_rd,
    input  wire [(STRUCT_DECODE_NEW_INST * IS_INST_OPERANDS * _BITWIDTH_LOW_IS_INST_REGS)-1:0] i_dec_rs,
    input  wire [STRUCT_DECODE_NEW_INST-1:0]                    i_dec_exception,
    input  wire [STRUCT_DECODE_NEW_INST-1:0]                    i_dec_newreg_alloc,
    input  wire [STRUCT_DECODE_NEW_INST-1:0]                    i_dec_jump,
    input  wire [STRUCT_DECODE_NEW_INST-1:0]                    i_dec_jump_reg,
    input  wire [STRUCT_DECODE_NEW_INST-1:0]                    i_dec_branch,
    input  wire [(STRUCT_DECODE_NEW_INST * _BITWIDTH_LOW_STRUCT_EX_PATH)-1:0] i_dec_expath,
    input  wire [(STRUCT_DECODE_NEW_INST * EX_INST_MICROOP_BITWIDTH)-1:0] i_dec_microop,
    input  wire [(STRUCT_DECODE_NEW_INST * IS_INST_IMM)-1:0]    i_dec_imm,

    // Ready Station Execution Issue Interface (o_ex_entry_*)
    output wire [_STRUCT_RS_OUT_ENTRY_ALL-1:0]                  o_ex_entry_valid,
    output wire [(_STRUCT_RS_OUT_ENTRY_ALL * (_BITWIDTH_CMB_FLOW_INDEXnPC + EX_INST_MICROOP_BITWIDTH + IS_INST_IMM + _BITWIDTH_LOW_STRUCT_PHYREGS + (_BITWIDTH_LOW_STRUCT_PHYREGS * IS_INST_OPERANDS)))-1:0] o_ex_entry,
    input  wire [_STRUCT_RS_OUT_ENTRY_ALL-1:0]                  i_ex_entry_get,

    // Execution Unit Write Back Interface (i_ex_done_*)
    input  wire [_STRUCT_EX_OUT_RESULT_ALL-1:0]                  i_ex_done,
    input  wire [(_STRUCT_EX_OUT_RESULT_ALL*_BITWIDTH_CMB_FLOW_INDEXnPC)-1:0] i_ex_done_pc,
    input  wire [(_STRUCT_EX_OUT_RESULT_ALL*_BITWIDTH_LOW_STRUCT_PHYREGS)-1:0] i_ex_done_phyreg,
    input  wire                                                 i_ex_done_branch,
    input  wire [IS_INST_PC_BITWIDTH-1:0]                       i_ex_done_branch_pc
);

    // -------------------------------------------------------------------------
    // Bitwidth and Startpoint Localparams (derived values)
    // -------------------------------------------------------------------------
    localparam int RS_PUSH_WIDTH                        = STRUCT_PRM_ENTRY_UPDATE + STRUCT_DECODE_NEW_INST;

    localparam int IST_BITWIDTH_OPREAND_PHYREG_FULL    = _BITWIDTH_LOW_STRUCT_PHYREGS * IS_INST_OPERANDS;
    localparam int IST_BITWIDTH_OPREAND_READY_FULL     = IS_INST_OPERANDS;
    
    localparam int IST_BITWIDTH                         = _BITWIDTH_CMB_FLOW_INDEXnPC + 
                                                          _BITWIDTH_LOW_STRUCT_EX_PATH + 
                                                          EX_INST_MICROOP_BITWIDTH + 
                                                          IS_INST_IMM + 
                                                          _BITWIDTH_LOW_STRUCT_PHYREGS + 
                                                          IST_BITWIDTH_OPREAND_PHYREG_FULL + 
                                                          IST_BITWIDTH_OPREAND_READY_FULL;

    localparam int IST_PACKET_BITWIDTH                  = IST_BITWIDTH * STRUCT_DECODE_NEW_INST;

    localparam int PRM_ALLOCATE_BITWIDTH                = _BITWIDTH_LOW_STRUCT_PHYREGS * STRUCT_DECODE_NEW_INST;
    localparam int PRM_UNALLOCATE_BITWIDTH              = _BITWIDTH_LOW_STRUCT_PHYREGS * STRUCT_UNALLOCATE_PHYREG;

    localparam int RS_ENTRY_BITWIDTH                    = _BITWIDTH_CMB_FLOW_INDEXnPC + 
                                                          _BITWIDTH_LOW_STRUCT_EX_PATH + 
                                                          EX_INST_MICROOP_BITWIDTH + 
                                                          IS_INST_IMM + 
                                                          _BITWIDTH_LOW_STRUCT_PHYREGS + 
                                                          IST_BITWIDTH_OPREAND_PHYREG_FULL;

    localparam int RS_PACKET_BITWIDTH                   = RS_ENTRY_BITWIDTH * RS_PUSH_WIDTH;
    
    localparam int NEL_JUMP_BRANCH_PACKET_WIDTH         = 3 + IS_INST_PC_BITWIDTH;

    // -------------------------------------------------------------------------
    // Interconnect Wires
    // -------------------------------------------------------------------------
    wire [(_BITWIDTH_CMB_FLOW_INDEXnPC * STRUCT_DECODE_NEW_INST)-1:0] nel_inst_pc;
    wire                                                              ist_insert_available;
    wire [STRUCT_DECODE_NEW_INST-1:0]                                 ist_field_insert;
    wire [STRUCT_DECODE_NEW_INST-1:0]                                 ist_field_valid;
    wire [IST_PACKET_BITWIDTH-1:0]                                    ist_field;
    wire [STRUCT_DECODE_NEW_INST-1:0]                                 allocate_position;
    wire [STRUCT_DECODE_NEW_INST-1:0]                                 prm_allocate_valid;
    wire [PRM_ALLOCATE_BITWIDTH-1:0]                                  prm_allocate_phyreg;
    wire [_STRUCT_EX_OUT_RESULT_ALL-1:0]                              wbc2nel_done;
    wire [(_STRUCT_EX_OUT_RESULT_ALL * _BITWIDTH_LOW_STRUCT_PHYREGS)-1:0] wbc2nel_done_phyreg;
    wire                                                              nel_block;
    wire                                                              nel_jump_inst;
    wire                                                              nel_jreg_branch_inst;
    wire [IS_INST_PC_BITWIDTH-1:0]                                    nel_jump_branch_pc;
    wire [STRUCT_DECODE_NEW_INST-1:0]                                 nel_newpc_valid;
    wire [(STRUCT_DECODE_NEW_INST * _BITWIDTH_CMB_FLOW_INDEXnPC)-1:0] nel_newpc;
    wire [STRUCT_DECODE_NEW_INST-1:0]                                 nel_lastreg_valid;
    wire [(STRUCT_DECODE_NEW_INST * _BITWIDTH_LOW_STRUCT_PHYREGS)-1:0] nel_lastreg;

    wire [(STRUCT_DECODE_NEW_INST * IS_INST_OPERANDS)-1:0]            prm_istindex_valid;
    wire [(STRUCT_DECODE_NEW_INST * IS_INST_OPERANDS * (_BITWIDTH_LOW_STRUCT_INST_STATE_ENTRIES + _BITWIDTH_LOW_STRUCT_PHYREGS))-1:0] prm_istindex_data;

    wire [STRUCT_PRM_ENTRY_UPDATE-1:0]                                ready_update_valid;
    wire [STRUCT_PRM_ENTRY_UPDATE-1:0]                                ready_update_get;
    wire [(STRUCT_PRM_ENTRY_UPDATE * (_BITWIDTH_LOW_STRUCT_INST_STATE_ENTRIES + _BITWIDTH_LOW_STRUCT_PHYREGS))-1:0] ready_update_data;

    wire [(IS_INST_PC_BITWIDTH + 1)-1:0]                              wbc2fcl_branch_data;
    wire [155:0]                                                      wbc_ex_result_data;


    wire                                                              push_rs_available;
    wire [RS_PUSH_WIDTH-1:0]                                          push_rs_valid;
    wire [RS_PACKET_BITWIDTH-1:0]                                     push_rs_data;

    wire [STRUCT_UNALLOCATE_PHYREG-1:0]                               prm_unallocate_valid;
    wire [PRM_UNALLOCATE_BITWIDTH-1:0]                                prm_unallocate_phyreg;

    wire [_STRUCT_EX_OUT_RESULT_ALL-1:0]                              wb_done;
    wire [(_STRUCT_EX_OUT_RESULT_ALL * _BITWIDTH_LOW_STRUCT_PHYREGS)-1:0] wb_done_phyreg;
    wire                                                              prm_active;

    wire [_STRUCT_EX_OUT_RESULT_ALL-1:0]                              wbc2fcl_done;
    wire [(_STRUCT_EX_OUT_RESULT_ALL * _BITWIDTH_CMB_FLOW_INDEXnPC)-1:0] wbc2fcl_pc;
    wire                                                              wbc2fcl_branch;
    wire [IS_INST_PC_BITWIDTH-1:0]                                    wbc2fcl_branch_pc;

    // -------------------------------------------------------------------------
    // Parallel Instruction PC Offset Mapping logic
    // -------------------------------------------------------------------------
    genvar pc_gen_idx;
    generate
        for (pc_gen_idx = 0; pc_gen_idx < STRUCT_DECODE_NEW_INST; pc_gen_idx = pc_gen_idx + 1) begin : gen_nel_pcs
            wire [_BITWIDTH_LOW_STRUCT_FLOW_WINDOWS-1:0] now_fcpath;
            wire [IS_INST_PC_BITWIDTH-1:0] now_pc;
            
            assign now_fcpath = o_im_pc[_BITWIDTH_CMB_FLOW_INDEXnPC-1 : IS_INST_PC_BITWIDTH];
            assign now_pc     = o_im_pc[IS_INST_PC_BITWIDTH-1 : 0] + (pc_gen_idx * IS_INST_PC_STEP);
            assign nel_inst_pc[pc_gen_idx * _BITWIDTH_CMB_FLOW_INDEXnPC +: _BITWIDTH_CMB_FLOW_INDEXnPC] = {now_fcpath, now_pc};
        end
    endgenerate

    // Bypass instruction raw data to external decoder
    assign o_dec_inst = i_im_inst;

    // FCL jump packet translation
    wire [NEL_JUMP_BRANCH_PACKET_WIDTH-1:0] fcl_jump_branch_data;
    assign fcl_jump_branch_data = {
        nel_jump_branch_pc,
        1'b0,
        nel_jreg_branch_inst,
        nel_jump_inst
    };

    // WBC 패킹 데이터 조립을 위한 분해 및 조립
    // i_ex_done_pc에서 각 실행 코어별 Flow Index와 실제 PC 분리
    wire [_BITWIDTH_LOW_STRUCT_FLOW_WINDOWS-1:0] flow_idx_branch = i_ex_done_pc[IS_INST_PC_BITWIDTH +: _BITWIDTH_LOW_STRUCT_FLOW_WINDOWS];
    wire [IS_INST_PC_BITWIDTH-1:0]               real_pc_branch  = i_ex_done_pc[IS_INST_PC_BITWIDTH-1:0];

    wire [_BITWIDTH_LOW_STRUCT_FLOW_WINDOWS-1:0] flow_idx_alu    = i_ex_done_pc[_BITWIDTH_CMB_FLOW_INDEXnPC + IS_INST_PC_BITWIDTH +: _BITWIDTH_LOW_STRUCT_FLOW_WINDOWS];
    wire [IS_INST_PC_BITWIDTH-1:0]               real_pc_alu     = i_ex_done_pc[_BITWIDTH_CMB_FLOW_INDEXnPC +: IS_INST_PC_BITWIDTH];

    wire [_BITWIDTH_LOW_STRUCT_FLOW_WINDOWS-1:0] flow_idx_mem    = i_ex_done_pc[(_BITWIDTH_CMB_FLOW_INDEXnPC * 2) + IS_INST_PC_BITWIDTH +: _BITWIDTH_LOW_STRUCT_FLOW_WINDOWS];
    wire [IS_INST_PC_BITWIDTH-1:0]               real_pc_mem     = i_ex_done_pc[(_BITWIDTH_CMB_FLOW_INDEXnPC * 2) +: IS_INST_PC_BITWIDTH];

    // i_ex_done_phyreg 에서 각 코어별 rd 물리 레지스터 주소 분리
    wire [_BITWIDTH_LOW_STRUCT_PHYREGS-1:0] rd_num_branch = i_ex_done_phyreg[0 +: _BITWIDTH_LOW_STRUCT_PHYREGS];
    wire [_BITWIDTH_LOW_STRUCT_PHYREGS-1:0] rd_num_alu    = i_ex_done_phyreg[(_BITWIDTH_LOW_STRUCT_PHYREGS * 1) +: _BITWIDTH_LOW_STRUCT_PHYREGS];
    wire [_BITWIDTH_LOW_STRUCT_PHYREGS-1:0] rd_num_mem    = i_ex_done_phyreg[(_BITWIDTH_LOW_STRUCT_PHYREGS * 2) +: _BITWIDTH_LOW_STRUCT_PHYREGS];

    // WBC로 보낼 패킹 데이터 조립 (MSB [MEM][ALU][Branch] LSB)
    assign wbc_ex_result_data = {
        rd_num_mem, flow_idx_mem, real_pc_mem,
        rd_num_alu, flow_idx_alu, real_pc_alu,
        i_ex_done_branch_pc, i_ex_done_branch, rd_num_branch, flow_idx_branch, real_pc_branch
    };

    // -------------------------------------------------------------------------
    // Sub-module Instantiations
    // -------------------------------------------------------------------------

    new_entry_logic #(
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
    ) U_NEL (
        .clk                         (clk),
        .reset_n                     (reset_n),
        .i_im_inst_valid             (i_im_inst_valid),
        .i_im_inst_pc                (nel_inst_pc),
        .o_im_inst_get                 (o_im_inst_get),
        .i_dec_rd                    (i_dec_rd),
        .i_dec_rs                    (i_dec_rs),
        .i_dec_exception             (i_dec_exception),
        .i_dec_newreg_alloc          (i_dec_newreg_alloc),
        .i_dec_jump                  (i_dec_jump),
        .i_dec_jump_reg              (i_dec_jump_reg),
        .i_dec_branch                (i_dec_branch),
        .i_dec_expath                (i_dec_expath),
        .i_dec_microop               (i_dec_microop),
        .i_dec_imm                   (i_dec_imm),
        .i_ist_insert_available      (ist_insert_available),
        .o_ist_field_insert            (ist_field_insert),
        .i_ist_field_valid             (ist_field_valid),
        .o_ist_field                   (ist_field),
        .o_allocate_position           (allocate_position),
        .i_prm_active                  (prm_active),
        .i_prm_allocate_valid          (prm_allocate_valid),
        .i_prm_allocate_phyreg         (prm_allocate_phyreg),
        .i_wbc2nel_done                (wbc2nel_done),
        .i_wbc2nel_done_phyreg         (wbc2nel_done_phyreg),
        .o_nel_block                   (nel_block),
        .o_nel_jump_inst               (nel_jump_inst),
        .o_nel_jreg_branch_inst        (nel_jreg_branch_inst),
        .o_nel_jump_branch_pc          (nel_jump_branch_pc),
        .o_nel_newpc_valid             (nel_newpc_valid),
        .o_nel_newpc                   (nel_newpc),
        .o_nel_lastreg_valid           (nel_lastreg_valid),
        .o_nel_lastreg                 (nel_lastreg)
    );

    instruction_state_table #(
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
        .STRUCT_PRM_ENTRY_UPDATE     (STRUCT_PRM_ENTRY_UPDATE),
        .STRUCT_PRM_ENTRY_BUFFER     (STRUCT_PRM_ENTRY_BUFFER),
        .STRUCT_UNALLOCATE_PHYREG    (STRUCT_UNALLOCATE_PHYREG),
        .STRUCT_FLOW_WINDOWS         (STRUCT_FLOW_WINDOWS),
        .STRUCT_FLOW_PC_MAX_RANGE    (STRUCT_FLOW_PC_MAX_RANGE)
    ) U_IST (
        .clk                         (clk),
        .reset_n                     (reset_n),
        .o_nel_newinst_get             (ist_insert_available),
        .i_nel_newinst_valid           (ist_field_insert),
        .i_nel_newinst_data            (ist_field),
        .o_prm_wait_phyreg_valid       (prm_istindex_valid),
        .o_prm_wait_phyreg_data        (prm_istindex_data),
        .i_prm_ready_phyreg_valid      (ready_update_valid),
        .o_prm_ready_phyreg_get        (ready_update_get),
        .i_prm_ready_phyreg_data       (ready_update_data),
        .i_rs_readyinst_get            (push_rs_available),
        .o_rs_readyinst_valid          (push_rs_valid),
        .o_rs_readyinst_data           (push_rs_data)
    );

    physical_register_mapping #(
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
    ) U_PRM (
        .clk                         (clk),
        .reset_n                     (reset_n),
        .i_nel_allocate_get            (allocate_position),
        .o_nel_allocate_valid          (prm_allocate_valid),
        .o_nel_allocate_phyreg         (prm_allocate_phyreg),
        .i_fcl_unallocate_valid        (prm_unallocate_valid),
        .i_fcl_unallocate_phyreg       (prm_unallocate_phyreg),
        .i_ist_unallocate_valid        (prm_istindex_valid),
        .i_ist_unallocate_data         (prm_istindex_data),
        .o_ist_ready_phyreg_valid      (ready_update_valid),
        .i_ist_ready_phyreg_get        (ready_update_get),
        .o_ist_ready_phyreg_data       (ready_update_data),
        .i_wbc_phyreg_valid            (wb_done),
        .i_wbc_phyreg_data             (wb_done_phyreg),
        .o_prm_active                  (prm_active)
    );

    ready_station #(
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
        .STRUCT_RS_OUT_ENTRY_SUM     (STRUCT_RS_OUT_ENTRY_SUM),
        .STRUCT_EX_CORES             (STRUCT_EX_CORES),
        .STRUCT_EX_OUT_RESULT        (STRUCT_EX_OUT_RESULT),
        .STRUCT_PRM_ENTRY_UPDATE     (STRUCT_PRM_ENTRY_UPDATE),
        .STRUCT_PRM_ENTRY_BUFFER     (STRUCT_PRM_ENTRY_BUFFER),
        .STRUCT_UNALLOCATE_PHYREG    (STRUCT_UNALLOCATE_PHYREG),
        .STRUCT_FLOW_WINDOWS         (STRUCT_FLOW_WINDOWS),
        .STRUCT_FLOW_PC_MAX_RANGE    (STRUCT_FLOW_PC_MAX_RANGE)
    ) U_RS (
        .clk                         (clk),
        .reset_n                     (reset_n),
        .o_ist_readyinst_get           (push_rs_available),
        .i_ist_readyinst_valid         (push_rs_valid),
        .i_ist_readyinst_data          (push_rs_data),
        .i_ex_exeinst_get              (i_ex_entry_get),
        .o_ex_exeinst_valid            (o_ex_entry_valid),
        .o_ex_exeinst_data             (o_ex_entry)
    );

    write_back_concatenation #(
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
    ) U_WBC (
        .clk                         (clk),
        .reset_n                     (reset_n),
        .i_ex_result_valid             (i_ex_done),
        .i_ex_result_data              (wbc_ex_result_data),
        .o_prm_phyreg_valid            (wb_done),
        .o_prm_phyreg_data             (wb_done_phyreg),
        .o_nel_phyreg_valid            (wbc2nel_done),
        .o_nel_phyreg_data             (wbc2nel_done_phyreg),
        .o_fcl_pc_valid                (wbc2fcl_done),
        .o_fcl_pc_data                 (wbc2fcl_pc),
        .o_fcl_branch_valid            (wbc2fcl_branch),
        .o_fcl_branch_data             (wbc2fcl_branch_data)
    );

    flow_control_logic #(
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
    ) U_FCL (
        .clk                         (clk),
        .reset_n                     (reset_n),
        .i_im_inst_valid             (i_im_inst_valid),
        .i_im_inst_get                 (o_im_inst_get),
        .o_im_re                     (o_im_pc_valid),
        .o_im_pc                     (o_im_pc),
        .i_nel_jump_branch_valid     (nel_jump_inst | nel_jreg_branch_inst),
        .i_nel_jump_branch_data     (fcl_jump_branch_data),
        .i_nel_newpc_valid           (nel_newpc_valid),
        .i_nel_newpc                 (nel_newpc),
        .i_nel_unallo_reg_valid     (nel_lastreg_valid),
        .i_nel_unallo_reg_data         (nel_lastreg),
        .o_prm_unallocate_valid     (prm_unallocate_valid),
        .o_prm_unallocate_phyreg     (prm_unallocate_phyreg),
        .i_wbc_pc_valid                 (wbc2fcl_done),
        .i_wbc_pc_data                 (wbc2fcl_pc),
        .i_wbc_branch_valid             (wbc2fcl_branch),
        .i_wbc_branch_data             ({wbc2fcl_branch_pc, wbc2fcl_branch}),
        .i_nel_block                 (nel_block)
    );

endmodule
