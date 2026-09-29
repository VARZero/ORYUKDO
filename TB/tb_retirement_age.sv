`timescale 1ns/1ps
module tb_retirement_age;
    logic clk=0;
    always #5 clk=~clk;
    logic reset_n=0, alloc=0, complete=0, resolve=0, fault=0;
    logic [7:0] age=0, complete_age=0, resolve_age=0, fault_age=0;
    logic [11:0] key=12'h101;
    wire live, retire, accepted, recover;
    wire [7:0] issue_age;
    retirement_frontier #(.KEY_WIDTH(12),.PC_WIDTH(8),.DEPTH(4),
        .AGE_WIDTH(8),.CHECK_AGE(1'b1),.USE_ALLOCATED_PREDICTION(1'b1)) dut (
        .clk(clk), .reset_n(reset_n), .i_allocate_valid(alloc), .o_allocate_ready(),
        .i_allocate_key(key),.i_allocate_age(age),.i_allocate_memory('0), .i_allocate_store(1'b0),
        .i_allocate_control(1'b1),.i_allocate_predicted_taken(1'b0),
        .i_allocate_predicted_target('0),.i_allocate_write(1'b0),
        .i_allocate_arch('0),.i_allocate_phyreg('0),
        .i_allocate_exception(1'b0),.i_allocate_cause('0),
        .i_complete_memory('0), .i_complete_valid(complete),.i_complete_key(key),.i_complete_age(complete_age),
        .o_complete_live(live),.i_issue_key(key),.o_issue_age(issue_age),
        .i_store_ready_valid(1'b0),.i_store_ready_key('0),
        .i_resolve_valid(resolve),.i_resolve_key(key),.i_resolve_age(resolve_age),
        .o_resolve_accept(accepted),.i_resolve_taken(1'b1),.i_resolve_target(8'h80),
        .i_resolve_predicted_taken(1'b1),.i_resolve_predicted_target(8'h80),
        .i_fault_valid(fault),.i_fault_key(key),.i_fault_age(fault_age),.i_fault_cause('0),
        .i_interrupt_pending(1'b0),.i_trap_vector('0),.i_store_commit_get(1'b0),
        .o_store_commit_valid(),.o_store_commit_key(),
        .o_retire_valid(retire),.o_retire_key(),.o_retire_write(),
        .o_retire_arch(),.o_retire_phyreg(),.o_recover_valid(recover),
        .o_recover_key(),.o_recover_age(),.o_redirect_pc(),
        .o_trap_valid(),.o_trap_interrupt(),.o_trap_cause(),.o_trap_pc(), .o_trap_key(),.o_count());
    initial begin
        repeat(2) @(negedge clk); reset_n=1;
        age=8'd5; alloc=1;
        @(negedge clk); alloc=0;
        if (issue_age!=8'd5) $fatal(1,"issue age unavailable");
        complete=1; resolve=1; complete_age=8'd4; resolve_age=8'd4;
        #1; if (live || accepted) $fatal(1,"stale generation accepted");
        @(negedge clk);
        if (retire || recover) $fatal(1,"stale generation completed branch");
        complete_age=8'd5; resolve_age=8'd5;
        #1; if (!live || !accepted) $fatal(1,"live generation rejected");
        @(negedge clk); complete=0; resolve=0;
        #1; if (!recover) $fatal(1,"stored prediction not used");
        $display("tb_retirement_age PASS");
        $finish;
    end
endmodule
