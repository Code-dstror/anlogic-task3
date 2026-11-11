`timescale 1ns / 1ps

// Own one true sensor FS through FE/ABORT and both independent source tails.
module physical_identity_source_fence #(
    parameter integer SEPARATE_DATA_RESET=0
) (
    input wire i_clk, i_rst_n, i_admit_enable,
    input wire i_event_valid,
    output wire o_event_ready,
    input wire [1:0] i_event_kind,
    input wire i_event_ok,
    input wire i_continuity_fault,
    input wire [7:0] i_event_error,
    input wire [31:0] i_event_sequence,input wire i_event_identity_valid,
    input wire i_context_valid,
    output wire o_context_ready,
    input wire [575:0] i_context,
    input wire [63:0] i_context_tag,
    input wire [31:0] i_context_session, i_context_epoch, i_context_sequence,
    input wire i_context_camera,
    input wire i_crop_geometry_done, i_crop_input_quiet,
    input wire i_rgb_geometry_done, i_rgb_output_quiet,
    input wire i_source_fault,
    input wire [7:0] i_source_error,
    output wire o_capture_frame_enable, o_source_idle,
    output wire o_raw_source_valid,
    input wire i_raw_source_ready,
    output wire [31:0] o_raw_source_session, o_raw_source_epoch, o_raw_source_sequence,
    output wire o_raw_source_camera, o_raw_source_ok,
    output wire [7:0] o_raw_source_error,
    output wire o_native_source_valid,
    input wire i_native_source_ready,
    output wire [575:0] o_native_source_context,
    output wire [63:0] o_native_source_tag,
    output wire o_native_source_ok,
    output wire [7:0] o_native_source_error,
    output wire [31:0] o_drop_count, o_stale_event_count,
    // Optional physical route for the same logical PIX reset. Storage keeps
    // i_rst_n on its original asynchronous reset network; only data masks
    // may use this pre-global-buffer copy. Default preserves legacy callers.
    input wire i_data_reset_n
);
    localparam [1:0] IDLE=2'd0, IGNORED=2'd1, OWNED=2'd2, FAULT=2'd3;
    localparam [1:0] FS=2'd0, FE=2'd1, ABORT=2'd2, DROPPED_UNANNOUNCED=2'd3;
    localparam [7:0] ERROR_SOURCE=8'd1, ERROR_GEOMETRY=8'd6;
    reg [1:0] state, state_next;
    reg context_seen, terminal_seen, crop_done, rgb_done;
    reg failed;
    reg [7:0] failure_code;
    reg [575:0] context_q;
    reg [63:0] tag_q;
    reg [31:0] session_q, epoch_q, sequence_q;
    reg [31:0] fs_sequence;
    wire terminal_identity_match=i_event_identity_valid && i_event_sequence==fs_sequence;
    reg camera_q;
    reg raw_valid, native_valid, raw_ok, native_ok;
    reg [7:0] raw_error, native_error;
    reg raw_issued, native_issued, raw_taken, native_taken;
    reg [31:0] drop_count, stale_count;
    wire event_fire=i_event_valid && o_event_ready;
    wire context_fire=i_context_valid && o_context_ready;
    wire context_identity_bad=context_fire && i_context_sequence!=fs_sequence;
    wire raw_fire=raw_valid && i_raw_source_ready;
    wire native_fire=native_valid && i_native_source_ready;
    wire new_owned=event_fire && i_event_kind==FS && i_admit_enable && i_event_identity_valid;
    wire terminal_event=event_fire && (i_event_kind==FE || i_event_kind==ABORT) &&
        state==OWNED && !terminal_seen && terminal_identity_match;
    wire terminal_bad=terminal_event &&
        (i_event_kind!=FE || !i_event_ok || |i_event_error);
    wire fault_now=failed || context_identity_bad || i_source_fault || i_continuity_fault || terminal_bad;
    wire [7:0] fault_code_now=failed ? failure_code : context_identity_bad ? 8'd7 :
        ((i_source_fault||i_continuity_fault) ? (i_source_error!=0 ? i_source_error : ERROR_SOURCE) :
        (i_event_error!=0 ? i_event_error : ERROR_SOURCE));
    wire dropped_event=event_fire && (i_event_kind==DROPPED_UNANNOUNCED ||
        (i_event_kind==FS && !i_event_identity_valid));
    wire dropped_owner=state==OWNED && state_next==IDLE &&
        (!context_seen || failed || !crop_done || !rgb_done);

    wire data_reset_n=SEPARATE_DATA_RESET!=0 ? i_data_reset_n : i_rst_n;
    assign o_event_ready=data_reset_n && state!=FAULT && (i_event_kind!=FS || state!=OWNED);
    assign o_context_ready=data_reset_n && state==OWNED && !context_seen && !raw_issued;
    assign o_capture_frame_enable=data_reset_n && state==OWNED;
    assign o_source_idle=data_reset_n && (state==IDLE || state==IGNORED) && !raw_valid && !native_valid;
    assign o_raw_source_valid=raw_valid;
    assign o_raw_source_session=session_q;
    assign o_raw_source_epoch=epoch_q;
    assign o_raw_source_sequence=sequence_q;
    assign o_raw_source_camera=camera_q;
    assign o_raw_source_ok=raw_ok;
    assign o_raw_source_error=raw_error;
    assign o_native_source_valid=native_valid;
    assign o_native_source_context=context_q;
    assign o_native_source_tag=tag_q;
    assign o_native_source_ok=native_ok;
    assign o_native_source_error=native_error;
    assign o_drop_count=drop_count;
    assign o_stale_event_count=stale_count;

    always @(*) begin
        state_next=state;
        case(state)
            IDLE,IGNORED: begin
                if(event_fire && i_event_kind==FS)
                    state_next=i_admit_enable && i_event_identity_valid ? OWNED : IGNORED;
                else if(state==IGNORED && event_fire &&
                    (i_event_kind==FE || i_event_kind==ABORT))
                    state_next=IDLE;
            end
            OWNED: begin
                if(terminal_seen && i_crop_input_quiet && i_rgb_output_quiet &&
                    ((!context_seen && !context_fire) || (raw_taken && native_taken)))
                    state_next=IDLE;
            end
            FAULT: state_next=FAULT;
            default: state_next=FAULT;
        endcase
    end

    always @(posedge i_clk or negedge i_rst_n) begin
        if(!i_rst_n) state<=IDLE;
        else state<=state_next;
    end

    always @(posedge i_clk or negedge i_rst_n) begin
        if(!i_rst_n) begin
            context_seen<=0;terminal_seen<=0;crop_done<=0;rgb_done<=0;
            failed<=0;failure_code<=0;context_q<=0;tag_q<=0;
            session_q<=0;epoch_q<=0;sequence_q<=0;camera_q<=0;fs_sequence<=0;
            raw_valid<=0;native_valid<=0;raw_ok<=0;native_ok<=0;
            raw_error<=0;native_error<=0;raw_issued<=0;native_issued<=0;
            raw_taken<=0;native_taken<=0;drop_count<=0;stale_count<=0;
        end else begin
            if(raw_fire) begin raw_valid<=0;raw_taken<=1;end
            if(native_fire) begin native_valid<=0;native_taken<=1;end
            if(dropped_event || dropped_owner) begin
                if(dropped_event && dropped_owner)
                    drop_count<=drop_count>=32'hfffffffe ? 32'hffffffff : drop_count+2'd2;
                else if(drop_count!=32'hffffffff) drop_count<=drop_count+1'b1;
            end
            if(event_fire && i_event_kind!=FS &&
                (state!=OWNED || terminal_seen || i_event_kind==2'd3 || !terminal_identity_match)) begin
                if(stale_count!=32'hffffffff) stale_count<=stale_count+1'b1;
            end
            if(state==OWNED) begin
                if(context_fire) begin
                    context_seen<=1;context_q<=i_context;tag_q<=i_context_tag;
                    session_q<=i_context_session;epoch_q<=i_context_epoch;
                    sequence_q<=i_context_sequence;camera_q<=i_context_camera;
                end
                if(i_crop_geometry_done) crop_done<=1;
                if(i_rgb_geometry_done) rgb_done<=1;
                if((context_identity_bad || i_source_fault || i_continuity_fault || terminal_bad) && !native_issued) begin
                    failed<=1;
                    if(!failed) failure_code<=fault_code_now;
                end
                if(terminal_event) terminal_seen<=1;
                // A sticky continuity failure is an authenticated negative
                // termination authority for this already owned FS. It never
                // fabricates FE/success, and still waits real crop/RGB quiet
                // plus the original independent SOURCE handshakes below.
                if(i_continuity_fault)terminal_seen<=1;
                if(terminal_seen && context_seen && i_crop_input_quiet && !raw_issued) begin
                    raw_issued<=1;raw_valid<=1;
                    raw_ok<=!fault_now && (crop_done || i_crop_geometry_done);
                    raw_error<=fault_now ? fault_code_now :
                        ((crop_done || i_crop_geometry_done) ? 8'd0 : ERROR_GEOMETRY);
                end
                if(terminal_seen && context_seen && raw_issued && i_crop_input_quiet &&
                    i_rgb_output_quiet && !native_issued) begin
                    native_issued<=1;native_valid<=1;
                    native_ok<=!fault_now && (crop_done || i_crop_geometry_done) &&
                               (rgb_done || i_rgb_geometry_done);
                    native_error<=fault_now ? fault_code_now :
                        (((crop_done || i_crop_geometry_done) && (rgb_done || i_rgb_geometry_done)) ?
                         8'd0 : ERROR_GEOMETRY);
                end
            end
            if(new_owned) begin
                fs_sequence<=i_event_sequence;
                context_seen<=0;terminal_seen<=0;crop_done<=0;rgb_done<=0;
                failed<=0;failure_code<=0;raw_valid<=0;native_valid<=0;
                raw_issued<=0;native_issued<=0;raw_taken<=0;native_taken<=0;
            end
        end
    end
endmodule
