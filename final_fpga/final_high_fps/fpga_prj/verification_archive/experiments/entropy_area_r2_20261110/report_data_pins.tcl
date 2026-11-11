import_device ph1_90.db -package PH1A90SEG324 -speed 2
open_project uhd_probe.al -noanalyze
open_run syn_1
if {![file isfile ready_to_state.timing]} {
    source report_paths.tcl
} else {
    if {![llength [get_clocks PIX]]} {read_sdc clock.sdc}
    update_timing
}

set ready [get_regs -nowarn byte_ready_q]
set state_d [get_pins -nowarn {dut/state_reg*.d}]
set state_ce [get_pins -nowarn {dut/state_reg*.ce}]
set magnitude [get_regs -nowarn {dut/ac2_magnitude*}]
set ac_data_d [get_pins -nowarn {dut/ac3_bits_reg*.d}]
set inventory [open data_pin_objects.txt w]
foreach key {ready state_d state_ce magnitude ac_data_d} {
    puts $inventory "$key [llength [set $key]] [set $key]"
    if {![llength [set $key]]} {error "Missing entropy setup timing pins for $key"}
}
close $inventory
report_timing_path -from $ready -to $state_d -ep_num 4 -path_num 1 -file ready_to_state_d.timing
report_timing_path -from $ready -to $state_ce -ep_num 4 -path_num 1 -file ready_to_state_ce.timing
report_timing_path -from $magnitude -to $ac_data_d -ep_num 4 -path_num 1 -file magnitude_to_ac_data_d.timing
close_project
puts ENTROPY_AREA_DATA_PINS_REPORTED
exit 0
