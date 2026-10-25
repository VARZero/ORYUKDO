`timescale 1ns/1ps
module tb_oryukdo_completion_queue #(parameter int LANES=6, DEPTH=2);
    localparam int SOURCE_W=$clog2(LANES);
    logic clk=0, reset_n=0, i_flush=0;
    logic [LANES-1:0] i_valid='0, i_fault='0;
    wire [LANES-1:0] o_ready;
    logic [LANES*16-1:0] i_token='0;
    logic [LANES*32-1:0] i_data='0,i_next='0;
    logic [LANES*5-1:0] i_cause='0;
    wire [1:0] o_valid,o_fault;
    logic [1:0] i_get='0;
    wire [31:0] o_token;
    wire [63:0] o_data,o_next;
    wire [9:0] o_cause;
    wire [2*SOURCE_W-1:0] o_source;
    int sent[LANES],received[LANES],phase,stalled,delivered;
    bit mixed;
    bit seen[LANES][512];
    logic [1:0] held='0;
    logic [16+32+32+5+1+SOURCE_W-1:0] previous[2];
    oryukdo_completion_queue #(.LANES(LANES),.DEPTH(DEPTH),.TOKEN_W(16)) dut(.*);
    always #5 clk=~clk;
    always @(posedge clk) begin
        if(!reset_n || i_flush) begin
            for(int l=0;l<LANES;l++) begin
                sent[l]=0;received[l]=0;
                for(int s=0;s<512;s++) seen[l][s]=0;
            end
            held='0;
        end else begin
            for(int b=0;b<2;b++) begin
                if(held[b] && (!o_valid[b] || previous[b]!=={o_token[b*16 +: 16],o_data[b*32 +: 32],
                    o_next[b*32 +: 32],o_cause[b*5 +: 5],o_fault[b],o_source[b*SOURCE_W +: SOURCE_W]}))
                    $fatal(1,"completion output changed while stalled");
                held[b]=o_valid[b] && !i_get[b];
                previous[b]={o_token[b*16 +: 16],o_data[b*32 +: 32],o_next[b*32 +: 32],
                    o_cause[b*5 +: 5],o_fault[b],o_source[b*SOURCE_W +: SOURCE_W]};
            end
            for(int l=0;l<LANES;l++) if(i_valid[l] && o_ready[l]) sent[l]++;
            for(int b=0;b<2;b++) if(o_valid[b] && i_get[b]) begin
                int l,seq,value;
                l=int'(o_source[b*SOURCE_W +: SOURCE_W]);
                seq=int'(o_token[b*16 +: 16])>>1;
                value=phase*100000+l*1000+seq;
                if(l>=LANES || seq>=sent[l] || seq>=512) $fatal(1,"unexpected completion source");
                // Independently stalled bank outputs may finish in either order.
                // Within one bank, producer FIFO order must still be preserved.
                if(seen[l][seq] || (!mixed && seq!=received[l])) $fatal(1,"duplicate or reordered completion");
                if(o_data[b*32 +: 32]!=32'(value) || o_next[b*32 +: 32]!=32'(value+4) ||
                   o_fault[b]!=(seq%5==0) || o_cause[b*5 +: 5]!=5'(seq%32) ||
                   o_token[b*16 +: 16]!=16'((seq<<1)+(mixed?((seq+l)%2):0)))
                    $fatal(1,"completion lost, reordered or corrupted lane=%d seq=%d",l,seq);
                if(o_token[b*16]!=1'(b)) $fatal(1,"wrong completion bank");
                seen[l][seq]=1;received[l]++;delivered++;
            end
            if(i_valid!='0 && o_ready=='0) stalled++;
        end
    end
    task automatic cycle(input int n,input bit feed);
        @(negedge clk);
        i_get=(n<DEPTH+3)?2'b00:(n%7==0)?2'b00:(n%11==0)?2'b01:2'b11;
        for(int l=0;l<LANES;l++) begin
            i_valid[l]=feed && (n%13!=l);
            i_data[l*32 +: 32]=32'(phase*100000+l*1000+sent[l]);
            i_next[l*32 +: 32]=i_data[l*32 +: 32]+4;
            i_token[l*16 +: 16]=16'((sent[l]<<1)+(mixed?((sent[l]+l)%2):0));
            i_fault[l]=sent[l]%5==0;i_cause[l*5 +: 5]=5'(sent[l]%32);
        end
        @(posedge clk);#1;
    endtask
    initial begin
        phase=1;mixed=0;stalled=0;delivered=0;
        repeat(3) @(negedge clk);reset_n=1;
        for(int n=0;n<200;n++) cycle(n,1);
        // Flush while queues contain pending results. No old payload may escape.
        @(negedge clk);i_flush=1;i_valid='0;@(negedge clk);i_flush=0;phase=2;mixed=1;
        for(int n=0;n<300;n++) cycle(n,1);
        for(int n=300;n<400;n++) cycle(n,0);
        for(int l=0;l<LANES;l++) if(received[l]!=sent[l]) $fatal(1,"completion starvation");
        if(stalled==0 || delivered<100) $fatal(1,"completion test did not exercise pressure");
        $display("tb_oryukdo_completion_queue PASS delivered=%d backpressure=%d",delivered,stalled);$finish;
    end
endmodule
