if {![llength [get_clocks PIX]]} {read_sdc clock.sdc}
update_timing
check_timing -file reopened_check.timing
report_timing_summary -ep_num 4 -path_num 2 -file reopened.timing

set pix [get_clocks PIX]
set reservoir [get_regs -nowarn {dut/reservoir[*] dut/reservoir_reg*}]
set count [get_regs -nowarn {dut/reservoir_count[*]}]
set length [get_regs -nowarn {dut/ac4_length[*]}]
set ready [get_regs -nowarn byte_ready_q]
set state [get_regs -nowarn {dut/state[*] dut/state*}]
set magnitude [get_regs -nowarn {dut/ac2_magnitude*}]
set ac_bits [get_regs -nowarn {dut/ac3_bits*}]
set inventory [open path_objects.txt w]
foreach key {pix reservoir count length ready state magnitude ac_bits} {
    puts $inventory "$key [llength [set $key]] [set $key]"
}
close $inventory
if {[llength $pix] != 1 || ![llength $reservoir] || ![llength $state] ||
    ![llength $count] || ![llength $length] || ![llength $ready]} {
    error "Missing entropy setup timing objects"
}
foreach key {count ready length} {
    report_timing_path -from [set $key] -to $reservoir -ep_num 8 -path_num 2 -file ${key}_to_reservoir.timing
}
report_timing_path -from $ready -to $state -ep_num 16 -path_num 2 -file ready_to_state.timing
if {[llength $magnitude] && [llength $ac_bits]} {
    report_timing_path -from $magnitude -to $ac_bits -ep_num 8 -path_num 2 -file magnitude_to_ac_bits.timing
}
