`timescale 1ns/1ps
// SDR ownership and read service. RAW export borrows the same slot and reader.
module stereo_raw_store #(
    parameter integer WIDTH=1920,HEIGHT=1080,EXTERNAL_DECODER=0,
    parameter integer RAW_EXPORT_ENABLE=0,VERIFY_DECODE_ACTIVE=0
)(
    input wire clk,rst_n,i_enable,i_stop,
    input wire [31:0] i_session,i_epoch,
    input wire [383:0] s_frame,input wire s_begin_valid,i_begin_camera,
    output wire s_begin_ready,o_begin_accepted,output wire [1:0] o_capture_slot,
    input wire [1:0] i_finish_valid,i_finish_ok,output wire [1:0] o_finish_ready,
    output wire o_job_valid,input wire i_job_ready,output wire [383:0] o_job_frame,
    output wire [63:0] o_job_lease,o_job_id,output wire [1:0] o_job_bayer,output wire o_job_time_valid,
    input wire i_retire_valid,input wire [63:0] i_retire_job_id,
    input wire i_release_quiet,output wire o_retire_ready,o_retire_done,o_retire_error,
    input wire i_req_valid,output wire o_req_ready,input wire [2:0] i_req_op,
    input wire i_req_camera,input wire [1:0] i_req_slot,
    input wire [31:0] i_req_generation,i_req_session,
    input wire [63:0] i_req_lease,i_req_job_id,
    output reg o_rsp_valid,input wire i_rsp_ready,output reg [3:0] o_rsp_code,
    output reg o_rsp_camera,output reg [1:0] o_rsp_slot,
    output reg [31:0] o_rsp_generation,o_rsp_session,o_rsp_sequence,o_rsp_epoch,
    input wire i_processing_done,i_processing_error,input wire [63:0] i_processing_job_id,
    output reg o_native_done,o_native_error,output wire [63:0] o_native_job_id,
    output wire [146:0] m_fifo_data,output wire m_fifo_valid,input wire m_fifo_ready,
    output wire o_read_quiet,o_empty,o_fault,
    output wire o_decode_start_valid,input wire i_decode_start_ready,
    output wire o_decode_release,o_decode_cancel,o_decode_run,
    output wire [127:0] o_decode_data,output wire [15:0] o_decode_keep,
    output wire o_decode_valid,o_decode_last,input wire i_decode_ready,
    input wire [39:0] i_decode_raw,input wire i_decode_raw_valid,
    output wire o_decode_raw_ready,input wire i_decode_sof,i_decode_eol,
    input wire i_decode_done,i_decode_aborted,i_decode_quiet,i_decode_active,
    output wire [3:0] m_axi_arid,output wire [27:0] m_axi_araddr,
    output wire [7:0] m_axi_arlen,output wire [2:0] m_axi_arsize,
    output wire [1:0] m_axi_arburst,output wire m_axi_arvalid,input wire m_axi_arready,
    input wire [3:0] m_axi_rid,input wire [127:0] m_axi_rdata,
    input wire [1:0] m_axi_rresp,input wire m_axi_rlast,m_axi_rvalid,output wire m_axi_rready,
    // Cold, exclusive RAW mode. The job descriptor is borrowed through SAFE.
    input wire i_raw_export,i_raw_cancel,
    output wire o_raw_record_valid,input wire i_raw_record_ready,
    output wire [31:0] o_raw_record_length,output wire [127:0] o_raw_record_identity,
    output wire [127:0] o_raw_data,output wire [15:0] o_raw_keep,
    output wire o_raw_valid,o_raw_last,input wire i_raw_ready,
    output wire o_raw_done_valid,o_raw_done_ok,o_raw_drained,
    input wire i_raw_retire_valid,output wire o_raw_retire_ready,
    input wire [127:0] i_raw_retire_identity
);
    wire owner_retire_ready,owner_retire_done,owner_retire_error;
    wire owner_empty,owner_job_valid,owner_job_owned,owner_fault;
    wire reader_ready,reader_done,reader_ok,reader_quiet,reader_fault;
    wire reader_fifo_valid,reader_decode_start,reader_decode_release,reader_decode_cancel;
    wire reader_decode_run,reader_decode_valid,reader_decode_raw_ready;
    reg read_owned,start_pending,read_complete,processing_seen,processing_bad,native_sent;
    reg [63:0] read_job;
    reg [27:0] read_base;
    reg raw_offer_held,raw_held,raw_cancel_pending,raw_payload_done,raw_retire_pending;
    wire raw_export=RAW_EXPORT_ENABLE!=0&&i_raw_export;
    // The AXI slave owns the held R beat. Delay cancellation while that beat
    // is presented to the RAW formatter, then drain any remaining AXI debt.
    wire raw_cancel=(i_stop||i_raw_cancel||raw_cancel_pending)&&!raw_held;
    wire raw_payload_fire=o_raw_valid&&i_raw_ready;
    wire raw_take=o_raw_record_valid&&i_raw_record_ready;
    wire raw_safe=i_raw_retire_valid&&o_raw_retire_ready;
    // STOP can coincide with the directory reaching OFFER. A descriptor
    // never presented to the record path can be released locally without AR.
    wire raw_drop=raw_export&&owner_job_valid&&i_stop&&!raw_offer_held;
    wire request_fire=i_req_valid&&o_req_ready;
    wire request_matches=i_req_camera==o_job_frame[4]&&i_req_slot==o_job_frame[6:5]&&
        i_req_generation==o_job_frame[44:13]&&i_req_session==o_job_frame[76:45]&&
        i_req_lease==o_job_lease&&i_req_job_id==o_job_id;
    // An accepted processing context still needs its matching terminal on STOP.
    // The reader starts cancelled and emits a zero-group failure FENCE, without AR.
    wire replay_ok=owner_job_owned&&request_matches&&!read_owned&&reader_ready;
    wire retire_ok=owner_job_owned&&request_matches&&read_owned&&read_complete&&processing_seen&&reader_quiet;
    wire replay_take=request_fire&&i_req_op==3'd4&&replay_ok;
    assign o_req_ready=!raw_export&&i_enable&&!o_rsp_valid&&!owner_fault&&!reader_fault;
    assign o_job_valid=owner_job_valid&&!raw_export;
    assign o_retire_ready=owner_retire_ready;
    assign o_retire_done=owner_retire_done;
    assign o_retire_error=owner_retire_error;
    assign o_native_job_id=read_job;
    // Bus/payload production quiet is distinct from the retained private read lease.
    // Ticket release needs this proof before its processing result can return.
    assign o_read_quiet=!start_pending&&reader_quiet&&(!read_owned||read_complete)&&!o_rsp_valid;
    assign o_empty=owner_empty&&o_read_quiet&&!read_owned;
    assign o_fault=owner_fault||reader_fault;

    // The product CDC sees the whole ARAW record. The formatter prepends its
    // fixed 64-byte header to the byte-exact packed reader output below.
    assign o_raw_record_valid=raw_export&&owner_job_valid&&(raw_offer_held||(!i_stop&&reader_ready));
    assign o_raw_record_length=32'd64+WIDTH*HEIGHT/4*5;
    assign o_raw_record_identity={16'h5241,o_job_frame[76:45],o_job_frame[44:13],
        13'd0,o_job_frame[4],o_job_frame[6:5],o_job_frame[108:77]};
    assign o_raw_data=o_decode_data;
    assign o_raw_keep=o_decode_keep;
    assign o_raw_last=o_decode_last;
    assign o_raw_valid=raw_export&&reader_decode_valid;
    assign o_raw_done_valid=raw_export&&read_owned&&read_complete;
    assign o_raw_done_ok=o_raw_done_valid&&!processing_bad;
    // A malformed AXI response does not prove drain or permit slot reuse.
    assign o_raw_drained=o_raw_done_valid&&reader_quiet&&!raw_held&&!o_fault;
    assign o_raw_retire_ready=o_raw_drained&&i_raw_retire_identity==o_raw_record_identity;

    assign m_fifo_valid=reader_fifo_valid&&!raw_export;
    assign o_decode_start_valid=reader_decode_start&&!raw_export;
    assign o_decode_release=reader_decode_release&&!raw_export;
    assign o_decode_cancel=reader_decode_cancel&&!raw_export;
    assign o_decode_run=reader_decode_run&&!raw_export;
    assign o_decode_valid=reader_decode_valid&&!raw_export;
    assign o_decode_raw_ready=reader_decode_raw_ready&&!raw_export;
    stereo_raw_owner #(.WIDTH(WIDTH),.HEIGHT(HEIGHT)) u_owner(
        .clk(clk),.rst_n(rst_n),.i_enable(i_enable),.i_stop(i_stop),.i_session(i_session),.i_epoch(i_epoch),
        .s_frame(s_frame),.s_begin_valid(s_begin_valid),.i_begin_camera(i_begin_camera),
        .s_begin_ready(s_begin_ready),.o_begin_accepted(o_begin_accepted),.o_capture_slot(o_capture_slot),
        .i_finish_valid(i_finish_valid),.i_finish_ok(i_finish_ok),.o_finish_ready(o_finish_ready),
        .o_job_valid(owner_job_valid),.i_job_ready(raw_export?(raw_take||raw_drop):i_job_ready),.o_job_frame(o_job_frame),
        .o_job_lease(o_job_lease),.o_job_id(o_job_id),.o_job_bayer(o_job_bayer),.o_job_time_valid(o_job_time_valid),
        .i_retire_valid(raw_export?raw_retire_pending:i_retire_valid),
        .i_retire_job_id(raw_export?read_job:i_retire_job_id),
        .i_release_quiet(i_release_quiet&&o_read_quiet&&!read_owned),.o_retire_ready(owner_retire_ready),
        .o_retire_done(owner_retire_done),.o_retire_error(owner_retire_error),
        .o_empty(owner_empty),.o_job_owned(owner_job_owned),.o_fault(owner_fault),.o_dropped());
    stereo_raw_reader #(.WIDTH(WIDTH),.HEIGHT(HEIGHT),.EXTERNAL_DECODER(EXTERNAL_DECODER),
        .VERIFY_DECODE_ACTIVE(VERIFY_DECODE_ACTIVE)) u_reader(
        .clk(clk),.rst_n(rst_n),.i_start_valid(start_pending),.o_start_ready(reader_ready),
        .i_base(read_base),.i_job_id(read_job),.i_cancel(raw_export?raw_cancel:i_stop),
        // The RAW consumer needs the real reader completion, not a PIX FENCE.
        .m_data(m_fifo_data),.m_valid(reader_fifo_valid),.m_ready(raw_export||m_fifo_ready),
        .o_done_valid(reader_done),.o_done_ok(reader_ok),.i_done_ready(1'b1),
        .o_bus_quiet(reader_quiet),.o_fault(reader_fault),
        .o_decode_start_valid(reader_decode_start),.i_decode_start_ready(raw_export||i_decode_start_ready),
        .o_decode_release(reader_decode_release),.o_decode_cancel(reader_decode_cancel),.o_decode_run(reader_decode_run),
        .o_decode_data(o_decode_data),.o_decode_keep(o_decode_keep),
        .o_decode_valid(reader_decode_valid),.o_decode_last(o_decode_last),.i_decode_ready(raw_export?i_raw_ready:i_decode_ready),
        .i_decode_raw(i_decode_raw),.i_decode_raw_valid(!raw_export&&i_decode_raw_valid),.o_decode_raw_ready(reader_decode_raw_ready),
        .i_decode_sof(i_decode_sof),.i_decode_eol(i_decode_eol),
        .i_decode_done(raw_export?raw_payload_done:i_decode_done),
        .i_decode_aborted(!raw_export&&i_decode_aborted),.i_decode_quiet(raw_export?!raw_held:i_decode_quiet),
        .i_decode_active(raw_export?(read_owned&&!read_complete):i_decode_active),
        .m_axi_arid(m_axi_arid),.m_axi_araddr(m_axi_araddr),.m_axi_arlen(m_axi_arlen),
        .m_axi_arsize(m_axi_arsize),.m_axi_arburst(m_axi_arburst),.m_axi_arvalid(m_axi_arvalid),
        .m_axi_arready(m_axi_arready),.m_axi_rid(m_axi_rid),.m_axi_rdata(m_axi_rdata),
        .m_axi_rresp(m_axi_rresp),.m_axi_rlast(m_axi_rlast),.m_axi_rvalid(m_axi_rvalid),.m_axi_rready(m_axi_rready));
    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)begin
            read_owned<=0;start_pending<=0;read_complete<=0;processing_seen<=0;processing_bad<=0;
            native_sent<=0;read_job<=0;read_base<=0;o_native_done<=0;o_native_error<=0;
            raw_offer_held<=0;raw_held<=0;raw_cancel_pending<=0;raw_payload_done<=0;raw_retire_pending<=0;
            o_rsp_valid<=0;o_rsp_code<=0;o_rsp_camera<=0;o_rsp_slot<=0;o_rsp_generation<=0;
            o_rsp_session<=0;o_rsp_sequence<=0;o_rsp_epoch<=0;
        end else begin
            o_native_done<=0;o_native_error<=0;
            raw_offer_held<=o_raw_record_valid&&!i_raw_record_ready;
            raw_held<=o_raw_valid&&!i_raw_ready;
            raw_payload_done<=raw_payload_fire&&o_raw_last;
            if(raw_take)raw_cancel_pending<=i_stop||i_raw_cancel;
            else if(raw_export&&read_owned&&(i_stop||i_raw_cancel))raw_cancel_pending<=1;
            if(raw_safe||raw_drop)begin read_owned<=0;raw_retire_pending<=1;end
            else if(raw_retire_pending&&owner_retire_ready)raw_retire_pending<=0;
            if(raw_drop)read_job<=o_job_id;
            if(o_rsp_valid&&i_rsp_ready)o_rsp_valid<=0;
            if(start_pending&&reader_ready)start_pending<=0;
            if(reader_done)begin read_complete<=1;if(!reader_ok)processing_bad<=1;end
            if(!raw_export&&i_processing_done&&read_owned&&i_processing_job_id==read_job)begin
                processing_seen<=1;if(i_processing_error)processing_bad<=1;
            end
            // This event is later than actual PIX FENCE consumption and final JPEG B.
            // Enqueueing a FENCE alone cannot certify native completion or release RAW.
            if(read_owned&&read_complete&&processing_seen&&!native_sent)begin
                o_native_done<=1;o_native_error<=processing_bad;native_sent<=1;
            end
            if(raw_take||replay_take)begin
                read_owned<=1;start_pending<=1;read_complete<=0;
                processing_seen<=0;processing_bad<=0;native_sent<=0;read_job<=o_job_id;
                read_base<=28'h2000000+{1'b0,o_job_frame[4],26'd0}+{2'd0,o_job_frame[6:5],24'd0};
            end
            if(request_fire)begin
                o_rsp_valid<=1;o_rsp_camera<=i_req_camera;o_rsp_slot<=i_req_slot;
                o_rsp_generation<=i_req_generation;o_rsp_session<=i_req_session;
                o_rsp_sequence<=o_job_frame[108:77];o_rsp_epoch<=o_job_frame[140:109];
                o_rsp_code<=4'd6;
                if(replay_take)o_rsp_code<=0;
                else if(i_req_op==5&&retire_ok)begin o_rsp_code<=0;read_owned<=0;end
            end
        end
    end
    generate if(RAW_EXPORT_ENABLE!=0&&EXTERNAL_DECODER==0)begin:g_bad_raw_export
        RAW_EXPORT_REQUIRES_EXTERNAL_PACKED_READER invalid_profile();
    end endgenerate
endmodule
