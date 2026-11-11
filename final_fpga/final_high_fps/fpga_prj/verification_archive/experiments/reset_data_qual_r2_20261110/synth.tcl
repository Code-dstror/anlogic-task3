import_device ph1_90.db -package PH1A90SEG324 -speed 2
create_project uhd_probe . -family ph1 -device PH1A90SEG324 -speed -2
set manifest [open sources.lst r]
set sources [split [string trim [read $manifest]] \n]
close $manifest
foreach source $sources {add_files $source}
top_module uhd_probe
set_param -run syn_1 flow thread 4
set_param -run syn_1 rtl min_control_set 2
set_param -run syn_1 gate map_mode area_prior
set_param -run syn_1 gate multi_thread_mapping partition
set_param -run syn_1 gate add_map_lut_struct on
launch_runs -step opt_gate syn_1
wait_run syn_1
set native uhd_probe_Runs/syn_1
if {![file isfile $native/.opt_gate.end.f] || [llength [glob -nocomplain -directory $native .*.error.f]]} {
    error "PIX qualification opt_gate failed"
}
close_project
open_project uhd_probe.al -noanalyze
open_run syn_1
report_area -file reopened.area
report_run_param syn_1 -file effective.params
if {![llength [get_clocks PIX]]} {read_sdc clock.sdc}
update_timing
check_timing -file reopened_check.timing
report_timing_summary -ep_num 8 -path_num 1 -file reopened.timing

set f3 [get_regs -nowarn {u_original/u_pixel_reset/g_falling_release$released_n*}]
set r3 [get_regs -nowarn {u_original/u_pixel_reset/release_pipe[2]}]
set qual_d [get_pins -nowarn {qualification_q_reg*.d}]
set ingress_d [get_pins -nowarn {u_ingress/axis_data_reg*.d}]
set ingress_ce [get_pins -nowarn {u_ingress/axis_data_reg*.ce}]
set private_d [get_pins -nowarn {u_original/*.d u_original/u_adapter/*.d u_original/u_original_cleanup/*.d}]
set private_ce [get_pins -nowarn {u_original/*.ce u_original/u_adapter/*.ce u_original/u_original_cleanup/*.ce}]
set asr [get_pins -nowarn {u_original/*.sr u_original/u_adapter/*.sr u_original/u_original_cleanup/*.sr u_model_isp_reset/*.sr}]
set groups {qual_d ingress_d ingress_ce private_d private_ce asr f3}
set objects [open objects.txt w]
puts $objects "pix [llength [get_clocks PIX]] [get_clocks PIX]"
foreach key [linsert $groups 0 r3] {puts $objects "$key [llength [set $key]] [set $key]"}
close $objects
if {[llength [get_clocks PIX]] != 1 || ![llength $f3] || ![llength $r3] ||
    ![llength $qual_d] || ![llength $ingress_d]} {
    error "Expected PIX qualification timing objects are absent"
}
foreach start {f3 r3} {
    report_timing_path -from [set $start] -ep_num 8 -path_num 1 -file ${start}_all.timing
    foreach group $groups {
        if {[llength [set $group]]} {
            report_timing_path -from [set $start] -to [set $group] -ep_num 6 -path_num 1 \
                -file ${start}_to_${group}.timing
        }
    }
}
close_project
puts UHD_PROBE_NATIVE_REOPENED
exit 0
