# The Command Lines that defined the layout and widget properties.

set Tab_Tab_0 [add_tab -name {Tab_0} -col_count {2}]

set Group_Box_RAM_Option [add_group -parent {Tab_0} -name {RAM Option} -col_count {2} -page_name {Basic}]

set Radio_Button_ERAM [add_param -parent {RAM Option} -name {ERAM} -widget {Radio Button}]
set_widget_prop -widget_id $Radio_Button_ERAM -prop {ButtonGroup} -value {RAM Option}
set_widget_prop -widget_id $Radio_Button_ERAM -prop {Display Name} -value {ERAM}

set Radio_Button_DRAM [add_param -parent {RAM Option} -name {DRAM} -widget {Radio Button}]
set_widget_prop -widget_id $Radio_Button_DRAM -prop {ButtonGroup} -value {RAM Option}
set_widget_prop -widget_id $Radio_Button_DRAM -prop {Display Name} -value {DRAM}

set Radio_Button_URAM [add_param -parent {RAM Option} -name {URAM} -widget {Radio Button}]
set_widget_prop -widget_id $Radio_Button_URAM -prop {ButtonGroup} -value {RAM Option}
set_widget_prop -widget_id $Radio_Button_URAM -prop {Display Name} -value {ERAM_144K}

set Group_Box_Implement_Option [add_group -parent {Tab_0} -name {Implement Option} -col_count {2}]

set Radio_Button_EMB9K_Area_Opt [add_param -parent {Implement Option} -name {EMB9K_Area_Opt} -widget {Radio Button}]
set_widget_prop -widget_id $Radio_Button_EMB9K_Area_Opt -prop {ButtonGroup} -value {Implement Option}
set_widget_prop -widget_id $Radio_Button_EMB9K_Area_Opt -prop {Display Name} -value {EMB9K(Area Opt)}

set Radio_Button_EMB9K_Timing_Opt [add_param -parent {Implement Option} -name {EMB9K_Timing_Opt} -widget {Radio Button}]
set_widget_prop -widget_id $Radio_Button_EMB9K_Timing_Opt -prop {ButtonGroup} -value {Implement Option}
set_widget_prop -widget_id $Radio_Button_EMB9K_Timing_Opt -prop {Display Name} -value {EMB9K(Timing Opt)}

set Radio_Button_EMB32K [add_param -parent {Implement Option} -name {EMB32K} -widget {Radio Button}]
set_widget_prop -widget_id $Radio_Button_EMB32K -prop {ButtonGroup} -value {Implement Option}
set_widget_prop -widget_id $Radio_Button_EMB32K -prop {Display Name} -value {EMB32K}

set Radio_Button_Auto [add_param -parent {Implement Option} -name {Auto} -widget {Radio Button}]
set_widget_prop -widget_id $Radio_Button_Auto -prop {ButtonGroup} -value {Implement Option}
set_widget_prop -widget_id $Radio_Button_Auto -prop {Display Name} -value {Auto}

set Radio_Button_EMB20K_Area_Opt [add_param -parent {Implement Option} -name {EMB20K_Area_Opt} -widget {Radio Button}]
set_widget_prop -widget_id $Radio_Button_EMB20K_Area_Opt -prop {ButtonGroup} -value {Implement Option}
set_widget_prop -widget_id $Radio_Button_EMB20K_Area_Opt -prop {Display Name} -value {EMB20K(Area Opt)}

set Radio_Button_EMB20K_Timing_Opt [add_param -parent {Implement Option} -name {EMB20K_Timing_Opt} -widget {Radio Button}]
set_widget_prop -widget_id $Radio_Button_EMB20K_Timing_Opt -prop {ButtonGroup} -value {Implement Option}
set_widget_prop -widget_id $Radio_Button_EMB20K_Timing_Opt -prop {Display Name} -value {EMB20K(Timing Opt)}

set Group_Box_Clock_Mode [add_group -parent {Tab_0} -name {Clock Mode} -col_count {2}]

set Radio_Button_ASYNC [add_param -parent {Clock Mode} -name {ASYNC} -widget {Radio Button}]
set_widget_prop -widget_id $Radio_Button_ASYNC -prop {ButtonGroup} -value {Clock Mode}
set_widget_prop -widget_id $Radio_Button_ASYNC -prop {Display Name} -value {ASYNC}

set Radio_Button_SYNC [add_param -parent {Clock Mode} -name {SYNC} -widget {Radio Button}]
set_widget_prop -widget_id $Radio_Button_SYNC -prop {ButtonGroup} -value {Clock Mode}
set_widget_prop -widget_id $Radio_Button_SYNC -prop {Display Name} -value {SYNC}

set Group_Box_Addr_Domain_Across_Control [add_group -parent {Tab_0} -name {Addr Domain Across Control} -col_count {2}]

set Combo_Box_Sync_Stages [add_param -parent {Addr Domain Across Control} -name {Sync_Stages} -widget {Combo Box}]
set_widget_prop -widget_id $Combo_Box_Sync_Stages -prop {Display Name} -value {Synchronization Stages}

set Group_Box_Data_Port_Option [add_group -parent {Tab_0} -name {Data Port Option} -col_count {2} -page_name {Local Ports}]

set Spin_Box_Write_Width [add_param -parent {Data Port Option} -name {Write_Width} -widget {Spin Box}]
set_widget_prop -widget_id $Spin_Box_Write_Width -prop {Display Name} -value {Write Width}

set Combo_Box_Read_Width [add_param -parent {Data Port Option} -name {Read_Width} -widget {Combo Box}]
set_widget_prop -widget_id $Combo_Box_Read_Width -prop {Display Name} -value {Read Width}

set Text_Write_Width_Range [add_param -parent {Data Port Option} -name {Write_Width_Range} -widget {Text}]
set_widget_prop -widget_id $Text_Write_Width_Range -prop {Display Name} -value {Write Width Range}

set Text_Read_Width_Range [add_param -parent {Data Port Option} -name {Read_Width_Range} -widget {Text}]
set_widget_prop -widget_id $Text_Read_Width_Range -prop {Display Name} -value {Read Width Range}

set Combo_Box_Write_Depth [add_param -parent {Data Port Option} -name {Write_Depth} -widget {Combo Box}]
set_widget_prop -widget_id $Combo_Box_Write_Depth -prop {Display Name} -value {Write Depth}

set Text_Read_Depth [add_param -parent {Data Port Option} -name {Read_Depth} -widget {Text}]
set_widget_prop -widget_id $Text_Read_Depth -prop {Display Name} -value {Read Depth}

set Group_Box_Show_Ahead_Option [add_group -parent {Tab_0} -name {Show Ahead Option} -col_count {2}]

set Radio_Button_Show_Ahead_Enable [add_param -parent {Show Ahead Option} -name {Show_Ahead_Enable} -widget {Radio Button}]
set_widget_prop -widget_id $Radio_Button_Show_Ahead_Enable -prop {ButtonGroup} -value {showahead}
set_widget_prop -widget_id $Radio_Button_Show_Ahead_Enable -prop {Display Name} -value {Enable}

set Radio_Button_Show_Ahead_Disable [add_param -parent {Show Ahead Option} -name {Show_Ahead_Disable} -widget {Radio Button}]
set_widget_prop -widget_id $Radio_Button_Show_Ahead_Disable -prop {ButtonGroup} -value {showahead}
set_widget_prop -widget_id $Radio_Button_Show_Ahead_Disable -prop {Display Name} -value {Disable}

set Group_Box_Out_Reg [add_group -parent {Tab_0} -name {Out Reg} -col_count {2}]

set Radio_Button_Out_Reg_Enable [add_param -parent {Out Reg} -name {Out_Reg_Enable} -widget {Radio Button}]
set_widget_prop -widget_id $Radio_Button_Out_Reg_Enable -prop {ButtonGroup} -value {OutReg}
set_widget_prop -widget_id $Radio_Button_Out_Reg_Enable -prop {Display Name} -value {Enable}

set Radio_Button_Out_Reg_Disable [add_param -parent {Out Reg} -name {Out_Reg_Disable} -widget {Radio Button}]
set_widget_prop -widget_id $Radio_Button_Out_Reg_Disable -prop {ButtonGroup} -value {OutReg}
set_widget_prop -widget_id $Radio_Button_Out_Reg_Disable -prop {Display Name} -value {Disable}

set Group_Box_Almost_num [add_group -parent {Tab_0} -name {Almost num} -col_count {2}]

set Line_Edit_Almost_Full_Num [add_param -parent {Almost num} -name {Almost_Full_Num} -widget {Line Edit}]
set_widget_prop -widget_id $Line_Edit_Almost_Full_Num -prop {Display Name} -value {Almost Full Num}

set Text_Almost_Full_Num_Range [add_param -parent {Almost num} -name {Almost_Full_Num_Range} -widget {Text}]
set_widget_prop -widget_id $Text_Almost_Full_Num_Range -prop {Display Name} -value {Almost Full Num Range}

set Line_Edit_Almost_Empty_Num [add_param -parent {Almost num} -name {Almost_Empty_Num} -widget {Line Edit}]
set_widget_prop -widget_id $Line_Edit_Almost_Empty_Num -prop {Display Name} -value {Almost Empty Num}

set Text_Almost_Empty_Num_Range [add_param -parent {Almost num} -name {Almost_Empty_Num_Range} -widget {Text}]
set_widget_prop -widget_id $Text_Almost_Empty_Num_Range -prop {Display Name} -value {Almost Empty Num Range}

set Group_Box_Reset_Option [add_group -parent {Tab_0} -name {Reset Option} -col_count {2}]

set Combo_Box_Reset_Type [add_param -parent {Reset Option} -name {Reset_Type} -widget {Combo Box}]
set_widget_prop -widget_id $Combo_Box_Reset_Type -prop {Display Name} -value {Reset Type}

set Line_Edit_Dout_Reset_Value [add_param -parent {Reset Option} -name {Dout_Reset_Value} -widget {Line Edit} -new_row {Y}]
set_widget_prop -widget_id $Line_Edit_Dout_Reset_Value -prop {Display Name} -value {Dout Reset Value(hex)}

set Line_Edit_SF2 [add_param -parent {} -name {SF2} -widget {Line Edit}]

set Line_Edit_RST_TYPE [add_param -parent {} -name {RST_TYPE} -widget {Line Edit}]

set Line_Edit_COMMON_CLK_EN [add_param -parent {} -name {COMMON_CLK_EN} -widget {Line Edit}]

set Line_Edit_EF3 [add_param -parent {} -name {EF3} -widget {Line Edit}]

set Line_Edit_WRUSEDW_WIDTH [add_param -parent {} -name {WRUSEDW_WIDTH} -widget {Line Edit}]

set Line_Edit_PH1 [add_param -parent {} -name {PH1} -widget {Line Edit}]

set Line_Edit_ADDR_WIDTH_R [add_param -parent {} -name {ADDR_WIDTH_R} -widget {Line Edit}]

set Line_Edit_DATA_WIDTH_W [add_param -parent {} -name {DATA_WIDTH_W} -widget {Line Edit}]

set Line_Edit_DOUT_INITVAL [add_param -parent {} -name {DOUT_INITVAL} -widget {Line Edit}]

set Line_Edit_EF4 [add_param -parent {} -name {EF4} -widget {Line Edit}]

set Line_Edit_EF5 [add_param -parent {} -name {EF5} -widget {Line Edit}]

set Line_Edit_SF1 [add_param -parent {} -name {SF1} -widget {Line Edit}]

set Line_Edit_AL_EMPTY_NUM [add_param -parent {} -name {AL_EMPTY_NUM} -widget {Line Edit}]

set Line_Edit_MEMORY_TYPE [add_param -parent {} -name {MEMORY_TYPE} -widget {Line Edit}]

set Line_Edit_EG4 [add_param -parent {} -name {EG4} -widget {Line Edit}]

set Line_Edit_EF2 [add_param -parent {} -name {EF2} -widget {Line Edit}]

set Line_Edit_DATA_WIDTH_R [add_param -parent {} -name {DATA_WIDTH_R} -widget {Line Edit}]

set Line_Edit_PH2 [add_param -parent {} -name {PH2} -widget {Line Edit}]

set Line_Edit_SHOW_AHEAD_EN [add_param -parent {} -name {SHOW_AHEAD_EN} -widget {Line Edit}]

set Line_Edit_ASYNC_RST_SYNC_RELS [add_param -parent {} -name {ASYNC_RST_SYNC_RELS} -widget {Line Edit}]

set Line_Edit_DR1 [add_param -parent {} -name {DR1} -widget {Line Edit}]

set Line_Edit_AL_FULL_NUM [add_param -parent {} -name {AL_FULL_NUM} -widget {Line Edit}]

set Line_Edit_OUTREG_EN [add_param -parent {} -name {OUTREG_EN} -widget {Line Edit}]

set Line_Edit_RDUSEDW_WIDTH [add_param -parent {} -name {RDUSEDW_WIDTH} -widget {Line Edit}]

set Line_Edit_EF3L15_25_45 [add_param -parent {} -name {EF3L15_25_45} -widget {Line Edit}]

set Line_Edit_SYNC_STAGE [add_param -parent {} -name {SYNC_STAGE} -widget {Line Edit}]

set Line_Edit_ADDR_WIDTH_W [add_param -parent {} -name {ADDR_WIDTH_W} -widget {Line Edit}]