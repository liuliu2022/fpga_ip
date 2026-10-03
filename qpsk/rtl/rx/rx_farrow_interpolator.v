`timescale 1ns / 1ps

// Cubic Farrow fractional-delay interpolator adapted from GoWinSDR v1
// interpolate_filter.v.  For x0=x[m], x1=x[m-1], x2=x[m-2], x3=x[m-3]:
//   f1 = 0.5*x0 - 0.5*x1 - 0.5*x2 + 0.5*x3
//   f2 =-0.5*x0 + 1.5*x1 - 0.5*x2 - 0.5*x3
//   y  = f1*mu^2 + f2*mu + x2
// mu is unsigned Q1.15. A request refers to the interval ending at the
// current input sample; the following sample supplies the future point x0.
// The multiplier chain is pipelined for one complex input sample per clock.
module rx_farrow_interpolator (
    input  wire                     clk,
    input  wire                     rst_n,
    input  wire                     in_valid,
    input  wire signed [15:0]       in_i,
    input  wire signed [15:0]       in_q,
    input  wire                     request_valid,
    input  wire        [15:0]       request_mu,
    output reg                      out_valid,
    output reg signed [15:0]        out_i,
    output reg signed [15:0]        out_q
);

reg signed [15:0] i_d1, i_d2, i_d3;
reg signed [15:0] q_d1, q_d2, q_d3;
reg pending;
reg [15:0] pending_mu;

reg s1_valid;
reg signed [17:0] s1_f1_i, s1_f2_i, s1_f1_q, s1_f2_q;
reg signed [15:0] s1_f3_i, s1_f3_q;
reg signed [16:0] s1_mu;

reg s2_valid;
reg signed [34:0] s2_f1_mu_i, s2_f2_mu_i;
reg signed [34:0] s2_f1_mu_q, s2_f2_mu_q;
reg signed [15:0] s2_f3_i, s2_f3_q;
reg signed [16:0] s2_mu;

reg s3_valid;
reg signed [36:0] s3_f1_mu2_i, s3_f1_mu2_q;
reg signed [34:0] s3_f2_mu_i, s3_f2_mu_q;
reg signed [15:0] s3_f3_i, s3_f3_q;

wire signed [17:0] in_i_ext = {{2{in_i[15]}},in_i};
wire signed [17:0] i_d1_ext = {{2{i_d1[15]}},i_d1};
wire signed [17:0] i_d2_ext = {{2{i_d2[15]}},i_d2};
wire signed [17:0] i_d3_ext = {{2{i_d3[15]}},i_d3};
wire signed [17:0] in_q_ext = {{2{in_q[15]}},in_q};
wire signed [17:0] q_d1_ext = {{2{q_d1[15]}},q_d1};
wire signed [17:0] q_d2_ext = {{2{q_d2[15]}},q_d2};
wire signed [17:0] q_d3_ext = {{2{q_d3[15]}},q_d3};

wire signed [17:0] next_f1_i =
    (in_i_ext >>> 1) - (i_d1_ext >>> 1) -
    (i_d2_ext >>> 1) + (i_d3_ext >>> 1);
wire signed [17:0] next_f2_i =
    i_d1_ext + (i_d1_ext >>> 1) - (in_i_ext >>> 1) -
    (i_d2_ext >>> 1) - (i_d3_ext >>> 1);
wire signed [17:0] next_f1_q =
    (in_q_ext >>> 1) - (q_d1_ext >>> 1) -
    (q_d2_ext >>> 1) + (q_d3_ext >>> 1);
wire signed [17:0] next_f2_q =
    q_d1_ext + (q_d1_ext >>> 1) - (in_q_ext >>> 1) -
    (q_d2_ext >>> 1) - (q_d3_ext >>> 1);

wire signed [19:0] result_i =
    $signed(s3_f1_mu2_i >>> 15) + $signed(s3_f2_mu_i >>> 15) + $signed(s3_f3_i);
wire signed [19:0] result_q =
    $signed(s3_f1_mu2_q >>> 15) + $signed(s3_f2_mu_q >>> 15) + $signed(s3_f3_q);

function signed [15:0] sat16;
    input signed [19:0] value;
    begin
        if (value > 32767) sat16 = 16'sh7fff;
        else if (value < -32768) sat16 = -16'sd32768;
        else sat16 = value[15:0];
    end
endfunction

always @(posedge clk) begin
    if (!rst_n) begin
        i_d1 <= 0; i_d2 <= 0; i_d3 <= 0;
        q_d1 <= 0; q_d2 <= 0; q_d3 <= 0;
        pending <= 1'b0; pending_mu <= 16'd0;
        s1_valid <= 1'b0; s2_valid <= 1'b0; s3_valid <= 1'b0;
        s1_f1_i <= 0; s1_f2_i <= 0; s1_f1_q <= 0; s1_f2_q <= 0;
        s1_f3_i <= 0; s1_f3_q <= 0; s1_mu <= 0;
        s2_f1_mu_i <= 0; s2_f2_mu_i <= 0;
        s2_f1_mu_q <= 0; s2_f2_mu_q <= 0;
        s2_f3_i <= 0; s2_f3_q <= 0; s2_mu <= 0;
        s3_f1_mu2_i <= 0; s3_f1_mu2_q <= 0;
        s3_f2_mu_i <= 0; s3_f2_mu_q <= 0;
        s3_f3_i <= 0; s3_f3_q <= 0;
        out_valid <= 1'b0; out_i <= 0; out_q <= 0;
    end else begin
        out_valid <= s3_valid;
        if (s3_valid) begin
            out_i <= sat16(result_i);
            out_q <= sat16(result_q);
        end

        s3_valid <= s2_valid;
        if (s2_valid) begin
            s3_f1_mu2_i <= (s2_f1_mu_i >>> 15) * s2_mu;
            s3_f1_mu2_q <= (s2_f1_mu_q >>> 15) * s2_mu;
            s3_f2_mu_i <= s2_f2_mu_i;
            s3_f2_mu_q <= s2_f2_mu_q;
            s3_f3_i <= s2_f3_i;
            s3_f3_q <= s2_f3_q;
        end

        s2_valid <= s1_valid;
        if (s1_valid) begin
            s2_f1_mu_i <= s1_f1_i * s1_mu;
            s2_f2_mu_i <= s1_f2_i * s1_mu;
            s2_f1_mu_q <= s1_f1_q * s1_mu;
            s2_f2_mu_q <= s1_f2_q * s1_mu;
            s2_f3_i <= s1_f3_i;
            s2_f3_q <= s1_f3_q;
            s2_mu <= s1_mu;
        end

        s1_valid <= in_valid && pending;
        if (in_valid && pending) begin
            s1_f1_i <= next_f1_i; s1_f2_i <= next_f2_i; s1_f3_i <= i_d2;
            s1_f1_q <= next_f1_q; s1_f2_q <= next_f2_q; s1_f3_q <= q_d2;
            s1_mu <= $signed({1'b0,pending_mu});
        end

        if (in_valid) begin
            i_d3 <= i_d2; i_d2 <= i_d1; i_d1 <= in_i;
            q_d3 <= q_d2; q_d2 <= q_d1; q_d1 <= in_q;
            pending <= request_valid;
            if (request_valid) pending_mu <= request_mu;
        end
    end
end

endmodule
