if { $ASYNC } {
set  file_name "$IP_EXPORT_PATH/$IP_COMPONENT_NAME/$IP_COMPONENT_NAME.tcl"
set  file_name_id [open $file_name w+] 
puts  $file_name_id {set clkw [get_clocks -nowarn -of [get_ports -nowarn {clkw}]]
set clkr [get_clocks -nowarn -of [get_ports -nowarn {clkr}]]

set wr_clk_period [get_property -nowarn -max PERIOD $clkw]
set rd_clk_period [get_property -nowarn -max PERIOD $clkr]

set dly_sly_slack 0.3

if { $clkw =="" } { 
    set wr_clk_period 1000 
}

if { $clkr =="" } {
    set rd_clk_period 1001
}

set_max_delay -from [get_regs -nowarn {*/cdc$cross_inst/primary_addr_gray_reg_w[*]}] -to [get_regs -nowarn {*/cdc$cross_inst/sync_r1_w[*]}] [expr min($wr_clk_period,$rd_clk_period) - $dly_sly_slack] -nowarn -datapath_only
set_max_delay -from [get_regs -nowarn {*/cdc$cross_inst/primary_addr_gray_reg_r[*]}] -to [get_regs -nowarn {*/cdc$cross_inst/sync_r1_r[*]}] [expr min($wr_clk_period,$rd_clk_period) - $dly_sly_slack] -nowarn -datapath_only}
close $file_name_id


set my_file_name "$IP_COMPONENT_NAME.tcl"
set xml_file "$IP_EXPORT_PATH/$IP_COMPONENT_NAME/$IP_COMPONENT_NAME.xml"

set new_xml_file "$IP_EXPORT_PATH/$IP_COMPONENT_NAME/temp.xml"
set new_xml_file_id [open $new_xml_file w]

set xml_file_id [open $xml_file r+]
while {[gets $xml_file_id line] != -1} {
    if {[regexp "</ipxact:fileSet>" $line ]} {
        puts -nonewline $new_xml_file_id "            <ipxact:file>
                <ipxact:name>$my_file_name</ipxact:name>
                <ipxact:fileType>SDC</ipxact:fileType>
            </ipxact:file> \n"
        puts $new_xml_file_id $line
    } else {
        puts $new_xml_file_id $line
    }
}
close $xml_file_id
close $new_xml_file_id

file delete -force $xml_file
file rename -force $IP_EXPORT_PATH/$IP_COMPONENT_NAME/temp.xml $IP_EXPORT_PATH/$IP_COMPONENT_NAME/$IP_COMPONENT_NAME.xml
}
