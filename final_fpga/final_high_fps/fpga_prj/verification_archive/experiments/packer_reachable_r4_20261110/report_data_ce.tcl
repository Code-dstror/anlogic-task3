import_device ph1_90.db -package PH1A90SEG324 -speed 2
open_project uhd_probe.al -noanalyze
open_run syn_1
if {![llength [get_clocks PIX]]} {read_sdc clock.sdc}
update_timing

set input [get_regs -nowarn {stimulus*}]
set count [get_regs -nowarn {dut/byte_count*}]
set ce [get_pins -nowarn {dut/byte_data_reg*.ce}]
set objects [open data_ce_objects.txt w]
puts $objects "input [llength $input]"
puts $objects "count [llength $count]"
puts $objects "ce [llength $ce]"
close $objects
if {![llength $input] || ![llength $count] || ![llength $ce]} {
    error "Missing packer data enable timing objects"
}
foreach origin {input count} {
    report_timing_path -from [set $origin] -to $ce -ep_num 4 -path_num 1 -file ${origin}_to_data_ce.timing
}
close_project
puts PACKER_DATA_CE_REPORTED
exit 0
