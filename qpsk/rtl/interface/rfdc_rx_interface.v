`timescale 1ns / 1ps

// RFSoC RFDC receive-interface adapter for one complex channel.
//
// The current T510 RFDC configuration presents the real and imaginary parts
// on two independent 64-bit AXI4-Stream interfaces.  Each word contains four
// chronological signed 16-bit samples, with the earliest sample in [15:0].
//
// This module keeps both streams in lockstep, passes the original words on to
// the existing capture/DMA path, and exposes the four complex samples to the
// future decimation filter.  No filtering or rate change is performed here.
module rfdc_rx_interface (
    (* X_INTERFACE_INFO = "xilinx.com:signal:clock:1.0 clk CLK" *)
    (* X_INTERFACE_PARAMETER = "ASSOCIATED_BUSIF s_axis_i:s_axis_q:m_axis_i:m_axis_q, ASSOCIATED_RESET aresetn, FREQ_HZ 61440000" *)
    input  wire                      clk,

    (* X_INTERFACE_INFO = "xilinx.com:signal:reset:1.0 aresetn RST" *)
    (* X_INTERFACE_PARAMETER = "POLARITY ACTIVE_LOW" *)
    input  wire                      aresetn,

    // RFDC I component (for channel 0 this is m00_axis).
    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 s_axis_i TDATA" *)
    input  wire [63:0]               s_axis_i_tdata,
    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 s_axis_i TVALID" *)
    input  wire                      s_axis_i_tvalid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 s_axis_i TREADY" *)
    output wire                      s_axis_i_tready,

    // RFDC Q component (for channel 0 this is m01_axis).
    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 s_axis_q TDATA" *)
    input  wire [63:0]               s_axis_q_tdata,
    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 s_axis_q TVALID" *)
    input  wire                      s_axis_q_tvalid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 s_axis_q TREADY" *)
    output wire                      s_axis_q_tready,

    // Raw pass-through to the existing capture path.
    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 m_axis_i TDATA" *)
    output wire [63:0]               m_axis_i_tdata,
    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 m_axis_i TVALID" *)
    output wire                      m_axis_i_tvalid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 m_axis_i TREADY" *)
    input  wire                      m_axis_i_tready,

    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 m_axis_q TDATA" *)
    output wire [63:0]               m_axis_q_tdata,
    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 m_axis_q TVALID" *)
    output wire                      m_axis_q_tvalid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 m_axis_q TREADY" *)
    input  wire                      m_axis_q_tready,

    // Four chronological complex samples for the DSP path.
    (* X_INTERFACE_IGNORE = "true" *) output wire signed [15:0] sample_i0,
    (* X_INTERFACE_IGNORE = "true" *) output wire signed [15:0] sample_q0,
    (* X_INTERFACE_IGNORE = "true" *) output wire signed [15:0] sample_i1,
    (* X_INTERFACE_IGNORE = "true" *) output wire signed [15:0] sample_q1,
    (* X_INTERFACE_IGNORE = "true" *) output wire signed [15:0] sample_i2,
    (* X_INTERFACE_IGNORE = "true" *) output wire signed [15:0] sample_q2,
    (* X_INTERFACE_IGNORE = "true" *) output wire signed [15:0] sample_i3,
    (* X_INTERFACE_IGNORE = "true" *) output wire signed [15:0] sample_q3,
    (* X_INTERFACE_IGNORE = "true" *) output wire sample_valid,

    // Sticky diagnostic for I/Q TVALID misalignment; cleared by reset.
    (* X_INTERFACE_IGNORE = "true" *) output reg valid_mismatch_sticky
);

reg  [63:0] i_buffer;
reg  [63:0] q_buffer;
reg         buffer_valid;
wire        output_ready;
wire        input_ready;
wire        input_transfer;
wire        output_transfer;

assign output_ready   = m_axis_i_tready & m_axis_q_tready;
assign input_ready    = ~buffer_valid | output_ready;
assign input_transfer = aresetn & s_axis_i_tvalid & s_axis_q_tvalid & input_ready;
assign output_transfer = aresetn & buffer_valid & output_ready;

// Only accept an input component when its partner is also valid and the
// paired holding register can accept a new word.
assign s_axis_i_tready = aresetn & s_axis_q_tvalid & input_ready;
assign s_axis_q_tready = aresetn & s_axis_i_tvalid & input_ready;

// The registered output keeps TVALID and TDATA stable under backpressure.
// Both master interfaces carry the same TVALID and therefore transfer as a
// pair when both TREADY inputs are asserted.
assign m_axis_i_tdata  = i_buffer;
assign m_axis_q_tdata  = q_buffer;
assign m_axis_i_tvalid = aresetn & buffer_valid;
assign m_axis_q_tvalid = aresetn & buffer_valid;

assign sample_valid = output_transfer;

assign sample_i0 = $signed(i_buffer[15:0]);
assign sample_i1 = $signed(i_buffer[31:16]);
assign sample_i2 = $signed(i_buffer[47:32]);
assign sample_i3 = $signed(i_buffer[63:48]);

assign sample_q0 = $signed(q_buffer[15:0]);
assign sample_q1 = $signed(q_buffer[31:16]);
assign sample_q2 = $signed(q_buffer[47:32]);
assign sample_q3 = $signed(q_buffer[63:48]);

always @(posedge clk) begin
    if (!aresetn) begin
        i_buffer <= 64'd0;
        q_buffer <= 64'd0;
        buffer_valid <= 1'b0;
        valid_mismatch_sticky <= 1'b0;
    end else begin
        if (output_transfer)
            buffer_valid <= 1'b0;

        // A simultaneous output and input replaces the consumed pair without
        // creating a bubble, sustaining one four-sample vector per clock.
        if (input_transfer) begin
            i_buffer <= s_axis_i_tdata;
            q_buffer <= s_axis_q_tdata;
            buffer_valid <= 1'b1;
        end

        if (s_axis_i_tvalid ^ s_axis_q_tvalid)
            valid_mismatch_sticky <= 1'b1;
    end
end

endmodule
