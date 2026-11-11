import_device ph1_90.db -package PH1A90SEG324 -speed 2
create_project uhd_probe . -family ph1 -device PH1A90SEG324 -speed -2
set manifest [open sources.lst r]
set sources [split [string trim [read $manifest]] \n]
close $manifest
foreach source $sources {add_files $source}
add_include_dir include
top_module uhd_probe
set_param -run syn_1 flow thread 4
launch_runs -step read_design syn_1
wait_run syn_1
set native uhd_probe_Runs/syn_1
if {![file isfile $native/.read_design.end.f] ||
    ![file isfile $native/uhd_probe_elaborate.db] ||
    [llength [glob -nocomplain -directory $native .*.error.f]]} {
    error "DFI IP closure read_design failed"
}
close_project
open_project uhd_probe.al -noanalyze
close_project
puts DFI_IP_CLOSURE_REOPENED
exit 0
