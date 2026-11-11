`timescale 1ns/1ps
`default_nettype none
// Physical cropped-tap admission only. RX READY is owned by the caller.
module physical_capture_router #(
    parameter integer WIDTH=1920, HEIGHT=1080,
    parameter integer UHD_WIDTH=0, UHD_HEIGHT=0
) (
    input wire clk,rst_n,i_future_enable,i_initialized,
    input wire [159:0] i_active_config,
    input wire [39:0] i_data,
    input wire i_valid,i_accept,i_sof,i_eol,i_abort,
    input wire [31:0] i_source_sequence,input wire i_source_identity_valid,
    input wire [196:0] i_metadata,
    output wire [39:0] o_data,
    output wire o_valid,o_accept,o_sof,o_eol,o_eof,o_abort,o_frame_idle,
    output wire [31:0] o_session,o_epoch,o_sequence,
    output wire [196:0] o_metadata,
    output reg o_fault,
    input wire i_uhd
);
    localparam integer GROUPS=WIDTH/4*HEIGHT;
    localparam integer UHD_GROUPS=UHD_WIDTH/4*UHD_HEIGHT;
    localparam UHD_ENABLED=UHD_WIDTH!=0||UHD_HEIGHT!=0;
    generate if(WIDTH<=0 || WIDTH%4!=0 || HEIGHT<=0 || WIDTH>65532 || HEIGHT>65535 ||
        (UHD_ENABLED&&(UHD_WIDTH<4||UHD_WIDTH%4!=0||UHD_WIDTH>65532||UHD_HEIGHT<1||UHD_HEIGHT>65535)))begin : bad_geometry
        RAW_CAPTURE_ROUTER_REQUIRES_NATIVE4_GEOMETRY invalid_configuration();
    end endgenerate
    reg frame_owned;
    reg [31:0] frame_sequence,frame_session,frame_epoch,groups_left;
    reg [196:0] frame_metadata;
    wire raw_fire=i_valid && i_accept;
    wire physical_sof=raw_fire && i_sof;
    wire start_uhd=UHD_ENABLED&&i_uhd;
    wire start_single=start_uhd ? UHD_GROUPS==1 : GROUPS==1;
    wire [31:0] after_start=start_uhd ? UHD_GROUPS-1 : GROUPS-1;
    wire admit=physical_sof && !frame_owned && i_future_enable &&
               i_initialized && !o_fault && !i_abort && i_source_identity_valid;
    // Provenance is physical; all measurement/qualification fields stay external.
    wire [196:0] physical_metadata={i_metadata[196],
        i_metadata[195]&&i_metadata[196],i_metadata[194:193],1'b1,i_metadata[191:0]};
    assign o_data=i_data;
    assign o_abort=frame_owned && (i_abort || physical_sof);
    assign o_valid=i_valid && (frame_owned || admit) && !o_abort;
    assign o_accept=i_accept;
    assign o_sof=admit;
    assign o_eol=o_valid && i_eol;
    assign o_eof=o_valid && i_accept && ((admit && start_single) ||
                  (frame_owned && groups_left==1));
    assign o_session=admit?i_active_config[63:32]:frame_session;
    assign o_epoch=admit?i_active_config[159:128]:frame_epoch;
    assign o_sequence=admit?i_source_sequence:frame_sequence;
    assign o_metadata=admit?physical_metadata:frame_metadata;
    assign o_frame_idle=!frame_owned && !o_valid && !o_abort;
    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)begin
            frame_owned<=0;frame_sequence<=0;
            frame_session<=0;frame_epoch<=0;groups_left<=0;frame_metadata<=0;o_fault<=0;
        end else begin
            // Borrow parser-issued identity. Never replace it with crop-only numbering.
            // An invalid physical identity cannot qualify a new native product.
            if(physical_sof&&!i_source_identity_valid)o_fault<=1;
            if(o_abort)begin
                frame_owned<=0;groups_left<=0;
                if(physical_sof)o_fault<=1;
            end else if(admit)begin
                frame_owned<=!start_single;groups_left<=after_start;
                frame_sequence<=i_source_sequence;
                frame_session<=i_active_config[63:32];frame_epoch<=i_active_config[159:128];
                frame_metadata<=physical_metadata;
            end else if(frame_owned && raw_fire)begin
                if(groups_left==1)begin frame_owned<=0;groups_left<=0;end
                else groups_left<=groups_left-32'd1;
            end
        end
    end
endmodule
`default_nettype wire
