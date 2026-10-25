 `timescale 1ns / 1ps

//`include "../memories.sv"

// NEW ENTRY LOGIC

module rv32i_decode_opcode #(
    parameter EX_PATH_NUM           = 3,
    parameter INST_OPREANDS         = 2,
    parameter MICROOP_WIDTH         = 5, // Micro-OP is not contained information of EX_PATH

    // (Autogenerate) Elements
    localparam BITWIDTH_EX_PATH_NUM = $clog2(EX_PATH_NUM)
) (
    input  wire [31:0]              inst_i,
    output reg                      exception_o,
    output reg                      newreg_alloc_o,
    output reg                      jump_o,
    output reg                      jump_reg_o,
    output reg                      branch_o,
    output reg  [INST_OPREANDS-1:0] ready_o,
    output reg  [BITWIDTH_EX_PATH_NUM-1:0] expath_o,
    output reg  [MICROOP_WIDTH-1:0] microop_o
);
    /*
    ==( Opcode, funct3/7 -> MicroOp )==
      
      [EX Channel 1: Branch, Jump Reg]
       - Branch Equal
       - Branch Not Equal
       - Branch Less Than (Signed)
       - Branch Less Than (Unsigned)
       - Branch Greater Equal (Signed)
       - Branch Greater Equal (Unsigned)
       - Jump Reg (Other Jump instrunction Process in Flow Control Logic and New Entry Logic)
      [EX Channel 2: ALU Reg/IMM]
       - ADD
       - SUB
       - SLL
       - SLT
       - SLTU
       - XOR
       - SRL
       - SRA
       - OR
       - AND
       - (IMM) ADD
       - (IMM) SLL
       - (IMM) SLT
       - (IMM) SLTU
       - (IMM) XOR
       - (IMM) SRL
       - (IMM) SRA
       - (IMM) OR
       - (IMM) AND
       - LUI
       - AUIPC
       - JUMP IMM
      [EX Channel 3: Memory Access]
       - LB
       - LH
       - LW
       - LBU
       - LHU
       - SB
       - SH
       - SW

    ===================================
    */

    always @(*) begin : Decoding
        case(inst_i[6:0])
            7'b1100011: begin // EX 1: Branch
                exception_o = 1'b0;
                newreg_alloc_o = 1'b0;
                jump_o = 1'b0;
                jump_reg_o = 1'b0;
                branch_o = 1'b1;
                ready_o = 2'b00;
                expath_o = 2'b00;
                microop_o = {2'b00, inst_i[14:12]};
            end
            7'b1100111: begin // EX 1: Jump Reg
                exception_o = 1'b0;
                newreg_alloc_o = 1'b1;
                jump_o = 1'b0;
                jump_reg_o = 1'b1;
                branch_o = 1'b0;
                ready_o = 2'b10;
                expath_o = 2'b00;
                microop_o = 5'b01000;
            end
            
            7'b0110011: begin // EX 2: ALU Reg
                exception_o = 1'b0;
                newreg_alloc_o = 1'b1;
                jump_o = 1'b0;
                jump_reg_o = 1'b0;
                branch_o = 1'b0;
                ready_o = 2'b00;
                expath_o = 2'b01;
                microop_o = {1'b0, inst_i[30], inst_i[14:12]};
            end
            7'b0010011: begin // EX 2: ALU IMM
                exception_o = 1'b0;
                newreg_alloc_o = 1'b1;
                jump_o = 1'b0;
                jump_reg_o = 1'b0;
                branch_o = 1'b0;
                ready_o = 2'b10;
                expath_o = 2'b01;
                microop_o = 
                    {1'b1, (inst_i[14:12] == 3'b101)? inst_i[30] : 1'b0, inst_i[14:12]};
            end
            7'b0110111: begin // EX 2: LUI
                exception_o = 1'b0;
                newreg_alloc_o = 1'b1;
                jump_o = 1'b0;
                jump_reg_o = 1'b0;
                branch_o = 1'b0;
                ready_o = 2'b11;
                expath_o = 2'b01;
                microop_o = 5'b11000;
            end
            7'b0010111: begin // EX 2: AUIPC
                exception_o = 1'b0;
                newreg_alloc_o = 1'b1;
                jump_o = 1'b0;
                jump_reg_o = 1'b0;
                branch_o = 1'b0;
                ready_o = 2'b11;
                expath_o = 2'b00;
                microop_o = 5'b11001;
            end
            7'b1101111: begin // EX 2: JAL
                exception_o = 1'b0;
                newreg_alloc_o = 1'b1;
                jump_o = 1'b1;
                jump_reg_o = 1'b0;
                branch_o = 1'b0;
                ready_o = 2'b11;
                expath_o = 2'b00;
                microop_o = 5'b11010;
            end

            7'b0000011: begin // EX 3: Memory Access Load
                exception_o = 1'b0;
                newreg_alloc_o = 1'b1;
                jump_o = 1'b0;
                jump_reg_o = 1'b0;
                branch_o = 1'b0;
                ready_o = 2'b10;
                expath_o = 2'b10;
                microop_o = {2'b00, inst_i[14:12]};
            end
            7'b0100011: begin // EX 3: Memory Access Store
                exception_o = 1'b0;
                newreg_alloc_o = 1'b0;
                jump_o = 1'b0;
                jump_reg_o = 1'b0;
                branch_o = 1'b0;
                ready_o = 2'b00;
                expath_o = 2'b10;
                microop_o = {2'b10, inst_i[14:12]};
            end

            default: begin
                exception_o = 1'b1;
                newreg_alloc_o = 1'b1;
                jump_o = 1'b0;
                jump_reg_o = 1'b0;
                branch_o = 1'b0;
                ready_o = 2'b11;
                expath_o = 2'b11;
                microop_o = 5'b00000;
            end
        endcase
    end
endmodule

module imm_extender (
	input  wire [31:0] inst_i,
	output reg  [31:0] imm_o
);

	always @(*) begin : Decode_AND_Create_IMM
		imm_o = 0;

		case(inst_i[6:0])
			7'b0100011 : imm_o = { {20{inst_i[31]}}, inst_i[31:25], inst_i[11:7] };
			7'b0000011, 7'b0010011, 7'b1100111 : imm_o = { {20{inst_i[31]}}, inst_i[31:20] };
			7'b1100011 : imm_o = { {20{inst_i[31]}}, inst_i[7], inst_i[30:25], inst_i[11:8], 1'b0 };
			7'b0110111, 7'b0010111 : imm_o = { inst_i[31:12], {12{1'b0}} };
			7'b1101111: imm_o = { {12{inst_i[31]}}, inst_i[19:12], inst_i[20], inst_i[30:21], 1'b0 };
		endcase
	end

endmodule

module rv32i_get_registers (
	input  wire [31:0] inst_i,
	output reg  [4:0]  rd_o,
	output reg  [4:0]  rs1_o,
	output reg  [4:0]  rs2_o
);
    assign rd_o  = inst_i[11:7];
    assign rs1_o = inst_i[19:15];
    assign rs2_o = inst_i[24:20];
    always @(*) begin : Decoding
        case(inst_i[6:0])
            7'b1100011: begin // EX 1: Branch
                rd_o  = 0;
                rs1_o = inst_i[19:15];
                rs2_o = inst_i[24:20];
            end
            7'b1100111: begin // EX 1: Jump Reg
                rd_o  = inst_i[11:7];
                rs1_o = inst_i[19:15];
                rs2_o = 0;
            end
            
            7'b0110011: begin // EX 2: ALU Reg
                rd_o  = inst_i[11:7];
                rs1_o = inst_i[19:15];
                rs2_o = inst_i[24:20];
            end
            7'b0010011: begin // EX 2: ALU IMM
                rd_o  = inst_i[11:7];
                rs1_o = inst_i[19:15];
                rs2_o = 0;
            end
            7'b0110111: begin // EX 2: LUI
                rd_o  = inst_i[11:7];
                rs1_o = inst_i[19:15];
                rs2_o = inst_i[24:20];
            end
            7'b0010111: begin // EX 2: AUIPC
                rd_o  = inst_i[11:7];
                rs1_o = inst_i[19:15];
                rs2_o = inst_i[24:20];
            end
            7'b1101111: begin // EX 2: JAL
                rd_o  = inst_i[11:7];
                rs1_o = inst_i[19:15];
                rs2_o = inst_i[24:20];
            end

            7'b0000011: begin // EX 3: Memory Access Load
                rd_o  = inst_i[11:7];
                rs1_o = inst_i[19:15];
                rs2_o = 0;
            end
            7'b0100011: begin // EX 3: Memory Access Store
                rd_o  = 0;
                rs1_o = inst_i[19:15];
                rs2_o = inst_i[24:20];
            end

            default: begin
                rd_o  = inst_i[11:7];
                rs1_o = inst_i[19:15];
                rs2_o = inst_i[24:20];
            end
        endcase
    end
endmodule

module new_entry_logic #(
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
    parameter MICROOP_WIDTH                 = 7, // Micro-OP is not contained information of EX_PATH

    // (Autogenerate) Elements
    localparam BITWIDTH_EX_PATH_NUM                     = $clog2(EX_PATH_NUM),
    localparam BITWIDTH_PHYREG_NUM                      = $clog2(PHYREG_NUM),
    localparam BITWIDTH_IST_ENTRY_NUM                   = $clog2(IST_ENTRY_NUM),
    localparam BITWIDTH_INST_NUM_OF_LOGICAL_REGISTER    = $clog2(INST_NUM_OF_LOGICAL_REGISTER),
    localparam BITWIDTH_FCL_RB_NUM                      = $clog2(FCL_RB_NUM),

    localparam BITWIDTH_FCL_PC_WIDTH                    = BITWIDTH_FCL_RB_NUM + INST_PC_WIDTH,

    // (Autogenerate) Field of Entry in Instruction State Table
        /* Entry: MSB [ ( Opreand Reday_n, ... , Opreand Reday_1 ) | 
                        ( Opreand Rename Register_n, ... , Opreand Rename Register_1 ) | 
                        Destination Rename Register | 
                        IMM | Micro-OP | EX_PATH | PC ] LSB */    
    localparam IST_BITWIDTH_OPREAND_PHYREG_FULL = BITWIDTH_PHYREG_NUM * INST_OPREANDS,
    localparam IST_BITWIDTH_OPREAND_READY_FULL  = INST_OPREANDS,
    localparam IST_BITWIDTH = BITWIDTH_FCL_PC_WIDTH + BITWIDTH_EX_PATH_NUM + MICROOP_WIDTH + INST_IMM_WIDTH + BITWIDTH_PHYREG_NUM
                              + IST_BITWIDTH_OPREAND_PHYREG_FULL + IST_BITWIDTH_OPREAND_READY_FULL,

    localparam IST_STARTPOINT_PHYREG            = BITWIDTH_FCL_PC_WIDTH + BITWIDTH_EX_PATH_NUM + MICROOP_WIDTH + INST_IMM_WIDTH,
    localparam IST_STARTPOINT_OPREAND_PHYREG    = IST_STARTPOINT_PHYREG + BITWIDTH_PHYREG_NUM,
    localparam IST_STARTPOINT_OPREAND_READY     = IST_STARTPOINT_OPREAND_PHYREG + IST_BITWIDTH_OPREAND_PHYREG_FULL,

    localparam IST_PACKET_BITWIDTH              = IST_BITWIDTH * DECODE_NEW_INST,

    // (Autogenerate) Field of Allocator in Instruction State Table
    localparam IST_ALLOCATE_BITWIDTH = BITWIDTH_IST_ENTRY_NUM * DECODE_NEW_INST,
    
    // (Autogenerate) Field of Allocator in Physical Register Manager
    localparam PRM_ALLOCATE_BITWIDTH        = BITWIDTH_PHYREG_NUM * DECODE_NEW_INST,

    // (Autogenerate) Width of Instructions
    localparam INST_INPUT_BITWIDTH          = INST_BITWIDTH * DECODE_NEW_INST,

    // (Autogenerate) Write Back Field
    localparam WB_PHYREGS_BITWIDTH          = BITWIDTH_PHYREG_NUM * EX_PATH_NUM

) (
    input                                       clk,
    input                                       reset_n,

    // Instruction Memory
        // <- New Inst Input
    input  wire [DECODE_NEW_INST-1:0]                         i_im_inst_valid,
    input  wire [(DECODE_NEW_INST*BITWIDTH_FCL_PC_WIDTH)-1:0] i_im_inst_pc,
    input  wire [(DECODE_NEW_INST*INST_BITWIDTH)-1:0]         i_im_inst,
    output reg  [DECODE_NEW_INST-1:0]                         o_im_inst_get,

    // Create IST Field
        // -> Instruction State Table Update
    input  wire                                         i_ist_insert_available,
    output reg  [DECODE_NEW_INST-1:0]                   o_ist_field_insert,
    input  wire [DECODE_NEW_INST-1:0]                   i_ist_field_valid,
    output reg  [IST_PACKET_BITWIDTH-1:0]               o_ist_field,

    // PRM
    output wire [DECODE_NEW_INST-1:0]                   o_allocate_position,
    input  wire                                         i_prm_active,
        // <- Physical Register Manager Allocator
    input  wire [DECODE_NEW_INST-1:0]                   i_prm_allocate_valid,
    input  wire [PRM_ALLOCATE_BITWIDTH-1:0]             i_prm_allocate_phyreg,
    
    // WBC
        // <- Ready Register number
    input  wire [EX_PATH_NUM-1:0]                       i_wbc2nel_done,
    input  wire [(EX_PATH_NUM*BITWIDTH_PHYREG_NUM)-1:0] i_wbc2nel_done_phyreg,

    // flow control Logic
        // <- Block
    output wire                                               o_nel_block,
        // <- Jump Instruction Input
    output reg                                                o_nel_jump_inst,
    output reg                                                o_nel_jreg_branch_inst,
    output reg  [INST_PC_WIDTH-1:0]                           o_nel_jump_branch_pc,
        // <- Allocate Registers input
    output wire [DECODE_NEW_INST-1:0]                         o_nel_newpc_valid,
    output wire [(BITWIDTH_FCL_PC_WIDTH*DECODE_NEW_INST)-1:0] o_nel_newpc,
    output wire [DECODE_NEW_INST-1:0]                         o_nel_lastreg_valid,
    output wire [(BITWIDTH_PHYREG_NUM*DECODE_NEW_INST)-1:0]   o_nel_lastreg
);

    // Stage1: Decoding Section
    wire [BITWIDTH_INST_NUM_OF_LOGICAL_REGISTER-1:0] rd          [0:DECODE_NEW_INST-1];
    wire [BITWIDTH_INST_NUM_OF_LOGICAL_REGISTER-1:0] rs          [0:DECODE_NEW_INST-1][0:INST_OPREANDS-1];
    wire                                    exception   [0:DECODE_NEW_INST-1];
    wire                                    newreg_alloc[0:DECODE_NEW_INST-1];
    wire                                    jump        [0:DECODE_NEW_INST-1];
    wire                                    jump_reg    [0:DECODE_NEW_INST-1];
    wire                                    branch      [0:DECODE_NEW_INST-1];
    wire [INST_OPREANDS-1:0]                ready       [0:DECODE_NEW_INST-1];
    wire [BITWIDTH_EX_PATH_NUM-1:0]         expath      [0:DECODE_NEW_INST-1];
    wire [MICROOP_WIDTH-1:0]                microop     [0:DECODE_NEW_INST-1];
    wire [31:0]                             imm         [0:DECODE_NEW_INST-1];

    wire [(DECODE_NEW_INST*BITWIDTH_PHYREG_NUM)-1:0]               past_log_phy_reg;
    wire [(DECODE_NEW_INST*INST_OPREANDS*BITWIDTH_PHYREG_NUM)-1:0] opreands_log_phy;

    reg  [(DECODE_NEW_INST*BITWIDTH_INST_NUM_OF_LOGICAL_REGISTER)-1:0]               rd_spread;
    reg  [(DECODE_NEW_INST*INST_OPREANDS*BITWIDTH_INST_NUM_OF_LOGICAL_REGISTER)-1:0] rs_spread;
    reg  [DECODE_NEW_INST-1:0]                                              newreg_alloc_spread;
    reg  [DECODE_NEW_INST-1:0]                                              im_inst_get;

    // Register Variables
    reg                                           active                [0:DECODE_NEW_INST-1];
    reg                                           active_next           [0:DECODE_NEW_INST-1];
    reg [BITWIDTH_FCL_PC_WIDTH-1:0]               pc_reg                [0:DECODE_NEW_INST-1];
    reg [BITWIDTH_FCL_PC_WIDTH-1:0]               pc_new                [0:DECODE_NEW_INST-1];
    reg [BITWIDTH_EX_PATH_NUM-1:0]                expath_reg            [0:DECODE_NEW_INST-1];
    reg [BITWIDTH_EX_PATH_NUM-1:0]                expath_new            [0:DECODE_NEW_INST-1];
    reg [MICROOP_WIDTH-1:0]                       microop_reg           [0:DECODE_NEW_INST-1];
    reg [MICROOP_WIDTH-1:0]                       microop_new           [0:DECODE_NEW_INST-1];
    reg [INST_IMM_WIDTH-1:0]                      imm_reg               [0:DECODE_NEW_INST-1];
    reg [INST_IMM_WIDTH-1:0]                      imm_new               [0:DECODE_NEW_INST-1];
    reg [BITWIDTH_PHYREG_NUM-1:0]                 new_log_phy_reg       [0:DECODE_NEW_INST-1];
    reg [BITWIDTH_PHYREG_NUM-1:0]                 new_log_phy_next      [0:DECODE_NEW_INST-1];
    reg [(INST_OPREANDS*BITWIDTH_PHYREG_NUM)-1:0] opreands_log_phy_reg  [0:DECODE_NEW_INST-1];
    reg [(INST_OPREANDS*BITWIDTH_PHYREG_NUM)-1:0] opreands_log_phy_next [0:DECODE_NEW_INST-1];
    reg [INST_OPREANDS-1:0]                       opreands_ready_reg    [0:DECODE_NEW_INST-1];
    reg [INST_OPREANDS-1:0]                       opreands_ready_next   [0:DECODE_NEW_INST-1];

    integer reg_new_entry_idx, new_entry_idx, opreand_idx;
    always @(posedge clk or negedge reset_n) begin
        for(reg_new_entry_idx = 0; reg_new_entry_idx < DECODE_NEW_INST; reg_new_entry_idx = reg_new_entry_idx+1) begin
            if (!reset_n) begin
                active               [reg_new_entry_idx] <= 1'b0; 
                pc_reg               [reg_new_entry_idx] <= 0;
                expath_reg           [reg_new_entry_idx] <= 0;
                microop_reg          [reg_new_entry_idx] <= 0;
                imm_reg              [reg_new_entry_idx] <= 0;
                new_log_phy_reg      [reg_new_entry_idx] <= 0; 
                opreands_log_phy_reg [reg_new_entry_idx] <= 0;
                opreands_ready_reg   [reg_new_entry_idx] <= 0;
            end
            else begin
                active               [reg_new_entry_idx] <= active_next           [reg_new_entry_idx]; 
                pc_reg               [reg_new_entry_idx] <= pc_new                [reg_new_entry_idx];
                expath_reg           [reg_new_entry_idx] <= expath_new            [reg_new_entry_idx];
                microop_reg          [reg_new_entry_idx] <= microop_new           [reg_new_entry_idx];
                imm_reg              [reg_new_entry_idx] <= imm_new               [reg_new_entry_idx];
                new_log_phy_reg      [reg_new_entry_idx] <= new_log_phy_next      [reg_new_entry_idx];
                opreands_log_phy_reg [reg_new_entry_idx] <= opreands_log_phy_next [reg_new_entry_idx];
                opreands_ready_reg   [reg_new_entry_idx] <= opreands_ready_next   [reg_new_entry_idx];
            end
        end
    end
    always @(*) begin
        for(new_entry_idx = 0; new_entry_idx < DECODE_NEW_INST; new_entry_idx = new_entry_idx+1) begin
            rd_spread[(BITWIDTH_INST_NUM_OF_LOGICAL_REGISTER*new_entry_idx) +: BITWIDTH_INST_NUM_OF_LOGICAL_REGISTER]
                = (newreg_alloc[new_entry_idx])? rd[new_entry_idx] : 0;

            for (opreand_idx = 0; opreand_idx < INST_OPREANDS; opreand_idx = opreand_idx+1) begin
                rs_spread[( BITWIDTH_INST_NUM_OF_LOGICAL_REGISTER * ((new_entry_idx*INST_OPREANDS) + opreand_idx) ) 
                            +: BITWIDTH_INST_NUM_OF_LOGICAL_REGISTER] = rs[new_entry_idx][opreand_idx];
            end

            if (rd[new_entry_idx] != 0)
                newreg_alloc_spread[new_entry_idx] = newreg_alloc[new_entry_idx];
            else
                newreg_alloc_spread[new_entry_idx] = 0;
        end

        for(new_entry_idx = 0; new_entry_idx < DECODE_NEW_INST; new_entry_idx = new_entry_idx+1) begin
            o_nel_jump_inst        = i_im_inst_valid & o_im_inst_get & jump[new_entry_idx];
            o_nel_jreg_branch_inst = i_im_inst_valid & o_im_inst_get & (jump_reg[new_entry_idx] | branch[new_entry_idx]);
            o_nel_jump_branch_pc   
                = i_im_inst_pc[(BITWIDTH_FCL_PC_WIDTH*new_entry_idx) +: INST_PC_WIDTH]+imm[new_entry_idx];

            if (jump[new_entry_idx] || jump_reg[new_entry_idx] || branch[new_entry_idx]) break;
        end

        im_inst_get = i_prm_allocate_valid & newreg_alloc_spread;
        im_inst_get |= ~newreg_alloc_spread;
        o_im_inst_get = 0;
        if (i_prm_active & i_ist_insert_available) begin
            for(new_entry_idx = 0; new_entry_idx < DECODE_NEW_INST; new_entry_idx = new_entry_idx+1) begin
                o_im_inst_get[new_entry_idx] = im_inst_get[new_entry_idx];
                if (!im_inst_get[new_entry_idx]) break;
            end
        end

        if (i_prm_active) begin
            for(new_entry_idx = 0; new_entry_idx < DECODE_NEW_INST; new_entry_idx = new_entry_idx+1) begin
                active_next[new_entry_idx] = i_im_inst_valid[new_entry_idx];
                pc_new[new_entry_idx]      = i_im_inst_pc[(BITWIDTH_FCL_PC_WIDTH*new_entry_idx) +: BITWIDTH_FCL_PC_WIDTH];
                expath_new[new_entry_idx]  = expath[new_entry_idx];
                microop_new[new_entry_idx] = microop[new_entry_idx];
                imm_new[new_entry_idx]     = imm[new_entry_idx];
                new_log_phy_next[new_entry_idx] = 0;
                if (newreg_alloc[new_entry_idx]) begin
                    new_log_phy_next[new_entry_idx] 
                        = i_prm_allocate_phyreg[(BITWIDTH_PHYREG_NUM*new_entry_idx) +: BITWIDTH_PHYREG_NUM];
                end
                opreands_log_phy_next[new_entry_idx] 
                    = opreands_log_phy[((INST_OPREANDS*BITWIDTH_PHYREG_NUM)*new_entry_idx) +: (INST_OPREANDS*BITWIDTH_PHYREG_NUM)];

                for (opreand_idx = 0; opreand_idx < INST_OPREANDS; opreand_idx = opreand_idx+1) begin
                    if (rs[new_entry_idx][opreand_idx] == 0)
                        opreands_ready_next[new_entry_idx][opreand_idx] = 1'b1;
                    else
                        opreands_ready_next[new_entry_idx][opreand_idx] = ready[new_entry_idx][opreand_idx];
                end
            end
        end
        else begin
            for(new_entry_idx = 0; new_entry_idx < DECODE_NEW_INST; new_entry_idx = new_entry_idx+1) begin
                active_next           [new_entry_idx] = active               [new_entry_idx]; 
                pc_new                [new_entry_idx] = pc_reg               [new_entry_idx];
                expath_new            [new_entry_idx] = expath_reg           [new_entry_idx];
                microop_new           [new_entry_idx] = microop_reg          [new_entry_idx];
                imm_new               [new_entry_idx] = imm_reg              [new_entry_idx];
                new_log_phy_next      [new_entry_idx] = new_log_phy_reg      [new_entry_idx];
                opreands_log_phy_next [new_entry_idx] = opreands_log_phy_reg [new_entry_idx];
                opreands_ready_next   [new_entry_idx] = opreands_ready_reg   [new_entry_idx];
            end
        end
    end
    assign o_nel_newpc_valid   = i_im_inst_valid & o_im_inst_get;
    assign o_nel_newpc         = i_im_inst_pc;
    assign o_nel_lastreg_valid = i_im_inst_valid & o_im_inst_get & newreg_alloc_spread;
    assign o_nel_lastreg       = past_log_phy_reg;
    assign o_allocate_position = i_im_inst_valid & o_im_inst_get & newreg_alloc_spread;
    assign o_nel_block         = ~i_ist_insert_available | ~i_prm_active;
        // 이번 버전은 모든 필드가 열린 상태에서만..

    // Stage2: Output Section
    wire [(DECODE_NEW_INST*INST_OPREANDS)-1:0] opreands_phy_ready;
    reg  [INST_OPREANDS-1:0]                   opreands_ready_final, opreands_ready_now;
    reg  [(DECODE_NEW_INST*INST_OPREANDS*BITWIDTH_PHYREG_NUM)-1:0] opreands_log_phy_reg_spread;
    integer ist_field_insert_idx, done_idx, opreands_ready_idx;
    always @(*) begin
        for (ist_field_insert_idx = 0; ist_field_insert_idx < DECODE_NEW_INST; ist_field_insert_idx = ist_field_insert_idx+1) begin
            o_ist_field_insert[ist_field_insert_idx] = active[ist_field_insert_idx];

            opreands_ready_now = 0;
            for (done_idx = 0; done_idx < EX_PATH_NUM; done_idx = done_idx+1) begin
                for (opreands_ready_idx = 0; opreands_ready_idx < INST_OPREANDS; opreands_ready_idx = opreands_ready_idx+1) begin
                    if ( opreands_log_phy_reg[ist_field_insert_idx][(BITWIDTH_PHYREG_NUM*opreands_ready_idx) +: BITWIDTH_PHYREG_NUM] 
                         == i_wbc2nel_done_phyreg[(BITWIDTH_PHYREG_NUM *opreands_ready_idx) +: BITWIDTH_PHYREG_NUM] ) begin
                            opreands_ready_now[opreands_ready_idx] = (i_wbc2nel_done[done_idx])? 1'b1 : 1'b0;
                         end
                end
            end

            opreands_ready_final = opreands_ready_reg[ist_field_insert_idx] | opreands_phy_ready[(INST_OPREANDS*ist_field_insert_idx) +: INST_OPREANDS] | opreands_ready_now[ist_field_insert_idx];

            o_ist_field[(IST_BITWIDTH*ist_field_insert_idx) +: IST_BITWIDTH]
                = { opreands_ready_final,                  opreands_log_phy_reg[ist_field_insert_idx],
                    new_log_phy_reg[ist_field_insert_idx], imm_reg[ist_field_insert_idx],
                    microop_reg[ist_field_insert_idx], expath_reg[ist_field_insert_idx], pc_reg[ist_field_insert_idx] };

            opreands_log_phy_reg_spread[((INST_OPREANDS*BITWIDTH_PHYREG_NUM)*ist_field_insert_idx) +: (INST_OPREANDS*BITWIDTH_PHYREG_NUM)]
                = opreands_log_phy_reg[ist_field_insert_idx];
        end
        if (~i_prm_active) o_ist_field_insert= 0;
    end

    genvar decoder_idx;
    generate
        for (decoder_idx = 0; decoder_idx < DECODE_NEW_INST; decoder_idx = decoder_idx+1) begin
            // instance decoder, register catcher, imm extender HERE
            rv32i_decode_opcode #(
                .EX_PATH_NUM  (EX_PATH_NUM),
                .INST_OPREANDS(INST_OPREANDS),
                .MICROOP_WIDTH(MICROOP_WIDTH)
            ) U_DECODER (
                .inst_i         (i_im_inst[(INST_BITWIDTH*decoder_idx) +: INST_BITWIDTH]),
                .exception_o    (exception[decoder_idx]), 
                .newreg_alloc_o (newreg_alloc[decoder_idx]),
                .jump_o         (jump[decoder_idx]),
                .jump_reg_o     (jump_reg[decoder_idx]),
                .branch_o       (branch[decoder_idx]),
                .ready_o        (ready[decoder_idx]),
                .expath_o       (expath[decoder_idx]),
                .microop_o      (microop[decoder_idx])
            );
            
            rv32i_get_registers U_REGISTER_GET (
            	.inst_i (i_im_inst[(INST_BITWIDTH*decoder_idx) +: INST_BITWIDTH]),
            	.rd_o   (rd[decoder_idx]),
            	.rs1_o  (rs[decoder_idx][0]),
            	.rs2_o  (rs[decoder_idx][1])
            );

            imm_extender U_IMM_EXT (
        	    .inst_i         (i_im_inst[(INST_BITWIDTH*decoder_idx) +: INST_BITWIDTH]),
        	    .imm_o          (imm[decoder_idx])
            );
        end
    endgenerate

    reg [DECODE_NEW_INST-1:0] map_log_phy_wes;
    integer rd_idx;
    always @(*) begin
        for(rd_idx = 0; rd_idx < DECODE_NEW_INST; rd_idx = rd_idx+1) begin
            if (rd[rd_idx] == 0) begin
                map_log_phy_wes[rd_idx] = 0;
            end
            else begin
                map_log_phy_wes[rd_idx] = o_im_inst_get & i_im_inst_valid & newreg_alloc[rd_idx];
            end
        end
    end

    regfile #(
        .READ_CHANNEL  (DECODE_NEW_INST+(DECODE_NEW_INST*INST_OPREANDS)),
        .WRITE_CHANNEL (DECODE_NEW_INST),
        .ENTRIES       (INST_NUM_OF_LOGICAL_REGISTER),
        .REG_WIDTH     (BITWIDTH_PHYREG_NUM)
    ) U_LOGICREG_PHYREG_MAP (
        .clk                 (clk),
        .reset_n             (reset_n),
        .i_read_addresses    ({rd_spread, rs_spread}),
        .i_write_wes         (map_log_phy_wes),
        .i_write_addresses   (rd_spread),
        .i_write_data        (i_prm_allocate_phyreg),
        .o_read_data         ({past_log_phy_reg, opreands_log_phy})
    );

    regfile_init_1 #(
        .READ_CHANNEL  (DECODE_NEW_INST*INST_OPREANDS),
        .WRITE_CHANNEL (EX_PATH_NUM+DECODE_NEW_INST),
        .ENTRIES       (PHYREG_NUM),
        .REG_WIDTH     (1)
    ) U_PHYREG_READY (
        .clk                 (clk),
        .reset_n             (reset_n),
        .i_read_addresses    (opreands_log_phy_reg_spread),
        .i_write_wes         ({i_wbc2nel_done, map_log_phy_wes}),
        .i_write_addresses   ({i_wbc2nel_done_phyreg, i_prm_allocate_phyreg}),
        .i_write_data        ({{EX_PATH_NUM{1'b1}}, {DECODE_NEW_INST{1'b0}}}),
        .o_read_data         (opreands_phy_ready)
    );

endmodule
