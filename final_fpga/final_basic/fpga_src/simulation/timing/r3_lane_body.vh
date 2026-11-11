localparam integer STRIPS=1;
integer vectors=0,frames=0;reg [3:0] mask_drive;
task tick;begin @(posedge clk);#2;@(negedge clk);end endtask
task reset_case;begin rst_n=0;repeat(3)tick();rst_n=1;repeat(2)tick();end endtask
task algebra;
    integer h,m,k,z;reg [10:0] history,value;
    begin
        force device.dut.g_shared[0].accepted=mask_drive;
        force device.baseline.g_shared[0].accepted=mask_drive;
        force device.dut.g_shared[1].accepted=mask_drive;
        force device.baseline.g_shared[1].accepted=mask_drive;
        for(z=0;z<2;z=z+1)for(h=0;h<6;h=h+1)for(m=0;m<16;m=m+1)for(k=0;k<12;k=k+1)begin
            history=h==0?0:h==1?1:h==2?20:h==3?1023:h==4?2040:2047;
            mask_drive=4'(m);
            device.dut.point_count[0]=z;device.baseline.point_count[0]=z;
            device.dut.point_count[1]=z;device.baseline.point_count[1]=z;
            device.dut.peak_strength[0]=history;device.baseline.peak_strength[0]=history;
            device.dut.peak_strength[1]=history;device.baseline.peak_strength[1]=history;
            for(integer lane=0;lane<4;lane=lane+1)begin
                value=k==0?0:k==1?history:k==2?2047:11'((k*331+lane*503)%2048);
                event_magnitude[lane*11+:11]=value;
            end
            #1;
            if(device.dut.g_shared[0].update_peak!==device.baseline.g_shared[0].update_peak ||
               device.dut.g_shared[1].update_peak!==device.baseline.g_shared[1].update_peak)
                $fatal(1,"R3 F23 predicate zero/mask/tie/history mismatch");
            if(device.dut.g_shared[0].vector_peak!==device.baseline.g_shared[0].vector_peak ||
               device.dut.g_shared[0].vector_lane!==device.baseline.g_shared[0].vector_lane)
                $fatal(1,"R3 F23 winner data changed");
            vectors=vectors+1;
        end
        release device.dut.g_shared[0].accepted;release device.baseline.g_shared[0].accepted;
        release device.dut.g_shared[1].accepted;release device.baseline.g_shared[1].accepted;
        reset_case();
    end
endtask
task launch(input integer number);
    begin
        start_context=number;terminal_context=number;start=1;tick();start=0;
    end
endtask
task pixels(input integer groups,input bit zero,input bit wrap);
    integer x,y;reg [10:0] value;
    begin
        if(wrap)begin
            device.dut.point_count[0]=20'hffffc;device.baseline.point_count[0]=20'hffffc;
            device.dut.peak_strength[0]=999;device.baseline.peak_strength[0]=999;
        end
        for(integer n=0;n<groups;n=n+1)begin
            x=(n%2)*4;y=n/2;
            event_metadata={start_context,2'd2,13'd8,13'd4,13'(x),13'(y),4'hf,
                1'(n==0),1'(x==4),1'(n==7)};
            for(integer lane=0;lane<4;lane=lane+1)begin
                value=zero?0:20;
                event_gx[lane*11+:11]=value;event_gy[lane*11+:11]=0;event_magnitude[lane*11+:11]=value;
            end
            event_valid=1;tick();
            if(wrap&&n==0&&device.dut.point_count[0]!=0)$fatal(1,"R3 F23 wrap not exercised");
            if(wrap&&n==2&&(device.dut.peak_strength[0]!=20||device.dut.peak_y[0]!=4))
                $fatal(1,"R3 F23 first-candidate branch after wrap was lost");
        end
        event_valid=0;
    end
endtask
task finish_case(input bit failed);
    begin frame_complete=!failed;frame_error=failed;tick();frame_complete=0;frame_error=0;frames=frames+1;end
endtask
initial begin
    native_width=32;native_height=16;mag_threshold=0;gx_min=1;ratio_shift=3;direction_sign=0;
    min_count=1;min_paired_strips=1;strip_y_begin=0;strip_y_end=4;roi_left=0;roi_split=4;roi_right=8;
    source_error_code=5;record_ready=0;
    reset_case();algebra();
    launch(1);pixels(8,0,1);finish_case(0);
    if(!record_valid)$fatal(1,"R3 F23 missing first record");
    launch(2);pixels(8,0,0);finish_case(0);
    if(record_drop_count!=1)$fatal(1,"R3 F23 publication stall/drop not exercised");
    record_ready=1;tick();record_ready=0;
    launch(3);pixels(2,0,0);finish_case(1);record_ready=1;tick();record_ready=0;
    launch(4);pixels(2,0,0);cancel=1;tick();cancel=0;tick();
    launch(5);pixels(8,1,0);finish_case(0);record_ready=1;tick();record_ready=0;
    direction_sign=3;launch(6);finish_case(0);
    repeat(4)tick();
    $display("RESULT: PASS R3_F23 vectors=%0d frames=%0d cycles=%0d",vectors,frames,device.r3_checks);$finish;
end
initial begin #100000;$fatal(1,"R3 F23 watchdog");end
