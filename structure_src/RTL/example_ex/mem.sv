`timescale 1ns / 1ps
module mem_ex #(
    parameter MICROOP_WIDTH         = 5
) (
    input                                  clk,
    input                                  reset_n,
	input                                  run_i,
	input        [MICROOP_WIDTH-1:0]       microop_i,
	input        [31:0] 			       rs1_i,
	input        [31:0] 			       rs2_i,
	input        [31:0] 			       imm_i,
	output logic [31:0] 	               rdata_proc_o,
    output logic                           re_vmem_o,
    output logic                           we_vmem_o,
	output logic [31:0] 	               addr_vmem_o,
	output logic [3:0]  	               strb_vmem_o,
	input        [31:0] 	               rdata_vmem_i,
	output logic [31:0] 	               wdata_vmem_o,
    input                                  ready_vmem_i,
	output logic                           we_proc_o,
	output logic                           done_o
);
    reg [31:0] addr;

    reg req;

    always_ff @(posedge clk or negedge reset_n) begin
        if (reset_n == 1'b0) req <= 0;
        else begin
            if (req) req <= (ready_vmem_i)? 1'b0 : 1'b1;
            else     req <= run_i;
        end
    end

	always_comb begin
        addr = 32'b0;

		case(microop_i)
			5'b0_0_000: begin // LB
                addr         = rs1_i + imm_i;

                case (addr[1:0])
                    2'd0: rdata_proc_o = {24'b0, rdata_vmem_i[7:0]  };
                    2'd1: rdata_proc_o = {24'b0, rdata_vmem_i[15:8] };
                    2'd2: rdata_proc_o = {24'b0, rdata_vmem_i[23:16]};
                    2'd3: rdata_proc_o = {24'b0, rdata_vmem_i[31:24]};
                    default: rdata_proc_o = 32'b0;
                endcase

                re_vmem_o    = run_i;
                we_vmem_o    = 1'b0;
                addr_vmem_o  = {addr[31:2], 2'b0};
                strb_vmem_o  = 4'b0;
                wdata_vmem_o = 32'b0;
				we_proc_o    = req & ready_vmem_i;
				done_o       = req & ready_vmem_i;
			end
			5'b0_0_001: begin // LH
                addr         = rs1_i + imm_i;

                case (addr[1])
                    1'd0: rdata_proc_o = {16'b0, rdata_vmem_i[15:0] };
                    1'd1: rdata_proc_o = {16'b0, rdata_vmem_i[31:16]};
                    default: rdata_proc_o = 32'b0;
                endcase

                re_vmem_o    = run_i;
                we_vmem_o    = 1'b0;
                addr_vmem_o  = {addr[31:2], 2'b0};
                strb_vmem_o  = 4'b0;
                wdata_vmem_o = 32'b0;
				we_proc_o    = req & ready_vmem_i;
				done_o       = req & ready_vmem_i;
			end
			5'b0_0_010: begin // LW
                addr         = rs1_i + imm_i;

                rdata_proc_o = rdata_vmem_i;
                re_vmem_o    = run_i;
                we_vmem_o    = 1'b0;
                addr_vmem_o  = {addr[31:2], 2'b0};
                strb_vmem_o  = 4'b0;
                wdata_vmem_o = 32'b0;
				we_proc_o    = req & ready_vmem_i;
				done_o       = req & ready_vmem_i;
			end
			5'b0_0_100: begin // LBU
                addr         = rs1_i + imm_i;

                case (addr[1:0])
                    2'd0: rdata_proc_o = {{24{rdata_vmem_i[7 ]}}, rdata_vmem_i[7:0]  };
                    2'd1: rdata_proc_o = {{24{rdata_vmem_i[15]}}, rdata_vmem_i[15:8] };
                    2'd2: rdata_proc_o = {{24{rdata_vmem_i[23]}}, rdata_vmem_i[23:16]};
                    2'd3: rdata_proc_o = {{24{rdata_vmem_i[31]}}, rdata_vmem_i[31:24]};
                    default: rdata_proc_o = 32'b0;
                endcase

                re_vmem_o    = run_i;
                we_vmem_o    = 1'b0;
                addr_vmem_o  = {addr[31:2], 2'b0};
                strb_vmem_o  = 4'b0;
                wdata_vmem_o = 32'b0;
				we_proc_o    = req & ready_vmem_i;
				done_o       = req & ready_vmem_i;
			end
			5'b0_0_101: begin // LHU
                addr         = rs1_i + imm_i;

                case (addr[1])
                    1'd0: rdata_proc_o = {{16{rdata_vmem_i[15]}}, rdata_vmem_i[15:0] };
                    1'd1: rdata_proc_o = {{16{rdata_vmem_i[31]}}, rdata_vmem_i[31:16]};
                    default: rdata_proc_o = 32'b0;
                endcase

                re_vmem_o    = run_i;
                we_vmem_o    = 1'b0;
                addr_vmem_o  = {addr[31:2], 2'b0};
                strb_vmem_o  = 4'b0;
                wdata_vmem_o = 32'b0;
				we_proc_o    = req & ready_vmem_i;
				done_o       = req & ready_vmem_i;
			end
            
			5'b1_0_000: begin // SB
                addr         = rs1_i + imm_i;

                rdata_proc_o = 32'b0;
                re_vmem_o    = 1'b0;
                we_vmem_o    = run_i;
                addr_vmem_o  = addr;
                strb_vmem_o  = 4'b0001;
                wdata_vmem_o = rs2_i;
				we_proc_o    = 1'b0;
				done_o       = req & ready_vmem_i;
			end
			5'b1_0_001: begin // SH
                addr         = rs1_i + imm_i;

                rdata_proc_o = 32'b0;
                re_vmem_o    = 1'b0;
                we_vmem_o    = run_i;
                addr_vmem_o  = addr;
                strb_vmem_o  = 4'b0011;
                wdata_vmem_o = rs2_i;
				we_proc_o    = 1'b0;
				done_o       = req & ready_vmem_i;
			end
			5'b1_0_010: begin // SW
                addr         = rs1_i + imm_i;

                rdata_proc_o = 32'b0;
                re_vmem_o    = 1'b0;
                we_vmem_o    = run_i;
                addr_vmem_o  = addr;
                strb_vmem_o  = 4'b1111;
                wdata_vmem_o = rs2_i;
				we_proc_o    = 1'b0;
				done_o       = req & ready_vmem_i;
			end

			default: begin
                rdata_proc_o = 32'b0;
                re_vmem_o    = 1'b0;
                we_vmem_o    = 1'b0;
                addr_vmem_o  = 32'b0;
                strb_vmem_o  = 4'b0000;
                wdata_vmem_o = 32'b0;
				we_proc_o    = 1'b0;
				done_o       = 1'b0;
			end
		endcase
	end

endmodule
