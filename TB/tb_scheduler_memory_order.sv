`timescale 1ns/1ps
module tb_scheduler_memory_order #(
    parameter bit ENABLE_RECOVERY_TRACKING = 1'b0,
    parameter bit TEST_EXCEPTION = 1'b0,
    parameter bit TEST_STORE = 1'b0,
    parameter bit TEST_BRANCH = 1'b0,
    parameter bit TEST_PREDICTOR = 1'b0
);
`ifdef GEN_TRACE
    initial begin
        $dumpfile("gen_lsq_sample.vcd");
        $dumpvars(0, tb_scheduler_memory_order);
    end
`endif
    logic clk=0;
    always #5 clk=~clk;
    logic reset_n=0;
    logic [1:0] i_im_req_pc_get=0;
    wire [1:0] o_im_req_pc_valid;
    wire [69:0] o_im_req_pc;
    logic [1:0] i_im_recv_inst_valid=0;
    wire [1:0] o_im_recv_inst_get;
    logic [69:0] i_im_recv_pc=0;
    logic [63:0] i_im_recv_inst=0;
    logic [1:0] i_nel_decode_exception=0;
    logic [9:0] i_nel_decode_exception_cause=0;
    logic [3:0] i_nel_decode_expath={2'd2,2'd2};
    logic [9:0] i_nel_decode_microop=0;
    logic [9:0] i_nel_decode_rd=0;
    logic [1:0] i_nel_decode_newreg=0;
    logic [19:0] i_nel_decode_rs=0;
    logic [63:0] i_nel_decode_imm=0;
    logic [1:0] i_nel_decode_jump=0;
    logic [1:0] i_nel_decode_jump_reg=0;
    logic [1:0] i_nel_decode_branch=0;
    wire [4:0] o_rs_entry_valid;
    logic [4:0] i_rs_entry_get=5'b11111;
    wire [459:0] o_rs_entry_data;
    logic [4:0] i_wbc_result_valid=0;
    logic [204:0] i_wbc_result_data=0;
    logic i_wbc_result_branch_valid=0;
    logic [34:0] i_wbc_result_branch_data=0;
    logic i_mem_agu_valid=0;
    wire o_mem_agu_get;
    logic [34:0] i_mem_agu_key=0;
    logic [31:0] i_mem_agu_age=0;
    logic [79:0] i_mem_agu_payload=0;
    wire o_mem_req_valid;
    logic i_mem_req_get=0;
    wire [34:0] o_mem_req_key;
    wire [79:0] o_mem_req_payload;
    logic i_mem_resp_valid=0;
    logic [31:0] i_mem_resp_data=0;
    wire o_mem_resp_ready,o_mem_complete_valid;
    wire [34:0] o_mem_complete_key;
    wire [5:0] o_mem_complete_rd;
    wire [31:0] o_mem_complete_data;
    logic i_store_commit_valid=0;
    logic [34:0] i_store_commit_key=0;
    wire recovery_trap_valid;
    wire [4:0] recovery_trap_cause;
    logic recovery_resolve_valid=0, recovery_interrupt_pending=0;
    wire recovery_flush;
    wire [31:0] recovery_redirect_pc, recovery_trap_pc;

    eulsukdo_scheduler #(.ENABLE_MEMORY_ORDER(1'b1),
        .ENABLE_RECOVERY_TRACKING(ENABLE_RECOVERY_TRACKING),
        .ENABLE_EXTERNAL_PREDICTOR(TEST_PREDICTOR),
        .ENABLE_STORE_COMMIT(ENABLE_RECOVERY_TRACKING),
        .STRUCT_INST_STATE_ENTRIES(8),
        .STRUCT_FLOW_PC_MAX_RANGE(4)) dut (
        .*, .o_rs_entry_age(), .i_wbc_result_age('0), .o_wbc_result_accept(),
        .o_predict_request_valid(), .o_predict_request_key(),
        .i_predict_valid(TEST_PREDICTOR), .i_predict_taken(TEST_PREDICTOR), .i_predict_target(32'h80),
        .o_predict_decision_taken(), .o_predict_decision_target(),
        .o_predict_update_valid(), .o_predict_update_key(),
        .o_predict_update_taken(), .o_predict_update_target(),
        .i_recovery_resolve_valid(recovery_resolve_valid), .i_recovery_resolve_age('0), .i_recovery_resolve_key(35'd0),
        .i_recovery_taken(1'b1), .i_recovery_target(32'h80),
        .i_recovery_predicted_taken(1'b1), .i_recovery_predicted_target(32'h80),
        .i_recovery_fault_valid(1'b0), .i_recovery_fault_age('0), .i_recovery_fault_key('0), .i_recovery_fault_cause('0),
        .i_recovery_interrupt_pending(recovery_interrupt_pending), .i_recovery_trap_vector(32'hf0),
        .o_recovery_flush(recovery_flush), .o_recovery_flush_key(), .o_recovery_flush_age(),
        .o_recovery_redirect_pc(recovery_redirect_pc), .o_recovery_trap_valid(recovery_trap_valid),
        .o_recovery_trap_interrupt(), .o_recovery_trap_pc(recovery_trap_pc), .o_recovery_trap_cause(recovery_trap_cause));

    task automatic send_agu(input logic [34:0] key);
        @(negedge clk);
        i_mem_agu_key=key;
        i_mem_agu_age=(key==35'd0) ? 32'd0 : 32'd1;
        i_mem_agu_payload={TEST_STORE && key==35'd0,32'(key),32'd0,4'hf,6'd0,5'd1};
        #1;
        if (!o_mem_agu_get) $fatal(1,"scheduler LSQ did not accept AGU key %0d",key);
        i_mem_agu_valid=1;
        @(negedge clk);
        i_mem_agu_valid=0;
    endtask
    task automatic finish_request(input logic [34:0] key);
        bit found=0;
        for(int cycle=0;cycle<32;cycle++) begin
            @(negedge clk);
            if(o_mem_req_valid) begin found=1;break;end
        end
        if(!found||o_mem_req_key!==key) $fatal(1,"memory issue expected key %0d got %0d",key,o_mem_req_key);
        i_mem_req_get=1;
        @(negedge clk);
        i_mem_req_get=0;
        i_mem_resp_valid=1;
        i_mem_resp_data=32'(key)+32'h100;
        #1;
        if(!o_mem_complete_valid || o_mem_complete_key!==key ||
           !dut.ex_wbc_result_valid[4] || dut.ex_wbc_result_data[4*41 +: 35]!==key)
            $fatal(1,"memory completion did not reach WBC");
        @(negedge clk);
        i_mem_resp_valid=0;
    endtask

    initial begin
        bit accepted;
        bit first_seen, second_seen;
        accepted=0;
        first_seen=0;
        second_seen=0;
        repeat(2) @(posedge clk);
        #1;
        reset_n=1;
        i_im_req_pc_get=2'b11;
        #1;
        if(o_im_req_pc_valid!==2'b11) $fatal(1,"fetch unavailable valid=%b PC=%h reset=%b",o_im_req_pc_valid,o_im_req_pc,reset_n);
        @(negedge clk);
        i_im_req_pc_get=0;
        i_im_recv_inst_valid=(TEST_EXCEPTION || TEST_BRANCH) ? 2'b01 : 2'b11;
        i_nel_decode_exception=TEST_EXCEPTION ? 2'b01 : 2'b00;
        i_nel_decode_branch=TEST_BRANCH ? 2'b01 : 2'b00;
        if (TEST_BRANCH) i_nel_decode_expath[1:0]=2'd0;
        i_nel_decode_exception_cause=TEST_EXCEPTION ? 10'd7 : 10'd0;
        i_im_recv_pc={35'd4,35'd0};
        for(int cycle=0;cycle<100;cycle++) begin
            @(posedge clk);
            if((o_im_recv_inst_get & i_im_recv_inst_valid)==i_im_recv_inst_valid) begin
                accepted=1;break;
            end
        end
        if(!accepted) $fatal(1,"NEL did not accept memory pair");
        #1;i_im_recv_inst_valid=0;
        if (TEST_BRANCH) begin
            bit found=0;
            for (int cycle=0;cycle<60;cycle++) begin
                @(negedge clk);
                if (dut.recovery_admit[0]) begin
                    found=1; break;
                end
            end
            if (!found) $fatal(1,"branch did not enter retirement frontier");
            @(negedge clk);
            if (!o_im_req_pc_valid[0] || o_im_req_pc[0 +: 32] !=
                (TEST_PREDICTOR ? 32'h80 : 32'd4))
                $fatal(1,"predictor decision did not redirect fetch");
            i_wbc_result_valid[0]=1;
            i_wbc_result_data[0 +: 35]=35'd0;
            recovery_resolve_valid=1;
            @(negedge clk);
            i_wbc_result_valid=0;
            recovery_resolve_valid=0;
            #1;
            if (TEST_PREDICTOR) begin
                if (recovery_flush) $fatal(1,"matching external prediction recovered");
            end else if (!recovery_flush || recovery_redirect_pc!=32'h80 || recovery_trap_valid)
                $fatal(1,"stored static prediction did not cause branch recovery");
            @(negedge clk);
            recovery_interrupt_pending=1;
            #1;
            if (!recovery_trap_valid || recovery_redirect_pc!=32'hf0 || recovery_trap_pc!=32'h80)
                $fatal(1,"interrupt did not enter at empty frontier");
            $display("scheduler branch prediction, recovery and interrupt PASS");
            $finish;
        end
        if (TEST_EXCEPTION) begin
            bit seen_trap=0;
            for (int cycle=0; cycle<30; cycle++) begin
                @(negedge clk);
                if (|o_rs_entry_valid) $fatal(1,"decode exception executed");
                if (recovery_trap_valid) begin
                    if (recovery_trap_cause!=5'd7) $fatal(1,"exception cause lost");
                    seen_trap=1; break;
                end
            end
            if (!seen_trap) $fatal(1,"decode exception never reached retirement");
            $display("scheduler decode exception reaches retirement without EX PASS");
            $finish;
        end
        for(int cycle=0;cycle<100;cycle++) begin
            @(posedge clk);
            if(o_rs_entry_valid[4]) begin
                if(o_rs_entry_data[4*92 +: 35]==35'd0) first_seen=1;
                if(o_rs_entry_data[4*92 +: 35]==35'd4) second_seen=1;
            end
            if(first_seen&&second_seen) break;
        end
        if(!first_seen||!second_seen) $fatal(1,"memory RS output not observed");
        send_agu(35'd4);
        repeat(4) @(negedge clk);
        if(o_mem_req_valid) $fatal(1,"younger memory instruction issued early");
        send_agu(35'd0);
        finish_request(35'd0);
        finish_request(35'd4);
        $display("scheduler NEL -> Memory RS -> AGU -> ordered request -> WBC passed");
        $finish;
    end
endmodule
