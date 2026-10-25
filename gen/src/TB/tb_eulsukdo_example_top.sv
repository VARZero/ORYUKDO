`timescale 1ns / 1ps

module tb_eulsukdo_example_top ();

    // Dynamic Scheduler Parameters (Scalable Structure)
    parameter int IS_INST_PC_BITWIDTH           = 32;
    parameter int IS_INST_PC_STEP               = 4;
    parameter int IS_INST_BITWIDTH               = 32;
    parameter int IS_INST_REGS                   = 32;
    parameter int IS_INST_OPERANDS               = 2;
    parameter int IS_INST_IMM                    = 32;

    parameter int EX_INST_MICROOP_BITWIDTH       = 5;

    parameter int STRUCT_DECODE_NEW_INST        = 2; // Decode width parameter (can be scaled)
    parameter int STRUCT_INST_STATE_ENTRIES     = 128;
    parameter int STRUCT_PHYREGS                 = 64;
    parameter int STRUCT_EX_PATH                 = 3; // Branch, ALU, Memory
    parameter int STRUCT_RS_OUT_ENTRY [STRUCT_EX_PATH] = '{1, 3, 1}; // 1 Branch, 3 ALU, 1 Mem
    parameter int STRUCT_EX_CORES                = 5; // Total 5 Cores
    parameter int STRUCT_EX_OUT_RESULT [STRUCT_EX_CORES] = '{1, 1, 1, 1, 1};
    parameter int STRUCT_PRM_ENTRY_UPDATE        = 3;
    parameter int STRUCT_PRM_ENTRY_BUFFER        = 4;
    parameter int STRUCT_UNALLOCATE_PHYREG       = 4;
    parameter int STRUCT_FLOW_WINDOWS            = 8;
    parameter int STRUCT_FLOW_PC_MAX_RANGE       = 8;

    // Simulation parameters
    parameter string INST_MEM_FILE = "src/TB/1decode3issue/inst.mem";
    parameter string DATA_MEM_FILE = "src/TB/1decode3issue/data.mem";
    parameter int    DRAIN_CYCLES  = 50;

    localparam int _BITWIDTH_LOW_STRUCT_FLOW_WINDOWS = $clog2(STRUCT_FLOW_WINDOWS);
    localparam int _BITWIDTH_CMB_FLOW_INDEXnPC       = _BITWIDTH_LOW_STRUCT_FLOW_WINDOWS + IS_INST_PC_BITWIDTH;

    // Signals
    reg                                                 clk;
    reg                                                 reset_n;

    // Instruction Memory Ports
    reg  [STRUCT_DECODE_NEW_INST-1:0]                    i_im_inst_valid;
    reg  [(STRUCT_DECODE_NEW_INST*IS_INST_BITWIDTH)-1:0] i_im_inst;
    wire [STRUCT_DECODE_NEW_INST-1:0]                    o_im_inst_get;
    wire                                                 o_im_pc_valid;
    wire [_BITWIDTH_CMB_FLOW_INDEXnPC-1:0]               o_im_pc;

    // Mock virtual memory interface
    wire                                                 re_vmem_o;
    wire                                                 we_vmem_o;
    wire [31:0]                                          addr_vmem_o;
    wire [3:0]                                           strb_vmem_o;
    reg  [31:0]                                          rdata_vmem_i;
    wire [31:0]                                          wdata_vmem_o;
    reg                                                  ready_vmem_i;

    // Memories for simulation
    reg [31:0] instruction_memory[0:511];
    reg [31:0] data_memory[0:511];

    reg        end_pc_flag;

    // Load Hex Files
    initial begin
        end_pc_flag = 0;
        $readmemh(INST_MEM_FILE, instruction_memory);
        $readmemh(DATA_MEM_FILE, data_memory);
    end

    // Clock Generation (100MHz)
    always #5 clk = ~clk;

    // DUT Instantiation
    eulsukdo_example_top #(
        .IS_INST_PC_BITWIDTH      (IS_INST_PC_BITWIDTH),
        .IS_INST_PC_STEP          (IS_INST_PC_STEP),
        .IS_INST_BITWIDTH         (IS_INST_BITWIDTH),
        .IS_INST_REGS             (IS_INST_REGS),
        .IS_INST_OPERANDS         (IS_INST_OPERANDS),
        .IS_INST_IMM              (IS_INST_IMM),
        .EX_INST_MICROOP_BITWIDTH (EX_INST_MICROOP_BITWIDTH),
        .STRUCT_DECODE_NEW_INST   (STRUCT_DECODE_NEW_INST),
        .STRUCT_INST_STATE_ENTRIES(STRUCT_INST_STATE_ENTRIES),
        .STRUCT_PHYREGS           (STRUCT_PHYREGS),
        .STRUCT_EX_PATH           (STRUCT_EX_PATH),
        .STRUCT_RS_OUT_ENTRY      (STRUCT_RS_OUT_ENTRY),
        .STRUCT_EX_CORES          (STRUCT_EX_CORES),
        .STRUCT_EX_OUT_RESULT     (STRUCT_EX_OUT_RESULT),
        .STRUCT_PRM_ENTRY_UPDATE  (STRUCT_PRM_ENTRY_UPDATE),
        .STRUCT_PRM_ENTRY_BUFFER  (STRUCT_PRM_ENTRY_BUFFER),
        .STRUCT_UNALLOCATE_PHYREG (STRUCT_UNALLOCATE_PHYREG),
        .STRUCT_FLOW_WINDOWS      (STRUCT_FLOW_WINDOWS),
        .STRUCT_FLOW_PC_MAX_RANGE (STRUCT_FLOW_PC_MAX_RANGE)
    ) dut (
        .clk            (clk),
        .reset_n        (reset_n),
        .i_im_inst_valid(i_im_inst_valid),
        .i_im_inst      (i_im_inst),
        .o_im_inst_get  (o_im_inst_get),
        .o_im_pc_valid  (o_im_pc_valid),
        .o_im_pc        (o_im_pc),
        .re_vmem_o      (re_vmem_o),
        .we_vmem_o      (we_vmem_o),
        .addr_vmem_o    (addr_vmem_o),
        .strb_vmem_o    (strb_vmem_o),
        .rdata_vmem_i   (rdata_vmem_i),
        .wdata_vmem_o   (wdata_vmem_o),
        .ready_vmem_i   (ready_vmem_i)
    );

    // Task to fetch N instructions concurrently (Scalable fetch loop)
    task fetch_instructions;
        reg [31:0] target_pc;
        reg [31:0] word_addr;
        reg [31:0] inst;
        reg        valid;
        reg        prev_ebreak;
        integer    d;

        #1; // wait for outputs to stabilize
        if (o_im_pc_valid) begin
            target_pc = o_im_pc[31:0];
            word_addr = target_pc >> 2;
            prev_ebreak = 1'b0;

            @(negedge clk);
            for (d = 0; d < STRUCT_DECODE_NEW_INST; d = d + 1) begin
                if ((word_addr + d) < 512 && !prev_ebreak) begin
                    inst  = instruction_memory[word_addr + d];
                    // If ebreak (00100073) or invalid value is detected, invalidate current & subsequent slots
                    if (inst == 32'h0010_0073 || inst === 32'hxxxxx) begin
                        valid = 1'b0;
                        prev_ebreak = 1'b1;
                        end_pc_flag = 1'b1;
                    end else begin
                        valid = 1'b1;
                    end
                end else begin
                    inst  = 32'h0;
                    valid = 1'b0;
                end

                i_im_inst[d * IS_INST_BITWIDTH +: IS_INST_BITWIDTH] = inst;
                i_im_inst_valid[d] = valid;
            end
        end else begin
            i_im_inst_valid = 0;
        end
    endtask

    // Virtual memory access handling for the MEM Core
    task data_memory_access_detect;
        int wait_time;
        reg [31:0] mem_addr;
        reg [1:0]  mode;
        
        wait_time = $urandom % 3; // randomize memory access latency (0-2 cycles)
        mem_addr  = addr_vmem_o;
        mem_addr[16] = 1'b0; // mask address to match data memory bounds
        mode      = {re_vmem_o, we_vmem_o};

        @(negedge clk);
        if (mode != 2'b00) begin
            for (int i = 0; i < wait_time; i = i + 1) begin 
                @(negedge clk); 
            end
            
            if (mode == 2'b10) begin // Read operation (Load)
                rdata_vmem_i = data_memory[mem_addr[8:0]]; // Indexing by word offset
                ready_vmem_i = 1'b1;
                $display("[%0d ns] [MEM LOAD] addr: 0x%h -> data: 0x%h", $time, addr_vmem_o, rdata_vmem_i);
            end
            else if (mode == 2'b01) begin // Write operation (Store)
                if (strb_vmem_o[3]) data_memory[mem_addr[8:0]][31:24] = wdata_vmem_o[31:24];
                if (strb_vmem_o[2]) data_memory[mem_addr[8:0]][23:16] = wdata_vmem_o[23:16];
                if (strb_vmem_o[1]) data_memory[mem_addr[8:0]][15: 8] = wdata_vmem_o[15: 8];
                if (strb_vmem_o[0]) data_memory[mem_addr[8:0]][ 7: 0] = wdata_vmem_o[ 7: 0];
                ready_vmem_i = 1'b1;
                $display("[%0d ns] [MEM STORE] addr: 0x%h <- data: 0x%h, strb: %b", $time, addr_vmem_o, wdata_vmem_o, strb_vmem_o);
            end
        end
        @(negedge clk);
        ready_vmem_i = 1'b0;
    endtask

    // Simulation Main Thread
    initial begin
        clk = 1'b0;
        reset_n = 1'b0;
        i_im_inst_valid = 0;
        i_im_inst = 0;
        rdata_vmem_i = 32'h0;
        ready_vmem_i = 1'b0;

        $display("=========================================");
        $display(" Starting EULSUKDO Parameterized Top Testbench");
        $display("   - Decode Width: %0d | Issue Width: 5", STRUCT_DECODE_NEW_INST);
        $display("=========================================");

        // Apply Reset
        @(negedge clk);
        @(negedge clk);
        reset_n = 1'b1;
        $display("[%0d ns] Reset Released. (Bitmap Allocator initialised in 1 cycle)", $time);
        @(negedge clk);

        fork
            // Thread 1: Instruction fetch loop
            begin
                while (!end_pc_flag) begin
                    fetch_instructions();
                end
                $display("[%0d ns] End instruction (ebreak or out-of-bounds) detected. Waiting for pipeline drain...", $time);
                repeat (DRAIN_CYCLES) @(negedge clk);
                $display("=========================================");
                $display(" Simulation completed successfully!");
                $display("=========================================");
                $finish;
            end

            // Thread 2: Virtual Memory controller loop
            begin
                forever begin
                    @(negedge clk);
                    if (re_vmem_o || we_vmem_o) begin
                        data_memory_access_detect();
                    end
                end
            end
        join
    end

endmodule
