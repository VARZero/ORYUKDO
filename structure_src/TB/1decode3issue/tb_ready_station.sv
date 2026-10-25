`timescale 1ns / 1ps

module tb_ready_station();

    // Dynamic Schedular Description
    parameter DECODE_NEW_INST   = 1;
    parameter PHYREG_NUM        = 64;
    parameter IST_ENTRY_NUM     = 128;
    parameter EX_PATH_NUM       = 3;
    parameter PRM_ENTRY_BUFFER  = 4;
    parameter RS_ENTRY_NUM      = 16;
    parameter RS_PUSH_WIDTH     = 3;
    parameter FCL_RB_NUM        = 8;
    parameter FCL_PC_GAP        = 4;
    parameter UNALLOCATE_PHYREG = 4;

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

    // (Autogenerate) Field of Entry in Instruction State Table
        /* Entry: MSB [ ( Opreand Reday_n, ... , Opreand Reday_1 ) | 
                        ( Opreand Rename Register_n, ... , Opreand Rename Register_1 ) | 
                        Destination Logical Register | 
                        Destination Rename Register | 
                        IMM | Micro-OP | EX_PATH | PC ] LSB */    
    localparam IST_BITWIDTH_OPREAND_PHYREG_FULL = BITWIDTH_PHYREG_NUM * INST_OPREANDS;

    
    // (Autogenerate) Ready Station Entry
    localparam RS_ENTRY_BITWIDTH            = BITWIDTH_FCL_PC_WIDTH + BITWIDTH_EX_PATH_NUM + MICROOP_WIDTH
                                              + INST_IMM_WIDTH + BITWIDTH_PHYREG_NUM + IST_BITWIDTH_OPREAND_PHYREG_FULL;
    localparam RS_PACKET_BITWIDTH           = RS_ENTRY_BITWIDTH * RS_PUSH_WIDTH;
    localparam EX_PACKET_BITWIDTH           = RS_ENTRY_BITWIDTH * EX_PATH_NUM;
    
    localparam RS_STARTPOINT_EX_PATH        = BITWIDTH_FCL_PC_WIDTH;

    // (Autogenerate) Write Back Field
    localparam WB_PHYREGS_BITWIDTH          = BITWIDTH_PHYREG_NUM * EX_PATH_NUM;

    reg clk;
    reg reset_n;
    
    // Entries Update
        // -> Instruction State Table Ready
    wire o_ist_ready_entry_get;
    reg  [RS_PUSH_WIDTH-1:0] i_ist_ready_entry_valid;
    reg  [RS_PACKET_BITWIDTH-1:0] i_ist_ready_entry;

    // Entries Pop
        // <- Execute Units Input
    reg  [EX_PATH_NUM-1:0] i_ex_entry_get;
    wire [EX_PATH_NUM-1:0] o_ex_entry_valid;
    wire [EX_PACKET_BITWIDTH-1:0] o_ex_entry;

    int                          expect_fifo_cnt[0:RS_PUSH_WIDTH-1]; 
    reg  [RS_ENTRY_BITWIDTH-1:0] expect_fifo_data[0:RS_PUSH_WIDTH-1][$:RS_ENTRY_NUM]; 

    reg  [RS_ENTRY_BITWIDTH-1:0] check_data;
    reg  [RS_ENTRY_BITWIDTH-1:0] pop_data;

    ready_station #(
        .DECODE_NEW_INST               (DECODE_NEW_INST),
        .PHYREG_NUM                    (PHYREG_NUM),
        .IST_ENTRY_NUM                 (IST_ENTRY_NUM),
        .EX_PATH_NUM                   (EX_PATH_NUM),
        .PRM_ENTRY_BUFFER              (PRM_ENTRY_BUFFER),
        .RS_ENTRY_NUM                  (RS_ENTRY_NUM),
        .RS_PUSH_WIDTH                 (RS_PUSH_WIDTH),
        .FCL_RB_NUM                    (FCL_RB_NUM),
        .FCL_PC_GAP                    (FCL_PC_GAP),
        .UNALLOCATE_PHYREG             (UNALLOCATE_PHYREG),
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
        .o_ist_ready_entry_get         (o_ist_ready_entry_get),
        .i_ist_ready_entry_valid       (i_ist_ready_entry_valid),
        .i_ist_ready_entry             (i_ist_ready_entry),
        .i_ex_entry_get                (i_ex_entry_get),
        .o_ex_entry_valid              (o_ex_entry_valid),
        .o_ex_entry                    (o_ex_entry)
    );

    always #5 clk = ~clk;

    task out_data();
        i_ex_entry_get = 0;
        for (int expath_idx = 0; expath_idx < EX_PATH_NUM; expath_idx++) begin
            if (o_ex_entry_valid[expath_idx]) begin
                i_ex_entry_get[expath_idx] = 1'b1;
                if (expect_fifo_cnt[expath_idx] === 0) begin
                    $display("FAIL: [%t] empty!!!", $time);
                end
                else begin
                    check_data = o_ex_entry[(RS_ENTRY_BITWIDTH*expath_idx) +: RS_ENTRY_BITWIDTH];
                    pop_data   = expect_fifo_data[expath_idx].pop_front();

                    if (check_data === pop_data) begin
                        $display("PASS: [%t] %x %x %d", $time, check_data, pop_data, expath_idx);
                    end
                    else begin
                        $display("FAIL: [%t] %x %x is not same.. %d", $time, check_data, pop_data, expath_idx);
                    end
                end
            end
        end
    endtask

    task in_data();
        bit [RS_PUSH_WIDTH-1:0]                    push_valid;
        bit [INST_PC_WIDTH-1:0]                    pc;
        bit [BITWIDTH_FCL_RB_NUM-1:0]              fclpath;
        bit [BITWIDTH_EX_PATH_NUM-1:0]             expath;
        bit [MICROOP_WIDTH-1:0]                    microop;
        bit [INST_IMM_WIDTH-1:0]                   imm;
        bit [BITWIDTH_PHYREG_NUM-1:0]              rd;
        bit [IST_BITWIDTH_OPREAND_PHYREG_FULL-1:0] rs;
        int expath_idx;

        push_valid = $urandom % (RS_PUSH_WIDTH+1);
        i_ist_ready_entry_valid = (o_ist_ready_entry_get)? push_valid : 0;
        for (int rs_push_idx = 0; rs_push_idx < RS_PUSH_WIDTH; rs_push_idx++) begin
            pc = $urandom;
            fclpath = $urandom;
            expath = $urandom % EX_PATH_NUM;
            microop = $urandom;
            imm = $urandom;
            rd = $urandom;
            rs = $urandom;
            
            i_ist_ready_entry[(RS_ENTRY_BITWIDTH*rs_push_idx) +: RS_ENTRY_BITWIDTH] 
                = {rs, rd, imm, microop, expath, fclpath, pc};
        end

        for (int rs_push_idx = 0; rs_push_idx < RS_PUSH_WIDTH; rs_push_idx++) begin
            if (i_ist_ready_entry_valid[rs_push_idx]) begin
                expath_idx = i_ist_ready_entry[((RS_ENTRY_BITWIDTH*rs_push_idx)+RS_STARTPOINT_EX_PATH) +: BITWIDTH_EX_PATH_NUM];
                expect_fifo_cnt[expath_idx]++;
                expect_fifo_data[expath_idx].push_back(i_ist_ready_entry[(RS_ENTRY_BITWIDTH*rs_push_idx) +: RS_ENTRY_BITWIDTH]);
                $display("PUSH: [%t] %d %x ", $time, expath_idx, i_ist_ready_entry[(RS_ENTRY_BITWIDTH*rs_push_idx) +: RS_ENTRY_BITWIDTH]);
            end
        end
    endtask

    initial begin
        #0;
        clk = 1'b0; reset_n = 1'b0;
        i_ist_ready_entry_valid = 0;
        i_ist_ready_entry       = 0;
        i_ex_entry_get          = 0;
        for (int expath_idx = 0; expath_idx < EX_PATH_NUM; expath_idx++) begin
            expect_fifo_cnt[expath_idx] = 0;
        end

        @(negedge clk);
        @(negedge clk);
        reset_n = 1'b1;
        @(negedge clk);

        repeat(100) begin
            in_data();
            @(negedge clk);
            out_data();
        end

        $finish;
    end

endmodule
