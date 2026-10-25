`timescale 1ns / 1ps

module ready_station #(
    // Instruction Set Parameters
    parameter int IS_INST_PC_BITWIDTH           = 32,
    parameter int IS_INST_PC_STEP               = 4,
    parameter int IS_INST_BITWIDTH               = 32,
    parameter int IS_INST_REGS                   = 32,
    parameter int IS_INST_OPERANDS               = 2,
    parameter int IS_INST_IMM                    = 32,

    // Execution Unit Parameters
    parameter int EX_INST_MICROOP_BITWIDTH       = 5,

    // EULSUKDO Structure Parameters
    parameter int STRUCT_DECODE_NEW_INST        = 1,
    parameter int STRUCT_INST_STATE_ENTRIES     = 128,
    parameter int STRUCT_PHYREGS                 = 64,
    parameter int STRUCT_EX_PATH                 = 3,
    parameter int STRUCT_RS_OUT_ENTRY [STRUCT_EX_PATH] = '{1, 1, 1},
    parameter int STRUCT_RS_OUT_ENTRY_SUM        = 3,
    parameter int STRUCT_EX_CORES                = 3,
    parameter int STRUCT_EX_OUT_RESULT [STRUCT_EX_CORES] = '{1, 1, 1},
    parameter int STRUCT_PRM_ENTRY_UPDATE        = 3,
    parameter int STRUCT_PRM_ENTRY_BUFFER        = 4,
    parameter int STRUCT_UNALLOCATE_PHYREG       = 4,
    parameter int STRUCT_FLOW_WINDOWS            = 8,
    parameter int STRUCT_FLOW_PC_MAX_RANGE       = 8,

    // Auto-generated Localparams in Parameter section for port declaration usage
    localparam int _BITWIDTH_LOW_STRUCT_PHYREGS         = $clog2(STRUCT_PHYREGS),
    localparam int _BITWIDTH_LOW_STRUCT_EX_PATH         = $clog2(STRUCT_EX_PATH),
    localparam int _BITWIDTH_LOW_STRUCT_FLOW_WINDOWS   = $clog2(STRUCT_FLOW_WINDOWS),
    localparam int _STRUCT_RS_OUT_ENTRY_ALL            = STRUCT_RS_OUT_ENTRY_SUM,

    // RS Push Width
    localparam int RS_PUSH_WIDTH                        = STRUCT_DECODE_NEW_INST + STRUCT_PRM_ENTRY_UPDATE,

    // Ready Station Entry Bitwidths (with and without EX Path)
    localparam int RS_ENTRY_BITWIDTH                    = _BITWIDTH_LOW_STRUCT_PHYREGS * IS_INST_OPERANDS + 
                                                          _BITWIDTH_LOW_STRUCT_PHYREGS + 
                                                          IS_INST_IMM + 
                                                          EX_INST_MICROOP_BITWIDTH + 
                                                          _BITWIDTH_LOW_STRUCT_FLOW_WINDOWS + 
                                                          IS_INST_PC_BITWIDTH,
                                                          
    localparam int IST_READYINST_ENTRY_BITWIDTH         = RS_ENTRY_BITWIDTH + _BITWIDTH_LOW_STRUCT_EX_PATH
) (
    input  wire                                                 clk,
    input  wire                                                 reset_n,

    // Ready instruction receive from IST (i/o_ist_readyinst_*)
    input  wire [RS_PUSH_WIDTH-1:0]                             i_ist_readyinst_valid,
    input  wire [(RS_PUSH_WIDTH * IST_READYINST_ENTRY_BITWIDTH)-1:0] i_ist_readyinst_data,
    output wire                                                 o_ist_readyinst_get,

    // Execution Units command issue (i/o_ex_exeinst_*)
    input  wire [_STRUCT_RS_OUT_ENTRY_ALL-1:0]                  i_ex_exeinst_get,
    output wire [_STRUCT_RS_OUT_ENTRY_ALL-1:0]                  o_ex_exeinst_valid,
    output wire [(_STRUCT_RS_OUT_ENTRY_ALL * RS_ENTRY_BITWIDTH)-1:0] o_ex_exeinst_data
);

    // Cumulative sum function to calculate offsets of STRUCT_RS_OUT_ENTRY
    function automatic int get_rs_out_offset(input int path_idx);
        int offset = 0;
        for (int i = 0; i < path_idx; i++) begin
            offset += STRUCT_RS_OUT_ENTRY[i];
        end
        return offset;
    endfunction

    // Startpoint of EX Path within the incoming IST packet
    localparam int RS_STARTPOINT_EX_PATH = IS_INST_PC_BITWIDTH + _BITWIDTH_LOW_STRUCT_FLOW_WINDOWS;
    localparam int UPPER_PART_START      = RS_STARTPOINT_EX_PATH + _BITWIDTH_LOW_STRUCT_EX_PATH;
    localparam int UPPER_PART_WIDTH      = IST_READYINST_ENTRY_BITWIDTH - UPPER_PART_START;

    // Split and pack input data to remove EX_PATH field
    wire [RS_PUSH_WIDTH-1:0]                    entry_valid;
    wire [(RS_PUSH_WIDTH * RS_ENTRY_BITWIDTH)-1:0] entry_data;

    assign entry_valid = i_ist_readyinst_valid;

    genvar k;
    generate
        for (k = 0; k < RS_PUSH_WIDTH; k = k + 1) begin : gen_strip_ex_path
            assign entry_data[k * RS_ENTRY_BITWIDTH +: RS_ENTRY_BITWIDTH] = {
                i_ist_readyinst_data[k * IST_READYINST_ENTRY_BITWIDTH + UPPER_PART_START +: UPPER_PART_WIDTH],
                i_ist_readyinst_data[k * IST_READYINST_ENTRY_BITWIDTH +: RS_STARTPOINT_EX_PATH]
            };
        end
    endgenerate

    // EX Path validation and routing logic
    reg  [RS_PUSH_WIDTH-1:0] ex_fifo_target_same_ex [0:STRUCT_EX_PATH-1];

    always @(*) begin
        for (integer target_ex = 0; target_ex < STRUCT_EX_PATH; target_ex = target_ex + 1) begin
            for (integer target_entry = 0; target_entry < RS_PUSH_WIDTH; target_entry = target_entry + 1) begin
                if (i_ist_readyinst_valid[target_entry] && 
                    (i_ist_readyinst_data[(IST_READYINST_ENTRY_BITWIDTH * target_entry) + RS_STARTPOINT_EX_PATH +: _BITWIDTH_LOW_STRUCT_EX_PATH] == target_ex)) begin
                    ex_fifo_target_same_ex[target_ex][target_entry] = i_ist_readyinst_valid[target_entry];
                end else begin
                    ex_fifo_target_same_ex[target_ex][target_entry] = 1'b0;
                end
            end
        end
    end

    // Connection arrays for EX Path FIFOs
    wire [STRUCT_EX_PATH-1:0]                   ex_fifo_available;
    wire [(RS_PUSH_WIDTH * RS_ENTRY_BITWIDTH)-1:0] ex_fifo_routed_data [0:STRUCT_EX_PATH-1];
    wire [RS_PUSH_WIDTH-1:0]                    ex_fifo_target_valid [0:STRUCT_EX_PATH-1];

    // FIFO Depth Calculation: based on STRUCT_INST_STATE_ENTRIES and RS_PUSH_WIDTH
    localparam int FIFO_DEPTH_CALC = (STRUCT_INST_STATE_ENTRIES / RS_PUSH_WIDTH) > 0 ? 
                                     (STRUCT_INST_STATE_ENTRIES / RS_PUSH_WIDTH) : 1;

    // Instantiate splitters and variable I/O FIFOs for each path
    genvar p;
    generate
        for (p = 0; p < STRUCT_EX_PATH; p = p + 1) begin : gen_rs_paths
            localparam int out_offset  = get_rs_out_offset(p);
            localparam int num_outputs = STRUCT_RS_OUT_ENTRY[p];

            // 1. gathers valid elements to LSB-aligned order
            position_splitter #(
                .INPUT_ENTRIES(RS_PUSH_WIDTH),
                .DATA_WIDTH   (RS_ENTRY_BITWIDTH)
            ) U_POSITION_SELECTOR (
                .valid_position_i(ex_fifo_target_same_ex[p]),
                .position_data_i (entry_data),
                .out_position_o  (ex_fifo_target_valid[p]),
                .data_o          (ex_fifo_routed_data[p])
            );

            // Connect controls and signals from the flat issue interface
            wire [num_outputs-1:0] pop_get_p   = i_ex_exeinst_get[out_offset +: num_outputs];
            wire [num_outputs-1:0] pop_valid_p;
            wire [(num_outputs * RS_ENTRY_BITWIDTH)-1:0] pop_data_p;

            assign o_ex_exeinst_valid[out_offset +: num_outputs] = pop_valid_p;
            assign o_ex_exeinst_data[out_offset * RS_ENTRY_BITWIDTH +: (num_outputs * RS_ENTRY_BITWIDTH)] = pop_data_p;

            // 2. FIFO instance for buffering commands
            fifo_ordering_position #(
                .PUSH_DATA  (RS_PUSH_WIDTH),
                .POP_DATA   (num_outputs),
                .ENTRY_WIDTH(RS_ENTRY_BITWIDTH),
                .FIFO_DEPTH (FIFO_DEPTH_CALC)
            ) U_RS_EX_FIFO (
                .clk             (clk),
                .reset_n         (reset_n),
                .push_valid_i    (ex_fifo_target_valid[p]),
                .push_data_i     (ex_fifo_routed_data[p]),
                .pop_get_i       (pop_get_p),
                .pop_valid_o     (pop_valid_p),
                .pop_data_o      (pop_data_p),
                .push_available_o(ex_fifo_available[p])
            );
        end
    endgenerate

    // IST Ready handshake: active only when all internal path FIFOs can accept new pushes
    assign o_ist_readyinst_get = &ex_fifo_available;

endmodule
