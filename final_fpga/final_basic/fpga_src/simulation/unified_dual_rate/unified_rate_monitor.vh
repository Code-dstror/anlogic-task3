// Passive monitor for a fixed physical60/N2 interval, followed by explicit drain.
integer jpeg_aw_count=0,jpeg_b_count=0,throughput_fd=0;
integer th_physical[0:1],th_fs[0:1],th_selected[0:1],th_crop[0:1],th_admit[0:1],th_finish[0:1];
integer th_sources[0:1],th_writers[0:1],th_raw_retire[0:1],th_safe[0:1],th_retire[0:1];
integer th_enqueue[0:1],th_consume[0:1],th_fifo_peak[0:1],th_raw_peak[0:1],th_jpeg_peak[0:1];
integer th_window_writer[0:1],th_window_safe[0:1],th_window_retire[0:1];
integer th_aw_stalls=0,th_w_stalls=0,th_ar_stalls=0,th_r_stalls=0,th_b_gaps=0;
realtime th_origin,th_input_end;
localparam integer PHYSICAL_PERIOD_NS=16666667;

task automatic throughput_identity(input string stage,input integer index);
    integer eye;
    begin
        eye=cameras[index];
        if(stage=="processing_start")th_sources[eye]++;
        if(stage=="writer")begin
            th_writers[eye]++;
            if(th_writers[eye]-th_retire[eye]>th_jpeg_peak[eye])th_jpeg_peak[eye]=th_writers[eye]-th_retire[eye];
        end
        if(stage=="raw_retire")th_raw_retire[eye]++;
        if(stage=="safe")th_safe[eye]++;
        if(stage=="retire")th_retire[eye]++;
        $fdisplay(throughput_fd,"{\"event\":\"%s\",\"camera\":%0d,\"sequence\":%0d,\"time_ns\":%.3f}",stage,eye,sequences[index],$realtime);
        $fflush(throughput_fd);
    end
endtask

task automatic periodic_camera(input integer eye);
    realtime deadline,remaining;
    begin
        for(integer frame_index=0;frame_index<THROUGHPUT_FRAMES*2;frame_index++)begin
            deadline=th_origin+frame_index*PHYSICAL_PERIOD_NS+(eye==1?EYE_PHASE_NS:0);
            remaining=deadline-$realtime;
            check(remaining>=0,"electrical source meets its own free-running deadline");
            #(remaining);th_physical[eye]++;
            $fdisplay(throughput_fd,"{\"event\":\"sensor_fs\",\"camera\":%0d,\"frame\":%0d,\"scheduled_ns\":%.3f,\"time_ns\":%.3f}",eye,frame_index,deadline,$realtime);
            if(eye==0)source0.frame(16'(16'h300+frame_index),-1);
            else source1.frame(16'(16'h500+frame_index),-1);
            $fdisplay(throughput_fd,"{\"event\":\"sensor_fe\",\"camera\":%0d,\"frame\":%0d,\"time_ns\":%.3f}",eye,frame_index,$realtime);
            $fflush(throughput_fd);
        end
        remaining=th_origin+THROUGHPUT_FRAMES*2*PHYSICAL_PERIOD_NS+(eye==1?EYE_PHASE_NS:0)-$realtime;
        check(remaining>=0,"last physical frame fits the fixed period");#(remaining);
    end
endtask

task automatic th_true_fs(input integer eye,input [31:0] seq,input bit admitted);
    begin
        check(admitted==(th_fs[eye]%2==0),"exact N2 selection on every trusted physical FS, including busy/skipped events");
        th_fs[eye]++;
        if(admitted)th_selected[eye]++;
        $fdisplay(throughput_fd,"{\"event\":\"trusted_fs\",\"camera\":%0d,\"ordinal\":%0d,\"sequence\":%0d,\"selected\":%0d,\"time_ns\":%.3f}",eye,th_fs[eye]-1,seq,admitted,$realtime);
        $fflush(throughput_fd);
    end
endtask

task automatic th_admit_event(input integer eye,input [31:0] seq);
    integer live;
    begin
        th_admit[eye]++;live=th_admit[eye]-th_raw_retire[eye];
        if(live>th_raw_peak[eye])th_raw_peak[eye]=live;
        $fdisplay(throughput_fd,"{\"event\":\"raw_admit\",\"camera\":%0d,\"sequence\":%0d,\"raw_live\":%0d,\"time_ns\":%.3f}",eye,seq,live,$realtime);
        $fflush(throughput_fd);
    end
endtask

initial begin
    for(integer eye=0;eye<2;eye++)begin
        th_physical[eye]=0;th_fs[eye]=0;th_selected[eye]=0;th_crop[eye]=0;th_admit[eye]=0;th_finish[eye]=0;
        th_sources[eye]=0;th_writers[eye]=0;th_raw_retire[eye]=0;th_safe[eye]=0;th_retire[eye]=0;
        th_enqueue[eye]=0;th_consume[eye]=0;th_fifo_peak[eye]=0;th_raw_peak[eye]=0;th_jpeg_peak[eye]=0;
        th_window_writer[eye]=0;th_window_safe[eye]=0;th_window_retire[eye]=0;
    end
    throughput_fd=$fopen("throughput_events.jsonl","w");
    $fdisplay(throughput_fd,"{\"event\":\"profile\",\"width\":1920,\"height\":1080,\"physical_period_ns\":%0d,\"capture_divisor\":2,\"admitted_per_eye\":%0d,\"eye_phase_ns\":%0d,\"source_waits_for_ready\":false,\"word_period_ns\":8.888888,\"word_valid_duty\":0.5,\"ddr_stalls\":true,\"host_bytes\":%0d,\"pattern\":\"hashed_detail_v1\"}",PHYSICAL_PERIOD_NS,THROUGHPUT_FRAMES,EYE_PHASE_NS,HOST_BYTES);
end

// Snapshot at the fixed input deadline, before the final drain. This separates
// bounded sustained delivery from counting a backlog after input has stopped.
initial begin
    wait(phase==8);wait(th_origin>$realtime);
    #(th_origin+THROUGHPUT_FRAMES*2*PHYSICAL_PERIOD_NS+EYE_PHASE_NS-$realtime);
    th_input_end=$realtime;
    for(integer eye=0;eye<2;eye++)begin
        th_window_writer[eye]=th_writers[eye];th_window_safe[eye]=th_safe[eye];th_window_retire[eye]=th_retire[eye];
        $fdisplay(throughput_fd,"{\"event\":\"fixed_window\",\"camera\":%0d,\"writer\":%0d,\"safe\":%0d,\"retire\":%0d,\"raw_inflight\":%0d,\"jpeg_inflight\":%0d,\"time_ns\":%.3f}",eye,th_writers[eye],th_safe[eye],th_retire[eye],th_admit[eye]-th_raw_retire[eye],th_writers[eye]-th_retire[eye],$realtime);
    end
    $fflush(throughput_fd);
end

always @(posedge dut.pixel_clk)if(dut.pixel_rst_n&&phase==8)begin
    if(dut.physical_event_valid&&dut.stereo_event0_ready&&dut.physical_event_kind==0&&dut.physical_event_identity_valid)
        th_true_fs(0,dut.physical_event_sequence,dut.u_stereo_capture0.admitted_fs);
    if(dut.camera1_event_valid&&dut.camera1_event_ready&&dut.camera1_event_kind==0&&dut.camera1_event_identity_valid)
        th_true_fs(1,dut.camera1_event_sequence,dut.u_stereo_capture1.admitted_fs);
    if(dut.capture0_valid&&dut.capture0_accept&&dut.capture0_sof)th_crop[0]++;
    if(dut.capture1_valid&&dut.capture1_accept&&dut.capture1_sof)th_crop[1]++;
    if(dut.raw_capture0_frame_accept)th_admit_event(0,dut.capture0_sequence);
    if(dut.raw_capture1_frame_accept)th_admit_event(1,dut.capture1_sequence);
    if(dut.raw_capture0_enqueue_fire)begin
        th_enqueue[0]++;
        if(th_enqueue[0]-th_consume[0]>th_fifo_peak[0])th_fifo_peak[0]=th_enqueue[0]-th_consume[0];
    end
    if(dut.raw_capture1_enqueue_fire)begin
        th_enqueue[1]++;
        if(th_enqueue[1]-th_consume[1]>th_fifo_peak[1])th_fifo_peak[1]=th_enqueue[1]-th_consume[1];
    end
end

always @(posedge dut.dfi_clk)if(dut.dfi_rst_n)begin
    if(dut.u_ddr_store.store_awvalid&&dut.u_ddr_store.store_awready)jpeg_aw_count++;
    if(dut.u_ddr_store.store_bvalid&&dut.u_ddr_store.store_bready)jpeg_b_count++;
    if(phase==8)begin
        if(dut.raw_capture0_consume_fire)th_consume[0]++;
        if(dut.raw_capture1_consume_fire)th_consume[1]++;
        for(integer eye=0;eye<2;eye++)if(`DUAL_STORE.i_finish_valid[eye]&&`DUAL_STORE.o_finish_ready[eye])begin
            check(`DUAL_STORE.i_finish_ok[eye],"selected clean RAW frame has a real good FINISH");th_finish[eye]++;
        end
        if(`DUAL_STORE.s_begin_valid&&`DUAL_STORE.s_begin_ready)
            check(`DUAL_STORE.o_begin_accepted,"two RAW slots cannot drop a selected physical60/N2 frame");
        if(`DUAL_MEM.axi_awvalid&&!`DUAL_MEM.axi_awready)th_aw_stalls++;
        if(`DUAL_MEM.axi_wvalid&&!`DUAL_MEM.axi_wready)th_w_stalls++;
        if(`DUAL_MEM.axi_arvalid&&!`DUAL_MEM.axi_arready)th_ar_stalls++;
        if(`DUAL_MEM.rd_active&&!`DUAL_MEM.axi_rvalid)th_r_stalls++;
        if(`DUAL_MEM.b_pending&&!`DUAL_MEM.axi_bvalid)th_b_gaps++;
    end
end

task automatic finish_throughput;
    begin
        for(integer eye=0;eye<2;eye++)begin
            check(th_physical[eye]==THROUGHPUT_FRAMES*2&&th_fs[eye]==THROUGHPUT_FRAMES*2,"all actual sensor FS crossed real CSI");
            check(th_selected[eye]==THROUGHPUT_FRAMES&&th_crop[eye]==THROUGHPUT_FRAMES,"FS-level N2 selected exactly one crop per chosen identity");
            check(th_admit[eye]==THROUGHPUT_FRAMES&&th_finish[eye]==THROUGHPUT_FRAMES,"all selected captures commit");
            check(th_sources[eye]==THROUGHPUT_FRAMES&&th_writers[eye]==THROUGHPUT_FRAMES&&th_raw_retire[eye]==THROUGHPUT_FRAMES&&th_safe[eye]==THROUGHPUT_FRAMES&&th_retire[eye]==THROUGHPUT_FRAMES,"all true RAW/JPEG/host lifecycles complete");
            check(th_enqueue[eye]==th_consume[eye]&&th_raw_peak[eye]<=2&&th_jpeg_peak[eye]<=3,"finite owned queues actually drain");
            check(th_window_writer[eye]==THROUGHPUT_FRAMES&&th_window_safe[eye]==THROUGHPUT_FRAMES,"fixed physical60/N2 window delivers all selected complete JPEGs to SAFE");
            $fdisplay(throughput_fd,"{\"event\":\"eye_summary\",\"camera\":%0d,\"physical\":%0d,\"trusted_fs\":%0d,\"selected\":%0d,\"crop\":%0d,\"admit\":%0d,\"raw_finish\":%0d,\"processing\":%0d,\"writer\":%0d,\"raw_retire\":%0d,\"safe\":%0d,\"retire\":%0d,\"enqueue\":%0d,\"consume\":%0d,\"raw_peak\":%0d,\"jpeg_peak\":%0d,\"fifo_peak\":%0d}",eye,th_physical[eye],th_fs[eye],th_selected[eye],th_crop[eye],th_admit[eye],th_finish[eye],th_sources[eye],th_writers[eye],th_raw_retire[eye],th_safe[eye],th_retire[eye],th_enqueue[eye],th_consume[eye],th_raw_peak[eye],th_jpeg_peak[eye],th_fifo_peak[eye]);
        end
        check(th_aw_stalls>0&&th_w_stalls>0&&th_ar_stalls>0&&th_r_stalls>0&&th_b_gaps>0,"all five DDR channel service gaps measured");
        check(dut.u_camera1.o_overflows==0&&!dut.stereo_source0_fault&&!dut.stereo_source1_fault&&!dut.raw_processing_fault,"no clean-source overflow or structural fault");
        $fdisplay(throughput_fd,"{\"event\":\"summary\",\"origin_ns\":%.3f,\"input_end_ns\":%.3f,\"drain_end_ns\":%.3f,\"aw_stalls\":%0d,\"w_stalls\":%0d,\"ar_stalls\":%0d,\"r_gaps\":%0d,\"b_gaps\":%0d,\"host_axis_stall_checks\":%0d,\"ack_hold_checks\":%0d}",th_origin,th_input_end,$realtime,th_aw_stalls,th_w_stalls,th_ar_stalls,th_r_stalls,th_b_gaps,held_checks,ack_hold_checks);
        $fclose(throughput_fd);
        $display("UNIFIED_DUAL_RATE_CAPTURE PASS physical60/N2 admittedPerEye=%0d; full independent checker still required",THROUGHPUT_FRAMES);
    end
endtask
