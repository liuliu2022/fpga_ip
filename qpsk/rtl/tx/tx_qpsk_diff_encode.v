`timescale 1ns / 1ps

// Differential encoder used by the GoWinSDR v1 QPSK transmitter.
// A missing input word is encoded as 2'b00, so the last constellation
// point is held and the DAC waveform remains continuous.
module tx_qpsk_diff_encode (
    input  wire       clk,
    input  wire       rst_n,
    input  wire       symbol_strobe,
    input  wire [1:0] data_in,
    input  wire       data_valid,
    output wire       data_ready,
    output wire       encoded_i,
    output wire       encoded_q,
    output reg        accepted_data
);

reg previous_i;
reg previous_q;

assign data_ready = rst_n && symbol_strobe;
assign encoded_i = previous_i ^ (data_valid ? data_in[0] : 1'b0);
assign encoded_q = previous_q ^ (data_valid ? data_in[1] : 1'b0);

always @(posedge clk) begin
    if (!rst_n) begin
        previous_i   <= 1'b0;
        previous_q   <= 1'b0;
        accepted_data <= 1'b0;
    end else begin
        accepted_data <= 1'b0;
        if (symbol_strobe) begin
            previous_i <= encoded_i;
            previous_q <= encoded_q;
            accepted_data <= data_valid;
        end
    end
end

endmodule
