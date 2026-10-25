`timescale 1ns / 1ps

module tb_new_entry_logic ();

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
    localparam BITWIDTH_INST_NUM_OF_LOGICAL_REGISTER    = $clog2(INST_NUM_OF_LOGICAL_REGISTER);
    localparam BITWIDTH_FCL_RB_NUM                      = $clog2(FCL_RB_NUM);
    localparam BITWIDTH_FCL_PC_WIDTH                    = BITWIDTH_FCL_RB_NUM + INST_PC_WIDTH;
    // (Autogenerate) Field of Entry in Instruction State Table
        /* Entry: MSB [ ( Opreand Reday_n, ... , Opreand Reday_1 ) | 
                        ( Opreand Rename Register_n, ... , Opreand Rename Register_1 ) | 
                        Destination Rename Register | 
                        IMM | Micro-OP | EX_PATH | PC ] LSB */    
    localparam IST_BITWIDTH_OPREAND_PHYREG_FULL = BITWIDTH_PHYREG_NUM * INST_OPREANDS;
    localparam IST_BITWIDTH_OPREAND_READY_FULL  = INST_OPREANDS;
    localparam IST_BITWIDTH = BITWIDTH_FCL_PC_WIDTH + MICROOP_WIDTH + INST_IMM_WIDTH + BITWIDTH_PHYREG_NUM
                              + IST_BITWIDTH_OPREAND_PHYREG_FULL + IST_BITWIDTH_OPREAND_READY_FULL;
    localparam IST_STARTPOINT_PHYREG            = BITWIDTH_FCL_PC_WIDTH + MICROOP_WIDTH + INST_IMM_WIDTH;
    localparam IST_STARTPOINT_LOGREG            = IST_STARTPOINT_PHYREG + BITWIDTH_PHYREG_NUM;
    localparam IST_STARTPOINT_OPREAND_PHYREG    = IST_STARTPOINT_LOGREG + BITWIDTH_INST_NUM_OF_LOGICAL_REGISTER;
    localparam IST_STARTPOINT_OPREAND_READY     = IST_STARTPOINT_OPREAND_PHYREG + IST_BITWIDTH_OPREAND_PHYREG_FULL;
    localparam IST_PACKET_BITWIDTH              = IST_BITWIDTH * DECODE_NEW_INST;
    // (Autogenerate) Field of Allocator in Instruction State Table
    localparam IST_ALLOCATE_BITWIDTH = BITWIDTH_IST_ENTRY_NUM * DECODE_NEW_INST;
    // (Autogenerate) Field of Allocator in Physical Register Manager
    localparam PRM_ALLOCATE_BITWIDTH        = BITWIDTH_PHYREG_NUM * DECODE_NEW_INST;
    // (Autogenerate) Width of Instructions
    localparam INST_INPUT_BITWIDTH          = INST_BITWIDTH * DECODE_NEW_INST;
    // (Autogenerate) Write Back Field
    localparam WB_PHYREGS_BITWIDTH          = BITWIDTH_PHYREG_NUM * EX_PATH_NUM;

    
    reg                                               clk;
    reg                                               reset_n;
    // Instruction Memory
        // <- New Inst Input
    reg [DECODE_NEW_INST-1:0]                         i_im_inst_valid;
    reg [(DECODE_NEW_INST*BITWIDTH_FCL_PC_WIDTH)-1:0] i_im_inst_pc;
    reg [(DECODE_NEW_INST*INST_BITWIDTH)-1:0]         i_im_inst;
    wire [DECODE_NEW_INST-1:0]                        o_im_inst_get;
    // Create IST Field
        // -> Instruction State Table Update
    reg                                               i_ist_insert_available;
    wire [DECODE_NEW_INST-1:0]                        o_ist_field_insert;
    reg [DECODE_NEW_INST-1:0]                         i_ist_field_valid;
    wire [IST_PACKET_BITWIDTH-1:0]                    o_ist_field;
    // PRM
    wire [DECODE_NEW_INST-1:0]                        o_allocate_position;
        // <- Physical Register Manager Allocator
    reg [DECODE_NEW_INST-1:0]                         i_prm_allocate_valid;
    reg [PRM_ALLOCATE_BITWIDTH-1:0]                   i_prm_allocate_phyreg;
    // WBC
        // <- Ready Register number
    reg [EX_PATH_NUM-1:0]                             i_wbc2nel_done;
    reg [(EX_PATH_NUM*BITWIDTH_PHYREG_NUM)-1:0]       i_wbc2nel_done_phyreg;
    // New Entry Logic
        // <- Block
    wire                                               o_nel_block;
        // <- Jump Instruction Input
    wire                                               o_nel_jump_inst;
    wire                                               o_nel_jreg_branch_inst;
    wire [INST_PC_WIDTH-1:0]                           o_nel_jump_branch_pc;
        // <- Allocate Registers input
    wire [DECODE_NEW_INST-1:0]                         o_nel_newpc_valid;
    wire [(BITWIDTH_FCL_PC_WIDTH*DECODE_NEW_INST)-1:0] o_nel_newpc;
    wire [DECODE_NEW_INST-1:0]                         o_nel_lastreg_valid;
    wire [(BITWIDTH_PHYREG_NUM*DECODE_NEW_INST)-1:0]   o_nel_lastreg;

    new_entry_logic #(
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
    ) dut (
        .clk                    (clk),
        .reset_n                (reset_n),
        .i_im_inst_valid        (i_im_inst_valid),
        .i_im_inst_pc           (i_im_inst_pc),
        .i_im_inst              (i_im_inst),
        .o_im_inst_get          (o_im_inst_get),
        .i_ist_insert_available (i_ist_insert_available),
        .o_ist_field_insert     (o_ist_field_insert),
        .i_ist_field_valid      (i_ist_field_valid),
        .o_ist_field            (o_ist_field),
        .o_allocate_position    (o_allocate_position),
        .i_prm_allocate_valid   (i_prm_allocate_valid),
        .i_prm_allocate_phyreg  (i_prm_allocate_phyreg),
        .i_wbc2nel_done         (i_wbc2nel_done),
        .i_wbc2nel_done_phyreg  (i_wbc2nel_done_phyreg),
        .o_nel_block            (o_nel_block),
        .o_nel_jump_inst        (o_nel_jump_inst),
        .o_nel_jreg_branch_inst (o_nel_jreg_branch_inst),
        .o_nel_jump_branch_pc   (o_nel_jump_branch_pc),
        .o_nel_newpc_valid      (o_nel_newpc_valid),
        .o_nel_newpc            (o_nel_newpc),
        .o_nel_lastreg_valid    (o_nel_lastreg_valid),
        .o_nel_lastreg          (o_nel_lastreg)
    );

    always #5 clk = ~clk;

    initial begin
        #0;
        clk = 1'b0; reset_n = 1'b0;
        i_im_inst_valid = 0;
        i_im_inst_pc    = 0;
        i_im_inst       = 0;
        i_ist_insert_available = 0;
        i_ist_field_valid = 0;
        i_prm_allocate_valid = 0;
        i_prm_allocate_phyreg = 0;
        i_wbc2nel_done = 0;
        i_wbc2nel_done_phyreg = 0;

        @(negedge clk);
        @(negedge clk);
        reset_n = 1'b1;
        @(negedge clk);

        i_ist_insert_available = 1;
        i_im_inst_valid = 1'b1;
        i_im_inst_pc    = 32'h0001_2350;
        i_im_inst       = 32'h0051_83b3; // add x7, x3, x5
        i_ist_field_valid = {DECODE_NEW_INST{1'b1}};
        @(negedge clk);
        
        i_ist_insert_available = 1;
        i_im_inst_valid = 1'b1;
        i_im_inst_pc    = 32'h0001_2354;
        i_im_inst       = 32'h0000_03b3; // add x7, x0, x0
        i_ist_field_valid = {DECODE_NEW_INST{1'b1}};
        @(negedge clk);
        @(negedge clk);
        @(negedge clk);
        $finish;
    end

endmodule