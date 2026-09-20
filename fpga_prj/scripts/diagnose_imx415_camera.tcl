set script_dir [file dirname [file normalize [info script]]]
set repo_dir [file normalize [file join $script_dir ../..]]
cd $repo_dir
import_device ph1_90.db -package PH1A90SEG324 -speed 2
set registration [open tmp/camera_td/register_camera.tcl r]
set text [read $registration]
close $registration
set hdl_sources {}
foreach line [split $text "\n"] {
    if {[regexp {^add_files \{(.*\.v)\}$} $line match path]} { lappend hdl_sources $path }
}
set diagnostic [open tmp/camera_td/read_camera.tcl w]
puts $diagnostic "read_hdl -file {$hdl_sources} -define PH1=1 -top imx415_camera_board_top"
close $diagnostic
source tmp/camera_td/read_camera.tcl
read_adc fpga_rtl/constraints/imx415_camera_board_top.adc
optimize_rtl
read_sdc fpga_rtl/constraints/imx415_camera_board_top.sdc
optimize_gate
report_area -file tmp/camera_td/diagnostic_area.rpt
exit 0
