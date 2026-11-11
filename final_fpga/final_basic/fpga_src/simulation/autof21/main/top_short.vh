// Actual TOP fixture: only ordinary native BAR CFG and CSI electrical-boundary
// inputs are driven. No ALGO command, internal completion or reset is forced.
integer autof21_lut_commands=0,autof21_cold_resets=0;
always @(posedge dut.pixel_clk)if(dut.pixel_rst_n)begin
    if(dut.f21_cfg_begin_valid||dut.f21_cfg_valid||dut.f21_cfg_commit_valid)
        autof21_lut_commands++;
    if(dut.start_valid&&dut.start_ready)begin
        check(dut.f21_owned_lut_valid&&dut.f21_owned_lut_generation==1,
            "automatic fixed G1 is ready before genuine frame START");
        check(algo_bar_writes==0&&autof21_lut_commands==0,
            "ordinary CFG to START requires zero ALGO writes and zero LUT load commands");
    end
end
task autof21_cold_reset;
    integer n;
    begin
        n=0;while(!dut.f21_owned_lut_valid&&n<20000)begin @(negedge dut.pixel_clk);n++;end
        check(n<20000&&dut.f21_owned_lut_generation==1,"cold boot automatically exposes fixed ROM G1");
        pcie_mperst=0;`R8_EP.link_up=0;
        repeat(30)@(negedge sys_clk);
        check(!dut.pixel_rst_n&&!dut.f21_lut_valid,"real host PERST asserts application and F21 cold reset");
        pcie_mperst=1;`R8_EP.link_up=1;
        wait(!dut.debug_local&&dut.debug_app_rst_n&&dut.session_rearm_ready&&dut.cfg_user_initialized);
        n=0;while(!dut.f21_owned_lut_valid&&n<20000)begin @(negedge dut.pixel_clk);n++;end
        check(n<20000&&dut.f21_owned_lut_generation==1&&algo_bar_writes==0,
            "after real cold reset fixed G1 returns without host algorithm initialization");
        autof21_cold_resets++;
        $display("AUTOF21_COLD_RESET PASS resets=%0d generation=%0d algo_writes=%0d",autof21_cold_resets,dut.f21_owned_lut_generation,algo_bar_writes);
    end
endtask
task autof21_probe_generations;
    reg [1023:0] extension;
    integer n,callbacks_before;
    begin
        callbacks_before=cfg_callbacks;
        extension=0;extension[7:0]=2;extension[15:10]=2;
        write_bar(`PCIE_REG_CFG_HOST_CAPABILITIES,1);
        write_bar(`PCIE_REG_CFG_REQUEST_SESSION,expected_session);
        write_bar(`PCIE_REG_CFG_REQUEST_MODE,0);write_bar(`PCIE_REG_CFG_REQUEST_QUALITY,75);
        write_bar(`PCIE_REG_CFG_REQUEST_FLAGS,0);write_bar(`PCIE_REG_CFG_REQUEST_MIN_QUALITY,1);
        write_bar(`PCIE_REG_CFG_REQUEST_FRAME_BUDGET,0);write_bar(`PCIE_REG_CFG_REQUEST_RESTART_MCUS,0);
        for(integer generation=1;generation<=2;generation++)begin
            extension[`PCIE_CFG_EXT_OFFSET_DEHAZE_LUT_GENERATION+:32]=generation;
            write_bar(`PCIE_REG_CFG_REQUEST_SEQUENCE,80+generation);
            for(integer k=0;k<32;k++)write_bar(`PCIE_REG_CFG_EXT_SHADOW_BASE+4*k,extension[k*32+:32]);
            write_bar(`PCIE_REG_CFG_COMMAND,`PCIE_CFG_COMMAND_PREPARE_EXT);n=0;
            do begin read_bar(`PCIE_REG_CFG_STATUS,config_value);n++;end
            while(!config_value[`PCIE_CFG_STATUS_READY]&&!config_value[`PCIE_CFG_STATUS_ERROR]&&n<3000);
            check(n<3000&&cfg_callbacks==callbacks_before,"generation probe cannot fabricate capture callback");
            if(generation==1)begin
                check(config_value[`PCIE_CFG_STATUS_READY]&&!config_value[`PCIE_CFG_STATUS_ERROR],"explicit fixed G1 ordinary CFG accepted");
                write_bar(`PCIE_REG_CFG_COMMAND,`PCIE_CFG_COMMAND_CANCEL);
                n=0;do begin read_bar(`PCIE_REG_CFG_STATUS,config_value);n++;end
                while(config_value[`PCIE_CFG_STATUS_BUSY]&&n<3000);
                check(n<3000&&!config_value[`PCIE_CFG_STATUS_ERROR],"G1 PREPARE cancel releases prepared work");
            end else begin
                check(config_value[`PCIE_CFG_STATUS_ERROR]&&!config_value[`PCIE_CFG_STATUS_READY],"ordinary CFG rejects unavailable nonzero G2");
            end
        end
        $display("AUTOF21_GENERATION_PROBE PASS explicit_g1=accepted g2=rejected callbacks=0");
    end
endtask
task autof21_run_short;
    begin
        rr_partial_fd=$fopen("runtime_partial_pixels.txt","w");rr_active=1;
        rr_fail_owned_frame(1);rr_discard_boundary();
        check(cfg_applies==1,"G0 dehaze ON becomes APPLIED only on actual SOURCE1 acceptance");
        configure_sdr_v2(0,101);
        rr_fail_owned_frame(3);rr_discard_boundary();
        check(cfg_applies==2,"dehaze OFF becomes APPLIED only on actual SOURCE3 acceptance");
        configure_sdr_v2(2,102);
        scenario_enables=2;
        rr_wait_source();rr_partial=1;sensor_event(0,1,0);
        for(integer row=0;row<32;row++)csi_line(row,0);
        check(rr_clears==2&&starts==3&&dut.job_sequence==5,"re-enabled dehaze recovers actual processed SOF of SOURCE5");
        check(cfg_applies==3&&dut.capture0_active_config[175:170]==2&&
            dut.capture0_active_config[160+`PCIE_CFG_EXT_OFFSET_DEHAZE_LUT_GENERATION+:32]==0,
            "ordinary G0 ON/OFF/ON preserves raw shadow identity and three real APPLIED boundaries");
        check(dut.capture0_algorithm_extension[`PCIE_CFG_EXT_OFFSET_DEHAZE_LUT_GENERATION+:32]==1&&
            dut.dfi_algorithm_extension[`PCIE_CFG_EXT_OFFSET_DEHAZE_LUT_GENERATION+:32]==1,
            "raw G0 ordinary CFG normalizes to effective fixed G1 in both actual algorithm domains");
        runtime_recovery_finish(1);
        check(algo_bar_writes==0&&autof21_lut_commands==0&&autof21_cold_resets==1&&
            dut.f21_owned_lut_valid&&dut.f21_owned_lut_generation==1,"short TOP auto initialization final invariant");
        $display("AUTOF21_TOP_SHORT PASS cfg_on_off_on=3 applied=3 cold_reset=1 source_bad=2 recovered=5 algo_writes=0 lut_commands=0 generation=1");
        done_o=1;
    end
endtask
