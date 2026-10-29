`timescale 1ns/1ps
// Direct-index completion table. Sequential window validation and retirement:
// one table row is inspected per cycle, never an associative tag search.
module oryukdo_frontier #(
    parameter int DEPTH=128, LANES=2, RESULTS=2, PC_W=32,
    parameter int GEN_W=32, ARCH_W=5, PHY_W=6, CAUSE_W=5,
    localparam int SLOT_W=(DEPTH>1)?$clog2(DEPTH):1,
    localparam int TOKEN_W=SLOT_W+GEN_W,
    localparam int COUNT_W=$clog2(DEPTH+1)
) (
    input wire clk, reset_n,
    input wire i_seal,
    input wire [LANES-1:0] i_allocate,
    output wire o_allocate_ready,
    output logic [LANES*TOKEN_W-1:0] o_allocate_token,
    input wire [LANES*PC_W-1:0] i_pc, i_predicted_next,
    input wire [LANES-1:0] i_end, i_control, i_store, i_serial, i_write, i_exception,
    input wire [LANES*ARCH_W-1:0] i_arch,
    input wire [LANES*PHY_W-1:0] i_phy,
    input wire [LANES*CAUSE_W-1:0] i_cause,
    input wire [RESULTS-1:0] i_complete,
    input wire [RESULTS*TOKEN_W-1:0] i_complete_token,
    input wire [RESULTS-1:0] i_complete_fault,
    input wire [RESULTS*CAUSE_W-1:0] i_complete_cause,
    input wire [RESULTS*PC_W-1:0] i_complete_next,
    output logic [RESULTS-1:0] o_complete_accept,
    output logic [RESULTS*PHY_W-1:0] o_complete_phy,
    // A checked AGU result may classify an access as non-speculative.
    input wire i_serial_valid,
    input wire [TOKEN_W-1:0] i_serial_token,
    output wire o_serial_accept,
    // A published store may report a precise bus failure at the ordered head.
    input wire i_store_fault,
    input wire [TOKEN_W-1:0] i_store_fault_token,
    input wire [CAUSE_W-1:0] i_store_fault_cause,
    output wire o_head_valid,
    output wire [TOKEN_W-1:0] o_head_token,
    output wire o_commit_valid,
    input wire i_commit_ready,
    output wire [TOKEN_W-1:0] o_commit_token,
    output wire o_commit_store, o_commit_write,
    output wire [ARCH_W-1:0] o_commit_arch,
    output wire [PHY_W-1:0] o_commit_phy,
    input wire i_interrupt,
    input wire [PC_W-1:0] i_trap_vector,
    input wire [PC_W-1:0] i_reset_pc,
    output wire o_flush, o_trap, o_trap_interrupt,
    output wire [PC_W-1:0] o_redirect_pc, o_trap_pc,
    output wire [CAUSE_W-1:0] o_trap_cause,
    output wire o_boundary,
    output wire o_stopped,
    output wire [COUNT_W-1:0] o_count
);
    typedef struct packed {
        logic valid, done, fault, wrong, last, control, store, serial, writes;
        logic [GEN_W-1:0] generation;
        logic [PC_W-1:0] pc, next_pc;
        logic [ARCH_W-1:0] arch;
        logic [PHY_W-1:0] phy;
        logic [CAUSE_W-1:0] cause;
    } entry_t;
    entry_t entries[DEPTH];
    logic [DEPTH-1:0] valid_bits, done_bits, fault_bits, wrong_bits, last_bits, serial_bits;
    logic [GEN_W-1:0] generations[DEPTH];
    typedef enum logic [1:0] {CHECK, DRAIN, EVENT} state_t;
    typedef enum logic [2:0] {WINDOW, FAULT, BRANCH, SERIAL, INTERRUPT} reason_t;
    state_t state;
    reason_t reason;
    logic [SLOT_W-1:0] head, tail, scan, limit;
    logic [COUNT_W-1:0] count, drain_left;
    logic [COUNT_W-1:0] scanned, pushes;
    logic [SLOT_W-1:0] alloc_slot[LANES];
    logic stopped, incoming_stop;
    logic irq_sealed;
    logic boot_pending;
    logic [PC_W-1:0] resume_pc, event_pc, event_redirect;
    logic [CAUSE_W-1:0] event_cause;
    wire retire = o_commit_valid && i_commit_ready;
    function automatic [SLOT_W-1:0] step(input [SLOT_W-1:0] p);
        return int'(p)==DEPTH-1 ? '0 : p+1'b1;
    endfunction
    function automatic logic live(input [TOKEN_W-1:0] token);
        if (int'(token[SLOT_W-1:0]) >= DEPTH) return 1'b0;
        return entries[token[SLOT_W-1:0]].valid &&
               entries[token[SLOT_W-1:0]].generation == token[SLOT_W +: GEN_W];
    endfunction
    always_comb begin
        logic [SLOT_W-1:0] cursor;
        cursor=tail; pushes='0;
        for (int lane=0;lane<LANES;lane++) begin
            alloc_slot[lane]=cursor;
            o_allocate_token[lane*TOKEN_W +: TOKEN_W]={generations[cursor]+GEN_W'(1),cursor};
            if (i_allocate[lane]) begin cursor=step(cursor); pushes++; end
        end
    end
    always_comb begin
        logic [TOKEN_W-1:0] token;
        incoming_stop=1'b0;
        o_complete_accept='0; o_complete_phy='0; token='0;
        for (int lane=0;lane<RESULTS;lane++) begin
            token=i_complete_token[lane*TOKEN_W +: TOKEN_W];
            o_complete_accept[lane]=reset_n && !o_flush && live(token) &&
                !entries[token[SLOT_W-1:0]].done;
            for (int older=0;older<lane;older++)
                if (i_complete[older] && o_complete_accept[older] &&
                    i_complete_token[older*TOKEN_W +: TOKEN_W]==token)
                    o_complete_accept[lane]=1'b0;
            if (o_complete_accept[lane]) begin
                o_complete_phy[lane*PHY_W +: PHY_W]=entries[token[SLOT_W-1:0]].phy;
                if (i_complete[lane] && (i_complete_fault[lane] ||
                    (entries[token[SLOT_W-1:0]].control &&
                     entries[token[SLOT_W-1:0]].next_pc != i_complete_next[lane*PC_W +: PC_W])))
                    incoming_stop=1'b1;
            end
        end
    end
    assign o_allocate_ready=reset_n && !boot_pending && !stopped && !i_interrupt && !i_seal && state!=EVENT &&
                            int'(count)<=DEPTH-LANES;
    // Draining the last older entry does not resolve its boundary. Hold younger
    // CSR/MMIO side effects until CHECK resumes or the pending event flushes.
    assign o_head_valid=reset_n && count!=0 && !o_flush &&
        (state==CHECK || (state==DRAIN && drain_left!=0));
    assign o_head_token={entries[head].generation,head};
    // Keep array dependencies explicit: XSim 2022.2 can miss changes hidden
    // inside live() when the input token itself stays constant.
    assign o_serial_accept=reset_n && !o_flush && int'(i_serial_token[SLOT_W-1:0])<DEPTH &&
        valid_bits[i_serial_token[SLOT_W-1:0]] &&
        generations[i_serial_token[SLOT_W-1:0]]==i_serial_token[SLOT_W +: GEN_W];
    assign o_commit_valid=reset_n && state==DRAIN && drain_left!=0;
    assign o_commit_token=o_head_token;
    assign o_commit_store=entries[head].store;
    assign o_commit_write=entries[head].writes;
    assign o_commit_arch=entries[head].arch;
    assign o_commit_phy=entries[head].phy;
    assign o_flush=reset_n && state==EVENT && (reason==FAULT || reason==BRANCH || reason==INTERRUPT);
    assign o_trap=o_flush && reason!=BRANCH;
    assign o_trap_interrupt=o_trap && reason==INTERRUPT;
    assign o_redirect_pc=reason==BRANCH ? event_redirect : i_trap_vector;
    assign o_trap_pc=event_pc;
    assign o_trap_cause=event_cause;
    assign o_boundary=reset_n && state==EVENT && reason==WINDOW;
    assign o_stopped=stopped || incoming_stop;
    assign o_count=count;
    always_ff @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            head<='0; tail<='0; scan<='0; limit<='0; count<='0;
            state<=CHECK; reason<=WINDOW; stopped<=0; irq_sealed<=0; scanned<='0; drain_left<='0;
            resume_pc<='0; boot_pending<=1; event_pc<='0; event_redirect<='0; event_cause<='0;
            
        end else if(boot_pending) begin
            // Sample the external boot address synchronously. A nonconstant
            // asynchronous reset value infers data-controlled latches in Vivado.
            resume_pc<=i_reset_pc; boot_pending<=0;
        end else if (o_flush) begin
            head<='0; tail<='0; scan<='0; count<='0; scanned<='0;
            drain_left<='0; state<=CHECK; stopped<=0; irq_sealed<=0;
            resume_pc<=o_redirect_pc;

        end else begin
            count<=count + (o_allocate_ready ? pushes : COUNT_W'(0)) - COUNT_W'(retire);
            if (incoming_stop) stopped<=1;
            if(!i_interrupt) irq_sealed<=0;
            if (o_allocate_ready) begin
                logic [SLOT_W-1:0] cursor;
                cursor=tail;
                for(int lane=0;lane<LANES;lane++) if(i_allocate[lane]) begin
                    if(i_exception[lane]) stopped<=1;
                    cursor=step(cursor);
                end
                tail<=cursor;
            end
            case(state)
                CHECK: begin
                    if(count==0 && i_interrupt) begin
                        reason<=INTERRUPT; event_pc<=resume_pc; event_cause<='0; state<=EVENT;
                    end else if(scanned<count && entries[scan].valid) begin
                        if(entries[scan].done && (entries[scan].fault || entries[scan].wrong || entries[scan].last)) begin
                            reason<=entries[scan].fault ? FAULT : entries[scan].wrong ? BRANCH : WINDOW;
                            event_pc<=entries[scan].pc; event_redirect<=entries[scan].next_pc;
                            event_cause<=entries[scan].cause;
                            drain_left<=scanned + COUNT_W'(!entries[scan].fault);
                            limit<=entries[scan].fault ? scan : step(scan);
                            state<=DRAIN;
                        end else if(entries[scan].serial && !entries[scan].done && scanned!=0) begin
                            // Establish a precise boundary before a side effect.
                            reason<=SERIAL; drain_left<=scanned; limit<=scan; state<=DRAIN;
                        end else if(entries[scan].done) begin
                            scan<=step(scan); scanned<=scanned+1'b1;
                        end
                    end
                end
                DRAIN: begin
                    if(drain_left==0) state<=EVENT;
                    else if(retire) begin
                        resume_pc<=entries[head].next_pc;
                        head<=step(head); drain_left<=drain_left-1'b1;
                    end
                end
                EVENT: begin
                    if(reason==WINDOW && i_interrupt) begin
                        reason<=INTERRUPT; event_pc<=resume_pc; event_cause<='0;
                    end else begin state<=CHECK; scan<=head; scanned<='0; end
                end
                default: state<=CHECK;
            endcase
            // A finite partial window must not depend on more fetch responses
            // before it can service an interrupt. Stop admission and seal it.
            if(i_interrupt && !irq_sealed && count!=0 && state==CHECK) begin
                irq_sealed<=1;
                // Restart even when CHECK is inspecting the old last row on
                // this edge; its newly set end bit is not visible until next cycle.
                scan<=head; scanned<='0;
            end
            if(i_seal && count!=0) begin
                if(state==CHECK) begin scan<=head; scanned<='0; end
            end
            if(i_store_fault && live(i_store_fault_token) && i_store_fault_token==o_head_token) begin
                stopped<=1; reason<=FAULT; state<=EVENT;
                event_pc<=entries[head].pc; event_cause<=i_store_fault_cause;
            end
        end
    end
    // Separate immutable instruction metadata from frequently changed flags.
    // A completion bank only writes rows of its own parity. No six-port table.
    typedef struct packed {
        logic [PC_W-1:0] pc;
        logic [ARCH_W-1:0] arch;
        logic [PHY_W-1:0] phy;
        logic control, store, writes;
    } info_t;
    info_t info[DEPTH];
    logic [PC_W-1:0] next_address[DEPTH];
    logic [CAUSE_W-1:0] causes[DEPTH];
    for(genvar row=0;row<DEPTH;row++) begin: G_ROW
        localparam int BANK=row%2;
        wire completed=i_complete[BANK] && o_complete_accept[BANK] &&
            i_complete_token[BANK*TOKEN_W +: SLOT_W]==SLOT_W'(row);
        assign entries[row]='{valid:valid_bits[row],done:done_bits[row],fault:fault_bits[row],
            wrong:wrong_bits[row],last:last_bits[row],serial:serial_bits[row],
            control:info[row].control,store:info[row].store,writes:info[row].writes,
            pc:info[row].pc,arch:info[row].arch,phy:info[row].phy,generation:generations[row],
            next_pc:next_address[row],cause:causes[row]};
        // Payloads need no reset; valid_bits protect every consumer.
        always_ff @(posedge clk) if(reset_n && !o_flush) begin
            for(int lane=0;lane<LANES;lane++) if(o_allocate_ready && i_allocate[lane] && alloc_slot[lane]==SLOT_W'(row)) begin
                info[row]<='{pc:i_pc[lane*PC_W +: PC_W],arch:i_arch[lane*ARCH_W +: ARCH_W],
                    phy:i_phy[lane*PHY_W +: PHY_W],control:i_control[lane],store:i_store[lane],
                    writes:i_write[lane] && !i_exception[lane]};
                next_address[row]<=i_predicted_next[lane*PC_W +: PC_W];
                causes[row]<=i_cause[lane*CAUSE_W +: CAUSE_W];
            end
            if(completed) begin
                causes[row]<=i_complete_cause[BANK*CAUSE_W +: CAUSE_W];
                if(info[row].control) next_address[row]<=i_complete_next[BANK*PC_W +: PC_W];
            end
        end
        always_ff @(posedge clk or negedge reset_n) begin
            if(!reset_n) begin
                valid_bits[row]<=0; done_bits[row]<=0; fault_bits[row]<=0; wrong_bits[row]<=0;
                last_bits[row]<=0; serial_bits[row]<=0; generations[row]<='0;
            end else if(o_flush) valid_bits[row]<=0;
            else begin
                for(int lane=0;lane<LANES;lane++) if(o_allocate_ready && i_allocate[lane] && alloc_slot[lane]==SLOT_W'(row)) begin
                    valid_bits[row]<=1; done_bits[row]<=i_exception[lane]; fault_bits[row]<=i_exception[lane];
                    wrong_bits[row]<=0; last_bits[row]<=i_end[lane]; serial_bits[row]<=i_serial[lane];
                    generations[row]<=generations[row]+1'b1;
                end
                if(completed) begin
                    done_bits[row]<=1; fault_bits[row]<=i_complete_fault[BANK];
                    if(info[row].control)
                        wrong_bits[row]<=next_address[row]!=i_complete_next[BANK*PC_W +: PC_W];
                end
                if(i_serial_valid && o_serial_accept && i_serial_token[SLOT_W-1:0]==SLOT_W'(row)) serial_bits[row]<=1;
                if(retire && head==SLOT_W'(row)) valid_bits[row]<=0;
                if(count!=0 && (i_seal || (i_interrupt && !irq_sealed && state==CHECK)) &&
                   (tail==0 ? SLOT_W'(DEPTH-1) : tail-1'b1)==SLOT_W'(row)) last_bits[row]<=1;
            end
        end
    end
    initial if(DEPTH<LANES || LANES<1 || RESULTS!=2) $fatal(1,"Invalid frontier dimensions");
    // synthesis translate_off
    always @(posedge clk) if(reset_n) begin
        assert(int'(count)<=DEPTH) else $fatal(1,"Frontier overflow");
        assert(!(retire && (!entries[head].valid || entries[head].fault))) else $fatal(1,"Invalid retirement");
    end
    // synthesis translate_on
endmodule
