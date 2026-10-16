`timescale 1ns / 1ps

// Gardner timing-error detector with a half-symbol NCO. The architecture is
// the GoWinSDR v1 sequence: NCO -> cubic Farrow interpolation -> alternating
// midpoint/symbol Gardner TED. The numeric rate is adapted to this receiver's
// 12 samples/symbol (six input samples per half-symbol event).
module rx_gardner_timing (
    input  wire                     clk,
    input  wire                     rst_n,
    input  wire                     enable,
    // One-cycle pulse from the packet synchronizer. The preamble uses the
    // wider acquisition loop; after sync the loop becomes a narrow tracker.
    input  wire                     frame_sync,
    input  wire                     in_valid,
    input  wire signed [15:0]       in_i,
    input  wire signed [15:0]       in_q,
    output reg                      symbol_valid,
    output reg signed [15:0]        symbol_i,
    output reg signed [15:0]        symbol_q,
    output reg signed [31:0]        timing_step,
    output reg signed [34:0]        timing_error
);

localparam [31:0] NOMINAL_HALF_SYMBOL_STEP = 32'd715827883; // 2^32/6
localparam [31:0] MIN_HALF_SYMBOL_STEP = 32'd681740840; // 2^32/6.30
localparam [31:0] MAX_HALF_SYMBOL_STEP = 32'd753503035; // 2^32/5.70
localparam signed [31:0] KP_STEP_WORD = 32'sd7158279;
localparam signed [31:0] KI_STEP_WORD = 32'sd95444;
localparam signed [31:0] TRACK_KP_STEP_WORD = 32'sd894785;
localparam signed [31:0] TRACK_KI_STEP_WORD = 32'sd5965;
localparam [31:0] TRACK_MIN_HALF_SYMBOL_STEP = 32'd708669604;
localparam [31:0] TRACK_MAX_HALF_SYMBOL_STEP = 32'd722986162;
localparam integer TRACK_INPUT_SAMPLES = 32768;

reg [31:0] timing_phase;
reg        half_toggle;
reg [2:0]  warmup_count;
reg signed [15:0] early_i, early_q;
reg signed [15:0] middle_i, middle_q;
reg signed [15:0] previous_error_q15;
reg [15:0] tracking_count;

wire [32:0] phase_sum = {1'b0,timing_phase} + {1'b0,timing_step};
wire interpolation_request = in_valid && phase_sum[32];
wire [32:0] samples_to_crossing = 33'h100000000 - {1'b0,timing_phase};
wire [35:0] mu_times_six = (samples_to_crossing << 2) + (samples_to_crossing << 1);
wire [18:0] mu_unclamped = mu_times_six >> 17;
wire [15:0] interpolation_mu = (mu_unclamped >= 19'd32768) ? 16'h8000 : mu_unclamped[15:0];

wire interp_valid;
wire signed [15:0] interp_i;
wire signed [15:0] interp_q;
wire signed [16:0] delta_i = $signed({interp_i[15],interp_i}) - $signed({early_i[15],early_i});
wire signed [16:0] delta_q = $signed({interp_q[15],interp_q}) - $signed({early_q[15],early_q});
wire signed [32:0] error_i = middle_i * delta_i;
wire signed [32:0] error_q = middle_q * delta_q;
wire signed [34:0] gardner_error = {{2{error_i[32]}},error_i} + {{2{error_q[32]}},error_q};
wire [16:0] abs_early_i = early_i[15] ? (17'd0-$signed({early_i[15],early_i})) : {1'b0,early_i};
wire [16:0] abs_early_q = early_q[15] ? (17'd0-$signed({early_q[15],early_q})) : {1'b0,early_q};
wire [16:0] abs_middle_i = middle_i[15] ? (17'd0-$signed({middle_i[15],middle_i})) : {1'b0,middle_i};
wire [16:0] abs_middle_q = middle_q[15] ? (17'd0-$signed({middle_q[15],middle_q})) : {1'b0,middle_q};
wire [16:0] abs_interp_i = interp_i[15] ? (17'd0-$signed({interp_i[15],interp_i})) : {1'b0,interp_i};
wire [16:0] abs_interp_q = interp_q[15] ? (17'd0-$signed({interp_q[15],interp_q})) : {1'b0,interp_q};
wire [16:0] early_magnitude = abs_early_i+abs_early_q;
wire [16:0] middle_magnitude = abs_middle_i+abs_middle_q;
wire [16:0] interp_magnitude = abs_interp_i+abs_interp_q;
wire [16:0] detector_magnitude_max =
    (early_magnitude >= middle_magnitude && early_magnitude >= interp_magnitude) ? early_magnitude :
    (middle_magnitude >= interp_magnitude) ? middle_magnitude : interp_magnitude;
wire [16:0] detector_magnitude = (detector_magnitude_max < 17'd16) ? 17'd16 : detector_magnitude_max;
wire [4:0] detector_exponent = ceil_log2_17(detector_magnitude);
// The TED error is quadratic in amplitude.  For exponent >= 7 normalize by
// shifting right; below that point a left shift preserves the same Q1.15
// loop gain instead of wrapping an unsigned negative shift count.
wire [5:0] gardner_right_shift = ({1'b0,detector_exponent} << 1)-6'd14;
wire [5:0] gardner_left_shift = 6'd14-({1'b0,detector_exponent} << 1);
wire signed [34:0] error_scaled = (detector_exponent >= 5'd7) ?
    (gardner_error >>> gardner_right_shift) :
    (gardner_error <<< gardner_left_shift);
wire signed [15:0] error_q15 = sat_error_q15(error_scaled);
wire signed [16:0] error_difference =
    $signed({error_q15[15],error_q15}) -
    $signed({previous_error_q15[15],previous_error_q15});
wire tracking_active = (tracking_count != 0);
wire signed [31:0] selected_kp = tracking_active ?
                                      TRACK_KP_STEP_WORD : KP_STEP_WORD;
wire signed [31:0] selected_ki = tracking_active ?
                                      TRACK_KI_STEP_WORD : KI_STEP_WORD;
wire signed [48:0] proportional_product = error_difference * selected_kp;
wire signed [47:0] integral_product = error_q15 * selected_ki;
wire signed [49:0] loop_product_sum =
    {{1{proportional_product[48]}},proportional_product} +
    {{2{integral_product[47]}},integral_product};
wire signed [31:0] timing_step_delta = loop_product_sum >>> 15;
wire signed [32:0] timing_step_candidate =
    $signed({timing_step[31],timing_step})+
    $signed({timing_step_delta[31],timing_step_delta});
wire signed [31:0] bounded_timing_step =
    (timing_step_candidate < $signed({1'b0,(tracking_active ? TRACK_MIN_HALF_SYMBOL_STEP : MIN_HALF_SYMBOL_STEP)})) ?
        $signed(tracking_active ? TRACK_MIN_HALF_SYMBOL_STEP : MIN_HALF_SYMBOL_STEP) :
    (timing_step_candidate > $signed({1'b0,(tracking_active ? TRACK_MAX_HALF_SYMBOL_STEP : MAX_HALF_SYMBOL_STEP)})) ?
        $signed(tracking_active ? TRACK_MAX_HALF_SYMBOL_STEP : MAX_HALF_SYMBOL_STEP) :
    timing_step_candidate[31:0];

function signed [15:0] sat_error_q15;
    input signed [34:0] value;
    begin
        if (value > 32767) sat_error_q15 = 16'sh7fff;
        else if (value < -32768) sat_error_q15 = -16'sd32768;
        else sat_error_q15 = value[15:0];
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

rx_farrow_interpolator u_interpolator (
    .clk(clk), .rst_n(rst_n), .enable(enable),
    .in_valid(in_valid), .in_i(in_i), .in_q(in_q),
    .request_valid(interpolation_request), .request_mu(interpolation_mu),
    .out_valid(interp_valid), .out_i(interp_i), .out_q(interp_q)
);

always @(posedge clk) begin
    if (!rst_n || !enable) begin
        timing_phase <= 32'd0;
        timing_step <= NOMINAL_HALF_SYMBOL_STEP;
        half_toggle <= 1'b0;
        warmup_count <= 3'd0;
        early_i <= 16'sd0; early_q <= 16'sd0;
        middle_i <= 16'sd0; middle_q <= 16'sd0;
        previous_error_q15 <= 16'sd0;
        tracking_count <= 16'd0;
        symbol_i <= 16'sd0; symbol_q <= 16'sd0;
        symbol_valid <= 1'b0;
        timing_error <= 35'sd0;
    end else begin
        symbol_valid <= 1'b0;
        if (frame_sync) begin
            // RFSoC DAC and ADC are clock coherent in loopback. Preserve the
            // interpolation phase but discard a biased acquisition rate.
            timing_step <= NOMINAL_HALF_SYMBOL_STEP;
            previous_error_q15 <= 16'sd0;
            tracking_count <= TRACK_INPUT_SAMPLES;
        end else if (in_valid && tracking_active) begin
            tracking_count <= tracking_count - 1'b1;
        end
        if (in_valid) begin
            timing_phase <= phase_sum[31:0];
        end
        if (interp_valid) begin
            early_i <= middle_i;
            early_q <= middle_q;
            middle_i <= interp_i;
            middle_q <= interp_q;
            if (warmup_count != 3'd7)
                warmup_count <= warmup_count + 1'b1;

            // Every other half-symbol strobe is a symbol centre.
            if (!half_toggle && warmup_count >= 3'd2) begin
                symbol_i <= interp_i;
                symbol_q <= interp_q;
                symbol_valid <= 1'b1;
                timing_error <= gardner_error;
                if (!frame_sync) begin
                    timing_step <= bounded_timing_step;
                    previous_error_q15 <= error_q15;
                end
            end
            half_toggle <= ~half_toggle;
        end
    end
end

endmodule
