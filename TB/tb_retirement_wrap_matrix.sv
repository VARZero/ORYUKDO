`timescale 1ns/1ps
// Repeated bundles cross non-power-of-two frontier head/tail boundaries.
module tb_retirement_wrap_matrix #(
    parameter int DEPTH = 10,
    parameter int LANES = 3,
    parameter int ROUNDS = 20
);
    logic clk = 0;
    always #5 clk = ~clk;
    logic reset_n = 0;
    logic [LANES-1:0] alloc_valid = 0, complete_valid = 0;
    wire [LANES*12-1:0] alloc_key, complete_key;
    wire [LANES*16-1:0] alloc_age, complete_age;
    logic [15:0] round_base = 0;
    logic stale_mode = 0;
    wire alloc_ready, retire_valid, recover_valid;
    wire [LANES-1:0] complete_live;
    wire [11:0] retire_key;
    wire [$clog2(DEPTH+1)-1:0] count;

    for (genvar lane = 0; lane < LANES; lane++) begin : GEN_TAGS
        assign alloc_key[lane*12 +: 12] = 12'(round_base+lane+1);
        assign alloc_age[lane*16 +: 16] = 16'(round_base+lane+1);
        assign complete_key[lane*12 +: 12] = 12'(round_base+(stale_mode ? 1 : LANES-lane));
        assign complete_age[lane*16 +: 16] = 16'(round_base+(stale_mode ? 2 : LANES-lane));
    end

    retirement_frontier #(
        .KEY_WIDTH(12), .PC_WIDTH(8), .AGE_WIDTH(16), .DEPTH(DEPTH),
        .ALLOC_LANES(LANES), .COMPLETE_LANES(LANES), .CHECK_AGE(1'b1)
    ) dut (
        .clk(clk), .reset_n(reset_n), .i_allocate_valid(alloc_valid),
        .o_allocate_ready(alloc_ready), .i_allocate_key(alloc_key),
        .i_allocate_age(alloc_age), .i_allocate_store('0),
        .i_allocate_memory('0), .i_allocate_control('0),
        .i_allocate_predicted_taken('0), .i_allocate_predicted_target('0),
        .i_allocate_write('0), .i_allocate_arch('0), .i_allocate_phyreg('0),
        .i_allocate_exception('0), .i_allocate_cause('0),
        .i_complete_valid(complete_valid), .i_complete_memory('0),
        .i_complete_key(complete_key), .i_complete_age(complete_age),
        .o_complete_live(complete_live), .i_issue_key('0), .o_issue_age(),
        .i_store_ready_valid(1'b0), .i_store_ready_key('0),
        .i_resolve_valid(1'b0), .i_resolve_key('0), .i_resolve_age('0),
        .o_resolve_accept(), .i_resolve_taken(1'b0), .i_resolve_target('0),
        .i_resolve_predicted_taken(1'b0), .i_resolve_predicted_target('0),
        .i_fault_valid(1'b0), .i_fault_key('0), .i_fault_age('0),
        .i_fault_cause('0), .i_interrupt_pending(1'b0),
        .i_trap_vector('0), .i_store_commit_get(1'b0),
        .o_store_commit_valid(), .o_store_commit_key(),
        .o_retire_valid(retire_valid), .o_retire_key(retire_key),
        .o_retire_write(), .o_retire_arch(), .o_retire_phyreg(),
        .o_recover_valid(recover_valid), .o_recover_key(), .o_recover_age(),
        .o_redirect_pc(), .o_trap_valid(), .o_trap_interrupt(),
        .o_trap_cause(), .o_trap_key(), .o_trap_pc(), .o_count(count)
    );

    initial begin
        repeat (2) @(negedge clk);
        reset_n = 1;
        for (int round = 0; round < ROUNDS; round++) begin
            round_base = 16'(round*LANES);
            alloc_valid = '1;
            #1;
            if (!alloc_ready) $fatal(1,"bundle admission blocked at round %0d",round);
            @(negedge clk);
            alloc_valid = 0;
            if (count != LANES) $fatal(1,"bundle count mismatch at round %0d",round);
            // A matching key with the wrong age must be rejected.
            stale_mode = 1;
            complete_valid = LANES'(1);
            #1;
            if (complete_live[0]) $fatal(1,"stale completion accepted at round %0d",round);
            @(negedge clk);
            stale_mode = 0;
            complete_valid = '1;
            #1;
            if (complete_live != {LANES{1'b1}})
                $fatal(1,"live completion lost at round %0d: %b",round,complete_live);
            @(negedge clk);
            complete_valid = 0;
            for (int lane = 0; lane < LANES; lane++) begin
                #1;
                if (!retire_valid || retire_key != 12'(round*LANES+lane+1) || recover_valid)
                    $fatal(1,"retirement order failed at round %0d lane %0d key %0d",round,lane,retire_key);
                @(negedge clk);
            end
            if (count != 0) $fatal(1,"frontier did not drain at round %0d",round);
        end
        $display("frontier depth=%0d lanes=%0d rounds=%0d wrap and age PASS",DEPTH,LANES,ROUNDS);
        $finish;
    end
endmodule
