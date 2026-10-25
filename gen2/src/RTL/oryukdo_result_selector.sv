`timescale 1ns/1ps
// Parallel duplicate suppression. A blocked earlier FIFO cannot suppress a
// later ready producer. Token eligibility is applied after selection: equal
// tokens must have equal eligibility, independent of their producer lane.
module oryukdo_result_selector #(
    parameter int LANES=5, TOKEN_W=37
) (
    input wire [LANES-1:0] i_valid, i_ready,
    input wire [LANES*TOKEN_W-1:0] i_token,
    output wire [LANES-1:0] o_selected
);
    for(genvar lane=0;lane<LANES;lane++) begin: G_LANE
        wire [LANES-1:0] earlier_duplicate;
        for(genvar prior=0;prior<LANES;prior++) begin: G_COMPARE
            if(prior<lane) begin
                assign earlier_duplicate[prior]=i_valid[prior] && i_ready[prior] &&
                    i_token[prior*TOKEN_W +: TOKEN_W]==i_token[lane*TOKEN_W +: TOKEN_W];
            end else assign earlier_duplicate[prior]=1'b0;
        end
        assign o_selected[lane]=i_valid[lane] && !(|earlier_duplicate);
    end
    initial if(LANES<1 || TOKEN_W<1) $fatal(1,"Invalid result selector dimensions");
endmodule
