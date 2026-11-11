`timescale 1ns / 1ps
`include "pcie_protocol_v1.vh"

// Join existing held producers; no additional sparse payload copy or FIFO.
module frame_record_v3_join #(
    parameter integer SEPARATE_DATA_RESET = 0
) (
    input wire i_clk,i_rst_n,
    input wire s_begin_valid,
    output wire o_begin_ready,
    input wire [159:0] s_begin_context,
    input wire [3:0] s_begin_features,
    input wire s_terminal_valid,s_terminal_error,
    input wire [159:0] s_terminal_context,
    input wire [1023:0] s_context2_extension,
    input wire s_context2_valid,
    output wire o_context2_ready,
    input wire [683:0] s_f22_record,
    input wire s_f22_valid,
    output wire o_f22_ready,
    input wire [176:0] s_f23_record,
    input wire s_f23_valid,
    output wire o_f23_ready,
    input wire [207:0] s_f24_record,
    input wire s_f24_valid,
    output wire o_f24_ready,
    input wire [264:0] s_f25_record,
    input wire s_f25_valid,
    output wire o_f25_ready,
    output wire [2047:0] m_extension,
    output wire m_extension_valid,
    input wire m_extension_ready,
    input wire i_stream_start,
    output wire [127:0] m_stream_data,
    output wire m_stream_valid,
    input wire m_stream_ready,
    output wire o_lane_read_enable,
    output wire [8:0] o_lane_read_index,
    input wire [39:0] i_lane_read_data,
    input wire i_lane_read_valid,
    output reg o_fault,
    output reg [31:0] o_stale_count,
    input wire i_data_reset_n
);
    reg owned,terminal_seen,terminal_error;
    reg [159:0] frame_identity;
    reg [3:0] features;
    localparam [31:0] SPARSE_MAGIC=`PCIE_RECORD_V3_SPARSE_MAGIC;
    wire [159:0] extension_context={16'd1,16'd0,8'd1,
        s_context2_extension[183:160],s_context2_extension[159:128],
        s_context2_extension[127:96],s_context2_extension[95:64]};
    wire f22_match=owned && features[0] && s_f22_record[683:524]==frame_identity;
    wire f23_match=owned && features[1] && s_f23_record[176:17]==frame_identity;
    wire f24_match=owned && features[2] && s_f24_record[207:48]==frame_identity;
    wire f25_match=owned && features[3] && s_f25_record[264:105]==frame_identity;
    wire all_present=(!features[0] || (s_f22_valid && f22_match)) &&
        (!features[1] || (s_f23_valid && f23_match)) &&
        (!features[2] || (s_f24_valid && f24_match)) &&
        (!features[3] || (s_f25_valid && f25_match));
    wire context2_match=owned && extension_context==frame_identity;
    wire output_fire=m_extension_valid && m_extension_ready;
    wire stale_f22=s_f22_valid && o_f22_ready && !f22_match;
    wire stale_f23=s_f23_valid && o_f23_ready && !f23_match;
    wire stale_f24=s_f24_valid && o_f24_ready && !f24_match;
    wire stale_f25=s_f25_valid && o_f25_ready && !f25_match;
    wire stale_terminal=s_terminal_valid && (!owned || terminal_seen || s_terminal_context!=frame_identity);
    wire [2:0] stale_increment={2'd0,stale_f22}+{2'd0,stale_f23}+
        {2'd0,stale_f24}+{2'd0,stale_f25}+{2'd0,stale_terminal};
    wire [32:0] stale_sum={1'b0,o_stale_count}+{30'd0,stale_increment};
    wire [8:0] point_count=features[1] ? s_f23_record[16:8] : 9'd0;
    wire [7:0] lane_status=features[1] ? s_f23_record[7:0] : 8'd0;
    // Only the 256-byte description is combinational; points remain in the
    // producer RAM until the final extension handshake, never a wide array.
    reg [1023:0] sparse;
    always @* begin
        sparse=0;
        sparse[31:0]=`PCIE_RECORD_V4_SPARSE_MAGIC;
        sparse[39:32]=`PCIE_RECORD_V4_SPARSE_SCHEMA;
        sparse[47:40]=`PCIE_RECORD_V4_POINT_BYTES;
        sparse[55:48]={4'd0,features}; sparse[63:56]={4'd0,features};
        sparse[71:64]={7'd0,terminal_error}; sparse[79:72]=lane_status;
        sparse[95:80]={7'd0,point_count};
        sparse[111:96]=`PCIE_RECORD_V4_ROI_BEGIN;
        sparse[127:112]=`PCIE_RECORD_V4_ROI_END;
        sparse[128+:524]=features[0] ? s_f22_record[523:0] : 524'd0;
        sparse[656+:48]=features[2] ? s_f24_record[47:0] : 48'd0;
        sparse[704+:105]=features[3] ? s_f25_record[104:0] : 105'd0;
    end
    reg stream_active,read_pending,word_valid,flit_valid;
    reg [7:0] flit_index;
    reg [8:0] point_index;
    reg [2:0] word_byte;
    reg [3:0] byte_index;
    reg [39:0] point_word;
    reg [127:0] byte_shift;
    wire head_phase=flit_index<16;
    wire stream_fire=m_stream_valid && m_stream_ready;
    wire all_points_read=point_index==point_count;
    wire byte_available=word_valid || (all_points_read && !read_pending);
    wire byte_step=stream_active && !head_phase && !flit_valid && byte_available;
    wire [7:0] next_byte=word_valid ? point_word[7:0] : 8'd0;
    assign o_lane_read_enable=stream_active && !head_phase && !flit_valid &&
        !word_valid && !read_pending && !all_points_read;
    assign o_lane_read_index=point_index;
    // Header and point-body lifetimes are disjoint. Retain one selected head
    // in the existing body register; only a real handshake advances its index.
    wire head_load=stream_active && head_phase && !flit_valid;
    // Stream transfers and the synchronous serializer share the data release.
    wire data_reset_n=SEPARATE_DATA_RESET!=0 ? i_data_reset_n : i_rst_n;
    assign m_stream_valid=data_reset_n && stream_active && flit_valid;
    assign m_stream_data=byte_shift;
    // Fixed 8-bit shifts trade ~2k short clocks/frame for a small datapath.
    // No 40-to-128 variable shift, payload reset or full-frame register copy.
    always @(posedge i_clk) begin
        if(!data_reset_n) begin
            stream_active<=0;read_pending<=0;word_valid<=0;flit_valid<=0;
            flit_index<=0;point_index<=0;word_byte<=0;byte_index<=0;
        end else begin
            // Idle local state already has the accepted-start values. The
            // wide producer identity/ingress feedback now only starts ownership.
            if(!stream_active) begin
                flit_index<=0;point_index<=0;
                read_pending<=0;word_valid<=0;flit_valid<=0;byte_index<=0;word_byte<=0;
            end
            if(i_stream_start && m_extension_valid && !stream_active)
                stream_active<=1;
            if(head_load) begin
                byte_shift<=m_extension[flit_index[3:0]*128+:128];flit_valid<=1;
            end
            if(o_lane_read_enable)read_pending<=1;
            if(read_pending && i_lane_read_valid) begin
                point_word<=i_lane_read_data;word_valid<=1;read_pending<=0;
                point_index<=point_index+1'b1;word_byte<=0;
            end
            if(byte_step) begin
                byte_shift<={next_byte,byte_shift[127:8]};
                if(word_valid) begin
                    point_word<={8'd0,point_word[39:8]};
                    if(word_byte==4)begin word_valid<=0;word_byte<=0;end
                    else word_byte<=word_byte+1'b1;
                end
                if(byte_index==15)begin flit_valid<=1;byte_index<=0;end
                else byte_index<=byte_index+1'b1;
            end
            if(stream_fire)begin
                flit_valid<=0;
                if(flit_index==127)stream_active<=0;
                else flit_index<=flit_index+1'b1;
            end
        end
    end

    assign o_begin_ready=data_reset_n && !owned && !o_fault;
    assign m_extension_valid=data_reset_n && owned && !o_fault && terminal_seen &&
        s_context2_valid && context2_match && all_present;
    assign m_extension={sparse,s_context2_extension};
    // Exact records remain held at their producers until the single output fire.
    // Wrong/late/disabled records are actually consumed and diagnosed.
    assign o_f22_ready=data_reset_n && (!f22_match || output_fire);
    assign o_f23_ready=data_reset_n && (!f23_match || output_fire);
    assign o_f24_ready=data_reset_n && (!f24_match || output_fire);
    assign o_f25_ready=data_reset_n && (!f25_match || output_fire);
    assign o_context2_ready=data_reset_n && ((s_context2_valid && owned && !context2_match) || output_fire);

    always @(posedge i_clk or negedge i_rst_n) begin
        if(!i_rst_n) begin
            owned<=0;terminal_seen<=0;terminal_error<=0;frame_identity<=0;features<=0;
            o_fault<=0;o_stale_count<=0;
        end else begin
            if(s_begin_valid && o_begin_ready) begin
                if((|s_begin_features[3:1]) && !s_begin_features[0]) o_fault<=1;
                else begin
                    owned<=1;terminal_seen<=0;terminal_error<=0;
                    frame_identity<=s_begin_context;features<=s_begin_features;
                end
            end
            if(s_terminal_valid && owned && !terminal_seen && s_terminal_context==frame_identity) begin
                terminal_seen<=1;terminal_error<=s_terminal_error;
            end
            if(s_context2_valid && owned && !context2_match) o_fault<=1;
            if(output_fire) begin owned<=0;terminal_seen<=0;end
            if(stale_increment!=0) o_stale_count<=stale_sum[32] ? 32'hffffffff : stale_sum[31:0];
        end
    end
endmodule
