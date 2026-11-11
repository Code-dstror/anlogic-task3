import_device ph1_90.db -package PH1A90SEG324 -speed 2
create_project raw_pack_probe . -family ph1 -device PH1A90SEG324 -speed -2
foreach source {shared_raw10_frame_ingress.v raw_pack_probe.v clock.sdc} {add_files $source}
top_module raw_pack_probe
set_param -run syn_1 flow thread 4
set_param -run syn_1 rtl min_control_set 2
set_param -run syn_1 gate map_mode area_prior
set_param -run syn_1 gate multi_thread_mapping partition
set_param -run syn_1 gate add_map_lut_struct on
launch_runs -step opt_gate syn_1
wait_run syn_1
set syn raw_pack_probe_Runs/syn_1
if {![file isfile $syn/.opt_gate.end.f] || [llength [glob -nocomplain $syn/.*.error.f]]} {
    error "Native RAW packing probe failed"
}
close_project
open_project raw_pack_probe.al -noanalyze
open_run syn_1
report_run_param syn_1 -file effective.params
report_area -file reopened.area
update_timing
report_timing_summary -ep_num 4 -path_num 1 -file reopened.timing
set history [get_regs -nowarn {u_leaf/raw_history[*]}]
set count [get_regs -nowarn {u_leaf/pack_bytes[*]}]
set payload [get_regs -nowarn {u_leaf/axis_data[*]}]
set objects [open objects.txt w]
foreach key {history count payload} {puts $objects "$key [llength [set $key]]"}
close $objects
if {[llength $history] && [llength $payload]} {
    report_timing_path -from $history -to $payload -ep_num 4 -path_num 1 -file history_to_data.timing
}
if {[llength $count] && [llength $payload]} {
    report_timing_path -from $count -to $payload -ep_num 4 -path_num 1 -file count_to_data.timing
}
close_project
puts RAW_PACK_PROBE_NATIVE_REOPENED
exit 0
