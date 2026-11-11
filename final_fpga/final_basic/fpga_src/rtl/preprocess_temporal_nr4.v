// Metadata-owned two-frame NR on stoppable replay; full raw history stays in DDR.
module preprocess_temporal_nr4 #(
    parameter integer MAX_WIDTH=3840, MAX_HEIGHT=2160, SLOTS_PER_CAMERA=4
) (
    input wire clk, rst_n,
    input wire i_start_valid, output wire o_start_ready,
    input wire [383:0] i_frame, input wire [63:0] i_tag, i_pipeline_key,
    input wire i_enable, input wire [7:0] i_motion_guard,
    input wire i_history_reset, i_third_enable,
    input wire i_history_available, input wire [383:0] i_history_frame,
    input wire [63:0] i_history_tag,
    input wire i_motion_qualified, input wire [63:0] i_motion_current_tag, i_motion_history_tag,
    output wire m_plan_valid, input wire m_plan_ready,
    output wire [383:0] o_frame, output wire [63:0] o_tag, o_pipeline_key, o_history_tag,
    output wire o_history_selected,
    input wire [95:0] s_rgb, input wire [3:0] s_keep,
    input wire s_sof, s_eol, s_last, s_valid, output wire s_ready,
    input wire [63:0] s_tag, input wire [31:0] s_index,
    input wire [95:0] h_rgb, input wire [3:0] h_keep,
    input wire h_sof, h_eol, h_last, h_valid, output wire h_ready,
    input wire [63:0] h_tag, input wire [31:0] h_index,
    input wire [7:0] motion_confidence, input wire [3:0] motion_lane_valid, motion_keep,
    input wire motion_sof, motion_eol, motion_last, motion_valid, output wire motion_ready,
    input wire [63:0] motion_current_tag, motion_history_tag, input wire [31:0] motion_index,
    input wire [95:0] h2_rgb, input wire [3:0] h2_keep,
    input wire h2_sof, h2_eol, h2_last, h2_valid, output wire h2_ready,
    input wire [63:0] h2_tag, input wire [31:0] h2_index,
    output wire [95:0] m_rgb, output wire m_valid, input wire m_ready,
    output wire [95:0] m_history_raw, m_history_filtered,
    output wire m_history_valid, input wire m_history_ready,
    output wire [3:0] m_keep, output wire m_sof, m_eol, m_last,
    output wire [31:0] m_index, output wire [63:0] m_tag,
    input wire i_frame_status_valid, output wire o_frame_status_ready,
    input wire [63:0] i_frame_status_tag, input wire i_frame_status_ok,
    input wire i_history_status_valid, output wire o_history_status_ready,
    input wire [63:0] i_history_status_tag, input wire i_history_status_ok,
    input wire i_abort, i_read_quiescent,
    output wire m_write_status_valid, input wire m_write_status_ready,
    output wire [63:0] m_write_status_tag, m_write_status_key,
    output wire [383:0] m_write_status_frame,
    output wire m_write_status_ok, output wire [7:0] m_write_status_error,
    output wire [31:0] m_write_status_pixels,
    input wire i_write_ack_valid, output wire o_write_ack_ready,
    input wire [63:0] i_write_ack_tag, i_write_ack_key, input wire [383:0] i_write_ack_frame,
    input wire i_write_ack_ok, input wire [7:0] i_write_ack_error,
    output reg m_result_valid, input wire m_result_ready,
    output wire [63:0] m_result_tag, m_result_key, output wire [383:0] m_result_frame,
    output reg m_result_ok, m_result_current_ok, m_result_history_commit, output reg [7:0] m_result_error,
    output wire o_busy, output wire [1:0] o_history_valid,
    input wire i_debug_enable, i_debug_snapshot,
    output reg [31:0] o_debug_frames, o_debug_history_used, o_debug_fallback_lanes, o_debug_stale_tokens,
    output reg o_first_fault_valid, output reg [7:0] o_first_fault_code,
    output reg [63:0] o_first_fault_tag, output reg [31:0] o_first_fault_index
);
    localparam [2:0] IDLE=0,CHECK=1,PLAN=2,ACTIVE=3,FENCE=4,ACK=5,RESULT=6;
    localparam [7:0] E_CONFIG=1,E_THIRD=2,E_STREAM=3,E_FRAME=4,E_HISTORY=5,E_WRITE=6,E_ABORT=7,E_COUNT=8,E_STALE=9,E_METADATA=10;
    reg [2:0] state;
    reg [383:0] frame, history_frame0, history_frame1;
    reg [63:0] tag, pipeline_key, history_tag, history_tag0, history_tag1, history_key0, history_key1;
    reg history_valid0, history_valid1, enabled, third_enabled, reset_history;
    reg history_offer_match, motion_qualified, history_selected;
    reg [7:0] guard, error_code;
    reg frame_bad, current_bad, planned, input_done, frame_status_seen, history_status_seen, ack_seen, ack_ok;
    reg [15:0] x, y;
    reg [31:0] input_index, input_pixels, output_pixels, written_pixels;
    reg write_status_ok;reg [7:0] write_status_error;
    reg [31:0] frames_count, history_count, fallback_count, stale_count;
    wire camera=frame[4];
    wire [383:0] saved_frame=camera ? history_frame1 : history_frame0;
    wire [63:0] saved_key=camera ? history_key1 : history_key0;
    wire saved_valid=camera ? history_valid1 : history_valid0;
    function matching_attributes;
        input [383:0] current, previous;
        begin matching_attributes=current[4:1]==previous[4:1] && current[76:45]==previous[76:45] &&
            current[140:109]==previous[140:109] && current[334:205]==previous[334:205];end
    endfunction
    function [2:0] lanes;
        input [3:0] keep;
        begin lanes={2'd0,keep[0]}+{2'd0,keep[1]}+{2'd0,keep[2]}+{2'd0,keep[3]};end
    endfunction
    function [31:0] increment;
        input [31:0] value;
        begin increment=&value ? value : value+1'b1;end
    endfunction
    wire valid_frame=frame[383:367]==0 && frame[12:5]<SLOTS_PER_CAMERA && frame[44:13]!=0 && frame[76:45]!=0 &&
        frame[2:1]!=3 && (frame[238:237]==1 || frame[238:237]==2) &&
        frame[220:205]!=0 && frame[220:205]<=MAX_WIDTH && frame[236:221]!=0 && frame[236:221]<=MAX_HEIGHT && tag!=0;
    wire compatible=saved_valid && matching_attributes(frame,saved_frame) && saved_key==pipeline_key &&
        frame[108:77]-saved_frame[108:77]==32'd1 && frame[204:141]>saved_frame[204:141];
    wire metadata_qualified=frame[0] && frame[302:271]!=0;
    wire select_history=enabled && metadata_qualified && !reset_history && compatible && history_offer_match && motion_qualified;
    assign o_start_ready=rst_n && state==IDLE;
    assign m_plan_valid=rst_n && state==PLAN;
    assign o_frame=frame;assign o_tag=tag;assign o_pipeline_key=pipeline_key;
    assign o_history_tag=history_tag;assign o_history_selected=history_selected;
    assign o_busy=state!=IDLE;assign o_history_valid={history_valid1,history_valid0};assign h2_ready=1'b0;

    reg v0,v1,v2,m_sent,history_sent;
    reg [95:0] raw0,history0,raw1,filtered1,raw2,filtered2;
    reg [7:0] confidence0;reg [3:0] valid0,keep0,keep1,keep2;
    reg [2:0] markers0,markers1,markers2;
    reg [31:0] index0,index1,index2;
    wire [95:0] blended;wire [3:0] fused;
    wire advance=!v2 || ((m_sent || m_ready) && (history_sent || m_history_ready));
    assign s_ready=rst_n && state==ACTIVE && !input_done && !i_abort && advance &&
        (!history_selected || (h_valid && motion_valid));
    assign h_ready=rst_n && state==ACTIVE && !input_done && !i_abort && advance && history_selected && s_valid && motion_valid;
    assign motion_ready=rst_n && state==ACTIVE && !input_done && !i_abort && advance && history_selected && s_valid && h_valid;
    wire join_fire=s_valid && s_ready;
    wire row_last={1'b0,x}+17'd4 >= {1'b0,frame[220:205]};
    wire frame_last=row_last && y==frame[236:221]-1'b1;
    wire [16:0] remaining={1'b0,frame[220:205]}-{1'b0,x};
    wire [3:0] expected_keep=!row_last || remaining>=4 ? 4'hf : remaining==3 ? 4'h7 : remaining==2 ? 4'h3 : 4'h1;
    wire current_good=s_tag==tag && s_index==input_index && s_keep==expected_keep &&
        s_sof==(input_index==0) && s_eol==row_last && s_last==frame_last;
    wire history_good=h_tag==history_tag && h_index==input_index && h_keep==s_keep &&
        {h_sof,h_eol,h_last}=={s_sof,s_eol,s_last};
    wire motion_good=motion_current_tag==tag && motion_history_tag==history_tag && motion_index==input_index &&
        motion_keep==s_keep && {motion_sof,motion_eol,motion_last}=={s_sof,s_eol,s_last};
    wire stream_good=current_good && (!history_selected || (history_good && motion_good));
    preprocess_temporal_nr_blend4 u_blend(.i_current(raw0),.i_history(history0),
        .i_confidence(confidence0),.i_lane_valid(valid0),.i_guard(guard),.o_rgb(blended),.o_fused(fused));
    assign m_rgb=filtered2;assign m_valid=rst_n && v2 && !m_sent;
    assign m_history_raw=raw2;assign m_history_filtered=filtered2;
    assign m_history_valid=rst_n && v2 && !history_sent;
    assign m_keep=keep2;assign {m_sof,m_eol,m_last}=markers2;assign m_index=index2;assign m_tag=tag;
    wire pipe_empty=!v0 && !v1 && !v2;
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin v0<=0;v1<=0;v2<=0;m_sent<=0;history_sent<=0;end
        else if(advance) begin
            v0<=join_fire;v1<=v0;v2<=v1;m_sent<=0;history_sent<=0;
            if(join_fire) begin
                raw0<=s_rgb;history0<=h_rgb;confidence0<=motion_confidence;
                valid0<=history_selected && !frame_bad && stream_good ? motion_lane_valid&s_keep : 4'd0;
                keep0<=s_keep;markers0<={s_sof,s_eol,s_last};index0<=s_index;
            end
            if(v0) begin raw1<=raw0;filtered1<=blended;keep1<=keep0;markers1<=markers0;index1<=index0;end
            if(v1) begin raw2<=raw1;filtered2<=filtered1;keep2<=keep1;markers2<=markers1;index2<=index1;end
        end else begin
            if(m_valid && m_ready) m_sent<=1;
            if(m_history_valid && m_history_ready) history_sent<=1;
        end
    end

    assign o_frame_status_ready=rst_n && planned && !frame_status_seen && state!=RESULT;
    assign o_history_status_ready=rst_n && planned && history_selected && !history_status_seen && state!=RESULT;
    wire frame_status_fire=i_frame_status_valid && o_frame_status_ready;
    wire history_status_fire=i_history_status_valid && o_history_status_ready;
    wire frame_status_match=i_frame_status_tag==tag;
    wire history_status_match=i_history_status_tag==history_tag;
    assign m_write_status_valid=rst_n && state==FENCE;
    assign m_write_status_tag=tag;assign m_write_status_key=pipeline_key;assign m_write_status_frame=frame;
    assign m_write_status_ok=write_status_ok;assign m_write_status_error=write_status_error;assign m_write_status_pixels=input_pixels;
    assign o_write_ack_ready=rst_n && state==ACK && !ack_seen;
    wire ack_fire=i_write_ack_valid && o_write_ack_ready;
    wire ack_match=i_write_ack_tag==tag && i_write_ack_key==pipeline_key && i_write_ack_frame==frame;
    wire stale_event=(frame_status_fire && !frame_status_match) || (history_status_fire && !history_status_match) || (ack_fire && !ack_match);
    wire draining=state==PLAN || state==ACTIVE || state==FENCE || state==ACK;
    wire complete_inputs=input_done && pipe_empty && frame_status_seen && history_status_seen;
    wire count_good=input_pixels==output_pixels && input_pixels==written_pixels;
    wire failure_now=(i_abort && draining) || (join_fire && !stream_good) ||
        (frame_status_fire && frame_status_match && !i_frame_status_ok) ||
        (history_status_fire && history_status_match && !i_history_status_ok) ||
        (ack_fire && ack_match && !i_write_ack_ok && metadata_qualified) || (state==ACTIVE && complete_inputs && !count_good);
    wire current_failure_now=(i_abort && draining) || (join_fire && !current_good) ||
        (frame_status_fire && frame_status_match && !i_frame_status_ok) ||
        (state==ACTIVE && complete_inputs && input_pixels!=output_pixels);
    wire [7:0] failure_code=i_abort ? E_ABORT : join_fire && !stream_good ? E_STREAM :
        frame_status_fire && !i_frame_status_ok ? E_FRAME : history_status_fire && !i_history_status_ok ? E_HISTORY :
        ack_fire && !i_write_ack_ok ? (i_write_ack_error==0 ? E_WRITE : i_write_ack_error) : E_COUNT;
    assign m_result_tag=tag;assign m_result_key=pipeline_key;assign m_result_frame=frame;

    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            state<=IDLE;frame<=0;tag<=0;pipeline_key<=0;history_tag<=0;
            history_frame0<=0;history_frame1<=0;history_tag0<=0;history_tag1<=0;history_key0<=0;history_key1<=0;
            history_valid0<=0;history_valid1<=0;enabled<=0;third_enabled<=0;reset_history<=0;
            history_offer_match<=0;motion_qualified<=0;history_selected<=0;guard<=0;error_code<=0;frame_bad<=0;current_bad<=0;planned<=0;
            input_done<=0;frame_status_seen<=0;history_status_seen<=0;ack_seen<=0;ack_ok<=0;
            x<=0;y<=0;input_index<=0;input_pixels<=0;output_pixels<=0;written_pixels<=0;write_status_ok<=0;write_status_error<=0;
            m_result_valid<=0;m_result_ok<=0;m_result_current_ok<=0;m_result_history_commit<=0;m_result_error<=0;
            frames_count<=0;history_count<=0;fallback_count<=0;stale_count<=0;
            o_debug_frames<=0;o_debug_history_used<=0;o_debug_fallback_lanes<=0;o_debug_stale_tokens<=0;
            o_first_fault_valid<=0;o_first_fault_code<=0;o_first_fault_tag<=0;o_first_fault_index<=0;
        end else begin
            if(i_debug_snapshot) begin o_debug_frames<=frames_count;o_debug_history_used<=history_count;o_debug_fallback_lanes<=fallback_count;o_debug_stale_tokens<=stale_count;end
            if(stale_event) stale_count<=increment(stale_count);
            if(i_debug_enable && !o_first_fault_valid &&
                (failure_now || stale_event || (state==CHECK && (!valid_frame || third_enabled)))) begin
                o_first_fault_valid<=1;o_first_fault_code<=state==CHECK ? (third_enabled ? E_THIRD : E_CONFIG) : failure_now ? failure_code : E_STALE;
                o_first_fault_tag<=tag;o_first_fault_index<=input_index;
            end
            if(failure_now) begin frame_bad<=1;if(!frame_bad) error_code<=failure_code;end
            if(current_failure_now) current_bad<=1;
            if(frame_status_fire && frame_status_match) frame_status_seen<=1;
            if(history_status_fire && history_status_match) history_status_seen<=1;
            if(ack_fire && ack_match) begin ack_seen<=1;ack_ok<=i_write_ack_ok;end
            if(i_abort && (state==PLAN || state==ACTIVE)) input_done<=1;
            if(join_fire) begin
                input_index<=input_index+1'b1;input_pixels<=input_pixels+lanes(s_keep);
                if(row_last) begin x<=0;y<=y+1'b1;end else x<=x+16'd4;
                if(frame_last || s_last) input_done<=1;
            end
            if(m_valid && m_ready) output_pixels<=output_pixels+lanes(m_keep);
            if(m_history_valid && m_history_ready) written_pixels<=written_pixels+lanes(m_keep);
            if(advance && v0) begin
                if(fallback_count<=32'hfffffffB) fallback_count<=fallback_count+lanes(keep0&~fused);
                else fallback_count<=32'hffffffff;
            end
            case(state)
                IDLE: if(i_start_valid) begin
                    frame<=i_frame;tag<=i_tag;pipeline_key<=i_pipeline_key;history_tag<=i_history_tag;
                    enabled<=i_enable;third_enabled<=i_third_enable;reset_history<=i_history_reset;guard<=i_motion_guard;
                    history_offer_match<=i_history_available && (i_frame[4] ?
                        (history_valid1 && i_history_frame==history_frame1 && i_history_tag==history_tag1) :
                        (history_valid0 && i_history_frame==history_frame0 && i_history_tag==history_tag0));
                    motion_qualified<=i_motion_qualified && i_motion_current_tag==i_tag && i_motion_history_tag==i_history_tag;
                    history_selected<=0;frame_bad<=0;current_bad<=0;error_code<=0;planned<=0;input_done<=0;
                    frame_status_seen<=0;history_status_seen<=0;ack_seen<=0;ack_ok<=0;
                    x<=0;y<=0;input_index<=0;input_pixels<=0;output_pixels<=0;written_pixels<=0;state<=CHECK;
                end
                CHECK: begin
                    if(!valid_frame || third_enabled) begin
                        m_result_valid<=1;m_result_ok<=0;m_result_current_ok<=0;m_result_history_commit<=0;m_result_error<=third_enabled ? E_THIRD : E_CONFIG;state<=RESULT;
                    end else begin
                        history_selected<=select_history;history_status_seen<=!select_history;
                        if(reset_history || !compatible || !metadata_qualified) begin if(camera) history_valid1<=0;else history_valid0<=0;end
                        if(select_history) history_count<=increment(history_count);
                        state<=PLAN;
                    end
                end
                PLAN: if(m_plan_ready) begin planned<=1;state<=ACTIVE;end
                ACTIVE: if(complete_inputs) begin
                    write_status_ok<=!frame_bad && !failure_now && count_good && metadata_qualified;
                    write_status_error<=frame_bad ? error_code : failure_now ? failure_code : metadata_qualified ? 8'd0 : E_METADATA;
                    state<=FENCE;
                end
                FENCE: if(m_write_status_ready) state<=ACK;
                ACK: if(ack_seen && i_read_quiescent) begin
                    m_result_valid<=1;m_result_ok<=!frame_bad && !failure_now;
                    m_result_current_ok<=!current_bad && !current_failure_now;
                    m_result_history_commit<=!frame_bad && !failure_now && ack_ok && metadata_qualified;
                    m_result_error<=frame_bad ? error_code : failure_now ? failure_code : !metadata_qualified ? E_METADATA : ack_ok ? 8'd0 : E_WRITE;
                    state<=RESULT;
                end
                RESULT: if(m_result_valid && m_result_ready) begin
                    if(m_result_history_commit) begin
                        if(camera) begin history_valid1<=1;history_frame1<=frame;history_tag1<=tag;history_key1<=pipeline_key;end
                        else begin history_valid0<=1;history_frame0<=frame;history_tag0<=tag;history_key0<=pipeline_key;end
                    end else if(planned) begin if(camera) history_valid1<=0;else history_valid0<=0;end
                    m_result_valid<=0;frames_count<=increment(frames_count);state<=IDLE;
                end
                default: begin state<=IDLE;history_valid0<=0;history_valid1<=0;m_result_valid<=0;end
            endcase
        end
    end
endmodule
