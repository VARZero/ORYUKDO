`timescale 1ns/1ps
module tb_memory_store_commit;
    localparam int KEY_W=10, ADDR_W=16, DATA_W=16, MASK_W=2, RD_W=3, OP_W=2;
    localparam int NEL_W=KEY_W+2+OP_W+ADDR_W+RD_W*3+2;
    localparam int PAYLOAD_W=1+ADDR_W+DATA_W+MASK_W+RD_W+OP_W;
    logic clk=0;
    always #5 clk=~clk;
    logic reset_n=0, nel_valid=0, agu_valid=0, req_get=0, resp_valid=0;
    logic commit_valid=0;
    logic [KEY_W-1:0] commit_key=0;
    logic [NEL_W-1:0] nel_data=0;
    logic [PAYLOAD_W-1:0] agu_payload=0;
    wire nel_ready, agu_get, req_valid, resp_ready, complete_valid;
    wire [KEY_W-1:0] req_key, complete_key;
    wire [PAYLOAD_W-1:0] req_payload;
    wire [RD_W-1:0] complete_rd;
    wire [DATA_W-1:0] complete_data;

    memory_order_queue #(.FLOW_PC_WIDTH(KEY_W), .ADDRESS_WIDTH(ADDR_W),
        .DATA_WIDTH(DATA_W), .MASK_WIDTH(MASK_W), .PHYREG_WIDTH(RD_W),
        .MICROOP_WIDTH(OP_W), .OPERANDS(2), .EXPATH_WIDTH(2), .MEMORY_PATH(2),
        .NEL_LANES(1), .DEPTH(4), .ENABLE_STORE_COMMIT(1'b1)) dut (
        .clk(clk), .reset_n(reset_n),
        .i_nel_valid(nel_valid), .i_nel_data(nel_data), .o_nel_ready(nel_ready),
        .i_nel_age('0), .i_flush_valid(1'b0), .i_flush_age('0),
        .i_agu_valid(agu_valid), .o_agu_get(agu_get),
        .i_agu_age('0), .i_agu_key(10'h101), .i_agu_payload(agu_payload),
        .o_mem_req_valid(req_valid), .i_mem_req_get(req_get),
        .o_mem_req_key(req_key), .o_mem_req_payload(req_payload),
        .i_store_commit_valid(commit_valid), .i_store_commit_key(commit_key),
        .i_mem_resp_valid(resp_valid), .i_mem_resp_data(DATA_W'(0)),
        .o_mem_resp_ready(resp_ready), .o_mem_complete_valid(complete_valid),
        .o_mem_complete_key(complete_key), .o_mem_complete_rd(complete_rd),
        .o_mem_complete_store(),
        .o_mem_complete_data(complete_data)
    );
    initial begin
        repeat(2) @(negedge clk); reset_n=1;
        nel_data[0 +: KEY_W] = 10'h101;
        nel_data[KEY_W +: 2] = 2'd2;
        nel_valid=1;
        @(negedge clk); nel_valid=0;
        agu_payload={1'b1,ADDR_W'(16'h100),DATA_W'(16'hbeef),MASK_W'(3),RD_W'(0),OP_W'(1)};
        agu_valid=1;
        #1; if (!agu_get) $fatal(1,"AGU blocked");
        @(negedge clk); agu_valid=0;
        repeat(3) @(negedge clk);
        if (req_valid) $fatal(1,"speculative store escaped");
        commit_valid=1; commit_key=10'h102;
        #1; if (req_valid) $fatal(1,"wrong key granted store");
        commit_key=10'h101;
        #1; if (!req_valid || req_key!=10'h101) $fatal(1,"committed store blocked");
        req_get=1;
        @(negedge clk); req_get=0; commit_valid=0;
        if (!resp_ready) $fatal(1,"committed store did not enter memory");
        resp_valid=1;
        #1; if (!complete_valid || complete_key!=10'h101) $fatal(1,"store completion missing");
        $display("tb_memory_store_commit PASS");
        $finish;
    end
endmodule
