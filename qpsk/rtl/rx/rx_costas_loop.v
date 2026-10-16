`timescale 1ns / 1ps

// Decision-directed QPSK Costas loop for the RFSoC receive chain.
// The PI coefficients are derived from GoWinSDR Matlab/costas.m with
// zeta=0.707 and BnTs=0.01, converted to a 32-bit phase accumulator.  The
// detector keeps the GoWinSDR decision-directed form, but normalizes it by
// the next power of two above |I|+|Q|.  This is divider-free and removes the
// former hidden requirement that the RRC output magnitude be near 8192.
module rx_costas_loop (
    input  wire                     clk,
    input  wire                     rst_n,
    input  wire                     force_recovery,
    input  wire                     in_valid,
    input  wire signed [15:0]       in_i,
    input  wire signed [15:0]       in_q,
    output reg                      out_valid,
    output reg signed [15:0]        out_i,
    output reg signed [15:0]        out_q,
    output reg signed [31:0]        frequency_word,
    output wire [31:0]              phase_word,
    output reg                      locked,
    output reg                      recovery_pulse,
    output reg                      signal_present
);

reg [31:0] phase_acc;
reg signed [15:0] error_q15;
reg signed [31:0] lock_metric;
reg [7:0] unlock_count;
reg [8:0] lock_good_count;
reg [9:0] recovery_cooldown;
reg [21:0] signal_magnitude_accumulator;
reg [6:0] signal_on_count;
reg [7:0] signal_off_count;
localparam signed [31:0] KP_PHASE_WORD = 32'sd19059814;
localparam signed [31:0] KI_PHASE_WORD = 32'sd269587;
localparam signed [31:0] MAX_FREQUENCY_WORD = 32'sd17476267; // +/-250 kHz
localparam signed [31:0] LOCK_THRESHOLD = 32'sd7864;         // 0.24 Q1.15
localparam signed [31:0] UNLOCK_THRESHOLD = 32'sd9175;       // 0.28 Q1.15
localparam [7:0] UNLOCK_SAMPLES = 8'd128;
localparam [8:0] LOCK_SAMPLES = 9'd256;
localparam [9:0] RECOVERY_COOLDOWN = 10'd512;
// The real ILA captures show useful decoding down to about |I|+|Q|=20.
// Qualify the loop with a slow L1-magnitude average so noise cannot assert
// carrier lock.  Separate on/off thresholds avoid chatter near the limit.
localparam [16:0] SIGNAL_ON_MAGNITUDE = 17'd16;
localparam [16:0] SIGNAL_OFF_MAGNITUDE = 17'd10;
localparam [6:0] SIGNAL_ON_SAMPLES = 7'd64;
localparam [7:0] SIGNAL_OFF_SAMPLES = 8'd128;
wire [7:0] nco_phase = phase_acc[31:24];
wire signed [15:0] nco_sin = sin_q15(nco_phase);
wire signed [15:0] nco_cos = sin_q15(nco_phase + 8'd64);
wire signed [32:0] mix_i_full = in_i * nco_cos + in_q * nco_sin;
wire signed [32:0] mix_q_full = in_q * nco_cos - in_i * nco_sin;
wire signed [17:0] mix_i_scaled = mix_i_full >>> 15;
wire signed [17:0] mix_q_scaled = mix_q_full >>> 15;
wire signed [15:0] mix_i = sat16(mix_i_scaled);
wire signed [15:0] mix_q = sat16(mix_q_scaled);

// QPSK decision-directed detector: sign(I)*Q - sign(Q)*I.  A leading-bit
// detector implements raw_error*2^(15-ceil(log2(|I|+|Q|))).
wire signed [16:0] signed_q = mix_i[15] ? -$signed({mix_q[15],mix_q}) : $signed({mix_q[15],mix_q});
wire signed [16:0] signed_i = mix_q[15] ? -$signed({mix_i[15],mix_i}) : $signed({mix_i[15],mix_i});
wire signed [17:0] raw_phase_error = signed_q - signed_i;
wire [16:0] abs_mix_i = mix_i[15] ? (17'd0-$signed({mix_i[15],mix_i})) : {1'b0,mix_i};
wire [16:0] abs_mix_q = mix_q[15] ? (17'd0-$signed({mix_q[15],mix_q})) : {1'b0,mix_q};
wire [16:0] detector_magnitude_sum = abs_mix_i + abs_mix_q;
wire [16:0] detector_magnitude = (detector_magnitude_sum < 17'd16) ? 17'd16 : detector_magnitude_sum;
wire [21:0] signal_accumulator_candidate =
    signal_magnitude_accumulator - (signal_magnitude_accumulator >> 5) +
    detector_magnitude_sum;
wire signal_acquisition_active = signal_present ||
    ((!signal_present) &&
     (signal_on_count >= SIGNAL_ON_SAMPLES-1'b1) &&
     (signal_accumulator_candidate >= (SIGNAL_ON_MAGNITUDE << 5)));
wire [4:0] detector_exponent = ceil_log2_17(detector_magnitude);
wire signed [33:0] raw_phase_error_ext = {{16{raw_phase_error[17]}},raw_phase_error};
wire signed [33:0] scaled_phase_error = (detector_exponent <= 5'd15) ?
    (raw_phase_error_ext <<< (5'd15-detector_exponent)) :
    (raw_phase_error_ext >>> (detector_exponent-5'd15));
wire signed [15:0] normalized_error = sat_q15(scaled_phase_error);

wire signed [47:0] proportional_product = error_q15 * KP_PHASE_WORD;
wire signed [47:0] integral_product = error_q15 * KI_PHASE_WORD;
wire signed [31:0] proportional = proportional_product >>> 15;
wire signed [31:0] integral_delta = integral_product >>> 15;
wire signed [32:0] frequency_candidate =
    $signed({frequency_word[31],frequency_word}) +
    $signed({integral_delta[31],integral_delta});
wire signed [31:0] bounded_frequency =
    (frequency_candidate > $signed({MAX_FREQUENCY_WORD[31],MAX_FREQUENCY_WORD})) ? MAX_FREQUENCY_WORD :
    (frequency_candidate < -$signed({MAX_FREQUENCY_WORD[31],MAX_FREQUENCY_WORD})) ? -MAX_FREQUENCY_WORD :
    frequency_candidate[31:0];
wire [16:0] abs_registered_error = error_q15[15] ?
    (17'd0-$signed({error_q15[15],error_q15})) : {1'b0,error_q15};
wire signed [32:0] metric_difference =
    $signed({16'd0,abs_registered_error})-$signed({lock_metric[31],lock_metric});
wire signed [32:0] metric_candidate_wide =
    $signed({lock_metric[31],lock_metric})+(metric_difference >>> 6);
wire signed [31:0] metric_candidate = metric_candidate_wide[31:0];

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
    input signed [33:0] value;
    begin
        if (value > 32767) sat_q15 = 16'sh7fff;
        else if (value < -32768) sat_q15 = -16'sd32768;
        else sat_q15 = value[15:0];
    end
endfunction

function [4:0] ceil_log2_17;
    input [16:0] value;
    begin
        if      (value <= 17'd16)    ceil_log2_17 = 5'd4;
        else if (value <= 17'd32)    ceil_log2_17 = 5'd5;
        else if (value <= 17'd64)    ceil_log2_17 = 5'd6;
        else if (value <= 17'd128)   ceil_log2_17 = 5'd7;
        else if (value <= 17'd256)   ceil_log2_17 = 5'd8;
        else if (value <= 17'd512)   ceil_log2_17 = 5'd9;
        else if (value <= 17'd1024)  ceil_log2_17 = 5'd10;
        else if (value <= 17'd2048)  ceil_log2_17 = 5'd11;
        else if (value <= 17'd4096)  ceil_log2_17 = 5'd12;
        else if (value <= 17'd8192)  ceil_log2_17 = 5'd13;
        else if (value <= 17'd16384) ceil_log2_17 = 5'd14;
        else if (value <= 17'd32768) ceil_log2_17 = 5'd15;
        else                          ceil_log2_17 = 5'd16;
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
        lock_metric <= 32'sd0;
        unlock_count <= 8'd0;
        lock_good_count <= 9'd0;
        recovery_cooldown <= 10'd0;
        signal_magnitude_accumulator <= 22'd0;
        signal_on_count <= 7'd0;
        signal_off_count <= 8'd0;
        signal_present <= 1'b0;
        locked <= 1'b0;
        recovery_pulse <= 1'b0;
        out_valid <= 1'b0;
        out_i <= 16'sd0;
        out_q <= 16'sd0;
    end else begin
        out_valid <= in_valid;
        recovery_pulse <= 1'b0;
        if (force_recovery) begin
            phase_acc <= 32'd0;
            frequency_word <= 32'sd0;
            error_q15 <= 16'sd0;
            lock_metric <= 32'sd0;
            unlock_count <= 8'd0;
            lock_good_count <= 9'd0;
            recovery_cooldown <= RECOVERY_COOLDOWN;
            locked <= 1'b0;
            recovery_pulse <= 1'b1;
        end else if (in_valid) begin
            out_i <= mix_i;
            out_q <= mix_q;
            signal_magnitude_accumulator <= signal_accumulator_candidate;

            if (!signal_present) begin
                signal_off_count <= 8'd0;
                if (signal_accumulator_candidate >= (SIGNAL_ON_MAGNITUDE << 5)) begin
                    if (signal_on_count < SIGNAL_ON_SAMPLES)
                        signal_on_count <= signal_on_count + 1'b1;
                    if (signal_on_count >= SIGNAL_ON_SAMPLES-1'b1) begin
                        signal_present <= 1'b1;
                        signal_on_count <= 7'd0;
                    end
                end else begin
                    signal_on_count <= 7'd0;
                end

            end else begin
                signal_on_count <= 7'd0;
                if (signal_accumulator_candidate < (SIGNAL_OFF_MAGNITUDE << 5)) begin
                    if (signal_off_count < SIGNAL_OFF_SAMPLES)
                        signal_off_count <= signal_off_count + 1'b1;
                    if (signal_off_count >= SIGNAL_OFF_SAMPLES-1'b1) begin
                        signal_present <= 1'b0;
                        signal_off_count <= 8'd0;
                    end
                end else begin
                    signal_off_count <= 8'd0;
                end
            end

            if (!signal_acquisition_active) begin
                // Do not allow thermal noise or converter offsets below the
                // qualified threshold to build a plausible carrier state.
                phase_acc <= 32'd0;
                frequency_word <= 32'sd0;
                error_q15 <= 16'sd0;
                lock_metric <= 32'sd0;
                unlock_count <= 8'd0;
                lock_good_count <= 9'd0;
                recovery_cooldown <= 10'd0;
                locked <= 1'b0;
            end else begin
                // Start acquisition on the exact sample that completes the
                // 64-sample energy qualification (not one sample later).
                error_q15 <= normalized_error;
                lock_metric <= metric_candidate;

                if (recovery_cooldown != 0)
                    recovery_cooldown <= recovery_cooldown - 1'b1;

                if (metric_candidate > UNLOCK_THRESHOLD) begin
                    if (unlock_count != 8'hff)
                        unlock_count <= unlock_count + 1'b1;
                    lock_good_count <= 9'd0;
                end else begin
                    if (unlock_count != 0)
                        unlock_count <= unlock_count - 1'b1;
                    if ((metric_candidate < LOCK_THRESHOLD) &&
                        (recovery_cooldown == 0)) begin
                        if (lock_good_count < LOCK_SAMPLES)
                            lock_good_count <= lock_good_count + 1'b1;
                        if ((lock_good_count >= LOCK_SAMPLES-1'b1) &&
                            signal_present)
                            locked <= 1'b1;
                    end else begin
                        lock_good_count <= 9'd0;
                    end
                end

                if ((unlock_count >= UNLOCK_SAMPLES-1'b1) &&
                    (metric_candidate > UNLOCK_THRESHOLD) &&
                    (recovery_cooldown == 0)) begin
                    frequency_word <= 32'sd0;
                    phase_acc <= 32'd0;
                    lock_metric <= 32'sd0;
                    unlock_count <= 8'd0;
                    lock_good_count <= 9'd0;
                    recovery_cooldown <= RECOVERY_COOLDOWN;
                    locked <= 1'b0;
                    recovery_pulse <= 1'b1;
                end else begin
                    frequency_word <= bounded_frequency;
                    phase_acc <= phase_acc + frequency_word + proportional;
                end
            end
        end
    end
end

endmodule
