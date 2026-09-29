`timescale 1ns/1ps
// Ordered completion and recovery boundary. Keys must be unique among live
// entries. A store is released only at the head; the caller acknowledges its
// external commit before the head advances. No speculative store is released.
module retirement_frontier #(
    parameter int KEY_WIDTH = 35,
    parameter int PC_WIDTH = 32,
    parameter int PC_STEP = 4,
    parameter int DEPTH = 128,
    parameter int EXCEPTION_WIDTH = 5,
    parameter int AGE_WIDTH = 32,
    parameter int ALLOC_LANES = 1,
    parameter int COMPLETE_LANES = 1,
    parameter int ARCH_WIDTH = 5,
    parameter int PHYREG_WIDTH = 6,
    parameter bit USE_ALLOCATED_PREDICTION = 0,
    parameter bit CHECK_AGE = 0,
    parameter int ISSUE_LANES = 1,
    localparam int INDEX_WIDTH = (DEPTH > 1) ? $clog2(DEPTH) : 1,
    localparam int COUNT_WIDTH = $clog2(DEPTH+1)
) (
    input  wire                       clk,
    input  wire                       reset_n,
    input  wire [ALLOC_LANES-1:0]     i_allocate_valid,
    output wire                       o_allocate_ready,
    input  wire [ALLOC_LANES*KEY_WIDTH-1:0] i_allocate_key,
    input  wire [ALLOC_LANES*AGE_WIDTH-1:0] i_allocate_age,
    input  wire [ALLOC_LANES-1:0]     i_allocate_store,
    input  wire [ALLOC_LANES-1:0]     i_allocate_memory,
    input  wire [ALLOC_LANES-1:0]     i_allocate_control,
    input  wire [ALLOC_LANES-1:0]     i_allocate_predicted_taken,
    input  wire [ALLOC_LANES*PC_WIDTH-1:0] i_allocate_predicted_target,
    input  wire [ALLOC_LANES-1:0]     i_allocate_write,
    input  wire [ALLOC_LANES*ARCH_WIDTH-1:0] i_allocate_arch,
    input  wire [ALLOC_LANES*PHYREG_WIDTH-1:0] i_allocate_phyreg,
    input  wire [ALLOC_LANES-1:0]     i_allocate_exception,
    input  wire [ALLOC_LANES*EXCEPTION_WIDTH-1:0] i_allocate_cause,
    input  wire [COMPLETE_LANES-1:0]  i_complete_valid,
    input  wire [COMPLETE_LANES-1:0]  i_complete_memory,
    input  wire [COMPLETE_LANES*KEY_WIDTH-1:0] i_complete_key,
    input  wire [COMPLETE_LANES*AGE_WIDTH-1:0] i_complete_age,
    output logic [COMPLETE_LANES-1:0] o_complete_live,
    input  wire [ISSUE_LANES*KEY_WIDTH-1:0] i_issue_key,
    output logic [ISSUE_LANES*AGE_WIDTH-1:0] o_issue_age,
    input  wire                       i_store_ready_valid,
    input  wire [KEY_WIDTH-1:0]       i_store_ready_key,
    input  wire                       i_resolve_valid,
    input  wire [KEY_WIDTH-1:0]       i_resolve_key,
    input  wire [AGE_WIDTH-1:0]       i_resolve_age,
    output wire                       o_resolve_accept,
    input  wire                       i_resolve_taken,
    input  wire [PC_WIDTH-1:0]        i_resolve_target,
    input  wire                       i_resolve_predicted_taken,
    input  wire [PC_WIDTH-1:0]        i_resolve_predicted_target,
    input  wire                       i_fault_valid,
    input  wire [KEY_WIDTH-1:0]       i_fault_key,
    input  wire [AGE_WIDTH-1:0]       i_fault_age,
    input  wire [EXCEPTION_WIDTH-1:0] i_fault_cause,
    input  wire                       i_interrupt_pending,
    input  wire [PC_WIDTH-1:0]        i_trap_vector,
    input  wire                       i_store_commit_get,
    output wire                       o_store_commit_valid,
    output wire [KEY_WIDTH-1:0]       o_store_commit_key,
    output wire                       o_retire_valid,
    output wire [KEY_WIDTH-1:0]       o_retire_key,
    output wire                       o_retire_write,
    output wire [ARCH_WIDTH-1:0]      o_retire_arch,
    output wire [PHYREG_WIDTH-1:0]    o_retire_phyreg,
    output logic                      o_recover_valid,
    output logic [KEY_WIDTH-1:0]      o_recover_key,
    output logic [AGE_WIDTH-1:0]      o_recover_age,
    output logic [PC_WIDTH-1:0]       o_redirect_pc,
    output logic                      o_trap_valid,
    output logic                      o_trap_interrupt,
    output logic [EXCEPTION_WIDTH-1:0] o_trap_cause,
    output logic [KEY_WIDTH-1:0]      o_trap_key,
    output logic [PC_WIDTH-1:0]       o_trap_pc,
    output wire [COUNT_WIDTH-1:0]     o_count
);
    logic [KEY_WIDTH-1:0] entry_key [0:DEPTH-1];
    logic [AGE_WIDTH-1:0] entry_age [0:DEPTH-1];
    logic [DEPTH-1:0] entry_done, entry_store, entry_fault, entry_resolved;
    logic [DEPTH-1:0] entry_memory, entry_mem_done;
    logic [DEPTH-1:0] entry_control;
    logic [DEPTH-1:0] entry_wrong, entry_write;
    logic [DEPTH-1:0] entry_predicted_taken;
    logic [PC_WIDTH-1:0] entry_predicted_target [0:DEPTH-1];
    logic [PC_WIDTH-1:0] entry_redirect [0:DEPTH-1];
    logic [ARCH_WIDTH-1:0] entry_arch [0:DEPTH-1];
    logic [PHYREG_WIDTH-1:0] entry_phyreg [0:DEPTH-1];
    logic [EXCEPTION_WIDTH-1:0] entry_cause [0:DEPTH-1];
    logic [INDEX_WIDTH-1:0] head, tail;
    logic [PC_WIDTH-1:0] resume_pc;
    logic [COUNT_WIDTH-1:0] count;
    logic resolve_found, fault_found;
    logic [INDEX_WIDTH-1:0] resolve_index, fault_index;
    logic mispredict;
    logic branch_recover, fault_recover, interrupt_recover;
    logic retire_fire;
    logic [ALLOC_LANES-1:0] allocate_fire;
    logic [COUNT_WIDTH-1:0] allocate_count;

    function automatic [INDEX_WIDTH-1:0] advance(input [INDEX_WIDTH-1:0] index);
        return (index == INDEX_WIDTH'(DEPTH-1)) ? '0 : index + 1'b1;
    endfunction

    always_comb begin
        resolve_found = 1'b0;
        fault_found = 1'b0;
        resolve_index = '0;
        fault_index = '0;
        for (int offset = 0; offset < DEPTH; offset++) begin
            if (offset < int'(count)) begin
                if (i_resolve_valid && entry_control[(int'(head)+offset)%DEPTH] &&
                    entry_key[(int'(head)+offset)%DEPTH] == i_resolve_key &&
                    (!CHECK_AGE || entry_age[(int'(head)+offset)%DEPTH] == i_resolve_age) && !resolve_found) begin
                    resolve_found = 1'b1;
                    resolve_index = INDEX_WIDTH'((int'(head)+offset)%DEPTH);
                end
                if (i_fault_valid && entry_key[(int'(head)+offset)%DEPTH] == i_fault_key &&
                    (!CHECK_AGE || entry_age[(int'(head)+offset)%DEPTH] == i_fault_age) && !fault_found) begin
                    fault_found = 1'b1;
                    fault_index = INDEX_WIDTH'((int'(head)+offset)%DEPTH);
                end
            end
        end
    end
    always_comb begin
        o_complete_live = '0;
        for (int offset = 0; offset < DEPTH; offset++) begin
            if (offset < int'(count)) begin
                for (int lane = 0; lane < COMPLETE_LANES; lane++) begin
                    if (entry_key[(int'(head)+offset)%DEPTH] == i_complete_key[lane*KEY_WIDTH +: KEY_WIDTH] &&
                        (!CHECK_AGE || entry_age[(int'(head)+offset)%DEPTH] == i_complete_age[lane*AGE_WIDTH +: AGE_WIDTH]))
                        o_complete_live[lane] = 1'b1;
                end
            end
        end
    end
    always_comb begin
        o_issue_age = '0;
        for (int offset = 0; offset < DEPTH; offset++) begin
            if (offset < int'(count)) begin
                for (int lane = 0; lane < ISSUE_LANES; lane++) begin
                    if (entry_key[(int'(head)+offset)%DEPTH] == i_issue_key[lane*KEY_WIDTH +: KEY_WIDTH])
                        o_issue_age[lane*AGE_WIDTH +: AGE_WIDTH] = entry_age[(int'(head)+offset)%DEPTH];
                end
            end
        end
    end

    assign mispredict = USE_ALLOCATED_PREDICTION ?
        (i_resolve_taken != entry_predicted_taken[resolve_index] ||
         (i_resolve_taken && i_resolve_target != entry_predicted_target[resolve_index])) :
        (i_resolve_taken != i_resolve_predicted_taken ||
         (i_resolve_taken && i_resolve_target != i_resolve_predicted_target));
    assign o_resolve_accept = resolve_found;
    assign fault_recover = count != 0 && entry_fault[head] && entry_done[head];
    // A branch result is remembered until every older instruction retires.
    // Only then may a global rollback discard the younger backend state.
    assign branch_recover = count != 0 && entry_done[head] &&
                            entry_resolved[head] && entry_wrong[head] && !fault_recover;
    assign interrupt_recover = i_interrupt_pending && count == 0;
    always_comb begin
        allocate_count = '0;
        for (int lane = 0; lane < ALLOC_LANES; lane++)
            if (allocate_fire[lane]) allocate_count++;
    end
    assign o_allocate_ready = count <= COUNT_WIDTH'(DEPTH-ALLOC_LANES) && !branch_recover &&
                              !fault_recover && !interrupt_recover;
    assign allocate_fire = i_allocate_valid & {ALLOC_LANES{o_allocate_ready}};
    assign o_store_commit_valid = count != 0 && entry_done[head] &&
                                  entry_store[head] && !entry_fault[head] && !branch_recover;
    assign o_store_commit_key = entry_key[head];
    assign o_retire_valid = count != 0 && entry_done[head] && entry_resolved[head] && !entry_fault[head] &&
                            (!entry_memory[head] || entry_mem_done[head] ||
                             (entry_store[head] && i_store_commit_get)) &&
                            (!entry_store[head] || i_store_commit_get);
    assign o_retire_key = entry_key[head];
    assign o_retire_write = o_retire_valid && entry_write[head];
    assign o_retire_arch = entry_arch[head];
    assign o_retire_phyreg = entry_phyreg[head];
    assign retire_fire = o_retire_valid;
    assign o_count = count;

    always_comb begin
        o_recover_valid = branch_recover || fault_recover || interrupt_recover;
        o_recover_key = '0;
        o_recover_age = '0;
        o_redirect_pc = '0;
        o_trap_valid = fault_recover || interrupt_recover;
        o_trap_interrupt = interrupt_recover;
        o_trap_cause = '0;
        o_trap_key = '0;
        o_trap_pc = '0;
        if (branch_recover) begin
            o_recover_key = entry_key[head];
            o_recover_age = entry_age[head];
            o_redirect_pc = entry_redirect[head];
        end else if (fault_recover) begin
            o_recover_key = entry_key[head];
            o_recover_age = entry_age[head];
            o_redirect_pc = i_trap_vector;
            o_trap_cause = entry_cause[head];
            o_trap_key = entry_key[head];
            o_trap_pc = entry_key[head][0 +: PC_WIDTH];
        end else if (interrupt_recover) begin
            o_redirect_pc = i_trap_vector;
            o_trap_pc = resume_pc;
        end
    end

    always_ff @(posedge clk or negedge reset_n) begin
        logic [INDEX_WIDTH-1:0] tail_cursor;
        if (!reset_n) begin
            head <= '0;
            tail <= '0;
            count <= '0;
            resume_pc <= '0;
            entry_done <= '0;
            entry_store <= '0;
            entry_memory <= '0;
            entry_mem_done <= '0;
            entry_fault <= '0;
            entry_resolved <= '0;
            entry_control <= '0;
            entry_wrong <= '0;
            entry_write <= '0;
            entry_predicted_taken <= '0;
        end else begin
            for (int lane = 0; lane < COMPLETE_LANES; lane++) begin
                if (i_complete_valid[lane] && o_complete_live[lane]) begin
                    for (int offset = 0; offset < DEPTH; offset++) begin
                        if (offset < int'(count) &&
                            entry_key[(int'(head)+offset)%DEPTH] ==
                            i_complete_key[lane*KEY_WIDTH +: KEY_WIDTH] &&
                            (!CHECK_AGE || entry_age[(int'(head)+offset)%DEPTH] == i_complete_age[lane*AGE_WIDTH +: AGE_WIDTH])) begin
                            entry_done[(int'(head)+offset)%DEPTH] <= 1'b1;
                            if (i_complete_memory[lane])
                                entry_mem_done[(int'(head)+offset)%DEPTH] <= 1'b1;
                        end
                    end
                end
            end
            if (i_store_ready_valid) begin
                for (int offset = 0; offset < DEPTH; offset++) begin
                    if (offset < int'(count) &&
                        entry_key[(int'(head)+offset)%DEPTH] == i_store_ready_key) begin
                        entry_store[(int'(head)+offset)%DEPTH] <= 1'b1;
                        entry_done[(int'(head)+offset)%DEPTH] <= 1'b1;
                    end
                end
            end
            if (fault_found) begin
                entry_fault[fault_index] <= 1'b1;
                entry_cause[fault_index] <= i_fault_cause;
            end
            if (resolve_found) begin
                entry_resolved[resolve_index] <= 1'b1;
                entry_wrong[resolve_index] <= mispredict;
                entry_redirect[resolve_index] <= i_resolve_taken ? i_resolve_target :
                    i_resolve_key[0 +: PC_WIDTH] + PC_WIDTH'(PC_STEP);
            end
            if (branch_recover) begin
                // The branch commits with recovery; every older entry is gone.
                resume_pc <= entry_redirect[head];
                head <= '0;
                tail <= '0;
                count <= '0;
            end else if (fault_recover) begin
                // An exception is delivered at the exact retirement frontier.
                // Younger work is invalid and must be removed by the consumers.
                head <= '0;
                tail <= '0;
                count <= '0;
            end else begin
                if (retire_fire) begin
                    head <= advance(head);
                    resume_pc <= entry_control[head] ? entry_redirect[head] :
                        entry_key[head][0 +: PC_WIDTH] + PC_WIDTH'(PC_STEP);
                end
                tail_cursor = tail;
                for (int lane = 0; lane < ALLOC_LANES; lane++) begin
                    if (allocate_fire[lane]) begin
                        entry_key[tail_cursor] <= i_allocate_key[lane*KEY_WIDTH +: KEY_WIDTH];
                        entry_age[tail_cursor] <= i_allocate_age[lane*AGE_WIDTH +: AGE_WIDTH];
                        entry_done[tail_cursor] <= i_allocate_exception[lane];
                        entry_store[tail_cursor] <= i_allocate_store[lane];
                        entry_memory[tail_cursor] <= i_allocate_memory[lane];
                        entry_mem_done[tail_cursor] <= 1'b0;
                        entry_resolved[tail_cursor] <= !i_allocate_control[lane];
                        entry_control[tail_cursor] <= i_allocate_control[lane];
                        entry_wrong[tail_cursor] <= 1'b0;
                        entry_write[tail_cursor] <= i_allocate_write[lane];
                        entry_predicted_taken[tail_cursor] <= i_allocate_predicted_taken[lane];
                        entry_predicted_target[tail_cursor] <= i_allocate_predicted_target[lane*PC_WIDTH +: PC_WIDTH];
                        entry_arch[tail_cursor] <= i_allocate_arch[lane*ARCH_WIDTH +: ARCH_WIDTH];
                        entry_phyreg[tail_cursor] <= i_allocate_phyreg[lane*PHYREG_WIDTH +: PHYREG_WIDTH];
                        entry_fault[tail_cursor] <= i_allocate_exception[lane];
                        entry_cause[tail_cursor] <= i_allocate_cause[lane*EXCEPTION_WIDTH +: EXCEPTION_WIDTH];
                        tail_cursor = advance(tail_cursor);
                    end
                end
                tail <= tail_cursor;
                count <= count + allocate_count - COUNT_WIDTH'(retire_fire);
            end
        end
    end
endmodule
