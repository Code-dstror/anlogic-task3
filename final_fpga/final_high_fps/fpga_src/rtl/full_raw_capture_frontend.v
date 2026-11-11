`timescale 1ns/1ps
// One passive capture datapath. External policy authorities retain their own
// descriptors, directory layouts, read/consumer proofs and identity counters.
module full_raw_capture_frontend #(parameter integer WIDTH=1920,HEIGHT=1080, HDR_MEMBER_ONLY=0, HDR_CAMERA_ID=0,
    parameter integer FIXED_HDR_ROLE=0,COMPACT_CAPTURE_HEADER=0,FENCE_COUNTER_BITS=32,STEREO_ENABLE=0,STEREO_CAPTURE_DIVISOR=4,STEREO_RUNTIME_CADENCE=0,
    parameter integer UHD_WIDTH=0,UHD_HEIGHT=0)(
    input pixel_clk,dfi_clk,cold_rst_n,
    input region_grant,stop,app_reset,capture_enable,
    // PIX-owned cold-mailbox mode; applied while admission is paused.
    input wire i_stereo_mode_pixel,
    // PIX-owned cold-mailbox output, stable throughout every admitted frame.
    input wire [7:0] i_stereo_frame_divisor_pixel,
    output capture_enqueue_fire,capture_consume_fire,capture_idle,capture_frame_accept,capture_writer_quiet,
    input select_valid,select_sdr,input [31:0] select_session,select_epoch,
    output select_ready,output reg select_applied,select_error,
    output reg route_sdr,output reg [31:0] active_session,active_epoch,
    input policy_quiet,policy_admit,output policy_stop,local_quiet,region_quiet,
    input [39:0] raw_data,input raw_valid,raw_accept,raw_sof,raw_eol,raw_abort,
    input [31:0] raw_sequence,input [196:0] raw_metadata,
    input time_valid, input bayer_valid,input [1:0] bayer_pattern,
    input source_valid,output source_ready,input [31:0] source_session,source_epoch,source_sequence,
    input source_camera,source_ok,input [7:0] source_error,
    output [383:0] capture_frame,output begin_valid,input begin_ready,begin_accepted,
    input [1:0] capture_slot,output finish_valid,finish_ok,input finish_ready,
    output fault,output [31:0] source_stale_count,capture_drops,capture_errors,
    output reg [31:0] source_frames,selected_frames,skipped_frames,
    output [3:0] m_axi_awid,output [27:0] m_axi_awaddr,output [7:0] m_axi_awlen,
    output [2:0] m_axi_awsize,output [1:0] m_axi_awburst,output m_axi_awvalid,input m_axi_awready,
    output [127:0] m_axi_wdata,output [15:0] m_axi_wstrb,output m_axi_wlast,m_axi_wvalid,input m_axi_wready,
    input [3:0] m_axi_bid,input [1:0] m_axi_bresp,input m_axi_bvalid,output m_axi_bready,
    input wire i_uhd_pixel
);
    wire pix_rst,dfi_rst;
    reset_release_sync #(.FALLING_RELEASE(1)) pr(.i_clk(pixel_clk),.i_async_rst_n(cold_rst_n),.o_rst_n(pix_rst));
    reset_release_sync #(.FALLING_RELEASE(1)) dr(.i_clk(dfi_clk),.i_async_rst_n(cold_rst_n),.o_rst_n(dfi_rst));
    reg configured,cfg_request,cfg_pending,cfg_ack,pix_configured,pix_sdr;
    reg [31:0] pix_session,pix_epoch;
    // The source holds this 65-bit bundle until cfg_ack returns. Only these
    // capture registers see the asynchronous bus; comparison and publication
    // run one full PIX cycle later from the captured local values.
    reg cfg_capture_pending;
    (* preserve *) reg cfg_sample_sdr;
    (* preserve *) reg [31:0] cfg_sample_session,cfg_sample_epoch;
    reg [1:0] cfg_request_sync,stop_sync;
    // Imported from the source-bound ClockTree fix; only stage 1 owns ACK.
    (* preserve="true", ASYNC_REG="TRUE" *) reg [1:0] cfg_ack_sync;
    reg phase,phase_valid,selected;
    // Local publication keeps mode fanout at this capture lane. This is not
    // another CDC: the common cold mailbox already owns the PIX mode copy.
    (* preserve="true" *) reg stereo_local;
    reg [7:0] stereo_phase;
    reg [7:0] stereo_last_divisor;
    wire [7:0] stereo_divisor=STEREO_RUNTIME_CADENCE!=0?
        i_stereo_frame_divisor_pixel:STEREO_CAPTURE_DIVISOR[7:0];
    wire cadence_changed=stereo_divisor!=stereo_last_divisor;
    wire stereo_pixel=STEREO_ENABLE!=0&&stereo_local;
    wire capture_camera=stereo_pixel ? HDR_MEMBER_ONLY!=0 : HDR_CAMERA_ID!=0;
    reg stop_was,drain_request,drain_ack,fence_matched;
    reg drain_hold;
    // Publish the complete DFI STOP level before its PIX synchronizer.
    (* preserve *) reg stop_publish;
    reg [1:0] drain_request_sync,drain_ack_sync;
    // Generic callers retain 32 bits. The dedicated 147x512 capture wrapper
    // chooses 10: 512 RAM words plus up to two native FWFT/output stages,
    // one source elastic token and two sink elastic tokens give 517 < 1024.
    // A writer-consumed token is already counted in consumed; AW/W/B debt is
    // retained independently by writer_quiet and is never inferred here.
    // The retained STOP request/ACK freezes production before equality is used.
    // Thus equality modulo 1024 is exact even across arbitrarily many wraps.
    reg [FENCE_COUNTER_BITS-1:0] produced,consumed,frozen_produced,fence_count;
    wire ingress_idle,writer_quiet;
    wire [146:0] enqueue,dequeue;
    wire enqueue_valid,enqueue_ready,dequeue_valid,dequeue_ready,source_reset_done,sink_reset_done;
    wire [9:0] available;
    wire requested_stop=stop||app_reset||!region_grant||select_valid||!configured||cfg_pending||fault||!policy_admit;
    // A STOP starts one retained drain transaction. A later short RUN cannot
    // reopen PIX or toggle a second request before the old PIX snapshot, FIFO
    // count and actual writer have all drained. Repeated STOPs coalesce while
    // this owner is held; no request/ACK phase can be reused as a fresh proof.
    wire effective_stop=requested_stop||drain_hold;
    wire physical_sof=raw_valid&&raw_accept&&raw_sof;
    wire select_now=!(HDR_MEMBER_ONLY && pix_sdr&&!stereo_pixel)&&pix_configured&&!stop_sync[1]&&(pix_sdr||capture_enable)&&
        (stereo_pixel?(stereo_divisor!=0&&!cadence_changed&&stereo_phase==0):(!pix_sdr||!phase_valid||raw_sequence[0]==phase));
    wire selected_input=physical_sof?select_now:selected;
    assign policy_stop=effective_stop;
    // Retained drain ownership cuts joint config READY/commit feedback.
    assign local_quiet=drain_hold&&stop_was&&fence_matched&&consumed==fence_count&&
        !dequeue_valid&&writer_quiet&&!fault&&sink_reset_done;
    assign region_quiet=local_quiet&&policy_quiet;
    // Config may apply while externally stopped, but only after real quiet.
    // STOP still prevents every capture throughout and after the ACK.
    assign select_ready=region_quiet&&!cfg_pending&&region_grant;
    assign capture_enqueue_fire=enqueue_valid&&enqueue_ready;
    assign capture_consume_fire=dequeue_valid&&dequeue_ready;
    assign capture_idle=ingress_idle;
    assign capture_writer_quiet=writer_quiet;
    always @(posedge dfi_clk or negedge dfi_rst)begin
        if(!dfi_rst)begin
            configured<=0;cfg_request<=0;cfg_pending<=0;cfg_ack_sync<=0;
            route_sdr<=0;active_session<=0;active_epoch<=0;select_applied<=0;select_error<=0;
            stop_publish<=1;
            drain_hold<=1;stop_was<=0;drain_request<=0;drain_ack_sync<=0;fence_matched<=0;fence_count<=0;consumed<=0;
        end else begin
            cfg_ack_sync<={cfg_ack_sync[0],cfg_ack};drain_ack_sync<={drain_ack_sync[0],drain_ack};
            stop_publish<=effective_stop;
            select_applied<=0;select_error<=0;stop_was<=effective_stop;
            if(requested_stop)drain_hold<=1;
            else if(local_quiet)drain_hold<=0;
            if(effective_stop&&!stop_was)drain_request<=!drain_request;
            fence_matched<=effective_stop&&stop_was&&drain_ack_sync[1]==drain_request;
            if(effective_stop&&stop_was&&drain_ack_sync[1]==drain_request)fence_count<=frozen_produced;
            if(dequeue_valid&&dequeue_ready)consumed<=consumed+1'b1;
            if(select_valid&&select_ready)begin
                if(select_session==0)select_error<=1;
                else begin
                    route_sdr<=select_sdr;active_session<=select_session;active_epoch<=select_epoch;
                    configured<=1;cfg_request<=!cfg_request;cfg_pending<=1;
                end
            end
            if(cfg_pending&&cfg_ack_sync[1]==cfg_request)begin cfg_pending<=0;select_applied<=1;end
        end
    end
    always @(posedge pixel_clk or negedge pix_rst)begin
        if(!pix_rst)begin
            cfg_request_sync<=0;cfg_ack<=0;pix_configured<=0;pix_sdr<=0;pix_session<=0;pix_epoch<=0;
            cfg_capture_pending<=0;cfg_sample_sdr<=0;cfg_sample_session<=0;cfg_sample_epoch<=0;
            stereo_local<=0;stereo_phase<=0;stereo_last_divisor<=STEREO_CAPTURE_DIVISOR;
            stop_sync<=3;drain_request_sync<=0;drain_ack<=0;phase<=0;phase_valid<=0;selected<=0;
            produced<=0;frozen_produced<=0;source_frames<=0;selected_frames<=0;skipped_frames<=0;
        end else begin
            stereo_local<=STEREO_ENABLE!=0&&i_stereo_mode_pixel;
            stereo_last_divisor<=stereo_divisor;
            if(!stereo_pixel||cadence_changed)stereo_phase<=0;
            cfg_request_sync<={cfg_request_sync[0],cfg_request};stop_sync<={stop_sync[0],stop_publish};
            drain_request_sync<={drain_request_sync[0],drain_request};
            if(!cfg_capture_pending&&cfg_request_sync[1]!=cfg_ack)begin
                cfg_sample_sdr<=route_sdr;cfg_sample_session<=active_session;cfg_sample_epoch<=active_epoch;
                cfg_capture_pending<=1;
            end
            if(cfg_capture_pending)begin
                if(!pix_configured||pix_sdr!=cfg_sample_sdr||pix_session!=cfg_sample_session||pix_epoch!=cfg_sample_epoch)phase_valid<=0;
                pix_session<=cfg_sample_session;pix_epoch<=cfg_sample_epoch;pix_sdr<=cfg_sample_sdr;
                pix_configured<=1;cfg_ack<=cfg_request_sync[1];cfg_capture_pending<=0;
            end
            if(physical_sof)begin
                if(stereo_pixel&&!cadence_changed)stereo_phase<=stereo_phase==stereo_divisor-1?8'd0:stereo_phase+1'b1;
                if(pix_sdr&&pix_configured&&!stop_sync[1]&&!phase_valid)begin phase<=raw_sequence[0];phase_valid<=1;end
                selected<=select_now;source_frames<=source_frames+1'b1;
                if(select_now)selected_frames<=selected_frames+1'b1;else skipped_frames<=skipped_frames+1'b1;
            end
            if(enqueue_valid&&enqueue_ready)produced<=produced+1'b1;
            if(stop_sync[1]&&ingress_idle&&!enqueue_valid&&drain_ack!=drain_request_sync[1])begin
                frozen_produced<=produced;drain_ack<=drain_request_sync[1];
            end
        end
    end
    shared_raw10_frame_ingress #(.WIDTH(WIDTH),.HEIGHT(HEIGHT),.CONTEXT_ENABLE(1),
        .EXTERNAL_SEQUENCE_ENABLE(1),.PAIR_METADATA_ENABLE(1),.SOURCE_TERMINAL_ENABLE(1),.FIXED_HDR_ROLE(FIXED_HDR_ROLE),
        .COMPACT_CAPTURE_HEADER(COMPACT_CAPTURE_HEADER),.UHD_WIDTH(UHD_WIDTH),.UHD_HEIGHT(UHD_HEIGHT)) ingress(
        .i_clk(pixel_clk),.i_rst_n(pix_rst),.i_enable(!(HDR_MEMBER_ONLY && pix_sdr&&!stereo_pixel)&&pix_configured&&!stop_sync[1]&&(pix_sdr||capture_enable)),.i_sdr_profile(pix_sdr),
        .i_uhd(i_uhd_pixel),
        .i_data(raw_data),.i_valid(raw_valid&&selected_input),.i_accept(raw_accept),.i_sof(raw_sof),.i_eol(raw_eol),
        .i_abort(raw_abort&&selected),.i_camera(capture_camera),.i_epoch(pix_epoch),.i_external_sequence(raw_sequence),.i_session_id(pix_session),
        .i_time_valid(time_valid),.i_metadata_valid(raw_metadata[196]),.i_timestamp(raw_metadata[63:0]),.i_actual_exposure(raw_metadata[95:64]),
        .i_gain(raw_metadata[127:96]),.i_calibration_id(raw_metadata[159:128]),.i_exposure_group(raw_metadata[191:160]),
        .i_source_kind(raw_metadata[192]),.i_exposure_role(raw_metadata[194:193]),.i_source_qualified(raw_metadata[195]),
        .i_bayer_valid(bayer_valid),.i_bayer_pattern(bayer_pattern),
        .i_source_valid(source_valid),.o_source_ready(source_ready),.i_source_session(source_session),.i_source_epoch(source_epoch),
        .i_source_sequence(source_sequence),.i_source_camera(source_camera),.i_source_ok(source_ok),.i_source_error(source_error),
        .o_source_stale_count(source_stale_count),.o_axis_tdata(enqueue[127:0]),.o_axis_tkeep(enqueue[143:128]),
        .o_axis_tlast(enqueue[144]),.o_axis_tuser(enqueue[146:145]),.o_axis_tvalid(enqueue_valid),.i_axis_tready(enqueue_ready),
        .o_capture_idle(ingress_idle),.o_frame_accept(capture_frame_accept),.o_drop_count(capture_drops),.o_error_count(capture_errors));
    raw_capture_fifo_eram_safe capture_fifo(.i_source_clk(pixel_clk),.i_source_rst_n(pix_rst),.i_source_data(enqueue),
        .i_source_valid(enqueue_valid),.o_source_ready(enqueue_ready),.o_source_reset_done(source_reset_done),
        .i_sink_clk(dfi_clk),.i_sink_rst_n(dfi_rst),.o_sink_data(dequeue),.o_sink_valid(dequeue_valid),.i_sink_ready(dequeue_ready),
        .o_available_count(available),.o_sink_reset_done(sink_reset_done));
    shared_raw_capture_writer #(.WIDTH(WIDTH),.HEIGHT(HEIGHT),.CAMERA_COUNT((STEREO_ENABLE!=0||HDR_CAMERA_ID!=0)?2:1),
        .FIXED_HDR_ROLE(FIXED_HDR_ROLE),.COMPACT_CAPTURE_HEADER(COMPACT_CAPTURE_HEADER),.UHD_WIDTH(UHD_WIDTH),.UHD_HEIGHT(UHD_HEIGHT)) writer(
        .i_clk(dfi_clk),.i_identity_rst_n(dfi_rst),.i_stop(effective_stop),.i_sdr_profile(route_sdr),
        .s_data(dequeue[127:0]),.s_keep(dequeue[143:128]),.s_last(dequeue[144]),.s_user(dequeue[146:145]),
        .s_valid(dequeue_valid),.s_ready(dequeue_ready),.i_available(available),.o_frame(capture_frame),
        .o_begin_valid(begin_valid),.i_begin_ready(begin_ready),.i_begin_accepted(begin_accepted),.i_capture_slot(capture_slot),
        .o_finish_valid(finish_valid),.o_finish_ok(finish_ok),.i_finish_ready(finish_ready),.o_quiet(writer_quiet),
        .o_protocol_fault(fault),.o_success_count(),.o_error_count(),
        .m_axi_awid(m_axi_awid),.m_axi_awaddr(m_axi_awaddr),.m_axi_awlen(m_axi_awlen),.m_axi_awsize(m_axi_awsize),.m_axi_awburst(m_axi_awburst),.m_axi_awvalid(m_axi_awvalid),.m_axi_awready(m_axi_awready),
        .m_axi_wdata(m_axi_wdata),.m_axi_wstrb(m_axi_wstrb),.m_axi_wlast(m_axi_wlast),.m_axi_wvalid(m_axi_wvalid),.m_axi_wready(m_axi_wready),
        .m_axi_bid(m_axi_bid),.m_axi_bresp(m_axi_bresp),.m_axi_bvalid(m_axi_bvalid),.m_axi_bready(m_axi_bready));
endmodule
