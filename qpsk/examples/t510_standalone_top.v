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
     wire       qpsk_tx_active;

//启用外部的时钟源输入经过buffer
 assign clk_main_sel=1'b0;
 // QPSK source, framing, DMA, pulse shaping and DAC broadcast now live in BD.
 assign dac_status_led = qpsk_tx_active;
 assign adc_status_led = data_rst_n;

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
    .qpsk_tx_active   ( qpsk_tx_active   ),
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

 endmodule
