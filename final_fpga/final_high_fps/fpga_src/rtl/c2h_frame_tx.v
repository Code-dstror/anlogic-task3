`timescale 1ns / 1ps
`include "pcie_protocol_v1.vh"

// 为主机方向帧添加协议头并发送AXI数据流
module c2h_frame_tx #(
    // An absent version port is ignored by the unchanged v1 profile.
    parameter integer RECORD_V2_ENABLE = 0,
    parameter integer RECORD_V3_ENABLE = 0,
    parameter integer RECORD_V4_ENABLE = 0,
    parameter integer RECORD_EXTENSION_WIDTH = RECORD_V3_ENABLE ? 3072 : 1024,
    parameter integer BORROW_EXTENSION = 0,
    parameter integer STREAM_EXTENSION = 0
) (
    // 时钟与复位
    input  wire i_clk,
    input  wire i_rst_n,

    // 链路与传输控制
    input  wire i_transport_enable,
    input  wire i_link_up,
    input  wire i_c2h_running,

    // 输入帧元数据
    input  wire i_meta_valid,
    output wire o_meta_ready,
    input  wire [31:0] i_meta_frame_sequence,
    input  wire [31:0] i_meta_payload_length,
    input  wire [15:0] i_meta_width,
    input  wire [15:0] i_meta_height,
    input  wire [7:0] i_meta_pixel_format,
    input  wire [7:0] i_meta_compression,
    input  wire [7:0] i_meta_quality,
    input  wire [63:0] i_meta_timestamp_ns,
    input  wire [31:0] i_meta_status,
    input  wire [31:0] i_meta_error_code,
    input  wire [15:0] i_meta_slot_id,
    input  wire [31:0] i_meta_payload_crc32,
    input  wire [15:0] i_meta_record_version,
    input  wire [RECORD_EXTENSION_WIDTH-1:0] i_meta_record_extension,

    // Qualified same-clock extension stream; only HEADER consumes it.
    input wire [127:0] i_extension_tdata,
    input wire i_extension_tvalid,i_extension_tlast,
    output wire o_extension_tready,

    // 输入载荷流
    input  wire [127:0] i_src_tdata,
    input  wire [15:0] i_src_tkeep,
    input  wire i_src_tvalid,
    output wire o_src_tready,
    input  wire i_src_tlast,

    // C2H输出流
    output wire [127:0] o_axis_tdata,
    output wire [15:0] o_axis_tkeep,
    output wire [15:0] o_axis_tuser,
    output wire o_axis_tvalid,
    input  wire i_axis_tready,
    output wire o_axis_tlast,

    // 发送状态与事件
    output wire o_tx_busy,
    output wire o_transport_ready,
    output wire [15:0] o_active_slot_id,
    output wire [31:0] o_last_error,
    output wire o_frame_accept,
    output wire o_frame_done, // 末拍完成握手后通知帧结束
    output wire o_frame_abort
);
    generate if(RECORD_EXTENSION_WIDTH!=1024 && RECORD_EXTENSION_WIDTH!=3072 && RECORD_EXTENSION_WIDTH!=16384) begin : invalid_record_width
        RECORD_EXTENSION_REQUIRES_1024_3072_OR_16384 u_invalid_record_width();
    end endgenerate
    generate if(RECORD_V3_ENABLE && RECORD_EXTENSION_WIDTH!=3072) begin : invalid_v3_width
        RECORD_V3_REQUIRES_3072 u_invalid_v3_width();
    end endgenerate
    generate if(RECORD_V4_ENABLE && (RECORD_EXTENSION_WIDTH!=16384 || STREAM_EXTENSION==0)) begin : invalid_v4_stream
        RECORD_V4_REQUIRES_16384_STREAM u_invalid_v4_stream();
    end endgenerate
    localparam integer HEADER_INDEX_WIDTH=RECORD_V4_ENABLE ? 8 : (RECORD_V3_ENABLE ? 5 : 4);
    localparam [15:0] V4_HEADER_LENGTH=`PCIE_RECORD_V4_HEADER_LENGTH;
    `include "pcie_record_v3_validate.vh"

    localparam [2:0] STATE_IDLE      = 3'd0;
    localparam [2:0] STATE_HEADER    = 3'd1;
    localparam [2:0] STATE_PAYLOAD   = 3'd2;
    localparam [2:0] STATE_WAIT_LAST = 3'd3;

    reg [2:0] state_current;
    reg [2:0] state_next;

    reg [HEADER_INDEX_WIDTH-1:0]  header_index;
    reg [15:0] meta_record_version;
    reg [RECORD_EXTENSION_WIDTH-1:0] record_extension_shift;
    wire [HEADER_INDEX_WIDTH-1:0] extension_word_index=header_index-4;
    // Number of complete nonterminal transfers still owed by this record.
    // Every legal nonterminal beat is exactly sixteen bytes.
    reg [27:0] payload_beats_after;
    reg [31:0] meta_frame_sequence;
    reg [31:0] meta_payload_length;
    reg [15:0] meta_width;
    reg [15:0] meta_height;
    reg [7:0]  meta_pixel_format;
    reg [7:0]  meta_compression;
    reg [7:0]  meta_quality;
    reg [63:0] meta_timestamp_ns;
    reg [31:0] meta_status;
    reg [31:0] meta_error_code;
    reg [15:0] meta_slot_id;
    reg [31:0] meta_payload_crc32;

    reg [127:0] axis_tdata_o;
    reg [15:0]  axis_tkeep_o;
    reg [15:0]  axis_tuser_o;
    reg         axis_tvalid_o;
    reg         axis_tlast_o;
    reg [31:0]  last_error_o;
    reg         frame_accept_o;
    reg         frame_done_o;
    reg         frame_abort_o;

    reg [127:0] beat_data;
    reg [15:0]  beat_keep;
    reg         beat_valid;
    reg         beat_last;
    reg [15:0]  expected_keep;

    wire output_fire;
    wire output_last_fire;
    wire buffer_ready;
    wire beat_load;
    wire meta_fire;
    wire metadata_length_valid;
    wire metadata_version_valid;
    wire [15:0] requested_version;
    wire [HEADER_INDEX_WIDTH-1:0] last_header_index;
    wire payload_expected_last;
    wire payload_fire;
    wire payload_protocol_error;
    wire extension_protocol_error;
    wire transport_fault;


    // 只在AXI有效就绪握手时推进发送位置
    assign output_fire = axis_tvalid_o && i_axis_tready;
    assign output_last_fire = output_fire && axis_tlast_o;
    assign buffer_ready = !axis_tvalid_o || i_axis_tready;
    assign beat_load = beat_valid && buffer_ready;
    assign metadata_length_valid = (i_meta_payload_length != 32'd0) &&
                                   (i_meta_payload_length <= `PCIE_MAX_PAYLOAD);
    assign requested_version = (RECORD_V2_ENABLE != 0 || RECORD_V3_ENABLE != 0 || RECORD_V4_ENABLE != 0) ? i_meta_record_version : 16'd1;
    assign metadata_version_valid = requested_version == 16'd1 ||
                                   ((RECORD_V2_ENABLE != 0 || RECORD_V3_ENABLE != 0 || RECORD_V4_ENABLE != 0) && requested_version == 16'd2) ||
                                   (RECORD_V3_ENABLE != 0 && requested_version == 16'd3) ||
                                   (RECORD_V4_ENABLE != 0 && requested_version == `PCIE_RECORD_V4_VERSION);
    assign last_header_index = meta_record_version == `PCIE_RECORD_V4_VERSION ? `PCIE_RECORD_V4_HEADER_LENGTH/16-1 : (meta_record_version == 16'd3 ? 5'd27 : (meta_record_version == 16'd2 ? 4'd11 : 4'd3));
    assign o_meta_ready = (state_current == STATE_IDLE) && !axis_tvalid_o &&
                          i_transport_enable && i_link_up && i_c2h_running;
    assign meta_fire = i_meta_valid && o_meta_ready;
    assign payload_expected_last = payload_beats_after == 28'd0;
    assign o_extension_tready = STREAM_EXTENSION!=0 && state_current==STATE_HEADER &&
                               header_index>=4 && buffer_ready && !transport_fault;
    assign extension_protocol_error = o_extension_tready && i_extension_tvalid &&
                                      (i_extension_tlast!=(header_index==last_header_index));
    assign o_src_tready = (state_current == STATE_PAYLOAD) && buffer_ready;
    assign payload_fire = i_src_tvalid && o_src_tready;
    assign payload_protocol_error = (i_src_tkeep != expected_keep) ||
                                    (i_src_tlast != payload_expected_last);
    assign transport_fault = (state_current != STATE_IDLE) &&
                             (!i_transport_enable || !i_link_up || !i_c2h_running);
    assign o_axis_tdata = axis_tdata_o;
    assign o_axis_tkeep = axis_tkeep_o;
    assign o_axis_tuser = axis_tuser_o;
    assign o_axis_tvalid = axis_tvalid_o;
    assign o_axis_tlast = axis_tlast_o;
    assign o_tx_busy = (state_current != STATE_IDLE) || axis_tvalid_o;
    assign o_transport_ready = o_meta_ready;
    assign o_active_slot_id = meta_slot_id;
    assign o_last_error = last_error_o;
    assign o_frame_accept = frame_accept_o;
    assign o_frame_done = frame_done_o;
    assign o_frame_abort = frame_abort_o;

    // 计算末拍期望字节使能
    always @(*) begin
        expected_keep = 16'hffff;
        if (payload_expected_last) begin
            case ({1'b0,meta_payload_length[3:0]})
                5'd1:  expected_keep = 16'h0001;
                5'd2:  expected_keep = 16'h0003;
                5'd3:  expected_keep = 16'h0007;
                5'd4:  expected_keep = 16'h000f;
                5'd5:  expected_keep = 16'h001f;
                5'd6:  expected_keep = 16'h003f;
                5'd7:  expected_keep = 16'h007f;
                5'd8:  expected_keep = 16'h00ff;
                5'd9:  expected_keep = 16'h01ff;
                5'd10: expected_keep = 16'h03ff;
                5'd11: expected_keep = 16'h07ff;
                5'd12: expected_keep = 16'h0fff;
                5'd13: expected_keep = 16'h1fff;
                5'd14: expected_keep = 16'h3fff;
                5'd15: expected_keep = 16'h7fff;
                default: expected_keep = 16'hffff;
            endcase
        end
    end

    // 选择帧头或载荷作为当前输出拍
    always @(*) begin
        beat_data = 128'd0;
        beat_keep = 16'hffff;
        beat_valid = 1'b0;
        beat_last = 1'b0;
        case (state_current)
            STATE_HEADER: begin
                beat_valid = 1'b1;
                case (header_index)
                    4'd0: beat_data = {
                        meta_payload_length,
                        meta_frame_sequence,
                        meta_record_version == `PCIE_RECORD_V4_VERSION ? V4_HEADER_LENGTH : (meta_record_version == 16'd3 ? 16'd448 : (meta_record_version == 16'd2 ? 16'd192 : 16'd64)),
                        meta_record_version,
                        `PCIE_FRAME_MAGIC
                    };
                    4'd1: beat_data = {
                        meta_timestamp_ns,
                        8'h01,
                        meta_quality,
                        meta_compression,
                        meta_pixel_format,
                        meta_height,
                        meta_width
                    };
                    4'd2: beat_data = {
                        meta_payload_crc32,
                        16'd0,
                        meta_slot_id,
                        meta_error_code,
                        meta_status
                    };
                    4'd3: beat_data = 128'd0;
                    default: begin
                        beat_data = STREAM_EXTENSION!=0 ? i_extension_tdata :
                            (BORROW_EXTENSION!=0 ? i_meta_record_extension[extension_word_index*128+:128] : record_extension_shift[127:0]);
                        if(STREAM_EXTENSION!=0)beat_valid=i_extension_tvalid;
                    end
                endcase
            end
            STATE_PAYLOAD: begin
                beat_data = i_src_tdata;
                beat_keep = expected_keep;
                beat_valid = i_src_tvalid;
                beat_last = payload_expected_last;
            end
            default: begin
                beat_data = 128'd0;
                beat_keep = 16'd0;
                beat_valid = 1'b0;
                beat_last = 1'b0;
            end
        endcase
    end

    // 根据元数据和载荷握手选择发送状态
    always @(*) begin
        state_next = state_current;
        if (transport_fault || extension_protocol_error) begin
            state_next = STATE_IDLE;
        end else begin
            case (state_current)
                STATE_IDLE: begin
                    if (meta_fire && metadata_length_valid && metadata_version_valid) begin
                        state_next = STATE_HEADER;
                    end
                end
                STATE_HEADER: begin
                    if (beat_load && (header_index == last_header_index)) begin
                        state_next = STATE_PAYLOAD;
                    end
                end
                STATE_PAYLOAD: begin
                    if (payload_fire && payload_protocol_error) begin
                        state_next = STATE_IDLE;
                    end else if (payload_fire && payload_expected_last) begin
                        state_next = STATE_WAIT_LAST;
                    end
                end
                STATE_WAIT_LAST: begin
                    if (output_last_fire) begin
                        state_next = STATE_IDLE;
                    end
                end
                default: state_next = STATE_IDLE;
            endcase
        end
    end

    // 寄存发送状态供下一周期使用
    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            state_current <= STATE_IDLE;
        end else begin
            state_current <= state_next;
        end
    end

    // 更新帧头位置载荷计数和完成事件
    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            header_index <= 4'd0;
            meta_record_version <= 16'd1;
            record_extension_shift <= {RECORD_EXTENSION_WIDTH{1'b0}};
            payload_beats_after <= 28'd0;
            meta_frame_sequence <= 32'd0;
            meta_payload_length <= 32'd0;
            meta_width <= 16'd0;
            meta_height <= 16'd0;
            meta_pixel_format <= 8'd0;
            meta_compression <= 8'd0;
            meta_quality <= 8'd0;
            meta_timestamp_ns <= 64'd0;
            meta_status <= 32'd0;
            meta_error_code <= 32'd0;
            meta_slot_id <= 16'd0;
            meta_payload_crc32 <= 32'd0;
            axis_tdata_o <= 128'd0;
            axis_tkeep_o <= 16'd0;
            axis_tuser_o <= 16'd0;
            axis_tvalid_o <= 1'b0;
            axis_tlast_o <= 1'b0;
            last_error_o <= `PCIE_ERROR_NONE;
            frame_accept_o <= 1'b0;
            frame_done_o <= 1'b0;
            frame_abort_o <= 1'b0;
        end else begin
            frame_accept_o <= 1'b0;
            frame_done_o <= 1'b0;
            frame_abort_o <= 1'b0;

            if (transport_fault) begin
                axis_tvalid_o <= 1'b0;
                axis_tlast_o <= 1'b0;
                frame_abort_o <= 1'b1;
                if (!i_link_up) begin
                    last_error_o <= `PCIE_ERROR_LINK_DOWN;
                end else begin
                    last_error_o <= `PCIE_ERROR_C2H_STOPPED;
                end
            end else begin
                if (buffer_ready) begin
                    axis_tvalid_o <= beat_valid;
                    if (beat_valid) begin
                        axis_tdata_o <= beat_data;
                        axis_tkeep_o <= beat_keep;
                        axis_tuser_o <= 16'd0;
                        axis_tlast_o <= beat_last;
                    end
                end

                if(extension_protocol_error)begin
                    axis_tvalid_o<=0;frame_abort_o<=1;last_error_o<=`PCIE_ERROR_HEADER_FORMAT;
                end
                if (meta_fire) begin
                    if (metadata_length_valid && metadata_version_valid) begin
                        meta_frame_sequence <= i_meta_frame_sequence;
                        meta_payload_length <= i_meta_payload_length;
                        meta_width <= i_meta_width;
                        meta_height <= i_meta_height;
                        meta_pixel_format <= i_meta_pixel_format;
                        meta_compression <= i_meta_compression;
                        meta_quality <= i_meta_quality;
                        meta_timestamp_ns <= i_meta_timestamp_ns;
                        meta_status <= i_meta_status;
                        meta_error_code <= i_meta_error_code;
                        meta_slot_id <= i_meta_slot_id;
                        meta_payload_crc32 <= i_meta_payload_crc32;
                        header_index <= 4'd0;
                        meta_record_version <= requested_version;
                        if(BORROW_EXTENSION==0 && STREAM_EXTENSION==0)
                            record_extension_shift <= (RECORD_V2_ENABLE != 0 || RECORD_V3_ENABLE != 0) && requested_version != 16'd1 ?
                                                      i_meta_record_extension : {RECORD_EXTENSION_WIDTH{1'b0}};
                        // ceil(length/16)-1, for an already accepted nonzero length.
                        // Keep the full 32-bit metadata length and its original bounds.
                        payload_beats_after <= i_meta_payload_length[31:4] -
                            (i_meta_payload_length[3:0]==0 ? 28'd1 : 28'd0);
                        last_error_o <= `PCIE_ERROR_NONE;
                        frame_accept_o <= 1'b1;
                    end else begin
                        last_error_o <= metadata_version_valid ? `PCIE_ERROR_PAYLOAD_LENGTH :
                                                                `PCIE_ERROR_HEADER_FORMAT;
                        frame_abort_o <= 1'b1;
                    end
                end

                if ((state_current == STATE_HEADER) && beat_load) begin
                    header_index <= header_index + 1'b1;
                    if (BORROW_EXTENSION==0 && STREAM_EXTENSION==0 && header_index >= 4'd4)
                        record_extension_shift <= record_extension_shift >> 128;
                end

                if (payload_fire) begin
                    if (payload_protocol_error) begin
                        axis_tvalid_o <= 1'b0;
                        frame_abort_o <= 1'b1;
                        if (i_src_tkeep != expected_keep) begin
                            last_error_o <= `PCIE_ERROR_PAYLOAD_KEEP;
                        end else begin
                            last_error_o <= `PCIE_ERROR_PAYLOAD_LAST;
                        end
                    end else if (!payload_expected_last) begin
                        payload_beats_after <= payload_beats_after - 1'b1;
                    end
                end

                if (output_last_fire && (state_current == STATE_WAIT_LAST)) begin
                    frame_done_o <= 1'b1;
                end
            end
        end
    end

endmodule
