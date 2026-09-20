# Independent camera board project; existing PCIe project is untouched.
set script_dir [file dirname [file normalize [info script]]]
set repo_dir [file normalize [file join $script_dir ../..]]
set project_dir [file join $repo_dir fpga_prj]
set project_file [file join $project_dir imx415_camera.al]
set rtl_dir [file join $repo_dir fpga_rtl]
cd $repo_dir
import_device ph1_90.db -package PH1A90SEG324 -speed 2
# Generate literal commands: this TD build loses variable arguments when its
# project commands are dispatched inside Tcl control bodies.
file mkdir [file join $repo_dir tmp camera_td]
set registration [file join $repo_dir tmp camera_td register_camera.tcl]
set commands [open $registration w]
if {[file exists $project_file]} {
    puts $commands "open_project {$project_file} -noanalyze"
} else {
    puts $commands "create_project imx415_camera {$project_dir} -family ph1 -device PH1A90SEG324 -speed -2"
}
puts $commands {top_module imx415_camera_board_top}
puts $commands {add_define {PH1=1}}
puts $commands {remove_source ../fpga_rtl/camera/isp/ui_ram_demosaic.v}
# Exclude testbenches and unused reference PHY top (the application wrapper
# corrects one declaration ordering issue in that top).
set source_files [concat \
    [glob [file join $rtl_dir camera *.v]] \
    [glob [file join $rtl_dir camera sensor *.v]] \
    [glob [file join $rtl_dir camera csi *.v]] \
    [glob [file join $rtl_dir camera isp *.v]] \
    [glob [file join $rtl_dir camera isp raw *.v]] \
    [glob [file join $rtl_dir camera isp color *.v]] \
    [glob [file join $rtl_dir vendor anlogic_camera sensor *.v]] \
    [glob [file join $rtl_dir vendor anlogic_camera clocks *.v]]]
foreach source_file [glob [file join $rtl_dir vendor anlogic_camera phy *.v]] {
    if {[file tail $source_file] ne "csi_rx_phy.v"} { lappend source_files $source_file }
}
lappend source_files [file join $rtl_dir vendor anlogic_pcie_sgdma al_ip sgdma_pll.v]
lappend source_files [file join $rtl_dir vendor anlogic_soft_fifo_3_0 Soft_FIFO RTL soft_fifo.v]
lappend source_files [file join $rtl_dir constraints imx415_camera_board_top.adc]
lappend source_files [file join $rtl_dir constraints imx415_camera_board_top.sdc]
foreach source_file $source_files {
    puts $commands "add_files {$source_file}"
}
puts $commands {close_project}
close $commands
source $registration
# TD writes a machine-local project root; keep the delivered project portable.
set stream [open $project_file r]
set content [read $stream]
close $stream
regsub {Path="[^"]*"} $content {Path="."} content
set stream [open $project_file w]
puts -nonewline $stream $content
close $stream
puts "@@@CAMERA SYNC PASS"
exit 0
