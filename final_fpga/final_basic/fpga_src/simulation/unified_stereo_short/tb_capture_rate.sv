`timescale 1ns/1ps
module tb_capture_rate;
    parameter integer FE_DELAY=397;
    localparam W=16,H=2,G=W*H/4,PERIOD=400,FRAMES=24;
`ifdef CANDIDATE
    localparam DIVISOR=1;
`else
    localparam DIVISOR=2;
`endif
    localparam RUNTIME_CADENCE=0;
    reg pix=0,clk=0,rst=0;
    always #4 pix=~pix;
    always #5 clk=~clk;
    reg enable=1,stop=0,cfg=0;
    wire cfg_ready,cfg_applied,front_quiet,front_fault;
    wire [39:0] raw[0:1];wire [1:0] raw_valid,sof,eol,source_valid,source_ok;
    wire [31:0] frame_sequence[0:1];wire [196:0] metadata[0:1];
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
    wire [31:0] source_sequence[0:1];
    wire [1:0] raw_abort,event_ready,source_idle,source_fault;
    reg [1:0] physical_valid=0,physical_sof=0,physical_eol=0,event_valid=0;
    reg [1:0] event_kind[0:1];
    reg [31:0] physical_sequence[0:1],event_sequence[0:1];
    reg [39:0] physical_data[0:1];
    generate for(genvar c=0;c<2;c++)begin:eye
        stereo_capture_source4 #(.CAMERA_ID(c),.WIDTH(W),.HEIGHT(H)
`ifdef CANDIDATE
            ,.FS_CADENCE_ENABLE(1)
`endif
        ) source(
            .clk(pix),.rst_n(rst),.i_data_reset_n(rst),.i_enable(enable),.i_session(32'd17),.i_epoch(32'd3),
            .i_time_ns(64'd100000),.i_time_valid(1'b1),.i_data(physical_data[c]),
            .i_valid(physical_valid[c]),.i_accept(1'b1),.i_sof(physical_sof[c]),.i_eol(physical_eol[c]),.i_abort(1'b0),
            .i_sequence(physical_sequence[c]),.i_identity_valid(1'b1),
            .i_event_valid(event_valid[c]),.o_event_ready(event_ready[c]),.i_event_kind(event_kind[c]),
            .i_event_ok(1'b1),.i_event_error(4'd0),.i_event_sequence(event_sequence[c]),.i_event_identity_valid(1'b1),
            .i_receive_fault(1'b0),.i_identity_quarantine(1'b0),
            .o_capture_data(raw[c]),.o_capture_valid(raw_valid[c]),.o_capture_accept(),.o_capture_sof(sof[c]),.o_capture_eol(eol[c]),
            .o_capture_abort(raw_abort[c]),.o_capture_geometry_done(),.o_capture_session(),.o_capture_epoch(),
            .o_capture_sequence(frame_sequence[c]),.o_capture_metadata(metadata[c]),
            .o_raw_source_valid(source_valid[c]),.i_raw_source_ready(source_ready[c]),
            .o_raw_source_session(),.o_raw_source_epoch(),.o_raw_source_sequence(source_sequence[c]),.o_raw_source_camera(),
            .o_raw_source_ok(source_ok[c]),.o_raw_source_error(),.o_idle(source_idle[c]),.o_fault(source_fault[c])
`ifdef CANDIDATE
            ,.i_frame_divisor(8'd2)
`endif
        );
    end endgenerate
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
        .raw_data(raw[0]),.raw_valid(raw_valid[0]),.raw_accept(1'b1),.raw_sof(sof[0]),.raw_eol(eol[0]),.raw_abort(raw_abort[0]),
        .raw_sequence(frame_sequence[0]),.raw_metadata(metadata[0]),.time_valid(1'b1),.bayer_valid(1'b1),.bayer_pattern(2'd2),
        .source_valid(source_valid[0]),.source_ready(source_ready[0]),.source_session(32'd17),.source_epoch(32'd3),
        .source_sequence(source_sequence[0]),.source_camera(1'b0),.source_ok(source_ok[0]),.source_error(source_ok[0]?8'd0:8'd9),
        .capture_frame(frame0),.begin_valid(begin_valid[0]),.begin_ready(begin_ready[0]),.begin_accepted(begin_accepted[0]),.capture_slot(slot0),
        .finish_valid(finish_valid[0]),.finish_ok(finish_ok[0]),.finish_ready(finish_ready[0]),
        .source_frames(observed0),.selected_frames(selected0),.skipped_frames(),
        .raw_data1(raw[1]),.raw_valid1(raw_valid[1]),.raw_accept1(1'b1),.raw_sof1(sof[1]),.raw_eol1(eol[1]),.raw_abort1(raw_abort[1]),
        .raw_sequence1(frame_sequence[1]),.raw_metadata1(metadata[1]),
        .source_valid1(source_valid[1]),.source_ready1(source_ready[1]),.source_session1(32'd17),.source_epoch1(32'd3),
        .source_sequence1(source_sequence[1]),.source_camera1(1'b1),.source_ok1(source_ok[1]),.source_error1(source_ok[1]?8'd0:8'd9),
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
    wire job_valid,owner_empty,owner_fault;
    wire [383:0] job_frame;wire [63:0] job_lease,job_id;
    reg job_ready=0,retire_valid=0;reg [63:0] retire_id=0;
    wire retire_ready,retire_done,retire_error;
    wire [31:0] dropped;
    stereo_raw_owner #(.WIDTH(W),.HEIGHT(H)) owner(
        .clk(clk),.rst_n(rst),.i_enable(enable),.i_stop(stop),.i_session(32'd17),.i_epoch(32'd3),
        .s_frame(begin_camera?frame1:frame0),.s_begin_valid(begin_hold),.i_begin_camera(begin_camera),
        .s_begin_ready(store_begin_ready),.o_begin_accepted(store_begin_accepted),.o_capture_slot(store_slot),
        .i_finish_valid(finish_valid),.i_finish_ok(finish_ok),.o_finish_ready(finish_ready),
        .o_job_valid(job_valid),.i_job_ready(job_ready),.o_job_frame(job_frame),.o_job_lease(job_lease),.o_job_id(job_id),
        .o_job_bayer(),.o_job_time_valid(),.i_retire_valid(retire_valid),.i_retire_job_id(retire_id),
        .i_release_quiet(1'b1),.o_retire_ready(retire_ready),.o_retire_done(retire_done),.o_retire_error(retire_error),
        .o_empty(owner_empty),.o_job_owned(),.o_fault(owner_fault),.o_dropped(dropped));
    // One shared complete-burst DDR writer with deterministic bounded stalls.
    // No response or consumer proof is inferred from elapsed frame count.
    reg write_active=0,b_pending=0,b_valid=0;
    reg [4:0] write_left=0;reg [3:0] write_id=0;
    integer b_wait=0,checks=0;
    assign awready=!write_active&&!b_pending&&!b_valid&&cycle%5!=0;
    assign wready=write_active&&cycle%4!=0;
    assign bvalid=b_valid;assign bid=write_id;assign bresp=0;
    always @(posedge clk)if(rst)begin
        if(awvalid&&awready)begin
            if(awsize!=4||awburst!=1||awlen>15||({1'b0,awaddr[11:0]}+(awlen+1)*16)>4096)$fatal(1,"bad AW");
            write_active<=1;write_left<=awlen+1;write_id<=awid;checks++;
        end
        if(wvalid&&wready)begin
            if(wlast!=(write_left==1))$fatal(1,"bad WLAST");
            write_left<=write_left-1;checks++;
            if(wlast)begin write_active<=0;b_pending<=1;b_wait<=17;end
        end
        if(b_pending)begin
            if(b_wait!=0)b_wait<=b_wait-1;
            else begin b_pending<=0;b_valid<=1;end
        end
        if(b_valid&&bready)b_valid<=0;
        if(front_fault||owner_fault||(|source_fault))$fatal(1,"structural fault");
        if(|(finish_valid&finish_ready&~finish_ok))$fatal(1,"clean input had negative FINISH");
    end
    integer jobs[0:1],last_sequence[0:1],completed[0:1],begins[0:1],finishes[0:1];
    integer warm_jobs[0:1];
    // Shared processing boundary model: 150 DFI cycles per job plus real
    // directory/offer/retire overhead. It has capacity for the selected input.
    integer service_left=0;reg processing=0;reg active_camera=0;
    always @(negedge clk)if(rst)begin
        job_ready=0;retire_valid=0;
        if(!processing&&job_valid)begin
            active_camera=job_frame[4];
            if(jobs[active_camera]!=0&&job_frame[108:77]<=last_sequence[active_camera])$fatal(1,"same-eye inversion");
            last_sequence[active_camera]=job_frame[108:77];jobs[active_camera]++;
            if(job_frame[108:77]>=4&&job_frame[108:77]<20)warm_jobs[active_camera]++;
            $display("TAKE eye=%0d source=%0d time=%0t",active_camera,job_frame[108:77],$time);
            retire_id=job_id;job_ready=1;processing=1;service_left=150;
        end else if(processing)begin
            if(service_left>0)service_left--;
            else if(retire_ready)begin retire_valid=1;processing=0;completed[active_camera]++;end
        end
    end
    always @(posedge clk)if(rst)for(integer c=0;c<2;c++)begin
        if(begin_valid[c]&&begin_ready[c])begin
            if(!begin_accepted[c])$fatal(1,"unexpected no-free/illegal BEGIN");begins[c]++;
        end
        if(finish_valid[c]&&finish_ready[c])finishes[c]++;
        if(retire_done&&retire_error)$fatal(1,"incorrect retire identity");
    end
    // Independent sensor timing. Frame input never waits for owner, DDR or
    // job readiness. FE may be late enough that SOURCE tails cross next FS.
    task automatic camera_frames(input integer c,input integer phase);
        integer f,t;
        begin
            repeat(phase)@(negedge pix);
            for(f=0;f<FRAMES;f++)begin
                for(t=0;t<PERIOD;t++)begin
                    event_valid[c]=t==0||t==FE_DELAY;
                    event_kind[c]=t==0?0:1;event_sequence[c]=f;
                    physical_valid[c]=t>=10&&t<10+G;
                    physical_sof[c]=t==10;physical_eol[c]=physical_valid[c]&&(t-10)%(W/4)==W/4-1;
                    physical_sequence[c]=f;
                    physical_data[c]={10'(c*311+f*37+t*17+3),10'(c*311+f*37+t*17+2),
                        10'(c*311+f*37+t*17+1),10'(c*311+f*37+t*17)};
                    if(!event_ready[c])$fatal(1,"physical event must drain");
                    @(negedge pix);
                end
            end
            event_valid[c]=0;physical_valid[c]=0;physical_sof[c]=0;physical_eol[c]=0;
        end
    endtask
    integer expected;
    initial begin
        for(integer c=0;c<2;c++)begin
            physical_data[c]=0;physical_sequence[c]=0;event_sequence[c]=0;event_kind[c]=0;
            jobs[c]=0;last_sequence[c]=-1;completed[c]=0;begins[c]=0;finishes[c]=0;warm_jobs[c]=0;
        end
        repeat(6)@(negedge clk);rst=1;
        wait(cfg_ready);@(negedge clk);cfg=1;@(negedge clk);cfg=0;
        wait(cfg_applied);repeat(30)@(negedge pix);
        fork camera_frames(0,0);camera_frames(1,37);join
        // The steady window is scored by SOURCE 4..19, not by drain totals.
        // Drain only proves every accepted job has a real terminal retirement.
        repeat(600)@(negedge clk);
`ifdef CANDIDATE
        expected=FRAMES/2;
        if(warm_jobs[0]!=8||warm_jobs[1]!=8)$fatal(1,"candidate steady selected SOURCE loss");
`else
        expected=FE_DELAY>=PERIOD-4?FRAMES/4:FRAMES/2;
        if(warm_jobs[0]!=(FE_DELAY>=PERIOD-4?4:8)||warm_jobs[1]!=(FE_DELAY>=PERIOD-4?4:8))$fatal(1,"baseline rate mechanism changed");
`endif
        for(integer c=0;c<2;c++)begin
            if(jobs[c]!=expected||begins[c]!=expected||finishes[c]!=expected||completed[c]!=expected)
                $fatal(1,"eye=%0d expected=%0d begin=%0d finish=%0d jobs=%0d retired=%0d",c,expected,begins[c],finishes[c],jobs[c],completed[c]);
        end
        if(dropped!=0||!owner_empty||source_idle!=3||!front_quiet&&stop)$fatal(1,"tail not actually empty");
        $display("RESULT: PASS CAPTURE_RATE fe_delay=%0d physical=%0d/%0d observed=%0d/%0d selected=%0d/%0d jobs=%0d/%0d steady=%0d/%0d checks=%0d",
            FE_DELAY,FRAMES,FRAMES,observed0,observed1,selected0,selected1,jobs[0],jobs[1],warm_jobs[0],warm_jobs[1],checks);
        $finish;
    end
    initial begin #3000000;$fatal(1,"capture rate timeout");end
endmodule
