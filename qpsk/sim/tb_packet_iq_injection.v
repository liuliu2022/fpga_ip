`timescale 1ns/1ps

// Complete receiver regression with MATLAB-generated four-sample-per-clock
// I/Q. RFDC DDC, AXI DMA and the RTL transmitter are intentionally bypassed.
module tb_packet_iq_injection #(
    parameter VECTOR_FILE = "../../qpsk/testdata/packet_iq_scenarios/baseline/iq_s16x4.txt",
    parameter CASE_NAME = "baseline"
);
reg clk=0,rst_n=0,sample_valid=0;
always #8.138020833 clk=~clk;
reg signed [15:0] sample_i0=0,sample_q0=0,sample_i1=0,sample_q1=0;
reg signed [15:0] sample_i2=0,sample_q2=0,sample_i3=0,sample_q3=0;

wire decim_valid,costas_valid,symbol_valid,decoded_valid;
wire signed [15:0] decim_i,decim_q,costas_i,costas_q,symbol_i,symbol_q;
wire [1:0] decoded_data;
wire signed [31:0] costas_frequency_word,timing_step;
wire [31:0] costas_phase_word;
wire costas_locked,costas_recovery;
wire signed [34:0] timing_error;
wire [31:0] rx_data;
wire [3:0] rx_keep;
wire rx_last,rx_valid;
wire sync_found,header_error,crc_error,frame_good,iq_swapped;
wire [15:0] frame_length;

reg [7:0] expected[0:63];
integer fd,ef,rc;
integer a0,b0,a1,b1,a2,b2,a3,b3;
integer received=0,errors=0,wait_cycles=0,input_clocks=0;
integer sync_count=0,header_errors=0,crc_errors=0,good_count=0;
integer costas_l1_sum=0,costas_l1_count=0;
integer i;

gowinsdr_rx_chain u_rx(
    .clk(clk),.rst_n(rst_n),.frame_sync(sync_found),.sample_valid(sample_valid),
    .sample_i0(sample_i0),.sample_q0(sample_q0),.sample_i1(sample_i1),.sample_q1(sample_q1),
    .sample_i2(sample_i2),.sample_q2(sample_q2),.sample_i3(sample_i3),.sample_q3(sample_q3),
    .decim_valid(decim_valid),.decim_i(decim_i),.decim_q(decim_q),
    .costas_valid(costas_valid),.costas_i(costas_i),.costas_q(costas_q),
    .symbol_valid(symbol_valid),.symbol_i(symbol_i),.symbol_q(symbol_q),
    .decoded_data(decoded_data),.decoded_valid(decoded_valid),
    .costas_frequency_word(costas_frequency_word),.costas_phase_word(costas_phase_word),
    .costas_locked(costas_locked),.costas_recovery(costas_recovery),
    .timing_step(timing_step),.timing_error(timing_error)
);

axis_rx_deframer #(.MAX_PAYLOAD(256),.WATCHDOG_CYCLES(100000)) u_deframer(
    .clk(clk),.rst_n(rst_n),.s_dibit(decoded_data),.s_dibit_valid(decoded_valid),
    .m_axis_tdata(rx_data),.m_axis_tkeep(rx_keep),.m_axis_tlast(rx_last),
    .m_axis_tvalid(rx_valid),.m_axis_tready(1'b1),.sync_found(sync_found),
    .header_error(header_error),.crc_error(crc_error),.frame_good(frame_good),
    .frame_length(frame_length),.iq_swapped(iq_swapped)
);

initial begin
    ef=$fopen("../../qpsk/testdata/packet_iq_scenarios/expected_payload.txt","r");
    if(!ef)$fatal(1,"cannot open expected payload");
    for(i=0;i<64;i=i+1) begin
        rc=$fscanf(ef,"%d\n",a0);if(rc!=1)$fatal(1,"bad expected payload");
        expected[i]=a0[7:0];
    end
    $fclose(ef);
    fd=$fopen(VECTOR_FILE,"r");
    if(!fd)$fatal(1,"cannot open I/Q vector %0s",VECTOR_FILE);
    repeat(12)@(negedge clk);rst_n=1;
    while(!$feof(fd)) begin
        rc=$fscanf(fd,"%d %d %d %d %d %d %d %d\n",a0,b0,a1,b1,a2,b2,a3,b3);
        if(rc==8) begin
            sample_i0=a0;sample_q0=b0;sample_i1=a1;sample_q1=b1;
            sample_i2=a2;sample_q2=b2;sample_i3=a3;sample_q3=b3;
            sample_valid=1;input_clocks=input_clocks+1;@(negedge clk);
        end
    end
    $fclose(fd);sample_valid=0;
    sample_i0=0;sample_q0=0;sample_i1=0;sample_q1=0;
    sample_i2=0;sample_q2=0;sample_i3=0;sample_q3=0;
    while(received<64 && wait_cycles<20000) begin
        @(posedge clk);wait_cycles=wait_cycles+1;
    end
    repeat(20)@(posedge clk);
    if(received==64 && errors==0 && frame_length==64 && good_count==1 &&
       header_errors==0 && crc_errors==0)
        $display("PASS IQ_INJECTION case=%0s clocks=%0d sync=%0d good=%0d swap=%0d freq=%0d timing_step=%0d mean_costas_l1=%0d",
            CASE_NAME,input_clocks,sync_count,good_count,iq_swapped,
            costas_frequency_word,timing_step,
            costas_l1_count ? costas_l1_sum/costas_l1_count : 0);
    else
        $fatal(1,"FAIL IQ_INJECTION case=%0s bytes=%0d errors=%0d len=%0d sync=%0d header=%0d crc=%0d good=%0d lock=%0d",
            CASE_NAME,received,errors,frame_length,sync_count,header_errors,
            crc_errors,good_count,costas_locked);
    $finish;
end

always @(posedge clk) begin
    if(rst_n) begin
        if(sync_found)sync_count=sync_count+1;
        if(header_error)header_errors=header_errors+1;
        if(crc_error)crc_errors=crc_errors+1;
        if(frame_good)good_count=good_count+1;
        if(costas_valid) begin
            costas_l1_sum=costas_l1_sum+(costas_i[15] ? -costas_i : costas_i)+
                (costas_q[15] ? -costas_q : costas_q);
            costas_l1_count=costas_l1_count+1;
        end
        if(rx_valid) begin
            for(i=0;i<4;i=i+1) if(rx_keep[i]) begin
                if(received>=64 || rx_data[(8*i)+:8]!==expected[received])errors=errors+1;
                received=received+1;
            end
        end
    end
end
endmodule

module tb_packet_iq_baseline;
tb_packet_iq_injection #(
    .VECTOR_FILE("../../qpsk/testdata/packet_iq_scenarios/baseline/iq_s16x4.txt"),
    .CASE_NAME("baseline")) u();
endmodule

module tb_packet_iq_phase90;
tb_packet_iq_injection #(
    .VECTOR_FILE("../../qpsk/testdata/packet_iq_scenarios/phase90/iq_s16x4.txt"),
    .CASE_NAME("phase90")) u();
endmodule

module tb_packet_iq_combined;
tb_packet_iq_injection #(
    .VECTOR_FILE("../../qpsk/testdata/packet_iq_scenarios/combined/iq_s16x4.txt"),
    .CASE_NAME("combined")) u();
endmodule

module tb_packet_iq_low_amp_20;
tb_packet_iq_injection #(
    .VECTOR_FILE("../../qpsk/testdata/packet_iq_scenarios/low_amp_20/iq_s16x4.txt"),
    .CASE_NAME("low_amp_20")) u();
endmodule
