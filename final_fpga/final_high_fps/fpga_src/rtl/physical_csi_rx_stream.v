`timescale 1ns / 1ps

// 跨时钟传递 CSI 字事件并统计接收错误
module physical_csi_rx_stream #(parameter integer RX_DIAG_ENABLE=0, parameter integer FRAME_EVENTS_ENABLE = 1,
    parameter integer EVENT_FIFO_DEPTH = 0,
    parameter [31:0] SEQUENCE_INITIAL=32'd0,
    parameter integer FRAME_RESYNC_ENABLE=0) (
    // 时钟与复位
    input  wire        i_word_clk,
    input  wire        i_pixel_clk,
    input  wire        i_reset_n,
    input  wire        i_decoder_reset_n,
    input wire i_identity_rst_n,
    output wire [31:0] o_raw_sequence, m_frame_event_sequence,
    output wire o_raw_identity_valid, m_frame_event_identity_valid,
    output wire o_identity_fault,
    output wire [63:0] o_identity_diag,
    output wire [63:0] o_trace_parser,
    output wire o_trace_trigger,
    input  wire        i_publish_enable,
    output wire       o_fifo_write_ready,
    // CSI 字输入
    input  wire [31:0] i_aligned_word,
    input  wire        i_aligned_valid,
    // RAW 像素流
    output wire [39:0] o_raw_data,
    output wire        o_raw_valid,
    input  wire        i_raw_ready,
    output wire        o_raw_sof,
    output wire        o_raw_eol,
    // Ordered whole-CSI boundary stream, enabled only by explicit parameter.
    output wire m_frame_event_valid,
    input wire m_frame_event_ready,
    output wire [1:0] m_frame_event_kind,
    output wire m_frame_event_ok,
    output wire [3:0] m_frame_event_error,
    // 帧异常与错误计数
    output wire        o_frame_abort,
    output wire [3:0]  o_error_code,
    output reg  [31:0] o_header_ecc_error_count,
    output reg  [31:0] o_payload_crc_error_count,
    output reg  [31:0] o_overflow_error_count,
    output reg  [31:0] o_length_error_count,
    // 包边界控制
    output wire       o_wait_for_sync,
    output wire       o_packet_done
);
    // Identity is a coordinated cohort reset request. Its deassertion
    // must reach WORD and PIX through separate local release chains: the
    // parser also uses this signal in ordinary data/CE logic.
    wire identity_word_reset_n,identity_pixel_reset_n;
    reset_release_sync u_identity_word_reset(
        .i_clk(i_word_clk),.i_async_rst_n(i_identity_rst_n),.o_rst_n(identity_word_reset_n));
    reset_release_sync u_identity_pixel_reset(
        .i_clk(i_pixel_clk),.i_async_rst_n(i_identity_rst_n),.o_rst_n(identity_pixel_reset_n));
    wire [39:0] source_data;
    wire source_valid;
    wire source_sof;
    wire source_eol;
    wire source_abort;
    wire word_identity_fault;
    reg [1:0] identity_fault_pixel;
    always @(posedge i_pixel_clk or negedge identity_pixel_reset_n)begin
        if(!identity_pixel_reset_n)identity_fault_pixel<=0;
        else identity_fault_pixel<={identity_fault_pixel[0],word_identity_fault};
    end
    assign o_identity_fault=identity_fault_pixel[1];
    wire [3:0] source_error;
    wire fifo_source_ready;
    wire unused_ecc_error;
    wire unused_crc_error;
    wire unused_length_error;
    wire [46:0] fifo_read_data;
    wire fifo_read_valid;
    reg drain_frame;
    reg abort_raw_seen, abort_event_seen;
    wire control_fs = !fifo_read_data[42] && fifo_read_data[46:43] == 4'd7;
    wire control_fe = !fifo_read_data[42] && fifo_read_data[46:43] == 4'd6;
    wire control_drop = !fifo_read_data[42] && fifo_read_data[46:43] == 4'd8;
    wire control_head = control_fs || control_fe || control_drop;
    wire raw_transfer = o_raw_valid && i_raw_ready;
    wire event_transfer = m_frame_event_valid && m_frame_event_ready;
    wire drop_data = drain_frame && !fifo_read_data[42] &&
                     !fifo_read_data[40] && !control_head;
    wire read_ready = FRAME_EVENTS_ENABLE == 0 ?
        (i_raw_ready || (drain_frame && !fifo_read_data[42] && !fifo_read_data[40])) :
        control_head ? event_transfer : fifo_read_data[42] ?
        ((abort_raw_seen || raw_transfer) && (abort_event_seen || event_transfer)) :
        (raw_transfer || drop_data);
    reg [1:0] word_reset_sync;
    reg [1:0] fifo_word_reset_sync;
    reg [1:0] pixel_reset_sync;
    wire decoder_domain_reset_n = i_reset_n && i_decoder_reset_n;
    wire publish_reset_n = i_reset_n && i_publish_enable;
    wire word_reset_n = word_reset_sync[1];
    wire fifo_word_reset_n = fifo_word_reset_sync[1];
    wire pixel_reset_n = pixel_reset_sync[1];
    assign o_fifo_write_ready = fifo_source_ready;

    // 共用异步复位分别进入字时钟域与像素时钟域，各域经过两个本地时钟沿后释放
    // 在字时钟域同步释放复位
    always @(posedge i_word_clk or negedge decoder_domain_reset_n) begin
        if (!decoder_domain_reset_n)
            word_reset_sync <= 2'b00;
        else
            word_reset_sync <= {word_reset_sync[0], 1'b1};
    end

    // 在像素时钟域同步释放复位
    always @(posedge i_word_clk or negedge publish_reset_n) begin
        if (!publish_reset_n)
            fifo_word_reset_sync <= 2'b00;
        else
            fifo_word_reset_sync <= {fifo_word_reset_sync[0], 1'b1};
    end

    always @(posedge i_pixel_clk or negedge publish_reset_n) begin
        if (!publish_reset_n)
            pixel_reset_sync <= 2'b00;
        else
            pixel_reset_sync <= {pixel_reset_sync[0], 1'b1};
    end

    // 在字时钟域解析包头并将像素与异常封装为同一事件
    physical_csi_word_core #(.RX_DIAG_ENABLE(RX_DIAG_ENABLE),.FRAME_EVENTS_ENABLE(FRAME_EVENTS_ENABLE),
        .SEQUENCE_INITIAL(SEQUENCE_INITIAL),.FRAME_RESYNC_ENABLE(FRAME_RESYNC_ENABLE)) u_word_core (
        .i_clk(i_word_clk), .i_reset_n(word_reset_n),.i_identity_rst_n(identity_word_reset_n),
        .o_source_sequence_count(),.o_identity_fault(word_identity_fault),.o_identity_diag(o_identity_diag),
        .o_trace_parser(o_trace_parser),.o_trace_trigger(o_trace_trigger),
        .i_word(i_aligned_word), .i_word_valid(i_aligned_valid),
        .i_sink_ready(i_publish_enable ? fifo_source_ready : 1'b1),
        .o_data(source_data), .o_valid(source_valid), .o_sof(source_sof),
        .o_eol(source_eol), .o_abort(source_abort),
        .o_error_code(source_error),
        .o_header_ecc_error(unused_ecc_error),
        .o_payload_crc_error(unused_crc_error),
        .o_length_error(unused_length_error),
        .o_wait_for_sync(o_wait_for_sync),
        .o_packet_done(o_packet_done)
    );

    // 事件跨域后按像素端握手读出，坏帧剩余像素可直接排空
    csi2_async_event_fifo #(.FIFO_DEPTH(EVENT_FIFO_DEPTH)) u_event_fifo (
        .i_write_clk(i_word_clk), .i_write_reset_n(fifo_word_reset_n),
        .i_write_data({source_error, source_abort, source_eol, source_sof, source_data}),
        .i_write_valid(source_valid), .o_write_ready(fifo_source_ready),
        .i_read_clk(i_pixel_clk), .i_read_reset_n(pixel_reset_n),
        .o_read_data(fifo_read_data), .o_read_valid(fifo_read_valid),
        .i_read_ready(read_ready)
    );

    // FS control is before its RAW words in the same unchanged official FIFO.
    reg [31:0] current_sequence;
    reg current_identity_valid;
    assign m_frame_event_sequence=fifo_read_data[31:0];
    assign m_frame_event_identity_valid=fifo_read_data[32] && !control_drop;
    assign o_raw_sequence=fifo_read_data[42] ? fifo_read_data[31:0] : current_sequence;
    assign o_raw_identity_valid=fifo_read_data[42] ? fifo_read_data[32] : current_identity_valid;
    always @(posedge i_pixel_clk or negedge pixel_reset_n)begin
        if(!pixel_reset_n)begin current_sequence<=0;current_identity_valid<=0;end
        else if(event_transfer && control_fs)begin
            current_sequence<=fifo_read_data[31:0];current_identity_valid<=fifo_read_data[32];
        end
    end
    assign o_raw_data = fifo_read_data[39:0];
    assign o_raw_sof = fifo_read_data[40];
    assign o_raw_eol = fifo_read_data[41];
    assign o_frame_abort = fifo_read_data[42];
    assign o_error_code = fifo_read_data[46:43];
    assign o_raw_valid = fifo_read_valid &&
        (!drain_frame || fifo_read_data[40] || fifo_read_data[42]) &&
        ((FRAME_EVENTS_ENABLE == 0) || (!control_head && !abort_raw_seen));
    assign m_frame_event_valid = FRAME_EVENTS_ENABLE != 0 && fifo_read_valid &&
        (control_head || (fifo_read_data[42] && !abort_event_seen));
    assign m_frame_event_kind = FRAME_EVENTS_ENABLE == 0 ? 2'd0 :
        control_drop ? 2'd3 : fifo_read_data[42] ? 2'd2 : control_fe ? 2'd1 : 2'd0;
    assign m_frame_event_ok = FRAME_EVENTS_ENABLE != 0 && !fifo_read_data[42] && !control_drop;
    assign m_frame_event_error = FRAME_EVENTS_ENABLE == 0 ? 4'd0 :
        control_drop ? 4'd3 : !fifo_read_data[42] ? 4'd0 : fifo_read_data[46:43];

    // Both ABORT consumers hold their own obligation. Neither VALID waits
    // for READY; consuming one side cannot pop or duplicate the other side.
    always @(posedge i_pixel_clk or negedge pixel_reset_n)begin
        if(!pixel_reset_n)begin abort_raw_seen<=0; abort_event_seen<=0; end
        else if(fifo_read_valid && read_ready)begin
            abort_raw_seen<=0; abort_event_seen<=0;
        end else if(FRAME_EVENTS_ENABLE != 0 && fifo_read_valid && fifo_read_data[42])begin
            if(raw_transfer)abort_raw_seen<=1;
            if(event_transfer)abort_event_seen<=1;
        end
    end

    // 按读出事件更新丢帧状态与错误计数
    always @(posedge i_pixel_clk or negedge pixel_reset_n) begin
        if (!pixel_reset_n) begin
            drain_frame <= 1'b0;
            o_header_ecc_error_count <= 32'd0;
            o_payload_crc_error_count <= 32'd0;
            o_overflow_error_count <= 32'd0;
            o_length_error_count <= 32'd0;
        end else begin
          if (event_transfer && control_drop)
            o_overflow_error_count <= o_overflow_error_count + 1'b1;
          if (o_raw_valid && i_raw_ready) begin
            if (o_frame_abort) begin
                drain_frame <= 1'b1;
                case (o_error_code)
                    4'd1: o_header_ecc_error_count <= o_header_ecc_error_count + 1'b1;
                    4'd2: o_payload_crc_error_count <= o_payload_crc_error_count + 1'b1;
                    4'd3: o_overflow_error_count <= o_overflow_error_count + 1'b1;
                    4'd4: o_length_error_count <= o_length_error_count + 1'b1;
                    default: o_length_error_count <= o_length_error_count + 1'b1;
                endcase
            end else if (o_raw_sof) begin
                drain_frame <= 1'b0;
            end
          end
        end
    end
endmodule
