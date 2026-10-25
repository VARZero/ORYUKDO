`timescale 1ns / 1ps

module write_back_concatenation #(
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
    localparam BITWIDTH_INST_NUM_OF_LOGICAL_REGISTER    = $clog2(INST_NUM_OF_LOGICAL_REGISTER),
    localparam BITWIDTH_FCL_RB_NUM                      = $clog2(FCL_RB_NUM),
    
    localparam BITWIDTH_FCL_PC_WIDTH                    = BITWIDTH_FCL_RB_NUM + INST_PC_WIDTH
) (
    input wire                  clk,
    input wire                  reset_n,

    // EX out
        // <- Execute Units Result Input
    input wire  [EX_PATH_NUM-1:0]                           i_ex_done,
    input wire  [(EX_PATH_NUM*BITWIDTH_FCL_PC_WIDTH)-1:0]   i_ex_done_pc,
    input wire                                              i_ex_done_branch,
    input wire  [INST_PC_WIDTH-1:0]                         i_ex_done_branch_pc,
    input wire  [(EX_PATH_NUM*BITWIDTH_PHYREG_NUM)-1:0]     i_ex_done_phyreg,

    // PRM
        // -> Ready Register number
    output wire [EX_PATH_NUM-1:0]                           o_wbc2prm_done,
    output wire [(EX_PATH_NUM*BITWIDTH_PHYREG_NUM)-1:0]     o_wbc2prm_done_phyreg,

    // NEL
        // -> Ready Register number
    output wire [EX_PATH_NUM-1:0]                           o_wbc2nel_done,
    output wire [(EX_PATH_NUM*BITWIDTH_PHYREG_NUM)-1:0]     o_wbc2nel_done_phyreg,

    // FCL
        // -> Ready instruction PC and Branch Result PC
    output wire [EX_PATH_NUM-1:0]                           o_wbc2fcl_done,
    output wire [(EX_PATH_NUM*BITWIDTH_FCL_PC_WIDTH)-1:0]   o_wbc2fcl_pc,
    output wire                                             o_wbc2fcl_branch,
    output wire [INST_PC_WIDTH-1:0]                         o_wbc2fcl_branch_pc
);
    // Branch unit is always Ex_0

    assign o_wbc2prm_done = i_ex_done;
    assign o_wbc2nel_done = i_ex_done;
    assign o_wbc2fcl_done = i_ex_done;

    assign o_wbc2prm_done_phyreg = i_ex_done_phyreg;
    assign o_wbc2nel_done_phyreg = i_ex_done_phyreg;

    assign o_wbc2fcl_pc = i_ex_done_pc;

    assign o_wbc2fcl_branch    = i_ex_done_branch;
    assign o_wbc2fcl_branch_pc = i_ex_done_branch_pc;

endmodule
