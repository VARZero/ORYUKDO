# EULSUKDO ISA Decoder Generator Prompt Template

This prompt is a template used to generate a synthesizable, high-quality SystemVerilog (SV) instruction decoder (e.g., RV32I Decoder) via an LLM. It decodes a 32-bit instruction word into logical registers, sign-extended immediate values, branch control flags, and EULSUKDO execution path port mappings.

---

## [LLM PROMPT] Synthesizable SystemVerilog ISA Decoder Generator

You are a digital design engineer specializing in high-performance Out-of-Order processor frontend pipelines. Your task is to design a **synthesizable SystemVerilog ISA Decoder** module that decodes a 32-bit instruction word and extracts destination/source logical register indices, immediate fields, branch/jump control flags, and EULSUKDO execution port indices (`expath`).

### 1. Module Specification & Interface Requirements

The module you generate must strictly comply with the following structural parameters and port definitions.

#### A. Hardware Parameters
* `IS_INST_BITWIDTH` (Default: 32): Bit-width of the instruction word.
* `IS_INST_REGS` (Default: 32): Number of logical registers (e.g., 32 registers x0~x31 for RV32I).
* `IS_INST_OPERANDS` (Default: 2): Maximum number of source operand registers (rs1, rs2, totaling 2).
* `IS_INST_IMM` (Default: 32): Bit-width of the output sign-extended immediate value.
* `EX_INST_MICROOP_BITWIDTH` (Default: 5): Bit-width of the micro-operation (uop) control code.
* `STRUCT_EX_PATH` (Default: 3): Number of physical execution paths (cores list ports) available in the scheduler.

#### B. Input and Output Ports
```systemverilog
module rv32i_decoder #(
    parameter int IS_INST_BITWIDTH         = 32,
    parameter int IS_INST_REGS             = 32,
    parameter int IS_INST_OPERANDS         = 2,
    parameter int IS_INST_IMM              = 32,
    parameter int EX_INST_MICROOP_BITWIDTH = 5,
    parameter int STRUCT_EX_PATH           = 3,
    
    localparam int LOGICAL_REG_IDX_WIDTH   = $clog2(IS_INST_REGS),
    localparam int EX_PATH_IDX_WIDTH       = $clog2(STRUCT_EX_PATH)
) (
    input  wire [IS_INST_BITWIDTH-1:0]                      inst_i,

    // 1. Register Index Decodes
    output reg  [LOGICAL_REG_IDX_WIDTH-1:0]                 rd_o,
    output reg  [(IS_INST_OPERANDS*LOGICAL_REG_IDX_WIDTH)-1:0] rs_o, // Vector bundle: [rs2, rs1]

    // 2. Control Flags
    output reg                                              exception_o,      // Asserted high if illegal instruction is detected
    output reg                                              newreg_alloc_o,   // Asserted high if destination register (rd) needs allocation
    output reg                                              jump_o,           // Asserted high for unconditional jumps (e.g., JAL)
    output reg                                              jump_reg_o,       // Asserted high for indirect jumps (e.g., JALR)
    output reg                                              branch_o,         // Asserted high for conditional branches (e.g., BEQ, BNE)

    // 3. Execution Mapping
    output reg  [EX_PATH_IDX_WIDTH-1:0]                      expath_o,         // Identifies which execution core port to route to
    output reg  [EX_INST_MICROOP_BITWIDTH-1:0]              microop_o,        // Detailed operation code for the execution unit
    output reg  [IS_INST_IMM-1:0]                           imm_o             // Extracted and sign-extended immediate value
);
```

### 2. Design Requirements

1. **Pure Combinational Logic**:
   * The decoder must resolve instruction details in a single cycle. Use purely combinational blocks (`always_comb`).
   * Avoid creating latch structures. Ensure that all output ports are assigned default values at the beginning of the `always_comb` block before any conditional logic.
2. **Immediate Decoding & Sign-Extension**:
   * Perform proper sign-extension according to the instruction format (e.g., I-type, S-type, B-type, U-type, J-type) using standard RISC-V bit-slice mapping:
     * **I-type**: `{{20{inst_i[31]}}, inst_i[31:20]}`
     * **S-type**: `{{20{inst_i[31]}}, inst_i[31:25], inst_i[11:7]}`
     * **B-type**: `{{19{inst_i[31]}}, inst_i[31], inst_i[7], inst_i[30:25], inst_i[11:8], 1'b0}`
     * **U-type**: `{inst_i[31:12], 12'b0}`
     * **J-type**: `{{11{inst_i[31]}}, inst_i[31], inst_i[19:12], inst_i[20], inst_i[30:21], 1'b0}`
3. **Execution Path Mapping (`expath_o`)**:
   * Assign `expath_o` to match the exact hardware port index configuration.
   * **[Insert expath allocation mapping rules here: e.g., 0 = Branch, 1 = ALU, 2 = Memory]**
4. **Micro-op Code Assignment (`microop_o`)**:
   * Translate the opcode and function fields into the internal micro-operation code format defined for the execution units (e.g., ADD=1, SUB=2).

---

### 3. Example Request Context

Please generate an RV32I-compliant decoder supporting the following execution path assignment:
* **Target Instruction Set**: RV32I Base Instruction Set
* **Execution Path Port Allocation (`expath_o`)**:
  * `expath_o = 0`: ALU instructions (ADD, SUB, SLL, SLT, SLTU, XOR, SRL, SRA, OR, AND, ADDI, SLTI, SLTIU, XORI, SRLI, SRAI, ORI, ANDI, LUI, AUIPC)
  * `expath_o = 1`: Branch/Jump instructions (BEQ, BNE, BLT, BGE, BLTU, BGEU, JAL, JALR)
  * `expath_o = 2`: Memory load/store instructions (LB, LH, LW, LBU, LHU, SB, SH, SW)
* **Additional Guidance**: Ensure that any unsupported opcode triggers the `exception_o` signal to high, while forcing `rd_o`, `rs_o`, and `imm_o` to `0` for safety.
