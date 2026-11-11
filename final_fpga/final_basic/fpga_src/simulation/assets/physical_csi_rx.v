`timescale 1ns / 1ps

// 接收 CSI RAW10 数据并输出带帧边界的像素流
module physical_csi_rx #(
    // 物理层通道与器件配置
    parameter MIPI_LAN = 4,
    parameter DEVICE = "PH1A",
    parameter integer FRAME_EVENTS_ENABLE = 1
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
    wire unused_delay_value;
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
    always @(posedge o_hs_word_clk or negedge i_reset_n)begin
        if(!i_reset_n)identity_started<=0;
        else if(decoder_reset_count==3'd5)identity_started<=1;
    end
    wire fifo_write_ready;

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
    always @(posedge i_pixel_clk or negedge i_reset_n) begin
        if (!i_reset_n)
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

    csi2_ph1_phy_wrapper #(.MIPI_LAN(MIPI_LAN), .DEVICE(DEVICE)) u_phy (
        .I_debug_button(i_debug_button), .I_ref_clock(i_ref_clk),
        .I_clk_hs_rx_p(i_mipi_clk_p), .I_reset_n(i_reset_n),
        .I_decoder_reset_n(decoder_reset_n),
        .I_hs_data_p(i_mipi_data_p), .I_enable(i_enable),
        .I_wait_for_sync(wait_for_sync), .I_packet_done(packet_done),
        .O_hs_div_clk(o_hs_word_clk), .O_reset_out(phy_reset_n),
        .O_rx_byte_data_align_vaild(lane_byte_valid),
        .O_rx_byte_data_align(lane_byte_data),
        .O_delay_value(unused_delay_value),
        .O_auto_delay_done(o_auto_delay_done),
        .O_dbg_delay(o_delay_debug), .O_dbg_best_len(o_delay_window)
    );

    csi_rx_word_align #(.MIPI_LAN(MIPI_LAN)) u_word_align (
        .I_word_clock(o_hs_word_clk), .I_reset_n(word_reset_n && decoder_reset_n),
        .I_enable(word_enable_sync[1]), .I_packet_done(packet_done),
        .I_wait_for_sync(wait_for_sync), .O_packet_done_out(),
        .I_word_in(lane_byte_data), .I_valid_in(lane_byte_valid),
        .O_word_out(aligned_word), .O_valid_out(aligned_word_valid)
    );

    csi_rx_word_gear_box #(.MIPI_LAN(MIPI_LAN)) u_gearbox (
        .I_word_clock(o_hs_word_clk), .I_reset_n(word_reset_n && decoder_reset_n),
        .I_enable(word_enable_sync[1]), .I_lane_data(aligned_word),
        .I_lane_data_valid(aligned_word_valid),
        .O_word_out(geared_word), .O_valid_out(geared_word_valid)
    );

    physical_csi_rx_stream #(.FRAME_EVENTS_ENABLE(FRAME_EVENTS_ENABLE)) u_stream (
        .i_word_clk(o_hs_word_clk), .i_pixel_clk(i_pixel_clk),
        .i_reset_n(phy_reset_n), .i_decoder_reset_n(decoder_reset_n),
        // Initial calibration starts the first published source cohort. Normal
        // FIFO backpressure never resets the decoder or sequence authority.
        .i_identity_rst_n(i_reset_n && identity_started),.o_identity_diag(),.o_identity_fault(o_source_identity_fault),
        .o_raw_sequence(o_raw_sequence),.o_raw_identity_valid(o_raw_identity_valid),
        .m_frame_event_sequence(m_frame_event_sequence),.m_frame_event_identity_valid(m_frame_event_identity_valid),
        .i_publish_enable(publish_enable),
        .o_fifo_write_ready(fifo_write_ready),
        .i_aligned_word(geared_word), .i_aligned_valid(geared_word_valid),
        .o_raw_data(o_raw_data), .o_raw_valid(o_raw_valid),
        .i_raw_ready(i_raw_ready), .o_raw_sof(o_raw_sof),
        .o_raw_eol(o_raw_eol),  .m_frame_event_valid(m_frame_event_valid), .m_frame_event_ready(m_frame_event_ready),
        .m_frame_event_kind(m_frame_event_kind), .m_frame_event_ok(m_frame_event_ok),
        .m_frame_event_error(m_frame_event_error),
        .o_frame_abort(o_frame_abort),
        .o_error_code(o_error_code),
        .o_header_ecc_error_count(o_header_ecc_error_count),
        .o_payload_crc_error_count(o_payload_crc_error_count),
        .o_overflow_error_count(o_overflow_error_count),
        .o_length_error_count(o_length_error_count),
        .o_wait_for_sync(wait_for_sync), .o_packet_done(packet_done)
    );
endmodule
