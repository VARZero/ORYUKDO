`timescale 1ns / 1ps

module new_entry_logic #(
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
    localparam int _BITWIDTH_LOW_IS_INST_REGS           = $clog2(IS_INST_REGS),

    localparam int _STRUCT_EX_OUT_RESULT_ALL            = STRUCT_EX_OUT_RESULT_SUM,

    // Composite bitwidths
    localparam int _BITWIDTH_CMB_FLOW_INDEXnPC          = _BITWIDTH_LOW_STRUCT_FLOW_WINDOWS + IS_INST_PC_BITWIDTH,

    // IST_READYINST_ENTRY_BITWIDTH: RS input packet width (contains EX Path)
    localparam int IST_READYINST_ENTRY_BITWIDTH         = _BITWIDTH_CMB_FLOW_INDEXnPC + 
                                                          _BITWIDTH_LOW_STRUCT_EX_PATH + 
                                                          EX_INST_MICROOP_BITWIDTH + 
                                                          IS_INST_IMM + 
                                                          _BITWIDTH_LOW_STRUCT_PHYREGS + 
                                                          (_BITWIDTH_LOW_STRUCT_PHYREGS * IS_INST_OPERANDS),

    // IST_BITWIDTH: IST internal register width (contains Ready flags)
    localparam int IST_BITWIDTH                         = IST_READYINST_ENTRY_BITWIDTH + IS_INST_OPERANDS,

    // PRM allocator bitwidth
    localparam int PRM_ALLOCATE_BITWIDTH                = _BITWIDTH_LOW_STRUCT_PHYREGS * STRUCT_DECODE_NEW_INST
) (
    input  wire                                                 clk,
    input  wire                                                 reset_n,

    // Instruction Memory Interface (i/o_im_inst_*)
    input  wire [STRUCT_DECODE_NEW_INST-1:0]                    i_im_inst_valid,
    input  wire [(STRUCT_DECODE_NEW_INST * _BITWIDTH_CMB_FLOW_INDEXnPC)-1:0] i_im_inst_pc,
    output reg  [STRUCT_DECODE_NEW_INST-1:0]                    o_im_inst_get,

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

    // IST Interface (i/o_nel_newinst_* / i_ist_field_*)
    input  wire                                                 i_ist_insert_available,
    output reg  [STRUCT_DECODE_NEW_INST-1:0]                    o_ist_field_insert,
    input  wire [STRUCT_DECODE_NEW_INST-1:0]                    i_ist_field_valid,
    output reg  [(STRUCT_DECODE_NEW_INST * IST_BITWIDTH)-1:0]   o_ist_field,

    // PRM Allocation Interface (i/o_prm_allocate_*)
    output wire [STRUCT_DECODE_NEW_INST-1:0]                    o_allocate_position,
    input  wire                                                 i_prm_active,
    input  wire [STRUCT_DECODE_NEW_INST-1:0]                    i_prm_allocate_valid,
    input  wire [PRM_ALLOCATE_BITWIDTH-1:0]                     i_prm_allocate_phyreg,
    
    // WBC Interface (i/o_wbc2nel_done_*)
    input  wire [_STRUCT_EX_OUT_RESULT_ALL-1:0]                  i_wbc2nel_done,
    input  wire [(_STRUCT_EX_OUT_RESULT_ALL * _BITWIDTH_LOW_STRUCT_PHYREGS)-1:0] i_wbc2nel_done_phyreg,

    // Flow Control Logic Block/Jump Interface (i/o_fcl_jump_branch_* / i_o_fcl_unallo_reg_*)
    output wire                                                 o_nel_block,
    output reg                                                  o_nel_jump_inst,
    output reg                                                  o_nel_jreg_branch_inst,
    output reg  [IS_INST_PC_BITWIDTH-1:0]                       o_nel_jump_branch_pc,
    output wire [STRUCT_DECODE_NEW_INST-1:0]                    o_nel_newpc_valid,
    output wire [(STRUCT_DECODE_NEW_INST * _BITWIDTH_CMB_FLOW_INDEXnPC)-1:0] o_nel_newpc,
    output wire [STRUCT_DECODE_NEW_INST-1:0]                    o_nel_lastreg_valid,
    output wire [(STRUCT_DECODE_NEW_INST * _BITWIDTH_LOW_STRUCT_PHYREGS)-1:0] o_nel_lastreg
);

    // -------------------------------------------------------------------------
    // Wires to connect decoded inputs to NEL internal logic
    // -------------------------------------------------------------------------
    wire [_BITWIDTH_LOW_IS_INST_REGS-1:0]                       rd          [0:STRUCT_DECODE_NEW_INST-1];
    wire [_BITWIDTH_LOW_IS_INST_REGS-1:0]                       rs          [0:STRUCT_DECODE_NEW_INST-1][0:IS_INST_OPERANDS-1];
    wire                                                        exception   [0:STRUCT_DECODE_NEW_INST-1];
    wire                                                        newreg_alloc[0:STRUCT_DECODE_NEW_INST-1];
    wire                                                        jump        [0:STRUCT_DECODE_NEW_INST-1];
    wire                                                        jump_reg    [0:STRUCT_DECODE_NEW_INST-1];
    wire                                                        branch      [0:STRUCT_DECODE_NEW_INST-1];
    wire [IS_INST_OPERANDS-1:0]                                 ready       [0:STRUCT_DECODE_NEW_INST-1];
    wire [_BITWIDTH_LOW_STRUCT_EX_PATH-1:0]                     expath      [0:STRUCT_DECODE_NEW_INST-1];
    wire [EX_INST_MICROOP_BITWIDTH-1:0]                         microop     [0:STRUCT_DECODE_NEW_INST-1];
    wire [IS_INST_IMM-1:0]                                      imm         [0:STRUCT_DECODE_NEW_INST-1];

    // Default assignment placeholder for ready tracking
    generate
        genvar r_idx;
        for (r_idx = 0; r_idx < STRUCT_DECODE_NEW_INST; r_idx = r_idx + 1) begin : gen_ready_init
            assign ready[r_idx] = 0;
        end
    endgenerate

    // -------------------------------------------------------------------------
    // Unpacking Decoded Input Signals
    // -------------------------------------------------------------------------
    genvar u_idx;
    generate
        for (u_idx = 0; u_idx < STRUCT_DECODE_NEW_INST; u_idx = u_idx + 1) begin : gen_dec_unpack
            assign rd[u_idx]           = i_dec_rd[u_idx * _BITWIDTH_LOW_IS_INST_REGS +: _BITWIDTH_LOW_IS_INST_REGS];
            assign exception[u_idx]    = i_dec_exception[u_idx];
            assign newreg_alloc[u_idx] = i_dec_newreg_alloc[u_idx];
            assign jump[u_idx]         = i_dec_jump[u_idx];
            assign jump_reg[u_idx]     = i_dec_jump_reg[u_idx];
            assign branch[u_idx]       = i_dec_branch[u_idx];
            assign expath[u_idx]       = i_dec_expath[u_idx * _BITWIDTH_LOW_STRUCT_EX_PATH +: _BITWIDTH_LOW_STRUCT_EX_PATH];
            assign microop[u_idx]      = i_dec_microop[u_idx * EX_INST_MICROOP_BITWIDTH +: EX_INST_MICROOP_BITWIDTH];
            assign imm[u_idx]          = i_dec_imm[u_idx * IS_INST_IMM +: IS_INST_IMM];
            
            for (genvar op_idx = 0; op_idx < IS_INST_OPERANDS; op_idx = op_idx + 1) begin : gen_unpack_rs
                assign rs[u_idx][op_idx] = i_dec_rs[((u_idx * IS_INST_OPERANDS) + op_idx) * _BITWIDTH_LOW_IS_INST_REGS +: _BITWIDTH_LOW_IS_INST_REGS];
            end
        end
    endgenerate

    // -------------------------------------------------------------------------
    // Flattened outputs to PRM / Register Mapper
    // -------------------------------------------------------------------------
    reg  [(STRUCT_DECODE_NEW_INST * _BITWIDTH_LOW_IS_INST_REGS)-1:0] rd_spread;
    reg  [(STRUCT_DECODE_NEW_INST * IS_INST_OPERANDS * _BITWIDTH_LOW_IS_INST_REGS)-1:0] rs_spread;
    reg  [STRUCT_DECODE_NEW_INST-1:0]                    newreg_alloc_spread;
    reg  [STRUCT_DECODE_NEW_INST-1:0]                    im_inst_get;

    always @(*) begin
        for (integer new_entry_idx = 0; new_entry_idx < STRUCT_DECODE_NEW_INST; new_entry_idx = new_entry_idx + 1) begin
            rd_spread[( _BITWIDTH_LOW_IS_INST_REGS * new_entry_idx ) +: _BITWIDTH_LOW_IS_INST_REGS] = 
                (newreg_alloc[new_entry_idx]) ? rd[new_entry_idx] : 0;

            for (integer opreand_idx = 0; opreand_idx < IS_INST_OPERANDS; opreand_idx = opreand_idx + 1) begin
                rs_spread[( _BITWIDTH_LOW_IS_INST_REGS * ((new_entry_idx * IS_INST_OPERANDS) + opreand_idx) ) +: _BITWIDTH_LOW_IS_INST_REGS] = 
                    rs[new_entry_idx][opreand_idx];
            end

            newreg_alloc_spread[new_entry_idx] = (rd[new_entry_idx] != 0) ? newreg_alloc[new_entry_idx] : 0;
        end
    end

    // -------------------------------------------------------------------------
    // Logic Mapping Registers and Dependencies
    // -------------------------------------------------------------------------
    wire [(STRUCT_DECODE_NEW_INST * _BITWIDTH_LOW_STRUCT_PHYREGS)-1:0]                past_log_phy_reg;
    wire [(STRUCT_DECODE_NEW_INST * IS_INST_OPERANDS * _BITWIDTH_LOW_STRUCT_PHYREGS)-1:0] opreands_log_phy;

    // Registers to pipeline the stage
    reg                                                 active                [0:STRUCT_DECODE_NEW_INST-1];
    reg                                                 active_next           [0:STRUCT_DECODE_NEW_INST-1];
    reg [_BITWIDTH_CMB_FLOW_INDEXnPC-1:0]               pc_reg                [0:STRUCT_DECODE_NEW_INST-1];
    reg [_BITWIDTH_CMB_FLOW_INDEXnPC-1:0]               pc_new                [0:STRUCT_DECODE_NEW_INST-1];
    reg [_BITWIDTH_LOW_STRUCT_EX_PATH-1:0]              expath_reg            [0:STRUCT_DECODE_NEW_INST-1];
    reg [_BITWIDTH_LOW_STRUCT_EX_PATH-1:0]              expath_new            [0:STRUCT_DECODE_NEW_INST-1];
    reg [EX_INST_MICROOP_BITWIDTH-1:0]                  microop_reg           [0:STRUCT_DECODE_NEW_INST-1];
    reg [EX_INST_MICROOP_BITWIDTH-1:0]                  microop_new           [0:STRUCT_DECODE_NEW_INST-1];
    reg [IS_INST_IMM-1:0]                               imm_reg               [0:STRUCT_DECODE_NEW_INST-1];
    reg [IS_INST_IMM-1:0]                               imm_new               [0:STRUCT_DECODE_NEW_INST-1];
    reg [_BITWIDTH_LOW_STRUCT_PHYREGS-1:0]              new_log_phy_reg       [0:STRUCT_DECODE_NEW_INST-1];
    reg [_BITWIDTH_LOW_STRUCT_PHYREGS-1:0]              new_log_phy_next      [0:STRUCT_DECODE_NEW_INST-1];
    reg [(IS_INST_OPERANDS * _BITWIDTH_LOW_STRUCT_PHYREGS)-1:0] opreands_log_phy_reg  [0:STRUCT_DECODE_NEW_INST-1];
    reg [(IS_INST_OPERANDS * _BITWIDTH_LOW_STRUCT_PHYREGS)-1:0] opreands_log_phy_next [0:STRUCT_DECODE_NEW_INST-1];
    reg [IS_INST_OPERANDS-1:0]                          opreands_ready_reg    [0:STRUCT_DECODE_NEW_INST-1];
    reg [IS_INST_OPERANDS-1:0]                          opreands_ready_next   [0:STRUCT_DECODE_NEW_INST-1];

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            for (integer i = 0; i < STRUCT_DECODE_NEW_INST; i = i + 1) begin
                active[i]               <= 1'b0; 
                pc_reg[i]               <= 0;
                expath_reg[i]           <= 0;
                microop_reg[i]          <= 0;
                imm_reg[i]              <= 0;
                new_log_phy_reg[i]      <= 0; 
                opreands_log_phy_reg[i] <= 0;
                opreands_ready_reg[i]   <= 0;
            end
        end else begin
            for (integer i = 0; i < STRUCT_DECODE_NEW_INST; i = i + 1) begin
                active[i]               <= active_next[i]; 
                pc_reg[i]               <= pc_new[i];
                expath_reg[i]           <= expath_new[i];
                microop_reg[i]          <= microop_new[i];
                imm_reg[i]              <= imm_new[i];
                new_log_phy_reg[i]      <= new_log_phy_next[i];
                opreands_log_phy_reg[i] <= opreands_log_phy_next[i];
                opreands_ready_reg[i]   <= opreands_ready_next[i];
            end
        end
    end

    // -------------------------------------------------------------------------
    // RAW Dependency Resolution (Forwarding logic for parallel decodes)
    // -------------------------------------------------------------------------
    reg  [_BITWIDTH_LOW_STRUCT_PHYREGS-1:0]             rs_mapped [0:STRUCT_DECODE_NEW_INST-1][0:IS_INST_OPERANDS-1];
    reg                                                 rs_ready_mapped [0:STRUCT_DECODE_NEW_INST-1][0:IS_INST_OPERANDS-1];

    always @(*) begin
        for (integer i = 0; i < STRUCT_DECODE_NEW_INST; i = i + 1) begin
            for (integer j = 0; j < IS_INST_OPERANDS; j = j + 1) begin
                // Read mappings from regfile and ready flags
                rs_mapped[i][j]       = opreands_log_phy[(i * IS_INST_OPERANDS + j) * _BITWIDTH_LOW_STRUCT_PHYREGS +: _BITWIDTH_LOW_STRUCT_PHYREGS];
                rs_ready_mapped[i][j] = opreands_phy_ready[i * IS_INST_OPERANDS + j];

                // Check for in-flight RAW dependency against preceding decodes in the same cycle
                for (integer h = 0; h < i; h = h + 1) begin
                    if (newreg_alloc[h] && (rd[h] != 0) && (rs[i][j] == rd[h])) begin
                        // Forward the newly allocated physical register address
                        rs_mapped[i][j]       = i_prm_allocate_phyreg[h * _BITWIDTH_LOW_STRUCT_PHYREGS +: _BITWIDTH_LOW_STRUCT_PHYREGS];
                        rs_ready_mapped[i][j] = 1'b0; // Depend on previous in-flight instruction (not ready)
                    end
                end
            end
        end
    end

    reg [STRUCT_DECODE_NEW_INST-1:0] inst_valid_masked;
    reg prev_control_flow_inst;
    integer mask_idx;

    always @(*) begin
        prev_control_flow_inst = 1'b0;
        inst_valid_masked = 0;
        for (mask_idx = 0; mask_idx < STRUCT_DECODE_NEW_INST; mask_idx = mask_idx + 1) begin
            if (prev_control_flow_inst) begin
                inst_valid_masked[mask_idx] = 1'b0;
            end else begin
                inst_valid_masked[mask_idx] = i_im_inst_valid[mask_idx];
            end

            if (i_im_inst_valid[mask_idx] && (jump[mask_idx] || jump_reg[mask_idx] || branch[mask_idx])) begin
                prev_control_flow_inst = 1'b1;
            end
        end
    end

    always @(*) begin
        // Jump/Branch control logic
        o_nel_jump_inst        = 1'b0;
        o_nel_jreg_branch_inst = 1'b0;
        o_nel_jump_branch_pc   = 0;

        for (integer i = 0; i < STRUCT_DECODE_NEW_INST; i = i + 1) begin
            if (i_im_inst_valid[i] && o_im_inst_get[i]) begin
                o_nel_jump_inst        = jump[i];
                o_nel_jreg_branch_inst = jump_reg[i] | branch[i];
                o_nel_jump_branch_pc   = i_im_inst_pc[i * _BITWIDTH_CMB_FLOW_INDEXnPC +: IS_INST_PC_BITWIDTH] + imm[i];
                if (jump[i] || jump_reg[i] || branch[i]) break;
            end
        end

        // Handshake control
        im_inst_get = i_prm_allocate_valid & newreg_alloc_spread;
        im_inst_get |= ~newreg_alloc_spread;
        o_im_inst_get = 0;

        if (i_prm_active && i_ist_insert_available) begin
            for (integer i = 0; i < STRUCT_DECODE_NEW_INST; i = i + 1) begin
                o_im_inst_get[i] = im_inst_get[i] & inst_valid_masked[i];
                if (!im_inst_get[i] || !inst_valid_masked[i]) break; // Maintain sequential decode flow
            end
        end

        // Pipeline stage updates
        if (i_prm_active) begin
            for (integer i = 0; i < STRUCT_DECODE_NEW_INST; i = i + 1) begin
                active_next[i]      = inst_valid_masked[i];
                pc_new[i]           = i_im_inst_pc[i * _BITWIDTH_CMB_FLOW_INDEXnPC +: _BITWIDTH_CMB_FLOW_INDEXnPC];
                expath_new[i]       = expath[i];
                microop_new[i]      = microop[i];
                imm_new[i]          = imm[i];
                
                new_log_phy_next[i] = 0;
                if (newreg_alloc[i]) begin
                    new_log_phy_next[i] = i_prm_allocate_phyreg[i * _BITWIDTH_LOW_STRUCT_PHYREGS +: _BITWIDTH_LOW_STRUCT_PHYREGS];
                end

                for (integer j = 0; j < IS_INST_OPERANDS; j = j + 1) begin
                    opreands_log_phy_next[i][j * _BITWIDTH_LOW_STRUCT_PHYREGS +: _BITWIDTH_LOW_STRUCT_PHYREGS] = rs_mapped[i][j];
                    
                    if (rs[i][j] == 0) begin
                        opreands_ready_next[i][j] = 1'b1; // Register x0 is always ready
                    end else begin
                        opreands_ready_next[i][j] = rs_ready_mapped[i][j];
                    end
                end
            end
        end else begin
            for (integer i = 0; i < STRUCT_DECODE_NEW_INST; i = i + 1) begin
                active_next[i]           = active[i]; 
                pc_new[i]                = pc_reg[i];
                expath_new[i]            = expath_reg[i];
                microop_new[i]           = microop_reg[i];
                imm_new[i]               = imm_reg[i];
                new_log_phy_next[i]      = new_log_phy_reg[i];
                opreands_log_phy_next[i] = opreands_log_phy_reg[i];
                opreands_ready_next[i]   = opreands_ready_reg[i];
            end
        end
    end

    assign o_nel_newpc_valid   = i_im_inst_valid & o_im_inst_get;
    assign o_nel_newpc         = i_im_inst_pc;
    assign o_nel_lastreg_valid = i_im_inst_valid & o_im_inst_get & newreg_alloc_spread;
    assign o_nel_lastreg       = past_log_phy_reg;
    assign o_allocate_position = i_im_inst_valid & o_im_inst_get & newreg_alloc_spread;
    assign o_nel_block         = ~i_ist_insert_available | ~i_prm_active;

    // -------------------------------------------------------------------------
    // Stage 2: Output Section
    // -------------------------------------------------------------------------
    wire [(STRUCT_DECODE_NEW_INST * IS_INST_OPERANDS)-1:0]                      opreands_phy_ready;
    reg  [IS_INST_OPERANDS-1:0]                                                 opreands_ready_final;
    reg  [IS_INST_OPERANDS-1:0]                                                 opreands_ready_now;
    reg  [(STRUCT_DECODE_NEW_INST * IS_INST_OPERANDS * _BITWIDTH_LOW_STRUCT_PHYREGS)-1:0] opreands_log_phy_reg_spread;

    always @(*) begin
        o_ist_field_insert = 0;
        o_ist_field        = 0;

        for (integer i = 0; i < STRUCT_DECODE_NEW_INST; i = i + 1) begin
            if (active[i]) begin
                o_ist_field_insert[i] = 1'b1;
            end

            opreands_ready_now = 0;
            // Scan through all executing outputs (WBC) for matching ready status
            for (integer done_idx = 0; done_idx < _STRUCT_EX_OUT_RESULT_ALL; done_idx = done_idx + 1) begin
                for (integer op_idx = 0; op_idx < IS_INST_OPERANDS; op_idx = op_idx + 1) begin
                    if (opreands_log_phy_reg[i][op_idx * _BITWIDTH_LOW_STRUCT_PHYREGS +: _BITWIDTH_LOW_STRUCT_PHYREGS] == 
                        i_wbc2nel_done_phyreg[done_idx * _BITWIDTH_LOW_STRUCT_PHYREGS +: _BITWIDTH_LOW_STRUCT_PHYREGS]) begin
                        opreands_ready_now[op_idx] = (i_wbc2nel_done[done_idx]) ? 1'b1 : 1'b0;
                    end
                end
            end

            opreands_ready_final = opreands_ready_reg[i] | 
                                   opreands_phy_ready[(IS_INST_OPERANDS * i) +: IS_INST_OPERANDS] | 
                                   opreands_ready_now;

            // Pack fields to form the internal IST instruction packet (IST_BITWIDTH)
            o_ist_field[(IST_BITWIDTH * i) +: IST_BITWIDTH] = { 
                opreands_ready_final,
                opreands_log_phy_reg[i],
                new_log_phy_reg[i],
                imm_reg[i],
                microop_reg[i],
                expath_reg[i],
                pc_reg[i] 
            };

            opreands_log_phy_reg_spread[((IS_INST_OPERANDS * _BITWIDTH_LOW_STRUCT_PHYREGS) * i) +: (IS_INST_OPERANDS * _BITWIDTH_LOW_STRUCT_PHYREGS)] = 
                opreands_log_phy_reg[i];
        end

        if (~i_prm_active) begin
            o_ist_field_insert = 0;
        end
    end

    // -------------------------------------------------------------------------
    // Registers mapping logic
    // -------------------------------------------------------------------------
    reg [STRUCT_DECODE_NEW_INST-1:0] map_log_phy_wes;
    always @(*) begin
        for (integer i = 0; i < STRUCT_DECODE_NEW_INST; i = i + 1) begin
            if (rd[i] == 0) begin
                map_log_phy_wes[i] = 0;
            end else begin
                map_log_phy_wes[i] = o_im_inst_get[i] & i_im_inst_valid[i] & newreg_alloc[i];
            end
        end
    end

    // ISA logical register mapping table
    regfile #(
        .READ_CHANNEL  (STRUCT_DECODE_NEW_INST + (STRUCT_DECODE_NEW_INST * IS_INST_OPERANDS)),
        .WRITE_CHANNEL (STRUCT_DECODE_NEW_INST),
        .ENTRIES       (IS_INST_REGS),
        .REG_WIDTH     (_BITWIDTH_LOW_STRUCT_PHYREGS)
    ) U_LOGICREG_PHYREG_MAP (
        .clk              (clk),
        .reset_n          (reset_n),
        .i_read_addresses ({rd_spread, rs_spread}),
        .i_write_wes      (map_log_phy_wes),
        .i_write_addresses(rd_spread),
        .i_write_data     (i_prm_allocate_phyreg),
        .o_read_data      ({past_log_phy_reg, opreands_log_phy})
    );

    // Ready flags tracker
    regfile_init_1 #(
        .READ_CHANNEL  (STRUCT_DECODE_NEW_INST * IS_INST_OPERANDS),
        .WRITE_CHANNEL (_STRUCT_EX_OUT_RESULT_ALL + STRUCT_DECODE_NEW_INST),
        .ENTRIES       (STRUCT_PHYREGS),
        .REG_WIDTH     (1)
    ) U_PHYREG_READY (
        .clk              (clk),
        .reset_n          (reset_n),
        .i_read_addresses (opreands_log_phy_reg_spread),
        .i_write_wes      ({i_wbc2nel_done, map_log_phy_wes}),
        .i_write_addresses({i_wbc2nel_done_phyreg, i_prm_allocate_phyreg}),
        .i_write_data     ({{_STRUCT_EX_OUT_RESULT_ALL{1'b1}}, {STRUCT_DECODE_NEW_INST{1'b0}}}),
        .o_read_data      (opreands_phy_ready)
    );

endmodule
