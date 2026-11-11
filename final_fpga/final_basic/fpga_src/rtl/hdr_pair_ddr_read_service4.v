`timescale 1ns/1ps
`default_nettype none
// Read-only RAW job phase. Caller already owns both exact JOB references.
module hdr_pair_ddr_read_service4 #(
    parameter integer MAX_WIDTH=1920, MAX_HEIGHT=1080,
    parameter [27:0] RAW_BASE=28'h2000000,
    parameter [31:0] SLOT_BYTES=32'h01000000,
    parameter [3:0] LONG_ID=4'd2, SHORT_ID=4'd3
)(
    input wire clk, rst_n,
    input wire s_start_valid, output wire s_start_ready,
    input wire [383:0] s_long_frame, s_short_frame,
    input wire [63:0] s_long_tag,s_short_tag,s_long_lease,s_short_lease,s_job_id,s_pair_id,
    input wire [2:0] s_ratio_log2,
    input wire [9:0] s_black_long,s_black_short,
    input wire [13:0] s_motion_base,
    input wire [3:0] s_motion_shift,
    input wire [63:0] s_max_delta_ns,
    output wire m_context_valid,input wire m_context_ready,
    output wire [383:0] o_long_frame,o_short_frame,
    output wire [63:0] o_long_tag,o_short_tag,o_job_id,o_pair_id,
    output reg [63:0] o_long_lease,o_short_lease,
    output wire [55:0] m_raw,
    output wire [31:0] m_index,
    output wire [3:0] m_keep,m_motion,
    output wire m_valid,m_sof,m_eol,m_eof,input wire m_ready,
    input wire i_cancel_valid,output wire o_cancel_ready,
    input wire [63:0] i_cancel_job_id,i_cancel_pair_id,
    output wire m_result_valid,input wire m_result_ready,
    output wire m_result_ok,output wire [7:0] o_first_error,
    output reg [7:0] o_service_error,
    output reg o_protocol_fault,
    output wire o_long_read_quiescent,o_short_read_quiescent,o_read_quiescent,o_quiescent,
    output wire o_long_source_valid,o_short_source_valid,
    output wire [31:0] o_long_pixels,o_short_pixels,o_output_pixels,
    output wire [3:0] m_axi_arid,output wire [27:0] m_axi_araddr,
    output wire [7:0] m_axi_arlen,output wire [2:0] m_axi_arsize,
    output wire [1:0] m_axi_arburst,output wire m_axi_arvalid,
    input wire m_axi_arready,input wire [3:0] m_axi_rid,
    input wire [127:0] m_axi_rdata,input wire [1:0] m_axi_rresp,
    input wire m_axi_rlast,m_axi_rvalid,output wire m_axi_rready
);
    localparam [1:0] IDLE=0, PREPARE=1, ACTIVE=2, FINISH=3;
    reg [1:0] state,next_state;
    reg prepared,started,failed,range_error;
    reg [15:0] rows_left,row_groups;
    reg [31:0] row_bytes,total_bytes,total_words,total_groups;
    reg [27:0] base_long,base_short;
    reg [31:0] issued_long,issued_short,returned_long,returned_short;
    reg owned_long,owned_short;
    reg [4:0] burst_long,burst_short,beat_long,beat_short;
    reg ar_held,ar_owner,round_robin;
    reg [27:0] ar_address;
    reg [4:0] ar_beats;
    reg [127:0] long_word,short_word;
    reg [15:0] long_keep,short_keep;
    reg long_last,short_last,long_word_valid,short_word_valid;
    reg closed_long,closed_short,abort_long,abort_short;
    reg source_long_valid,source_short_valid,source_long_sent,source_short_sent;
    reg source_long_ok,source_short_ok;
    reg [7:0] source_long_error,source_short_error;
    reg [31:0] source_long_pixels,source_short_pixels,long_index,short_index;
    reg [15:0] long_column,short_column;
    reg [9:0] long_occupancy,short_occupancy;
    reg internal_cancel_sent;
    wire fifo_rst_n;
    wire long_full,short_full,long_empty,short_empty,long_fifo_valid,short_fifo_valid;
    wire long_wr_done,long_rd_done,short_wr_done,short_rd_done;
    wire [39:0] long_fifo_data,short_fifo_data;
    wire long_pair_ready,short_pair_ready,adapter_cancel_ready;
    wire fifos_ready=fifo_rst_n && long_wr_done && long_rd_done && short_wr_done && short_rd_done;
    wire long_fifo_head=fifos_ready && long_fifo_valid && !long_empty;
    wire short_fifo_head=fifos_ready && short_fifo_valid && !short_empty;
    wire internal_cancel_valid=failed && state!=IDLE && !internal_cancel_sent && !m_result_valid;
    wire long_fifo_pop=long_fifo_head && long_pair_ready;
    wire short_fifo_pop=short_fifo_head && short_pair_ready;
    // Admission reserves 64 native groups for a whole 16-beat burst. At most
    // 52 new groups, four retained-word groups and five reservoir groups exist.
    wire long_capacity=long_occupancy<=10'd448;
    wire short_capacity=short_occupancy<=10'd448;
    wire adapter_start_ready,adapter_context_valid;
    wire adapter_context_ready=prepared && (range_error || m_context_ready);
    wire start_fire=s_start_valid && s_start_ready;
    wire context_fire=adapter_context_valid && adapter_context_ready;
    wire replay_start=context_fire && !range_error && !failed;
    wire [39:0] long_native,short_native;
    wire long_native_valid,short_native_valid,long_native_ready,short_native_ready;
    wire long_sof,long_eol,long_abort,long_done,short_sof,short_eol,short_abort,short_done;
    wire long_axis_ready,short_axis_ready;
    wire long_abort_start=failed && started && !closed_long && !abort_long && !long_done;
    wire short_abort_start=failed && started && !closed_short && !abort_short && !short_done;
    wire source_long_ready,source_short_ready;
    wire known_long=m_axi_rid==LONG_ID && owned_long;
    wire known_short=m_axi_rid==SHORT_ID && owned_short;
    wire response_last_ok=known_long ? m_axi_rlast==(beat_long==burst_long-1'b1) :
        m_axi_rlast==(beat_short==burst_short-1'b1);
    wire long_pop=long_word_valid && (closed_long || long_axis_ready);
    wire short_pop=short_word_valid && (closed_short || short_axis_ready);
    wire read_fire=m_axi_rvalid && m_axi_rready;
    wire ar_fire=m_axi_arvalid && m_axi_arready;
    wire long_native_fire=long_native_valid && long_native_ready;
    wire short_native_fire=short_native_valid && short_native_ready;
    wire [32:0] arena_end={5'd0,RAW_BASE}+({1'b0,SLOT_BYTES}<<3);
    wire [32:0] base_long_wide={5'd0,RAW_BASE}+
        (o_long_frame[4] ? ({1'b0,SLOT_BYTES}<<2) : 33'd0)+
        (o_long_frame[5] ? {1'b0,SLOT_BYTES} : 33'd0)+
        (o_long_frame[6] ? ({1'b0,SLOT_BYTES}<<1) : 33'd0);
    wire [32:0] base_short_wide={5'd0,RAW_BASE}+
        (o_short_frame[4] ? ({1'b0,SLOT_BYTES}<<2) : 33'd0)+
        (o_short_frame[5] ? {1'b0,SLOT_BYTES} : 33'd0)+
        (o_short_frame[6] ? ({1'b0,SLOT_BYTES}<<1) : 33'd0);
    wire [32:0] rounded_bytes=({1'b0,total_bytes}+15)&33'h1fffffff0;
    wire cancel_match=i_cancel_job_id==o_job_id && i_cancel_pair_id==o_pair_id;
    wire transaction_failed=failed || range_error || o_first_error!=0;

    assign s_start_ready=rst_n && fifos_ready && state==IDLE && adapter_start_ready && !o_protocol_fault;
    assign o_cancel_ready=adapter_cancel_ready && !internal_cancel_valid;
    assign long_native_ready=fifos_ready && !long_full;
    assign short_native_ready=fifos_ready && !short_full;
    assign m_context_valid=adapter_context_valid && prepared && !range_error;
    assign m_axi_arvalid=rst_n && ar_held;
    assign m_axi_arid=ar_owner ? SHORT_ID : LONG_ID;
    assign m_axi_araddr=ar_address;
    assign m_axi_arlen={3'd0,ar_beats}-1'b1;
    assign m_axi_arsize=3'd4;assign m_axi_arburst=2'd1;
    assign m_axi_rready=rst_n && !o_protocol_fault && response_last_ok &&
        ((known_long && (failed || !long_word_valid || long_pop)) ||
         (known_short && (failed || !short_word_valid || short_pop)));
    assign o_long_read_quiescent=closed_long && !owned_long &&
        !(ar_held && !ar_owner) && !long_word_valid && !long_native_valid &&
        long_occupancy==0 && !long_fifo_head && !o_protocol_fault;
    assign o_short_read_quiescent=closed_short && !owned_short &&
        !(ar_held && ar_owner) && !short_word_valid && !short_native_valid &&
        short_occupancy==0 && !short_fifo_head && !o_protocol_fault;
    assign o_read_quiescent=o_long_read_quiescent && o_short_read_quiescent;
    assign o_quiescent=rst_n && state==IDLE && o_read_quiescent;
    assign o_long_source_valid=source_long_valid;
    assign o_short_source_valid=source_short_valid;

    // One retained AR holder; accepted bursts have independent reader credits.
    reg select_reader,can_issue;
    reg [27:0] selected_address;
    reg [31:0] remaining_words;
    reg [8:0] boundary_words;
    reg [4:0] selected_beats;
    always @* begin
        select_reader=round_robin;can_issue=0;
        if(!owned_long && long_capacity && issued_long<total_words &&
            (owned_short || !short_capacity || issued_short==total_words || !round_robin))begin
            select_reader=0;can_issue=1;
        end else if(!owned_short && short_capacity && issued_short<total_words)begin select_reader=1;can_issue=1;end
        selected_address=select_reader ? base_short+(issued_short<<4) : base_long+(issued_long<<4);
        remaining_words=total_words-(select_reader ? issued_short : issued_long);
        boundary_words=(13'd4096-{1'b0,selected_address[11:0]})>>4;
        selected_beats=remaining_words>=16 ? 5'd16 : remaining_words[4:0];
        if(boundary_words<selected_beats)selected_beats=boundary_words[4:0];
    end
    always @* begin
        next_state=state;
        case(state)
            IDLE:if(start_fire)next_state=PREPARE;
            PREPARE:if(prepared)next_state=ACTIVE;
            ACTIVE:if(m_result_valid)next_state=FINISH;
            FINISH:if(m_result_valid && m_result_ready)next_state=IDLE;
            default:next_state=IDLE;
        endcase
        if(m_result_valid && m_result_ready)next_state=IDLE;
    end
    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)state<=IDLE;else state<=next_state;
    end
    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)begin
            prepared<=0;started<=0;failed<=0;range_error<=0;rows_left<=0;row_bytes<=0;row_groups<=0;
            total_bytes<=0;total_words<=0;total_groups<=0;base_long<=0;base_short<=0;
            o_long_lease<=0;o_short_lease<=0;o_service_error<=0;o_protocol_fault<=0;
        end else begin
            if(start_fire)begin
                prepared<=0;started<=0;failed<=0;range_error<=0;
                rows_left<=s_long_frame[236:221];
                row_groups<=s_long_frame[220:205]>>2;
                row_bytes<=(s_long_frame[220:205]>>2)+((s_long_frame[220:205]>>2)<<2);
                total_bytes<=0;total_words<=0;total_groups<=0;
                o_long_lease<=s_long_lease;o_short_lease<=s_short_lease;o_service_error<=0;
            end
            if(state==PREPARE && !prepared)begin
                if(rows_left!=0)begin total_bytes<=total_bytes+row_bytes;total_groups<=total_groups+row_groups;rows_left<=rows_left-1'b1;end
                else begin
                    prepared<=1;total_words<=(total_bytes+15)>>4;
                    base_long<=base_long_wide[27:0];base_short<=base_short_wide[27:0];
                    if(LONG_ID[3:2]!=0 || SHORT_ID[3:2]!=0 || LONG_ID==SHORT_ID ||
                        SLOT_BYTES<256 || SLOT_BYTES>32'h02000000 || SLOT_BYTES[7:0]!=0 || RAW_BASE[7:0]!=0 ||
                        arena_end>33'h10000000 || total_bytes==0 || rounded_bytes>SLOT_BYTES ||
                        base_long_wide<RAW_BASE || base_short_wide<RAW_BASE ||
                        base_long_wide+rounded_bytes>arena_end || base_short_wide+rounded_bytes>arena_end ||
                        o_long_frame[12:5]>=4 || o_short_frame[12:5]>=4 ||
                        o_long_lease==0 || o_short_lease==0)begin
                        range_error<=1;failed<=1;o_service_error<=8'he0;
                    end
                end
            end
            if(replay_start)started<=1;
            if((o_first_error!=0 && state!=IDLE && !m_result_valid) ||
                (i_cancel_valid && o_cancel_ready && cancel_match && !m_result_valid))begin
                failed<=1;if(o_service_error==0)o_service_error<=8'he2;
            end
            if(read_fire && m_axi_rresp!=0)begin failed<=1;if(o_service_error==0)o_service_error<=8'he1;end
            if(long_abort || short_abort)begin failed<=1;if(o_service_error==0)o_service_error<=8'he3;end
            if(m_axi_rvalid && !o_protocol_fault &&
                (!(known_long || known_short) || !response_last_ok))begin
                o_protocol_fault<=1;failed<=1;o_service_error<=8'he4;
            end
        end
    end
    // Cancellation never clears a presented AR or an accepted burst.
    always @(posedge clk or negedge rst_n)begin
        if(!rst_n || start_fire)begin
            ar_held<=0;ar_owner<=0;ar_address<=0;ar_beats<=0;round_robin<=0;
            owned_long<=0;owned_short<=0;burst_long<=0;burst_short<=0;beat_long<=0;beat_short<=0;
            issued_long<=0;issued_short<=0;returned_long<=0;returned_short<=0;
        end else begin
            if(state==ACTIVE && started && !ar_held && !transaction_failed && !o_protocol_fault &&
                !(i_cancel_valid && o_cancel_ready && cancel_match) &&
                !(read_fire && m_axi_rresp!=0) && !(long_abort || short_abort) && can_issue)begin
                ar_held<=1;ar_owner<=select_reader;ar_address<=selected_address;ar_beats<=selected_beats;
            end
            if(ar_fire)begin
                ar_held<=0;round_robin<=!ar_owner;
                if(ar_owner)begin owned_short<=1;burst_short<=ar_beats;beat_short<=0;issued_short<=issued_short+ar_beats;end
                else begin owned_long<=1;burst_long<=ar_beats;beat_long<=0;issued_long<=issued_long+ar_beats;end
            end
            if(read_fire)begin
                if(known_long)begin beat_long<=beat_long+1'b1;returned_long<=returned_long+1'b1;if(m_axi_rlast)owned_long<=0;end
                if(known_short)begin beat_short<=beat_short+1'b1;returned_short<=returned_short+1'b1;if(m_axi_rlast)owned_short<=0;end
            end
        end
    end
    // The decoder's explicit abort closes its byte branch; then a local discard
    // consumer accepts any retained word while outstanding DDR responses drain.
    always @(posedge clk or negedge rst_n)begin
        if(!rst_n || start_fire)begin
            long_word_valid<=0;short_word_valid<=0;long_keep<=0;short_keep<=0;long_last<=0;short_last<=0;
            closed_long<=1;closed_short<=1;abort_long<=0;abort_short<=0;long_index<=0;short_index<=0;
            long_column<=0;short_column<=0;internal_cancel_sent<=0;
            source_long_valid<=0;source_short_valid<=0;source_long_sent<=0;source_short_sent<=0;
            source_long_ok<=0;source_short_ok<=0;source_long_error<=0;source_short_error<=0;
            source_long_pixels<=0;source_short_pixels<=0;
        end else begin
            if(replay_start)begin closed_long<=0;closed_short<=0;end
            if(long_abort_start)abort_long<=1;if(short_abort_start)abort_short<=1;
            if(long_done || long_abort)closed_long<=1;if(short_done || short_abort)closed_short<=1;
            if((internal_cancel_valid && adapter_cancel_ready) ||
                (i_cancel_valid && o_cancel_ready && cancel_match))internal_cancel_sent<=1;
            if(long_fifo_pop)begin
                long_index<=long_index+1'b1;
                long_column<=long_column==row_groups-1'b1 ? 0 : long_column+1'b1;
            end
            if(short_fifo_pop)begin
                short_index<=short_index+1'b1;
                short_column<=short_column==row_groups-1'b1 ? 0 : short_column+1'b1;
            end
            if(long_pop)long_word_valid<=0;if(short_pop)short_word_valid<=0;
            if(read_fire && !transaction_failed && m_axi_rresp==0)begin
                if(known_long)begin
                    long_word<=m_axi_rdata;long_word_valid<=1;
                    long_last<=returned_long==total_words-1'b1;
                    long_keep<=returned_long==total_words-1'b1 && total_bytes[3:0]!=0 ?
                        (16'hffff>>(16-total_bytes[3:0])) : 16'hffff;
                end else begin
                    short_word<=m_axi_rdata;short_word_valid<=1;
                    short_last<=returned_short==total_words-1'b1;
                    short_keep<=returned_short==total_words-1'b1 && total_bytes[3:0]!=0 ?
                        (16'hffff>>(16-total_bytes[3:0])) : 16'hffff;
                end
            end
            if(!source_long_sent && !source_long_valid && !o_protocol_fault &&
                o_long_read_quiescent && (transaction_failed || (started && long_index==total_groups)))begin
                source_long_valid<=1;source_long_ok<=!transaction_failed;
                source_long_error<=transaction_failed ? (o_service_error==0 ? 8'he2 : o_service_error) : 0;
                source_long_pixels<=long_index<<2;
            end
            if(!source_short_sent && !source_short_valid && !o_protocol_fault &&
                o_short_read_quiescent && (transaction_failed || (started && short_index==total_groups)))begin
                source_short_valid<=1;source_short_ok<=!transaction_failed;
                source_short_error<=transaction_failed ? (o_service_error==0 ? 8'he2 : o_service_error) : 0;
                source_short_pixels<=short_index<<2;
            end
            if(source_long_valid && source_long_ready)begin source_long_valid<=0;source_long_sent<=1;end
            if(source_short_valid && source_short_ready)begin source_short_valid<=0;source_short_sent<=1;end
        end
    end
    // Storage and clock-domain/reset implementation belong to the formally
    // generated GUI-managed IP. These counters describe real local handshakes;
    // they neither replace FIFO pointers nor use EMPTY as a drain certificate.
    reset_release_sync u_fifo_reset(.i_clk(clk),.i_async_rst_n(rst_n),.o_rst_n(fifo_rst_n));
    control_fifo_40x512 u_long_native_fifo(
        .di(long_native),.clkw(clk),.wrst(!fifo_rst_n),.we(long_native_fire),
        .clkr(clk),.rrst(!fifo_rst_n),.re(long_fifo_pop),.dout(long_fifo_data),
        .empty_flag(long_empty),.aempty(),.full_flag(long_full),.afull(),
        .valid(long_fifo_valid),.overflow(),.underflow(),.wr_success(),.rdusedw(),.wrusedw(),
        .wr_rst_done(long_wr_done),.rd_rst_done(long_rd_done));
    control_fifo_40x512 u_short_native_fifo(
        .di(short_native),.clkw(clk),.wrst(!fifo_rst_n),.we(short_native_fire),
        .clkr(clk),.rrst(!fifo_rst_n),.re(short_fifo_pop),.dout(short_fifo_data),
        .empty_flag(short_empty),.aempty(),.full_flag(short_full),.afull(),
        .valid(short_fifo_valid),.overflow(),.underflow(),.wr_success(),.rdusedw(),.wrusedw(),
        .wr_rst_done(short_wr_done),.rd_rst_done(short_rd_done));
    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)begin long_occupancy<=0;short_occupancy<=0;end
        else begin
            case({long_native_fire,long_fifo_pop})
                2'b10:long_occupancy<=long_occupancy+1'b1;
                2'b01:long_occupancy<=long_occupancy-1'b1;
                default:long_occupancy<=long_occupancy;
            endcase
            case({short_native_fire,short_fifo_pop})
                2'b10:short_occupancy<=short_occupancy+1'b1;
                2'b01:short_occupancy<=short_occupancy-1'b1;
                default:short_occupancy<=short_occupancy;
            endcase
        end
    end
    raw10_frame_replay u_long_replay(
        .i_clk(clk),.i_rst_n(rst_n),.i_start(replay_start || long_abort_start),
        .i_width(o_long_frame[220:205]),.i_height(o_long_frame[236:221]),
        .i_axis_tdata(long_word),.i_axis_tkeep(long_keep),.i_axis_tvalid(long_word_valid && !closed_long),
        .o_axis_tready(long_axis_ready),.i_axis_tlast(long_last),.o_data(long_native),.o_valid(long_native_valid),
        .i_ready(long_native_ready),.o_sof(long_sof),.o_eol(long_eol),.o_abort(long_abort),.o_done(long_done));
    raw10_frame_replay u_short_replay(
        .i_clk(clk),.i_rst_n(rst_n),.i_start(replay_start || short_abort_start),
        .i_width(o_short_frame[220:205]),.i_height(o_short_frame[236:221]),
        .i_axis_tdata(short_word),.i_axis_tkeep(short_keep),.i_axis_tvalid(short_word_valid && !closed_short),
        .o_axis_tready(short_axis_ready),.i_axis_tlast(short_last),.o_data(short_native),.o_valid(short_native_valid),
        .i_ready(short_native_ready),.o_sof(short_sof),.o_eol(short_eol),.o_abort(short_abort),.o_done(short_done));
    hdr_raw14_pair_adapter4 #(.MAX_WIDTH(MAX_WIDTH),.MAX_HEIGHT(MAX_HEIGHT)) u_pair(
        .clk(clk),.rst_n(rst_n),.s_start_valid(s_start_valid && fifos_ready && state==IDLE && !o_protocol_fault),.s_start_ready(adapter_start_ready),
        .s_long_frame(s_long_frame),.s_short_frame(s_short_frame),.s_long_tag(s_long_tag),.s_short_tag(s_short_tag),
        .s_job_id(s_job_id),.s_pair_id(s_pair_id),.s_ratio_log2(s_ratio_log2),.s_black_long(s_black_long),.s_black_short(s_black_short),
        .s_motion_base(s_motion_base),.s_motion_shift(s_motion_shift),.s_max_delta_ns(s_max_delta_ns),
        .m_context_valid(adapter_context_valid),.m_context_ready(adapter_context_ready),
        .o_long_frame(o_long_frame),.o_short_frame(o_short_frame),.o_long_tag(o_long_tag),.o_short_tag(o_short_tag),
        .o_job_id(o_job_id),.o_pair_id(o_pair_id),.o_radiance_format(),.o_radiance_bits(),.o_black_corrected(),.o_ratio_log2(),
        .s_long_data(long_fifo_data),.s_short_data(short_fifo_data),.s_long_index(long_index),.s_short_index(short_index),
        .s_long_data_tag(o_long_tag),.s_short_data_tag(o_short_tag),.s_long_keep(4'hf),.s_short_keep(4'hf),
        .s_long_sof(long_index==0),.s_long_eol(long_column==row_groups-1'b1),.s_long_eof(long_index==total_groups-1'b1),
        .s_short_sof(short_index==0),.s_short_eol(short_column==row_groups-1'b1),.s_short_eof(short_index==total_groups-1'b1),
        .s_long_valid(long_fifo_head),.s_short_valid(short_fifo_head),.s_long_ready(long_pair_ready),.s_short_ready(short_pair_ready),
        .m_raw(m_raw),.m_index(m_index),.m_keep(m_keep),.m_motion(m_motion),
        .m_sof(m_sof),.m_eol(m_eol),.m_eof(m_eof),.m_valid(m_valid),.m_ready(m_ready),
        .s_long_source_valid(source_long_valid),.s_short_source_valid(source_short_valid),
        .s_long_source_ready(source_long_ready),.s_short_source_ready(source_short_ready),
        .s_long_source_frame(o_long_frame),.s_short_source_frame(o_short_frame),
        .s_long_source_tag(o_long_tag),.s_short_source_tag(o_short_tag),
        .s_long_source_job_id(o_job_id),.s_short_source_job_id(o_job_id),
        .s_long_source_pair_id(o_pair_id),.s_short_source_pair_id(o_pair_id),
        .s_long_source_pixels(source_long_pixels),.s_short_source_pixels(source_short_pixels),
        .s_long_source_ok(source_long_ok),.s_short_source_ok(source_short_ok),
        .s_long_source_error(source_long_error),.s_short_source_error(source_short_error),
        .i_long_read_quiescent(o_long_read_quiescent),.i_short_read_quiescent(o_short_read_quiescent),
        .i_cancel_valid(internal_cancel_valid || i_cancel_valid),.o_cancel_ready(adapter_cancel_ready),
        .i_cancel_job_id(internal_cancel_valid ? o_job_id : i_cancel_job_id),
        .i_cancel_pair_id(internal_cancel_valid ? o_pair_id : i_cancel_pair_id),
        .m_result_valid(m_result_valid),.m_result_ready(m_result_ready),.m_result_ok(m_result_ok),.o_first_error(o_first_error),
        .o_long_source_error(),.o_short_source_error(),.o_long_pixels(o_long_pixels),.o_short_pixels(o_short_pixels),
        .o_output_pixels(o_output_pixels),.o_stale_source_count(),.o_stale_cancel_count(),.o_busy(),.o_quiescent());
endmodule
`default_nettype wire
