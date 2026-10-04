if {$argc < 1} {
    error "usage: integrate_packet_dma_bd.tcl <T510 project directory>"
}
set project_dir [file normalize [lindex $argv 0]]
set project_file [file join $project_dir antsdr_t510_standalone.xpr]
set bd_file [file join $project_dir antsdr_t510_standalone.srcs sources_1 bd T510_design T510_design.bd]
set packet_dir [file join $project_dir antsdr_t510_standalone.srcs sources_1 new gowinsdr_port packet_link]
set tx_dir [file join $project_dir antsdr_t510_standalone.srcs sources_1 new gowinsdr_port tx_chain]

open_project $project_file

foreach file_name {axis_tx_framer.v axis_rx_deframer.v} {
    set source_file [file normalize [file join $packet_dir $file_name]]
    if {[llength [get_files -quiet $source_file]] == 0} {
        add_files -fileset sources_1 -norecurse $source_file
    }
}
set tx_coeff_include [file normalize [file join $tx_dir tx_rrc_coeffs_case.vh]]
if {[llength [get_files -quiet $tx_coeff_include]] == 0} {
    add_files -fileset sources_1 -norecurse $tx_coeff_include
    set_property file_type {Verilog Header} [get_files $tx_coeff_include]
}
foreach file_name {tb_axis_packet_link.v tb_full_phy_packet_loopback.v} {
    set sim_file [file normalize [file join $packet_dir sim $file_name]]
    if {[llength [get_files -quiet $sim_file]] == 0} {
        add_files -fileset sim_1 -norecurse $sim_file
    }
}
update_compile_order -fileset sources_1
update_compile_order -fileset sim_1

open_bd_design $bd_file
if {[llength [get_bd_cells -quiet axi_dma_qpsk]] != 0} {
    error "axi_dma_qpsk already exists; refusing a duplicate integration"
}

# Keep the existing ADC IQ capture DMA. The packet DMA is a separate,
# full-duplex simple-mode engine with 32-bit streams and 128-bit DDR ports.
set dma [create_bd_cell -type ip -vlnv xilinx.com:ip:axi_dma:7.1 axi_dma_qpsk]
set_property -dict [list \
    CONFIG.c_include_sg {0} \
    CONFIG.c_include_mm2s {1} \
    CONFIG.c_include_s2mm {1} \
    CONFIG.c_include_mm2s_dre {1} \
    CONFIG.c_include_s2mm_dre {1} \
    CONFIG.c_m_axi_mm2s_data_width {128} \
    CONFIG.c_m_axi_s2mm_data_width {128} \
    CONFIG.c_m_axis_mm2s_tdata_width {32} \
    CONFIG.c_s_axis_s2mm_tdata_width {32} \
    CONFIG.c_mm2s_burst_size {64} \
    CONFIG.c_s2mm_burst_size {64} \
    CONFIG.c_sg_length_width {26}] $dma

set tx_cdc [create_bd_cell -type ip -vlnv xilinx.com:ip:axis_clock_converter:1.1 qpsk_tx_axis_cdc]
set_property -dict [list CONFIG.TDATA_NUM_BYTES {4} CONFIG.HAS_TKEEP {1} CONFIG.HAS_TLAST {1} CONFIG.IS_ACLK_ASYNC {1}] $tx_cdc
set rx_cdc [create_bd_cell -type ip -vlnv xilinx.com:ip:axis_clock_converter:1.1 qpsk_rx_axis_cdc]
set_property -dict [list CONFIG.TDATA_NUM_BYTES {4} CONFIG.HAS_TKEEP {1} CONFIG.HAS_TLAST {1} CONFIG.IS_ACLK_ASYNC {1}] $rx_cdc

set tx_framer [create_bd_cell -type module -reference axis_tx_framer axis_tx_framer_0]
set tx_phy [create_bd_cell -type module -reference gowinsdr_tx_chain gowinsdr_tx_chain_0]
set rx_deframer [create_bd_cell -type module -reference axis_rx_deframer axis_rx_deframer_0]
set_property CONFIG.MAX_PAYLOAD {512} $tx_framer
set_property CONFIG.MAX_PAYLOAD {512} $rx_deframer

set tx_broadcast [create_bd_cell -type ip -vlnv xilinx.com:ip:axis_broadcaster:1.1 qpsk_dac_broadcaster]
set_property -dict [list \
    CONFIG.NUM_MI {8} \
    CONFIG.S_TDATA_NUM_BYTES {16} \
    CONFIG.M_TDATA_NUM_BYTES {16} \
    CONFIG.HAS_TREADY {1} \
    CONFIG.HAS_TKEEP {0} \
    CONFIG.HAS_TLAST {0}] $tx_broadcast

# AXI-Stream packet path.
connect_bd_intf_net [get_bd_intf_pins $dma/M_AXIS_MM2S] [get_bd_intf_pins $tx_cdc/S_AXIS]
connect_bd_intf_net [get_bd_intf_pins $tx_cdc/M_AXIS] [get_bd_intf_pins $tx_framer/s_axis]
connect_bd_intf_net [get_bd_intf_pins $rx_deframer/m_axis] [get_bd_intf_pins $rx_cdc/S_AXIS]
connect_bd_intf_net [get_bd_intf_pins $rx_cdc/M_AXIS] [get_bd_intf_pins $dma/S_AXIS_S2MM]

# Visible two-bit packet/PHY boundaries.
connect_bd_net [get_bd_pins $tx_framer/m_dibit] [get_bd_pins $tx_phy/data_in]
connect_bd_net [get_bd_pins $tx_framer/m_dibit_valid] [get_bd_pins $tx_phy/data_valid]
connect_bd_net [get_bd_pins $tx_phy/data_ready] [get_bd_pins $tx_framer/m_dibit_ready]
connect_bd_net [get_bd_pins gowinsdr_rx_chain_0/decoded_data] [get_bd_pins $rx_deframer/s_dibit]
connect_bd_net [get_bd_pins gowinsdr_rx_chain_0/decoded_valid] [get_bd_pins $rx_deframer/s_dibit_valid]

# Move all DAC traffic inside the BD. One QPSK stream is broadcast to the same
# eight enabled RFDC DAC streams used by the prior top-level wiring.
connect_bd_intf_net [get_bd_intf_pins $tx_phy/m_axis] [get_bd_intf_pins $tx_broadcast/S_AXIS]
set dac_ifaces {s00_axis s02_axis s10_axis s12_axis s20_axis s22_axis s30_axis s32_axis}
for {set i 0} {$i < 8} {incr i} {
    set ext_name [lindex $dac_ifaces $i]
    set net_obj [get_bd_intf_nets -quiet -of_objects [get_bd_intf_ports -quiet $ext_name]]
    if {[llength $net_obj]} { delete_bd_objs $net_obj }
    set ext_obj [get_bd_intf_ports -quiet $ext_name]
    if {[llength $ext_obj]} { delete_bd_objs $ext_obj }
    connect_bd_intf_net \
        [get_bd_intf_pins $tx_broadcast/[format "M%02d_AXIS" $i]] \
        [get_bd_intf_pins usp_rf_data_converter_0/$ext_name]
}

# PS control interconnect: expose the new DMA at the fourth master port.
set_property CONFIG.NUM_MI {4} [get_bd_cells ps8_0_axi_periph]
connect_bd_intf_net [get_bd_intf_pins ps8_0_axi_periph/M03_AXI] [get_bd_intf_pins $dma/S_AXI_LITE]

# DDR path: the existing IQ DMA plus the two packet-DMA memory masters share
# the already-enabled coherent HPC0 port through SmartConnect.
set_property CONFIG.NUM_SI {3} [get_bd_cells axi_smc]
connect_bd_intf_net [get_bd_intf_pins $dma/M_AXI_MM2S] [get_bd_intf_pins axi_smc/S01_AXI]
connect_bd_intf_net [get_bd_intf_pins $dma/M_AXI_S2MM] [get_bd_intf_pins axi_smc/S02_AXI]

# 100-MHz PS/DDR domain.
connect_bd_net [get_bd_pins zynq_ultra_ps_e_0/pl_clk0] \
    [get_bd_pins $dma/s_axi_lite_aclk] \
    [get_bd_pins $dma/m_axi_mm2s_aclk] \
    [get_bd_pins $dma/m_axi_s2mm_aclk] \
    [get_bd_pins $tx_cdc/s_axis_aclk] \
    [get_bd_pins $rx_cdc/m_axis_aclk] \
    [get_bd_pins ps8_0_axi_periph/M03_ACLK]
connect_bd_net [get_bd_pins rst_ps8_0_99M/peripheral_aresetn] \
    [get_bd_pins $dma/axi_resetn] \
    [get_bd_pins $tx_cdc/s_axis_aresetn] \
    [get_bd_pins $rx_cdc/m_axis_aresetn] \
    [get_bd_pins ps8_0_axi_periph/M03_ARESETN]

# 61.44-MHz DAC domain.
connect_bd_net [get_bd_pins clk_wiz_0/clk_out2] \
    [get_bd_pins $tx_cdc/m_axis_aclk] \
    [get_bd_pins $tx_framer/clk] \
    [get_bd_pins $tx_phy/clk] \
    [get_bd_pins $tx_broadcast/aclk]
connect_bd_net [get_bd_pins clk_wiz_0/locked] \
    [get_bd_pins $tx_cdc/m_axis_aresetn] \
    [get_bd_pins $tx_framer/rst_n] \
    [get_bd_pins $tx_phy/rst_n] \
    [get_bd_pins $tx_broadcast/aresetn]

# 61.44-MHz ADC domain.
connect_bd_net [get_bd_pins clk_wiz_0/clk_out1] \
    [get_bd_pins $rx_deframer/clk] \
    [get_bd_pins $rx_cdc/s_axis_aclk]
connect_bd_net [get_bd_pins rst_clk_wiz_0_61M/peripheral_aresetn] \
    [get_bd_pins $rx_deframer/rst_n] \
    [get_bd_pins $rx_cdc/s_axis_aresetn]

# Combine the original IQ-capture interrupt with packet MM2S and S2MM IRQs.
set old_irq_net [get_bd_nets -quiet -of_objects [get_bd_pins axi_dma_0/s2mm_introut]]
if {[llength $old_irq_net]} { delete_bd_objs $old_irq_net }
set irq_concat [create_bd_cell -type ip -vlnv xilinx.com:ip:xlconcat:2.1 qpsk_dma_irq_concat]
set_property CONFIG.NUM_PORTS {3} $irq_concat
connect_bd_net [get_bd_pins axi_dma_0/s2mm_introut] [get_bd_pins $irq_concat/In0]
connect_bd_net [get_bd_pins $dma/mm2s_introut] [get_bd_pins $irq_concat/In1]
connect_bd_net [get_bd_pins $dma/s2mm_introut] [get_bd_pins $irq_concat/In2]
connect_bd_net [get_bd_pins $irq_concat/dout] [get_bd_pins zynq_ultra_ps_e_0/pl_ps_irq0]

set tx_active [create_bd_port -dir O qpsk_tx_active]
connect_bd_net [get_bd_pins $tx_framer/m_dibit_valid] $tx_active

# Fixed register address for later standalone PS software.
assign_bd_address -offset 0x0080060000 -range 64K \
    -target_address_space [get_bd_addr_spaces zynq_ultra_ps_e_0/Data] \
    [get_bd_addr_segs $dma/S_AXI_LITE/Reg]
assign_bd_address

regenerate_bd_layout
validate_bd_design
save_bd_design
generate_target all [get_files $bd_file]
make_wrapper -files [get_files $bd_file] -top
update_compile_order -fileset sources_1
puts "PASS: modular QPSK packet DMA chain inserted into T510_design"
close_project
exit
