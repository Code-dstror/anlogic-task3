// Optional bounded 1080p30-per-eye measurement. Included in the existing MAIN;
// every observation is passive. No DUT handshake/credit/owner is overridden.
integer jpeg_aw_count=0,jpeg_b_count=0;
integer throughput_fd=0;
integer th_physical[0:1],th_crop[0:1],th_admit[0:1],th_finish[0:1];
integer th_sources[0:1],th_writers[0:1],th_raw_retire[0:1],th_safe[0:1],th_retire[0:1];
integer th_enqueue[0:1],th_consume[0:1],th_fifo_peak[0:1],th_raw_peak[0:1],th_jpeg_peak[0:1];
integer th_aw_stalls=0,th_w_stalls=0,th_ar_stalls=0,th_r_stalls=0,th_b_gaps=0;
realtime th_origin;
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

// Start both independent electrical sources on the same absolute deadlines.
// Only their own word clock quantizes a start (< one 8.889 ns word cycle).
// Frame completion never waits for DUT backpressure, JPEG or host progress.
task automatic periodic_camera(input integer eye);
    realtime deadline,remaining;
    begin
        for(integer frame_index=0;frame_index<THROUGHPUT_FRAMES*2;frame_index++)begin
            deadline=th_origin+frame_index*PHYSICAL_PERIOD_NS;
            remaining=deadline-$realtime;
            check(remaining>=0,"electrical camera cannot meet its next physical60 SOF");
            #(remaining);
            th_physical[eye]++;
            $fdisplay(throughput_fd,"{\"event\":\"sensor_fs\",\"camera\":%0d,\"frame\":%0d,\"scheduled_ns\":%.3f,\"time_ns\":%.3f}",eye,frame_index,deadline,$realtime);
            if(eye==0)source0.frame(16'(16'h300+frame_index),-1);
            else source1.frame(16'(16'h500+frame_index),-1);
            $fdisplay(throughput_fd,"{\"event\":\"sensor_fe\",\"camera\":%0d,\"frame\":%0d,\"time_ns\":%.3f}",eye,frame_index,$realtime);
            $fflush(throughput_fd);
        end
        // Include the final frame period, so the admission-rate denominator
        // includes a complete physical60/N2 window rather than active pixels.
        remaining=th_origin+THROUGHPUT_FRAMES*2*PHYSICAL_PERIOD_NS-$realtime;
        check(remaining>=0,"last physical frame fits its fixed period");
        #(remaining);
    end
endtask

task automatic th_crop_event(input integer eye,input [31:0] sequence_id);
    begin
        th_crop[eye]++;
        $fdisplay(throughput_fd,"{\"event\":\"crop_sof\",\"camera\":%0d,\"sequence\":%0d,\"time_ns\":%.3f}",eye,sequence_id,$realtime);
    end
endtask

task automatic th_admit_event(input integer eye,input [31:0] sequence_id);
    integer live;
    begin
        th_admit[eye]++;live=th_admit[eye]-th_raw_retire[eye];
        if(live>th_raw_peak[eye])th_raw_peak[eye]=live;
        $fdisplay(throughput_fd,"{\"event\":\"raw_admit\",\"camera\":%0d,\"sequence\":%0d,\"raw_live\":%0d,\"time_ns\":%.3f}",eye,sequence_id,live,$realtime);
        $fflush(throughput_fd);
    end
endtask

initial begin
    for(integer eye=0;eye<2;eye++)begin
        th_physical[eye]=0;th_crop[eye]=0;th_admit[eye]=0;th_finish[eye]=0;
        th_sources[eye]=0;th_writers[eye]=0;th_raw_retire[eye]=0;th_safe[eye]=0;th_retire[eye]=0;
        th_enqueue[eye]=0;th_consume[eye]=0;th_fifo_peak[eye]=0;th_raw_peak[eye]=0;th_jpeg_peak[eye]=0;
    end
    if(THROUGHPUT_FRAMES!=0)begin
        throughput_fd=$fopen("throughput_events.jsonl","w");
        $fdisplay(throughput_fd,"{\"event\":\"profile\",\"width\":1920,\"height\":1080,\"physical_period_ns\":%0d,\"capture_divisor\":2,\"admitted_per_eye\":%0d,\"source_waits_for_ready\":false,\"word_period_ns\":8.888888,\"word_valid_duty\":0.5,\"ddr_stalls\":true,\"host_bytes\":%0d,\"pattern\":\"hashed_detail_v1\"}",PHYSICAL_PERIOD_NS,THROUGHPUT_FRAMES,HOST_BYTES);
    end
end

always @(posedge dut.pixel_clk)if(dut.pixel_rst_n&&phase==8&&THROUGHPUT_FRAMES!=0)begin
    if(dut.capture0_valid&&dut.capture0_accept&&dut.capture0_sof)th_crop_event(0,dut.capture0_sequence);
    if(dut.capture1_valid&&dut.capture1_accept&&dut.capture1_sof)th_crop_event(1,dut.capture1_sequence);
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
    // JPEG-specific channel counts avoid confusing another eye's live RAW
    // write with uncompleted JPEG data at the writer's successful ACK.
    if(dut.u_ddr_store.store_awvalid&&dut.u_ddr_store.store_awready)jpeg_aw_count++;
    if(dut.u_ddr_store.store_bvalid&&dut.u_ddr_store.store_bready)jpeg_b_count++;
    if(phase==8&&THROUGHPUT_FRAMES!=0)begin
        if(dut.raw_capture0_consume_fire)th_consume[0]++;
        if(dut.raw_capture1_consume_fire)th_consume[1]++;
        for(integer eye=0;eye<2;eye++)if(`DUAL_STORE.i_finish_valid[eye]&&`DUAL_STORE.o_finish_ready[eye])begin
            check(`DUAL_STORE.i_finish_ok[eye],"every selected RAW frame commits successfully");
            th_finish[eye]++;
            $fdisplay(throughput_fd,"{\"event\":\"raw_finish\",\"camera\":%0d,\"time_ns\":%.3f}",eye,$realtime);
        end
        if(`DUAL_STORE.s_begin_valid&&`DUAL_STORE.s_begin_ready)
            check(`DUAL_STORE.o_begin_accepted,"finite RAW slots cannot drop a selected physical60/N2 frame");
        if(`DUAL_MEM.axi_awvalid&&!`DUAL_MEM.axi_awready)th_aw_stalls++;
        if(`DUAL_MEM.axi_wvalid&&!`DUAL_MEM.axi_wready)th_w_stalls++;
        if(`DUAL_MEM.axi_arvalid&&!`DUAL_MEM.axi_arready)th_ar_stalls++;
        if(`DUAL_MEM.rd_active&&!`DUAL_MEM.axi_rvalid&&0)th_r_stalls++;
        if(`DUAL_MEM.b_pending&&0)th_b_gaps++;
    end
end

task automatic finish_throughput;
    begin
        for(integer eye=0;eye<2;eye++)begin
            check(th_physical[eye]==THROUGHPUT_FRAMES*2&&th_crop[eye]==THROUGHPUT_FRAMES*2,"all physical frames crossed the real CSI crop");
            check(th_admit[eye]==THROUGHPUT_FRAMES&&th_finish[eye]==THROUGHPUT_FRAMES,"N2 admits and commits every selected frame");
            check(th_sources[eye]==THROUGHPUT_FRAMES&&th_writers[eye]==THROUGHPUT_FRAMES&&th_raw_retire[eye]==THROUGHPUT_FRAMES&&th_safe[eye]==THROUGHPUT_FRAMES&&th_retire[eye]==THROUGHPUT_FRAMES,"every eye completes RAW/shared JPEG/native SAFE lifecycle");
            check(th_enqueue[eye]==th_consume[eye]&&th_raw_peak[eye]<=2&&th_jpeg_peak[eye]<=3,"finite queues drain without overwriting owned slots");
            $fdisplay(throughput_fd,"{\"event\":\"eye_summary\",\"camera\":%0d,\"physical\":%0d,\"crop\":%0d,\"admit\":%0d,\"raw_finish\":%0d,\"processing\":%0d,\"writer\":%0d,\"raw_retire\":%0d,\"safe\":%0d,\"retire\":%0d,\"enqueue\":%0d,\"consume\":%0d,\"raw_peak\":%0d,\"jpeg_peak\":%0d,\"fifo_peak\":%0d}",eye,th_physical[eye],th_crop[eye],th_admit[eye],th_finish[eye],th_sources[eye],th_writers[eye],th_raw_retire[eye],th_safe[eye],th_retire[eye],th_enqueue[eye],th_consume[eye],th_raw_peak[eye],th_jpeg_peak[eye],th_fifo_peak[eye]);
        end
        check(th_aw_stalls>0&&th_w_stalls>0&&th_ar_stalls>0&&th_r_stalls>0&&th_b_gaps>0,"all five DDR channels exercise bounded service gaps");
        check(dut.u_camera1.o_overflows==0&&!dut.stereo_source0_fault&&!dut.stereo_source1_fault&&!dut.raw_processing_fault,"no CSI overflow or stereo fault");
        $fdisplay(throughput_fd,"{\"event\":\"summary\",\"origin_ns\":%.3f,\"input_end_ns\":%.3f,\"end_ns\":%.3f,\"aw_stalls\":%0d,\"w_stalls\":%0d,\"ar_stalls\":%0d,\"r_gaps\":%0d,\"b_gaps\":%0d,\"host_axis_stall_checks\":%0d,\"ack_hold_checks\":%0d}",th_origin,th_origin+THROUGHPUT_FRAMES*2*PHYSICAL_PERIOD_NS,$realtime,th_aw_stalls,th_w_stalls,th_ar_stalls,th_r_stalls,th_b_gaps,held_checks,ack_hold_checks);
        $fclose(throughput_fd);
        $display("DUAL_THROUGHPUT_CAPTURE PASS physical60/N2 admittedPerEye=%0d; rate qualification requires check_throughput.py",THROUGHPUT_FRAMES);
    end
endtask
