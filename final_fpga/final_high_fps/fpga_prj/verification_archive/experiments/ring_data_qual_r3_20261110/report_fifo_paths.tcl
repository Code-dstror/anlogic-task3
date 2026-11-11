import_device ph1_90.db -package PH1A90SEG324 -speed 2
open_project uhd_probe.al -noanalyze
open_run syn_1
if {![llength [get_clocks DFI]]} {read_sdc clock.sdc}
update_timing

set f3 [get_regs -nowarn {u_ring/u_record_owner_reset/g_falling_release$released_n*}]
set r3 [get_regs -nowarn {u_ring/u_record_owner_reset/release_pipe[2]}]
set egress_ready [lsort -unique [get_nets -nowarn {egress_token_ready u_egress/o_token_ready u_fifo_fence/i_sink_ready}]]
set marker_quiet [lsort -unique [get_nets -nowarn {sink_quiet u_fifo_fence/i_sink_quiet}]]
set fifo_data [get_regs -nowarn {u_fifo_fence/fifo/read_count* u_fifo_fence/fifo/read_head*}]
set fifo_cells [get_cells -nowarn {u_fifo_fence/fifo/read_buffer_syn_*}]
set inventory [open fifo_path_objects.txt w]
foreach key {f3 r3 egress_ready marker_quiet fifo_data fifo_cells} {
    puts $inventory "$key [llength [set $key]] [set $key]"
}
close $inventory
if {![llength $f3] || ![llength $r3] || ![llength $egress_ready] || ![llength $fifo_data]} {
    error "Missing DFI FIFO branch timing objects"
}
foreach start {f3 r3} {
    foreach branch {egress_ready marker_quiet} {
        if {[llength [set $branch]]} {
            report_timing_path -from [set $start] -through [set $branch] -to $fifo_data \
                -ep_num 6 -path_num 1 -file ${start}_through_${branch}_to_fifo_data.timing
        }
    }
    if {[llength $fifo_cells]} {
        report_timing_path -from [set $start] -to $fifo_cells -ep_num 6 -path_num 1 \
            -file ${start}_to_fifo_cells.timing
    }
}
close_project
puts DFI_FIFO_BRANCH_REPORTS_DONE
exit 0
