// Explicit sparse-cell projection for F39. This is an approximate conservative
// support field, never dense motion estimation. All full maps remain in DDR.
module preprocess_motion_projection4 #(
    parameter integer MAX_WIDTH=3840,MAX_HEIGHT=2160,SLOTS_PER_CAMERA=4
) (
    input wire clk,rst_n,reader_reset_done,cancel,
    input wire start_valid,output wire start_ready,
    input wire [383:0] start_frame,start_history_frame,
    input wire [63:0] start_key,start_tag,start_history_tag,input wire nr_history_available,
    input wire [383:0] map_frame,map_history_frame,
    input wire [63:0] map_key,input wire [31:0] map_tag,map_history_tag,
    input wire map_committed,f26_success,f26_temporal_trust,global_change,brightness_change,
    input wire [8:0] map_width,input wire [7:0] map_height,
    input wire [15:0] map_full_pixels,
    output wire plan_valid,input wire plan_ready,output wire plan_use_map,
    output wire [383:0] o_frame,o_history_frame,
    output wire [63:0] o_key,o_tag,o_history_tag,
    output wire [8:0] o_map_width,output wire [7:0] o_map_height,
    input wire map_valid,output wire map_ready,input wire [7:0] map_confidence,
    input wire [3:0] map_keep,input wire map_sof,map_eol,map_last,
    input wire [31:0] map_index,input wire [63:0] map_stream_tag,
    input wire read_error,
    output wire motion_valid,input wire motion_ready,
    output wire [7:0] motion_confidence,output wire [3:0] motion_lane_valid,motion_keep,
    output wire motion_sof,motion_eol,motion_last,output wire [31:0] motion_index,
    output wire abort_request,
    output wire close_valid,input wire close_ready,output wire close_cancel,
    input wire ack_valid,output wire ack_ready,
    input wire [383:0] ack_frame,input wire [63:0] ack_key,ack_tag,
    input wire ack_quiescent,ack_ok,input wire [31:0] ack_groups,
    output wire status_valid,input wire status_ready,
    output reg [1:0] status_kind,output reg [7:0] status_error,
    output wire status_qualified,output wire [7:0] status_bypass_reason,
    output reg [31:0] status_map_groups,status_output_groups,status_output_pixels,
    input wire debug_clear,
    output reg [31:0] stale_acks,frames_projected,frames_skipped,frames_failed
);
    localparam [2:0] IDLE=0,CHECK=1,PLAN=2,RUN=3,CLOSE=4,ACK=5,STATUS=6;
    localparam [1:0] SKIPPED=0,COMPLETE=1,FAILED=2;
    localparam [7:0] E_START=1,E_MAP=2,E_READ=3,E_CANCEL=4,E_ACK=5,E_COUNT=6;
    reg [2:0] state;
    reg [383:0] frame,history_frame;
    reg [63:0] key,tag,history_tag;
    reg [15:0] width,height,declared_pixels,check_pixels;
    reg [8:0] obs_width,read_x;
    reg [7:0] obs_height,check_rows;
    reg [15:0] read_y,out_x,out_y;
    reg [7:0] reason,error_code;
    reg use_map,failed,read_owned,read_end,output_end,close_cancel_locked;
    reg [31:0] read_groups,out_groups,out_pixels;
    reg look_valid,active_valid;
    reg [7:0] look_cells,active_cells;
    reg [3:0] active_keep;
    reg [2:0] phase;
    reg output_valid;
    reg [7:0] output_confidence;
    reg [3:0] output_keep,output_lane_valid;
    reg [2:0] output_markers;
    reg [31:0] output_index;
    reg [31:0] generated_groups;
    reg [3:0] look_keep;
    function [31:0] increment;
        input [31:0] n;begin increment=&n ? n : n+1'b1;end
    endfunction
    function [2:0] lanes;
        input [3:0] keep;
        begin lanes={2'd0,keep[0]}+{2'd0,keep[1]}+{2'd0,keep[2]}+{2'd0,keep[3]};end
    endfunction
    function [1:0] conservative;
        input [1:0] confidence;
        begin conservative=confidence==3 ? 2 : confidence==2 ? 1 : 0;end
    endfunction
    wire [15:0] declared_width=start_frame[220:205],declared_height=start_frame[236:221];
    wire bad_start=declared_width==0||declared_width>MAX_WIDTH||declared_height==0||declared_height>MAX_HEIGHT||start_tag==0;
    wire same_attributes=start_frame[4:1]==start_history_frame[4:1]&&
        start_frame[76:45]==start_history_frame[76:45]&&start_frame[140:109]==start_history_frame[140:109]&&
        start_frame[334:205]==start_history_frame[334:205];
    wire known_current=start_frame[0]&&start_frame[383:367]==0&&start_frame[12:5]<SLOTS_PER_CAMERA&&
        start_frame[44:13]!=0&&start_frame[76:45]!=0&&start_frame[302:271]!=0&&start_frame[2:1]!=3&&
        (start_frame[238:237]==1||start_frame[238:237]==2);
    wire known_history=start_history_frame[0]&&start_history_frame[383:367]==0&&
        start_history_frame[12:5]<SLOTS_PER_CAMERA&&start_history_frame[44:13]!=0&&
        start_history_frame[76:45]!=0&&start_history_frame[302:271]!=0&&start_history_frame[2:1]!=3&&
        (start_history_frame[238:237]==1||start_history_frame[238:237]==2);
    wire [15:0] native_map_width=({7'd0,map_width}<<2)+({7'd0,map_width}<<1);
    wire [15:0] native_map_height=({8'd0,map_height}<<2)+({8'd0,map_height}<<1);
    reg [7:0] start_reason;
    always @* begin
        start_reason=0;
        start_reason[0]=!map_committed||!f26_success||!f26_temporal_trust||!nr_history_available;
        start_reason[1]=map_frame!=start_frame||map_history_frame!=start_history_frame;
        start_reason[2]=map_key!=start_key||map_tag==0||map_history_tag==0||
            start_tag!={32'd0,map_tag}||start_history_tag!={32'd0,map_history_tag};
        start_reason[3]=!same_attributes;
        start_reason[4]=start_history_frame[108:77]==32'hffffffff||
            start_frame[108:77]!=start_history_frame[108:77]+32'd1||
            start_frame[204:141]<=start_history_frame[204:141];
        start_reason[5]=global_change||brightness_change;
        start_reason[6]=map_width==0||map_width>320||map_height==0||map_height>180||
            declared_width!=native_map_width||declared_height!=native_map_height;
        start_reason[7]=!known_current||!known_history;
    end
    assign start_ready=rst_n&&reader_reset_done&&state==IDLE;
    assign plan_valid=rst_n&&state==PLAN;
    assign plan_use_map=use_map;
    assign o_frame=frame;assign o_history_frame=history_frame;
    assign o_key=key;assign o_tag=tag;assign o_history_tag=history_tag;
    assign o_map_width=obs_width;assign o_map_height=obs_height;
    // Admission uses only registered lookahead credit. No output-ready path
    // returns to reader-ready; six phases leave ample time to refill one cell.
    assign map_ready=rst_n&&read_owned&&((state==RUN&&!read_end&&!look_valid&&!failed&&!cancel&&!read_error)||failed);
    wire map_fire=map_valid&&map_ready;
    wire [9:0] remaining_cells={1'b0,obs_width}-{1'b0,read_x};
    wire [3:0] expected_map_keep=remaining_cells>=4 ? 4'hf : remaining_cells==3 ? 4'h7 : remaining_cells==2 ? 4'h3 : 4'h1;
    wire row_map_last={1'b0,read_x}+10'd4>={1'b0,obs_width};
    wire frame_map_last=row_map_last&&read_y+1'b1==height;
    wire map_good=map_keep==expected_map_keep&&map_index==read_groups&&map_stream_tag==tag&&
        map_sof==(read_groups==0)&&map_eol==row_map_last&&map_last==frame_map_last;
    wire advance=!output_valid||motion_ready;
    assign motion_valid=rst_n&&output_valid;
    assign motion_confidence=output_confidence;assign motion_keep=output_keep;
    assign motion_lane_valid=output_lane_valid;
    assign {motion_sof,motion_eol,motion_last}=output_markers;
    assign motion_index=output_index;
    assign abort_request=rst_n&&failed&&use_map&&state!=IDLE;
    assign close_valid=rst_n&&state==CLOSE;
    assign close_cancel=close_cancel_locked;
    assign ack_ready=rst_n&&state==ACK;
    assign status_valid=rst_n&&state==STATUS;
    assign status_qualified=status_kind==COMPLETE;
    assign status_bypass_reason=reason;
    wire ack_match=ack_frame==frame&&ack_key==key&&ack_tag==tag;
    wire [16:0] remaining_native={1'b0,width}-{1'b0,out_x};
    wire [3:0] next_keep=remaining_native>=4 ? 4'hf : remaining_native==3 ? 4'h7 : remaining_native==2 ? 4'h3 : 4'h1;
    wire next_eol={1'b0,out_x}+17'd4>={1'b0,width};
    wire next_last=next_eol&&out_y+1'b1==height;
    wire active_last=phase==5||(active_keep==1&&phase==1)||(active_keep==3&&phase==2)||(active_keep==7&&phase==4);
    integer lane,cell_select;
    reg [7:0] next_confidence;
    reg [3:0] next_lane_valid;
    always @* begin
        next_confidence=0;next_lane_valid=0;cell_select=0;
        for(lane=0;lane<4;lane=lane+1) begin
            case(phase)
                0:cell_select=0;
                1:cell_select=lane<2 ? 0 : 1;
                2:cell_select=1;
                3:cell_select=2;
                4:cell_select=lane<2 ? 2 : 3;
                default:cell_select=3;
            endcase
            if(next_keep[lane]) begin
                next_confidence[lane*2+:2]=conservative(active_cells[cell_select*2+:2]);
                next_lane_valid[lane]=next_confidence[lane*2+:2]!=0;
            end
        end
    end
    task fail;
        input [7:0] code;
        begin
            failed<=1;if(!failed) error_code<=code;
            look_valid<=0;active_valid<=0;
        end
    endtask
    task publish;
        input [1:0] kind;input [7:0] code;
        begin
            state<=STATUS;status_kind<=kind;status_error<=code;
            if(kind==FAILED) begin failed<=1;if(!failed) error_code<=code;end
            status_map_groups<=read_groups;status_output_groups<=out_groups;status_output_pixels<=out_pixels;
            if(kind==COMPLETE) frames_projected<=increment(frames_projected);
            else if(kind==SKIPPED) frames_skipped<=increment(frames_skipped);
            else frames_failed<=increment(frames_failed);
        end
    endtask
    always @(posedge clk) begin
        if(!rst_n) begin
            state<=IDLE;output_valid<=0;active_valid<=0;look_valid<=0;read_owned<=0;
            stale_acks<=0;frames_projected<=0;frames_skipped<=0;frames_failed<=0;
            failed<=0;use_map<=0;reason<=0;status_kind<=SKIPPED;status_error<=0;
            status_map_groups<=0;status_output_groups<=0;status_output_pixels<=0;
        end else begin
            if(debug_clear) begin stale_acks<=0;frames_projected<=0;frames_skipped<=0;frames_failed<=0;end
            if(output_valid&&motion_ready) begin
                output_valid<=0;out_groups<=out_groups+1'b1;out_pixels<=out_pixels+lanes(output_keep);
                if(output_markers[0]) output_end<=1;
            end
            if(map_fire) read_groups<=read_groups+1'b1;
            if((read_owned||state==CHECK||state==PLAN)&&cancel&&state!=STATUS) fail(E_CANCEL);
            else if(read_owned&&read_error&&state!=STATUS) fail(E_READ);
            case(state)
                IDLE:if(start_valid&&start_ready) begin
                    frame<=start_frame;history_frame<=start_history_frame;key<=start_key;tag<=start_tag;history_tag<=start_history_tag;
                    width<=declared_width;height<=declared_height;obs_width<=map_width;obs_height<=map_height;declared_pixels<=map_full_pixels;
                    reason<=start_reason;check_pixels<=0;check_rows<=0;read_groups<=0;out_groups<=0;out_pixels<=0;
                    generated_groups<=0;read_x<=0;read_y<=0;out_x<=0;out_y<=0;phase<=0;
                    read_end<=0;output_end<=0;failed<=0;error_code<=0;read_owned<=0;
                    output_valid<=0;active_valid<=0;look_valid<=0;
                    if(bad_start) begin
                        state<=STATUS;status_kind<=FAILED;status_error<=E_START;status_map_groups<=0;status_output_groups<=0;status_output_pixels<=0;
                        frames_failed<=increment(frames_failed);
                    end else state<=CHECK;
                end
                CHECK:begin
                    // Geometry qualification counts declared sparse rows with
                    // an adder, not an inferred variable multiplier/DSP.
                    if(reason!=0) begin use_map<=0;state<=PLAN;end
                    else if(check_rows==obs_height) begin
                        if(check_pixels!=declared_pixels) begin reason[0]<=1;use_map<=0;end else use_map<=1;
                        state<=PLAN;
                    end else begin check_pixels<=check_pixels+obs_width;check_rows<=check_rows+1'b1;end
                end
                PLAN:if(plan_valid&&plan_ready) begin
                    if(!use_map) begin
                        if(failed||cancel) publish(FAILED,failed ? error_code : E_CANCEL);else publish(SKIPPED,0);
                    end
                    else begin read_owned<=1;state<=RUN;end
                end
                RUN:begin
                    if(map_fire) begin
                        if(map_last) read_end<=1;
                        if(!failed&&!cancel&&!read_error) begin
                            if(!map_good) fail(E_MAP);
                            else begin
                                look_valid<=1;look_cells<=map_confidence;look_keep<=map_keep;
                                if(row_map_last) begin read_x<=0;read_y<=read_y+1'b1;end else read_x<=read_x+9'd4;
                            end
                        end
                    end
                    if(!failed&&!cancel&&!read_error&&!(map_fire&&!map_good)) begin
                        if(!active_valid&&look_valid) begin
                            active_valid<=1;active_cells<=look_cells;active_keep<=look_keep;look_valid<=0;phase<=0;
                        end
                        if(advance&&active_valid) begin
                            output_valid<=1;output_confidence<=next_confidence;output_lane_valid<=next_lane_valid;output_keep<=next_keep;
                            output_markers<={generated_groups==0,next_eol,next_last};output_index<=generated_groups;
                            generated_groups<=generated_groups+1'b1;
                            if(next_eol) begin out_x<=0;out_y<=out_y+1'b1;end else out_x<=out_x+16'd4;
                            if(active_last) begin
                                phase<=0;
                                if(look_valid) begin active_cells<=look_cells;active_keep<=look_keep;look_valid<=0;end else active_valid<=0;
                            end else phase<=phase+1'b1;
                        end
                    end
                    if((failed||cancel||read_error)&&!output_valid) begin state<=CLOSE;close_cancel_locked<=1;end
                    else if(!failed&&output_end&&!output_valid&&!active_valid&&!look_valid) begin
                        if(read_end) begin state<=CLOSE;close_cancel_locked<=0;end
                        else begin fail(E_COUNT);state<=CLOSE;close_cancel_locked<=1;end
                    end
                end
                CLOSE:if(close_valid&&close_ready) state<=ACK;
                ACK:if(ack_valid&&ack_ready) begin
                    if(!ack_match) stale_acks<=increment(stale_acks);
                    else if(!ack_quiescent||map_valid) begin fail(E_ACK);end
                    else begin
                        read_owned<=0;
                        if(failed||cancel||read_error) publish(FAILED,failed ? error_code : cancel ? E_CANCEL : E_READ);
                        else if(!ack_ok||ack_groups!=read_groups||!output_end||!read_end) publish(FAILED,!ack_ok ? E_READ : E_COUNT);
                        else publish(COMPLETE,0);
                    end
                end
                STATUS:if(status_valid&&status_ready) state<=IDLE;
                default:begin
                    // Corrupt control cannot release a real reader reference.
                    if(read_owned) begin fail(E_READ);state<=RUN;end
                    else begin state<=IDLE;output_valid<=0;active_valid<=0;look_valid<=0;end
                end
            endcase
        end
    end
endmodule
