`timescale 1ns / 1ps

// Independent four-phase FIR decimator for the RFDC four-sample vector.
// 44 Q1.17 taps, 245.76 -> 61.44 MSPS. Products and the balanced adder tree
// are fully pipelined for a 61.44 MHz fabric clock.
module rx_polyphase_decim4 (
    input wire clk, input wire rst_n, input wire in_valid,
    input wire signed [15:0] in_i0,in_i1,in_i2,in_i3,
    input wire signed [15:0] in_q0,in_q1,in_q2,in_q3,
    output reg out_valid,
    output reg signed [15:0] out_i,out_q
);

localparam integer PHASE_TAPS=11;
localparam integer SHIFT=17;
reg signed [15:0] iz0[0:9],iz1[0:9],iz2[0:9],iz3[0:9];
reg signed [15:0] qz0[0:9],qz1[0:9],qz2[0:9],qz3[0:9];
reg signed [47:0] p_i[0:43],p_q[0:43];
reg signed [47:0] s1_i[0:21],s1_q[0:21];
reg signed [47:0] s2_i[0:10],s2_q[0:10];
reg signed [47:0] s3_i[0:5], s3_q[0:5];
reg signed [47:0] s4_i[0:2], s4_q[0:2];
reg signed [47:0] s5_i[0:1], s5_q[0:1];
reg [5:0] valid_pipe;
integer r,k;

function signed [17:0] c;
 input integer x; begin case(x)
 0:c=17;1:c=51;2:c=111;3:c=193;4:c=275;5:c=318;6:c=265;7:c=63;
 8:c=-322;9:c=-872;10:c=-1501;11:c=-2041;12:c=-2267;13:c=-1928;
 14:c=-813;15:c=1186;16:c=4022;17:c=7466;18:c=11128;19:c=14516;
 20:c=17125;21:c=18544;22:c=18544;23:c=17125;24:c=14516;25:c=11128;
 26:c=7466;27:c=4022;28:c=1186;29:c=-813;30:c=-1928;31:c=-2267;
 32:c=-2041;33:c=-1501;34:c=-872;35:c=-322;36:c=63;37:c=265;
 38:c=318;39:c=275;40:c=193;41:c=111;42:c=51;43:c=17;
 default:c=0; endcase end
endfunction

function signed [15:0] sat;
 input signed [47:0] v; reg signed [47:0] a,z; begin
  a=(v>=0)?v+(48'sd1<<<(SHIFT-1)):v+(48'sd1<<<(SHIFT-1))-1'b1;
  z=a>>>SHIFT;
  if(z>32767)sat=16'sh7fff; else if(z< -32768)sat=-16'sd32768; else sat=z[15:0];
 end endfunction

always @(posedge clk) begin
 if(!rst_n) begin
  valid_pipe<=0; out_valid<=0; out_i<=0; out_q<=0;
  for(k=0;k<10;k=k+1) begin iz0[k]<=0;iz1[k]<=0;iz2[k]<=0;iz3[k]<=0;qz0[k]<=0;qz1[k]<=0;qz2[k]<=0;qz3[k]<=0; end
  for(k=0;k<44;k=k+1) begin p_i[k]<=0;p_q[k]<=0; end
  for(k=0;k<22;k=k+1) begin s1_i[k]<=0;s1_q[k]<=0; end
  for(k=0;k<11;k=k+1) begin s2_i[k]<=0;s2_q[k]<=0; end
  for(k=0;k<6;k=k+1) begin s3_i[k]<=0;s3_q[k]<=0; end
  for(k=0;k<3;k=k+1) begin s4_i[k]<=0;s4_q[k]<=0; end
  for(k=0;k<2;k=k+1) begin s5_i[k]<=0;s5_q[k]<=0; end
 end else begin
  valid_pipe<={valid_pipe[4:0],in_valid};
  out_valid<=valid_pipe[5];
  if(valid_pipe[5]) begin out_i<=sat(s5_i[0]+s5_i[1]);out_q<=sat(s5_q[0]+s5_q[1]);end
  if(valid_pipe[4]) begin s5_i[0]<=s4_i[0]+s4_i[1];s5_q[0]<=s4_q[0]+s4_q[1];s5_i[1]<=s4_i[2];s5_q[1]<=s4_q[2];end
  if(valid_pipe[3]) begin for(k=0;k<3;k=k+1) begin s4_i[k]<=s3_i[2*k]+s3_i[2*k+1];s4_q[k]<=s3_q[2*k]+s3_q[2*k+1];end end
  if(valid_pipe[2]) begin
   for(k=0;k<5;k=k+1) begin s3_i[k]<=s2_i[2*k]+s2_i[2*k+1];s3_q[k]<=s2_q[2*k]+s2_q[2*k+1];end
   s3_i[5]<=s2_i[10];s3_q[5]<=s2_q[10];
  end
  if(valid_pipe[1]) begin
   for(k=0;k<10;k=k+1) begin s2_i[k]<=s1_i[2*k]+s1_i[2*k+1];s2_q[k]<=s1_q[2*k]+s1_q[2*k+1];end
   s2_i[10]<=s1_i[20]+s1_i[21];s2_q[10]<=s1_q[20]+s1_q[21];
  end
  if(valid_pipe[0]) begin for(k=0;k<22;k=k+1) begin s1_i[k]<=p_i[2*k]+p_i[2*k+1];s1_q[k]<=p_q[2*k]+p_q[2*k+1];end end
  if(in_valid) begin
   for(r=0;r<PHASE_TAPS;r=r+1) begin
    if(r==0) begin
     p_i[4*r]<=in_i3*c(4*r);p_i[4*r+1]<=in_i2*c(4*r+1);p_i[4*r+2]<=in_i1*c(4*r+2);p_i[4*r+3]<=in_i0*c(4*r+3);
     p_q[4*r]<=in_q3*c(4*r);p_q[4*r+1]<=in_q2*c(4*r+1);p_q[4*r+2]<=in_q1*c(4*r+2);p_q[4*r+3]<=in_q0*c(4*r+3);
    end else begin
     p_i[4*r]<=iz3[r-1]*c(4*r);p_i[4*r+1]<=iz2[r-1]*c(4*r+1);p_i[4*r+2]<=iz1[r-1]*c(4*r+2);p_i[4*r+3]<=iz0[r-1]*c(4*r+3);
     p_q[4*r]<=qz3[r-1]*c(4*r);p_q[4*r+1]<=qz2[r-1]*c(4*r+1);p_q[4*r+2]<=qz1[r-1]*c(4*r+2);p_q[4*r+3]<=qz0[r-1]*c(4*r+3);
    end
   end
   for(k=9;k>0;k=k-1) begin iz0[k]<=iz0[k-1];iz1[k]<=iz1[k-1];iz2[k]<=iz2[k-1];iz3[k]<=iz3[k-1];qz0[k]<=qz0[k-1];qz1[k]<=qz1[k-1];qz2[k]<=qz2[k-1];qz3[k]<=qz3[k-1];end
   iz0[0]<=in_i0;iz1[0]<=in_i1;iz2[0]<=in_i2;iz3[0]<=in_i3;qz0[0]<=in_q0;qz1[0]<=in_q1;qz2[0]<=in_q2;qz3[0]<=in_q3;
  end
 end
end
endmodule
