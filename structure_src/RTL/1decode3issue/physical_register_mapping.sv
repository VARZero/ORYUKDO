`timescale 1ns / 1ps
//
//`include "../memories.sv"
//`include "../position_splitter.sv"

module physical_register_mapping #(
    // Dynamic Schedular Description
    parameter DECODE_NEW_INST          = 1,
    parameter PHYREG_NUM               = 64,
    parameter IST_ENTRY_NUM            = 128,
    parameter EX_PATH_NUM              = 3,
    parameter PRM_ENTRY_BUFFER         = 4,
    parameter PRM_ENTRY_UPDATE         = 3,
    parameter PRM_READY_OUT_FIFO_DEPTH = 32,
    parameter RS_ENTRY_NUM             = 16,
    parameter UNALLOCATE_PHYREG        = 4,

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
    localparam BITWIDTH_PHYREG_BUFFER                   = $clog2(PRM_ENTRY_BUFFER+1),
    localparam BITWIDTH_IST_ENTRY_NUM                   = $clog2(IST_ENTRY_NUM),
    localparam BITWIDTH_INST_NUM_OF_LOGICAL_REGISTER    = $clog2(INST_NUM_OF_LOGICAL_REGISTER),
    
    localparam RS_PUSH_WIDTH        = PRM_ENTRY_UPDATE + DECODE_NEW_INST,

    localparam PRM_READY_OUT_WIDTH  = BITWIDTH_PHYREG_NUM + BITWIDTH_IST_ENTRY_NUM,

    // (Autogenerate) Field of Allocator in Physical Register Manager
    localparam PRM_ALLOCATE_BITWIDTH        = BITWIDTH_PHYREG_NUM * DECODE_NEW_INST,
    localparam PRM_UNALLOCATE_BITWIDTH      = BITWIDTH_PHYREG_NUM * UNALLOCATE_PHYREG,

    localparam BLOCKING_LIMIT               = PRM_ENTRY_BUFFER - DECODE_NEW_INST
) (
    input                                       clk,
    input                                       reset_n,

    // Allocators
    input  wire [DECODE_NEW_INST-1:0]           i_allocate_position,
        // <- Physical Register Manager Allocator
    output wire [DECODE_NEW_INST-1:0]           o_prm_allocate_valid,
    output wire [PRM_ALLOCATE_BITWIDTH-1:0]     o_prm_allocate_phyreg,
        // -> Physical Register Manager Unallocator
    input  wire [UNALLOCATE_PHYREG-1:0]           i_prm_unallocate_valid,
    input  wire [PRM_UNALLOCATE_BITWIDTH-1:0]     i_prm_unallocate_phyreg,

        // -> Physical Register Manager Opreands Update
    input  wire [(DECODE_NEW_INST*INST_OPREANDS)-1:0]                          i_prm_istindex_valid,
    input  wire [(BITWIDTH_PHYREG_NUM*(DECODE_NEW_INST*INST_OPREANDS))-1:0]    i_prm_istindex_phyreg,
    input  wire [(BITWIDTH_IST_ENTRY_NUM*(DECODE_NEW_INST*INST_OPREANDS))-1:0] i_prm_istindex_istidx,
    
    // Update Ready Field
        // <- Physical Register Manager Opreands POP
    output wire [(PRM_ENTRY_UPDATE)-1:0]                                       o_ready_update_valid,
    input  wire [(PRM_ENTRY_UPDATE)-1:0]                                       i_ready_update_get,
    output wire [(BITWIDTH_PHYREG_NUM*PRM_ENTRY_UPDATE)-1:0]                   o_ready_update_phyreg,
    output wire [(BITWIDTH_IST_ENTRY_NUM*PRM_ENTRY_UPDATE)-1:0]                o_ready_update_istidx,

        // -> WB Physical Register Ready
    input  wire [EX_PATH_NUM-1:0] i_wb_done,
    input  wire [(EX_PATH_NUM*BITWIDTH_PHYREG_NUM)-1:0] i_wb_done_phyreg,

    // Block
    output wire o_prm_active
);
    wire allocator_active;

    // Allocate PHYREG
    allocator_start_one #(
    	.NUM_OF_ENTRIES (PHYREG_NUM),
        .UNALLOCATES    (UNALLOCATE_PHYREG),
        .ALLOCATES      (DECODE_NEW_INST)
    ) U_ALLOCATE_PHYREG (
        .clk                    (clk),
        .reset_n                (reset_n),
        .unallocate_valid_i     (i_prm_unallocate_valid),
        .unallocate_entries_i   (i_prm_unallocate_phyreg),
        .allocating_i           (i_allocate_position),
    	.allocate_valid_o       (o_prm_allocate_valid),
        .allocate_entries_o     (o_prm_allocate_phyreg),
    	.init_done              (allocator_active)
    );

    // PHYREG Counter
    reg  [PHYREG_NUM-1:0]                                                 cnt_blocking, cnt_blocking_set, cnt_blocking_reset;
    always @(posedge clk or negedge reset_n) begin
        if (reset_n == 1'b0) cnt_blocking <= 0;
        else                 cnt_blocking <= ( cnt_blocking_set & ~cnt_blocking_reset );
    end
    wire [(BITWIDTH_PHYREG_BUFFER*EX_PATH_NUM)-1:0]                       pop_phyreg_buf_cnt;
    wire [( BITWIDTH_PHYREG_BUFFER*(DECODE_NEW_INST*INST_OPREANDS) )-1:0] opreands_phyreg_buf_cnt;
    reg  [(DECODE_NEW_INST*INST_OPREANDS)-1:0]                            update_prm_istindex_valid;
    reg  [( BITWIDTH_PHYREG_BUFFER*(DECODE_NEW_INST*INST_OPREANDS) )-1:0] update_phyreg_buf_cnt;
    reg  [DECODE_NEW_INST-1:0]                                            target_phyreg[0:PHYREG_NUM-1];
    reg  [(DECODE_NEW_INST*INST_OPREANDS)-1:0]                            map_table_write_valid[0:PRM_ENTRY_BUFFER-1];

    reg  [DECODE_NEW_INST-1:0]                                            suffix_or[0:PHYREG_NUM-1];

    reg  [BITWIDTH_PHYREG_BUFFER-1:0]                                     cnt_phyreg_position[0:(DECODE_NEW_INST*INST_OPREANDS)-1][0:(DECODE_NEW_INST*INST_OPREANDS)-1];

    reg  [BITWIDTH_PHYREG_BUFFER-1:0]                                     cnt_phyreg_buf_split[0:DECODE_NEW_INST-1][0:INST_OPREANDS-1];
    reg  [BITWIDTH_PHYREG_NUM-1:0]                                        newentry_phyreg_split[0:DECODE_NEW_INST-1][0:INST_OPREANDS-1];
    reg  [BITWIDTH_IST_ENTRY_NUM-1:0]                                     newentry_istnum_split[0:DECODE_NEW_INST-1][0:INST_OPREANDS-1];

    integer split_inst_cnt, split_opreand_cnt, init_idx, phyreg_idx, sum_bit_idx;
    always @(*) begin
        cnt_blocking_set = cnt_blocking;
        // Initial
        update_prm_istindex_valid = 0; update_phyreg_buf_cnt = 0;
        for (init_idx = 0; init_idx < PHYREG_NUM; init_idx = init_idx+1) begin
            target_phyreg[init_idx] = 0;
        end
        for (init_idx = 0; init_idx < PRM_ENTRY_BUFFER; init_idx = init_idx+1) begin
            map_table_write_valid[init_idx] = 0;
        end
        for (init_idx = 0; init_idx < (DECODE_NEW_INST*INST_OPREANDS); init_idx = init_idx+1) begin
            for (int i = 0; i < (DECODE_NEW_INST*INST_OPREANDS); i++) begin
                cnt_phyreg_position[init_idx][i] = 0;
            end
        end

        // Split fields and Check PHYREG fading
        for (split_inst_cnt = 0; split_inst_cnt < DECODE_NEW_INST; split_inst_cnt = split_inst_cnt+1) begin
            for (split_opreand_cnt = 0; split_opreand_cnt < INST_OPREANDS; split_opreand_cnt = split_opreand_cnt+1) begin
                cnt_phyreg_buf_split[split_inst_cnt][split_opreand_cnt]
                    = opreands_phyreg_buf_cnt[ (BITWIDTH_PHYREG_BUFFER*( (split_inst_cnt*INST_OPREANDS) + split_opreand_cnt )) +: BITWIDTH_PHYREG_BUFFER ];

                newentry_phyreg_split[split_inst_cnt][split_opreand_cnt]
                    = i_prm_istindex_phyreg[ (BITWIDTH_PHYREG_NUM*( (split_inst_cnt*INST_OPREANDS) + split_opreand_cnt )) +: BITWIDTH_PHYREG_NUM ];
                newentry_istnum_split[split_inst_cnt][split_opreand_cnt]
                    = i_prm_istindex_istidx[ (BITWIDTH_IST_ENTRY_NUM*( (split_inst_cnt*INST_OPREANDS) + split_opreand_cnt )) +: BITWIDTH_IST_ENTRY_NUM ];
                
                if (i_prm_istindex_valid[ (split_inst_cnt*INST_OPREANDS)+split_opreand_cnt ]) begin
                    target_phyreg[ newentry_phyreg_split[split_inst_cnt][split_opreand_cnt] ][split_inst_cnt] = 1'b1;
                end
            end
        end

        // Suffix OR Logic
        for (phyreg_idx = 0; phyreg_idx < PHYREG_NUM; phyreg_idx = phyreg_idx+1) begin
            suffix_or[phyreg_idx][DECODE_NEW_INST-1] = 1'b0;
            for (split_inst_cnt = DECODE_NEW_INST-2; split_inst_cnt >= 0; split_inst_cnt = split_inst_cnt+1) begin
                suffix_or[phyreg_idx][split_inst_cnt] 
                    = suffix_or[phyreg_idx][split_inst_cnt+1] | target_phyreg[phyreg_idx][split_inst_cnt+1];
            end
        end

        // Prefix Sum Logic
        for (split_inst_cnt = 0; split_inst_cnt < DECODE_NEW_INST; split_inst_cnt = split_inst_cnt+1) begin
            for (split_opreand_cnt = 0; split_opreand_cnt < INST_OPREANDS; split_opreand_cnt = split_opreand_cnt+1) begin
                cnt_phyreg_position[split_inst_cnt][split_opreand_cnt] = cnt_phyreg_buf_split[split_inst_cnt][split_opreand_cnt];

                for (sum_bit_idx = 0; sum_bit_idx < DECODE_NEW_INST; sum_bit_idx = sum_bit_idx+1) begin
                    cnt_phyreg_position[split_inst_cnt][split_opreand_cnt] 
                        += ( (target_phyreg[ newentry_phyreg_split[split_inst_cnt][split_opreand_cnt] ][sum_bit_idx] )? 1'b1 : 1'b0 );
                end
            end
        end
        
        // Valid signal generate
        for (split_inst_cnt = 0; split_inst_cnt < DECODE_NEW_INST; split_inst_cnt = split_inst_cnt+1) begin
        for (split_opreand_cnt = 0; split_opreand_cnt < INST_OPREANDS; split_opreand_cnt = split_opreand_cnt+1) begin
            if (target_phyreg[ newentry_phyreg_split[split_inst_cnt][split_opreand_cnt] ][split_inst_cnt]) begin
                map_table_write_valid[ cnt_phyreg_buf_split[split_inst_cnt][split_opreand_cnt] ]
                                     [(split_inst_cnt*INST_OPREANDS) + split_opreand_cnt] = 1'b1;

                if (!suffix_or[ newentry_phyreg_split[split_inst_cnt][split_opreand_cnt] ][split_inst_cnt]) begin 
                    // 뒤에 활성화 된 비트가 없을때
                    update_prm_istindex_valid[(split_inst_cnt*INST_OPREANDS) + split_opreand_cnt] = 1'b1;
                    update_phyreg_buf_cnt[(BITWIDTH_PHYREG_BUFFER*( (split_inst_cnt*INST_OPREANDS)+split_opreand_cnt )) +: BITWIDTH_PHYREG_BUFFER] 
                        = cnt_phyreg_position[split_inst_cnt][split_opreand_cnt];

                    if ( cnt_phyreg_position[split_inst_cnt][split_opreand_cnt] > (BLOCKING_LIMIT) ) begin
                        cnt_blocking_set[ newentry_phyreg_split[split_inst_cnt][split_opreand_cnt] ] = 1'b1;
                    end
                end
            end
        end
        end

    end
    regfile #(
        .READ_CHANNEL  ( EX_PATH_NUM+(DECODE_NEW_INST*INST_OPREANDS) ),
        .WRITE_CHANNEL ( EX_PATH_NUM+(DECODE_NEW_INST*INST_OPREANDS) ),
        .ENTRIES       (PHYREG_NUM),
        .REG_WIDTH     (BITWIDTH_PHYREG_BUFFER)
    ) U_PHYREG_CNT_REG (
        .clk                 (clk),
        .reset_n             (reset_n),
        .i_read_addresses    ({i_wb_done_phyreg, i_prm_istindex_phyreg}),
        .i_write_wes         ({i_wb_done, update_prm_istindex_valid}),
        .i_write_addresses   ({i_wb_done_phyreg, i_prm_istindex_phyreg}),
        .i_write_data        ({ {(EX_PATH_NUM*BITWIDTH_PHYREG_BUFFER){1'b0}}, update_phyreg_buf_cnt}),
        .o_read_data         ({pop_phyreg_buf_cnt, opreands_phyreg_buf_cnt})
    );

    // PHYREG Mapping IST Entry
    wire [(BITWIDTH_IST_ENTRY_NUM*EX_PATH_NUM)-1:0]                     out_wb_istentries[0:PRM_ENTRY_BUFFER-1];
    reg  [(PRM_READY_OUT_WIDTH*PRM_ENTRY_BUFFER)-1:0]                   out_istentries_fifo_push[0:EX_PATH_NUM-1];
    reg  [BITWIDTH_PHYREG_NUM-1:0]                                      out_istentries_fifo_push_PRM[0:EX_PATH_NUM-1];
    reg  [BITWIDTH_IST_ENTRY_NUM-1:0]                                   out_istentries_fifo_push_IST[0:PRM_ENTRY_BUFFER-1][0:EX_PATH_NUM-1];
    integer ist_entrybuf_idx, ist_expath_idx;
    always @(*) begin
        cnt_blocking_reset = 0;
        // to out FIFO
        for (ist_expath_idx = 0; ist_expath_idx < EX_PATH_NUM; ist_expath_idx = ist_expath_idx+1) begin
            out_istentries_fifo_push_PRM[ist_expath_idx] = i_wb_done_phyreg[(BITWIDTH_PHYREG_NUM*ist_expath_idx) +: BITWIDTH_PHYREG_NUM];
            for (ist_entrybuf_idx = 0; ist_entrybuf_idx < PRM_ENTRY_BUFFER; ist_entrybuf_idx = ist_entrybuf_idx+1) begin
                out_istentries_fifo_push_IST[ist_entrybuf_idx][ist_expath_idx]
                    = out_wb_istentries[ist_entrybuf_idx][( BITWIDTH_IST_ENTRY_NUM * ist_expath_idx ) +: BITWIDTH_IST_ENTRY_NUM];
            end
        end

        for (ist_expath_idx = 0; ist_expath_idx < EX_PATH_NUM; ist_expath_idx = ist_expath_idx+1) begin
            out_istentries_fifo_push[ist_expath_idx] = 0;
            if (i_wb_done[ist_expath_idx]) begin
                cnt_blocking_reset[out_istentries_fifo_push_PRM[ist_expath_idx]] = 1'b1;
                for (ist_entrybuf_idx = 0; ist_entrybuf_idx < PRM_ENTRY_BUFFER; ist_entrybuf_idx = ist_entrybuf_idx+1) begin
                    out_istentries_fifo_push[ist_expath_idx][( PRM_READY_OUT_WIDTH * ist_entrybuf_idx ) +: PRM_READY_OUT_WIDTH]
                        = {out_istentries_fifo_push_PRM[ist_expath_idx], out_istentries_fifo_push_IST[ist_entrybuf_idx][ist_expath_idx]};
                end
            end
        end
    end
    genvar phyreg_buf_idx;
    generate
        for (phyreg_buf_idx = 0; phyreg_buf_idx < PRM_ENTRY_BUFFER; phyreg_buf_idx = phyreg_buf_idx+1) begin
            regfile #(
                .READ_CHANNEL  (EX_PATH_NUM),
                .WRITE_CHANNEL ((DECODE_NEW_INST*INST_OPREANDS)),
                .ENTRIES       (PHYREG_NUM),
                .REG_WIDTH     (BITWIDTH_IST_ENTRY_NUM)
            ) U_PHYREG_BUF (
                .clk                 (clk),
                .reset_n             (reset_n),
                .i_read_addresses    (i_wb_done_phyreg),
                .i_write_wes         (map_table_write_valid[phyreg_buf_idx]),
                .i_write_addresses   (i_prm_istindex_phyreg),
                .i_write_data        (i_prm_istindex_istidx),
                .o_read_data         (out_wb_istentries[phyreg_buf_idx])
            );
        end
    endgenerate

    // Output FIFO
    wire [1:0]                         o_ready_update_valid_out[0:PRM_ENTRY_UPDATE-1];
    wire [PRM_ENTRY_UPDATE-1:0]        fifo_available;
    wire [(PRM_READY_OUT_WIDTH*2)-1:0] ready_out_fifo_out[0:PRM_ENTRY_UPDATE-1];
    reg  [PRM_ENTRY_BUFFER-1:0]        push_valid_position[0:PRM_ENTRY_UPDATE-1];
    reg  [BITWIDTH_PHYREG_BUFFER-1:0]  cnt_phyreg_pop_split;
    integer update_idx, pos_idx;
    always @(*) begin
        cnt_phyreg_pop_split = 0;
        for (update_idx = 0; update_idx < PRM_ENTRY_UPDATE; update_idx = update_idx+1) begin
            push_valid_position[update_idx] = 1'b0;
            if (i_wb_done[update_idx]) begin
                cnt_phyreg_pop_split = pop_phyreg_buf_cnt[(BITWIDTH_PHYREG_BUFFER*update_idx) +: BITWIDTH_PHYREG_BUFFER];
                for (pos_idx = 0; pos_idx < PRM_ENTRY_BUFFER; pos_idx = pos_idx+1) begin
                    if (pos_idx < cnt_phyreg_pop_split)
                        push_valid_position[update_idx][pos_idx] = 1'b1;
                end
            end
        end
    end
    genvar ready_update_fifo;
    generate
        for (ready_update_fifo = 0; ready_update_fifo < PRM_ENTRY_UPDATE; ready_update_fifo = ready_update_fifo+1) begin
            fifo_ordering_position #(
            	.PUSH_DATA  (PRM_ENTRY_BUFFER),
            	.POP_DATA   (2),
            	.ENTRY_WIDTH(PRM_READY_OUT_WIDTH),
            	.FIFO_DEPTH (PRM_READY_OUT_FIFO_DEPTH)
            ) U_PRM_OUT_FIFO (
            	.clk                (clk),
            	.reset_n            (reset_n),
            	.push_valid_i       (push_valid_position[ready_update_fifo]),
            	.push_data_i        (out_istentries_fifo_push[ready_update_fifo]),
            	.pop_get_i          ({1'b0, i_ready_update_get[ready_update_fifo]}),
            	.pop_valid_o        (o_ready_update_valid_out[ready_update_fifo]),
            	.pop_data_o         (ready_out_fifo_out[ready_update_fifo]),
            	.push_available_o   (fifo_available[ready_update_fifo])
            );

            assign o_ready_update_phyreg[(BITWIDTH_PHYREG_NUM*ready_update_fifo) +: BITWIDTH_PHYREG_NUM] 
                = ready_out_fifo_out[ready_update_fifo][PRM_READY_OUT_WIDTH-1:BITWIDTH_IST_ENTRY_NUM];
            assign o_ready_update_istidx[(BITWIDTH_IST_ENTRY_NUM*ready_update_fifo) +: BITWIDTH_IST_ENTRY_NUM] 
                = ready_out_fifo_out[ready_update_fifo][BITWIDTH_IST_ENTRY_NUM-1:0];
            assign o_ready_update_valid[ready_update_fifo] = o_ready_update_valid_out[ready_update_fifo][0];
        end
    endgenerate

    assign o_prm_active = allocator_active & (&o_prm_allocate_valid) & (&fifo_available) & ~(|cnt_blocking);

endmodule
