if {$argc < 1} {
    error "usage: validate_packet_dma_project.tcl <T510 project directory>"
}
set project_dir [file normalize [lindex $argv 0]]
set project_file [file join $project_dir antsdr_t510_standalone.xpr]
set report_dir [file join $project_dir antsdr_t510_standalone.srcs sources_1 new gowinsdr_port packet_link project_synth]
file mkdir $report_dir

open_project $project_file
set_property top t510_standalone_top [get_filesets sources_1]
update_compile_order -fileset sources_1
open_bd_design [get_files T510_design.bd]
validate_bd_design
save_bd_design

reset_run synth_1
launch_runs synth_1 -jobs 1
wait_on_run synth_1
set run_status [get_property STATUS [get_runs synth_1]]
puts "SYNTH_STATUS=$run_status"
if {![string match "*Complete*" $run_status]} {
    error "synth_1 did not complete"
}
open_run synth_1
report_utilization -file [file join $report_dir utilization.txt]
report_timing_summary -file [file join $report_dir timing_summary.txt]
report_drc -file [file join $report_dir drc.txt]
puts "PASS: full T510 project synthesis completed"
close_project
exit
