`timescale 1ns / 1ps

module tb_write_back_concatenation ();

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

    reg                  clk;
    reg                  reset_n;

    // EX out
        // <- Execute Units Result Input
    reg  [EX_PATH_NUM-1:0]                          i_ex_done;
    reg  [(EX_PATH_NUM*BITWIDTH_FCL_PC_WIDTH)-1:0]  i_ex_done_pc;
    reg                                             i_ex_done_branch;
    reg  [INST_PC_WIDTH-1:0]                        i_ex_done_branch_pc;
    reg  [(EX_PATH_NUM*BITWIDTH_PHYREG_NUM)-1:0]    i_ex_done_phyreg;

    // PRM
        // -> Ready Register number
    wire [EX_PATH_NUM-1:0]                          o_wbc2prm_done;
    wire [(EX_PATH_NUM*BITWIDTH_PHYREG_NUM)-1:0]    o_wbc2prm_done_phyreg;

    // NEL
        // -> Ready Register number
    wire [EX_PATH_NUM-1:0]                          o_wbc2nel_done;
    wire [(EX_PATH_NUM*BITWIDTH_PHYREG_NUM)-1:0]    o_wbc2nel_done_phyreg;

    // FCL
        // -> Ready instruction PC and Branch Result PC
    wire [EX_PATH_NUM-1:0]                          o_wbc2fcl_done;
    wire [(EX_PATH_NUM*BITWIDTH_FCL_PC_WIDTH)-1:0]  o_wbc2fcl_pc;
    wire                                            o_wbc2fcl_branch;
    wire [INST_PC_WIDTH-1:0]                        o_wbc2fcl_branch_pc;

    reg [2:0] pass_condition;
        // done, 

    write_back_concatenation #(
        .DECODE_NEW_INST               (DECODE_NEW_INST),
        .PHYREG_NUM                    (PHYREG_NUM),
        .IST_ENTRY_NUM                 (IST_ENTRY_NUM),
        .EX_PATH_NUM                   (EX_PATH_NUM),
        .PRM_ENTRY_BUFFER              (PRM_ENTRY_BUFFER),
        .RS_ENTRY_NUM                  (RS_ENTRY_NUM),
        .RS_PUSH_WIDTH                 (RS_PUSH_WIDTH),
        .INST_PC_WIDTH                 (INST_PC_WIDTH),
        .INST_BITWIDTH                 (INST_BITWIDTH),
        .INST_OPCODE_WIDTH             (INST_OPCODE_WIDTH),
        .INST_OPTIONAL_OPCODE_WIDTH    (INST_OPTIONAL_OPCODE_WIDTH),
        .INST_IMM_WIDTH                (INST_IMM_WIDTH),
        .INST_NUM_OF_LOGICAL_REGISTER  (INST_NUM_OF_LOGICAL_REGISTER),
        .INST_OPREANDS                 (INST_OPREANDS),
        .MICROOP_WIDTH                 (MICROOP_WIDTH)
    ) dut (
        .clk                    (clk),
        .reset_n                (reset_n),
        .i_ex_done              (i_ex_done),
        .i_ex_done_pc           (i_ex_done_pc),
        .i_ex_done_branch       (i_ex_done_branch),
        .i_ex_done_branch_pc    (i_ex_done_branch_pc),
        .i_ex_done_phyreg       (i_ex_done_phyreg),
        .o_wbc2prm_done         (o_wbc2prm_done),
        .o_wbc2prm_done_phyreg  (o_wbc2prm_done_phyreg),
        .o_wbc2nel_done         (o_wbc2nel_done),
        .o_wbc2nel_done_phyreg  (o_wbc2nel_done_phyreg),
        .o_wbc2fcl_done         (o_wbc2fcl_done),
        .o_wbc2fcl_pc           (o_wbc2fcl_pc),
        .o_wbc2fcl_branch       (o_wbc2fcl_branch),
        .o_wbc2fcl_branch_pc    (o_wbc2fcl_branch_pc)
    );

    always #5 clk = ~clk;

    task random_done();
        
        i_ex_done = $urandom % (2**EX_PATH_NUM);
        for (int i = 0; i < EX_PATH_NUM; i++) begin
            i_ex_done_pc[(BITWIDTH_FCL_PC_WIDTH*i_ex_done) +: BITWIDTH_FCL_PC_WIDTH] = {$urandom, $urandom};
            i_ex_done_phyreg[(BITWIDTH_PHYREG_NUM*i_ex_done) +: BITWIDTH_PHYREG_NUM] = $urandom;
        end

        if (i_ex_done[0]) begin
            i_ex_done_branch    = $urandom % 2;
            i_ex_done_branch_pc = $urandom;
        end
        
        @(negedge clk);

        pass_condition[0] = (o_wbc2prm_done == i_ex_done);
        pass_condition[1] = (o_wbc2nel_done == i_ex_done);
        pass_condition[2] = (o_wbc2fcl_done == i_ex_done);
        if (&pass_condition) $display("PASS: [%t] done", $time);
        else                 $display("FAIL: [%t] done - %b", $time, pass_condition);
        for (int i = 0; i < EX_PATH_NUM; i++) begin
            pass_condition = 0;
            if (i_ex_done[i]) begin
                pass_condition[0] = (i_ex_done_phyreg[(BITWIDTH_PHYREG_NUM*i) +: BITWIDTH_PHYREG_NUM] 
                                        == o_wbc2prm_done_phyreg[(BITWIDTH_PHYREG_NUM*i) +: BITWIDTH_PHYREG_NUM]);
                pass_condition[1] = (i_ex_done_phyreg[(BITWIDTH_PHYREG_NUM*i) +: BITWIDTH_PHYREG_NUM] 
                                        == o_wbc2nel_done_phyreg[(BITWIDTH_PHYREG_NUM*i) +: BITWIDTH_PHYREG_NUM]);
                pass_condition[2] = (i_ex_done_pc[(BITWIDTH_FCL_PC_WIDTH*i) +: BITWIDTH_FCL_PC_WIDTH] 
                                        == o_wbc2fcl_pc[(BITWIDTH_FCL_PC_WIDTH*i) +: BITWIDTH_FCL_PC_WIDTH]);
                if (&pass_condition) $display("PASS: [%t] data", $time);
                else                 $display("FAIL: [%t] data - %b", $time, pass_condition);
            end
        end
        if (i_ex_done_branch) begin pass_condition[0] = (i_ex_done_branch_pc == o_wbc2fcl_branch_pc);
            if (pass_condition[0]) $display("PASS: [%t] branch", $time);
            else                   $display("FAIL: [%t] branch - %b", $time, pass_condition);
        end
    endtask

    initial begin
        #0;
        clk = 1'b0; reset_n = 1'b0;
        i_ex_done = 0;
        i_ex_done_pc = 0;
        i_ex_done_branch = 0;
        i_ex_done_branch_pc = 0;
        i_ex_done_phyreg = 0;
        
        @(negedge clk);
        @(negedge clk);
        reset_n = 1'b1;
        @(negedge clk);

        repeat(100) random_done();

        @(negedge clk);

        $finish;
    end

endmodule
