import_device ph1_90.db -package PH1A90SEG324 -speed 2
create_project uhd_probe . -family ph1 -device PH1A90SEG324 -speed -2
foreach source {jpeg_byte_packer.v uhd_probe.v clock.sdc} {add_files $source}
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
    error "Packer opt_gate failed"
}
close_project
open_project uhd_probe.al -noanalyze
open_run syn_1
report_area -file reopened.area
report_run_param syn_1 -file effective.params
if {![llength [get_clocks PIX]]} {read_sdc clock.sdc}
update_timing
report_timing_summary -ep_num 6 -path_num 1 -file reopened.timing

set input [get_regs -nowarn {stimulus*}]
set byte [get_regs -nowarn {stimulus[0] stimulus[1] stimulus[2] stimulus[3]
    stimulus[4] stimulus[5] stimulus[6] stimulus[7]}]
set count [get_regs -nowarn {dut/byte_count*}]
set data_d [get_pins -nowarn {dut/byte_data_reg*.d}]
set count_d [get_pins -nowarn {dut/byte_count_reg*.d}]
set objects [open objects.txt w]
foreach name {input byte count data_d count_d} {
    puts $objects "$name [llength [set $name]] [set $name]"
}
close $objects
if {[llength [get_clocks PIX]] != 1 || ![llength $input] || ![llength $byte] ||
    ![llength $count] || ![llength $data_d] || ![llength $count_d]} {
    error "Missing packer timing objects"
}
foreach origin {input count} {
    foreach target {data count} {
        report_timing_path -from [set $origin] -to [set ${target}_d] \
            -ep_num 4 -path_num 1 -file ${origin}_to_${target}.timing
    }
}
report_timing_path -from $byte -to $data_d -ep_num 4 -path_num 1 -file byte_to_data.timing
close_project
puts UHD_PROBE_NATIVE_REOPENED
exit 0
