`timescale 1ns/1ps
// EULSUKDO 9b0e1c6 pipelined PRM dependency engine, with physical allocation
// supplied by ORYUKDO's recoverable rename map. Reset on rollback cancels all
// waiter mappings; committed operands enter IST with their ready bits set.
module oryukdo_dependency_mapper #(
    // Instruction Set Parameters
    parameter int IS_INST_PC_BITWIDTH                   = 32,
    parameter int IS_INST_PC_STEP                       = 4,
    parameter int IS_INST_BITWIDTH                      = 32,
    parameter int IS_INST_REGS                          = 32,
    parameter int IS_INST_OPERANDS                      = 2,
    parameter int IS_INST_IMM                           = 32,

    // Execution Unit Parameters
    parameter int EX_INST_MICROOP_BITWIDTH              = 5,

    // EULSUKDO Structure Parameters
    parameter int STRUCT_DECODE_NEW_INST                = 2,
    parameter int STRUCT_INST_STATE_ENTRIES             = 128,
    parameter int STRUCT_PHYREGS                        = 64,
    parameter int STRUCT_EX_PATH                        = 3,
    parameter int STRUCT_RS_OUT_ENTRY[STRUCT_EX_PATH]   = {1, 3, 1},
    parameter int STRUCT_EX_CORES                       = 5,
    parameter int STRUCT_EX_OUT_RESULT[STRUCT_EX_CORES] = {1, 1, 1, 1, 1},
    parameter int STRUCT_EX_OUT_RESULT_SUM              = 5,
    parameter int STRUCT_EX_BRANCH                      = 1,
    parameter int STRUCT_PRM_ENTRY_UPDATE               = 5,
    parameter int STRUCT_PRM_ENTRY_BUFFER               = 4,
    parameter int STRUCT_UNALLOCATE_PHYREG              = 4,
    parameter int STRUCT_FLOW_WINDOWS                   = 8,
    parameter int STRUCT_FLOW_PC_MAX_RANGE              = 16,
    parameter int STRUCT_PRM_OUTPUT_FIFO_DEPTH          = 64,
    parameter int STRUCT_PRM_INPUT_BUFFER_DEPTH         = 3,

    // Synthesis Create Local Parameters
    localparam int _BITWIDTH_IS_INST_REGS               = $clog2(IS_INST_REGS),
    localparam int _BITWIDTH_STRUCT_INST_STATE_ENTRIES  = $clog2(STRUCT_INST_STATE_ENTRIES),
    localparam int _BITWIDTH_STRUCT_PHYREGS             = $clog2(STRUCT_PHYREGS),
    localparam int _BITWIDTH_STRUCT_EX_PATH             = $clog2(STRUCT_EX_PATH),
    localparam int _BITWIDTH_STRUCT_FLOW_WINDOWS        = (STRUCT_FLOW_WINDOWS > 1)? $clog2(STRUCT_FLOW_WINDOWS) : 1,
    localparam int _BITWIDTH_READY_PRM                  = _BITWIDTH_STRUCT_INST_STATE_ENTRIES+_BITWIDTH_STRUCT_PHYREGS,
    localparam int _BITWIDTH_FLOW_WINDOWS_PC            = _BITWIDTH_STRUCT_FLOW_WINDOWS
                                                         + IS_INST_PC_BITWIDTH,
    localparam int _BITWIDTH_INTERNAL_INST_WIDTH        = _BITWIDTH_STRUCT_FLOW_WINDOWS
                                                         + IS_INST_PC_BITWIDTH
                                                         + _BITWIDTH_STRUCT_EX_PATH
                                                         + EX_INST_MICROOP_BITWIDTH
                                                         + IS_INST_IMM
                                                         + _BITWIDTH_STRUCT_PHYREGS // rd
                                                         + (_BITWIDTH_STRUCT_PHYREGS * IS_INST_OPERANDS) // rs1..n
                                                         + IS_INST_OPERANDS, // Ready1..n
    localparam int _BITWIDTH_EX_INST_WIDTH              = _BITWIDTH_STRUCT_FLOW_WINDOWS
                                                         + IS_INST_PC_BITWIDTH
                                                         + _BITWIDTH_STRUCT_EX_PATH
                                                         + EX_INST_MICROOP_BITWIDTH
                                                         + IS_INST_IMM
                                                         + _BITWIDTH_STRUCT_PHYREGS // rd
                                                         + (_BITWIDTH_STRUCT_PHYREGS * IS_INST_OPERANDS), // rs1..n
    localparam int _BITWIDTH_EX_RESULT_WIDTH            = _BITWIDTH_STRUCT_FLOW_WINDOWS
                                                         + IS_INST_PC_BITWIDTH
                                                         + _BITWIDTH_STRUCT_PHYREGS, // rd
    localparam int _BITWIDTH_STRUCT_RETIRED_PHYREG_MSG  = _BITWIDTH_STRUCT_FLOW_WINDOWS
                                                         + IS_INST_PC_BITWIDTH
                                                         + _BITWIDTH_STRUCT_PHYREGS, // Retired Register
    localparam int _BITWIDTH_STRUCT_JUMP_BRANCH_INFO    = 1 // Jump Register Flag
                                                         + 1 // Branch Flag
                                                         + IS_INST_PC_BITWIDTH, // New Program Counter
    localparam int _BITWIDTH_STRUCT_EX_DONE_PC          = _BITWIDTH_STRUCT_FLOW_WINDOWS
                                                         + IS_INST_PC_BITWIDTH
) (
    input  wire                                                                        clk,
    input  wire                                                                        reset_n,
    // Physical allocation belongs to the recoverable rename map.
    input wire [STRUCT_DECODE_NEW_INST-1:0] i_external_allocate_valid,
    input wire [STRUCT_DECODE_NEW_INST*$clog2(STRUCT_PHYREGS)-1:0] i_external_allocate_data,

    // Wait Physical Registers Input (IST)
    input  wire [(STRUCT_DECODE_NEW_INST*IS_INST_OPERANDS)-1:0]                        i_ist_wait_phyreg_valid,
    input  wire [(STRUCT_DECODE_NEW_INST*IS_INST_OPERANDS*(_BITWIDTH_READY_PRM) )-1:0] i_ist_wait_phyreg_data,

    // Broadcast Done phyreg Input (WBC)
    input  wire [STRUCT_EX_OUT_RESULT_SUM-1:0]                                         i_wbc_done_phyreg_valid,
    input  wire [(STRUCT_EX_OUT_RESULT_SUM *(_BITWIDTH_STRUCT_PHYREGS) )-1:0]          i_wbc_done_phyreg_data,

    // Unallocate Retired Registers Input (FCL)
    input  wire [STRUCT_UNALLOCATE_PHYREG-1:0]                                         i_fcl_unallocate_phyreg_valid,
    input  wire [(STRUCT_UNALLOCATE_PHYREG *(_BITWIDTH_STRUCT_PHYREGS) )-1:0]          i_fcl_unallocate_phyreg_data,

    // Allocate Physical Registers Output (NEL)
    output wire [STRUCT_DECODE_NEW_INST-1:0]                                           o_nel_phyreg_valid,
    input  wire [STRUCT_DECODE_NEW_INST-1:0]                                           i_nel_phyreg_get,
    output wire [(STRUCT_DECODE_NEW_INST *(_BITWIDTH_STRUCT_PHYREGS) )-1:0]            o_nel_phyreg_data,

    // Ready Physical Registers Output (IST)
    output wire [STRUCT_PRM_ENTRY_UPDATE-1:0]                                          o_ist_ready_phyreg_valid,
    output logic [(STRUCT_PRM_ENTRY_UPDATE*(_BITWIDTH_READY_PRM) )-1:0]                o_ist_ready_phyreg_data
);

    // Parameters require positive channel/buffer sizes and STRUCT_PHYREGS >= 2.
    localparam int WAIT_INPUTS                     = STRUCT_DECODE_NEW_INST*IS_INST_OPERANDS;
    // Keep one slot reserved for the already-renamed NEL Stage 2 bundle.
    // Three slots allow one bundle/cycle with occupancy-only admission;
    // a two-slot override is safe but can insert admission bubbles.
    // Deeper upstream pipelines require a larger buffer / reservation policy.
    localparam int INPUT_BUFFER_ENTRIES            = (STRUCT_PRM_INPUT_BUFFER_DEPTH < 2)? 2 : STRUCT_PRM_INPUT_BUFFER_DEPTH;
    localparam int _BITWIDTH_INPUT_BUNDLE           = WAIT_INPUTS*(_BITWIDTH_READY_PRM+1);
    localparam int _BITWIDTH_INPUT_BUFFER_ADDR      = $clog2(INPUT_BUFFER_ENTRIES);
    localparam int _BITWIDTH_INPUT_BUFFER_COUNT     = $clog2(INPUT_BUFFER_ENTRIES+1);
    localparam int PREFIX_WIDTH                    = $clog2(WAIT_INPUTS+1);
    localparam int COUNTER_CHANNELS                = WAIT_INPUTS+1;
    localparam int OUTPUT_PUSH_CHANNELS            = STRUCT_PRM_ENTRY_BUFFER+WAIT_INPUTS;
    localparam int OUTPUT_FIFO_ENTRIES             = (STRUCT_PRM_OUTPUT_FIFO_DEPTH < OUTPUT_PUSH_CHANNELS)?
                                                        OUTPUT_PUSH_CHANNELS : STRUCT_PRM_OUTPUT_FIFO_DEPTH;
    localparam int _BITWIDTH_STRUCT_PRM_ENTRY_BUFFER = $clog2(STRUCT_PRM_ENTRY_BUFFER+1);
    // Four adjacent PHYREGs form a leaf. Merge only the first return-width
    // candidates at each level; pad the last group / tree with empty leaves.
    localparam int RETURN_GROUP_SIZE               = 4;
    localparam int RETURN_GROUPS                   = (STRUCT_PHYREGS+RETURN_GROUP_SIZE-1)/RETURN_GROUP_SIZE;
    localparam int RETURN_LEAVES                   = 1 << $clog2(RETURN_GROUPS);
    localparam int RETURN_COUNT_WIDTH              = $clog2(STRUCT_UNALLOCATE_PHYREG+1);

    logic [_BITWIDTH_READY_PRM-1:0]                 wait_input_list       [0:WAIT_INPUTS-1];
    logic [_BITWIDTH_STRUCT_PHYREGS-1:0]            wait_input_phyreg     [0:WAIT_INPUTS-1];
    logic [_BITWIDTH_STRUCT_INST_STATE_ENTRIES-1:0] wait_input_istentry   [0:WAIT_INPUTS-1];
    logic [WAIT_INPUTS-1:0]                         wait_input_valid;
    logic [WAIT_INPUTS-1:0]                         wait_ready_valid;
    logic [PREFIX_WIDTH-1:0]                       wait_prefix_count     [0:WAIT_INPUTS-1];
    logic [WAIT_INPUTS-1:0]                         wait_suffix_valid;

    // Capture the complete IST input (Valid + Data) before mapping it.
    // If any unfinished PHYREG would overflow, retain the entire head bundle.
    // New physical-register offers stop; WBC and already-renamed IST inputs continue.
    logic [_BITWIDTH_INPUT_BUFFER_ADDR-1:0]        input_read_ptr, input_read_ptr_next;
    logic [_BITWIDTH_INPUT_BUFFER_ADDR-1:0]        input_write_ptr, input_write_ptr_next;
    logic [_BITWIDTH_INPUT_BUFFER_COUNT-1:0]       input_count, input_count_next;
    wire  [_BITWIDTH_INPUT_BUNDLE-1:0]             input_buffer_read_data;
    wire  [_BITWIDTH_INPUT_BUNDLE-1:0]             input_buffer_write_data;
    logic                                         input_push, input_pop, input_fire, input_stall;

    // Preprocess -> reserve -> commit. The wide request payload stays in
    // map_data until commit; only a narrow write plan crosses the new stage.
    logic                                         map_stage_valid;
    logic [WAIT_INPUTS-1:0]                        prepare_valid, map_valid;
    logic [WAIT_INPUTS*_BITWIDTH_READY_PRM-1:0]     map_data;
    logic [PREFIX_WIDTH-1:0]                       prepare_prefix [0:WAIT_INPUTS-1];
    logic [WAIT_INPUTS-1:0]                        prepare_suffix;
    logic                                         input_map_fit;
    localparam int PLAN_SUM_WIDTH = ((_BITWIDTH_STRUCT_PRM_ENTRY_BUFFER > PREFIX_WIDTH)?
                                     _BITWIDTH_STRUCT_PRM_ENTRY_BUFFER : PREFIX_WIDTH)+1;
    logic                                         plan_valid, plan_capture;
    logic [WAIT_INPUTS-1:0]                        plan_ready_valid;
    logic [WAIT_INPUTS-1:0]                        prepare_map_write [0:STRUCT_PRM_ENTRY_BUFFER-1];
    logic [WAIT_INPUTS-1:0]                        plan_map_write [0:STRUCT_PRM_ENTRY_BUFFER-1];
    logic [WAIT_INPUTS-1:0]                        prepare_counter_valid, plan_counter_valid;
    logic [WAIT_INPUTS*_BITWIDTH_STRUCT_PRM_ENTRY_BUFFER-1:0] prepare_counter_data, plan_counter_data;

    // Ready remains set until allocation of a new lifetime, so a one-cycle WBC
    // pulse is not lost while the output FIFO is full or an input bundle is held.
    logic [STRUCT_PHYREGS-1:0]                      phyreg_ready, phyreg_ready_next;
    logic [STRUCT_PHYREGS-1:0]                      mapping_active, mapping_active_next;
    logic [STRUCT_PHYREGS-1:0]                      retired_pending, retired_pending_next;

    logic [_BITWIDTH_STRUCT_PHYREGS-1:0]            drain_start, drain_start_next;
    logic [_BITWIDTH_STRUCT_PHYREGS-1:0]            drain_phyreg;
    logic                                         drain_valid, drain_fire;
    // One reserved completed row. Selection never depends on counter reads or
    // FIFO readiness; the registered identity is retained through backpressure.
    localparam int DRAIN_LEAVES = 1 << $clog2(STRUCT_PHYREGS);
    logic [STRUCT_PHYREGS-1:0]                      drain_candidates, drain_masked;
    logic [_BITWIDTH_STRUCT_PHYREGS:0]             drain_first, drain_after_start;
    logic [_BITWIDTH_STRUCT_PHYREGS-1:0]           drain_select_phyreg;
    logic                                         drain_select_valid;

    // Counter port 0 drains a completed row; ports 1..WAIT_INPUTS append requests.
    logic [(COUNTER_CHANNELS*_BITWIDTH_STRUCT_PHYREGS)-1:0] counter_addr;
    logic [(COUNTER_CHANNELS*_BITWIDTH_STRUCT_PRM_ENTRY_BUFFER)-1:0] counter_read_data;
    logic [(COUNTER_CHANNELS*_BITWIDTH_STRUCT_PRM_ENTRY_BUFFER)-1:0] counter_write_data;
    logic [COUNTER_CHANNELS-1:0]                    counter_write_valid;
    logic [(WAIT_INPUTS*_BITWIDTH_STRUCT_PHYREGS)-1:0] mapping_write_addr;
    logic [(WAIT_INPUTS*_BITWIDTH_STRUCT_INST_STATE_ENTRIES)-1:0] mapping_write_data;
    logic [WAIT_INPUTS-1:0]                         mapping_write_valid   [0:STRUCT_PRM_ENTRY_BUFFER-1];
    wire  [_BITWIDTH_STRUCT_INST_STATE_ENTRIES-1:0] mapping_read_data     [0:STRUCT_PRM_ENTRY_BUFFER-1];

    // Fixed input lanes: completed row first, then ready requests from the head.
    // The common FIFO owns compaction, storage, occupancy and output delivery.
    logic [OUTPUT_PUSH_CHANNELS-1:0]                output_push_valid;
    wire  [OUTPUT_PUSH_CHANNELS-1:0]                output_push_ready;
    // Elastic notification bundle: ownership moves here when map counters are
    // cleared. FIFO stalls cannot lose the list or repeat the map commit.
    logic [OUTPUT_PUSH_CHANNELS-1:0]                notify_valid;
    logic [(OUTPUT_PUSH_CHANNELS*_BITWIDTH_READY_PRM)-1:0] notify_data;
    wire                                          notify_accept = !(|notify_valid) || (&output_push_ready);
    logic [(OUTPUT_PUSH_CHANNELS*_BITWIDTH_READY_PRM)-1:0] output_push_data;
    wire  [STRUCT_PRM_ENTRY_UPDATE-1:0]             output_valid;
    wire  [(STRUCT_PRM_ENTRY_UPDATE*_BITWIDTH_READY_PRM)-1:0] output_data;

    wire  [STRUCT_DECODE_NEW_INST-1:0]              allocate_valid;
    wire  [(STRUCT_DECODE_NEW_INST*_BITWIDTH_STRUCT_PHYREGS)-1:0] allocate_data;
    wire  [STRUCT_DECODE_NEW_INST-1:0]              allocate_fire;
    logic [STRUCT_UNALLOCATE_PHYREG-1:0]            unallocate_valid;
    wire  [STRUCT_UNALLOCATE_PHYREG-1:0]            unallocate_ready;
    logic [(STRUCT_UNALLOCATE_PHYREG*_BITWIDTH_STRUCT_PHYREGS)-1:0] unallocate_data;
    logic [RETURN_COUNT_WIDTH-1:0]                 return_tree_count [0:2*RETURN_LEAVES-1];
    logic [_BITWIDTH_STRUCT_PHYREGS-1:0]           return_tree_data  [0:2*RETURN_LEAVES-1][0:STRUCT_UNALLOCATE_PHYREG-1];
    logic [RETURN_COUNT_WIDTH:0]                   return_merge_count;

    assign o_nel_phyreg_valid         = allocate_valid & {STRUCT_DECODE_NEW_INST{~input_stall}};
    assign o_nel_phyreg_data          = allocate_data;
    assign allocate_fire             = i_nel_phyreg_get & o_nel_phyreg_valid;
    assign o_ist_ready_phyreg_valid   = output_valid;
    assign o_ist_ready_phyreg_data    = output_data;
    assign input_buffer_write_data   = {i_ist_wait_phyreg_valid, i_ist_wait_phyreg_data};

    integer idx_address;
    integer idx_push;
    integer idx_wait, idx_slot, idx_done, idx_allocate, idx_retire;
    integer idx_return_node, idx_return_group, idx_return_slot, idx_return_lane, return_phyreg;
    integer drain_count;
    logic [_BITWIDTH_STRUCT_PHYREGS-1:0] target_phyreg;

    // Stage 1: deduplicate and count same-PHYREG requests, independently of
    // completion state. All requests for a PHYREG see the same live Ready bit
    // in stage 2, so their prefix/suffix remain valid even if WBC arrives later.
    always_comb begin
        prepare_valid = input_buffer_read_data[WAIT_INPUTS*_BITWIDTH_READY_PRM +: WAIT_INPUTS];
        prepare_suffix = '0;
        for (int lane = 0; lane < WAIT_INPUTS; lane++) begin
            for (int prev = 0; prev < lane; prev++) begin
                if (input_buffer_read_data[WAIT_INPUTS*_BITWIDTH_READY_PRM+prev] &&
                    input_buffer_read_data[prev*_BITWIDTH_READY_PRM +: _BITWIDTH_READY_PRM] ==
                    input_buffer_read_data[lane*_BITWIDTH_READY_PRM +: _BITWIDTH_READY_PRM])
                    prepare_valid[lane] = 1'b0;
            end
        end
        for (int lane = 0; lane < WAIT_INPUTS; lane++) begin
            prepare_prefix[lane] = '0;
            for (int other = 0; other < WAIT_INPUTS; other++) begin
                if (prepare_valid[lane] && prepare_valid[other] &&
                    input_buffer_read_data[lane*_BITWIDTH_READY_PRM +: _BITWIDTH_STRUCT_PHYREGS] ==
                    input_buffer_read_data[other*_BITWIDTH_READY_PRM +: _BITWIDTH_STRUCT_PHYREGS]) begin
                    if (other < lane) prepare_prefix[lane] = prepare_prefix[lane]+1'b1;
                    if (other > lane) prepare_suffix[lane] = 1'b1;
                end
            end
        end
    end

    // Balanced fixed-index priority encoders avoid a variable-index circular
    // scan. Prefer candidates >= the cursor, otherwise wrap to the first row.
    function automatic [_BITWIDTH_STRUCT_PHYREGS:0] first_drain(
        input logic [STRUCT_PHYREGS-1:0] candidates
    );
        logic [_BITWIDTH_STRUCT_PHYREGS:0] tree [0:2*DRAIN_LEAVES-1];
        for (int leaf = 0; leaf < DRAIN_LEAVES; leaf++) begin
            tree[DRAIN_LEAVES+leaf] = '0;
            if (leaf < STRUCT_PHYREGS)
                tree[DRAIN_LEAVES+leaf] = {candidates[leaf], _BITWIDTH_STRUCT_PHYREGS'(leaf)};
        end
        for (int node = DRAIN_LEAVES-1; node > 0; node--)
            tree[node] = tree[2*node][_BITWIDTH_STRUCT_PHYREGS] ? tree[2*node] : tree[2*node+1];
        first_drain = tree[1];
    endfunction

    always_comb begin
        for (int row = 0; row < STRUCT_PHYREGS; row++) begin
            // Exclude the reserved row even on its commit cycle. Its active bit
            // is cleared on that edge; a replacement must be a different row.
            drain_candidates[row] = phyreg_ready[row] && mapping_active[row] &&
                                    !(drain_valid && drain_phyreg == _BITWIDTH_STRUCT_PHYREGS'(row));
            drain_masked[row] = drain_candidates[row] && (_BITWIDTH_STRUCT_PHYREGS'(row) >= drain_start);
        end
        drain_first = first_drain(drain_candidates);
        drain_after_start = first_drain(drain_masked);
        drain_select_valid = drain_first[_BITWIDTH_STRUCT_PHYREGS];
        drain_select_phyreg = drain_after_start[_BITWIDTH_STRUCT_PHYREGS] ?
                              drain_after_start[0 +: _BITWIDTH_STRUCT_PHYREGS] :
                              drain_first[0 +: _BITWIDTH_STRUCT_PHYREGS];
    end

    always_comb begin
        // Stage 2: read live Ready/occupancy to prepare a reservation. Once
        // reserved, this classification stays fixed through the commit edge.
        wait_input_valid = map_valid & {WAIT_INPUTS{reset_n && map_stage_valid}};
        wait_ready_valid = 0;
        for (int idx_input = 0; idx_input < WAIT_INPUTS; idx_input = idx_input+1) begin
            wait_input_list[idx_input] = map_data[(_BITWIDTH_READY_PRM*idx_input) +: _BITWIDTH_READY_PRM];
            wait_input_phyreg[idx_input] = wait_input_list[idx_input][0 +: _BITWIDTH_STRUCT_PHYREGS];
            wait_input_istentry[idx_input] = wait_input_list[idx_input][_BITWIDTH_STRUCT_PHYREGS +: _BITWIDTH_STRUCT_INST_STATE_ENTRIES];
            wait_ready_valid[idx_input] = wait_input_valid[idx_input] && phyreg_ready[wait_input_phyreg[idx_input]];
        end

        // Mapping Counter / Map Addresses
        counter_addr = 0;
        counter_addr[0 +: _BITWIDTH_STRUCT_PHYREGS] = drain_phyreg;
        mapping_write_addr = 0;
        mapping_write_data = 0;
        for (idx_address = 0; idx_address < WAIT_INPUTS; idx_address = idx_address+1) begin
            counter_addr[(_BITWIDTH_STRUCT_PHYREGS*(idx_address+1)) +: _BITWIDTH_STRUCT_PHYREGS] = wait_input_phyreg[idx_address];
            mapping_write_addr[(_BITWIDTH_STRUCT_PHYREGS*idx_address) +: _BITWIDTH_STRUCT_PHYREGS] = wait_input_phyreg[idx_address];
            mapping_write_data[(_BITWIDTH_STRUCT_INST_STATE_ENTRIES*idx_address) +: _BITWIDTH_STRUCT_INST_STATE_ENTRIES] = wait_input_istentry[idx_address];
        end

    end

    always_comb begin
        logic [PLAN_SUM_WIDTH-1:0] total;
        // Plan exact write enables and final row counts before changing state.
        total='0; input_map_fit=1'b1;
        prepare_counter_valid='0; prepare_counter_data='0;
        for(int slot=0;slot<STRUCT_PRM_ENTRY_BUFFER;slot++) prepare_map_write[slot]='0;
        for(int lane=0;lane<WAIT_INPUTS;lane++) begin
            total=PLAN_SUM_WIDTH'(counter_read_data[(_BITWIDTH_STRUCT_PRM_ENTRY_BUFFER*(lane+1)) +: _BITWIDTH_STRUCT_PRM_ENTRY_BUFFER])
                  +PLAN_SUM_WIDTH'(wait_prefix_count[lane])+PLAN_SUM_WIDTH'(1);
            if(wait_input_valid[lane] && !wait_ready_valid[lane]) begin
                if(total>PLAN_SUM_WIDTH'(STRUCT_PRM_ENTRY_BUFFER)) input_map_fit=0;
                for(int slot=0;slot<STRUCT_PRM_ENTRY_BUFFER;slot++)
                    prepare_map_write[slot][lane]=(total==PLAN_SUM_WIDTH'(slot+1));
                prepare_counter_valid[lane]=!wait_suffix_valid[lane];
                prepare_counter_data[lane*_BITWIDTH_STRUCT_PRM_ENTRY_BUFFER +: _BITWIDTH_STRUCT_PRM_ENTRY_BUFFER]=
                    _BITWIDTH_STRUCT_PRM_ENTRY_BUFFER'(total);
            end
        end
        plan_capture=reset_n && map_stage_valid && !plan_valid && input_map_fit;
    end

    always_comb begin
        // Completed Map and Ready Input Requests -> Output FIFO
        // Ready reserves the entire input width, so a row is accepted atomically.
        // Buffered requests that completed while waiting bypass the map. Sparse
        // lanes are left in place; compaction happens inside the common FIFO.
        output_push_valid = 0;
        output_push_data = 0;
        drain_count = 0;
        if (drain_valid) drain_count = int'(counter_read_data[0 +: _BITWIDTH_STRUCT_PRM_ENTRY_BUFFER]);
        // A pending plan owns the table until commit. A drain on the plan's
        // capture edge cannot touch its unready rows; later drains wait. WBC
        // still updates sticky Ready, so rows completed here drain afterward.
        drain_fire = reset_n && !plan_valid && drain_valid && (drain_count != 0) && notify_accept;
        // Only registered occupancy gates commit; FIFO ready cannot reach map
        // write enables. Ready bypasses may wait until the notification buffer
        // is empty, while already-buffered notifications continue to drain.
        input_fire = reset_n && plan_valid && (!(|plan_ready_valid) || !(|notify_valid));

        if (drain_fire) begin
            for (idx_push = 0; idx_push < STRUCT_PRM_ENTRY_BUFFER; idx_push = idx_push+1) begin
                if (idx_push < drain_count) begin
                    output_push_valid[idx_push] = 1'b1;
                    output_push_data[(_BITWIDTH_READY_PRM*idx_push) +: _BITWIDTH_READY_PRM] =
                        {mapping_read_data[idx_push], drain_phyreg};
                end
            end
        end
        if (input_fire) begin
            for (idx_push = 0; idx_push < WAIT_INPUTS; idx_push = idx_push+1) begin
                if (plan_ready_valid[idx_push]) begin
                    output_push_valid[STRUCT_PRM_ENTRY_BUFFER+idx_push] = 1'b1;
                    output_push_data[(_BITWIDTH_READY_PRM*(STRUCT_PRM_ENTRY_BUFFER+idx_push)) +: _BITWIDTH_READY_PRM] =
                        wait_input_list[idx_push];
                end
            end
        end

        // Stop upstream from REGISTERED occupancy only: no commit / output
        // FIFO ready path may propagate combinationally into NEL admission.
        // Reserve one slot for the already-renamed NEL Stage 2 bundle. The
        // current IST push can consume the last unreserved slot on this edge.
        input_stall = !reset_n || (input_count >= _BITWIDTH_INPUT_BUFFER_COUNT'(INPUT_BUFFER_ENTRIES-1));
        input_pop = reset_n && (input_count != 0) && (!map_stage_valid || input_fire);
        input_push = reset_n && (|i_ist_wait_phyreg_valid) &&
                     ((input_count < _BITWIDTH_INPUT_BUFFER_COUNT'(INPUT_BUFFER_ENTRIES)) || input_pop);
        input_read_ptr_next = input_read_ptr;
        input_write_ptr_next = input_write_ptr;
        input_count_next = _BITWIDTH_INPUT_BUFFER_COUNT'(int'(input_count)+(input_push? 1 : 0)-(input_pop? 1 : 0));
        if (input_pop) input_read_ptr_next = _BITWIDTH_INPUT_BUFFER_ADDR'((int'(input_read_ptr)+1)%INPUT_BUFFER_ENTRIES);
        if (input_push) input_write_ptr_next = _BITWIDTH_INPUT_BUFFER_ADDR'((int'(input_write_ptr)+1)%INPUT_BUFFER_ENTRIES);

        // Mapping Updates and Next State
        phyreg_ready_next = phyreg_ready;
        mapping_active_next = mapping_active;
        retired_pending_next = retired_pending;
        drain_start_next = drain_start;
        counter_write_valid = 0;
        counter_write_data = 0;
        unallocate_valid = 0;
        unallocate_data = 0;
        target_phyreg = 0;
        for (idx_slot = 0; idx_slot < STRUCT_PRM_ENTRY_BUFFER; idx_slot = idx_slot+1)
            mapping_write_valid[idx_slot] = plan_map_write[idx_slot] & {WAIT_INPUTS{input_fire}};

        // Release a map only after its entire batch has secured notification buffer space.
        if (drain_fire) begin
            counter_write_valid[0] = 1'b1;
            mapping_active_next[drain_phyreg] = 1'b0;
        end

        // Advance fairness on reservation, not downstream acceptance. Holding
        // the current row excludes it from subsequent selections until commit.
        if ((!drain_valid || drain_fire) && drain_select_valid) begin
            if (drain_select_phyreg == STRUCT_PHYREGS-1) drain_start_next = 0;
            else drain_start_next = drain_select_phyreg+1'b1;
        end

        // Commit the saved plan without rereading capacity or reclassifying
        // Ready. A row that completed after reservation is still appended and
        // then drained using its sticky Ready bit, including all new waiters.
        for (idx_wait = 0; idx_wait < WAIT_INPUTS; idx_wait = idx_wait+1) begin
            counter_write_valid[idx_wait+1] = input_fire && plan_counter_valid[idx_wait];
            counter_write_data[(_BITWIDTH_STRUCT_PRM_ENTRY_BUFFER*(idx_wait+1)) +: _BITWIDTH_STRUCT_PRM_ENTRY_BUFFER] =
                plan_counter_data[(_BITWIDTH_STRUCT_PRM_ENTRY_BUFFER*idx_wait) +: _BITWIDTH_STRUCT_PRM_ENTRY_BUFFER];
            if (input_fire && wait_input_valid[idx_wait] && !plan_ready_valid[idx_wait]) begin
                target_phyreg = wait_input_phyreg[idx_wait];
                mapping_active_next[target_phyreg] = 1'b1;
            end
        end


        for (idx_allocate = 0; idx_allocate < STRUCT_DECODE_NEW_INST; idx_allocate = idx_allocate+1) begin
            if (allocate_fire[idx_allocate]) begin
                target_phyreg = allocate_data[(_BITWIDTH_STRUCT_PHYREGS*idx_allocate) +: _BITWIDTH_STRUCT_PHYREGS];
                phyreg_ready_next[target_phyreg] = 1'b0;
            end
        end
        for (idx_done = 0; idx_done < STRUCT_EX_OUT_RESULT_SUM; idx_done = idx_done+1) begin
            if (i_wbc_done_phyreg_valid[idx_done]) begin
                target_phyreg = i_wbc_done_phyreg_data[(_BITWIDTH_STRUCT_PHYREGS*idx_done) +: _BITWIDTH_STRUCT_PHYREGS];
                phyreg_ready_next[target_phyreg] = 1'b1;
            end
        end
        phyreg_ready_next[0] = 1'b1;

        // FCL returns only after all readers in this and older windows complete.
        // No per-PHYREG notification counter is needed under that contract.
        // Its Valid-only return pulse is still retained until the allocator accepts.
        for (idx_retire = 0; idx_retire < STRUCT_UNALLOCATE_PHYREG; idx_retire = idx_retire+1) begin
            if (i_fcl_unallocate_phyreg_valid[idx_retire]) begin
                target_phyreg = i_fcl_unallocate_phyreg_data[(_BITWIDTH_STRUCT_PHYREGS*idx_retire) +: _BITWIDTH_STRUCT_PHYREGS];
                if (target_phyreg != 0) retired_pending_next[target_phyreg] = 1'b1;
            end
        end
        // Parallel local selection, then balanced merges. No count passes
        // serially through all PHYREGs. Lower PHYREG numbers still go first.
        return_phyreg = 0;
        return_merge_count = 0;
        for (idx_return_node = 0; idx_return_node < 2*RETURN_LEAVES; idx_return_node = idx_return_node+1) begin
            return_tree_count[idx_return_node] = 0;
            for (idx_return_lane = 0; idx_return_lane < STRUCT_UNALLOCATE_PHYREG; idx_return_lane = idx_return_lane+1)
                return_tree_data[idx_return_node][idx_return_lane] = 0;
        end
        for (idx_return_group = 0; idx_return_group < RETURN_GROUPS; idx_return_group = idx_return_group+1) begin
            for (idx_return_slot = 0; idx_return_slot < RETURN_GROUP_SIZE; idx_return_slot = idx_return_slot+1) begin
                return_phyreg = idx_return_group*RETURN_GROUP_SIZE+idx_return_slot;
                if ((return_phyreg > 0) && (return_phyreg < STRUCT_PHYREGS)) begin
                    if (retired_pending[return_phyreg] &&
                        (return_tree_count[RETURN_LEAVES+idx_return_group] < STRUCT_UNALLOCATE_PHYREG)) begin
                        return_tree_data[RETURN_LEAVES+idx_return_group][return_tree_count[RETURN_LEAVES+idx_return_group]] =
                            _BITWIDTH_STRUCT_PHYREGS'(return_phyreg);
                        return_tree_count[RETURN_LEAVES+idx_return_group] = return_tree_count[RETURN_LEAVES+idx_return_group]+1'b1;
                    end
                end
            end
        end
        for (idx_return_node = RETURN_LEAVES-1; idx_return_node > 0; idx_return_node = idx_return_node-1) begin
            return_merge_count = {1'b0, return_tree_count[2*idx_return_node]} +
                                 {1'b0, return_tree_count[2*idx_return_node+1]};
            if (return_merge_count > STRUCT_UNALLOCATE_PHYREG)
                return_tree_count[idx_return_node] = RETURN_COUNT_WIDTH'(STRUCT_UNALLOCATE_PHYREG);
            else return_tree_count[idx_return_node] = RETURN_COUNT_WIDTH'(return_merge_count);
            for (idx_return_lane = 0; idx_return_lane < STRUCT_UNALLOCATE_PHYREG; idx_return_lane = idx_return_lane+1) begin
                if (idx_return_lane < return_tree_count[idx_return_node]) begin
                    if (idx_return_lane < return_tree_count[2*idx_return_node])
                        return_tree_data[idx_return_node][idx_return_lane] = return_tree_data[2*idx_return_node][idx_return_lane];
                    else return_tree_data[idx_return_node][idx_return_lane] =
                        return_tree_data[2*idx_return_node+1][RETURN_COUNT_WIDTH'(idx_return_lane)-return_tree_count[2*idx_return_node]];
                end
            end
        end
        for (idx_return_lane = 0; idx_return_lane < STRUCT_UNALLOCATE_PHYREG; idx_return_lane = idx_return_lane+1) begin
            if (idx_return_lane < return_tree_count[1]) begin
                unallocate_valid[idx_return_lane] = reset_n;
                unallocate_data[(_BITWIDTH_STRUCT_PHYREGS*idx_return_lane) +: _BITWIDTH_STRUCT_PHYREGS] = return_tree_data[1][idx_return_lane];
                if (reset_n && unallocate_ready[idx_return_lane])
                    retired_pending_next[return_tree_data[1][idx_return_lane]] = 1'b0;
            end
        end
    end

    // synthesis translate_off
    always @(posedge clk) if(reset_n) begin
        if(plan_valid) begin
            assert(map_stage_valid) else $fatal(1,"PRM plan lost its payload");
            for(int lane=0;lane<WAIT_INPUTS;lane++) begin
                if(plan_counter_valid[lane]) begin
                    assert(int'(plan_counter_data[lane*_BITWIDTH_STRUCT_PRM_ENTRY_BUFFER +: _BITWIDTH_STRUCT_PRM_ENTRY_BUFFER]) ==
                           int'(counter_read_data[(lane+1)*_BITWIDTH_STRUCT_PRM_ENTRY_BUFFER +: _BITWIDTH_STRUCT_PRM_ENTRY_BUFFER])+
                           int'(wait_prefix_count[lane])+1)
                        else $fatal(1,"PRM reserved row changed before commit");
                    assert(int'(plan_counter_data[lane*_BITWIDTH_STRUCT_PRM_ENTRY_BUFFER +: _BITWIDTH_STRUCT_PRM_ENTRY_BUFFER])<=STRUCT_PRM_ENTRY_BUFFER)
                        else $fatal(1,"PRM reservation exceeds row capacity");
                end
            end
        end
        if(plan_capture && drain_fire) for(int lane=0;lane<WAIT_INPUTS;lane++)
            if(wait_input_valid[lane] && !wait_ready_valid[lane])
                assert(wait_input_phyreg[lane]!=drain_phyreg)
                    else $fatal(1,"PRM reservation collided with a retiring row");
    end
    // synthesis translate_on
    // Payload validity is plan_valid; no wide reset tree is needed for the plan.
    always_ff @(posedge clk) if(plan_capture) begin
        plan_ready_valid<=wait_ready_valid;
        plan_counter_valid<=prepare_counter_valid;
        plan_counter_data<=prepare_counter_data;
        for(int slot=0;slot<STRUCT_PRM_ENTRY_BUFFER;slot++) plan_map_write[slot]<=prepare_map_write[slot];
    end
    always_ff @(posedge clk or negedge reset_n) begin
        if (~reset_n) begin
            input_read_ptr <= 0;
            input_write_ptr <= 0;
            input_count <= 0;
            map_stage_valid <= 0;
            plan_valid <= 0;
            map_valid <= 0;
            map_data <= 0;
            wait_suffix_valid <= 0;
            for (int lane = 0; lane < WAIT_INPUTS; lane++) wait_prefix_count[lane] <= 0;
            phyreg_ready <= {{(STRUCT_PHYREGS-1){1'b0}}, 1'b1};
            mapping_active <= 0;
            retired_pending <= 0;
            drain_start <= 0;
            drain_valid <= 0;
            drain_phyreg <= 0;
            notify_valid <= 0;
            notify_data <= 0;
        end
        else begin
            if(plan_capture) plan_valid<=1;
            else if(input_fire) plan_valid<=0;
`ifndef SYNTHESIS
            // Valid-only input has no retry handshake. Reaching this condition
            // means the upstream stop / one-time admission contract was violated.
            if ((|i_ist_wait_phyreg_valid) && !input_push)
                $error("PRM input buffer overflow: NEL must stop on missing PHYREG offers and IST must send each admitted bundle once.");
`endif
            if (input_pop) begin
                map_stage_valid <= 1'b1;
                map_valid <= prepare_valid;
                map_data <= input_buffer_read_data[0 +: WAIT_INPUTS*_BITWIDTH_READY_PRM];
                wait_suffix_valid <= prepare_suffix;
                for (int lane = 0; lane < WAIT_INPUTS; lane++) wait_prefix_count[lane] <= prepare_prefix[lane];
            end
            else if (input_fire) map_stage_valid <= 1'b0;
            input_read_ptr <= input_read_ptr_next;
            input_write_ptr <= input_write_ptr_next;
            input_count <= input_count_next;
            phyreg_ready <= phyreg_ready_next;
            mapping_active <= mapping_active_next;
            retired_pending <= retired_pending_next;
            drain_start <= drain_start_next;
            if (!drain_valid || drain_fire) begin
                drain_valid <= drain_select_valid;
                if (drain_select_valid) drain_phyreg <= drain_select_phyreg;
            end
            if (notify_accept) begin
                notify_valid <= output_push_valid;
                if (|output_push_valid) notify_data <= output_push_data;
            end
        end
    end

    regfile #(
        .DATA_WIDTH    (_BITWIDTH_INPUT_BUNDLE),
        .ENTRIES       (INPUT_BUFFER_ENTRIES),
        .READ_CHANNEL  (1),
        .WRITE_CHANNEL (1),
        .INITIAL_VALUE (0)
    ) U_PRM_INPUT_BUFFER (
        .clk           (clk),
        .reset_n       (reset_n),
        .i_flush       (1'b0),
        .i_read_addr   (input_read_ptr),
        .o_read_data   (input_buffer_read_data),
        .i_write_addr  (input_write_ptr),
        .i_write_en    (input_push),
        .i_write_data  (input_buffer_write_data)
    );

    assign allocate_valid = i_external_allocate_valid;
    assign allocate_data = i_external_allocate_data;
    assign unallocate_ready = '1;

    regfile #(
        .DATA_WIDTH    (_BITWIDTH_STRUCT_PRM_ENTRY_BUFFER),
        .ENTRIES       (STRUCT_PHYREGS),
        .READ_CHANNEL  (COUNTER_CHANNELS),
        .WRITE_CHANNEL (COUNTER_CHANNELS),
        .INITIAL_VALUE (0)
    ) U_PRM_MAPPING_COUNTER (
        .clk           (clk),
        .reset_n       (reset_n),
        .i_flush       (1'b0),
        .i_read_addr   (counter_addr),
        .o_read_data   (counter_read_data),
        .i_write_addr  (counter_addr),
        .i_write_en    (counter_write_valid),
        .i_write_data  (counter_write_data)
    );

    genvar mapping_idx;
    generate
        for (mapping_idx = 0; mapping_idx < STRUCT_PRM_ENTRY_BUFFER; mapping_idx = mapping_idx+1) begin : GEN_PRM_IST_MAP
            regfile #(
                .DATA_WIDTH    (_BITWIDTH_STRUCT_INST_STATE_ENTRIES),
                .ENTRIES       (STRUCT_PHYREGS),
                .READ_CHANNEL  (1),
                .WRITE_CHANNEL (WAIT_INPUTS),
                .INITIAL_VALUE (0)
            ) U_PRM_IST_MAP (
                .clk           (clk),
                .reset_n       (reset_n),
                .i_flush       (1'b0),
                .i_read_addr   (drain_phyreg),
                .o_read_data   (mapping_read_data[mapping_idx]),
                .i_write_addr  (mapping_write_addr),
                .i_write_en    (mapping_write_valid[mapping_idx]),
                .i_write_data  (mapping_write_data)
            );
        end

    endgenerate

    fifo_multichan #(
        .DATA_WIDTH    (_BITWIDTH_READY_PRM),
        .READ_CHANNEL  (STRUCT_PRM_ENTRY_UPDATE),
        .WRITE_CHANNEL (OUTPUT_PUSH_CHANNELS),
        .MIN_FIFO_ENTRY(OUTPUT_FIFO_ENTRIES),
        .USE_BRAM      (1'b1),
        .OPTIMIZED_INPUT_GATHER(1'b1)
    ) U_PRM_OUTPUT_FIFO (
        .clk           (clk),
        .reset_n       (reset_n),
        .i_flush       (1'b0),
        .i_push        (notify_valid & {OUTPUT_PUSH_CHANNELS{reset_n && (&output_push_ready)}}),
        .o_push_ready  (output_push_ready),
        .i_push_data   (notify_data),
        // IST merges same-entry notifications; every valid lane is consumed.
        .i_pop         (output_valid),
        .o_pop_valid   (output_valid),
        .o_pop_data    (output_data)
    );
endmodule
