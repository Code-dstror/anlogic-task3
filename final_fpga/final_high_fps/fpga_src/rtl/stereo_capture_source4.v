`timescale 1ns/1ps
`default_nettype none

// One physical eye: passive cropped RAW4 admission plus authenticated SOURCE.
// No ISP/native pixel owner is created. Native fence status is consumed locally.
module stereo_capture_source4 #(
    parameter integer CAMERA_ID=0,
    parameter integer WIDTH=1920,
    parameter integer HEIGHT=1080,
    parameter integer TAG_WIDTH=32,
    parameter integer SEPARATE_DATA_RESET=0,
    parameter integer FS_CADENCE_ENABLE=0,
    parameter integer UHD_WIDTH=0, UHD_HEIGHT=0
)(
    input wire clk, rst_n, i_enable,
    input wire [31:0] i_session, i_epoch,
    input wire [63:0] i_time_ns,
    input wire i_time_valid,
    input wire [39:0] i_data,
    input wire i_valid, i_accept, i_sof, i_eol, i_abort,
    input wire [31:0] i_sequence,
    input wire i_identity_valid,
    input wire i_event_valid,
    output wire o_event_ready,
    input wire [1:0] i_event_kind,
    input wire i_event_ok,
    input wire [3:0] i_event_error,
    input wire [31:0] i_event_sequence,
    input wire i_event_identity_valid,
    input wire i_receive_fault, i_identity_quarantine,
    output wire [39:0] o_capture_data,
    output wire o_capture_valid, o_capture_accept, o_capture_sof, o_capture_eol,
    output wire o_capture_abort, o_capture_geometry_done,
    output wire [31:0] o_capture_session, o_capture_epoch, o_capture_sequence,
    output wire [196:0] o_capture_metadata,
    output wire o_raw_source_valid,
    input wire i_raw_source_ready,
    output wire [31:0] o_raw_source_session, o_raw_source_epoch, o_raw_source_sequence,
    output wire o_raw_source_camera, o_raw_source_ok,
    output wire [7:0] o_raw_source_error,
    output wire o_idle, o_fault,
    // Same logical PIX reset as rst_n; local copy only for data masks.
    input wire i_data_reset_n,
    // Cold PIX configuration; applies to the next true trusted FS only.
    // Legacy/default callers retain capture-all behavior.
    input wire [7:0] i_frame_divisor,
    // Committed CAM0 SDR profile. Freeze it at the authenticated sensor FS.
    input wire i_uhd
);
    localparam integer GROUPS_PER_ROW=WIDTH/4;
    localparam UHD_ENABLED=UHD_WIDTH!=0||UHD_HEIGHT!=0;
    generate if((CAMERA_ID!=0&&CAMERA_ID!=1)||WIDTH<4||WIDTH%4!=0||
                HEIGHT<1||WIDTH>65532||HEIGHT>65535||TAG_WIDTH<1||TAG_WIDTH>64||
                (UHD_ENABLED&&CAMERA_ID!=0))begin:g_invalid
        STEREO_SOURCE_REQUIRES_VALID_CAMERA_RAW4_GEOMETRY_AND_FINITE_TAG invalid_configuration();
    end endgenerate

    wire fence_event_ready, fence_context_ready, fence_capture, fence_idle;
    wire router_idle, router_fault, router_eof;
    reg [31:0] frame_session, frame_epoch, frame_sequence;
    reg [63:0] frame_time;
    reg [TAG_WIDTH-1:0] tag_count, frame_tag;
    reg registered_frame, continuity_failed, geometry_failed, terminal_observed, capture_active;
    reg frame_uhd;
    wire tag_exhausted=&tag_count;
    wire admission_allowed=i_enable&&i_time_valid&&!tag_exhausted&&!router_fault&&
        !i_receive_fault&&!i_identity_quarantine;
    reg [7:0] fs_phase,fs_last_divisor;
    wire cadence_changed=i_frame_divisor!=fs_last_divisor;
    wire cadence_select=FS_CADENCE_ENABLE==0||
        (i_frame_divisor!=0&&(cadence_changed||fs_phase==0)&&i_event_ok&&i_event_error==0);
    wire admit_enable=admission_allowed&&cadence_select;

    // The physical producer never waits indefinitely for SOURCE retirement.
    // A next FS while the previous owner is busy is discarded, not held at
    // the RX FIFO head. Exact sequence filtering discards that frame's crop.
    wire data_reset_n=SEPARATE_DATA_RESET!=0 ? i_data_reset_n : rst_n;
    assign o_event_ready=data_reset_n;
    wire event_fire=i_event_valid&&o_event_ready;
    // Phase advances on the real identity event even if the previous SOURCE
    // still owns its fence. Busy/drop cannot create a second divide-by-N.
    wire trusted_fs=event_fire&&i_event_kind==0&&i_event_identity_valid&&
        i_event_ok&&i_event_error==0;
    wire fence_event_valid=i_event_valid&&fence_event_ready;
    wire admitted_fs=event_fire&&fence_event_ready&&i_event_kind==0&&
        i_event_identity_valid&&admit_enable;
    wire busy_fs=event_fire&&i_event_kind==0&&!fence_event_ready;
    wire matching_terminal=event_fire&&fence_event_ready&&fence_capture&&
        (i_event_kind==1||i_event_kind==2)&&i_event_identity_valid&&i_event_sequence==frame_sequence;
    wire missing_terminal=busy_fs&&fence_capture&&!terminal_observed;
    wire raw_identity_lost=fence_capture&&registered_frame&&capture_active&&i_valid&&i_accept&&
        (!i_identity_valid||i_sequence!=frame_sequence);
    wire continuity_fault=continuity_failed||i_receive_fault||i_identity_quarantine||missing_terminal||raw_identity_lost;

    // Snapshot at true sensor FS, before crop latency and independently of
    // later configuration writes. Time is known; exposure/gain/calibration,
    // exposure grouping/role and measurement qualification remain UNKNOWN.
    wire [159:0] active_config={frame_epoch,64'd0,frame_session,32'd0};
    wire [196:0] metadata={4'd0,1'b1,128'd0,frame_time};
    wire owner_match=fence_capture&&registered_frame&&i_identity_valid&&i_sequence==frame_sequence;
    wire router_input_valid=i_valid&&owner_match;
    wire capture_permit=fence_capture&&registered_frame&&!continuity_fault&&!geometry_failed;
    wire router_abort=i_abort||continuity_fault||geometry_failed;
    physical_capture_router #(.WIDTH(WIDTH),.HEIGHT(HEIGHT),.UHD_WIDTH(UHD_WIDTH),.UHD_HEIGHT(UHD_HEIGHT)) u_router(
        .clk(clk),.rst_n(rst_n),.i_future_enable(capture_permit),.i_initialized(1'b1),
        .i_uhd(frame_uhd),
        .i_active_config(active_config),.i_data(i_data),.i_valid(router_input_valid),
        .i_accept(i_accept),.i_sof(i_sof),.i_eol(i_eol),.i_abort(router_abort),
        .i_source_sequence(i_sequence),.i_source_identity_valid(i_identity_valid),.i_metadata(metadata),
        .o_data(o_capture_data),.o_valid(o_capture_valid),.o_accept(o_capture_accept),
        .o_sof(o_capture_sof),.o_eol(o_capture_eol),.o_eof(router_eof),
        .o_abort(o_capture_abort),.o_frame_idle(router_idle),
        .o_session(o_capture_session),.o_epoch(o_capture_epoch),.o_sequence(o_capture_sequence),
        .o_metadata(o_capture_metadata),.o_fault(router_fault));

    wire capture_fire=o_capture_valid&&o_capture_accept;
    reg [15:0] group_in_row, row_index;
    wire [15:0] current_group=o_capture_sof?16'd0:group_in_row;
    wire [15:0] current_row=o_capture_sof?16'd0:row_index;
    localparam [15:0] LAST_GROUP=GROUPS_PER_ROW-1, UHD_LAST_GROUP=UHD_WIDTH/4-1;
    localparam [15:0] LAST_ROW=HEIGHT-1, UHD_LAST_ROW=UHD_HEIGHT-1;
    wire last_group=current_group==(frame_uhd?UHD_LAST_GROUP:LAST_GROUP);
    wire [15:0] final_row=frame_uhd?UHD_LAST_ROW:LAST_ROW;
    wire correct_eol=o_capture_eol==last_group;
    wire geometry_error=capture_fire&&(!correct_eol||current_row>final_row||
        (router_eof&&(current_row!=final_row||!last_group)));
    assign o_capture_geometry_done=router_eof&&!geometry_failed&&!geometry_error&&!continuity_fault;

    // Both independent fence tails describe this one RAW capture. There is
    // no RGB pipeline here. Quiet includes the live crop presentation so an
    // accepted FE never races a held cropped group that has not been drained.
    wire crop_quiet=router_idle&&!i_valid&&!i_abort;
    wire context_valid=capture_fire&&o_capture_sof;
    wire [575:0] source_capsule={414'd0,1'b1,(CAMERA_ID==1),frame_time,
        frame_epoch,frame_session,frame_sequence};
    wire [63:0] source_tag={{(64-TAG_WIDTH){1'b0}},frame_tag};
    wire native_valid,native_ok;
    wire [7:0] native_error;
    wire [575:0] native_context;
    wire [63:0] native_tag;
    physical_identity_source_fence #(.SEPARATE_DATA_RESET(SEPARATE_DATA_RESET)) u_fence(
        .i_clk(clk),.i_rst_n(rst_n),.i_data_reset_n(data_reset_n),.i_admit_enable(admit_enable),
        .i_event_valid(fence_event_valid),.o_event_ready(fence_event_ready),
        .i_event_kind(i_event_kind),.i_event_ok(i_event_ok),.i_event_error({4'd0,i_event_error}),
        .i_event_sequence(i_event_sequence),.i_event_identity_valid(i_event_identity_valid),
        .i_continuity_fault(continuity_fault),
        .i_context_valid(context_valid),.o_context_ready(fence_context_ready),
        .i_context(source_capsule),.i_context_tag(source_tag),
        .i_context_session(o_capture_session),.i_context_epoch(o_capture_epoch),
        .i_context_sequence(o_capture_sequence),.i_context_camera(CAMERA_ID==1),
        .i_crop_geometry_done(o_capture_geometry_done),.i_crop_input_quiet(crop_quiet),
        .i_rgb_geometry_done(o_capture_geometry_done),.i_rgb_output_quiet(crop_quiet),
        .i_source_fault(o_capture_abort||geometry_error||geometry_failed||router_fault||
            (context_valid&&!fence_context_ready)),.i_source_error(8'd1),
        .o_capture_frame_enable(fence_capture),.o_source_idle(fence_idle),
        .o_raw_source_valid(o_raw_source_valid),.i_raw_source_ready(i_raw_source_ready),
        .o_raw_source_session(o_raw_source_session),.o_raw_source_epoch(o_raw_source_epoch),
        .o_raw_source_sequence(o_raw_source_sequence),.o_raw_source_camera(o_raw_source_camera),
        .o_raw_source_ok(o_raw_source_ok),.o_raw_source_error(o_raw_source_error),
        .o_native_source_valid(native_valid),.i_native_source_ready(1'b1),
        .o_native_source_context(native_context),.o_native_source_tag(native_tag),
        .o_native_source_ok(native_ok),.o_native_source_error(native_error),
        .o_drop_count(),.o_stale_event_count());

    // Only admitted/held owners block global idle; unowned camera input is passive.
    // crop_quiet above still protects the terminal tail of an admitted frame.
    assign o_idle=fence_idle&&router_idle;
    assign o_fault=router_fault||tag_exhausted||i_identity_quarantine;
    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)begin
            frame_session<=0;frame_epoch<=0;frame_sequence<=0;frame_time<=0;
            tag_count<=0;frame_tag<=0;registered_frame<=0;
            frame_uhd<=0;
            continuity_failed<=0;geometry_failed<=0;terminal_observed<=0;
            group_in_row<=0;row_index<=0;capture_active<=0;
            fs_phase<=0;fs_last_divisor<=0;
        end else begin
            fs_last_divisor<=i_frame_divisor;
            if(FS_CADENCE_ENABLE!=0)begin
                if(cadence_changed)fs_phase<=0;
                if(trusted_fs)begin
                    if(i_frame_divisor==0||i_frame_divisor==1)fs_phase<=0;
                    else if(cadence_changed||fs_phase==0)fs_phase<=1;
                    else fs_phase<=fs_phase==i_frame_divisor-1?8'd0:fs_phase+1'b1;
                end
            end
            if(fence_idle)registered_frame<=0;
            if(fence_capture&&(i_receive_fault||i_identity_quarantine||missing_terminal||raw_identity_lost))begin
                continuity_failed<=1;terminal_observed<=1;
            end
            if(matching_terminal)terminal_observed<=1;
            if(geometry_error||(context_valid&&!fence_context_ready))geometry_failed<=1;
            if(o_capture_abort||router_eof)capture_active<=0;
            else if(capture_fire&&o_capture_sof)capture_active<=1;
            if(capture_fire)begin
                if(last_group)begin group_in_row<=0;row_index<=current_row+1'b1;end
                else begin group_in_row<=current_group+1'b1;row_index<=current_row;end
            end
            if(admitted_fs)begin
                frame_session<=i_session;frame_epoch<=i_epoch;frame_sequence<=i_event_sequence;frame_time<=i_time_ns;
                tag_count<=tag_count+1'b1;frame_tag<=tag_count+1'b1;registered_frame<=1;
                frame_uhd<=UHD_ENABLED&&i_uhd;
                continuity_failed<=0;geometry_failed<=0;terminal_observed<=0;
                group_in_row<=0;row_index<=0;capture_active<=0;
            end
        end
    end
endmodule
`default_nettype wire
