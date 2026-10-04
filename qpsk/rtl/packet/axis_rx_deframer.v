`timescale 1ns / 1ps

// QPSK dibit-to-AXI4-Stream deframer. A payload is released to DMA only after
// header CRC8 and payload CRC32 have both passed.
module axis_rx_deframer #(
    parameter integer MAX_PAYLOAD     = 512,
    parameter integer WATCHDOG_CYCLES = 1000000
) (
    (* X_INTERFACE_INFO = "xilinx.com:signal:clock:1.0 clk CLK" *)
    (* X_INTERFACE_PARAMETER = "ASSOCIATED_BUSIF m_axis, ASSOCIATED_RESET rst_n, FREQ_HZ 61440000" *)
    input  wire        clk,
    (* X_INTERFACE_INFO = "xilinx.com:signal:reset:1.0 rst_n RST" *)
    (* X_INTERFACE_PARAMETER = "POLARITY ACTIVE_LOW" *)
    input  wire        rst_n,
    (* X_INTERFACE_IGNORE = "true" *) input wire [1:0] s_dibit,
    (* X_INTERFACE_IGNORE = "true" *) input wire       s_dibit_valid,

    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 m_axis TDATA" *)
    output reg  [31:0] m_axis_tdata,
    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 m_axis TKEEP" *)
    output reg  [3:0]  m_axis_tkeep,
    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 m_axis TLAST" *)
    output reg         m_axis_tlast,
    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 m_axis TVALID" *)
    output reg         m_axis_tvalid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 m_axis TREADY" *)
    input  wire        m_axis_tready,

    output reg         sync_found,
    output reg         header_error,
    output reg         crc_error,
    output reg         frame_good,
    output reg [15:0]  frame_length
);

localparam [1:0] ST_SEARCH = 2'd0;
localparam [1:0] ST_HEADER = 2'd1;
localparam [1:0] ST_BODY   = 2'd2;
localparam [1:0] ST_OUTPUT = 2'd3;

reg [1:0] state;
reg [31:0] sync_shift;
reg [5:0] byte_shift;
reg [1:0] dibit_count;
reg [1:0] header_index;
reg [7:0] header_crc_state;
reg [7:0] control_byte;
reg [7:0] length_hi;
reg [15:0] payload_length;
reg [15:0] body_byte_count;
reg [31:0] crc_state;
reg [7:0] fcs_byte0;
reg [7:0] fcs_byte1;
reg [7:0] fcs_byte2;
reg [6:0] scrambler_state;
reg [31:0] watchdog;
reg [15:0] output_index;
reg [7:0] payload_mem [0:MAX_PAYLOAD-1];

reg [7:0] received_byte;
reg [15:0] candidate_length;
reg [31:0] received_fcs;
integer lane;

function [31:0] crc32_byte;
    input [31:0] crc_in;
    input [7:0] data_in;
    integer bit_index;
    reg [31:0] c;
    begin
        c = crc_in ^ data_in;
        for (bit_index = 0; bit_index < 8; bit_index = bit_index + 1)
            c = c[0] ? ((c >> 1) ^ 32'hEDB88320) : (c >> 1);
        crc32_byte = c;
    end
endfunction

function [7:0] crc8_byte;
    input [7:0] crc_in;
    input [7:0] data_in;
    integer bit_index;
    reg [7:0] c;
    begin
        c = crc_in ^ data_in;
        for (bit_index = 0; bit_index < 8; bit_index = bit_index + 1)
            c = c[7] ? ((c << 1) ^ 8'h07) : (c << 1);
        crc8_byte = c;
    end
endfunction

function [1:0] descramble_dibit;
    input [1:0] data_in;
    input [6:0] state_in;
    reg [6:0] s;
    reg feedback;
    begin
        s = state_in;
        feedback = s[6] ^ s[3];
        descramble_dibit[1] = data_in[1] ^ feedback;
        s = {s[5:0], feedback};
        feedback = s[6] ^ s[3];
        descramble_dibit[0] = data_in[0] ^ feedback;
    end
endfunction

function [6:0] scrambler_next2;
    input [6:0] state_in;
    reg [6:0] s;
    reg feedback;
    begin
        s = state_in;
        feedback = s[6] ^ s[3];
        s = {s[5:0], feedback};
        feedback = s[6] ^ s[3];
        scrambler_next2 = {s[5:0], feedback};
    end
endfunction

wire [31:0] shifted_sync = {sync_shift[29:0], s_dibit};
wire [1:0] clean_dibit = (state == ST_BODY) ?
                         descramble_dibit(s_dibit, scrambler_state) : s_dibit;

always @(posedge clk) begin
    if (!rst_n) begin
        state             <= ST_SEARCH;
        sync_shift        <= 32'd0;
        byte_shift        <= 6'd0;
        dibit_count       <= 2'd0;
        header_index      <= 2'd0;
        header_crc_state  <= 8'd0;
        control_byte      <= 8'd0;
        length_hi         <= 8'd0;
        payload_length    <= 16'd0;
        body_byte_count   <= 16'd0;
        crc_state         <= 32'hFFFFFFFF;
        scrambler_state   <= 7'h5D;
        watchdog          <= 32'd0;
        output_index      <= 16'd0;
        m_axis_tdata      <= 32'd0;
        m_axis_tkeep      <= 4'd0;
        m_axis_tlast      <= 1'b0;
        m_axis_tvalid     <= 1'b0;
        sync_found        <= 1'b0;
        header_error      <= 1'b0;
        crc_error         <= 1'b0;
        frame_good        <= 1'b0;
        frame_length      <= 16'd0;
        fcs_byte0         <= 8'd0;
        fcs_byte1         <= 8'd0;
        fcs_byte2         <= 8'd0;
    end else begin
        sync_found   <= 1'b0;
        header_error <= 1'b0;
        crc_error    <= 1'b0;
        frame_good   <= 1'b0;

        if ((state == ST_HEADER) || (state == ST_BODY)) begin
            if (s_dibit_valid)
                watchdog <= 32'd0;
            else if (watchdog >= WATCHDOG_CYCLES-1) begin
                state <= ST_SEARCH;
                watchdog <= 32'd0;
                dibit_count <= 2'd0;
            end else
                watchdog <= watchdog + 1'b1;
        end else
            watchdog <= 32'd0;

        if (state == ST_SEARCH) begin
            m_axis_tvalid <= 1'b0;
            if (s_dibit_valid) begin
                sync_shift <= shifted_sync;
                if (shifted_sync == 32'hEB90CAD3) begin
                    state            <= ST_HEADER;
                    sync_found       <= 1'b1;
                    dibit_count      <= 2'd0;
                    byte_shift       <= 6'd0;
                    header_index     <= 2'd0;
                    header_crc_state <= 8'd0;
                end
            end
        end else if ((state == ST_HEADER) && s_dibit_valid) begin
            byte_shift <= {byte_shift[3:0], clean_dibit};
            if (dibit_count != 2'd3) begin
                dibit_count <= dibit_count + 1'b1;
            end else begin
                received_byte = {byte_shift, clean_dibit};
                dibit_count <= 2'd0;
                case (header_index)
                    2'd0: begin
                        control_byte <= received_byte;
                        header_crc_state <= crc8_byte(8'h00, received_byte);
                        header_index <= 2'd1;
                    end
                    2'd1: begin
                        length_hi <= received_byte;
                        header_crc_state <= crc8_byte(header_crc_state, received_byte);
                        header_index <= 2'd2;
                    end
                    2'd2: begin
                        payload_length <= {length_hi, received_byte};
                        header_crc_state <= crc8_byte(header_crc_state, received_byte);
                        header_index <= 2'd3;
                    end
                    default: begin
                        candidate_length = payload_length;
                        if ((control_byte == 8'h10) &&
                            (received_byte == header_crc_state) &&
                            (candidate_length != 0) &&
                            (candidate_length <= MAX_PAYLOAD)) begin
                            state           <= ST_BODY;
                            body_byte_count <= 16'd0;
                            crc_state       <= 32'hFFFFFFFF;
                            scrambler_state <= 7'h5D;
                        end else begin
                            state        <= ST_SEARCH;
                            header_error <= 1'b1;
                        end
                    end
                endcase
            end
        end else if ((state == ST_BODY) && s_dibit_valid) begin
            scrambler_state <= scrambler_next2(scrambler_state);
            byte_shift <= {byte_shift[3:0], clean_dibit};
            if (dibit_count != 2'd3) begin
                dibit_count <= dibit_count + 1'b1;
            end else begin
                received_byte = {byte_shift, clean_dibit};
                dibit_count <= 2'd0;
                if (body_byte_count < payload_length) begin
                    payload_mem[body_byte_count] <= received_byte;
                    crc_state <= crc32_byte(crc_state, received_byte);
                end else begin
                    case (body_byte_count - payload_length)
                        16'd0: fcs_byte0 <= received_byte;
                        16'd1: fcs_byte1 <= received_byte;
                        16'd2: fcs_byte2 <= received_byte;
                        default: begin
                            received_fcs = {received_byte, fcs_byte2,
                                            fcs_byte1, fcs_byte0};
                            if (received_fcs == ~crc_state) begin
                                state         <= ST_OUTPUT;
                                output_index  <= 16'd0;
                                frame_length  <= payload_length;
                                frame_good    <= 1'b1;
                                m_axis_tvalid <= 1'b0;
                            end else begin
                                state     <= ST_SEARCH;
                                crc_error <= 1'b1;
                            end
                        end
                    endcase
                end
                body_byte_count <= body_byte_count + 1'b1;
            end
        end else if (state == ST_OUTPUT) begin
            if (m_axis_tvalid && m_axis_tready && m_axis_tlast) begin
                m_axis_tvalid <= 1'b0;
                m_axis_tlast  <= 1'b0;
                state         <= ST_SEARCH;
            end else if (!m_axis_tvalid || m_axis_tready) begin
                m_axis_tdata <= 32'd0;
                m_axis_tkeep <= 4'd0;
                for (lane = 0; lane < 4; lane = lane + 1) begin
                    if ((output_index + lane) < payload_length) begin
                        m_axis_tdata[(8*lane) +: 8] <= payload_mem[output_index + lane];
                        m_axis_tkeep[lane] <= 1'b1;
                    end
                end
                m_axis_tlast  <= ((output_index + 4) >= payload_length);
                m_axis_tvalid <= 1'b1;
                if ((output_index + 4) >= payload_length)
                    output_index <= payload_length;
                else
                    output_index <= output_index + 4;
            end
        end
    end
end

endmodule
