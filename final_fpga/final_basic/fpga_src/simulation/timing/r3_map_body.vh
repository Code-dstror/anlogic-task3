integer observations=0,commits=0,hidden_differences=0;
reg [159:0] expected_context;
task tick;begin @(posedge clk);#2;@(negedge clk);end endtask
always @(posedge clk)if(rst_n)begin
    if(map_commit)begin
        commits=commits+1;
        if(map_commit_context!==expected_context)$fatal(1,"R3 map published wrong held context");
    end
    if(!device.dut.owned&&device.dut.owned_context!==device.baseline.owned_context)
        hidden_differences=hidden_differences+1;
end
function automatic [208:0] cohort(input [31:0] session,epoch);
    cohort={session,epoch,32'd1000,16'd100,13'd120,13'd120,3'd0,1'b1,
        1'b1,8'd224,9'd128,8'd8,9'd16,8'd64,8'd48,8'd208,8'd24};
endfunction
task cfg_begin(input integer generation);
    begin
        cfg_generation=generation;cfg_begin_valid=1;
        do @(posedge clk);while(!cfg_begin_ready);
        @(negedge clk);cfg_begin_valid=0;
    end
endtask
task load_table;
    begin
        cfg_begin(1);
        for(integer n=0;n<=256;n=n+1)begin
            cfg_index=9'(n);cfg_value=n<64?0:11'((131072+n)/(2*n));cfg_valid=1;
            do @(posedge clk);while(!cfg_ready);
            @(negedge clk);cfg_valid=0;obs_context=160'(n*73+9);
        end
        cfg_commit_valid=1;do @(posedge clk);while(!cfg_commit_ready);
        @(negedge clk);cfg_commit_valid=0;
        repeat(8)tick();
        if(!cfg_status_valid||!cfg_status_ok||lut_generation!=1)$fatal(1,"R3 map load/status stall coverage");
        cfg_status_ready=1;tick();cfg_status_ready=0;
    end
endtask
task main_start(input integer capture);
    begin
        main_frame_id=capture;main_cohort=cohort(1,1);main_begin=1;
        do @(posedge clk);while(!main_begin_ready);
        @(negedge clk);main_begin=0;obs_frame_id=capture;obs_cohort=main_cohort;
    end
endtask
task pixels(input integer count,input [159:0] context_value);
    begin
        expected_context=context_value;
        for(integer n=0;n<count;n=n+1)begin
            obs_context=context_value;obs_valid=1;obs_sof=n==0;obs_eol=n%20==19;obs_last=n==399;
            obs_rgb={8'(40+n%20),8'(60+n/20),8'(80+(n*3)%80)};obs_y=8'(60+(n*5)%120);
            do @(posedge clk);while(!obs_ready);
            @(negedge clk);obs_valid=0;obs_context=context_value^160'hcd83921a;
            tick();
        end
        obs_valid=0;obs_sof=0;obs_eol=0;obs_last=0;obs_context=context_value;
        observations=observations+1;
    end
endtask
task source_event(input integer capture,input bit good);
    begin
        source_session=1;source_epoch=1;source_capture=capture;source_ok=good;source_valid=1;
        do @(posedge clk);while(!source_ready);
        @(negedge clk);source_valid=0;
    end
endtask
task status_event(input bit good,input [159:0] context_value);
    begin
        obs_context=context_value;obs_status_ok=good;obs_status_error=good?0:7;
        obs_status_pixels=400;obs_status_delivered=400;obs_status_valid=1;
        do @(posedge clk);while(!obs_status_ready);
        @(negedge clk);obs_status_valid=0;
    end
endtask
task await_commit(input integer number);
    integer guard;
    begin
        guard=0;while(commits<number&&guard<2000)begin tick();guard=guard+1;end
        if(commits!=number)$fatal(1,"R3 qualified map failed to publish");
        repeat(4)tick();
    end
endtask
task release_pin;
    integer guard;
    begin
        main_release=1;guard=0;while(main_pin_valid&&guard<30)begin tick();guard=guard+1;end
        if(main_pin_valid)$fatal(1,"R3 main pin did not retire");main_release=0;tick();
    end
endtask
initial begin
    i_history_eligible=1;cfg_status_ready=0;
    repeat(5)tick();rst_n=1;repeat(10)begin obs_context=obs_context+160'h11111234;tick();end
    load_table();
    // An independent load may abort while unowned payload freely changes.
    cfg_begin(2);cfg_abort=1;tick();cfg_abort=0;repeat(4)tick();
    if(!cfg_status_valid||cfg_status_ok||cfg_status_error!=4)$fatal(1,"R3 load abort coverage");
    cfg_status_ready=1;tick();cfg_status_ready=0;
    main_start(1);pixels(400,160'h101);source_event(1,1);status_event(1,160'h101);await_commit(1);
    main_start(2);pixels(97,160'h202);frame_cancel=1;tick();frame_cancel=0;repeat(5)tick();
    if(device.dut.owned||firstfault_context!==160'h202)$fatal(1,"R3 cancel lost old owned context");release_pin();
    debug_clear_firstfault=1;tick();debug_clear_firstfault=0;
    main_start(3);pixels(81,160'h303);source_event(3,0);repeat(5)tick();
    if(device.dut.owned||firstfault_context!==160'h303)$fatal(1,"R3 negative SOURCE lost context");release_pin();
    main_start(4);pixels(400,160'h404);source_event(4,1);status_event(1,160'h404);await_commit(2);release_pin();
    debug_clear_firstfault=1;tick();debug_clear_firstfault=0;
    main_start(5);pixels(400,160'h505);status_event(0,160'h505);repeat(5)tick();
    if(device.dut.owned||firstfault_context!==160'h505)$fatal(1,"R3 failed F20 lost context");
    source_event(5,1);release_pin();
    debug_clear_firstfault=1;tick();debug_clear_firstfault=0;
    main_start(32'hffffffff);pixels(1,160'h606);source_event(32'hffffffff,0);repeat(4)tick();release_pin();
    main_start(0);pixels(1,160'h707);status_event(0,160'h707);source_event(0,1);release_pin();
    if(firstfault_context!==160'h606)$fatal(1,"R3 wrapped unqualified frame leaked hidden context");
    // Reset and idle payload changes cannot leak a new visible diagnostic.
    history_reset=1;tick();history_reset=0;
    repeat(20)begin obs_context=obs_context+160'h129377;tick();end
    if(commits!=2||hidden_differences==0)$fatal(1,"R3 hidden payload/qualified publish coverage");
    $display("RESULT: PASS R3_F21_MAP observations=%0d commits=%0d hidden_differences=%0d cycles=%0d",
        observations,commits,hidden_differences,device.r3_checks);$finish;
end
initial begin #500000;$fatal(1,"R3 map watchdog");end
