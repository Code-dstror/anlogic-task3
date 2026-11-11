import_device ph1_90.db -package PH1A90SEG324 -speed 2
create_project uhd_probe . -family ph1 -device PH1A90SEG324 -speed -2
set manifest [open sources.lst r]
set sources [split [string trim [read $manifest]] \n]
close $manifest
foreach source $sources {add_files $source}
add_include_dir include
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
    error "DFI ring opt_gate failed"
}
close_project
open_project uhd_probe.al -noanalyze
open_run syn_1
report_area -file reopened.area
report_run_param syn_1 -file effective.params
if {![llength [get_clocks DFI]]} {read_sdc clock.sdc}
update_timing
check_timing -file reopened_check.timing
report_timing_summary -ep_num 8 -path_num 1 -file reopened.timing

set f3 [get_regs -nowarn {u_ring/u_record_owner_reset/g_falling_release$released_n*}]
set r3 [get_regs -nowarn {u_ring/u_record_owner_reset/release_pipe[2]}]
set token_d [get_pins -nowarn {token_ready_q_reg*.d}]
set quiet_d [get_pins -nowarn {write_quiet_q_reg*.d}]
set hdr_d [get_pins -nowarn {hdr_release_q_reg*.d hdr_clear_q_reg*.d}]
set fifo_ce [get_pins -nowarn {
    u_fifo_fence/fifo/read_buffer*.ce u_fifo_fence/fifo/read_buffer*.cea u_fifo_fence/fifo/read_buffer*.ceb
}]
set fifo_data [get_regs -nowarn {u_fifo_fence/fifo/read_count* u_fifo_fence/fifo/read_head*}]
set slot_d [get_pins -nowarn {u_ring/u_store/slot_state*.d}]
set slot_ce [get_pins -nowarn {u_ring/u_store/slot_state*.ce}]
set asr [get_pins -nowarn {u_ring/u_store/*.sr u_ring/u_store/cold_bank/*.sr u_ring/u_record_owner_reset/*.sr}]
set egress_ready [get_nets -nowarn {egress_token_ready u_egress/o_token_ready u_fifo_fence/i_sink_ready}]
set groups {token_d fifo_ce fifo_data quiet_d hdr_d slot_d slot_ce asr f3}
set objects [open objects.txt w]
puts $objects "dfi [llength [get_clocks DFI]] [get_clocks DFI]"
puts $objects "pix [llength [get_clocks PIX]] [get_clocks PIX]"
foreach key [linsert $groups 0 r3 egress_ready] {puts $objects "$key [llength [set $key]] [set $key]"}
close $objects
if {[llength [get_clocks DFI]] != 1 || [llength [get_clocks PIX]] != 1 ||
    ![llength $f3] || ![llength $r3] || ![llength $token_d] ||
    ![llength $quiet_d] || ![llength $hdr_d] || ![llength $fifo_data]} {
    error "Expected DFI qualification timing objects are absent"
}
foreach start {f3 r3} {
    report_timing_path -from [set $start] -ep_num 8 -path_num 1 -file ${start}_all.timing
    foreach group $groups {
        if {[llength [set $group]]} {
            report_timing_path -from [set $start] -to [set $group] -ep_num 6 -path_num 1 \
                -file ${start}_to_${group}.timing
        }
    }
    if {[llength $egress_ready] && [llength $fifo_ce]} {
        report_timing_path -from [set $start] -through $egress_ready -to $fifo_ce \
            -ep_num 6 -path_num 1 -file ${start}_through_egress_to_fifo.timing
    }
}
close_project
puts UHD_PROBE_NATIVE_REOPENED
exit 0
