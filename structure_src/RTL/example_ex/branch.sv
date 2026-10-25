`timescale 1ns / 1ps
module branch_ex #(
    parameter EX_PATH_NUM           = 3,
    parameter INST_OPREANDS         = 2,
    parameter MICROOP_WIDTH         = 5, // Micro-OP is not contained information of EX_PATH
    parameter PHYREG_NUM            = 64,
    parameter FCL_RB_NUM            = 8,
    parameter INST_PC_WIDTH         = 32,

    // (Autogenerate) Elements
    localparam BITWIDTH_PHYREG_NUM   = $clog2(PHYREG_NUM),
    localparam BITWIDTH_EX_PATH_NUM  = $clog2(EX_PATH_NUM),
    localparam BITWIDTH_FCL_RB_NUM   = $clog2(FCL_RB_NUM),
    localparam BITWIDTH_FCL_PC_WIDTH = BITWIDTH_FCL_RB_NUM + INST_PC_WIDTH
) (
	input                                    run_i,
	input        [MICROOP_WIDTH-1:0]         microop_i,
	input        [31:0] 			         rs1_i,
	input        [31:0] 			         rs2_i,
	input        [31:0] 			         imm_i,
	input        [BITWIDTH_FCL_PC_WIDTH-1:0] pc_i,
	output logic [31:0] 	                 new_pc_o,
	output logic [31:0] 	                 return_pc_o,
	output logic                             we_o,
	output logic                             branch_o,
	output logic                             done_o
);

	always_comb begin
		case(microop_i)
			5'b0_0_000: begin // BEQ
                new_pc_o = pc_i[INST_PC_WIDTH-1:0] + imm_i;
                return_pc_o = 0;
				we_o = 1'b0;
                branch_o = (rs1_i == rs2_i)? run_i : 1'b0;
				done_o = run_i;
			end
			5'b0_0_001: begin // BNE
                new_pc_o = pc_i[INST_PC_WIDTH-1:0] + imm_i;
                return_pc_o = 0;
				we_o = 1'b0;
                branch_o = (rs1_i != rs2_i)? run_i : 1'b0;
				done_o = run_i;
			end
			5'b0_0_100: begin // BLT
                new_pc_o = pc_i[INST_PC_WIDTH-1:0] + imm_i;
                return_pc_o = 0;
				we_o = 1'b0;
                branch_o = ($signed(rs1_i) < $signed(rs2_i))? run_i : 1'b0;
				done_o = run_i;
			end
			5'b0_0_101: begin // BGE
                new_pc_o = pc_i[INST_PC_WIDTH-1:0] + imm_i;
                return_pc_o = 0;
				we_o = 1'b0;
                branch_o = ($signed(rs1_i) >= $signed(rs2_i))? run_i : 1'b0;
				done_o = run_i;
			end
			5'b0_0_110: begin // BLTU
                new_pc_o = pc_i[INST_PC_WIDTH-1:0] + imm_i;
                return_pc_o = 0;
				we_o = 1'b0;
                branch_o = (rs1_i < rs2_i)? run_i : 1'b0;
				done_o = run_i;
			end
			5'b0_0_111: begin // BGEU
                new_pc_o = pc_i[INST_PC_WIDTH-1:0] + imm_i;
                return_pc_o = 0;
				we_o = 1'b0;
                branch_o = (rs1_i >= rs2_i)? run_i : 1'b0;
				done_o = run_i;
			end
			5'b0_1_000: begin // Jump Reg
                new_pc_o = rs1_i + imm_i;
                return_pc_o = pc_i+4;
				we_o = run_i;
                branch_o = run_i;
				done_o = run_i;
            end
			5'b1_1_001: begin // AUIPC
                new_pc_o = 0;
                return_pc_o = pc_i+imm_i;
				we_o = run_i;
                branch_o = 1'b0;
				done_o = run_i;
			end
			5'b1_1_010: begin // JAL
                new_pc_o = 0;
                return_pc_o = pc_i+4;
				we_o = run_i;
                branch_o = 1'b0;
				done_o = run_i;
			end

			default: begin
				new_pc_o = 32'b0;
                return_pc_o = 0;
				we_o = 1'b0;
                branch_o = 1'b0;
				done_o = 1'b0;
			end
		endcase
	end

endmodule