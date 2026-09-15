# Build the existing PCIe C2H project and export routed reports/netlists.

proc fail_if_marker_exists {run_dir} {
    set markers [glob -nocomplain -directory $run_dir .*error.f]
    if {[llength $markers] != 0} {
        puts "@@@FAIL error marker in $run_dir: $markers"
        exit 1
    }
}

proc require_nonempty_file {path description} {
    if {![file exists $path] || [file size $path] == 0} {
        puts "@@@FAIL missing or empty $description: $path"
        exit 1
    }
}

proc copy_required_file {source destination description} {
    require_nonempty_file $source $description
    file copy -force $source $destination
}

set script_dir [file dirname [file normalize [info script]]]
set repo_dir [file normalize [file join $script_dir ../..]]
set project_file [file join $repo_dir fpga_prj anlogic2026.al]
set run_root [file join $repo_dir fpga_prj anlogic2026_Runs]
set report_dir [file join $repo_dir tmp td_reports]
file mkdir $report_dir

import_device ph1_90.db -package PH1A90SEG324 -speed 2
open_project $project_file -noanalyze

puts "@@@STEP synthesis"
reset_runs syn_1
launch_runs -step opt_gate syn_1
wait_run syn_1 -quiet
fail_if_marker_exists [file join $run_root syn_1]

puts "@@@STEP place route bitstream"
launch_runs -step bitgen phy_1
wait_run phy_1 -quiet
fail_if_marker_exists [file join $run_root phy_1]

puts "@@@STEP routed reports"
set phy_run_dir [file join $run_root phy_1]
copy_required_file [file join $phy_run_dir anlogic2026_phy.area] \
    [file join $report_dir area.rpt] "routed area report"
copy_required_file [file join $phy_run_dir route.qor] \
    [file join $report_dir route.qor] "routed QoR report"
copy_required_file [file join $phy_run_dir final_timing.rpt] \
    [file join $report_dir timing_summary.rpt] "final timing report"
copy_required_file [file join $phy_run_dir anlogic2026_phy.ts] \
    [file join $report_dir timing_summary_short.rpt] "timing summary"

puts "@@@BUILD PASS"
exit 0
