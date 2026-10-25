module tb_flow_control_logic ();

    // Dynamic Schedular Description
    parameter DECODE_NEW_INST   = 1;
    parameter PHYREG_NUM        = 64;
    parameter IST_ENTRY_NUM     = 128;
    parameter EX_PATH_NUM       = 3;
    parameter PRM_ENTRY_BUFFER  = 4;
    parameter RS_ENTRY_NUM      = 16;
    parameter RS_PUSH_WIDTH     = 3;
    parameter FCL_RB_NUM        = 8;
    parameter FCL_PC_GAP        = 4;
    parameter UNALLOCATE_PHYREG = 4;

    // Instruction Field Description
    parameter INST_PC_WIDTH                 = 32;
    parameter INST_BITWIDTH                 = 32;
    parameter INST_OPCODE_WIDTH             = 7;
    parameter INST_OPTIONAL_OPCODE_WIDTH    = 10;
    parameter INST_IMM_WIDTH                = 32;
    parameter INST_NUM_OF_LOGICAL_REGISTER  = 32;
    parameter INST_OPREANDS                 = 2;

    // Internal Field Description (Decoder Compiler (or Human) Generate)
    parameter MICROOP_WIDTH                 = 5; // Micro-OP is not contained information of EX_PATH

    // (Autogenerate) Elements
    localparam BITWIDTH_EX_PATH_NUM                     = $clog2(EX_PATH_NUM);
    localparam BITWIDTH_PHYREG_NUM                      = $clog2(PHYREG_NUM);
    localparam BITWIDTH_IST_ENTRY_NUM                   = $clog2(IST_ENTRY_NUM);
    localparam BITWIDTH_INST_NUM_OF_OGICAL_REGISTER     = $clog2(INST_NUM_OF_LOGICAL_REGISTER);
    localparam BITWIDTH_FCL_RB_NUM                      = $clog2(FCL_RB_NUM);

    localparam BITWIDTH_FCL_PC_WIDTH                    = BITWIDTH_FCL_RB_NUM + INST_PC_WIDTH;

    localparam FCL_RB_PC_GAP_MAX                        = (PHYREG_NUM/2)*FCL_PC_GAP;
    
    reg                                                clk;
    reg                                                reset_n;

    // New Entry Logic
        // <- Block
    reg                                                i_nel_block;
        // <- Jump Instruction Input
    reg                                                i_nel_jump_inst;
    reg                                                i_nel_jreg_branch_inst;
    reg  [INST_PC_WIDTH-1:0]                           i_nel_jump_branch_pc;
        // <- Allocate Registers input
    reg  [DECODE_NEW_INST-1:0]                         i_nel_newpc_valid;
    reg  [(BITWIDTH_FCL_PC_WIDTH*DECODE_NEW_INST)-1:0] i_nel_newpc;
    reg  [DECODE_NEW_INST-1:0]                         i_nel_newreg_valid;
    reg  [(BITWIDTH_PHYREG_NUM*DECODE_NEW_INST)-1:0]   i_nel_newreg;

    // Physical Register Mapper
        // -> Unallocate Registers Output
    wire [UNALLOCATE_PHYREG-1:0]                       o_prm_unallocate_valid;
    wire [(BITWIDTH_PHYREG_NUM*UNALLOCATE_PHYREG)-1:0] o_prm_unallocate_phyreg;

    // Write Back Concatenation
        // <- PC Input
    reg  [EX_PATH_NUM-1:0]                             i_wbc2fcl_done;
    reg  [(EX_PATH_NUM*BITWIDTH_FCL_PC_WIDTH)-1:0]     i_wbc2fcl_pc;
    reg                                                i_wbc2fcl_branch;
    reg  [INST_PC_WIDTH-1:0]                           i_wbc2fcl_branch_pc;

    // Instruction Memory
        // -> New PC Output
    wire                                               o_im_re;
    wire [BITWIDTH_FCL_PC_WIDTH-1:0]                   o_im_pc;

    flow_control_logic #(
        .DECODE_NEW_INST               (DECODE_NEW_INST),
        .PHYREG_NUM                    (PHYREG_NUM),
        .IST_ENTRY_NUM                 (IST_ENTRY_NUM),
        .EX_PATH_NUM                   (EX_PATH_NUM),
        .PRM_ENTRY_BUFFER              (PRM_ENTRY_BUFFER),
        .RS_ENTRY_NUM                  (RS_ENTRY_NUM),
        .RS_PUSH_WIDTH                 (RS_PUSH_WIDTH),
        .FCL_RB_NUM                    (FCL_RB_NUM),
        .FCL_PC_GAP                    (FCL_PC_GAP),
        .UNALLOCATE_PHYREG             (UNALLOCATE_PHYREG),
        .INST_PC_WIDTH                 (INST_PC_WIDTH),
        .INST_BITWIDTH                 (INST_BITWIDTH),
        .INST_OPCODE_WIDTH             (INST_OPCODE_WIDTH),
        .INST_OPTIONAL_OPCODE_WIDTH    (INST_OPTIONAL_OPCODE_WIDTH),
        .INST_IMM_WIDTH                (INST_IMM_WIDTH),
        .INST_NUM_OF_LOGICAL_REGISTER  (INST_NUM_OF_LOGICAL_REGISTER),
        .INST_OPREANDS                 (INST_OPREANDS),
        .MICROOP_WIDTH                 (MICROOP_WIDTH)
    ) (
        .clk                           (clk),
        .reset_n                       (reset_n),
        .i_nel_block                   (i_nel_block),
        .i_nel_jump_inst               (i_nel_jump_inst),
        .i_nel_jreg_branch_inst        (i_nel_jreg_branch_inst),
        .i_nel_jump_branch_pc          (i_nel_jump_branch_pc),
        .i_nel_newpc_valid             (i_nel_newpc_valid),
        .i_nel_newpc                   (i_nel_newpc),
        .i_nel_newreg_valid            (i_nel_newreg_valid),
        .i_nel_newreg                  (i_nel_newreg),
        .o_prm_unallocate_valid        (o_prm_unallocate_valid),
        .o_prm_unallocate_phyreg       (o_prm_unallocate_phyreg),
        .i_wbc2fcl_done                (i_wbc2fcl_done),
        .i_wbc2fcl_pc                  (i_wbc2fcl_pc),
        .i_wbc2fcl_branch              (i_wbc2fcl_branch),
        .i_wbc2fcl_branch_pc           (i_wbc2fcl_branch_pc),
        .o_im_re                       (o_im_re),
        .o_im_pc                       (o_im_pc)
    );

    always #5 clk = ~clk;

    initial begin
        #0;
        clk = 0; reset_n = 0;
        i_nel_block = 0;

        i_nel_jump_inst = 0;
        i_nel_jreg_branch_inst = 0;
        i_nel_jump_branch_pc = 0;
        
        i_nel_newpc_valid = 0;
        i_nel_newpc = 0;
        i_nel_newreg_valid = 0;
        i_nel_newreg = 0;

        i_wbc2fcl_done = 0;
        i_wbc2fcl_pc = 0;
        i_wbc2fcl_branch = 0;
        i_wbc2fcl_branch_pc = 0;
    end

endmodule
