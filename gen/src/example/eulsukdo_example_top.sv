`timescale 1ns / 1ps

// =============================================================================
// 💡 EULSUKDO Out-of-Order Core Subsystem Example
//    - Decode Width : 2 (Super-scalar Fetch & Decode)
//    - Issue Width  : 5 (1 Branch Core, 3 ALU Cores, 1 Memory Core)
// =============================================================================

module eulsukdo_example_top #(
    parameter int IS_INST_PC_BITWIDTH           = 32,
    parameter int IS_INST_PC_STEP               = 4,
    parameter int IS_INST_BITWIDTH               = 32,
    parameter int IS_INST_REGS                   = 32,
    parameter int IS_INST_OPERANDS               = 2,
    parameter int IS_INST_IMM                    = 32,

    parameter int EX_INST_MICROOP_BITWIDTH       = 5,

    parameter int STRUCT_DECODE_NEW_INST        = 2, // 2 Decode slots
    parameter int STRUCT_INST_STATE_ENTRIES     = 128,
    parameter int STRUCT_PHYREGS                 = 64,
    parameter int STRUCT_EX_PATH                 = 3, // Branch, ALU, Memory
    parameter int STRUCT_RS_OUT_ENTRY [STRUCT_EX_PATH] = '{1, 3, 1}, // 1 Branch, 3 ALU, 1 Mem
    parameter int STRUCT_EX_CORES                = 5, // Total 5 Cores
    parameter int STRUCT_EX_OUT_RESULT [STRUCT_EX_CORES] = '{1, 1, 1, 1, 1}, // 1 outcome per core
    parameter int STRUCT_EX_OUT_RESULT_SUM       = 5,
    parameter int STRUCT_RS_OUT_ENTRY_SUM        = 5,
    parameter int STRUCT_PRM_ENTRY_UPDATE        = 3,
    parameter int STRUCT_PRM_ENTRY_BUFFER        = 4,
    parameter int STRUCT_UNALLOCATE_PHYREG       = 4,
    parameter int STRUCT_FLOW_WINDOWS            = 8,
    parameter int STRUCT_FLOW_PC_MAX_RANGE       = 8,

    // Localparam offset definitions
    localparam int _BITWIDTH_LOW_STRUCT_FLOW_WINDOWS = $clog2(STRUCT_FLOW_WINDOWS),
    localparam int _BITWIDTH_LOW_STRUCT_PHYREGS      = $clog2(STRUCT_PHYREGS),
    localparam int _BITWIDTH_LOW_STRUCT_EX_PATH      = $clog2(STRUCT_EX_PATH),
    localparam int _BITWIDTH_LOW_STRUCT_INST_STATE_ENTRIES = $clog2(STRUCT_INST_STATE_ENTRIES),
    localparam int _BITWIDTH_LOW_IS_INST_REGS        = $clog2(IS_INST_REGS),
    
    localparam int _STRUCT_EX_OUT_RESULT_ALL         = STRUCT_EX_OUT_RESULT_SUM,
    localparam int _STRUCT_RS_OUT_ENTRY_ALL          = STRUCT_RS_OUT_ENTRY_SUM,
    localparam int _BITWIDTH_CMB_FLOW_INDEXnPC       = _BITWIDTH_LOW_STRUCT_FLOW_WINDOWS + IS_INST_PC_BITWIDTH
) (
    input  wire                                                 clk,
    input  wire                                                 reset_n,

    // Instruction Memory Ports (Connected to double-width Fetch logic)
    input  wire [STRUCT_DECODE_NEW_INST-1:0]                    i_im_inst_valid,
    input  wire [(STRUCT_DECODE_NEW_INST*IS_INST_BITWIDTH)-1:0] i_im_inst,
    output wire [STRUCT_DECODE_NEW_INST-1:0]                    o_im_inst_get,
    output wire                                                 o_im_pc_valid,
    output wire [_BITWIDTH_CMB_FLOW_INDEXnPC-1:0]               o_im_pc,

    // Mock virtual memory interface for the MEM Core
    output wire                                                 re_vmem_o,
    output wire                                                 we_vmem_o,
    output wire [31:0]                                          addr_vmem_o,
    output wire [3:0]                                           strb_vmem_o,
    input  wire [31:0]                                          rdata_vmem_i,
    output wire [31:0]                                          wdata_vmem_o,
    input  wire                                                 ready_vmem_i
);

    // RS Issue Bitwidths
    localparam int RS_ENTRY_BITWIDTH = _BITWIDTH_CMB_FLOW_INDEXnPC + 
                                       _BITWIDTH_LOW_STRUCT_EX_PATH + 
                                       EX_INST_MICROOP_BITWIDTH + 
                                       IS_INST_IMM + 
                                       _BITWIDTH_LOW_STRUCT_PHYREGS + 
                                       (_BITWIDTH_LOW_STRUCT_PHYREGS * IS_INST_OPERANDS);

    // -------------------------------------------------------------------------
    // 1. Double Decode Stage (Decoders instantiated externally)
    // -------------------------------------------------------------------------
    wire [(STRUCT_DECODE_NEW_INST * _BITWIDTH_LOW_IS_INST_REGS)-1:0] dec_rd;
    wire [(STRUCT_DECODE_NEW_INST * IS_INST_OPERANDS * _BITWIDTH_LOW_IS_INST_REGS)-1:0] dec_rs;
    wire [STRUCT_DECODE_NEW_INST-1:0]                                dec_exception;
    wire [STRUCT_DECODE_NEW_INST-1:0]                                dec_newreg_alloc;
    wire [STRUCT_DECODE_NEW_INST-1:0]                                dec_jump;
    wire [STRUCT_DECODE_NEW_INST-1:0]                                dec_jump_reg;
    wire [STRUCT_DECODE_NEW_INST-1:0]                                dec_branch;
    wire [(STRUCT_DECODE_NEW_INST * _BITWIDTH_LOW_STRUCT_EX_PATH)-1:0] dec_expath;
    wire [(STRUCT_DECODE_NEW_INST * EX_INST_MICROOP_BITWIDTH)-1:0]   dec_microop;
    wire [(STRUCT_DECODE_NEW_INST * IS_INST_IMM)-1:0]                dec_imm;

    wire [(STRUCT_DECODE_NEW_INST * IS_INST_BITWIDTH)-1:0]           dec_raw_inst;

    // Connect decoders
    genvar d_idx;
    generate
        for (d_idx = 0; d_idx < STRUCT_DECODE_NEW_INST; d_idx = d_idx + 1) begin : gen_decoders
            rv32i_decoder #(
                .IS_INST_BITWIDTH         (IS_INST_BITWIDTH),
                .IS_INST_REGS             (IS_INST_REGS),
                .IS_INST_OPERANDS         (IS_INST_OPERANDS),
                .IS_INST_IMM             (IS_INST_IMM),
                .EX_INST_MICROOP_BITWIDTH (EX_INST_MICROOP_BITWIDTH),
                .STRUCT_EX_PATH           (STRUCT_EX_PATH)
            ) U_DEC (
                .inst_i        (dec_raw_inst[d_idx * IS_INST_BITWIDTH +: IS_INST_BITWIDTH]),
                .rd_o          (dec_rd[d_idx * _BITWIDTH_LOW_IS_INST_REGS +: _BITWIDTH_LOW_IS_INST_REGS]),
                .rs_o          (dec_rs[(d_idx * IS_INST_OPERANDS * _BITWIDTH_LOW_IS_INST_REGS) +: (IS_INST_OPERANDS * _BITWIDTH_LOW_IS_INST_REGS)]),
                .exception_o   (dec_exception[d_idx]),
                .newreg_alloc_o(dec_newreg_alloc[d_idx]),
                .jump_o        (dec_jump[d_idx]),
                .jump_reg_o    (dec_jump_reg[d_idx]),
                .branch_o      (dec_branch[d_idx]),
                .expath_o      (dec_expath[d_idx * _BITWIDTH_LOW_STRUCT_EX_PATH +: _BITWIDTH_LOW_STRUCT_EX_PATH]),
                .microop_o     (dec_microop[d_idx * EX_INST_MICROOP_BITWIDTH +: EX_INST_MICROOP_BITWIDTH]),
                .imm_o         (dec_imm[d_idx * IS_INST_IMM +: IS_INST_IMM])
            );
        end
    endgenerate

    // -------------------------------------------------------------------------
    // 2. EULSUKDO Core Scheduler Instance
    // -------------------------------------------------------------------------
    wire [_STRUCT_RS_OUT_ENTRY_ALL-1:0]                  ex_entry_valid;
    wire [(_STRUCT_RS_OUT_ENTRY_ALL * RS_ENTRY_BITWIDTH)-1:0] ex_entry;
    wire [_STRUCT_RS_OUT_ENTRY_ALL-1:0]                  ex_entry_get;

    wire [_STRUCT_EX_OUT_RESULT_ALL-1:0]                 ex_done;
    wire [(_STRUCT_EX_OUT_RESULT_ALL*IS_INST_PC_BITWIDTH)-1:0] ex_done_pc;
    wire [(_STRUCT_EX_OUT_RESULT_ALL*_BITWIDTH_LOW_STRUCT_PHYREGS)-1:0] ex_done_phyreg;
    wire                                                 ex_done_branch;
    wire [IS_INST_PC_BITWIDTH-1:0]                       ex_done_branch_pc;

    eulsukdo_gen #(
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
        .STRUCT_RS_OUT_ENTRY_SUM     (STRUCT_RS_OUT_ENTRY_SUM),
        .STRUCT_PRM_ENTRY_UPDATE     (STRUCT_PRM_ENTRY_UPDATE),
        .STRUCT_PRM_ENTRY_BUFFER     (STRUCT_PRM_ENTRY_BUFFER),
        .STRUCT_UNALLOCATE_PHYREG    (STRUCT_UNALLOCATE_PHYREG),
        .STRUCT_FLOW_WINDOWS         (STRUCT_FLOW_WINDOWS),
        .STRUCT_FLOW_PC_MAX_RANGE    (STRUCT_FLOW_PC_MAX_RANGE)
    ) U_SCHEDULER_CORE (
        .clk                         (clk),
        .reset_n                     (reset_n),
        .i_im_inst_valid             (i_im_inst_valid),
        .i_im_inst                     (i_im_inst),
        .o_im_inst_get                 (o_im_inst_get),
        .o_dec_inst                  (dec_raw_inst),
        .o_im_pc_valid               (o_im_pc_valid),
        .o_im_pc                     (o_im_pc),

        // Decoded signals interface
        .i_dec_rd                    (dec_rd),
        .i_dec_rs                    (dec_rs),
        .i_dec_exception             (dec_exception),
        .i_dec_newreg_alloc          (dec_newreg_alloc),
        .i_dec_jump                  (dec_jump),
        .i_dec_jump_reg              (dec_jump_reg),
        .i_dec_branch                (dec_branch),
        .i_dec_expath                (dec_expath),
        .i_dec_microop               (dec_microop),
        .i_dec_imm                   (dec_imm),

        // Scheduler command issue outputs to external EX cores
        .o_ex_entry_valid            (ex_entry_valid),
        .o_ex_entry                  (ex_entry),
        .i_ex_entry_get                (ex_entry_get),

        // Execution unit writeback inputs
        .i_ex_done                   (ex_done),
        .i_ex_done_pc                (ex_done_pc),
        .i_ex_done_phyreg            (ex_done_phyreg),
        .i_ex_done_branch            (ex_done_branch),
        .i_ex_done_branch_pc         (ex_done_branch_pc)
    );

    // -------------------------------------------------------------------------
    // 3. Physical Register File (PRF) Instance
    //    - Reads: 10 channels (5 issue slots * 2 operands)
    //    - Writes: 5 channels (5 writeback sources)
    // -------------------------------------------------------------------------
    wire [(_STRUCT_RS_OUT_ENTRY_ALL * IS_INST_OPERANDS * _BITWIDTH_LOW_STRUCT_PHYREGS)-1:0] prf_read_addr;
    wire [(_STRUCT_RS_OUT_ENTRY_ALL * IS_INST_OPERANDS * 32)-1:0] prf_read_data;
    
    wire [_STRUCT_RS_OUT_ENTRY_ALL-1:0] prf_write_we;
    wire [(_STRUCT_RS_OUT_ENTRY_ALL * _BITWIDTH_LOW_STRUCT_PHYREGS)-1:0] prf_write_addr;
    wire [(_STRUCT_RS_OUT_ENTRY_ALL * 32)-1:0] prf_write_data;

    regfile #(
        .READ_CHANNEL  (_STRUCT_RS_OUT_ENTRY_ALL * IS_INST_OPERANDS),
        .WRITE_CHANNEL (_STRUCT_RS_OUT_ENTRY_ALL),
        .ENTRIES       (STRUCT_PHYREGS),
        .REG_WIDTH     (32)
    ) U_PRF (
        .clk              (clk),
        .reset_n          (reset_n),
        .i_read_addresses (prf_read_addr),
        .i_write_wes      (prf_write_we),
        .i_write_addresses(prf_write_addr),
        .i_write_data     (prf_write_data),
        .o_read_data      (prf_read_data)
    );

    // -------------------------------------------------------------------------
    // 4. Execution Core Array (5 Cores mapping logic)
    // -------------------------------------------------------------------------
    
    // Path 0: Branch (1 slot, index 0)
    wire        run_branch  = ex_entry_valid[0];
    wire [31:0] pc_branch   = ex_entry[0 +: IS_INST_PC_BITWIDTH];
    wire [4:0]  uop_branch  = ex_entry[(_BITWIDTH_CMB_FLOW_INDEXnPC + _BITWIDTH_LOW_STRUCT_EX_PATH) +: EX_INST_MICROOP_BITWIDTH];
    wire [31:0] imm_branch  = ex_entry[(_BITWIDTH_CMB_FLOW_INDEXnPC + _BITWIDTH_LOW_STRUCT_EX_PATH + EX_INST_MICROOP_BITWIDTH) +: IS_INST_IMM];
    wire [_BITWIDTH_LOW_STRUCT_PHYREGS-1:0] rd_branch = ex_entry[(_BITWIDTH_CMB_FLOW_INDEXnPC + _BITWIDTH_LOW_STRUCT_EX_PATH + EX_INST_MICROOP_BITWIDTH + IS_INST_IMM) +: _BITWIDTH_LOW_STRUCT_PHYREGS];
    wire [_BITWIDTH_LOW_STRUCT_PHYREGS-1:0] rs1_branch = ex_entry[(_BITWIDTH_CMB_FLOW_INDEXnPC + _BITWIDTH_LOW_STRUCT_EX_PATH + EX_INST_MICROOP_BITWIDTH + IS_INST_IMM + _BITWIDTH_LOW_STRUCT_PHYREGS) +: _BITWIDTH_LOW_STRUCT_PHYREGS];
    wire [_BITWIDTH_LOW_STRUCT_PHYREGS-1:0] rs2_branch = ex_entry[(_BITWIDTH_CMB_FLOW_INDEXnPC + _BITWIDTH_LOW_STRUCT_EX_PATH + EX_INST_MICROOP_BITWIDTH + IS_INST_IMM + _BITWIDTH_LOW_STRUCT_PHYREGS + _BITWIDTH_LOW_STRUCT_PHYREGS) +: _BITWIDTH_LOW_STRUCT_PHYREGS];
    
    wire [31:0] rs1_val_branch = prf_read_data[0*32 +: 32];
    wire [31:0] rs2_val_branch = prf_read_data[1*32 +: 32];
    
    wire [31:0] branch_tgt_pc;
    wire [31:0] branch_rd_val;
    wire        branch_we;
    wire        branch_taken;
    wire        branch_done;

    assign prf_read_addr[0*_BITWIDTH_LOW_STRUCT_PHYREGS +: _BITWIDTH_LOW_STRUCT_PHYREGS] = rs1_branch;
    assign prf_read_addr[1*_BITWIDTH_LOW_STRUCT_PHYREGS +: _BITWIDTH_LOW_STRUCT_PHYREGS] = rs2_branch;

    branch_ex #(
        .IS_INST_PC_BITWIDTH(IS_INST_PC_BITWIDTH)
    ) U_BRANCH_CORE (
        .run_i      (run_branch),
        .microop_i  (uop_branch),
        .rs1_i      (rs1_val_branch),
        .rs2_i      (rs2_val_branch),
        .imm_i      (imm_branch),
        .pc_i       (pc_branch),
        .new_pc_o   (branch_tgt_pc),
        .return_pc_o(branch_rd_val),
        .we_o       (branch_we),
        .branch_o   (branch_taken),
        .done_o     (branch_done)
    );

    // Path 1: ALU (3 slots, indexes 1, 2, 3)
    wire [2:0]  run_alu;
    wire [31:0] pc_alu   [3];
    wire [4:0]  uop_alu  [3];
    wire [31:0] imm_alu  [3];
    wire [_BITWIDTH_LOW_STRUCT_PHYREGS-1:0] rd_alu  [3];
    wire [_BITWIDTH_LOW_STRUCT_PHYREGS-1:0] rs1_alu [3];
    wire [_BITWIDTH_LOW_STRUCT_PHYREGS-1:0] rs2_alu [3];

    wire [31:0] rs1_val_alu [3];
    wire [31:0] rs2_val_alu [3];

    wire [31:0] alu_result [3];
    wire [2:0]  alu_we;
    wire [2:0]  alu_done;

    genvar a;
    generate
        for (a = 0; a < 3; a = a + 1) begin : gen_alu_connections
            localparam int slot_idx = 1 + a;
            assign run_alu[a]   = ex_entry_valid[slot_idx];
            assign pc_alu[a]    = ex_entry[slot_idx * RS_ENTRY_BITWIDTH +: IS_INST_PC_BITWIDTH];
            assign uop_alu[a]   = ex_entry[(slot_idx * RS_ENTRY_BITWIDTH + _BITWIDTH_CMB_FLOW_INDEXnPC + _BITWIDTH_LOW_STRUCT_EX_PATH) +: EX_INST_MICROOP_BITWIDTH];
            assign imm_alu[a]   = ex_entry[(slot_idx * RS_ENTRY_BITWIDTH + _BITWIDTH_CMB_FLOW_INDEXnPC + _BITWIDTH_LOW_STRUCT_EX_PATH + EX_INST_MICROOP_BITWIDTH) +: IS_INST_IMM];
            assign rd_alu[a]    = ex_entry[(slot_idx * RS_ENTRY_BITWIDTH + _BITWIDTH_CMB_FLOW_INDEXnPC + _BITWIDTH_LOW_STRUCT_EX_PATH + EX_INST_MICROOP_BITWIDTH + IS_INST_IMM) +: _BITWIDTH_LOW_STRUCT_PHYREGS];
            assign rs1_alu[a]   = ex_entry[(slot_idx * RS_ENTRY_BITWIDTH + _BITWIDTH_CMB_FLOW_INDEXnPC + _BITWIDTH_LOW_STRUCT_EX_PATH + EX_INST_MICROOP_BITWIDTH + IS_INST_IMM + _BITWIDTH_LOW_STRUCT_PHYREGS) +: _BITWIDTH_LOW_STRUCT_PHYREGS];
            assign rs2_alu[a]   = ex_entry[(slot_idx * RS_ENTRY_BITWIDTH + _BITWIDTH_CMB_FLOW_INDEXnPC + _BITWIDTH_LOW_STRUCT_EX_PATH + EX_INST_MICROOP_BITWIDTH + IS_INST_IMM + _BITWIDTH_LOW_STRUCT_PHYREGS + _BITWIDTH_LOW_STRUCT_PHYREGS) +: _BITWIDTH_LOW_STRUCT_PHYREGS];
            
            assign prf_read_addr[(slot_idx * 2) * _BITWIDTH_LOW_STRUCT_PHYREGS +: _BITWIDTH_LOW_STRUCT_PHYREGS] = rs1_alu[a];
            assign prf_read_addr[((slot_idx * 2) + 1) * _BITWIDTH_LOW_STRUCT_PHYREGS +: _BITWIDTH_LOW_STRUCT_PHYREGS] = rs2_alu[a];

            assign rs1_val_alu[a] = prf_read_data[(slot_idx * 2) * 32 +: 32];
            assign rs2_val_alu[a] = prf_read_data[((slot_idx * 2) + 1) * 32 +: 32];

            alu_ex U_ALU_CORE (
                .run_i       (run_alu[a]),
                .microop_i   (uop_alu[a]),
                .rs1_i       (rs1_val_alu[a]),
                .rs2_i       (rs2_val_alu[a]),
                .imm_i       (imm_alu[a]),
                .alu_result_o(alu_result[a]),
                .we_o        (alu_we[a]),
                .done_o      (alu_done[a])
            );
        end
    endgenerate

    // Path 2: Memory (1 slot, index 4)
    wire        run_mem  = ex_entry_valid[4];
    wire [31:0] pc_mem   = ex_entry[4 * RS_ENTRY_BITWIDTH +: IS_INST_PC_BITWIDTH];
    wire [4:0]  uop_mem  = ex_entry[(4 * RS_ENTRY_BITWIDTH + _BITWIDTH_CMB_FLOW_INDEXnPC + _BITWIDTH_LOW_STRUCT_EX_PATH) +: EX_INST_MICROOP_BITWIDTH];
    wire [31:0] imm_mem  = ex_entry[(4 * RS_ENTRY_BITWIDTH + _BITWIDTH_CMB_FLOW_INDEXnPC + _BITWIDTH_LOW_STRUCT_EX_PATH + EX_INST_MICROOP_BITWIDTH) +: IS_INST_IMM];
    wire [_BITWIDTH_LOW_STRUCT_PHYREGS-1:0] rd_mem = ex_entry[(4 * RS_ENTRY_BITWIDTH + _BITWIDTH_CMB_FLOW_INDEXnPC + _BITWIDTH_LOW_STRUCT_EX_PATH + EX_INST_MICROOP_BITWIDTH + IS_INST_IMM) +: _BITWIDTH_LOW_STRUCT_PHYREGS];
    wire [_BITWIDTH_LOW_STRUCT_PHYREGS-1:0] rs1_mem = ex_entry[(4 * RS_ENTRY_BITWIDTH + _BITWIDTH_CMB_FLOW_INDEXnPC + _BITWIDTH_LOW_STRUCT_EX_PATH + EX_INST_MICROOP_BITWIDTH + IS_INST_IMM + _BITWIDTH_LOW_STRUCT_PHYREGS) +: _BITWIDTH_LOW_STRUCT_PHYREGS];
    wire [_BITWIDTH_LOW_STRUCT_PHYREGS-1:0] rs2_mem = ex_entry[(4 * RS_ENTRY_BITWIDTH + _BITWIDTH_CMB_FLOW_INDEXnPC + _BITWIDTH_LOW_STRUCT_EX_PATH + EX_INST_MICROOP_BITWIDTH + IS_INST_IMM + _BITWIDTH_LOW_STRUCT_PHYREGS + _BITWIDTH_LOW_STRUCT_PHYREGS) +: _BITWIDTH_LOW_STRUCT_PHYREGS];
    
    wire [31:0] rs1_val_mem = prf_read_data[8*32 +: 32];
    wire [31:0] rs2_val_mem = prf_read_data[9*32 +: 32];

    wire [31:0] mem_proc_rdata;
    wire        mem_we;
    wire        mem_done;

    assign prf_read_addr[8*_BITWIDTH_LOW_STRUCT_PHYREGS +: _BITWIDTH_LOW_STRUCT_PHYREGS] = rs1_mem;
    assign prf_read_addr[9*_BITWIDTH_LOW_STRUCT_PHYREGS +: _BITWIDTH_LOW_STRUCT_PHYREGS] = rs2_mem;

    mem_ex U_MEM_CORE (
        .clk         (clk),
        .reset_n     (reset_n),
        .run_i       (run_mem),
        .microop_i   (uop_mem),
        .rs1_i       (rs1_val_mem),
        .rs2_i       (rs2_val_mem),
        .imm_i       (imm_mem),
        .rdata_proc_o(mem_proc_rdata),
        .re_vmem_o   (re_vmem_o),
        .we_vmem_o   (we_vmem_o),
        .addr_vmem_o (addr_vmem_o),
        .strb_vmem_o (strb_vmem_o),
        .rdata_vmem_i(rdata_vmem_i),
        .wdata_vmem_o(wdata_vmem_o),
        .ready_vmem_i(ready_vmem_i),
        .we_proc_o   (mem_we),
        .done_o      (mem_done)
    );

    // -------------------------------------------------------------------------
    // 5. Port assignments and interconnect bindings
    // -------------------------------------------------------------------------
    assign ex_entry_get = {mem_done, alu_done, branch_done};

    // WBC done outputs (Mapped to 5 cores)
    assign ex_done        = {mem_done, alu_done, branch_done};
    assign ex_done_pc    = {pc_mem, pc_alu[2], pc_alu[1], pc_alu[0], pc_branch};
    assign ex_done_phyreg = {rd_mem, rd_alu[2], rd_alu[1], rd_alu[0], rd_branch};
    
    assign ex_done_branch    = branch_taken;
    assign ex_done_branch_pc = branch_tgt_pc;

    // Write back logic mapping (to write inside PRF)
    assign prf_write_we   = {mem_we, alu_we, branch_we};
    assign prf_write_addr = {rd_mem, rd_alu[2], rd_alu[1], rd_alu[0], rd_branch};
    assign prf_write_data = {mem_proc_rdata, alu_result[2], alu_result[1], alu_result[0], branch_rd_val};

endmodule


// =============================================================================
// 💡 Dummy Simulation Modules (Allows standalone compilation)
// =============================================================================

module rv32i_decoder #(
    parameter int IS_INST_BITWIDTH = 32,
    parameter int IS_INST_REGS = 32,
    parameter int IS_INST_OPERANDS = 2,
    parameter int IS_INST_IMM = 32,
    parameter int EX_INST_MICROOP_BITWIDTH = 5,
    parameter int STRUCT_EX_PATH = 3,
    localparam int REG_ADDR_WIDTH = $clog2(IS_INST_REGS),
    localparam int EX_PATH_ADDR_WIDTH = $clog2(STRUCT_EX_PATH)
) (
    input  wire [IS_INST_BITWIDTH-1:0]           inst_i,
    output reg  [REG_ADDR_WIDTH-1:0]             rd_o,
    output reg  [(IS_INST_OPERANDS*REG_ADDR_WIDTH)-1:0] rs_o,
    output reg                                   exception_o,
    output reg                                   newreg_alloc_o,
    output reg                                   jump_o,
    output reg                                   jump_reg_o,
    output reg                                   branch_o,
    output reg  [EX_PATH_ADDR_WIDTH-1:0]         expath_o,
    output reg  [EX_INST_MICROOP_BITWIDTH-1:0]   microop_o,
    output reg  [IS_INST_IMM-1:0]                imm_o
);
    // Simple mock logic for demonstration
    always @(*) begin
        rd_o           = inst_i[11:7];
        rs_o           = {inst_i[24:20], inst_i[19:15]};
        exception_o    = 1'b0;
        newreg_alloc_o = (rd_o != 0);
        jump_o         = (inst_i[6:0] == 7'b1101111); // JAL
        jump_reg_o     = (inst_i[6:0] == 7'b1100111); // JALR
        branch_o       = (inst_i[6:0] == 7'b1100011); // Branch
        
        // Select path
        if (jump_o || jump_reg_o || branch_o) begin
            expath_o = 0; // Branch path
        end else if (inst_i[6:0] == 7'b0000011 || inst_i[6:0] == 7'b0100011) begin
            expath_o = 2; // Memory path
        end else begin
            expath_o = 1; // ALU path
        end

        microop_o      = inst_i[14:12]; // funct3 as microop
        imm_o          = {{20{inst_i[31]}}, inst_i[31:20]}; // default I-Type imm
    end
endmodule


module branch_ex #(
    parameter int IS_INST_PC_BITWIDTH = 32
) (
    input  wire        run_i,
    input  wire [4:0]  microop_i,
    input  wire [31:0] rs1_i,
    input  wire [31:0] rs2_i,
    input  wire [31:0] imm_i,
    input  wire [31:0] pc_i,
    output reg  [31:0] new_pc_o,
    output reg  [31:0] return_pc_o,
    output reg         we_o,
    output reg         branch_o,
    output reg         done_o
);
    always @(*) begin
        new_pc_o    = pc_i + imm_i;
        return_pc_o = pc_i + 4;
        we_o        = 1'b0;
        branch_o    = 1'b0;
        done_o      = run_i;

        if (run_i) begin
            case (microop_i[2:0])
                3'b000: branch_o = (rs1_i == rs2_i); // BEQ
                3'b001: branch_o = (rs1_i != rs2_i); // BNE
                default: branch_o = 1'b0;
            endcase
        end
    end
endmodule


module alu_ex (
    input  wire        run_i,
    input  wire [4:0]  microop_i,
    input  wire [31:0] rs1_i,
    input  wire [31:0] rs2_i,
    input  wire [31:0] imm_i,
    output reg  [31:0] alu_result_o,
    output reg         we_o,
    output reg         done_o
);
    always @(*) begin
        alu_result_o = 0;
        we_o         = run_i;
        done_o       = run_i;
        if (run_i) begin
            case (microop_i[2:0])
                3'b000: alu_result_o = rs1_i + imm_i; // ADDI
                3'b010: alu_result_o = rs1_i - rs2_i; // SUB
                3'b111: alu_result_o = rs1_i & rs2_i; // AND
                default: alu_result_o = rs1_i + rs2_i;
            endcase
        end
    end
endmodule


module mem_ex (
    input  wire        clk,
    input  wire        reset_n,
    input  wire        run_i,
    input  wire [4:0]  microop_i,
    input  wire [31:0] rs1_i,
    input  wire [31:0] rs2_i,
    input  wire [31:0] imm_i,
    output reg  [31:0] rdata_proc_o,
    output reg         re_vmem_o,
    output reg         we_vmem_o,
    output reg  [31:0] addr_vmem_o,
    output reg  [3:0]  strb_vmem_o,
    input  wire [31:0] rdata_vmem_i,
    output reg  [31:0] wdata_vmem_o,
    input  wire        ready_vmem_i,
    output reg         we_proc_o,
    output reg         done_o
);
    always @(*) begin
        re_vmem_o    = run_i && (microop_i[2:0] == 3'b000); // Load
        we_vmem_o    = run_i && (microop_i[2:0] == 3'b001); // Store
        addr_vmem_o  = rs1_i + imm_i;
        strb_vmem_o  = 4'b1111;
        wdata_vmem_o = rs2_i;
        rdata_proc_o = rdata_vmem_i;
        we_proc_o    = re_vmem_o; // Write back to registers only on Load
        done_o       = run_i && ready_vmem_i;
    end
endmodule
