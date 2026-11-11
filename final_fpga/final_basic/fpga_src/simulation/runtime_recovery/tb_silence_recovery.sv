`timescale 1ns/1ps
module @TOP@;
    localparam integer LIMIT=@LIMIT@,DEFAULT_CASE=@DEFAULT@;
    reg clk=0,rst_n=0;
    always #4 clk=~clk;
    wire raw_valid,raw_ready,receive_fault,phy_ready,parser_fault;
    wire event_valid,event_identity_valid,config_done,delay_ready,mode_running,hdr_mode,pipeline_abort;
    wire [1:0] event_kind;
    wire quarantine;
    reg recovery_quiet=1;
    integer checks=0,pulses=0,stage=0;
    time silence_start,first_fault;
    @CAMERA@
    // Actual top reset predicate: this guard protects SDR, and is held reset
    // during HDR mode. This simulation deliberately selects SDR.
    production_source_identity_guard guard(.clk(clk),.rst_n(rst_n&&mode_running&&!hdr_mode),
        .phy_ready(phy_ready),.receive_fault(receive_fault),.parser_identity_fault(parser_fault),
        .i_recovery_quiet(recovery_quiet),
        .event_valid(event_valid),.event_kind(event_kind),.event_identity_valid(event_identity_valid),.quarantine(quarantine));
    always @(posedge receive_fault)begin if(pulses==0)first_fault=$time;pulses=pulses+1;end
    task check(input bit okay,input string why);
        begin checks=checks+1;if(!okay)$fatal(1,"@TOP@ stage=%0d %s count=%0d fault=%b quarantine=%b",stage,why,camera.silence_count,receive_fault,quarantine);end
    endtask
    task recover_boundary;
        begin
            recovery_quiet=0;good_fs();repeat(3)@(negedge clk);
            check(quarantine,"healthy FS cannot clear quarantine before owner quiet");
            recovery_quiet=1;good_fs();repeat(3)@(negedge clk);
            check(!quarantine,"consumed healthy FS clears only after owner quiet");
        end
    endtask
    task set_raw(input bit value);
        begin @(negedge clk);camera.u_receiver.tb_raw_valid=value;end
    endtask
    task good_fs;
        begin
            @(negedge clk);camera.u_receiver.tb_event_valid=1;camera.u_receiver.tb_event_kind=0;
            camera.u_receiver.tb_identity_valid=1;camera.u_receiver.tb_raw_valid=1;camera.u_receiver.tb_sof=1;
            @(negedge clk);camera.u_receiver.tb_event_valid=0;camera.u_receiver.tb_sof=0;
        end
    endtask
    initial begin
        stage=1;repeat(4)@(negedge clk);rst_n=1;
        repeat(40)@(negedge clk);
        check(mode_running&&!hdr_mode&&!quarantine,"SDR source cohort released before identity");
        check(!config_done&&!delay_ready&&camera.silence_count==0,"sensor configuration gates watchdog");
        camera.u_config.tb_done=1;
        repeat(DEFAULT_CASE?16:96)@(negedge clk);
        check(config_done&&!delay_ready&&!receive_fault&&pulses==0&&camera.silence_count==0,
            "calibration not ready prevents silence timeout, beyond reduced threshold");
        camera.u_receiver.tb_delay_ready=1;camera.u_receiver.tb_raw_valid=1;
        repeat(8)@(negedge clk);good_fs();
        check(guard.cohort_started&&!quarantine,"healthy identity-bearing FS establishes continuity");
        stage=2;
        if(!DEFAULT_CASE)begin
            // Exactly LIMIT-1 empty clocks: a beat before the threshold resets
            // the real counter and does not poison continuity.
            set_raw(0);#((LIMIT-1)*8);
            check(!receive_fault&&pulses==0&&camera.silence_count==LIMIT-1,"subthreshold gap remains recoverable");
            camera.u_receiver.tb_raw_valid=1;
            @(posedge clk);#1;check(camera.silence_count==0&&!quarantine,"returning valid clears subthreshold silence");
            // Valid held under backpressure is activity even without transfers.
            camera.u_pipeline.tb_ready=0;
            #(8*(LIMIT+17));
            check(raw_valid&&!raw_ready&&camera.silence_count==0&&pulses==0&&!quarantine,
                "valid under backpressure is not silence");
            camera.u_pipeline.tb_ready=1;
        end
        stage=3;set_raw(0);silence_start=$time;
        #((LIMIT-1)*8);
        check(camera.silence_count==LIMIT-1&&pulses==0&&!receive_fault&&!quarantine,
            "no timeout until threshold edge");
        @(posedge clk);#1;
        check(receive_fault&&pulses==1&&camera.silence_reported&&pipeline_abort,
            "exact threshold emits receive-fault abort pulse from real wrapper");
        check(!quarantine,"guard observes registered fault on following edge");
        @(posedge clk);#1;
        check(!receive_fault&&quarantine&&pulses==1,"one-cycle receive fault causes persistent SDR quarantine");
        // Keep silence longer; reported latch prevents repeated abort pulses.
        repeat(12)@(negedge clk);
        check(pulses==1&&!receive_fault&&quarantine,"continued silence emits one abort only");
        stage=4;recover_boundary();
        check(raw_valid&&raw_ready&&camera.silence_count==0&&!receive_fault&&!quarantine,
            "activity plus quiet healthy FS recovers the live SDR cohort");
        if(!DEFAULT_CASE)begin
            // A fresh inactivity episode re-arms without a cohort reset.
            set_raw(0);#(LIMIT*8);#1;
            check(pulses==2&&receive_fault,"second silence episode re-arms one-shot watchdog");
            @(negedge clk);set_raw(1);repeat(3)@(negedge clk);
            check(quarantine,"second silence fault quarantines the same cohort");recover_boundary();
            // The actual wrapper edge detector must re-arm when parser loss
            // clears at its recovery FS; a held fault emits one pulse only.
            for(integer episode=0;episode<2;episode=episode+1)begin
                @(negedge clk);camera.u_receiver.tb_parser_fault=1;
                repeat(5)@(negedge clk);
                check(quarantine&&pulses==3+episode,"repeated parser loss emits exactly one abort per rising edge");
                camera.u_receiver.tb_parser_fault=0;repeat(3)@(negedge clk);recover_boundary();
            end
            for(integer episode=0;episode<2;episode=episode+1)begin
                @(negedge clk);camera.u_receiver.tb_phy_ready=0;
                repeat(5)@(negedge clk);
                check(quarantine&&pulses==5+episode,"repeated PHY short loss emits one abort per falling edge");
                camera.u_receiver.tb_phy_ready=1;repeat(3)@(negedge clk);recover_boundary();
            end
            check(pulses==6&&!quarantine,"two silence two parser and two PHY episodes recover without reset");
        end
        $display("RESULT: PASS @TOP@ checks=%0d threshold=%0d first_episode_fault_edge_ns=%0d quiet_start_ns=%0d pulses=%0d quarantine=%b",checks,LIMIT,first_fault,silence_start,pulses,quarantine);$finish;
    end
    initial begin #(8*(LIMIT+10000));$fatal(1,"@TOP@ watchdog stage=%0d",stage);end
endmodule
