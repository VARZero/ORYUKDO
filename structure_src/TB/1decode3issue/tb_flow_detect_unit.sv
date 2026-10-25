module tb_flow_detect_unit ();

    parameter DECODE_NEW_INST               = 1;
    parameter PHYREG_NUM                    = 64;
    parameter UNALLOCATE_PHYREG             = 4;
    parameter INST_PC_WIDTH                 = 32;
    parameter EX_PATH_NUM                   = 3;

    localparam MAX_PC_RANGE                 = PHYREG_NUM/2;
    localparam BITWIDTH_PC_RANGE            = $clog2(MAX_PC_RANGE);
    localparam BITWIDTH_PHYREG_NUM          = $clog2(PHYREG_NUM);

    reg                  clk;
    reg                  reset_n;

    // Flow Control Logic
        // <- Entry Valid input
    // input  wire                                               i_entry_force_deactive,
        // -> Entry Valid output
    wire                                               o_entry_active;
    wire                                               o_entry_free;
        // <- PC Input
    reg                                                i_set_start_pc_valid;
    reg  [INST_PC_WIDTH-1:0]                           i_set_start_pc;
    reg                                                i_set_last_pc_valid;
    reg  [INST_PC_WIDTH-1:0]                           i_set_last_pc;
        // <- Allocate Registers input
    reg  [DECODE_NEW_INST-1:0]                         i_nel_newpc_valid,
    reg  [(INST_PC_WIDTH*DECODE_NEW_INST)-1:0]         i_nel_newpc,
    reg  [DECODE_NEW_INST-1:0]                         i_nel_lastreg_valid,
    reg  [(BITWIDTH_PHYREG_NUM*DECODE_NEW_INST)-1:0]   i_nel_lastreg,

    // Write Back Concatenation
        // <- PC Input
    reg  [EX_PATH_NUM-1:0]                             i_wbc2fcl_done,
    reg  [(EX_PATH_NUM*INST_PC_WIDTH)-1:0]             i_wbc2fcl_pc,
    
    // Physical Register Mapper
        // -> Unallocate Registers Output
    reg                                                i_unallocate_use,
    wire [UNALLOCATE_PHYREG-1:0]                       o_prm_unallocate_valid,
    wire [(BITWIDTH_PHYREG_NUM*UNALLOCATE_PHYREG)-1:0] o_prm_unallocate_phyreg

    flow_detect_unit #(
        .DECODE_NEW_INST            (DECODE_NEW_INST),
        .PHYREG_NUM                 (PHYREG_NUM),
        .UNALLOCATE_PHYREG          (UNALLOCATE_PHYREG),
        .INST_PC_WIDTH              (INST_PC_WIDTH),
        .EX_PATH_NUM                (EX_PATH_NUM)
    ) (
        .clk                        (clk),
        .reset_n                    (reset_n),
        .o_entry_active             (o_entry_active),
        .o_entry_free               (o_entry_free),
        .i_set_start_pc_valid       (i_set_start_pc_valid),
        .i_set_start_pc             (i_set_start_pc),
        .i_set_last_pc_valid        (i_set_last_pc_valid),
        .i_set_last_pc              (i_set_last_pc),
        .i_nel_newpc_valid          (i_nel_newpc_valid),
        .i_nel_newpc                (i_nel_newpc),
        .i_nel_lastreg_valid        (i_nel_lastreg_valid),
        .i_nel_lastreg              (i_nel_lastreg),
        .i_wbc2fcl_done             (i_wbc2fcl_done),
        .i_wbc2fcl_pc               (i_wbc2fcl_pc),
        .i_unallocate_use           (i_unallocate_use),
        .o_prm_unallocate_valid     (o_prm_unallocate_valid),
        .o_prm_unallocate_phyreg    (o_prm_unallocate_phyreg)
    );
    
    always #5 clk = ~clk;

    reg flag_change_last_addr;
    reg [29:0] addr;

    task address_start;
        flag_change_last_addr = 0;
        addr = $urandom;
        i_set_start_pc_valid = 1'b1; i_set_start_pc = {addr   , 2'b00};
        i_set_last_pc_valid  = 1'b1; i_set_last_pc  = {addr+32, 2'b00};
        @(negedge clk);
        i_set_start_pc_valid = 1'b0;
        i_set_last_pc_valid  = 1'b0;
    endtask

    task new_inst_insert;
        if (flag_change_last_addr == 0) begin
            addr = addr+1;
            flag_change_last_addr = ( ($urandom % 10) == 0 );
            
            i_nel_newpc_valid   = 1'b1; 
            i_nel_newpc = addr;
            i_nel_lastreg_valid = $urandom % 2;
            i_nel_lastreg = $urandom;
        end
    endtask

    task end_inst_insert;
        i_nel_newpc_valid   = 1'b0;
        i_nel_lastreg_valid = 1'b0;
    endtask
    
    task done_fcl;
        i_wbc2fcl_done = 1'b1; i_wbc2fcl_pc = 0;
    endtask

    initial begin
        #0;
        clk = 1'b0; reset_n = 1'b1;

        i_set_start_pc_valid = 0; i_set_start_pc = 0;
        i_set_last_pc_valid = 0; i_set_last_pc = 0;

        i_nel_newpc_valid = 0; i_nel_newpc = 0;
        i_nel_lastreg_valid = 0; i_nel_lastreg = 0;

        i_wbc2fcl_done = 0; i_wbc2fcl_pc = 0;

        i_unallocate_use = 0;

        @(negedge clk);
        @(negedge clk);
        reset_n = 1'b0;
        @(negedge clk);
    end

endmodule
