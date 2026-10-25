`timescale 1ns/1ps
// Indexed rename maps and FIFO free list. Recovery rebuilds the free list one
// register/cycle; it never selects free registers with a wide priority encoder.
module oryukdo_rename #(
    parameter int ARCH=32, PHY=64, LANES=2, OPERANDS=2, RESULTS=6,
    localparam int ARCH_W=$clog2(ARCH), PHY_W=$clog2(PHY), COUNT_W=$clog2(PHY+1)
) (
    input wire clk, reset_n, i_flush,
    input wire [LANES-1:0] i_valid, i_write,
    input wire i_accept,
    input wire [LANES*ARCH_W-1:0] i_rd,
    input wire [LANES*OPERANDS*ARCH_W-1:0] i_rs,
    output wire o_ready,
    output logic [LANES*PHY_W-1:0] o_rd,
    output logic [LANES*OPERANDS*PHY_W-1:0] o_rs,
    output logic [LANES*OPERANDS-1:0] o_rs_ready,
    input wire [RESULTS-1:0] i_done,
    input wire [RESULTS*PHY_W-1:0] i_done_phy,
    input wire i_retire_write,
    input wire [ARCH_W-1:0] i_retire_arch,
    input wire [PHY_W-1:0] i_retire_phy,
    output wire o_initializing
);
    logic [PHY_W-1:0] speculative[ARCH], committed[ARCH];
    logic [PHY_W-1:0] free_queue[PHY];
    logic [PHY_W-1:0] read_ptr, write_ptr;
    logic [COUNT_W-1:0] free_count, build_index, need;
    logic [PHY-1:0] reserved, ready;
    logic building;
    wire [PHY_W-1:0] old_phy=committed[i_retire_arch];
    wire release_old=i_retire_write && i_retire_arch!=0 && old_phy!=0 && old_phy!=i_retire_phy;
    function automatic [PHY_W-1:0] offset(input [PHY_W-1:0] p,input int amount);
        return PHY_W'((int'(p)+amount)%PHY);
    endfunction
    always_comb begin
        logic [PHY_W-1:0] source;
        logic [ARCH_W-1:0] arch_source;
        need='0; o_rd='0; o_rs='0; o_rs_ready='0; source='0; arch_source='0;
        for(int lane=0;lane<LANES;lane++) begin
            if(i_valid[lane] && i_write[lane] && i_rd[lane*ARCH_W +: ARCH_W]!=0) begin
                o_rd[lane*PHY_W +: PHY_W]=free_queue[offset(read_ptr,int'(need))];
                need++;
            end
            for(int op=0;op<OPERANDS;op++) begin
                arch_source=i_rs[(lane*OPERANDS+op)*ARCH_W +: ARCH_W];
                source=speculative[arch_source];
                if(arch_source==0) source='0;
                for(int prior=0;prior<lane;prior++)
                    if(i_valid[prior] && i_write[prior] && arch_source!=0 &&
                        i_rd[prior*ARCH_W +: ARCH_W]==arch_source)
                        source=o_rd[prior*PHY_W +: PHY_W];
                o_rs[(lane*OPERANDS+op)*PHY_W +: PHY_W]=source;
                o_rs_ready[lane*OPERANDS+op]=ready[source];
                for(int result_lane=0;result_lane<RESULTS;result_lane++)
                    if(i_done[result_lane] && i_done_phy[result_lane*PHY_W +: PHY_W]==source)
                        o_rs_ready[lane*OPERANDS+op]=1;
                for(int prior=0;prior<lane;prior++)
                    if(i_valid[prior] && i_write[prior] && arch_source!=0 &&
                        i_rd[prior*ARCH_W +: ARCH_W]==arch_source)
                        o_rs_ready[lane*OPERANDS+op]=0;
            end
        end
    end
    always_comb begin
        reserved='0; reserved[0]=1;
        for(int a=1;a<ARCH;a++) reserved[committed[a]]=1;
    end
    assign o_ready=reset_n && !i_flush && !building && free_count>=need;
    assign o_initializing=building;
    always_ff @(posedge clk or negedge reset_n) begin
        if(!reset_n) begin
            read_ptr<='0; write_ptr<='0; free_count<='0; build_index<=1;
            building<=1; ready<='1;
            for(int a=0;a<ARCH;a++) begin speculative[a]<='0; committed[a]<='0; end
        end else if(i_flush) begin
            building<=1; build_index<=1; read_ptr<='0; write_ptr<='0; free_count<='0; ready<='1;
            for(int a=0;a<ARCH;a++) speculative[a]<=committed[a];
        end else begin
            if(building) begin
                if(!reserved[PHY_W'(build_index)]) begin
                    free_queue[write_ptr]<=PHY_W'(build_index);
                    write_ptr<=offset(write_ptr,1); free_count<=free_count+1'b1;
                end
                if(int'(build_index)==PHY-1) building<=0;
                else build_index<=build_index+1'b1;
            end else begin
                free_count<=free_count-((i_accept && o_ready)?need:COUNT_W'(0))+COUNT_W'(release_old);
                if(release_old) begin free_queue[write_ptr]<=old_phy; write_ptr<=offset(write_ptr,1); end
                if(i_accept && o_ready) read_ptr<=offset(read_ptr,int'(need));
            end
            if(i_retire_write && i_retire_arch!=0) committed[i_retire_arch]<=i_retire_phy;
            for(int lane=0;lane<RESULTS;lane++) if(i_done[lane]) ready[i_done_phy[lane*PHY_W +: PHY_W]]<=1;
            if(i_accept && o_ready) for(int lane=0;lane<LANES;lane++)
                if(i_valid[lane] && i_write[lane] && i_rd[lane*ARCH_W +: ARCH_W]!=0) begin
                    speculative[i_rd[lane*ARCH_W +: ARCH_W]]<=o_rd[lane*PHY_W +: PHY_W];
                    ready[o_rd[lane*PHY_W +: PHY_W]]<=0;
                end
            ready[0]<=1;
        end
    end
    initial if(ARCH<2 || PHY<2 || LANES<1) $fatal(1,"Invalid rename dimensions");
endmodule
