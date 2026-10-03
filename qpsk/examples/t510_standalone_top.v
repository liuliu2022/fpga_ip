// --------------------------------------------------------------------
// Copyright (c) 2023 by MicroPhase Technologies Inc.
// --------------------------------------------------------------------
//
// Permission:
//
//   MicroPhase grants permission to use and modify this code for use
//   in synthesis for all MicroPhase Development Boards.
//   Other use of this code, including the selling
//   ,duplication, or modification of any portion is strictly prohibited.
//
// Disclaimer:
//
//   This VHDL/Verilog or C/C++ source code is intended as a design reference
//   which illustrates how these types of functions can be implemented.
//   It is the user's responsibility to verify their design for
//   consistency and functionality through the use of formal
//   verification methods.  MicroPhase provides no warranty regarding the use
//   or functionality of this code.
//
// --------------------------------------------------------------------
//
//                     MicroPhase Technologies Inc
//                     Shanghai, China
//
//                     web: http://www.microphase.cn/
//                     email: support@microphase.cn
//
// --------------------------------------------------------------------
// --------------------------------------------------------------------
//
// Major Functions:
//
// --------------------------------------------------------------------
// --------------------------------------------------------------------
//
//  Revision History
//  Date          By            Revision    Change Description
//---------------------------------------------------------------------
// 2025.03.13     Ao Guohua     1.0          Original
//
// --------------------------------------------------------------------
// --------------------------------------------------------------------
module t510_standalone_top(
    //rf端口
     input adc1_clk_clk_n    ,
     input adc1_clk_clk_p    ,
     input dac2_clk_clk_n    ,
     input dac2_clk_clk_p    ,
     input sysref_in_diff_n  ,
     input sysref_in_diff_p  ,
     input vin0_01_v_n       ,
     input vin0_01_v_p       ,
     input vin0_23_v_n       ,
     input vin0_23_v_p       ,
     input vin1_01_v_n       ,
     input vin1_01_v_p       ,
     input vin1_23_v_n       ,
     input vin1_23_v_p       ,
     input vin2_01_v_n       ,
     input vin2_01_v_p       ,
     input vin2_23_v_n       ,
     input vin2_23_v_p       ,
     input vin3_01_v_n       ,
     input vin3_01_v_p       ,
     input vin3_23_v_n       ,
     input vin3_23_v_p       ,
     output vout00_v_n       ,
     output vout00_v_p       ,
     output vout02_v_n       ,
     output vout02_v_p       ,
     output vout10_v_n       ,
     output vout10_v_p       ,
     output vout12_v_n       ,
     output vout12_v_p       ,
     output vout20_v_n       ,
     output vout20_v_p       ,
     output vout22_v_n       ,
     output vout22_v_p       ,
     output vout30_v_n       ,
     output vout30_v_p       ,
     output vout32_v_n       ,
     output vout32_v_p       ,
  //pl端同步的时钟
     input  pl_clk_p           ,
     input  pl_clk_n           ,
     input  pl_sys_ref_p       ,
     input  pl_sys_ref_n       ,
 //时钟选择信号
     output  clk_main_sel       ,
 //LMK同步信号
     inout  lmk_sync           ,
  //iinc
     inout  iic_scl_io ,
     inout  iic_sda_io ,
     output iic_rst_n ,
   //led
     output dac_status_led     ,
     output adc_status_led

     );
     wire       adc_m_axis_clk;
     wire       dac_s_axis_clk;
     wire       data_rst_n;

     wire [127:0]s00_axis_tdata;
     wire        s00_axis_tready;
     wire        s00_axis_tvalid;
     wire [127:0]s02_axis_tdata;
     wire        s02_axis_tready;
     wire        s02_axis_tvalid;
     wire [127:0]s10_axis_tdata;
     wire        s10_axis_tready;
     wire        s10_axis_tvalid;
     wire [127:0]s12_axis_tdata;
     wire        s12_axis_tready;
     wire        s12_axis_tvalid;
     wire [127:0]s20_axis_tdata;
     wire        s20_axis_tready;
     wire        s20_axis_tvalid;
     wire [127:0]s22_axis_tdata;
     wire        s22_axis_tready;
     wire        s22_axis_tvalid;
     wire [127:0]s30_axis_tdata;
     wire        s30_axis_tready;
     wire        s30_axis_tvalid;
     wire [127:0]s32_axis_tdata;
     wire        s32_axis_tready;
     wire        s32_axis_tvalid;








 //*************GoWinSDR差分QPSK发射链驱动DAC****************
 // 61.44 MHz PL时钟下每拍输出4个连续IQ样本，RFDC输入等效245.76 MSPS。
 // RFDC内部保持原有x20插值和1.5 GHz NCO配置，不修改数据转换器参数。
 wire [15:0]  dac_data_i0;
 wire [15:0]  dac_data_q0;
 wire [15:0]  dac_data_i1;
 wire [15:0]  dac_data_q1;
 wire [15:0]  dac_data_i2;
 wire [15:0]  dac_data_q2;
 wire [15:0]  dac_data_i3;
 wire [15:0]  dac_data_q3;
 wire [127:0] s_axis_tdata;

 wire [1:0]   tx_payload_data;
 wire         tx_payload_valid;
 wire         tx_payload_ready;
 wire         tx_payload_accepted;
 wire         tx_axis_tvalid;
 wire         tx_axis_tready;

//启用外部的时钟源输入经过buffer
 assign clk_main_sel=1'b0;
 tx_prbs_qpsk_source u_tx_source (
     .clk(dac_s_axis_clk),
     .rst_n(data_rst_n),
     .data_out(tx_payload_data),
     .data_valid(tx_payload_valid),
     .data_ready(tx_payload_ready)
 );

 gowinsdr_tx_chain u_tx_chain (
     .clk(dac_s_axis_clk),
     .rst_n(data_rst_n),
     .data_in(tx_payload_data),
     .data_valid(tx_payload_valid),
     .data_ready(tx_payload_ready),
     .data_accepted(tx_payload_accepted),
     .m_axis_tdata(s_axis_tdata),
     .m_axis_tvalid(tx_axis_tvalid),
     .m_axis_tready(tx_axis_tready)
 );

 // Eight enabled DAC streams are broadcast together, matching the original
 // standalone design. RFDC stream ready signals are synchronous and normally
 // remain asserted; the QPSK state advances only when every stream is ready.
 assign tx_axis_tready = s00_axis_tready & s02_axis_tready &
                         s10_axis_tready & s12_axis_tready &
                         s20_axis_tready & s22_axis_tready &
                         s30_axis_tready & s32_axis_tready;
 assign s00_axis_tvalid = tx_axis_tvalid;
 assign s02_axis_tvalid = tx_axis_tvalid;
 assign s10_axis_tvalid = tx_axis_tvalid;
 assign s12_axis_tvalid = tx_axis_tvalid;
 assign s20_axis_tvalid = tx_axis_tvalid;
 assign s22_axis_tvalid = tx_axis_tvalid;
 assign s30_axis_tvalid = tx_axis_tvalid;
 assign s32_axis_tvalid = tx_axis_tvalid;

 assign dac_data_i0 = s_axis_tdata[15:0];
 assign dac_data_q0 = s_axis_tdata[31:16];
 assign dac_data_i1 = s_axis_tdata[47:32];
 assign dac_data_q1 = s_axis_tdata[63:48];
 assign dac_data_i2 = s_axis_tdata[79:64];
 assign dac_data_q2 = s_axis_tdata[95:80];
 assign dac_data_i3 = s_axis_tdata[111:96];
 assign dac_data_q3 = s_axis_tdata[127:112];

 assign s00_axis_tdata =s_axis_tdata;
 assign s02_axis_tdata =s_axis_tdata;
 assign s10_axis_tdata =s_axis_tdata;
 assign s12_axis_tdata =s_axis_tdata;
 assign s20_axis_tdata =s_axis_tdata;
 assign s22_axis_tdata =s_axis_tdata;
 assign s30_axis_tdata =s_axis_tdata;
 assign s32_axis_tdata =s_axis_tdata;
 //dac_status_led指示8个接受数据通道是否都准备好
 assign dac_status_led=!(s00_axis_tready&s02_axis_tready&s10_axis_tready&s12_axis_tready
                   &s20_axis_tready&s22_axis_tready&s30_axis_tready&s32_axis_tready);

T510_design_wrapper u_T510_design_wrapper(
    .adc1_clk_clk_n   ( adc1_clk_clk_n   ),
    .adc1_clk_clk_p   ( adc1_clk_clk_p   ),
    .adc_m_axis_clk   ( adc_m_axis_clk   ),
    .dac2_clk_clk_n   ( dac2_clk_clk_n   ),
    .dac2_clk_clk_p   ( dac2_clk_clk_p   ),
    .dac_s_axis_clk   ( dac_s_axis_clk   ),
    .data_rst_n       ( data_rst_n       ),
    .emio             ( lmk_sync         ),
    .iic_scl_io       ( iic_scl_io       ),
    .iic_sda_io       ( iic_sda_io       ),
    .pl_clk_n         ( pl_clk_n         ),
    .pl_clk_p         ( pl_clk_p         ),
    .pl_sys_ref_n     ( pl_sys_ref_n     ),
    .pl_sys_ref_p     ( pl_sys_ref_p     ),
    .s00_axis_tdata   ( s00_axis_tdata   ),
    .s00_axis_tready  ( s00_axis_tready  ),
    .s00_axis_tvalid  ( s00_axis_tvalid  ),
    .s02_axis_tdata   ( s02_axis_tdata   ),
    .s02_axis_tready  ( s02_axis_tready  ),
    .s02_axis_tvalid  ( s02_axis_tvalid  ),
    .s10_axis_tdata   ( s10_axis_tdata   ),
    .s10_axis_tready  ( s10_axis_tready  ),
    .s10_axis_tvalid  ( s10_axis_tvalid  ),
    .s12_axis_tdata   ( s12_axis_tdata   ),
    .s12_axis_tready  ( s12_axis_tready  ),
    .s12_axis_tvalid  ( s12_axis_tvalid  ),
    .s20_axis_tdata   ( s20_axis_tdata   ),
    .s20_axis_tready  ( s20_axis_tready  ),
    .s20_axis_tvalid  ( s20_axis_tvalid  ),
    .s22_axis_tdata   ( s22_axis_tdata   ),
    .s22_axis_tready  ( s22_axis_tready  ),
    .s22_axis_tvalid  ( s22_axis_tvalid  ),
    .s30_axis_tdata   ( s30_axis_tdata   ),
    .s30_axis_tready  ( s30_axis_tready  ),
    .s30_axis_tvalid  ( s30_axis_tvalid  ),
    .s32_axis_tdata   ( s32_axis_tdata   ),
    .s32_axis_tready  ( s32_axis_tready  ),
    .s32_axis_tvalid  ( s32_axis_tvalid  ),
    .sysref_in_diff_n ( sysref_in_diff_n ),
    .sysref_in_diff_p ( sysref_in_diff_p ),
    .vin0_01_v_n      ( vin0_01_v_n      ),
    .vin0_01_v_p      ( vin0_01_v_p      ),
    .vin0_23_v_n      ( vin0_23_v_n      ),
    .vin0_23_v_p      ( vin0_23_v_p      ),
    .vin1_01_v_n      ( vin1_01_v_n      ),
    .vin1_01_v_p      ( vin1_01_v_p      ),
    .vin1_23_v_n      ( vin1_23_v_n      ),
    .vin1_23_v_p      ( vin1_23_v_p      ),
    .vin2_01_v_n      ( vin2_01_v_n      ),
    .vin2_01_v_p      ( vin2_01_v_p      ),
    .vin2_23_v_n      ( vin2_23_v_n      ),
    .vin2_23_v_p      ( vin2_23_v_p      ),
    .vin3_01_v_n      ( vin3_01_v_n      ),
    .vin3_01_v_p      ( vin3_01_v_p      ),
    .vin3_23_v_n      ( vin3_23_v_n      ),
    .vin3_23_v_p      ( vin3_23_v_p      ),
    .vout00_v_n       ( vout00_v_n       ),
    .vout00_v_p       ( vout00_v_p       ),
    .vout02_v_n       ( vout02_v_n       ),
    .vout02_v_p       ( vout02_v_p       ),
    .vout10_v_n       ( vout10_v_n       ),
    .vout10_v_p       ( vout10_v_p       ),
    .vout12_v_n       ( vout12_v_n       ),
    .vout12_v_p       ( vout12_v_p       ),
    .vout20_v_n       ( vout20_v_n       ),
    .vout20_v_p       ( vout20_v_p       ),
    .vout22_v_n       ( vout22_v_n       ),
    .vout22_v_p       ( vout22_v_p       ),
    .vout30_v_n       ( vout30_v_n       ),
    .vout30_v_p       ( vout30_v_p       ),
    .vout32_v_n       ( vout32_v_n       ),
    .vout32_v_p       ( vout32_v_p       )
);
 //ila_adc_data ila_adc_data (
 //    .clk(adc_m_axis_clk), // input wire clk
 //    .probe0 (adc_data_ch0_i ), // input wire [15:0]  probe0
 //    .probe1 (adc_data_ch0_q ), // input wire [15:0]  probe1
 //    .probe2 (adc_data_ch1_i), // input wire [15:0]  probe2
 //    .probe3 (adc_data_ch1_q), // input wire [15:0]  probe3
 //    .probe4 (adc_data_ch2_i), // input wire [15:0]  probe4
 //    .probe5 (adc_data_ch2_q), // input wire [15:0]  probe5
 //    .probe6 (adc_data_ch3_i), // input wire [15:0]  probe6
 //    .probe7 (adc_data_ch3_q), // input wire [15:0]  probe7
 //    .probe8 (adc_data_ch4_i), // input wire [15:0]  probe8
 //    .probe9 (adc_data_ch4_q), // input wire [15:0]  probe9
 //    .probe10(adc_data_ch5_i), // input wire [15:0]  probe10
 //    .probe11(adc_data_ch5_q), // input wire [15:0]  probe11
 //    .probe12(adc_data_ch6_i), // input wire [15:0]  probe12
 //    .probe13(adc_data_ch6_q), // input wire [15:0]  probe13
 //    .probe14(adc_data_ch7_i), // input wire [15:0]  probe14
 //    .probe15(adc_data_ch7_q) // input wire [15:0]  probe15
 //);

 ila_dac_data ila_dac_data (
     .clk(dac_s_axis_clk), // input wire clk

     .probe0(dac_data_i0), // input wire [15:0]  probe0
     .probe1(dac_data_q0), // input wire [15:0]  probe1
     .probe2(dac_data_i1), // input wire [15:0]  probe2
     .probe3(dac_data_q1), // input wire [15:0]  probe3
     .probe4(dac_data_i2), // input wire [15:0]  probe4
     .probe5(dac_data_q2), // input wire [15:0]  probe5
     .probe6(dac_data_i3), // input wire [15:0]  probe6
     .probe7(dac_data_q3) // input wire [15:0]  probe7
 );

 endmodule
