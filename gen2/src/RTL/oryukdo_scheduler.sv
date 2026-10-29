`timescale 1ns/1ps
// Recoverable decoded-instruction top. EX/data RF, fetch/decode, MMU and CSR
// are external. Existing EULSUKDO IST / pipelined PRM / banked RS are reused.
module oryukdo_scheduler #(
    parameter int PC_W=32, DATA_W=32, IMM_W=32, UOP_W=5,
    parameter int ARCH=32, PHY=64, DECODE=2, ENTRIES=128,
    parameter int WINDOWS=8, WINDOW_SIZE=16, PC_STEP=4,
    parameter int PATHS=3, EX_LANES=5,
    parameter int PATH_LANES[PATHS]='{1,3,1},
    parameter int ISSUE=EX_LANES, UPDATES=EX_LANES, RS_DEPTH=128,
    parameter int GEN_W=32, EPOCH_W=32,
    parameter bit EXTERNAL_PREDICTOR=0,
    parameter bit CUSTOM_LSQ=0,
    localparam int SLOT_W=(ENTRIES>1)?$clog2(ENTRIES):1,
    localparam int TOKEN_W=SLOT_W+GEN_W,
    localparam int FLOW_W=(WINDOWS>1)?$clog2(WINDOWS):1,
    localparam int ARCH_W=$clog2(ARCH), PHY_W=$clog2(PHY), PATH_W=$clog2(PATHS),
    localparam int KEY_W=PC_W+TOKEN_W+FLOW_W,
    localparam int EX_W=KEY_W+PATH_W+UOP_W+IMM_W+3*PHY_W,
    localparam int RESULTS=EX_LANES+1,
    localparam int BYTES=DATA_W/8
) (
    input wire clk, reset_n,
    input wire [PC_W-1:0] i_reset_pc,
    output wire [PC_W-1:0] o_fetch_pc,
    output wire [EPOCH_W-1:0] o_fetch_epoch,
    input wire [EPOCH_W-1:0] i_decode_epoch,
    input wire [DECODE-1:0] i_decode_valid,
    output logic [DECODE-1:0] o_decode_get,
    input wire [DECODE*PC_W-1:0] i_decode_pc,
    input wire [DECODE*PATH_W-1:0] i_decode_path,
    input wire [DECODE*UOP_W-1:0] i_decode_uop,
    input wire [DECODE*IMM_W-1:0] i_decode_imm,
    input wire [DECODE*ARCH_W-1:0] i_decode_rd,
    input wire [DECODE*2*ARCH_W-1:0] i_decode_rs,
    input wire [DECODE-1:0] i_decode_write, i_decode_control, i_decode_memory,
    input wire [DECODE-1:0] i_decode_store, i_decode_csr, i_decode_end, i_decode_exception,
    input wire [DECODE*5-1:0] i_decode_cause,
    output wire o_predict_valid,
    output logic [PC_W-1:0] o_predict_pc,
    output wire [EPOCH_W-1:0] o_predict_epoch,
    input wire i_predict_valid,
    input wire [PC_W-1:0] i_predict_pc, i_predict_next,
    input wire [EPOCH_W-1:0] i_predict_epoch,
    output logic [EX_LANES-1:0] o_predict_update_valid,
    output logic [EX_LANES*PC_W-1:0] o_predict_update_pc,
    output logic [EX_LANES*PC_W-1:0] o_predict_update_next,
    output logic [EX_LANES-1:0] o_ex_valid,
    input wire [EX_LANES-1:0] i_ex_get,
    output logic [EX_LANES*EX_W-1:0] o_ex_data,
    output logic [EX_LANES*TOKEN_W-1:0] o_ex_token,
    output logic [EX_LANES-1:0] o_ex_memory, o_ex_store, o_ex_csr,
    input wire [EX_LANES-1:0] i_result_valid, i_result_fault,
    input wire [EX_LANES*TOKEN_W-1:0] i_result_token,
    input wire [EX_LANES*DATA_W-1:0] i_result_data,
    input wire [EX_LANES*PC_W-1:0] i_result_next,
    input wire [EX_LANES*5-1:0] i_result_cause,
    output wire [EX_LANES-1:0] o_result_accept,
    output logic [RESULTS-1:0] o_wb_valid,
    output logic [RESULTS*PHY_W-1:0] o_wb_phy,
    output logic [RESULTS*DATA_W-1:0] o_wb_data,
    output logic [RESULTS*UOP_W-1:0] o_wb_uop,
    input wire i_agu_valid,
    output wire o_agu_ready,
    input wire [TOKEN_W-1:0] i_agu_token,
    input wire [PC_W-1:0] i_agu_address,
    input wire [DATA_W-1:0] i_agu_data,
    input wire [BYTES-1:0] i_agu_mask,
    input wire i_agu_nonspec, i_agu_fault,
    input wire [4:0] i_agu_cause,
    output wire o_mem_valid,
    input wire i_mem_ready,
    output wire o_mem_store,
    output wire [PC_W-1:0] o_mem_address,
    output wire [DATA_W-1:0] o_mem_data,
    output wire [BYTES-1:0] o_mem_mask,
    input wire i_mem_response_valid,
    output wire o_mem_response_ready,
    input wire [DATA_W-1:0] i_mem_response_data,
    input wire i_mem_response_fault,
    input wire [4:0] i_mem_response_cause,
    input wire i_interrupt,
    input wire [PC_W-1:0] i_trap_vector,
    output wire o_flush, o_trap, o_trap_interrupt,
    output wire [PC_W-1:0] o_redirect_pc, o_trap_pc,
    output wire [4:0] o_trap_cause,
    output wire o_window_boundary, o_exception_pending,
    output wire o_retire,
    output wire [TOKEN_W-1:0] o_retire_token
);
    localparam int INT_W=EX_W+2;
    localparam int BANKS=2, SOURCE_W=$clog2(RESULTS);
    localparam int READY_W=SLOT_W+PHY_W;
    localparam int CHANNELS=DECODE+ISSUE;
    wire backend_reset_n;
    // RF writes happen on o_wb_*; internal readiness follows one cycle later.
    // Both NEL and PRM see the same registered pulse, including late waiters.
    logic [BANKS-1:0] wake_valid;
    logic [BANKS*PHY_W-1:0] wake_phy;
    wire [RESULTS-1:0] ready_valid={{(RESULTS-BANKS){1'b0}},wake_valid} & {RESULTS{backend_reset_n}};
    wire [RESULTS*PHY_W-1:0] ready_phy={{((RESULTS-BANKS)*PHY_W){1'b0}},wake_phy};
    logic [PC_W-1:0] fetch_pc;
    logic boot_pending;
    logic [EPOCH_W-1:0] epoch;
    logic [FLOW_W-1:0] flow;
    integer window_count;
    logic [DECODE-1:0] selected, ends, writes;
    // Decode validation and resource allocation are separate clock stages.
    // Only selected is validity; the payload remains stable until allocation.
    typedef struct packed {
        logic [DECODE*PC_W-1:0] pc, predicted;
        logic [DECODE*PATH_W-1:0] path;
        logic [DECODE*UOP_W-1:0] uop;
        logic [DECODE*IMM_W-1:0] imm;
        logic [DECODE*ARCH_W-1:0] rd;
        logic [DECODE*2*ARCH_W-1:0] rs;
        logic [DECODE-1:0] writes, control, memory_op, store, csr, end_window, exception;
        logic [DECODE*5-1:0] cause;
        logic [EPOCH_W-1:0] epoch;
    } decoded_t;
    decoded_t decoded;
    logic [DECODE-1:0] capture_selected, capture_writes;
    logic [DECODE*PC_W-1:0] capture_predicted;
    wire capture_ready;
    wire capture= capture_ready && (|capture_selected);
    logic [DECODE*PC_W-1:0] predicted;
    logic [DECODE*FLOW_W-1:0] flow_ids;
    logic [FLOW_W-1:0] next_flow;
    integer next_window_count;
    logic [PC_W-1:0] next_fetch, sequential_next;
    logic csr_pending;
    logic csr_barrier;
    logic [EX_W-1:0] csr_packet;
    logic [$clog2(EX_LANES)-1:0] csr_lane;
    logic has_control;
    wire prediction_ready;
    wire [PC_W-1:0] prediction_next;
    wire frontier_ready, rename_ready, initializing;
    wire lsq_allocate_ready;
    wire [$clog2(ENTRIES+1)-1:0] frontier_count;
    // Seal a partial window on resource pressure, so its retirement can free
    // slots/registers without requiring the very admission it is blocking.
    wire seal_window=reset_n && !initializing && !o_flush && window_count!=0 &&
        (((|selected) && (!rename_ready || !lsq_allocate_ready)) || int'(frontier_count)>ENTRIES-DECODE);
    wire [DECODE*TOKEN_W-1:0] allocated_tokens;
    wire [DECODE*PHY_W-1:0] rename_rd;
    wire [DECODE*2*PHY_W-1:0] rename_rs;
    wire [DECODE*2-1:0] rename_ready_bits;
    wire [DECODE-1:0] prm_alloc_valid;
    logic [DECODE-1:0] dispatch_valid;
    logic [DECODE*INT_W-1:0] dispatch_data;
    wire admit;
    logic fault_pending;
    wire frontier_stopped;
    wire [DECODE-1:0] allocate=selected & {DECODE{admit}};
    assign admit=reset_n && (|selected) && !o_flush && !csr_barrier && !fault_pending &&
               !(|dispatch_valid) && frontier_ready && rename_ready && lsq_allocate_ready &&
               (&prm_alloc_valid) && decoded.epoch==epoch;
    // No combinational bypass/refill: capture cannot reach token allocation.
    assign capture_ready=reset_n && !boot_pending && !initializing && !o_flush &&
        !(|selected) && !csr_barrier && !fault_pending && !i_interrupt &&
        prediction_ready && i_decode_epoch==epoch;
    wire [DECODE-1:0] ist_get;
    assign backend_reset_n=reset_n && !o_flush && !initializing;
    wire dispatch_fire=backend_reset_n && (&ist_get) && (|dispatch_valid);
    wire [CHANNELS-1:0] ist_valid, rs_get;
    wire [CHANNELS*EX_W-1:0] ist_data;
    wire [DECODE*2-1:0] wait_valid;
    wire [DECODE*2*READY_W-1:0] wait_data;
    wire [UPDATES-1:0] notify_valid;
    wire [UPDATES*READY_W-1:0] notify_data;
    wire [EX_LANES-1:0] rs_valid;
    wire [EX_LANES*EX_W-1:0] rs_data;
    logic [EX_LANES-1:0] rs_pop;
    typedef struct packed {
        logic valid, issued, queued, memory_op, store, csr, control;
        logic [GEN_W-1:0] generation;
        logic [UOP_W-1:0] uop;
        logic [PC_W-1:0] pc;
    } metadata_t;
    metadata_t metadata[ENTRIES];
    wire [BANKS-1:0] complete_valid, complete_fault, complete_accept;
    wire [BANKS*TOKEN_W-1:0] complete_token;
    wire [BANKS*5-1:0] complete_cause;
    wire [BANKS*PC_W-1:0] complete_next;
    wire [BANKS*PHY_W-1:0] complete_phy;
    wire [BANKS*DATA_W-1:0] complete_data;
    wire [BANKS*SOURCE_W-1:0] complete_source;
    wire [RESULTS-1:0] queue_ready;
    logic [RESULTS-1:0] queue_valid;
    logic [EX_LANES-1:0] result_eligible;
    wire [RESULTS*TOKEN_W-1:0] incoming_token;
    wire [RESULTS-1:0] incoming_fault;
    wire [RESULTS*5-1:0] incoming_cause;
    wire mem_completion_discard;
    wire head_valid, commit_valid, commit_ready, commit_store, commit_write;
    wire [TOKEN_W-1:0] head_token, commit_token;
    wire [ARCH_W-1:0] commit_arch;
    wire [PHY_W-1:0] commit_phy;
    wire mem_done_valid, mem_done_fault, mem_agu_ready, serial_valid, store_fault;
    wire [TOKEN_W-1:0] mem_done_token, serial_token, store_fault_token;
    wire [DATA_W-1:0] mem_done_data;
    wire [4:0] mem_done_cause, store_fault_cause;
    wire agu_fault_now=i_agu_valid && o_agu_ready && i_agu_fault;
    function automatic logic meta_live(input [TOKEN_W-1:0] token);
        if(int'(token[SLOT_W-1:0])>=ENTRIES) return 0;
        return metadata[token[SLOT_W-1:0]].valid &&
               metadata[token[SLOT_W-1:0]].generation==token[SLOT_W +: GEN_W];
    endfunction
    function automatic integer path_first_lane(input [PATH_W-1:0] path);
        integer lane_base;
        lane_base=0;
        for(integer p=0;p<PATHS;p++) if(p<int'(path)) lane_base+=PATH_LANES[p];
        return lane_base;
    endfunction
    assign o_fetch_pc=fetch_pc;
    assign o_fetch_epoch=epoch;
    assign o_predict_epoch=epoch;
    assign o_predict_valid=reset_n && !boot_pending && !initializing && !o_flush &&
        !(|selected) && !csr_barrier && !fault_pending && !i_interrupt && has_control && i_decode_epoch==epoch;
    generate if(EXTERNAL_PREDICTOR) begin: G_EXTERNAL_PREDICTOR
        assign prediction_ready=!has_control || (i_predict_valid && i_predict_pc==o_predict_pc && i_predict_epoch==epoch);
        assign prediction_next=i_predict_next;
    end else begin: G_STATIC_PREDICTOR
        assign prediction_ready=1'b1;
        assign prediction_next=o_predict_pc+PC_W'(PC_STEP);
    end endgenerate
    always_comb begin
        logic stop_prefix;
        logic [PC_W-1:0] expected;
        capture_selected='0; capture_writes='0;
        has_control=0; o_predict_pc='0; stop_prefix=0; expected=fetch_pc;
        sequential_next=fetch_pc;
        for(int lane=0;lane<DECODE;lane++) begin
            // Compute candidate PCs independently; only the valid prefix chains.
            expected=fetch_pc+PC_W'(lane*PC_STEP);
            if(!stop_prefix && i_decode_valid[lane] && i_decode_pc[lane*PC_W +: PC_W]==expected) begin
                capture_selected[lane]=1;
                capture_writes[lane]=i_decode_write[lane] && !i_decode_exception[lane] && i_decode_rd[lane*ARCH_W +: ARCH_W]!=0;
                sequential_next=i_decode_pc[lane*PC_W +: PC_W]+PC_W'(PC_STEP);
                if(i_decode_control[lane]) begin
                    has_control=1; o_predict_pc=i_decode_pc[lane*PC_W +: PC_W];
                    stop_prefix=1;
                end
                if(i_decode_exception[lane] || i_decode_csr[lane]) stop_prefix=1;
            end else stop_prefix=1;
        end
    end
    always_comb begin
        capture_predicted='0;
        for(int lane=0;lane<DECODE;lane++)
            capture_predicted[lane*PC_W +: PC_W]=(capture_selected[lane] && i_decode_control[lane]) ?
                prediction_next : i_decode_pc[lane*PC_W +: PC_W]+PC_W'(PC_STEP);
        next_fetch=has_control ? prediction_next : sequential_next;
    end
    assign o_decode_get=capture_selected & {DECODE{capture_ready}};
    assign writes=decoded.writes;
    assign predicted=decoded.predicted;
    // Window assignment uses current allocation state, not capture-time state:
    // resource pressure may seal an older window while this bundle is held.
    always_comb begin
        ends='0; flow_ids='0; next_flow=flow; next_window_count=window_count;
        for(int lane=0;lane<DECODE;lane++) if(selected[lane]) begin
            flow_ids[lane*FLOW_W +: FLOW_W]=next_flow;
            ends[lane]=decoded.end_window[lane] || decoded.control[lane] || decoded.csr[lane] || next_window_count==WINDOW_SIZE-1;
            if(ends[lane]) begin
                next_flow=(int'(next_flow)==WINDOWS-1)?'0:next_flow+1'b1;
                next_window_count=0;
            end else next_window_count++;
        end
    end
    always_ff @(posedge clk) if(capture) begin
        decoded<='{pc:i_decode_pc,predicted:capture_predicted,path:i_decode_path,
            uop:i_decode_uop,imm:i_decode_imm,rd:i_decode_rd,rs:i_decode_rs,
            writes:capture_writes,control:i_decode_control,memory_op:i_decode_memory,
            store:i_decode_store,csr:i_decode_csr,end_window:i_decode_end,
            exception:i_decode_exception,cause:i_decode_cause,epoch:i_decode_epoch};
    end
    always_ff @(posedge clk or negedge reset_n) begin
        if(!reset_n) selected<='0;
        else if(o_flush || (o_retire && metadata[commit_token[SLOT_W-1:0]].csr)) selected<='0;
        else if(capture) selected<=capture_selected;
        else if(admit) selected<='0;
    end
    always_comb begin
        logic [TOKEN_W-1:0] token;
        o_ex_valid='0; o_ex_token='0; o_ex_memory='0; o_ex_store='0; o_ex_csr='0; o_ex_data=rs_data;
        rs_pop='0; result_eligible='0; token='0;
        for(int lane=0;lane<EX_LANES;lane++) begin
            token=rs_data[lane*EX_W+PC_W +: TOKEN_W];
            o_ex_token[lane*TOKEN_W +: TOKEN_W]=token;
            // RS owns each instruction exactly once until this handshake.
            // Its complete state is flushed before slots can be reused. Keep
            // the ownership checks as assertions, not on the FIFO pop path.
            o_ex_valid[lane]=backend_reset_n && rs_valid[lane];
            if(o_ex_valid[lane]) begin
                o_ex_memory[lane]=metadata[token[SLOT_W-1:0]].memory_op;
                o_ex_store[lane]=metadata[token[SLOT_W-1:0]].store;
                o_ex_csr[lane]=metadata[token[SLOT_W-1:0]].csr;
            end
            rs_pop[lane]=backend_reset_n && rs_valid[lane] && i_ex_get[lane];
            token=i_result_token[lane*TOKEN_W +: TOKEN_W];
            if(meta_live(token)) begin
                result_eligible[lane]=metadata[token[SLOT_W-1:0]].issued && !metadata[token[SLOT_W-1:0]].queued && !metadata[token[SLOT_W-1:0]].memory_op;
            end
        end
        // CSR never occupies a blocked RS output. Its operands are ready once
        // all older instructions have retired, so it can bypass IST/RS there.
        token=csr_packet[PC_W +: TOKEN_W];
        if(backend_reset_n && csr_pending && head_valid && head_token==token) begin
            o_ex_valid[csr_lane]=1;
            o_ex_data[int'(csr_lane)*EX_W +: EX_W]=csr_packet;
            o_ex_token[int'(csr_lane)*TOKEN_W +: TOKEN_W]=token;
            o_ex_memory[csr_lane]=0; o_ex_store[csr_lane]=0; o_ex_csr[csr_lane]=1;
            // At the ordered CSR head, all older instructions have retired
            // and admission of younger instructions is barred. RS is empty,
            // so CSR eligibility need not feed back into the RS pop network.
        end
    end
    // All memory completions, including AGU faults, cross U_MEMORY's registered
    // completion output. AGU admission cannot arbitrate this FIFO input or its
    // acknowledgement back to the memory service engine.
    assign incoming_token={mem_done_token,i_result_token};
    assign incoming_fault={mem_done_fault,i_result_fault};
    assign incoming_cause={mem_done_cause,i_result_cause};
    assign mem_completion_discard=!meta_live(mem_done_token) ||
        !metadata[mem_done_token[SLOT_W-1:0]].memory_op || metadata[mem_done_token[SLOT_W-1:0]].queued;
    wire [EX_LANES-1:0] result_selected;
    // Eligibility depends only on the token. Equal tokens therefore share
    // eligibility, so duplicate arbitration needs no other lane's validation
    // result. All comparisons run in parallel and only local eligibility gates
    // the selected output. EX/memory classes remain disjoint.
    oryukdo_result_selector #(.LANES(EX_LANES),.TOKEN_W(TOKEN_W)) U_RESULT_SELECT (
        .i_valid(i_result_valid),.i_ready(queue_ready[EX_LANES-1:0]),
        .i_token(i_result_token),.o_selected(result_selected));
    assign queue_valid={mem_done_valid && !mem_completion_discard,result_selected & result_eligible};
    for(genvar lane=0;lane<EX_LANES;lane++) begin: G_RESULT_READY
        assign o_result_accept[lane]=queue_ready[lane] && result_eligible[lane] &&
            (!i_result_valid[lane] || queue_valid[lane]);
    end
    oryukdo_completion_queue #(.LANES(RESULTS),.DEPTH(2),.TOKEN_W(TOKEN_W),.DATA_W(DATA_W),.PC_W(PC_W)) U_COMPLETION (
        .clk(clk),.reset_n(reset_n),.i_flush(o_flush),.i_valid(queue_valid),.o_ready(queue_ready),
        .i_token(incoming_token),.i_data({mem_done_data,i_result_data}),.i_next({PC_W'(0),i_result_next}),
        .i_fault(incoming_fault),.i_cause(incoming_cause),.o_valid(complete_valid),.i_get(2'b11),
        .o_token(complete_token),.o_data(complete_data),.o_next(complete_next),
        .o_fault(complete_fault),.o_cause(complete_cause),.o_source(complete_source));
    always_comb begin
        logic [TOKEN_W-1:0] token;
        integer source_lane;
        o_wb_valid='0; o_wb_phy='0; o_wb_data='0; o_wb_uop='0;
        o_predict_update_valid='0; o_predict_update_pc='0; o_predict_update_next='0;
        token='0; source_lane=0;
        for(int bank=0;bank<BANKS;bank++) begin
            token=complete_token[bank*TOKEN_W +: TOKEN_W];
            source_lane=int'(complete_source[bank*SOURCE_W +: SOURCE_W]);
            o_wb_phy[bank*PHY_W +: PHY_W]=complete_phy[bank*PHY_W +: PHY_W];
            o_wb_data[bank*DATA_W +: DATA_W]=complete_data[bank*DATA_W +: DATA_W];
            if(meta_live(token)) begin
                o_wb_uop[bank*UOP_W +: UOP_W]=metadata[token[SLOT_W-1:0]].uop;
                o_wb_valid[bank]=complete_valid[bank] && complete_accept[bank] && !complete_fault[bank] &&
                    complete_phy[bank*PHY_W +: PHY_W]!=0;
                if(source_lane<EX_LANES && complete_valid[bank] && complete_accept[bank] &&
                   !complete_fault[bank] && metadata[token[SLOT_W-1:0]].control) begin
                    o_predict_update_valid[source_lane]=1;
                    o_predict_update_pc[source_lane*PC_W +: PC_W]=metadata[token[SLOT_W-1:0]].pc;
                    o_predict_update_next[source_lane*PC_W +: PC_W]=complete_next[bank*PC_W +: PC_W];
                end
            end
        end
    end
    always_ff @(posedge clk or negedge reset_n) begin
        if(!reset_n) wake_valid<='0;
        else if(o_flush || initializing) wake_valid<='0;
        else wake_valid<=o_wb_valid[BANKS-1:0];
    end
    always_ff @(posedge clk) begin
        for(int bank=0;bank<BANKS;bank++) if(o_wb_valid[bank])
            wake_phy[bank*PHY_W +: PHY_W]<=o_wb_phy[bank*PHY_W +: PHY_W];
    end
    wire agu_eligible=reset_n && !o_flush && meta_live(i_agu_token) && metadata[i_agu_token[SLOT_W-1:0]].issued &&
        !metadata[i_agu_token[SLOT_W-1:0]].queued;
    assign o_agu_ready=mem_agu_ready && agu_eligible;
    assign o_exception_pending=frontier_stopped || fault_pending;
    always_ff @(posedge clk or negedge reset_n) begin
        if(!reset_n) fault_pending<=0;
        else if(o_flush) fault_pending<=0;
        // Stop new admission on the fault's AGU acceptance edge even though
        // ordered memory completion and precise trap delivery happen later.
        else if(agu_fault_now || |(queue_valid & queue_ready & incoming_fault)) fault_pending<=1;
    end
    assign o_retire=commit_valid && commit_ready;
    assign o_retire_token=commit_token;
    always_ff @(posedge clk or negedge reset_n) begin
        if(!reset_n) begin
            fetch_pc<='0; boot_pending<=1; epoch<='0; flow<='0; window_count<=0;
            csr_pending<=0; csr_barrier<=0; csr_packet<='0; csr_lane<='0;
            for(int n=0;n<ENTRIES;n++) metadata[n]<='0;
        end else if(boot_pending) begin
            fetch_pc<=i_reset_pc; boot_pending<=0;
        end else if(o_flush) begin
            fetch_pc<=o_redirect_pc; epoch<=epoch+1'b1; flow<='0; window_count<=0;
            csr_pending<=0; csr_barrier<=0;
            for(int n=0;n<ENTRIES;n++) metadata[n].valid<=0;
        end else begin
            if(seal_window) begin
                window_count<=0;
                flow<=(int'(flow)==WINDOWS-1)?'0:flow+1'b1;
            end
            if(o_retire) begin
                metadata[commit_token[SLOT_W-1:0]].valid<=0;
                if(metadata[commit_token[SLOT_W-1:0]].csr) begin
                    // CSR can change translation or execution mode. No younger
                    // instruction may execute using the old system state, and
                    // prefetched responses must be refreshed after retirement.
                    csr_barrier<=0;
                    epoch<=epoch+1'b1;
                end
            end
            for(int lane=0;lane<EX_LANES;lane++) if(o_ex_valid[lane] && i_ex_get[lane]) begin
                metadata[o_ex_token[lane*TOKEN_W +: SLOT_W]].issued<=1;
                if(o_ex_csr[lane]) csr_pending<=0;
            end
            for(int lane=0;lane<RESULTS;lane++) if(queue_valid[lane] && queue_ready[lane])
                metadata[incoming_token[lane*TOKEN_W +: SLOT_W]].queued<=1;
            if(capture) fetch_pc<=next_fetch;
            if(admit) begin
                flow<=next_flow; window_count<=next_window_count;
                for(int lane=0;lane<DECODE;lane++) if(selected[lane]) begin
                    metadata[allocated_tokens[lane*TOKEN_W +: SLOT_W]]<='{
                        valid:1'b1, issued:1'b0, queued:1'b0, memory_op:decoded.memory_op[lane], store:decoded.store[lane],
                        csr:decoded.csr[lane], control:decoded.control[lane],
                        generation:allocated_tokens[lane*TOKEN_W+SLOT_W +: GEN_W],
                        uop:decoded.uop[lane*UOP_W +: UOP_W], pc:decoded.pc[lane*PC_W +: PC_W]};
                    if(decoded.csr[lane] && !decoded.exception[lane]) begin
                        csr_pending<=1;
                        csr_barrier<=1;
                        csr_lane<=$clog2(EX_LANES)'(path_first_lane(decoded.path[lane*PATH_W +: PATH_W]));
                        csr_packet<={rename_rs[lane*2*PHY_W +: 2*PHY_W],
                            rename_rd[lane*PHY_W +: PHY_W], decoded.imm[lane*IMM_W +: IMM_W],
                            decoded.uop[lane*UOP_W +: UOP_W], decoded.path[lane*PATH_W +: PATH_W],
                            flow_ids[lane*FLOW_W +: FLOW_W], allocated_tokens[lane*TOKEN_W +: TOKEN_W],
                            decoded.pc[lane*PC_W +: PC_W]};
                    end
                end
            end
        end
    end
    oryukdo_new_entry_logic #(.PC_W(PC_W),.TOKEN_W(TOKEN_W),.FLOW_W(FLOW_W),.PATH_W(PATH_W),
        .UOP_W(UOP_W),.IMM_W(IMM_W),.ARCH(ARCH),.PHY(PHY),.LANES(DECODE),.RESULTS(RESULTS)) U_NEL (
        .clk(clk),.reset_n(reset_n),.i_flush(o_flush),.i_accept(admit),.i_dispatch(dispatch_fire),
        .i_valid(selected),.i_write(writes),.i_exception(decoded.exception),.i_csr(decoded.csr),
        .i_rd(decoded.rd),.i_rs(decoded.rs),.i_pc(decoded.pc),.i_token(allocated_tokens),.i_flow(flow_ids),
        .i_path(decoded.path),.i_uop(decoded.uop),.i_imm(decoded.imm),
        .i_done(ready_valid),.i_done_phy(ready_phy),.i_retire_write(o_retire && commit_write),
        .i_retire_arch(commit_arch),.i_retire_phy(commit_phy),.o_rename_ready(rename_ready),
        .o_initializing(initializing),.o_rd(rename_rd),.o_rs(rename_rs),.o_rs_ready(rename_ready_bits),
        .o_dispatch_valid(dispatch_valid),.o_dispatch_data(dispatch_data));
    oryukdo_frontier #(.DEPTH(ENTRIES),.LANES(DECODE),.RESULTS(BANKS),.PC_W(PC_W),
        .GEN_W(GEN_W),.ARCH_W(ARCH_W),.PHY_W(PHY_W)) U_FRONTIER (
        .clk(clk),.reset_n(reset_n),.i_seal(seal_window),.i_allocate(allocate),.o_allocate_ready(frontier_ready),
        .o_allocate_token(allocated_tokens),.i_pc(decoded.pc),.i_predicted_next(predicted),
        .i_end(ends),.i_control(decoded.control),.i_store(decoded.store),.i_serial(decoded.csr),
        .i_write(writes),.i_exception(decoded.exception),.i_arch(decoded.rd),.i_phy(rename_rd),.i_cause(decoded.cause),
        .i_complete(complete_valid),.i_complete_token(complete_token),.i_complete_fault(complete_fault),
        .i_complete_cause(complete_cause),.i_complete_next(complete_next),
        .o_complete_accept(complete_accept),.o_complete_phy(complete_phy),
        .i_serial_valid(serial_valid),.i_serial_token(serial_token),.o_serial_accept(),
        .i_store_fault(store_fault),.i_store_fault_token(store_fault_token),.i_store_fault_cause(store_fault_cause),
        .o_head_valid(head_valid),.o_head_token(head_token),
        .o_commit_valid(commit_valid),.i_commit_ready(commit_ready),.o_commit_token(commit_token),
        .o_commit_store(commit_store),.o_commit_write(commit_write),.o_commit_arch(commit_arch),.o_commit_phy(commit_phy),
        .i_interrupt(i_interrupt),.i_trap_vector(i_trap_vector),.i_reset_pc(i_reset_pc),
        .o_flush(o_flush),.o_trap(o_trap),.o_trap_interrupt(o_trap_interrupt),.o_redirect_pc(o_redirect_pc),
        .o_trap_pc(o_trap_pc),.o_trap_cause(o_trap_cause),.o_boundary(o_window_boundary),.o_stopped(frontier_stopped),.o_count(frontier_count));
    generate if (CUSTOM_LSQ) begin : GEN_CUSTOM_LSQ
    oryukdo_custom_lsq #(.DEPTH(ENTRIES),.LANES(DECODE),.ADDR_W(PC_W),.DATA_W(DATA_W),.GEN_W(GEN_W)) U_LSQ (
        .i_reserve(selected),.o_allocate_ready(lsq_allocate_ready),
        .clk(clk),.reset_n(reset_n),.i_flush(o_flush),.i_allocate(allocate),.i_memory(decoded.memory_op),
        .i_store(decoded.store),.i_token(allocated_tokens),.i_agu_valid(i_agu_valid && agu_eligible),.o_agu_ready(mem_agu_ready),
        .i_agu_token(i_agu_token),.i_agu_address(i_agu_address),.i_agu_data(i_agu_data),.i_agu_mask(i_agu_mask),
        .i_agu_nonspec(i_agu_nonspec),.i_agu_fault(i_agu_fault),.i_agu_cause(i_agu_cause),
        .o_serial_valid(serial_valid),.o_serial_token(serial_token),.i_head_valid(head_valid),.i_head_token(head_token),
        .i_commit_valid(commit_valid),.i_commit_store(commit_store),.i_retire(o_retire),.i_commit_token(commit_token),
        .o_commit_ready(commit_ready),.o_complete_valid(mem_done_valid),.i_complete_accept(mem_completion_discard || queue_ready[EX_LANES]),
        .o_complete_token(mem_done_token),.o_complete_data(mem_done_data),.o_complete_fault(mem_done_fault),.o_complete_cause(mem_done_cause),
        .o_request_valid(o_mem_valid),.i_request_ready(i_mem_ready),.o_request_store(o_mem_store),
        .o_request_address(o_mem_address),.o_request_data(o_mem_data),.o_request_mask(o_mem_mask),
        .i_response_valid(i_mem_response_valid),.o_response_ready(o_mem_response_ready),.i_response_data(i_mem_response_data),
        .i_response_fault(i_mem_response_fault),.i_response_cause(i_mem_response_cause),
        .o_store_fault(store_fault),.o_store_fault_token(store_fault_token),.o_store_fault_cause(store_fault_cause));
    end else begin : GEN_BUILTIN_LSQ
        assign lsq_allocate_ready=1'b1;
    oryukdo_memory #(.DEPTH(ENTRIES),.LANES(DECODE),.ADDR_W(PC_W),.DATA_W(DATA_W),.GEN_W(GEN_W)) U_MEMORY (
        .clk(clk),.reset_n(reset_n),.i_flush(o_flush),.i_allocate(allocate),.i_memory(decoded.memory_op),
        .i_store(decoded.store),.i_token(allocated_tokens),.i_agu_valid(i_agu_valid && o_agu_ready),.o_agu_ready(mem_agu_ready),
        .i_agu_token(i_agu_token),.i_agu_address(i_agu_address),.i_agu_data(i_agu_data),.i_agu_mask(i_agu_mask),
        .i_agu_nonspec(i_agu_nonspec),.i_agu_fault(i_agu_fault),.i_agu_cause(i_agu_cause),
        .o_serial_valid(serial_valid),.o_serial_token(serial_token),.i_head_valid(head_valid),.i_head_token(head_token),
        .i_commit_valid(commit_valid),.i_commit_store(commit_store),.i_retire(o_retire),.i_commit_token(commit_token),
        .o_commit_ready(commit_ready),.o_complete_valid(mem_done_valid),.i_complete_accept(mem_completion_discard || queue_ready[EX_LANES]),
        .o_complete_token(mem_done_token),.o_complete_data(mem_done_data),.o_complete_fault(mem_done_fault),.o_complete_cause(mem_done_cause),
        .o_request_valid(o_mem_valid),.i_request_ready(i_mem_ready),.o_request_store(o_mem_store),
        .o_request_address(o_mem_address),.o_request_data(o_mem_data),.o_request_mask(o_mem_mask),
        .i_response_valid(i_mem_response_valid),.o_response_ready(o_mem_response_ready),.i_response_data(i_mem_response_data),
        .i_response_fault(i_mem_response_fault),.i_response_cause(i_mem_response_cause),
        .o_store_fault(store_fault),.o_store_fault_token(store_fault_token),.o_store_fault_cause(store_fault_cause));
    end endgenerate
    // Backend instances are generated below with a common opaque extended PC
    // field: {generation, slot, actual PC}. IST/PRM/RS never interpret that field.

    instruction_state_table #( .IS_INST_PC_BITWIDTH(PC_W+TOKEN_W), .IS_INST_IMM(IMM_W), .IS_INST_REGS(ARCH),
 .EX_INST_MICROOP_BITWIDTH(UOP_W), .STRUCT_DECODE_NEW_INST(DECODE),
 .STRUCT_INST_STATE_ENTRIES(ENTRIES), .STRUCT_PHYREGS(PHY),
 .STRUCT_EX_PATH(PATHS), .STRUCT_RS_OUT_ENTRY(PATH_LANES), .STRUCT_EX_CORES(EX_LANES),
 .STRUCT_EX_OUT_RESULT('{default:1}), .STRUCT_EX_OUT_RESULT_SUM(RESULTS), .STRUCT_PRM_ENTRY_UPDATE(UPDATES),
 .STRUCT_PRM_ENTRY_BUFFER(4), .STRUCT_UNALLOCATE_PHYREG(1),
 .STRUCT_FLOW_WINDOWS(WINDOWS), .STRUCT_FLOW_PC_MAX_RANGE(WINDOW_SIZE), .STRUCT_IST_ISSUE_WIDTH(ISSUE)) U_IST (
        .clk(clk),.reset_n(backend_reset_n),
        .i_nel_new_inst_valid(dispatch_valid & {DECODE{dispatch_fire}}),
        .o_nel_new_inst_get(ist_get),.i_nel_new_inst_data(dispatch_data),
        .i_prm_ready_phyreg_valid(notify_valid),.i_prm_ready_phyreg_data(notify_data),
        .o_rs_ready_inst_valid(ist_valid),.i_rs_ready_inst_get(rs_get),.o_rs_ready_inst_data(ist_data),
        .o_prm_wait_phyreg_valid(wait_valid),.o_prm_wait_phyreg_data(wait_data));
    ready_station #( .IS_INST_PC_BITWIDTH(PC_W+TOKEN_W), .IS_INST_IMM(IMM_W), .IS_INST_REGS(ARCH),
 .EX_INST_MICROOP_BITWIDTH(UOP_W), .STRUCT_DECODE_NEW_INST(DECODE),
 .STRUCT_INST_STATE_ENTRIES(ENTRIES), .STRUCT_PHYREGS(PHY),
 .STRUCT_EX_PATH(PATHS), .STRUCT_RS_OUT_ENTRY(PATH_LANES), .STRUCT_EX_CORES(EX_LANES),
 .STRUCT_EX_OUT_RESULT('{default:1}), .STRUCT_EX_OUT_RESULT_SUM(RESULTS), .STRUCT_PRM_ENTRY_UPDATE(UPDATES),
 .STRUCT_PRM_ENTRY_BUFFER(4), .STRUCT_UNALLOCATE_PHYREG(1),
 .STRUCT_FLOW_WINDOWS(WINDOWS), .STRUCT_FLOW_PC_MAX_RANGE(WINDOW_SIZE),.STRUCT_IST_ISSUE_WIDTH(ISSUE),.STRUCT_RS_FIFO_WIDTH(RS_DEPTH)) U_RS (
        .clk(clk),.reset_n(backend_reset_n),.i_ist_ready_inst_valid(ist_valid),
        .o_ist_ready_inst_get(rs_get),.i_ist_ready_inst_data(ist_data),
        .o_ex_wait_inst_valid(rs_valid),.i_ex_wait_inst_get(rs_pop),.o_ex_wait_inst_data(rs_data));
    oryukdo_dependency_mapper #( .IS_INST_PC_BITWIDTH(PC_W+TOKEN_W), .IS_INST_IMM(IMM_W), .IS_INST_REGS(ARCH),
 .EX_INST_MICROOP_BITWIDTH(UOP_W), .STRUCT_DECODE_NEW_INST(DECODE),
 .STRUCT_INST_STATE_ENTRIES(ENTRIES), .STRUCT_PHYREGS(PHY),
 .STRUCT_EX_PATH(PATHS), .STRUCT_RS_OUT_ENTRY(PATH_LANES), .STRUCT_EX_CORES(EX_LANES),
 .STRUCT_EX_OUT_RESULT('{default:1}), .STRUCT_EX_OUT_RESULT_SUM(RESULTS), .STRUCT_PRM_ENTRY_UPDATE(UPDATES),
 .STRUCT_PRM_ENTRY_BUFFER(4), .STRUCT_UNALLOCATE_PHYREG(1),
 .STRUCT_FLOW_WINDOWS(WINDOWS), .STRUCT_FLOW_PC_MAX_RANGE(WINDOW_SIZE)) U_PRM (
        .clk(clk),.reset_n(backend_reset_n),
        .i_external_allocate_valid({DECODE{rename_ready}}),.i_external_allocate_data(rename_rd),
        .i_ist_wait_phyreg_valid(wait_valid),.i_ist_wait_phyreg_data(wait_data),
        .i_wbc_done_phyreg_valid(ready_valid),.i_wbc_done_phyreg_data(ready_phy),
        .i_fcl_unallocate_phyreg_valid('0),.i_fcl_unallocate_phyreg_data('0),
        .o_nel_phyreg_valid(prm_alloc_valid),.i_nel_phyreg_get(allocate & writes),.o_nel_phyreg_data(),
        .o_ist_ready_phyreg_valid(notify_valid),.o_ist_ready_phyreg_data(notify_data));
    initial begin
        integer total_lanes;
        total_lanes=0;
        for(integer p=0;p<PATHS;p++) begin
            if(PATH_LANES[p]<1) $fatal(1,"Each EX path needs at least one lane");
            total_lanes+=PATH_LANES[p];
        end
        if(total_lanes!=EX_LANES) $fatal(1,"EX lane count mismatch");
        if(ENTRIES<DECODE || PHY<ARCH+DECODE || WINDOWS<1 || WINDOW_SIZE<1 || PATHS<2)
            $fatal(1,"Invalid ORYUKDO dimensions");
    end
    // synthesis translate_off
    always @(posedge clk) if(reset_n && !o_flush) begin
        for(int lane=0;lane<EX_LANES;lane++) for(int prior=0;prior<lane;prior++)
            if(i_result_token[lane*TOKEN_W +: TOKEN_W]==i_result_token[prior*TOKEN_W +: TOKEN_W]) begin
                assert(result_eligible[lane]==result_eligible[prior])
                    else $fatal(1,"Equal result tokens have lane-dependent eligibility");
                assert(!(queue_valid[lane] && queue_ready[lane] && queue_valid[prior] && queue_ready[prior]))
                    else $fatal(1,"Duplicate result accepted on multiple lanes");
            end
    end
    logic [BANKS*TOKEN_W-1:0] wake_token;
    always @(posedge clk) begin
        for(int bank=0;bank<BANKS;bank++) if(o_wb_valid[bank])
            wake_token[bank*TOKEN_W +: TOKEN_W]<=complete_token[bank*TOKEN_W +: TOKEN_W];
        if(backend_reset_n) for(int bank=0;bank<BANKS;bank++) if(wake_valid[bank]) begin
            assert(meta_live(wake_token[bank*TOKEN_W +: TOKEN_W]))
                else $fatal(1,"Delayed Ready outlived its instruction");
            for(int lane=0;lane<DECODE;lane++) if(allocate[lane] && writes[lane])
                assert(rename_rd[lane*PHY_W +: PHY_W]!=wake_phy[bank*PHY_W +: PHY_W])
                    else $fatal(1,"Delayed Ready overlaps physical register reuse");
        end
    end
    always @(posedge clk) if(backend_reset_n) begin
        for(int lane=0;lane<EX_LANES;lane++) if(rs_valid[lane]) begin
            assert(meta_live(rs_data[lane*EX_W+PC_W +: TOKEN_W]))
                else $fatal(1,"RS holds a stale or unallocated token");
            assert(!metadata[rs_data[lane*EX_W+PC_W +: SLOT_W]].issued &&
                   !metadata[rs_data[lane*EX_W+PC_W +: SLOT_W]].queued &&
                   !metadata[rs_data[lane*EX_W+PC_W +: SLOT_W]].csr)
                else $fatal(1,"RS lost single ownership before EX acceptance");
            for(int prior=0;prior<lane;prior++) if(rs_valid[prior])
                assert(rs_data[prior*EX_W+PC_W +: TOKEN_W]!=rs_data[lane*EX_W+PC_W +: TOKEN_W])
                    else $fatal(1,"Duplicate token across RS outputs");
        end
        if(csr_pending && head_valid && head_token==csr_packet[PC_W +: TOKEN_W])
            assert(rs_valid=='0) else $fatal(1,"Ordered CSR overlaps outstanding RS instructions");
    end
    always @(posedge clk) if(reset_n && !o_flush) begin
        for(int lane=0;lane<EX_LANES;lane++) if(queue_valid[lane] && queue_valid[EX_LANES])
            assert(incoming_token[lane*TOKEN_W +: TOKEN_W]!=mem_done_token)
                else $fatal(1,"EX and memory completion classes overlap");
    end
    always @(posedge clk) if(reset_n && admit) begin
        for(integer lane=0;lane<DECODE;lane++) if(selected[lane]) begin
            assert(int'(decoded.path[lane*PATH_W +: PATH_W])<PATHS) else $fatal(1,"Invalid EX path");
            assert(!decoded.store[lane] || decoded.memory_op[lane]) else $fatal(1,"Store needs memory classification");
            assert(!(decoded.csr[lane] && decoded.memory_op[lane])) else $fatal(1,"CSR and memory are distinct classes");
        end
    end
    // synthesis translate_on
endmodule
