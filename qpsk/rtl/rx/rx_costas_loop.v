`timescale 1ns / 1ps

// Decision-directed QPSK Costas loop for the RFSoC receive chain.
// The PI coefficients are derived from GoWinSDR Matlab/costas.m with
// zeta=0.707 and BnTs=0.01, converted to a 32-bit phase accumulator.  The
// detector uses the GoWinSDR fixed-scale hardware approach.  The nominal
// |I|+|Q| level is 8192, so conversion to signed Q1.15 is an exact <<2 and
// does not infer a variable divider on the 61.44-MHz feedback path.
module rx_costas_loop (
    input  wire                     clk,
    input  wire                     rst_n,
    input  wire                     in_valid,
    input  wire signed [15:0]       in_i,
    input  wire signed [15:0]       in_q,
    output reg                      out_valid,
    output reg signed [15:0]        out_i,
    output reg signed [15:0]        out_q,
    output reg signed [31:0]        frequency_word,
    output wire [31:0]              phase_word
);

reg [31:0] phase_acc;
reg signed [15:0] error_q15;
localparam signed [31:0] KP_PHASE_WORD = 32'sd19059814;
localparam signed [31:0] KI_PHASE_WORD = 32'sd269587;
wire [7:0] nco_phase = phase_acc[31:24];
wire signed [15:0] nco_sin = sin_q15(nco_phase);
wire signed [15:0] nco_cos = sin_q15(nco_phase + 8'd64);
wire signed [32:0] mix_i_full = in_i * nco_cos + in_q * nco_sin;
wire signed [32:0] mix_q_full = in_q * nco_cos - in_i * nco_sin;
wire signed [17:0] mix_i_scaled = mix_i_full >>> 15;
wire signed [17:0] mix_q_scaled = mix_q_full >>> 15;
wire signed [15:0] mix_i = sat16(mix_i_scaled);
wire signed [15:0] mix_q = sat16(mix_q_scaled);

// QPSK decision-directed detector: sign(I)*Q - sign(Q)*I.  The RRC output is
// designed around a nominal |I|+|Q| of 8192; therefore raw_error*4 maps that
// level to Q1.15 without a divider.  Saturation bounds large transients.  The
// registered detector output is consumed by the PI section on the next valid
// sample, matching the MATLAB fixed-point model.
wire signed [16:0] signed_q = mix_i[15] ? -$signed({mix_q[15],mix_q}) : $signed({mix_q[15],mix_q});
wire signed [16:0] signed_i = mix_q[15] ? -$signed({mix_i[15],mix_i}) : $signed({mix_i[15],mix_i});
wire signed [17:0] raw_phase_error = signed_q - signed_i;
wire signed [19:0] scaled_phase_error = {{2{raw_phase_error[17]}},raw_phase_error} <<< 2;
wire signed [15:0] normalized_error = sat_q15(scaled_phase_error);

wire signed [47:0] proportional_product = error_q15 * KP_PHASE_WORD;
wire signed [47:0] integral_product = error_q15 * KI_PHASE_WORD;
wire signed [31:0] proportional = proportional_product >>> 15;
wire signed [31:0] integral_delta = integral_product >>> 15;

assign phase_word = phase_acc;

function signed [15:0] sat16;
    input signed [17:0] value;
    begin
        if (value > 32767) sat16 = 16'sh7fff;
        else if (value < -32768) sat16 = -16'sd32768;
        else sat16 = value[15:0];
    end
endfunction

function signed [15:0] sat_q15;
    input signed [19:0] value;
    begin
        if (value > 32767) sat_q15 = 16'sh7fff;
        else if (value < -32768) sat_q15 = -16'sd32768;
        else sat_q15 = value[15:0];
    end
endfunction

function signed [15:0] quarter_sin;
    input [6:0] index;
    begin
        case(index)
            0: quarter_sin=0;
            1: quarter_sin=804;
            2: quarter_sin=1608;
            3: quarter_sin=2410;
            4: quarter_sin=3212;
            5: quarter_sin=4011;
            6: quarter_sin=4808;
            7: quarter_sin=5602;
            8: quarter_sin=6393;
            9: quarter_sin=7179;
            10: quarter_sin=7962;
            11: quarter_sin=8739;
            12: quarter_sin=9512;
            13: quarter_sin=10278;
            14: quarter_sin=11039;
            15: quarter_sin=11793;
            16: quarter_sin=12539;
            17: quarter_sin=13279;
            18: quarter_sin=14010;
            19: quarter_sin=14732;
            20: quarter_sin=15446;
            21: quarter_sin=16151;
            22: quarter_sin=16846;
            23: quarter_sin=17530;
            24: quarter_sin=18204;
            25: quarter_sin=18868;
            26: quarter_sin=19519;
            27: quarter_sin=20159;
            28: quarter_sin=20787;
            29: quarter_sin=21403;
            30: quarter_sin=22005;
            31: quarter_sin=22594;
            32: quarter_sin=23170;
            33: quarter_sin=23731;
            34: quarter_sin=24279;
            35: quarter_sin=24811;
            36: quarter_sin=25329;
            37: quarter_sin=25832;
            38: quarter_sin=26319;
            39: quarter_sin=26790;
            40: quarter_sin=27245;
            41: quarter_sin=27683;
            42: quarter_sin=28105;
            43: quarter_sin=28510;
            44: quarter_sin=28898;
            45: quarter_sin=29268;
            46: quarter_sin=29621;
            47: quarter_sin=29956;
            48: quarter_sin=30273;
            49: quarter_sin=30571;
            50: quarter_sin=30852;
            51: quarter_sin=31113;
            52: quarter_sin=31356;
            53: quarter_sin=31580;
            54: quarter_sin=31785;
            55: quarter_sin=31971;
            56: quarter_sin=32137;
            57: quarter_sin=32285;
            58: quarter_sin=32412;
            59: quarter_sin=32521;
            60: quarter_sin=32609;
            61: quarter_sin=32678;
            62: quarter_sin=32728;
            63: quarter_sin=32757;
            64: quarter_sin=32767;
            default: quarter_sin=0;
        endcase
    end
endfunction

function signed [15:0] sin_q15;
    input [7:0] index;
    reg signed [15:0] magnitude;
    begin
        case(index[7:6])
            2'd0: sin_q15 = quarter_sin({1'b0,index[5:0]});
            2'd1: sin_q15 = quarter_sin(7'd64-{1'b0,index[5:0]});
            2'd2: begin
                magnitude = quarter_sin({1'b0,index[5:0]});
                sin_q15 = -magnitude;
            end
            default: begin
                magnitude = quarter_sin(7'd64-{1'b0,index[5:0]});
                sin_q15 = -magnitude;
            end
        endcase
    end
endfunction

always @(posedge clk) begin
    if (!rst_n) begin
        phase_acc <= 32'd0;
        frequency_word <= 32'sd0;
        error_q15 <= 16'sd0;
        out_valid <= 1'b0;
        out_i <= 16'sd0;
        out_q <= 16'sd0;
    end else begin
        out_valid <= in_valid;
        if (in_valid) begin
            out_i <= mix_i;
            out_q <= mix_q;
            error_q15 <= normalized_error;
            frequency_word <= frequency_word + integral_delta;
            phase_acc <= phase_acc + frequency_word + proportional;
        end
    end
end

endmodule
