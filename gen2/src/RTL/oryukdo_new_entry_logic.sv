`timescale 1ns/1ps
// ORYUKDO NEL: recoverable rename/operand readiness and the registered IST
// dispatch boundary. Fetch/window control remains outside, as with FCL.
module oryukdo_new_entry_logic #(
    parameter int PC_W=32, TOKEN_W=37, FLOW_W=3, PATH_W=2, UOP_W=5, IMM_W=32,
    parameter int ARCH=32, PHY=64, LANES=2, RESULTS=6,
    localparam int ARCH_W=$clog2(ARCH), PHY_W=$clog2(PHY),
    localparam int KEY_W=PC_W+TOKEN_W+FLOW_W,
    localparam int EX_W=KEY_W+PATH_W+UOP_W+IMM_W+3*PHY_W,
    localparam int INT_W=EX_W+2, RS_OFFSET=KEY_W+PATH_W+UOP_W+IMM_W+PHY_W
) (
    input wire clk, reset_n, i_flush, i_accept, i_dispatch,
    input wire [LANES-1:0] i_valid, i_write, i_exception, i_csr,
    input wire [LANES*ARCH_W-1:0] i_rd,
    input wire [LANES*2*ARCH_W-1:0] i_rs,
    input wire [LANES*PC_W-1:0] i_pc,
    input wire [LANES*TOKEN_W-1:0] i_token,
    input wire [LANES*FLOW_W-1:0] i_flow,
    input wire [LANES*PATH_W-1:0] i_path,
    input wire [LANES*UOP_W-1:0] i_uop,
    input wire [LANES*IMM_W-1:0] i_imm,
    input wire [RESULTS-1:0] i_done,
    input wire [RESULTS*PHY_W-1:0] i_done_phy,
    input wire i_retire_write,
    input wire [ARCH_W-1:0] i_retire_arch,
    input wire [PHY_W-1:0] i_retire_phy,
    output wire o_rename_ready, o_initializing,
    output wire [LANES*PHY_W-1:0] o_rd,
    output wire [LANES*2*PHY_W-1:0] o_rs,
    output wire [LANES*2-1:0] o_rs_ready,
    output logic [LANES-1:0] o_dispatch_valid,
    output logic [LANES*INT_W-1:0] o_dispatch_data
);
    logic [LANES*INT_W-1:0] buffered;
    oryukdo_rename #(.ARCH(ARCH),.PHY(PHY),.LANES(LANES),.RESULTS(RESULTS)) U_RENAME (
        .clk(clk),.reset_n(reset_n),.i_flush(i_flush),.i_valid(i_valid),.i_write(i_write),.i_accept(i_accept),
        .i_rd(i_rd),.i_rs(i_rs),.o_ready(o_rename_ready),.o_rd(o_rd),.o_rs(o_rs),.o_rs_ready(o_rs_ready),
        .i_done(i_done),.i_done_phy(i_done_phy),.i_retire_write(i_retire_write),
        .i_retire_arch(i_retire_arch),.i_retire_phy(i_retire_phy),.o_initializing(o_initializing));
    always_comb begin
        o_dispatch_data=buffered;
        // Refresh held operands, including writeback on the IST transfer edge.
        for(int lane=0;lane<LANES;lane++) for(int op=0;op<2;op++)
            for(int result_lane=0;result_lane<RESULTS;result_lane++)
                if(o_dispatch_valid[lane] && i_done[result_lane] &&
                   buffered[lane*INT_W+RS_OFFSET+op*PHY_W +: PHY_W]==i_done_phy[result_lane*PHY_W +: PHY_W])
                    o_dispatch_data[lane*INT_W+EX_W+op]=1;
    end
    always_ff @(posedge clk or negedge reset_n) begin
        if(!reset_n) begin o_dispatch_valid<='0; buffered<='0; end
        else if(i_flush) begin o_dispatch_valid<='0; buffered<='0; end
        else begin
            buffered<=o_dispatch_data;
            if(i_dispatch) o_dispatch_valid<='0;
            if(i_accept) for(int lane=0;lane<LANES;lane++) if(i_valid[lane]) begin
                o_dispatch_valid[lane]<=!i_exception[lane] && !i_csr[lane];
                buffered[lane*INT_W +: INT_W]<={o_rs_ready[lane*2 +: 2],o_rs[lane*2*PHY_W +: 2*PHY_W],
                    o_rd[lane*PHY_W +: PHY_W],i_imm[lane*IMM_W +: IMM_W],i_uop[lane*UOP_W +: UOP_W],
                    i_path[lane*PATH_W +: PATH_W],i_flow[lane*FLOW_W +: FLOW_W],
                    i_token[lane*TOKEN_W +: TOKEN_W],i_pc[lane*PC_W +: PC_W]};
            end
        end
    end
endmodule
