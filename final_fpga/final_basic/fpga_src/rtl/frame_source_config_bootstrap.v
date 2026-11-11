`timescale 1ns/1ps
`default_nettype none

// One cold LOCAL BOOT or transparent online routing; no private CFG fallback.
module frame_source_config_bootstrap #(parameter integer EXT_WIDTH=0) (
    input wire clk,rst_n,i_local,i_transport_reset_done,
    input wire [159+EXT_WIDTH:0] s_online_config_data,
    input wire s_online_config_valid,
    output wire s_online_config_ready,
    output wire [159+EXT_WIDTH:0] m_online_ack_data,
    output wire m_online_ack_valid,m_online_ack_ok,
    input wire m_online_ack_ready,
    input wire i_online_source_ready,i_online_pause_new_frames,
    output wire [159+EXT_WIDTH:0] m_source_config_data,
    output wire m_source_config_valid,
    input wire m_source_config_ready,
    input wire [159+EXT_WIDTH:0] s_whole_ack_data,
    input wire s_whole_ack_valid,s_whole_ack_ok,
    output wire s_whole_ack_ready,
    output wire o_source_ready,o_pause_new_frames,
    output reg o_local_initialized,o_local_fault,o_mode_fault,
    output reg [31:0] o_stale_ack_count,
    output wire [159+EXT_WIDTH:0] o_local_config
);
    localparam [159+EXT_WIDTH:0] LOCAL_BOOT={32'd0,6'd0,16'd0,25'd0,7'd1,1'b0,
                                  7'd75,2'd0,32'd1,32'd0};
    reg mode_locked,local_mode,local_sent;
    wire operational=rst_n&&i_transport_reset_done&&mode_locked;
    wire local_offer=operational&&local_mode&&!local_sent&&!o_local_fault;
    assign o_local_config=LOCAL_BOOT;
    assign m_source_config_data=local_mode?LOCAL_BOOT:s_online_config_data;
    assign m_source_config_valid=local_mode?local_offer:
        operational&&s_online_config_valid;
    assign s_online_config_ready=operational&&!local_mode&&m_source_config_ready;
    assign m_online_ack_data=s_whole_ack_data;
    assign m_online_ack_ok=s_whole_ack_ok;
    assign m_online_ack_valid=operational&&!local_mode&&s_whole_ack_valid;
    // Consume stale LOCAL replies so that they cannot block the true ACK.
    assign s_whole_ack_ready=operational&&(local_mode||m_online_ack_ready);
    assign o_source_ready=operational&&!o_local_fault&&!o_mode_fault&&
        (local_mode?o_local_initialized:i_online_source_ready);
    assign o_pause_new_frames=!operational||o_local_fault||o_mode_fault||
        (local_mode?!o_local_initialized:i_online_pause_new_frames);
    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)begin
            mode_locked<=0;local_mode<=0;local_sent<=0;
            o_local_initialized<=0;o_local_fault<=0;o_mode_fault<=0;o_stale_ack_count<=0;
        end else begin
            if(!mode_locked)begin mode_locked<=1;local_mode<=i_local;end
            else if(i_local!=local_mode)o_mode_fault<=1;
            // A warm mode fault never retracts an already presented request.
            if(local_offer&&m_source_config_ready)local_sent<=1;
            if(operational&&local_mode&&s_whole_ack_valid&&s_whole_ack_ready)begin
                if(local_sent&&!o_local_initialized&&!o_local_fault&&s_whole_ack_data==LOCAL_BOOT)begin
                    if(s_whole_ack_ok)o_local_initialized<=1;
                    else o_local_fault<=1;
                end else if(!(&o_stale_ack_count))o_stale_ack_count<=o_stale_ack_count+1'b1;
            end
        end
    end
endmodule
`default_nettype wire
