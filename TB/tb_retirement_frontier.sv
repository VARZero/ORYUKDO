`timescale 1ns/1ps
module tb_retirement_frontier;
    logic clk = 0;
    always #5 clk = ~clk;
    logic reset_n = 0, allocate_valid = 0, allocate_store = 0;
    logic allocate_exception = 0, complete_valid = 0, resolve_valid = 0;
    logic allocate_memory = 0, complete_memory = 0;
    logic resolve_taken = 0, predicted_taken = 0, fault_valid = 0;
    logic interrupt_pending = 0, store_get = 0;
    logic [11:0] allocate_key = 0, complete_key = 0, resolve_key = 0, fault_key = 0;
    logic [7:0] resolve_target = 0, predicted_target = 0, trap_vector = 8'hf0;
    logic [3:0] allocate_cause = 0, fault_cause = 0;
    wire allocate_ready, store_valid, retire_valid, recover_valid, trap_valid, trap_interrupt;
    wire [11:0] store_key, retire_key, recover_key, trap_key;
    wire [7:0] redirect_pc;
    wire [3:0] trap_cause, count;

    retirement_frontier #(.KEY_WIDTH(12), .PC_WIDTH(8), .DEPTH(8), .EXCEPTION_WIDTH(4)) dut (
        .clk(clk), .reset_n(reset_n),
        .i_allocate_valid(allocate_valid), .o_allocate_ready(allocate_ready),
        .i_allocate_key(allocate_key), .i_allocate_age(32'(allocate_key)),
        .i_allocate_memory(allocate_memory), .i_allocate_store(allocate_store),
        .i_allocate_control(allocate_key==12'h105),
        .i_allocate_predicted_taken(1'b0), .i_allocate_predicted_target('0),
        .i_allocate_write(1'b0), .i_allocate_arch('0), .i_allocate_phyreg('0),
        .i_allocate_exception(allocate_exception), .i_allocate_cause(allocate_cause),
        .i_complete_memory(complete_memory), .i_complete_valid(complete_valid), .i_complete_age('0), .o_complete_live(), .i_issue_key('0), .o_issue_age(), .i_complete_key(complete_key),
        .i_store_ready_valid(1'b0), .i_store_ready_key('0),
        .i_resolve_valid(resolve_valid), .i_resolve_age('0), .o_resolve_accept(), .i_resolve_key(resolve_key),
        .i_resolve_taken(resolve_taken), .i_resolve_target(resolve_target),
        .i_resolve_predicted_taken(predicted_taken), .i_resolve_predicted_target(predicted_target),
        .i_fault_valid(fault_valid), .i_fault_age('0), .i_fault_key(fault_key), .i_fault_cause(fault_cause),
        .i_interrupt_pending(interrupt_pending), .i_trap_vector(trap_vector),
        .i_store_commit_get(store_get), .o_store_commit_valid(store_valid),
        .o_store_commit_key(store_key), .o_retire_valid(retire_valid), .o_retire_key(retire_key),
        .o_retire_write(), .o_retire_arch(), .o_retire_phyreg(),
        .o_recover_valid(recover_valid), .o_recover_key(recover_key), .o_recover_age(),
        .o_redirect_pc(redirect_pc),
        .o_trap_valid(trap_valid), .o_trap_interrupt(trap_interrupt),
        .o_trap_cause(trap_cause), .o_trap_pc(), .o_trap_key(trap_key), .o_count(count)
    );

    task automatic tick;
        @(posedge clk); #1;
    endtask
    task automatic allocate(input [11:0] key, input bit is_store, input bit is_fault);
        @(negedge clk);
        allocate_key = key;
        allocate_store = is_store;
        allocate_exception = is_fault;
        allocate_cause = 4'h3;
        allocate_valid = 1;
        if (!allocate_ready) $fatal(1, "allocation blocked unexpectedly");
        tick();
        allocate_valid = 0;
    endtask
    task automatic complete(input [11:0] key);
        @(negedge clk);
        complete_key = key;
        complete_valid = 1;
        tick();
        complete_valid = 0;
    endtask

    initial begin
        tick(); reset_n = 1;
        allocate(12'h101, 0, 0);
        allocate(12'h105, 0, 0);
        allocate(12'h109, 1, 0);
        complete(12'h109);
        if (store_valid || retire_valid) $fatal(1, "younger store escaped frontier");
        @(negedge clk);
        resolve_key = 12'h105;
        resolve_taken = 1;
        resolve_target = 8'h40;
        predicted_taken = 0;
        resolve_valid = 1;
        #1;
        if (recover_valid) $fatal(1, "branch recovered before older retirement");
        tick(); resolve_valid = 0;
        if (count != 3 || store_valid) $fatal(1, "speculative store escaped");
        complete(12'h105);
        complete(12'h101);
        if (!retire_valid || retire_key != 12'h101) $fatal(1, "oldest completion not retired");
        tick();
        if (!recover_valid || recover_key != 12'h105 || redirect_pc != 8'h40)
            $fatal(1, "wrong branch redirect at frontier");
        tick();
        if (count != 0 || store_valid) $fatal(1, "younger store was not squashed");
        allocate(12'h141, 1, 0);
        complete(12'h141);
        if (!store_valid || retire_valid) $fatal(1, "store requires commit ack");
        @(negedge clk); store_get = 1; #1;
        if (!retire_valid) $fatal(1, "committed store did not retire");
        tick(); store_get = 0;
        allocate_memory=1;
        allocate(12'h142, 0, 0);
        allocate_memory=0;
        complete(12'h142);
        if (retire_valid) $fatal(1,"AGU WBC retired a load before LSQ response");
        complete_memory=1;
        complete(12'h142);
        complete_memory=0;
        if (!retire_valid || retire_key!=12'h142) $fatal(1,"LSQ completion did not retire load");
        tick();
        allocate(12'h143, 0, 0);
        allocate(12'h145, 0, 1);
        allocate(12'h149, 0, 0);
        if (trap_valid) $fatal(1, "younger exception entered before older retirement");
        complete(12'h143);
        tick();
        if (!trap_valid || trap_cause != 4'h3 || trap_key != 12'h145 || redirect_pc != trap_vector)
            $fatal(1, "imprecise exception");
        tick();
        if (count != 0) $fatal(1, "exception did not squash younger instruction");
        @(negedge clk); interrupt_pending = 1;
        #1;
        if (!trap_valid || !trap_interrupt || !recover_valid) $fatal(1, "interrupt entry missing");
        $display("tb_retirement_frontier PASS");
        $finish;
    end
endmodule
