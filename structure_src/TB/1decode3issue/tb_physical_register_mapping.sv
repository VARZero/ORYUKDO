`timescale 1ns / 1ps

module tb_physical_register_mapping ();

    // Dynamic Schedular Description
    parameter DECODE_NEW_INST          = 1;
    parameter PHYREG_NUM               = 64;
    parameter IST_ENTRY_NUM            = 128;
    parameter EX_PATH_NUM              = 3;
    parameter PRM_ENTRY_BUFFER         = 4;
    parameter PRM_ENTRY_UPDATE         = 3;
    parameter PRM_READY_OUT_FIFO_DEPTH = 32;
    parameter RS_ENTRY_NUM             = 16;
    parameter UNALLOCATE_PHYREG        = 4;

    // Instruction Field Description
    parameter INST_PC_WIDTH                 = 32;
    parameter INST_BITWIDTH                 = 32;
    parameter INST_OPCODE_WIDTH             = 7;
    parameter INST_OPTIONAL_OPCODE_WIDTH    = 10;
    parameter INST_IMM_WIDTH                = 32;
    parameter INST_NUM_OF_LOGICAL_REGISTER  = 32;
    parameter INST_OPREANDS                 = 2;

    // Internal Field Description (Decoder Compiler (or Human) Generate)
    parameter MICROOP_WIDTH                 = 5; // Micro-OP is not contained information of EX_PATH

    // (Autogenerate) Elements
    localparam BITWIDTH_EX_PATH_NUM                     = $clog2(EX_PATH_NUM);
    localparam BITWIDTH_PHYREG_NUM                      = $clog2(PHYREG_NUM);
    localparam BITWIDTH_PHYREG_BUFFER                   = $clog2(PRM_ENTRY_BUFFER);
    localparam BITWIDTH_IST_ENTRY_NUM                   = $clog2(IST_ENTRY_NUM);
    localparam BITWIDTH_INST_NUM_OF_LOGICAL_REGISTER    = $clog2(INST_NUM_OF_LOGICAL_REGISTER);
    
    localparam RS_PUSH_WIDTH        = PRM_ENTRY_UPDATE + DECODE_NEW_INST;

    localparam PRM_READY_OUT_WIDTH  = BITWIDTH_PHYREG_NUM + BITWIDTH_IST_ENTRY_NUM;

    // (Autogenerate) Field of Allocator in Physical Register Manager
    localparam PRM_ALLOCATE_BITWIDTH        = BITWIDTH_PHYREG_NUM * DECODE_NEW_INST;
    localparam PRM_UNALLOCATE_BITWIDTH      = BITWIDTH_PHYREG_NUM * UNALLOCATE_PHYREG;

    reg                                                                clk;
    reg                                                                reset_n;

    // Allocators
    reg [DECODE_NEW_INST-1:0]                                          i_allocate_position;
        // <- Physical Register Manager Allocator
    wire [DECODE_NEW_INST-1:0]                                         o_prm_allocate_valid;
    wire [PRM_ALLOCATE_BITWIDTH-1:0]                                   o_prm_allocate_phyreg;
        // -> Physical Register Manager Unallocator
    reg [UNALLOCATE_PHYREG-1:0]                                        i_prm_unallocate_valid;
    reg [PRM_UNALLOCATE_BITWIDTH-1:0]                                  i_prm_unallocate_phyreg;

        // -> Physical Register Manager Opreands Update
    reg [(DECODE_NEW_INST*INST_OPREANDS)-1:0]                          i_prm_istindex_valid;
    reg [(BITWIDTH_PHYREG_NUM*(DECODE_NEW_INST*INST_OPREANDS))-1:0]    i_prm_istindex_phyreg;
    reg [(BITWIDTH_IST_ENTRY_NUM*(DECODE_NEW_INST*INST_OPREANDS))-1:0] i_prm_istindex_istidx;
    
    // Update Ready Field
        // <- Physical Register Manager Opreands POP
    wire [(PRM_ENTRY_UPDATE)-1:0]                                      o_ready_update_valid;
    reg  [(PRM_ENTRY_UPDATE)-1:0]                                      i_ready_update_get;
    wire [(BITWIDTH_PHYREG_NUM*PRM_ENTRY_UPDATE)-1:0]                  o_ready_update_phyreg;
    wire [(BITWIDTH_IST_ENTRY_NUM*PRM_ENTRY_UPDATE)-1:0]               o_ready_update_istidx;

        // -> WB Physical Register Ready
    reg [EX_PATH_NUM-1:0]                                              i_wb_done;
    reg [(EX_PATH_NUM*BITWIDTH_PHYREG_NUM)-1:0]                        i_wb_done_phyreg;

    // Block
    wire                                                               o_prm_active;

    physical_register_mapping #(
        .DECODE_NEW_INST              (DECODE_NEW_INST),
        .PHYREG_NUM                   (PHYREG_NUM),
        .IST_ENTRY_NUM                (IST_ENTRY_NUM),
        .EX_PATH_NUM                  (EX_PATH_NUM),
        .PRM_ENTRY_BUFFER             (PRM_ENTRY_BUFFER),
        .PRM_ENTRY_UPDATE             (PRM_ENTRY_UPDATE),
        .PRM_READY_OUT_FIFO_DEPTH     (PRM_READY_OUT_FIFO_DEPTH),
        .RS_ENTRY_NUM                 (RS_ENTRY_NUM),
        .UNALLOCATE_PHYREG            (UNALLOCATE_PHYREG),
        .INST_PC_WIDTH                (INST_PC_WIDTH),
        .INST_BITWIDTH                (INST_BITWIDTH),
        .INST_OPCODE_WIDTH            (INST_OPCODE_WIDTH),
        .INST_OPTIONAL_OPCODE_WIDTH   (INST_OPTIONAL_OPCODE_WIDTH),
        .INST_IMM_WIDTH               (INST_IMM_WIDTH),
        .INST_NUM_OF_LOGICAL_REGISTER (INST_NUM_OF_LOGICAL_REGISTER),
        .INST_OPREANDS                (INST_OPREANDS),
        .MICROOP_WIDTH                (MICROOP_WIDTH)
    ) dut (
        .clk                          (clk),
        .reset_n                      (reset_n),
        .i_allocate_position          (i_allocate_position),
        .o_prm_allocate_valid         (o_prm_allocate_valid),
        .o_prm_allocate_phyreg        (o_prm_allocate_phyreg),
        .i_prm_unallocate_valid       (i_prm_unallocate_valid),
        .i_prm_unallocate_phyreg      (i_prm_unallocate_phyreg),
        .i_prm_istindex_valid         (i_prm_istindex_valid),
        .i_prm_istindex_phyreg        (i_prm_istindex_phyreg),
        .i_prm_istindex_istidx        (i_prm_istindex_istidx),
        .o_ready_update_valid         (o_ready_update_valid),
        .i_ready_update_get           (i_ready_update_get),
        .o_ready_update_phyreg        (o_ready_update_phyreg),
        .o_ready_update_istidx        (o_ready_update_istidx),
        .i_wb_done                    (i_wb_done),
        .i_wb_done_phyreg             (i_wb_done_phyreg),
        .o_prm_active                 (o_prm_active)
    );

    always #5 clk = ~clk;

    reg active[0:PHYREG_NUM-1];
    int active_cnt;
    int ist;

    task test_variable_init;
        for (int i = 0; i < PHYREG_NUM; i++) active[i] = 0;
        active_cnt = 0;
        ist = 0;
    endtask

    task ist_push;
        int sel        = $urandom % PHYREG_NUM;
        int rand_cycle = $urandom % PHYREG_NUM;
        int k          = 0;
        i_prm_istindex_valid = 0;
        for (int i_inst = 0; i_inst < DECODE_NEW_INST; i_inst++) begin
        for (int i_opr = 0; i_opr < INST_OPREANDS; i_opr++) begin
            if ( ( $urandom % 2 ) == 0 ) begin
                i_prm_istindex_valid[(DECODE_NEW_INST*i_inst)+i_opr] = 1'b1;

                k = 0;
                for (int j = 0; j < rand_cycle;) begin
                    if (k >= PHYREG_NUM) k = 0;
                    else k++;

                    if (!active[k]) j++;
                end
                active_cnt++;
                active[k] = 1'b1;
                i_prm_istindex_phyreg[(BITWIDTH_PHYREG_NUM* ((DECODE_NEW_INST*i_inst)+i_opr) ) +: BITWIDTH_PHYREG_NUM] = k;
                i_prm_istindex_istidx[(BITWIDTH_IST_ENTRY_NUM* ((DECODE_NEW_INST*i_inst)+i_opr) ) +: BITWIDTH_IST_ENTRY_NUM] = ist;
            end
        end
            ist++;
            if (ist >= IST_ENTRY_NUM) ist = 0;

        end
    endtask

    task get_phyreg;
        int get_reg = $urandom % (DECODE_NEW_INST+1);
        for (int i = 0; i < DECODE_NEW_INST; i++) begin
            if (!active[i]) active[i] = 1'b1;
        end
    endtask

    task wb_insert;
        int sel        = $urandom % PHYREG_NUM;
        int rand_cycle = $urandom % PHYREG_NUM;
        int k          = 0;
        i_wb_done = 0;
        if (active_cnt > 0) begin
            for (int i = 0; i < EX_PATH_NUM; i++) begin
                if ( ( $urandom % 16 ) == 0 ) begin
                    i_wb_done[i] = 1'b1;

                    k = 0;
                    for (int j = 0; j < rand_cycle;) begin
                        if (k >= PHYREG_NUM) k = 0;
                        else k++;

                        if (active[k]) j++;
                    end

                    active_cnt--;
                    active[k] = 1'b0;
                    i_wb_done_phyreg[(BITWIDTH_PHYREG_NUM * i) +: BITWIDTH_PHYREG_NUM] = k;
                end
            end
        end
    endtask

    task check_ready;
    endtask

    initial begin
        clk = 0; reset_n = 0;
        i_allocate_position = 0;
        i_prm_unallocate_valid = 0;
        i_prm_unallocate_phyreg = 0;
        i_prm_istindex_valid = 0;
        i_prm_istindex_phyreg = 0;
        i_prm_istindex_istidx = 0;
        i_ready_update_get = {PRM_ENTRY_UPDATE{1'b1}};
        i_wb_done = 0;
        i_wb_done_phyreg = 0;

        test_variable_init();

        @(negedge clk);
        @(negedge clk);
        reset_n = 1'b1;
        @(negedge clk);

        wait(o_prm_active);

        @(posedge clk);
        repeat(30) begin
            @(posedge clk);
            #1; wb_insert(); #1; ist_push(); 
        end
        
        $finish;
    end

endmodule
