reg [220:0] metadata_drive=0;reg [43:0] magnitude_drive=0;
integer predicates=0,frames=0,completions=0,errors=0;
task tick;begin @(posedge clk);#2;@(negedge clk);end endtask
task reset_case;begin rst_n=0;repeat(4)tick();rst_n=1;repeat(3)tick();end endtask
always @(posedge clk)if(rst_n)begin
    if(frame_complete)completions=completions+1;
    if(frame_error)errors=errors+1;
end
task algebra;
    reg [10:0] history;integer h,m,k;
    begin
        force device.dut.pyramid.full_event_valid=0;force device.baseline.pyramid.full_event_valid=0;
        force device.dut.pyramid.low_event_valid=0;force device.baseline.pyramid.low_event_valid=0;
        force device.dut.pyramid.full_event_metadata=metadata_drive;force device.baseline.pyramid.full_event_metadata=metadata_drive;
        force device.dut.pyramid.low_event_metadata=metadata_drive;force device.baseline.pyramid.low_event_metadata=metadata_drive;
        force device.dut.pyramid.full_event_magnitude=magnitude_drive;force device.baseline.pyramid.full_event_magnitude=magnitude_drive;
        force device.dut.pyramid.low_event_magnitude=magnitude_drive;force device.baseline.pyramid.low_event_magnitude=magnitude_drive;
        for(h=0;h<6;h=h+1)for(m=0;m<16;m=m+1)for(k=0;k<16;k=k+1)begin
            history=h==0?0:h==1?1:h==2?40:h==3?1023:h==4?2040:2047;
            metadata_drive=0;metadata_drive[6:3]=4'(m);metadata_drive[60:59]=k[0]?1:2;
            device.dut.pyramid.peak_gradient[0]=history;device.baseline.pyramid.peak_gradient[0]=history;
            device.dut.pyramid.peak_gradient[1]=history;device.baseline.pyramid.peak_gradient[1]=history;
            device.dut.pyramid.peak_gradient[2]=history;device.baseline.pyramid.peak_gradient[2]=history;
            for(integer lane=0;lane<4;lane=lane+1)
                magnitude_drive[lane*11+:11]=k<2?0:k<4?history:11'((k*317+lane*503)%2048);
            #1;
            if((|device.dut.pyramid.full_peak_exceeds)!==
                (device.baseline.pyramid.full_summary[36:26]>device.baseline.pyramid.peak_gradient[0]) ||
               (|device.dut.pyramid.low_peak_exceeds)!==
                (device.baseline.pyramid.low_summary[36:26]>device.baseline.pyramid.peak_gradient[metadata_drive[60:59]]))
                $fatal(1,"R3 F22 CE predicate mismatch");
            if(device.dut.pyramid.full_summary!==device.baseline.pyramid.full_summary ||
               device.dut.pyramid.low_summary!==device.baseline.pyramid.low_summary)
                $fatal(1,"R3 F22 winner data tree changed");
            predicates=predicates+1;
        end
        release device.dut.pyramid.full_event_valid;release device.baseline.pyramid.full_event_valid;
        release device.dut.pyramid.low_event_valid;release device.baseline.pyramid.low_event_valid;
        release device.dut.pyramid.full_event_metadata;release device.baseline.pyramid.full_event_metadata;
        release device.dut.pyramid.low_event_metadata;release device.baseline.pyramid.low_event_metadata;
        release device.dut.pyramid.full_event_magnitude;release device.baseline.pyramid.full_event_magnitude;
        release device.dut.pyramid.low_event_magnitude;release device.baseline.pyramid.low_event_magnitude;
        reset_case();
    end
endtask
task frame_case(input integer number,input integer kind);
    integer guard,total,x,y;reg sent;
    begin
        cfg_context=number;cfg_width=32;cfg_height=32;cfg_gray=0;cfg_color_filter=0;
        cfg_multiscale=1;cfg_lane=1;cfg_threshold=0;cfg_gx_min=1;cfg_ratio=3;cfg_sign=0;
        cfg_min_count=1;cfg_min_strips=1;cfg_left=0;
        for(integer s=0;s<4;s=s+1)begin
            cfg_y_begin[s*13+:13]=13'(s*2);cfg_y_end[s*13+:13]=13'((s+1)*2);
            cfg_split[s*13+:13]=4;cfg_right[s*13+:13]=8;
        end
        wait(start_ready);start_valid=1;tick();start_valid=0;
        total=kind==3||kind==4?70:256;
        for(integer n=0;n<total;n=n+1)begin
            x=(n%8)*4;y=n/8;
            for(integer lane=0;lane<4;lane=lane+1)begin
                s_y[lane*8+:8]=kind==0?0:kind==1?8'(3*(x+lane)+2*y):8'(((x+lane)/2+y/3)%2?255:0);
                s_rgb[lane*24+:24]={3{s_y[lane*8+:8]}};
            end
            s_valid=1;s_sof=n==0;s_eol=n%8==7;sent=0;
            while(!sent)begin @(posedge clk);if(s_ready)sent=1;@(negedge clk);end
        end
        s_valid=0;s_sof=0;s_eol=0;
        if(kind==3)begin cancel=1;tick();cancel=0;end
        if(kind==4)begin source_error=1;tick();source_error=0;end
        guard=0;while(busy&&guard<20000)begin tick();guard=guard+1;end
        if(guard==20000)$fatal(1,"R3 filter frame did not finish");
        frames=frames+1;repeat(3)tick();
    end
endtask
initial begin
    m_ready=1;pyramid_ready=0;lane_ready=0;reset_case();algebra();
    frame_case(1,0);frame_case(2,1);
    if(pyramid_drops==0||lane_drops==0)$fatal(1,"R3 publication stall/drop was not exercised");
    pyramid_ready=1;lane_ready=1;repeat(8)tick();
    frame_case(3,2);frame_case(4,3);frame_case(5,4);frame_case(6,1);
    if(completions<3||errors<1)$fatal(1,"R3 terminal success/error coverage");
    $display("RESULT: PASS R3_F22_F23 predicates=%0d frames=%0d success=%0d errors=%0d cycles=%0d",
        predicates,frames,completions,errors,device.r3_checks);$finish;
end
initial begin #1000000;$fatal(1,"R3 filter watchdog");end
