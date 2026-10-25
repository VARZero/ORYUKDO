export interface CoreTypeConfig {
  id: string;
  name: string;
  count: number;
  stroke: string;
}

export interface SchedulerConfig {
  decodeWidth: number;
  phyRegs: number;
  robEntries: number;
  coresList: CoreTypeConfig[];
  prmUpdate: number;
  prmBuffer: number;
  unallocatePhyreg: number;
  flowWindows: number;
  isaName?: string;
}

export function generateRTL(config: SchedulerConfig): string {
  const {
    decodeWidth,
    phyRegs,
    robEntries,
    coresList,
    prmUpdate,
    prmBuffer,
    unallocatePhyreg,
    flowWindows,
    isaName,
  } = config;

  const totalCores = coresList.reduce((sum, c) => sum + c.count, 0);
  const exPaths = coresList.length;
  
  // Format arrays for SystemVerilog
  const rsOutEntryList = coresList.map(c => c.count).join(', ');
  const rsOutEntry = `'{${rsOutEntryList}}`;
  const exOutResult = `'{${Array(totalCores).fill(1).join(', ')}}`;

  // Comment block for breakdown of paths
  const pathsComment = coresList
    .map(c => `//    - ${c.name} Core(s): ${c.count} slot(s)`)
    .join('\n');

  return `\`timescale 1ns / 1ps

// =============================================================================
// 💡 Auto-Generated EULSUKDO Core Subsystem Wrapper
//    - Decode Width : ${decodeWidth}
//    - Issue Width  : ${totalCores}
${pathsComment}
//    - Physical Regs: ${phyRegs}
// =============================================================================

module eulsukdo_example_top #(
    parameter int IS_INST_PC_BITWIDTH           = 32,
    parameter int IS_INST_PC_STEP               = 4,
    parameter int IS_INST_BITWIDTH               = 32,
    parameter int IS_INST_REGS                   = 32,
    parameter int IS_INST_OPERANDS               = 2,
    parameter int IS_INST_IMM                    = 32,

    parameter int EX_INST_MICROOP_BITWIDTH       = 5,

    parameter int STRUCT_DECODE_NEW_INST        = ${decodeWidth},
    parameter int STRUCT_INST_STATE_ENTRIES     = ${robEntries},
    parameter int STRUCT_PHYREGS                 = ${phyRegs},
    parameter int STRUCT_EX_PATH                 = ${exPaths},
    parameter int STRUCT_RS_OUT_ENTRY [STRUCT_EX_PATH] = ${rsOutEntry},
    parameter int STRUCT_EX_CORES                = ${totalCores},
    parameter int STRUCT_EX_OUT_RESULT [STRUCT_EX_CORES] = ${exOutResult},
    parameter int STRUCT_EX_OUT_RESULT_SUM       = ${totalCores},
    parameter int STRUCT_RS_OUT_ENTRY_SUM        = ${totalCores},
    parameter int STRUCT_PRM_ENTRY_UPDATE        = ${prmUpdate},
    parameter int STRUCT_PRM_ENTRY_BUFFER        = ${prmBuffer},
    parameter int STRUCT_UNALLOCATE_PHYREG       = ${unallocatePhyreg},
    parameter int STRUCT_FLOW_WINDOWS            = ${flowWindows},
    parameter int STRUCT_FLOW_PC_MAX_RANGE       = 8,

    // Generated localparams
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

    // Instruction Memory Ports
    input  wire [STRUCT_DECODE_NEW_INST-1:0]                    i_im_inst_valid,
    input  wire [(STRUCT_DECODE_NEW_INST*IS_INST_BITWIDTH)-1:0] i_im_inst,
    output wire [STRUCT_DECODE_NEW_INST-1:0]                    o_im_inst_get,
    output wire                                                 o_im_pc_valid,
    output wire [_BITWIDTH_CMB_FLOW_INDEXnPC-1:0]               o_im_pc,

    // Virtual memory interface
    output wire                                                 re_vmem_o,
    output wire                                                 we_vmem_o,
    output wire [31:0]                                          addr_vmem_o,
    output wire [3:0]                                           strb_vmem_o,
    input  wire [31:0]                                          rdata_vmem_i,
    output wire [31:0]                                          wdata_vmem_o,
    input  wire                                                 ready_vmem_i
);

    // RS Entry bitwidth calculation
    localparam int RS_ENTRY_BITWIDTH = _BITWIDTH_CMB_FLOW_INDEXnPC + 
                                       _BITWIDTH_LOW_STRUCT_EX_PATH + 
                                       EX_INST_MICROOP_BITWIDTH + 
                                       IS_INST_IMM + 
                                       _BITWIDTH_LOW_STRUCT_PHYREGS + 
                                       (_BITWIDTH_LOW_STRUCT_PHYREGS * IS_INST_OPERANDS);

    // -------------------------------------------------------------------------
    // 1. Decoder Interface & Unpack
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

    genvar d_idx;
    generate
        for (d_idx = 0; d_idx < STRUCT_DECODE_NEW_INST; d_idx = d_idx + 1) begin : gen_decoders
            ${isaName || 'eulsukdo'}_decoder #(
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

        // Issue output
        .o_ex_entry_valid            (ex_entry_valid),
        .o_ex_entry                  (ex_entry),
        .i_ex_entry_get                (ex_entry_get),

        // Writeback inputs
        .i_ex_done                   (ex_done),
        .i_ex_done_pc                (ex_done_pc),
        .i_ex_done_phyreg            (ex_done_phyreg),
        .i_ex_done_branch            (ex_done_branch),
        .i_ex_done_branch_pc         (ex_done_branch_pc)
    );

    // -------------------------------------------------------------------------
    // 3. Physical Register File (PRF)
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
    // 4. Execution Core Mapping Matrix
    // -------------------------------------------------------------------------
    // Auto-stitched logic mapped according to dynamic issue counts:
    // Total issue width: \${_STRUCT_RS_OUT_ENTRY_ALL} ports
    
    assign ex_entry_get = ex_done;

endmodule
`;
}
