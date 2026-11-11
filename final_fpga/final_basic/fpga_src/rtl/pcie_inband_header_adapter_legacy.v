`timescale 1ns / 1ps
`include "pcie_protocol_v1.vh"

// 校验带内帧头并分离元数据与载荷
module pcie_inband_header_adapter_legacy #(
    parameter integer RECORD_V2_ENABLE = 0,
    parameter integer RECORD_V3_ENABLE = 0,
    parameter integer RECORD_EXTENSION_WIDTH = RECORD_V3_ENABLE ? 3072 : 1024
) (
    // 时钟与复位
    input  wire i_clk,
    input  wire i_rst_n,

    // 带内输入流
    input  wire [127:0] i_src_tdata,
    input  wire [15:0] i_src_tkeep,
    input  wire i_src_tvalid,
    output wire o_src_tready,
    input  wire i_src_tlast,
    // The owner selects the format while all record domains are quiescent.
    // A header never changes this selection by carrying its own version.
    input  wire [15:0] i_selected_version,

    // 帧元数据输出
    output wire o_meta_valid,
    input  wire i_meta_ready,
    output wire [31:0] o_meta_frame_sequence,
    output wire [31:0] o_meta_payload_length,
    output wire [15:0] o_meta_width,
    output wire [15:0] o_meta_height,
    output wire [7:0] o_meta_pixel_format,
    output wire [7:0] o_meta_compression,
    output wire [7:0] o_meta_quality,
    output wire [63:0] o_meta_timestamp_ns,
    output wire [31:0] o_meta_status,
    output wire [31:0] o_meta_error_code,
    output wire [15:0] o_meta_slot_id,
    output wire [31:0] o_meta_payload_crc32,
    output wire [15:0] o_meta_record_version,
    output wire [RECORD_EXTENSION_WIDTH-1:0] o_meta_record_extension,

    // 载荷输出流
    output wire [127:0] o_payload_tdata,
    output wire [15:0] o_payload_tkeep,
    output wire o_payload_tvalid,
    input  wire i_payload_tready,
    output wire o_payload_tlast,

    // 错误与活动状态
    output wire o_header_error, // 带内帧头校验失败
    output wire [31:0] o_last_error,
    output wire o_busy
);
    generate if(RECORD_EXTENSION_WIDTH!=1024 && RECORD_EXTENSION_WIDTH!=3072) begin : invalid_record_width
        RECORD_EXTENSION_REQUIRES_1024_OR_3072 u_invalid_record_width();
    end endgenerate
    generate if(RECORD_V3_ENABLE && RECORD_EXTENSION_WIDTH!=3072) begin : invalid_v3_width
        RECORD_V3_REQUIRES_3072 u_invalid_v3_width();
    end endgenerate
    localparam integer HEADER_INDEX_WIDTH=RECORD_V3_ENABLE ? 5 : 4;
    `include "pcie_record_v3_validate.vh"

    localparam [2:0] STATE_HEADER = 3'd0;
    localparam [2:0] STATE_META = 3'd1;
    localparam [2:0] STATE_PAYLOAD = 3'd2;
    localparam [2:0] STATE_DRAIN = 3'd3;

    reg [2:0] state_current;
    reg [2:0] state_next;
    wire [HEADER_INDEX_WIDTH-1:0] header_index;
    reg [HEADER_INDEX_WIDTH-1:0] index_candidate, index_history;
    reg header_accept_q, error_candidate_q;
    reg [15:0] selected_version;
    reg [RECORD_EXTENSION_WIDTH-1:0] record_extension;
    reg [127:0] header_zero;
    reg [127:0] header_one;
    reg [127:0] header_two;
    reg [31:0] last_error_o;

    wire source_fire;
    wire header_capture;
    wire header_complete;
    wire header_beat_valid;
    wire final_header_valid;
    wire base_header_valid;
    wire extension_header_valid;
    wire [15:0] current_selection;
    wire [HEADER_INDEX_WIDTH-1:0] last_header_index;
    reg [RECORD_EXTENSION_WIDTH-1:0] extension_candidate;
    wire [2047:0] sparse_candidate=extension_candidate >> 1024;

    // 按帧头和载荷阶段生成源端反压
    assign o_src_tready = (state_current == STATE_HEADER) ||
                          (state_current == STATE_DRAIN) ||
                          ((state_current == STATE_PAYLOAD) && i_payload_tready);
    assign source_fire = i_src_tvalid && o_src_tready;
    // HEADER is always ready. Keep its late acceptance separate from the
    // independently computed counter value and the wide header-bank enables.
    assign header_capture = (state_current == STATE_HEADER) && i_src_tvalid;
    assign header_complete = !header_beat_valid || header_index == last_header_index ||
                             (header_index == 4'd3 && !base_header_valid);
    assign o_meta_valid = state_current == STATE_META;
    assign o_payload_tdata = i_src_tdata;
    assign o_payload_tkeep = i_src_tkeep;
    assign o_payload_tvalid = (state_current == STATE_PAYLOAD) && i_src_tvalid;
    assign o_payload_tlast = i_src_tlast;
    assign o_header_error = header_accept_q && error_candidate_q;
    assign o_last_error = last_error_o;
    assign o_busy = state_current != STATE_HEADER || header_index != 4'd0;
    assign current_selection = (RECORD_V2_ENABLE != 0 || RECORD_V3_ENABLE != 0) ? i_selected_version : 16'd1;
    assign last_header_index = selected_version == 16'd3 ? 5'd27 : (selected_version == 16'd2 ? 4'd11 : 4'd3);
    always @(*) begin
        extension_candidate=record_extension;
        if(header_index>=4) extension_candidate[(header_index-4)*128+:128]=i_src_tdata;
    end

    assign o_meta_frame_sequence = header_zero[95:64];
    assign o_meta_payload_length = header_zero[127:96];
    assign o_meta_width = header_one[15:0];
    assign o_meta_height = header_one[31:16];
    assign o_meta_pixel_format = header_one[39:32];
    assign o_meta_compression = header_one[47:40];
    assign o_meta_quality = header_one[55:48];
    assign o_meta_timestamp_ns = header_one[127:64];
    assign o_meta_status = header_two[31:0];
    assign o_meta_error_code = header_two[63:32];
    assign o_meta_slot_id = header_two[79:64];
    assign o_meta_payload_crc32 = header_two[127:96];
    assign o_meta_record_version = selected_version;
    assign o_meta_record_extension = (RECORD_V2_ENABLE != 0 || RECORD_V3_ENABLE != 0) && selected_version != 16'd1 ?
                                     record_extension : {RECORD_EXTENSION_WIDTH{1'b0}};

    assign header_beat_valid = (i_src_tkeep == 16'hffff) && !i_src_tlast;
    assign base_header_valid = header_beat_valid && (i_src_tdata == 128'd0) &&
                                (header_zero[31:0] == `PCIE_FRAME_MAGIC) &&
                                (header_zero[47:32] == selected_version) &&
                                (selected_version == 16'd1 || ((RECORD_V2_ENABLE != 0 || RECORD_V3_ENABLE != 0) && selected_version == 16'd2) ||
                                 (RECORD_V3_ENABLE != 0 && selected_version == 16'd3)) &&
                                (header_zero[63:48] == (selected_version == 16'd3 ? 16'd448 : (selected_version == 16'd2 ? 16'd192 : 16'd64))) &&
                                (header_zero[127:96] != 32'd0) &&
                                (header_zero[127:96] <= `PCIE_MAX_PAYLOAD) &&
                                (header_one[63:56] == 8'h01) &&
                                (header_two[95:80] == 16'd0) &&
                                (selected_version == 16'd1 || header_two[79:64] < `PCIE_RECORD_V2_SLOT_COUNT);
    // Wire structure and exact source association. Algorithm qualification and
    // observation-grid arithmetic belong to their producers and the host parser.
    assign extension_header_valid = header_beat_valid &&
        extension_candidate[31:0] == `PCIE_RECORD_V2_EXTENSION_MAGIC &&
        extension_candidate[47:32] == `PCIE_RECORD_V2_SCHEMA_VERSION &&
        extension_candidate[63:60] == 4'd0 && extension_candidate[1023:960] == 64'd0 &&
        extension_candidate[223:192] != 0 && extension_candidate[255:224] != 0 &&
        (!extension_candidate[48] ? extension_candidate[191:64] == 128'd0 :
            (extension_candidate[95:64] != 0 && extension_candidate[159:128] == header_zero[95:64] &&
             extension_candidate[167:160] <= 1 && extension_candidate[175:168] <= 1 &&
             (extension_candidate[183:176] == 1 || extension_candidate[183:176] == 2) &&
             extension_candidate[191:184] <= 2)) &&
        (!extension_candidate[49] ? {extension_candidate[383:352],extension_candidate[287:256]} == 64'd0 :
                                    extension_candidate[287:256] != 0) &&
        (extension_candidate[50] || extension_candidate[319:288] == 0) &&
        (extension_candidate[51] || extension_candidate[351:320] == 0) &&
        (!extension_candidate[52] ? (header_one[127:64] == 0 && extension_candidate[943:936] == 0) :
             (extension_candidate[943:936] == 1 || extension_candidate[943:936] == 2)) &&
        (!extension_candidate[53] ? extension_candidate[447:384] == 0 : extension_candidate[447:384] != 0) &&
        (!extension_candidate[54] ? extension_candidate[511:448] == 0 : extension_candidate[511:448] != 0) &&
        (!extension_candidate[55] ? extension_candidate[575:512] == 0 : extension_candidate[575:512] != 0) &&
        (!extension_candidate[56] ? extension_candidate[735:576] == 0 :
            (extension_candidate[48] && extension_candidate[607:576] == extension_candidate[95:64] &&
             extension_candidate[639:608] == extension_candidate[127:96] &&
             extension_candidate[671:640] == extension_candidate[159:128] &&
             extension_candidate[695:672] == extension_candidate[183:160] &&
             extension_candidate[703:696] == 8'd1 && extension_candidate[719:704] == 16'd0 &&
             extension_candidate[735:720] == `PCIE_RECORD_V2_NEUTRAL_CONTEXT_SCHEMA)) &&
        (!extension_candidate[57] ? extension_candidate[919:736] == 0 :
            (extension_candidate[56] && extension_candidate[751:736] != 0 &&
             extension_candidate[751:736] == extension_candidate[767:752] &&
             extension_candidate[879:864] != 0 && extension_candidate[895:880] != 0 &&
             extension_candidate[903:896] == 1 && extension_candidate[911:904] == 0 &&
             extension_candidate[919:912] == 1)) &&
        (!(extension_candidate[58] || extension_candidate[59]) || extension_candidate[48]) &&
        extension_candidate[959:947] == 0;
    assign final_header_valid = selected_version == 16'd3 ?
        (extension_header_valid && sparse_v3_valid(sparse_candidate)) :
        (selected_version == 16'd2 ? extension_header_valid : base_header_valid);

    // 根据输入拍握手选择帧头解析状态
    always @(*) begin
        state_next = state_current;
        case (state_current)
            STATE_HEADER: begin
                if (source_fire) begin
                    if (!header_beat_valid) begin
                        state_next = i_src_tlast ? STATE_HEADER : STATE_DRAIN;
                    end else if (header_index == 4'd3 && !base_header_valid) begin
                        state_next = STATE_DRAIN;
                    end else if (header_index == last_header_index) begin
                        state_next = final_header_valid ? STATE_META : STATE_DRAIN;
                    end
                end
            end
            STATE_META: begin
                if (i_meta_ready) begin
                    state_next = STATE_PAYLOAD;
                end
            end
            STATE_PAYLOAD: begin
                if (source_fire && i_src_tlast) begin
                    state_next = STATE_HEADER;
                end
            end
            STATE_DRAIN: begin
                if (source_fire && i_src_tlast) begin
                    state_next = STATE_HEADER;
                end
            end
            default: state_next = STATE_HEADER;
        endcase
    end

    // 寄存帧头解析状态
    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            state_current <= STATE_HEADER;
        end else begin
            state_current <= state_next;
        end
    end

    // Acceptance is registered separately from candidate interpretation.
    // The selected index and error still describe this same source edge;
    // late VALID does not traverse header qualification or index feedback.
    assign header_index = header_accept_q ? index_candidate : index_history;
    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            header_accept_q <= 0;
            error_candidate_q <= 0;
            index_candidate <= 0;
            index_history <= 0;
        end else begin
            header_accept_q <= header_capture;
            error_candidate_q <= !header_beat_valid ||
                (header_index == 4'd3 && !base_header_valid) ||
                (header_index == last_header_index && !final_header_valid);
            index_candidate <= header_complete ? {HEADER_INDEX_WIDTH{1'b0}} : header_index + 1'b1;
            index_history <= header_index;
        end
    end

    // 保存帧头字段并跟踪载荷长度
    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            selected_version <= 16'd1;
            record_extension <= {RECORD_EXTENSION_WIDTH{1'b0}};
            header_zero <= 128'd0;
            header_one <= 128'd0;
            header_two <= 128'd0;
            last_error_o <= `PCIE_ERROR_NONE;
        end else begin
            if (header_capture) begin
                if (!header_beat_valid) begin
                    last_error_o <= `PCIE_ERROR_HEADER_FORMAT;
                end else begin
                    case (header_index)
                        4'd0: begin
                            header_zero <= i_src_tdata;
                            selected_version <= current_selection;
                            record_extension <= {RECORD_EXTENSION_WIDTH{1'b0}};
                        end
                        4'd1: header_one <= i_src_tdata;
                        4'd2: header_two <= i_src_tdata;
                        default: begin
                            if (header_index >= 4'd4)
                                record_extension <= extension_candidate;
                        end
                    endcase
                    if (header_index == last_header_index || (header_index == 4'd3 && !base_header_valid)) begin
                            if (!final_header_valid || (header_index == 4'd3 && !base_header_valid)) begin
                                last_error_o <= `PCIE_ERROR_HEADER_FORMAT;
                            end else begin
                                last_error_o <= `PCIE_ERROR_NONE;
                            end
                    end
                end
            end
        end
    end

endmodule
