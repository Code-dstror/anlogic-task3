if {![llength [get_clocks PIX]]} {read_sdc clock.sdc}
update_timing
check_timing -file reopened_check.timing
report_timing_summary -ep_num 4 -path_num 2 -file reopened.timing

set pix [get_clocks PIX]
set d [get_pins -nowarn {dut/reservoir_reg*.d}]
set ce [get_pins -nowarn {dut/reservoir_reg*.ce}]
set formatter [get_regs -nowarn {formatter_state_q*}]
set buffer_valid [get_regs -nowarn buffer_valid_q]
set buffer_last [get_regs -nowarn buffer_last_q]
set queue [get_regs -nowarn {fmt_count_q*}]
set encoder [get_regs -nowarn {encoder_state_q*}]
set abort_release [get_regs -nowarn abort_released_q]
set groups {formatter buffer_valid buffer_last queue encoder abort_release}
set inventory [open path_objects.txt w]
foreach key [concat {pix d ce} $groups] {
    puts $inventory "$key [llength [set $key]] [set $key]"
}
close $inventory
if {[llength $pix] != 1 || ![llength $d]} {
    error "Missing READY-return clock or reservoir data pin"
}
foreach key $groups {
    if {![llength [set $key]]} {error "Missing READY-return register group $key"}
    foreach pin {d ce} {
        if {[llength [set $pin]]} {
            report_timing_path -from [set $key] -to [set $pin] -ep_num 4 -path_num 1 \
                -file ${key}_to_reservoir_${pin}.timing
        }
    }
}
