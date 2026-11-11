`timescale 1ns/1ps
`default_nettype none

// Pair-owned RAW10 readers feed the existing elastic RAW14 merge without truncation.
module hdr_raw14_pair_adapter4 #(
    parameter integer MAX_WIDTH=1920, MAX_HEIGHT=1080, SLOTS_PER_CAMERA=4
) (
    input wire clk, rst_n,
    input wire s_start_valid, output wire s_start_ready,
    input wire [383:0] s_long_frame, s_short_frame,
    input wire [63:0] s_long_tag, s_short_tag, s_job_id, s_pair_id,
    input wire [2:0] s_ratio_log2,
    input wire [9:0] s_black_long, s_black_short,
    input wire [13:0] s_motion_base,
    input wire [3:0] s_motion_shift,
    input wire [63:0] s_max_delta_ns,
    output wire m_context_valid, input wire m_context_ready,
    output reg [383:0] o_long_frame, o_short_frame,
    output reg [63:0] o_long_tag, o_short_tag, o_job_id, o_pair_id,
    output wire [1:0] o_radiance_format,
    output wire [4:0] o_radiance_bits,
    output wire o_black_corrected,
    output reg [2:0] o_ratio_log2,
    input wire [39:0] s_long_data, s_short_data,
    input wire [31:0] s_long_index, s_short_index,
    input wire [63:0] s_long_data_tag, s_short_data_tag,
    input wire [3:0] s_long_keep, s_short_keep,
    input wire s_long_sof, s_long_eol, s_long_eof,
    input wire s_short_sof, s_short_eol, s_short_eof,
    input wire s_long_valid, s_short_valid,
    output wire s_long_ready, s_short_ready,
    output wire [55:0] m_raw,
    output wire [31:0] m_index,
    output wire [3:0] m_keep, m_motion,
    output wire m_sof, m_eol, m_eof, m_valid,
    input wire m_ready,
    input wire s_long_source_valid, s_short_source_valid,
    output wire s_long_source_ready, s_short_source_ready,
    input wire [383:0] s_long_source_frame, s_short_source_frame,
    input wire [63:0] s_long_source_tag, s_short_source_tag,
    input wire [63:0] s_long_source_job_id, s_short_source_job_id,
    input wire [63:0] s_long_source_pair_id, s_short_source_pair_id,
    input wire [31:0] s_long_source_pixels, s_short_source_pixels,
    input wire s_long_source_ok, s_short_source_ok,
    input wire [7:0] s_long_source_error, s_short_source_error,
    input wire i_long_read_quiescent, i_short_read_quiescent,
    input wire i_cancel_valid, output wire o_cancel_ready,
    input wire [63:0] i_cancel_job_id, i_cancel_pair_id,
    output wire m_result_valid, input wire m_result_ready,
    output wire m_result_ok, output reg [7:0] o_first_error,
    output reg [7:0] o_long_source_error, o_short_source_error,
    output reg [31:0] o_long_pixels, o_short_pixels, o_output_pixels,
    output reg [31:0] o_stale_source_count, o_stale_cancel_count,
    output wire o_busy, o_quiescent
);
    localparam [3:0] IDLE=0, COMMON=1, RATIO=2, CONTEXT=3,
        RUN=4, DRAIN=5, FINAL=6, RESULT=7, SIZE=8;
    reg [3:0] state, next_state;
    reg [9:0] black_long, black_short;
    reg [13:0] motion_base;
    reg [3:0] motion_shift;
    reg [63:0] max_delta_ns, timestamp_delta;
    reg [31:0] expected_pixels, expected_groups, next_index;
    reg [15:0] row_groups, column, rows_left;
    reg long_head_valid, short_head_valid;
    reg [39:0] long_head, short_head;
    reg [31:0] long_index, short_index;
    reg [63:0] long_tag, short_tag;
    reg [3:0] long_keep, short_keep;
    reg long_sof, long_eol, long_eof, short_sof, short_eol, short_eof;
    reg long_seen, short_seen, long_ok, short_ok;
    reg [31:0] long_terminal_pixels, short_terminal_pixels;
    reg [3:0] inflight;
    reg [191:0] index_pipe;
    reg [5:0] eof_pipe;
    wire merge_ready;
    wire active=state!=IDLE;
    wire result_frozen=state==RESULT;
    wire long_fire=s_long_valid && s_long_ready;
    wire short_fire=s_short_valid && s_short_ready;
    wire long_source_fire=s_long_source_valid && s_long_source_ready;
    wire short_source_fire=s_short_source_valid && s_short_source_ready;
    wire long_source_match=s_long_source_frame==o_long_frame &&
        s_long_source_tag==o_long_tag && s_long_source_job_id==o_job_id &&
        s_long_source_pair_id==o_pair_id;
    wire short_source_match=s_short_source_frame==o_short_frame &&
        s_short_source_tag==o_short_tag && s_short_source_job_id==o_job_id &&
        s_short_source_pair_id==o_pair_id;
    wire cancel_fire=i_cancel_valid && o_cancel_ready;
    wire cancel_match=i_cancel_job_id==o_job_id && i_cancel_pair_id==o_pair_id;
    wire expected_sof=next_index==0;
    wire expected_eol=column==row_groups-1'b1;
    wire expected_eof=next_index==expected_groups-1'b1;
    reg [7:0] detected_error;
    wire paired=state==RUN && long_head_valid && short_head_valid;
    wire merge_valid=paired && detected_error==0 && o_first_error==0;
    wire pair_fire=merge_valid && merge_ready;
    wire output_fire=m_valid && m_ready;
    wire streams_quiet=long_seen && short_seen && i_long_read_quiescent &&
        i_short_read_quiescent && !long_head_valid && !short_head_valid &&
        inflight==0 && !m_valid;
    wire [63:0] scaled_short_exposure={32'd0,o_short_frame[302:271]} << o_ratio_log2;

    // No payload is accepted before context ownership, except real failure drain.
    assign s_start_ready=rst_n && state==IDLE;
    assign m_context_valid=rst_n && state==CONTEXT;
    assign s_long_ready=rst_n && !long_seen &&
        ((state==RUN && (!long_head_valid || pair_fire)) || state==DRAIN);
    assign s_short_ready=rst_n && !short_seen &&
        ((state==RUN && (!short_head_valid || pair_fire)) || state==DRAIN);
    assign s_long_source_ready=rst_n && active;
    assign s_short_source_ready=rst_n && active;
    assign o_cancel_ready=rst_n && active;
    assign m_result_valid=rst_n && result_frozen;
    assign m_result_ok=o_first_error==0;
    assign o_busy=active;
    assign o_quiescent=rst_n && state==IDLE;
    assign o_radiance_format=2'd2;
    assign o_radiance_bits=5'd14;
    assign o_black_corrected=1'b1;
    assign m_index=index_pipe[191:160];
    assign m_eof=eof_pipe[5];
    assign m_keep=4'hf;

    function [2:0] pixels_in_keep;
        input [3:0] keep;
        begin
            case(keep)
                0:pixels_in_keep=0;
                1,2,4,8:pixels_in_keep=1;
                3,5,6,9,10,12:pixels_in_keep=2;
                7,11,13,14:pixels_in_keep=3;
                default:pixels_in_keep=4;
            endcase
        end
    endfunction

    // First-error checks are frame-rate metadata checks or registered group checks.
    always @* begin
        detected_error=0;
        if(state==COMMON) begin
            if(o_long_frame[383:367]!=0 || o_short_frame[383:367]!=0 ||
                !o_long_frame[0] || !o_short_frame[0] ||
                o_long_frame[2:1]!=1 || o_short_frame[2:1]!=2 ||
                o_long_frame[3]!=o_short_frame[3] || o_long_frame[4]!=o_short_frame[4] ||
                o_long_frame[12:5]>=SLOTS_PER_CAMERA || o_short_frame[12:5]>=SLOTS_PER_CAMERA ||
                o_long_frame[12:5]==o_short_frame[12:5] ||
                o_long_frame[44:13]==0 || o_short_frame[44:13]==0 ||
                o_long_frame[76:45]==0 || o_long_frame[76:45]!=o_short_frame[76:45] ||
                o_long_frame[140:109]!=o_short_frame[140:109] ||
                o_long_frame[238:237]!=1 || o_short_frame[238:237]!=1 ||
                o_long_frame[270:239]!=o_short_frame[270:239] ||
                o_long_frame[334:303]!=o_short_frame[334:303] ||
                o_long_frame[366:335]==0 || o_long_frame[366:335]!=o_short_frame[366:335] ||
                o_long_frame[204:141]>o_short_frame[204:141] ||
                o_long_tag==0 || o_short_tag==0 || o_long_tag==o_short_tag ||
                o_job_id==0 || o_pair_id==0)
                detected_error=1;
            else if(o_long_frame[220:205]!=o_short_frame[220:205] ||
                o_long_frame[236:221]!=o_short_frame[236:221] ||
                o_long_frame[220:205]<8 || o_long_frame[220:205]>MAX_WIDTH || o_long_frame[220:205]>8191 ||
                o_long_frame[206:205]!=0 || o_long_frame[236:221]<3 ||
                o_long_frame[236:221]>MAX_HEIGHT || o_long_frame[236:221]>8191)
                detected_error=3;
        end
        if(state==RATIO && (o_ratio_log2>4 || o_ratio_log2==0 ||
            o_short_frame[302:271]==0 || o_long_frame[302:271]==0 ||
            o_long_frame[334:303]==0 || {32'd0,o_long_frame[302:271]}!=scaled_short_exposure ||
            timestamp_delta>max_delta_ns))
            detected_error=2;
        if(state==RUN && paired) begin
            if(long_tag!=o_long_tag || short_tag!=o_short_tag) detected_error=7;
            else if(long_index!=next_index || short_index!=next_index) detected_error=4;
            else if(long_keep!=4'hf || short_keep!=4'hf) detected_error=5;
            else if(long_sof!=expected_sof || short_sof!=expected_sof ||
                long_eol!=expected_eol || short_eol!=expected_eol ||
                long_eof!=expected_eof || short_eof!=expected_eof) detected_error=6;
        end
        if(state==RUN && ((long_seen && o_long_pixels!=expected_pixels) ||
            (short_seen && o_short_pixels!=expected_pixels))) detected_error=9;
        if(!result_frozen) begin
            if(long_source_fire && long_source_match && !long_seen && (!s_long_source_ok || s_long_source_error!=0))
                detected_error=8;
            if(short_source_fire && short_source_match && !short_seen && (!s_short_source_ok || s_short_source_error!=0))
                detected_error=8;
            if(cancel_fire && cancel_match) detected_error=10;
            if((long_fire && o_long_pixels>32'hffffffff-pixels_in_keep(s_long_keep)) ||
                (short_fire && o_short_pixels>32'hffffffff-pixels_in_keep(s_short_keep)))detected_error=11;
        end
        if(state==FINAL && o_first_error==0 &&
            (!long_ok || !short_ok || long_terminal_pixels!=expected_pixels ||
            short_terminal_pixels!=expected_pixels || o_long_pixels!=expected_pixels ||
            o_short_pixels!=expected_pixels || o_output_pixels!=expected_pixels ||
            next_index!=expected_groups)) detected_error=9;
    end

    // The controller never uses timeout or FIFO-empty to manufacture retirement.
    always @* begin
        next_state=state;
        case(state)
            IDLE:if(s_start_valid && s_start_ready)next_state=COMMON;
            COMMON:next_state=detected_error!=0 ? DRAIN : RATIO;
            RATIO:next_state=(detected_error!=0 || o_first_error!=0) ? DRAIN : SIZE;
            SIZE:if(detected_error!=0 || o_first_error!=0)next_state=DRAIN;
                else if(rows_left==0)next_state=CONTEXT;
            CONTEXT:if(m_context_valid && m_context_ready)
                next_state=(detected_error!=0 || o_first_error!=0) ? DRAIN : RUN;
            RUN:if(detected_error!=0 || o_first_error!=0 ||
                (pair_fire && expected_eof))next_state=DRAIN;
            DRAIN:if(streams_quiet)next_state=FINAL;
            FINAL:next_state=RESULT;
            RESULT:if(m_result_valid && m_result_ready)next_state=IDLE;
            default:next_state=IDLE;
        endcase
    end
    always @(posedge clk) begin
        if(!rst_n)state<=IDLE;
        else state<=next_state;
    end

    // Original descriptors are immutable; derived RAW14 metadata is separate.
    always @(posedge clk) begin
        if(!rst_n) begin
            o_long_frame<=0;o_short_frame<=0;o_long_tag<=0;o_short_tag<=0;o_job_id<=0;o_pair_id<=0;
            o_ratio_log2<=0;black_long<=0;black_short<=0;motion_base<=0;motion_shift<=0;
            max_delta_ns<=0;timestamp_delta<=0;expected_pixels<=0;expected_groups<=0;row_groups<=0;rows_left<=0;
            o_first_error<=0;o_stale_source_count<=0;o_stale_cancel_count<=0;
        end else begin
            if(s_start_valid && s_start_ready)begin
                o_long_frame<=s_long_frame;o_short_frame<=s_short_frame;
                o_long_tag<=s_long_tag;o_short_tag<=s_short_tag;o_job_id<=s_job_id;o_pair_id<=s_pair_id;
                o_ratio_log2<=s_ratio_log2;black_long<=s_black_long;black_short<=s_black_short;
                motion_base<=s_motion_base;motion_shift<=s_motion_shift;max_delta_ns<=s_max_delta_ns;
                o_first_error<=0;
            end else if(!result_frozen && o_first_error==0 && detected_error!=0)
                o_first_error<=detected_error;
            if(state==COMMON)begin
                expected_pixels<=0;expected_groups<=0;rows_left<=o_long_frame[236:221];
                row_groups<=o_long_frame[220:205]>>2;
                timestamp_delta<=o_short_frame[204:141]-o_long_frame[204:141];
            end
            if(state==SIZE && rows_left!=0)begin
                expected_pixels<=expected_pixels+o_long_frame[220:205];
                expected_groups<=expected_groups+row_groups;rows_left<=rows_left-1'b1;
            end
            if((long_source_fire && (!long_source_match || long_seen || result_frozen)) ||
                (short_source_fire && (!short_source_match || short_seen || result_frozen)))
                o_stale_source_count<=o_stale_source_count+1'b1;
            if(cancel_fire && (!cancel_match || result_frozen))
                o_stale_cancel_count<=o_stale_cancel_count+1'b1;
        end
    end

    // One group per reader, plus the merge's existing six-stage elastic pipeline.
    always @(posedge clk) begin
        if(!rst_n || (s_start_valid && s_start_ready))begin
            long_head_valid<=0;short_head_valid<=0;long_seen<=0;short_seen<=0;long_ok<=0;short_ok<=0;
            o_long_pixels<=0;o_short_pixels<=0;o_output_pixels<=0;next_index<=0;column<=0;
            long_terminal_pixels<=0;short_terminal_pixels<=0;o_long_source_error<=0;o_short_source_error<=0;
            inflight<=0;index_pipe<=0;eof_pipe<=0;
        end else begin
            if(pair_fire)begin
                long_head_valid<=0;short_head_valid<=0;next_index<=next_index+1'b1;
                if(expected_eol)column<=0;else column<=column+1'b1;
            end
            if(long_fire)begin
                o_long_pixels<=o_long_pixels>32'hffffffff-pixels_in_keep(s_long_keep) ?
                    32'hffffffff : o_long_pixels+pixels_in_keep(s_long_keep);
                if(state==RUN)begin
                    long_head_valid<=1;long_head<=s_long_data;long_index<=s_long_index;
                    long_tag<=s_long_data_tag;long_keep<=s_long_keep;
                    long_sof<=s_long_sof;long_eol<=s_long_eol;long_eof<=s_long_eof;
                end
            end
            if(short_fire)begin
                o_short_pixels<=o_short_pixels>32'hffffffff-pixels_in_keep(s_short_keep) ?
                    32'hffffffff : o_short_pixels+pixels_in_keep(s_short_keep);
                if(state==RUN)begin
                    short_head_valid<=1;short_head<=s_short_data;short_index<=s_short_index;
                    short_tag<=s_short_data_tag;short_keep<=s_short_keep;
                    short_sof<=s_short_sof;short_eol<=s_short_eol;short_eof<=s_short_eof;
                end
            end
            if(state==DRAIN)begin long_head_valid<=0;short_head_valid<=0;end
            if(long_source_fire && long_source_match && !long_seen && !result_frozen)begin
                long_seen<=1;long_ok<=s_long_source_ok && s_long_source_error==0;
                long_terminal_pixels<=s_long_source_pixels;o_long_source_error<=s_long_source_error;
            end
            if(short_source_fire && short_source_match && !short_seen && !result_frozen)begin
                short_seen<=1;short_ok<=s_short_source_ok && s_short_source_error==0;
                short_terminal_pixels<=s_short_source_pixels;o_short_source_error<=s_short_source_error;
            end
            case({pair_fire,output_fire})
                2'b10:inflight<=inflight+1'b1;
                2'b01:inflight<=inflight-1'b1;
                default:inflight<=inflight;
            endcase
            if(output_fire)o_output_pixels<=o_output_pixels+4;
            if(merge_ready)begin
                index_pipe<={index_pipe[159:0],next_index};
                eof_pipe<={eof_pipe[4:0],expected_eof};
            end
        end
    end
    hdr_merge4 u_merge(
        .clk(clk),.rst_n(rst_n),.clear(1'b0),.cfg_ratio_log2(o_ratio_log2),
        .cfg_black_long(black_long),.cfg_black_short(black_short),
        .cfg_motion_base(motion_base),.cfg_motion_shift(motion_shift),
        .s_long(long_head),.s_short(short_head),.s_valid(merge_valid),.s_ready(merge_ready),
        .s_sof(expected_sof),.s_eol(expected_eol),.m_raw(m_raw),.m_valid(m_valid),
        .m_ready(m_ready),.m_sof(m_sof),.m_eol(m_eol),.m_motion(m_motion));
endmodule
`default_nettype wire
