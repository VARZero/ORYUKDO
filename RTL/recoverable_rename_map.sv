`timescale 1ns/1ps
// The speculative map is updated by NEL. The committed map changes only at
// the ordered retirement frontier. Recovery restores the speculative map from
// committed state, including a branch that retires on the recovery edge.
module recoverable_rename_map #(
    parameter int ARCH_REGS = 32,
    parameter int PHYREGS = 64,
    parameter int READ_CHANNELS = 6,
    parameter int WRITE_CHANNELS = 2,
    localparam int ARCH_WIDTH = $clog2(ARCH_REGS),
    localparam int PHY_WIDTH = $clog2(PHYREGS)
) (
    input  wire clk,
    input  wire reset_n,
    input  wire i_recover,
    input  wire [READ_CHANNELS*ARCH_WIDTH-1:0] i_read_addr,
    output wire [READ_CHANNELS*PHY_WIDTH-1:0] o_read_data,
    input  wire [WRITE_CHANNELS*ARCH_WIDTH-1:0] i_write_addr,
    input  wire [WRITE_CHANNELS-1:0] i_write_en,
    input  wire [WRITE_CHANNELS*PHY_WIDTH-1:0] i_write_data,
    input  wire i_retire_write,
    input  wire [ARCH_WIDTH-1:0] i_retire_arch,
    input  wire [PHY_WIDTH-1:0] i_retire_phyreg,
    output wire o_retire_old_valid,
    output wire [PHY_WIDTH-1:0] o_retire_old_phyreg,
    output logic [PHYREGS-1:0] o_reserved_phyreg
);
    logic [PHY_WIDTH-1:0] speculative [0:ARCH_REGS-1];
    logic [PHY_WIDTH-1:0] committed [0:ARCH_REGS-1];
    assign o_retire_old_phyreg = committed[i_retire_arch];
    assign o_retire_old_valid = i_retire_write &&
        o_retire_old_phyreg != '0 && o_retire_old_phyreg != i_retire_phyreg;

    for (genvar read_lane = 0; read_lane < READ_CHANNELS; read_lane++) begin : GEN_READ
        assign o_read_data[read_lane*PHY_WIDTH +: PHY_WIDTH] =
            speculative[i_read_addr[read_lane*ARCH_WIDTH +: ARCH_WIDTH]];
    end

    always_comb begin
        o_reserved_phyreg = '0;
        o_reserved_phyreg[0] = 1'b1;
        for (int arch = 0; arch < ARCH_REGS; arch++) begin
            if (i_retire_write && int'(i_retire_arch) == arch)
                o_reserved_phyreg[i_retire_phyreg] = 1'b1;
            else
                o_reserved_phyreg[committed[arch]] = 1'b1;
        end
    end

    for (genvar arch = 0; arch < ARCH_REGS; arch++) begin : GEN_MAP
        always_ff @(posedge clk or negedge reset_n) begin
            if (!reset_n) begin
                speculative[arch] <= '0;
                committed[arch] <= '0;
            end else begin
                if (i_retire_write && i_retire_arch == ARCH_WIDTH'(arch))
                    committed[arch] <= i_retire_phyreg;
                if (i_recover) begin
                    speculative[arch] <= (i_retire_write && i_retire_arch == ARCH_WIDTH'(arch)) ?
                                         i_retire_phyreg : committed[arch];
                end else begin
                    for (int lane = 0; lane < WRITE_CHANNELS; lane++) begin
                        if (i_write_en[lane] &&
                            i_write_addr[lane*ARCH_WIDTH +: ARCH_WIDTH] == ARCH_WIDTH'(arch))
                            speculative[arch] <= i_write_data[lane*PHY_WIDTH +: PHY_WIDTH];
                    end
                end
            end
        end
    end
endmodule
