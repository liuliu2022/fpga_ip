`timescale 1ns/1ps

module tb_gowinsdr_rx_chain;
localparam VECTOR_DIR = "../vectors";

reg clk=0, rst_n=0, sample_valid=0;
reg signed [15:0] sample_i0=0,sample_q0=0,sample_i1=0,sample_q1=0;
reg signed [15:0] sample_i2=0,sample_q2=0,sample_i3=0,sample_q3=0;
wire decim_valid,costas_valid,symbol_valid,decoded_valid;
wire signed [15:0] decim_i,decim_q,costas_i,costas_q,symbol_i,symbol_q;
wire [1:0] decoded_data;
wire signed [31:0] costas_frequency_word,timing_step;
wire [31:0] costas_phase_word;
wire signed [34:0] timing_error;

integer fstim,fdec,frrc,fcostas,fsymbol,fdecoded;
integer rc,failures=0,input_count=0,dec_count=0,rrc_count=0;
integer costas_count=0,symbol_count=0,decoded_count=0;
integer a0,b0,a1,b1,a2,b2,a3,b3;
integer ref_decim_i,ref_decim_q,ref_rrc_i,ref_rrc_q;
integer ref_costas_i,ref_costas_q,ref_costas_frequency;
integer ref_symbol_i,ref_symbol_q,ref_timing_step,ref_decoded_data;
reg [31:0] ref_costas_phase;
reg signed [63:0] ref_timing_error;

always #8.138020833 clk=~clk; // 61.44 MHz

gowinsdr_rx_chain dut(
 .clk(clk),.rst_n(rst_n),.sample_valid(sample_valid),
 .sample_i0(sample_i0),.sample_q0(sample_q0),.sample_i1(sample_i1),.sample_q1(sample_q1),
 .sample_i2(sample_i2),.sample_q2(sample_q2),.sample_i3(sample_i3),.sample_q3(sample_q3),
 .decim_valid(decim_valid),.decim_i(decim_i),.decim_q(decim_q),
 .costas_valid(costas_valid),.costas_i(costas_i),.costas_q(costas_q),
 .symbol_valid(symbol_valid),.symbol_i(symbol_i),.symbol_q(symbol_q),
 .decoded_data(decoded_data),.decoded_valid(decoded_valid),
 .costas_frequency_word(costas_frequency_word),.costas_phase_word(costas_phase_word),
 .timing_step(timing_step),.timing_error(timing_error)
);

initial begin
 fstim=$fopen({VECTOR_DIR,"/rfdc_input_iq.txt"},"r");
 fdec=$fopen({VECTOR_DIR,"/expected_decim4.txt"},"r");
 frrc=$fopen({VECTOR_DIR,"/expected_rrc.txt"},"r");
 fcostas=$fopen({VECTOR_DIR,"/expected_costas.txt"},"r");
 fsymbol=$fopen({VECTOR_DIR,"/expected_symbols.txt"},"r");
 fdecoded=$fopen({VECTOR_DIR,"/expected_decoded.txt"},"r");
 if(!fstim || !fdec || !frrc || !fcostas || !fsymbol || !fdecoded)
  $fatal(1,"Generate vectors with MATLAB before running RTL simulation");
 repeat(8) @(negedge clk); rst_n=1;
 while(!$feof(fstim)) begin
  rc=$fscanf(fstim,"%d %d %d %d %d %d %d %d\n",a0,b0,a1,b1,a2,b2,a3,b3);
  if(rc==8) begin
   sample_i0=a0;sample_q0=b0;sample_i1=a1;sample_q1=b1;
   sample_i2=a2;sample_q2=b2;sample_i3=a3;sample_q3=b3;
   sample_valid=1; input_count=input_count+1; @(negedge clk);
  end
 end
 sample_valid=0;
 sample_i0=0;sample_q0=0;sample_i1=0;sample_q1=0;
 sample_i2=0;sample_q2=0;sample_i3=0;sample_q3=0;
 repeat(256) @(negedge clk);
 $display("COUNTS input=%0d decim=%0d rrc=%0d costas=%0d symbols=%0d decoded=%0d",
  input_count,dec_count,rrc_count,costas_count,symbol_count,decoded_count);
 if(failures==0) $display("PASS: MATLAB fixed-point model and RTL agree at every checked stage");
 else $fatal(1,"FAIL: %0d stage mismatches",failures);
 $finish;
end

always @(posedge clk) begin
 #1;
 if(decim_valid) begin
  rc=$fscanf(fdec,"%d %d\n",ref_decim_i,ref_decim_q); dec_count=dec_count+1;
  if(rc!=2 || decim_i!==ref_decim_i || decim_q!==ref_decim_q) begin
   failures=failures+1;
   if(failures<20) $display("DECIM[%0d] rtl=(%0d,%0d) ref=(%0d,%0d)",dec_count,decim_i,decim_q,ref_decim_i,ref_decim_q);
  end
 end
 if(dut.rrc_valid) begin
  rc=$fscanf(frrc,"%d %d\n",ref_rrc_i,ref_rrc_q); rrc_count=rrc_count+1;
  if(rc!=2 || dut.rrc_i!==ref_rrc_i || dut.rrc_q!==ref_rrc_q) begin
   failures=failures+1;
   if(failures<20) $display("RRC[%0d] rtl=(%0d,%0d) ref=(%0d,%0d)",rrc_count,dut.rrc_i,dut.rrc_q,ref_rrc_i,ref_rrc_q);
  end
 end
 if(costas_valid) begin
  rc=$fscanf(fcostas,"%d %d %d %h\n",ref_costas_i,ref_costas_q,ref_costas_frequency,ref_costas_phase);
  costas_count=costas_count+1;
  if(rc!=4 || costas_i!==ref_costas_i || costas_q!==ref_costas_q ||
     costas_frequency_word!==ref_costas_frequency || costas_phase_word!==ref_costas_phase) begin
   failures=failures+1;
   if(failures<20) $display("COSTAS[%0d] rtl=(%0d,%0d,%0d,%h) ref=(%0d,%0d,%0d,%h)",
    costas_count,costas_i,costas_q,costas_frequency_word,costas_phase_word,
    ref_costas_i,ref_costas_q,ref_costas_frequency,ref_costas_phase);
  end
 end
 if(symbol_valid) begin
  rc=$fscanf(fsymbol,"%d %d %d %d\n",ref_symbol_i,ref_symbol_q,ref_timing_step,ref_timing_error);
  symbol_count=symbol_count+1;
  if(rc!=4 || symbol_i!==ref_symbol_i || symbol_q!==ref_symbol_q ||
     timing_step!==ref_timing_step || timing_error!==ref_timing_error[34:0]) begin
   failures=failures+1;
   if(failures<20) $display("SYMBOL[%0d] rtl=(%0d,%0d,%0d,%0d) ref=(%0d,%0d,%0d,%0d)",
    symbol_count,symbol_i,symbol_q,timing_step,timing_error,
    ref_symbol_i,ref_symbol_q,ref_timing_step,ref_timing_error);
  end
 end
 if(decoded_valid) begin
  rc=$fscanf(fdecoded,"%d\n",ref_decoded_data); decoded_count=decoded_count+1;
  if(rc!=1 || decoded_data!==ref_decoded_data[1:0]) begin
   failures=failures+1;
   if(failures<20) $display("DECODED[%0d] rtl=%0d ref=%0d",decoded_count,decoded_data,ref_decoded_data);
  end
 end
end
endmodule
