# Export the already-routed design for ModelSim timing simulation.

proc require_nonempty_file {path description} {
    if {![file exists $path] || [file size $path] == 0} {
        puts "@@@FAIL missing or empty $description: $path"
        exit 1
    }
}

set script_dir [file dirname [file normalize [info script]]]
set repo_dir [file normalize [file join $script_dir ../..]]
set project_file [file join $repo_dir fpga_prj anlogic2026.al]
set report_dir [file join $repo_dir tmp td_reports]
file mkdir $report_dir

import_device ph1_90.db -package PH1A90SEG324 -speed 2
open_project $project_file -noanalyze
open_run phy_1

set old_pwd [pwd]
cd $report_dir
write_verilog pcie_c2h_post_route.v

# SDF contains routed cell/interconnect delays; timing exceptions are not part
# of the SDF payload.  Clear the loaded project/IP constraints before export to
# avoid TD 6.2.1 re-reading the unscoped PCIe IPC SDC during write_sdf.
clear_sdc
write_sdf -file pcie_c2h_post_route.sdf
cd $old_pwd
close_run

set emitted_netlist [file join $report_dir pcie_c2h_test_top_out.v]
set emitted_sdf [file join $report_dir pcie_c2h_test_top.sdf]
if {[file exists $emitted_netlist]} {
    file rename -force $emitted_netlist [file join $report_dir pcie_c2h_post_route.v]
}
if {[file exists $emitted_sdf]} {
    file rename -force $emitted_sdf [file join $report_dir pcie_c2h_post_route.sdf]
}
require_nonempty_file [file join $report_dir pcie_c2h_post_route.v] "routed Verilog netlist"
require_nonempty_file [file join $report_dir pcie_c2h_post_route.sdf] "routed SDF"

puts "@@@EXPORT PASS"
exit 0
