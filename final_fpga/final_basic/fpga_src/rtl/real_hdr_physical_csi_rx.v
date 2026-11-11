`timescale 1ns / 1ps

// 接收 CSI RAW10 数据并输出带帧边界的像素流
module real_hdr_physical_csi_rx #(parameter integer RX_DIAG_ENABLE=0,
    // 物理层通道与器件配置
    parameter MIPI_LAN = 4,
    parameter DEVICE = "PH1A",
    parameter integer FRAME_EVENTS_ENABLE = 1,
    parameter integer EVENT_FIFO_DEPTH = 0
)(
    // 参考与 CSI 时钟
    input  wire                i_ref_clk,
    input  wire                i_mipi_clk_p,
    // CSI 数据引脚
    input  wire [MIPI_LAN-1:0] i_mipi_data_p,
    // 像素时钟与复位
    input  wire                i_pixel_clk,
    input  wire                i_reset_n,
    // 接收使能
    input  wire                i_enable,
    input wire i_hdr_mode,i_hdr_cycle_enable,
    output wire [146:0] m_hdr0_data,m_hdr1_data,
    output wire m_hdr0_valid,m_hdr1_valid,
    input wire m_hdr0_ready,m_hdr1_ready,
    // 延迟校准调试控制
    input  wire                i_debug_button,
    // RAW 像素流
    output wire [39:0]         o_raw_data,
    output wire                o_raw_valid,
    input  wire                i_raw_ready,
    output wire                o_raw_sof,
    output wire                o_raw_eol,
    output wire m_frame_event_valid,
    input wire m_frame_event_ready,
    output wire [1:0] m_frame_event_kind,
    output wire m_frame_event_ok,
    output wire [3:0] m_frame_event_error,
    output wire [31:0] m_frame_event_sequence,o_raw_sequence,
    output wire m_frame_event_identity_valid,o_raw_identity_valid,
    output wire o_source_identity_fault,
    output wire [127:0] o_rx_diag_word,
    output wire [255:0] o_rx_trace_sample,
    output wire o_rx_trace_trigger,o_rx_trace_cohort_n,o_rx_trace_enable,
    // 帧异常与错误计数
    output wire                o_frame_abort,
    output wire [3:0]          o_error_code,
    output wire [31:0]         o_header_ecc_error_count,
    output wire [31:0]         o_payload_crc_error_count,
    output wire [31:0]         o_overflow_error_count,
    output wire [31:0]         o_length_error_count,
    // 字时钟输出
    output wire                o_hs_word_clk,
    // 物理层校准状态
    output wire                o_auto_delay_done,
    output wire [7:0]          o_delay_debug,
    output wire [5:0]          o_delay_window,
    output wire                o_phy_ready,
    // Read-only byte/word taps for the camera-only diagnostic top.
    output wire [8*MIPI_LAN-1:0] o_diag_lane_bytes,
    output wire [MIPI_LAN-1:0]   o_diag_lane_valid,
    output wire [8*MIPI_LAN-1:0] o_diag_aligned_word,
    output wire                  o_diag_aligned_valid,
    output wire [31:0]           o_diag_geared_word,
    output wire                  o_diag_geared_valid,
    output wire                  o_diag_wait_sync,
    output wire                  o_diag_packet_done,
    output wire                  o_diag_publish_enable,
    output wire                  o_diag_word_reset_n
);
    wire [MIPI_LAN-1:0] lane_byte_valid;
    wire [8*MIPI_LAN-1:0] lane_byte_data;
    wire [8*MIPI_LAN-1:0] aligned_word;
    wire aligned_word_valid;
    wire [31:0] geared_word;
    wire geared_word_valid;
    wire phy_reset_n;
    wire wait_for_sync;
    wire packet_done;
    wire hdr_packet_continue;
    wire [8*MIPI_LAN-1:0] trace_raw_bytes;
    wire [3*MIPI_LAN-1:0] trace_byte_offset,trace_word_taps;
    wire [MIPI_LAN-1:0] trace_byte_found;
    wire [15:0] trace_calibration;
    wire [63:0] trace_parser;
    wire unused_delay_value;
    // i_reset_n is the coordinated REF-domain source-cohort request.
    // PHY reset is WORD-local but may drop on clock loss; it must never
    // restart source identity. Release this outer cohort independently in
    // WORD and PIX before it reaches functional state or status selection.
    wire cohort_word_rst_n,cohort_pixel_rst_n;
    reset_release_sync u_cohort_word_reset(
        .i_clk(o_hs_word_clk),.i_async_rst_n(i_reset_n),.o_rst_n(cohort_word_rst_n));
    reset_release_sync u_cohort_pixel_reset(
        .i_clk(i_pixel_clk),.i_async_rst_n(i_reset_n),.o_rst_n(cohort_pixel_rst_n));
    reg [1:0] hdr_mode_pixel;
    always @(posedge i_pixel_clk or negedge cohort_pixel_rst_n)begin
        if(!cohort_pixel_rst_n)hdr_mode_pixel<=0;
        else hdr_mode_pixel<={hdr_mode_pixel[0],i_hdr_mode};
    end
    reg [1:0] phy_ready_sync;
    reg [1:0] word_reset_sync;
    reg [1:0] word_enable_sync;
    wire word_reset_n = word_reset_sync[1];
    reg [2:0] decoder_reset_count;
    reg decoder_reset_n, publish_enable;
    // Calibration traffic is outside the initial cohort. Once started, a
    // later PHY/decoder reset may invalidate trust but must not rewind the
    // counter under the same product session. i_reset_n is the coordinated
    // outer source-cohort reset, independent of phy_reset_n.
    reg identity_started;
    always @(posedge o_hs_word_clk or negedge cohort_word_rst_n)begin
        if(!cohort_word_rst_n)identity_started<=0;
        else if(decoder_reset_count==3'd5)identity_started<=1;
    end
    wire fifo_write_ready,sdr_fifo_write_ready,hdr_fifo_write_ready;
    wire sdr_wait_for_sync,sdr_packet_done,hdr_wait_for_sync,hdr_packet_done;
    wire sdr_identity_fault,hdr_identity_fault;
    wire [31:0] sdr_ecc,sdr_crc,sdr_overflow,sdr_length,hdr_crc,hdr_overflow,hdr_length;
    reg [1:0] hdr_mode_word,hdr_cycle_word;
    // Preserve a supported in-flight same-burst header. The restricted HDR
    // boundary adapter rejects ambiguous trail; neither aligner is replaced.
    wire phy_packet_done=hdr_mode_word[1] ?
        (hdr_packet_done && !hdr_packet_continue) : sdr_packet_done;
    always @(posedge o_hs_word_clk or negedge cohort_word_rst_n)begin
        if(!cohort_word_rst_n)begin hdr_mode_word<=0;hdr_cycle_word<=0;end
        else begin hdr_mode_word<={hdr_mode_word[0],i_hdr_mode};hdr_cycle_word<={hdr_cycle_word[0],i_hdr_cycle_enable};end
    end
    assign fifo_write_ready=hdr_mode_word[1]?hdr_fifo_write_ready:sdr_fifo_write_ready;
    assign wait_for_sync=hdr_mode_word[1]?hdr_wait_for_sync:sdr_wait_for_sync;
    assign packet_done=hdr_mode_word[1]?hdr_packet_done:sdr_packet_done;
    assign o_source_identity_fault=hdr_mode_pixel[1]?hdr_identity_fault:sdr_identity_fault;
    assign o_header_ecc_error_count=hdr_mode_pixel[1]?{31'd0,hdr_identity_fault}:sdr_ecc;
    assign o_payload_crc_error_count=hdr_mode_pixel[1]?hdr_crc:sdr_crc;
    assign o_overflow_error_count=hdr_mode_pixel[1]?hdr_overflow:sdr_overflow;
    assign o_length_error_count=hdr_mode_pixel[1]?hdr_length:sdr_length;

    // Calibration needs the live decoder feedback. Once its final tap is
    // applied, clear only packet decoding for four byte clocks and start
    // publication from a fresh sync byte. PHY and eye scan remain running.
    always @(posedge o_hs_word_clk or negedge phy_reset_n) begin
        if (!phy_reset_n) begin
            decoder_reset_count <= 3'd0;
            decoder_reset_n <= 1'b1;
            publish_enable <= 1'b0;
        end else if (!o_auto_delay_done) begin
            decoder_reset_count <= 3'd0;
            decoder_reset_n <= 1'b1;
            publish_enable <= 1'b0;
        end else if (decoder_reset_count < 3'd4) begin
            decoder_reset_count <= decoder_reset_count + 1'b1;
            decoder_reset_n <= 1'b0;
            publish_enable <= 1'b0;
        end else if (decoder_reset_count == 3'd4) begin
            // Release both FIFO ports, then wait for the actual write-ready
            // signal before accepting a new decoder event.
            decoder_reset_n <= 1'b0;
            publish_enable <= 1'b1;
            if (fifo_write_ready) begin
                decoder_reset_count <= 3'd5;
                decoder_reset_n <= 1'b1;
            end
        end else begin
            // The barrier is one-shot. FIFO backpressure during normal
            // capture must never reset the packet decoder.
            decoder_reset_n <= 1'b1;
            publish_enable <= 1'b1;
        end
    end

    // 物理层复位由参考时钟域产生，停钟时异步断言并在恢复后的字时钟域同步释放
    // 接收使能也先同步，再交给字对齐器和齿轮箱使用
    // 同步字时钟域复位和接收使能
    always @(posedge o_hs_word_clk or negedge phy_reset_n) begin
        if (!phy_reset_n) begin
            word_reset_sync <= 2'b00;
            word_enable_sync <= 2'b00;
        end else begin
            word_reset_sync <= {word_reset_sync[0], 1'b1};
            word_enable_sync <= {word_enable_sync[0], i_enable};
        end
    end

    // 将物理层就绪状态同步到像素时钟域
    always @(posedge i_pixel_clk or negedge cohort_pixel_rst_n) begin
        if (!cohort_pixel_rst_n)
            phy_ready_sync <= 2'b00;
        else
            phy_ready_sync <= {phy_ready_sync[0], phy_reset_n};
    end
    assign o_phy_ready = phy_ready_sync[1];
    assign o_diag_lane_bytes = lane_byte_data;
    assign o_diag_lane_valid = lane_byte_valid;
    assign o_diag_aligned_word = aligned_word;
    assign o_diag_aligned_valid = aligned_word_valid;
    assign o_diag_geared_word = geared_word;
    assign o_diag_geared_valid = geared_word_valid;
    assign o_diag_wait_sync = wait_for_sync;
    assign o_diag_packet_done = packet_done;
    assign o_diag_publish_enable = publish_enable;
    assign o_diag_word_reset_n = word_reset_n && decoder_reset_n;
    // RT/V1 is a passive WORD-domain bus. No tap is used by capture control.
    assign o_rx_trace_cohort_n=cohort_word_rst_n && identity_started && !hdr_mode_word[1];
    assign o_rx_trace_enable=!hdr_mode_word[1];
    assign o_rx_trace_sample={3'd0,o_rx_trace_trigger,cohort_word_rst_n,phy_reset_n,
        identity_started,hdr_mode_word[1],publish_enable,word_reset_n,decoder_reset_n,
        phy_packet_done,packet_done,wait_for_sync,geared_word_valid,aligned_word_valid,
        trace_calibration,trace_parser,trace_word_taps,trace_byte_found,trace_byte_offset,
        lane_byte_valid,geared_word,aligned_word,lane_byte_data,trace_raw_bytes};

    csi2_ph1_phy_wrapper #(.MIPI_LAN(MIPI_LAN), .DEVICE(DEVICE)) u_phy (
        .I_debug_button(i_debug_button), .I_ref_clock(i_ref_clk),
        .I_clk_hs_rx_p(i_mipi_clk_p), .I_reset_n(i_reset_n),
        .I_decoder_reset_n(decoder_reset_n),
        .I_hs_data_p(i_mipi_data_p), .I_enable(i_enable),
        .I_wait_for_sync(wait_for_sync), .I_packet_done(phy_packet_done),
        .O_hs_div_clk(o_hs_word_clk), .O_reset_out(phy_reset_n),
        .O_rx_byte_data_align_vaild(lane_byte_valid),
        .O_rx_byte_data_align(lane_byte_data),
        .O_delay_value(unused_delay_value),
        .O_auto_delay_done(o_auto_delay_done),
        .O_dbg_delay(o_delay_debug), .O_dbg_best_len(o_delay_window)
        ,.O_diag_raw_bytes(trace_raw_bytes),.O_diag_byte_offset(trace_byte_offset)
        ,.O_diag_byte_found(trace_byte_found),.O_diag_calibration(trace_calibration)
    );

    csi_rx_word_align_observed #(.MIPI_LAN(MIPI_LAN)) u_word_align (
        .I_word_clock(o_hs_word_clk), .I_reset_n(word_reset_n && decoder_reset_n),
        .I_enable(word_enable_sync[1]), .I_packet_done(phy_packet_done),
        .I_wait_for_sync(wait_for_sync), .O_packet_done_out(),
        .I_word_in(lane_byte_data), .I_valid_in(lane_byte_valid),
        .O_word_out(aligned_word), .O_valid_out(aligned_word_valid),.o_diag_taps(trace_word_taps)
    );

    csi_rx_word_gear_box #(.MIPI_LAN(MIPI_LAN)) u_gearbox (
        .I_word_clock(o_hs_word_clk), .I_reset_n(word_reset_n && decoder_reset_n),
        .I_enable(word_enable_sync[1]), .I_lane_data(aligned_word),
        .I_lane_data_valid(aligned_word_valid),
        .O_word_out(geared_word), .O_valid_out(geared_word_valid)
    );

    wire [63:0] sdr_identity_diag;
    wire [31:0] hdr_fs0_count,hdr_fs1_count;
    assign o_rx_diag_word={hdr_fs1_count,hdr_fs0_count,sdr_identity_diag};
    // Only SDR may reestablish a frame identity after a receive failure.
    // HDR keeps its independent dual-VC continuity and packet-boundary logic.
    physical_csi_rx_stream #(.RX_DIAG_ENABLE(RX_DIAG_ENABLE),.FRAME_EVENTS_ENABLE(FRAME_EVENTS_ENABLE),
        .EVENT_FIFO_DEPTH(EVENT_FIFO_DEPTH), .FRAME_RESYNC_ENABLE(1)) u_stream (
        .i_word_clk(o_hs_word_clk), .i_pixel_clk(i_pixel_clk),
        .i_reset_n(phy_reset_n&&!hdr_mode_word[1]), .i_decoder_reset_n(decoder_reset_n),
        // Initial calibration starts the first published source cohort. Normal
        // FIFO backpressure never resets the decoder or sequence authority.
        .i_identity_rst_n(i_reset_n && identity_started&&!hdr_mode_word[1]),.o_identity_fault(sdr_identity_fault),
        .o_identity_diag(sdr_identity_diag),
        .o_trace_parser(trace_parser),.o_trace_trigger(o_rx_trace_trigger),
        .o_raw_sequence(o_raw_sequence),.o_raw_identity_valid(o_raw_identity_valid),
        .m_frame_event_sequence(m_frame_event_sequence),.m_frame_event_identity_valid(m_frame_event_identity_valid),
        .i_publish_enable(publish_enable&&!hdr_mode_word[1]),
        .o_fifo_write_ready(sdr_fifo_write_ready),
        .i_aligned_word(geared_word), .i_aligned_valid(geared_word_valid),
        .o_raw_data(o_raw_data), .o_raw_valid(o_raw_valid),
        .i_raw_ready(i_raw_ready), .o_raw_sof(o_raw_sof),
        .o_raw_eol(o_raw_eol),  .m_frame_event_valid(m_frame_event_valid), .m_frame_event_ready(m_frame_event_ready),
        .m_frame_event_kind(m_frame_event_kind), .m_frame_event_ok(m_frame_event_ok),
        .m_frame_event_error(m_frame_event_error),
        .o_frame_abort(o_frame_abort),
        .o_error_code(o_error_code),
        .o_header_ecc_error_count(sdr_ecc),
        .o_payload_crc_error_count(sdr_crc),
        .o_overflow_error_count(sdr_overflow),
        .o_length_error_count(sdr_length),
        .o_wait_for_sync(sdr_wait_for_sync), .o_packet_done(sdr_packet_done)
    );
    real_hdr_csi_capture_stream u_hdr_stream(
        .i_word_clk(o_hs_word_clk),.i_pixel_clk(i_pixel_clk),
        .i_reset_n(phy_reset_n&&hdr_mode_word[1]),.i_decoder_reset_n(decoder_reset_n),
        .i_identity_rst_n(i_reset_n&&identity_started&&hdr_mode_word[1]),
        .i_publish_enable(publish_enable&&hdr_mode_word[1]),.i_cycle_enable(hdr_cycle_word[1]),
        .i_word(geared_word),.i_word_valid(geared_word_valid),
        .o_fifo_write_ready(hdr_fifo_write_ready),.o_wait_for_sync(hdr_wait_for_sync),.o_packet_done(hdr_packet_done),.o_packet_continue(hdr_packet_continue),.o_identity_fault(hdr_identity_fault),
        .m0_data(m_hdr0_data),.m1_data(m_hdr1_data),.m0_valid(m_hdr0_valid),.m1_valid(m_hdr1_valid),.m0_ready(m_hdr0_ready),.m1_ready(m_hdr1_ready),
        .o_crc_errors(hdr_crc),.o_overflow_errors(hdr_overflow),.o_format_errors(hdr_length),
        .o_sequence_count0(hdr_fs0_count),.o_sequence_count1(hdr_fs1_count),.o_fs0_observe_valid(),.o_fs1_observe_valid(),.o_fs0_number(),.o_fs1_number());
endmodule
