if {$argc < 1} {
    error "usage: vivado -mode batch -source enable_packet_iq_ambiguity_bd.tcl -tclargs <project.xpr>"
}

set project_path [file normalize [lindex $argv 0]]
open_project $project_path

set bd_file [get_files -quiet */T510_design.bd]
if {[llength $bd_file] != 1} {
    error "expected one T510_design.bd, found [llength $bd_file]"
}
open_bd_design $bd_file
update_compile_order -fileset sources_1

# Refresh the receiver deframer module reference so the iq_swapped status pin
# and the dual-sync implementation are visible in the BD.
set deframer_ref [get_ips -quiet *axis_rx_deframer*]
if {[llength $deframer_ref] != 1} {
    error "expected one generated axis_rx_deframer module reference, found [llength $deframer_ref]"
}
update_module_reference $deframer_ref

foreach required_cell {axis_tx_framer_0 gowinsdr_tx_chain_0 axis_rx_deframer_0 tx_symbol_test_0 tx_framer_hold_0 ila_1 ila_2} {
    if {[llength [get_bd_cells -quiet $required_cell]] != 1} {
        error "required BD cell is missing: $required_cell"
    }
}

# Remove the temporary on-board 00/01/10/11 test-source wiring. The test block
# remains in the diagram, held inactive, so it can be reconnected later.
foreach net_name {
    tx_symbol_test_0_data_out
    tx_symbol_test_0_data_valid
    gowinsdr_tx_chain_0_data_ready
    axis_tx_framer_0_m_dibit
    axis_tx_framer_0_m_dibit_valid
    tx_framer_hold_0_dout
} {
    set old_net [get_bd_nets -quiet $net_name]
    if {[llength $old_net]} {
        delete_bd_objs $old_net
    }
}

# Activate the real packet path: DMA -> framer -> QPSK transmitter.
connect_bd_net \
    [get_bd_pins axis_tx_framer_0/m_dibit] \
    [get_bd_pins gowinsdr_tx_chain_0/data_in] \
    [get_bd_pins ila_1/probe0]
connect_bd_net \
    [get_bd_pins axis_tx_framer_0/m_dibit_valid] \
    [get_bd_pins gowinsdr_tx_chain_0/data_valid] \
    [get_bd_pins ila_1/probe1] \
    [get_bd_ports qpsk_tx_active]
connect_bd_net \
    [get_bd_pins gowinsdr_tx_chain_0/data_ready] \
    [get_bd_pins axis_tx_framer_0/m_dibit_ready] \
    [get_bd_pins ila_1/probe2]

# Hold the disconnected test generator inactive without deleting its visual BD
# block. CONST_VAL is already zero in the existing design.
connect_bd_net \
    [get_bd_pins tx_framer_hold_0/dout] \
    [get_bd_pins tx_symbol_test_0/data_ready]

# Make the selected ambiguity branch observable next to sync/CRC status.
set_property CONFIG.C_NUM_OF_PROBES {8} [get_bd_cells ila_2]
connect_bd_net \
    [get_bd_pins axis_rx_deframer_0/iq_swapped] \
    [get_bd_pins ila_2/probe7]

regenerate_bd_layout
validate_bd_design -force
save_bd_design
generate_target all $bd_file
update_compile_order -fileset sources_1

puts "PACKET_IQ_AMBIGUITY_BD_PASS"
puts "TX_SOURCE: axis_tx_framer_0 -> gowinsdr_tx_chain_0"
puts "RX_RESOLVER_STATUS: axis_rx_deframer_0/iq_swapped -> ila_2/probe7"
close_project
exit
