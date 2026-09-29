`timescale 1ns/1ps
// External predictor port reference implementation. A replacement may use
// i_update_* to train state; prediction and update are independent channels.
module static_not_taken_predictor #(
    parameter int PC_WIDTH = 32,
    parameter int PC_STEP = 4
) (
    input  wire                i_predict_valid,
    input  wire [PC_WIDTH-1:0] i_predict_pc,
    output wire                o_predict_valid,
    output wire                o_predict_taken,
    output wire [PC_WIDTH-1:0] o_predict_target,
    input  wire                i_update_valid,
    input  wire [PC_WIDTH-1:0] i_update_pc,
    input  wire                i_update_taken,
    input  wire [PC_WIDTH-1:0] i_update_target
);
    assign o_predict_valid = i_predict_valid;
    assign o_predict_taken = 1'b0;
    assign o_predict_target = i_predict_pc + PC_WIDTH'(PC_STEP);
endmodule
