    // All controls drive the same PIPE instance as the final LIVE service.
    localparam W=256,H=128,N=W*H/4;
    integer histogram[0:1][0:255],next_hist[0:255],map_y[0:255];
    reg [127:0] expected[0:N-1];reg [95:0] original[0:N-1];
    integer n_enhanced=0,n_output=0,dcp_changes=0,he_changes=0;
    integer frame_count=0,expected_dcp=0,expected_he=0,eye=0,cycle=0;
    reg checking=0,done_seen=0,expect_cancel=0;
    reg [127:0] held;reg stall=0;
    function automatic [23:0] pixel(input integer x,y,cam);
        integer haze,l,r,g,b;
        begin
            haze=cam?170:110;
            l=((x/8*5+y/4*11+cam*13)%120);
            r=haze+l/2;g=haze+8+l/3;b=haze+13+l/2;
            pixel={r[7:0],g[7:0],b[7:0]};
        end
    endfunction
    function automatic integer luma(input [23:0] rgb);
        return (77*rgb[23:16]+150*rgb[15:8]+29*rgb[7:0]+128)>>8;
    endfunction
    function automatic [7:0] sat(input integer n);
        return n<0 ? 0 : n>255 ? 255 : n;
    endfunction
    always @(negedge clk)begin
        cycle=cycle+1;m_ready=cycle%7!=3&&cycle%11!=1;
        if(cycle>250000)$fatal(1,"joint watchdog frames=%0d",frame_count);
    end
    always @(posedge clk)if(rst_n)begin : monitor
        integer lum,delta,out_lum;
        reg [23:0] rgb,restored;
        reg [127:0] gold;
        if(m_frame_error&&!expect_cancel)$fatal(1,"unexpected pipeline cancel");
        if(m_frame_done)done_seen=1;
        if(stall&&!expect_cancel&&(!m_valid||{m_luma,m_data}!==held))$fatal(1,"output changed under backpressure");
        stall=m_valid&&!m_ready;held={m_luma,m_data};
        if(checking&&dut.enhanced_valid&&dut.enhanced_ready)begin
            if(n_enhanced>=N)$fatal(1,"duplicated enhanced beat");
            if(o_dehaze_history_used!==expected_dcp[0])$fatal(1,"wrong frame history usage eye=%d, seq=%d",eye,cfg_he_capture_sequence);
            if(o_dehaze_history_used&&dut.enhanced_rgb!==original[n_enhanced])dcp_changes++;
            if(!o_dehaze_history_used&&dut.enhanced_rgb!==original[n_enhanced])$fatal(1,"DCP identity frame=%d beat=%d expected=%h actual=%h",frame_count,n_enhanced,original[n_enhanced],dut.enhanced_rgb);
            for(integer k=0;k<4;k++)begin
                rgb=dut.enhanced_rgb[k*24+:24];lum=luma(rgb);
                if(dut.enhanced_luma[k*8+:8]!==lum[7:0])$fatal(1,"DCP did not rebuild exact Y");
                next_hist[lum]++;
                // Independent temporal HE oracle for the downstream handoff.
                delta=expected_he&&cfg_enable[2] ? map_y[lum]-lum : 0;
                if(delta>32)delta=32;if(delta< -32)delta=-32;
                restored={sat(int'(rgb[23:16])+delta),sat(int'(rgb[15:8])+delta),sat(int'(rgb[7:0])+delta)};
                if(restored!=rgb)he_changes++;
                out_lum=luma(restored);
                gold[k*24+:24]=restored;gold[96+8*k+:8]=out_lum[7:0];
            end
            expected[n_enhanced]=gold;n_enhanced++;
        end
        if(checking&&m_valid&&m_ready)begin
            if(n_output>=n_enhanced||{m_luma,m_data}!==expected[n_output]||m_sof!==(n_output==0)||m_eol!==(n_output%(W/4)==W/4-1))
                $fatal(1,"DCP->HE RGB/Y mismatch eye=%0d frame=%0d beat=%0d, got=%h expected=%h",eye,frame_count,n_output,{m_luma,m_data},expected[n_output]);
            n_output++;
        end
    end
    task automatic send_frame(input integer camera,seq_id,input bit dcp_on,he_on,have_dcp,have_he);
        integer cdf,first;reg [95:0] word;
        begin
            @(negedge clk);eye=camera;cfg_dehaze_enable=dcp_on;cfg_enable={he_on,2'b00};
            cfg_he_capture_sequence=seq_id;cfg_he_context={32'd11,32'd3,32'd0,16'd256,13'(W),13'(H),camera[0],3'd0};
            cfg_filter_context={63'd0,camera[0],32'(seq_id),32'd3,32'd11};
            i_dehaze_terminal_key={camera[0],32'd11,32'd3,32'(seq_id)};
            i_he_source_camera=camera;i_he_source_sequence=seq_id;i_he_source_session=11;i_he_source_epoch=3;
            for(integer k=0;k<256;k++)next_hist[k]=0;
            cdf=0;first=0;
            for(integer k=0;k<256;k++)begin
                cdf+=histogram[camera][k];if(first==0&&cdf!=0)first=cdf;
                map_y[k]=first==W*H ? k : first==0 ? 0 : (cdf-first)*255/(W*H-first);
            end
            n_enhanced=0;n_output=0;dcp_changes=0;he_changes=0;done_seen=0;
            expected_dcp=have_dcp;expected_he=have_he;checking=1;i_filter_start_valid=1;
            do @(posedge clk);while(!o_filter_start_ready);
            @(negedge clk);i_filter_start_valid=0;
            for(integer y=0;y<H;y++)for(integer x=0;x<W;x+=4)begin
                for(integer k=0;k<4;k++)word[24*k+:24]=pixel(x+k,y,camera);
                original[(y*W+x)/4]=word;
                s_valid=1;s_data=word;s_sof=(x==0&&y==0);s_eol=x==W-4;
                do @(posedge clk);while(!s_ready);
                @(negedge clk);
            end
            s_valid=0;s_sof=0;s_eol=0;s_frame_done=1;
            @(negedge clk);s_frame_done=0;i_he_source_valid=1;i_he_source_ok=1;
            do @(posedge clk);while(!o_he_source_ready);
            @(negedge clk);i_he_source_valid=0;
            if(dcp_on)begin
                // A foreign success has identical session/epoch/sequence. Only
                // the camera bit differs; it cannot publish this pending map.
                i_dehaze_terminal_key[96]=!camera[0];i_dehaze_terminal_valid=1;i_dehaze_terminal_ok=1;
                @(negedge clk);i_dehaze_terminal_valid=0;
                repeat(96)@(negedge clk);
                if(!o_dehaze_pending)$fatal(1,"wrong-eye SOURCE released estimator");
                i_dehaze_terminal_key[96]=camera[0];
            end
            i_dehaze_terminal_valid=1;i_dehaze_terminal_ok=1;
            @(negedge clk);i_dehaze_terminal_valid=0;
            wait(done_seen);@(negedge clk);
            if(n_enhanced!=N||n_output!=N||(have_dcp&&dcp_changes==0)||(have_he&&he_on&&he_changes==0))
                $fatal(1,"incomplete frame/effect: enhanced=%d out=%d changed=%d/%d",n_enhanced,n_output,dcp_changes,he_changes);
            $display("DCP_HE_FRAME eye=%0d seq=%0d history=%0d dehaze_changed_groups=%0d he_changed_pixels=%0d",eye,seq_id,have_dcp,dcp_changes,he_changes);
            for(integer k=0;k<256;k++)histogram[camera][k]=next_hist[k];
            checking=0;frame_count++;
            repeat(12000)@(negedge clk);
        end
    endtask
    task automatic abort_partial_cam1;
        begin
            @(negedge clk);eye=1;cfg_dehaze_enable=1;cfg_enable=4;
            cfg_he_capture_sequence=13;cfg_he_context={32'd11,32'd3,32'd0,16'd256,13'(W),13'(H),1'b1,3'd0};
            cfg_filter_context={63'd0,1'b1,32'd13,32'd3,32'd11};i_dehaze_terminal_key={1'b1,32'd11,32'd3,32'd13};
            i_filter_start_valid=1;do @(posedge clk);while(!o_filter_start_ready);
            @(negedge clk);i_filter_start_valid=0;
            for(integer k=0;k<16;k++)begin
                s_valid=1;s_sof=k==0;s_eol=0;s_data={4{24'hcd9911}};
                do @(posedge clk);while(!s_ready);@(negedge clk);
            end
            s_valid=0;s_sof=0;expect_cancel=1;
            i_dehaze_terminal_valid=1;i_dehaze_terminal_ok=0;s_frame_error=1;
            @(negedge clk);s_frame_error=0;i_dehaze_terminal_valid=0;
            repeat(1100)@(negedge clk);expect_cancel=0;
            if(o_dehaze_pending||dut.g_dehaze.u_restore.hist_seq[0]!==12||
               dut.g_dehaze.u_restore.hist_seq[1]!==12)$fatal(1,"truncated bad eye published or damaged good history");
            $display("DCP_HE_BAD_SOURCE PASS cam1 truncated seq=13, CAM0/CAM1 retain seq=12");
        end
    endtask
    initial begin
        cfg_width=W;cfg_height=H;cfg_schema2=1;cfg_he_history_eligible=1;
        i_window_ready=1;f22_record_ready=1;f23_record_ready=1;
        for(integer c=0;c<2;c++)for(integer b=0;b<256;b++)histogram[c][b]=0;
        repeat(10)@(negedge clk);rst_n=1;i_he_history_rst_n=1;repeat(550)@(negedge clk);
        send_frame(0,10,1,1,0,0);send_frame(1,10,1,1,0,0);
        send_frame(0,12,1,1,1,1);send_frame(1,12,1,1,1,1);
        abort_partial_cam1();
        send_frame(0,14,0,0,0,0);
        $display("RESULT: PASS JOINT_DCP_HE frame_count=%0d checked_pixels=%0d",frame_count,frame_count*W*H);$finish;
    end
