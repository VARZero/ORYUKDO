`timescale 1ns / 1ps

//`include "../memories.sv"
//`include "../position_splitter.sv"
//
module ready_station #(
    // Dynamic Schedular Description
    parameter DECODE_NEW_INST   = 1,
    parameter PHYREG_NUM        = 64,
    parameter IST_ENTRY_NUM     = 128,
    parameter EX_PATH_NUM       = 3,
    parameter PRM_ENTRY_BUFFER  = 4,
    parameter RS_ENTRY_NUM      = 16,
    parameter RS_PUSH_WIDTH     = 3,
    parameter FCL_RB_NUM        = 8,
    parameter FCL_PC_GAP        = 4,
    parameter UNALLOCATE_PHYREG = 4,

    // Instruction Field Description
    parameter INST_PC_WIDTH                 = 32,
    parameter INST_BITWIDTH                 = 32,
    parameter INST_OPCODE_WIDTH             = 7,
    parameter INST_OPTIONAL_OPCODE_WIDTH    = 10,
    parameter INST_IMM_WIDTH                = 32,
    parameter INST_NUM_OF_LOGICAL_REGISTER  = 32,
    parameter INST_OPREANDS                 = 2,

    // Internal Field Description (Decoder Compiler (or Human) Generate)
    parameter MICROOP_WIDTH                 = 5, // Micro-OP is not contained information of EX_PATH

    // (Autogenerate) Elements
    localparam BITWIDTH_EX_PATH_NUM                     = $clog2(EX_PATH_NUM),
    localparam BITWIDTH_PHYREG_NUM                      = $clog2(PHYREG_NUM),
    localparam BITWIDTH_IST_ENTRY_NUM                   = $clog2(IST_ENTRY_NUM),
    localparam BITWIDTH_INST_NUM_OF_LOGICAL_REGISTER    = $clog2(INST_NUM_OF_LOGICAL_REGISTER),
    localparam BITWIDTH_FCL_RB_NUM                      = $clog2(FCL_RB_NUM),
    
    localparam BITWIDTH_FCL_PC_WIDTH                    = BITWIDTH_FCL_RB_NUM + INST_PC_WIDTH,

    // (Autogenerate) Field of Entry in Instruction State Table
        /* Entry: MSB [ ( Opreand Reday_n, ... , Opreand Reday_1 ) | 
                        ( Opreand Rename Register_n, ... , Opreand Rename Register_1 ) | 
                        Destination Logical Register | 
                        Destination Rename Register | 
                        IMM | Micro-OP | EX_PATH | PC ] LSB */    
    localparam IST_BITWIDTH_OPREAND_PHYREG_FULL = BITWIDTH_PHYREG_NUM * INST_OPREANDS,

    
    // (Autogenerate) Ready Station Entry
    localparam RS_ENTRY_BITWIDTH            = BITWIDTH_FCL_PC_WIDTH + BITWIDTH_EX_PATH_NUM + MICROOP_WIDTH
                                              + INST_IMM_WIDTH + BITWIDTH_PHYREG_NUM + IST_BITWIDTH_OPREAND_PHYREG_FULL,
    localparam RS_PACKET_BITWIDTH           = RS_ENTRY_BITWIDTH * RS_PUSH_WIDTH,
    localparam EX_PACKET_BITWIDTH           = RS_ENTRY_BITWIDTH * EX_PATH_NUM,
    
    localparam RS_STARTPOINT_EX_PATH        = BITWIDTH_FCL_PC_WIDTH,

    // (Autogenerate) Write Back Field
    localparam WB_PHYREGS_BITWIDTH          = BITWIDTH_PHYREG_NUM * EX_PATH_NUM
) (
    input  wire clk,
    input  wire reset_n,
    
    // Entries Update
        // -> Instruction State Table Ready
    output wire o_ist_ready_entry_get,
    input  wire [RS_PUSH_WIDTH-1:0] i_ist_ready_entry_valid,
    input  wire [RS_PACKET_BITWIDTH-1:0] i_ist_ready_entry,

    // Entries Pop
        // <- Execute Units Input
    input  wire [EX_PATH_NUM-1:0] i_ex_entry_get,
    output wire [EX_PATH_NUM-1:0] o_ex_entry_valid,
    output wire [EX_PACKET_BITWIDTH-1:0] o_ex_entry
);
    wire [EX_PATH_NUM-1:0] ex_fifo_available;
    wire [RS_PACKET_BITWIDTH-1:0] ex_fifo_data[0:EX_PATH_NUM-1];

    reg  [RS_PUSH_WIDTH-1:0] ex_fifo_target_same_ex[0:EX_PATH_NUM-1];
    always @(*) begin
        for (integer target_ex = 0; target_ex < EX_PATH_NUM; target_ex = target_ex+1) begin
            for (integer target_entry = 0; target_entry < RS_PUSH_WIDTH; target_entry = target_entry+1) begin
                if (i_ist_ready_entry
                    [((RS_ENTRY_BITWIDTH*target_entry)+RS_STARTPOINT_EX_PATH) +: BITWIDTH_EX_PATH_NUM] 
                    == target_ex ) begin

                    ex_fifo_target_same_ex[target_ex][target_entry] = i_ist_ready_entry_valid[target_entry];
                end
                else ex_fifo_target_same_ex[target_ex][target_entry] = 1'b0;
            end
        end
    end

    wire [RS_PUSH_WIDTH-1:0]         ex_fifo_target_valid[0:EX_PATH_NUM-1];
    wire [1:0]                       rs_ex_fifo_valid[0:EX_PATH_NUM-1];
    wire [(RS_ENTRY_BITWIDTH*2)-1:0] rs_ex_fifo_data[0:EX_PATH_NUM-1];

    genvar ex_target_fifo;
    generate
        for (ex_target_fifo = 0; ex_target_fifo < EX_PATH_NUM; ex_target_fifo = ex_target_fifo+1) begin
            position_splitter #(
                .INPUT_ENTRIES(RS_PUSH_WIDTH),
                .DATA_WIDTH   (RS_ENTRY_BITWIDTH)
            ) U_POSITION_SELECTOR (
            	.valid_position_i(ex_fifo_target_same_ex[ex_target_fifo]),
            	.position_data_i (i_ist_ready_entry),
            	.out_position_o  (ex_fifo_target_valid[ex_target_fifo]),
            	.data_o          (ex_fifo_data[ex_target_fifo])
            );

            fifo_ordering_position #(
            	.PUSH_DATA  (RS_PUSH_WIDTH),
            	.POP_DATA   (2),
            	.ENTRY_WIDTH(RS_ENTRY_BITWIDTH),
            	.FIFO_DEPTH (RS_ENTRY_NUM/RS_PUSH_WIDTH)
            ) U_RS_EX_FIFO (
            	.clk                (clk),
            	.reset_n            (reset_n),
            	.push_valid_i       (ex_fifo_target_valid[ex_target_fifo]),
            	.push_data_i        (ex_fifo_data[ex_target_fifo]),
            	.pop_get_i          ({1'b0, i_ex_entry_get[ex_target_fifo]}),
            	.pop_valid_o        (rs_ex_fifo_valid[ex_target_fifo]),
            	.pop_data_o         (rs_ex_fifo_data[ex_target_fifo]),
            	.push_available_o   (ex_fifo_available[ex_target_fifo])
            );

            assign o_ex_entry_valid[ex_target_fifo] = rs_ex_fifo_valid[ex_target_fifo][0];
            assign o_ex_entry[(RS_ENTRY_BITWIDTH * ex_target_fifo) +: RS_ENTRY_BITWIDTH] 
                        = rs_ex_fifo_data[ex_target_fifo][0 +: RS_ENTRY_BITWIDTH];
        end
    endgenerate

    assign o_ist_ready_entry_get = &ex_fifo_available;

endmodule
