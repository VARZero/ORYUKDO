`timescale 1ns/1ps
// Exercise realistic decoder widths and EX completion order with recovery enabled.
module tb_recovery_width_matrix #(
    parameter int DECODE_LANES = 3,
    parameter int ENTRY_DEPTH = 16,
    parameter bit MEMORY_ORDER = 0,
    parameter bit COMPACT_EX = 0
);
    localparam int EX_CORES = COMPACT_EX ? 3 : 5;
    localparam int RS_OUT[3] = COMPACT_EX ? '{1,1,1} : '{1,3,1};
    localparam int EX_RESULTS[EX_CORES] = '{default:1};
    logic clk = 0;
    always #5 clk = ~clk;
    logic reset_n = 0;
    logic [DECODE_LANES-1:0] i_im_req_pc_get = 0;
    wire [DECODE_LANES-1:0] o_im_req_pc_valid;
    wire [DECODE_LANES*35-1:0] o_im_req_pc;
    logic [DECODE_LANES-1:0] i_im_recv_inst_valid = 0;
    wire [DECODE_LANES-1:0] o_im_recv_inst_get;
    logic [DECODE_LANES*35-1:0] i_im_recv_pc = 0;
    logic [DECODE_LANES*32-1:0] i_im_recv_inst = 0;
    logic [DECODE_LANES-1:0] i_nel_decode_exception = 0;
    logic [DECODE_LANES*2-1:0] i_nel_decode_expath = 0;
    logic [DECODE_LANES*5-1:0] i_nel_decode_microop = 0;
    logic [DECODE_LANES*5-1:0] i_nel_decode_rd = 0;
    logic [DECODE_LANES-1:0] i_nel_decode_newreg = 0;
    logic [DECODE_LANES*10-1:0] i_nel_decode_rs = 0;
    logic [DECODE_LANES*32-1:0] i_nel_decode_imm = 0;
    logic [DECODE_LANES-1:0] i_nel_decode_jump = 0;
    logic [DECODE_LANES-1:0] i_nel_decode_jump_reg = 0;
    logic [DECODE_LANES-1:0] i_nel_decode_branch = 0;
    wire [EX_CORES-1:0] o_rs_entry_valid;
    logic [EX_CORES-1:0] i_rs_entry_get = '1;
    wire [EX_CORES*92-1:0] o_rs_entry_data;
    wire [EX_CORES*32-1:0] o_rs_entry_age;
    logic [EX_CORES-1:0] i_wbc_result_valid = 0;
    wire [EX_CORES*41-1:0] i_wbc_result_data;
    wire [EX_CORES*32-1:0] i_wbc_result_age;
    wire [EX_CORES-1:0] o_wbc_result_accept;
    logic i_wbc_result_branch_valid = 0;
    logic [34:0] i_wbc_result_branch_data = 0;
    wire recovery_flush;
    logic [DECODE_LANES-1:0] issued = 0;

    for (genvar lane = 0; lane < EX_CORES; lane++) begin : GEN_EX_RESPONSES
        if (lane < DECODE_LANES) begin : GEN_USED
            assign i_wbc_result_data[lane*41 +: 41] =
                {6'd0,35'(4*(DECODE_LANES-1-lane))};
            assign i_wbc_result_age[lane*32 +: 32] =
                32'(DECODE_LANES-1-lane);
        end else begin : GEN_UNUSED
            assign i_wbc_result_data[lane*41 +: 41] = '0;
            assign i_wbc_result_age[lane*32 +: 32] = '0;
        end
    end

    eulsukdo_scheduler #(
        .STRUCT_DECODE_NEW_INST(DECODE_LANES), .ENABLE_RECOVERY_TRACKING(1'b1),
        .STRUCT_INST_STATE_ENTRIES(ENTRY_DEPTH), .ENABLE_MEMORY_ORDER(MEMORY_ORDER),
        .ENABLE_STORE_COMMIT(MEMORY_ORDER), .STRUCT_RS_OUT_ENTRY(RS_OUT),
        .STRUCT_EX_CORES(EX_CORES), .STRUCT_EX_OUT_RESULT(EX_RESULTS),
        .STRUCT_EX_OUT_RESULT_SUM(EX_CORES)
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
            for (int lane = 0; lane < EX_CORES; lane++) begin
                if (o_rs_entry_valid[lane] && i_rs_entry_get[lane]) begin
                    for (int index = 0; index < DECODE_LANES; index++) begin
                        if (o_rs_entry_data[lane*92 +: 35] == 35'(4*index)) begin
                            if (o_rs_entry_age[lane*32 +: 32] != 32'(index))
                                $fatal(1,"issue age mismatch for instruction %0d",index);
                            if (((index % 2 == 0) && lane != 0) ||
                                ((index % 2 == 1) && (lane < 1 || lane > (COMPACT_EX ? 1 : 3))))
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
        for (int lane = 0; lane < DECODE_LANES; lane++) begin
            i_nel_decode_expath[lane*2 +: 2] = 2'(lane % 2);
            i_nel_decode_microop[lane*5 +: 5] = 5'd1;
        end
        repeat (2) @(negedge clk);
        reset_n = 1'b1;
        i_im_req_pc_get = '1;
        #1;
        if (o_im_req_pc_valid !== {DECODE_LANES{1'b1}})
            $fatal(1,"fetch request unavailable for %0d lanes",DECODE_LANES);
        for (int lane = 0; lane < DECODE_LANES; lane++)
            if (o_im_req_pc[lane*35 +: 35] !== 35'(4*lane))
                $fatal(1,"fetch PC mismatch on lane %0d",lane);
        @(negedge clk);
        i_im_req_pc_get = '0;
        for (int lane = 0; lane < DECODE_LANES; lane++)
            i_im_recv_pc[lane*35 +: 35] = 35'(4*lane);
        i_im_recv_inst_valid = '1;
        accepted = 0;
        for (int cycle = 0; cycle < 100; cycle++) begin
            @(posedge clk);
            if (o_im_recv_inst_get == {DECODE_LANES{1'b1}}) begin
                accepted = 1;
                break;
            end
        end
        if (!accepted) $fatal(1,"decode bundle rejected for %0d lanes",DECODE_LANES);
        #1;
        i_im_recv_inst_valid = '0;
        for (int cycle = 0; cycle < 100 && issued != {DECODE_LANES{1'b1}}; cycle++) @(negedge clk);
        if (issued != {DECODE_LANES{1'b1}}) $fatal(1,"EX paths did not issue all instructions: %b",issued);
        if (dut.GEN_RECOVERY_TRACKING.U_RETIREMENT_FRONTIER.o_count != DECODE_LANES)
            $fatal(1,"frontier lost bundle allocation");
        for (int lane = 0; lane < DECODE_LANES-1; lane++) complete(lane);
        if (dut.GEN_RECOVERY_TRACKING.U_RETIREMENT_FRONTIER.o_count != DECODE_LANES)
            $fatal(1,"younger completions retired before oldest");
        complete(DECODE_LANES-1);
        for (int cycle = 0; cycle < 8; cycle++) @(negedge clk);
        if (dut.GEN_RECOVERY_TRACKING.U_RETIREMENT_FRONTIER.o_count != 0 || recovery_flush)
            $fatal(1,"bundle did not retire in order: count %0d head %0d done %b resolved %b",
                dut.GEN_RECOVERY_TRACKING.U_RETIREMENT_FRONTIER.o_count,
                dut.GEN_RECOVERY_TRACKING.U_RETIREMENT_FRONTIER.head,
                dut.GEN_RECOVERY_TRACKING.U_RETIREMENT_FRONTIER.entry_done,
                dut.GEN_RECOVERY_TRACKING.U_RETIREMENT_FRONTIER.entry_resolved);
        $display("decode=%0d ex=%0d depth=%0d lsq=%0b: routing and ordered retirement passed",
            DECODE_LANES,EX_CORES,ENTRY_DEPTH,MEMORY_ORDER);
        $finish;
    end
endmodule
