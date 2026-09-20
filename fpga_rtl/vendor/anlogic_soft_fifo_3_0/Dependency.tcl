# The Command Lines that defined the parameter attributes.

set_param -param_id {ERAM} -data_type {Mutex} -members {RAM Option}
set_param -param_id {DRAM} -data_type {Mutex} -members {RAM Option}
set_param -param_id {URAM} -data_type {Mutex} -members {RAM Option}
set_param -param_id {EMB9K_Area_Opt} -data_type {Mutex} -members {Implement Option}
set_param -param_id {EMB9K_Timing_Opt} -data_type {Mutex} -members {Implement Option}
set_param -param_id {EMB32K} -data_type {Mutex} -members {Implement Option}
set_param -param_id {Auto} -data_type {Mutex} -members {Implement Option}
set_param -param_id {EMB20K_Area_Opt} -data_type {Mutex} -members {Implement Option}
set_param -param_id {EMB20K_Timing_Opt} -data_type {Mutex} -members {Implement Option}
set_param -param_id {ASYNC} -data_type {Mutex} -members {Clock Mode}
set_param -param_id {SYNC} -data_type {Mutex} -members {Clock Mode}
set_param -param_id {Write_Width} -data_type {Integer} -min {1} -max {data_width_a_high_range_a $ERAM $DRAM $URAM} -step {1}
set_param -param_id {Write_Depth} -data_type {Integer} -list {depth_list $Write_Width $ERAM $DRAM $URAM}
set_param -param_id {Read_Width} -data_type {Integer} -list {cal_read_width $Write_Width $Write_Depth $ERAM $DRAM $URAM}
set_param -param_id {Read_Depth} -data_type {Integer} -value {cal_read_depth $Write_Width $Write_Depth $Read_Width}
set_param -param_id {Show_Ahead_Enable} -data_type {Mutex} -members {showahead}
set_param -param_id {Show_Ahead_Disable} -data_type {Mutex} -members {showahead}
set_param -param_id {Out_Reg_Enable} -data_type {Mutex} -members {OutReg}
set_param -param_id {Out_Reg_Disable} -data_type {Mutex} -members {OutReg}
set_param -param_id {Almost_Full_Num} -data_type {Integer} -min {3} -max {cal_al_full_num $Write_Depth} -step {1}
set_param -param_id {Almost_Empty_Num} -data_type {Integer} -min {2} -max {cal_al_empty_num $Read_Depth} -step {1}
set_param -param_id {Sync_Stages} -data_type {Integer} -list {list "2" "3" "4" "5" "6" "7" "8"}
set_param -param_id {Reset_Type} -data_type {String} -list {rst_type_proc $ASYNC}
set_param -param_id {Dout_Reset_Value} -data_type {String} -value {0}
set_param -param_id {Write_Width_Range} -data_type {String} -value {write_width_range [data_width_a_high_range_a $ERAM $DRAM $URAM]}
set_param -param_id {Read_Width_Range} -data_type {String} -value {write_width_range [data_width_a_high_range_a $ERAM $DRAM $URAM]}
set_param -param_id {Almost_Full_Num_Range} -data_type {String} -value {show_al_full $Write_Depth}
set_param -param_id {Almost_Empty_Num_Range} -data_type {String} -value {show_al_empty $Read_Depth}
set_param -param_id {COMMON_CLK_EN} -data_type {Integer} -value {expr {$SYNC==1?1:0}}
set_param -param_id {MEMORY_TYPE} -data_type {Integer} -value {ram_piritive $ERAM $DRAM $URAM $EMB9K_Area_Opt $EMB9K_Timing_Opt $EMB20K_Area_Opt $EMB20K_Timing_Opt $EMB32K $Auto}
set_param -param_id {RST_TYPE} -data_type {Integer} -value {rst_type $Reset_Type}
set_param -param_id {DATA_WIDTH_W} -data_type {Integer} -value {expr $Write_Width}
set_param -param_id {ADDR_WIDTH_W} -data_type {Integer} -value {expr int(log($Write_Depth)/log(2))}
set_param -param_id {DATA_WIDTH_R} -data_type {Integer} -value {expr $Read_Width}
set_param -param_id {ADDR_WIDTH_R} -data_type {Integer} -value {expr int(log($Read_Depth)/log(2))}
set_param -param_id {DOUT_INITVAL} -data_type {Integer} -value {dout_initval $Read_Width $Dout_Reset_Value $Reset_Type}
set_param -param_id {OUTREG_EN} -data_type {String} -value {expr $Out_Reg_Enable==1?"OUT_REG":"NOREG"}
set_param -param_id {SHOW_AHEAD_EN} -data_type {Integer} -value {expr $Show_Ahead_Enable}
set_param -param_id {AL_FULL_NUM} -data_type {Integer} -value {expr $Almost_Full_Num}
set_param -param_id {AL_EMPTY_NUM} -data_type {Integer} -value {expr $Almost_Empty_Num}
set_param -param_id {RDUSEDW_WIDTH} -data_type {Integer} -value {rdusedw_width $Show_Ahead_Enable $ADDR_WIDTH_W $ADDR_WIDTH_R $ASYNC}
set_param -param_id {WRUSEDW_WIDTH} -data_type {Integer} -value {wrusedw_width $Show_Ahead_Enable $ADDR_WIDTH_W $ADDR_WIDTH_R $ASYNC}
set_param -param_id {ASYNC_RST_SYNC_RELS} -data_type {Integer} -value {expr {$Reset_Type=="ASYNC Reset SYNC Release"?1:0}}
set_param -param_id {SYNC_STAGE} -data_type {Integer} -value {expr $Sync_Stages}
set_param -param_id {EG4} -data_type {Integer} -value {expr {[devics_info_eg4]==1?1:0}}
set_param -param_id {EF2} -data_type {Integer} -value {expr {[devics_info_ef2]==1?1:0}}
set_param -param_id {EF3} -data_type {Integer} -value {expr {[devics_info_ef3]==1?1:0}}
set_param -param_id {EF4} -data_type {Integer} -value {expr {[devics_info_ef4]==1?1:0}}
set_param -param_id {EF5} -data_type {Integer} -value {expr {[devics_info_ef5]==1?1:0}}
set_param -param_id {SF1} -data_type {Integer} -value {expr {[devics_info_sf1]==1?1:0}}
set_param -param_id {SF2} -data_type {Integer} -value {expr {[devics_info_sf2]==1?1:0}}
set_param -param_id {PH1} -data_type {Integer} -value {expr {[devics_info_ph1]==1?1:0}}
set_param -param_id {PH2} -data_type {Integer} -value {expr {[devics_info_ph2]==1?1:0}}
set_param -param_id {DR1} -data_type {Integer} -value {expr {[devics_info_dr1]==1?1:0}}
set_param -param_id {EF3L15_25_45} -data_type {Integer} -value {expr {[devics_info_ef3l15_25_45]==1?1:0}}
# The Tcl Procs that used in parameter dependency.

proc cal_read_width {write_width write_depth eram dram uram} {
    set high_range [data_width_a_high_range_a $eram $dram $uram]
    for {set i -4} {$i<5} {incr i} {
        set count [expr pow(2,$i)*$write_width]
        if { (([expr int($count) == $count]) && $count >= 1 && $high_range >= $count)||$count==1} {
            set read_depth [expr $write_width*$write_depth/$count]
            if {$read_depth>=16} {
              lappend hhh [expr int($count)]
            }
        }
    }
    return $hhh
}

proc clog2 {depth} {
    return "[expr int(log10($depth)/log10(2)) ]"
}

proc cal_read_depth {DATA_WIDTH_W Write_Depth DATA_WIDTH_R} {
    return "[expr $DATA_WIDTH_W*$Write_Depth/$DATA_WIDTH_R]"
}

proc cal_al_empty_num {read_depth} {
    return "[expr $read_depth-4]"
}

proc cal_al_full_num {write_depth} {
    return "[expr $write_depth-3]"
}

proc outregmux {en dis} {
    if {$en} {
        return  {"OUTREG"}
    } elseif {$dis} {
        return  {"NOREG"}
    }
}

proc show_ahead_mux {en dis} {
    if {$en} {
        return  1
    } elseif {$dis} {
        return  0
    }
}

proc show_al_full {wdepth} {
    return "3-[expr $wdepth-3]"
}

proc show_al_empty {rdepth} {
    return "2-[expr $rdepth-4]"
}

proc depth_list {
    width
    eram
    dram
    uram
} {
    set range_depth [data_depth_a_high_range $width $eram $dram $uram]
    set depth_width [expr int(log($range_depth)/log(2))]
    for {set i 4} {$i<=$depth_width} {incr i} {
        set count [expr pow(2,$i)]
        lappend hhh [expr int($count)]
    }
    return $hhh
}

proc data_depth_a_high_range {
    width
    eram
    dram
    uram
} {
    set ram_num [ram_size $eram $dram $uram]
    set ram_num_test [expr int(pow(2,int(log($ram_num)/log(2))))]
    set max_ram [expr $ram_num_test*16*1024]
    if {$width<=16} {
        set depth [expr int(pow(2,int(log($max_ram/16)/log(2))))]
        if {$depth < 131072} {
            return $depth
        } else {
            return 131072
        }
    } else {
        set width_log [expr log($width)/log(2)]
        if {$width_log > int($width_log) } {
            set cal_width [expr int($width_log) + 1]
              } else {
            set cal_width int($width_log)
        }
        set cal_width_a [expr int(pow(2,$cal_width))]
        set return_depth [expr $max_ram/$cal_width_a]
        if { $return_depth > 131072 } {
            return 131072
        } else {
            return $return_depth
        }
    }
}

proc data_width_a_high_range_a {
    eram
    dram
    uram
 } { 
    
    set ram_num_test [ram_size $eram $dram $uram ]

    if {$ram_num_test < 4} {
        return 64
    } elseif {$ram_num_test >= 4 && $ram_num_test < 9} {
        return 128
    } elseif {$ram_num_test >= 9 && $ram_num_test < 30} {
        return 256
    } elseif {$ram_num_test < 30} {
        return 512
    } else {
        return 1024
    }
}

proc findCommaPosition {str n} {
    set count 0
    set commaPos -1
    while {$count < $n} {
        set commaPos [string first "," $str $commaPos+1]
        if {$commaPos == -1} {
            return -1
        }
        incr count
    }
    return $commaPos
}

proc ram_size { eram dram uram } {
    global IP_DEVICE
    global IP_INSTALL_PATH
    global IP_CONFIDENTIAL_DEVICE
    catch {puts $IP_CONFIDENTIAL_DEVICE} error_info
    if {[regexp -nocase {(no)} $error_info match]} {
        set IP_CONFIDENTIAL_DEVICE "NO_DEVICE_MATCH"
    }
    set source_path_length [string length $IP_INSTALL_PATH]
    set same_str [string range $IP_INSTALL_PATH 0 [expr $source_path_length - 24]]
    set csv_path $same_str\/arch\/device_resource\/device_resource.csv
    catch {set open_csv [open $csv_path r]} open_file_r
    if { [regexp -nocase {(no)} $open_file_r match] } {
        set size 100
    } else {
        while {[gets $open_csv line]!=-1} {
            if { [regexp -nocase "^$IP_DEVICE|$IP_CONFIDENTIAL_DEVICE" $line match] } {
              set comma_f [findCommaPosition $line 7]
              set comma_s [findCommaPosition $line 8]
              set comma_t [findCommaPosition $line 9]
              set comma_fo [findCommaPosition $line 10]
              set str   [string range $line [expr $comma_f+1] [expr $comma_s-1]]
              set str_1 [string range $line [expr $comma_s+1] [expr $comma_t-1]]
              set str_2 [string range $line [expr $comma_t+1] [expr $comma_fo-1]]
              if {$eram} {
                  if { $str < 100 } {
                    return 3
                  } elseif { $str >= 100 && $str < 500 } {
                    return 8
                  } elseif { $str >= 500 && $str < 1000 } {
                    return 20
                  } else {
                    set size [expr $str/20]
                  }
              } elseif {$dram} {
                  return [ expr $str_1/2/20 + 1]
              } else {
                  return 120
              }
                set size [expr $str/20]
                close $open_csv
                return $size
            }
        }
        set size 100
    }  
    return $size
}

proc write_width_range {width_max} {
    set range "1~$width_max"
    return $range
}

proc devics_info_eg4 { } {
    global IP_DEVICE
    if {[regexp -nocase {(EG4D|EG4X|EG4A|EG4S)} $IP_DEVICE match]} {
        return 1
    } else {
        return 0
    }
}

proc devics_info_ef2 { } {
    global IP_DEVICE
    if {[regexp -nocase {(EF2)} $IP_DEVICE match]} {
        return 1
    } else {
        return 0
    }
}

proc devics_info_ef3 { } {
    global IP_DEVICE
    if {[regexp -nocase {(EF3)} $IP_DEVICE match]} {
        return 1
    } else {
        return 0
    }
}

proc devics_info_ef4 { } {
    global IP_DEVICE
    if {[regexp -nocase {(EF4)} $IP_DEVICE match]} {
        return 1
    } else {
        return 0
    }
}

proc devics_info_ef5 { } {
    global IP_DEVICE
    if {[regexp -nocase {(EF5)} $IP_DEVICE match]} {
        return 1
    } else {
        return 0
    }
}

proc devics_info_sf1 { } {
    global IP_DEVICE
    if {[regexp -nocase {(SF1)} $IP_DEVICE match]} {
        return 1
    } else {
        return 0
    }
}

proc devics_info_sf2 { } {
    global IP_DEVICE
    if {[regexp -nocase {(SF2)} $IP_DEVICE match]} {
        return 1
    } else {
        return 0
    }
}

proc devics_info_ph1 { } {
    global IP_DEVICE
    if {[regexp -nocase {(PH1)} $IP_DEVICE match]} {
        return 1
    } else {
        return 0
    }
}

proc devics_info_ph2 { } {
    global IP_DEVICE
    if {[regexp -nocase {(PH2)} $IP_DEVICE match]} {
        return 1
    } else {
        return 0
    }
}

proc devics_info_dr1 { } {
    global IP_DEVICE
    if {[regexp -nocase {(DR1)} $IP_DEVICE match]} {
        return 1
    } else {
        return 0
    }
}

proc devics_info_ef3l15_25_45 { } {
    global IP_DEVICE
    if {[regexp -nocase {(EF3L15CG256B)} $IP_DEVICE match]} {
        return 1
    } else {
        return 0
    }
}

proc ram_piritive { eram dram uram eram_9k eram_9k_fast eram_20k eram_20k_fast eram_32k auto} {
    set ram_switch $eram$dram$uram
    switch $ram_switch {
        "100" {
            if {$eram_9k == 1} {
                return 2                
            } elseif {$eram_9k_fast == 1} {
                return 4  
            } elseif {$eram_20k == 1} {
                return 0  
            } elseif {$eram_20k_fast == 1} {
                return 1  
            } elseif {$eram_32k == 1} {
                return 3  
            } elseif {$auto == 1} {
                return 0  
            } 
        }
        "010" {
            return 5
        }
        "001" {
            return 6
        }
        default { 
            return 0 
        }
    }
}
   
proc rst_type { Reset_Type } {
    switch $Reset_Type {
        "ASYNC Reset" {
            return 1
        }
        "SYNC Reset" {
            return 2
        }
        "ASYNC Reset SYNC Release" {
            return 1
        }
        "No Reset" {
            return 0
        }
        default { 
            return 0 
        }
    }
}

proc wrusedw_width { showahead write_width read_width async} {
    if { $showahead == 1 } {
        set usedw_width [expr $write_width + 1]
    } else {
        if {$async == 0} {
            set usedw_width [expr $write_width + 1]
        } else {
            set usedw_width $write_width
        }
    }
    return $usedw_width
}

proc rdusedw_width { showahead write_width read_width async} {
    if { $showahead == 1 } {
        set usedw_width [expr $read_width + 1]
    } else {
        if {$async == 0} {
            set usedw_width [expr $read_width + 1]
        } else {
            set usedw_width $read_width
        }
    }
    return $usedw_width
}

proc dout_initval { read_width reset_value reset_type} {
    global IP_GEN_PARAM_ERROR_FLAG
    global IP_GEN_PARAM_ERROR_MSG
    set IP_GEN_PARAM_ERROR_FLAG 0
    set IP_GEN_PARAM_ERROR_MSG ""
    set hex_chars {0 1 2 3 4 5 6 7 8 9 a b c d e f A B C D E F}
    for {set i 0} {$i < [string length $reset_value]} {incr i} {
        set char [string index $reset_value $i]
        if {[lsearch -exact $hex_chars $char] < 0} {
            set IP_GEN_PARAM_ERROR_FLAG 1
            set IP_GEN_PARAM_ERROR_MSG "Please ensure that the Dout Reset Value(hex) you input only contains hexadecimal characters."
        }
    }
    if {$reset_type == "No Reset"} {
        return "$read_width\'h0"
    }
    set dout "$read_width\'h$reset_value"
    return $dout
}


proc rst_type_proc {async} {
    if {$async} {
        set list_rst [list "ASYNC Reset" "ASYNC Reset SYNC Release" "No Reset"]
    } else {
        set list_rst [list "SYNC Reset"  "ASYNC Reset SYNC Release" "No Reset"]
    }
}