`timescale 1ns / 1ps

// Pipelined 121-tap QPSK receive RRC matched filter.
// Fs=61.44 MSPS, Rs=5.12 Msym/s, beta=0.35, span=10 symbols.
module rx_matched_rrc(
 input wire clk,input wire rst_n,input wire in_valid,
 input wire signed [15:0] in_i,in_q,
 output reg out_valid,output reg signed [15:0] out_i,out_q
);
localparam integer TAPS=121,SHIFT=17;
reg signed [15:0] di[0:119],dq[0:119];
reg signed [47:0] p_i[0:120],p_q[0:120];
reg signed [47:0] s1_i[0:60],s1_q[0:60];
reg signed [47:0] s2_i[0:30],s2_q[0:30];
reg signed [47:0] s3_i[0:15],s3_q[0:15];
reg signed [47:0] s4_i[0:7],s4_q[0:7];
reg signed [47:0] s5_i[0:3],s5_q[0:3];
reg signed [47:0] s6_i[0:1],s6_q[0:1];
reg [6:0] valid_pipe;
integer k;

function signed [17:0] c; input integer x; begin case(x)
0:c=82;1:c=53;2:c=15;3:c=-26;4:c=-67;5:c=-102;6:c=-127;7:c=-139;8:c=-134;9:c=-113;
10:c=-77;11:c=-30;12:c=22;13:c=74;14:c=117;15:c=146;16:c=155;17:c=142;18:c=105;19:c=47;
20:c=-25;21:c=-105;22:c=-181;23:c=-243;24:c=-279;25:c=-281;26:c=-243;27:c=-162;28:c=-42;29:c=110;
30:c=281;31:c=452;32:c=605;33:c=716;34:c=768;35:c=741;36:c=626;37:c=419;38:c=124;39:c=-242;
40:c=-655;41:c=-1082;42:c=-1482;43:c=-1810;44:c=-2020;45:c=-2068;46:c=-1919;47:c=-1543;48:c=-929;49:c=-74;
50:c=1002;51:c=2268;52:c=3675;53:c=5164;54:c=6664;55:c=8100;56:c=9400;57:c=10494;58:c=11321;59:c=11837;
60:c=12022;61:c=11837;62:c=11321;63:c=10494;64:c=9400;65:c=8100;66:c=6664;67:c=5164;68:c=3675;69:c=2268;
70:c=1002;71:c=-74;72:c=-929;73:c=-1543;74:c=-1919;75:c=-2068;76:c=-2020;77:c=-1810;78:c=-1482;79:c=-1082;
80:c=-655;81:c=-242;82:c=124;83:c=419;84:c=626;85:c=741;86:c=768;87:c=716;88:c=605;89:c=452;
90:c=281;91:c=110;92:c=-42;93:c=-162;94:c=-243;95:c=-281;96:c=-279;97:c=-243;98:c=-181;99:c=-105;
100:c=-25;101:c=47;102:c=105;103:c=142;104:c=155;105:c=146;106:c=117;107:c=74;108:c=22;109:c=-30;
110:c=-77;111:c=-113;112:c=-134;113:c=-139;114:c=-127;115:c=-102;116:c=-67;117:c=-26;118:c=15;119:c=53;120:c=82;
default:c=0;endcase end endfunction

function signed [15:0] sat;input signed [47:0] v;reg signed [47:0] a,z;begin
 a=(v>=0)?v+(48'sd1<<<(SHIFT-1)):v+(48'sd1<<<(SHIFT-1))-1'b1;z=a>>>SHIFT;
 if(z>32767)sat=16'sh7fff;else if(z< -32768)sat=-16'sd32768;else sat=z[15:0];
end endfunction

always @(posedge clk) begin
 if(!rst_n) begin
  valid_pipe<=0;out_valid<=0;out_i<=0;out_q<=0;
  for(k=0;k<120;k=k+1)begin di[k]<=0;dq[k]<=0;end
  for(k=0;k<121;k=k+1)begin p_i[k]<=0;p_q[k]<=0;end
  for(k=0;k<61;k=k+1)begin s1_i[k]<=0;s1_q[k]<=0;end
  for(k=0;k<31;k=k+1)begin s2_i[k]<=0;s2_q[k]<=0;end
  for(k=0;k<16;k=k+1)begin s3_i[k]<=0;s3_q[k]<=0;end
  for(k=0;k<8;k=k+1)begin s4_i[k]<=0;s4_q[k]<=0;end
  for(k=0;k<4;k=k+1)begin s5_i[k]<=0;s5_q[k]<=0;end
  for(k=0;k<2;k=k+1)begin s6_i[k]<=0;s6_q[k]<=0;end
 end else begin
  valid_pipe<={valid_pipe[5:0],in_valid};out_valid<=valid_pipe[6];
  if(valid_pipe[6])begin out_i<=sat(s6_i[0]+s6_i[1]);out_q<=sat(s6_q[0]+s6_q[1]);end
  if(valid_pipe[5])begin for(k=0;k<2;k=k+1)begin s6_i[k]<=s5_i[2*k]+s5_i[2*k+1];s6_q[k]<=s5_q[2*k]+s5_q[2*k+1];end end
  if(valid_pipe[4])begin for(k=0;k<4;k=k+1)begin s5_i[k]<=s4_i[2*k]+s4_i[2*k+1];s5_q[k]<=s4_q[2*k]+s4_q[2*k+1];end end
  if(valid_pipe[3])begin for(k=0;k<8;k=k+1)begin s4_i[k]<=s3_i[2*k]+s3_i[2*k+1];s4_q[k]<=s3_q[2*k]+s3_q[2*k+1];end end
  if(valid_pipe[2])begin
   for(k=0;k<15;k=k+1)begin s3_i[k]<=s2_i[2*k]+s2_i[2*k+1];s3_q[k]<=s2_q[2*k]+s2_q[2*k+1];end
   s3_i[15]<=s2_i[30];s3_q[15]<=s2_q[30];
  end
  if(valid_pipe[1])begin
   for(k=0;k<30;k=k+1)begin s2_i[k]<=s1_i[2*k]+s1_i[2*k+1];s2_q[k]<=s1_q[2*k]+s1_q[2*k+1];end
   s2_i[30]<=s1_i[60];s2_q[30]<=s1_q[60];
  end
  if(valid_pipe[0])begin
   for(k=0;k<60;k=k+1)begin s1_i[k]<=p_i[2*k]+p_i[2*k+1];s1_q[k]<=p_q[2*k]+p_q[2*k+1];end
   s1_i[60]<=p_i[120];s1_q[60]<=p_q[120];
  end
  if(in_valid)begin
   p_i[0]<=in_i*c(0);p_q[0]<=in_q*c(0);
   for(k=1;k<TAPS;k=k+1)begin p_i[k]<=di[k-1]*c(k);p_q[k]<=dq[k-1]*c(k);end
   for(k=119;k>0;k=k-1)begin di[k]<=di[k-1];dq[k]<=dq[k-1];end
   di[0]<=in_i;dq[0]<=in_q;
  end
 end
end
endmodule
