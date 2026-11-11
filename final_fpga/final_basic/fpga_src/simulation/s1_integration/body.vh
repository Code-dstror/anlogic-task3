    localparam integer GROUPS=518400;
    reg [127:0] source_words[0:GROUPS-1],gold[0:GROUPS-1];
    integer cycle=0,outputs=0,inputs=0,frame_number=0,commits=0;
    integer held_checks=0,eof_stalls=0,stall_budget=0;
    reg expect_history=0,compare_output=0,held=0;
    reg [129:0] held_word;
    reg [31:0] random_state=32'h51a0ba21;
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
        if(cycle>12000000)begin
            $display("S1_WATCHDOG frame=%0d inputs=%0d outputs=%0d commits=%0d source_valid=%b source_ready=%b frame_quiet=%b map_state=%0d sampled=%0d map_firstfault=%0d f20_pending=%b observer_busy=%b obsvalid=%b pin=%b wrapper_busy=%b",frame_number,inputs,outputs,commits,source_valid,source_ready,o_frame_quiet,dut.u_map.state,dut.u_map.sampled,dut.u_map.firstfault,dut.f20_pending,dut.observer_busy,dut.observe_pixel_valid,dut.map_pin_valid,dut.wrapper_busy);
            $fatal(1,"S1 service watchdog");
        end
        if(!rst_n)held=0;
        else begin
            if(o_map_commit)commits=commits+1;
            if(compare_output)begin
                if(o_fault||m_frame_error)$fatal(1,"service fault frame%0d input%0d output%0d",frame_number,inputs,outputs);
                if(s_valid&&s_ready)inputs=inputs+1;
                if(held)begin
                    if(!m_valid||word!==held_word)$fatal(1,"output changed while stalled");
                    held_checks=held_checks+1;
                end
                if(m_valid&&m_ready)begin
                    if(outputs>=GROUPS)$fatal(1,"extra output");
                    if({m_y,m_rgb}!==gold[outputs])$fatal(1,"S1 independent RGB/Y frame%0d group%0d got%h expected%h",frame_number,outputs,{m_y,m_rgb},gold[outputs]);
                    if(m_sof!==(outputs==0)||m_eol!==(outputs%480==479))$fatal(1,"geometry");
                    if(o_history_used!==expect_history)$fatal(1,"history frame%0d got%b expected%b",frame_number,o_history_used,expect_history);
                    outputs=outputs+1;
                end
                held=m_valid&&!m_ready;held_word=word;
            end else held=0;
        end
    end
    task cold_reset;
        begin
            compare_output=0;s_valid=0;s_frame_done=0;source_valid=0;
            rst_n=0;i_processing_rst_n=0;
            repeat(8)@(negedge clk);
            rst_n=1;i_processing_rst_n=1;
            repeat(20)@(negedge clk);
            if(!lut_valid||lut_generation!=1)$fatal(1,"immutable G1 after reset");
        end
    endtask
    task start_frame(input integer capture,input bit enhanced,input bit bypass);
        begin
            frame_number=frame_number+1;
            outputs=0;inputs=0;expect_history=enhanced;stall_budget=17;
            if(enhanced)$readmemh("fixtures/expected.hex",gold);
            else $readmemh("fixtures/source.hex",gold);
            // Session/epoch/capture occupy the public context layout, and
            // exposure/gain exactly match the cohort observed by real F20.
            frame_owner={32'h10203040,32'(capture)};frame_capture=capture;
            frame_context={32'd0,32'd0,32'(capture),32'd1,32'h10203040};
            frame_cohort={32'h10203040,32'd1,32'd1000,16'd256,13'd1920,13'd1080,
                3'd1,1'b0,1'b1,8'd224,9'd128,8'd8,9'd16,8'd80,8'd48,8'd208,8'd24};
            frame_cohort[66]=!bypass;
            @(negedge clk);i_source_frame_begin=1;i_product_begin=0;
            @(negedge clk);i_source_frame_begin=0;i_product_begin=0;
            i_filter_start_valid=1;
            do @(posedge clk);while(!o_filter_start_ready);
            @(negedge clk);i_filter_start_valid=0;
            compare_output=1;
        end
    endtask
    task send_pixels(input integer count);
        begin
            fork
                begin
                    // Product admission follows the actual processed SOF,
                    // exactly one pulse even if the input is backpressured.
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
    task finish_frame(input bit observe);
        integer old_commits;
        begin
            old_commits=commits;
            @(negedge clk);s_frame_done=1;
            @(negedge clk);s_frame_done=0;
            if(observe)begin
                // SOURCE can precede delayed F20 status and coefficient scan.
                source_session=32'h10203040;source_epoch=1;source_capture=frame_capture;
                source_ok=1;source_valid=2;
                do @(posedge clk);while(!source_ready[1]);
                @(negedge clk);source_valid=0;
            end
            wait(outputs==GROUPS);
            wait(o_frame_quiet);
            if(observe)wait(commits==old_commits+1);
            @(negedge clk);i_frame_released=1;
            @(negedge clk);i_frame_released=0;
            repeat(8)@(negedge clk);
            if(outputs!=GROUPS||inputs!=GROUPS)$fatal(1,"count mismatch");
            compare_output=0;
            $display("S1_SERVICE_FRAME PASS frame=%0d history=%0d inputs=%0d outputs=%0d",frame_number,expect_history,inputs,outputs);
        end
    endtask
    initial begin
        cfg_schema2=1;cfg_enable=0;cfg_he_history_eligible=1;
        m_stats_ready=1;f22_record_ready=1;f23_record_ready=1;i_window_ready=1;cfg_status_ready=1;
        $readmemh("fixtures/source.hex",source_words);
        cold_reset();
        start_frame(1,0,0);send_pixels(GROUPS);finish_frame(1);
        start_frame(2,1,0);send_pixels(GROUPS);finish_frame(1);
        // Reset an owned partial enhanced frame, then recover without history.
        start_frame(3,1,0);send_pixels(701);cold_reset();
        start_frame(1,0,0);send_pixels(GROUPS);finish_frame(1);
        // F21 disabled by the public frozen cohort; the rest of the service
        // remains the real pipeline and emits untouched RGB and computed Y.
        start_frame(2,0,1);send_pixels(GROUPS);finish_frame(0);
        if(held_checks<40||eof_stalls<60)$fatal(1,"stall coverage missing");
        $display("RESULT: PASS S1_SERVICE frames=4 reset_partial=1 full_hd_groups=%0d held_checks=%0d eof_stalls=%0d",4*GROUPS,held_checks,eof_stalls);
        $finish;
    end
