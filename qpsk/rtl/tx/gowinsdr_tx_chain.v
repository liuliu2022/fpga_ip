`timescale 1ns / 1ps

// RFSoC parallel QPSK transmitter derived from the GoWinSDR v1 TX path.
module gowinsdr_tx_chain (
    (* X_INTERFACE_INFO = "xilinx.com:signal:clock:1.0 clk CLK" *)
    (* X_INTERFACE_PARAMETER = "ASSOCIATED_RESET rst_n, FREQ_HZ 61440000" *)
    input  wire                     clk,
    (* X_INTERFACE_INFO = "xilinx.com:signal:reset:1.0 rst_n RST" *)
    (* X_INTERFACE_PARAMETER = "POLARITY ACTIVE_LOW" *)
    input  wire                     rst_n,

    (* X_INTERFACE_IGNORE = "true" *) input wire [1:0] data_in,
    (* X_INTERFACE_IGNORE = "true" *) input wire       data_valid,
    (* X_INTERFACE_IGNORE = "true" *) output wire      data_ready,
    (* X_INTERFACE_IGNORE = "true" *) output wire      data_accepted,

    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 m_axis TDATA" *)
    output wire [127:0]             m_axis_tdata,
    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 m_axis TVALID" *)
    output wire                     m_axis_tvalid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 m_axis TREADY" *)
    input  wire                     m_axis_tready
);

wire encoded_i;
wire encoded_q;
wire symbol_strobe;
wire signed [15:0] sample_i0, sample_q0;
wire signed [15:0] sample_i1, sample_q1;
wire signed [15:0] sample_i2, sample_q2;
wire signed [15:0] sample_i3, sample_q3;

tx_qpsk_diff_encode u_encoder (
    .clk(clk), .rst_n(rst_n), .symbol_strobe(symbol_strobe),
    .data_in(data_in), .data_valid(data_valid), .data_ready(data_ready),
    .encoded_i(encoded_i), .encoded_q(encoded_q),
    .accepted_data(data_accepted)
);

tx_rrc_interp48x4 u_rrc (
    .clk(clk), .rst_n(rst_n), .symbol_strobe(symbol_strobe),
    .symbol_i(encoded_i), .symbol_q(encoded_q),
    .out_valid(m_axis_tvalid), .out_ready(m_axis_tready),
    .out_i0(sample_i0), .out_q0(sample_q0),
    .out_i1(sample_i1), .out_q1(sample_q1),
    .out_i2(sample_i2), .out_q2(sample_q2),
    .out_i3(sample_i3), .out_q3(sample_q3)
);

// Preserve the RFDC ordering already used by t510_standalone_top.v.
assign m_axis_tdata = {sample_q3, sample_i3, sample_q2, sample_i2,
                       sample_q1, sample_i1, sample_q0, sample_i0};

endmodule
