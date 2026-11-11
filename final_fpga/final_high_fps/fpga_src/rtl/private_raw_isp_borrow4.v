`timescale 1ns / 1ps

// Authenticated private RAW source and the unique ISP/native RGB boundary.
module private_raw_isp_borrow4 #(
    parameter integer MAX_WIDTH=1920,MAX_HEIGHT=1080,
    parameter integer RAW_SAMPLE_BITS=10,
    parameter integer EXTERNAL_ISP_ENABLE=0,
    // Original owner only; preserve the legacy profile for other integrations.
    parameter integer ORIGINAL_SYNC_CLEAR_ENABLE=0,
    parameter integer BASE_WIDTH=1920, BASE_HEIGHT=1080
)(
    input wire i_pixel_clk,i_pixel_rst_n,
    input wire i_context_fire,i_context_private,
    input wire [383:0] i_context_frame,
    input wire [63:0] i_context_job,i_context_pair,i_context_key,i_context_aux,
    input wire i_context_member,
    output wire o_context_available,o_payload_enable,o_pool_idle,
    input wire i_owner_published,i_owner_valid,input wire [383:0] i_owner_frame,
    input wire [63:0] i_owner_lease,i_owner_job,i_owner_pair,i_owner_native_tag,
    input wire [31:0] i_owner_writer_tag,input wire i_owner_member,
    input wire [1:0] i_bayer_phase,input wire [29:0] i_wb_gains,
    input wire i_hdr_enable,input wire [3:0] i_tone_shift,
    output wire [4*RAW_SAMPLE_BITS-1:0] o_isp_raw_data,
    output wire o_isp_raw_valid,o_isp_raw_sof,o_isp_raw_eol,
    input wire i_isp_raw_ready,input wire [95:0] i_isp_rgb,
    input wire i_isp_rgb_valid,i_isp_rgb_sof,i_isp_rgb_eol,i_isp_idle,
    output wire o_isp_rgb_ready,o_isp_reset_n,
    output wire [1:0] o_isp_bayer_phase,output wire [29:0] o_isp_wb_gains,
    output wire o_isp_hdr_enable,output wire [3:0] o_isp_tone_shift,
    input wire [4*RAW_SAMPLE_BITS-1:0] s_raw_data,
    input wire s_raw_valid,s_raw_sof,s_raw_eol,output wire s_raw_ready,
    input wire s_raw_source_valid,output wire s_raw_source_ready,
    input wire [383:0] s_raw_source_frame,
    input wire [63:0] s_raw_source_lease,s_raw_source_job,s_raw_source_pair,s_raw_source_tag,
    input wire s_raw_source_member,s_raw_source_ok,input wire [7:0] s_raw_source_error,
    input wire i_raw_source_read_quiescent,i_pixel_cancel,
    input wire i_pipeline_quiescent,i_post_pool_idle,i_post_pixel_fault,i_processed_source_fire,
    output wire [575:0] m_context,output wire m_context_valid,input wire m_context_ready,
    output wire [95:0] m_rgb,output wire [3:0] m_keep,
    output wire m_sof,m_eol,m_last,m_valid,input wire m_ready,
    output wire [63:0] m_tag,output wire [31:0] m_index,
    output wire m_status_valid,input wire m_status_ready,output wire [575:0] m_status_context,
    output wire [63:0] m_status_tag,output wire m_status_ok,output wire [7:0] m_status_error,
    output wire [31:0] m_status_groups,output wire o_original_read_quiescent,
    output wire o_locked_owner_valid,output wire [383:0] o_locked_frame,
    output wire [63:0] o_locked_lease,o_locked_job,o_locked_pair,o_locked_native_tag,
    output wire [31:0] o_locked_writer_tag,output wire o_locked_member,
    output wire o_pixel_fault,o_isp_idle,o_isp_cleanup,output wire [31:0] o_stale_raw_source_count
);
    wire pixel_reset_n, pixel_data_reset_n;
    // Keep the falling ASR release and qualify same-domain handshakes
    // from the existing rising release stage. The first sample is unchanged.
    reset_release_sync_data #(.DATA_RESET_COPIES(0),.FALLING_RELEASE(1)) u_pixel_reset(
        .i_clk(i_pixel_clk),.i_async_rst_n(i_pixel_rst_n),
        .o_rst_n(pixel_reset_n),.o_data_rst_n(pixel_data_reset_n));
    generate if(RAW_SAMPLE_BITS!=10 && RAW_SAMPLE_BITS!=14)begin: bad_sample_width
        PRIVATE_RAW_SAMPLE_BITS_MUST_BE_TEN_OR_FOURTEEN invalid_configuration();
    end endgenerate
    localparam [2:0] IDLE=0, WAIT_OWNER=1, OPEN=2, RUN=3, DRAIN=4, FAULT=5;
    reg [2:0] state, state_next;
    // The unique PIX ticket publication is immutable until this entire
    // source/post chain reports pool_idle. No second frame/lease owner.
    wire [383:0] frame=i_owner_frame;
    wire [63:0] job=i_owner_job,pair=i_owner_pair,lease=i_owner_lease;
    wire [63:0] key={frame[76:45],31'd0,frame[4]},aux=job;
    wire member=i_owner_member;
    wire [31:0] writer_tag=i_owner_writer_tag;
    reg [63:0] native_tag;
    reg [1:0] phase;
    reg [29:0] gains;
    reg hdr;
    reg [3:0] tone_shift;
    reg raw_source_seen, raw_source_sent, raw_source_ok, raw_source_quiet, poisoned;
    reg [7:0] raw_source_error;
    reg raw_held;
    reg protocol_fault;
    reg context_available;
    reg [31:0] stale_raw_source_count;
    wire [575:0] native_context={aux,key,native_tag,frame};
    // Authenticate the original full command before borrowing. Main's
    // ticket is already published, but context_owned rises next edge.
    wire command_match=i_owner_published && i_context_frame==i_owner_frame &&
        i_context_job==i_owner_job && i_context_pair==i_owner_pair &&
        i_context_member==i_owner_member && i_context_key==key && i_context_aux==aux;
    wire owner_match=i_owner_lease!=0 && i_owner_writer_tag!=0 && i_owner_native_tag!=0;
    wire source_match=s_raw_source_frame==frame && s_raw_source_job==job &&
        s_raw_source_pair==pair && s_raw_source_lease==lease && s_raw_source_member==member &&
        s_raw_source_tag==native_tag;
    assign s_raw_source_ready=pixel_data_reset_n && (state==RUN || state==DRAIN);
    wire raw_source_fire=s_raw_source_valid && s_raw_source_ready;
    wire exact_source_fire=raw_source_fire && source_match && !raw_source_seen;
    wire source_failure=!s_raw_source_ok || s_raw_source_error!=0 || poisoned || i_pixel_cancel;
    wire adapter_context_ready, adapter_busy, adapter_context_fire;
    wire adapter_status_input_ready, adapter_source_ready;
    wire [575:0] original_context;
    wire original_context_valid;
    wire [95:0] original_rgb;
    wire [3:0] original_keep;
    wire original_sof, original_eol, original_last, original_valid, original_ready;
    wire [63:0] original_tag;
    wire [31:0] original_index, original_status_groups;
    wire original_status_valid, original_status_ok, original_quiet;
    wire [7:0] original_status_error;
    wire [63:0] original_status_tag;
    wire original_status_ready;
    wire isp_valid, isp_ready, isp_sof, isp_eol, isp_raw_ready, isp_reset_n;
    wire [95:0] isp_rgb;
    wire cleanup_pending, cleanup_status, cleanup_fault;
    wire [55:0] raw14;
    genvar lane;
    generate for(lane=0;lane<4;lane=lane+1)begin: extend_raw
        assign raw14[lane*14 +: 14]={{(14-RAW_SAMPLE_BITS){1'b0}},s_raw_data[lane*RAW_SAMPLE_BITS +: RAW_SAMPLE_BITS]};
    end endgenerate
    wire raw_to_isp=state==RUN && (!poisoned && !i_pixel_cancel || raw_held);
    wire raw_isp_valid=s_raw_valid && raw_to_isp;
    assign s_raw_ready=pixel_data_reset_n && state==RUN && (raw_to_isp ? isp_raw_ready : 1'b1);
    assign o_payload_enable=pixel_data_reset_n && state==RUN;
    assign adapter_context_fire=state==OPEN && adapter_context_ready;
    assign o_isp_reset_n=isp_reset_n;
    assign o_isp_bayer_phase=phase;
    assign o_isp_wb_gains=gains;
    assign o_isp_hdr_enable=hdr;
    assign o_isp_tone_shift=tone_shift;
    generate if(EXTERNAL_ISP_ENABLE==0)begin : g_internal_isp
    assign o_isp_raw_data=0;assign o_isp_raw_valid=0;
    assign o_isp_raw_sof=0;assign o_isp_raw_eol=0;assign o_isp_rgb_ready=0;
    shared_wide_isp #(.MAX_WIDTH(MAX_WIDTH),.MAX_HEIGHT(MAX_HEIGHT),.HDR_BLACK_CORRECTED_ENABLE(RAW_SAMPLE_BITS==14)) u_isp(
        .clk(i_pixel_clk),.rst_n(isp_reset_n),.cfg_width(frame[217:205]),.cfg_height(frame[233:221]),
        .cfg_bayer_phase(phase),.cfg_hdr(hdr),.cfg_tone_shift(tone_shift),.cfg_tone_preset(2'd0),.cfg_wb_gains(gains),
        .s_data(raw14),.s_valid(raw_isp_valid),.s_ready(isp_raw_ready),.s_sof(s_raw_sof),.s_eol(s_raw_eol),
        .m_data(isp_rgb),.m_valid(isp_valid),.m_ready(isp_ready),.m_sof(isp_sof),.m_eol(isp_eol),
        .o_job_idle(o_isp_idle),.stat_beats(),.stat_frames(),.stat_saturated());
    end else if(EXTERNAL_ISP_ENABLE==1)begin : g_external_isp
        assign o_isp_raw_data=s_raw_data;assign o_isp_raw_valid=raw_isp_valid;
        assign o_isp_raw_sof=s_raw_sof;assign o_isp_raw_eol=s_raw_eol;
        assign isp_raw_ready=i_isp_raw_ready;
        assign isp_rgb=i_isp_rgb;assign isp_valid=i_isp_rgb_valid;
        assign isp_sof=i_isp_rgb_sof;assign isp_eol=i_isp_rgb_eol;
        assign o_isp_rgb_ready=isp_ready;assign o_isp_idle=i_isp_idle;
    end else begin : bad_external_isp
        PRIVATE_EXTERNAL_ISP_ENABLE_MUST_BE_ZERO_OR_ONE invalid_configuration();
    end endgenerate
    hdr_pair_product_abort_drain4 #(.SYNC_CLEAR_ENABLE(ORIGINAL_SYNC_CLEAR_ENABLE),.FALLING_INPUT_RESET(1)) u_original_cleanup(
        .clk(i_pixel_clk),.rst_n(pixel_reset_n),.i_context_fire(adapter_context_fire),.i_context_tag(native_tag),
        .i_source_fire(exact_source_fire),.i_source_tag(s_raw_source_tag),
        .i_source_ok(!source_failure),.i_source_read_quiescent(i_raw_source_read_quiescent),
        .i_native_job_start(raw_isp_valid && isp_raw_ready && s_raw_sof),
        .i_native_valid(s_raw_valid),.i_isp_valid(isp_valid),.i_preprocess_valid(original_valid),.i_admission_valid(1'b0),
        .i_data_reset_n(pixel_reset_n),.o_local_data_rst_n(),
        .o_local_rst_n(isp_reset_n),.o_drain_pending(cleanup_pending),
        .o_failed_status_valid(cleanup_status),.i_failed_status_ready(1'b1),
        .o_protocol_fault(cleanup_fault),.o_stale_source_count(),.o_cleanup_pulse(o_isp_cleanup));
    camera_rgb_native_fixed1080_borrow4 #(.MAX_WIDTH(MAX_WIDTH),.MAX_HEIGHT(MAX_HEIGHT),
        .BASE_WIDTH(BASE_WIDTH),.BASE_HEIGHT(BASE_HEIGHT)) u_adapter(
        .clk(i_pixel_clk),.rst_n(pixel_reset_n),.s_context(native_context),
        .s_context_valid(state==OPEN),.s_context_ready(adapter_context_ready),
        .s_rgb(isp_rgb),.s_valid(isp_valid),.s_ready(isp_ready),.s_sof(isp_sof),.s_eol(isp_eol),
        .i_cancel(poisoned || i_pixel_cancel),.i_pipeline_error(1'b0),
        .i_pipeline_quiescent(o_isp_idle && !cleanup_pending),.i_source_read_quiescent(raw_source_quiet),
        .i_source_status_valid(raw_source_seen && !raw_source_sent),.o_source_status_ready(adapter_status_input_ready),
        .i_source_status_tag(native_tag),.i_source_status_ok(raw_source_ok),.i_source_status_error(raw_source_error),
        .m_context(original_context),.m_context_valid(original_context_valid),.m_context_ready(adapter_source_ready),
        .m_rgb(original_rgb),.m_keep(original_keep),.m_sof(original_sof),.m_eol(original_eol),.m_last(original_last),
        .m_valid(original_valid),.m_ready(original_ready),.m_tag(original_tag),.m_index(original_index),
        .m_status_valid(original_status_valid),.m_status_ready(original_status_ready),.m_status_tag(original_status_tag),
        .m_status_ok(original_status_ok),.m_status_error(original_status_error),.m_status_groups(original_status_groups),
        .o_read_quiescent(original_quiet),.o_busy(adapter_busy),.o_cancel_request(),
        .o_input_groups(),.o_output_groups(),.o_stale_status_count());

    wire post_pool_idle=i_post_pool_idle, post_pixel_fault=i_post_pixel_fault;
    assign o_stale_raw_source_count=stale_raw_source_count;
    assign o_pixel_fault=protocol_fault || cleanup_fault || post_pixel_fault;
    assign o_context_available=context_available&&!i_pixel_cancel&&!o_pixel_fault;
    assign o_pool_idle=o_context_available;

    always @(posedge i_pixel_clk or negedge pixel_reset_n)begin
        if(!pixel_reset_n)context_available<=0;
        else if(i_context_fire||state!=IDLE||i_pixel_cancel||o_pixel_fault)context_available<=0;
        else context_available<=i_pipeline_quiescent&&o_isp_idle&&!adapter_busy&&!cleanup_pending&&post_pool_idle;
    end

    always @(*) begin
        state_next=state;
        case(state)
            IDLE: if(i_context_fire)begin
                if(!o_context_available || !i_context_private || !command_match || i_context_job==0 ||
                    i_context_frame[220:205]==0 || i_context_frame[220:205]>MAX_WIDTH ||
                    i_context_frame[206:205]!=0 || i_context_frame[236:221]==0 ||
                    i_context_frame[236:221]>MAX_HEIGHT)state_next=FAULT;
                else state_next=WAIT_OWNER;
            end
            WAIT_OWNER: if(i_owner_valid)state_next=owner_match ? OPEN : FAULT;
            OPEN: if(adapter_context_fire)state_next=RUN;
            RUN: if(i_processed_source_fire)state_next=DRAIN;
            DRAIN: if(!adapter_busy && !cleanup_pending && post_pool_idle && i_pipeline_quiescent)state_next=IDLE;
            FAULT: state_next=FAULT;
            default: state_next=FAULT;
        endcase
        if(i_context_fire && state!=IDLE)state_next=FAULT;
        if(exact_source_fire && !i_raw_source_read_quiescent)state_next=FAULT;
        if(state!=IDLE && !i_owner_published)state_next=FAULT;
        if((state==OPEN || state==RUN || state==DRAIN) &&
            (!i_owner_valid || i_owner_native_tag!=native_tag))state_next=FAULT;
    end
    always @(posedge i_pixel_clk or negedge pixel_reset_n)begin
        if(!pixel_reset_n)state<=IDLE;
        else state<=state_next;
    end
    // Upstream SOURCE authentication and unpublished ISP cleanup stay here.
    always @(posedge i_pixel_clk or negedge pixel_reset_n)begin
        if(!pixel_reset_n)begin
            native_tag<=0;
            phase<=0;gains<={3{10'd256}};hdr<=0;tone_shift<=0;raw_source_seen<=0;raw_source_sent<=0;raw_source_ok<=0;
            raw_source_quiet<=0;raw_source_error<=0;poisoned<=0;raw_held<=0;
            protocol_fault<=0;stale_raw_source_count<=0;
        end else begin
            raw_held<=raw_isp_valid && !isp_raw_ready;
            if(state_next==FAULT)protocol_fault<=1;
            if(state==IDLE && i_context_fire && state_next==WAIT_OWNER)begin
                raw_source_seen<=0;raw_source_sent<=0;
                raw_source_ok<=0;raw_source_quiet<=0;raw_source_error<=0;poisoned<=0;
            end
            if(state==WAIT_OWNER && i_owner_valid && owner_match)begin
                native_tag<=i_owner_native_tag;
                phase<=i_bayer_phase;gains<=i_wb_gains;
                hdr<=RAW_SAMPLE_BITS==14 && i_hdr_enable;
                tone_shift<=RAW_SAMPLE_BITS==14 ? i_tone_shift : 4'd0;
            end
            if(state==RUN && i_pixel_cancel)poisoned<=1;
            // Before the first authenticated SOURCE, the adapter has no valid
            // result to read. Capture the offer's result on the handshake and
            // let the identity check publish it. After publication, hold it
            // even if the reader presents a stale or duplicate SOURCE.
            if(raw_source_fire && !raw_source_seen)begin
                raw_source_quiet<=i_raw_source_read_quiescent;
                raw_source_ok<=!source_failure;
                raw_source_error<=s_raw_source_error!=0 ? s_raw_source_error :
                    source_failure ? 8'd3 : 8'd0;
            end
            if(raw_source_fire)begin
                if(!source_match || raw_source_seen)begin
                    if(!(&stale_raw_source_count))stale_raw_source_count<=stale_raw_source_count+1'b1;
                end else begin
                    raw_source_seen<=1;
                    if(source_failure)poisoned<=1;
                end
            end
            if(raw_source_seen && !raw_source_sent && adapter_status_input_ready)raw_source_sent<=1;
        end
    end
    assign m_context=original_context;
    assign m_context_valid=original_context_valid;
    assign adapter_source_ready=m_context_ready;
    assign m_rgb=original_rgb;assign m_keep=original_keep;
    assign m_sof=original_sof;assign m_eol=original_eol;assign m_last=original_last;
    assign m_valid=original_valid;assign original_ready=m_ready;
    assign m_tag=original_tag;assign m_index=original_index;
    assign m_status_valid=original_status_valid;assign original_status_ready=m_status_ready;
    assign m_status_context=native_context;assign m_status_tag=original_status_tag;
    assign m_status_ok=original_status_ok;assign m_status_error=original_status_error;
    assign m_status_groups=original_status_groups;assign o_original_read_quiescent=original_quiet;
    assign o_locked_owner_valid=state==RUN;assign o_locked_frame=frame;
    assign o_locked_lease=lease;assign o_locked_job=job;assign o_locked_pair=pair;
    assign o_locked_native_tag=native_tag;assign o_locked_writer_tag=writer_tag;assign o_locked_member=member;
endmodule
