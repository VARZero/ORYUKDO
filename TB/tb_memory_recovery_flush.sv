`timescale 1ns/1ps
module tb_memory_recovery_flush;
    localparam int KEY_W=10, AGE_W=8, ADDR_W=16, DATA_W=16, MASK_W=2, RD_W=3, OP_W=2;
    localparam int NEL_W=KEY_W+2+OP_W+ADDR_W+RD_W*3+2;
    localparam int PAYLOAD_W=1+ADDR_W+DATA_W+MASK_W+RD_W+OP_W;
    logic clk=0;
    always #5 clk=~clk;
    logic reset_n=0, nel_valid=0, agu_valid=0, req_get=0, resp_valid=0;
    logic flush_valid=0;
    logic [AGE_W-1:0] nel_age=0, flush_age=0, agu_age=0;
    logic [NEL_W-1:0] nel_data=0;
    logic [KEY_W-1:0] agu_key=0;
    logic [PAYLOAD_W-1:0] agu_payload=0;
    wire nel_ready, agu_get, req_valid, resp_ready, complete_valid;
    wire [KEY_W-1:0] req_key, complete_key;
    wire [PAYLOAD_W-1:0] req_payload;
    wire [RD_W-1:0] complete_rd;
    wire [DATA_W-1:0] complete_data;
    memory_order_queue #(.FLOW_PC_WIDTH(KEY_W), .ADDRESS_WIDTH(ADDR_W),
        .DATA_WIDTH(DATA_W), .MASK_WIDTH(MASK_W), .PHYREG_WIDTH(RD_W),
        .MICROOP_WIDTH(OP_W), .OPERANDS(2), .EXPATH_WIDTH(2), .MEMORY_PATH(2),
        .NEL_LANES(1), .DEPTH(4), .AGE_WIDTH(AGE_W),
        .ENABLE_RECOVERY_FLUSH(1'b1)) dut (
        .clk(clk), .reset_n(reset_n), .i_nel_valid(nel_valid),
        .i_nel_data(nel_data), .i_nel_age(nel_age), .o_nel_ready(nel_ready),
        .i_flush_valid(flush_valid), .i_flush_age(flush_age),
        .i_agu_valid(agu_valid), .o_agu_get(agu_get),
        .i_agu_key(agu_key), .i_agu_age(agu_age), .i_agu_payload(agu_payload),
        .o_mem_req_valid(req_valid), .i_mem_req_get(req_get),
        .o_mem_req_key(req_key), .o_mem_req_payload(req_payload),
        .i_store_commit_valid(1'b0), .i_store_commit_key('0),
        .i_mem_resp_valid(resp_valid), .i_mem_resp_data(DATA_W'(0)),
        .o_mem_resp_ready(resp_ready), .o_mem_complete_valid(complete_valid),
        .o_mem_complete_key(complete_key), .o_mem_complete_rd(complete_rd),
        .o_mem_complete_store(),
        .o_mem_complete_data(complete_data)
    );
    task automatic enqueue(input [KEY_W-1:0] key, input [AGE_W-1:0] age);
        @(negedge clk);
        nel_data='0; nel_data[0 +: KEY_W]=key;
        nel_data[KEY_W +: 2]=2'd2;
        nel_age=age; nel_valid=1;
        @(negedge clk); nel_valid=0;
    endtask
    task automatic agu(input [KEY_W-1:0] key);
        @(negedge clk);
        agu_key=key;
        agu_age=AGE_W'(key-10'h100);
        agu_payload={1'b0,ADDR_W'(key),DATA_W'(key),MASK_W'(3),RD_W'(0),OP_W'(1)};
        #1; if (!agu_get) $fatal(1,"AGU key %h rejected",key);
        agu_valid=1;
        @(negedge clk); agu_valid=0;
    endtask
    task automatic request(input [KEY_W-1:0] key);
        @(negedge clk);
        #1;
        if (!req_valid || req_key!=key) $fatal(1,"expected request %h got %h valid=%b",key,req_key,req_valid);
        req_get=1;
        @(negedge clk); req_get=0;
    endtask
    initial begin
        repeat(2) @(negedge clk); reset_n=1;
        enqueue(10'h101,8'd1);
        enqueue(10'h102,8'd2);
        enqueue(10'h103,8'd3);
        agu(10'h103);
        agu(10'h102);
        agu(10'h101);
        request(10'h101);
        @(negedge clk); flush_age=8'd2; flush_valid=1;
        #1; if (req_valid) $fatal(1,"request during flush");
        @(negedge clk); flush_valid=0;
        resp_valid=1; #1;
        if (!complete_valid || complete_key!=10'h101) $fatal(1,"older response lost");
        @(negedge clk); resp_valid=0;
        request(10'h102);
        @(negedge clk); flush_age=8'd1; flush_valid=1;
        @(negedge clk); flush_valid=0;
        resp_valid=1; #1;
        if (complete_valid || !resp_ready) $fatal(1,"squashed load response entered WBC");
        @(negedge clk); resp_valid=0;
        repeat(2) @(negedge clk);
        if (req_valid || dut.order_count!=0 || dut.ready_count!=0)
            $fatal(1,"younger B/A entries survived flush");
        agu_key=10'h103; #1;
        if (agu_get) $fatal(1,"stale AGU result accepted");
        enqueue(10'h103,8'd4);
        agu_age=8'd3; #1;
        if (agu_get) $fatal(1,"old generation accepted at reused key");
        agu_age=8'd4; #1;
        if (!agu_get) $fatal(1,"live generation rejected at reused key");
        $display("tb_memory_recovery_flush PASS");
        $finish;
    end
endmodule
