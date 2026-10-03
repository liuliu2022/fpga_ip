`timescale 1ns / 1ps

// RFSoC receive-chain wrapper derived from the GoWinSDR v1 QPSK path.
module gowinsdr_rx_chain (
    (* X_INTERFACE_INFO = "xilinx.com:signal:clock:1.0 clk CLK" *)
    (* X_INTERFACE_PARAMETER = "ASSOCIATED_RESET rst_n, FREQ_HZ 61440000" *)
    input  wire                     clk,
    (* X_INTERFACE_INFO = "xilinx.com:signal:reset:1.0 rst_n RST" *)
    (* X_INTERFACE_PARAMETER = "POLARITY ACTIVE_LOW" *)
    input  wire                     rst_n,

    (* X_INTERFACE_IGNORE = "true" *) input wire sample_valid,
    (* X_INTERFACE_IGNORE = "true" *) input wire signed [15:0] sample_i0,
    (* X_INTERFACE_IGNORE = "true" *) input wire signed [15:0] sample_q0,
    (* X_INTERFACE_IGNORE = "true" *) input wire signed [15:0] sample_i1,
    (* X_INTERFACE_IGNORE = "true" *) input wire signed [15:0] sample_q1,
    (* X_INTERFACE_IGNORE = "true" *) input wire signed [15:0] sample_i2,
    (* X_INTERFACE_IGNORE = "true" *) input wire signed [15:0] sample_q2,
    (* X_INTERFACE_IGNORE = "true" *) input wire signed [15:0] sample_i3,
    (* X_INTERFACE_IGNORE = "true" *) input wire signed [15:0] sample_q3,

    (* X_INTERFACE_IGNORE = "true" *) output wire decim_valid,
    (* X_INTERFACE_IGNORE = "true" *) output wire signed [15:0] decim_i,
    (* X_INTERFACE_IGNORE = "true" *) output wire signed [15:0] decim_q,
    (* X_INTERFACE_IGNORE = "true" *) output wire costas_valid,
    (* X_INTERFACE_IGNORE = "true" *) output wire signed [15:0] costas_i,
    (* X_INTERFACE_IGNORE = "true" *) output wire signed [15:0] costas_q,
    (* X_INTERFACE_IGNORE = "true" *) output wire symbol_valid,
    (* X_INTERFACE_IGNORE = "true" *) output wire signed [15:0] symbol_i,
    (* X_INTERFACE_IGNORE = "true" *) output wire signed [15:0] symbol_q,
    (* X_INTERFACE_IGNORE = "true" *) output wire [1:0] decoded_data,
    (* X_INTERFACE_IGNORE = "true" *) output wire decoded_valid,
    (* X_INTERFACE_IGNORE = "true" *) output wire signed [31:0] costas_frequency_word,
    (* X_INTERFACE_IGNORE = "true" *) output wire [31:0] costas_phase_word,
    (* X_INTERFACE_IGNORE = "true" *) output wire signed [31:0] timing_step,
    (* X_INTERFACE_IGNORE = "true" *) output wire signed [34:0] timing_error
);

wire rrc_valid;
wire signed [15:0] rrc_i;
wire signed [15:0] rrc_q;

rx_polyphase_decim4 u_decimator (
    .clk(clk), .rst_n(rst_n), .in_valid(sample_valid),
    .in_i0(sample_i0), .in_i1(sample_i1), .in_i2(sample_i2), .in_i3(sample_i3),
    .in_q0(sample_q0), .in_q1(sample_q1), .in_q2(sample_q2), .in_q3(sample_q3),
    .out_valid(decim_valid), .out_i(decim_i), .out_q(decim_q)
);

rx_matched_rrc u_matched_filter (
    .clk(clk), .rst_n(rst_n), .in_valid(decim_valid),
    .in_i(decim_i), .in_q(decim_q),
    .out_valid(rrc_valid), .out_i(rrc_i), .out_q(rrc_q)
);

rx_costas_loop u_costas (
    .clk(clk), .rst_n(rst_n), .in_valid(rrc_valid),
    .in_i(rrc_i), .in_q(rrc_q),
    .out_valid(costas_valid), .out_i(costas_i), .out_q(costas_q),
    .frequency_word(costas_frequency_word), .phase_word(costas_phase_word)
);

rx_gardner_timing u_timing (
    .clk(clk), .rst_n(rst_n), .in_valid(costas_valid),
    .in_i(costas_i), .in_q(costas_q),
    .symbol_valid(symbol_valid), .symbol_i(symbol_i), .symbol_q(symbol_q),
    .timing_step(timing_step), .timing_error(timing_error)
);

rx_qpsk_diff_decode u_decoder (
    .clk(clk), .rst_n(rst_n), .symbol_valid(symbol_valid),
    .symbol_i(symbol_i), .symbol_q(symbol_q),
    .data_out(decoded_data), .data_valid(decoded_valid)
);

endmodule
