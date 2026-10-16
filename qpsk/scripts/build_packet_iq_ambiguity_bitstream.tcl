if {$argc < 1} {
    error "usage: build_packet_iq_ambiguity_bitstream.tcl <T510 project directory>"
}

set_param general.maxThreads 2
set project_dir [file normalize [lindex $argv 0]]
set project_file [file join $project_dir antsdr_t510_standalone.xpr]
set report_dir [file join $project_dir antsdr_t510_standalone.srcs sources_1 new gowinsdr_port packet_link project_impl]
file mkdir $report_dir

open_project $project_file
config_ip_cache -disable_cache
set_property top t510_standalone_top [get_filesets sources_1]
update_compile_order -fileset sources_1

reset_run impl_1
launch_runs impl_1 -to_step write_bitstream -jobs 1
wait_on_run impl_1

set run_status [get_property STATUS [get_runs impl_1]]
puts "BITSTREAM_STATUS=$run_status"
if {![string match "*write_bitstream Complete*" $run_status]} {
    error "impl_1 did not complete bitstream generation"
}

open_run impl_1
report_utilization -file [file join $report_dir utilization.txt]
report_timing_summary -file [file join $report_dir timing_summary.txt]
report_drc -file [file join $report_dir drc.txt]
report_clock_interaction -file [file join $report_dir clock_interaction.txt]

set bit_file [file join $project_dir antsdr_t510_standalone.runs impl_1 t510_standalone_top.bit]
if {![file exists $bit_file]} {
    error "bitstream status completed but file is missing: $bit_file"
}
puts "BITSTREAM_FILE=$bit_file"
puts "PASS: IQ-ambiguity-resolving T510 bitstream generated"
close_project
exit
