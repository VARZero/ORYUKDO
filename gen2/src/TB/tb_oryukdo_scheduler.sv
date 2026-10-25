`timescale 1ns/1ps
module tb_oryukdo_scheduler #(

    parameter int PC_W=32, DATA_W=32, IMM_W=32, UOP_W=5,
    parameter int ARCH=16, PHY=32, DECODE=2, ENTRIES=32,
    parameter int WINDOWS=8, WINDOW_SIZE=16, PC_STEP=4,
    parameter int PATHS=3, EX_LANES=5,
    parameter int PATH_LANES[PATHS]='{1,EX_LANES-2,1},
    parameter int ISSUE=EX_LANES, UPDATES=EX_LANES, RS_DEPTH=16,
    parameter int GEN_W=8, EPOCH_W=8,
    parameter bit EXTERNAL_PREDICTOR=0,
    parameter bit CUSTOM_LSQ=0,
    localparam int SLOT_W=(ENTRIES>1)?$clog2(ENTRIES):1,
    localparam int TOKEN_W=SLOT_W+GEN_W,
    localparam int FLOW_W=(WINDOWS>1)?$clog2(WINDOWS):1,
    localparam int ARCH_W=$clog2(ARCH), PHY_W=$clog2(PHY), PATH_W=$clog2(PATHS),
    localparam int KEY_W=PC_W+TOKEN_W+FLOW_W,
    localparam int EX_W=KEY_W+PATH_W+UOP_W+IMM_W+3*PHY_W,
    localparam int RESULTS=EX_LANES+1,
    localparam int BYTES=DATA_W/8
) ();
    logic  clk='0;
    logic  reset_n='0;
    logic [PC_W-1:0] i_reset_pc='0;
    logic [PC_W-1:0] o_fetch_pc;
    logic [EPOCH_W-1:0] o_fetch_epoch;
    logic [EPOCH_W-1:0] i_decode_epoch='0;
    logic [DECODE-1:0] i_decode_valid='0;
    logic [DECODE-1:0] o_decode_get;
    logic [DECODE*PC_W-1:0] i_decode_pc='0;
    logic [DECODE*PATH_W-1:0] i_decode_path='0;
    logic [DECODE*UOP_W-1:0] i_decode_uop='0;
    logic [DECODE*IMM_W-1:0] i_decode_imm='0;
    logic [DECODE*ARCH_W-1:0] i_decode_rd='0;
    logic [DECODE*2*ARCH_W-1:0] i_decode_rs='0;
    logic [DECODE-1:0] i_decode_write='0;
    logic [DECODE-1:0] i_decode_control='0;
    logic [DECODE-1:0] i_decode_memory='0;
    logic [DECODE-1:0] i_decode_store='0;
    logic [DECODE-1:0] i_decode_csr='0;
    logic [DECODE-1:0] i_decode_end='0;
    logic [DECODE-1:0] i_decode_exception='0;
    logic [DECODE*5-1:0] i_decode_cause='0;
    logic  o_predict_valid;
    logic [PC_W-1:0] o_predict_pc;
    logic [EPOCH_W-1:0] o_predict_epoch;
    logic  i_predict_valid='0;
    logic [PC_W-1:0] i_predict_pc='0;
    logic [PC_W-1:0] i_predict_next='0;
    logic [EPOCH_W-1:0] i_predict_epoch='0;
    logic [EX_LANES-1:0] o_predict_update_valid;
    logic [EX_LANES*PC_W-1:0] o_predict_update_pc;
    logic [EX_LANES*PC_W-1:0] o_predict_update_next;
    logic [EX_LANES-1:0] o_ex_valid;
    logic [EX_LANES-1:0] i_ex_get='0;
    logic [EX_LANES*EX_W-1:0] o_ex_data;
    logic [EX_LANES*TOKEN_W-1:0] o_ex_token;
    logic [EX_LANES-1:0] o_ex_memory;
    logic [EX_LANES-1:0] o_ex_store;
    logic [EX_LANES-1:0] o_ex_csr;
    logic [EX_LANES-1:0] i_result_valid='0;
    logic [EX_LANES-1:0] i_result_fault='0;
    logic [EX_LANES*TOKEN_W-1:0] i_result_token='0;
    logic [EX_LANES*DATA_W-1:0] i_result_data='0;
    logic [EX_LANES*PC_W-1:0] i_result_next='0;
    logic [EX_LANES*5-1:0] i_result_cause='0;
    logic [EX_LANES-1:0] o_result_accept;
    logic [RESULTS-1:0] o_wb_valid;
    logic [RESULTS*PHY_W-1:0] o_wb_phy;
    logic [RESULTS*DATA_W-1:0] o_wb_data;
    logic [RESULTS*UOP_W-1:0] o_wb_uop;
    logic  i_agu_valid='0;
    logic  o_agu_ready;
    logic [TOKEN_W-1:0] i_agu_token='0;
    logic [PC_W-1:0] i_agu_address='0;
    logic [DATA_W-1:0] i_agu_data='0;
    logic [BYTES-1:0] i_agu_mask='0;
    logic  i_agu_nonspec='0;
    logic  i_agu_fault='0;
    logic [4:0] i_agu_cause='0;
    logic  o_mem_valid;
    logic  i_mem_ready='0;
    logic  o_mem_store;
    logic [PC_W-1:0] o_mem_address;
    logic [DATA_W-1:0] o_mem_data;
    logic [BYTES-1:0] o_mem_mask;
    logic  i_mem_response_valid='0;
    logic  o_mem_response_ready;
    logic [DATA_W-1:0] i_mem_response_data='0;
    logic  i_mem_response_fault='0;
    logic [4:0] i_mem_response_cause='0;
    logic  i_interrupt='0;
    logic [PC_W-1:0] i_trap_vector='0;
    logic  o_flush;
    logic  o_trap;
    logic  o_trap_interrupt;
    logic [PC_W-1:0] o_redirect_pc;
    logic [PC_W-1:0] o_trap_pc;
    logic [4:0] o_trap_cause;
    logic  o_window_boundary;
    logic  o_exception_pending;
    logic  o_retire;
    logic [TOKEN_W-1:0] o_retire_token;
    oryukdo_scheduler #(.PC_W(PC_W),.DATA_W(DATA_W),.IMM_W(IMM_W),.UOP_W(UOP_W),
      .ARCH(ARCH),.PHY(PHY),.DECODE(DECODE),.ENTRIES(ENTRIES),.WINDOWS(WINDOWS),.WINDOW_SIZE(WINDOW_SIZE),
      .PATHS(PATHS),.EX_LANES(EX_LANES),.PATH_LANES(PATH_LANES),.ISSUE(ISSUE),.UPDATES(UPDATES),
      .RS_DEPTH(RS_DEPTH),.GEN_W(GEN_W),.EPOCH_W(EPOCH_W),.EXTERNAL_PREDICTOR(EXTERNAL_PREDICTOR),.CUSTOM_LSQ(CUSTOM_LSQ)) dut(.*);
    always #5 clk=~clk;
    logic [TOKEN_W-1:0] tokens[1024];
    logic [PHY_W-1:0] prd[1024], prs1[1024], prs2[1024];
    logic [FLOW_W-1:0] seen_flow[1024];
    logic [IMM_W-1:0] seen_imm[1024];
    logic [UOP_W-1:0] seen_uop[1024];
    logic [DATA_W-1:0] registers[PHY], memory_words[256];
    bit issued[1024], retired[1024];
    integer stores, loads, io_reads, trap_count, flush_count, cycle_count;
    logic [PC_W-1:0] last_trap_pc, last_redirect;
    logic [4:0] last_cause;
    bit last_interrupt;
    integer bus_delay;
    bit bus_pending, pending_store;
    logic [PC_W-1:0] pending_address;
    logic [DATA_W-1:0] pending_data;
    logic [BYTES-1:0] pending_mask;
    bit hold_bus, fault_bus, response_taken;
    logic [EX_LANES-1:0] block_ex='0, held_ex='0;
    logic [EX_W+TOKEN_W+3-1:0] held_packet[EX_LANES];
    localparam int RD_OFFSET=KEY_W+PATH_W+UOP_W+IMM_W;
    localparam int FLUSH_WAITERS=(RS_DEPTH>=32)?12:6;
    always @(posedge clk) begin
      if(!reset_n || o_flush) begin
        held_ex='0;
        if(reset_n && |o_ex_valid) $fatal(1,"EX issue remained valid during flush");
      end else for(int e=0;e<EX_LANES;e++) begin
        if(held_ex[e] && (!o_ex_valid[e] || held_packet[e]!==
            {o_ex_data[e*EX_W +: EX_W],o_ex_token[e*TOKEN_W +: TOKEN_W],o_ex_memory[e],o_ex_store[e],o_ex_csr[e]}))
          $fatal(1,"stalled EX output changed lane=%d",e);
        held_ex[e]=o_ex_valid[e] && !i_ex_get[e];
        held_packet[e]={o_ex_data[e*EX_W +: EX_W],o_ex_token[e*TOKEN_W +: TOKEN_W],o_ex_memory[e],o_ex_store[e],o_ex_csr[e]};
      end
    end
    always @(posedge clk) begin
      if(reset_n) begin
        cycle_count++;
        if(cycle_count>20000) $fatal(1,"global timeout pc=%h frontier=%d head=%d scan=%d count=%d",
          o_fetch_pc,dut.U_FRONTIER.state,dut.U_FRONTIER.head,dut.U_FRONTIER.scan,dut.U_FRONTIER.count);
        for(int e=0;e<EX_LANES;e++) if(o_ex_valid[e] && i_ex_get[e]) begin
          int p;
          p=int'(o_ex_data[e*EX_W +: PC_W])/4;
          if(issued[p]) $fatal(1,"duplicate issue pc=%h",p*4);
          issued[p]=1;tokens[p]=o_ex_token[e*TOKEN_W +: TOKEN_W];
          prd[p]=o_ex_data[e*EX_W+RD_OFFSET +: PHY_W];
          prs1[p]=o_ex_data[e*EX_W+RD_OFFSET+PHY_W +: PHY_W];
          prs2[p]=o_ex_data[e*EX_W+RD_OFFSET+2*PHY_W +: PHY_W];
          seen_flow[p]=o_ex_data[e*EX_W+PC_W+TOKEN_W +: FLOW_W];
          seen_uop[p]=o_ex_data[e*EX_W+KEY_W+PATH_W +: UOP_W];
          seen_imm[p]=o_ex_data[e*EX_W+KEY_W+PATH_W+UOP_W +: IMM_W];
        end
        for(int r=0;r<RESULTS;r++) if(o_wb_valid[r])
          registers[o_wb_phy[r*PHY_W +: PHY_W]]=o_wb_data[r*DATA_W +: DATA_W];
        if(o_retire) for(int p=0;p<1024;p++) if(issued[p] && tokens[p]==o_retire_token) retired[p]=1;
        if(o_trap) begin trap_count++;last_trap_pc=o_trap_pc;last_cause=o_trap_cause;last_interrupt=o_trap_interrupt;end
        if(o_flush) begin flush_count++;last_redirect=o_redirect_pc;end
      end
    end
    // An in-order bus with finite backpressure and delayed response.
    always @(negedge clk) begin
      if(!reset_n) begin
        bus_pending=0;bus_delay=0;i_mem_ready=0;i_mem_response_valid=0;
        i_mem_response_fault=0;i_mem_response_cause=0;response_taken=0;
      end else begin
        i_mem_ready=!bus_pending && !hold_bus && cycle_count%4!=0;
        i_ex_get=((cycle_count%5==0)?'0:'1) & ~block_ex;
        if(response_taken) begin i_mem_response_valid=0;bus_pending=0;response_taken=0;end
        if(bus_pending && !i_mem_response_valid && !hold_bus) begin
          if(bus_delay!=0) bus_delay--;
          else begin
            i_mem_response_valid=1;i_mem_response_fault=fault_bus;
            i_mem_response_cause=pending_store ? 5'd7 : 5'd5;
            i_mem_response_data=memory_words[pending_address[9:2]];
            if(pending_store && !fault_bus)
              for(int b=0;b<BYTES;b++) if(pending_mask[b]) memory_words[pending_address[9:2]][b*8 +: 8]=pending_data[b*8 +: 8];
          end
        end
      end
    end
    always @(posedge clk) if(reset_n && i_mem_response_valid && o_mem_response_ready) response_taken=1;
    always @(posedge clk) if(reset_n && o_mem_valid && i_mem_ready) begin
      if(bus_pending) $fatal(1,"multiple bus requests");
      bus_pending=1;bus_delay=3;pending_store=o_mem_store;pending_address=o_mem_address;
      pending_data=o_mem_data;pending_mask=o_mem_mask;
      if(o_mem_store) stores++; else begin loads++;if(o_mem_address==32'h100) io_reads++;end
    end
    task automatic tick(input int n=1); repeat(n) begin @(posedge clk);#1;end endtask
    task automatic restart;
      @(negedge clk);reset_n=0;i_decode_valid='0;i_result_valid='0;i_agu_valid=0;
      i_interrupt=0;hold_bus=0;fault_bus=0;i_predict_valid=0;i_trap_vector=32'h200;block_ex='0;
      i_ex_get='1;stores=0;loads=0;io_reads=0;trap_count=0;flush_count=0;cycle_count=0;
      for(int p=0;p<1024;p++) begin issued[p]=0;retired[p]=0;tokens[p]='0;end
      for(int p=0;p<PHY;p++) registers[p]='0;
      for(int p=0;p<256;p++) memory_words[p]=32'h11223344;
      tick(3);@(negedge clk);reset_n=1;tick(PHY+8);
    endtask
    task automatic send(input int pc, input bit mem=0,st=0,control=0,csr=0,last=0,
                        input int rd=0,rs1=0,rs2=0,input bit exception=0,input int predicted_next=-1);
      @(negedge clk);
      i_decode_valid='0;i_decode_valid[0]=1;i_decode_epoch=o_fetch_epoch;
      i_decode_pc='0;i_decode_pc[0 +: PC_W]=PC_W'(pc);
      i_decode_path='0;i_decode_path[0 +: PATH_W]=PATH_W'(mem?PATHS-1:control?0:1);
      i_decode_uop='0;i_decode_imm='0;i_decode_rd='0;i_decode_rs='0;
      i_decode_rd[0 +: ARCH_W]=ARCH_W'(rd);i_decode_rs[0 +: ARCH_W]=ARCH_W'(rs1);
      i_decode_rs[ARCH_W +: ARCH_W]=ARCH_W'(rs2);
      i_decode_write='0;i_decode_write[0]=rd!=0;
      i_decode_control='0;i_decode_control[0]=control;
      i_decode_memory='0;i_decode_memory[0]=mem;i_decode_store='0;i_decode_store[0]=st;
      i_decode_csr='0;i_decode_csr[0]=csr;i_decode_end='0;i_decode_end[0]=last;
      i_decode_exception='0;i_decode_exception[0]=exception;i_decode_cause='0;i_decode_cause[0 +: 5]=5'd2;
      if(EXTERNAL_PREDICTOR && control) begin
        i_predict_valid=1;i_predict_pc=PC_W'(pc);i_predict_epoch=o_fetch_epoch;
        i_predict_next=PC_W'(predicted_next<0 ? pc+4 : predicted_next);
      end
      begin
        bit accepted;
        accepted=0;
        for(int t=0;t<1000;t++) begin
          @(posedge clk);if(o_decode_get[0]) begin accepted=1;break;end
        end
        if(!accepted) $fatal(1,"decode blocked pc=%h fetch=%h ready=%b/%b/%b stopped=%b",pc,o_fetch_pc,
            dut.frontier_ready,dut.rename_ready,dut.prm_alloc_valid,o_exception_pending);
      end
      @(negedge clk);i_decode_valid='0;i_predict_valid=0;
    endtask
    task automatic wait_issue(input int pc);
      for(int t=0;t<1000;t++) begin if(issued[pc/4]) return;tick();end
      $fatal(1,"issue timeout pc=%h",pc);
    endtask
    task automatic complete(input int pc,input int data=0,input int nextpc=0,input bit fault=0,input int cause=5);
      wait_issue(pc);@(negedge clk);
      i_result_valid='0;i_result_valid[0]=1;i_result_token='0;i_result_token[0 +: TOKEN_W]=tokens[pc/4];
      i_result_data='0;i_result_data[0 +: DATA_W]=DATA_W'(data);
      i_result_next='0;i_result_next[0 +: PC_W]=PC_W'(nextpc);
      i_result_fault='0;i_result_fault[0]=fault;i_result_cause='0;i_result_cause[0 +: 5]=5'(cause);
      #1;if(!o_result_accept[0]) $fatal(1,"live result rejected pc=%h",pc);
      tick();@(negedge clk);i_result_valid='0;
    endtask
    task automatic agu(input int pc,input int address,input int data=0,input int mask=15,input bit nonspec=0,fault=0);
      wait_issue(pc);@(negedge clk);i_agu_valid=1;i_agu_token=tokens[pc/4];
      i_agu_address=PC_W'(address);i_agu_data=DATA_W'(data);i_agu_mask=BYTES'(mask);
      i_agu_nonspec=nonspec;i_agu_fault=fault;i_agu_cause=5'd5;
      #1;if(!o_agu_ready) $fatal(1,"AGU rejected pc=%h",pc);
      tick();@(negedge clk);i_agu_valid=0;
    endtask
    task automatic wait_value(input int pc,input int expected);
      wait_issue(pc);
      for(int t=0;t<1000;t++) begin
        if(registers[prd[pc/4]]==DATA_W'(expected)) return;
        tick();
      end
      $fatal(1,"load value mismatch pc=%h got=%h expected=%h",pc,registers[prd[pc/4]],expected);
    endtask
    task automatic wait_retired(input int pc);
      for(int t=0;t<1000;t++) begin if(retired[pc/4]) return;tick();end
      $fatal(1,"retire timeout pc=%h head=%d scan=%d state=%d drain=%d",pc,dut.U_FRONTIER.head,dut.U_FRONTIER.scan,dut.U_FRONTIER.state,dut.U_FRONTIER.drain_left);
    endtask
    task automatic wait_flush;
      for(int t=0;t<1000;t++) begin if(flush_count!=0) return;tick();end
      $fatal(1,"flush timeout");
    endtask
    task automatic send_bundle;
      @(negedge clk);
      i_decode_valid='1;i_decode_epoch=o_fetch_epoch;i_decode_pc='0;i_decode_path='0;
      i_decode_uop='0;i_decode_imm='0;i_decode_rd='0;i_decode_rs='0;
      i_decode_write='1;i_decode_control='0;i_decode_memory='0;i_decode_store='0;
      i_decode_csr='0;i_decode_end='0;i_decode_end[DECODE-1]=1;
      i_decode_exception='0;i_decode_cause='0;
      for(int l=0;l<DECODE;l++) begin
        i_decode_pc[l*PC_W +: PC_W]=PC_W'(4*l);
        i_decode_path[l*PATH_W +: PATH_W]=PATH_W'(1);
        i_decode_rd[l*ARCH_W +: ARCH_W]=ARCH_W'(l+1);
        if(l>0) i_decode_rs[(l*2)*ARCH_W +: ARCH_W]=ARCH_W'(l);
      end
      begin
        bit accepted;accepted=0;
        for(int t=0;t<1000;t++) begin @(posedge clk);if(&o_decode_get) begin accepted=1;break;end end
        if(!accepted) $fatal(1,"bundle admission failed");
      end
      @(negedge clk);i_decode_valid='0;
    endtask
    generate if(CUSTOM_LSQ) begin : CUSTOM_TEST
      task automatic run;
        // Stall a captured instruction, then prove partial-window retirement
        // still progresses and late WBC readiness reaches the held consumer.
        restart();send(0,0,0,0,0,0,1);wait_issue(0);
        @(negedge clk);dut.GEN_CUSTOM_LSQ.U_LSQ.block_allocate=1;
        send(4,0,0,0,0,1,2,1);complete(0,42);wait_retired(0);tick(8);
        if(issued[1] || dut.frontier_count!=0) $fatal(1,"Custom allocation stall leaked");
        @(negedge clk);dut.GEN_CUSTOM_LSQ.U_LSQ.block_allocate=0;
        wait_issue(4);
        if(registers[prs1[1]]!=42) $fatal(1,"WBC lost during custom LSQ stall");
        complete(4,43);wait_retired(4);
        // Backpressured AGU must keep valid visible to the user implementation.
        restart();send(0,1,0,0,0,1,1);wait_issue(0);
        @(negedge clk);dut.GEN_CUSTOM_LSQ.U_LSQ.block_agu=1;
        i_agu_valid=1;i_agu_token=tokens[0];i_agu_address=32'h40;i_agu_mask='1;
        tick(8);
        if(o_agu_ready || loads || !dut.GEN_CUSTOM_LSQ.U_LSQ.i_agu_valid)
          $fatal(1,"Custom AGU handshake lost valid or accepted early");
        @(negedge clk);dut.GEN_CUSTOM_LSQ.U_LSQ.block_agu=0;
        #1;if(!o_agu_ready) $fatal(1,"Custom AGU did not resume");
        tick();@(negedge clk);i_agu_valid=0;wait_retired(0);
        if(loads!=1) $fatal(1,"Custom AGU accepted duplicate request");
        // Flush cancels an allocated branch and the still-unallocated bundle.
        restart();send(0,0,0,1,0,1,0);wait_issue(0);
        @(negedge clk);dut.GEN_CUSTOM_LSQ.U_LSQ.block_allocate=1;
        send(4,1,1,0,0,1,0);complete(0,0,32'h80);wait_flush();
        @(negedge clk);dut.GEN_CUSTOM_LSQ.U_LSQ.block_allocate=0;tick(20);
        if(issued[1] || stores || loads) $fatal(1,"Flushed custom allocation escaped");
        $display("custom LSQ allocation/AGU stalls, window drain, WBC and flush PASS");
      endtask
    end else begin : CUSTOM_TEST
      task automatic run; endtask
    end endgenerate
    initial begin
      CUSTOM_TEST.run();
      // PC candidates are parallel, but admission must remain a contiguous
      // prefix: a missing first lane or an invalid/control lane cuts the suffix.
      if(DECODE>1) for(int mode=0;mode<2;mode++) begin
        restart();
        @(negedge clk);
        i_decode_epoch=o_fetch_epoch;i_decode_valid='1;i_decode_valid[0]=0;
        i_decode_pc='0;i_decode_path='0;i_decode_uop='0;i_decode_imm='0;
        i_decode_rd='0;i_decode_rs='0;i_decode_write='0;i_decode_control='0;
        i_decode_memory='0;i_decode_store='0;i_decode_csr='0;i_decode_exception='0;
        i_decode_end='1;i_decode_cause='0;
        for(int l=0;l<DECODE;l++) i_decode_pc[l*PC_W +: PC_W]=PC_W'(l*4);
        tick(3);if(|o_decode_get || o_fetch_pc!=0) $fatal(1,"decode accepted a non-prefix valid lane");
        @(negedge clk);i_decode_valid[0]=1;
        if(mode==0) i_decode_pc[PC_W +: PC_W]=PC_W'(12);
        else begin
          i_decode_control[0]=1;
          if(EXTERNAL_PREDICTOR) begin
            i_predict_valid=1;i_predict_pc=0;i_predict_next=4;i_predict_epoch=o_fetch_epoch;
          end
        end
        #1;if(o_decode_get!=DECODE'(1)) $fatal(1,"decode prefix did not stop at PC mismatch/control");
        tick();@(negedge clk);i_decode_valid='0;i_predict_valid=0;
        if(o_fetch_pc!=4) $fatal(1,"rejected suffix advanced fetch PC");
        complete(0,0,4);wait_retired(0);tick(5);
        if(issued[1] || issued[2] || issued[3] || flush_count) $fatal(1,"rejected decode suffix escaped");
      end
      $display("parallel PC validation preserves contiguous prefix PASS");
      // Sparse and dependent multi-lane admission uses distinct physical registers.
      restart();send_bundle();
      for(int l=0;l<DECODE;l++) begin
        wait_issue(l*4);
        if(l>0 && registers[prs1[l]]!=DATA_W'(l+10)) $fatal(1,"same-bundle dependency failed");
        complete(l*4,l+11);
      end
      wait_retired((DECODE-1)*4);
      $display("multi-lane rename dependency PASS");
      // Older window blocks publication, not same-CPU forwarding and dependency wakeup.
      restart();
      send(0,0,0,0,0,1,1);
      send(4,1,1);send(8,1,0,0,0,0,2);send(12,0,0,0,0,1,3,2);
      agu(4,32'h40,32'h12345678);agu(8,32'h40);
      wait_value(8,32'h12345678);wait_issue(12);
      if(registers[prs1[3]]!=32'h12345678 || stores!=0 || loads!=0) $fatal(1,"local forwarding/order failure");
      complete(12,32'h12345679);tick(10);if(stores!=0) $fatal(1,"younger window published");
      complete(0,7);wait_retired(12);
      if(stores!=1 || memory_words[16]!=32'h12345678) $fatal(1,"store not published");
      $display("local store forwarding and ordered windows PASS");
      // Wrong prediction kills younger store and its forwarded load.
      restart();send(0,0,0,1);send(4,1,1);send(8,1,0,0,0,1,2);
      agu(4,32'h40,99);agu(8,32'h40);wait_value(8,99);
      complete(0,0,32'h80);wait_flush();
      if(stores!=0 || last_redirect!=32'h80 || trap_count!=0) $fatal(1,"branch rollback failure");
      @(negedge clk);i_result_valid[0]=1;i_result_token[0 +: TOKEN_W]=tokens[2];
      #1;if(o_result_accept[0]) $fatal(1,"stale result accepted");
      tick();@(negedge clk);i_result_valid='0;
      send(32'h80,0,0,0,0,1,1);complete(32'h80,8);wait_retired(32'h80);
      $display("branch rollback and stale completion PASS");
      // Exception before a younger store: no publication.
      restart();send(0,0,0,0,0,0,1);send(4,1,1,0,0,1);
      agu(4,32'h40,99);complete(0,0,0,1,5);wait_flush();
      if(stores!=0 || last_trap_pc!=0 || last_cause!=5) $fatal(1,"imprecise exception");
      // Correct store prefix of a faulting window must survive.
      restart();send(0,1,1);send(4,1,0,0,0,0,2);send(8,1,1,0,0,1);
      agu(0,32'h40,77);agu(4,32'h44,0,15,0,1);agu(8,32'h48,88);
      wait_flush();if(stores!=1 || memory_words[16]!=77 || memory_words[18]==88 || last_trap_pc!=4)
        $fatal(1,"fault prefix failure");
      $display("precise exception prefix PASS");
      // A fault waits behind an older blocked load, but stops frontend input
      // immediately. Faulting loads/stores must never access the external bus.
      for(int fault_store=0;fault_store<2;fault_store++) begin
        restart();hold_bus=1;
        send(0,1,0,0,0,0,1);send(4,1,1'(fault_store),0,0,0,fault_store?0:2);
        send(8,1,1,0,0,1);
        agu(0,32'h40);agu(4,32'h44,99,15,0,1);
        if(!o_exception_pending) $fatal(1,"AGU fault did not stop admission on acceptance");
        agu(8,32'h48,88);
        // Retry the fault and also submit its token through the EX interface.
        @(negedge clk);i_agu_valid=1;i_agu_token=tokens[1];i_agu_fault=1;
        i_result_valid='1;i_result_fault='0;
        for(int l=0;l<EX_LANES;l++) i_result_token[l*TOKEN_W +: TOKEN_W]=tokens[1];
        i_decode_valid='0;i_decode_valid[0]=1;i_decode_pc[0 +: PC_W]=12;i_decode_epoch=o_fetch_epoch;
        #1;if(o_agu_ready || |o_result_accept || |o_decode_get) $fatal(1,"fault duplicate or younger decode accepted");
        tick(8);
        if(trap_count || loads || stores || retired[1] || registers[prd[1]]!=0)
          $fatal(1,"AGU fault bypassed older load or produced a side effect");
        @(negedge clk);i_agu_valid=0;i_result_valid='0;i_decode_valid='0;hold_bus=0;
        wait_flush();
        if(last_trap_pc!=4 || last_cause!=5 || loads!=1 || stores || !retired[0] || retired[1] ||
           registers[prd[1]]!=0 || memory_words[17]!=32'h11223344 || memory_words[18]!=32'h11223344)
          $fatal(1,"delayed AGU fault lost precise prefix");
      end
      $display("registered AGU faults, early stop and completion-class isolation PASS");
      // Serial MMIO before the fault must be allowed to finish. Waiting for
      // the registered fault must not create a window/publication deadlock.
      restart();send(0,0,0,0,0,0,1);send(4,1,1);send(8,1,0,0,0,1,2);
      agu(4,32'h100,55,15,1);agu(8,32'h44,0,15,0,1);complete(0,21);
      wait_flush();
      if(last_trap_pc!=8 || stores!=1 || loads || memory_words[64]!=55 || !retired[0] || !retired[1])
        $fatal(1,"registered fault blocked older serial MMIO");
      $display("registered fault after older serial MMIO PASS");
      // A younger pending AGU fault disappears on an older branch recovery,
      // even when memory has not reached that fault's completion yet.
      restart();hold_bus=1;send(0,0,0,1);send(4,1,0,0,0,0,1);send(8,1,1,0,0,1);
      agu(4,32'h40);agu(8,32'h44,99,15,0,1);complete(0,0,32'h100);wait_flush();
      @(negedge clk);hold_bus=0;tick(PHY+8);
      if(trap_count || o_exception_pending || stores) $fatal(1,"wrong-path AGU fault survived recovery");
      send(32'h100,0,0,0,0,1,1);complete(32'h100,42);wait_retired(32'h100);
      $display("branch recovery discards uncompleted AGU fault PASS");
      // Sequential per-byte forwarding merges the youngest store and memory.
      restart();send(0,1,1);send(4,1,1);send(8,1,0,0,0,1,2);
      agu(0,32'h40,32'h0000bbaa,3);agu(4,32'h40,32'h0000cc00,2);agu(8,32'h40);
      wait_value(8,32'h1122ccaa);wait_retired(8);
      if(loads!=1 || stores!=2 || memory_words[16]!=32'h1122ccaa) $fatal(1,"byte forwarding failure");
      $display("partial overlapping store forwarding PASS");
      // CSR executes only after older effects and immediately exposes IRQ state.
      restart();send(0,1,1);send(4,0,0,0,1);
      agu(0,32'h40,55);wait_issue(4);
      if(memory_words[16]!=55 || stores!=1) $fatal(1,"CSR bypassed older store");
      complete(4);@(negedge clk);i_interrupt=1;wait_flush();
      if(!last_interrupt || last_trap_pc!=8 || stores!=1) $fatal(1,"CSR interrupt boundary failure");
      $display("serialized CSR and interrupt boundary PASS");
      // CSR must not block a late-ready predecessor in the same RS path.
      restart();send(0,1,0,0,0,0,1);send(4,0,0,0,0,0,2,1);send(8,0,0,0,1);
      agu(0,32'h40);wait_value(0,32'h11223344);wait_issue(4);
      if(issued[2]) $fatal(1,"CSR issued before late-ready predecessor");
      complete(4,99);wait_issue(8);complete(8);wait_retired(8);
      $display("CSR avoids RS head-of-line deadlock PASS");
      restart();send(0,0,0,0,1,0,1);
      // Offer a younger memory operation before CSR completion. Even after
      // CSR issue, admission stays blocked until it retires. Then the old
      // prefetched epoch stays rejected until the frontend refetches.
      wait_issue(0);
      @(negedge clk);i_decode_valid='0;i_decode_valid[0]=1;
      i_decode_pc='0;i_decode_pc[0 +: PC_W]=4;i_decode_epoch=o_fetch_epoch;
      i_decode_csr='0;i_decode_memory[0]=1;i_decode_store='0;
      tick(8);if(o_decode_get!=0 || issued[1] || loads) $fatal(1,"younger instruction crossed CSR");
      complete(0,85);wait_retired(0);tick(3);
      if(o_decode_get!=0 || issued[1] || loads) $fatal(1,"stale pre-CSR fetch epoch accepted");
      @(negedge clk);i_decode_valid='0;
      send(4,0,0,0,0,1,2,1);wait_issue(4);
      if(registers[prs1[1]]!=85) $fatal(1,"CSR result failed to wake dependent instruction");
      complete(4,86);wait_retired(4);
      $display("CSR register result dependency PASS");
      // MMU non-speculative read splits the window before touching the device.
      restart();send(0,1,1);send(4,1,0,0,0,1,2);
      agu(4,32'h100,0,15,1);tick(15);if(io_reads!=0) $fatal(1,"speculative MMIO read");
      agu(0,32'h40,42);wait_value(4,32'h11223344);wait_retired(4);
      if(io_reads!=1 || stores!=1) $fatal(1,"MMIO serialization failure");
      // A store bus error is a precise fault at the head, not a lost completion.
      restart();fault_bus=1;send(0,1,1,0,0,1);agu(0,32'h40,42);wait_flush();
      if(last_trap_pc!=0 || last_cause!=7 || stores!=1 || memory_words[16]==42) $fatal(1,"store bus fault failure");
      $display("MMIO and store bus fault PASS");
      restart();send(0,0,0,0,0,0,0,0,0,1);wait_flush();
      if(issued[0] || last_trap_pc!=0 || last_cause!=2) $fatal(1,"decode exception executed");
      $display("decode exception PASS");
      // Multiple independent completions in one cycle, younger finishes first.
      restart();send(0,0,0,0,0,0,1);send(4,0,0,0,0,1,2);wait_issue(0);wait_issue(4);
      @(negedge clk);i_result_valid='0;i_result_valid[1:0]=2'b11;
      i_result_token[0 +: TOKEN_W]=tokens[1];i_result_token[TOKEN_W +: TOKEN_W]=tokens[0];
      i_result_fault='0;i_result_data[0 +: DATA_W]=22;i_result_data[DATA_W +: DATA_W]=11;
      #1;if(o_result_accept[1:0]!=2'b11) $fatal(1,"parallel completions rejected");
      tick();@(negedge clk);i_result_valid='0;wait_retired(4);
      if(registers[prd[0]]!=11 || registers[prd[1]]!=22) $fatal(1,"parallel writeback mismatch");
      // All EX producers return different even slots simultaneously. They
      // enqueue together but must serialize through bank zero without loss.
      restart();
      for(int n=0;n<EX_LANES*2;n++) send(n*4,0,0,0,0,n==EX_LANES*2-1,1+n);
      for(int n=0;n<EX_LANES*2;n++) wait_issue(n*4);
      @(negedge clk);i_result_valid='1;i_result_fault='0;
      for(int l=0;l<EX_LANES;l++) begin
        i_result_token[l*TOKEN_W +: TOKEN_W]=tokens[l*2];
        i_result_data[l*DATA_W +: DATA_W]=DATA_W'(100+l);
      end
      #1;if(o_result_accept!='1 || o_wb_valid!='0) $fatal(1,"completion enqueue and writeback were not separated");
      tick();@(negedge clk);i_result_valid='0;
      // A duplicate is rejected even before its queued original reaches the table.
      i_result_valid[0]=1;i_result_token[0 +: TOKEN_W]=tokens[(EX_LANES-1)*2];
      #1;if(o_result_accept[0]) $fatal(1,"queued duplicate completion accepted");
      tick();@(negedge clk);i_result_valid='0;
      for(int l=0;l<EX_LANES;l++) wait_value(l*8,100+l);
      for(int l=0;l<EX_LANES;l++) complete(l*8+4,200+l);
      wait_retired((EX_LANES*2-1)*4);
      $display("same-bank completion burst and duplicate rejection PASS");
      // Several producers offer the same token with different payloads/faults.
      // Exactly the first ready valid lane owns the result and its side effects.
      for(int first_lane=0;first_lane<EX_LANES;first_lane++) begin
        restart();send(0,0,0,0,0,1,1);wait_issue(0);
        @(negedge clk);i_result_valid='0;i_result_fault='1;
        for(int lane=0;lane<EX_LANES;lane++) begin
          i_result_valid[lane]=(lane>=first_lane);
          i_result_token[lane*TOKEN_W +: TOKEN_W]=tokens[0];
          i_result_data[lane*DATA_W +: DATA_W]=DATA_W'(100+lane);
        end
        i_result_fault[first_lane]=0;
        #1;if((o_result_accept & i_result_valid)!=(EX_LANES'(1)<<first_lane))
          $fatal(1,"simultaneous duplicate winner incorrect first=%d accept=%b",first_lane,o_result_accept);
        tick();@(negedge clk);i_result_valid='1;
        #1;if(|o_result_accept) $fatal(1,"duplicate accepted after winning enqueue");
        tick();@(negedge clk);i_result_valid='0;
        wait_value(0,100+first_lane);wait_retired(0);tick(4);
        if(trap_count || o_exception_pending) $fatal(1,"losing duplicate fault escaped");
      end
      restart();send(0,0,0,0,0,1,1);wait_issue(0);
      @(negedge clk);i_result_valid='1;i_result_fault='1;
      for(int lane=0;lane<EX_LANES;lane++)
        i_result_token[lane*TOKEN_W +: TOKEN_W]=tokens[0] ^ (TOKEN_W'(1)<<SLOT_W);
      i_result_token[(EX_LANES-1)*TOKEN_W +: TOKEN_W]=tokens[0];
      i_result_fault[EX_LANES-1]=0;i_result_data[(EX_LANES-1)*DATA_W +: DATA_W]=71;
      #1;if(o_result_accept!=(EX_LANES'(1)<<(EX_LANES-1)))
        $fatal(1,"stale same-slot token suppressed a live result");
      tick();@(negedge clk);i_result_valid='0;
      wait_value(0,71);wait_retired(0);
      if(trap_count || o_exception_pending) $fatal(1,"stale duplicate fault escaped");
      $display("parallel duplicate priority, payload and stale-generation isolation PASS");
      // Move a two-source consumer across completion/Ready/dispatch edges.
      // Both banks must wake it whether it enters before or after the pulse.
      for(int skew=0;skew<8;skew++) begin
        restart();send(0,0,0,0,0,0,1);send(4,0,0,0,0,0,2);
        wait_issue(0);wait_issue(4);
        fork
          begin
            @(negedge clk);i_result_valid='0;i_result_valid[1:0]=2'b11;i_result_fault='0;
            i_result_token[0 +: TOKEN_W]=tokens[0];i_result_token[TOKEN_W +: TOKEN_W]=tokens[1];
            i_result_data[0 +: DATA_W]=101;i_result_data[DATA_W +: DATA_W]=202;
            #1;if(o_result_accept[1:0]!=2'b11) $fatal(1,"two-bank wake producers rejected");
            tick();@(negedge clk);i_result_valid='0;
          end
          begin tick(skew);send(8,0,0,0,0,1,3,1,2);end
        join
        wait_issue(8);
        if(registers[prs1[2]]!=101 || registers[prs2[2]]!=202)
          $fatal(1,"Ready raced RF write or lost a source skew=%d",skew);
        complete(8,303);wait_retired(8);
      end
      $display("two-source wake across completion and dispatch edges PASS");
      // Vary a younger completion relative to a recovering branch. Its Ready
      // pulse must not affect the restored mapping or a newly allocated life.
      for(int skew=0;skew<8;skew++) begin
        restart();send(0,0,0,1);send(4,0,0,0,0,1,1);wait_issue(0);wait_issue(4);
        fork
          begin
            // Each concurrent producer owns only its own lane.
            @(negedge clk);i_result_valid[0]=1;i_result_fault[0]=0;
            i_result_token[0 +: TOKEN_W]=tokens[0];i_result_data[0 +: DATA_W]=0;
            i_result_next[0 +: PC_W]=32'h800;
            #1;if(!o_result_accept[0]) $fatal(1,"recovering branch result rejected");
            tick();@(negedge clk);i_result_valid[0]=0;
          end
          begin
            tick(skew);@(negedge clk);
            i_result_valid[1]=1;i_result_fault[1]=0;
            i_result_token[TOKEN_W +: TOKEN_W]=tokens[1];i_result_data[DATA_W +: DATA_W]=99;
            tick();@(negedge clk);i_result_valid[1]=0;
          end
        join
        wait_flush();tick(PHY+8);
        if(retired[1]) $fatal(1,"younger wake retired across recovery");
        send(32'h800,0,0,0,0,0,1);send(32'h804,0,0,0,0,1,2,1);
        wait_issue(32'h800);tick(16);
        if(issued[32'h804/4]) $fatal(1,"old Ready woke a new physical register lifetime");
        complete(32'h800,47);wait_issue(32'h804);
        if(registers[prs1[32'h804/4]]!=47) $fatal(1,"post-recovery wake data mismatch");
        complete(32'h804,48);wait_retired(32'h804);
      end
      $display("Ready recovery overlap and new lifetime isolation PASS");
      // Admission can overlap result enqueue on the edge before the registered
      // fault stop. The extra younger instruction must still be discarded.
      restart();send(0,0,0,0,0,0,1);wait_issue(0);
      fork
        complete(0,0,0,1,5);
        send(4,0,0,0,0,1,2);
      join
      wait_flush();
      if(last_trap_pc!=0 || last_cause!=5 || retired[1]) $fatal(1,"fault/admission overlap broke precision");
      $display("registered fault stop and overlapping admission PASS");
      // Interrupt seals an otherwise incomplete frontend window.
      restart();send(0,0,0,0,0,0,1);complete(0,9);
      // Assert IRQ on the exact edge CHECK first sees the completed last row.
      i_interrupt=1;wait_flush();
      if(!last_interrupt || last_trap_pc!=4 || !retired[0]) $fatal(1,"partial window IRQ stalled");
      $display("parallel completion and partial-window interrupt PASS");
      // A load response outstanding at rollback is consumed without writing RF.
      restart();send(0,0,0,1);send(4,1,0,0,0,1,2);agu(4,32'h40);
      begin
        bit requested;requested=0;
        for(int t=0;t<1000;t++) begin if(loads==1) begin requested=1;break;end tick();end
        if(!requested) $fatal(1,"load request missing");
      end
      @(negedge clk);hold_bus=1;
      complete(0,0,32'h80);wait_flush();
      @(negedge clk);hold_bus=0;
      tick(15);if(registers[prd[1]]!=0) $fatal(1,"squashed load wrote physical register");
      send(32'h80,1,0,0,0,1,1);agu(32'h80,32'h44);wait_value(32'h80,32'h11223344);wait_retired(32'h80);
      $display("late memory response after recovery PASS");
      if(EXTERNAL_PREDICTOR) begin
        restart();
        // Supply a control bundle manually; neither absent nor stale predictions may admit it.
        @(negedge clk);i_decode_valid='0;i_decode_valid[0]=1;i_decode_pc='0;i_decode_epoch=o_fetch_epoch;
        i_decode_path='0;i_decode_write='0;i_decode_control='0;i_decode_control[0]=1;
        i_decode_memory='0;i_decode_store='0;i_decode_csr='0;i_decode_end='0;i_decode_exception='0;
        i_decode_rd='0;i_decode_rs='0;i_predict_valid=0;
        tick(5);if(|o_decode_get || o_fetch_pc!=0) $fatal(1,"missing predictor did not stall");
        @(negedge clk);i_predict_valid=1;i_predict_pc=0;i_predict_next=32'h80;i_predict_epoch=o_fetch_epoch+1'b1;
        tick(5);if(|o_decode_get || o_fetch_pc!=0) $fatal(1,"stale predictor accepted");
        @(negedge clk);i_predict_epoch=o_fetch_epoch;
        begin
          bit accepted;accepted=0;
          for(int t=0;t<100;t++) begin @(posedge clk);if(o_decode_get[0]) begin accepted=1;break;end end
          if(!accepted) $fatal(1,"custom prediction rejected");
        end
        @(negedge clk);i_decode_valid='0;i_predict_valid=0;
        if(o_fetch_pc!=32'h80) $fatal(1,"custom target ignored");
        complete(0,0,32'h80);wait_retired(0);tick(5);
        if(flush_count) $fatal(1,"correct custom prediction recovered");
        $display("external-only predictor handshake PASS");
      end
      // Preserve both old architectural state and a retiring branch link register.
      restart();send(0,0,0,0,0,1,1);complete(0,11);wait_retired(0);
      send(4,0,0,1,0,0,2);send(8,0,0,0,0,1,1);complete(8,99);
      complete(4,8,32'h80);wait_flush();
      send(32'h80,0,0,0,0,1,3,1,2);wait_issue(32'h80);
      if(registers[prs1[32]]!=11 || registers[prs2[32]]!=8) $fatal(1,"committed mapping rollback failed");
      complete(32'h80,19);wait_retired(32'h80);
      // An unresolved store address cannot be bypassed by a younger load.
      restart();send(0,1,1);send(4,1,0,0,0,1,1);agu(4,32'h40);tick(20);
      if(loads || stores) $fatal(1,"load bypassed unresolved older store");
      agu(0,32'h40,88);wait_value(4,88);wait_retired(4);
      // Non-speculative MMIO store establishes the same ordered boundary as a read.
      restart();send(0,1,1);send(4,1,1,0,0,1);
      agu(4,32'h100,66,15,1);tick(20);if(stores) $fatal(1,"MMIO store bypassed predecessor");
      agu(0,32'h40,55);wait_retired(4);
      if(stores!=2 || memory_words[16]!=55 || memory_words[64]!=66) $fatal(1,"MMIO store failed");
      $display("rename recovery, unresolved store and MMIO store PASS");
      // Reuse table slots and physical registers several times.
      restart();
      for(int n=0;n<ENTRIES*3;n++) begin
        send(n*4,0,0,0,0,1,1);
        if(n==ENTRIES) begin
          wait_issue(n*4);@(negedge clk);i_result_valid[0]=1;i_result_token[0 +: TOKEN_W]=tokens[0];
          #1;if(o_result_accept[0]) $fatal(1,"ABA stale completion accepted at reused slot");
          tick();@(negedge clk);i_result_valid='0;
        end
        complete(n*4,n+1);wait_retired(n*4);
      end
      if(dut.U_NEL.U_RENAME.committed[1]==0) $fatal(1,"committed rename lost");
      $display("slot and physical register reuse PASS");
      // Open windows must make progress even when the configured maximum is
      // larger than available table slots or free physical registers.
      restart();
      for(int n=0;n<ENTRIES*2;n++) begin
        send(n*4,0,0,0,0,n==ENTRIES*2-1,1);complete(n*4,n+1);
      end
      wait_retired((ENTRIES*2-1)*4);
      $display("resource-pressure partial window sealing PASS");
      // Fill the frontier without completing it, then capture one more bundle.
      // Its inputs are deliberately changed while held. A producer completes
      // during the stall; the consumer must observe that Ready state on rename.
      restart();
      begin
        int limit;
        limit=ENTRIES-DECODE+1;
        for(int n=0;n<limit;n++) send(n*4,0,0,0,0,0,n==0?1:0);
        send(limit*4,0,0,0,0,1,2,1);
        i_decode_pc='1;i_decode_path='1;i_decode_uop='1;i_decode_imm='1;
        i_decode_rd='1;i_decode_rs='1;i_decode_memory='1;i_decode_store='1;
        i_decode_csr='1;i_decode_control='1;i_decode_exception='1;
        tick(8);
        if(issued[limit] || stores || loads) $fatal(1,"held decode bypassed full frontier");
        complete(0,73);tick(8);
        if(issued[limit]) $fatal(1,"held decode bypassed unfinished window");
        for(int n=1;n<limit;n++) complete(n*4);
        wait_issue(limit*4);
        if(registers[prs1[limit]]!=73 || seen_imm[limit]!=0 || seen_uop[limit]!=0 ||
           seen_flow[limit]!=FLOW_W'(((limit+WINDOW_SIZE-1)/WINDOW_SIZE)%WINDOWS))
          $fatal(1,"held decode payload, WBC readiness or resealed flow was lost");
        complete(limit*4,74);wait_retired(limit*4);
      end
      $display("decode buffer backpressure, payload isolation and WBC readiness PASS");
      // A rollback must drop a captured bundle that has no allocated token yet.
      restart();
      begin
        int limit;
        limit=ENTRIES-DECODE+1;
        send(0,0,0,1);
        for(int n=1;n<limit;n++) send(n*4);
        send(limit*4,1,1,0,0,1);
        tick(8);if(issued[limit]) $fatal(1,"decode buffer was not held for recovery test");
        complete(0,0,32'h800);wait_flush();tick(PHY+8);
        if(issued[limit] || stores || loads) $fatal(1,"squashed decode escaped after recovery");
        send(32'h800,0,0,0,0,1,1);complete(32'h800,91);wait_retired(32'h800);
      end
      $display("flush discards captured unallocated decode PASS");
      // Capture advanced fetch PC, but no instruction has entered the frontier.
      // An IRQ here must resume at the first unallocated instruction, not PC+4.
      restart();send(0,0,0,0,0,1,1);i_interrupt=1;wait_flush();
      if(!last_interrupt || last_trap_pc!=0 || issued[0]) $fatal(1,"IRQ lost captured decode boundary");
      $display("interrupt between decode capture and allocation PASS");
      // A WBC wakes a batch of IST waiters into a stalled RS. No instruction
      // may disappear, issue twice, or accept a result before the EX handshake.
      restart();send(0,0,0,0,0,0,1);wait_issue(0);
      for(int e=1;e<EX_LANES-1;e++) block_ex[e]=1;
      // Stay below the smallest PRM wait-list capacity until WBC arrives.
      for(int n=1;n<=6;n++) send(n*4,0,0,0,0,0,0,1);
      complete(0,77);
      for(int n=7;n<=12;n++) send(n*4,0,0,0,0,n==12,0,1);
      tick(32);
      for(int n=1;n<=12;n++) if(issued[n]) $fatal(1,"stalled RS instruction issued");
      begin
        int lane;
        lane=-1;
        for(int e=1;e<EX_LANES-1;e++) if(o_ex_valid[e]) lane=e;
        if(lane<0) $fatal(1,"WBC failed to fill stalled RS outputs");
        @(negedge clk);i_result_valid='0;i_result_valid[0]=1;i_result_fault='0;
        i_result_token[0 +: TOKEN_W]=o_ex_token[lane*TOKEN_W +: TOKEN_W];
        #1;if(o_result_accept[0]) $fatal(1,"unissued RS token accepted as completion");
        tick();@(negedge clk);i_result_valid='0;block_ex[1]=0;
      end
      tick(12);@(negedge clk);block_ex='0;
      for(int n=1;n<=12;n++) complete(n*4);
      wait_retired(48);tick(12);
      $display("single RS ownership through WBC and asymmetric EX stalls PASS");
      // Release EX backpressure on the flush edge: neither held output heads
      // nor queued RS contents may escape. Reuse a cancelled token's slot.
      restart();send(0,0,0,1);wait_issue(0);
      for(int e=1;e<EX_LANES-1;e++) block_ex[e]=1;
      for(int n=1;n<=FLUSH_WAITERS;n++) send(n*4,0,0,0,0,n==FLUSH_WAITERS);
      tick(32);
      begin
        logic [TOKEN_W-1:0] cancelled;
        int lane,slot;
        lane=-1;
        for(int e=1;e<EX_LANES-1;e++) if(o_ex_valid[e]) lane=e;
        if(lane<0) $fatal(1,"no held RS output for flush test");
        cancelled=o_ex_token[lane*TOKEN_W +: TOKEN_W];slot=int'(cancelled[SLOT_W-1:0]);
        complete(0,0,32'h800);
        for(int t=0;t<1000 && !o_flush;t++) tick();
        if(!o_flush) $fatal(1,"branch did not request flush");
        @(negedge clk);block_ex='0;#1;i_ex_get='1;
        #1;if(|o_ex_valid) $fatal(1,"backpressure release exposed a flushed instruction");
        wait_flush();tick(PHY+8);
        for(int n=1;n<=FLUSH_WAITERS;n++) if(issued[n]) $fatal(1,"cancelled RS entry survived flush");
        for(int n=0;n<=slot;n++) begin
          send(32'h800+n*4,0,0,0,0,1,1);wait_issue(32'h800+n*4);
          if(n==slot) begin
            @(negedge clk);i_result_valid='0;i_result_valid[0]=1;i_result_fault='1;
            i_result_token[0 +: TOKEN_W]=cancelled;
            #1;if(o_result_accept[0]) $fatal(1,"stale completion passed after cancelled RS slot reuse");
            tick();@(negedge clk);i_result_valid='0;
          end
          complete(32'h800+n*4,n+1);wait_retired(32'h800+n*4);
        end
        if(trap_count || o_exception_pending) $fatal(1,"cancelled result caused an exception");
      end
      $display("flush kills stalled RS heads and queued entries before slot reuse PASS");
      // Ordered CSR shares an EX port only after every older RS entry drained.
      restart();send(0,0,0,0,0,0,1);wait_issue(0);
      send(4,0,0,0,1,1,2,1);block_ex='1;complete(0,31);tick(32);
      if(!retired[0] || issued[1] || !(|(o_ex_valid & o_ex_csr))) $fatal(1,"ordered CSR did not wait on EX backpressure");
      @(negedge clk);block_ex='0;complete(4,32);wait_retired(4);
      $display("ordered CSR output holds while RS is empty PASS");
      // Public-interface cycle comparison, also run on the preserved netlist.
      // Scripted completion latency and periodic EX stalls are identical.
      for(int mode=0;mode<2;mode++) begin
        int started;
        restart();started=cycle_count;
        fork
          begin
            for(int n=0;n<32;n++) send(n*4,0,0,0,0,n==31,mode?1:0,mode?1:0);
          end
          begin
            for(int n=0;n<32;n++) complete(n*4,n+1);
          end
        join
        wait_retired(124);
        if(mode) wait_value(124,32);
        $display("PERF mode=%0d instructions=32 cycles=%0d",mode,cycle_count-started);
      end
      i_reset_pc=32'h100;restart();
      if(o_fetch_pc!=32'h100) $fatal(1,"boot PC was not sampled synchronously");
      @(negedge clk);i_interrupt=1;wait_flush();
      if(last_trap_pc!=32'h100) $fatal(1,"idle interrupt lost nonzero boot PC");
      $display("nonzero boot PC and idle interrupt PASS");
      $display("tb_oryukdo_scheduler PASS");$finish;
    end
endmodule

// Test-only user implementation; never compile alongside the example template.
module oryukdo_custom_lsq #(
    parameter int DEPTH=128, LANES=2, ADDR_W=32, DATA_W=32, GEN_W=32, CAUSE_W=5,
    localparam int SLOT_W=(DEPTH>1)?$clog2(DEPTH):1,
    localparam int TOKEN_W=SLOT_W+GEN_W, BYTES=DATA_W/8
) (
    input wire clk, reset_n, i_flush,
    // Preview only: no allocation side effects until i_allocate.
    input wire [LANES-1:0] i_reserve,
    output wire o_allocate_ready,
    input wire [LANES-1:0] i_allocate, i_memory, i_store,
    input wire [LANES*TOKEN_W-1:0] i_token,
    input wire i_agu_valid,
    output wire o_agu_ready,
    input wire [TOKEN_W-1:0] i_agu_token,
    input wire [ADDR_W-1:0] i_agu_address,
    input wire [DATA_W-1:0] i_agu_data,
    input wire [BYTES-1:0] i_agu_mask,
    input wire i_agu_nonspec, i_agu_fault,
    input wire [CAUSE_W-1:0] i_agu_cause,
    output wire o_serial_valid,
    output wire [TOKEN_W-1:0] o_serial_token,
    input wire i_head_valid,
    input wire [TOKEN_W-1:0] i_head_token,
    input wire i_commit_valid, i_commit_store, i_retire,
    input wire [TOKEN_W-1:0] i_commit_token,
    output wire o_commit_ready,
    output logic o_complete_valid,
    input wire i_complete_accept,
    output logic [TOKEN_W-1:0] o_complete_token,
    output logic [DATA_W-1:0] o_complete_data,
    output logic o_complete_fault,
    output logic [CAUSE_W-1:0] o_complete_cause,
    output wire o_request_valid,
    input wire i_request_ready,
    output wire o_request_store,
    output wire [ADDR_W-1:0] o_request_address,
    output wire [DATA_W-1:0] o_request_data,
    output wire [BYTES-1:0] o_request_mask,
    input wire i_response_valid,
    output wire o_response_ready,
    input wire [DATA_W-1:0] i_response_data,
    input wire i_response_fault,
    input wire [CAUSE_W-1:0] i_response_cause,
    output logic o_store_fault,
    output logic [TOKEN_W-1:0] o_store_fault_token,
    output logic [CAUSE_W-1:0] o_store_fault_cause
);
    logic block_allocate=0, block_agu=0;
    wire reference_agu_ready;
    assign o_allocate_ready=!block_allocate;
    assign o_agu_ready=reference_agu_ready && !block_agu;
    always @(posedge clk) if(reset_n && !i_flush) begin
        assert((i_allocate & ~i_reserve)=='0) else $fatal(1,"Allocation outside preview");
        assert(o_allocate_ready || i_allocate=='0) else $fatal(1,"Allocation ignored custom backpressure");
    end
    oryukdo_memory #(.DEPTH(DEPTH),.LANES(LANES),.ADDR_W(ADDR_W),
        .DATA_W(DATA_W),.GEN_W(GEN_W),.CAUSE_W(CAUSE_W)) U_REFERENCE (
        .clk(clk),
        .reset_n(reset_n),
        .i_flush(i_flush),
        .i_allocate(i_allocate),
        .i_memory(i_memory),
        .i_store(i_store),
        .i_token(i_token),
        .i_agu_valid(i_agu_valid && !block_agu),
        .o_agu_ready(reference_agu_ready),
        .i_agu_token(i_agu_token),
        .i_agu_address(i_agu_address),
        .i_agu_data(i_agu_data),
        .i_agu_mask(i_agu_mask),
        .i_agu_nonspec(i_agu_nonspec),
        .i_agu_fault(i_agu_fault),
        .i_agu_cause(i_agu_cause),
        .o_serial_valid(o_serial_valid),
        .o_serial_token(o_serial_token),
        .i_head_valid(i_head_valid),
        .i_head_token(i_head_token),
        .i_commit_valid(i_commit_valid),
        .i_commit_store(i_commit_store),
        .i_retire(i_retire),
        .i_commit_token(i_commit_token),
        .o_commit_ready(o_commit_ready),
        .o_complete_valid(o_complete_valid),
        .i_complete_accept(i_complete_accept),
        .o_complete_token(o_complete_token),
        .o_complete_data(o_complete_data),
        .o_complete_fault(o_complete_fault),
        .o_complete_cause(o_complete_cause),
        .o_request_valid(o_request_valid),
        .i_request_ready(i_request_ready),
        .o_request_store(o_request_store),
        .o_request_address(o_request_address),
        .o_request_data(o_request_data),
        .o_request_mask(o_request_mask),
        .i_response_valid(i_response_valid),
        .o_response_ready(o_response_ready),
        .i_response_data(i_response_data),
        .i_response_fault(i_response_fault),
        .i_response_cause(i_response_cause),
        .o_store_fault(o_store_fault),
        .o_store_fault_token(o_store_fault_token),
        .o_store_fault_cause(o_store_fault_cause)
    );
endmodule
