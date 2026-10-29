`timescale 1ns/1ps
// Observe public retirement/head/flush handshakes, not internal FSM encodings.
module tb_oryukdo_frontier #(
    parameter int DEPTH=4,
    parameter int TEST=0, // 0: ordered boundaries, 1: stable-token acceptance
    localparam int SLOT_W=$clog2(DEPTH), TOKEN_W=SLOT_W+8
) ();
    logic clk=0, reset_n=0, i_seal=0;
    logic i_allocate=0, i_end=0, i_control=0, i_store=0, i_serial=0;
    logic i_write=0, i_exception=0;
    logic [31:0] i_pc=0, i_predicted_next=0;
    logic [4:0] i_arch=0, i_cause=0;
    logic [5:0] i_phy=0;
    logic [1:0] i_complete=0, i_complete_fault=0;
    logic [2*TOKEN_W-1:0] i_complete_token=0;
    logic [9:0] i_complete_cause=0;
    logic [63:0] i_complete_next=0;
    logic i_serial_valid=0, i_store_fault=0, i_commit_ready=1, i_interrupt=0;
    logic [TOKEN_W-1:0] i_serial_token=0, i_store_fault_token=0;
    logic [4:0] i_store_fault_cause=0;
    logic [31:0] i_trap_vector=32'h20000, i_reset_pc=32'h10000;
    wire o_allocate_ready, o_serial_accept, o_head_valid, o_commit_valid;
    wire o_commit_store, o_commit_write, o_flush, o_trap, o_trap_interrupt;
    wire o_boundary, o_stopped;
    wire [TOKEN_W-1:0] o_allocate_token, o_head_token, o_commit_token;
    wire [1:0] o_complete_accept;
    wire [11:0] o_complete_phy;
    wire [4:0] o_commit_arch, o_trap_cause;
    wire [5:0] o_commit_phy;
    wire [31:0] o_redirect_pc, o_trap_pc;
    wire [$clog2(DEPTH+1)-1:0] o_count;
    oryukdo_frontier #(.DEPTH(DEPTH),.LANES(1),.GEN_W(8)) dut(.*);

    task automatic tick;
        #2; clk=1; #2; clk=0; #2;
    endtask
    task automatic reset;
        reset_n=0; i_allocate=0; i_complete=0; i_interrupt=0;
        i_serial_valid=0; i_store_fault=0; i_commit_ready=1;
        tick(); reset_n=1; tick();
    endtask
    task automatic allocate(input bit last, control, serial,
                            input int pc, output logic [TOKEN_W-1:0] token);
        i_allocate=1; i_end=last; i_control=control; i_serial=serial;
        i_pc=32'(pc); i_predicted_next=32'(pc+4); #1;
        if(!o_allocate_ready) $fatal(1,"Allocation unexpectedly blocked");
        token=o_allocate_token; tick(); i_allocate=0;
    endtask
    task automatic complete(input logic [TOKEN_W-1:0] token,
                            input int next_pc, input bit fault);
        int bank;
        bank=int'(token[SLOT_W-1:0])%2;
        i_complete=2'(1<<bank);
        i_complete_token[bank*TOKEN_W +: TOKEN_W]=token;
        i_complete_next[bank*32 +: 32]=32'(next_pc);
        i_complete_fault[bank]=fault; i_complete_cause[bank*5 +: 5]=5'd5;
        #1; if(!o_complete_accept[bank]) $fatal(1,"Completion rejected");
        tick(); i_complete=0; i_complete_fault=0;
    endtask
    task automatic boundaries;
        logic [TOKEN_W-1:0] older, younger;
        bit retired, flushed, boundary, allowed, commit;
        // Interrupt, redirect, ordinary window, serial prefix, precise fault.
        for(int mode=0;mode<5;mode++) begin
            reset();
            allocate(mode!=3,mode==1,0,'h10000,older);
            allocate(1,0,1,'h10004,younger);
            complete(older,mode==1?'h11000:'h10004,mode==4);
            retired=0; flushed=0; boundary=0; allowed=0;
            // Retirement backpressure must leave the younger operation blocked.
            i_commit_ready=0;
            repeat(mode==4 ? 0 : 4) begin
                if(o_head_valid && o_head_token==younger)
                    $fatal(1,"Younger side effect bypassed stalled retirement");
                tick();
            end
            i_commit_ready=1;
            for(int n=0;n<40;n++) begin
                #1;
                if(o_head_valid && o_head_token==younger) begin
                    if(mode==0 || mode==1 || mode==4)
                        $fatal(1,"Younger ordered side effect escaped boundary mode=%0d",mode);
                    if(!retired || (mode==2 && !boundary))
                        $fatal(1,"Ordered execution preceded retirement/window event");
                    allowed=1; break;
                end
                if(o_boundary) boundary=1;
                if(o_flush) begin
                    flushed=1;
                    if(mode==0 && (!o_trap_interrupt || o_trap_pc!=32'h10004))
                        $fatal(1,"Interrupt boundary PC/type lost");
                    if(mode==1 && (o_trap || o_redirect_pc!=32'h11000))
                        $fatal(1,"Branch redirect lost");
                    if(mode==4 && (!o_trap || o_trap_interrupt || o_trap_cause!=5))
                        $fatal(1,"Precise fault lost");
                    break;
                end
                commit=o_commit_valid; tick();
                if(commit) begin
                    retired=1;
                    // Interrupt arriving exactly after the last older retirement.
                    if(mode==0) i_interrupt=1;
                end
            end
            if(mode==2 || mode==3) begin
                if(!allowed || flushed) $fatal(1,"Normal ordered operation did not resume");
                complete(younger,'h10008,0);
                repeat(12) tick();
                if(o_count!=0) $fatal(1,"Normal serial operation did not retire");
            end else if(!flushed || (mode!=4 && !retired))
                $fatal(1,"Boundary did not finish mode=%0d",mode);
        end
    endtask
    task automatic stable_token;
        logic [TOKEN_W-1:0] token;
        reset();
        // Set once before allocation. Only the DUT's valid/generation changes.
        i_serial_token=TOKEN_W'(1<<SLOT_W); #1;
        if(o_serial_accept) $fatal(1,"Unallocated token accepted");
        allocate(1,0,0,'h10000,token);
        if(token!=i_serial_token || !o_serial_accept)
            $fatal(1,"Stable token not accepted after allocation");
        complete(token,'h10004,0); repeat(12) tick();
        if(o_serial_accept || o_count!=0) $fatal(1,"Retired stable token still accepted");
        reset();
        if(o_serial_accept) $fatal(1,"Reset token accepted");
        allocate(1,1,0,'h10000,token);
        if(!o_serial_accept) $fatal(1,"Stable token not accepted after reset/reallocation");
        complete(token,'h11000,0); repeat(12) tick();
        if(o_serial_accept || o_count!=0) $fatal(1,"Flushed token still accepted");
        allocate(1,0,0,'h11000,token);
        if(token==i_serial_token || o_serial_accept) $fatal(1,"Stale generation accepted on slot reuse");
        i_serial_token=token; #1;
        if(!o_serial_accept) $fatal(1,"New generation rejected");
        if(DEPTH!=(1<<SLOT_W)) begin
            i_serial_token=TOKEN_W'((1<<SLOT_W)|DEPTH); #1;
            if(o_serial_accept) $fatal(1,"Out-of-range slot accepted");
        end
    endtask
    initial begin
        if(TEST==0) boundaries(); else stable_token();
        $display("tb_oryukdo_frontier PASS TEST=%0d DEPTH=%0d",TEST,DEPTH);
        $finish;
    end
    initial begin #100000; $fatal(1,"Frontier test timeout"); end
endmodule
