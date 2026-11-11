import_device ph1_90.db -package PH1A90SEG324 -speed 2
create_project hdr_quality_color_probe . -family ph1 -device PH1A90SEG324 -speed -2
set manifest [open sources.lst r]
set sources [split [string trim [read $manifest]] \n]
close $manifest
foreach source $sources {add_files $source}
add_define {PH1=1}
add_define {HDR_QUALITY_PROBE=1}
top_module hdr_quality_color_probe
set_param -run syn_1 flow thread 4
set_param -run syn_1 rtl min_control_set 2
set_param -run syn_1 gate map_mode area_prior
set_param -run syn_1 gate multi_thread_mapping partition
set_param -run syn_1 gate add_map_lut_struct on
launch_runs -step opt_gate syn_1
wait_run syn_1
set native hdr_quality_color_probe_Runs/syn_1
if {![file isfile $native/.opt_gate.end.f] || [llength [glob -nocomplain -directory $native .*.error.f]]} {
    error "HDR color probe opt_gate failed"
}
close_project
open_project hdr_quality_color_probe.al -noanalyze
open_run syn_1
report_area -file reopened.area
report_run_param syn_1 -file effective.params
read_sdc [file normalize probe.sdc]
update_timing
check_timing -file reopened_check.timing
report_timing_summary -ep_num 16 -path_num 2 -file reopened.timing
set pix [get_clocks PIX]
set color [get_regs -nowarn {u_color/*}]
set tone [get_regs -nowarn {u_color/u_tone96/*}]
puts "HDR_QUALITY_COLOR_OBJECTS pix=[llength $pix] color=[llength $color] tone=[llength $tone]"
if {[llength $pix] != 1 || ![llength $color] || ![llength $tone]} {
    error "HDR color probe PIX clock, color or Tone registers missing"
}
report_timing_path -from $color -to $color -ep_num 16 -path_num 2 -file color.timing
report_timing_path -from $tone -to $tone -ep_num 8 -path_num 2 -file tone.timing
set normalize [get_regs -nowarn {u_color/normalize0*}]
if {[llength $normalize]} {
    report_timing_path -from $normalize -ep_num 16 -path_num 2 -file wb_normalize.timing
}
close_project
puts HDR_QUALITY_COLOR_PROBE_NATIVE_REOPENED
exit 0
