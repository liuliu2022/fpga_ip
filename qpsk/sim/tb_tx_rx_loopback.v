`timescale 1ns / 1ps

module tb_tx_rx_loopback;
localparam SYMBOLS=512;

reg clk=0;
reg rst_n=0;
wire [1:0] source_data;
wire source_valid;
wire source_ready;
wire [127:0] tx_data;
wire tx_valid;

wire decoded_valid;
wire [1:0] decoded_data;
wire decim_valid;
wire signed [15:0] decim_i,decim_q;
wire costas_valid;
wire signed [15:0] costas_i,costas_q;
wire symbol_valid;
wire signed [15:0] symbol_i,symbol_q;
wire signed [31:0] frequency_word;
wire [31:0] phase_word;
wire signed [31:0] timing_step;
wire signed [34:0] timing_error;

reg [1:0] sent [0:1023];
reg [1:0] received [0:1023];
integer sent_count=0;
integer received_count=0;
integer cycle_count=0;
integer lag;
integer k;
integer compare_count;
integer direct_errors;
integer swap_errors;
integer best_errors;
integer best_lag;
reg [1:0] swapped;

always #8.138 clk=~clk;

tx_prbs_qpsk_source u_source (
    .clk(clk),.rst_n(rst_n),.data_out(source_data),
    .data_valid(source_valid),.data_ready(source_ready)
);

gowinsdr_tx_chain u_tx (
    .clk(clk),.rst_n(rst_n),.data_in(source_data),.data_valid(source_valid),
    .data_ready(source_ready),.data_accepted(),.m_axis_tdata(tx_data),
    .m_axis_tvalid(tx_valid),.m_axis_tready(1'b1)
);

gowinsdr_rx_chain u_rx (
    .clk(clk),.rst_n(rst_n),.sample_valid(tx_valid),
    .sample_i0(tx_data[15:0]),.sample_q0(tx_data[31:16]),
    .sample_i1(tx_data[47:32]),.sample_q1(tx_data[63:48]),
    .sample_i2(tx_data[79:64]),.sample_q2(tx_data[95:80]),
    .sample_i3(tx_data[111:96]),.sample_q3(tx_data[127:112]),
    .decim_valid(decim_valid),.decim_i(decim_i),.decim_q(decim_q),
    .costas_valid(costas_valid),.costas_i(costas_i),.costas_q(costas_q),
    .symbol_valid(symbol_valid),.symbol_i(symbol_i),.symbol_q(symbol_q),
    .decoded_data(decoded_data),.decoded_valid(decoded_valid),
    .costas_frequency_word(frequency_word),.costas_phase_word(phase_word),
    .timing_step(timing_step),.timing_error(timing_error)
);

initial begin
    repeat(8) @(posedge clk);
    @(negedge clk);
    rst_n=1;
    repeat(8500) @(posedge clk);

    best_errors=1000000;
    best_lag=-1;
    for (lag=0;lag<=80;lag=lag+1) begin
        direct_errors=0;
        swap_errors=0;
        compare_count=0;
        for (k=32;k<SYMBOLS-64;k=k+1) begin
            if ((k+lag)<received_count) begin
                if (received[k+lag] !== sent[k]) direct_errors=direct_errors+1;
                swapped={received[k+lag][0],received[k+lag][1]};
                if (swapped !== sent[k]) swap_errors=swap_errors+1;
                compare_count=compare_count+1;
            end
        end
        if (compare_count>300 && direct_errors<best_errors) begin
            best_errors=direct_errors;
            best_lag=lag;
        end
        if (compare_count>300 && swap_errors<best_errors) begin
            best_errors=swap_errors;
            best_lag=lag;
        end
    end

    $display("LOOPBACK sent=%0d decoded=%0d best_lag=%0d errors=%0d",
        sent_count,received_count,best_lag,best_errors);
    if (best_errors==0)
        $display("PASS: RTL TX -> RTL RX differential-QPSK loopback decoded without errors");
    else
        $display("FAIL: RTL loopback has %0d errors",best_errors);
    $finish;
end

always @(posedge clk) begin
    if (rst_n) begin
        cycle_count=cycle_count+1;
        if (source_ready && source_valid && sent_count<SYMBOLS) begin
            sent[sent_count]=source_data;
            sent_count=sent_count+1;
        end
        if (decoded_valid && received_count<1024) begin
            received[received_count]=decoded_data;
            received_count=received_count+1;
        end
    end
end
endmodule
