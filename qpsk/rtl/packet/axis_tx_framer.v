`timescale 1ns / 1ps

// Store-and-forward AXI4-Stream packet framer for the QPSK symbol interface.
// Frame on air (bytes):
//   32 x 55 | EB 90 CA D3 | 10 | length[15:8] | length[7:0] | header_crc8
//   | scrambled payload | scrambled CRC32/IEEE (little endian)
// Each byte is transmitted most-significant dibit first.
module axis_tx_framer #(
    parameter integer MAX_PAYLOAD    = 512,
    parameter integer PREAMBLE_BYTES = 32
) (
    (* X_INTERFACE_INFO = "xilinx.com:signal:clock:1.0 clk CLK" *)
    (* X_INTERFACE_PARAMETER = "ASSOCIATED_BUSIF s_axis, ASSOCIATED_RESET rst_n, FREQ_HZ 61440000" *)
    input  wire        clk,
    (* X_INTERFACE_INFO = "xilinx.com:signal:reset:1.0 rst_n RST" *)
    (* X_INTERFACE_PARAMETER = "POLARITY ACTIVE_LOW" *)
    input  wire        rst_n,

    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 s_axis TDATA" *)
    input  wire [31:0] s_axis_tdata,
    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 s_axis TKEEP" *)
    input  wire [3:0]  s_axis_tkeep,
    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 s_axis TLAST" *)
    input  wire        s_axis_tlast,
    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 s_axis TVALID" *)
    input  wire        s_axis_tvalid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 s_axis TREADY" *)
    output wire        s_axis_tready,

    (* X_INTERFACE_IGNORE = "true" *) output wire [1:0] m_dibit,
    (* X_INTERFACE_IGNORE = "true" *) output wire       m_dibit_valid,
    (* X_INTERFACE_IGNORE = "true" *) input  wire       m_dibit_ready,

    output reg         frame_accepted,
    output reg         frame_sent,
    output reg [15:0]  frame_length
);

localparam [2:0] ST_RECEIVE  = 3'd0;
localparam [2:0] ST_PREAMBLE = 3'd1;
localparam [2:0] ST_SYNC     = 3'd2;
localparam [2:0] ST_HEADER   = 3'd3;
localparam [2:0] ST_PAYLOAD  = 3'd4;
localparam [2:0] ST_FCS      = 3'd5;

reg [2:0] state;
// AXI words are stored with one write port so Vivado can infer a compact RAM.
reg [31:0] payload_mem [0:(MAX_PAYLOAD/4)-1];
reg [15:0] payload_length;
reg [15:0] byte_index;
reg [1:0] dibit_index;
reg [31:0] crc_state;
reg [6:0] scrambler_state;

integer lane;
reg [15:0] next_length;
reg [31:0] next_crc;
reg [7:0] selected_byte;
reg [1:0] raw_dibit;

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

function [1:0] scramble_dibit;
    input [1:0] data_in;
    input [6:0] state_in;
    reg [6:0] s;
    reg feedback;
    begin
        s = state_in;
        feedback = s[6] ^ s[3];
        scramble_dibit[1] = data_in[1] ^ feedback;
        s = {s[5:0], feedback};
        feedback = s[6] ^ s[3];
        scramble_dibit[0] = data_in[0] ^ feedback;
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

wire [7:0] header_crc = crc8_byte(
    crc8_byte(crc8_byte(8'h00, 8'h10), payload_length[15:8]),
    payload_length[7:0]);
wire [31:0] final_crc = ~crc_state;

assign s_axis_tready = (state == ST_RECEIVE) &&
                       (payload_length <= (MAX_PAYLOAD - 4));
assign m_dibit_valid = (state != ST_RECEIVE);
assign m_dibit = ((state == ST_PAYLOAD) || (state == ST_FCS)) ?
                 scramble_dibit(raw_dibit, scrambler_state) : raw_dibit;

always @* begin
    selected_byte = 8'h00;
    case (state)
        ST_PREAMBLE: selected_byte = 8'h55;
        ST_SYNC: begin
            case (byte_index[1:0])
                2'd0: selected_byte = 8'hEB;
                2'd1: selected_byte = 8'h90;
                2'd2: selected_byte = 8'hCA;
                default: selected_byte = 8'hD3;
            endcase
        end
        ST_HEADER: begin
            case (byte_index[1:0])
                2'd0: selected_byte = 8'h10;
                2'd1: selected_byte = payload_length[15:8];
                2'd2: selected_byte = payload_length[7:0];
                default: selected_byte = header_crc;
            endcase
        end
        ST_PAYLOAD: begin
            case (byte_index[1:0])
                2'd0: selected_byte = payload_mem[byte_index[15:2]][7:0];
                2'd1: selected_byte = payload_mem[byte_index[15:2]][15:8];
                2'd2: selected_byte = payload_mem[byte_index[15:2]][23:16];
                default: selected_byte = payload_mem[byte_index[15:2]][31:24];
            endcase
        end
        ST_FCS: begin
            case (byte_index[1:0])
                2'd0: selected_byte = final_crc[7:0];
                2'd1: selected_byte = final_crc[15:8];
                2'd2: selected_byte = final_crc[23:16];
                default: selected_byte = final_crc[31:24];
            endcase
        end
        default: selected_byte = 8'h00;
    endcase

    case (dibit_index)
        2'd0: raw_dibit = selected_byte[7:6];
        2'd1: raw_dibit = selected_byte[5:4];
        2'd2: raw_dibit = selected_byte[3:2];
        default: raw_dibit = selected_byte[1:0];
    endcase
end

always @(posedge clk) begin
    if (!rst_n) begin
        state             <= ST_RECEIVE;
        payload_length    <= 16'd0;
        frame_length      <= 16'd0;
        byte_index        <= 16'd0;
        dibit_index       <= 2'd0;
        crc_state         <= 32'hFFFFFFFF;
        scrambler_state   <= 7'h5D;
        frame_accepted    <= 1'b0;
        frame_sent        <= 1'b0;
    end else begin
        frame_accepted <= 1'b0;
        frame_sent     <= 1'b0;

        if (s_axis_tvalid && s_axis_tready) begin
            next_length = payload_length;
            next_crc = crc_state;
            payload_mem[payload_length[15:2]] <= s_axis_tdata;
            for (lane = 0; lane < 4; lane = lane + 1) begin
                if (s_axis_tkeep[lane] && (next_length < MAX_PAYLOAD)) begin
                    next_crc = crc32_byte(next_crc, s_axis_tdata[(8*lane) +: 8]);
                    next_length = next_length + 1'b1;
                end
            end
            payload_length <= next_length;
            crc_state <= next_crc;

            if (s_axis_tlast && (next_length != 0)) begin
                frame_length   <= next_length;
                frame_accepted <= 1'b1;
                state          <= ST_PREAMBLE;
                byte_index     <= 16'd0;
                dibit_index    <= 2'd0;
            end
        end

        if (m_dibit_valid && m_dibit_ready) begin
            if ((state == ST_PAYLOAD) || (state == ST_FCS))
                scrambler_state <= scrambler_next2(scrambler_state);

            if (dibit_index != 2'd3) begin
                dibit_index <= dibit_index + 1'b1;
            end else begin
                dibit_index <= 2'd0;
                case (state)
                    ST_PREAMBLE: begin
                        if (byte_index == PREAMBLE_BYTES-1) begin
                            state <= ST_SYNC;
                            byte_index <= 16'd0;
                        end else byte_index <= byte_index + 1'b1;
                    end
                    ST_SYNC: begin
                        if (byte_index == 16'd3) begin
                            state <= ST_HEADER;
                            byte_index <= 16'd0;
                        end else byte_index <= byte_index + 1'b1;
                    end
                    ST_HEADER: begin
                        if (byte_index == 16'd3) begin
                            state <= ST_PAYLOAD;
                            byte_index <= 16'd0;
                            scrambler_state <= 7'h5D;
                        end else byte_index <= byte_index + 1'b1;
                    end
                    ST_PAYLOAD: begin
                        if (byte_index == payload_length-1) begin
                            state <= ST_FCS;
                            byte_index <= 16'd0;
                        end else byte_index <= byte_index + 1'b1;
                    end
                    ST_FCS: begin
                        if (byte_index == 16'd3) begin
                            state          <= ST_RECEIVE;
                            payload_length <= 16'd0;
                            crc_state      <= 32'hFFFFFFFF;
                            byte_index     <= 16'd0;
                            frame_sent     <= 1'b1;
                        end else byte_index <= byte_index + 1'b1;
                    end
                    default: state <= ST_RECEIVE;
                endcase
            end
        end
    end
end

endmodule
