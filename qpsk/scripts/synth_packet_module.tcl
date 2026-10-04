if {$argc != 2} {
    error "usage: synth_packet_module.tcl <axis_tx_framer|axis_rx_deframer> <T510 project directory>"
}
set top_name [lindex $argv 0]
set local_dir [file dirname [file normalize [info script]]]
set project_dir [file normalize [lindex $argv 1]]
set rtl_dir [file join $project_dir antsdr_t510_standalone.srcs sources_1 new gowinsdr_port packet_link]
set report_dir [file join $rtl_dir module_synth $top_name]
file mkdir $report_dir

create_project -in_memory -part xczu47dr-ffve1156-2-i
read_verilog [file join $rtl_dir ${top_name}.v]
synth_design -top $top_name -part xczu47dr-ffve1156-2-i -mode out_of_context
report_utilization -file [file join $report_dir utilization.txt]
report_timing_summary -file [file join $report_dir timing_summary.txt]
report_drc -file [file join $report_dir drc.txt]
write_checkpoint -force [file join $report_dir ${top_name}.dcp]
puts "PASS: OOC synthesis $top_name"
close_project
exit
