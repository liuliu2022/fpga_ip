if {$argc < 1} {
    error "usage: generate_packet_dma_bitstream.tcl <T510 project directory>"
}
set project_dir [file normalize [lindex $argv 0]]
set project_file [file join $project_dir antsdr_t510_standalone.xpr]

open_project $project_file
set run_status [get_property STATUS [get_runs impl_1]]
if {![string match "*route_design Complete*" $run_status] && ![string match "*write_bitstream Complete*" $run_status]} {
    error "impl_1 is not routed: $run_status"
}

launch_runs impl_1 -to_step write_bitstream -jobs 1
wait_on_run impl_1
set final_status [get_property STATUS [get_runs impl_1]]
puts "BITSTREAM_STATUS=$final_status"
if {![string match "*write_bitstream Complete*" $final_status]} {
    error "bitstream generation did not complete"
}
puts "PASS: T510 QPSK packet/DMA bitstream generated"
close_project
exit
