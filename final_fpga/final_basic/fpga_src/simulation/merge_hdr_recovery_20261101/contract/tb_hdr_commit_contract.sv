`timescale 1ns/1ps
// Real full_raw_store, capture FIFOs, writer and cold owners. Only the AXI
// write-response endpoint is modeled; no hierarchy forces fabricate ownership.
`include "pcie_protocol_v1.vh"
module tb_hdr_commit_contract;
    localparam integer W=16,H=4,G=W*H/4;
    reg pix=0,clk=0,rst=0;
    always #4 pix=~pix;
    always #5 clk=~clk;
    reg cfg=0,stop=0,job_ready=0,raw_valid=0,raw_sof=0,raw_eol=0,source_valid=0;
    reg [39:0] raw=0;
    reg [196:0] meta0=0,meta1=0;
    reg source0=0,pair_ready=0;
    wire source_ready0,pair_valid,legacy_valid;
    integer finishes0=0,finishes1=0,legacy_commits=0,pair_takes=0,aw_count=0,b_count=0;
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
    reg observe=0;
    assign awready=!write_active&&!bvalid;
    assign wready=write_active;
    full_raw_store #(.WIDTH(W),.HEIGHT(H),.DESCRIPTOR_ENABLE(1),.DUAL_CAPTURE_ENABLE(1),
        .PAIR_METADATA_ENABLE(1),.CAMERA_COUNT(1),.CANONICAL_PRIVATE_FETCH_ENABLE(1),
        .SHARED_REPLAY_FIFO_ENABLE(1),.STEREO_ENABLE(1),.STEREO_CAPTURE_DIVISOR(1)) dut(
        .i_cam1_hdr_enable(1'b0),.i_cam1_hdr_data(80'd0),.i_cam1_hdr_valid(2'b0),
        .i_cam1_hdr_sof(2'b0),.i_cam1_hdr_eol(2'b0),.i_cam1_hdr_abort(2'b0),
        .i_cam1_hdr_sequence(64'd0),.i_cam1_hdr_metadata(394'd0),
        .i_cam1_hdr_source_valid(2'b0),.i_cam1_hdr_source_ok(2'b0),
        .i_cam1_hdr_source_session(64'd0),.i_cam1_hdr_source_epoch(64'd0),
        .i_cam1_hdr_source_sequence(64'd0),.i_cam1_hdr_source_error(16'd0),
        .o_cam1_hdr_source_ready(),.o_cam1_hdr_idle(),
        .i_stereo_mode(1'b0),.i_stereo_mode_pixel(1'b0),.o_stereo_job_valid(job_valid),.i_stereo_job_ready(job_ready),.i_stereo_frame_divisor_pixel(8'd1),
        .o_stereo_job_frame(job_frame),.o_stereo_job_lease(job_lease),.o_stereo_job_id(job_id),
        .i_stereo_retire_valid(1'b0),.i_stereo_retire_job_id(64'd0),.o_stereo_empty(stereo_empty),
        .i_stereo_processing_done(1'b0),.i_stereo_processing_error(1'b0),.i_stereo_processing_job_id(64'd0),
        .i_sdr_lz_enable(1'b0),.i_lz_fault(1'b0),.i_lz_region_quiet(1'b1),
        .i_capture_time_valid(1'b1),.i_bayer_valid(1'b1),.i_isp_bayer_phase(2'd0),
        .o_raw_route_sdr(route_sdr),.o_raw_policy_admit(admit),
        .i_sdr_read_request_valid(1'b0),.i_sdr_read_request_context(448'd0),.i_sdr_read_ready(1'b0),
        .i_sdr_reader_cancel(1'b0),.i_sdr_release_valid(1'b0),.i_sdr_release_context(448'd0),.i_sdr_consumer_quiet(1'b1),
        .s_hdr_axi_arid(4'd0),.s_hdr_axi_araddr(28'd0),.s_hdr_axi_arlen(8'd0),.s_hdr_axi_arsize(3'd4),
        .s_hdr_axi_arburst(2'd1),.s_hdr_axi_arvalid(1'b0),.s_hdr_axi_rready(1'b0),
        .i_identity_rst_n(rst),.i_pair_stop(stop),.i_pair_fault(1'b0),
        .i_pair_config_valid(cfg),.o_pair_config_ready(cfg_ready),.o_pair_config_error(cfg_error),
        .i_pair_session(32'd17),.i_pair_epoch(32'd3),.i_pair_max_wait(32'd100),.i_pair_max_age(32'd1000),
        .i_pair_max_delta(64'd10),.i_pair_ratio(3'd4),.i_pair_hdr_enable(1'b1),
        .i_pair_ready(pair_ready),.i_pair_release_valid(1'b0),.i_pair_release_bank(1'b0),.i_pair_release_id(64'd0),
        .i_pair_read_quiet(1'b1),.i_pair_product_quiet(1'b1),.i_pair_ticket_released(1'b1),
        .i_pair_directory_valid(1'b0),.i_pair_directory_slot(2'd0),.m_pair_directory_ready(1'b0),.i_pair_now(64'd110),
        .i_capture_enable(1'b1),.i_pixel_clk(pix),.i_pixel_rst_n(rst),.i_dfi_clk(clk),.i_dfi_rst_n(rst),
        .i_ddr_ready(1'b1),.i_cfs_enable(1'b0),.i_physical_mono_current_enable(1'b0),
        .i_user_clk(clk),.i_user_rst_n(rst),
        .i_capture_data(raw),.i_capture_valid(raw_valid),.i_capture_accept(1'b1),
        .i_capture_sof(raw_sof),.i_capture_eol(raw_eol),.i_capture_abort(1'b0),
        .i_capture_epoch(32'd3),.i_session_id(32'd17),.i_frame_sequence(32'd10),.i_mode_epoch(32'd3),
        .i_capture_metadata(meta0),.i_capture_source_valid(source0),.i_capture_source_session(32'd17),
        .i_capture_source_epoch(32'd3),.i_capture_source_sequence(32'd10),.i_capture_source_camera(1'b0),
        .i_capture_source_ok(1'b1),.i_capture_source_error(8'd0),
        .i_capture1_clk(pix),.i_capture1_rst_n(rst),.i_capture1_data(raw),.i_capture1_valid(raw_valid),
        .i_capture1_accept(1'b1),.i_capture1_sof(raw_sof),.i_capture1_eol(raw_eol),.i_capture1_abort(1'b0),
        .i_capture1_session(32'd17),.i_capture1_sequence(32'd10),.i_capture1_epoch(32'd3),.i_capture1_metadata(meta1),
        .i_capture1_source_valid(source_valid),.o_capture1_source_ready(source_ready),
        .i_capture1_source_session(32'd17),.i_capture1_source_epoch(32'd3),.i_capture1_source_sequence(32'd10),
        .i_capture1_source_camera(1'b0),.i_capture1_source_ok(1'b1),.i_capture1_source_error(8'd0),
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
        .m_axi_arvalid(arvalid),.m_axi_arready(1'b1),.m_axi_rid(4'd1),.m_axi_rdata(128'd0),
        .m_axi_rresp(2'd0),.m_axi_rlast(1'b0),.m_axi_rvalid(1'b0),
        .m_axi_araddr(),.m_axi_arburst(),.m_axi_arid(),.m_axi_arlen(),.m_axi_arsize(),
        .m_axi_awburst(),.m_axi_awsize(),.m_axi_rready(),.m_axi_wdata(),.m_axi_wstrb(),
        .m_pair_directory_data(),.m_pair_directory_last(),.m_pair_directory_valid(),.m_pair_directory_word(),
        .m_shared_replay_data(),.m_shared_replay_valid(),.o_bar_read_data(),.o_bar_read_response(),
        .o_bar_read_response_valid(),.o_bar_write_response(),.o_capture_source_ready(source_ready0),.o_capture_source_stale_count(),
        .o_capture_write_quiescent(),.o_capture0_consume_fire(),.o_capture0_enqueue_fire(),.o_capture0_frame_accept(),
        .o_capture0_idle(),.o_capture1_consume_fire(),.o_capture1_enqueue_fire(),.o_capture1_frame_accept(),
        .o_capture1_idle(),.o_capture1_source_stale_count(),.o_cfs_busy_count(),.o_cfs_compressed_count(),
        .o_cfs_no_benefit_count(),.o_cfs_overflow_count(),.o_cfs_protocol_fault(),.o_commit_frame(),.o_commit_lease(),
        .o_commit_valid(legacy_valid),.o_host_replay_context_valid(),.o_host_replay_descriptor(),.o_host_replay_metadata_valid(),
        .o_lz_region_grant(),.o_lz_stop(),.o_mask_block_ready(),.o_mask_cache_retire(),.o_mask_command_data(),
        .o_mask_command_valid(),.o_mask_response_ready(),.o_pair_bank(),.o_pair_directory_ready(),.o_pair_id(),
        .o_pair_release_ready(),.o_pair_valid(pair_valid),.o_private_native_done(),.o_private_native_error(),
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
        .o_stereo_retire_ready(),.s_hdr_axi_arready(),.s_hdr_axi_rdata(),.s_hdr_axi_rid(),.s_hdr_axi_rlast(),
        .s_hdr_axi_rresp(),.s_hdr_axi_rvalid(),.s_shared_replay_ready());

    always @(posedge clk or negedge rst)begin
        if(!rst)begin write_active<=0;bvalid<=0;beats<=0;bid<=0;end
        else begin
            if(awvalid&&awready)begin
                if(awlen!=4)$fatal(1,"unexpected real HDR capture burst length");aw_count++;
                write_active<=1;beats<=awlen+1'b1;bid<=awid;
            end
            if(wvalid&&wready)begin
                if(wlast!=(beats==1))$fatal(1,"real capture WLAST shape");
                beats<=beats-1'b1;
                if(wlast)begin write_active<=0;bvalid<=1;end
            end
            if(bvalid&&bready)begin bvalid<=0;b_count++;end
        end
    end
    task check_descriptor(input [383:0] frame,input integer role);
        begin
            if(frame[2:1]!=role||frame[108:77]!=10||frame[76:45]!=17||frame[140:109]!=3||frame[366:335]!=10)
                $fatal(1,"real writer member descriptor identity");
        end
    endtask
    always @(posedge clk)if(rst)begin
        if(dut.finish_valid&&dut.finish_ready)begin
            if(!dut.finish_ok)$fatal(1,"LONG finish not OK");
            check_descriptor(dut.capture_frame,1);finishes0++;
        end
        if(dut.finish_valid1&&dut.hdr_finish1_ready)begin
            if(!dut.finish_ok1)$fatal(1,"SHORT finish not OK");
            check_descriptor(dut.capture_frame1,2);finishes1++;
        end
        if(legacy_valid)begin
            if(!(dut.finish_valid&&dut.finish_ready&&dut.finish_ok))$fatal(1,"legacy observation without LONG finish");
            legacy_commits++;
        end
        if(pair_valid)begin
            if(finishes0!=1||finishes1!=1)$fatal(1,"pair presented before both real member writes completed");
            if(pair_ready)pair_takes++;
        end
    end
    integer g;
    initial begin
        meta0[196:193]=4'b1101;meta1[196:193]=4'b1110;
        meta0[192]=`PCIE_RECORD_V2_SOURCE_PHYSICAL;meta1[192]=`PCIE_RECORD_V2_SOURCE_PHYSICAL;
        meta0[191:160]=10;meta1[191:160]=10;
        meta0[159:128]=32'h56a3d02f;meta1[159:128]=32'h56a3d02f;
        meta0[127:96]=256;meta1[127:96]=256;
        meta0[95:64]=3200;meta1[95:64]=200;meta0[63:0]=100;meta1[63:0]=104;
        #500;rst=1;repeat(100)@(negedge clk);
        cfg=1;do @(posedge clk);while(!cfg_ready);
        if(cfg_error)$fatal(1,"real HDR configuration rejected");
        @(negedge clk);cfg=0;wait(admit&&!route_sdr);repeat(30)@(negedge pix);
        for(g=0;g<G;g=g+1)begin
            raw={10'd13,10'd7,10'd3,10'd1};raw_valid=1;raw_sof=g==0;raw_eol=g%(W/4)==W/4-1;
            @(negedge pix);
        end
        raw_valid=0;raw_sof=0;raw_eol=0;repeat(4)@(negedge pix);
        fork
            begin source0=1;do @(posedge pix);while(!source_ready0);@(negedge pix);source0=0;end
            begin source_valid=1;do @(posedge pix);while(!source_ready);@(negedge pix);source_valid=0;end
        join
        wait(pair_valid);repeat(4)@(negedge clk);
        if(finishes0!=1||finishes1!=1||legacy_commits!=1||aw_count!=2||b_count!=2||fault)
            $fatal(1,"HDR contract counts finish=%0d/%0d legacy=%0d AW/B=%0d/%0d fault=%b",finishes0,finishes1,legacy_commits,aw_count,b_count,fault);
        pair_ready=1;@(negedge clk);pair_ready=0;repeat(4)@(negedge clk);
        if(pair_takes!=1)$fatal(1,"actual pair acquire count");
        $display("RESULT: PASS HDR_COMMIT_CONTRACT real_member_finish=1/1 legacy_long_commit=1 pair_acquire=1 AW=2 B=2");$finish;
    end
    initial begin #1000000;$fatal(1,"real HDR commit contract watchdog");end
endmodule
