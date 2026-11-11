# Use the native syn_1 run, ending at the elaborated design database.
cd [file normalize [file join [file dirname [info script]] ..]]
import_device ph1_90.db -package PH1A90SEG324 -speed 2
open_project rfcamera_raw_r2.al -noanalyze
reset_runs syn_1
launch_runs -step read_design syn_1
wait_run syn_1
set checkdir [file normalize rfcamera_raw_r2_Runs/syn_1]
if {![file exists [file join $checkdir .read_design.end.f]] ||
    ![file isfile [file join $checkdir rfcamera_raw_r2_elaborate.db]] ||
    [llength [glob -nocomplain -directory $checkdir .*.error.f]]} {
    error "Native read_design did not complete cleanly"
}
report_run_param syn_1 -file rfcamera_raw_r2_Runs/syn_1/effective.params
if {![file isfile rfcamera_raw_r2_Runs/syn_1/effective.params]} {
    error "No native parameter readback"
}
close_project
open_project rfcamera_raw_r2.al -noanalyze
close_project
puts "CAMERA_SHARED_READ_DESIGN_DONE"
exit 0
