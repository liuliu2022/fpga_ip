`timescale 1ns / 1ps

// Deterministic standalone source. Replace this block with an AXI/FIFO source
// when host payload transport is added; the TX chain interface is unchanged.
module tx_prbs_qpsk_source (
    input  wire       clk,
    input  wire       rst_n,
    output wire [1:0] data_out,
    output wire       data_valid,
    input  wire       data_ready
);

reg [15:0] lfsr;
wire feedback = lfsr[0];

assign data_out = {lfsr[1], lfsr[0]};
assign data_valid = rst_n;

always @(posedge clk) begin
    if (!rst_n)
        lfsr <= 16'h1ace;
    else if (data_ready)
        lfsr <= (lfsr >> 1) ^ (feedback ? 16'hb400 : 16'h0000);
end

endmodule
