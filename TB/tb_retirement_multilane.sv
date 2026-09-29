`timescale 1ns/1ps
module tb_retirement_multilane;
    logic clk=0;
    always #5 clk=~clk;
    logic reset_n=0;
    logic [1:0] alloc_valid=0, complete_valid=0, alloc_control=0;
    logic [23:0] alloc_key=0, complete_key=0;
    logic [15:0] alloc_age=0;
    logic resolve_valid=0, resolve_taken=0;
    logic [11:0] resolve_key=0;
    logic [7:0] resolve_target=0;
    wire alloc_ready, retire_valid, recover_valid;
    wire [11:0] retire_key, recover_key;
    wire [7:0] recover_age;
    wire [3:0] count;
    retirement_frontier #(.KEY_WIDTH(12), .PC_WIDTH(8), .DEPTH(8),
        .AGE_WIDTH(8), .ALLOC_LANES(2), .COMPLETE_LANES(2)) dut (
        .clk(clk), .reset_n(reset_n), .i_allocate_valid(alloc_valid),
        .o_allocate_ready(alloc_ready), .i_allocate_key(alloc_key),
        .i_allocate_age(alloc_age), .i_allocate_memory('0), .i_allocate_store(2'b0),
        .i_allocate_control(alloc_control), .i_allocate_exception(2'b0),
        .i_allocate_predicted_taken('0), .i_allocate_predicted_target('0),
        .i_allocate_write('0), .i_allocate_arch('0), .i_allocate_phyreg('0),
        .i_allocate_cause('0), .i_complete_memory('0), .i_complete_valid(complete_valid),
        .i_complete_age('0), .o_complete_live(), .i_issue_key('0), .o_issue_age(), .i_complete_key(complete_key), .i_store_ready_valid(1'b0),
        .i_store_ready_key('0), .i_resolve_valid(resolve_valid),
        .i_resolve_age('0), .o_resolve_accept(), .i_resolve_key(resolve_key), .i_resolve_taken(resolve_taken),
        .i_resolve_target(resolve_target), .i_resolve_predicted_taken(1'b0),
        .i_resolve_predicted_target('0), .i_fault_valid(1'b0),
        .i_fault_age('0), .i_fault_key('0), .i_fault_cause('0), .i_interrupt_pending(1'b0),
        .i_trap_vector('0), .i_store_commit_get(1'b0),
        .o_store_commit_valid(), .o_store_commit_key(),
        .o_retire_valid(retire_valid), .o_retire_key(retire_key),
        .o_retire_write(), .o_retire_arch(), .o_retire_phyreg(),
        .o_recover_valid(recover_valid), .o_recover_key(recover_key),
        .o_recover_age(recover_age), .o_redirect_pc(), .o_trap_valid(),
        .o_trap_interrupt(), .o_trap_cause(), .o_trap_pc(), .o_trap_key(), .o_count(count)
    );
    initial begin
        repeat(2) @(negedge clk); reset_n=1;
        alloc_valid=2'b11; alloc_key={12'h105,12'h101};
        alloc_age={8'd2,8'd1}; alloc_control=2'b10;
        #1; if(!alloc_ready) $fatal(1,"bundle blocked");
        @(negedge clk); alloc_valid=0;
        complete_valid=2'b11; complete_key={12'h105,12'h101};
        @(negedge clk); complete_valid=0;
        #1; if(!retire_valid || retire_key!=12'h101) $fatal(1,"first lane not head");
        @(negedge clk);
        #1; if(retire_valid || count!=1) $fatal(1,"unresolved branch retired");
        resolve_valid=1; resolve_key=12'h105; resolve_taken=1; resolve_target=8'h40;
        @(posedge clk);
        #1; if(!recover_valid || recover_key!=12'h105 || recover_age!=8'd2)
            $fatal(1,"branch age/key lost");
        @(negedge clk); resolve_valid=0;
        @(posedge clk);
        #1; if(count!=0) $fatal(1,"resolved branch and younger entries not drained");
        $display("tb_retirement_multilane PASS");
        $finish;
    end
endmodule
