`timescale 1ns/1ps
`default_nettype none

// Strict physical member geometry before the existing 47-bit event FIFO.
// Validate every image line, including discarded margins. FE succeeds only
// after the full sensor raster; crop completion alone is never SOURCE success.
module real_hdr_member_crop10 #(
    parameter integer SENSOR_WIDTH=1944, SENSOR_HEIGHT=1097,
    parameter integer CROP_X=12, CROP_Y=8, WIDTH=1920, HEIGHT=1080
) (
    input wire i_clk, i_reset_n,
    input wire [47:0] s_data,
    input wire s_valid,
    output wire s_ready,
    input wire s_sof, s_eol, s_abort,
    input wire [3:0] s_error,
    input wire [31:0] s_group,s_sequence,
    input wire s_identity_valid,s_cycle_valid,
    input wire [15:0] s_frame_number,
    output reg [39:0] m_data,
    output reg m_valid,
    input wire m_ready,
    output reg m_sof, m_eol, m_abort,
    output reg [3:0] m_error,
    output reg [31:0] m_group,m_sequence,
    output reg m_identity_valid,m_cycle_valid,
    output reg [15:0] m_frame_number,
    output reg [31:0] o_geometry_errors, o_complete_frames
);
    localparam integer SOURCE_GROUPS=SENSOR_WIDTH/4;
    localparam integer FIRST_GROUP=CROP_X/4;
    localparam integer OUTPUT_GROUPS=WIDTH/4;
    reg active;
    reg [15:0] row_count, group_count;
    reg [32:0] frame_identity;
    reg [31:0] frame_group;
    reg frame_cycle_valid;
    reg [15:0] frame_number;
    wire room=!m_valid || m_ready;
    wire selected=row_count>=CROP_Y && row_count<CROP_Y+HEIGHT &&
        group_count>=FIRST_GROUP && group_count<FIRST_GROUP+OUTPUT_GROUPS;
    wire malformed=row_count>=SENSOR_HEIGHT ||
        (s_sof!=(row_count==0 && group_count==0)) ||
        (s_eol!=(group_count==SOURCE_GROUPS-1));
    assign s_ready=room;
    function [39:0] quantize;
        input [47:0] p;
        integer lane;
        reg [12:0] rounded;
        begin
            for(lane=0;lane<4;lane=lane+1)begin
                rounded={1'b0,p[lane*12+:12]}+13'd2;
                quantize[lane*10+:10]=rounded>=13'd4096 ? 10'd1023 : rounded[11:2];
            end
        end
    endfunction
    always @(posedge i_clk or negedge i_reset_n)begin
        if(!i_reset_n)begin
            active<=0;row_count<=0;group_count<=0;frame_identity<=0;
            frame_group<=0;frame_cycle_valid<=0;frame_number<=0;
            m_valid<=0;m_data<=0;m_sof<=0;m_eol<=0;m_abort<=0;m_error<=0;
            m_group<=0;m_sequence<=0;m_identity_valid<=0;m_cycle_valid<=0;m_frame_number<=0;
            o_geometry_errors<=0;o_complete_frames<=0;
        end else begin
            if(m_valid && m_ready)m_valid<=0;
            if(s_valid && s_ready)begin
                m_group<=frame_group;m_sequence<=frame_identity[31:0];
                m_identity_valid<=frame_identity[32];m_cycle_valid<=frame_cycle_valid;m_frame_number<=frame_number;
                if(!s_abort && s_error==7)begin
                    m_valid<=1;m_sof<=0;m_eol<=0;
                    if(active)begin
                        m_data<={7'd0,frame_identity};m_abort<=1;m_error<=5;active<=0;
                        o_geometry_errors<=o_geometry_errors+1;
                    end else begin
                        m_data<=s_data[39:0];m_abort<=0;m_error<=7;
                        frame_identity<=s_data[32:0];active<=1;row_count<=0;group_count<=0;
                        frame_group<=s_group;frame_cycle_valid<=s_cycle_valid;frame_number<=s_frame_number;
                        m_group<=s_group;m_sequence<=s_sequence;m_identity_valid<=s_identity_valid;
                        m_cycle_valid<=s_cycle_valid;m_frame_number<=s_frame_number;
                    end
                end else if(s_abort)begin
                    if(active)begin
                        m_valid<=1;m_data<={7'd0,frame_identity};m_sof<=0;m_eol<=0;
                        m_abort<=1;m_error<=s_error;active<=0;
                    end
                end else if(s_error==6)begin
                    if(active)begin
                        m_valid<=1;m_data<={7'd0,frame_identity};m_sof<=0;m_eol<=0;active<=0;
                        if(row_count==SENSOR_HEIGHT && group_count==0)begin
                            m_abort<=0;m_error<=6;o_complete_frames<=o_complete_frames+1;
                        end else begin
                            m_abort<=1;m_error<=4;o_geometry_errors<=o_geometry_errors+1;
                        end
                    end
                end else if(s_error==8)begin
                    m_valid<=1;m_data<=s_data[39:0];m_sof<=0;m_eol<=0;m_abort<=0;m_error<=8;
                    m_group<=s_group;m_sequence<=s_sequence;m_identity_valid<=0;m_cycle_valid<=0;m_frame_number<=s_frame_number;
                end else if(active && s_error==0)begin
                    if(malformed)begin
                        m_valid<=1;m_data<={7'd0,frame_identity};m_sof<=0;m_eol<=0;
                        m_abort<=1;m_error<=4;active<=0;o_geometry_errors<=o_geometry_errors+1;
                    end else begin
                        if(s_eol)begin group_count<=0;row_count<=row_count+1'b1;end
                        else group_count<=group_count+1'b1;
                        if(selected)begin
                            m_valid<=1;m_data<=quantize(s_data);m_abort<=0;m_error<=0;
                            m_sof<=row_count==CROP_Y && group_count==FIRST_GROUP;
                            m_eol<=group_count==FIRST_GROUP+OUTPUT_GROUPS-1;
                        end
                    end
                end
            end
        end
    end
    generate if(SENSOR_WIDTH%4!=0 || CROP_X%4!=0 || WIDTH%4!=0 ||
        SENSOR_WIDTH<4 || SENSOR_WIDTH>65532 || SENSOR_HEIGHT<1 || SENSOR_HEIGHT>65534 ||
        CROP_X<0 || CROP_Y<0 || WIDTH<4 || HEIGHT<1 ||
        CROP_X+WIDTH>SENSOR_WIDTH || CROP_Y+HEIGHT>SENSOR_HEIGHT)begin:g_bad_geometry
        REAL_HDR_INVALID_PHYSICAL_CROP invalid_geometry();
    end endgenerate
endmodule
`default_nettype wire
