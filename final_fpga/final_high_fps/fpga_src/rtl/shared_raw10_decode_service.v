`timescale 1ns/1ps
`default_nettype none
// One DFI RAW10 reservoir. The two existing readers retain AXI promises,
// descriptors, DATA/FENCE holding and result ownership. A core terminal is
// private: kind cannot change until the selected reader's real result handshake.
module shared_raw10_decode_service #(
    parameter integer WIDTH=1920, HEIGHT=1080,
    parameter integer UHD_WIDTH=0, UHD_HEIGHT=0
)(
    input wire clk, rst_n,
    input wire hdr_start_valid, output wire hdr_start_ready,
    input wire hdr_release, input wire [1:0] hdr_abort,
    input wire hdr_member, input wire [127:0] hdr_data,
    input wire [15:0] hdr_keep, input wire hdr_valid, hdr_last,
    output wire hdr_ready,
    output wire hdr_raw_member, output wire [39:0] hdr_raw,
    output wire hdr_raw_valid, input wire hdr_raw_ready,
    output wire [1:0] hdr_done, hdr_aborted,
    input wire stereo_start_valid, output wire stereo_start_ready,
    input wire stereo_release, stereo_cancel, stereo_run,
    input wire [127:0] stereo_data, input wire [15:0] stereo_keep,
    input wire stereo_valid, stereo_last, output wire stereo_ready,
    output wire [39:0] stereo_raw, output wire stereo_raw_valid,
    input wire stereo_raw_ready, output wire stereo_sof, stereo_eol,
    output wire stereo_done, stereo_aborted, stereo_quiet, stereo_active,
    output wire quiet,
    // Borrowed with the SDR START request. HDR always uses the base geometry.
    input wire stereo_uhd
);
    localparam UHD_ENABLED=UHD_WIDTH!=0||UHD_HEIGHT!=0;
    localparam integer GROUPS=WIDTH*HEIGHT/4, FRAME_BYTES=GROUPS*5;
    localparam integer UHD_GROUPS=UHD_WIDTH/4*UHD_HEIGHT, UHD_FRAME_BYTES=UHD_GROUPS*5;
    localparam integer ROW_GROUPS=WIDTH/4, UHD_ROW_GROUPS=UHD_WIDTH/4;
    localparam integer MAX_BYTES=UHD_FRAME_BYTES>FRAME_BYTES?UHD_FRAME_BYTES:FRAME_BYTES;
    localparam integer MAX_GROUPS=UHD_GROUPS>GROUPS?UHD_GROUPS:GROUPS;
    localparam integer MAX_ROW_GROUPS=UHD_ROW_GROUPS>ROW_GROUPS?UHD_ROW_GROUPS:ROW_GROUPS;
    function integer count_width;
        input integer maximum;
        integer value;
        begin
            value=maximum;count_width=0;
            while(value>0)begin count_width=count_width+1;value=value>>1;end
            if(count_width==0)count_width=1;
        end
    endfunction
    // Include the accepted/emitted terminal count itself, not just max index.
    localparam integer BYTE_COUNT_WIDTH=MAX_BYTES>0?count_width(MAX_BYTES):32;
    localparam integer GROUP_COUNT_WIDTH=MAX_GROUPS>0?count_width(MAX_GROUPS):32;
    // Keep the original contract for geometry outside the old 16-bit column.
    localparam integer COLUMN_WIDTH=(MAX_ROW_GROUPS>0 && MAX_ROW_GROUPS<=65536)?count_width(MAX_ROW_GROUPS-1):16;
    localparam [COLUMN_WIDTH-1:0] LAST_COLUMN=ROW_GROUPS-1, UHD_LAST_COLUMN=UHD_ROW_GROUPS-1;
    // Keep local reset assertion immediate while beginning ready/grant
    // qualification on a positive edge. Only cold startup gains one edge.
    (* preserve="true" *) reg ready_run;
    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)ready_run<=1'b0;
        else ready_run<=1'b1;
    end
    reg owned, selected_hdr, stereo_pending, stereo_cancelled, frame_uhd;
    reg [COLUMN_WIDTH-1:0] column;
    wire core_idle, core_ready, core_member, core_valid;
    wire [39:0] core_raw;
    wire [31:0] emitted0;
    wire [1:0] core_done, core_abort;
    wire core_clean=core_idle && !(|core_done) && !(|core_abort);
    // Neither request depends on its grant. The readers present only their
    // local eligible request; this priority therefore has no ready/start loop.
    wire available=ready_run && !owned && !stereo_pending && core_clean;
    assign hdr_start_ready=available;
    assign stereo_start_ready=available && !hdr_start_valid;
    wire start_hdr=hdr_start_valid && hdr_start_ready;
    wire start_stereo=stereo_start_valid && stereo_start_ready;
    wire discard=owned && !selected_hdr &&
        (stereo_cancelled || stereo_cancel || !stereo_run);
    wire [1:0] abort_request=selected_hdr ? hdr_abort : {1'b0,discard};
    assign quiet=available && !start_hdr && !start_stereo;
    assign hdr_ready=owned && selected_hdr && core_ready;
    assign hdr_raw_member=core_member;
    assign hdr_raw=core_raw;
    assign hdr_raw_valid=owned && selected_hdr && core_valid;
    assign hdr_done=owned && selected_hdr ? core_done : 2'b00;
    assign hdr_aborted=owned && selected_hdr ? core_abort : 2'b00;
    assign stereo_ready=owned && !selected_hdr && core_ready && !discard;
    assign stereo_raw=core_raw;
    assign stereo_raw_valid=owned && !selected_hdr && core_valid && !discard;
    assign stereo_sof=emitted0==0;
    assign stereo_eol=column==(frame_uhd?UHD_LAST_COLUMN:LAST_COLUMN);
    assign stereo_done=owned && !selected_hdr && core_done[0];
    assign stereo_aborted=owned && !selected_hdr && core_abort[0];
    assign stereo_quiet=core_clean && !stereo_pending;
    // The outer grant precedes the core START by one clock. Report the core
    // context itself, including drain, until the separate terminal pulse.
    assign stereo_active=owned && !selected_hdr && !core_idle;
    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)begin
            owned<=0;selected_hdr<=0;stereo_pending<=0;stereo_cancelled<=0;frame_uhd<=0;column<=0;
        end else begin
            stereo_pending<=0;
            if(start_hdr || start_stereo)begin
                owned<=1;selected_hdr<=start_hdr;stereo_pending<=start_stereo;
                stereo_cancelled<=start_stereo && stereo_cancel;column<=0;
                frame_uhd<=start_stereo && UHD_ENABLED && stereo_uhd;
            end else if(owned)begin
                if(!selected_hdr && (stereo_cancel || !stereo_run))stereo_cancelled<=1;
                if(stereo_raw_valid && stereo_raw_ready)
                    column<=stereo_eol ? {COLUMN_WIDTH{1'b0}} : column+1'b1;
                if(core_clean && (selected_hdr ? hdr_release : stereo_release))owned<=0;
            end
        end
    end
    wire start_uhd=stereo_pending&&frame_uhd;
    shared_raw10_decoder_masked #(
        .BYTE_COUNT_WIDTH(BYTE_COUNT_WIDTH),.GROUP_COUNT_WIDTH(GROUP_COUNT_WIDTH)
    ) u_decoder(
        .i_clk(clk),.i_rst_n(rst_n),
        // HDR starts on its original edge; stereo retains the reader's START
        // cycle after outer acceptance, exactly as its standalone decoder did.
        .i_start(start_hdr || stereo_pending),
        .i_member_mask(stereo_pending ? 2'b01 : 2'b11),
        .i_total_bytes(start_uhd?UHD_FRAME_BYTES:FRAME_BYTES),
        .i_total_groups(start_uhd?UHD_GROUPS:GROUPS),
        .i_abort(abort_request),.o_idle(core_idle),.o_emitted0(emitted0),
        .i_axis_member(selected_hdr ? hdr_member : 1'b0),
        .i_axis_data(selected_hdr ? hdr_data : stereo_data),
        .i_axis_keep(selected_hdr ? hdr_keep : stereo_keep),
        .i_axis_valid(owned && (selected_hdr ? hdr_valid : stereo_valid && !discard)),
        .i_axis_last(selected_hdr ? hdr_last : stereo_last),.o_axis_ready(core_ready),
        .o_member(core_member),.o_data(core_raw),.o_valid(core_valid),
        .i_ready(selected_hdr ? hdr_raw_ready : discard || stereo_raw_ready),
        .o_done(core_done),.o_abort(core_abort));
endmodule
`default_nettype wire
