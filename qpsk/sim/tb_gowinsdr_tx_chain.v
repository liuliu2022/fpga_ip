`timescale 1ns / 1ps

module tb_gowinsdr_tx_chain;
localparam SYMBOLS = 256;
localparam PACKETS = SYMBOLS*12;

reg clk=0;
reg rst_n=0;
reg [1:0] source_data;
reg source_valid;
wire source_ready;
wire data_accepted;
wire [127:0] axis_data;
wire axis_valid;
reg axis_ready=1;

integer input_fd;
integer expected_fd;
integer input_values [0:SYMBOLS-1];
integer expected [0:PACKETS*8-1];
integer input_count;
integer packet_count;
integer errors;
integer r;
integer c;
integer scan_value;
integer actual;

always #8.138 clk=~clk;

gowinsdr_tx_chain u_dut (
    .clk(clk), .rst_n(rst_n),
    .data_in(source_data), .data_valid(source_valid),
    .data_ready(source_ready), .data_accepted(data_accepted),
    .m_axis_tdata(axis_data), .m_axis_tvalid(axis_valid),
    .m_axis_tready(axis_ready)
);

initial begin
    input_fd=$fopen("../vectors/tx_input_data.txt","r");
    expected_fd=$fopen("../vectors/tx_expected_iq.txt","r");
    if (input_fd==0 || expected_fd==0) begin
        $display("FAIL: cannot open MATLAB TX vectors");
        $finish;
    end
    for (r=0;r<SYMBOLS;r=r+1)
        scan_value=$fscanf(input_fd,"%d\n",input_values[r]);
    for (r=0;r<PACKETS;r=r+1)
        for (c=0;c<8;c=c+1)
            scan_value=$fscanf(expected_fd,"%d",expected[r*8+c]);
    $fclose(input_fd);
    $fclose(expected_fd);

    input_count=0;
    packet_count=0;
    errors=0;
    source_data=input_values[0];
    source_valid=0;
    repeat(6) @(posedge clk);
    @(negedge clk);
    rst_n=1;
    source_valid=1;
end

always @(posedge clk) begin
    if (rst_n) begin
        if (axis_valid && axis_ready && packet_count<PACKETS) begin
            for (c=0;c<8;c=c+1) begin
                actual=$signed(axis_data[c*16 +: 16]);
                if (actual !== expected[packet_count*8+c]) begin
                    if (errors<12)
                        $display("TX MISMATCH packet=%0d lane_value=%0d rtl=%0d matlab=%0d",
                            packet_count,c,actual,expected[packet_count*8+c]);
                    errors=errors+1;
                end
            end
            packet_count=packet_count+1;
            if (packet_count==PACKETS) begin
                if (errors==0)
                    $display("PASS: MATLAB and RTL TX agree for %0d symbols (%0d complex samples)",
                        SYMBOLS,PACKETS*4);
                else
                    $display("FAIL: TX mismatches=%0d",errors);
                $finish;
            end
        end

        if (source_ready && source_valid) begin
            input_count=input_count+1;
            if (input_count<SYMBOLS)
                source_data=input_values[input_count];
            else
                source_valid=0;
        end
    end
end

initial begin
    #2000000;
    $display("FAIL: timeout packets=%0d errors=%0d",packet_count,errors);
    $finish;
end
endmodule
