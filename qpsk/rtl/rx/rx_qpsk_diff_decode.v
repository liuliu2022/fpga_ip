`timescale 1ns / 1ps

// Hard QPSK decision followed by the differential rule used in GoWinSDR v1.
module rx_qpsk_diff_decode (
    input  wire              clk,
    input  wire              rst_n,
    input  wire              symbol_valid,
    input  wire signed [15:0] symbol_i,
    input  wire signed [15:0] symbol_q,
    output reg  [1:0]        data_out,
    output reg               data_valid
);

reg previous_i;
reg previous_q;
wire decision_i = ~symbol_i[15];
wire decision_q = ~symbol_q[15];

always @(posedge clk) begin
    if (!rst_n) begin
        previous_i <= 1'b0;
        previous_q <= 1'b0;
        data_out <= 2'b00;
        data_valid <= 1'b0;
    end else begin
        data_valid <= 1'b0;
        if (symbol_valid) begin
            data_out[0] <= decision_i ^ previous_i;
            data_out[1] <= decision_q ^ previous_q;
            previous_i <= decision_i;
            previous_q <= decision_q;
            data_valid <= 1'b1;
        end
    end
end

endmodule
