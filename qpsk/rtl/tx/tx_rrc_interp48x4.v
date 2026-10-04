`timescale 1ns / 1ps

// 48-sample/symbol root-raised-cosine interpolator.
// Four consecutive complex samples are evaluated in parallel on each
// 61.44-MHz PL clock, producing the RFDC's 245.76-MSPS baseband stream.
// QPSK inputs are signs, so coefficient add/subtract replaces multipliers.
module tx_rrc_interp48x4 (
    input  wire                     clk,
    input  wire                     rst_n,
    output wire                     symbol_strobe,
    input  wire                     symbol_i,
    input  wire                     symbol_q,
    output wire                     out_valid,
    input  wire                     out_ready,
    output wire signed [15:0]       out_i0,
    output wire signed [15:0]       out_q0,
    output wire signed [15:0]       out_i1,
    output wire signed [15:0]       out_q1,
    output wire signed [15:0]       out_i2,
    output wire signed [15:0]       out_q2,
    output wire signed [15:0]       out_i3,
    output wire signed [15:0]       out_q3
);

// -1, 0, or +1. Zero initialization reproduces causal FIR startup.
reg signed [1:0] history_i [0:10];
reg signed [1:0] history_q [0:10];
reg [5:0] phase_base;
reg out_valid_reg;
reg signed [15:0] out_i_reg [0:3];
reg signed [15:0] out_q_reg [0:3];
wire advance = !out_valid_reg || out_ready;

integer lane;
integer tap;
integer k;
reg signed [31:0] accum_i [0:3];
reg signed [31:0] accum_q [0:3];
reg signed [17:0] coefficient;
reg signed [1:0] sign_i;
reg signed [1:0] sign_q;

function signed [17:0] tx_rrc_coeff;
    input [5:0] phase;
    input [3:0] tap_index;
    integer coefficient_index;
    begin
        coefficient_index = phase + 48*tap_index;
        case (coefficient_index)
`define TX_RRC_COEFF_CASE_CONTEXT
`include "tx_rrc_coeffs_case.vh"
`undef TX_RRC_COEFF_CASE_CONTEXT
            default: tx_rrc_coeff = 18'sd0;
        endcase
    end
endfunction

function signed [15:0] saturate16;
    input signed [31:0] value;
    begin
        if (value > 32767)
            saturate16 = 16'sh7fff;
        else if (value < -32768)
            saturate16 = -16'sd32768;
        else
            saturate16 = value[15:0];
    end
endfunction

assign out_valid = out_valid_reg;
assign symbol_strobe = rst_n && advance && (phase_base == 0);

always @* begin
    for (lane = 0; lane < 4; lane = lane + 1) begin
        accum_i[lane] = 32'sd0;
        accum_q[lane] = 32'sd0;
        for (tap = 0; tap < 11; tap = tap + 1) begin
            coefficient = tx_rrc_coeff(phase_base + lane, tap);
            if (phase_base == 0) begin
                if (tap == 0) begin
                    sign_i = symbol_i ? 2'sd1 : -2'sd1;
                    sign_q = symbol_q ? 2'sd1 : -2'sd1;
                end else begin
                    sign_i = history_i[tap-1];
                    sign_q = history_q[tap-1];
                end
            end else begin
                sign_i = history_i[tap];
                sign_q = history_q[tap];
            end

            if (sign_i > 0)
                accum_i[lane] = accum_i[lane] + coefficient;
            else if (sign_i < 0)
                accum_i[lane] = accum_i[lane] - coefficient;

            if (sign_q > 0)
                accum_q[lane] = accum_q[lane] + coefficient;
            else if (sign_q < 0)
                accum_q[lane] = accum_q[lane] - coefficient;
        end
    end
end

assign out_i0 = out_i_reg[0];
assign out_q0 = out_q_reg[0];
assign out_i1 = out_i_reg[1];
assign out_q1 = out_q_reg[1];
assign out_i2 = out_i_reg[2];
assign out_q2 = out_q_reg[2];
assign out_i3 = out_i_reg[3];
assign out_q3 = out_q_reg[3];

always @(posedge clk) begin
    if (!rst_n) begin
        phase_base <= 0;
        out_valid_reg <= 1'b0;
        for (k = 0; k < 11; k = k + 1) begin
            history_i[k] <= 0;
            history_q[k] <= 0;
        end
        for (k = 0; k < 4; k = k + 1) begin
            out_i_reg[k] <= 0;
            out_q_reg[k] <= 0;
        end
    end else if (advance) begin
        out_valid_reg <= 1'b1;
        for (k = 0; k < 4; k = k + 1) begin
            out_i_reg[k] <= saturate16(accum_i[k]);
            out_q_reg[k] <= saturate16(accum_q[k]);
        end
        if (phase_base == 44) begin
            phase_base <= 0;
        end else begin
            if (phase_base == 0) begin
                for (k = 10; k > 0; k = k - 1) begin
                    history_i[k] <= history_i[k-1];
                    history_q[k] <= history_q[k-1];
                end
                history_i[0] <= symbol_i ? 2'sd1 : -2'sd1;
                history_q[0] <= symbol_q ? 2'sd1 : -2'sd1;
            end
            phase_base <= phase_base + 4;
        end
    end
end

endmodule
