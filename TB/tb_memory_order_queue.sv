`timescale 1ns/1ps
module tb_memory_order_queue;
    localparam int KEY_W=10, ADDR_W=16, DATA_W=16, MASK_W=2, RD_W=3, OP_W=2;
    localparam int NEL_W=KEY_W+2+OP_W+ADDR_W+RD_W*3+2;
    localparam int PAYLOAD_W=1+ADDR_W+DATA_W+MASK_W+RD_W+OP_W;
    logic clk=0;
    always #5 clk=~clk;
    logic reset_n=0;
    logic [1:0] i_nel_valid=0;
    logic [2*NEL_W-1:0] i_nel_data=0;
    wire o_nel_ready;
    logic i_agu_valid=0;
    wire o_agu_get;
    logic [KEY_W-1:0] i_agu_key=0;
    logic [PAYLOAD_W-1:0] i_agu_payload=0;
    wire o_mem_req_valid;
    logic i_mem_req_get=0;
    wire [KEY_W-1:0] o_mem_req_key;
    wire [PAYLOAD_W-1:0] o_mem_req_payload;
    logic i_store_commit_valid=0;
    logic [KEY_W-1:0] i_store_commit_key=0;
    logic i_mem_resp_valid=0;
    logic [DATA_W-1:0] i_mem_resp_data=0;
    wire o_mem_resp_ready,o_mem_complete_valid;
    wire [KEY_W-1:0] o_mem_complete_key;
    wire [RD_W-1:0] o_mem_complete_rd;
    wire [DATA_W-1:0] o_mem_complete_data;

    memory_order_queue #(.FLOW_PC_WIDTH(KEY_W),.ADDRESS_WIDTH(ADDR_W),
        .DATA_WIDTH(DATA_W),.MASK_WIDTH(MASK_W),.PHYREG_WIDTH(RD_W),
        .MICROOP_WIDTH(OP_W),.OPERANDS(2),.EXPATH_WIDTH(2),.MEMORY_PATH(2),
        .NEL_LANES(2),.DEPTH(4)) dut (
            .*, .i_nel_age('0), .i_agu_age('0),
            .i_flush_valid(1'b0), .i_flush_age('0),
            .o_mem_complete_store());

    task automatic enqueue_pair(input logic [KEY_W-1:0] first_key,
                                input logic [KEY_W-1:0] second_key);
        @(negedge clk);
        if (!o_nel_ready) $fatal(1,"NEL was unexpectedly blocked");
        i_nel_valid=2'b11;
        i_nel_data='0;
        i_nel_data[0 +: KEY_W]=first_key;
        i_nel_data[KEY_W +: 2]=2'd2;
        i_nel_data[NEL_W +: KEY_W]=second_key;
        i_nel_data[NEL_W+KEY_W +: 2]=2'd2;
        @(negedge clk);
        i_nel_valid=0;
    endtask
    task automatic agu(input logic [KEY_W-1:0] key,
                       input logic [RD_W-1:0] rd);
        @(negedge clk);
        i_agu_key=key;
        i_agu_payload={1'b0,ADDR_W'(key),DATA_W'(key+16),MASK_W'(3),rd,OP_W'(1)};
        #1;
        if (!o_agu_get) $fatal(1,"AGU backpressure at key %0d",key);
        i_agu_valid=1;
        @(negedge clk);
        i_agu_valid=0;
    endtask
    task automatic complete(input logic [KEY_W-1:0] expected_key,
                            input logic [RD_W-1:0] expected_rd);
        int wait_count=0;
        while (!o_mem_req_valid && wait_count<12) begin
            @(negedge clk);wait_count++;
        end
        if (!o_mem_req_valid || o_mem_req_key!==expected_key)
            $fatal(1,"issue order expected %0d, got valid=%b key=%0d",expected_key,o_mem_req_valid,o_mem_req_key);
        if (expected_key == 10'h002) begin
            // A scanned match must remain stable while memory refuses it.
            repeat(3) begin
                @(negedge clk);
                if (!o_mem_req_valid || o_mem_req_key!==expected_key)
                    $fatal(1,"request changed under memory backpressure");
            end
        end
        if (o_mem_req_payload[OP_W +: RD_W] !== expected_rd)
            $fatal(1,"payload rd mismatch");
        i_mem_req_get=1;
        @(negedge clk);
        i_mem_req_get=0;
        if (!o_mem_resp_ready || o_mem_req_valid)
            $fatal(1,"one outstanding memory request rule broken");
        i_mem_resp_data=DATA_W'(expected_key+32);
        i_mem_resp_valid=1;
        #1;
        if (!o_mem_complete_valid || o_mem_complete_key!==expected_key ||
            o_mem_complete_rd!==expected_rd || o_mem_complete_data!==DATA_W'(expected_key+32))
            $fatal(1,"response metadata mismatch");
        @(negedge clk);
        i_mem_resp_valid=0;
    endtask

    initial begin
        repeat(2) @(negedge clk);
        reset_n=1;
        enqueue_pair(10'h001,10'h002);
        enqueue_pair(10'h003,10'h004);
        if (o_nel_ready) $fatal(1,"NEL must stop when B has four entries");
        agu(10'h004,3'd4);
        agu(10'h003,3'd3);
        agu(10'h002,3'd2);
        repeat(5) @(negedge clk);
        if (o_mem_req_valid) $fatal(1,"younger AGU passed B head");
        agu(10'h001,3'd1); // B head takes the dedicated bypass slot.
        complete(10'h001,3'd1);
        complete(10'h002,3'd2);
        complete(10'h003,3'd3);
        complete(10'h004,3'd4);
        // Same low PC, different Flow Number in the high tag bits.
        enqueue_pair(10'h005,10'h205);
        agu(10'h205,3'd6);
        repeat(4) @(negedge clk);
        if (o_mem_req_valid) $fatal(1,"a different flow matched the same PC");
        agu(10'h005,3'd5);
        complete(10'h005,3'd5);
        complete(10'h205,3'd6);
        $display("NEL order, AGU rotation, head bypass, response gating and Flow tags passed");
        $finish;
    end
endmodule
