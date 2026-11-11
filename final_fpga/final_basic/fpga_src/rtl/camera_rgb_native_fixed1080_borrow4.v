// Fixed production overlay. See CONTRACT.md and SOURCE.json.
`timescale 1ns / 1ps

// A single held native beat separates camera abort from the published stream.
module camera_rgb_native_fixed1080_borrow4 #(
    parameter integer MAX_WIDTH=1920,
    parameter integer MAX_HEIGHT=1080
) (
    input wire clk,rst_n,
    input wire [575:0] s_context,input wire s_context_valid,output wire s_context_ready,
    input wire [95:0] s_rgb,input wire s_valid,output wire s_ready,
    input wire s_sof,s_eol,
    input wire i_cancel,i_pipeline_error,i_pipeline_quiescent,i_source_read_quiescent,
    input wire i_source_status_valid,output wire o_source_status_ready,
    input wire [63:0] i_source_status_tag,input wire i_source_status_ok,
    input wire [7:0] i_source_status_error,
    output wire [575:0] m_context,output wire m_context_valid,input wire m_context_ready,
    output wire [95:0] m_rgb,output wire [3:0] m_keep,
    output wire m_sof,m_eol,m_last,m_valid,input wire m_ready,
    output wire [63:0] m_tag,output wire [31:0] m_index,
    output wire m_status_valid,input wire m_status_ready,
    output wire [63:0] m_status_tag,output wire m_status_ok,
    output wire [7:0] m_status_error,output wire [31:0] m_status_groups,
    output wire o_read_quiescent,o_busy,o_cancel_request,
    output wire [31:0] o_input_groups,o_output_groups,
    output wire [31:0] o_stale_status_count
);
    generate if(MAX_WIDTH!=1920 || MAX_HEIGHT!=1080)begin:g_bad_profile
        FIXED_RGB_BORROW_REQUIRES_MONO_1920_1080 invalid_geometry();
    end endgenerate
    localparam [1:0] IDLE=0,CONTEXT=1,STREAM=2,STATUS=3;
    localparam [7:0] E_CONTEXT=1,E_RASTER=2,E_CANCEL=3,E_PIPELINE=4,E_LENGTH=5,E_SOURCE=6;
    reg [1:0] state,state_next;
    // Parent holds this exact ticket-derived context until o_busy drops.
    wire [575:0] locked_context=s_context;
    reg [95:0] output_rgb;
    reg [3:0] output_keep;
    reg output_sof,output_eol,output_last,output_valid;
    reg [31:0] output_index,input_groups,output_groups,raster_groups,stale_status_count;
    // The validated fixed raster stops after x=1916/y=1079.
    // Counts below remain full-width actual handshakes, including error drains.
    reg [10:0] raster_x,raster_y;
    reg end_seen,failed,source_seen,source_ok,status_ok;
    reg [7:0] first_error,status_error;
    wire active=state==CONTEXT || state==STREAM;
    wire context_good=s_context[447:384]!=0 && s_context[220:205]==16'd1920 &&
        s_context[236:221]==16'd1080;
    wire status_match=i_source_status_tag==locked_context[447:384];
    wire source_status_fire=i_source_status_valid && o_source_status_ready;
    wire source_failure=source_status_fire && status_match && !source_seen &&
        (!i_source_status_ok || i_source_status_error!=0);
    wire stop_output=failed || i_cancel || i_pipeline_error || source_failure;
    wire output_fire=m_valid && m_ready;
    wire output_room=!output_valid || output_fire;
    wire row_last=raster_x==11'd1916;
    wire frame_last=row_last && raster_y==11'd1079;
    wire word_bad=end_seen || s_sof!=(raster_groups==0) || s_eol!=row_last;
    wire input_fire=s_valid && s_ready;
    wire [3:0] row_keep=4'hf;
    wire closure=state==STREAM && source_seen && i_pipeline_quiescent &&
        i_source_read_quiescent && !s_valid && !output_valid;
    // Data is meaningful only with the held output valid. Keep asynchronous
    // reset on ownership/validity, not on the96 payload FFs: the first valid
    // beat always loads its own RGB, including after a stopped-clock reset.
    always @(posedge clk)begin
        if(active&&s_valid&&output_room&&!stop_output&&!word_bad)output_rgb<=s_rgb;
    end

    assign s_context_ready=rst_n && state==IDLE;
    assign m_context=locked_context;
    assign m_context_valid=rst_n && state==CONTEXT;
    assign s_ready=rst_n && active && (stop_output || end_seen || output_room);
    assign o_source_status_ready=rst_n && active;
    assign m_rgb=output_rgb;assign m_keep=output_keep;
    assign m_sof=output_sof;assign m_eol=output_eol;assign m_last=output_last;
    assign m_valid=rst_n && state==STREAM && output_valid;
    assign m_index=output_index;assign m_tag=locked_context[447:384];
    assign m_status_valid=rst_n && state==STATUS;
    assign m_status_tag=locked_context[447:384];assign m_status_ok=status_ok;
    assign m_status_error=status_error;assign m_status_groups=output_groups;
    assign o_read_quiescent=m_status_valid;
    assign o_busy=state!=IDLE;assign o_cancel_request=active && stop_output;
    assign o_input_groups=input_groups;assign o_output_groups=output_groups;
    assign o_stale_status_count=stale_status_count;

    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) state<=IDLE;
        else state<=state_next;
    end
    always @(*) begin
        state_next=state;
        case(state)
            IDLE: if(s_context_valid && s_context_ready) state_next=CONTEXT;
            CONTEXT: if(m_context_valid && m_context_ready) state_next=STREAM;
            STREAM: if(closure) state_next=STATUS;
            STATUS: if(m_status_valid && m_status_ready) state_next=IDLE;
            default: state_next=IDLE;
        endcase
    end

    // Cancellation poisons future production, never the register already held.
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            output_keep<=0;output_sof<=0;output_eol<=0;
            output_last<=0;output_valid<=0;output_index<=0;input_groups<=0;output_groups<=0;
            raster_groups<=0;raster_x<=0;raster_y<=0;end_seen<=0;failed<=0;
            source_seen<=0;source_ok<=0;status_ok<=0;first_error<=0;status_error<=0;stale_status_count<=0;
        end else begin
            if(s_context_valid && s_context_ready) begin
                output_valid<=0;input_groups<=0;output_groups<=0;
                raster_groups<=0;raster_x<=0;raster_y<=0;end_seen<=0;
                failed<=!context_good;first_error<=context_good ? 8'd0 : E_CONTEXT;
                source_seen<=0;source_ok<=0;status_ok<=0;status_error<=0;
            end
            if(output_fire) begin output_valid<=0;output_groups<=output_groups+1'b1;end
            if(active) begin
                if(i_cancel || i_pipeline_error || source_failure) begin
                    failed<=1;
                    if(!failed) first_error<=i_cancel ? E_CANCEL : i_pipeline_error ? E_PIPELINE :
                        i_source_status_error!=0 ? i_source_status_error : E_SOURCE;
                end
                if(source_status_fire) begin
                    if(!status_match || source_seen) begin
                        if(!(&stale_status_count)) stale_status_count<=stale_status_count+1'b1;
                    end else begin source_seen<=1;source_ok<=i_source_status_ok && i_source_status_error==0;end
                end
                if(input_fire) begin
                    input_groups<=input_groups+1'b1;
                    if(!stop_output && word_bad) begin
                        failed<=1;if(!failed) first_error<=E_RASTER;
                    end
                    if(!stop_output && !word_bad) begin
                        output_keep<=row_keep;output_sof<=s_sof;output_eol<=s_eol;
                        output_last<=frame_last;output_index<=raster_groups;output_valid<=1;
                        raster_groups<=raster_groups+1'b1;end_seen<=frame_last;
                        if(row_last) begin raster_x<=0;raster_y<=raster_y+1'b1;end
                        else raster_x<=raster_x+11'd4;
                    end
                end
            end
            if(closure) begin
                status_ok<=source_ok && end_seen && !stop_output;
                status_error<=stop_output ? (first_error!=0 ? first_error :
                    i_cancel ? E_CANCEL : i_pipeline_error ? E_PIPELINE : E_SOURCE) :
                    !end_seen ? E_LENGTH : 8'd0;
            end
        end
    end
endmodule
