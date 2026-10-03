set script_dir [file dirname [file normalize [info script]]]
set project_dir [file normalize [file join $script_dir .. .. .. ..]]
set rtl_files [list \
    [file normalize [file join $project_dir antsdr_t510_standalone.srcs sources_1 new gowinsdr_port rfdc_rx_interface.v]] \
    [file normalize [file join $project_dir antsdr_t510_standalone.srcs sources_1 new gowinsdr_port rx_chain rx_polyphase_decim4.v]] \
    [file normalize [file join $project_dir antsdr_t510_standalone.srcs sources_1 new gowinsdr_port rx_chain rx_matched_rrc.v]] \
    [file normalize [file join $project_dir antsdr_t510_standalone.srcs sources_1 new gowinsdr_port rx_chain rx_costas_loop.v]] \
    [file normalize [file join $project_dir antsdr_t510_standalone.srcs sources_1 new gowinsdr_port rx_chain rx_farrow_interpolator.v]] \
    [file normalize [file join $project_dir antsdr_t510_standalone.srcs sources_1 new gowinsdr_port rx_chain rx_gardner_timing.v]] \
    [file normalize [file join $project_dir antsdr_t510_standalone.srcs sources_1 new gowinsdr_port rx_chain rx_qpsk_diff_decode.v]] \
    [file normalize [file join $project_dir antsdr_t510_standalone.srcs sources_1 new gowinsdr_port rx_chain gowinsdr_rx_chain.v]] \
    [file normalize [file join $project_dir antsdr_t510_standalone.srcs sources_1 new gowinsdr_port tx_chain tx_qpsk_diff_encode.v]] \
    [file normalize [file join $project_dir antsdr_t510_standalone.srcs sources_1 new gowinsdr_port tx_chain tx_rrc_interp48x4.v]] \
    [file normalize [file join $project_dir antsdr_t510_standalone.srcs sources_1 new gowinsdr_port tx_chain gowinsdr_tx_chain.v]] \
    [file normalize [file join $project_dir antsdr_t510_standalone.srcs sources_1 new gowinsdr_port tx_chain tx_prbs_qpsk_source.v]]]
set tb_files [list \
    [file normalize [file join $project_dir antsdr_t510_standalone.srcs sim_1 new tb_rfdc_rx_interface.v]] \
    [file normalize [file join $project_dir antsdr_t510_standalone.srcs sim_1 new tb_rfdc_rx_bd_path.v]] \
    [file normalize [file join $project_dir antsdr_t510_standalone.srcs sim_1 new tb_rx_polyphase_decim4.v]] \
    [file normalize [file join $project_dir antsdr_t510_standalone.srcs sim_1 new tb_gowinsdr_rx_chain.v]] \
    [file normalize [file join $project_dir antsdr_t510_standalone.srcs sources_1 new gowinsdr_port tx_chain sim tb_gowinsdr_tx_chain.v]] \
    [file normalize [file join $project_dir antsdr_t510_standalone.srcs sources_1 new gowinsdr_port tx_chain sim tb_tx_rx_loopback.v]]]

if {[llength [get_projects -quiet]] == 0} {
    open_project [file join $project_dir antsdr_t510_standalone.xpr]
}

foreach rtl_file $rtl_files {
    if {[llength [get_files -quiet $rtl_file]] == 0} {
        add_files -fileset sources_1 -norecurse $rtl_file
    }
}

foreach tb_file $tb_files {
    if {[llength [get_files -quiet $tb_file]] == 0} {
        add_files -fileset sim_1 -norecurse $tb_file
    }
}

set tx_include_dir [file normalize [file join $project_dir antsdr_t510_standalone.srcs sources_1 new gowinsdr_port tx_chain]]
set_property include_dirs [list $tx_include_dir] [get_filesets sources_1]
set_property include_dirs [list $tx_include_dir] [get_filesets sim_1]

update_compile_order -fileset sources_1
update_compile_order -fileset sim_1
puts "Added GoWinSDR RFDC interface plus complete RX/TX-chain sources."
