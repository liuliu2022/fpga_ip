if {$argc < 1} {
    error "usage: vivado -mode batch -source enable_packet_timing_repair_bd.tcl -tclargs <project.xpr>"
}

set project_path [file normalize [lindex $argv 0]]
open_project $project_path
set bd_file [get_files -quiet */T510_design.bd]
if {[llength $bd_file] != 1} {
    error "expected one T510_design.bd, found [llength $bd_file]"
}
open_bd_design $bd_file
update_compile_order -fileset sources_1

foreach pattern {*gowinsdr_rx_chain* *axis_rx_deframer*} {
    set module_ref [get_ips -quiet $pattern]
    if {[llength $module_ref] != 1} {
        error "expected one module reference for $pattern, found [llength $module_ref]"
    }
    update_module_reference $module_ref
}

foreach pin_name {
    gowinsdr_rx_chain_0/frame_sync
    axis_rx_deframer_0/sync_found
} {
    if {[llength [get_bd_pins -quiet $pin_name]] != 1} {
        error "required repaired port is missing: $pin_name"
    }
}

# Reuse the existing sync_found net. The pulse switches Gardner from its
# acquisition coefficients to the narrow in-frame tracking coefficients.
set sync_net [get_bd_nets -quiet -of_objects \
    [get_bd_pins axis_rx_deframer_0/sync_found]]
if {[llength $sync_net] != 1} {
    error "sync_found is not connected to exactly one BD net"
}
set frame_sync_pin [get_bd_pins gowinsdr_rx_chain_0/frame_sync]
set frame_sync_net [get_bd_nets -quiet -of_objects $frame_sync_pin]
if {[llength $frame_sync_net] == 0} {
    connect_bd_net -net $sync_net $frame_sync_pin
} elseif {$frame_sync_net ne $sync_net} {
    error "frame_sync is connected to the wrong net: $frame_sync_net"
}

# Preserve the existing eight ILA status probes.
set_property CONFIG.C_NUM_OF_PROBES {8} [get_bd_cells ila_2]
set orphan_net [get_bd_nets -quiet axis_rx_deframer_0_header_slip_corrected]
if {[llength $orphan_net]} {
    delete_bd_objs $orphan_net
}

regenerate_bd_layout
validate_bd_design -force
save_bd_design
generate_target all $bd_file
update_compile_order -fileset sources_1

puts "PACKET_TIMING_REPAIR_BD_PASS"
puts "TRACKING_FEEDBACK: axis_rx_deframer_0/sync_found -> gowinsdr_rx_chain_0/frame_sync"
close_project
exit
