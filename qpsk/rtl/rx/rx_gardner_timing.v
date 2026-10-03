`timescale 1ns / 1ps

// Gardner timing-error detector with a half-symbol NCO. The architecture is
// the GoWinSDR v1 sequence: NCO -> cubic Farrow interpolation -> alternating
// midpoint/symbol Gardner TED. The numeric rate is adapted to this receiver's
// 12 samples/symbol (six input samples per half-symbol event).
module rx_gardner_timing (
    input  wire                     clk,
    input  wire                     rst_n,
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
localparam signed [31:0] KP_STEP_WORD = 32'sd19959391;
localparam signed [31:0] KI_STEP_WORD = 32'sd282311;

reg [31:0] timing_phase;
reg        half_toggle;
reg [2:0]  warmup_count;
reg signed [15:0] early_i, early_q;
reg signed [15:0] middle_i, middle_q;
reg signed [15:0] previous_error_q15;

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
wire signed [34:0] error_scaled = gardner_error >>> 11;
wire signed [15:0] error_q15 = sat_error_q15(error_scaled);
wire signed [16:0] error_difference =
    $signed({error_q15[15],error_q15}) -
    $signed({previous_error_q15[15],previous_error_q15});
wire signed [48:0] proportional_product = error_difference * KP_STEP_WORD;
wire signed [47:0] integral_product = error_q15 * KI_STEP_WORD;
wire signed [49:0] loop_product_sum =
    {{1{proportional_product[48]}},proportional_product} +
    {{2{integral_product[47]}},integral_product};
wire signed [31:0] timing_step_delta = loop_product_sum >>> 15;

function signed [15:0] sat_error_q15;
    input signed [34:0] value;
    begin
        if (value > 32767) sat_error_q15 = 16'sh7fff;
        else if (value < -32768) sat_error_q15 = -16'sd32768;
        else sat_error_q15 = value[15:0];
    end
endfunction

rx_farrow_interpolator u_interpolator (
    .clk(clk), .rst_n(rst_n),
    .in_valid(in_valid), .in_i(in_i), .in_q(in_q),
    .request_valid(interpolation_request), .request_mu(interpolation_mu),
    .out_valid(interp_valid), .out_i(interp_i), .out_q(interp_q)
);

always @(posedge clk) begin
    if (!rst_n) begin
        timing_phase <= 32'd0;
        timing_step <= NOMINAL_HALF_SYMBOL_STEP;
        half_toggle <= 1'b0;
        warmup_count <= 3'd0;
        early_i <= 16'sd0; early_q <= 16'sd0;
        middle_i <= 16'sd0; middle_q <= 16'sd0;
        previous_error_q15 <= 16'sd0;
        symbol_i <= 16'sd0; symbol_q <= 16'sd0;
        symbol_valid <= 1'b0;
        timing_error <= 35'sd0;
    end else begin
        symbol_valid <= 1'b0;
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
                timing_step <= timing_step + timing_step_delta;
                previous_error_q15 <= error_q15;
            end
            half_toggle <= ~half_toggle;
        end
    end
end

endmodule
