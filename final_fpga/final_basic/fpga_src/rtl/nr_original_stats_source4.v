`timescale 1ns / 1ps
`default_nettype none

// Snapshot the existing original observer; whole SOURCE qualifies its result.
module nr_original_stats_source4 #(
    parameter integer SOURCE_WIDTH=1920,SOURCE_HEIGHT=1080
) (
    input wire clk,rst_n,
    input wire i_start,output wire o_start_ready,
    input wire [383:0] i_frame,input wire [63:0] i_tag,
    input wire [159:0] i_observer_expected_context,
    input wire i_observation_valid,i_observation_metadata_match,
    input wire [159:0] i_observation_context,
    input wire [183:0] i_observation_statistics,
    input wire i_source_valid,i_source_ok,input wire [7:0] i_source_error,
    input wire [31:0] i_source_pixels,i_accepted_pixels,
    input wire i_source_quiescent,i_no_observer,
    output wire m_valid,input wire m_ready,
    output wire [63:0] m_tag,output wire [159:0] m_context,
    output wire [183:0] m_statistics
);
    localparam integer OBS_WIDTH=SOURCE_WIDTH/6,OBS_HEIGHT=SOURCE_HEIGHT/6;
    localparam integer OBS_PIXELS=OBS_WIDTH*OBS_HEIGHT,SOURCE_PIXELS=SOURCE_WIDTH*SOURCE_HEIGHT;
    reg active,pending,source_seen,source_ok,source_count_ok,observation_seen,observation_ok;
    reg [7:0] source_error,observation_error;
    reg [63:0] tag_locked;
    reg [159:0] context_locked,observer_context_locked;
    reg [183:0] observed_statistics,result_statistics;
    wire observation_match=i_observation_metadata_match && i_observation_context==observer_context_locked;
    wire complete_observation=observation_match && i_observation_statistics[15:0]==OBS_PIXELS &&
        i_observation_statistics[31:16]==OBS_PIXELS && i_observation_statistics[143:128]==OBS_WIDTH &&
        i_observation_statistics[159:144]==OBS_HEIGHT && i_observation_statistics[167:160]==1 &&
        i_observation_statistics[175:168]==0 && i_observation_statistics[183:176]==1;
    wire success=source_ok && source_count_ok && observation_seen && observation_ok;
    wire [7:0] failure=!source_ok ? (source_error!=0 ? source_error : 8'd44) :
        !source_count_ok ? 8'd41 : !observation_seen ? 8'd9 :
        observation_error!=0 ? observation_error : 8'd41;
    assign o_start_ready=rst_n && !active && !pending;
    assign m_valid=rst_n && pending;
    assign m_tag=tag_locked;assign m_context=context_locked;assign m_statistics=result_statistics;
    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)begin
            active<=0;pending<=0;source_seen<=0;source_ok<=0;source_count_ok<=0;
            observation_seen<=0;observation_ok<=0;source_error<=0;observation_error<=0;
            tag_locked<=0;context_locked<=0;observer_context_locked<=0;
            observed_statistics<=0;result_statistics<=0;
        end else begin
            if(m_valid && m_ready)pending<=0;
            if(i_start && o_start_ready)begin
                active<=1;source_seen<=0;source_ok<=0;source_count_ok<=0;
                observation_seen<=0;observation_ok<=0;source_error<=0;observation_error<=0;
                tag_locked<=i_tag;observer_context_locked<=i_observer_expected_context;
                context_locked<={16'd1,16'd0,8'd1,6'd0,i_frame[238:237],7'd0,i_frame[3],
                    7'd0,i_frame[4],i_frame[108:77],i_frame[140:109],i_frame[76:45]};
                observed_statistics<=0;
            end else if(active)begin
                if(i_source_valid && !source_seen)begin
                    source_seen<=1;source_ok<=i_source_ok && i_source_error==0;
                    source_error<=i_source_error;
                    source_count_ok<=i_source_pixels==i_accepted_pixels && i_source_pixels==SOURCE_PIXELS;
                end
                if(i_observation_valid && !observation_seen)begin
                    observation_seen<=1;observation_ok<=complete_observation;
                    observation_error<=observation_match ? i_observation_statistics[175:168] : 8'd41;
                    observed_statistics<=i_observation_statistics;
                end
                if(source_seen && i_source_quiescent && (observation_seen || i_no_observer))begin
                    active<=0;pending<=1;
                    result_statistics<=success ? observed_statistics : {8'd1,failure,8'd0,160'd0};
                end
            end
        end
    end
endmodule
`default_nettype wire
