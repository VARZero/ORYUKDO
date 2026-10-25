`timescale 1ns / 1ps

module tb_instruction_state_table ();

    // Dynamic Schedular Description
    parameter DECODE_NEW_INST   = 1;
    parameter PHYREG_NUM        = 64;
    parameter IST_ENTRY_NUM     = 128;
    parameter EX_PATH_NUM       = 3;
    parameter PRM_ENTRY_BUFFER  = 4;
    parameter PRM_ENTRY_UPDATE  = 3;
    parameter RS_ENTRY_NUM      = 16;
    parameter FCL_RB_NUM        = 8;

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
    localparam BITWIDTH_IST_ENTRY_NUM                   = $clog2(IST_ENTRY_NUM);
    localparam BITWIDTH_INST_NUM_OF_LOGICAL_REGISTER    = $clog2(INST_NUM_OF_LOGICAL_REGISTER);
    localparam BITWIDTH_FCL_RB_NUM                      = $clog2(FCL_RB_NUM);
    localparam BITWIDTH_FCL_PC_WIDTH                    = BITWIDTH_FCL_RB_NUM + INST_PC_WIDTH;
    
    localparam RS_PUSH_WIDTH     = PRM_ENTRY_UPDATE + DECODE_NEW_INST;

    // (Autogenerate) Field of Entry in Instruction State Table
        /* Entry: MSB [ ( Opreand Reday_n, ... , Opreand Reday_1 ) | 
                        ( Opreand Rename Register_n, ... , Opreand Rename Register_1 ) | 
                        Destination Rename Register | 
                        IMM | PC | Micro-OP | EX_PATH ] LSB */    
    localparam IST_BITWIDTH_OPREAND_PHYREG_FULL = BITWIDTH_PHYREG_NUM * INST_OPREANDS;
    localparam IST_BITWIDTH_OPREAND_READY_FULL  = INST_OPREANDS;
    localparam IST_BITWIDTH = BITWIDTH_FCL_PC_WIDTH + BITWIDTH_EX_PATH_NUM + MICROOP_WIDTH + INST_IMM_WIDTH + BITWIDTH_PHYREG_NUM
                              + IST_BITWIDTH_OPREAND_PHYREG_FULL + IST_BITWIDTH_OPREAND_READY_FULL;

    localparam IST_STARTPOINT_PHYREG            = BITWIDTH_FCL_PC_WIDTH + BITWIDTH_EX_PATH_NUM + MICROOP_WIDTH + INST_IMM_WIDTH;
    localparam IST_STARTPOINT_OPREAND_PHYREG    = IST_STARTPOINT_PHYREG + BITWIDTH_PHYREG_NUM;
    localparam IST_STARTPOINT_OPREAND_READY     = IST_STARTPOINT_OPREAND_PHYREG + IST_BITWIDTH_OPREAND_PHYREG_FULL;

    localparam IST_PACKET_BITWIDTH              = IST_BITWIDTH * DECODE_NEW_INST;

    // (Autogenerate) Ready Station Entry
    localparam RS_ENTRY_BITWIDTH            = BITWIDTH_FCL_PC_WIDTH + BITWIDTH_EX_PATH_NUM + MICROOP_WIDTH + INST_IMM_WIDTH 
                                                + BITWIDTH_PHYREG_NUM + IST_BITWIDTH_OPREAND_PHYREG_FULL;
                                                
    reg                                                                 clk;
    reg                                                                 reset_n;
    wire                                                                o_ist_insert_available;
    reg  [DECODE_NEW_INST-1:0]                                          i_ist_field_insert;
    wire [DECODE_NEW_INST-1:0]                                          o_ist_field_valid;
    reg  [IST_PACKET_BITWIDTH-1:0]                                      i_ist_field;
    wire [(DECODE_NEW_INST*INST_OPREANDS)-1:0]                          o_prm_istindex_valid;
    wire [(BITWIDTH_PHYREG_NUM*(DECODE_NEW_INST*INST_OPREANDS))-1:0]    o_prm_istindex_phyreg;
    wire [(BITWIDTH_IST_ENTRY_NUM*(DECODE_NEW_INST*INST_OPREANDS))-1:0] o_prm_istindex_istidx;
    reg  [(PRM_ENTRY_UPDATE)-1:0]                                       i_ready_update_valid;
    wire [(PRM_ENTRY_UPDATE)-1:0]                                       o_ready_update_get;
    reg  [(BITWIDTH_PHYREG_NUM*PRM_ENTRY_UPDATE)-1:0]                   i_ready_update_phyreg;
    reg  [(BITWIDTH_IST_ENTRY_NUM*PRM_ENTRY_UPDATE)-1:0]                i_ready_update_istidx;
    reg                                                                 i_push_rs_available;
    wire [(RS_PUSH_WIDTH)-1:0]                                          o_push_rs_valid;
    wire [(RS_PUSH_WIDTH*RS_ENTRY_BITWIDTH)-1:0]                        o_push_rs_data;

    int                                         ist_entry_cnt; 
    reg  [IST_BITWIDTH-1:0]                     ist_entry_data [0:IST_ENTRY_NUM-1];
    reg  [BITWIDTH_PHYREG_NUM-1:0]              ist_entry_rs   [0:IST_ENTRY_NUM-1][0:INST_OPREANDS-1];
    reg  [IST_BITWIDTH_OPREAND_READY_FULL-1:0]  ist_entry_ready[0:IST_ENTRY_NUM-1];

    int                                         phyreg_ist_cnt     [0:PHYREG_NUM-1]; 
    reg  [BITWIDTH_IST_ENTRY_NUM-1:0]           phyreg_ist_istentry[0:PHYREG_NUM-1][$]; 

    instruction_state_table #(
        .DECODE_NEW_INST               (DECODE_NEW_INST),
        .PHYREG_NUM                    (PHYREG_NUM),
        .IST_ENTRY_NUM                 (IST_ENTRY_NUM),
        .EX_PATH_NUM                   (EX_PATH_NUM),
        .PRM_ENTRY_BUFFER              (PRM_ENTRY_BUFFER),
        .PRM_ENTRY_UPDATE              (PRM_ENTRY_UPDATE),
        .RS_ENTRY_NUM                  (RS_ENTRY_NUM),
        .FCL_RB_NUM                    (FCL_RB_NUM),
        .INST_PC_WIDTH                 (INST_PC_WIDTH),
        .INST_BITWIDTH                 (INST_BITWIDTH),
        .INST_OPCODE_WIDTH             (INST_OPCODE_WIDTH),
        .INST_OPTIONAL_OPCODE_WIDTH    (INST_OPTIONAL_OPCODE_WIDTH),
        .INST_IMM_WIDTH                (INST_IMM_WIDTH),
        .INST_NUM_OF_LOGICAL_REGISTER  (INST_NUM_OF_LOGICAL_REGISTER),
        .INST_OPREANDS                 (INST_OPREANDS),
        .MICROOP_WIDTH                 (MICROOP_WIDTH)
    ) dut (
        .clk                           (clk),
        .reset_n                       (reset_n),
        .o_ist_insert_available        (o_ist_insert_available),
        .i_ist_field_insert            (i_ist_field_insert),
        .o_ist_field_valid             (o_ist_field_valid),
        .i_ist_field                   (i_ist_field),
        .o_prm_istindex_valid          (o_prm_istindex_valid),
        .o_prm_istindex_phyreg         (o_prm_istindex_phyreg),
        .o_prm_istindex_istidx         (o_prm_istindex_istidx),
        .i_ready_update_valid          (i_ready_update_valid),
        .o_ready_update_get            (o_ready_update_get),
        .i_ready_update_phyreg         (i_ready_update_phyreg),
        .i_ready_update_istidx         (i_ready_update_istidx),
        .i_push_rs_available           (i_push_rs_available),
        .o_push_rs_valid               (o_push_rs_valid),
        .o_push_rs_data                (o_push_rs_data)
    );

    always #5 clk = ~clk;

    task insert_entry;
        bit [RS_PUSH_WIDTH-1:0]                    push_valid;
        bit [INST_PC_WIDTH-1:0]                    pc;
        bit [BITWIDTH_FCL_RB_NUM-1:0]              fclpath;
        bit [BITWIDTH_EX_PATH_NUM-1:0]             expath;
        bit [MICROOP_WIDTH-1:0]                    microop;
        bit [INST_IMM_WIDTH-1:0]                   imm;
        bit [BITWIDTH_PHYREG_NUM-1:0]              rd;
        bit [IST_BITWIDTH_OPREAND_PHYREG_FULL-1:0] rs;
        bit [IST_BITWIDTH_OPREAND_READY_FULL-1:0]  ready;
        int expath_idx;

        i_ist_field_insert = 0;
        if (o_ist_insert_available) begin
            for (int nel_push_idx = 0; nel_push_idx < DECODE_NEW_INST; nel_push_idx++) begin
                if ($urandom % 2) begin
                    i_ist_field_insert[nel_push_idx] = 1'b1;
                    pc      = $urandom;
                    fclpath = $urandom;
                    expath  = $urandom % EX_PATH_NUM;
                    microop = $urandom;
                    imm     = $urandom;
                    rd      = $urandom % PHYREG_NUM;
                    for (int rs_idx = 0; rs_idx < INST_OPREANDS; rs_idx++) begin
                        rs[(BITWIDTH_PHYREG_NUM*rs_idx) +: BITWIDTH_PHYREG_NUM] = $urandom % PHYREG_NUM;
                    end
                    ready   = $urandom % (2 ** IST_BITWIDTH_OPREAND_READY_FULL);

                    i_ist_field[(IST_BITWIDTH*nel_push_idx) +: IST_BITWIDTH] 
                        = {ready, rs, rd, imm, microop, expath, fclpath, pc};

                    ist_entry_data[ist_entry_cnt]  = i_ist_field[RS_ENTRY_BITWIDTH-1:0];
                    ist_entry_ready[ist_entry_cnt] = ready;
                    for (int rs_idx = 0; rs_idx < INST_OPREANDS; rs_idx++) begin
                        ist_entry_rs[ist_entry_cnt][rs_idx] = rs[(BITWIDTH_PHYREG_NUM*rs_idx) +: BITWIDTH_PHYREG_NUM];
                    end
                    ist_entry_cnt = (ist_entry_cnt == (IST_ENTRY_NUM-1))? 0 : ist_entry_cnt+1;

                    // Two Opreand output
                    $display(" [%t] PUSH IST ENTRY: %h (expath: %d / rd: r%d / rs: r%d(%b), r%d(%b) )",
                                $time, i_ist_field[(IST_BITWIDTH*nel_push_idx) +: IST_BITWIDTH] ,
                                expath, rd, 
                                rs[BITWIDTH_PHYREG_NUM-1:0], ready[0],
                                rs[IST_BITWIDTH_OPREAND_PHYREG_FULL-1:BITWIDTH_PHYREG_NUM], ready[1]);
                end
            end
        end
    endtask

    task prm_insert;
        bit [BITWIDTH_PHYREG_NUM-1:0]    target_phyreg;
        bit [BITWIDTH_IST_ENTRY_NUM-1:0] out_ist_entry_num;
        for (int prm_to_idx = 0; prm_to_idx < (DECODE_NEW_INST*INST_OPREANDS); prm_to_idx = prm_to_idx+1) begin
            if (o_prm_istindex_valid[prm_to_idx]) begin
                target_phyreg     = o_prm_istindex_phyreg[(BITWIDTH_PHYREG_NUM*prm_to_idx) +: BITWIDTH_PHYREG_NUM];
                out_ist_entry_num = o_prm_istindex_istidx[(BITWIDTH_IST_ENTRY_NUM*prm_to_idx) +: BITWIDTH_IST_ENTRY_NUM];
                phyreg_ist_istentry[target_phyreg].push_back(out_ist_entry_num);
                phyreg_ist_cnt[target_phyreg] += 1;
                $display("    prm out!! [%t] PHYREG: %d, IST: %d %d", $time, target_phyreg, out_ist_entry_num, phyreg_ist_cnt[target_phyreg]);
            end
        end
    endtask

    task prm_output_sim;
        int active = $urandom % 10;
        int rand_try = $urandom % ( 2 ** (PRM_ENTRY_UPDATE) );
        int rand_phy_get = ($urandom % 20)+1;
        int rand_circle = ($urandom % 20)+1;
        int enable_phys = 0;
        bit [BITWIDTH_PHYREG_NUM-1:0]    target_phyreg;
        bit [BITWIDTH_IST_ENTRY_NUM-1:0] target_ist;
        
        for (int ena_phys_idx = 0; ena_phys_idx < PHYREG_NUM; ena_phys_idx = ena_phys_idx+1) begin
            if (phyreg_ist_cnt[ena_phys_idx] != 0) enable_phys++;
        end
        
        i_ready_update_valid = 0;

        if (enable_phys != 0) begin
            if (active == 0) begin
                i_ready_update_valid = rand_try[PRM_ENTRY_UPDATE-1:0];
                for (int try_idx = 0; try_idx < PRM_ENTRY_UPDATE; try_idx = try_idx+1) begin
                    if (i_ready_update_valid[try_idx]) begin
                        target_phyreg = 0;
                        for (int phy_get = 0; phy_get < rand_phy_get;) begin
                            if (phyreg_ist_cnt[++target_phyreg]) phy_get++;
                            if (target_phyreg >= PHYREG_NUM) target_phyreg = 0;
                        end

                        for (int circle_idx = 0; circle_idx < rand_circle; circle_idx++) begin
                            target_ist = phyreg_ist_istentry[target_phyreg].pop_front();
                            phyreg_ist_istentry[target_phyreg].push_back(target_ist);
                        end

                        phyreg_ist_istentry[target_phyreg].pop_back();
                        phyreg_ist_cnt[target_phyreg]--;

                        i_ready_update_phyreg[(BITWIDTH_PHYREG_NUM*try_idx) +: BITWIDTH_PHYREG_NUM] = target_phyreg;
                        i_ready_update_istidx[(BITWIDTH_IST_ENTRY_NUM*try_idx) +: BITWIDTH_IST_ENTRY_NUM] = target_ist;

                        $display("    ready insert!! [%t] PHYREG: %d, IST: %d %d", $time, target_phyreg, target_ist, try_idx);
                    end
                end
            end
        end
    endtask

    task check_rs_out;
        bit [BITWIDTH_PHYREG_NUM-1:0]              target_phyreg;
        bit [BITWIDTH_IST_ENTRY_NUM-1:0]           target_ist;
        bit [IST_BITWIDTH_OPREAND_PHYREG_FULL-1:0] update_ready;
        bit [BITWIDTH_PHYREG_NUM-1:0]              opr_phyreg;
        bit [IST_BITWIDTH-1:0]                     comp_rs;
        bit [IST_BITWIDTH-1:0]                     out_rs;
        bit                                        c;
        int rs_out_idx;

        // ready 업데이트 반영
        for (int ready_get_idx = 0; ready_get_idx < PRM_ENTRY_UPDATE; ready_get_idx++) begin
            update_ready = 0;
            if (i_ready_update_valid[ready_get_idx]) begin
                target_ist = i_ready_update_istidx[(BITWIDTH_IST_ENTRY_NUM*ready_get_idx) +: BITWIDTH_IST_ENTRY_NUM];
                target_phyreg = i_ready_update_phyreg[(BITWIDTH_PHYREG_NUM*ready_get_idx) +: BITWIDTH_PHYREG_NUM];

                for (int opr_idx = 0; opr_idx < INST_OPREANDS; opr_idx++) begin
                    opr_phyreg = ist_entry_rs[target_phyreg][opr_idx];
                    if (opr_phyreg == target_phyreg) begin update_ready[opr_idx] = 1'b1; end
                end

                ist_entry_ready[target_ist] |= update_ready;
            end
        end

        // rs 확인
        for (int rs_idx = 0; rs_idx < IST_ENTRY_NUM; rs_idx++) begin
            if (&ist_entry_ready[rs_idx]) begin
                comp_rs = ist_entry_data[rs_idx];
                ist_entry_cnt--;
                /*
                ist_entry_data[rs_idx] = 0;
                for (int opr_idx = 0; opr_idx < INST_OPREANDS; opr_idx++) begin
                    ist_entry_rs[rs_idx][opr_idx] = 0;
                end
                */
                
                c = 0;
                
                // Decode Section
                //for ()
                // PRM Section
                for (rs_out_idx = 0; rs_out_idx < RS_PUSH_WIDTH; rs_out_idx++) begin
                    if (o_push_rs_valid[rs_out_idx]) begin
                        c = 1;
                        out_rs = o_push_rs_data[(RS_ENTRY_BITWIDTH*rs_out_idx) +: RS_ENTRY_BITWIDTH];
                        if (out_rs === comp_rs) begin
                            $display("PASS [%t] %d out: %h / target: %h", $time, rs_idx, out_rs, comp_rs);
                            break;
                        end
                        //else begin
                        //    $display("FAIL [%t] %d out: %h / target: %h %d", $time, rs_idx, out_rs, comp_rs, rs_out_idx);
                        //    $stop;
                        //end
                    end
                end
                
                if (c == 0) begin
                    $display("FAIL-404 [%t] %d out: %h / target: %h", $time, rs_idx, out_rs, comp_rs);
                    $stop;
                end
                
                ist_entry_ready[rs_idx] = 0;
            end
        end
    endtask

    initial begin
        #0;
        clk = 1'b0; reset_n = 1'b0;
        i_ist_field_insert = 0;
        i_ist_field = 0;
        i_ready_update_valid = 0;
        i_ready_update_phyreg = 0;
        i_ready_update_istidx = 0;
        i_push_rs_available = 0;

        ist_entry_cnt = 0;
        for (int ena_phys_idx = 0; ena_phys_idx < PHYREG_NUM; ena_phys_idx = ena_phys_idx+1) begin
            phyreg_ist_cnt[ena_phys_idx] = 0;
        end

        @(negedge clk);
        @(negedge clk);
        reset_n = 1'b1;
        @(negedge clk);
        i_push_rs_available = 1'b1;
        wait(o_ist_insert_available);
        @(negedge clk);
        @(posedge clk);
            
        repeat(10000) begin
            #1; insert_entry(); #1; prm_insert();
            @(negedge clk); #1;
            prm_output_sim(); #1; check_rs_out();
            @(posedge clk);
        end
        @(posedge clk);

        $finish;
    end

endmodule