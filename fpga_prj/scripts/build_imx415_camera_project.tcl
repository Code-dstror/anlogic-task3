set script_dir [file dirname [file normalize [info script]]]
set repo_dir [file normalize [file join $script_dir ../..]]
cd $repo_dir
set project_file [file join $repo_dir fpga_prj imx415_camera.al]
set run_root [file join $repo_dir fpga_prj imx415_camera_Runs]
set report_dir [file join $repo_dir tmp camera_td]
file mkdir $report_dir
proc check_run {path} {
    set failed [glob -nocomplain -directory $path .*error.f]
    if {[llength $failed]} { puts "@@@FAIL $failed"; exit 1 }
}
import_device ph1_90.db -package PH1A90SEG324 -speed 2
open_project $project_file -noanalyze
reset_runs syn_1
launch_runs -step opt_gate syn_1
wait_run syn_1 -quiet
check_run [file join $run_root syn_1]
if {[info exists ::env(CAMERA_SYNTH_ONLY)] && $::env(CAMERA_SYNTH_ONLY) eq "1"} {
    puts "@@@CAMERA SYNTH PASS"
    exit 0
}
launch_runs -step bitgen phy_1
wait_run phy_1 -quiet
check_run [file join $run_root phy_1]
# TD 6.2.168116 can crash reopening a routed database. The run already
# produces final reports; copy these instead of opening the database again.
foreach {source_name output_name} {
    final_timing.rpt timing_summary.rpt
    imx415_camera_phy.area area.rpt
    route_clock_utilization.txt clocks.rpt
    imx415_camera_phy.ts timing_status.rpt
    route.qor route.qor
} {
    set source_path [file join $run_root phy_1 $source_name]
    if {![file exists $source_path] || [file size $source_path] == 0} {
        puts "@@@FAIL missing report $source_path"
        exit 1
    }
    file copy -force $source_path [file join $report_dir $output_name]
}
set timing_file [open [file join $report_dir timing_status.rpt] r]
set timing_text [read $timing_file]
close $timing_file
if {![regexp {SWNS: ([+-]?[0-9.]+)ns} $timing_text unused setup_wns] ||
    ![regexp {HWNS: ([+-]?[0-9.]+)ns} $timing_text unused hold_wns]} {
    puts "@@@FAIL cannot parse final timing"
    exit 1
}
if {$setup_wns < 0 || $hold_wns < 0} {
    puts "@@@FAIL timing setup=$setup_wns ns hold=$hold_wns ns"
    exit 1
}
puts "@@@CAMERA BUILD PASS"
exit 0
