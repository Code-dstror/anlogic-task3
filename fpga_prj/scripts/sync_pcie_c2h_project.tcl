# Synchronize the reviewed PCIe C2H source set into the existing TD project.

proc must {label command_result} {
    if {$command_result != 0} {
        puts "@@@FAIL $label"
        exit 1
    }
}

proc restore_portable_project_path {project_file} {
    set project_dir [file normalize [file dirname $project_file]]
    set absolute_attr "Path=\"$project_dir\""
    set portable_attr {Path="."}

    set project_stream [open $project_file r]
    fconfigure $project_stream -translation binary
    set project_data [read $project_stream]
    close $project_stream

    set original_data $project_data
    if {[string first $absolute_attr $project_data] >= 0} {
        set project_data [string map [list $absolute_attr $portable_attr] $project_data]
    } elseif {[string first $portable_attr $project_data] < 0} {
        puts "@@@FAIL unexpected project path in $project_file"
        exit 1
    }
    set project_data [string map [list "\r\n" "\n"] $project_data]

    if {$project_data eq $original_data} {
        return
    }
    set project_stream [open $project_file w]
    fconfigure $project_stream -translation binary
    puts -nonewline $project_stream $project_data
    close $project_stream
}

set script_dir [file dirname [file normalize [info script]]]
set repo_dir [file normalize [file join $script_dir ../..]]
set project_file [file join $repo_dir fpga_prj anlogic2026.al]
set rtl_dir [file join $repo_dir fpga_rtl]
set vendor_dir [file join $rtl_dir vendor anlogic_pcie_sgdma]

puts "@@@STEP load PH1A90SEG324-2 device"
must "import_device" [catch {
    import_device ph1_90.db -package PH1A90SEG324 -speed 2
} import_message]

puts "@@@STEP open existing project"
must "open_project" [catch {
    open_project $project_file -noanalyze
} open_message]

# Remove superseded registrations from an interrupted earlier sync.  The FIFO
# is now the official Soft_FIFO 3.0 RTL, and the newer vendor PLL IPC is kept as
# a documented generated-Verilog compatibility fallback for TD 6.2.1.
remove_source ../fpga_rtl/ip/pcie_axis_async_fifo.ipc
remove_source ../fpga_rtl/vendor/anlogic_pcie_sgdma/al_ip/sgdma_pll.ipc

top_module pcie_c2h_test_top
add_include_dir [file join $rtl_dir include]
add_define {AXI4ST_BUS_EN=1 AXI4L_MBUS_EN=1 USR_IRQ_EN=1 MSI_EN=1'b1 PH1=1}

set source_files [list \
    [file join $rtl_dir pcie c2h_frame_tx.v] \
    [file join $rtl_dir pcie pcie_inband_header_adapter.v] \
    [file join $rtl_dir pcie pcie_video_transport.v] \
    [file join $rtl_dir pcie c2h_inband_test_source.v] \
    [file join $rtl_dir pcie c2h_test_source.v] \
    [file join $rtl_dir pcie h2c_stream_checker.v] \
    [file join $rtl_dir pcie pcie_app_regs.v] \
    [file join $rtl_dir vendor anlogic_soft_fifo_3_0 Soft_FIFO RTL soft_fifo.v] \
    [file join $rtl_dir pcie axis_frame_fifo_ip.v] \
    [file join $rtl_dir pcie pcie_sgdma_endpoint.v] \
    [file join $rtl_dir pcie pcie_c2h_test_top.v] \
    [file join $vendor_dir sgdma src_enc sgdma_ip_all.enc.v] \
    [file join $vendor_dir sgdma bridge case_ep al_pcie_if_ep.v] \
    [file join $vendor_dir sgdma bridge tx_if axi4_st_mux.v] \
    [file join $vendor_dir sgdma bridge tx_if pcie_tx_client02rq_new.v] \
    [file join $vendor_dir sgdma bridge tx_if pcie_tx_client12cc.v] \
    [file join $vendor_dir sgdma bridge rx_if pcie_rx_bypass2rc.v] \
    [file join $vendor_dir sgdma bridge rx_if pcie_rx_trgt2cq.v] \
    [file join $vendor_dir sgdma bridge sideband_if pcie_sideband_dbi2mgmt.v] \
    [file join $vendor_dir sgdma bridge sideband_if pcie_sideband_msi.v] \
    [file join $vendor_dir sgdma sgdma_subsys.v] \
    [file join $vendor_dir al_ip PH1_LOGIC_PCIE.ipc] \
    [file join $vendor_dir al_ip sgdma_pll.v] \
    [file join $rtl_dir constraints pcie_c2h_test_top.adc] \
    [file join $rtl_dir constraints pcie_c2h_test_top.sdc] \
]

puts "@@@STEP register source and constraint files"
foreach source_file $source_files {
    if {![file exists $source_file]} {
        puts "@@@FAIL missing source: $source_file"
        exit 1
    }
    set add_result [catch {add_files $source_file} add_message]
    if {$add_result != 0} {
        puts "@@@FAIL add_files $source_file"
        puts $add_message
        exit 1
    }
}

close_project
restore_portable_project_path $project_file
puts "@@@SYNC PASS"
exit 0
