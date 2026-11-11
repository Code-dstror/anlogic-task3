`timescale 1ns/1ps
// Real full_raw_store, capture FIFOs, writer and cold owners. Only the AXI
// write-response endpoint is modeled; no hierarchy forces fabricate ownership.
module tb_stereo_hdr_capture #(parameter integer AUDIT_CASE = 0);
    localparam integer W=16,H=4,G=W*H/4;
    reg pix=0,clk=0,rst=0;
    always #4 pix=~pix;
    always #5 clk=~clk;
    reg cfg=0,stop=0,job_ready=0,raw_valid=0,raw_sof=0,raw_eol=0,source_valid=0;
    reg [39:0] raw=0;
    wire cfg_ready,cfg_error,admit,route_sdr,source_ready,job_valid,stereo_empty,private_quiet,fault;
    wire [383:0] job_frame;
    wire [63:0] job_id,job_lease;
    wire [3:0] awid;wire [27:0] awaddr;wire [7:0] awlen;
    wire awvalid,awready,wvalid,wready,wlast,bready;
    wire arvalid;
    reg write_active=0,bvalid=0;
    reg [3:0] bid=0;
    reg [4:0] beats=0;
    integer checks=0;
    reg [3:0] member_source=0,member_ok=15;
    wire [3:0] terminal_ready;
    reg [31:0] seq=31,group_id=1,epoch=3;
    reg hold_b=0,product_quiet=1,ticket_quiet=1,next_hdr=1,expect_wrong_release=0;
    reg [39:0] sample[0:3];
    wire [196:0] long_meta={1'b1,1'b1,2'd1,1'b1,group_id,32'h56a3d02f,32'd256,32'd3200,64'd100};
    wire [196:0] short_meta={1'b1,1'b1,2'd2,1'b1,group_id,32'h56a3d02f,32'd256,32'd200,64'd101};
    wire pair_valid,pair_bank,pair_release_ready,dir_ready,dir_valid,dir_last;
    wire [63:0] pair_id;
    reg pair_take=0,release_valid=0,retire_bank=0,dir_req=0,dir_consume=0;
    reg [63:0] retire_id=0;
    reg [1:0] dir_slot=0;
    wire [31:0] dir_data;
    wire [3:0] dir_word;
    wire [127:0] write_data;
    wire [15:0] write_keep;
    reg [127:0] memory[0:7][0:4];
    reg [2:0] write_slot=0;
    reg [3:0] write_word=0;
    reg [31:0] cycle=0;
    reg [3:0] response_delay=0;
    reg [7:0] writes_complete=0;
    integer round_number;
    reg read_start=0,read_camera=0,read_bank=0;
    wire read_start_ready,read_done,read_ok,read_fault,read_quiet;
    wire [27:0] read_addr,ddr_araddr;
    wire [7:0] read_arlen,ddr_arlen;
    wire [127:0] read_payload;
    wire read_arvalid,read_arready,read_rvalid,read_rready,read_rlast;
    wire [31:0] out_index;
    wire [55:0] merged_raw;
    wire merge_valid,merge_sof,merge_eol,merge_eof;
    wire merge_ready=cycle[2:0]!=2;
    wire [3:0] motion;
    reg read_active=0;
    reg [2:0] memory_slot=0,read_beat=0;
    reg [31:0] merged_groups=0;
    wire ddr_rready;
    wire hdr_decode_start,hdr_decode_start_ready,hdr_decode_release;
    wire [1:0] hdr_decode_abort,hdr_decode_done,hdr_decode_aborted;
    wire hdr_decode_member,hdr_decode_valid,hdr_decode_last,hdr_decode_ready;
    wire [127:0] hdr_decode_data;wire [15:0] hdr_decode_keep;
    wire [39:0] hdr_decode_raw;
    wire hdr_decode_raw_member,hdr_decode_raw_valid,hdr_decode_raw_ready;
    wire stereo_decode_start,stereo_decode_start_ready,stereo_decode_release;
    wire stereo_decode_cancel,stereo_decode_run,stereo_decode_valid,stereo_decode_last,stereo_decode_ready;
    wire [127:0] stereo_decode_data;wire [15:0] stereo_decode_keep;
    wire [39:0] stereo_decode_raw;
    wire stereo_decode_raw_valid,stereo_decode_raw_ready,stereo_decode_sof,stereo_decode_eol;
    wire stereo_decode_done,stereo_decode_aborted,stereo_decode_quiet;
        shared_raw10_decode_service #(.WIDTH(W),.HEIGHT(H)) u_decode_service(
            .clk(clk),.rst_n(rst),
            .hdr_start_valid(hdr_decode_start),.hdr_start_ready(hdr_decode_start_ready),
            .hdr_release(hdr_decode_release),.hdr_abort(hdr_decode_abort),
            .hdr_member(hdr_decode_member),.hdr_data(hdr_decode_data),.hdr_keep(hdr_decode_keep),
            .hdr_valid(hdr_decode_valid),.hdr_last(hdr_decode_last),.hdr_ready(hdr_decode_ready),
            .hdr_raw_member(hdr_decode_raw_member),.hdr_raw(hdr_decode_raw),
            .hdr_raw_valid(hdr_decode_raw_valid),.hdr_raw_ready(hdr_decode_raw_ready),
            .hdr_done(hdr_decode_done),.hdr_aborted(hdr_decode_aborted),
            .stereo_start_valid(stereo_decode_start),.stereo_start_ready(stereo_decode_start_ready),
            .stereo_release(stereo_decode_release),.stereo_cancel(stereo_decode_cancel),.stereo_run(stereo_decode_run),
            .stereo_data(stereo_decode_data),.stereo_keep(stereo_decode_keep),
            .stereo_valid(stereo_decode_valid),.stereo_last(stereo_decode_last),.stereo_ready(stereo_decode_ready),
            .stereo_raw(stereo_decode_raw),.stereo_raw_valid(stereo_decode_raw_valid),.stereo_raw_ready(stereo_decode_raw_ready),
            .stereo_sof(stereo_decode_sof),.stereo_eol(stereo_decode_eol),
            .stereo_done(stereo_decode_done),.stereo_aborted(stereo_decode_aborted),.stereo_quiet(stereo_decode_quiet),.quiet());
    hdr_pair_pixel_reader #(.WIDTH(W),.HEIGHT(H),.EXTERNAL_DECODER(1)) reader(
            .o_decode_start_valid(hdr_decode_start),.i_decode_start_ready(hdr_decode_start_ready),
            .o_decode_release(hdr_decode_release),.o_decode_abort(hdr_decode_abort),
            .o_decode_member(hdr_decode_member),.o_decode_data(hdr_decode_data),.o_decode_keep(hdr_decode_keep),
            .o_decode_valid(hdr_decode_valid),.o_decode_last(hdr_decode_last),.i_decode_ready(hdr_decode_ready),
            .i_decode_raw_member(hdr_decode_raw_member),.i_decode_raw(hdr_decode_raw),
            .i_decode_raw_valid(hdr_decode_raw_valid),.o_decode_raw_ready(hdr_decode_raw_ready),
            .i_decode_done(hdr_decode_done),.i_decode_aborted(hdr_decode_aborted),

        .i_clk(clk),.i_identity_rst_n(rst),.i_start_valid(read_start),.i_pair_bank(read_bank),
        .i_pair_camera(read_camera),.o_start_ready(read_start_ready),.i_ratio_log2(3'd4),
        .i_black_long(10'd50),.i_black_short(10'd50),.i_motion_base(14'h3fff),
        .i_motion_shift(4'd1),.i_cancel(1'b0),.m_raw(merged_raw),.m_motion(motion),
        .m_valid(merge_valid),.m_sof(merge_sof),.m_eol(merge_eol),.m_eof(merge_eof),
        .m_index(out_index),.m_ready(merge_ready),
        .o_result_valid(read_done),.o_result_ok(read_ok),.i_result_ready(1'b1),
        .o_read_quiet(read_quiet),.o_protocol_fault(read_fault),.o_long_occupancy(),.o_short_occupancy(),
        .m_axi_arid(),.m_axi_araddr(read_addr),.m_axi_arlen(read_arlen),.m_axi_arsize(),.m_axi_arburst(),
        .m_axi_arvalid(read_arvalid),.m_axi_arready(read_arready),.m_axi_rid(4'd1),
        .m_axi_rdata(read_payload),.m_axi_rresp(2'd0),.m_axi_rlast(read_rlast),
        .m_axi_rvalid(read_rvalid),.m_axi_rready(read_rready));


    assign awready=!write_active&&!bvalid&&response_delay==0&&cycle[1:0]!=1;
    assign wready=write_active&&cycle[2:0]!=5;
    full_raw_store #(.WIDTH(W),.HEIGHT(H),.SECOND_HDR_CAMERA(1),.DESCRIPTOR_ENABLE(1),.DUAL_CAPTURE_ENABLE(1),
        .PAIR_METADATA_ENABLE(1),.CAMERA_COUNT(1),.CANONICAL_PRIVATE_FETCH_ENABLE(1),
        .SHARED_REPLAY_FIFO_ENABLE(1),.STEREO_ENABLE(1),.STEREO_CAPTURE_DIVISOR(1),.SHARED_DECODE_ENABLE(1)) dut(
            .o_decode_start_valid(stereo_decode_start),.i_decode_start_ready(stereo_decode_start_ready),
            .o_decode_release(stereo_decode_release),.o_decode_cancel(stereo_decode_cancel),.o_decode_run(stereo_decode_run),
            .o_decode_data(stereo_decode_data),.o_decode_keep(stereo_decode_keep),
            .o_decode_valid(stereo_decode_valid),.o_decode_last(stereo_decode_last),.i_decode_ready(stereo_decode_ready),
            .i_decode_raw(stereo_decode_raw),.i_decode_raw_valid(stereo_decode_raw_valid),.o_decode_raw_ready(stereo_decode_raw_ready),
            .i_decode_sof(stereo_decode_sof),.i_decode_eol(stereo_decode_eol),
            .i_decode_done(stereo_decode_done),.i_decode_aborted(stereo_decode_aborted),.i_decode_quiet(stereo_decode_quiet),

         .i_cam1_hdr_enable(1'b1),.i_cam1_hdr_data({sample[3],sample[2]}),.i_cam1_hdr_valid({2{raw_valid}}),
        .i_cam1_hdr_sof({2{raw_sof}}),.i_cam1_hdr_eol({2{raw_eol}}),.i_cam1_hdr_abort(2'd0),
        .i_cam1_hdr_sequence({seq,seq}),.i_cam1_hdr_metadata({short_meta,long_meta}),
        .i_cam1_hdr_source_valid(member_source[3:2]),.o_cam1_hdr_source_ready(terminal_ready[3:2]),
        .i_cam1_hdr_source_session({2{32'd17}}),.i_cam1_hdr_source_epoch({2{epoch}}),
        .i_cam1_hdr_source_sequence({seq,seq}),.i_cam1_hdr_source_ok(member_ok[3:2]),
        .i_cam1_hdr_source_error({(member_ok[3]?8'd0:8'd9),(member_ok[2]?8'd0:8'd9)}),.o_cam1_hdr_idle(),
        .i_stereo_mode(1'b0),.i_stereo_mode_pixel(1'b0),.o_stereo_job_valid(job_valid),.i_stereo_job_ready(job_ready),.i_stereo_frame_divisor_pixel(8'd1),
        .o_stereo_job_frame(job_frame),.o_stereo_job_lease(job_lease),.o_stereo_job_id(job_id),
        .i_stereo_retire_valid(1'b0),.i_stereo_retire_job_id(64'd0),.o_stereo_empty(stereo_empty),
        .i_stereo_processing_done(1'b0),.i_stereo_processing_error(1'b0),.i_stereo_processing_job_id(64'd0),
        .i_sdr_lz_enable(1'b0),.i_lz_fault(1'b0),.i_lz_region_quiet(1'b1),
        .i_capture_time_valid(1'b1),.i_bayer_valid(1'b1),.i_isp_bayer_phase(2'd0),
        .o_raw_route_sdr(route_sdr),.o_raw_policy_admit(admit),
        .i_sdr_read_request_valid(1'b0),.i_sdr_read_request_context(448'd0),.i_sdr_read_ready(1'b0),
        .i_sdr_reader_cancel(1'b0),.i_sdr_release_valid(1'b0),.i_sdr_release_context(448'd0),.i_sdr_consumer_quiet(1'b1),
        .s_hdr_axi_arid(4'd0),.s_hdr_axi_araddr(read_addr),.s_hdr_axi_arlen(read_arlen),.s_hdr_axi_arsize(3'd4),
        .s_hdr_axi_arburst(2'd1),.s_hdr_axi_arvalid(read_arvalid),.s_hdr_axi_rready(read_rready),
        .i_identity_rst_n(rst),.i_pair_stop(stop),.i_pair_fault(1'b0),
        .i_pair_config_valid(cfg),.o_pair_config_ready(cfg_ready),.o_pair_config_error(cfg_error),
        .i_pair_session(32'd17),.i_pair_epoch(epoch),.i_pair_max_wait(32'd100),.i_pair_max_age(32'd1000),
        .i_pair_max_delta(64'd10),.i_pair_ratio(3'd4),.i_pair_hdr_enable(next_hdr),
        .i_pair_ready(pair_take),.i_pair_release_valid(release_valid),.i_pair_release_bank(retire_bank),.i_pair_release_id(retire_id),
        .i_pair_read_quiet(read_quiet),.i_pair_product_quiet(product_quiet),.i_pair_ticket_released(ticket_quiet),
        .i_pair_directory_valid(dir_req),.i_pair_directory_slot(dir_slot),.m_pair_directory_ready(dir_consume),.i_pair_now(64'd110),
        .i_capture_enable(1'b1),.i_pixel_clk(pix),.i_pixel_rst_n(rst),.i_dfi_clk(clk),.i_dfi_rst_n(rst),
        .i_ddr_ready(1'b1),.i_cfs_enable(1'b0),.i_physical_mono_current_enable(1'b0),
        .i_user_clk(clk),.i_user_rst_n(rst),
        .i_capture_data(sample[0]),.i_capture_valid(raw_valid),.i_capture_accept(1'b1),
        .i_capture_sof(raw_sof),.i_capture_eol(raw_eol),.i_capture_abort(1'b0),
        .i_capture_epoch(epoch),.i_session_id(32'd17),.i_frame_sequence(seq),.i_mode_epoch(epoch),
        .i_capture_metadata(long_meta),.i_capture_source_valid(member_source[0]),.i_capture_source_session(32'd17),
        .i_capture_source_epoch(epoch),.i_capture_source_sequence(seq),.i_capture_source_camera(1'b0),
        .i_capture_source_ok(member_ok[0]),.i_capture_source_error((member_ok[0] ? 8'd0 : 8'd9)),
        .i_capture1_clk(pix),.i_capture1_rst_n(rst),.i_capture1_data(sample[1]),.i_capture1_valid(raw_valid),
        .i_capture1_accept(1'b1),.i_capture1_sof(raw_sof),.i_capture1_eol(raw_eol),.i_capture1_abort(1'b0),
        .i_capture1_session(32'd17),.i_capture1_sequence(seq),.i_capture1_epoch(epoch),.i_capture1_metadata(short_meta),
        .i_capture1_source_valid(member_source[1]),.o_capture1_source_ready(terminal_ready[1]),
        .i_capture1_source_session(32'd17),.i_capture1_source_epoch(epoch),.i_capture1_source_sequence(seq),
        .i_capture1_source_camera(1'b0),.i_capture1_source_ok(member_ok[1]),.i_capture1_source_error((member_ok[1] ? 8'd0 : 8'd9)),
        .o_private_ownership_quiescent(private_quiet),.i_commit_ready(1'b0),
        .i_ref_valid(1'b0),.i_ref_op(2'd0),.i_ref_mask(2'd0),.i_ref_frame0(384'd0),.i_ref_frame1(384'd0),
        .i_ref_lease0(64'd0),.i_ref_lease1(64'd0),.i_ref_job_id(64'd0),.o_reference_fault(fault),
        .i_shared_replay_source_select(1'b0),.i_shared_replay_sink_select(1'b0),
        .s_shared_replay_data(147'd0),.s_shared_replay_valid(1'b0),.m_shared_replay_ready(1'b0),
        .i_private_req_valid(1'b0),.i_private_req_op(3'd0),.i_private_req_camera(1'b0),.i_private_req_slot(2'd0),
        .i_private_req_generation(32'd0),.i_private_req_session(32'd0),.i_private_req_lease(64'd0),.i_private_req_job_id(64'd0),
        .i_private_req_offset(32'd0),.i_private_req_length(32'd0),.i_public_read_admission_enable(1'b0),
        .i_mask_command_ready(1'b0),.i_mask_response_data(147'd0),.i_mask_response_valid(1'b0),
        .i_mask_block_data(147'd0),.i_mask_block_valid(1'b0),.i_mask_owner_complete(1'b0),
        .i_private_descriptor(384'd0),.i_private_pair_id(64'd0),.i_private_member_index(1'b0),
        .i_private_rsp_ready(1'b0),.i_private_read_ready(1'b0),.i_replay_context_ready(1'b0),
        .i_host_replay_context_ready(1'b0),.i_replay_safe(1'b1),.i_replay_ready(1'b0),
        .i_bar_write_valid(1'b0),.i_bar_write_offset(12'd0),.i_bar_write_data(32'd0),.i_bar_write_strobes(4'd0),
        .i_bar_read_valid(1'b0),.i_bar_read_offset(12'd0),
        .m_axi_awid(awid),.m_axi_awaddr(awaddr),.m_axi_awlen(awlen),.m_axi_awvalid(awvalid),.m_axi_awready(awready),
        .m_axi_wlast(wlast),.m_axi_wvalid(wvalid),.m_axi_wready(wready),
        .m_axi_bid(bid),.m_axi_bresp(2'd0),.m_axi_bvalid(bvalid),.m_axi_bready(bready),
        .m_axi_arvalid(arvalid),.m_axi_arready(!read_active),.m_axi_rid(4'd1),.m_axi_rdata(memory[memory_slot][read_beat]),
        .m_axi_rresp(2'd0),.m_axi_rlast(read_beat==4),.m_axi_rvalid(read_active),
        .m_axi_araddr(ddr_araddr),.m_axi_arburst(),.m_axi_arid(),.m_axi_arlen(ddr_arlen),.m_axi_arsize(),
        .m_axi_awburst(),.m_axi_awsize(),.m_axi_rready(ddr_rready),.m_axi_wdata(write_data),.m_axi_wstrb(write_keep),
        .m_pair_directory_data(dir_data),.m_pair_directory_last(dir_last),.m_pair_directory_valid(dir_valid),.m_pair_directory_word(dir_word),
        .m_shared_replay_data(),.m_shared_replay_valid(),.o_bar_read_data(),.o_bar_read_response(),
        .o_bar_read_response_valid(),.o_bar_write_response(),.o_capture_source_ready(terminal_ready[0]),.o_capture_source_stale_count(),
        .o_capture_write_quiescent(),.o_capture0_consume_fire(),.o_capture0_enqueue_fire(),.o_capture0_frame_accept(),
        .o_capture0_idle(),.o_capture1_consume_fire(),.o_capture1_enqueue_fire(),.o_capture1_frame_accept(),
        .o_capture1_idle(),.o_capture1_source_stale_count(),.o_cfs_busy_count(),.o_cfs_compressed_count(),
        .o_cfs_no_benefit_count(),.o_cfs_overflow_count(),.o_cfs_protocol_fault(),.o_commit_frame(),.o_commit_lease(),
        .o_commit_valid(),.o_host_replay_context_valid(),.o_host_replay_descriptor(),.o_host_replay_metadata_valid(),
        .o_lz_region_grant(),.o_lz_stop(),.o_mask_block_ready(),.o_mask_cache_retire(),.o_mask_command_data(),
        .o_mask_command_valid(),.o_mask_response_ready(),.o_pair_bank(pair_bank),.o_pair_directory_ready(dir_ready),.o_pair_id(pair_id),
        .o_pair_release_ready(pair_release_ready),.o_pair_valid(pair_valid),.o_private_native_done(),.o_private_native_error(),
        .o_private_native_job_id(),.o_private_native_member_index(),.o_private_read_complete(),.o_private_read_data(),
        .o_private_read_error(),.o_private_read_keep(),.o_private_read_last(),.o_private_read_protocol_fault(),
        .o_private_read_valid(),.o_private_req_ready(),.o_private_rsp_camera(),.o_private_rsp_code(),
        .o_private_rsp_descriptor(),.o_private_rsp_epoch(),.o_private_rsp_generation(),.o_private_rsp_metadata_valid(),
        .o_private_rsp_sequence(),.o_private_rsp_session(),.o_private_rsp_slot(),.o_private_rsp_valid(),
        .o_public_read_quiescent(),.o_raw_mode_applied(),.o_raw_mode_busy(),.o_raw_region_quiet(),.o_read_quiescent(),
        .o_ref_ready(),.o_replay_abort(),.o_replay_active(),.o_replay_context_valid(),.o_replay_data(),
        .o_replay_descriptor(),.o_replay_eol(),.o_replay_job_id(),.o_replay_member_index(),.o_replay_native_done(),
        .o_replay_native_error(),.o_replay_pair_id(),.o_replay_private(),.o_replay_protocol_fault(),.o_replay_sof(),
        .o_replay_valid(),.o_sdr_frame_context(),.o_sdr_offer_valid(),.o_sdr_read_data(),.o_sdr_read_done_ok(),
        .o_sdr_read_done_valid(),.o_sdr_read_keep(),.o_sdr_read_last(),.o_sdr_read_owned(),.o_sdr_read_request_ready(),
        .o_sdr_read_valid(),.o_sdr_release_ready(),.o_shared_replay_sink_reset_done(),.o_shared_replay_source_reset_done(),
        .o_stereo_job_bayer(),.o_stereo_job_time_valid(),.o_stereo_retire_done(),.o_stereo_retire_error(),
        .o_stereo_retire_ready(),.s_hdr_axi_arready(read_arready),.s_hdr_axi_rdata(read_payload),.s_hdr_axi_rid(),.s_hdr_axi_rlast(read_rlast),
        .s_hdr_axi_rresp(),.s_hdr_axi_rvalid(read_rvalid),.s_shared_replay_ready());


    function automatic [7:0] pixel_byte(input integer lane);
        pixel_byte=8'h31 + lane*19 + round_number;
    endfunction
    always @(posedge clk)if(rst)begin
        cycle<=cycle+1;
        if(fault&&!expect_wrong_release)$fatal(1,"capture protocol fault");
        if(awvalid&&awready)begin
            if(awaddr<28'h2000000||awaddr>=28'ha000000||awaddr[23:0]!=0||awlen!=4)
                $fatal(1,"unexpected RAW write burst %h/%d",awaddr,awlen);
            write_slot<=(awaddr-28'h2000000)>>24;
            write_word<=0;write_active<=1;beats<=awlen+1'b1;bid<=awid;
        end
        if(wvalid&&wready)begin
            if(wlast!=(beats==1)||write_keep!=16'hffff)$fatal(1,"bad write termination");
            memory[write_slot][write_word]<=write_data;
            write_word<=write_word+1'b1;beats<=beats-1'b1;
            if(wlast)begin write_active<=0;response_delay<=6;end
        end
        if(response_delay!=0&&!hold_b)begin
            response_delay<=response_delay-1'b1;
            if(response_delay==1)bvalid<=1;
        end
        if(bvalid&&bready)begin bvalid<=0;writes_complete[write_slot]<=1;end
    end
    // Independent scalar reference. Motion threshold is above the maximum
    // residual for this fixture, so all four weights use the static knee.
    function automatic [13:0] reference_merge(input [9:0] l,input [9:0] sh);
        integer lw,sw,w;
        begin
            lw=l>50?l-50:0;
            sw=sh>50?(sh-50)*16:0;
            w=l<=768?0:l>=896?16:(l-768)/8;
            reference_merge=(lw*(16-w)+sw*w+8)/16;
        end
    endfunction
    integer jlane;
    always @(posedge clk)if(rst)begin
        if(arvalid&&!read_active)begin
            if(ddr_arlen!=4 || ddr_araddr[23:0]!=0)$fatal(1,"invalid HDR AR");
            read_active<=1;memory_slot<=(ddr_araddr-28'h2000000)>>24;read_beat<=0;
        end
        if(read_active&&ddr_rready)begin
            if(read_beat==4)read_active<=0;
            else read_beat<=read_beat+1'b1;
        end
        if(read_start&&read_start_ready)merged_groups<=0;
        if(read_fault)$fatal(1,"reader protocol fault");
        if(merge_valid&&merge_ready)begin
            if(out_index!==merged_groups||merge_sof!==(merged_groups==0)||
                merge_eol!==(merged_groups%(W/4)==W/4-1)||merge_eof!==(merged_groups==G-1)||motion!=0)
                $fatal(1,"fused group framing");
            for(jlane=0;jlane<4;jlane=jlane+1)
                if(merged_raw[jlane*14+:14]!==reference_merge(sample[read_camera*2][jlane*10+:10],
                       sample[read_camera*2+1][jlane*10+:10]))$fatal(1,"wrong eye, exposure or RAW14 value");
            merged_groups<=merged_groups+1;
        end
    end
    task automatic send_exposures(input integer bad_member);
        integer g,j;
        reg [3:0] consumed;
        begin
            @(negedge pix);
            for(j=0;j<4;j=j+1)begin
                sample[j]={5{pixel_byte(j)}};
                member_ok[j]=j!=bad_member;
            end
            for(g=0;g<G;g=g+1)begin
                raw_valid=1;raw_sof=g==0;raw_eol=g%(W/4)==W/4-1;
                @(negedge pix);
            end
            raw_valid=0;raw_sof=0;raw_eol=0;
            repeat(4)@(negedge pix);
            member_source=15;
            while(|member_source)begin
                @(posedge pix);consumed=terminal_ready&member_source;
                @(negedge pix);member_source=member_source&~consumed;
            end
        end
    endtask
    task automatic consume_pair(output integer camera);
        integer role,j,addr;
        reg [63:0] id;
        reg bank;
        begin
            wait(pair_valid);@(negedge clk);
            id=pair_id;bank=pair_bank;camera=id[31];
            repeat(17)begin
                @(negedge clk);
                if(!pair_valid||pair_id!==id||pair_bank!==bank)$fatal(1,"changed stalled pair");
            end
            pair_take=1;@(negedge clk);pair_take=0;
            for(role=0;role<2;role=role+1)begin
                dir_slot={bank,role[0]};dir_req=1;
                do @(posedge clk);while(!dir_ready);
                @(negedge clk);dir_req=0;dir_consume=1;
                for(j=0;j<16;j=j+1)begin
                    do @(posedge clk);while(!dir_valid);
                    if(dir_word!==j[3:0]||dir_last!==(j==15))$fatal(1,"bad directory framing");
                    case(j)
                    0:if(dir_data[4]!==camera[0]||dir_data[2:1]!==role+1||dir_data[6:5]!==dir_slot)$fatal(1,"crossed eye/role/slot");
                    2:if(dir_data!=17)$fatal(1,"session");
                    3:if(dir_data!=seq)$fatal(1,"sequence");
                    4:if(dir_data!=epoch)$fatal(1,"epoch");
                    8:if(dir_data!=(role?200:3200))$fatal(1,"exposure");
                    11:if(dir_data!=group_id)$fatal(1,"exposure group");
                    endcase
                end
                @(negedge clk);dir_consume=0;
                addr=camera*4+dir_slot;
                if(!writes_complete[addr])$fatal(1,"published ahead of B");
                for(j=0;j<5;j=j+1)begin
                    if(memory[addr][j]!=={16{pixel_byte(camera*2+role)}})$fatal(1,"RAW slot alias");
                end
            end
            read_camera=camera[0];read_bank=bank;read_start=1;
            do @(posedge clk);while(!read_start_ready);
            @(negedge clk);read_start=0;
            wait(read_done);@(negedge clk);
            if(!read_ok||merged_groups!=G)$fatal(1,"reader failed complete fusion");
            retire_bank=bank;retire_id=id;release_valid=1;
            do @(posedge clk);while(!pair_release_ready);
            @(negedge clk);release_valid=0;
        end
    endtask
    integer first_eye,second_eye;
    task automatic stop_with_write_response_pending;
        begin
            round_number=0;hold_b=1;
            fork
                send_exposures(-1);
                begin
                    wait(response_delay>0);@(negedge clk);stop=1;
                    repeat(120)begin
                        @(negedge clk);
                        if(pair_valid || dut.o_capture_write_quiescent || dut.o_raw_region_quiet)
                            $fatal(1,"STOP reported quiet or published a frame ahead of held DDR B");
                    end
                    hold_b=0;
                end
            join
            wait(private_quiet && dut.o_capture_write_quiescent && dut.frontend_quiet);
            if(fault || pair_valid)$fatal(1,"stop returned ambiguous owner");
            stop=0;repeat(100)@(negedge pix);
            round_number=1;seq=32;group_id=2;send_exposures(-1);
            consume_pair(first_eye);consume_pair(second_eye);
            if(first_eye==second_eye)$fatal(1,"failed to restore both eyes after STOP");
            wait(private_quiet);$display("RESULT: PASS HDR_STOP_WITH_WLAST_B_DEBT 120 cycles blocked, both eyes resumed");$finish;
        end
    endtask
    task automatic switch_while_pair_owned;
        begin
            round_number=0;send_exposures(-1);
            wait(pair_valid);@(negedge clk);
            first_eye=pair_id[31];retire_bank=pair_bank;retire_id=pair_id;
            pair_take=1;@(negedge clk);pair_take=0;
            product_quiet=0;ticket_quiet=0;release_valid=1;
            next_hdr=0;epoch=4;cfg=1;
            repeat(80)begin
                @(negedge clk);
                if(private_quiet || pair_release_ready || cfg_ready || route_sdr)$fatal(1,"mode moved while acquired");
            end
            ticket_quiet=1;repeat(20)begin @(negedge clk);if(pair_release_ready || route_sdr)$fatal(1,"product debt lost");end
            product_quiet=1;do @(posedge clk);while(!pair_release_ready);
            @(negedge clk);release_valid=0;
            do @(posedge clk);while(!cfg_ready);
            if(!route_sdr || cfg_error || !private_quiet)$fatal(1,"new SDR state not clean");
            @(negedge clk);cfg=0;repeat(50)@(negedge clk);
            cfg=1;next_hdr=1;epoch=5;
            do @(posedge clk);while(!cfg_ready);
            if(cfg_error || route_sdr)$fatal(1,"return to HDR rejected");
            @(negedge clk);cfg=0;repeat(100)@(negedge pix);
            round_number=1;seq=32;group_id=2;send_exposures(-1);
            consume_pair(first_eye);consume_pair(second_eye);
            if(first_eye==second_eye)$fatal(1,"new owners aliased");
            wait(private_quiet);$display("RESULT: PASS HDR_MODE_EXIT_HELD_PAIR paid ticket/product debts; return HDR both eyes");$finish;
        end
    endtask
    task automatic reject_other_eye_retire;
        begin
            round_number=0;send_exposures(-1);
            wait(pair_valid);@(negedge clk);first_eye=pair_id[31];retire_bank=pair_bank;retire_id=pair_id^64'h80000000;
            pair_take=1;@(negedge clk);pair_take=0;
            expect_wrong_release=1;release_valid=1;do @(posedge clk);while(!pair_release_ready);
            @(negedge clk);release_valid=0;repeat(15)@(negedge clk);
            if(!fault || private_quiet || dut.o_raw_region_quiet)$fatal(1,"wrong-eye release failed to quarantine");
            if(dut.eye_empty[first_eye])$fatal(1,"wrong-eye freed current bank");
            $display("RESULT: PASS HDR_STALE_RELEASE wrong eye with identical serial quarantined, owned bank retained");$finish;
        end
    endtask
    initial begin
        #500;rst=1;repeat(100)@(negedge clk);
        cfg=1;do @(posedge clk);while(!cfg_ready);
        if(cfg_error)$fatal(1,"HDR configuration rejected");
        @(negedge clk);cfg=0;wait(admit&&!route_sdr);repeat(40)@(negedge pix);
        case(AUDIT_CASE)
            0: begin end
            1: stop_with_write_response_pending();
            2: switch_while_pair_owned();
            3: reject_other_eye_retire();
            default: $fatal(1,"unknown slot lifecycle case");
        endcase
        // Identical group/sequence on both eyes catches accidental cross-eye matching.
        round_number=0;send_exposures(-1);
        consume_pair(first_eye);consume_pair(second_eye);
        if(first_eye==second_eye)$fatal(1,"duplicate eye");
        wait(private_quiet);round_number=1;seq=32;group_id=2;
        send_exposures(2);consume_pair(first_eye);
        if(first_eye!=0)$fatal(1,"bad CAM1 LONG published");
        wait(private_quiet);repeat(20)@(negedge clk);
        if(pair_valid)$fatal(1,"unpaired product");
        round_number=2;seq=33;group_id=3;send_exposures(-1);
        consume_pair(first_eye);consume_pair(second_eye);
        if(first_eye==second_eye)$fatal(1,"failed eye did not recover");
        wait(private_quiet);
        $display("RESULT: PASS STEREO_HDR_CAPTURE 12 exposures, five pairs and 320 scalar RAW14 values, bad member isolated and recovered");$finish;
    end
    initial begin #1000000;$fatal(1,"watchdog cfg=%d admit=%b front_stop=%b valid=%b pairs=%b state0=%h state1=%h done=%h",
        dut.cfg_state,admit,dut.frontend_stop,pair_valid,dut.eye_pair_valid,
        dut.eye_empty[0],dut.eye_empty[1],writes_complete);end
endmodule
