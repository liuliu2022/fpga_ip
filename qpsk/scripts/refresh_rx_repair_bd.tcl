if {$argc < 1} {
    error "usage: vivado -mode batch -source refresh_rx_repair_bd.tcl -tclargs <project.xpr>"
}

set project_path [file normalize [lindex $argv 0]]
open_project $project_path

set bd_file [get_files -quiet */T510_design.bd]
if {[llength $bd_file] != 1} {
    error "expected one T510_design.bd, found [llength $bd_file]"
}
open_bd_design $bd_file

set rx_cell [get_bd_cells -quiet gowinsdr_rx_chain_0]
if {[llength $rx_cell] != 1} {
    error "gowinsdr_rx_chain_0 module-reference cell is missing"
}

update_compile_order -fileset sources_1
set rx_module_ref [get_ips -quiet *gowinsdr_rx_chain*]
puts "RX_MODULE_REFERENCE_OBJECTS: $rx_module_ref"
if {[llength $rx_module_ref] != 1} {
    error "expected one generated receiver module reference, found [llength $rx_module_ref]"
}
if {[catch {update_module_reference $rx_module_ref} refresh_error refresh_options]} {
    puts stderr "MODULE_REFERENCE_REFRESH_ERROR: $refresh_error"
    puts stderr "AVAILABLE_COMMANDS: [info commands *module*ref*]"
    if {[llength [info commands update_module_reference]]} {
        puts stderr [help update_module_reference]
    }
    return -options $refresh_options $refresh_error
}
validate_bd_design -force
save_bd_design

set lock_pin [get_bd_pins -quiet gowinsdr_rx_chain_0/costas_locked]
set recovery_pin [get_bd_pins -quiet gowinsdr_rx_chain_0/costas_recovery]
if {[llength $lock_pin] != 1 || [llength $recovery_pin] != 1} {
    error "updated receiver diagnostic pins were not created"
}

puts "RX_REPAIR_BD_PASS cell=$rx_cell lock_pin=$lock_pin recovery_pin=$recovery_pin"
close_project
