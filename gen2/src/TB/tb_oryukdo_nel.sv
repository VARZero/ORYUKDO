`timescale 1ns/1ps
module tb_oryukdo_nel;
    localparam int PC_W=32,TOKEN_W=12,FLOW_W=3,PATH_W=2,UOP_W=5,IMM_W=32;
    localparam int ARCH=8,PHY=16,LANES=1,RESULTS=2,ARCH_W=3,PHY_W=4;
    localparam int EX_W=PC_W+TOKEN_W+FLOW_W+PATH_W+UOP_W+IMM_W+3*PHY_W,INT_W=EX_W+2;
    logic clk=0,reset_n=0,i_flush=0,i_accept=0,i_dispatch=0;
    logic [0:0] i_valid='0,i_write='0,i_exception='0,i_csr='0;
    logic [2:0] i_rd='0;
    logic [5:0] i_rs='0;
    logic [31:0] i_pc='0,i_imm='0;
    logic [11:0] i_token='0;
    logic [2:0] i_flow='0;
    logic [1:0] i_path='0;
    logic [4:0] i_uop='0;
    logic [1:0] i_done='0;
    logic [7:0] i_done_phy='0;
    logic i_retire_write=0;
    logic [2:0] i_retire_arch='0;
    logic [3:0] i_retire_phy='0;
    wire o_rename_ready,o_initializing;
    wire [3:0] o_rd;
    wire [7:0] o_rs;
    wire [1:0] o_rs_ready;
    wire [0:0] o_dispatch_valid;
    wire [INT_W-1:0] o_dispatch_data;
    logic [3:0] producer;
    oryukdo_new_entry_logic #(.TOKEN_W(TOKEN_W),.ARCH(ARCH),.PHY(PHY),.LANES(LANES),.RESULTS(RESULTS)) dut(.*);
    always #5 clk=~clk;
    task automatic tick; @(posedge clk);#1;endtask
    initial begin
        repeat(3) @(negedge clk);reset_n=1;
        repeat(PHY+2) tick();
        @(negedge clk);i_valid=1;i_write=1;i_rd=1;i_accept=1;#1;
        if(!o_rename_ready) $fatal(1,"NEL not initialized");producer=o_rd;tick();
        @(negedge clk);i_valid=0;i_accept=0;i_dispatch=1;tick();
        @(negedge clk);i_dispatch=0;i_valid=1;i_write=1;i_rd=2;i_rs=6'(1);i_pc=4;i_token=1;i_accept=1;
        #1;if(o_rs[3:0]!=producer || o_rs_ready[0]) $fatal(1,"NEL dependency lookup failed");tick();
        @(negedge clk);i_valid=0;i_accept=0;
        repeat(5) tick();
        if(!o_dispatch_valid || o_dispatch_data[EX_W]) $fatal(1,"NEL did not hold unresolved operand");
        @(negedge clk);i_done=1;i_done_phy[3:0]=producer;#1;
        if(!o_dispatch_data[EX_W]) $fatal(1,"NEL missed same-edge WBC bypass");tick();
        @(negedge clk);i_done=0;repeat(3) tick();
        if(!o_dispatch_data[EX_W] || !o_dispatch_valid) $fatal(1,"NEL lost held WBC readiness");
        @(negedge clk);i_retire_write=1;i_retire_arch=1;i_retire_phy=producer;tick();
        @(negedge clk);i_retire_write=0;i_flush=1;tick();
        if(o_dispatch_valid) $fatal(1,"NEL failed to flush dispatch");
        @(negedge clk);i_flush=0;repeat(PHY+2) tick();
        @(negedge clk);i_valid=1;i_rd=3;i_rs=6'(1);#1;
        if(o_rs[3:0]!=producer || !o_rs_ready[0]) $fatal(1,"NEL committed mapping recovery failed");
        $display("tb_oryukdo_nel PASS held readiness, WBC bypass and recovery");$finish;
    end
endmodule
