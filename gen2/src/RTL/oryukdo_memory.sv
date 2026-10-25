`timescale 1ns/1ps
// Ordered internal memory service, delayed store publication and sequential
// byte forwarding. A scan compares ONE previous store per cycle (no CAM).
module oryukdo_memory #(
    parameter int DEPTH=128, LANES=2, ADDR_W=32, DATA_W=32, GEN_W=32, CAUSE_W=5,
    localparam int SLOT_W=(DEPTH>1)?$clog2(DEPTH):1,
    localparam int TOKEN_W=SLOT_W+GEN_W, BYTES=DATA_W/8
) (
    input wire clk, reset_n, i_flush,
    input wire [LANES-1:0] i_allocate, i_memory, i_store,
    input wire [LANES*TOKEN_W-1:0] i_token,
    input wire i_agu_valid,
    output wire o_agu_ready,
    input wire [TOKEN_W-1:0] i_agu_token,
    input wire [ADDR_W-1:0] i_agu_address,
    input wire [DATA_W-1:0] i_agu_data,
    input wire [BYTES-1:0] i_agu_mask,
    input wire i_agu_nonspec, i_agu_fault,
    input wire [CAUSE_W-1:0] i_agu_cause,
    output wire o_serial_valid,
    output wire [TOKEN_W-1:0] o_serial_token,
    input wire i_head_valid,
    input wire [TOKEN_W-1:0] i_head_token,
    input wire i_commit_valid, i_commit_store, i_retire,
    input wire [TOKEN_W-1:0] i_commit_token,
    output wire o_commit_ready,
    output logic o_complete_valid,
    input wire i_complete_accept,
    output logic [TOKEN_W-1:0] o_complete_token,
    output logic [DATA_W-1:0] o_complete_data,
    output logic o_complete_fault,
    output logic [CAUSE_W-1:0] o_complete_cause,
    output wire o_request_valid,
    input wire i_request_ready,
    output wire o_request_store,
    output wire [ADDR_W-1:0] o_request_address,
    output wire [DATA_W-1:0] o_request_data,
    output wire [BYTES-1:0] o_request_mask,
    input wire i_response_valid,
    output wire o_response_ready,
    input wire [DATA_W-1:0] i_response_data,
    input wire i_response_fault,
    input wire [CAUSE_W-1:0] i_response_cause,
    output logic o_store_fault,
    output logic [TOKEN_W-1:0] o_store_fault_token,
    output logic [CAUSE_W-1:0] o_store_fault_cause
);
    typedef struct packed {
        logic valid, memory_op, store, prepared, processed, published, nonspec, fault;
        logic [GEN_W-1:0] generation;
        logic [ADDR_W-1:0] address;
        logic [DATA_W-1:0] data;
        logic [BYTES-1:0] mask;
        logic [CAUSE_W-1:0] cause;
    } entry_t;
    entry_t entries[DEPTH];
    logic [SLOT_W-1:0] service, scan;
    typedef enum logic [1:0] {IDLE, SCAN, LOAD_REQUEST, LOAD_WAIT} work_t;
    typedef enum logic [1:0] {BUS_IDLE, BUS_REQUEST, BUS_WAIT} bus_t;
    work_t work_state;
    bus_t bus_state;
    logic [DATA_W-1:0] forwarded, bus_forwarded;
    logic [BYTES-1:0] forwarded_mask, bus_forwarded_mask;
    logic [ADDR_W-1:0] bus_address;
    logic [DATA_W-1:0] bus_data;
    logic [BYTES-1:0] bus_mask;
    logic bus_store, bus_killed;
    logic [TOKEN_W-1:0] bus_token;
    wire [TOKEN_W-1:0] service_token={entries[service].generation,service};
    wire completion_fire=o_complete_valid && i_complete_accept;
    function automatic [SLOT_W-1:0] step(input [SLOT_W-1:0] p);
        return int'(p)==DEPTH-1 ? '0 : p+1'b1;
    endfunction
    function automatic logic live(input [TOKEN_W-1:0] token);
        if(int'(token[SLOT_W-1:0])>=DEPTH) return 0;
        return entries[token[SLOT_W-1:0]].valid &&
            entries[token[SLOT_W-1:0]].generation==token[SLOT_W +: GEN_W];
    endfunction
    assign o_agu_ready=reset_n && !i_flush && live(i_agu_token) &&
        entries[i_agu_token[SLOT_W-1:0]].memory_op && !entries[i_agu_token[SLOT_W-1:0]].prepared;
    assign o_serial_valid=i_agu_valid && o_agu_ready && i_agu_nonspec;
    assign o_serial_token=i_agu_token;
    assign o_commit_ready=!i_commit_store ||
        (live(i_commit_token) && entries[i_commit_token[SLOT_W-1:0]].published);
    assign o_request_valid=reset_n && bus_state==BUS_REQUEST;
    assign o_request_store=bus_store;
    assign o_request_address=bus_address;
    assign o_request_data=bus_data;
    assign o_request_mask=bus_mask;
    assign o_response_ready=reset_n && bus_state==BUS_WAIT &&
        (bus_store || bus_killed || i_flush || !o_complete_valid);
    always_ff @(posedge clk or negedge reset_n) begin
        if(!reset_n) begin
            service<='0; scan<='0; work_state<=IDLE; bus_state<=BUS_IDLE;
            forwarded<='0; forwarded_mask<='0; bus_forwarded<='0; bus_forwarded_mask<='0;
            bus_address<='0; bus_data<='0; bus_mask<='0; bus_token<='0;
            bus_store<=0; bus_killed<=0;
            o_complete_valid<=0; o_complete_token<='0; o_complete_data<='0;
            o_complete_fault<=0; o_complete_cause<='0;
            o_store_fault<=0; o_store_fault_token<='0; o_store_fault_cause<='0;
            for(int n=0;n<DEPTH;n++) entries[n]<='0;
        end else begin
            o_store_fault<=0;
            if(completion_fire) begin
                o_complete_valid<=0;
                if(live(o_complete_token)) entries[o_complete_token[SLOT_W-1:0]].processed<=1;
                service<=step(service); work_state<=IDLE;
            end
            if(i_retire) entries[i_commit_token[SLOT_W-1:0]].valid<=0;
            for(int lane=0;lane<LANES;lane++) if(i_allocate[lane]) begin
                entries[i_token[lane*TOKEN_W +: SLOT_W]]<='{
                    valid:1'b1, memory_op:i_memory[lane], store:i_store[lane],
                    prepared:1'b0, processed:1'b0, published:1'b0, nonspec:1'b0, fault:1'b0,
                    generation:i_token[lane*TOKEN_W+SLOT_W +: GEN_W],
                    address:'0, data:'0, mask:'0, cause:'0};
            end
            if(i_agu_valid && o_agu_ready) begin
                entries[i_agu_token[SLOT_W-1:0]].prepared<=1;
                entries[i_agu_token[SLOT_W-1:0]].address<=i_agu_address;
                entries[i_agu_token[SLOT_W-1:0]].data<=i_agu_data;
                entries[i_agu_token[SLOT_W-1:0]].mask<=i_agu_mask;
                entries[i_agu_token[SLOT_W-1:0]].nonspec<=i_agu_nonspec;
                entries[i_agu_token[SLOT_W-1:0]].fault<=i_agu_fault;
                entries[i_agu_token[SLOT_W-1:0]].cause<=i_agu_cause;
            end
            if(!o_complete_valid && !i_flush) begin
                case(work_state)
                    IDLE: if(entries[service].valid && !entries[service].processed) begin
                        if(!entries[service].memory_op) begin
                            entries[service].processed<=1; service<=step(service);
                        end else if(entries[service].prepared) begin
                            if(entries[service].fault || (entries[service].store &&
                                (!entries[service].nonspec || entries[service].published))) begin
                                o_complete_valid<=1; o_complete_token<=service_token;
                                o_complete_data<='0; o_complete_fault<=entries[service].fault;
                                o_complete_cause<=entries[service].cause;
                            end else if(!entries[service].store &&
                                (!entries[service].nonspec || (i_head_valid && i_head_token==service_token))) begin
                                forwarded<='0; forwarded_mask<='0;
                                scan<=i_head_token[SLOT_W-1:0];
                                work_state<=entries[service].nonspec ? LOAD_REQUEST : SCAN;
                            end
                        end
                    end
                    SCAN: begin
                        if(scan==service) begin
                            if((forwarded_mask & entries[service].mask)==entries[service].mask) begin
                                o_complete_valid<=1; o_complete_token<=service_token;
                                o_complete_data<=forwarded; o_complete_fault<=0; o_complete_cause<='0;
                            end else work_state<=LOAD_REQUEST;
                        end else begin
                            if(entries[scan].valid && entries[scan].memory_op && entries[scan].store &&
                               entries[scan].prepared && !entries[scan].fault &&
                               entries[scan].address==entries[service].address) begin
                                for(int b=0;b<BYTES;b++) if(entries[scan].mask[b]) begin
                                    forwarded[b*8 +: 8]<=entries[scan].data[b*8 +: 8];
                                    forwarded_mask[b]<=1;
                                end
                            end
                            scan<=step(scan);
                        end
                    end
                    default: begin end
                endcase
            end
            if(bus_state==BUS_IDLE && !i_flush) begin
                bus_killed<=0;
                if(i_commit_valid && i_commit_store && live(i_commit_token) &&
                   !entries[i_commit_token[SLOT_W-1:0]].published &&
                   !entries[i_commit_token[SLOT_W-1:0]].fault) begin
                    bus_state<=BUS_REQUEST; bus_store<=1; bus_token<=i_commit_token;
                    bus_address<=entries[i_commit_token[SLOT_W-1:0]].address;
                    bus_data<=entries[i_commit_token[SLOT_W-1:0]].data;
                    bus_mask<=entries[i_commit_token[SLOT_W-1:0]].mask;
                end else if(work_state==IDLE && entries[service].valid && entries[service].store &&
                    entries[service].prepared && entries[service].nonspec && !entries[service].fault &&
                    !entries[service].published && i_head_valid && i_head_token==service_token) begin
                    bus_state<=BUS_REQUEST; bus_store<=1; bus_token<=service_token;
                    bus_address<=entries[service].address; bus_data<=entries[service].data;
                    bus_mask<=entries[service].mask;
                end else if(work_state==LOAD_REQUEST) begin
                    bus_state<=BUS_REQUEST; bus_store<=0; bus_token<=service_token;
                    bus_address<=entries[service].address; bus_data<='0;
                    bus_mask<=entries[service].mask; bus_forwarded<=forwarded;
                    bus_forwarded_mask<=forwarded_mask; work_state<=LOAD_WAIT;
                end
            end
            if(o_request_valid && i_request_ready) bus_state<=BUS_WAIT;
            if(i_response_valid && o_response_ready) begin
                bus_state<=BUS_IDLE;
                if(!bus_killed && !i_flush && live(bus_token)) begin
                    if(bus_store) begin
                        if(i_response_fault) begin
                            entries[bus_token[SLOT_W-1:0]].fault<=1;
                            o_store_fault<=1; o_store_fault_token<=bus_token;
                            o_store_fault_cause<=i_response_cause;
                        end else entries[bus_token[SLOT_W-1:0]].published<=1;
                    end else begin
                        o_complete_valid<=1; o_complete_token<=bus_token;
                        o_complete_data<=i_response_data;
                        for(int b=0;b<BYTES;b++) if(bus_forwarded_mask[b])
                            o_complete_data[b*8 +: 8]<=bus_forwarded[b*8 +: 8];
                        o_complete_fault<=i_response_fault; o_complete_cause<=i_response_cause;
                    end
                end
            end
            if(i_flush) begin
                service<='0; scan<='0; work_state<=IDLE; o_complete_valid<=0;
                bus_killed<=1;
                for(int n=0;n<DEPTH;n++) entries[n].valid<=0;
            end
        end
    end
    initial if(DATA_W%8!=0 || DEPTH<LANES) $fatal(1,"Invalid memory dimensions");
endmodule
