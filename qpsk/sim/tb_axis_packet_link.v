`timescale 1ns / 1ps

module tb_axis_packet_link;
reg clk = 0;
reg rst_n = 0;
always #5 clk = ~clk;

reg [31:0] tx_data;
reg [3:0] tx_keep;
reg tx_last;
reg tx_valid;
wire tx_ready;
wire [1:0] dibit;
wire dibit_valid;
reg dibit_ready = 1;
wire [31:0] rx_data;
wire [3:0] rx_keep;
wire rx_last;
wire rx_valid;
reg rx_ready = 1;
wire tx_accepted, tx_sent;
wire sync_found, header_error, crc_error, frame_good;
wire iq_swapped;
wire [15:0] tx_length, rx_length;
wire [1:0] swapped_dibit = {dibit[0], dibit[1]};
wire [31:0] swap_rx_data;
wire [3:0] swap_rx_keep;
wire swap_rx_last;
wire swap_rx_valid;
wire swap_sync_found, swap_header_error, swap_crc_error, swap_frame_good;
wire swap_iq_swapped;
wire [15:0] swap_rx_length;
reg [7:0] expected [0:36];
integer received_count = 0;
integer errors = 0;
integer swap_received_count = 0;
integer swap_errors = 0;
integer i;

axis_tx_framer #(.MAX_PAYLOAD(256), .PREAMBLE_BYTES(32)) u_tx (
    .clk(clk), .rst_n(rst_n),
    .s_axis_tdata(tx_data), .s_axis_tkeep(tx_keep),
    .s_axis_tlast(tx_last), .s_axis_tvalid(tx_valid),
    .s_axis_tready(tx_ready), .m_dibit(dibit),
    .m_dibit_valid(dibit_valid), .m_dibit_ready(dibit_ready),
    .frame_accepted(tx_accepted), .frame_sent(tx_sent),
    .frame_length(tx_length)
);

axis_rx_deframer #(.MAX_PAYLOAD(256), .WATCHDOG_CYCLES(10000)) u_rx (
    .clk(clk), .rst_n(rst_n), .s_dibit(dibit),
    .s_dibit_valid(dibit_valid && dibit_ready),
    .m_axis_tdata(rx_data), .m_axis_tkeep(rx_keep),
    .m_axis_tlast(rx_last), .m_axis_tvalid(rx_valid),
    .m_axis_tready(rx_ready), .sync_found(sync_found),
    .header_error(header_error), .crc_error(crc_error),
    .frame_good(frame_good), .frame_length(rx_length),
    .iq_swapped(iq_swapped)
);

// Model the residual 90/270-degree Costas ambiguity seen on the board: after
// the PHY's per-axis differential decoder, the two bits of every dibit swap.
axis_rx_deframer #(.MAX_PAYLOAD(256), .WATCHDOG_CYCLES(10000)) u_rx_swapped (
    .clk(clk), .rst_n(rst_n), .s_dibit(swapped_dibit),
    .s_dibit_valid(dibit_valid && dibit_ready),
    .m_axis_tdata(swap_rx_data), .m_axis_tkeep(swap_rx_keep),
    .m_axis_tlast(swap_rx_last), .m_axis_tvalid(swap_rx_valid),
    .m_axis_tready(rx_ready), .sync_found(swap_sync_found),
    .header_error(swap_header_error), .crc_error(swap_crc_error),
    .frame_good(swap_frame_good), .frame_length(swap_rx_length),
    .iq_swapped(swap_iq_swapped)
);

task send_word;
    input [31:0] data;
    input [3:0] keep;
    input last;
    begin
        @(negedge clk);
        tx_data = data; tx_keep = keep; tx_last = last; tx_valid = 1;
        while (!tx_ready) @(negedge clk);
        @(negedge clk);
        tx_valid = 0; tx_last = 0; tx_keep = 0; tx_data = 0;
    end
endtask

initial begin
    for (i = 0; i < 37; i = i + 1)
        expected[i] = (i * 8'h25) ^ 8'hA7;
    tx_data = 0; tx_keep = 0; tx_last = 0; tx_valid = 0;
    repeat (8) @(posedge clk);
    rst_n = 1;
    for (i = 0; i < 36; i = i + 4)
        send_word({expected[i+3], expected[i+2], expected[i+1], expected[i]},
                  4'hF, 1'b0);
    send_word({24'd0, expected[36]}, 4'h1, 1'b1);
    wait (tx_sent);
    repeat (100) @(posedge clk);
    if ((received_count == 37) && (errors == 0) &&
        (rx_length == 37) && !iq_swapped &&
        (swap_received_count == 37) && (swap_errors == 0) &&
        (swap_rx_length == 37) && swap_iq_swapped &&
        !header_error && !crc_error &&
        !swap_header_error && !swap_crc_error)
        $display("PASS: normal and I/Q-swapped packet sync, descrambling and CRC loopback");
    else
        $display("FAIL: normal bytes=%0d errors=%0d len=%0d swap=%0d; swapped bytes=%0d errors=%0d len=%0d swap=%0d",
                 received_count, errors, rx_length, iq_swapped,
                 swap_received_count, swap_errors, swap_rx_length,
                 swap_iq_swapped);
    $finish;
end

always @(posedge clk) begin
    if (rst_n && rx_valid && rx_ready) begin
        for (i = 0; i < 4; i = i + 1) begin
            if (rx_keep[i]) begin
                if (rx_data[(8*i)+:8] !== expected[received_count])
                    errors = errors + 1;
                received_count = received_count + 1;
            end
        end
    end
    if (rst_n && swap_rx_valid && rx_ready) begin
        for (i = 0; i < 4; i = i + 1) begin
            if (swap_rx_keep[i]) begin
                if (swap_rx_data[(8*i)+:8] !== expected[swap_received_count])
                    swap_errors = swap_errors + 1;
                swap_received_count = swap_received_count + 1;
            end
        end
    end
end

endmodule
