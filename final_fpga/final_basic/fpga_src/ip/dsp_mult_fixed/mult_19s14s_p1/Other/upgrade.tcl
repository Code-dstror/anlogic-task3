
proc report_ip_status { current_ip_version original_ip_version upgrade_result current_part recommended_part } {

    set $current_ip_version [string trim $current_ip_version]
    set $current_part   [string trim $current_part]
    set $recommended_part   [string trim $recommended_part]
    set $original_ip_version    [string trim $original_ip_version]
    set $upgrade_result     [string trim $upgrade_result]

    if {$current_part != $recommended_part } {
        set IP_Status 3
        set Recommendation 1
        set Lock 1
        set Upgradable 0
        puts "current_part is different from recommended_part"
        return [list $IP_Status $Recommendation $Lock $Upgradable ]
    }

    set recommend_version "1.1.0"
    set IP_comparibiliy_table [list "1.0.0" "1.1.0"]
    #puts "IP_comparibiliy_table is $IP_comparibiliy_table"
    set comparibiliy_result [lsearch -exact $IP_comparibiliy_table $current_ip_version]
    set recommend_version_list [split $recommend_version "."]
    set current_version_list [split $current_ip_version "."]

    if {$comparibiliy_result == -1} {
        set IP_Status 3
        set Recommendation 1
        set Lock 1
        set Upgradable 0
        puts "version is no include"
        return [list $IP_Status $Recommendation $Lock $Upgradable]      
    } 

    if {[lindex $recommend_version_list 0] != [lindex $current_version_list 0]} {
        set IP_Status 0
        set Recommendation 0
        set Lock 0
        set Upgradable 1
        return [list $IP_Status $Recommendation $Lock $Upgradable]              
    } elseif {[lindex $recommend_version_list 1] != [lindex $current_version_list 1]} {
        set IP_Status 1 
        set Recommendation 0
        set Lock 0
        set Upgradable 1
        return [list $IP_Status $Recommendation $Lock $Upgradable]
    } elseif {[lindex $recommend_version_list 2] != [lindex $current_version_list 2]} {
        set IP_Status 2
        set Recommendation 0
        set Lock 0
        set Upgradable 1
        return [list $IP_Status $Recommendation $Lock $Upgradable]            
    } elseif {$current_ip_version == $recommend_version} {
        set IP_Status 4
        set Recommendation 2
        set Lock 0
        set Upgradable 0
        return [list $IP_Status $Recommendation $Lock $Upgradable]             
    } else {
        set IP_Status 3
        set Recommendation 1
        set Lock 0
        set Upgradable 0            
        return [list $IP_Status $Recommendation $Lock $Upgradable]
    }
}

proc upgrade_ip	{ param_txt_path port_txt_path current_ip_version } {
    return 1
    
}

