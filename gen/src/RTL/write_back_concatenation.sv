`timescale 1ns / 1ps

module write_back_concatenation #(
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
    localparam int _STRUCT_EX_OUT_RESULT_ALL            = STRUCT_EX_OUT_RESULT_SUM,
    localparam int _BITWIDTH_LOW_STRUCT_PHYREGS         = $clog2(STRUCT_PHYREGS),
    localparam int _BITWIDTH_LOW_STRUCT_FLOW_WINDOWS   = $clog2(STRUCT_FLOW_WINDOWS),

    // Composite bitwidths
    localparam int _BITWIDTH_CMB_BRANCH_RESULT          = (IS_INST_PC_BITWIDTH * 2) + 1 + _BITWIDTH_LOW_STRUCT_PHYREGS + _BITWIDTH_LOW_STRUCT_FLOW_WINDOWS,
    localparam int _BITWIDTH_CMB_NORMAL_RESULT          = IS_INST_PC_BITWIDTH + _BITWIDTH_LOW_STRUCT_FLOW_WINDOWS + _BITWIDTH_LOW_STRUCT_PHYREGS,
    localparam int _BITWIDTH_CMB_TOTAL_EX_RESULT        = _BITWIDTH_CMB_BRANCH_RESULT + (_BITWIDTH_CMB_NORMAL_RESULT * (_STRUCT_EX_OUT_RESULT_ALL - 1))
) (
    input  wire                                                 clk,
    input  wire                                                 reset_n,

    // Execute Units Result Input (i_ex_result_*)
    input  wire [_STRUCT_EX_OUT_RESULT_ALL-1:0]                  i_ex_result_valid,
    input  wire [_BITWIDTH_CMB_TOTAL_EX_RESULT-1:0]              i_ex_result_data,

    // PRM (o_prm_phyreg_*)
    output wire [_STRUCT_EX_OUT_RESULT_ALL-1:0]                  o_prm_phyreg_valid,
    output wire [(_STRUCT_EX_OUT_RESULT_ALL * _BITWIDTH_LOW_STRUCT_PHYREGS)-1:0] o_prm_phyreg_data,

    // NEL (o_nel_phyreg_*)
    output wire [_STRUCT_EX_OUT_RESULT_ALL-1:0]                  o_nel_phyreg_valid,
    output wire [(_STRUCT_EX_OUT_RESULT_ALL * _BITWIDTH_LOW_STRUCT_PHYREGS)-1:0] o_nel_phyreg_data,

    // FCL PC Output (o_fcl_pc_*)
    output wire [_STRUCT_EX_OUT_RESULT_ALL-1:0]                  o_fcl_pc_valid,
    output wire [(_STRUCT_EX_OUT_RESULT_ALL * (_BITWIDTH_LOW_STRUCT_FLOW_WINDOWS + IS_INST_PC_BITWIDTH))-1:0] o_fcl_pc_data,

    // FCL Branch Output (o_fcl_branch_*)
    output wire                                                 o_fcl_branch_valid,
    output wire [(IS_INST_PC_BITWIDTH + 1)-1:0]                 o_fcl_branch_data
);

    // -------------------------------------------------------------------------
    // Combinational extraction logic
    // -------------------------------------------------------------------------
    assign o_prm_phyreg_valid = i_ex_result_valid;
    assign o_nel_phyreg_valid = i_ex_result_valid;
    assign o_fcl_pc_valid     = i_ex_result_valid;

    // Index 0: Branch result unpacking
    wire [IS_INST_PC_BITWIDTH-1:0]           pc_0         = i_ex_result_data[0 +: IS_INST_PC_BITWIDTH];
    wire [_BITWIDTH_LOW_STRUCT_FLOW_WINDOWS-1:0] flow_idx_0 = i_ex_result_data[IS_INST_PC_BITWIDTH +: _BITWIDTH_LOW_STRUCT_FLOW_WINDOWS];
    wire [_BITWIDTH_LOW_STRUCT_PHYREGS-1:0]  rd_0         = i_ex_result_data[IS_INST_PC_BITWIDTH + _BITWIDTH_LOW_STRUCT_FLOW_WINDOWS +: _BITWIDTH_LOW_STRUCT_PHYREGS];
    wire                                     branch_act_0 = i_ex_result_data[IS_INST_PC_BITWIDTH + _BITWIDTH_LOW_STRUCT_FLOW_WINDOWS + _BITWIDTH_LOW_STRUCT_PHYREGS];
    wire [IS_INST_PC_BITWIDTH-1:0]           new_pc_0     = i_ex_result_data[IS_INST_PC_BITWIDTH + _BITWIDTH_LOW_STRUCT_FLOW_WINDOWS + _BITWIDTH_LOW_STRUCT_PHYREGS + 1 +: IS_INST_PC_BITWIDTH];

    assign o_prm_phyreg_data[0 +: _BITWIDTH_LOW_STRUCT_PHYREGS] = rd_0;
    assign o_nel_phyreg_data[0 +: _BITWIDTH_LOW_STRUCT_PHYREGS] = rd_0;
    assign o_fcl_pc_data[0 +: (_BITWIDTH_LOW_STRUCT_FLOW_WINDOWS + IS_INST_PC_BITWIDTH)] = {pc_0, flow_idx_0};

    assign o_fcl_branch_valid = i_ex_result_valid[0];
    assign o_fcl_branch_data  = {new_pc_0, branch_act_0};

    // Index 1 to N: Normal result unpacking (for general execute units)
    genvar i;
    generate
        for (i = 1; i < _STRUCT_EX_OUT_RESULT_ALL; i = i + 1) begin : gen_wbc_unpack
            localparam int offset = _BITWIDTH_CMB_BRANCH_RESULT + (i - 1) * _BITWIDTH_CMB_NORMAL_RESULT;
            
            wire [IS_INST_PC_BITWIDTH-1:0]           pc_i       = i_ex_result_data[offset +: IS_INST_PC_BITWIDTH];
            wire [_BITWIDTH_LOW_STRUCT_FLOW_WINDOWS-1:0] flow_idx_i = i_ex_result_data[offset + IS_INST_PC_BITWIDTH +: _BITWIDTH_LOW_STRUCT_FLOW_WINDOWS];
            wire [_BITWIDTH_LOW_STRUCT_PHYREGS-1:0]  rd_i       = i_ex_result_data[offset + IS_INST_PC_BITWIDTH + _BITWIDTH_LOW_STRUCT_FLOW_WINDOWS +: _BITWIDTH_LOW_STRUCT_PHYREGS];

            assign o_prm_phyreg_data[i * _BITWIDTH_LOW_STRUCT_PHYREGS +: _BITWIDTH_LOW_STRUCT_PHYREGS] = rd_i;
            assign o_nel_phyreg_data[i * _BITWIDTH_LOW_STRUCT_PHYREGS +: _BITWIDTH_LOW_STRUCT_PHYREGS] = rd_i;
            assign o_fcl_pc_data[i * (_BITWIDTH_LOW_STRUCT_FLOW_WINDOWS + IS_INST_PC_BITWIDTH) +: (_BITWIDTH_LOW_STRUCT_FLOW_WINDOWS + IS_INST_PC_BITWIDTH)] = {pc_i, flow_idx_i};
        end
    endgenerate

endmodule
