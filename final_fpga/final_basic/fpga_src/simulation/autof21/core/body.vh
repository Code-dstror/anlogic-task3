integer commits=0,tiles=0,reads=0,status_holds=0,rejections=0,cycle=0;
reg [159:0] expected_context;
reg [19:0] expected_word={9'd128,11'd512};
reg check_read=0;
task tick;begin @(posedge clk);#2;@(negedge clk);end endtask
function automatic [208:0] cohort(input [31:0] session,epoch);
    cohort={session,epoch,32'd1000,16'd100,13'd120,13'd120,3'd0,1'b1,
        1'b1,8'd224,9'd128,8'd8,9'd16,8'd64,8'd48,8'd208,8'd24};
endfunction
always @(posedge clk)begin
    cycle=cycle+1;
    if(cycle>30000)$fatal(1,"core timeout");
    if(rst_n&&compare)begin
        if(candidate_tile_valid)begin
            if(candidate_tile_index!=0||candidate_tile_data!==expected_word)
                $fatal(1,"fixed scalar tile mismatch %h",candidate_tile_data);
            tiles=tiles+1;
        end
        if(map_commit)begin
            commits=commits+1;
            if(map_commit_context!==expected_context)$fatal(1,"held context changed");
        end
        if(main_reply_valid)begin
            if(check_read&&main_reply_data!==expected_word)$fatal(1,"pinned RAM reply changed");
            reads=reads+1;
        end
        if(cfg_status_valid&&!a_cfg_status_ready)begin
            if(cfg_status_ok||cfg_status_error!=4||cfg_status_generation!=1)$fatal(1,"fixed status changed");
            status_holds=status_holds+1;
        end
        if(auto_core.load_busy)$fatal(1,"auto entered loader");
        if(!lut_valid||lut_generation!=1)$fatal(1,"auto ROM invalidated");
    end
end
task reset_all;
    begin
        compare=0;rst_n=0;main_begin=0;main_release=0;main_req_valid=0;
        obs_valid=0;obs_status_valid=0;source_valid=0;frame_cancel=0;history_reset=0;
        a_cfg_begin_valid=0;a_cfg_valid=0;a_cfg_commit_valid=0;a_cfg_abort=0;
        m_cfg_begin_valid=0;m_cfg_valid=0;m_cfg_commit_valid=0;m_cfg_abort=0;
        a_cfg_status_ready=0;m_cfg_status_ready=0;
        repeat(5)tick();
        if(lut_valid||main_pin_valid||map_commit)$fatal(1,"reset visible state leaked");
        rst_n=1;
        repeat(6)tick();
        if(!lut_valid||lut_generation!=1||m_lut_valid||m_lut_generation!=0)
            $fatal(1,"cold auto/default-manual contract wrong");
        if(main_history_valid||auto_core.history_valid)$fatal(1,"cold history fabricated");
    end
endtask
task manual_load;
    begin
        m_cfg_generation=1;m_cfg_begin_valid=1;
        do @(posedge clk);while(!m_cfg_begin_ready);
        @(negedge clk);m_cfg_begin_valid=0;
        for(integer n=0;n<=256;n=n+1)begin
            m_cfg_index=9'(n);m_cfg_value=n<64?0:11'((131072+n)/(2*n));m_cfg_valid=1;
            do @(posedge clk);while(!m_cfg_ready);
            @(negedge clk);m_cfg_valid=0;
            // Every frozen entry is compared with the exact guide integer formula.
            if(auto_core.canonical_reciprocal(9'(n))!==m_cfg_value)$fatal(1,"ROM index %0d",n);
        end
        m_cfg_commit_valid=1;do @(posedge clk);while(!m_cfg_commit_ready);
        @(negedge clk);m_cfg_commit_valid=0;repeat(4)tick();
        if(!m_cfg_status_valid||!m_cfg_status_ok||m_lut_generation!=1||!m_lut_valid)$fatal(1,"manual G1 failed");
        m_cfg_status_ready=1;tick();m_cfg_status_ready=0;compare=1;
    end
endtask
task auto_reject(input integer kind);
    begin
        a_cfg_generation=32'hffffffff;a_cfg_index=256;a_cfg_value=11'h7ff;
        a_cfg_begin_valid=kind==0;a_cfg_valid=kind==1;a_cfg_commit_valid=kind==2;
        if(!cfg_begin_ready||!cfg_ready||!cfg_commit_ready)$fatal(1,"auto reject not bounded");
        tick();a_cfg_begin_valid=0;a_cfg_valid=0;a_cfg_commit_valid=0;
        if(!cfg_status_valid||cfg_status_ok||cfg_status_error!=4||cfg_status_generation!=1)$fatal(1,"auto did not reject");
        if(cfg_begin_ready||cfg_ready||cfg_commit_ready)$fatal(1,"unconsumed status overwritten");
        rejections=rejections+1;
    end
endtask
task ack_auto;
    begin a_cfg_status_ready=1;tick();a_cfg_status_ready=0;tick();end
endtask
task main_start(input integer capture,input bit expected_history);
    begin
        main_frame_id=capture;main_cohort=cohort(1,1);main_begin=1;
        do begin
            @(posedge clk);
            if(main_begin_ready&&main_history_valid!==expected_history)$fatal(1,"history selection capture%0d",capture);
        end while(!main_begin_ready);
        @(negedge clk);main_begin=0;obs_frame_id=capture;obs_cohort=main_cohort;
    end
endtask
task pixels(input integer count,input [159:0] context_value);
    begin
        expected_context=context_value;
        for(integer n=0;n<count;n=n+1)begin
            obs_context=context_value;obs_valid=1;obs_sof=n==0;obs_eol=n%20==19;obs_last=n==399;
            obs_rgb={8'd96,8'd112,8'd128};obs_y=109;
            do @(posedge clk);while(!obs_ready);
            @(negedge clk);obs_valid=0;
        end
        obs_valid=0;obs_sof=0;obs_eol=0;obs_last=0;
    end
endtask
task source_event(input integer capture,input bit good);
    begin
        source_session=1;source_epoch=1;source_capture=capture;source_ok=good;source_valid=1;
        do @(posedge clk);while(!source_ready);
        @(negedge clk);source_valid=0;
    end
endtask
task status_event(input bit good);
    begin
        obs_status_ok=good;obs_status_error=good?0:7;
        obs_status_pixels=400;obs_status_delivered=400;obs_status_valid=1;
        do @(posedge clk);while(!obs_status_ready);
        @(negedge clk);obs_status_valid=0;
    end
endtask
task await_commit(input integer number);
    integer guard;
    begin
        guard=0;while(commits<number&&guard<2000)begin tick();guard=guard+1;end
        if(commits!=number)$fatal(1,"qualified map did not publish");repeat(4)tick();
    end
endtask
task release_pin;
    begin main_release=1;repeat(7)tick();if(main_pin_valid)$fatal(1,"pin stuck");main_release=0;tick();end
endtask
initial begin
    i_history_eligible=1;
    reset_all();manual_load();
    // No observation/load may invent a previous-frame map at first admission.
    main_start(1,0);
    auto_reject(0);
    pixels(400,160'h101);source_event(1,1);status_event(1);await_commit(1);
    // An unconsumed immutable-table status must not block map publication.
    if(status_holds<400||!cfg_status_valid)$fatal(1,"status isolation not exercised");ack_auto();
    main_start(2,1);
    if(!main_pin_valid||main_pin_capture!=2||main_pin_a!=96)$fatal(1,"real history not pinned");
    auto_reject(1);a_cfg_abort=1;repeat(4)tick();a_cfg_abort=0;
    check_read=1;main_req_tile=0;main_req_valid=1;
    do @(posedge clk);while(!main_req_ready);
    @(negedge clk);main_req_valid=0;
    frame_cancel=1;tick();frame_cancel=0;history_reset=1;tick();history_reset=0;
    repeat(8)tick();
    if(reads!=1||!main_pin_valid||!cfg_status_valid)$fatal(1,"cleanup retracted pinned read/status");
    release_pin();ack_auto();auto_reject(2);ack_auto();
    main_start(3,0);pixels(400,160'h303);source_event(3,1);status_event(1);await_commit(2);
    main_start(4,1);pixels(97,160'h404);frame_cancel=1;tick();frame_cancel=0;repeat(5)tick();
    if(auto_core.owned||firstfault_context!==160'h404)$fatal(1,"cancel owner/context");release_pin();
    main_start(5,1);pixels(81,160'h505);source_event(5,0);repeat(5)tick();
    if(auto_core.owned||auto_core.history_valid)$fatal(1,"negative source published/kept history");release_pin();
    main_start(6,0);pixels(400,160'h606);source_event(6,1);status_event(1);await_commit(3);
    main_start(7,1);pixels(400,160'h707);status_event(0);repeat(5)tick();
    if(auto_core.owned||auto_core.history_valid||commits!=3)$fatal(1,"failed F20 qualification");release_pin();
    // An in-flight partial observation is removed by real reset; no stale map.
    main_start(8,0);pixels(5,160'h808);
    reset_all();manual_load();main_start(1,0);
    if(commits!=3||tiles!=3||reads!=1||rejections!=3||comparisons<2000)$fatal(1,"coverage missing");
    $display("RESULT: PASS AUTO_F21_CORE comparisons=%0d commits=%0d tiles=%0d reads=%0d rejections=%0d status_holds=%0d ROM_entries=257 cold_resets=2",comparisons,commits,tiles,reads,rejections,status_holds);
    $finish;
end
