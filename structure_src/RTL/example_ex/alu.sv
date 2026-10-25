`timescale 1ns / 1ps
module alu_ex #(
    parameter EX_PATH_NUM           = 3,
    parameter INST_OPREANDS         = 2,
    parameter MICROOP_WIDTH         = 5, // Micro-OP is not contained information of EX_PATH
    parameter PHYREG_NUM            = 64,

    // (Autogenerate) Elements
    localparam BITWIDTH_PHYREG_NUM  = $clog2(PHYREG_NUM),
    localparam BITWIDTH_EX_PATH_NUM = $clog2(EX_PATH_NUM)
) (
	input                                  run_i,
	input        [MICROOP_WIDTH-1:0]       microop_i,
	input        [31:0] 			       rs1_i,
	input        [31:0] 			       rs2_i,
	input        [31:0] 			       imm_i,
	output logic [31:0] 	               alu_result_o,
	output logic                           we_o,
	output logic                           done_o
);

	always_comb begin
		case(microop_i)
			5'b0_0_000: begin // ADD
				alu_result_o = rs1_i + rs2_i;
				we_o = run_i;
				done_o = run_i;
			end
			5'b0_1_000: begin // SUB
				alu_result_o = rs1_i - rs2_i;
				we_o = run_i;
				done_o = run_i;
			end
			5'b0_0_001: begin // SLL
				alu_result_o = rs1_i << rs2_i[4:0];
				we_o = run_i;
				done_o = run_i;
			end
			5'b0_0_010: begin // SLT
				alu_result_o = ( $signed(rs1_i) < $signed(rs2_i) )? 32'd1 : 32'b0;
				we_o = run_i;
				done_o = run_i;
			end
			5'b0_0_011: begin // SLTU
				alu_result_o = ( rs1_i < rs2_i )? 32'd1 : 32'b0;
				we_o = run_i;
				done_o = run_i;
			end
			5'b0_0_100: begin // XOR
				alu_result_o = rs1_i ^ rs2_i;
				we_o = run_i;
				done_o = run_i;
			end
			5'b0_0_101: begin // SRL
				alu_result_o = rs1_i >> rs2_i[4:0];
				we_o = run_i;
				done_o = run_i;
			end
			5'b0_1_101: begin // SRA
				alu_result_o = $signed(rs1_i) >>> rs2_i[4:0];
				we_o = run_i;
				done_o = run_i;
			end
			5'b0_0_110: begin // OR
				alu_result_o = rs1_i | rs2_i;
				we_o = run_i;
				done_o = run_i;
			end
			5'b0_0_111: begin // AND
				alu_result_o = rs1_i & rs2_i;
				we_o = run_i;
				done_o = run_i;
			end

			5'b1_0_000: begin // ADDI
				alu_result_o = rs1_i + imm_i;
				we_o = run_i;
				done_o = run_i;
			end
			5'b1_0_001: begin // SLLI
				alu_result_o = rs1_i << imm_i[4:0];
				we_o = run_i;
				done_o = run_i;
			end
			5'b1_0_010: begin // SLTI
				alu_result_o = ( $signed(rs1_i) < $signed(imm_i) )? 32'd1 : 32'b0;
				we_o = run_i;
				done_o = run_i;
			end
			5'b1_0_011: begin // SLTIU
				alu_result_o = ( rs1_i < imm_i )? 32'd1 : 32'b0;
				we_o = run_i;
				done_o = run_i;
			end
			5'b1_0_100: begin // XORI
				alu_result_o = rs1_i ^ imm_i;
				we_o = run_i;
				done_o = run_i;
			end
			5'b1_0_101: begin // SRLI
				alu_result_o = rs1_i >> imm_i[4:0];
				we_o = run_i;
				done_o = run_i;
			end
			5'b1_1_101: begin // SRAI
				alu_result_o = $signed(rs1_i) >>> imm_i[4:0];
				we_o = run_i;
				done_o = run_i;
			end
			5'b1_0_110: begin // ORI
				alu_result_o = rs1_i | imm_i;
				we_o = run_i;
				done_o = run_i;
			end
			5'b1_0_111: begin // ANDI
				alu_result_o = rs1_i & imm_i;
				we_o = run_i;
				done_o = run_i;
			end
			5'b1_1_000: begin // LUI
				alu_result_o = imm_i;
				we_o = run_i;
				done_o = run_i;
			end

			default: begin
				alu_result_o = 32'b0;
				we_o = 1'b0;
				done_o = 1'b0;
			end
		endcase
	end

endmodule