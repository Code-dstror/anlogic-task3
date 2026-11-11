// Neutral sparse-Y motion with external history transactions; no payload memory.
module preprocess_motion4 #(
    parameter integer MAX_WIDTH=320,
    parameter integer MAX_HEIGHT=180
) (
    input wire clk,rst_n,cancel,source_error,debug_clear,
    input wire source_reset_done,backend_reset_done,
    input wire start_valid,
    output wire start_ready,
    input wire [383:0] start_frame,start_history_frame,
    input wire [63:0] start_pipeline_key,
    input wire [159:0] start_context,
    input wire [31:0] start_tag,start_history_tag,
    input wire [8:0] start_width,
    input wire [7:0] start_height,
    input wire start_history_available,
    input wire [7:0] start_static_threshold,start_weak_threshold,start_motion_threshold,
    output wire begin_valid,
    input wire begin_ready,
    output reg [383:0] o_frame,o_history_frame,
    output reg [63:0] o_pipeline_key,
    output reg [159:0] o_context,
    output reg [31:0] o_tag,o_history_tag,
    output reg [8:0] o_width,
    output reg [7:0] o_height,
    output reg o_history_used,
    output reg [7:0] o_history_reason,
    input wire current_valid,
    output wire current_ready,
    input wire [31:0] current_y,
    input wire [3:0] current_keep,
    input wire current_sof,current_eol,current_eof,
    input wire [31:0] current_tag,
    input wire history_valid,
    output wire history_ready,
    input wire [31:0] history_y,
    input wire [3:0] history_keep,
    input wire history_sof,history_eol,history_eof,
    input wire [31:0] history_tag,
    output wire mask_valid,
    input wire mask_ready,
    output reg [3:0] mask_bits,
    output reg [7:0] mask_confidence,
    output reg [3:0] mask_keep,
    output reg mask_sof,mask_eol,mask_eof,
    output reg [8:0] mask_x,
    output reg [7:0] mask_y,
    output reg [15:0] mask_native_x,mask_native_y,
    output wire write_valid,
    input wire write_ready,
    output reg [31:0] write_y,
    output wire [3:0] write_keep,
    output wire write_sof,write_eol,write_eof,
    input wire source_done_valid,
    output wire source_done_ready,
    input wire [383:0] source_done_frame,
    input wire [63:0] source_done_key,
    input wire [159:0] source_done_context,
    input wire [31:0] source_done_tag,
    input wire source_done_ok,
    output wire close_valid,
    input wire close_ready,
    output reg close_commit_candidate,
    output reg [15:0] close_write_pixels,
    input wire ack_valid,
    output wire ack_ready,
    input wire [383:0] ack_frame,
    input wire [63:0] ack_key,
    input wire [159:0] ack_context,
    input wire [31:0] ack_tag,
    input wire ack_quiescent,ack_write_ok,
    input wire [15:0] ack_write_pixels,
    output wire status_valid,
    input wire status_ready,
    output reg status_success,
    output wire history_publish,
    output reg [7:0] status_error,
    output reg [15:0] pixel_count,mask_count,write_count,foreground_count,
    output reg [15:0] confidence0_count,confidence1_count,confidence2_count,confidence3_count,
    output reg [23:0] sum_absdiff,sum_y,
    output reg signed [24:0] sum_diff,
    output reg global_change_hint,brightness_shift_hint,temporal_trust,
    output reg [31:0] frames_started,frames_completed,frames_failed,
    output reg first_fault_valid,
    output reg [7:0] first_fault_code,
    output reg [383:0] first_fault_frame,
    output reg [31:0] first_fault_tag
);
    localparam [2:0] ST_IDLE=0,ST_BEGIN=1,ST_RUN=2,ST_DRAIN=3,ST_CLOSE=4,ST_ACK=5,ST_STATUS=6;
    reg [2:0] state;
    reg failed,source_seen,source_ok,backend_seen,backend_ok,eof_seen;
    reg [7:0] first_error,static_threshold,weak_threshold,motion_threshold;
    reg mask_pending,write_pending;
    reg [8:0] x;
    reg [7:0] y;
    // These are two scalar metadata records, never pixel/history storage.
    reg cache0_valid,cache1_valid;
    reg [383:0] cache0_frame,cache1_frame;
    reg [63:0] cache0_key,cache1_key;
    reg [31:0] cache0_tag,cache1_tag;
    reg [8:0] cache0_width,cache1_width;
    reg [7:0] cache0_height,cache1_height;
    wire cache_valid=start_frame[4] ? cache1_valid : cache0_valid;
    wire [383:0] cache_frame=start_frame[4] ? cache1_frame : cache0_frame;
    wire [63:0] cache_key=start_frame[4] ? cache1_key : cache0_key;
    wire [31:0] cache_tag=start_frame[4] ? cache1_tag : cache0_tag;
    wire [8:0] cache_width=start_frame[4] ? cache1_width : cache0_width;
    wire [7:0] cache_height=start_frame[4] ? cache1_height : cache0_height;
    wire [15:0] native_width=({7'b0,start_width}<<2)+({7'b0,start_width}<<1);
    wire [15:0] native_height=({8'b0,start_height}<<2)+({8'b0,start_height}<<1);
    wire bad_start=start_width==0||start_width>MAX_WIDTH||start_width>320||
        start_height==0||start_height>MAX_HEIGHT||start_height>180||
        start_static_threshold>start_weak_threshold||start_weak_threshold>start_motion_threshold||
        !start_frame[0]||start_frame[383:367]!=0||start_frame[44:13]==0||start_frame[76:45]==0||
        start_frame[302:271]==0||start_frame[2:1]==3||
        (start_frame[238:237]!=1&&start_frame[238:237]!=2)||
        start_frame[220:205]!=native_width||start_frame[236:221]!=native_height;
    reg [7:0] history_reason;
    always @* begin
        history_reason=0;
        if(!cache_valid) history_reason=1;
        else begin
            if(!start_history_available||start_history_frame!=cache_frame||start_history_tag!=cache_tag) history_reason[1]=1;
            if(start_frame[76:45]!=cache_frame[76:45]||start_frame[140:109]!=cache_frame[140:109]) history_reason[2]=1;
            if(start_frame[236:205]!=cache_frame[236:205]||start_frame[238:237]!=cache_frame[238:237]||
                start_frame[270:239]!=cache_frame[270:239]||start_pipeline_key!=cache_key||
                start_width!=cache_width||start_height!=cache_height) history_reason[3]=1;
            if(start_frame[334:271]!=cache_frame[334:271]) history_reason[4]=1;
            if(start_frame[3:1]!=cache_frame[3:1]) history_reason[5]=1;
            if(cache_frame[108:77]==32'hffffffff||start_frame[108:77]!=cache_frame[108:77]+32'd1||
                start_frame[204:141]<=cache_frame[204:141]) history_reason[6]=1;
        end
        if(bad_start) history_reason[7]=1;
    end
    wire run=rst_n;
    assign start_ready=run&&state==ST_IDLE&&source_reset_done&&backend_reset_done;
    wire take_start=start_valid&&start_ready;
    assign begin_valid=run&&state==ST_BEGIN;
    assign mask_valid=run&&mask_pending;
    assign write_valid=run&&write_pending;
    assign {write_keep,write_sof,write_eol,write_eof}={mask_keep,mask_sof,mask_eol,mask_eof};
    assign close_valid=run&&state==ST_CLOSE;
    assign ack_ready=run&&state==ST_ACK;
    assign status_valid=run&&state==ST_STATUS;
    assign history_publish=status_valid&&status_success;
    wire active=state!=ST_IDLE&&state!=ST_STATUS;
    assign source_done_ready=run&&active&&!source_seen;
    wire draining=state==ST_DRAIN||state==ST_CLOSE||state==ST_ACK;
    wire group_free=(!mask_pending||mask_ready)&&(!write_pending||write_ready);
    assign current_ready=run&&(draining||(state==ST_RUN&&!cancel&&!source_error&&group_free&&
        (!o_history_used||history_valid)));
    assign history_ready=run&&(draining||(state==ST_RUN&&!cancel&&!source_error&&group_free&&
        o_history_used&&current_valid));
    wire take_current=current_valid&&current_ready;
    wire take_history=history_valid&&history_ready;
    wire take_mask=mask_valid&&mask_ready;
    wire take_write=write_valid&&write_ready;
    wire take_source=source_done_valid&&source_done_ready;
    wire source_match=source_done_frame==o_frame&&source_done_key==o_pipeline_key&&
        source_done_context==o_context&&source_done_tag==o_tag;
    wire take_ack=ack_valid&&ack_ready;
    wire ack_match=ack_frame==o_frame&&ack_key==o_pipeline_key&&ack_context==o_context&&ack_tag==o_tag;
    // A quiescent ACK cannot coexist with a returned held history head.
    wire real_ack=take_ack&&ack_match&&ack_quiescent&&!history_valid;
    function [2:0] lanes;
        input [3:0] keep;
        begin case(keep) 1:lanes=1;3:lanes=2;7:lanes=3;15:lanes=4;default:lanes=0;endcase end
    endfunction
    wire [8:0] remaining=o_width-x;
    wire [2:0] group_lanes=remaining>=4 ? 3'd4 : remaining[2:0];
    wire [3:0] expected_keep=group_lanes==4 ? 4'hf : group_lanes==3 ? 4'h7 : group_lanes==2 ? 4'h3 : 4'h1;
    wire expected_sof=x==0&&y==0;
    wire expected_eol=x+group_lanes==o_width;
    wire expected_eof=expected_eol&&y+1'b1==o_height;
    wire current_bad=current_keep!=expected_keep||current_sof!=expected_sof||
        current_eol!=expected_eol||current_eof!=expected_eof||current_tag!=o_tag;
    wire history_bad=history_keep!=expected_keep||history_sof!=expected_sof||
        history_eol!=expected_eol||history_eof!=expected_eof||history_tag!=o_tag;
    reg [7:0] fault_code;
    always @* begin
        fault_code=0;
        if(active) begin
            if((state==ST_RUN&&take_current&&current_bad)||
                (draining&&eof_seen&&take_current&&!failed)) fault_code=2;
            else if(source_error||(take_source&&source_match&&!source_done_ok)) fault_code=3;
            else if((state==ST_RUN&&((o_history_used&&take_history&&history_bad)||
                (!o_history_used&&history_valid)))||
                (draining&&eof_seen&&take_history&&!failed)) fault_code=4;
            else if((take_source&&!source_match)||(take_ack&&(!ack_match||!ack_quiescent||history_valid))) fault_code=5;
            else if(real_ack&&(!ack_write_ok||ack_write_pixels!=write_count)) fault_code=6;
            else if(cancel) fault_code=7;
        end
    end
    wire new_fault=active&&!failed&&fault_code!=0;
    wire compute_group=state==ST_RUN&&take_current&&fault_code==0&&!failed;
    reg [3:0] next_mask;
    reg [7:0] next_confidence;
    reg [31:0] next_write_y;
    reg [2:0] add_foreground,add_conf0,add_conf1,add_conf2,add_conf3;
    reg [9:0] add_abs,add_y;
    reg signed [10:0] add_diff;
    reg [7:0] lane_current,lane_history,lane_diff;
    reg signed [8:0] lane_signed;
    reg [1:0] lane_confidence;
    integer lane;
    always @* begin
        next_mask=0;next_confidence=0;next_write_y=0;
        add_foreground=0;add_conf0=0;add_conf1=0;add_conf2=0;add_conf3=0;
        add_abs=0;add_diff=0;add_y=0;
        lane_current=0;lane_history=0;lane_diff=0;lane_signed=0;lane_confidence=0;
        for(lane=0;lane<4;lane=lane+1) begin
            if(expected_keep[lane]) begin
                lane_current=current_y[lane*8 +:8];lane_history=history_y[lane*8 +:8];
                next_write_y[lane*8 +:8]=lane_current;add_y=add_y+lane_current;
                lane_signed=$signed({1'b0,lane_current})-$signed({1'b0,lane_history});
                lane_diff=lane_signed[8] ? -lane_signed : lane_signed;
                lane_confidence=0;
                if(o_history_used) begin
                    next_mask[lane]=lane_diff>motion_threshold;
                    lane_confidence=lane_diff<=static_threshold ? 3 : lane_diff<=weak_threshold ? 2 :
                        lane_diff<=motion_threshold ? 1 : 0;
                    add_abs=add_abs+lane_diff;add_diff=add_diff+lane_signed;
                end
                next_confidence[lane*2 +:2]=lane_confidence;
                add_foreground=add_foreground+next_mask[lane];
                case(lane_confidence) 0:add_conf0=add_conf0+1'b1;1:add_conf1=add_conf1+1'b1;
                    2:add_conf2=add_conf2+1'b1;3:add_conf3=add_conf3+1'b1;endcase
            end
        end
    end
    wire [24:0] abs_sum_diff=sum_diff[24] ? -sum_diff : sum_diff;
    wire broad_hint=o_history_used&&pixel_count!=0&&({2'b0,foreground_count}<<2)>={2'b0,pixel_count};
    wire brightness_hint=o_history_used&&pixel_count!=0&&abs_sum_diff>=({9'b0,pixel_count}<<3);
    wire source_terminal=source_seen||(take_source&&source_match);
    wire backend_terminal=backend_seen||real_ack;
    wire all_success=!failed&&fault_code==0&&(source_ok||(take_source&&source_match&&source_done_ok))&&
        (backend_ok||(real_ack&&ack_write_ok&&ack_write_pixels==write_count))&&eof_seen&&
        pixel_count!=0&&mask_count==pixel_count&&write_count==pixel_count;

    always @(posedge clk) begin
        if(!rst_n) begin
            state<=ST_IDLE;failed<=0;source_seen<=0;source_ok<=0;backend_seen<=0;backend_ok<=0;eof_seen<=0;
            first_error<=0;static_threshold<=0;weak_threshold<=0;motion_threshold<=0;
            mask_pending<=0;write_pending<=0;x<=0;y<=0;
            cache0_valid<=0;cache1_valid<=0;cache0_frame<=0;cache1_frame<=0;
            cache0_key<=0;cache1_key<=0;cache0_tag<=0;cache1_tag<=0;
            cache0_width<=0;cache1_width<=0;cache0_height<=0;cache1_height<=0;
            o_frame<=0;o_history_frame<=0;o_pipeline_key<=0;o_context<=0;o_tag<=0;o_history_tag<=0;
            o_width<=0;o_height<=0;o_history_used<=0;o_history_reason<=0;
            mask_bits<=0;mask_confidence<=0;mask_keep<=0;mask_sof<=0;mask_eol<=0;mask_eof<=0;
            mask_x<=0;mask_y<=0;mask_native_x<=0;mask_native_y<=0;write_y<=0;
            close_commit_candidate<=0;close_write_pixels<=0;status_success<=0;status_error<=0;
            pixel_count<=0;mask_count<=0;write_count<=0;foreground_count<=0;
            confidence0_count<=0;confidence1_count<=0;confidence2_count<=0;confidence3_count<=0;
            sum_absdiff<=0;sum_diff<=0;sum_y<=0;global_change_hint<=0;brightness_shift_hint<=0;temporal_trust<=0;
        end else begin
            if(take_mask) begin mask_pending<=0;mask_count<=mask_count+lanes(mask_keep);end
            if(take_write) begin write_pending<=0;write_count<=write_count+lanes(mask_keep);end
            if(take_source&&source_match) begin source_seen<=1;source_ok<=source_done_ok;end
            if(real_ack) begin backend_seen<=1;backend_ok<=ack_write_ok&&ack_write_pixels==write_count;end
            if(new_fault) begin
                failed<=1;first_error<=fault_code;
                if(o_frame[4]) cache1_valid<=0;else cache0_valid<=0;
                if(state==ST_RUN) state<=ST_DRAIN;
            end
            case(state)
                ST_IDLE: if(take_start) begin
                    o_frame<=start_frame;o_pipeline_key<=start_pipeline_key;o_context<=start_context;o_tag<=start_tag;
                    o_width<=start_width;o_height<=start_height;
                    o_history_used<=history_reason==0;o_history_reason<=history_reason;
                    o_history_frame<=history_reason==0 ? cache_frame : 384'd0;
                    o_history_tag<=history_reason==0 ? cache_tag : 32'd0;
                    static_threshold<=start_static_threshold;weak_threshold<=start_weak_threshold;motion_threshold<=start_motion_threshold;
                    failed<=bad_start;first_error<=bad_start ? 8'd1 : 8'd0;
                    source_seen<=0;source_ok<=0;backend_seen<=0;backend_ok<=0;eof_seen<=0;
                    mask_pending<=0;write_pending<=0;x<=0;y<=0;
                    pixel_count<=0;mask_count<=0;write_count<=0;foreground_count<=0;
                    confidence0_count<=0;confidence1_count<=0;confidence2_count<=0;confidence3_count<=0;
                    sum_absdiff<=0;sum_diff<=0;sum_y<=0;global_change_hint<=0;brightness_shift_hint<=0;temporal_trust<=0;
                    close_commit_candidate<=0;close_write_pixels<=0;status_success<=0;status_error<=bad_start ? 8'd1 : 8'd0;
                    if(history_reason!=0) begin if(start_frame[4]) cache1_valid<=0;else cache0_valid<=0;end
                    state<=bad_start ? ST_STATUS : ST_BEGIN;
                end
                ST_BEGIN: if(begin_valid&&begin_ready) state<=(failed||fault_code!=0) ? ST_DRAIN : ST_RUN;
                ST_RUN: if(compute_group) begin
                    mask_pending<=1;write_pending<=1;mask_bits<=next_mask;mask_confidence<=next_confidence;
                    mask_keep<=expected_keep;mask_sof<=expected_sof;mask_eol<=expected_eol;mask_eof<=expected_eof;
                    mask_x<=x;mask_y<=y;
                    mask_native_x<=16'd3+({7'b0,x}<<2)+({7'b0,x}<<1);
                    mask_native_y<=16'd3+({8'b0,y}<<2)+({8'b0,y}<<1);write_y<=next_write_y;
                    pixel_count<=pixel_count+group_lanes;foreground_count<=foreground_count+add_foreground;
                    confidence0_count<=confidence0_count+add_conf0;confidence1_count<=confidence1_count+add_conf1;
                    confidence2_count<=confidence2_count+add_conf2;confidence3_count<=confidence3_count+add_conf3;
                    sum_absdiff<=sum_absdiff+add_abs;sum_diff<=sum_diff+add_diff;sum_y<=sum_y+add_y;
                    if(expected_eol) begin x<=0;y<=y+1'b1;end else x<=x+group_lanes;
                    if(expected_eof) begin eof_seen<=1;state<=ST_DRAIN;end
                end
                ST_DRAIN: if(!mask_pending&&!write_pending&&(failed||fault_code!=0||(source_seen&&source_ok))) begin
                    close_commit_candidate<=!failed&&fault_code==0&&source_seen&&source_ok&&eof_seen&&
                        pixel_count!=0&&mask_count==pixel_count&&write_count==pixel_count;
                    close_write_pixels<=write_count;state<=ST_CLOSE;
                end
                ST_CLOSE: if(close_valid&&close_ready) state<=ST_ACK;
                ST_ACK: if(backend_terminal&&source_terminal&&!current_valid&&!history_valid&&!mask_pending&&!write_pending) begin
                    status_success<=all_success;status_error<=failed ? first_error : fault_code;
                    global_change_hint<=broad_hint;brightness_shift_hint<=brightness_hint;
                    temporal_trust<=all_success&&o_history_used&&!broad_hint&&!brightness_hint;
                    state<=ST_STATUS;
                end
                ST_STATUS: if(status_valid&&status_ready) begin
                    if(status_success) begin
                        if(o_frame[4]) begin
                            cache1_valid<=1;cache1_frame<=o_frame;cache1_key<=o_pipeline_key;cache1_tag<=o_tag;
                            cache1_width<=o_width;cache1_height<=o_height;
                        end else begin
                            cache0_valid<=1;cache0_frame<=o_frame;cache0_key<=o_pipeline_key;cache0_tag<=o_tag;
                            cache0_width<=o_width;cache0_height<=o_height;
                        end
                    end
                    state<=ST_IDLE;
                end
                default: state<=ST_IDLE;
            endcase
        end
    end
    // Diagnostics are independent of every functional/cache/stat signal.
    always @(posedge clk) begin
        if(!rst_n||debug_clear) begin
            frames_started<=0;frames_completed<=0;frames_failed<=0;
            first_fault_valid<=0;first_fault_code<=0;first_fault_frame<=0;first_fault_tag<=0;
        end else begin
            if(take_start) frames_started<=frames_started+1'b1;
            if(status_valid&&status_ready) begin
                if(status_success) frames_completed<=frames_completed+1'b1;else frames_failed<=frames_failed+1'b1;
            end
            if((take_start&&bad_start)||new_fault) begin
                if(!first_fault_valid) begin
                    first_fault_valid<=1;first_fault_code<=take_start&&bad_start ? 8'd1 : fault_code;
                    first_fault_frame<=take_start ? start_frame : o_frame;first_fault_tag<=take_start ? start_tag : o_tag;
                end
            end
        end
    end
endmodule
