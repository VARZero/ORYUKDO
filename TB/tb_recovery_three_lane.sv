`timescale 1ns/1ps
// Exercise a wider decoder bundle and multiple EX paths with recovery enabled.
module tb_recovery_three_lane;
    logic clk = 0;
    always #5 clk = ~clk;
    logic reset_n = 0;
    logic [2:0] i_im_req_pc_get = 0;
    wire [2:0] o_im_req_pc_valid;
    wire [104:0] o_im_req_pc;
    logic [2:0] i_im_recv_inst_valid = 0;
    wire [2:0] o_im_recv_inst_get;
    logic [104:0] i_im_recv_pc = 0;
    logic [95:0] i_im_recv_inst = 0;
    logic [2:0] i_nel_decode_exception = 0;
    logic [5:0] i_nel_decode_expath = {2'd1,2'd1,2'd0};
    logic [14:0] i_nel_decode_microop = {5'd1,5'd1,5'd1};
    logic [14:0] i_nel_decode_rd = 0;
    logic [2:0] i_nel_decode_newreg = 0;
    logic [29:0] i_nel_decode_rs = 0;
    logic [95:0] i_nel_decode_imm = 0;
    logic [2:0] i_nel_decode_jump = 0;
    logic [2:0] i_nel_decode_jump_reg = 0;
    logic [2:0] i_nel_decode_branch = 0;
    wire [4:0] o_rs_entry_valid;
    logic [4:0] i_rs_entry_get = '1;
    wire [459:0] o_rs_entry_data;
    wire [159:0] o_rs_entry_age;
    logic [4:0] i_wbc_result_valid = 0;
    logic [204:0] i_wbc_result_data = 0;
    logic [159:0] i_wbc_result_age = 0;
    wire [4:0] o_wbc_result_accept;
    logic i_wbc_result_branch_valid = 0;
    logic [34:0] i_wbc_result_branch_data = 0;
    wire recovery_flush;
    logic [2:0] issued = 0;

    eulsukdo_scheduler #(
        .STRUCT_DECODE_NEW_INST(3), .ENABLE_RECOVERY_TRACKING(1'b1),
        .STRUCT_INST_STATE_ENTRIES(16)
    ) dut (
        .*, .i_nel_decode_exception_cause('0),
        .o_predict_request_valid(), .o_predict_request_key(),
        .i_predict_valid(1'b0), .i_predict_taken(1'b0), .i_predict_target('0),
        .o_predict_decision_taken(), .o_predict_decision_target(),
        .o_predict_update_valid(), .o_predict_update_key(),
        .o_predict_update_taken(), .o_predict_update_target(),
        .i_recovery_resolve_valid(1'b0), .i_recovery_resolve_key('0),
        .i_recovery_resolve_age('0), .i_recovery_taken(1'b0),
        .i_recovery_target('0), .i_recovery_predicted_taken(1'b0),
        .i_recovery_predicted_target('0), .i_recovery_fault_valid(1'b0),
        .i_recovery_fault_key('0), .i_recovery_fault_age('0),
        .i_recovery_fault_cause('0), .i_recovery_interrupt_pending(1'b0),
        .i_recovery_trap_vector('0), .o_recovery_flush(recovery_flush),
        .o_recovery_flush_key(), .o_recovery_flush_age(),
        .o_recovery_redirect_pc(), .o_recovery_trap_valid(),
        .o_recovery_trap_interrupt(), .o_recovery_trap_pc(),
        .o_recovery_trap_cause(),
        .i_mem_agu_valid(1'b0), .o_mem_agu_get(),
        .i_mem_agu_key('0), .i_mem_agu_age('0), .i_mem_agu_payload('0),
        .o_mem_req_valid(), .i_mem_req_get(1'b0), .o_mem_req_key(),
        .o_mem_req_payload(), .i_store_commit_valid(1'b0),
        .i_store_commit_key('0), .i_mem_resp_valid(1'b0),
        .i_mem_resp_data('0), .o_mem_resp_ready(),
        .o_mem_complete_valid(), .o_mem_complete_key(),
        .o_mem_complete_rd(), .o_mem_complete_data()
    );

    always @(posedge clk) begin
        if (reset_n) begin
            for (int lane = 0; lane < 5; lane++) begin
                if (o_rs_entry_valid[lane] && i_rs_entry_get[lane]) begin
                    for (int index = 0; index < 3; index++) begin
                        if (o_rs_entry_data[lane*92 +: 35] == 35'(4*index)) begin
                            if (o_rs_entry_age[lane*32 +: 32] != 32'(index))
                                $fatal(1,"issue age mismatch for instruction %0d",index);
                            if ((index == 0 && lane != 0) ||
                                (index > 0 && (lane < 1 || lane > 3)))
                                $fatal(1,"instruction %0d issued from wrong EX path %0d",index,lane);
                            issued[index] <= 1'b1;
                        end
                    end
                end
            end
        end
    end

    task automatic complete(input int lane);
        @(negedge clk);
        i_wbc_result_valid[lane] = 1'b1;
        #1;
        if (!o_wbc_result_accept[lane])
            $fatal(1,"live completion rejected: lane %0d",lane);
        if (!dut.ex_wbc_result_valid[lane] || !dut.wbc_fcl_done_pc_valid[lane])
            $fatal(1,"live completion did not enter WBC: lane %0d ex %b wbc %b",
                lane,dut.ex_wbc_result_valid[lane],dut.wbc_fcl_done_pc_valid[lane]);
        @(negedge clk);
        i_wbc_result_valid = '0;
    endtask

    initial begin
        bit accepted;
        i_wbc_result_data[0 +: 41] = {6'd0,35'd8};
        i_wbc_result_data[41 +: 41] = {6'd0,35'd4};
        i_wbc_result_data[82 +: 41] = {6'd0,35'd0};
        i_wbc_result_age[0 +: 32] = 32'd2;
        i_wbc_result_age[32 +: 32] = 32'd1;
        i_wbc_result_age[64 +: 32] = 32'd0;
        repeat (2) @(negedge clk);
        reset_n = 1'b1;
        i_im_req_pc_get = 3'b111;
        #1;
        if (o_im_req_pc_valid !== 3'b111 ||
            o_im_req_pc !== {35'd8,35'd4,35'd0})
            $fatal(1,"three-lane fetch request unavailable");
        @(negedge clk);
        i_im_req_pc_get = '0;
        i_im_recv_pc = {35'd8,35'd4,35'd0};
        i_im_recv_inst_valid = 3'b111;
        accepted = 0;
        for (int cycle = 0; cycle < 100; cycle++) begin
            @(posedge clk);
            if (o_im_recv_inst_get == 3'b111) begin
                accepted = 1;
                break;
            end
        end
        if (!accepted) $fatal(1,"three-lane decode bundle rejected");
        #1;
        i_im_recv_inst_valid = '0;
        for (int cycle = 0; cycle < 100 && issued != 3'b111; cycle++) @(negedge clk);
        if (issued != 3'b111) $fatal(1,"EX paths did not issue all three instructions: %b",issued);
        if (dut.GEN_RECOVERY_TRACKING.U_RETIREMENT_FRONTIER.o_count != 3)
            $fatal(1,"frontier lost three-lane allocation");
        complete(0);
        complete(1);
        if (dut.GEN_RECOVERY_TRACKING.U_RETIREMENT_FRONTIER.o_count != 3)
            $fatal(1,"younger completions retired before oldest");
        complete(2);
        for (int cycle = 0; cycle < 8; cycle++) @(negedge clk);
        if (dut.GEN_RECOVERY_TRACKING.U_RETIREMENT_FRONTIER.o_count != 0 || recovery_flush)
            $fatal(1,"three-lane bundle did not retire in order: count %0d head %0d done %b resolved %b",
                dut.GEN_RECOVERY_TRACKING.U_RETIREMENT_FRONTIER.o_count,
                dut.GEN_RECOVERY_TRACKING.U_RETIREMENT_FRONTIER.head,
                dut.GEN_RECOVERY_TRACKING.U_RETIREMENT_FRONTIER.entry_done,
                dut.GEN_RECOVERY_TRACKING.U_RETIREMENT_FRONTIER.entry_resolved);
        $display("three-lane decode, multiple EX paths and ordered recovery retirement passed");
        $finish;
    end
endmodule
