set script_dir [file dirname [file normalize [info script]]]
set qpsk_dir [file normalize [file join $script_dir ..]]
set tx_dir [file join $qpsk_dir rtl tx]
set out_dir [file join $script_dir synth_out]
file mkdir $out_dir

create_project -in_memory -part xczu47dr-ffve1156-2-i
add_files -norecurse [list \
    [file join $tx_dir tx_qpsk_diff_encode.v] \
    [file join $tx_dir tx_rrc_interp48x4.v] \
    [file join $tx_dir gowinsdr_tx_chain.v]]
set_property include_dirs [list $tx_dir] [current_fileset]
synth_design -top gowinsdr_tx_chain -part xczu47dr-ffve1156-2-i -mode out_of_context
create_clock -name tx_clk -period 16.276 [get_ports clk]
report_utilization -file [file join $out_dir utilization.txt]
report_timing_summary -delay_type max -max_paths 10 -file [file join $out_dir timing_summary.txt]
write_checkpoint -force [file join $out_dir gowinsdr_tx_chain_synth.dcp]

set timing_paths [get_timing_paths -delay_type max -max_paths 1]
if {[llength $timing_paths] > 0} {
    puts [format "TX_WNS_NS=%.3f" [get_property SLACK [lindex $timing_paths 0]]]
}
puts "TX synthesis complete. Reports: $out_dir"
