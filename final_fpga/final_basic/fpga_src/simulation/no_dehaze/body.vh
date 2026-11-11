    localparam integer GROUPS=518400;
    reg [127:0] source_words[0:GROUPS-1],gold[0:GROUPS-1];
    reg [31:0] quarter_gold[0:129599];
    reg [31:0] expected_stats[0:5];
    integer stats_count=0,source_checks=0;
    reg [39:0] point_gold[0:302];
    integer point_counts[0:1];
    integer cycle=0,outputs=0,inputs=0,frame_number=0;
    integer held_checks=0,eof_stalls=0,stall_budget=0;
    integer qpoints=0,serial_points=0,half_events=0,qi=0;
    integer checked_points=0,stereo_checks=0,complete_frames=0;
    reg expect_history=0,compare_output=0,held=0,joint_check=0;
    reg [129:0] held_word;
    reg [176:0] held_descriptor;
    reg [31:0] refsample,random_state=32'h51a0ba21;
    wire [129:0] word={m_sof,m_eol,m_y,m_rgb};
    always @(negedge clk)begin
        random_state={random_state[30:0],random_state[31]^random_state[21]^random_state[1]^random_state[0]};
        m_ready=random_state[0]||random_state[3];
        if(m_valid&&outputs==GROUPS-1&&stall_budget>0)begin
            m_ready=0;stall_budget=stall_budget-1;eof_stalls=eof_stalls+1;
        end
    end
    always @(posedge clk)begin
        cycle=cycle+1;
        if(cycle>6000000)begin
            $display("JOINT_WATCHDOG frame%0d inputs%0d outputs%0d q%0d serial%0d quiet%b state%0d f22%b f23%b",frame_number,inputs,outputs,qpoints,serial_points,o_frame_quiet,0,f22_record_valid,f23_record_valid);
            $fatal(1,"No-dehaze bounded watchdog");
        end
        if(!rst_n)held=0;
        else begin
            if(o_map_commit||o_history_used||o_history_age!=0||o_frame_lut_generation!=0||lut_valid||lut_generation!=0)
                $fatal(1,"removed dehaze produced status");
            if(source_ready[1]!==1'b1||source_cancel_done[1]!==1'b1||source_owner_match[1]||source_accepted[1]||source_skip[1])
                $fatal(1,"removed SOURCE branch blocked or qualified");
            if(m_stats_valid&&m_stats_ready)begin
                if(m_stats_context!==frame_context||m_statistics[15:0]!==16'd57600||m_statistics[31:16]!==16'd57600||
                   m_statistics[63:32]!==expected_stats[1]||m_statistics[103:96]!==expected_stats[2][7:0]||
                   m_statistics[111:104]!==expected_stats[3][7:0]||m_statistics[79:64]!==expected_stats[4][15:0]||
                   m_statistics[95:80]!==expected_stats[5][15:0]||m_statistics[175:168]!=0)
                    $fatal(1,"neutral F20 statistics mismatch %h",m_statistics);
                stats_count=stats_count+1;
            end
            if(source_valid[0]&&source_ready[0])begin
                if(!source_owner_match[0]||!source_accepted[0])$fatal(1,"HE SOURCE did not authenticate");
                source_checks=source_checks+1;
            end
            if(compare_output)begin
                if(o_fault||m_frame_error||o_filter_error)$fatal(1,"service fault frame%0d input%0d output%0d",frame_number,inputs,outputs);
                if(s_valid&&s_ready)inputs=inputs+1;
                if(held)begin
                    if(!m_valid||word!==held_word)$fatal(1,"output changed while stalled");
                    held_checks=held_checks+1;
                end
                if(m_valid&&m_ready)begin
                    if(outputs>=GROUPS)$fatal(1,"extra output");
                    if({m_y,m_rgb}!==gold[outputs])$fatal(1,"joint RGB/Y frame%0d group%0d got%h expected%h",frame_number,outputs,{m_y,m_rgb},gold[outputs]);
                    if(m_sof!==(outputs==0)||m_eol!==(outputs%480==479))$fatal(1,"geometry");
                    if(dut.u_pipeline.g_full_preprocess.u_hist.o_frame_history_used!==expect_history)$fatal(1,"HE history frame%0d got%b expected%b",frame_number,dut.u_pipeline.g_full_preprocess.u_hist.o_frame_history_used,expect_history);
                    outputs=outputs+1;
                end
                held=m_valid&&!m_ready;held_word=word;
            end else held=0;
            if(joint_check)begin
                if(dut.u_pipeline.g_full_preprocess.u_filter.low_valid&&dut.u_pipeline.g_full_preprocess.u_filter.low_metadata[60:59]==1)
                    half_events=half_events+1;
                if(dut.u_pipeline.g_full_preprocess.u_filter.quarter_delayed)begin
                    if(!dut.u_pipeline.g_full_preprocess.u_filter.hints_valid||dut.u_pipeline.g_full_preprocess.u_filter.hints_error)
                        $fatal(1,"native color hint progress");
                    for(integer i=0;i<4;i=i+1)begin
                        qi=dut.u_pipeline.g_full_preprocess.u_filter.quarter_y*480+dut.u_pipeline.g_full_preprocess.u_filter.quarter_x+i;
                        refsample=quarter_gold[qi];
                        if(dut.u_pipeline.g_full_preprocess.u_filter.quarter_gx[i*11+:11]!==refsample[10:0]||
                           dut.u_pipeline.g_full_preprocess.u_filter.quarter_gy[i*11+:11]!==refsample[21:11]||
                           dut.u_pipeline.g_full_preprocess.u_filter.quarter_center[i*8+:8]!==refsample[29:22]||
                           (dut.u_pipeline.g_full_preprocess.u_filter.hints[i*2+1]?2'd2:dut.u_pipeline.g_full_preprocess.u_filter.hints[i*2]?2'd1:2'd0)!==refsample[31:30])
                            $fatal(1,"quarter p11/Gx/Gy/native hint frame%0d index%0d got%h/%h/%h/%h expected%h",frame_number,qi,
                                dut.u_pipeline.g_full_preprocess.u_filter.quarter_gx[i*11+:11],dut.u_pipeline.g_full_preprocess.u_filter.quarter_gy[i*11+:11],
                                dut.u_pipeline.g_full_preprocess.u_filter.quarter_center[i*8+:8],dut.u_pipeline.g_full_preprocess.u_filter.hints[i*2+:2],refsample);
                        qpoints=qpoints+1;
                    end
                end
                if(dut.u_pipeline.g_full_preprocess.u_filter.lane.queue_valid)begin
                    qi=dut.u_pipeline.g_full_preprocess.u_filter.lane.queue_y*480+dut.u_pipeline.g_full_preprocess.u_filter.lane.queue_x;
                    refsample=quarter_gold[qi];
                    if(dut.u_pipeline.g_full_preprocess.u_filter.lane.queue_sample[29:0]!==refsample[29:0]||
                       (dut.u_pipeline.g_full_preprocess.u_filter.lane.queue_sample[31]?2'd2:dut.u_pipeline.g_full_preprocess.u_filter.lane.queue_sample[30]?2'd1:2'd0)!==refsample[31:30])
                        $fatal(1,"serialized C1 sample mismatch index%0d",qi);
                    serial_points=serial_points+1;
                end
            end
        end
    end
    task cold_reset;
        begin
            compare_output=0;joint_check=0;s_valid=0;s_frame_done=0;source_valid=0;
            rst_n=0;i_processing_rst_n=0;
            repeat(8)@(negedge clk);
            rst_n=1;i_processing_rst_n=1;
            repeat(20)@(negedge clk);
            if(lut_valid||lut_generation!=0)$fatal(1,"removed G1 advertised after reset");
        end
    endtask
    task start_frame(input integer capture,input bit enhanced,input bit lane_enable);
        begin
            frame_number=frame_number+1;
            outputs=0;inputs=0;expect_history=enhanced;stall_budget=17;
            qpoints=0;serial_points=0;half_events=0;
            if(enhanced)$readmemh("expected1.hex",gold);
            else $readmemh("expected0.hex",gold);
            $readmemh("quarter.hex",quarter_gold);$readmemh("points.hex",point_gold);
            frame_owner={32'h10203040,32'(capture)};frame_capture=capture;
            frame_context={32'd0,32'd0,32'(capture),32'd1,32'h10203040};
            frame_cohort={32'h10203040,32'd1,32'd1000,16'd256,13'd1920,13'd1080,
                3'd1,1'b0,1'b0,8'd224,9'd128,8'd8,9'd16,8'd80,8'd48,8'd208,8'd24};
            // All enabled numerical operations are Gray/Gaussian/HE and C1.
            cfg_lane=lane_enable;cfg_multiscale=lane_enable;
            @(negedge clk);i_source_frame_begin=1;i_product_begin=0;
            @(negedge clk);i_source_frame_begin=0;i_product_begin=0;
            i_filter_start_valid=1;
            do @(posedge clk);while(!o_filter_start_ready);
            @(negedge clk);i_filter_start_valid=0;
            compare_output=1;joint_check=lane_enable;
        end
    endtask
    task send_pixels(input integer count);
        begin
            fork
                begin
                    do @(posedge clk);while(!(m_valid&&m_ready&&m_sof));
                    @(negedge clk);i_product_begin=1;
                    @(negedge clk);i_product_begin=0;
                end
                begin
                    for(integer k=0;k<count;k=k+1)begin
                        @(negedge clk);s_valid=1;s_rgb=source_words[k][95:0];
                        s_sof=k==0;s_eol=k%480==479;
                        do @(posedge clk);while(!s_ready);
                    end
                    @(negedge clk);s_valid=0;s_sof=0;s_eol=0;
                end
            join
        end
    endtask
    task finish_frame(input integer golden_index);
        begin
            @(negedge clk);s_frame_done=1;
            @(negedge clk);s_frame_done=0;
            source_session=32'h10203040;source_epoch=1;source_capture=frame_capture;
            source_ok=1;source_valid=1;
            do @(posedge clk);while(!source_ready[0]);
            @(negedge clk);source_valid=0;
            wait(outputs==GROUPS);
            wait(o_frame_quiet&&f22_record_valid&&f23_record_valid);
            wait(stats_count==frame_number);
            if(golden_index==0)wait(dut.u_pipeline.g_full_preprocess.u_hist.pending_lut);
            if(qpoints!=129600||serial_points!=129600||half_events!=129600)$fatal(1,"joint event count q%0d serial%0d half%0d",qpoints,serial_points,half_events);
            // Sparse descriptor packs context above its 17-bit status/count.
            if(f23_record_data[176:17]!==frame_context||f23_record_data[16:8]!==point_counts[golden_index]||f23_record_data[7:0]!==0)
                $fatal(1,"sparse descriptor got%h expected count%0d context%h",f23_record_data,point_counts[golden_index],frame_context);
            held_descriptor=f23_record_data;
            repeat(9)begin @(posedge clk);#1;if(!f23_record_valid||f23_record_data!==held_descriptor)$fatal(1,"F23 hold");end
            for(integer index=0;index<point_counts[golden_index];index=index+1)begin
                @(negedge clk);lane_read_enable=1;lane_read_index=index;
                @(posedge clk);#1;
                if(!lane_read_valid||lane_read_data!==point_gold[index])$fatal(1,"joint sparse point %0d got%h expected%h",index,lane_read_data,point_gold[index]);
                checked_points=checked_points+1;
            end
            @(negedge clk);lane_read_enable=0;f22_record_ready=1;f23_record_ready=1;i_frame_released=1;
            @(negedge clk);f22_record_ready=0;f23_record_ready=0;i_frame_released=0;
            repeat(8)@(negedge clk);
            if(outputs!=GROUPS||inputs!=GROUPS)$fatal(1,"count mismatch");
            compare_output=0;joint_check=0;complete_frames=complete_frames+1;
            $display("NO_DEHAZE_JOINT PASS frame=%0d history=%0d native_groups=%0d qpoints=%0d serial_points=%0d sparse_points=%0d",frame_number,expect_history,outputs,qpoints,serial_points,point_counts[golden_index]);
        end
    endtask
    initial begin
        cfg_schema2=1;cfg_enable=4;cfg_he_history_eligible=1;
        cfg_filter_gray=1;cfg_filter_color=1;
        m_stats_ready=1;f22_record_ready=0;f23_record_ready=0;i_window_ready=1;cfg_status_ready=1;
        $readmemh("source.hex",source_words);$readmemh("stats.hex",expected_stats);
        point_counts[0]=expected_stats[0];point_counts[1]=expected_stats[0];
        cold_reset();
        start_frame(1,0,1);send_pixels(GROUPS);finish_frame(0);
        start_frame(2,1,1);send_pixels(GROUPS);finish_frame(1);
        if(source_checks!=2||stats_count!=2||complete_frames!=2||held_checks<40||eof_stalls<30)$fatal(1,"joint coverage missing");
        $display("RESULT: PASS NO_DEHAZE_SERVICE complete_hd_frames=%0d gray_colorGaussian_HE=1 qualified_history_frame2=1 rgb_y_groups=%0d quarter_samples=259200 serialized_samples=259200 candidate_words=%0d neutral_stats=%0d source_auth=%0d held_checks=%0d eof_stalls=%0d",complete_frames,2*GROUPS,checked_points,stats_count,source_checks,held_checks,eof_stalls);
        $finish;
    end
