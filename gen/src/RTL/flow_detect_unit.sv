`timescale 1ns / 1ps

module flow_detect_unit #(
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
    localparam int _STRUCT_EX_OUT_RESULT_ALL            = STRUCT_EX_OUT_RESULT_SUM,

    // Range bitwidth based on STRUCT_FLOW_PC_MAX_RANGE
    localparam int BITWIDTH_PC_RANGE                    = $clog2(STRUCT_FLOW_PC_MAX_RANGE)
) (
    input  wire                                                 clk,
    input  wire                                                 reset_n,

    // Flow Control Logic interface
    output reg                                                  o_entry_active,
    output reg                                                  o_entry_free,
    input  wire                                                 i_set_start_pc_valid,
    input  wire [IS_INST_PC_BITWIDTH-1:0]                       i_set_start_pc,
    input  wire                                                 i_set_last_pc_valid,
    input  wire [IS_INST_PC_BITWIDTH-1:0]                       i_set_last_pc,
    
    // Allocate Registers inputs from NEL
    input  wire [STRUCT_DECODE_NEW_INST-1:0]                    i_nel_newpc_valid,
    input  wire [(STRUCT_DECODE_NEW_INST * IS_INST_PC_BITWIDTH)-1:0] i_nel_newpc,
    input  wire [STRUCT_DECODE_NEW_INST-1:0]                    i_nel_lastreg_valid,
    input  wire [(STRUCT_DECODE_NEW_INST * _BITWIDTH_LOW_STRUCT_PHYREGS)-1:0] i_nel_lastreg,

    // Write Back Concatenation interface
    input  wire [_STRUCT_EX_OUT_RESULT_ALL-1:0]                  i_wbc2fcl_done,
    input  wire [(_STRUCT_EX_OUT_RESULT_ALL * IS_INST_PC_BITWIDTH)-1:0] i_wbc2fcl_pc,
    
    // Physical Register Mapper interface for unallocation/free
    input  wire                                                 i_unallocate_use,
    output wire [STRUCT_UNALLOCATE_PHYREG-1:0]                   o_prm_unallocate_valid,
    output wire [(STRUCT_UNALLOCATE_PHYREG * _BITWIDTH_LOW_STRUCT_PHYREGS)-1:0] o_prm_unallocate_phyreg
);

    reg  [BITWIDTH_PC_RANGE:0]                                  entry_done_range_sum;
    reg  [IS_INST_PC_BITWIDTH-1:0]                              split_wb_pc [0:_STRUCT_EX_OUT_RESULT_ALL-1];
    
    wire [(STRUCT_UNALLOCATE_PHYREG * 2)-1:0]                   phyreg_unallocate_valid;
    wire [((STRUCT_UNALLOCATE_PHYREG * 2) * _BITWIDTH_LOW_STRUCT_PHYREGS)-1:0] phyreg_unallocate;
    wire [IS_INST_PC_BITWIDTH-1:0]                              new_range_sub_pc;

    integer target_pc;

    // FDU States
    localparam reg [1:0] UNACTIVE  = 2'b00;
    localparam reg [1:0] ACTIVE    = 2'b01;
    localparam reg [1:0] WAIT_FREE = 2'b10;
    localparam reg [1:0] FREE      = 2'b11;

    // Registers
    reg [1:0]                                                   state,      state_next;
    reg [IS_INST_PC_BITWIDTH-1:0]                               pc_start,   pc_start_next;
    reg [IS_INST_PC_BITWIDTH-1:0]                               pc_last,    pc_last_next;
    reg [BITWIDTH_PC_RANGE:0]                                   range_cnt,  range_cnt_next;
    reg [BITWIDTH_PC_RANGE:0]                                   range,      range_next;
    
    always @(posedge clk or negedge reset_n) begin
        if (reset_n == 1'b0) begin
            state     <= UNACTIVE;
            pc_start  <= 0;
            pc_last   <= 0;
            range_cnt <= 0;
            range     <= 0;
        end else begin
            state     <= state_next;
            pc_start  <= pc_start_next;
            pc_last   <= pc_last_next;
            range_cnt <= range_cnt_next;
            range     <= range_next;
        end
    end

    // State Transition
    always @(*) begin
        case (state)
            UNACTIVE: begin
                if (i_set_start_pc_valid) state_next = ACTIVE;
                else                      state_next = UNACTIVE;
            end
            ACTIVE: begin
                if (!i_set_last_pc_valid && (range_cnt >= range)) state_next = WAIT_FREE;
                else                                              state_next = ACTIVE;
            end
            WAIT_FREE: begin
                if (!i_unallocate_use) state_next = FREE;
                else                   state_next = WAIT_FREE;
            end
            FREE: begin
                if (!(|phyreg_unallocate_valid)) state_next = UNACTIVE;
                else                             state_next = FREE;
            end
            default: begin
                state_next = UNACTIVE;
            end
        endcase
    end

    // State Operations and Counter Calculations
    integer target_push_catch;
    reg [STRUCT_DECODE_NEW_INST-1:0]                            push_valid;
    reg [STRUCT_UNALLOCATE_PHYREG-1:0]                          pop_get;

    always @(*) begin
        entry_done_range_sum = 0;
        for (target_pc = 0; target_pc < _STRUCT_EX_OUT_RESULT_ALL; target_pc = target_pc + 1) begin
            split_wb_pc[target_pc] = i_wbc2fcl_pc[(IS_INST_PC_BITWIDTH * target_pc) +: IS_INST_PC_BITWIDTH];
            if (i_wbc2fcl_done[target_pc]) begin
                if ((split_wb_pc[target_pc] >= pc_start) && (split_wb_pc[target_pc] <= pc_last)) begin
                    entry_done_range_sum = entry_done_range_sum + 1;
                end
            end
        end

        case (state)
            UNACTIVE: begin
                push_valid = 0;
                pop_get    = 0;
                if (i_set_start_pc_valid) begin
                    pc_start_next   = i_set_start_pc;
                    pc_last_next    = i_set_start_pc + (STRUCT_FLOW_PC_MAX_RANGE << 2);
                    range_cnt_next  = 0;
                    range_next      = STRUCT_FLOW_PC_MAX_RANGE;
                end else begin
                    pc_start_next   = 0;
                    pc_last_next    = 0;
                    range_cnt_next  = 0;
                    range_next      = 0;
                end
            end
            ACTIVE: begin
                for (target_push_catch = 0; target_push_catch < STRUCT_DECODE_NEW_INST; target_push_catch = target_push_catch + 1) begin
                    push_valid[target_push_catch] = 
                        ((i_nel_newpc[(IS_INST_PC_BITWIDTH * target_push_catch) +: IS_INST_PC_BITWIDTH] >= pc_start) && 
                         (i_nel_newpc[(IS_INST_PC_BITWIDTH * target_push_catch) +: IS_INST_PC_BITWIDTH] <= pc_last)) ? 
                             i_nel_newpc_valid[target_push_catch] & i_nel_lastreg_valid[target_push_catch] : 1'b0;
                end
                pop_get         = 0;
                pc_start_next   = pc_start;
                pc_last_next    = (i_set_last_pc_valid) ? i_set_last_pc : pc_last;
                range_cnt_next  = range_cnt + entry_done_range_sum;
                range_next      = (i_set_last_pc_valid) ? (new_range_sub_pc / IS_INST_PC_STEP) + 1'b1 : range;
            end
            WAIT_FREE: begin
                push_valid      = 0;
                pc_start_next   = 0;
                pop_get         = 0;
                pc_last_next    = 0;
                range_cnt_next  = 0;
                range_next      = 0;
            end
            FREE: begin
                push_valid      = 0;
                pop_get         = {STRUCT_UNALLOCATE_PHYREG{1'b1}};
                pc_start_next   = 0;
                pc_last_next    = 0;
                range_cnt_next  = 0;
                range_next      = 0;
            end
            default: begin
                push_valid      = 0;
                pc_start_next   = 0;
                pop_get         = 0;
                pc_last_next    = 0;
                range_cnt_next  = 0;
                range_next      = 0;
            end
        endcase
    end

    // State Output Assignments
    always @(*) begin
        case (state)
            UNACTIVE: begin
                o_entry_active = 1'b0;
                o_entry_free   = 1'b0;
            end
            ACTIVE: begin
                o_entry_active = 1'b1;
                o_entry_free   = 1'b0;
            end
            WAIT_FREE: begin
                o_entry_active = 1'b1;
                o_entry_free   = 1'b1;
            end
            FREE: begin
                o_entry_active = 1'b1;
                o_entry_free   = 1'b1;
            end
            default: begin
                o_entry_active = 1'b0;
                o_entry_free   = 1'b0;
            end
        endcase
    end

    assign new_range_sub_pc = i_set_last_pc - pc_start;

    assign o_prm_unallocate_valid  = (state == FREE) ? phyreg_unallocate_valid[STRUCT_UNALLOCATE_PHYREG-1:0] : 0;
    assign o_prm_unallocate_phyreg = phyreg_unallocate[(STRUCT_UNALLOCATE_PHYREG * _BITWIDTH_LOW_STRUCT_PHYREGS)-1:0];

    // Store physical registers to return when FDU becomes free
    fifo_ordering_position #(
        .PUSH_DATA      (STRUCT_DECODE_NEW_INST + 1),
        .POP_DATA       (STRUCT_UNALLOCATE_PHYREG * 2),
        .ENTRY_WIDTH    (_BITWIDTH_LOW_STRUCT_PHYREGS),
        .FIFO_DEPTH     ((STRUCT_PHYREGS / (STRUCT_UNALLOCATE_PHYREG * 2)) + 1)
    ) U_END_PHYREG_STORE (
        .clk             (clk),
        .reset_n         (reset_n),
        .push_valid_i    ({1'b0, push_valid}),
        .push_data_i     ({{_BITWIDTH_LOW_STRUCT_PHYREGS{1'b0}}, i_nel_lastreg}),
        .pop_get_i       ({{STRUCT_UNALLOCATE_PHYREG{1'b0}}, pop_get}),
        .pop_valid_o     (phyreg_unallocate_valid),
        .pop_data_o      (phyreg_unallocate),
        .push_available_o()
    );

endmodule
