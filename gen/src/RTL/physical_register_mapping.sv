`timescale 1ns / 1ps

module physical_register_mapping #(
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
    localparam int _BITWIDTH_LOW_STRUCT_PRM_ENTRY_BUFFER = $clog2(STRUCT_PRM_ENTRY_BUFFER + 1),

    localparam int _STRUCT_EX_OUT_RESULT_ALL            = STRUCT_EX_OUT_RESULT_SUM,

    // Allocator & Unallocator flat widths
    localparam int PRM_ALLOCATE_BITWIDTH                = _BITWIDTH_LOW_STRUCT_PHYREGS * STRUCT_DECODE_NEW_INST,
    localparam int PRM_UNALLOCATE_BITWIDTH              = _BITWIDTH_LOW_STRUCT_PHYREGS * STRUCT_UNALLOCATE_PHYREG,

    // Composite ID pair bitwidth [Instruction State Entry Number][Physical Register Number]
    localparam int _BITWIDTH_CMB_IST_ENTRYnPHYREG       = _BITWIDTH_LOW_STRUCT_INST_STATE_ENTRIES + _BITWIDTH_LOW_STRUCT_PHYREGS,

    localparam int BLOCKING_LIMIT                       = STRUCT_PRM_ENTRY_BUFFER - STRUCT_DECODE_NEW_INST,
    
    // Output Ready ID pair width [Physical Register Number][Instruction State Entry Number]
    localparam int PRM_READY_OUT_WIDTH                  = _BITWIDTH_LOW_STRUCT_PHYREGS + _BITWIDTH_LOW_STRUCT_INST_STATE_ENTRIES,
    
    // Splitter Channel width: contains buffer push data & valid mask
    localparam int SPLIT_CHANNEL_WIDTH                  = (STRUCT_PRM_ENTRY_BUFFER * PRM_READY_OUT_WIDTH) + STRUCT_PRM_ENTRY_BUFFER
) (
    input  wire                                                 clk,
    input  wire                                                 reset_n,

    // NEL interface for new register allocate (i/o_nel_allocate_*)
    input  wire [STRUCT_DECODE_NEW_INST-1:0]                    i_nel_allocate_get,  // allocate position from decoder
    output wire [STRUCT_DECODE_NEW_INST-1:0]                    o_nel_allocate_valid,
    output wire [PRM_ALLOCATE_BITWIDTH-1:0]                     o_nel_allocate_phyreg,

    // FCL interface for register unallocate/free (i/o_fcl_unallocate_*)
    input  wire [STRUCT_UNALLOCATE_PHYREG-1:0]                  i_fcl_unallocate_valid,
    input  wire [PRM_UNALLOCATE_BITWIDTH-1:0]                   i_fcl_unallocate_phyreg,

    // IST interface to receive waiting operands (i/o_ist_unallocate_*)
    input  wire [(STRUCT_DECODE_NEW_INST * IS_INST_OPERANDS)-1:0] i_ist_unallocate_valid,
    input  wire [(STRUCT_DECODE_NEW_INST * IS_INST_OPERANDS * _BITWIDTH_CMB_IST_ENTRYnPHYREG)-1:0] i_ist_unallocate_data,

    // WBC interface to receive completed registers (i/o_wbc_phyreg_*)
    input  wire [_STRUCT_EX_OUT_RESULT_ALL-1:0]                  i_wbc_phyreg_valid,
    input  wire [(_STRUCT_EX_OUT_RESULT_ALL * _BITWIDTH_LOW_STRUCT_PHYREGS)-1:0] i_wbc_phyreg_data,

    // IST interface to push ready registers (i/o_ist_ready_phyreg_*)
    output wire [STRUCT_PRM_ENTRY_UPDATE-1:0]                   o_ist_ready_phyreg_valid,
    output wire [(STRUCT_PRM_ENTRY_UPDATE * _BITWIDTH_CMB_IST_ENTRYnPHYREG)-1:0] o_ist_ready_phyreg_data,
    input  wire [STRUCT_PRM_ENTRY_UPDATE-1:0]                   i_ist_ready_phyreg_get,

    // PRM active status (resource pressure block indicator)
    output wire                                                 o_prm_active
);

    wire allocator_active;

    // Allocate physical registers
    allocator_start_one #(
        .NUM_OF_ENTRIES (STRUCT_PHYREGS),
        .UNALLOCATES    (STRUCT_UNALLOCATE_PHYREG),
        .ALLOCATES      (STRUCT_DECODE_NEW_INST)
    ) U_ALLOCATE_PHYREG (
        .clk                 (clk),
        .reset_n             (reset_n),
        .unallocate_valid_i  (i_fcl_unallocate_valid),
        .unallocate_entries_i(i_fcl_unallocate_phyreg),
        .allocating_i        (i_nel_allocate_get),
        .allocate_valid_o    (o_nel_allocate_valid),
        .allocate_entries_o  (o_nel_allocate_phyreg),
        .init_done           (allocator_active)
    );

    // Blocking status registers for registers with full buffers
    reg  [STRUCT_PHYREGS-1:0] cnt_blocking;
    reg  [STRUCT_PHYREGS-1:0] cnt_blocking_set;
    reg  [STRUCT_PHYREGS-1:0] cnt_blocking_reset;

    always @(posedge clk or negedge reset_n) begin
        if (reset_n == 1'b0) cnt_blocking <= 0;
        else                 cnt_blocking <= (cnt_blocking_set & ~cnt_blocking_reset);
    end

    // Unpack incoming IST waiting operands
    wire [STRUCT_DECODE_NEW_INST * IS_INST_OPERANDS - 1:0]                     wait_valid;
    wire [_BITWIDTH_LOW_STRUCT_PHYREGS-1:0]                                    wait_phyreg [0:STRUCT_DECODE_NEW_INST * IS_INST_OPERANDS - 1];
    wire [_BITWIDTH_LOW_STRUCT_INST_STATE_ENTRIES-1:0]                        wait_istidx [0:STRUCT_DECODE_NEW_INST * IS_INST_OPERANDS - 1];
    
    // Flat equivalents for regfile connections
    wire [(STRUCT_DECODE_NEW_INST * IS_INST_OPERANDS * _BITWIDTH_LOW_STRUCT_PHYREGS)-1:0] flat_wait_phyreg;
    wire [(STRUCT_DECODE_NEW_INST * IS_INST_OPERANDS * _BITWIDTH_LOW_STRUCT_INST_STATE_ENTRIES)-1:0] flat_wait_istidx;

    assign wait_valid = i_ist_unallocate_valid;

    genvar w;
    generate
        for (w = 0; w < STRUCT_DECODE_NEW_INST * IS_INST_OPERANDS; w = w + 1) begin : gen_unpack_ist_unallocate
            assign wait_istidx[w] = i_ist_unallocate_data[w * _BITWIDTH_CMB_IST_ENTRYnPHYREG + _BITWIDTH_LOW_STRUCT_PHYREGS +: _BITWIDTH_LOW_STRUCT_INST_STATE_ENTRIES];
            assign wait_phyreg[w] = i_ist_unallocate_data[w * _BITWIDTH_CMB_IST_ENTRYnPHYREG +: _BITWIDTH_LOW_STRUCT_PHYREGS];
            
            assign flat_wait_phyreg[w * _BITWIDTH_LOW_STRUCT_PHYREGS +: _BITWIDTH_LOW_STRUCT_PHYREGS] = wait_phyreg[w];
            assign flat_wait_istidx[w * _BITWIDTH_LOW_STRUCT_INST_STATE_ENTRIES +: _BITWIDTH_LOW_STRUCT_INST_STATE_ENTRIES] = wait_istidx[w];
        end
    endgenerate

    // Buffer count management
    wire [(_BITWIDTH_LOW_STRUCT_PRM_ENTRY_BUFFER * _STRUCT_EX_OUT_RESULT_ALL)-1:0]            pop_phyreg_buf_cnt;
    wire [(_BITWIDTH_LOW_STRUCT_PRM_ENTRY_BUFFER * (STRUCT_DECODE_NEW_INST * IS_INST_OPERANDS))-1:0] operands_phyreg_buf_cnt;
    reg  [(STRUCT_DECODE_NEW_INST * IS_INST_OPERANDS)-1:0]                                   update_istindex_valid;
    reg  [(_BITWIDTH_LOW_STRUCT_PRM_ENTRY_BUFFER * (STRUCT_DECODE_NEW_INST * IS_INST_OPERANDS))-1:0] update_phyreg_buf_cnt;

    reg  [STRUCT_DECODE_NEW_INST-1:0]                                                      target_phyreg [0:STRUCT_PHYREGS-1];
    reg  [(STRUCT_DECODE_NEW_INST * IS_INST_OPERANDS)-1:0]                                   map_table_write_valid [0:STRUCT_PRM_ENTRY_BUFFER-1];
    reg  [STRUCT_DECODE_NEW_INST-1:0]                                                      suffix_or [0:STRUCT_PHYREGS-1];

    reg  [_BITWIDTH_LOW_STRUCT_PRM_ENTRY_BUFFER-1:0]                                         cnt_phyreg_position [0:STRUCT_DECODE_NEW_INST-1][0:IS_INST_OPERANDS-1];
    reg  [_BITWIDTH_LOW_STRUCT_PRM_ENTRY_BUFFER-1:0]                                         cnt_phyreg_buf_split [0:STRUCT_DECODE_NEW_INST-1][0:IS_INST_OPERANDS-1];

    integer split_inst_cnt, split_opreand_cnt, init_idx, phyreg_idx, sum_bit_idx;
    
    always @(*) begin
        cnt_blocking_set = cnt_blocking;
        update_istindex_valid = 0; 
        update_phyreg_buf_cnt = 0;

        for (init_idx = 0; init_idx < STRUCT_PHYREGS; init_idx = init_idx + 1) begin
            target_phyreg[init_idx] = 0;
        end
        for (init_idx = 0; init_idx < STRUCT_PRM_ENTRY_BUFFER; init_idx = init_idx + 1) begin
            map_table_write_valid[init_idx] = 0;
        end
        for (integer inst_idx = 0; inst_idx < STRUCT_DECODE_NEW_INST; inst_idx = inst_idx + 1) begin
            for (integer opr_idx = 0; opr_idx < IS_INST_OPERANDS; opr_idx = opr_idx + 1) begin
                cnt_phyreg_position[inst_idx][opr_idx] = 0;
            end
        end

        // Extract buffer count for incoming operand registers
        for (split_inst_cnt = 0; split_inst_cnt < STRUCT_DECODE_NEW_INST; split_inst_cnt = split_inst_cnt + 1) begin
            for (split_opreand_cnt = 0; split_opreand_cnt < IS_INST_OPERANDS; split_opreand_cnt = split_opreand_cnt + 1) begin
                integer flat_idx = split_inst_cnt * IS_INST_OPERANDS + split_opreand_cnt;
                
                cnt_phyreg_buf_split[split_inst_cnt][split_opreand_cnt] = 
                    operands_phyreg_buf_cnt[(_BITWIDTH_LOW_STRUCT_PRM_ENTRY_BUFFER * flat_idx) +: _BITWIDTH_LOW_STRUCT_PRM_ENTRY_BUFFER];
                
                if (wait_valid[flat_idx]) begin
                    target_phyreg[wait_phyreg[flat_idx]][split_inst_cnt] = 1'b1;
                end
            end
        end

        // Suffix OR logic to handle in-flight dependencies in the same cycle
        for (phyreg_idx = 0; phyreg_idx < STRUCT_PHYREGS; phyreg_idx = phyreg_idx + 1) begin
            suffix_or[phyreg_idx][STRUCT_DECODE_NEW_INST-1] = 1'b0;
            for (split_inst_cnt = STRUCT_DECODE_NEW_INST-2; split_inst_cnt >= 0; split_inst_cnt = split_inst_cnt - 1) begin
                suffix_or[phyreg_idx][split_inst_cnt] = 
                    suffix_or[phyreg_idx][split_inst_cnt+1] | target_phyreg[phyreg_idx][split_inst_cnt+1];
            end
        end

        // Prefix Sum logic to compute new buffer counts
        for (split_inst_cnt = 0; split_inst_cnt < STRUCT_DECODE_NEW_INST; split_inst_cnt = split_inst_cnt + 1) begin
            for (split_opreand_cnt = 0; split_opreand_cnt < IS_INST_OPERANDS; split_opreand_cnt = split_opreand_cnt + 1) begin
                integer flat_idx = split_inst_cnt * IS_INST_OPERANDS + split_opreand_cnt;
                
                cnt_phyreg_position[split_inst_cnt][split_opreand_cnt] = cnt_phyreg_buf_split[split_inst_cnt][split_opreand_cnt];

                for (sum_bit_idx = 0; sum_bit_idx < STRUCT_DECODE_NEW_INST; sum_bit_idx = sum_bit_idx + 1) begin
                    if (sum_bit_idx <= split_inst_cnt) begin
                        cnt_phyreg_position[split_inst_cnt][split_opreand_cnt] += 
                            (target_phyreg[wait_phyreg[flat_idx]][sum_bit_idx] ? 1'b1 : 1'b0);
                    end
                end
            end
        end
        
        // Output write enable generation
        for (split_inst_cnt = 0; split_inst_cnt < STRUCT_DECODE_NEW_INST; split_inst_cnt = split_inst_cnt + 1) begin
            for (split_opreand_cnt = 0; split_opreand_cnt < IS_INST_OPERANDS; split_opreand_cnt = split_opreand_cnt + 1) begin
                integer flat_idx = split_inst_cnt * IS_INST_OPERANDS + split_opreand_cnt;
                
                if (target_phyreg[wait_phyreg[flat_idx]][split_inst_cnt]) begin
                    map_table_write_valid[cnt_phyreg_buf_split[split_inst_cnt][split_opreand_cnt]][flat_idx] = 1'b1;

                    if (!suffix_or[wait_phyreg[flat_idx]][split_inst_cnt]) begin 
                        // Last update in sequence writes back new counter
                        update_istindex_valid[flat_idx] = 1'b1;
                        update_phyreg_buf_cnt[(_BITWIDTH_LOW_STRUCT_PRM_ENTRY_BUFFER * flat_idx) +: _BITWIDTH_LOW_STRUCT_PRM_ENTRY_BUFFER] = 
                            cnt_phyreg_position[split_inst_cnt][split_opreand_cnt];

                        if (cnt_phyreg_position[split_inst_cnt][split_opreand_cnt] > BLOCKING_LIMIT) begin
                            cnt_blocking_set[wait_phyreg[flat_idx]] = 1'b1;
                        end
                    end
                end
            end
        end
    end

    // Counter RF for buffer positions
    regfile #(
        .READ_CHANNEL ( _STRUCT_EX_OUT_RESULT_ALL + (STRUCT_DECODE_NEW_INST * IS_INST_OPERANDS) ),
        .WRITE_CHANNEL( _STRUCT_EX_OUT_RESULT_ALL + (STRUCT_DECODE_NEW_INST * IS_INST_OPERANDS) ),
        .ENTRIES      ( STRUCT_PHYREGS ),
        .REG_WIDTH    ( _BITWIDTH_LOW_STRUCT_PRM_ENTRY_BUFFER )
    ) U_PHYREG_CNT_REG (
        .clk              (clk),
        .reset_n          (reset_n),
        .i_read_addresses ({i_wbc_phyreg_data, flat_wait_phyreg}),
        .i_write_wes      ({i_wbc_phyreg_valid, update_istindex_valid}),
        .i_write_addresses({i_wbc_phyreg_data, flat_wait_phyreg}),
        .i_write_data     ({ {(_STRUCT_EX_OUT_RESULT_ALL * _BITWIDTH_LOW_STRUCT_PRM_ENTRY_BUFFER){1'b0}}, update_phyreg_buf_cnt}),
        .o_read_data      ({pop_phyreg_buf_cnt, operands_phyreg_buf_cnt})
    );

    // Physical register mapping buffers (IST ID storage)
    wire [(_BITWIDTH_LOW_STRUCT_INST_STATE_ENTRIES * _STRUCT_EX_OUT_RESULT_ALL)-1:0] out_wb_istentries [0:STRUCT_PRM_ENTRY_BUFFER-1];

    genvar phyreg_buf_idx;
    generate
        for (phyreg_buf_idx = 0; phyreg_buf_idx < STRUCT_PRM_ENTRY_BUFFER; phyreg_buf_idx = phyreg_buf_idx + 1) begin : gen_prm_buffers
            regfile #(
                .READ_CHANNEL ( _STRUCT_EX_OUT_RESULT_ALL ),
                .WRITE_CHANNEL( STRUCT_DECODE_NEW_INST * IS_INST_OPERANDS ),
                .ENTRIES      ( STRUCT_PHYREGS ),
                .REG_WIDTH    ( _BITWIDTH_LOW_STRUCT_INST_STATE_ENTRIES )
            ) U_PHYREG_BUF (
                .clk              (clk),
                .reset_n          (reset_n),
                .i_read_addresses (i_wbc_phyreg_data),
                .i_write_wes      (map_table_write_valid[phyreg_buf_idx]),
                .i_write_addresses(flat_wait_phyreg),
                .i_write_data     (flat_wait_istidx),
                .o_read_data      (out_wb_istentries[phyreg_buf_idx])
            );
        end
    endgenerate

    // Unpack complete notification details and prepare push packets
    reg  [_BITWIDTH_LOW_STRUCT_PHYREGS-1:0]              done_phyreg [0:_STRUCT_EX_OUT_RESULT_ALL-1];
    reg  [_BITWIDTH_LOW_STRUCT_PRM_ENTRY_BUFFER-1:0]     done_buf_cnt [0:_STRUCT_EX_OUT_RESULT_ALL-1];
    reg  [_BITWIDTH_LOW_STRUCT_INST_STATE_ENTRIES-1:0]   done_ist_ids [0:_STRUCT_EX_OUT_RESULT_ALL-1][0:STRUCT_PRM_ENTRY_BUFFER-1];
    
    reg  [STRUCT_PRM_ENTRY_BUFFER-1:0]                    done_push_mask [0:_STRUCT_EX_OUT_RESULT_ALL-1];
    reg  [(STRUCT_PRM_ENTRY_BUFFER * PRM_READY_OUT_WIDTH)-1:0] done_fifo_data [0:_STRUCT_EX_OUT_RESULT_ALL-1];

    wire [(_STRUCT_EX_OUT_RESULT_ALL * SPLIT_CHANNEL_WIDTH)-1:0] flat_done_channel_data;

    always @(*) begin
        cnt_blocking_reset = 0;
        
        for (integer u = 0; u < _STRUCT_EX_OUT_RESULT_ALL; u = u + 1) begin
            done_phyreg[u]  = i_wbc_phyreg_data[u * _BITWIDTH_LOW_STRUCT_PHYREGS +: _BITWIDTH_LOW_STRUCT_PHYREGS];
            done_buf_cnt[u] = pop_phyreg_buf_cnt[u * _BITWIDTH_LOW_STRUCT_PRM_ENTRY_BUFFER +: _BITWIDTH_LOW_STRUCT_PRM_ENTRY_BUFFER];
            
            done_push_mask[u] = 0;
            done_fifo_data[u] = 0;

            if (i_wbc_phyreg_valid[u]) begin
                cnt_blocking_reset[done_phyreg[u]] = 1'b1;
                
                for (integer b = 0; b < STRUCT_PRM_ENTRY_BUFFER; b = b + 1) begin
                    done_ist_ids[u][b] = out_wb_istentries[b][u * _BITWIDTH_LOW_STRUCT_INST_STATE_ENTRIES +: _BITWIDTH_LOW_STRUCT_INST_STATE_ENTRIES];
                    
                    if (b < done_buf_cnt[u]) begin
                        done_push_mask[u][b] = 1'b1;
                    end
                    
                    done_fifo_data[u][b * PRM_READY_OUT_WIDTH +: PRM_READY_OUT_WIDTH] = {done_phyreg[u], done_ist_ids[u][b]};
                end
            end
        end
    end

    genvar u_idx;
    generate
        for (u_idx = 0; u_idx < _STRUCT_EX_OUT_RESULT_ALL; u_idx = u_idx + 1) begin : gen_flat_done_channel
            assign flat_done_channel_data[u_idx * SPLIT_CHANNEL_WIDTH +: SPLIT_CHANNEL_WIDTH] = {
                done_push_mask[u_idx],
                done_fifo_data[u_idx]
            };
        end
    endgenerate

    // Route valid done packets to output FIFOs using position_splitter (Gather)
    wire [_STRUCT_EX_OUT_RESULT_ALL-1:0]                  gather_valid;
    wire [(_STRUCT_EX_OUT_RESULT_ALL * SPLIT_CHANNEL_WIDTH)-1:0] gather_data;

    position_splitter #(
        .INPUT_ENTRIES(_STRUCT_EX_OUT_RESULT_ALL),
        .DATA_WIDTH   (SPLIT_CHANNEL_WIDTH)
    ) U_DONE_GATHER_SPLITTER (
        .valid_position_i(i_wbc_phyreg_valid),
        .position_data_i (flat_done_channel_data),
        .out_position_o  (gather_valid),
        .data_o          (gather_data)
    );

    // Connections to the final updated output FIFOs
    wire [1:0]                                           fifo_pop_valid [0:STRUCT_PRM_ENTRY_UPDATE-1];
    wire [STRUCT_PRM_ENTRY_UPDATE-1:0]                   fifo_available;
    wire [(PRM_READY_OUT_WIDTH * 2)-1:0]                 fifo_pop_data [0:STRUCT_PRM_ENTRY_UPDATE-1];
    
    wire [STRUCT_PRM_ENTRY_BUFFER-1:0]                   fifo_push_mask [0:STRUCT_PRM_ENTRY_UPDATE-1];
    wire [(STRUCT_PRM_ENTRY_BUFFER * PRM_READY_OUT_WIDTH)-1:0] fifo_push_data [0:STRUCT_PRM_ENTRY_UPDATE-1];

    genvar f_idx;
    generate
        for (f_idx = 0; f_idx < STRUCT_PRM_ENTRY_UPDATE; f_idx = f_idx + 1) begin : gen_prm_output_fifos
            assign fifo_push_mask[f_idx] = gather_data[f_idx * SPLIT_CHANNEL_WIDTH + (STRUCT_PRM_ENTRY_BUFFER * PRM_READY_OUT_WIDTH) +: STRUCT_PRM_ENTRY_BUFFER];
            assign fifo_push_data[f_idx] = gather_data[f_idx * SPLIT_CHANNEL_WIDTH +: (STRUCT_PRM_ENTRY_BUFFER * PRM_READY_OUT_WIDTH)];

            // Pop get control and Handshake assignment
            wire pop_get_f = i_ist_ready_phyreg_get[f_idx];
            
            fifo_ordering_position #(
                .PUSH_DATA  (STRUCT_PRM_ENTRY_BUFFER),
                .POP_DATA   (2),
                .ENTRY_WIDTH(PRM_READY_OUT_WIDTH),
                .FIFO_DEPTH (32) // static depth based on PRM_READY_OUT_FIFO_DEPTH
            ) U_PRM_OUT_FIFO (
                .clk             (clk),
                .reset_n         (reset_n),
                .push_valid_i    (fifo_push_mask[f_idx] & {STRUCT_PRM_ENTRY_BUFFER{gather_valid[f_idx]}}),
                .push_data_i     (fifo_push_data[f_idx]),
                .pop_get_i       ({1'b0, pop_get_f}),
                .pop_valid_o     (fifo_pop_valid[f_idx]),
                .pop_data_o      (fifo_pop_data[f_idx]),
                .push_available_o(fifo_available[f_idx])
            );

            // Reconstruct flat IST output pair: [Instruction State Entry Number][Physical Register Number]
            wire [_BITWIDTH_LOW_STRUCT_PHYREGS-1:0]        out_phyreg = fifo_pop_data[f_idx][PRM_READY_OUT_WIDTH-1 : _BITWIDTH_LOW_STRUCT_INST_STATE_ENTRIES];
            wire [_BITWIDTH_LOW_STRUCT_INST_STATE_ENTRIES-1:0] out_istidx = fifo_pop_data[f_idx][_BITWIDTH_LOW_STRUCT_INST_STATE_ENTRIES-1 : 0];

            assign o_ist_ready_phyreg_data[f_idx * _BITWIDTH_CMB_IST_ENTRYnPHYREG +: _BITWIDTH_CMB_IST_ENTRYnPHYREG] = {
                out_istidx,
                out_phyreg
            };
            assign o_ist_ready_phyreg_valid[f_idx] = fifo_pop_valid[f_idx][0];
        end
    endgenerate

    // PRM active status: true when allocator is ready, output FIFOs have space, and no registers are blocked
    assign o_prm_active = allocator_active & (&o_nel_allocate_valid) & (&fifo_available) & ~(|cnt_blocking);

endmodule
