`timescale 1ns/1ps
module memory_order_queue #(
    parameter int FLOW_PC_WIDTH = 35,
    parameter int ADDRESS_WIDTH = 32,
    parameter int DATA_WIDTH = 32,
    parameter int MASK_WIDTH = 4,
    parameter int PHYREG_WIDTH = 6,
    parameter int MICROOP_WIDTH = 5,
    parameter int OPERANDS = 2,
    parameter int EXPATH_WIDTH = 2,
    parameter int MEMORY_PATH = 2,
    parameter int NEL_LANES = 2,
    parameter int DEPTH = 128,
    parameter bit ENABLE_STORE_COMMIT = 1'b0,
    parameter bit ENABLE_RECOVERY_FLUSH = 1'b0,
    parameter int AGE_WIDTH = 32,
    localparam int INTERNAL_WIDTH = FLOW_PC_WIDTH + EXPATH_WIDTH + MICROOP_WIDTH
                                  + ADDRESS_WIDTH + PHYREG_WIDTH*(1+OPERANDS) + OPERANDS,
    localparam int PAYLOAD_WIDTH = 1 + ADDRESS_WIDTH + DATA_WIDTH + MASK_WIDTH
                                 + PHYREG_WIDTH + MICROOP_WIDTH,
    localparam int COUNT_WIDTH = $clog2(DEPTH+1),
    localparam int SLOT_WIDTH = (DEPTH > 1) ? $clog2(DEPTH) : 1
) (
    input  wire clk,
    input  wire reset_n,
    input  wire [NEL_LANES-1:0] i_nel_valid,
    input  wire [NEL_LANES*INTERNAL_WIDTH-1:0] i_nel_data,
    input  wire [NEL_LANES*AGE_WIDTH-1:0] i_nel_age,
    output wire o_nel_ready,
    input  wire i_flush_valid,
    input  wire [AGE_WIDTH-1:0] i_flush_age,
    input  wire i_agu_valid,
    output wire o_agu_get,
    input  wire [FLOW_PC_WIDTH-1:0] i_agu_key,
    input  wire [AGE_WIDTH-1:0] i_agu_age,
    input  wire [PAYLOAD_WIDTH-1:0] i_agu_payload,
    output wire o_mem_req_valid,
    input  wire i_mem_req_get,
    output wire [FLOW_PC_WIDTH-1:0] o_mem_req_key,
    output wire [PAYLOAD_WIDTH-1:0] o_mem_req_payload,
    input  wire i_store_commit_valid,
    input  wire [FLOW_PC_WIDTH-1:0] i_store_commit_key,
    input  wire i_mem_resp_valid,
    input  wire [DATA_WIDTH-1:0] i_mem_resp_data,
    output wire o_mem_resp_ready,
    output wire o_mem_complete_valid,
    output wire [FLOW_PC_WIDTH-1:0] o_mem_complete_key,
    output wire o_mem_complete_store,
    output wire [PHYREG_WIDTH-1:0] o_mem_complete_rd,
    output wire [DATA_WIDTH-1:0] o_mem_complete_data
);
    logic [FLOW_PC_WIDTH-1:0] order_key [0:DEPTH-1];
    logic [AGE_WIDTH-1:0] order_age [0:DEPTH-1];
    logic [COUNT_WIDTH-1:0] order_count;
    logic [SLOT_WIDTH-1:0] order_head, order_tail;

    logic [FLOW_PC_WIDTH-1:0] ready_key [0:DEPTH-1];
    logic [AGE_WIDTH-1:0] ready_age [0:DEPTH-1];
    logic [SLOT_WIDTH-1:0] ready_slot [0:DEPTH-1];
    logic [COUNT_WIDTH-1:0] ready_count;
    logic [SLOT_WIDTH-1:0] scan;
    logic [DEPTH-1:0] slot_used;
    logic [PAYLOAD_WIDTH-1:0] result_buffer [0:DEPTH-1];
    logic free_found;
    logic [SLOT_WIDTH-1:0] free_slot;

    logic head_valid;
    logic [FLOW_PC_WIDTH-1:0] head_key;
    logic [PAYLOAD_WIDTH-1:0] head_payload;
    logic [AGE_WIDTH-1:0] head_age;
    logic memory_busy;
    logic [FLOW_PC_WIDTH-1:0] inflight_key;
    logic [PHYREG_WIDTH-1:0] inflight_rd;
    logic inflight_store;
    logic [AGE_WIDTH-1:0] inflight_age;
    logic inflight_killed;
    logic agu_found;
    logic [AGE_WIDTH-1:0] agu_age;
    logic [COUNT_WIDTH-1:0] keep_order_count, keep_ready_count;
    logic [SLOT_WIDTH-1:0] compact_src [0:DEPTH-1];

    logic [NEL_LANES-1:0] nel_memory;
    logic [COUNT_WIDTH-1:0] nel_count;
    logic scan_match, use_head, request_fire, ready_push, head_push;
    wire [FLOW_PC_WIDTH-1:0] order_front = order_key[order_head];

    function automatic [SLOT_WIDTH-1:0] wrap_next(input [SLOT_WIDTH-1:0] position);
        return (position == SLOT_WIDTH'(DEPTH-1)) ? '0 : position + 1'b1;
    endfunction

    // NEL only emits a valid bundle once every lane can be accepted by IST.
    // Reserve enough room for a complete bundle, regardless of its path mix.
    assign o_nel_ready = order_count <= COUNT_WIDTH'(DEPTH-NEL_LANES);
    always_comb begin
        nel_memory = '0;
        nel_count = '0;
        for (int lane = 0; lane < NEL_LANES; lane++) begin
            if (i_nel_valid[lane] &&
                i_nel_data[lane*INTERNAL_WIDTH + FLOW_PC_WIDTH +: EXPATH_WIDTH] == EXPATH_WIDTH'(MEMORY_PATH)) begin
                nel_memory[lane] = 1'b1;
                nel_count = nel_count + 1'b1;
            end
        end
    end

    always_comb begin
        free_found = 1'b0;
        free_slot = '0;
        for (int slot = 0; slot < DEPTH; slot++) begin
            if (!free_found && !slot_used[slot]) begin
                free_found = 1'b1;
                free_slot = SLOT_WIDTH'(slot);
            end
        end
    end

    assign scan_match = (order_count != 0) && (ready_count != 0) &&
                        (ready_key[scan] == order_front);
    assign use_head = head_valid && (order_count != 0) && (head_key == order_front);
    wire [PAYLOAD_WIDTH-1:0] selected_payload = use_head ? head_payload : result_buffer[ready_slot[scan]];
    wire [FLOW_PC_WIDTH-1:0] selected_key = use_head ? head_key : ready_key[scan];
    wire selected_store = selected_payload[PAYLOAD_WIDTH-1];
    // A store cannot escape into an irreversible bus transaction before the
    // retirement frontier grants this exact key. Loads retain their old path.
    assign o_mem_req_valid = !(ENABLE_RECOVERY_FLUSH && i_flush_valid) &&
                             !memory_busy && (use_head || scan_match) &&
                             (!ENABLE_STORE_COMMIT || !selected_store ||
                              (i_store_commit_valid && i_store_commit_key == selected_key));
    assign o_mem_req_key = selected_key;
    assign o_mem_req_payload = selected_payload;
    assign request_fire = o_mem_req_valid && i_mem_req_get;

    // A head result bypasses A. A dedicated register holds it while memory is busy.
    // Other results need a free A slot; upstream AGU/EX must honor o_agu_get.
    always_comb begin
        agu_found = 1'b0;
        agu_age = '0;
        keep_order_count = '0;
        keep_ready_count = '0;
        for (int idx = 0; idx < DEPTH; idx++) compact_src[idx] = '0;
        for (int offset = 0; offset < DEPTH; offset++) begin
            if (offset < int'(order_count)) begin
                if (order_key[(int'(order_head)+offset)%DEPTH] == i_agu_key &&
                    (!ENABLE_RECOVERY_FLUSH || order_age[(int'(order_head)+offset)%DEPTH] == i_agu_age)) begin
                    agu_found = 1'b1;
                    agu_age = order_age[(int'(order_head)+offset)%DEPTH];
                end
                if (order_age[(int'(order_head)+offset)%DEPTH] <= i_flush_age)
                    keep_order_count++;
            end
            if (offset < int'(ready_count) && ready_age[offset] <= i_flush_age) begin
                compact_src[keep_ready_count] = SLOT_WIDTH'(offset);
                keep_ready_count++;
            end
        end
    end
    assign o_agu_get = !(ENABLE_RECOVERY_FLUSH && i_flush_valid) &&
                       (!ENABLE_RECOVERY_FLUSH || agu_found) && (order_count != 0) &&
                       ((i_agu_key == order_front) ? !head_valid :
                        (free_found && ready_count < COUNT_WIDTH'(DEPTH)));
    assign head_push = i_agu_valid && o_agu_get && i_agu_key == order_front && !head_valid;
    assign ready_push = i_agu_valid && o_agu_get && !head_push;

    assign o_mem_resp_ready = memory_busy;
    assign o_mem_complete_valid = memory_busy && i_mem_resp_valid &&
                                  (!ENABLE_RECOVERY_FLUSH ||
                                   (!inflight_killed &&
                                    !(i_flush_valid && inflight_age > i_flush_age)));
    assign o_mem_complete_key = inflight_key;
    assign o_mem_complete_store = inflight_store;
    assign o_mem_complete_rd = inflight_rd;
    assign o_mem_complete_data = i_mem_resp_data;

    for (genvar idx = 0; idx < DEPTH; idx++) begin : GEN_READY_ENTRIES
        always_ff @(posedge clk) begin
            if (reset_n) begin
                if (ENABLE_RECOVERY_FLUSH && i_flush_valid) begin
                    if (idx < int'(keep_ready_count)) begin
                        ready_key[idx] <= ready_key[compact_src[idx]];
                        ready_age[idx] <= ready_age[compact_src[idx]];
                        ready_slot[idx] <= ready_slot[compact_src[idx]];
                    end
                end else begin
                    if (idx < DEPTH-1 && request_fire && !use_head &&
                        idx >= int'(scan) && idx < int'(ready_count)-1) begin
                        ready_key[idx] <= ready_key[idx+1];
                        ready_age[idx] <= ready_age[idx+1];
                        ready_slot[idx] <= ready_slot[idx+1];
                    end
                    if (ready_push && idx == int'(ready_count)-int'(request_fire && !use_head)) begin
                        ready_key[idx] <= i_agu_key;
                        ready_age[idx] <= agu_age;
                        ready_slot[idx] <= free_slot;
                    end
                end
            end
        end
    end

    always_ff @(posedge clk or negedge reset_n) begin
        logic [SLOT_WIDTH-1:0] tail_cursor;
        if (!reset_n) begin
            order_count <= '0;
            order_head <= '0;
            order_tail <= '0;
            ready_count <= '0;
            scan <= '0;
            slot_used <= '0;
            head_valid <= 1'b0;
            head_key <= '0;
            head_payload <= '0;
            head_age <= '0;
            memory_busy <= 1'b0;
            inflight_key <= '0;
            inflight_rd <= '0;
            inflight_store <= 1'b0;
            inflight_age <= '0;
            inflight_killed <= 1'b0;
        end else if (ENABLE_RECOVERY_FLUSH && i_flush_valid) begin
            order_count <= keep_order_count;
            order_tail <= SLOT_WIDTH'((int'(order_head)+int'(keep_order_count))%DEPTH);
            ready_count <= keep_ready_count;
            scan <= '0;
            slot_used <= '0;
            for (int idx = 0; idx < DEPTH; idx++) begin
                if (idx < int'(ready_count) && ready_age[idx] <= i_flush_age)
                    slot_used[ready_slot[idx]] <= 1'b1;
            end
            if (head_valid && head_age > i_flush_age) head_valid <= 1'b0;
            if (memory_busy && inflight_age > i_flush_age) inflight_killed <= 1'b1;
            if (memory_busy && i_mem_resp_valid) begin
                memory_busy <= 1'b0;
                inflight_killed <= 1'b0;
            end
        end else begin
            tail_cursor = order_tail;
            if (o_nel_ready) begin
                for (int lane = 0; lane < NEL_LANES; lane++) begin
                    if (nel_memory[lane]) begin
                        order_key[tail_cursor] <= i_nel_data[lane*INTERNAL_WIDTH +: FLOW_PC_WIDTH];
                        order_age[tail_cursor] <= i_nel_age[lane*AGE_WIDTH +: AGE_WIDTH];
                        tail_cursor = wrap_next(tail_cursor);
                    end
                end
                order_tail <= tail_cursor;
            end
            order_count <= order_count + (o_nel_ready ? nel_count : '0) - COUNT_WIDTH'(request_fire);
            if (request_fire) order_head <= wrap_next(order_head);

            if (head_push) begin
                head_valid <= 1'b1;
                head_key <= i_agu_key;
                head_payload <= i_agu_payload;
                head_age <= agu_age;
            end
            if (request_fire && use_head) head_valid <= 1'b0;

            if (request_fire && !use_head) begin
                slot_used[ready_slot[scan]] <= 1'b0;
                scan <= '0;
            end else if (ready_count != 0 && !memory_busy && !o_mem_req_valid) begin
                scan <= (scan == SLOT_WIDTH'(ready_count-1'b1)) ? '0 : scan + 1'b1;
            end
            if (ready_push) begin
                result_buffer[free_slot] <= i_agu_payload;
                slot_used[free_slot] <= 1'b1;
            end
            ready_count <= ready_count + COUNT_WIDTH'(ready_push)
                                      - COUNT_WIDTH'(request_fire && !use_head);

            if (request_fire) begin
                memory_busy <= 1'b1;
                inflight_key <= o_mem_req_key;
                inflight_rd <= o_mem_req_payload[MICROOP_WIDTH +: PHYREG_WIDTH];
                inflight_store <= selected_store;
                inflight_age <= use_head ? head_age : ready_age[scan];
                inflight_killed <= 1'b0;
            end
            if (memory_busy && i_mem_resp_valid) begin
                memory_busy <= 1'b0;
                inflight_killed <= 1'b0;
            end
        end
    end
endmodule
