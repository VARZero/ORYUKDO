module tb_eulsukdo_1dec_3issue ();

    // Dynamic Schedular Description
    parameter DECODE_NEW_INST   = 1;
    parameter PHYREG_NUM        = 64;
    parameter IST_ENTRY_NUM     = 128;
    parameter EX_PATH_NUM       = 3;
    parameter PRM_ENTRY_BUFFER  = 4;
    parameter PRM_ENTRY_UPDATE  = 3;
    parameter PRM_READY_OUT_FIFO_DEPTH = 32;
    parameter RS_ENTRY_NUM      = 16;
    parameter FCL_RB_NUM        = 8; // test, default = 8
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

    localparam RS_PUSH_WIDTH     = PRM_ENTRY_UPDATE + DECODE_NEW_INST;

    reg                                                clk;
    reg                                                reset_n;
    reg  [DECODE_NEW_INST-1:0]                         i_im_inst_valid;
    reg  [(DECODE_NEW_INST*INST_BITWIDTH)-1:0]         i_im_inst;
    wire [DECODE_NEW_INST-1:0]                         o_im_inst_get;
    wire                                               o_im_re;
    wire [BITWIDTH_FCL_PC_WIDTH-1:0]                   o_im_pc;
    
    wire                                               re_vmem_o;
    wire                                               we_vmem_o;
    wire [31:0]                                        addr_vmem_o;
    wire [3:0]                                         strb_vmem_o;
    reg  [31:0]                                        rdata_vmem_i;
    wire [31:0]                                        wdata_vmem_o;
    reg                                                ready_vmem_i;

    reg [INST_PC_WIDTH-3:0] now_pc;
    reg end_pc_flag;

    reg [31:0] instruction_memory[0:511];
    reg [31:0] data_memory[0:511];

    initial begin
        now_pc = 0; // Reset Address
        $readmemh("inst.mem", instruction_memory);
        $readmemh("data.mem", data_memory);
    end

    task ist_memory_access_detect;
        bit i_set;

        i_set = 0;
        #1;
        if (o_im_re) i_set = 1;
        
        @(negedge clk);
        if (i_set) begin
            if (now_pc < 512) begin
                now_pc = o_im_pc[11:2];
                i_im_inst = instruction_memory[now_pc[8:0]];
                i_im_inst_valid = (i_im_inst == 32'h0010_0073)? 1'b0 : 1'b1;
            end
            else begin
                i_im_inst_valid = 1'b0;
                end_pc_flag = 1'b1;
            end
        end
        else begin
            i_im_inst_valid = 0;
        end
    endtask

    task data_memory_access_detect;
        int wait_time;
        reg [31:0] mem_addr;
        reg [1:0] mode;
        
        wait_time = $urandom%5;
        mem_addr = addr_vmem_o;
        mem_addr = addr_vmem_o;
        mem_addr[16] = 1'b0;
        mode = {re_vmem_o, we_vmem_o};
        @(negedge clk);
        $display("1 wait time %d, mode %b", wait_time, mode);
        if (mode) begin
            for (int i = 0; i < wait_time; i++) begin @(negedge clk); end
            $display("wait time %d, mode %b", wait_time, mode);
            if (mode == 2'b10) begin // read
                rdata_vmem_i = data_memory[mem_addr];
                ready_vmem_i = 1'b1;
                $display("load!! mem[%h] = %h", mem_addr, rdata_vmem_i);
            end
            else if (mode == 2'b01) begin // write
                data_memory[mem_addr][31:24] = (strb_vmem_o[3])? wdata_vmem_o[31:24] : data_memory[mem_addr][31:24];
                data_memory[mem_addr][23:16] = (strb_vmem_o[2])? wdata_vmem_o[23:16] : data_memory[mem_addr][23:16];
                data_memory[mem_addr][15: 8] = (strb_vmem_o[1])? wdata_vmem_o[15: 8] : data_memory[mem_addr][15: 8];
                data_memory[mem_addr][ 7: 0] = (strb_vmem_o[0])? wdata_vmem_o[ 7: 0] : data_memory[mem_addr][ 7: 0];
                ready_vmem_i = 1'b1;
                $display("store!! mem[%h] = %h", mem_addr, data_memory[mem_addr]);
            end
        end
        @(negedge clk);
        ready_vmem_i = 1'b0;
    endtask

    eulsukdo_1dec_3issue #(
        .DECODE_NEW_INST               (DECODE_NEW_INST),
        .PHYREG_NUM                    (PHYREG_NUM),
        .IST_ENTRY_NUM                 (IST_ENTRY_NUM),
        .EX_PATH_NUM                   (EX_PATH_NUM),
        .PRM_ENTRY_BUFFER              (PRM_ENTRY_BUFFER),
        .PRM_ENTRY_UPDATE              (PRM_ENTRY_UPDATE),
        .PRM_READY_OUT_FIFO_DEPTH      (PRM_READY_OUT_FIFO_DEPTH),
        .RS_ENTRY_NUM                  (RS_ENTRY_NUM),
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
        .i_im_inst_valid               (i_im_inst_valid),
        .i_im_inst                     (i_im_inst),
        .o_im_inst_get                 (o_im_inst_get),
        .o_im_re                       (o_im_re),
        .o_im_pc                       (o_im_pc),
        .re_vmem_o                     (re_vmem_o),
        .we_vmem_o                     (we_vmem_o),
        .addr_vmem_o                   (addr_vmem_o),
        .strb_vmem_o                   (strb_vmem_o),
        .rdata_vmem_i                  (rdata_vmem_i),
        .wdata_vmem_o                  (wdata_vmem_o),
        .ready_vmem_i                  (ready_vmem_i)
    );

    always #5 clk = ~clk;

    initial begin
        end_pc_flag = 0;

        #0;
        clk = 1'b0; reset_n = 1'b0;
        i_im_inst_valid = 0;
        i_im_inst       = 0;

        rdata_vmem_i = 0;
        ready_vmem_i = 0;

        @(negedge clk);
        @(negedge clk);
        reset_n = 1'b1;
        @(negedge clk);

        wait(o_im_re);
        @(negedge clk);
        
        fork
            begin
                repeat(10000) begin
                    ist_memory_access_detect();
                end
            end

            begin
                forever begin
                    @(negedge clk);
                    if (re_vmem_o || we_vmem_o)
                        data_memory_access_detect();
                end
            end
        join

        @(negedge clk);


        $finish;
    end

endmodule