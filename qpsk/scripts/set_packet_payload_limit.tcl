if {$argc < 1} {
    error "usage: set_packet_payload_limit.tcl <T510 project directory>"
}
set project_dir [file normalize [lindex $argv 0]]
set project_file [file join $project_dir antsdr_t510_standalone.xpr]
set bd_file [file join $project_dir antsdr_t510_standalone.srcs sources_1 bd T510_design T510_design.bd]
open_project $project_file
open_bd_design $bd_file
set_property CONFIG.MAX_PAYLOAD {512} [get_bd_cells axis_tx_framer_0]
set_property CONFIG.MAX_PAYLOAD {512} [get_bd_cells axis_rx_deframer_0]
validate_bd_design
save_bd_design
generate_target all [get_files $bd_file]
make_wrapper -files [get_files $bd_file] -top
close_project
exit
