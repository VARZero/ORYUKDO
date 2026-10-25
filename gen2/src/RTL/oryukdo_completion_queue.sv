`timescale 1ns/1ps
// One small FIFO per producer. Each slot-parity bank drains one head/cycle.
// Only FIFO heads are arbitrated; instruction identities are never CAM-searched.
module oryukdo_completion_queue #(
    parameter int LANES=6, DEPTH=2, TOKEN_W=37, DATA_W=32, PC_W=32, CAUSE_W=5,
    localparam int SOURCE_W=(LANES>1)?$clog2(LANES):1,
    localparam int PTR_W=(DEPTH>1)?$clog2(DEPTH):1,
    localparam int COUNT_W=$clog2(DEPTH+1),
    localparam int PACKET_W=TOKEN_W+DATA_W+PC_W+CAUSE_W+1
) (
    input wire clk, reset_n, i_flush,
    input wire [LANES-1:0] i_valid, i_fault,
    output wire [LANES-1:0] o_ready,
    input wire [LANES*TOKEN_W-1:0] i_token,
    input wire [LANES*DATA_W-1:0] i_data,
    input wire [LANES*PC_W-1:0] i_next,
    input wire [LANES*CAUSE_W-1:0] i_cause,
    output logic [1:0] o_valid, o_fault,
    input wire [1:0] i_get,
    output logic [2*TOKEN_W-1:0] o_token,
    output logic [2*DATA_W-1:0] o_data,
    output logic [2*PC_W-1:0] o_next,
    output logic [2*CAUSE_W-1:0] o_cause,
    output logic [2*SOURCE_W-1:0] o_source
);
    logic [PACKET_W-1:0] packets[LANES][DEPTH];
    logic [PTR_W-1:0] rd[LANES], wr[LANES];
    logic [COUNT_W-1:0] count[LANES];
    logic [SOURCE_W-1:0] turn[2];
    logic [LANES-1:0] pop;
    wire [PACKET_W-1:0] heads[LANES];
    logic [1:0] selected_valid, stage_valid;
    logic [PACKET_W-1:0] selected_packet[2], stage_packet[2];
    logic [SOURCE_W-1:0] selected_source[2], stage_source[2];
    wire [1:0] can_take=~stage_valid | i_get;
    function automatic [PTR_W-1:0] step(input [PTR_W-1:0] p);
        return int'(p)==DEPTH-1 ? '0 : p+1'b1;
    endfunction
    for(genvar lane=0;lane<LANES;lane++) begin: G_FIFO
        assign heads[lane]=packets[lane][rd[lane]];
        assign o_ready[lane]=reset_n && !i_flush && count[lane]<DEPTH;
        // Payload storage has no reset; validity is entirely in count.
        always_ff @(posedge clk) if(i_valid[lane] && o_ready[lane])
            packets[lane][wr[lane]]<={i_fault[lane],i_cause[lane*CAUSE_W +: CAUSE_W],
                i_next[lane*PC_W +: PC_W],i_data[lane*DATA_W +: DATA_W],i_token[lane*TOKEN_W +: TOKEN_W]};
        always_ff @(posedge clk or negedge reset_n) begin
            if(!reset_n) begin rd[lane]<='0; wr[lane]<='0; count[lane]<='0; end
            else if(i_flush) begin rd[lane]<='0; wr[lane]<='0; count[lane]<='0; end
            else begin
                if(i_valid[lane] && o_ready[lane]) wr[lane]<=step(wr[lane]);
                if(pop[lane]) rd[lane]<=step(rd[lane]);
                case({i_valid[lane] && o_ready[lane],pop[lane]})
                    2'b10: count[lane]<=count[lane]+1'b1;
                    2'b01: count[lane]<=count[lane]-1'b1;
                    default: begin end
                endcase
            end
        end
    end
    always_comb begin
        integer candidate;
        logic [PACKET_W-1:0] packet;
        logic [LANES-1:0] grant;
        logic found;
        selected_valid='0; pop='0;
        candidate=0; packet='0; grant='0; found=0;
        for(int bank=0;bank<2;bank++) begin
            grant='0; found=0; selected_source[bank]='0;
            // Arbitrate only narrow request bits. Do not rotate/select the
            // entire wide packet once for every round-robin candidate.
            for(int offset=0;offset<LANES;offset++) begin
                candidate=int'(turn[bank])+offset;
                if(candidate>=LANES) candidate=candidate-LANES;
                if(reset_n && !i_flush && !found && count[candidate]!=0 && heads[candidate][0]==1'(bank)) begin
                    grant[candidate]=1; found=1;
                end
            end
            // One shared head read per FIFO, followed by one one-hot data mux.
            packet='0;
            for(int lane=0;lane<LANES;lane++) begin
                packet=packet | (heads[lane] & {PACKET_W{grant[lane]}});
                selected_source[bank]=selected_source[bank] |
                    (SOURCE_W'(lane) & {SOURCE_W{grant[lane]}});
                pop[lane]=pop[lane] || (grant[lane] && can_take[bank]);
            end
            selected_valid[bank]=found;
            selected_packet[bank]=packet;
        end
    end
    always_comb begin
        o_valid=stage_valid & {2{reset_n && !i_flush}};
        o_fault='0; o_token='0; o_data='0; o_next='0; o_cause='0; o_source='0;
        for(int bank=0;bank<2;bank++) begin
            {o_fault[bank],o_cause[bank*CAUSE_W +: CAUSE_W],o_next[bank*PC_W +: PC_W],
             o_data[bank*DATA_W +: DATA_W],o_token[bank*TOKEN_W +: TOKEN_W]}=stage_packet[bank];
            o_source[bank*SOURCE_W +: SOURCE_W]=stage_source[bank];
            // Make the physical bank selection explicit to synthesis.
            o_token[bank*TOKEN_W]=1'(bank);
        end
    end
    always_ff @(posedge clk or negedge reset_n) begin
        if(!reset_n) begin
            stage_valid<='0;
            for(int bank=0;bank<2;bank++) begin turn[bank]<='0;stage_packet[bank]<='0;stage_source[bank]<='0;end
        end else if(i_flush) begin turn[0]<='0; turn[1]<='0; stage_valid<='0; end
        else for(int bank=0;bank<2;bank++) if(can_take[bank]) begin
            stage_valid[bank]<=selected_valid[bank];
            if(selected_valid[bank]) begin
                stage_packet[bank]<=selected_packet[bank];
                stage_source[bank]<=selected_source[bank];
                turn[bank]<=int'(selected_source[bank])==LANES-1 ? '0 : selected_source[bank]+1'b1;
            end
        end
    end
    initial if(LANES<1 || DEPTH<1 || TOKEN_W<2) $fatal(1,"Invalid completion FIFO dimensions");
endmodule
