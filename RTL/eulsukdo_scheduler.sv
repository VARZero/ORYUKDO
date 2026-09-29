`timescale 1ns/1ps
module eulsukdo_scheduler #(
    // Instruction Set Parameters
    parameter int IS_INST_PC_BITWIDTH                   = 32,
    parameter int IS_INST_PC_STEP                       = 4,
    parameter int IS_INST_BITWIDTH                      = 32,
    parameter int IS_INST_REGS                          = 32,
    parameter int IS_INST_OPERANDS                      = 2,
    parameter int IS_INST_IMM                           = 32,

    // Execution Unit Parameters
    parameter int EX_INST_MICROOP_BITWIDTH              = 5,

    // EULSUKDO Structure Parameters
    parameter int STRUCT_DECODE_NEW_INST                = 2,
    parameter int STRUCT_INST_STATE_ENTRIES             = 128,
    parameter int STRUCT_PHYREGS                        = 64,
    parameter int STRUCT_EX_PATH                        = 3,
    parameter int STRUCT_RS_OUT_ENTRY[STRUCT_EX_PATH]   = {1, 3, 1},
    parameter int STRUCT_EX_CORES                       = 5,
    parameter int STRUCT_EX_OUT_RESULT[STRUCT_EX_CORES] = {1, 1, 1, 1, 1},
    parameter int STRUCT_EX_OUT_RESULT_SUM              = 5,
    parameter int STRUCT_EX_BRANCH                      = 1,
    parameter int STRUCT_PRM_ENTRY_UPDATE               = 5,
    parameter int STRUCT_PRM_ENTRY_BUFFER               = 4,
    parameter int STRUCT_UNALLOCATE_PHYREG              = 4,
    parameter int STRUCT_FLOW_WINDOWS                   = 8,
    parameter int STRUCT_FLOW_PC_MAX_RANGE              = 16,
    parameter bit ENABLE_MEMORY_ORDER                   = 1'b0,
    parameter bit ENABLE_STORE_COMMIT                   = 1'b0,
    parameter bit ENABLE_RECOVERY_TRACKING              = 1'b0,
    parameter bit ENABLE_EXTERNAL_PREDICTOR              = 1'b0,
    parameter int RECOVERY_AGE_WIDTH                    = 32,
    parameter int STRUCT_MEM_EX_PATH                    = STRUCT_EX_PATH-1,
    parameter int STRUCT_MEM_WBC_LANE                   = STRUCT_EX_OUT_RESULT_SUM-1,

    // Synthesis Create Local Parameters
    localparam int _BITWIDTH_IS_INST_REGS               = $clog2(IS_INST_REGS),
    localparam int _BITWIDTH_STRUCT_INST_STATE_ENTRIES  = $clog2(STRUCT_INST_STATE_ENTRIES),
    localparam int _BITWIDTH_STRUCT_PHYREGS             = $clog2(STRUCT_PHYREGS),
    localparam int _BITWIDTH_STRUCT_EX_PATH             = $clog2(STRUCT_EX_PATH),
    localparam int _BITWIDTH_STRUCT_FLOW_WINDOWS        = $clog2(STRUCT_FLOW_WINDOWS),
    localparam int _BITWIDTH_READY_PRM                  = _BITWIDTH_STRUCT_INST_STATE_ENTRIES+_BITWIDTH_STRUCT_PHYREGS,
    localparam int _BITWIDTH_FLOW_WINDOWS_PC            = _BITWIDTH_STRUCT_FLOW_WINDOWS
                                                         + IS_INST_PC_BITWIDTH,
    localparam int _BITWIDTH_INTERNAL_INST_WIDTH        = _BITWIDTH_STRUCT_FLOW_WINDOWS
                                                         + IS_INST_PC_BITWIDTH
                                                         + _BITWIDTH_STRUCT_EX_PATH
                                                         + EX_INST_MICROOP_BITWIDTH
                                                         + IS_INST_IMM
                                                         + _BITWIDTH_STRUCT_PHYREGS // rd
                                                         + (_BITWIDTH_STRUCT_PHYREGS * IS_INST_OPERANDS) // rs1..n
                                                         + IS_INST_OPERANDS, // Ready1..n
    localparam int _BITWIDTH_EX_INST_WIDTH              = _BITWIDTH_STRUCT_FLOW_WINDOWS
                                                         + IS_INST_PC_BITWIDTH
                                                         + _BITWIDTH_STRUCT_EX_PATH
                                                         + EX_INST_MICROOP_BITWIDTH
                                                         + IS_INST_IMM
                                                         + _BITWIDTH_STRUCT_PHYREGS // rd
                                                         + (_BITWIDTH_STRUCT_PHYREGS * IS_INST_OPERANDS), // rs1..n
    localparam int _BITWIDTH_EX_RESULT_WIDTH            = _BITWIDTH_STRUCT_FLOW_WINDOWS
                                                         + IS_INST_PC_BITWIDTH
                                                         + _BITWIDTH_STRUCT_PHYREGS, // rd
    localparam int _BITWIDTH_STRUCT_RETIRED_PHYREG_MSG  = _BITWIDTH_STRUCT_FLOW_WINDOWS
                                                         + IS_INST_PC_BITWIDTH
                                                         + _BITWIDTH_STRUCT_PHYREGS, // Retired Register
    localparam int _BITWIDTH_STRUCT_JUMP_BRANCH_INFO    = 1 // Jump Flag
                                                         + 1 // Jump Register Flag
                                                         + 1 // Branch Flag
                                                         + IS_INST_PC_BITWIDTH, // New Program Counter
    localparam int _BITWIDTH_STRUCT_EX_DONE_PC          = _BITWIDTH_STRUCT_FLOW_WINDOWS
                                                         + IS_INST_PC_BITWIDTH,
    localparam int _BITWIDTH_MEM_PAYLOAD                = 1 + IS_INST_PC_BITWIDTH
                                                         + IS_INST_PC_BITWIDTH
                                                         + IS_INST_PC_BITWIDTH/8
                                                         + _BITWIDTH_STRUCT_PHYREGS
                                                         + EX_INST_MICROOP_BITWIDTH
) (
    input  wire                                                                              clk,
    input  wire                                                                              reset_n,

    // PC Request
    output wire [STRUCT_DECODE_NEW_INST-1:0]                                                 o_im_req_pc_valid,
    input  wire [STRUCT_DECODE_NEW_INST-1:0]                                                 i_im_req_pc_get,
    output wire [(STRUCT_DECODE_NEW_INST * _BITWIDTH_FLOW_WINDOWS_PC)-1:0]                   o_im_req_pc,
    
    // Instruction Receive
    input  wire [STRUCT_DECODE_NEW_INST-1:0]                                                 i_im_recv_inst_valid,
    output wire [STRUCT_DECODE_NEW_INST-1:0]                                                 o_im_recv_inst_get,
    input  wire [(STRUCT_DECODE_NEW_INST * _BITWIDTH_FLOW_WINDOWS_PC)-1:0]                   i_im_recv_pc,
    input  wire [(STRUCT_DECODE_NEW_INST * IS_INST_BITWIDTH)-1:0]                            i_im_recv_inst,
    
    // Decoder Info Receive
    input  wire [STRUCT_DECODE_NEW_INST-1:0]                                                 i_nel_decode_exception,
    input  wire [STRUCT_DECODE_NEW_INST*5-1:0]                                               i_nel_decode_exception_cause,
    input  wire [(STRUCT_DECODE_NEW_INST *(_BITWIDTH_STRUCT_EX_PATH) )-1:0]                  i_nel_decode_expath,
    input  wire [(STRUCT_DECODE_NEW_INST *(EX_INST_MICROOP_BITWIDTH) )-1:0]                  i_nel_decode_microop,
    input  wire [(STRUCT_DECODE_NEW_INST *(_BITWIDTH_IS_INST_REGS) )-1:0]                    i_nel_decode_rd,
    input  wire [STRUCT_DECODE_NEW_INST-1:0]                                                 i_nel_decode_newreg,
    input  wire [((STRUCT_DECODE_NEW_INST*IS_INST_OPERANDS) *(_BITWIDTH_IS_INST_REGS) )-1:0] i_nel_decode_rs,
    input  wire [(STRUCT_DECODE_NEW_INST *(IS_INST_IMM) )-1:0]                               i_nel_decode_imm,
    input  wire [STRUCT_DECODE_NEW_INST-1:0]                                                 i_nel_decode_jump,
    input  wire [STRUCT_DECODE_NEW_INST-1:0]                                                 i_nel_decode_jump_reg,
    input  wire [STRUCT_DECODE_NEW_INST-1:0]                                                 i_nel_decode_branch,
    
    // EX Inst Push (RS Out)
    output wire [STRUCT_EX_CORES-1:0]                                                        o_rs_entry_valid,
    input  wire [STRUCT_EX_CORES-1:0]                                                        i_rs_entry_get,
    output wire [(STRUCT_EX_CORES *(_BITWIDTH_EX_INST_WIDTH) )-1:0]                          o_rs_entry_data,
    output wire [STRUCT_EX_CORES*RECOVERY_AGE_WIDTH-1:0]                                    o_rs_entry_age,

    // EX Result Receive (EX Out)
    input  wire [STRUCT_EX_OUT_RESULT_SUM-1:0]                                               i_wbc_result_valid,
    input  wire [(STRUCT_EX_OUT_RESULT_SUM *(_BITWIDTH_EX_RESULT_WIDTH) )-1:0]               i_wbc_result_data,
    input  wire [STRUCT_EX_OUT_RESULT_SUM*RECOVERY_AGE_WIDTH-1:0]                           i_wbc_result_age,
    output wire [STRUCT_EX_OUT_RESULT_SUM-1:0]                                              o_wbc_result_accept,
    input  wire [STRUCT_EX_BRANCH-1:0]                                                       i_wbc_result_branch_valid,
    input  wire [(STRUCT_EX_BRANCH * _BITWIDTH_STRUCT_JUMP_BRANCH_INFO)-1:0]                 i_wbc_result_branch_data,

    // Memory AGU result (external Memory EX), ordered request and completion.
    input  wire                                                                              i_mem_agu_valid,
    output wire                                                                              o_mem_agu_get,
    input  wire [_BITWIDTH_FLOW_WINDOWS_PC-1:0]                                             i_mem_agu_key,
    input  wire [RECOVERY_AGE_WIDTH-1:0]                                                     i_mem_agu_age,
    input  wire [_BITWIDTH_MEM_PAYLOAD-1:0]                                                  i_mem_agu_payload,
    output wire                                                                              o_mem_req_valid,
    input  wire                                                                              i_mem_req_get,
    output wire [_BITWIDTH_FLOW_WINDOWS_PC-1:0]                                             o_mem_req_key,
    output wire [_BITWIDTH_MEM_PAYLOAD-1:0]                                                  o_mem_req_payload,
    input  wire                                                                              i_store_commit_valid,
    input  wire [_BITWIDTH_FLOW_WINDOWS_PC-1:0]                                             i_store_commit_key,
    input  wire                                                                              i_mem_resp_valid,
    input  wire [IS_INST_PC_BITWIDTH-1:0]                                                    i_mem_resp_data,
    output wire                                                                              o_mem_resp_ready,
    output wire                                                                              o_mem_complete_valid,
    output wire [_BITWIDTH_FLOW_WINDOWS_PC-1:0]                                             o_mem_complete_key,
    output wire [_BITWIDTH_STRUCT_PHYREGS-1:0]                                              o_mem_complete_rd,
    output wire [IS_INST_PC_BITWIDTH-1:0]                                                    o_mem_complete_data,
    // Tagged branch resolution and trap entry are supplied by external EX/CSR.
    input  wire                                                                              i_recovery_resolve_valid,
    input  wire [_BITWIDTH_FLOW_WINDOWS_PC-1:0]                                             i_recovery_resolve_key,
    input  wire [RECOVERY_AGE_WIDTH-1:0]                                                     i_recovery_resolve_age,
    input  wire                                                                              i_recovery_taken,
    input  wire [IS_INST_PC_BITWIDTH-1:0]                                                    i_recovery_target,
    input  wire                                                                              i_recovery_predicted_taken,
    input  wire [IS_INST_PC_BITWIDTH-1:0]                                                    i_recovery_predicted_target,
    input  wire                                                                              i_recovery_fault_valid,
    input  wire [_BITWIDTH_FLOW_WINDOWS_PC-1:0]                                             i_recovery_fault_key,
    input  wire [RECOVERY_AGE_WIDTH-1:0]                                                     i_recovery_fault_age,
    input  wire [4:0]                                                                        i_recovery_fault_cause,
    input  wire                                                                              i_recovery_interrupt_pending,
    input  wire [IS_INST_PC_BITWIDTH-1:0]                                                    i_recovery_trap_vector,
    output wire                                                                              o_recovery_flush,
    output wire [_BITWIDTH_FLOW_WINDOWS_PC-1:0]                                             o_recovery_flush_key,
    output wire [RECOVERY_AGE_WIDTH-1:0]                                                     o_recovery_flush_age,
    output wire [IS_INST_PC_BITWIDTH-1:0]                                                    o_recovery_redirect_pc,
    output wire                                                                              o_recovery_trap_valid,
    output wire                                                                              o_recovery_trap_interrupt,
    output wire [4:0]                                                                        o_recovery_trap_cause,
    output wire [IS_INST_PC_BITWIDTH-1:0]                                                    o_recovery_trap_pc,
    output wire                                                                              o_predict_request_valid,
    output wire [_BITWIDTH_FLOW_WINDOWS_PC-1:0]                                             o_predict_request_key,
    input  wire                                                                              i_predict_valid,
    input  wire                                                                              i_predict_taken,
    input  wire [IS_INST_PC_BITWIDTH-1:0]                                                    i_predict_target,
    output wire                                                                              o_predict_decision_taken,
    output wire [IS_INST_PC_BITWIDTH-1:0]                                                    o_predict_decision_target,
    output wire                                                                              o_predict_update_valid,
    output wire [_BITWIDTH_FLOW_WINDOWS_PC-1:0]                                             o_predict_update_key,
    output wire                                                                              o_predict_update_taken,
    output wire [IS_INST_PC_BITWIDTH-1:0]                                                    o_predict_update_target
);

// START ===[ INTERNAL WIRE AREA ]=== START //
    // IM -> NEL : Instruction Receive
    wire [STRUCT_DECODE_NEW_INST-1:0]                                                         im_nel_recv_inst_valid;
    wire [STRUCT_DECODE_NEW_INST-1:0]                                                         im_nel_recv_inst_get;
    wire [(STRUCT_DECODE_NEW_INST *(_BITWIDTH_FLOW_WINDOWS_PC) )-1:0]                         im_nel_recv_pc;
    wire [STRUCT_DECODE_NEW_INST-1:0]                                                         fcl_im_recv_discard;

    // PRM -> NEL : Allocatable Physical Registers
    wire [STRUCT_DECODE_NEW_INST-1:0]                                                         prm_nel_phyreg_valid;
    wire [STRUCT_DECODE_NEW_INST-1:0]                                                         prm_nel_phyreg_get;
    wire [(STRUCT_DECODE_NEW_INST *(_BITWIDTH_STRUCT_PHYREGS) )-1:0]                          prm_nel_phyreg_data;

    // WBC -> NEL, PRM (Broadcast) : Done Physical Registers
    wire [STRUCT_EX_OUT_RESULT_SUM-1:0]                                                       wbc_broadcast_done_phyreg_valid;
    wire [(STRUCT_EX_OUT_RESULT_SUM *(_BITWIDTH_STRUCT_PHYREGS) )-1:0]                        wbc_broadcast_done_phyreg_data;

    // NEL -> IST : New Internal Instructions
    wire [STRUCT_DECODE_NEW_INST-1:0]                                                         nel_ist_new_inst_valid;
    wire [STRUCT_DECODE_NEW_INST-1:0]                                                         nel_ist_new_inst_get;
    wire [STRUCT_DECODE_NEW_INST-1:0]                                                         ist_nel_new_inst_get;
    wire [(STRUCT_DECODE_NEW_INST *(_BITWIDTH_INTERNAL_INST_WIDTH) )-1:0]                     nel_ist_new_inst_data;
    wire [STRUCT_DECODE_NEW_INST-1:0]                                                         nel_ist_new_inst_exception;
    wire [STRUCT_DECODE_NEW_INST*5-1:0]                                                       nel_ist_new_inst_exception_cause;
    wire [STRUCT_DECODE_NEW_INST-1:0]                                                         nel_ist_new_inst_control;
    wire [STRUCT_DECODE_NEW_INST-1:0]                                                         nel_ist_new_inst_predict_taken;
    wire [STRUCT_DECODE_NEW_INST*IS_INST_PC_BITWIDTH-1:0]                                    nel_ist_new_inst_predict_target;
    wire [STRUCT_DECODE_NEW_INST-1:0]                                                         nel_ist_new_inst_write;
    wire [STRUCT_DECODE_NEW_INST*_BITWIDTH_IS_INST_REGS-1:0]                                  nel_ist_new_inst_arch;
    wire [STRUCT_DECODE_NEW_INST*_BITWIDTH_STRUCT_PHYREGS-1:0]                                nel_ist_new_inst_phyreg;
    wire [STRUCT_DECODE_NEW_INST-1:0]                                                         nel_ist_execution_valid;
    wire                                                                                       lsq_nel_ready;
    wire                                                                                       lsq_complete_valid;
    wire [_BITWIDTH_FLOW_WINDOWS_PC-1:0]                                                      lsq_complete_key;
    wire [_BITWIDTH_STRUCT_PHYREGS-1:0]                                                       lsq_complete_rd;
    wire                                                                                       lsq_complete_store;
    wire                                                                                       recovery_ready;
    wire                                                                                       recovery_store_commit_valid;
    wire [_BITWIDTH_FLOW_WINDOWS_PC-1:0]                                                      recovery_store_commit_key;
    wire [STRUCT_DECODE_NEW_INST*RECOVERY_AGE_WIDTH-1:0]                                     recovery_nel_age;
    wire [STRUCT_DECODE_NEW_INST*_BITWIDTH_FLOW_WINDOWS_PC-1:0]                              recovery_nel_keys;
    logic [RECOVERY_AGE_WIDTH-1:0]                                                            recovery_next_age;
    wire [STRUCT_DECODE_NEW_INST-1:0]                                                         recovery_admit;
    wire [STRUCT_DECODE_NEW_INST-1:0]                                                         recovery_memory_admit;
    wire [STRUCT_EX_OUT_RESULT_SUM*_BITWIDTH_FLOW_WINDOWS_PC-1:0]                             recovery_done_keys;
    wire [STRUCT_EX_OUT_RESULT_SUM*RECOVERY_AGE_WIDTH-1:0]                                    recovery_done_age;
    wire [STRUCT_EX_OUT_RESULT_SUM-1:0]                                                        recovery_done_live;
    wire [STRUCT_EX_CORES*_BITWIDTH_FLOW_WINDOWS_PC-1:0]                                      recovery_issue_keys;
    wire [(STRUCT_EX_CORES+1)*RECOVERY_AGE_WIDTH-1:0]                                          recovery_issue_ages;
    wire                                                                                       recovery_retire_write;
    wire                                                                                       recovery_retire_valid;
    wire [_BITWIDTH_FLOW_WINDOWS_PC-1:0]                                                      recovery_retire_key;
    wire [_BITWIDTH_IS_INST_REGS-1:0]                                                         recovery_retire_arch;
    wire [_BITWIDTH_STRUCT_PHYREGS-1:0]                                                       recovery_retire_phyreg;
    wire                                                                                       recovery_retire_old_valid;
    wire [_BITWIDTH_STRUCT_PHYREGS-1:0]                                                       recovery_retire_old_phyreg;
    wire [STRUCT_PHYREGS-1:0]                                                                 recovery_reserved_phyreg;
    wire                                                                                       recovery_resolve_accept;

    // NEL -> FCL : Retired Physical Registers
    wire [STRUCT_DECODE_NEW_INST-1:0]                                                         nel_fcl_retired_phyreg_valid;
    wire [(STRUCT_DECODE_NEW_INST *(_BITWIDTH_STRUCT_RETIRED_PHYREG_MSG) )-1:0]               nel_fcl_retired_phyreg_data;
    
    // NEL -> FCL : Jump/Branch Information
    wire                                                                                      nel_fcl_jumpbranch_valid;
    wire [_BITWIDTH_STRUCT_JUMP_BRANCH_INFO-1:0]                                              nel_fcl_jumpbranch_data;
    wire [_BITWIDTH_FLOW_WINDOWS_PC-1:0]                                                      nel_fcl_control_key;
    wire                                                                                       static_predict_taken;
    wire [IS_INST_PC_BITWIDTH-1:0]                                                            static_predict_target;

    // PRM -> IST : Ready Phyreg/ISTmap pair
    wire [STRUCT_PRM_ENTRY_UPDATE-1:0]                                                        prm_ist_ready_phyreg_valid;
    wire [(STRUCT_PRM_ENTRY_UPDATE *(_BITWIDTH_READY_PRM) )-1:0]                              prm_ist_ready_phyreg_data;

    // IST -> RS : Executable (All phyreg in instruction are ready) Internal Instructions
    wire [(STRUCT_DECODE_NEW_INST+STRUCT_PRM_ENTRY_UPDATE)-1:0]                               ist_rs_ready_inst_valid;
    wire [((STRUCT_DECODE_NEW_INST+STRUCT_PRM_ENTRY_UPDATE) *(_BITWIDTH_EX_INST_WIDTH) )-1:0] ist_rs_ready_inst_data;
    wire [(STRUCT_DECODE_NEW_INST+STRUCT_PRM_ENTRY_UPDATE)-1:0]                               ist_rs_ready_inst_get;

    // IST -> PRM : Wait Phyreg/ISTmap pair
    wire [(STRUCT_DECODE_NEW_INST*IS_INST_OPERANDS)-1:0]                                     ist_prm_wait_phyreg_valid;
    wire [(STRUCT_DECODE_NEW_INST*IS_INST_OPERANDS*(_BITWIDTH_READY_PRM))-1:0]                ist_prm_wait_phyreg_data;

    // RS -> EX : Wait EX Instructions
    wire [STRUCT_EX_CORES-1:0]                                                                rs_ex_wait_inst_valid;
    wire [STRUCT_EX_CORES-1:0]                                                                rs_ex_wait_inst_get;
    wire [(STRUCT_EX_CORES *(_BITWIDTH_EX_INST_WIDTH) )-1:0]                                  rs_ex_wait_inst_data;

    // EX -> WBC : Done EX Branch Result
    wire [STRUCT_EX_BRANCH-1:0]                                                               ex_wbc_result_branch_valid;
    wire [(STRUCT_EX_BRANCH *(_BITWIDTH_STRUCT_JUMP_BRANCH_INFO) )-1:0]                       ex_wbc_result_branch_data;
    
    // EX -> WBC : Done EX Phyreg Result
    wire [STRUCT_EX_OUT_RESULT_SUM-1:0]                                                       ex_wbc_result_valid;
    wire [(STRUCT_EX_OUT_RESULT_SUM *(_BITWIDTH_EX_RESULT_WIDTH) )-1:0]                       ex_wbc_result_data;
    
    // WBC -> FCL : Branch Result
    wire [STRUCT_EX_BRANCH-1:0]                                                               wbc_fcl_branch_valid;
    wire [(STRUCT_EX_BRANCH *(_BITWIDTH_STRUCT_JUMP_BRANCH_INFO) )-1:0]                       wbc_fcl_branch_data;
    
    // WBC -> FCL : Done PC
    wire [STRUCT_EX_OUT_RESULT_SUM-1:0]                                                       wbc_fcl_done_pc_valid;
    wire [(STRUCT_EX_OUT_RESULT_SUM *(_BITWIDTH_STRUCT_EX_DONE_PC) )-1:0]                     wbc_fcl_done_pc_data;

    // FCL -> IM : New PC Request
    wire [STRUCT_DECODE_NEW_INST-1:0]                                                         fcl_im_req_pc_valid;
    wire [STRUCT_DECODE_NEW_INST-1:0]                                                         fcl_im_req_pc_get;
    wire [(STRUCT_DECODE_NEW_INST *(_BITWIDTH_FLOW_WINDOWS_PC) )-1:0]                         fcl_im_req_pc;

    // FCL -> PRM : Unallocate Retired Registers
    wire [STRUCT_UNALLOCATE_PHYREG-1:0]                                                       fcl_prm_unallocate_phyreg_valid;
    wire [(STRUCT_UNALLOCATE_PHYREG *(_BITWIDTH_STRUCT_PHYREGS) )-1:0]                        fcl_prm_unallocate_phyreg_data;
    wire [STRUCT_UNALLOCATE_PHYREG-1:0]                                                       prm_unallocate_phyreg_valid;
    wire [(STRUCT_UNALLOCATE_PHYREG *(_BITWIDTH_STRUCT_PHYREGS) )-1:0]                        prm_unallocate_phyreg_data;

    // DECODER -> NEL : ISA Infomation
    wire [STRUCT_DECODE_NEW_INST-1:0]                                                         dec_nel_decode_exception;
    wire [STRUCT_DECODE_NEW_INST*5-1:0]                                                       dec_nel_decode_exception_cause;
    wire [(STRUCT_DECODE_NEW_INST *(_BITWIDTH_STRUCT_EX_PATH) )-1:0]                          dec_nel_decode_expath;
    wire [(STRUCT_DECODE_NEW_INST *(EX_INST_MICROOP_BITWIDTH) )-1:0]                          dec_nel_decode_microop;
    wire [(STRUCT_DECODE_NEW_INST *(_BITWIDTH_IS_INST_REGS) )-1:0]                            dec_nel_decode_rd;
    wire [STRUCT_DECODE_NEW_INST-1:0]                                                         dec_nel_decode_newreg;
    wire [((STRUCT_DECODE_NEW_INST*IS_INST_OPERANDS) *(_BITWIDTH_IS_INST_REGS) )-1:0]         dec_nel_decode_rs;
    wire [(STRUCT_DECODE_NEW_INST *(IS_INST_IMM) )-1:0]                                       dec_nel_decode_imm;
    wire [STRUCT_DECODE_NEW_INST-1:0]                                                         dec_nel_decode_jump;
    wire [STRUCT_DECODE_NEW_INST-1:0]                                                         dec_nel_decode_jump_reg;
    wire [STRUCT_DECODE_NEW_INST-1:0]                                                         dec_nel_decode_branch;

// END   ===[ INTERNAL WIRE AREA ]===   END //

// START ===[ INSTANCE AREA ]=== START //
    new_entry_logic #(
        .ENABLE_PRECISE_EXCEPTION(ENABLE_RECOVERY_TRACKING),
        .ENABLE_RECOVERY_RENAME(ENABLE_RECOVERY_TRACKING),
        .IS_INST_PC_BITWIDTH(IS_INST_PC_BITWIDTH),
        .IS_INST_PC_STEP(IS_INST_PC_STEP),
        .IS_INST_BITWIDTH(IS_INST_BITWIDTH),
        .IS_INST_REGS(IS_INST_REGS),
        .IS_INST_OPERANDS(IS_INST_OPERANDS),
        .IS_INST_IMM(IS_INST_IMM),
        .EX_INST_MICROOP_BITWIDTH(EX_INST_MICROOP_BITWIDTH),
        .STRUCT_DECODE_NEW_INST(STRUCT_DECODE_NEW_INST),
        .STRUCT_INST_STATE_ENTRIES(STRUCT_INST_STATE_ENTRIES),
        .STRUCT_PHYREGS(STRUCT_PHYREGS),
        .STRUCT_EX_PATH(STRUCT_EX_PATH),
        .STRUCT_RS_OUT_ENTRY(STRUCT_RS_OUT_ENTRY),
        .STRUCT_EX_CORES(STRUCT_EX_CORES),
        .STRUCT_EX_OUT_RESULT(STRUCT_EX_OUT_RESULT),
        .STRUCT_EX_OUT_RESULT_SUM(STRUCT_EX_OUT_RESULT_SUM),
        .STRUCT_EX_BRANCH(STRUCT_EX_BRANCH),
        .STRUCT_PRM_ENTRY_UPDATE(STRUCT_PRM_ENTRY_UPDATE),
        .STRUCT_PRM_ENTRY_BUFFER(STRUCT_PRM_ENTRY_BUFFER),
        .STRUCT_UNALLOCATE_PHYREG(STRUCT_UNALLOCATE_PHYREG),
        .STRUCT_FLOW_WINDOWS(STRUCT_FLOW_WINDOWS),
        .STRUCT_FLOW_PC_MAX_RANGE(STRUCT_FLOW_PC_MAX_RANGE)
    ) U_NEW_ENTRY_LOGIC (
        .clk                            (clk),
        .reset_n                        (reset_n),
        .i_recover                      (o_recovery_flush),
        .i_predict_taken                (o_predict_decision_taken),
        .i_predict_target               (o_predict_decision_target),
        .i_retire_write                 (recovery_retire_write),
        .i_retire_arch                  (recovery_retire_arch),
        .i_retire_phyreg                (recovery_retire_phyreg),
        .o_retire_old_valid             (recovery_retire_old_valid),
        .o_retire_old_phyreg            (recovery_retire_old_phyreg),
        .o_reserved_phyreg              (recovery_reserved_phyreg),

        // Instruction Input (IM)
        .i_im_recv_inst_valid           (im_nel_recv_inst_valid),
        .o_im_recv_inst_get             (im_nel_recv_inst_get),
        .i_im_recv_pc                   (im_nel_recv_pc),

        // Allocate Physical Registers Input (PRM)
        .i_prm_phyreg_valid             (prm_nel_phyreg_valid),
        .o_prm_phyreg_get               (prm_nel_phyreg_get),
        .i_prm_phyreg_data              (prm_nel_phyreg_data),

        // Done Physical Registers Input (WBC)
        .i_wbc_done_phyreg_valid        (wbc_broadcast_done_phyreg_valid),
        .i_wbc_done_phyreg_data         (wbc_broadcast_done_phyreg_data),

        // Decoder Input (Decoder)
        .i_dec_decode_exception         (dec_nel_decode_exception),
        .i_dec_decode_exception_cause   (dec_nel_decode_exception_cause),
        .i_dec_decode_expath            (dec_nel_decode_expath),
        .i_dec_decode_microop           (dec_nel_decode_microop),
        .i_dec_decode_rd                (dec_nel_decode_rd),
        .i_dec_decode_newreg            (dec_nel_decode_newreg),
        .i_dec_decode_rs                (dec_nel_decode_rs),
        .i_dec_decode_imm               (dec_nel_decode_imm),
        .i_dec_decode_jump              (dec_nel_decode_jump),
        .i_dec_decode_jump_reg          (dec_nel_decode_jump_reg),
        .i_dec_decode_branch            (dec_nel_decode_branch),

        // Create Internal Instruction Output (IST)
        .o_ist_new_inst_valid           (nel_ist_new_inst_valid),
        .i_ist_new_inst_get             (nel_ist_new_inst_get),
        .o_ist_new_inst_data            (nel_ist_new_inst_data),
        .o_ist_new_inst_exception       (nel_ist_new_inst_exception),
        .o_ist_new_inst_exception_cause (nel_ist_new_inst_exception_cause),
        .o_ist_new_inst_control         (nel_ist_new_inst_control),
        .o_ist_new_inst_predict_taken   (nel_ist_new_inst_predict_taken),
        .o_ist_new_inst_predict_target  (nel_ist_new_inst_predict_target),
        .o_ist_new_inst_write           (nel_ist_new_inst_write),
        .o_ist_new_inst_arch            (nel_ist_new_inst_arch),
        .o_ist_new_inst_phyreg          (nel_ist_new_inst_phyreg),

        // Retired Physical Registers Output (FCL)
        .o_fcl_retired_phyreg_valid     (nel_fcl_retired_phyreg_valid),
        .o_fcl_retired_phyreg_data      (nel_fcl_retired_phyreg_data),

        // Jump/Branch Information Output (FCL)
        .o_fcl_jumpbranch_valid         (nel_fcl_jumpbranch_valid),
        .o_fcl_control_key              (nel_fcl_control_key),
        .o_fcl_jumpbranch_data          (nel_fcl_jumpbranch_data)
    );

    instruction_state_table #(
        .IS_INST_PC_BITWIDTH(IS_INST_PC_BITWIDTH),
        .IS_INST_PC_STEP(IS_INST_PC_STEP),
        .IS_INST_BITWIDTH(IS_INST_BITWIDTH),
        .IS_INST_REGS(IS_INST_REGS),
        .IS_INST_OPERANDS(IS_INST_OPERANDS),
        .IS_INST_IMM(IS_INST_IMM),
        .EX_INST_MICROOP_BITWIDTH(EX_INST_MICROOP_BITWIDTH),
        .STRUCT_DECODE_NEW_INST(STRUCT_DECODE_NEW_INST),
        .STRUCT_INST_STATE_ENTRIES(STRUCT_INST_STATE_ENTRIES),
        .STRUCT_PHYREGS(STRUCT_PHYREGS),
        .STRUCT_EX_PATH(STRUCT_EX_PATH),
        .STRUCT_RS_OUT_ENTRY(STRUCT_RS_OUT_ENTRY),
        .STRUCT_EX_CORES(STRUCT_EX_CORES),
        .STRUCT_EX_OUT_RESULT(STRUCT_EX_OUT_RESULT),
        .STRUCT_EX_OUT_RESULT_SUM(STRUCT_EX_OUT_RESULT_SUM),
        .STRUCT_EX_BRANCH(STRUCT_EX_BRANCH),
        .STRUCT_PRM_ENTRY_UPDATE(STRUCT_PRM_ENTRY_UPDATE),
        .STRUCT_PRM_ENTRY_BUFFER(STRUCT_PRM_ENTRY_BUFFER),
        .STRUCT_UNALLOCATE_PHYREG(STRUCT_UNALLOCATE_PHYREG),
        .STRUCT_FLOW_WINDOWS(STRUCT_FLOW_WINDOWS),
        .STRUCT_FLOW_PC_MAX_RANGE(STRUCT_FLOW_PC_MAX_RANGE)
    ) U_INSTRUCTION_STATE_TABLE (
        .clk                            (clk),
        .reset_n                        (reset_n),
        .i_recover                      (ENABLE_RECOVERY_TRACKING && o_recovery_flush),

        // New Internal Instruction Input (NEL)
        .i_nel_new_inst_valid           (nel_ist_execution_valid),
        .o_nel_new_inst_get             (ist_nel_new_inst_get),
        .i_nel_new_inst_data            (nel_ist_new_inst_data),

        // Ready Physical Registers Input (PRM)
        .i_prm_ready_phyreg_valid       (prm_ist_ready_phyreg_valid), 
        .i_prm_ready_phyreg_data        (prm_ist_ready_phyreg_data), 
        
        // Executable (All phyreg in instruction are ready) Internal Instruction Output (RS)
        .o_rs_ready_inst_valid          (ist_rs_ready_inst_valid),
        .o_rs_ready_inst_data           (ist_rs_ready_inst_data),
        .i_rs_ready_inst_get             (ist_rs_ready_inst_get),

        // Wait Physical Registers Output (PRM)
        .o_prm_wait_phyreg_valid        (ist_prm_wait_phyreg_valid), 
        .o_prm_wait_phyreg_data         (ist_prm_wait_phyreg_data)
    );

    ready_station #(
        .IS_INST_PC_BITWIDTH(IS_INST_PC_BITWIDTH),
        .IS_INST_PC_STEP(IS_INST_PC_STEP),
        .IS_INST_BITWIDTH(IS_INST_BITWIDTH),
        .IS_INST_REGS(IS_INST_REGS),
        .IS_INST_OPERANDS(IS_INST_OPERANDS),
        .IS_INST_IMM(IS_INST_IMM),
        .EX_INST_MICROOP_BITWIDTH(EX_INST_MICROOP_BITWIDTH),
        .STRUCT_DECODE_NEW_INST(STRUCT_DECODE_NEW_INST),
        .STRUCT_INST_STATE_ENTRIES(STRUCT_INST_STATE_ENTRIES),
        .STRUCT_PHYREGS(STRUCT_PHYREGS),
        .STRUCT_EX_PATH(STRUCT_EX_PATH),
        .STRUCT_RS_OUT_ENTRY(STRUCT_RS_OUT_ENTRY),
        .STRUCT_EX_CORES(STRUCT_EX_CORES),
        .STRUCT_EX_OUT_RESULT(STRUCT_EX_OUT_RESULT),
        .STRUCT_EX_OUT_RESULT_SUM(STRUCT_EX_OUT_RESULT_SUM),
        .STRUCT_EX_BRANCH(STRUCT_EX_BRANCH),
        .STRUCT_PRM_ENTRY_UPDATE(STRUCT_PRM_ENTRY_UPDATE),
        .STRUCT_PRM_ENTRY_BUFFER(STRUCT_PRM_ENTRY_BUFFER),
        .STRUCT_UNALLOCATE_PHYREG(STRUCT_UNALLOCATE_PHYREG),
        .STRUCT_FLOW_WINDOWS(STRUCT_FLOW_WINDOWS),
        .STRUCT_FLOW_PC_MAX_RANGE(STRUCT_FLOW_PC_MAX_RANGE)
    ) U_READY_STATION (
        .clk                            (clk),
        .reset_n                        (reset_n),
        .i_recover                      (ENABLE_RECOVERY_TRACKING && o_recovery_flush),

        // Executable (All phyreg in instruction are ready) Internal Instruction Input (IST)
        .i_ist_ready_inst_valid         (ist_rs_ready_inst_valid),
        .i_ist_ready_inst_data          (ist_rs_ready_inst_data),
        .o_ist_ready_inst_get           (ist_rs_ready_inst_get),

        // Wait EX Instruction Output (EX)
        .o_ex_wait_inst_valid           (rs_ex_wait_inst_valid),
        .i_ex_wait_inst_get             (rs_ex_wait_inst_get),
        .o_ex_wait_inst_data            (rs_ex_wait_inst_data)
    );

    write_back_concatenation #(
        .IS_INST_PC_BITWIDTH(IS_INST_PC_BITWIDTH),
        .IS_INST_PC_STEP(IS_INST_PC_STEP),
        .IS_INST_BITWIDTH(IS_INST_BITWIDTH),
        .IS_INST_REGS(IS_INST_REGS),
        .IS_INST_OPERANDS(IS_INST_OPERANDS),
        .IS_INST_IMM(IS_INST_IMM),
        .EX_INST_MICROOP_BITWIDTH(EX_INST_MICROOP_BITWIDTH),
        .STRUCT_DECODE_NEW_INST(STRUCT_DECODE_NEW_INST),
        .STRUCT_INST_STATE_ENTRIES(STRUCT_INST_STATE_ENTRIES),
        .STRUCT_PHYREGS(STRUCT_PHYREGS),
        .STRUCT_EX_PATH(STRUCT_EX_PATH),
        .STRUCT_RS_OUT_ENTRY(STRUCT_RS_OUT_ENTRY),
        .STRUCT_EX_CORES(STRUCT_EX_CORES),
        .STRUCT_EX_OUT_RESULT(STRUCT_EX_OUT_RESULT),
        .STRUCT_EX_OUT_RESULT_SUM(STRUCT_EX_OUT_RESULT_SUM),
        .STRUCT_EX_BRANCH(STRUCT_EX_BRANCH),
        .STRUCT_PRM_ENTRY_UPDATE(STRUCT_PRM_ENTRY_UPDATE),
        .STRUCT_PRM_ENTRY_BUFFER(STRUCT_PRM_ENTRY_BUFFER),
        .STRUCT_UNALLOCATE_PHYREG(STRUCT_UNALLOCATE_PHYREG),
        .STRUCT_FLOW_WINDOWS(STRUCT_FLOW_WINDOWS),
        .STRUCT_FLOW_PC_MAX_RANGE(STRUCT_FLOW_PC_MAX_RANGE)
    ) U_WRITE_BACK_CONCATENATION (
        // Result branch EX Input (EX)
        .i_ex_result_branch_valid       (ex_wbc_result_branch_valid),
        .i_ex_result_branch_data        (ex_wbc_result_branch_data),

        // Result EX Input (EX)
        .i_ex_result_valid              (ex_wbc_result_valid),
        .i_ex_result_data               (ex_wbc_result_data),

        // Branch Result Output (FCL)
        .o_fcl_branch_valid             (wbc_fcl_branch_valid),
        .o_fcl_branch_data              (wbc_fcl_branch_data),

        // Done PC Output (FCL)
        .o_fcl_done_pc_valid            (wbc_fcl_done_pc_valid),
        .o_fcl_done_pc_data             (wbc_fcl_done_pc_data),

        // Broadcast Done phyreg Output (NEL, PRM)
        .o_broadcast_done_phyreg_valid  (wbc_broadcast_done_phyreg_valid),
        .o_broadcast_done_phyreg_data   (wbc_broadcast_done_phyreg_data)
    );

    flow_control_logic #(
        .ENABLE_RECOVERY_PREDICTION(ENABLE_RECOVERY_TRACKING),
        .IS_INST_PC_BITWIDTH(IS_INST_PC_BITWIDTH),
        .IS_INST_PC_STEP(IS_INST_PC_STEP),
        .IS_INST_BITWIDTH(IS_INST_BITWIDTH),
        .IS_INST_REGS(IS_INST_REGS),
        .IS_INST_OPERANDS(IS_INST_OPERANDS),
        .IS_INST_IMM(IS_INST_IMM),
        .EX_INST_MICROOP_BITWIDTH(EX_INST_MICROOP_BITWIDTH),
        .STRUCT_DECODE_NEW_INST(STRUCT_DECODE_NEW_INST),
        .STRUCT_INST_STATE_ENTRIES(STRUCT_INST_STATE_ENTRIES),
        .STRUCT_PHYREGS(STRUCT_PHYREGS),
        .STRUCT_EX_PATH(STRUCT_EX_PATH),
        .STRUCT_RS_OUT_ENTRY(STRUCT_RS_OUT_ENTRY),
        .STRUCT_EX_CORES(STRUCT_EX_CORES),
        .STRUCT_EX_OUT_RESULT(STRUCT_EX_OUT_RESULT),
        .STRUCT_EX_OUT_RESULT_SUM(STRUCT_EX_OUT_RESULT_SUM),
        .STRUCT_EX_BRANCH(STRUCT_EX_BRANCH),
        .STRUCT_PRM_ENTRY_UPDATE(STRUCT_PRM_ENTRY_UPDATE),
        .STRUCT_PRM_ENTRY_BUFFER(STRUCT_PRM_ENTRY_BUFFER),
        .STRUCT_UNALLOCATE_PHYREG(STRUCT_UNALLOCATE_PHYREG),
        .STRUCT_FLOW_WINDOWS(STRUCT_FLOW_WINDOWS),
        .STRUCT_FLOW_PC_MAX_RANGE(STRUCT_FLOW_PC_MAX_RANGE)
    ) U_FLOW_CONTROL_LOGIC (
        .clk                            (clk),
        .reset_n                        (reset_n),
        
        // Done PC Input (WBC)
        .i_wbc_done_pc_valid            (wbc_fcl_done_pc_valid),
        .i_wbc_done_pc_data             (wbc_fcl_done_pc_data),
        .i_wbc_branch_valid             (ENABLE_RECOVERY_TRACKING ? '0 : wbc_fcl_branch_valid),
        .i_wbc_branch_data              (wbc_fcl_branch_data),
        
        // Jump/Branch Information Input (NEL)
        .i_nel_jumpbranch_valid         (nel_fcl_jumpbranch_valid),
        .i_nel_jumpbranch_data          (nel_fcl_jumpbranch_data),
        .i_nel_control_key              (nel_fcl_control_key),
        .i_predict_taken                (o_predict_decision_taken),
        .i_predict_target               (o_predict_decision_target),
        .i_recover_valid                (o_recovery_flush),
        .i_recover_pc                   (o_recovery_redirect_pc),
        .i_retire_valid                 (recovery_retire_valid),
        .i_retire_key                   (recovery_retire_key),

        // Retired Physical Registers Input (NEL)
        .i_nel_retired_phyreg_valid     (nel_fcl_retired_phyreg_valid),
        .i_nel_retired_phyreg_data      (nel_fcl_retired_phyreg_data),
        .i_im_recv_inst_valid           (i_im_recv_inst_valid),
        .i_im_recv_inst_get             (o_im_recv_inst_get),
        .i_im_recv_pc                   (i_im_recv_pc),
        .o_im_recv_discard              (fcl_im_recv_discard),

        // Request New Instruction Output (IM)
        .o_im_req_pc_valid              (fcl_im_req_pc_valid),
        .i_im_req_pc_get                (fcl_im_req_pc_get),
        .o_im_req_pc                    (fcl_im_req_pc),

        // Unallocate Retired Registers Output (PRM)
        .o_prm_unallocate_phyreg_valid  (fcl_prm_unallocate_phyreg_valid),
        .o_prm_unallocate_phyreg_data   (fcl_prm_unallocate_phyreg_data)
    );

    physical_register_mapper #(
        .ENABLE_RECOVERY_ALLOCATOR(ENABLE_RECOVERY_TRACKING),
        .IS_INST_PC_BITWIDTH(IS_INST_PC_BITWIDTH),
        .IS_INST_PC_STEP(IS_INST_PC_STEP),
        .IS_INST_BITWIDTH(IS_INST_BITWIDTH),
        .IS_INST_REGS(IS_INST_REGS),
        .IS_INST_OPERANDS(IS_INST_OPERANDS),
        .IS_INST_IMM(IS_INST_IMM),
        .EX_INST_MICROOP_BITWIDTH(EX_INST_MICROOP_BITWIDTH),
        .STRUCT_DECODE_NEW_INST(STRUCT_DECODE_NEW_INST),
        .STRUCT_INST_STATE_ENTRIES(STRUCT_INST_STATE_ENTRIES),
        .STRUCT_PHYREGS(STRUCT_PHYREGS),
        .STRUCT_EX_PATH(STRUCT_EX_PATH),
        .STRUCT_RS_OUT_ENTRY(STRUCT_RS_OUT_ENTRY),
        .STRUCT_EX_CORES(STRUCT_EX_CORES),
        .STRUCT_EX_OUT_RESULT(STRUCT_EX_OUT_RESULT),
        .STRUCT_EX_OUT_RESULT_SUM(STRUCT_EX_OUT_RESULT_SUM),
        .STRUCT_EX_BRANCH(STRUCT_EX_BRANCH),
        .STRUCT_PRM_ENTRY_UPDATE(STRUCT_PRM_ENTRY_UPDATE),
        .STRUCT_PRM_ENTRY_BUFFER(STRUCT_PRM_ENTRY_BUFFER),
        .STRUCT_UNALLOCATE_PHYREG(STRUCT_UNALLOCATE_PHYREG),
        .STRUCT_FLOW_WINDOWS(STRUCT_FLOW_WINDOWS),
        .STRUCT_FLOW_PC_MAX_RANGE(STRUCT_FLOW_PC_MAX_RANGE)
    ) U_PHYSICAL_REGISTER_MAPPER (
        .clk                            (clk),
        .reset_n                        (reset_n),
        .i_recover                      (o_recovery_flush),
        .i_reserved_phyreg              (recovery_reserved_phyreg),

        // Wait Physical Registers Input (IST)
        .i_ist_wait_phyreg_valid        (ist_prm_wait_phyreg_valid), 
        .i_ist_wait_phyreg_data         (ist_prm_wait_phyreg_data),
        
        // Broadcast Done phyreg Input (WBC)
        .i_wbc_done_phyreg_valid        (wbc_broadcast_done_phyreg_valid),
        .i_wbc_done_phyreg_data         (wbc_broadcast_done_phyreg_data),

        // Unallocate Retired Registers Input (FCL)
        .i_fcl_unallocate_phyreg_valid  (prm_unallocate_phyreg_valid),
        .i_fcl_unallocate_phyreg_data   (prm_unallocate_phyreg_data),

        // Allocate Physical Registers Output (NEL)
        .o_nel_phyreg_valid             (prm_nel_phyreg_valid),
        .i_nel_phyreg_get               (prm_nel_phyreg_get),
        .o_nel_phyreg_data              (prm_nel_phyreg_data),

        // Ready Physical Registers Output (IST)
        .o_ist_ready_phyreg_valid       (prm_ist_ready_phyreg_valid), 
        .o_ist_ready_phyreg_data        (prm_ist_ready_phyreg_data)
    );

    assign nel_ist_new_inst_get = ist_nel_new_inst_get &
                                   {STRUCT_DECODE_NEW_INST{lsq_nel_ready && recovery_ready}};

    assign recovery_admit = nel_ist_new_inst_valid & nel_ist_new_inst_get;
    for (genvar mem_lane = 0; mem_lane < STRUCT_DECODE_NEW_INST; mem_lane++) begin : GEN_RECOVERY_MEMORY
        assign recovery_memory_admit[mem_lane] = ENABLE_MEMORY_ORDER &&
            nel_ist_new_inst_data[mem_lane*_BITWIDTH_INTERNAL_INST_WIDTH +
                                  _BITWIDTH_FLOW_WINDOWS_PC +: _BITWIDTH_STRUCT_EX_PATH] ==
            _BITWIDTH_STRUCT_EX_PATH'(STRUCT_MEM_EX_PATH);
    end
    assign nel_ist_execution_valid = nel_ist_new_inst_valid &
        ~(nel_ist_new_inst_exception & {STRUCT_DECODE_NEW_INST{ENABLE_RECOVERY_TRACKING}});
    for (genvar age_lane = 0; age_lane < STRUCT_DECODE_NEW_INST; age_lane++) begin : GEN_RECOVERY_AGE
        wire [RECOVERY_AGE_WIDTH-1:0] preceding = RECOVERY_AGE_WIDTH'($countones(recovery_admit &
            ((STRUCT_DECODE_NEW_INST'(1) << age_lane)-1'b1)));
        assign recovery_nel_age[age_lane*RECOVERY_AGE_WIDTH +: RECOVERY_AGE_WIDTH] =
            recovery_next_age + preceding;
        assign recovery_nel_keys[age_lane*_BITWIDTH_FLOW_WINDOWS_PC +: _BITWIDTH_FLOW_WINDOWS_PC] =
            nel_ist_new_inst_data[age_lane*_BITWIDTH_INTERNAL_INST_WIDTH +: _BITWIDTH_FLOW_WINDOWS_PC];
    end
    for (genvar issue_lane = 0; issue_lane < STRUCT_EX_CORES; issue_lane++) begin : GEN_RECOVERY_ISSUE
        assign recovery_issue_keys[issue_lane*_BITWIDTH_FLOW_WINDOWS_PC +: _BITWIDTH_FLOW_WINDOWS_PC] =
            rs_ex_wait_inst_data[issue_lane*_BITWIDTH_EX_INST_WIDTH +: _BITWIDTH_FLOW_WINDOWS_PC];
    end
    assign o_rs_entry_age = recovery_issue_ages[0 +: STRUCT_EX_CORES*RECOVERY_AGE_WIDTH];
    assign o_wbc_result_accept = ENABLE_RECOVERY_TRACKING ?
        (recovery_done_live & {STRUCT_EX_OUT_RESULT_SUM{!o_recovery_flush}}) : '1;
    // Flow completion may precede architectural retirement. In recovery mode,
    // return the overwritten committed mapping only when its writer retires.
    assign prm_unallocate_phyreg_valid = ENABLE_RECOVERY_TRACKING ?
        {{(STRUCT_UNALLOCATE_PHYREG-1){1'b0}}, recovery_retire_old_valid} :
        fcl_prm_unallocate_phyreg_valid;
    assign prm_unallocate_phyreg_data = ENABLE_RECOVERY_TRACKING ?
        {{((STRUCT_UNALLOCATE_PHYREG-1)*_BITWIDTH_STRUCT_PHYREGS){1'b0}},
         recovery_retire_old_phyreg} : fcl_prm_unallocate_phyreg_data;
    for (genvar result_lane = 0; result_lane < STRUCT_EX_OUT_RESULT_SUM; result_lane++) begin : GEN_RECOVERY_RESULT_AGE
        if (ENABLE_MEMORY_ORDER && result_lane == STRUCT_MEM_WBC_LANE) begin : GEN_MEMORY_RESULT_AGE
            assign recovery_done_age[result_lane*RECOVERY_AGE_WIDTH +: RECOVERY_AGE_WIDTH] =
                recovery_issue_ages[STRUCT_EX_CORES*RECOVERY_AGE_WIDTH +: RECOVERY_AGE_WIDTH];
        end else begin : GEN_EXTERNAL_RESULT_AGE
            assign recovery_done_age[result_lane*RECOVERY_AGE_WIDTH +: RECOVERY_AGE_WIDTH] =
                i_wbc_result_age[result_lane*RECOVERY_AGE_WIDTH +: RECOVERY_AGE_WIDTH];
        end
    end
    for (genvar done_lane = 0; done_lane < STRUCT_EX_OUT_RESULT_SUM; done_lane++) begin : GEN_RECOVERY_DONE
        // Determine whether a result is live before filtering its WBC valid.
        // Looking up the already-filtered WBC output forms a combinational
        // dependency between result acceptance and the result being checked.
        if (ENABLE_MEMORY_ORDER && done_lane == STRUCT_MEM_WBC_LANE) begin : GEN_MEMORY_KEY
            assign recovery_done_keys[done_lane*_BITWIDTH_FLOW_WINDOWS_PC +: _BITWIDTH_FLOW_WINDOWS_PC] =
                lsq_complete_key;
        end else begin : GEN_EXTERNAL_KEY
            assign recovery_done_keys[done_lane*_BITWIDTH_FLOW_WINDOWS_PC +: _BITWIDTH_FLOW_WINDOWS_PC] =
                i_wbc_result_data[done_lane*_BITWIDTH_EX_RESULT_WIDTH +: _BITWIDTH_FLOW_WINDOWS_PC];
        end
    end
    always_ff @(posedge clk or negedge reset_n) begin
        if (!reset_n) recovery_next_age <= '0;
        else recovery_next_age <= recovery_next_age + RECOVERY_AGE_WIDTH'($countones(recovery_admit));
    end

    generate
        if (ENABLE_RECOVERY_TRACKING) begin : GEN_RECOVERY_TRACKING
            retirement_frontier #(
                .KEY_WIDTH(_BITWIDTH_FLOW_WINDOWS_PC), .PC_WIDTH(IS_INST_PC_BITWIDTH),
                .PC_STEP(IS_INST_PC_STEP), .DEPTH(STRUCT_INST_STATE_ENTRIES),
                .AGE_WIDTH(RECOVERY_AGE_WIDTH), .ALLOC_LANES(STRUCT_DECODE_NEW_INST),
                .COMPLETE_LANES(STRUCT_EX_OUT_RESULT_SUM),
                .ISSUE_LANES(STRUCT_EX_CORES+1), .CHECK_AGE(1'b1),
                .USE_ALLOCATED_PREDICTION(1'b1),
                .ARCH_WIDTH(_BITWIDTH_IS_INST_REGS), .PHYREG_WIDTH(_BITWIDTH_STRUCT_PHYREGS)
            ) U_RETIREMENT_FRONTIER (
                .clk(clk), .reset_n(reset_n),
                .i_allocate_valid(recovery_admit), .o_allocate_ready(recovery_ready),
                .i_allocate_key(recovery_nel_keys),
                .i_allocate_age(recovery_nel_age),
                .i_allocate_store('0), .i_allocate_memory(recovery_memory_admit),
                .i_allocate_control(nel_ist_new_inst_control),
                .i_allocate_predicted_taken(nel_ist_new_inst_predict_taken),
                .i_allocate_predicted_target(nel_ist_new_inst_predict_target),
                .i_allocate_write(nel_ist_new_inst_write),
                .i_allocate_arch(nel_ist_new_inst_arch),
                .i_allocate_phyreg(nel_ist_new_inst_phyreg),
                .i_allocate_exception(nel_ist_new_inst_exception),
                .i_allocate_cause(nel_ist_new_inst_exception_cause),
                .i_complete_valid(wbc_fcl_done_pc_valid),
                .i_complete_memory(STRUCT_EX_OUT_RESULT_SUM'(1) << STRUCT_MEM_WBC_LANE),
                .i_complete_key(recovery_done_keys),
                .i_complete_age(recovery_done_age), .o_complete_live(recovery_done_live),
                .i_issue_key({lsq_complete_key,recovery_issue_keys}), .o_issue_age(recovery_issue_ages),
                .i_store_ready_valid(i_mem_agu_valid && o_mem_agu_get && i_mem_agu_payload[_BITWIDTH_MEM_PAYLOAD-1]),
                .i_store_ready_key(i_mem_agu_key),
                .i_resolve_valid(i_recovery_resolve_valid), .i_resolve_key(i_recovery_resolve_key),
                .i_resolve_age(i_recovery_resolve_age),
                .o_resolve_accept(recovery_resolve_accept),
                .i_resolve_taken(i_recovery_taken), .i_resolve_target(i_recovery_target),
                .i_resolve_predicted_taken(i_recovery_predicted_taken),
                .i_resolve_predicted_target(i_recovery_predicted_target),
                .i_fault_valid(i_recovery_fault_valid), .i_fault_key(i_recovery_fault_key),
                .i_fault_age(i_recovery_fault_age),
                .i_fault_cause(i_recovery_fault_cause),
                .i_interrupt_pending(i_recovery_interrupt_pending), .i_trap_vector(i_recovery_trap_vector),
                .i_store_commit_get(lsq_complete_valid && lsq_complete_store),
                .o_store_commit_valid(recovery_store_commit_valid),
                .o_store_commit_key(recovery_store_commit_key),
                .o_retire_valid(recovery_retire_valid), .o_retire_key(recovery_retire_key),
                .o_retire_write(recovery_retire_write),
                .o_retire_arch(recovery_retire_arch),
                .o_retire_phyreg(recovery_retire_phyreg),
                .o_recover_valid(o_recovery_flush), .o_recover_key(o_recovery_flush_key),
                .o_recover_age(o_recovery_flush_age), .o_redirect_pc(o_recovery_redirect_pc),
                .o_trap_valid(o_recovery_trap_valid), .o_trap_interrupt(o_recovery_trap_interrupt),
                .o_trap_cause(o_recovery_trap_cause), .o_trap_key(),
                .o_trap_pc(o_recovery_trap_pc), .o_count()
            );
        end else begin : GEN_NO_RECOVERY_TRACKING
            assign recovery_ready = 1'b1;
            assign recovery_store_commit_valid = 1'b0;
            assign recovery_store_commit_key = '0;
            assign recovery_retire_write = 1'b0;
            assign recovery_retire_valid = 1'b0;
            assign recovery_retire_key = '0;
            assign recovery_retire_arch = '0;
            assign recovery_retire_phyreg = '0;
            assign recovery_done_live = '1;
            assign recovery_issue_ages = '0;
            assign recovery_resolve_accept = 1'b0;
            assign o_recovery_flush = 1'b0;
            assign o_recovery_flush_key = '0;
            assign o_recovery_flush_age = '0;
            assign o_recovery_redirect_pc = '0;
            assign o_recovery_trap_valid = 1'b0;
            assign o_recovery_trap_interrupt = 1'b0;
            assign o_recovery_trap_cause = '0;
            assign o_recovery_trap_pc = '0;
        end
    endgenerate

    generate
        if (ENABLE_MEMORY_ORDER) begin : GEN_MEMORY_ORDER
            memory_order_queue #(
                .FLOW_PC_WIDTH(_BITWIDTH_FLOW_WINDOWS_PC),
                .ADDRESS_WIDTH(IS_INST_PC_BITWIDTH),
                .DATA_WIDTH(IS_INST_PC_BITWIDTH),
                .MASK_WIDTH(IS_INST_PC_BITWIDTH/8),
                .PHYREG_WIDTH(_BITWIDTH_STRUCT_PHYREGS),
                .MICROOP_WIDTH(EX_INST_MICROOP_BITWIDTH),
                .OPERANDS(IS_INST_OPERANDS),
                .EXPATH_WIDTH(_BITWIDTH_STRUCT_EX_PATH),
                .MEMORY_PATH(STRUCT_MEM_EX_PATH),
                .NEL_LANES(STRUCT_DECODE_NEW_INST),
                .DEPTH(STRUCT_INST_STATE_ENTRIES),
                .ENABLE_STORE_COMMIT(ENABLE_STORE_COMMIT),
                .ENABLE_RECOVERY_FLUSH(ENABLE_RECOVERY_TRACKING),
                .AGE_WIDTH(RECOVERY_AGE_WIDTH)
            ) U_MEMORY_ORDER_QUEUE (
                .clk(clk), .reset_n(reset_n),
                .i_nel_valid(nel_ist_execution_valid),
                .i_nel_data(nel_ist_new_inst_data),
                .i_nel_age(recovery_nel_age),
                .o_nel_ready(lsq_nel_ready),
                .i_flush_valid(o_recovery_flush),
                .i_flush_age(o_recovery_flush_age),
                .i_agu_valid(i_mem_agu_valid),
                .o_agu_get(o_mem_agu_get),
                .i_agu_key(i_mem_agu_key),
                .i_agu_age(i_mem_agu_age),
                .i_agu_payload(i_mem_agu_payload),
                .o_mem_req_valid(o_mem_req_valid),
                .i_mem_req_get(i_mem_req_get),
                .o_mem_req_key(o_mem_req_key),
                .o_mem_req_payload(o_mem_req_payload),
                .i_store_commit_valid(ENABLE_RECOVERY_TRACKING ? recovery_store_commit_valid : i_store_commit_valid),
                .i_store_commit_key(ENABLE_RECOVERY_TRACKING ? recovery_store_commit_key : i_store_commit_key),
                .i_mem_resp_valid(i_mem_resp_valid),
                .i_mem_resp_data(i_mem_resp_data),
                .o_mem_resp_ready(o_mem_resp_ready),
                .o_mem_complete_valid(lsq_complete_valid),
                .o_mem_complete_key(lsq_complete_key),
                .o_mem_complete_store(lsq_complete_store),
                .o_mem_complete_rd(lsq_complete_rd),
                .o_mem_complete_data(o_mem_complete_data)
            );
            assign o_mem_complete_valid = lsq_complete_valid;
            assign o_mem_complete_key = lsq_complete_key;
            assign o_mem_complete_rd = lsq_complete_rd;
        end else begin : GEN_NO_MEMORY_ORDER
            assign lsq_nel_ready = 1'b1;
            assign lsq_complete_valid = 1'b0;
            assign lsq_complete_key = '0;
            assign lsq_complete_rd = '0;
            assign lsq_complete_store = 1'b0;
            assign o_mem_agu_get = 1'b0;
            assign o_mem_req_valid = 1'b0;
            assign o_mem_req_key = '0;
            assign o_mem_req_payload = '0;
            assign o_mem_resp_ready = 1'b0;
            assign o_mem_complete_valid = 1'b0;
            assign o_mem_complete_key = '0;
            assign o_mem_complete_rd = '0;
            assign o_mem_complete_data = '0;
        end
    endgenerate

// END   ===[ INSTANCE AREA ]===   END //

// START ===[ INPUT, OUTPUT AREA ]=== START //
    static_not_taken_predictor #(
        .PC_WIDTH(IS_INST_PC_BITWIDTH), .PC_STEP(IS_INST_PC_STEP)
    ) U_STATIC_NOT_TAKEN (
        .i_predict_valid(nel_fcl_jumpbranch_valid),
        .i_predict_pc(nel_fcl_control_key[0 +: IS_INST_PC_BITWIDTH]),
        .o_predict_valid(), .o_predict_taken(static_predict_taken),
        .o_predict_target(static_predict_target),
        .i_update_valid(recovery_resolve_accept),
        .i_update_pc(i_recovery_resolve_key[0 +: IS_INST_PC_BITWIDTH]),
        .i_update_taken(i_recovery_taken), .i_update_target(i_recovery_target)
    );
    assign o_predict_request_valid = ENABLE_RECOVERY_TRACKING && nel_fcl_jumpbranch_valid;
    assign o_predict_request_key = nel_fcl_control_key;
    assign o_predict_decision_taken = ENABLE_RECOVERY_TRACKING && ENABLE_EXTERNAL_PREDICTOR &&
                                      i_predict_valid ? i_predict_taken : static_predict_taken;
    assign o_predict_decision_target = ENABLE_RECOVERY_TRACKING && ENABLE_EXTERNAL_PREDICTOR &&
                                       i_predict_valid ? i_predict_target : static_predict_target;
    assign o_predict_update_valid = ENABLE_RECOVERY_TRACKING && recovery_resolve_accept;
    assign o_predict_update_key = i_recovery_resolve_key;
    assign o_predict_update_taken = i_recovery_taken;
    assign o_predict_update_target = i_recovery_target;
    // PC Request Output
    assign o_im_req_pc_valid          = fcl_im_req_pc_valid;
    assign fcl_im_req_pc_get          = i_im_req_pc_get;
    assign o_im_req_pc                = fcl_im_req_pc;

    // Instruction Receive Input
    assign im_nel_recv_inst_valid     = i_im_recv_inst_valid & ~fcl_im_recv_discard;
    assign o_im_recv_inst_get         = im_nel_recv_inst_get | (i_im_recv_inst_valid & fcl_im_recv_discard);
    assign im_nel_recv_pc             = i_im_recv_pc;

    // Decoder Info Receive
    assign dec_nel_decode_exception   = i_nel_decode_exception;
    assign dec_nel_decode_exception_cause = i_nel_decode_exception_cause;
    assign dec_nel_decode_expath      = i_nel_decode_expath;
    assign dec_nel_decode_microop     = i_nel_decode_microop;
    assign dec_nel_decode_rd          = i_nel_decode_rd;
    assign dec_nel_decode_newreg      = i_nel_decode_newreg;
    assign dec_nel_decode_rs          = i_nel_decode_rs;
    assign dec_nel_decode_imm         = i_nel_decode_imm;
    assign dec_nel_decode_jump        = i_nel_decode_jump;
    assign dec_nel_decode_jump_reg    = i_nel_decode_jump_reg;
    assign dec_nel_decode_branch      = i_nel_decode_branch;

    // EX Inst Push (RS Out)
    assign o_rs_entry_valid           = rs_ex_wait_inst_valid &
                                        {STRUCT_EX_CORES{!o_recovery_flush}};
    assign rs_ex_wait_inst_get        = i_rs_entry_get;
    assign o_rs_entry_data            = rs_ex_wait_inst_data;

    // EX Result Receive (EX Out)
    for (genvar result_lane = 0; result_lane < STRUCT_EX_OUT_RESULT_SUM; result_lane++) begin : GEN_WBC_INPUT
        if (ENABLE_MEMORY_ORDER && result_lane == STRUCT_MEM_WBC_LANE) begin : GEN_MEMORY_WBC
            assign ex_wbc_result_valid[result_lane] = lsq_complete_valid;
            assign ex_wbc_result_data[result_lane*_BITWIDTH_EX_RESULT_WIDTH +: _BITWIDTH_EX_RESULT_WIDTH] =
                {lsq_complete_rd,lsq_complete_key};
        end else begin : GEN_OTHER_WBC
            assign ex_wbc_result_valid[result_lane] = i_wbc_result_valid[result_lane] &&
                (!ENABLE_RECOVERY_TRACKING || (recovery_done_live[result_lane] && !o_recovery_flush));
            assign ex_wbc_result_data[result_lane*_BITWIDTH_EX_RESULT_WIDTH +: _BITWIDTH_EX_RESULT_WIDTH] =
                i_wbc_result_data[result_lane*_BITWIDTH_EX_RESULT_WIDTH +: _BITWIDTH_EX_RESULT_WIDTH];
        end
    end
    assign ex_wbc_result_branch_valid = i_wbc_result_branch_valid;
    assign ex_wbc_result_branch_data  = i_wbc_result_branch_data;

// END   ===[ INPUT, OUTPUT AREA ]===   END //

endmodule
