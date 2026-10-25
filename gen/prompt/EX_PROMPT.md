# EULSUKDO Execution Core (EX) Generator Prompt Template

This prompt is a template used to generate a high-quality, synthesizable SystemVerilog (SV) execution core (e.g., ALU, Branch Unit, FPU, Memory Access Unit, etc.) via an LLM. It is designed to fully align with the EULSUKDO Out-of-Order Scheduler wrapper interface.

---

## [LLM PROMPT] Synthesizable SystemVerilog Execution Core (EX) Generator

You are an expert digital hardware design engineer specializing in high-performance Out-of-Order (OoO) processor subsystems. Your task is to design a **synthesizable SystemVerilog Execution Core (EX)** module that receives issued execution details from the EULSUKDO Scheduler (Reservation Station), executes the operation, and reports the writeback/completion status.

### 1. Module Specification & Interface Requirements

The module you generate must strictly comply with the following structural parameters and port definitions.

#### A. Hardware Parameters
* `IS_INST_PC_BITWIDTH` (Default: 32): Bit-width of the instruction Program Counter (PC).
* `IS_INST_IMM` (Default: 32): Bit-width of the instruction immediate value.
* `EX_INST_MICROOP_BITWIDTH` (Default: 5): Bit-width of the micro-operation (uop) control code.
* `STRUCT_PHYREGS` (Default: 64): Total number of physical registers in the Physical Register File (PRF).
* `LATENCY` (Default: 1): Execution latency in clock cycles. 
  * If `LATENCY = 0`, it must be designed as a purely combinational logic bypass.
  * If `LATENCY >= 1`, it must include a pipeline register chain of exactly that number of clock cycles.

#### B. Input and Output Ports
```systemverilog
module eulsukdo_ex_core_template #(
    parameter int IS_INST_PC_BITWIDTH     = 32,
    parameter int IS_INST_IMM            = 32,
    parameter int EX_INST_MICROOP_BITWIDTH = 5,
    parameter int STRUCT_PHYREGS           = 64,
    parameter int LATENCY                  = 1,
    localparam int PHYREG_IDX_WIDTH        = $clog2(STRUCT_PHYREGS)
) (
    input  wire                             clk,
    input  wire                             reset_n,

    // 1. Issue Interface (From Scheduler Reservation Station)
    input  wire                             i_issue_valid,
    input  wire [EX_INST_MICROOP_BITWIDTH-1:0] i_issue_uop,
    input  wire [IS_INST_PC_BITWIDTH-1:0]   i_issue_pc,
    input  wire [IS_INST_IMM-1:0]          i_issue_imm,
    input  wire [PHYREG_IDX_WIDTH-1:0]     i_issue_rd_phy,      // Destination physical register index
    input  wire                            i_issue_rd_alloc,    // Destination register allocation flag
    input  wire [31:0]                      i_issue_src1_val,    // Operand 1 value read from PRF
    input  wire [31:0]                      i_issue_src2_val,    // Operand 2 value read from PRF
    output wire                             o_issue_ready,       // Core ready to accept new input (Backpressure)

    // 2. Writeback / Done Interface (To Scheduler Register / ROB)
    output wire                             o_wb_valid,          // Operation completion valid signal
    output wire [IS_INST_PC_BITWIDTH-1:0]   o_wb_pc,             // Completed instruction's PC
    output wire [PHYREG_IDX_WIDTH-1:0]     o_wb_rd_phy,         // Completed destination physical register
    output wire                            o_wb_rd_alloc,
    output wire [31:0]                      o_wb_result,         // Operation result data
    
    // Branch Resolution (Only relevant if this is a Branch Unit; otherwise tie to 0)
    output wire                             o_wb_branch_taken,   // Branch execution outcome (taken or not)
    output wire [IS_INST_PC_BITWIDTH-1:0]   o_wb_branch_target   // Resolved branch target PC address
);
```

### 2. Design Requirements

1. **Pipeline Latency Handling**:
   * If `LATENCY == 0`, assign inputs directly to the outputs in the same cycle with no clock delay.
   * If `LATENCY >= 1`, implement a sequential pipeline register chain (`always_ff @(posedge clk or negedge reset_n)`) to shift data, control flags (`rd_phy`, `rd_alloc`), and the valid status by exactly the specified number of cycles.
2. **Execution Logic**:
   * Implement execution operations based on the `i_issue_uop` code.
   * **[Insert core type here: e.g., ALU / Multiplier / Branch / Memory Address Generator]**
3. **Reset and Flow Control**:
   * On asynchronous reset (`reset_n == 0`), clear all internal control registers and pipeline valid flags to `0`.
   * Manage the `o_issue_ready` backpressure signal properly when pipeline stages or buffer resources are full.
4. **Strict SystemVerilog Style**:
   * Use `always_comb` and `always_ff` blocks cleanly.
   * Do not mix combinational and sequential assignments. Ensure code is fully synthesizable and free of implicit latches.

---

### 3. Example Request Context

Please generate a **[Insert core type here: e.g., ALU / FPU / Branch / MEM]** core supporting the following settings:
* **Microop Definitions**:
  * `5'h01`: ADD / SUB
  * `5'h02`: SLL / SRL / SRA
  * `5'h03`: AND / OR / XOR
* **Latency**: `LATENCY = 1`
* **Additional Instructions**: Comment the pipeline stages clearly so that internal data registers and control status registers can be easily traced.
