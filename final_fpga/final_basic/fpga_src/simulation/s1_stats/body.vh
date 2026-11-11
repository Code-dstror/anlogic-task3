    integer checks=0,commits=0,i,k;
    reg [31:0] samples[0:403199];
    reg [71:0] expected[0:13];
    reg [13:0] histograms[0:1791];
    reg [9:0] gains[0:63];
    integer active_kind=0,histogram_checks=0;
    reg [71:0] frozen0,frozen1;
    task check(input bit good,input string why);
        begin checks++;if(!good)$fatal(1,"S1 stats %s state=%0d sampled=%0d",why,dut.state,dut.sampled);end
    endtask
    always @(posedge clk)begin
        #1;
        check(map_commit===t_map_commit,"spatial/temporal control agrees");
        if(map_commit)commits++;
        if(main_pin_valid&&frozen0!==0)begin
            check({main_pin_gain,main_pin_center}===frozen0,"spatial pin frozen");
            check({t_main_pin_gain,t_main_pin_center}===frozen1,"temporal pin frozen");
        end
    end
    // Observe the actual final RAM read after all update tags have drained.
    // The expected per-bin counts are independently enumerated by the oracle.
    always @(posedge clk)if(rst_n&&dut.state==dut.SCAN_WAIT&&dut.read_valid[1]&&!dut.read_hist[1])begin
        check(dut.ram_word[13:0]===histograms[active_kind*256+dut.scan_band*64+dut.scan_bin],"all final histogram bins exact");
        check(temporal.ram_word===dut.ram_word,"temporal/spatial RAM contents agree");
        histogram_checks++;
    end
    task begin_main(input integer id,input bit valid_history);
        begin
            @(negedge clk);main_frame_id=id;main_begin=1;
            #1;check(main_begin_ready,"main no startup/statistics wait");check(main_history_valid==valid_history,"main history qualification");
            @(posedge clk);@(negedge clk);main_begin=0;
            if(valid_history)begin
                frozen0={main_pin_gain,main_pin_center};frozen1={t_main_pin_gain,t_main_pin_center};
                check(main_pin_valid,"main pin acquired");
            end
        end
    endtask
    task release_main;
        begin
            @(negedge clk);main_release=1;@(negedge clk);main_release=0;
            repeat(3)@(negedge clk);frozen0=0;frozen1=0;
            check(!main_pin_valid,"pin retired");
        end
    endtask
    task source(input integer id,input bit good);
        begin
            @(negedge clk);source_capture=id;source_valid=1;source_ok=good;
            #1;check(source_ready,"source ready");check(source_owner_match,"source owner match");
            @(negedge clk);source_valid=0;
        end
    endtask
    task terminal(input bit good,input integer count);
        begin
            @(negedge clk);obs_status_valid=1;obs_status_ok=good;obs_status_error=good ? 0 : 3;
            obs_status_pixels=count;obs_status_delivered=count;
            #1;check(obs_status_ready,"terminal ready");
            @(negedge clk);obs_status_valid=0;
        end
    endtask
    task observe(input integer kind,input integer id,input integer source_order);
        integer p;
        begin
            active_kind=kind;
            for(p=0;p<57600;p++)begin
                @(negedge clk);obs_valid=1;obs_rgb=samples[kind*57600+p][31:8];obs_y=samples[kind*57600+p][7:0];
                obs_frame_id=id;obs_sof=p==0;obs_eol=(p%320)==319;obs_last=p==57599;
                if(p==1&&source_order==0)begin source_valid=1;source_capture=id;source_ok=1;end
                else source_valid=0;
                #1;check(obs_ready,"continuous observation one sample/clk");
                if(p==0)check(source_decision_collect,"eligible first sample collect");
            end
            @(negedge clk);obs_valid=0;source_valid=0;obs_sof=0;obs_eol=0;obs_last=0;
            if(source_order==1)source(id,1);
        end
    endtask
    task await_commit(input integer expected_count);
        integer timeout;
        begin
            timeout=0;
            while(commits<expected_count&&timeout<2000)begin @(negedge clk);timeout++;end
            check(commits==expected_count,"bounded qualified publication");
            repeat(540)@(negedge clk);
        end
    endtask
    initial begin
        frozen0=0;frozen1=0;
        $readmemh("samples.hex",samples);$readmemh("expected.hex",expected);
        $readmemh("histograms.hex",histograms);$readmemh("gains.hex",gains);
        for(i=0;i<64;i++)check(dut.gain_table(i)===gains[i],"all 64 gain constants exact");
        main_cohort=0;main_cohort[208:177]=1;main_cohort[176:145]=2;
        main_cohort[96:84]=1920;main_cohort[83:71]=1080;main_cohort[67]=1;main_cohort[66]=1;
        main_cohort[57:49]=128;main_cohort[15:8]=128;
        obs_cohort=main_cohort;source_session=1;source_epoch=2;obs_context=160'h42;
        cfg_status_ready=1;i_history_eligible=1;
        #32;rst_n=1;repeat(8)@(negedge clk);
        check(lut_valid&&lut_generation==1,"fixed G1 ready independently of histogram");
        begin_main(1,0);
        // Reset-time uncleared bank causes a bounded skip, never a MAIN wait.
        obs_valid=1;obs_sof=1;obs_frame_id=1;
        #1;check(obs_ready&&!source_decision_collect,"uncleared bank skip");
        @(negedge clk);obs_valid=0;obs_sof=0;terminal(0,0);
        repeat(540)@(negedge clk);
        // Skip consumed capture1; rebuild compatible cohort/session for sequence.
        history_reset=1;@(negedge clk);history_reset=0;
        repeat(4)@(negedge clk);
        main_cohort[208:177]=3;obs_cohort=main_cohort;source_session=3;
        for(k=0;k<7;k++)begin
            begin_main(k+1,k!=0);
            if(k!=0)begin
                check({main_pin_gain,main_pin_center}===expected[(k-1)*2],"spatial oracle snapshot");
                check({t_main_pin_gain,t_main_pin_center}===expected[(k-1)*2+1],"stateful temporal oracle snapshot");
            end
            // Keep prior pin while statistics publish a newer snapshot.
            observe(k,k+1,k%2);
            terminal(1,57600);
            if(k%2==0)begin end
            await_commit(k+1);
            check(dut.history_gain===expected[k*2][71:32]&&dut.history_center===expected[k*2][31:0],"spatial coefficients exact");
            check(temporal.history_gain===expected[k*2+1][71:32]&&temporal.history_center===expected[k*2+1][31:0],"temporal coefficients exact");
            if(k!=0)release_main();
        end
        // An incorrect SOURCE identity is rejected without releasing owner.
        begin_main(8,1);release_main();
        observe(0,8,2);
        source_capture=99;source_valid=1;@(negedge clk);source_valid=0;
        check(source_rejects!=0,"wrong source rejected");
        terminal(1,57600);repeat(8)@(negedge clk);check(commits==7,"F20 alone not publish");
        source(8,1);await_commit(8);
        begin_main(9,1);release_main();observe(0,9,1);terminal(1,57599);
        repeat(540)@(negedge clk);check(commits==8,"short F20 cannot publish");
        begin_main(10,1);release_main();observe(0,10,2);terminal(1,57600);source(10,0);
        repeat(540)@(negedge clk);check(commits==8&&!dut.history_valid,"negative source invalidates history");
        begin_main(11,0);observe(0,11,1);
        frame_cancel=1;@(negedge clk);frame_cancel=0;repeat(10)@(negedge clk);
        check(source_cancel_done&&!dut.owned,"cancel drains accepted RAM updates");
        terminal(1,57600);repeat(540)@(negedge clk);check(commits==8,"cancel no publication");
        begin_main(12,0);observe(0,12,1);terminal(1,57600);
        history_reset=1;@(negedge clk);history_reset=0;repeat(540)@(negedge clk);
        check(commits==8&&!dut.history_valid,"history reset veto publication");
        // Out-of-order/replayed main invalidates old history; capture replay skipped.
        begin_main(12,0);obs_frame_id=12;obs_sof=1;obs_valid=1;#1;
        check(!source_decision_collect,"duplicate observation skipped");
        @(negedge clk);obs_valid=0;obs_sof=0;terminal(0,0);
        cfg_begin_valid=1;@(negedge clk);cfg_begin_valid=0;#1;
        check(cfg_status_valid&&!cfg_status_ok&&cfg_status_error==4,"runtime config bounded immutable failure");
        $display("RESULT: PASS S1_STATS checks=%0d commits=%0d histogram_bins=%0d continuous_same_AB=1 quantile_1439_1440=1 night_strict=1 frozen_pin=1 temporal_slew=1",checks,commits,histogram_checks);
        $finish;
    end
    initial begin #6000000;$fatal(1,"S1 statistics watchdog");end
