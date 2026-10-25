`timescale 1ns / 1ps
module eulsukdo_1dec_3issue #(
    // Dynamic Schedular Description
    parameter DECODE_NEW_INST   = 1,
    parameter PHYREG_NUM        = 64,
    parameter IST_ENTRY_NUM     = 128,
    parameter EX_PATH_NUM       = 3,
    parameter PRM_ENTRY_BUFFER  = 4,
    parameter PRM_ENTRY_UPDATE  = 3,
    parameter PRM_READY_OUT_FIFO_DEPTH = 32,
    parameter RS_ENTRY_NUM      = 16,
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
    localparam BITWIDTH_FCL_PC_WIDTH                    = BITWIDTH_FCL_RB_NUM + INST_PC_WIDTH,

    localparam RS_PUSH_WIDTH     = PRM_ENTRY_UPDATE + DECODE_NEW_INST
) (
    input                                             clk,
    input                                             reset_n,

    input  wire [DECODE_NEW_INST-1:0]                         i_im_inst_valid,
    input  wire [(DECODE_NEW_INST*INST_BITWIDTH)-1:0]         i_im_inst,
    output wire [DECODE_NEW_INST-1:0]                         o_im_inst_get,
    
    output wire                                               o_im_re,
    output wire [BITWIDTH_FCL_PC_WIDTH-1:0]                   o_im_pc,

    // EX INOUT Section Start ==============================================

        // Memory Start ===================================
        
        output wire        re_vmem_o,
        output wire        we_vmem_o,
        output wire [31:0] addr_vmem_o,
        output wire [3:0]  strb_vmem_o,
        input  wire [31:0] rdata_vmem_i,
        output wire [31:0] wdata_vmem_o,
        input  wire        ready_vmem_i

        // Memory End =====================================
    

    // EX INOUT Section End ================================================
);
    localparam IST_BITWIDTH_OPREAND_PHYREG_FULL = BITWIDTH_PHYREG_NUM * INST_OPREANDS;
    localparam IST_BITWIDTH_OPREAND_READY_FULL  = INST_OPREANDS;
    localparam IST_BITWIDTH = BITWIDTH_FCL_PC_WIDTH + BITWIDTH_EX_PATH_NUM + MICROOP_WIDTH + INST_IMM_WIDTH + BITWIDTH_PHYREG_NUM
                              + IST_BITWIDTH_OPREAND_PHYREG_FULL + IST_BITWIDTH_OPREAND_READY_FULL;
    localparam IST_STARTPOINT_PHYREG            = BITWIDTH_FCL_PC_WIDTH + BITWIDTH_EX_PATH_NUM + MICROOP_WIDTH + INST_IMM_WIDTH;
    localparam IST_STARTPOINT_OPREAND_PHYREG    = IST_STARTPOINT_PHYREG + BITWIDTH_PHYREG_NUM;
    localparam IST_STARTPOINT_OPREAND_READY     = IST_STARTPOINT_OPREAND_PHYREG + IST_BITWIDTH_OPREAND_PHYREG_FULL;
    localparam IST_PACKET_BITWIDTH              = IST_BITWIDTH * DECODE_NEW_INST;
    localparam IST_ALLOCATE_BITWIDTH            = BITWIDTH_IST_ENTRY_NUM * DECODE_NEW_INST;
    localparam PRM_ALLOCATE_BITWIDTH            = BITWIDTH_PHYREG_NUM * DECODE_NEW_INST;
    localparam INST_INPUT_BITWIDTH              = INST_BITWIDTH * DECODE_NEW_INST;
    localparam WB_PHYREGS_BITWIDTH              = BITWIDTH_PHYREG_NUM * EX_PATH_NUM;
    localparam PRM_UNALLOCATE_BITWIDTH          = BITWIDTH_PHYREG_NUM * UNALLOCATE_PHYREG;
    localparam RS_ENTRY_BITWIDTH                = BITWIDTH_FCL_PC_WIDTH + BITWIDTH_EX_PATH_NUM + MICROOP_WIDTH
                                                  + INST_IMM_WIDTH + BITWIDTH_PHYREG_NUM + IST_BITWIDTH_OPREAND_PHYREG_FULL;
    localparam RS_STARTPOINT_PC                 = 0;
    localparam RS_STARTPOINT_EXPATH             = RS_STARTPOINT_PC + BITWIDTH_FCL_PC_WIDTH;
    localparam RS_STARTPOINT_MICROOP            = RS_STARTPOINT_EXPATH + BITWIDTH_EX_PATH_NUM;
    localparam RS_STARTPOINT_IMM                = RS_STARTPOINT_MICROOP + MICROOP_WIDTH;
    localparam RS_STARTPOINT_RD                 = RS_STARTPOINT_IMM + INST_IMM_WIDTH;
    localparam RS_STARTPOINT_RS1                = RS_STARTPOINT_RD + BITWIDTH_PHYREG_NUM;
    localparam RS_STARTPOINT_RS2                = RS_STARTPOINT_RS1 + BITWIDTH_PHYREG_NUM;

    localparam RS_PACKET_BITWIDTH               = RS_ENTRY_BITWIDTH * RS_PUSH_WIDTH;
    localparam EX_PACKET_BITWIDTH               = RS_ENTRY_BITWIDTH * EX_PATH_NUM;

    wire [(DECODE_NEW_INST*BITWIDTH_FCL_PC_WIDTH)-1:0]                  fcl_inst_pc;
    wire                                                                ist_insert_available;
    wire [DECODE_NEW_INST-1:0]                                          ist_field_insert;
    wire [DECODE_NEW_INST-1:0]                                          ist_field_valid;
    wire [IST_PACKET_BITWIDTH-1:0]                                      ist_field;
    wire [DECODE_NEW_INST-1:0]                                          allocate_position;
    wire [DECODE_NEW_INST-1:0]                                          prm_allocate_valid;
    wire [PRM_ALLOCATE_BITWIDTH-1:0]                                    prm_allocate_phyreg;
    wire [EX_PATH_NUM-1:0]                                              wbc2nel_done;
    wire [(EX_PATH_NUM*BITWIDTH_PHYREG_NUM)-1:0]                        wbc2nel_done_phyreg;
    wire                                                                nel_block;
    wire                                                                nel_jump_inst;
    wire                                                                nel_jreg_branch_inst;
    wire [INST_PC_WIDTH-1:0]                                            nel_jump_branch_pc;
    wire [DECODE_NEW_INST-1:0]                                          nel_newpc_valid;
    wire [(BITWIDTH_FCL_PC_WIDTH*DECODE_NEW_INST)-1:0]                  nel_newpc;
    wire [DECODE_NEW_INST-1:0]                                          nel_lastreg_valid;
    wire [(BITWIDTH_PHYREG_NUM*DECODE_NEW_INST)-1:0]                    nel_lastreg;
    wire [(DECODE_NEW_INST*INST_OPREANDS)-1:0]                          prm_istindex_valid;
    wire [(BITWIDTH_PHYREG_NUM*(DECODE_NEW_INST*INST_OPREANDS))-1:0]    prm_istindex_phyreg;
    wire [(BITWIDTH_IST_ENTRY_NUM*(DECODE_NEW_INST*INST_OPREANDS))-1:0] prm_istindex_istidx;
    wire [PRM_ENTRY_UPDATE-1:0]                                         ready_update_valid;
    wire [PRM_ENTRY_UPDATE-1:0]                                         ready_update_get;
    wire [(BITWIDTH_PHYREG_NUM*PRM_ENTRY_UPDATE)-1:0]                   ready_update_phyreg;
    wire [(BITWIDTH_IST_ENTRY_NUM*PRM_ENTRY_UPDATE)-1:0]                ready_update_istidx;
    wire                                                                push_rs_available;
    wire [RS_PUSH_WIDTH-1:0]                                            push_rs_valid;
    wire [(RS_PUSH_WIDTH*RS_ENTRY_BITWIDTH)-1:0]                        push_rs_data;
    wire [UNALLOCATE_PHYREG-1:0]                                        prm_unallocate_valid;
    wire [PRM_UNALLOCATE_BITWIDTH-1:0]                                  prm_unallocate_phyreg;
    wire [EX_PATH_NUM-1:0]                                              wb_done;
    wire [(EX_PATH_NUM*BITWIDTH_PHYREG_NUM)-1:0]                        wb_done_phyreg;
    wire                                                                prm_active;
    wire [EX_PATH_NUM-1:0]                                              ex_entry_get;
    wire [EX_PATH_NUM-1:0]                                              ex_entry_valid;
    wire [EX_PACKET_BITWIDTH-1:0]                                       ex_entry;
    wire [EX_PATH_NUM-1:0]                                              wbc2fcl_done;
    wire [(EX_PATH_NUM*BITWIDTH_FCL_PC_WIDTH)-1:0]                      wbc2fcl_pc;
    wire                                                                wbc2fcl_branch;
    wire [INST_PC_WIDTH-1:0]                                            wbc2fcl_branch_pc;

    assign o_im_pc = fcl_inst_pc[INST_PC_WIDTH-1:0];

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
    ) U_NEL (
        .clk                           (clk),
        .reset_n                       (reset_n),
        .i_im_inst_valid               (i_im_inst_valid),
        .i_im_inst_pc                  (fcl_inst_pc),
        .i_im_inst                     (i_im_inst),
        .o_im_inst_get                 (o_im_inst_get),
        .i_ist_insert_available        (ist_insert_available),
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
        .DECODE_NEW_INST               (DECODE_NEW_INST),
        .PHYREG_NUM                    (PHYREG_NUM),
        .IST_ENTRY_NUM                 (IST_ENTRY_NUM),
        .EX_PATH_NUM                   (EX_PATH_NUM),
        .PRM_ENTRY_BUFFER              (PRM_ENTRY_BUFFER),
        .PRM_ENTRY_UPDATE              (PRM_ENTRY_UPDATE),
        .RS_ENTRY_NUM                  (RS_ENTRY_NUM),
        .FCL_RB_NUM                    (FCL_RB_NUM),
        .INST_PC_WIDTH                 (INST_PC_WIDTH),
        .INST_BITWIDTH                 (INST_BITWIDTH),
        .INST_OPCODE_WIDTH             (INST_OPCODE_WIDTH),
        .INST_OPTIONAL_OPCODE_WIDTH    (INST_OPTIONAL_OPCODE_WIDTH),
        .INST_IMM_WIDTH                (INST_IMM_WIDTH),
        .INST_NUM_OF_LOGICAL_REGISTER  (INST_NUM_OF_LOGICAL_REGISTER),
        .INST_OPREANDS                 (INST_OPREANDS),
        .MICROOP_WIDTH                 (MICROOP_WIDTH)
    ) U_IST (
        .clk                           (clk),
        .reset_n                       (reset_n),
        .o_ist_insert_available        (ist_insert_available),
        .i_ist_field_insert            (ist_field_insert),
        .o_ist_field_valid             (ist_field_valid),
        .i_ist_field                   (ist_field),
        .o_prm_istindex_valid          (prm_istindex_valid),
        .o_prm_istindex_phyreg         (prm_istindex_phyreg),
        .o_prm_istindex_istidx         (prm_istindex_istidx),
        .i_ready_update_valid          (ready_update_valid),
        .o_ready_update_get            (ready_update_get),
        .i_ready_update_phyreg         (ready_update_phyreg),
        .i_ready_update_istidx         (ready_update_istidx),
        .i_push_rs_available           (push_rs_available),
        .o_push_rs_valid               (push_rs_valid),
        .o_push_rs_data                (push_rs_data)
    );

    physical_register_mapping #(
        .DECODE_NEW_INST               (DECODE_NEW_INST),
        .PHYREG_NUM                    (PHYREG_NUM),
        .IST_ENTRY_NUM                 (IST_ENTRY_NUM),
        .EX_PATH_NUM                   (EX_PATH_NUM),
        .PRM_ENTRY_BUFFER              (PRM_ENTRY_BUFFER),
        .PRM_ENTRY_UPDATE              (PRM_ENTRY_UPDATE),
        .PRM_READY_OUT_FIFO_DEPTH      (PRM_READY_OUT_FIFO_DEPTH),
        .RS_ENTRY_NUM                  (RS_ENTRY_NUM),
        .UNALLOCATE_PHYREG             (UNALLOCATE_PHYREG),
        .INST_PC_WIDTH                 (INST_PC_WIDTH),
        .INST_BITWIDTH                 (INST_BITWIDTH),
        .INST_OPCODE_WIDTH             (INST_OPCODE_WIDTH),
        .INST_OPTIONAL_OPCODE_WIDTH    (INST_OPTIONAL_OPCODE_WIDTH),
        .INST_IMM_WIDTH                (INST_IMM_WIDTH),
        .INST_NUM_OF_LOGICAL_REGISTER  (INST_NUM_OF_LOGICAL_REGISTER),
        .INST_OPREANDS                 (INST_OPREANDS),
        .MICROOP_WIDTH                 (MICROOP_WIDTH)
    ) U_PRM (
        .clk                           (clk),
        .reset_n                       (reset_n),
        .i_allocate_position           (allocate_position),
        .o_prm_allocate_valid          (prm_allocate_valid),
        .o_prm_allocate_phyreg         (prm_allocate_phyreg),
        .i_prm_unallocate_valid        (prm_unallocate_valid),
        .i_prm_unallocate_phyreg       (prm_unallocate_phyreg),
        .i_prm_istindex_valid          (prm_istindex_valid),
        .i_prm_istindex_phyreg         (prm_istindex_phyreg),
        .i_prm_istindex_istidx         (prm_istindex_istidx),
        .o_ready_update_valid          (ready_update_valid),
        .i_ready_update_get            (ready_update_get),
        .o_ready_update_phyreg         (ready_update_phyreg),
        .o_ready_update_istidx         (ready_update_istidx),
        .i_wb_done                     (wb_done),
        .i_wb_done_phyreg              (wb_done_phyreg),
        .o_prm_active                  (prm_active)
    );

    ready_station #(
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
    ) U_RS (
        .clk                           (clk),
        .reset_n                       (reset_n),
        .o_ist_ready_entry_get         (push_rs_available),
        .i_ist_ready_entry_valid       (push_rs_valid),
        .i_ist_ready_entry             (push_rs_data),
        .i_ex_entry_get                (ex_entry_get),
        .o_ex_entry_valid              (ex_entry_valid),
        .o_ex_entry                    (ex_entry)
    );

    // EX Section Start ============================================================

    wire run_branch, run_alu, run_mem;
    wire we_branch, we_alu, we_mem;
    wire done_branch, done_alu, done_mem;
    wire [RS_ENTRY_BITWIDTH-1:0] inst_branch, inst_alu, inst_mem;
    wire [MICROOP_WIDTH-1:0] microop_branch, microop_alu, microop_mem;
    wire [BITWIDTH_FCL_PC_WIDTH-1:0] pc_branch, pc_alu, pc_mem;
    wire [31:0] new_pc;
    wire [BITWIDTH_PHYREG_NUM-1:0] rs1_num_branch, rs2_num_branch, rd_num_branch;
    wire [BITWIDTH_PHYREG_NUM-1:0] rs1_num_alu, rs2_num_alu, rd_num_alu;
    wire [BITWIDTH_PHYREG_NUM-1:0] rs1_num_mem, rs2_num_mem, rd_num_mem;
    wire [31:0] imm_branch, rs1_branch, rs2_branch, rd_value_branch;
    wire [31:0] imm_alu, rs1_alu, rs2_alu, result_alu;
    wire [31:0] imm_mem, rs1_mem, rs2_mem, result_mem;
    wire en_branch;

    wire [EX_PATH_NUM-1:0] done_all_ex;

    assign {run_mem, run_alu, run_branch} = ex_entry_valid;
    assign ex_entry_get = {done_mem, done_alu, done_branch};
    assign done_all_ex  = {done_mem, done_alu, done_branch};

    assign inst_branch = ex_entry[0 +: RS_ENTRY_BITWIDTH];
    assign     pc_branch      = inst_branch[RS_STARTPOINT_PC      +: BITWIDTH_FCL_PC_WIDTH];
    assign     microop_branch = inst_branch[RS_STARTPOINT_MICROOP +: MICROOP_WIDTH        ];
    assign     imm_branch     = inst_branch[RS_STARTPOINT_IMM     +: INST_IMM_WIDTH       ];
    assign     rd_num_branch  = inst_branch[RS_STARTPOINT_RD      +: BITWIDTH_PHYREG_NUM  ];
    assign     rs1_num_branch = inst_branch[RS_STARTPOINT_RS1     +: BITWIDTH_PHYREG_NUM  ];
    assign     rs2_num_branch = inst_branch[RS_STARTPOINT_RS2     +: BITWIDTH_PHYREG_NUM  ];

    assign inst_alu    = ex_entry[RS_ENTRY_BITWIDTH +: RS_ENTRY_BITWIDTH];
    assign     pc_alu         = inst_alu[RS_STARTPOINT_PC      +: BITWIDTH_FCL_PC_WIDTH];
    assign     microop_alu    = inst_alu[RS_STARTPOINT_MICROOP +: MICROOP_WIDTH        ];
    assign     imm_alu        = inst_alu[RS_STARTPOINT_IMM     +: INST_IMM_WIDTH       ];
    assign     rd_num_alu     = inst_alu[RS_STARTPOINT_RD      +: BITWIDTH_PHYREG_NUM  ];
    assign     rs1_num_alu    = inst_alu[RS_STARTPOINT_RS1     +: BITWIDTH_PHYREG_NUM  ];
    assign     rs2_num_alu    = inst_alu[RS_STARTPOINT_RS2     +: BITWIDTH_PHYREG_NUM  ];

    assign inst_mem    = ex_entry[RS_ENTRY_BITWIDTH*2 +: RS_ENTRY_BITWIDTH];
    assign     pc_mem         = inst_mem[RS_STARTPOINT_PC      +: BITWIDTH_FCL_PC_WIDTH];
    assign     microop_mem    = inst_mem[RS_STARTPOINT_MICROOP +: MICROOP_WIDTH        ];
    assign     imm_mem        = inst_mem[RS_STARTPOINT_IMM     +: INST_IMM_WIDTH       ];
    assign     rd_num_mem     = inst_mem[RS_STARTPOINT_RD      +: BITWIDTH_PHYREG_NUM  ];
    assign     rs1_num_mem    = inst_mem[RS_STARTPOINT_RS1     +: BITWIDTH_PHYREG_NUM  ];
    assign     rs2_num_mem    = inst_mem[RS_STARTPOINT_RS2     +: BITWIDTH_PHYREG_NUM  ];

    branch_ex #(
        .EX_PATH_NUM                  (EX_PATH_NUM),
        .INST_OPREANDS                (INST_OPREANDS),
        .MICROOP_WIDTH                (MICROOP_WIDTH),
        .PHYREG_NUM                   (PHYREG_NUM),
        .FCL_RB_NUM                   (FCL_RB_NUM),
        .INST_PC_WIDTH                (INST_PC_WIDTH)
    ) U_EX_BRANCH (
    	.run_i                        (run_branch),
    	.microop_i                    (microop_branch),
    	.rs1_i                        (rs1_branch),
    	.rs2_i                        (rs2_branch),
    	.imm_i                        (imm_branch),
    	.pc_i                         (pc_branch),
    	.new_pc_o                     (new_pc),
    	.return_pc_o                  (rd_value_branch),
    	.we_o                         (we_branch),
    	.branch_o                     (en_branch),
    	.done_o                       (done_branch)
    );

    alu_ex #(
        .EX_PATH_NUM                  (EX_PATH_NUM),
        .INST_OPREANDS                (INST_OPREANDS),
        .MICROOP_WIDTH                (MICROOP_WIDTH),
        .PHYREG_NUM                   (PHYREG_NUM)
    ) U_EX_ALU0 (
    	.run_i                        (run_alu),
    	.microop_i                    (microop_alu),
    	.rs1_i                        (rs1_alu),
    	.rs2_i                        (rs2_alu),
    	.imm_i                        (imm_alu),
    	.alu_result_o                 (result_alu),
    	.we_o                         (we_alu),
    	.done_o                       (done_alu)
    );

    mem_ex #(
        .MICROOP_WIDTH                (MICROOP_WIDTH)
    ) U_EX_MEM0 (
        .clk                          (clk),
        .reset_n                      (reset_n),
    	.run_i                        (run_mem),
    	.microop_i                    (microop_mem),
    	.rs1_i                        (rs1_mem),
    	.rs2_i                        (rs2_mem),
    	.imm_i                        (imm_mem),
    	.rdata_proc_o                 (result_mem),
        .re_vmem_o                    (re_vmem_o),
        .we_vmem_o                    (we_vmem_o),
    	.addr_vmem_o                  (addr_vmem_o),
    	.strb_vmem_o                  (strb_vmem_o),
    	.rdata_vmem_i                 (rdata_vmem_i),
    	.wdata_vmem_o                 (wdata_vmem_o),
        .ready_vmem_i                 (ready_vmem_i),
    	.we_proc_o                    (we_mem),
    	.done_o                       (done_mem)
    );

    regfile #(
        .READ_CHANNEL                 (EX_PATH_NUM*INST_OPREANDS),
        .WRITE_CHANNEL                (EX_PATH_NUM),
        .ENTRIES                      (PHYREG_NUM),
        .REG_WIDTH                    (32)
    ) U_EX_PHYREG_RF (
        .clk                          (clk),
        .reset_n                      (reset_n),
        .i_read_addresses             ({rs2_num_mem, rs1_num_mem, rs2_num_alu, rs1_num_alu, rs2_num_branch, rs1_num_branch}),
        .i_write_wes                  ({we_mem, we_alu, we_branch}),
        .i_write_addresses            ({rd_num_mem, rd_num_alu, rd_num_branch}),
        .i_write_data                 ({result_mem, result_alu, rd_value_branch}),
        .o_read_data                  ({rs2_mem, rs1_mem, rs2_alu, rs1_alu, rs2_branch, rs1_branch})
    );

    // EX Section End =====================================================

    write_back_concatenation #(
        .DECODE_NEW_INST               (DECODE_NEW_INST),
        .PHYREG_NUM                    (PHYREG_NUM),
        .IST_ENTRY_NUM                 (IST_ENTRY_NUM),
        .EX_PATH_NUM                   (EX_PATH_NUM),
        .PRM_ENTRY_BUFFER              (PRM_ENTRY_BUFFER),
        .RS_ENTRY_NUM                  (RS_ENTRY_NUM),
        .RS_PUSH_WIDTH                 (RS_PUSH_WIDTH),
        .INST_PC_WIDTH                 (INST_PC_WIDTH),
        .INST_BITWIDTH                 (INST_BITWIDTH),
        .INST_OPCODE_WIDTH             (INST_OPCODE_WIDTH),
        .INST_OPTIONAL_OPCODE_WIDTH    (INST_OPTIONAL_OPCODE_WIDTH),
        .INST_IMM_WIDTH                (INST_IMM_WIDTH),
        .INST_NUM_OF_LOGICAL_REGISTER  (INST_NUM_OF_LOGICAL_REGISTER),
        .INST_OPREANDS                 (INST_OPREANDS),
        .MICROOP_WIDTH                 (MICROOP_WIDTH)
    ) U_WBC (
        .clk                           (clk),
        .reset_n                       (reset_n),
        .i_ex_done                     (done_all_ex),
        .i_ex_done_pc                  ({pc_mem, pc_alu, pc_branch}),
        .i_ex_done_branch              (en_branch),
        .i_ex_done_branch_pc           (new_pc),
        .i_ex_done_phyreg              ({rd_num_mem, rd_num_alu, rd_num_branch}),
        .o_wbc2prm_done                (wb_done),
        .o_wbc2prm_done_phyreg         (wb_done_phyreg),
        .o_wbc2nel_done                (wbc2nel_done),
        .o_wbc2nel_done_phyreg         (wbc2nel_done_phyreg),
        .o_wbc2fcl_done                (wbc2fcl_done),
        .o_wbc2fcl_pc                  (wbc2fcl_pc),
        .o_wbc2fcl_branch              (wbc2fcl_branch),
        .o_wbc2fcl_branch_pc           (wbc2fcl_branch_pc)
    );

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
    ) U_FCL (
        .clk                           (clk),
        .reset_n                       (reset_n),
        .i_im_inst_get                 (o_im_inst_get),
        .i_nel_block                   (nel_block),
        .i_nel_jump_inst               (nel_jump_inst),
        .i_nel_jreg_branch_inst        (nel_jreg_branch_inst),
        .i_nel_jump_branch_pc          (nel_jump_branch_pc),
        .i_nel_newpc_valid             (nel_newpc_valid),
        .i_nel_newpc                   (nel_newpc),
        .i_nel_lastreg_valid           (nel_lastreg_valid),
        .i_nel_lastreg                 (nel_lastreg),
        .o_prm_unallocate_valid        (prm_unallocate_valid),
        .o_prm_unallocate_phyreg       (prm_unallocate_phyreg),
        .i_wbc2fcl_done                (wbc2fcl_done),
        .i_wbc2fcl_pc                  (wbc2fcl_pc),
        .i_wbc2fcl_branch              (wbc2fcl_branch),
        .i_wbc2fcl_branch_pc           (wbc2fcl_branch_pc),
        .i_im_inst_valid               (i_im_inst_valid),
        .o_im_re                       (o_im_re),
        .o_im_pc                       (fcl_inst_pc)
    );

endmodule
