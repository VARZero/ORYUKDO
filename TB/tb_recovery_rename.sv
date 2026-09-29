`timescale 1ns/1ps
module tb_recovery_rename;
    logic clk=0;
    always #5 clk=~clk;
    logic reset_n=0, recover=0, retire=0;
    logic [3:0] read_arch=4'd2, write_arch=4'd2, retire_arch=4'd2;
    logic [3:0] write_phy=0, retire_phy=0;
    logic write_en=0;
    wire [3:0] read_phy;
    wire [15:0] reserved;
    wire old_valid;
    wire [3:0] old_phy;
    logic [15:0] used_for_restore=0;
    logic restore=0, allocate=0;
    wire alloc_valid;
    wire [3:0] alloc_phy;
    recoverable_rename_map #(.ARCH_REGS(16), .PHYREGS(16),
        .READ_CHANNELS(1), .WRITE_CHANNELS(1)) rename (
        .clk(clk), .reset_n(reset_n), .i_recover(recover),
        .i_read_addr(read_arch), .o_read_data(read_phy),
        .i_write_addr(write_arch), .i_write_en(write_en), .i_write_data(write_phy),
        .i_retire_write(retire), .i_retire_arch(retire_arch),
        .i_retire_phyreg(retire_phy), .o_reserved_phyreg(reserved),
        .o_retire_old_valid(old_valid), .o_retire_old_phyreg(old_phy));
    recovery_phyreg_allocator #(.PHYREGS(16), .ALLOCATE_CHANNELS(1),
        .UNALLOCATE_CHANNELS(1)) freelist (
        .clk(clk), .reset_n(reset_n), .i_restore(restore),
        .i_reserved(used_for_restore), .i_unallocate(old_valid),
        .i_unallocate_data(old_phy), .i_allocate(allocate),
        .o_allocate_valid(alloc_valid), .o_allocate_data(alloc_phy));
    initial begin
        repeat(2) @(negedge clk);
        reset_n=1;
        write_en=1; write_phy=4'd1;
        @(negedge clk);
        retire=1; retire_phy=4'd1;
        write_phy=4'd2;
        @(negedge clk);
        retire=0; write_phy=4'd3;
        @(negedge clk);
        if (read_phy!=4'd3 || reserved[3] || !reserved[1])
            $fatal(1,"speculative and committed mappings mixed");
        if (old_valid) $fatal(1,"old register returned without retirement");
        write_en=0; recover=1; used_for_restore=reserved; restore=1;
        @(negedge clk);
        recover=0; restore=0;
        if (read_phy!=4'd1 || !alloc_valid || alloc_phy!=4'd2)
            $fatal(1,"rename or physical free list did not roll back");
        retire=1; retire_phy=4'd4; recover=1;
        #1;
        used_for_restore=reserved; restore=1;
        if (!old_valid || old_phy!=4'd1)
            $fatal(1,"overwritten committed register not released at retirement");
        @(negedge clk);
        if (read_phy!=4'd4 || !reserved[4] || alloc_phy!=4'd1)
            $fatal(1,"same-edge retiring branch mapping lost");
        $display("tb_recovery_rename PASS");
        $finish;
    end
endmodule
