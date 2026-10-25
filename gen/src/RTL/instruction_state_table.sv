`timescale 1ns / 1ps

module instruction_state_table #(
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

    localparam int RS_PUSH_WIDTH                        = STRUCT_DECODE_NEW_INST + STRUCT_PRM_ENTRY_UPDATE,

    // Bitwidths of operands and entries
    localparam int IST_BITWIDTH_OPREAND_PHYREG_FULL    = _BITWIDTH_LOW_STRUCT_PHYREGS * IS_INST_OPERANDS,
    localparam int IST_BITWIDTH_OPREAND_READY_FULL     = IS_INST_OPERANDS,
    
    // Composite bitwidths
    localparam int _BITWIDTH_CMB_FLOW_INDEXnPC          = _BITWIDTH_LOW_STRUCT_FLOW_WINDOWS + IS_INST_PC_BITWIDTH,

    // IST_READYINST_ENTRY_BITWIDTH: RS input packet width (contains EX Path)
    localparam int IST_READYINST_ENTRY_BITWIDTH         = _BITWIDTH_CMB_FLOW_INDEXnPC + 
                                                          _BITWIDTH_LOW_STRUCT_EX_PATH + 
                                                          EX_INST_MICROOP_BITWIDTH + 
                                                          IS_INST_IMM + 
                                                          _BITWIDTH_LOW_STRUCT_PHYREGS + 
                                                          IST_BITWIDTH_OPREAND_PHYREG_FULL,

    // IST_BITWIDTH: IST internal register width (contains Ready flags)
    localparam int IST_BITWIDTH                         = IST_READYINST_ENTRY_BITWIDTH + IST_BITWIDTH_OPREAND_READY_FULL,
    
    // Composite ID pair bitwidth [Instruction State Entry Number][Physical Register Number]
    localparam int _BITWIDTH_CMB_IST_ENTRYnPHYREG       = _BITWIDTH_LOW_STRUCT_INST_STATE_ENTRIES + _BITWIDTH_LOW_STRUCT_PHYREGS
) (
    input  wire                                                 clk,
    input  wire                                                 reset_n,

    // NEL interface for new instruction insert (i/o_nel_newinst_*)
    input  wire [STRUCT_DECODE_NEW_INST-1:0]                    i_nel_newinst_valid,
    input  wire [(STRUCT_DECODE_NEW_INST * IST_BITWIDTH)-1:0]   i_nel_newinst_data,
    output wire [STRUCT_DECODE_NEW_INST-1:0]                    o_nel_newinst_get,

    // PRM interface to register waiting operands (i/o_prm_wait_phyreg_*)
    output reg  [(STRUCT_DECODE_NEW_INST * IS_INST_OPERANDS)-1:0] o_prm_wait_phyreg_valid,
    output reg  [(STRUCT_DECODE_NEW_INST * IS_INST_OPERANDS * _BITWIDTH_CMB_IST_ENTRYnPHYREG)-1:0] o_prm_wait_phyreg_data,

    // PRM interface to receive ready notifications (i/o_prm_ready_phyreg_*)
    input  wire [STRUCT_PRM_ENTRY_UPDATE-1:0]                   i_prm_ready_phyreg_valid,
    input  wire [(STRUCT_PRM_ENTRY_UPDATE * _BITWIDTH_CMB_IST_ENTRYnPHYREG)-1:0] i_prm_ready_phyreg_data,
    output wire [STRUCT_PRM_ENTRY_UPDATE-1:0]                   o_prm_ready_phyreg_get,

    // RS interface to push ready commands (i/o_rs_readyinst_*)
    input  wire                                                 i_rs_readyinst_get,
    output wire [RS_PUSH_WIDTH-1:0]                             o_rs_readyinst_valid,
    output wire [(RS_PUSH_WIDTH * IST_READYINST_ENTRY_BITWIDTH)-1:0] o_rs_readyinst_data
);

    // -------------------------------------------------------------------------
    // Localparam offsets within IST entries
    // -------------------------------------------------------------------------
    localparam int IST_STARTPOINT_PHYREG          = _BITWIDTH_CMB_FLOW_INDEXnPC + _BITWIDTH_LOW_STRUCT_EX_PATH + EX_INST_MICROOP_BITWIDTH + IS_INST_IMM;
    localparam int IST_STARTPOINT_OPREAND_PHYREG  = IST_STARTPOINT_PHYREG + _BITWIDTH_LOW_STRUCT_PHYREGS;
    localparam int IST_STARTPOINT_OPREAND_READY   = IST_STARTPOINT_OPREAND_PHYREG + IST_BITWIDTH_OPREAND_PHYREG_FULL;

    wire allocator_enable;
    wire [STRUCT_DECODE_NEW_INST-1:0] new_ist_alloc_valid;

    // Handshake control
    assign o_nel_newinst_get      = allocator_enable & i_rs_readyinst_get & new_ist_alloc_valid;
    assign o_prm_ready_phyreg_get = (i_rs_readyinst_get) ? {STRUCT_PRM_ENTRY_UPDATE{1'b1}} : {STRUCT_PRM_ENTRY_UPDATE{1'b0}};

    // Allocator connections
    wire [(STRUCT_DECODE_NEW_INST*2)-1:0]                      new_ist_valid;
    wire [(STRUCT_DECODE_NEW_INST*2 * _BITWIDTH_LOW_STRUCT_INST_STATE_ENTRIES)-1:0] new_ist_num_full;
    wire [(STRUCT_DECODE_NEW_INST * _BITWIDTH_LOW_STRUCT_INST_STATE_ENTRIES)-1:0]   new_ist_num;

    assign new_ist_num = new_ist_num_full[(STRUCT_DECODE_NEW_INST * _BITWIDTH_LOW_STRUCT_INST_STATE_ENTRIES)-1:0];
    assign new_ist_alloc_valid = new_ist_valid[STRUCT_DECODE_NEW_INST-1:0];

    reg  [STRUCT_DECODE_NEW_INST-1:0]  push_rs_valid_low;
    reg  [STRUCT_PRM_ENTRY_UPDATE-1:0] push_rs_valid_high;
    assign o_rs_readyinst_valid = { push_rs_valid_high, push_rs_valid_low };

    // Splitting input data
    reg  [(IST_READYINST_ENTRY_BITWIDTH * STRUCT_DECODE_NEW_INST)-1:0] ist_entries_spread;
    reg  [(IST_BITWIDTH_OPREAND_PHYREG_FULL * STRUCT_DECODE_NEW_INST)-1:0] ist_opreands_spread;
    reg  [(IST_BITWIDTH_OPREAND_READY_FULL * STRUCT_DECODE_NEW_INST)-1:0]  ist_readys_spread;

    reg  [IST_READYINST_ENTRY_BITWIDTH-1:0]        ist_entries_split [0:STRUCT_DECODE_NEW_INST-1];
    reg  [IST_BITWIDTH_OPREAND_PHYREG_FULL-1:0]   ist_opreands_split[0:STRUCT_DECODE_NEW_INST-1];
    reg  [IST_BITWIDTH_OPREAND_READY_FULL-1:0]    ist_readys_split  [0:STRUCT_DECODE_NEW_INST-1];
    reg  [STRUCT_DECODE_NEW_INST-1:0]              ist_readys_split_opreand[0:IST_BITWIDTH_OPREAND_READY_FULL-1];

    always @(*) begin
        push_rs_valid_low = 0;
        o_prm_wait_phyreg_valid = 0;
        o_prm_wait_phyreg_data = 0;

        for (integer new_entry = 0; new_entry < STRUCT_DECODE_NEW_INST; new_entry = new_entry + 1) begin
            // Split entry data
            ist_entries_split[new_entry] = i_nel_newinst_data[(IST_BITWIDTH * new_entry) +: IST_READYINST_ENTRY_BITWIDTH];
            ist_entries_spread[(IST_READYINST_ENTRY_BITWIDTH * new_entry) +: IST_READYINST_ENTRY_BITWIDTH] = ist_entries_split[new_entry];

            // Split operands
            ist_opreands_split[new_entry] = i_nel_newinst_data[((IST_BITWIDTH * new_entry) + IST_STARTPOINT_OPREAND_PHYREG) +: IST_BITWIDTH_OPREAND_PHYREG_FULL];
            ist_opreands_spread[(IST_BITWIDTH_OPREAND_PHYREG_FULL * new_entry) +: IST_BITWIDTH_OPREAND_PHYREG_FULL] = ist_opreands_split[new_entry];

            // Split ready flags
            ist_readys_split[new_entry] = i_nel_newinst_data[((IST_BITWIDTH * new_entry) + IST_STARTPOINT_OPREAND_READY) +: IST_BITWIDTH_OPREAND_READY_FULL];
            ist_readys_spread[(IST_BITWIDTH_OPREAND_READY_FULL * new_entry) +: IST_BITWIDTH_OPREAND_READY_FULL] = ist_readys_split[new_entry];

            // Direct issue to RS if already ready
            if (&ist_readys_split[new_entry] && i_rs_readyinst_get) begin
                push_rs_valid_low[new_entry] = new_ist_alloc_valid[new_entry] & i_nel_newinst_valid[new_entry];
            end

            // PRM wait registration
            for (integer new_opr_sel = 0; new_opr_sel < IS_INST_OPERANDS; new_opr_sel = new_opr_sel + 1) begin
                if (ist_readys_split[new_entry][new_opr_sel]) begin
                    o_prm_wait_phyreg_valid[((IS_INST_OPERANDS * new_entry) + new_opr_sel)] = 1'b0;
                end else begin
                    o_prm_wait_phyreg_valid[((IS_INST_OPERANDS * new_entry) + new_opr_sel)] = 
                        (i_rs_readyinst_get) ? i_nel_newinst_valid[new_entry] & new_ist_alloc_valid[new_entry] : 1'b0;
                end
                
                // Pack [IST Entry Number][Physical Register Number] to o_prm_wait_phyreg_data
                o_prm_wait_phyreg_data[(((IS_INST_OPERANDS * new_entry) + new_opr_sel) * _BITWIDTH_CMB_IST_ENTRYnPHYREG) +: _BITWIDTH_CMB_IST_ENTRYnPHYREG] = {
                    new_ist_num[(new_entry * _BITWIDTH_LOW_STRUCT_INST_STATE_ENTRIES) +: _BITWIDTH_LOW_STRUCT_INST_STATE_ENTRIES],
                    ist_opreands_split[new_entry][(new_opr_sel * _BITWIDTH_LOW_STRUCT_PHYREGS) +: _BITWIDTH_LOW_STRUCT_PHYREGS]
                };
            end
        end

        for (integer new_entry = 0; new_entry < STRUCT_DECODE_NEW_INST; new_entry = new_entry + 1) begin
            for (integer new_opr_sel = 0; new_opr_sel < IS_INST_OPERANDS; new_opr_sel = new_opr_sel + 1) begin
                ist_readys_split_opreand[new_opr_sel][new_entry] = ist_readys_split[new_entry][new_opr_sel];
            end
        end
    end
    
    assign o_rs_readyinst_data[(STRUCT_DECODE_NEW_INST * IST_READYINST_ENTRY_BITWIDTH)-1:0] = ist_entries_spread;

    // Unpack ready notifications from PRM
    wire [STRUCT_PRM_ENTRY_UPDATE-1:0]                   i_ready_update_valid  = i_prm_ready_phyreg_valid;
    wire [_BITWIDTH_LOW_STRUCT_PHYREGS-1:0]              i_ready_update_phyreg [0:STRUCT_PRM_ENTRY_UPDATE-1];
    wire [_BITWIDTH_LOW_STRUCT_INST_STATE_ENTRIES-1:0]   i_ready_update_istidx [0:STRUCT_PRM_ENTRY_UPDATE-1];
    reg  [(STRUCT_PRM_ENTRY_UPDATE * _BITWIDTH_LOW_STRUCT_INST_STATE_ENTRIES)-1:0] i_ready_update_istidx_flat;

    genvar m;
    generate
        for (m = 0; m < STRUCT_PRM_ENTRY_UPDATE; m = m + 1) begin : gen_unpack_prm_ready
            assign i_ready_update_phyreg[m] = i_prm_ready_phyreg_data[m * _BITWIDTH_CMB_IST_ENTRYnPHYREG +: _BITWIDTH_LOW_STRUCT_PHYREGS];
            assign i_ready_update_istidx[m] = i_prm_ready_phyreg_data[m * _BITWIDTH_CMB_IST_ENTRYnPHYREG + _BITWIDTH_LOW_STRUCT_PHYREGS +: _BITWIDTH_LOW_STRUCT_INST_STATE_ENTRIES];
            
            always @(*) begin
                i_ready_update_istidx_flat[m * _BITWIDTH_LOW_STRUCT_INST_STATE_ENTRIES +: _BITWIDTH_LOW_STRUCT_INST_STATE_ENTRIES] = i_ready_update_istidx[m];
            end
        end
    endgenerate

    // Read stored operand values from Entry Table
    wire [(STRUCT_PRM_ENTRY_UPDATE * IST_BITWIDTH_OPREAND_PHYREG_FULL)-1:0] done_opreands;
    reg  [_BITWIDTH_LOW_STRUCT_PHYREGS-1:0]                               done_opreands_split[0:STRUCT_PRM_ENTRY_UPDATE-1][0:IS_INST_OPERANDS-1];
    
    always @(*) begin
        for (integer done_entries = 0; done_entries < STRUCT_PRM_ENTRY_UPDATE; done_entries = done_entries + 1) begin
            for (integer opreand_sel = 0; opreand_sel < IS_INST_OPERANDS; opreand_sel = opreand_sel + 1) begin
                done_opreands_split[done_entries][opreand_sel] = 
                    done_opreands[((IST_BITWIDTH_OPREAND_PHYREG_FULL * done_entries) + (_BITWIDTH_LOW_STRUCT_PHYREGS * opreand_sel)) +: _BITWIDTH_LOW_STRUCT_PHYREGS];
            end
        end
    end

    // Ready Checker logic for updated entries
    wire [STRUCT_PRM_ENTRY_UPDATE-1:0]                done_readys       [0:IST_BITWIDTH_OPREAND_READY_FULL-1];
    reg  [STRUCT_PRM_ENTRY_UPDATE-1:0]                done_readys_update[0:IST_BITWIDTH_OPREAND_READY_FULL-1];
    reg  [IST_BITWIDTH_OPREAND_READY_FULL-1:0] done_readys_spread;

    always @(*) begin
        push_rs_valid_high = 0;

        for (integer comp_opr = 0; comp_opr < STRUCT_PRM_ENTRY_UPDATE; comp_opr = comp_opr + 1) begin
            for (integer opr_sel = 0; opr_sel < IS_INST_OPERANDS; opr_sel = opr_sel + 1) begin
                if (done_opreands_split[comp_opr][opr_sel] == i_ready_update_phyreg[comp_opr])
                    done_readys_update[opr_sel][comp_opr] = (i_ready_update_valid[comp_opr]) ? 1'b1 : 1'b0;
                else 
                    done_readys_update[opr_sel][comp_opr] = 1'b0;
            end
        end
        
        for (integer opr_sel = 0; opr_sel < IS_INST_OPERANDS; opr_sel = opr_sel + 1) begin
            for (integer comp_opr = 0; comp_opr < STRUCT_PRM_ENTRY_UPDATE; comp_opr = comp_opr + 1) begin
                done_readys_update[opr_sel][comp_opr] = done_readys_update[opr_sel][comp_opr] | done_readys[opr_sel][comp_opr];
            end
        end

        for (integer comp_opr = 0; comp_opr < STRUCT_PRM_ENTRY_UPDATE; comp_opr = comp_opr + 1) begin
            done_readys_spread = 0;

            for (integer opr_sel = 0; opr_sel < IS_INST_OPERANDS; opr_sel = opr_sel + 1) begin
                done_readys_spread[opr_sel] = done_readys_update[opr_sel][comp_opr];
            end

            if ((&done_readys_spread) && i_rs_readyinst_get) begin
                push_rs_valid_high[comp_opr] = i_ready_update_valid[comp_opr];
            end
        end
    end

    // Allocate IST Entry using the system Allocator
    allocator #(
        .NUM_OF_ENTRIES (STRUCT_INST_STATE_ENTRIES),
        .UNALLOCATES    (RS_PUSH_WIDTH),
        .ALLOCATES      (STRUCT_DECODE_NEW_INST * 2)
    ) U_ALLOCATE_IST_ENTRY (
        .clk                 (clk),
        .reset_n             (reset_n),
        .unallocate_valid_i  (o_rs_readyinst_valid),
        .unallocate_entries_i({i_ready_update_istidx_flat, new_ist_num}),
        .allocating_i        ({ {STRUCT_DECODE_NEW_INST{1'b0}}, i_nel_newinst_valid & o_nel_newinst_get }),
        .allocate_valid_o    (new_ist_valid),
        .allocate_entries_o  (new_ist_num_full),
        .init_done           (allocator_enable)
    );
 
    // IST Entry table storing command fields
    regfile #(
        .READ_CHANNEL    (STRUCT_PRM_ENTRY_UPDATE),
        .WRITE_CHANNEL   (STRUCT_DECODE_NEW_INST),
        .ENTRIES         (STRUCT_INST_STATE_ENTRIES),
        .REG_WIDTH       (IST_READYINST_ENTRY_BITWIDTH)
    ) U_IST_ENTRIES (
        .clk                 (clk),
        .reset_n             (reset_n),
        .i_read_addresses    (i_ready_update_istidx_flat),
        .i_write_wes         (i_nel_newinst_valid & new_ist_alloc_valid),
        .i_write_addresses   (new_ist_num),
        .i_write_data        (ist_entries_spread),
        .o_read_data         (o_rs_readyinst_data[(STRUCT_DECODE_NEW_INST * IST_READYINST_ENTRY_BITWIDTH) +: (STRUCT_PRM_ENTRY_UPDATE * IST_READYINST_ENTRY_BITWIDTH)])
    );
    
    // IST Operands table storing physical register IDs
    regfile #(
        .READ_CHANNEL    (STRUCT_PRM_ENTRY_UPDATE),
        .WRITE_CHANNEL   (STRUCT_DECODE_NEW_INST),
        .ENTRIES         (STRUCT_INST_STATE_ENTRIES),
        .REG_WIDTH       (IST_BITWIDTH_OPREAND_PHYREG_FULL)
    ) U_IST_OPREANDS (
        .clk                 (clk),
        .reset_n             (reset_n),
        .i_read_addresses    (i_ready_update_istidx_flat),
        .i_write_wes         (i_nel_newinst_valid & new_ist_alloc_valid),
        .i_write_addresses   (new_ist_num),
        .i_write_data        (ist_opreands_spread),
        .o_read_data         (done_opreands)
    );

    // Generate ready flags storage for each operand
    genvar target_ready;
    generate
        for (target_ready = 0; target_ready < IS_INST_OPERANDS; target_ready = target_ready + 1) begin : gen_ist_ready_flags
            regfile #(
                .READ_CHANNEL    (STRUCT_PRM_ENTRY_UPDATE),
                .WRITE_CHANNEL   (STRUCT_PRM_ENTRY_UPDATE + STRUCT_DECODE_NEW_INST),
                .ENTRIES         (STRUCT_INST_STATE_ENTRIES),
                .REG_WIDTH       (1)
            ) U_IST_READY (
                .clk              (clk),
                .reset_n          (reset_n),
                .i_read_addresses (i_ready_update_istidx_flat),
                .i_write_wes      ({i_ready_update_valid & o_prm_ready_phyreg_get, i_nel_newinst_valid & new_ist_alloc_valid}),
                .i_write_addresses({i_ready_update_istidx_flat, new_ist_num}),
                .i_write_data     ({done_readys_update[target_ready], ist_readys_split_opreand[target_ready]}),
                .o_read_data      (done_readys[target_ready])
            );
        end
    endgenerate

endmodule
