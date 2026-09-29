`timescale 1ns/1ps
// Bitmap free list used by the recovery configuration. On rollback only
// committed-map physical registers remain reserved.
module recovery_phyreg_allocator #(
    parameter int PHYREGS = 64,
    parameter int ALLOCATE_CHANNELS = 2,
    parameter int UNALLOCATE_CHANNELS = 4,
    localparam int PHY_WIDTH = $clog2(PHYREGS)
) (
    input  wire clk,
    input  wire reset_n,
    input  wire i_restore,
    input  wire [PHYREGS-1:0] i_reserved,
    input  wire [UNALLOCATE_CHANNELS-1:0] i_unallocate,
    input  wire [UNALLOCATE_CHANNELS*PHY_WIDTH-1:0] i_unallocate_data,
    input  wire [ALLOCATE_CHANNELS-1:0] i_allocate,
    output logic [ALLOCATE_CHANNELS-1:0] o_allocate_valid,
    output logic [ALLOCATE_CHANNELS*PHY_WIDTH-1:0] o_allocate_data
);
    logic [PHYREGS-1:0] used, selected;
    always_comb begin
        selected = used;
        selected[0] = 1'b1;
        o_allocate_valid = '0;
        o_allocate_data = '0;
        for (int lane = 0; lane < ALLOCATE_CHANNELS; lane++) begin
            for (int preg = 1; preg < PHYREGS; preg++) begin
                if (!o_allocate_valid[lane] && !selected[preg]) begin
                    o_allocate_valid[lane] = 1'b1;
                    o_allocate_data[lane*PHY_WIDTH +: PHY_WIDTH] = PHY_WIDTH'(preg);
                    selected[preg] = 1'b1;
                end
            end
        end
    end
    always_ff @(posedge clk or negedge reset_n) begin
        if (!reset_n) used <= {{(PHYREGS-1){1'b0}},1'b1};
        else if (i_restore) used <= i_reserved | {{(PHYREGS-1){1'b0}},1'b1};
        else begin
            for (int lane = 0; lane < UNALLOCATE_CHANNELS; lane++) begin
                if (i_unallocate[lane] &&
                    i_unallocate_data[lane*PHY_WIDTH +: PHY_WIDTH] != 0)
                    used[i_unallocate_data[lane*PHY_WIDTH +: PHY_WIDTH]] <= 1'b0;
            end
            for (int lane = 0; lane < ALLOCATE_CHANNELS; lane++) begin
                if (i_allocate[lane] && o_allocate_valid[lane])
                    used[o_allocate_data[lane*PHY_WIDTH +: PHY_WIDTH]] <= 1'b1;
            end
        end
    end
endmodule
