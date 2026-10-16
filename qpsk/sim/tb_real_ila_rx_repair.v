`timescale 1ns / 1ps

// Regression for the repaired post-DDC receiver using captures taken from
// the RFSoC ILA.  The 1008-sample coherent part of each capture is repeated
// so carrier and timing acquisition, rather than file length, determines the
// result.  The final 256 differential dibits must be an error-free 0,1,2,3
// cycle (allowing cycle offset and the normal I/Q-bit interchange ambiguity).
module tb_real_ila_rx_repair;

localparam integer CAPTURE_SAMPLES = 1008;
localparam integer REPETITIONS = 32;
localparam integer TAIL_WORDS = 256;

reg clk = 1'b0;
reg rst_n = 1'b0;
reg in_valid = 1'b0;
reg signed [15:0] in_i = 16'sd0;
reg signed [15:0] in_q = 16'sd0;
always #5 clk = ~clk;

wire rrc_valid;
wire signed [15:0] rrc_i, rrc_q;
wire costas_valid;
wire signed [15:0] costas_i, costas_q;
wire signed [31:0] frequency_word;
wire [31:0] phase_word;
wire costas_locked;
wire recovery_pulse;
wire signal_present;
wire symbol_valid;
wire signed [15:0] symbol_i, symbol_q;
wire signed [31:0] timing_step;
wire signed [34:0] timing_error;
wire [1:0] decoded_data;
wire decoded_valid;

reg [1:0] tail_words [0:TAIL_WORDS-1];
integer tail_write = 0;
integer decoded_count = 0;
integer recovery_count = 0;
integer lock_rise_count = 0;
reg locked_d = 1'b0;

rx_matched_rrc u_rrc (
    .clk(clk), .rst_n(rst_n), .in_valid(in_valid),
    .in_i(in_i), .in_q(in_q),
    .out_valid(rrc_valid), .out_i(rrc_i), .out_q(rrc_q)
);

rx_costas_loop u_costas (
    .clk(clk), .rst_n(rst_n), .force_recovery(1'b0),
    .in_valid(rrc_valid),
    .in_i(rrc_i), .in_q(rrc_q),
    .out_valid(costas_valid), .out_i(costas_i), .out_q(costas_q),
    .frequency_word(frequency_word), .phase_word(phase_word),
    .locked(costas_locked), .recovery_pulse(recovery_pulse),
    .signal_present(signal_present)
);

rx_gardner_timing u_gardner (
    .clk(clk), .rst_n(rst_n), .enable(costas_locked),
    .frame_sync(1'b0),
    .in_valid(costas_valid), .in_i(costas_i), .in_q(costas_q),
    .symbol_valid(symbol_valid), .symbol_i(symbol_i), .symbol_q(symbol_q),
    .timing_step(timing_step), .timing_error(timing_error)
);

rx_qpsk_diff_decode u_decode (
    .clk(clk), .rst_n(rst_n), .symbol_valid(symbol_valid),
    .symbol_i(symbol_i), .symbol_q(symbol_q),
    .data_out(decoded_data), .data_valid(decoded_valid)
);

always @(posedge clk) begin
    if (!rst_n) begin
        tail_write <= 0;
        decoded_count <= 0;
        recovery_count <= 0;
        lock_rise_count <= 0;
        locked_d <= 1'b0;
    end else begin
        locked_d <= costas_locked;
        if (costas_locked && !locked_d)
            lock_rise_count <= lock_rise_count + 1;
        if (recovery_pulse)
            recovery_count <= recovery_count + 1;
        if (decoded_valid) begin
            tail_words[tail_write] <= decoded_data;
            tail_write <= (tail_write == TAIL_WORDS-1) ? 0 : tail_write+1;
            decoded_count <= decoded_count+1;
        end
    end
end

task reset_receiver;
begin
    in_valid = 1'b0;
    rst_n = 1'b0;
    repeat (12) @(posedge clk);
    rst_n = 1'b1;
    repeat (4) @(posedge clk);
end
endtask

task run_capture;
    input [8*512-1:0] path;
    reg signed [15:0] capture_i [0:CAPTURE_SAMPLES-1];
    reg signed [15:0] capture_q [0:CAPTURE_SAMPLES-1];
    integer fd;
    integer status;
    integer sample_index;
    integer repetition;
    integer value_i;
    integer value_q;
begin
    fd = $fopen(path,"r");
    if (fd == 0) begin
        $display("FAIL: cannot open %0s",path);
        $fatal(1);
    end
    for (sample_index=0; sample_index<CAPTURE_SAMPLES; sample_index=sample_index+1) begin
        status = $fscanf(fd,"%d %d\n",value_i,value_q);
        if (status != 2) begin
            $display("FAIL: malformed capture %0s at sample %0d",path,sample_index);
            $fatal(1);
        end
        capture_i[sample_index] = value_i;
        capture_q[sample_index] = value_q;
    end
    $fclose(fd);

    for (repetition=0; repetition<REPETITIONS; repetition=repetition+1) begin
        for (sample_index=0; sample_index<CAPTURE_SAMPLES; sample_index=sample_index+1) begin
            @(negedge clk);
            in_valid = 1'b1;
            in_i = capture_i[sample_index];
            in_q = capture_q[sample_index];
        end
    end
    @(negedge clk);
    in_valid = 1'b0;
    in_i = 16'sd0;
    in_q = 16'sd0;
    repeat (32) @(posedge clk);
end
endtask

task check_tail;
    input [8*64-1:0] capture_name;
    integer offset;
    integer index;
    integer ring_index;
    integer expected;
    integer direct_errors;
    integer swapped_errors;
    integer best_errors;
    reg [1:0] observed;
    reg [1:0] swapped;
begin
    if (decoded_count < TAIL_WORDS) begin
        $display("FAIL %0s: only %0d decoded words",capture_name,decoded_count);
        $fatal(1);
    end
    best_errors = TAIL_WORDS+1;
    for (offset=0; offset<4; offset=offset+1) begin
        direct_errors = 0;
        swapped_errors = 0;
        for (index=0; index<TAIL_WORDS; index=index+1) begin
            ring_index = tail_write+index;
            if (ring_index >= TAIL_WORDS)
                ring_index = ring_index-TAIL_WORDS;
            observed = tail_words[ring_index];
            swapped = {observed[0],observed[1]};
            expected = (index+offset) & 3;
            if (observed != expected[1:0]) direct_errors = direct_errors+1;
            if (swapped != expected[1:0]) swapped_errors = swapped_errors+1;
        end
        if (direct_errors < best_errors) best_errors = direct_errors;
        if (swapped_errors < best_errors) best_errors = swapped_errors;
    end
    $display("RESULT %0s decoded=%0d tail_errors=%0d locked=%0d lock_rises=%0d recoveries=%0d frequency_word=%0d timing_step=%0d",
        capture_name,decoded_count,best_errors,costas_locked,lock_rise_count,
        recovery_count,frequency_word,timing_step);
    if (best_errors != 0 || !costas_locked) begin
        $display("FAIL %0s",capture_name);
        $fatal(1);
    end
end
endtask

initial begin
    reset_receiver();
    run_capture("qpsk/testdata/ila_board_captures/stimulus/rx_decim_iq_s16.txt");
    check_tail("rx.csv");

    reset_receiver();
    run_capture("qpsk/testdata/ila_board_captures/stimulus/iladata_decim_iq_s16.txt");
    check_tail("iladata.csv");

    $display("PASS: repaired RTL decodes both real RFSoC ILA captures");
    $finish;
end

endmodule
