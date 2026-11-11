integer checks=0,commands=0,pixel_ticks=0,reads=0,pin_reads=0,resets=0;
reg [31:0] got;
reg check_pixel=0;
reg old_core_run=0;
time last_pixel_edge=0;
always @(posedge i_pixel_clk)begin
    last_pixel_edge=$time;pixel_ticks=pixel_ticks+1;
    if(check_pixel)begin
        if(!o_pixel_lut_valid||!lut_valid||lut_generation!=1||!map_main_req_ready)
            $fatal(1,"USER activity interfered with PIX map ownership");
        if(map_main_reply_valid)begin
            if(map_main_reply_data!=={9'd128,11'd512})$fatal(1,"pinned map data changed");
            pin_reads=pin_reads+1;
        end
    end
    #1;
    if(cfg_begin_valid||cfg_valid||cfg_commit_valid||cfg_abort||!cfg_status_ready||
       o_pixel_fault||o_pixel_loading||o_pixel_update_busy||o_user_busy||o_stale_reply_count!=0)
        $fatal(1,"fixed service produced a loader/busy/fault side effect");
end
always @(o_core_reset_n)if($time>0&&$time!=last_pixel_edge)$fatal(1,"kernel reset changed between pixel edges");
always @(posedge i_user_clk)if(dut.user_rst_n)begin
    #1;
    if(dut.user_lut_valid!==
       (dut.ready_sync&&i_user_session_ready&&i_user_session!=0))$fatal(1,"USER readiness gate mismatch");
end
task utick;begin @(posedge i_user_clk);#1;@(negedge i_user_clk);end endtask
task ptick;begin @(posedge i_pixel_clk);#1;@(negedge i_pixel_clk);end endtask
task write_reg(input [11:0] offset,input [31:0] data,input [3:0] strobes,input [1:0] response);
    begin
        @(negedge i_user_clk);write_offset=offset;write_data=data;write_strobes=strobes;write_valid=1;
        #1;if(write_response!==response)$fatal(1,"write response offset%h",offset);
        utick();write_valid=0;checks=checks+1;
    end
endtask
task read_reg(input [11:0] offset,input [1:0] response);
    begin
        @(negedge i_user_clk);read_offset=offset;read_valid=1;
        @(posedge i_user_clk);#1;
        if(!read_response_valid||read_response!==response)$fatal(1,"read response offset%h",offset);
        got=read_data;@(negedge i_user_clk);read_valid=0;reads=reads+1;
    end
endtask
task read_equals(input [11:0] offset,input [31:0] expected);
    begin read_reg(offset,0);if(got!==expected)$fatal(1,"read %h got%h expected%h",offset,got,expected);checks=checks+1;end
endtask
task ready_status(input bit valid);
    begin
        read_reg(`PCIE_REG_ALGO_STATUS,0);
        if(got[3]!==valid||got[4]||got[0])$fatal(1,"live status ready%0d got%h",valid,got);
        read_equals(`PCIE_REG_ALGO_ACTIVE_GENERATION,1);
    end
endtask
task set_fields(input integer session_value,sequence_value,target_value);
    begin
        write_reg(`PCIE_REG_ALGO_TARGET,target_value,15,0);
        write_reg(`PCIE_REG_ALGO_SESSION,session_value,15,0);
        write_reg(`PCIE_REG_ALGO_SEQUENCE,sequence_value,15,0);
        write_reg(`PCIE_REG_ALGO_GENERATION,0,15,0);
        write_reg(`PCIE_REG_ALGO_INDEX,0,15,0);
        write_reg(`PCIE_REG_ALGO_VALUE,0,15,0);
    end
endtask
task command(input integer opcode,session_value,sequence_value,target_value,error_value);
    begin
        set_fields(session_value,sequence_value,target_value);
        write_reg(`PCIE_REG_ALGO_COMMAND,opcode,15,0);
        read_equals(`PCIE_REG_ALGO_RESPONSE_SEQUENCE,sequence_value);
        read_equals(`PCIE_REG_ALGO_RESPONSE_SESSION,session_value);
        read_equals(`PCIE_REG_ALGO_RESULT_GENERATION,1);
        read_equals(`PCIE_REG_ALGO_ERROR,error_value);
        read_reg(`PCIE_REG_ALGO_STATUS,0);
        if(!got[1]||got[2]!=(error_value!=0)||!got[3]||got[4]||got[0])$fatal(1,"command terminal status %h",got);
        commands=commands+1;
    end
endtask
task reset_side(input integer side);
    begin
        check_pixel=0;
        @(negedge i_user_clk);
        if(side!=2)i_user_rst_n=0;
        if(side!=1)i_pixel_rst_n=0;
        #1;if(dut.ready_meta||dut.ready_sync||read_response_valid)$fatal(1,"cohort USER isolation not asynchronous");
        repeat(7)ptick();
        if(o_pixel_lut_valid||o_core_reset_n||o_user_reset_done)$fatal(1,"cohort reset failed");
        i_user_rst_n=1;i_pixel_rst_n=1;
        repeat(18)ptick();repeat(5)utick();
        if(!o_user_reset_done||!o_pixel_reset_done||!o_pixel_lut_valid||!lut_valid||lut_generation!=1)
            $fatal(1,"no-command cold G1 failed side%0d",side);
        read_equals(`PCIE_REG_ALGO_RESPONSE_SEQUENCE,0);
        read_equals(`PCIE_REG_ALGO_RESPONSE_SESSION,0);
        read_equals(`PCIE_REG_ALGO_STATUS,8);
        resets=resets+1;
    end
endtask
task build_and_pin;
    begin
        map_i_history_eligible=1;
        map_main_cohort={32'd9,32'd1,32'd1000,16'd100,13'd120,13'd120,3'd0,1'b1,
            1'b1,8'd224,9'd128,8'd8,9'd16,8'd64,8'd48,8'd208,8'd24};
        map_obs_cohort=map_main_cohort;map_main_frame_id=1;map_obs_frame_id=1;map_main_begin=1;
        do @(posedge i_pixel_clk);while(!map_main_begin_ready);
        @(negedge i_pixel_clk);map_main_begin=0;
        if(map_main_pin_valid)$fatal(1,"cold history invented");
        for(integer n=0;n<400;n=n+1)begin
            map_obs_valid=1;map_obs_sof=n==0;map_obs_eol=n%20==19;map_obs_last=n==399;
            map_obs_rgb={8'd96,8'd112,8'd128};map_obs_y=109;
            do @(posedge i_pixel_clk);while(!map_obs_ready);
            @(negedge i_pixel_clk);map_obs_valid=0;
        end
        map_obs_sof=0;map_obs_eol=0;map_obs_last=0;
        map_source_session=9;map_source_epoch=1;map_source_capture=1;map_source_ok=1;map_source_valid=1;
        do @(posedge i_pixel_clk);while(!map_source_ready);
        @(negedge i_pixel_clk);map_source_valid=0;
        map_obs_status_ok=1;map_obs_status_error=0;map_obs_status_pixels=400;map_obs_status_delivered=400;map_obs_status_valid=1;
        do @(posedge i_pixel_clk);while(!map_obs_status_ready);
        @(negedge i_pixel_clk);map_obs_status_valid=0;
        wait(map_map_commit);repeat(4)ptick();
        map_main_frame_id=2;map_main_begin=1;
        do @(posedge i_pixel_clk);while(!map_main_begin_ready);
        @(negedge i_pixel_clk);map_main_begin=0;
        if(!map_main_pin_valid||map_main_pin_a!=96)$fatal(1,"qualified pin missing");
        check_pixel=1;map_main_req_valid=1;map_main_req_tile=0;
    end
endtask
initial begin
    i_user_session=9;i_pixel_session=9;i_user_session_ready=1;i_pixel_session_ready=1;
    reset_side(0);
    read_equals(`PCIE_REG_ALGO_MAGIC,`PCIE_ALGO_MAGIC);
    read_equals(`PCIE_REG_ALGO_ABI_VERSION,`PCIE_ALGO_ABI_VERSION);
    read_equals(`PCIE_REG_ALGO_FEATURES,32'd1<<`PCIE_ALGO_FEATURE_F21);
    // Both USER and PIX readiness, and real nonzero sessions, gate raw status.
    i_user_session_ready=0;ready_status(0);i_user_session_ready=1;ready_status(1);
    i_user_session=0;ready_status(0);i_user_session=9;ready_status(1);
    @(negedge i_pixel_clk);i_pixel_session_ready=0;
    repeat(4)utick();ready_status(0);
    i_pixel_session_ready=1;repeat(4)utick();ready_status(1);
    i_pixel_session=0;repeat(4)utick();ready_status(0);
    i_pixel_session=9;repeat(4)utick();ready_status(1);
    // Shadow fields preserve byte strobes; COMMAND requires all four bytes.
    write_reg(`PCIE_REG_ALGO_GENERATION,32'h11223344,15,0);
    write_reg(`PCIE_REG_ALGO_GENERATION,32'haa00bb00,4'b1010,0);
    read_equals(`PCIE_REG_ALGO_GENERATION,32'haa22bb44);
    write_reg(`PCIE_REG_ALGO_GENERATION,32'hffffffff,0,0);
    read_equals(`PCIE_REG_ALGO_GENERATION,32'haa22bb44);
    write_reg(`PCIE_REG_ALGO_COMMAND,5,1,2);read_equals(`PCIE_REG_ALGO_RESPONSE_SEQUENCE,0);
    write_reg(12'hfff,0,15,2);read_reg(12'hfff,2);
    command(5,9,1,1,0);
    command(5,8,2,1,`PCIE_ALGO_ERROR_SESSION);
    command(5,9,1,1,`PCIE_ALGO_ERROR_SEQUENCE);
    command(5,9,2,2,`PCIE_ALGO_ERROR_INVALID);
    command(5,9,2,1,0);
    build_and_pin();
    // Ignored core status can stay asserted while USER does commands and reads.
    cfg_status_valid=1;cfg_status_ok=0;cfg_status_error=8'hff;cfg_status_generation=32'hdeadbeef;
    for(integer op=1;op<=4;op=op+1)begin
        command(op,9,2+op,1,`PCIE_ALGO_ERROR_CORE_STATE);
        repeat(3)utick();ready_status(1);
    end
    command(5,9,7,1,0);
    repeat(16)begin ready_status(1);read_equals(`PCIE_REG_ALGO_ERROR,0);end
    if(pin_reads<100)$fatal(1,"pixel requests did not continue through USER transactions");
    cfg_status_valid=0;map_main_req_valid=0;check_pixel=0;
    repeat(5)ptick();map_main_release=1;repeat(6)ptick();map_main_release=0;
    reset_side(1);reset_side(2);
    command(5,9,1,1,0);
    if(commands!=11||resets!=3)$fatal(1,"control coverage count commands%0d",commands);
    $display("RESULT: PASS FIXED_DEHAZE_CONTROL commands=%0d checks=%0d reads=%0d pixel_reads=%0d cold_resets=%0d pixel_ticks=%0d no_load=1",commands,checks,reads,pin_reads,resets,pixel_ticks);
    $finish;
end
initial begin #1000000;$fatal(1,"fixed control watchdog");end
