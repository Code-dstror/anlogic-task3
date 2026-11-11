`timescale 1ns/1ps
module tb_stereo_store;
    parameter integer DIVISOR=1;
    parameter integer RUNTIME_CADENCE=0;
    parameter integer STOP_BEFORE_REPLAY=0;
    localparam W=68,H=52,G=W*H/4,BYTES=G*5;
    reg pix=0,clk=0,rst=0;
    always #4 pix=~pix;
    always #5 clk=~clk;
    reg enable=1,stop=0,cfg=0;
    wire cfg_ready,cfg_applied,front_quiet,front_fault;
    reg [39:0] raw[0:1];reg [1:0] raw_valid=0,sof=0,eol=0,source_valid=0,source_ok=3;
    reg [31:0] frame_sequence[0:1];reg [196:0] metadata[0:1];
    wire [1:0] source_ready,begin_valid,begin_ready,begin_accepted,finish_valid,finish_ok,finish_ready;
    wire [383:0] frame0,frame1;
    wire [1:0] slot0,slot1;
    wire [3:0] awid,bid,arid,rid;wire [27:0] awaddr,araddr;
    wire [7:0] awlen,arlen;wire [2:0] awsize,arsize;wire [1:0] awburst,arburst,bresp,rresp;
    wire awvalid,awready,wvalid,wready,wlast,bvalid,bready,arvalid,arready,rvalid,rready,rlast;
    wire [127:0] wdata,rdata;wire [15:0] wstrb;
    reg [31:0] cycle=0;
    always @(posedge clk)cycle<=cycle+1;
    wire [31:0] selected0,selected1,observed0,observed1;
    dual_raw_capture_frontend #(.WIDTH(W),.HEIGHT(H),.STEREO_ENABLE(1),
        .STEREO_CAPTURE_DIVISOR(RUNTIME_CADENCE!=0?4:DIVISOR),.STEREO_RUNTIME_CADENCE(RUNTIME_CADENCE)) capture(
        .i_stereo_mode_pixel(1'b1),.pixel_clk(pix),.dfi_clk(clk),.cold_rst_n(rst),
        .i_stereo_frame_divisor_pixel(DIVISOR[7:0]),
        .region_grant(1'b1),.stop(stop),.app_reset(1'b0),.capture_enable(enable),
        .select_valid(cfg),.select_sdr(1'b1),.select_session(32'd17),.select_epoch(32'd3),
        .select_ready(cfg_ready),.select_applied(cfg_applied),.select_error(),
        .route_sdr(),.active_session(),.active_epoch(),.policy_quiet(1'b1),.policy_admit(enable),
        .policy_stop(),.local_quiet(front_quiet),.region_quiet(),
        .capture_enqueue_fire(),.capture_consume_fire(),.capture_idle(),.capture_frame_accept(),.capture_writer_quiet(),
        .source_stale_count(),.capture_drops(),.capture_errors(),
        .capture_enqueue_fire1(),.capture_consume_fire1(),.capture_idle1(),.capture_frame_accept1(),.source_stale_count1(),
        .raw_data(raw[0]),.raw_valid(raw_valid[0]),.raw_accept(1'b1),.raw_sof(sof[0]),.raw_eol(eol[0]),.raw_abort(1'b0),
        .raw_sequence(frame_sequence[0]),.raw_metadata(metadata[0]),.time_valid(1'b1),.bayer_valid(1'b1),.bayer_pattern(2'd2),
        .source_valid(source_valid[0]),.source_ready(source_ready[0]),.source_session(32'd17),.source_epoch(32'd3),
        .source_sequence(frame_sequence[0]),.source_camera(1'b0),.source_ok(source_ok[0]),.source_error(source_ok[0]?8'd0:8'd9),
        .capture_frame(frame0),.begin_valid(begin_valid[0]),.begin_ready(begin_ready[0]),.begin_accepted(begin_accepted[0]),.capture_slot(slot0),
        .finish_valid(finish_valid[0]),.finish_ok(finish_ok[0]),.finish_ready(finish_ready[0]),
        .source_frames(observed0),.selected_frames(selected0),.skipped_frames(),
        .raw_data1(raw[1]),.raw_valid1(raw_valid[1]),.raw_accept1(1'b1),.raw_sof1(sof[1]),.raw_eol1(eol[1]),.raw_abort1(1'b0),
        .raw_sequence1(frame_sequence[1]),.raw_metadata1(metadata[1]),
        .source_valid1(source_valid[1]),.source_ready1(source_ready[1]),.source_session1(32'd17),.source_epoch1(32'd3),
        .source_sequence1(frame_sequence[1]),.source_camera1(1'b1),.source_ok1(source_ok[1]),.source_error1(source_ok[1]?8'd0:8'd9),
        .capture_frame1(frame1),.begin_valid1(begin_valid[1]),.begin_ready1(begin_ready[1]),.begin_accepted1(begin_accepted[1]),.capture_slot1(slot1),
        .finish_valid1(finish_valid[1]),.finish_ok1(finish_ok[1]),.finish_ready1(finish_ready[1]),
        .source_frames1(observed1),.selected_frames1(selected1),.skipped_frames1(),.fault(front_fault),
        .m_axi_awid(awid),.m_axi_awaddr(awaddr),.m_axi_awlen(awlen),.m_axi_awsize(awsize),.m_axi_awburst(awburst),
        .m_axi_awvalid(awvalid),.m_axi_awready(awready),.m_axi_wdata(wdata),.m_axi_wstrb(wstrb),
        .m_axi_wlast(wlast),.m_axi_wvalid(wvalid),.m_axi_wready(wready),
        .m_axi_bid(bid),.m_axi_bresp(bresp),.m_axi_bvalid(bvalid),.m_axi_bready(bready));
    reg begin_hold=0,begin_camera=0,turn=0;
    wire store_begin_ready,store_begin_accepted;wire [1:0] store_slot;
    always @(posedge clk or negedge rst)begin
        if(!rst)begin begin_hold<=0;begin_camera<=0;turn<=0;end
        else begin
            if(!begin_hold&&|begin_valid)begin begin_hold<=1;begin_camera<=(&begin_valid)?turn:begin_valid[1];end
            if(begin_hold&&store_begin_ready)begin begin_hold<=0;turn<=!begin_camera;end
        end
    end
    assign begin_ready={store_begin_ready&&begin_hold&&begin_camera,store_begin_ready&&begin_hold&&!begin_camera};
    assign begin_accepted={2{store_begin_accepted}};assign slot0=store_slot;assign slot1=store_slot;
    wire job_valid,owner_empty,store_fault,read_quiet;reg job_ready=0;
    wire [383:0] job_frame;wire [63:0] job_lease,job_id;wire [1:0] job_bayer;wire job_time;
    reg retire_valid=0;reg [63:0] retire_id=0;wire retire_ready,retire_done,retire_error;
    reg req_valid=0;wire req_ready;reg [2:0] req_op=0;reg req_camera=0;reg [1:0] req_slot=0;
    reg [31:0] req_gen=0,req_session=17;reg [63:0] req_lease=0,req_job=0;
    wire rsp_valid;reg rsp_ready=0;wire [3:0] rsp_code;wire rsp_camera;wire [1:0] rsp_slot;
    wire [31:0] rsp_gen,rsp_session,rsp_sequence,rsp_epoch;
    reg process_done=0,process_error=0;reg [63:0] process_job=0;wire native_done,native_error;wire [63:0] native_job;
    wire [146:0] token;wire token_valid;integer last_hold=0;
    wire token_ready=(cycle%7!=0)&&(cycle%11!=0)&&!(token_valid&&token[146:145]==0&&token[102]&&last_hold<5);
    stereo_raw_store #(.WIDTH(W),.HEIGHT(H)) store(
        // This fixture exercises the local reader configuration.
        .o_decode_start_valid(),.i_decode_start_ready(1'b0),.o_decode_release(),.o_decode_cancel(),.o_decode_run(),
        .o_decode_data(),.o_decode_keep(),.o_decode_valid(),.o_decode_last(),.i_decode_ready(1'b0),
        .i_decode_raw(40'd0),.i_decode_raw_valid(1'b0),.o_decode_raw_ready(),
        .i_decode_sof(1'b0),.i_decode_eol(1'b0),.i_decode_done(1'b0),.i_decode_aborted(1'b0),.i_decode_quiet(1'b1),
        .clk(clk),.rst_n(rst),.i_enable(enable),.i_stop(stop),.i_session(32'd17),.i_epoch(32'd3),
        .s_frame(begin_camera?frame1:frame0),.s_begin_valid(begin_hold),.i_begin_camera(begin_camera),
        .s_begin_ready(store_begin_ready),.o_begin_accepted(store_begin_accepted),.o_capture_slot(store_slot),
        .i_finish_valid(finish_valid),.i_finish_ok(finish_ok),.o_finish_ready(finish_ready),
        .o_job_valid(job_valid),.i_job_ready(job_ready),.o_job_frame(job_frame),.o_job_lease(job_lease),.o_job_id(job_id),
        .o_job_bayer(job_bayer),.o_job_time_valid(job_time),
        .i_retire_valid(retire_valid),.i_retire_job_id(retire_id),.i_release_quiet(1'b1),
        .o_retire_ready(retire_ready),.o_retire_done(retire_done),.o_retire_error(retire_error),
        .i_req_valid(req_valid),.o_req_ready(req_ready),.i_req_op(req_op),.i_req_camera(req_camera),.i_req_slot(req_slot),
        .i_req_generation(req_gen),.i_req_session(req_session),.i_req_lease(req_lease),.i_req_job_id(req_job),
        .o_rsp_valid(rsp_valid),.i_rsp_ready(rsp_ready),.o_rsp_code(rsp_code),.o_rsp_camera(rsp_camera),.o_rsp_slot(rsp_slot),
        .o_rsp_generation(rsp_gen),.o_rsp_session(rsp_session),.o_rsp_sequence(rsp_sequence),.o_rsp_epoch(rsp_epoch),
        .i_processing_done(process_done),.i_processing_error(process_error),.i_processing_job_id(process_job),
        .o_native_done(native_done),.o_native_error(native_error),.o_native_job_id(native_job),
        .m_fifo_data(token),.m_fifo_valid(token_valid),.m_fifo_ready(token_ready),
        .o_read_quiet(read_quiet),.o_empty(owner_empty),.o_fault(store_fault),
        .m_axi_arid(arid),.m_axi_araddr(araddr),.m_axi_arlen(arlen),.m_axi_arsize(arsize),.m_axi_arburst(arburst),
        .m_axi_arvalid(arvalid),.m_axi_arready(arready),.m_axi_rid(rid),.m_axi_rdata(rdata),.m_axi_rresp(rresp),
        .m_axi_rlast(rlast),.m_axi_rvalid(rvalid),.m_axi_rready(rready));
    byte memory[0:32767];
    function integer loc(input [27:0] address);
        reg [27:0] offset;
        begin offset=address-28'h2000000;loc=offset[26]*16384+offset[25:24]*8192+offset[12:0];end
    endfunction
    reg write_active=0,b_pending=0,b_valid=0;reg [27:0] write_address=0;reg [4:0] write_left=0;reg [3:0] write_id=0;
    integer b_wait=0;reg [1:0] b_response=0;reg fail_write0=0;
    assign awready=!write_active&&!b_pending&&!b_valid&&cycle%5!=0;
    assign wready=write_active&&cycle%4!=0;
    assign bvalid=b_valid;assign bid=write_id;assign bresp=b_response;
    reg read_active=0,r_valid=0;reg [27:0] read_address=0;reg [4:0] read_left=0;reg [3:0] read_id=0;
    integer ar_count=0;
    reg [127:0] read_data=0;reg r_last=0;reg [1:0] read_response=0;reg fail_read=0,block_ar=0;
    assign arready=!read_active&&!r_valid&&cycle%3!=0&&!block_ar;
    assign rvalid=r_valid;assign rdata=read_data;assign rid=read_id;assign rresp=read_response;assign rlast=r_last;
    integer byte_index;
    always @(posedge clk or negedge rst)begin
        if(!rst)begin write_active<=0;b_pending<=0;b_valid<=0;b_wait<=0;read_active<=0;r_valid<=0;end
        else begin
            if(awvalid&&awready)begin
                if(awsize!=4||awburst!=1||awlen>15||({1'b0,awaddr[11:0]}+(awlen+1)*16)>4096)$fatal(1,"bad AW");
                write_active<=1;write_address<=awaddr;write_left<=awlen+1;write_id<=awid;
            end
            if(wvalid&&wready)begin
                if(wlast!=(write_left==1))$fatal(1,"bad WLAST");
                for(byte_index=0;byte_index<16;byte_index=byte_index+1)if(wstrb[byte_index])memory[loc(write_address)+byte_index]<=wdata[byte_index*8+:8];
                write_address<=write_address+16;write_left<=write_left-1;
                if(wlast)begin write_active<=0;b_pending<=1;b_wait<=17;b_response<=fail_write0&&!write_address[26]?2:0;end
            end
            if(b_pending)begin
                if(b_wait!=0)b_wait<=b_wait-1;
                else begin b_pending<=0;b_valid<=1;end
            end
            if(b_valid&&bready)b_valid<=0;
            if(arvalid&&arready)begin
                if(arsize!=4||arburst!=1||arlen>15||({1'b0,araddr[11:0]}+(arlen+1)*16)>4096)$fatal(1,"bad AR");
                read_active<=1;read_address<=araddr;read_left<=arlen+1;read_id<=arid;
                ar_count<=ar_count+1;
            end
            if(!r_valid||rready)begin
                r_valid<=0;
                if(read_active&&cycle%5!=1)begin
                    r_valid<=1;r_last<=read_left==1;read_response<=fail_read?2:0;
                    for(byte_index=0;byte_index<16;byte_index=byte_index+1)read_data[byte_index*8+:8]<=memory[loc(read_address)+byte_index];
                    read_address<=read_address+16;read_left<=read_left-1;
                    if(read_left==1)read_active<=0;
                end
            end
        end
    end
    function [9:0] sample(input integer camera,seq,index);
        sample=(camera*311+seq*37+index*17+(index>>4))&1023;
    endfunction
    function [39:0] group(input integer camera,seq,index);
        group={sample(camera,seq,index*4+3),sample(camera,seq,index*4+2),sample(camera,seq,index*4+1),sample(camera,seq,index*4)};
    endfunction
    integer expected_frame_sequence[0:1];integer completed=0,checks=0;
    task automatic send_frames(input integer camera,seq,input bit good);
        integer f,g;
        begin
            expected_frame_sequence[camera]=seq;
            for(f=0;f<DIVISOR;f=f+1)begin
                @(negedge pix);frame_sequence[camera]=seq+f;metadata[camera]=0;metadata[camera][192]=1;
                metadata[camera][63:0]=64'd100000+seq*100;source_ok[camera]=good;
                for(g=0;g<G;g=g+1)begin
                    raw[camera]=group(camera,seq+f,g);raw_valid[camera]=1;sof[camera]=g==0;eol[camera]=g%(W/4)==W/4-1;
                    @(negedge pix);
                end
                raw_valid[camera]=0;sof[camera]=0;eol[camera]=0;
                repeat(4)@(negedge pix);
                source_valid[camera]=1;
                do @(posedge pix);while(!source_ready[camera]);
                @(negedge pix);source_valid[camera]=0;
                repeat(80)@(negedge pix);
            end
        end
    endtask
    task automatic request(input [2:0] op,input [3:0] expected_code);
        begin
            @(negedge clk);req_op=op;req_valid=1;
            do @(posedge clk);while(!req_ready);
            @(negedge clk);req_valid=0;
            wait(rsp_valid);repeat(3)@(negedge clk);
            if(rsp_code!==expected_code||rsp_camera!==req_camera||rsp_gen!==req_gen)
                $fatal(1,"bad private response op=%0d code=%0d expected=%0d stop=%0d",op,rsp_code,expected_code,stop);
            rsp_ready=1;@(negedge clk);rsp_ready=0;checks=checks+1;
        end
    endtask
    integer output_group=0,fences=0;reg checking=0,expect_error=0;integer checking_camera=0,checking_sequence=0;
    reg [63:0] checking_job=0;reg [146:0] stalled_token;reg held_token=0;
    integer lane;
    always @(posedge clk)if(rst)begin
        if(STOP_BEFORE_REPLAY!=0&&checking&&arvalid)$fatal(1,"STOP-before-REPLAY presented an AR");
        if(token_valid&&token[146:145]==0&&token[102]&&last_hold<5)last_hold=last_hold+1;
        if(held_token&&(!token_valid||token!==stalled_token))$fatal(1,"token changed while stalled");
        held_token=token_valid&&!token_ready;stalled_token=token;
        if(token_valid&&token_ready)begin
            if(!checking)$fatal(1,"unowned replay");
            if(token[146:145]==0)begin
                if(token[134:103]!==output_group||token[100]!=(output_group==0)||token[101]!=(output_group%(W/4)==W/4-1)||token[102]!=(output_group==G-1))$fatal(1,"RAW framing");
                for(lane=0;lane<4;lane=lane+1)if(token[lane*14+:14]!=={4'd0,sample(checking_camera,checking_sequence,output_group*4+lane)})$fatal(1,"RAW sample cam%0d seq%0d group%0d",checking_camera,checking_sequence,output_group);
                output_group=output_group+1;checks=checks+5;
            end else if(token[146:145]==1)begin
                if(token[95:32]!==checking_job||token[31:0]!==output_group||token[96]===expect_error)$fatal(1,"bad FENCE");
                if(STOP_BEFORE_REPLAY!=0&&(token[104:97]!=1||output_group!=0))$fatal(1,"missing zero-group cancelled FENCE");
                if(!expect_error&&output_group!=G)$fatal(1,"truncated good frame");
                fences=fences+1;checks=checks+1;
            end else $fatal(1,"unknown token");
        end
        if(front_fault||store_fault)$fatal(1,"unexpected protocol fault");
    end
    task automatic consume_job(input integer fault_mode);
        reg [383:0] frozen_frame;reg [63:0] frozen_job;integer target_fence,b,starting_ar_count;
        reg [39:0] expected_word;
        reg bad_read,cancel_read;
        begin
            bad_read=fault_mode==1;cancel_read=fault_mode==2;
            wait(job_valid);frozen_frame=job_frame;frozen_job=job_id;
            repeat(7)begin @(negedge clk);if(!job_valid||job_frame!==frozen_frame||job_id!==frozen_job)$fatal(1,"job stall changed");end
            if(job_frame[108:77]!==expected_frame_sequence[job_frame[4]]||job_frame[76:45]!=17||job_frame[140:109]!=3||job_frame[0]!=0||!job_id[63]||job_bayer!=2||!job_time)$fatal(1,"job identity");
            checking_camera=job_frame[4];checking_sequence=expected_frame_sequence[checking_camera];checking_job=job_id;
            req_camera=job_frame[4];req_slot=job_frame[6:5];req_gen=job_frame[44:13];req_lease=job_lease;req_job=job_id;
            for(b=0;b<BYTES;b=b+1)begin
                expected_word=group(checking_camera,checking_sequence,b/5);
                if(memory[checking_camera*16384+req_slot*8192+b]!==((expected_word>>(8*(b%5)))&8'hff))$fatal(1,"stored byte mismatch %0d",b);
                checks=checks+1;
            end
            job_ready=1;@(negedge clk);job_ready=0;
            checking=1;expect_error=fault_mode!=0;output_group=0;last_hold=0;target_fence=fences+1;
            fail_read=bad_read;block_ar=cancel_read;
            starting_ar_count=ar_count;
            // The processing member/context can be accepted before REPLAY.
            // STOP must still admit this exact owned capability for a zero-data
            // failure FENCE, allowing its real PIX context to reach a terminal.
            if(fault_mode==3)stop=1;
            // Wrong generation must not start a read.
            req_gen=req_gen+1;request(4,6);req_gen=req_gen-1;
            if(fault_mode==3)begin
                req_camera=!req_camera;request(4,6);req_camera=!req_camera;
                req_slot=req_slot^2'd1;request(4,6);req_slot=req_slot^2'd1;
                req_session=req_session^32'd1;request(4,6);req_session=req_session^32'd1;
                req_lease=req_lease^64'h100;request(4,6);req_lease=req_lease^64'h100;
                req_job=req_job^64'h100;request(4,6);req_job=req_job^64'h100;
            end
            if(fault_mode==3&&(ar_count!=starting_ar_count||fences!=target_fence-1||token_valid))
                $fatal(1,"STOP accepted a stale replay identity");
            request(4,0);
            if(cancel_read)begin
                wait(arvalid);stop=1;
                repeat(5)begin @(negedge clk);if(!arvalid)$fatal(1,"cancel withdrew AR");end
                block_ar=0;
            end
            wait(fences==target_fence);
            if(fault_mode==3&&(output_group!=0||ar_count!=starting_ar_count||arvalid))
                $fatal(1,"STOP-before-REPLAY issued data or AXI traffic");
            if(owner_empty)$fatal(1,"FENCE enqueue released RAW ownership");
            repeat(8)begin @(negedge clk);if(native_done)$fatal(1,"enqueue fabricated nativeDone");end
            process_job=req_job^64'h100;process_done=1;@(negedge clk);process_done=0;
            repeat(4)begin @(negedge clk);if(native_done)$fatal(1,"stale result released native");end
            process_job=req_job;process_error=fault_mode!=0;process_done=1;@(negedge clk);process_done=0;
            wait(native_done);if(native_job!==req_job||native_error!==(fault_mode!=0))$fatal(1,"native completion identity");
            @(negedge clk);request(5,0);
            retire_id=req_job^64'h100;retire_valid=1;do @(posedge clk);while(!retire_ready);
            @(negedge clk);retire_valid=0;wait(retire_done);if(!retire_error)$fatal(1,"stale owner retire accepted");
            @(negedge clk);retire_id=req_job;retire_valid=1;do @(posedge clk);while(!retire_ready);
            @(negedge clk);retire_valid=0;wait(retire_done);if(retire_error)$fatal(1,"owner retire failed");
            checking=0;fail_read=0;stop=0;completed=completed+1;
            request(4,6); // The retired descriptor is retained data, never a live capability.
            $display("STEREO_JOB camera=%0d sequence=%0d fault_mode=%0d groups=%0d",checking_camera,checking_sequence,fault_mode,output_group);
            repeat(5)@(negedge clk);
        end
    endtask
    initial begin
        raw[0]=0;raw[1]=0;frame_sequence[0]=0;frame_sequence[1]=0;metadata[0]=0;metadata[1]=0;
        #500;rst=1;repeat(100)@(negedge clk);cfg=1;
        $display("STEREO_STEP config_offer");
        do @(posedge clk);while(!cfg_ready);@(negedge clk);cfg=0;$display("STEREO_STEP config_accept");
        wait(cfg_applied);$display("STEREO_STEP config_applied");repeat(30)@(negedge clk);
        if(STOP_BEFORE_REPLAY!=0)begin
            send_frames(1,100,1);consume_job(3);
            repeat(100)@(negedge clk);
            if(!owner_empty||!read_quiet||ar_count!=0)$fatal(1,"STOP-before-REPLAY did not retire cleanly");
            $display("RESULT: PASS STEREO_STOP_BEFORE_REPLAY divisor=%0d checks=%0d groups=%0d ar=%0d",DIVISOR,checks,output_group,ar_count);
            $finish;
        end
        fork send_frames(0,10,1);send_frames(1,20,1);join
        consume_job(0);consume_job(0);
        fork send_frames(0,30,0);send_frames(1,40,1);join
        consume_job(0);repeat(100)@(negedge clk);if(!owner_empty)$fatal(1,"failed source retained/published slot");
        send_frames(0,50,1);consume_job(1);
        send_frames(1,60,1);consume_job(2);
        repeat(100)@(negedge clk);fail_write0=1;
        fork send_frames(0,70,1);send_frames(1,80,1);join
        consume_job(0);fail_write0=0;
        repeat(100)@(negedge clk);
        if(completed!=6||selected0!=4||selected1!=4||observed0!=4*DIVISOR||observed1!=4*DIVISOR)$fatal(1,"decimation counters");
        stop=1;repeat(100)@(negedge clk);if(!owner_empty||!read_quiet)$fatal(1,"final drain");
        // Coordinated cold reset includes the modeled DDR bus, never a fake RETIRE.
        stop=0;repeat(100)@(negedge clk);
        fork : cold_reset_case
            send_frames(0,90,1);
            begin wait(raw_valid[0]&&sof[0]);repeat(100)@(negedge pix);rst=0;disable cold_reset_case;end
        join
        raw_valid=0;sof=0;eol=0;source_valid=0;#500;rst=1;
        repeat(100)@(negedge clk);if(!owner_empty||job_valid||token_valid)$fatal(1,"cold reset retained prior work");
        $display("RESULT: PASS STEREO_STORE divisor=%0d checks=%0d completed=%0d bytes_per_frame=%0d",DIVISOR,checks,completed,BYTES);
        $finish;
    end
    // Production borrowed-context contract: the actual owner retains every
    // descriptor bit through its real retire response, after processing/native.
    reg owner_context_held=0;
    reg [511:0] owner_context_snapshot;
    integer owner_hold_checks=0;
    always @(posedge clk)begin
        if(!rst)owner_context_held=0;
        else begin
            if(owner_context_held)begin
                if({job_frame,job_lease,job_id}!==owner_context_snapshot)
                    $fatal(1,"real owner context changed before retire response");
                owner_hold_checks++;
                if(retire_done&&!retire_error)begin
                    $display("OWNER_CONTEXT_HELD PASS through_real_retire_done checks=%0d",owner_hold_checks);
                    owner_context_held=0;
                end
            end
            if(job_valid&&job_ready)begin
                if(owner_context_held)$fatal(1,"owner reused before response");
                owner_context_snapshot={job_frame,job_lease,job_id};owner_context_held=1;
            end
        end
    end
    initial begin #5000000;$fatal(1,"watchdog begin=%b job=%b front=%b owner=%b reader=%b cfg_ready=%b cfg_wait=%b observed=%0d/%0d selected=%0d/%0d source_valid=%b ready=%b ingress=%0d/%0d",begin_valid,job_valid,front_fault,store.u_owner.job_state,store.u_reader.state,cfg_ready,capture.config_wait,observed0,observed1,selected0,selected1,source_valid,source_ready,capture.u_member0.ingress.state,capture.u_member1.ingress.state);end
endmodule
