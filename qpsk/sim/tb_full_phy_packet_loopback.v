`timescale 1ns / 1ps

module tb_full_phy_packet_loopback;
reg clk = 0;
reg rst_n = 0;
always #8.138 clk = ~clk;

reg [31:0] dma_tx_data;
reg [3:0] dma_tx_keep;
reg dma_tx_last;
reg dma_tx_valid;
wire dma_tx_ready;
wire [1:0] tx_dibit;
wire tx_dibit_valid;
wire tx_dibit_ready;
wire [127:0] tx_iq;
wire tx_iq_valid;
wire [1:0] rx_dibit;
wire rx_dibit_valid;
wire [31:0] dma_rx_data;
wire [3:0] dma_rx_keep;
wire dma_rx_last;
wire dma_rx_valid;
reg dma_rx_ready = 1;
wire tx_frame_accepted, tx_frame_sent;
wire sync_found, header_error, crc_error, frame_good;
wire [15:0] tx_frame_length, rx_frame_length;

wire decim_valid, costas_valid, symbol_valid;
wire signed [15:0] decim_i, decim_q, costas_i, costas_q, symbol_i, symbol_q;
wire signed [31:0] frequency_word, timing_step;
wire [31:0] phase_word;
wire signed [34:0] timing_error;

reg [7:0] expected [0:63];
integer received_count = 0;
integer errors = 0;
integer cycles = 0;
integer i;

axis_tx_framer #(.MAX_PAYLOAD(256), .PREAMBLE_BYTES(32)) u_framer (
    .clk(clk), .rst_n(rst_n), .s_axis_tdata(dma_tx_data),
    .s_axis_tkeep(dma_tx_keep), .s_axis_tlast(dma_tx_last),
    .s_axis_tvalid(dma_tx_valid), .s_axis_tready(dma_tx_ready),
    .m_dibit(tx_dibit), .m_dibit_valid(tx_dibit_valid),
    .m_dibit_ready(tx_dibit_ready), .frame_accepted(tx_frame_accepted),
    .frame_sent(tx_frame_sent), .frame_length(tx_frame_length)
);

gowinsdr_tx_chain u_tx (
    .clk(clk), .rst_n(rst_n), .data_in(tx_dibit),
    .data_valid(tx_dibit_valid), .data_ready(tx_dibit_ready),
    .data_accepted(), .m_axis_tdata(tx_iq),
    .m_axis_tvalid(tx_iq_valid), .m_axis_tready(1'b1)
);

gowinsdr_rx_chain u_rx (
    .clk(clk), .rst_n(rst_n), .sample_valid(tx_iq_valid),
    .sample_i0(tx_iq[15:0]), .sample_q0(tx_iq[31:16]),
    .sample_i1(tx_iq[47:32]), .sample_q1(tx_iq[63:48]),
    .sample_i2(tx_iq[79:64]), .sample_q2(tx_iq[95:80]),
    .sample_i3(tx_iq[111:96]), .sample_q3(tx_iq[127:112]),
    .decim_valid(decim_valid), .decim_i(decim_i), .decim_q(decim_q),
    .costas_valid(costas_valid), .costas_i(costas_i), .costas_q(costas_q),
    .symbol_valid(symbol_valid), .symbol_i(symbol_i), .symbol_q(symbol_q),
    .decoded_data(rx_dibit), .decoded_valid(rx_dibit_valid),
    .costas_frequency_word(frequency_word), .costas_phase_word(phase_word),
    .timing_step(timing_step), .timing_error(timing_error)
);

axis_rx_deframer #(.MAX_PAYLOAD(256), .WATCHDOG_CYCLES(100000)) u_deframer (
    .clk(clk), .rst_n(rst_n), .s_dibit(rx_dibit),
    .s_dibit_valid(rx_dibit_valid), .m_axis_tdata(dma_rx_data),
    .m_axis_tkeep(dma_rx_keep), .m_axis_tlast(dma_rx_last),
    .m_axis_tvalid(dma_rx_valid), .m_axis_tready(dma_rx_ready),
    .sync_found(sync_found), .header_error(header_error),
    .crc_error(crc_error), .frame_good(frame_good),
    .frame_length(rx_frame_length)
);

task send_word;
    input [31:0] data;
    input [3:0] keep;
    input last;
    begin
        @(negedge clk);
        dma_tx_data = data; dma_tx_keep = keep;
        dma_tx_last = last; dma_tx_valid = 1;
        while (!dma_tx_ready) @(negedge clk);
        @(negedge clk);
        dma_tx_valid = 0; dma_tx_last = 0;
        dma_tx_keep = 0; dma_tx_data = 0;
    end
endtask

initial begin
    for (i = 0; i < 64; i = i + 1)
        expected[i] = (i * 8'h39) + 8'h17;
    dma_tx_data = 0; dma_tx_keep = 0;
    dma_tx_last = 0; dma_tx_valid = 0;
    repeat (16) @(posedge clk);
    rst_n = 1;
    repeat (64) @(posedge clk);
    for (i = 0; i < 64; i = i + 4)
        send_word({expected[i+3], expected[i+2], expected[i+1], expected[i]},
                  4'hF, i == 60);

    while ((received_count < 64) && (cycles < 40000)) begin
        @(posedge clk);
        cycles = cycles + 1;
    end
    repeat (20) @(posedge clk);
    if ((received_count == 64) && (errors == 0) &&
        (rx_frame_length == 64) && !header_error && !crc_error)
        $display("PASS: DMA payload -> frame -> QPSK TX/RX -> deframe -> DMA payload");
    else
        $display("FAIL: bytes=%0d errors=%0d length=%0d timeout_cycles=%0d",
                 received_count, errors, rx_frame_length, cycles);
    $finish;
end

always @(posedge clk) begin
    if (rst_n && dma_rx_valid && dma_rx_ready) begin
        for (i = 0; i < 4; i = i + 1) begin
            if (dma_rx_keep[i]) begin
                if (dma_rx_data[(8*i)+:8] !== expected[received_count])
                    errors = errors + 1;
                received_count = received_count + 1;
            end
        end
    end
end

endmodule
