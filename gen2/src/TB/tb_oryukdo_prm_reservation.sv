`timescale 1ns/1ps

// WBC pulses at every pipeline boundary, including a blocked commit stage.
// Scoreboard checks exactly-once notification from the public interface.
module tb_oryukdo_prm_reservation #(
    parameter int DECODE = 2,
    parameter int UPDATES = 1,
    parameter int DEPTH = 3,
    parameter int ROW_DEPTH = 4
);
    localparam int INPUTS = 2*DECODE;
    localparam int PHY_W = 4, IST_W = 7, PAIR_W = PHY_W+IST_W;
    logic clk = 0, reset_n = 0;
    always #5 clk = ~clk;
    logic [INPUTS-1:0] wait_valid = 0;
    logic [INPUTS*PAIR_W-1:0] wait_data = 0;
    logic [4:0] done_valid = 0;
    logic [5*PHY_W-1:0] done_data = 0;
    wire [DECODE-1:0] alloc_valid;
    wire [UPDATES-1:0] ready_valid;
    wire [UPDATES*PAIR_W-1:0] ready_data;
    oryukdo_dependency_mapper #(
        .STRUCT_DECODE_NEW_INST(DECODE), .STRUCT_PHYREGS(16),
        .STRUCT_INST_STATE_ENTRIES(128), .STRUCT_PRM_ENTRY_BUFFER(ROW_DEPTH), .STRUCT_PRM_ENTRY_UPDATE(UPDATES),
        .STRUCT_PRM_INPUT_BUFFER_DEPTH(DEPTH), .STRUCT_PRM_OUTPUT_FIFO_DEPTH(8)
    ) dut (
        .clk(clk), .reset_n(reset_n),
        .i_external_allocate_valid('1), .i_external_allocate_data(allocate_data),
        .i_ist_wait_phyreg_valid(wait_valid), .i_ist_wait_phyreg_data(wait_data),
        .i_wbc_done_phyreg_valid(done_valid), .i_wbc_done_phyreg_data(done_data),
        .i_fcl_unallocate_phyreg_valid('0), .i_fcl_unallocate_phyreg_data('0),
        .o_nel_phyreg_valid(alloc_valid), .i_nel_phyreg_get(allocate_get), .o_nel_phyreg_data(),
        .o_ist_ready_phyreg_valid(ready_valid), .o_ist_ready_phyreg_data(ready_data)
    );
    logic [DECODE-1:0] allocate_get='0;
    logic [DECODE*PHY_W-1:0] allocate_data='0;
    bit pending[128][16], completed[16];
    int sent = 0, received = 0;
    always @(posedge clk) begin
        if (!reset_n) begin
            sent = 0; received = 0;
            for (int p = 0; p < 16; p++) begin
                completed[p] = (p == 0);
                for (int s = 0; s < 128; s++) pending[s][p] = 0;
            end
        end else begin
            for(int lane=0;lane<DECODE;lane++) if(allocate_get[lane] && alloc_valid[lane])
                completed[int'(allocate_data[lane*PHY_W +: PHY_W])]=0;
            for (int lane = 0; lane < INPUTS; lane++) begin
                if (wait_valid[lane]) begin
                    automatic int p = int'(wait_data[lane*PAIR_W +: PHY_W]);
                    automatic int s = int'(wait_data[lane*PAIR_W+PHY_W +: IST_W]);
                    automatic bit duplicate = 0;
                    for (int prev = 0; prev < lane; prev++)
                        if (wait_valid[prev] && wait_data[prev*PAIR_W +: PAIR_W] == wait_data[lane*PAIR_W +: PAIR_W]) duplicate = 1;
                    if (!duplicate) begin
                        if (pending[s][p]) $fatal(1, "Test reused pending pair");
                        pending[s][p] = 1; sent++;
                    end
                end
            end
            for (int lane = 0; lane < 5; lane++)
                if (done_valid[lane]) completed[int'(done_data[lane*PHY_W +: PHY_W])] = 1;
            for (int lane = 0; lane < UPDATES; lane++) begin
                if (ready_valid[lane]) begin
                    automatic int p = int'(ready_data[lane*PAIR_W +: PHY_W]);
                    automatic int s = int'(ready_data[lane*PAIR_W+PHY_W +: IST_W]);
                    if (!pending[s][p] || !completed[p]) $fatal(1, "Duplicate/early notification IST=%0d PHY=%0d", s, p);
                    pending[s][p] = 0; received++;
                end
            end
        end
    end
    task automatic step;
        @(posedge clk); #1; @(negedge clk);
    endtask
    task automatic pair(input int lane, input int s, input int p);
        wait_valid[lane] = 1;
        wait_data[lane*PAIR_W +: PAIR_W] = {IST_W'(s), PHY_W'(p)};
    endtask
    task automatic pulse(input int p);
        done_valid = 1; done_data = (5*PHY_W)'(p);
        step(); done_valid = 0;
    endtask
    task automatic drain;
        for (int t = 0; t < 500; t++) begin
            if (received == sent) begin
                repeat (12) step(); // Detect late duplicates too.
                return;
            end
            step();
        end
        $fatal(1, "Lost completion sent=%0d received=%0d", sent, received);
    endtask
    task automatic offer;
        // Valid-only IST requests obey the upstream occupancy reservation.
        for(int t=0;t<1000;t++) begin
            if(&alloc_valid) return;
            step();
        end
        $fatal(1,"PRM offer timeout");
    endtask
    task automatic new_life(input int p);
        for(int s=0;s<128;s++) if(pending[s][p]) $fatal(1,"Reused live test register");
        offer();allocate_get=1;allocate_data=(DECODE*PHY_W)'(p);step();allocate_get=0;
    endtask
    initial begin
        repeat(3) step();reset_n=1;repeat(10) step();
        // One-cycle WBC before capture, during preprocess/reservation/commit,
        // and after commit. Reuse the row only after all notifications arrived.
        for(int offset=-1;offset<=5;offset++) begin
            new_life(1);
            if(offset==-1) pulse(1);
            for(int lane=0;lane<INPUTS;lane++) pair(lane,lane%2,1);
            if(offset==0) begin done_valid=1;done_data=(5*PHY_W)'(1);end
            step();wait_valid=0;done_valid=0;
            if(offset>0) begin repeat(offset-1) step();pulse(1);end
            drain();
        end
        // Fill one row, then hold a mixed bundle until WBC frees/bypasses it.
        new_life(6);new_life(7);new_life(8);
        for(int s=0;s<ROW_DEPTH;s++) begin offer();pair(0,s,6);step();wait_valid=0;end
        repeat(20) step();
        offer();pair(0,ROW_DEPTH,6);pair(1,ROW_DEPTH+1,7);step();wait_valid=0;
        offer();pair(0,ROW_DEPTH+2,8);step();wait_valid=0;
        repeat(8) step();
        if(!dut.map_stage_valid || dut.plan_valid || dut.input_fire) $fatal(1,"Missing capacity-stall coverage");
        pulse(7);pulse(8);repeat(8) step();
        if(!pending[ROW_DEPTH+1][7] || !pending[ROW_DEPTH+2][8]) $fatal(1,"Bypassed blocked input bundle");
        pulse(6);drain();
        // Keep existing waiters while a new one is reserved, then complete on
        // the reservation edge. Both old and new waiters must drain once.
        new_life(9);
        pair(0,20,9);step();wait_valid=0;repeat(8) step();
        pair(0,21,9);step();wait_valid=0;
        begin
            bit found;found=0;
            for(int t=0;t<100;t++) begin if(dut.plan_capture) begin found=1;break;end step();end
            if(!found) $fatal(1,"Missing reservation-edge WBC coverage");
        end
        pulse(9);drain();
        // Reset while a write plan owns its row. No old map/notification escapes.
        new_life(10);pair(0,22,10);step();wait_valid=0;
        begin
            bit found;found=0;
            for(int t=0;t<100;t++) begin if(dut.plan_valid) begin found=1;break;end step();end
            if(!found) $fatal(1,"Missing reserved-plan reset coverage");
        end
        reset_n=0;step();reset_n=1;pulse(10);repeat(20) step();
        pair(0,23,10);step();wait_valid=0;drain();
        // Ready traffic outruns a narrow output. Plans must wait without
        // overwriting the notification buffer or starving a late WBC.
        new_life(11);new_life(12);pulse(11);
        for(int batch=0;batch<20;batch++) begin
            offer();
            for(int lane=0;lane<INPUTS;lane++) pair(lane,batch*INPUTS+lane,11);
            step();wait_valid=0;
        end
        offer();pair(0,120,11);pair(1,121,12);step();wait_valid=0;
        // Wait for the final mixed bundle to reach its immutable write plan.
        begin
            bit found;found=0;
            for(int t=0;t<1000;t++) begin
                if(dut.plan_valid && dut.wait_input_phyreg[1]==12) begin found=1;break;end
                step();
            end
            if(!found) $fatal(1,"Missing mixed ready/unready plan");
        end
        pulse(12);drain();
        if(DECODE>1 && held_plans==0) $fatal(1,"Missing notification-backpressure coverage");
        $display("tb_oryukdo_prm_reservation PASS D=%0d U=%0d input=%0d row=%0d held_plans=%0d",DECODE,UPDATES,DEPTH,ROW_DEPTH,held_plans);
        $finish;
    end
    int held_plans=0;
    always @(posedge clk) if(reset_n && dut.plan_valid && !dut.input_fire) held_plans++;
    initial begin #1000000; $fatal(1,"Reservation watchdog"); end
endmodule
