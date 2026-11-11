`timescale 1ns / 1ps
`include "jpeg_quant_config.vh"

// 串接JPEG编码流水线并管理单帧结果
module jpeg_encoder_top #(
    parameter integer MAX_WIDTH = 3840,
    parameter integer MAX_HEIGHT = 2160,
    parameter integer SHARED_STREAM_ENABLE = 0,
    parameter ROM_INIT_ROOT = `JPEG_QUANT_DEFAULT_ROOT,
    parameter ROM_INIT_SUFFIX = ".mif",
    parameter integer TINY_DISTRIBUTED_RAM_ENABLE = 0,
    parameter integer COEFF_BANKED_STORAGE_ENABLE = 0,
    parameter integer MCU_ROW_STREAM_ENABLE = 0,
    parameter integer FIXED_GEOMETRY_ENABLE = 0,
    parameter integer DUAL_GEOMETRY_ENABLE = 0
) (
    // 时钟与复位
    input wire i_clk,
    input wire i_rst_n,

    // 像素输入流
    input wire [95:0] i_rgb,
    input wire [31:0] i_luma,
    input wire [7:0] i_quality,
    input wire [31:0] i_session_id, i_mode_epoch,
    input wire i_camera_id,
    input wire [15:0] i_restart_mcus,
    input wire i_rgb_valid,
    output wire o_rgb_ready,
    input wire i_sof,
    input wire i_eol,
    input wire [31:0] i_capture_id,
    input wire [12:0] i_width,
    input wire [12:0] i_height,

    // 帧状态输入
    input wire i_frame_status_valid,
    output wire o_frame_status_ready,
    input wire [31:0] i_frame_status_id,
    input wire i_frame_ok,

    // 编码载荷输出
    output wire [127:0] o_axis_tdata,
    output wire [15:0] o_axis_tkeep,
    output wire o_axis_tvalid,
    input wire i_axis_tready,
    output wire o_axis_tlast,

    // 帧结果输出
    output wire o_result_valid,
    input wire i_result_ready,
    output wire [31:0] o_result_id,
    output wire o_result_ok,
    output wire [24:0] o_payload_length, // 编码结束时得到的实际字节数
    output wire [7:0] o_error_code,
    output wire [7:0] o_result_quality,
    output wire [31:0] o_result_epoch,
    output wire o_idle
);
    localparam [2:0] S_IDLE=0, S_RUN=1, S_ABORT=2,
                     S_DRAIN=3, S_RESULT=4;
    localparam [7:0] ERR_NONE=0, ERR_STATUS=1, ERR_MCU=2,
                     ERR_ENTROPY=3, ERR_FORMAT=4, ERR_PACKER=5,
                     ERR_INPUT=6;
    reg [2:0] state;
    reg [31:0] frame_id;
    reg [12:0] frame_width, frame_height;
    reg [7:0] quality;
    reg [31:0] session_id,mode_epoch;
    reg camera_id;
    reg [15:0] restart_mcus;
    reg status_seen, status_ok, last_seen, input_done;
    reg [12:0] rows_seen;
    reg [24:0] byte_count;
    reg [7:0] error_code;
    wire start_fire, private_rst_n, aborting;
    reg abort_released;
    wire color_ready, color_valid, color_sof, color_eol;
    wire [31:0] color_y, color_id;
    wire [15:0] color_cb, color_cr;
    wire mcu_ready, mcu_valid, mcu_last, mcu_error;
    wire [511:0] mcu_samples;
    wire [1:0] mcu_comp, mcu_index;
    wire [8:0] mcu_x, mcu_y;
    wire [31:0] mcu_id, mcu_error_id;
    wire [2:0] mcu_error_code;
    wire dct_ready, dct_valid, dct_last;
    wire [1023:0] dct_coeff;
    wire [1:0] dct_comp, dct_index;
    wire [8:0] dct_x, dct_y;
    wire [31:0] dct_id;
    wire quant_ready, quant_valid, quant_last;
    wire quant_error,coeff_token_valid,coeff_token_ready;
    wire [146:0] coeff_token;
    wire [6:0] table_quality;
    wire table_component,table_enable;
    wire [2:0] table_column;
    wire [63:0] table_quantizers;
    wire [1023:0] quant_coeff;
    wire [1:0] quant_comp, quant_index;
    wire [8:0] quant_x, quant_y;
    wire [31:0] quant_id;
    wire ent_ready, ent_valid, ent_last, ent_idle, ent_done, ent_error;
    wire [7:0] ent_byte, ent_error_code;
    wire [31:0] ent_error_id;
    wire fmt_start_ready, fmt_ent_ready, fmt_valid, fmt_last, fmt_idle, fmt_error;
    wire [7:0] fmt_byte;
    wire [31:0] fmt_id;
    wire pack_ready, pack_idle, pack_error, pack_overflow;
    // Two local bytes cut the packer's combinational READY/reset cone before
    // it can reach a ROM port. The one frame owner retains capture_id until
    // its actual AXIS tail/result; this queue needs only {last, byte}.
    reg [8:0] fmt_slot0, fmt_slot1;
    reg fmt_read_slot, fmt_write_slot;
    reg [1:0] fmt_count;
    wire fmt_queue_ready = fmt_count < 2;
    wire fmt_queue_valid = fmt_count != 0;
    wire [8:0] fmt_queue_data = fmt_read_slot ? fmt_slot1 : fmt_slot0;
    wire fmt_push = fmt_valid && fmt_queue_ready && !aborting;
    wire fmt_pop = fmt_queue_valid && pack_ready;
    wire fmt_queue_empty = fmt_count == 0;
    wire axis_fire, status_fire, matching_status, input_changed;
    reg [4:0] beat_bytes;
    integer k;

    // 中止是同步清空脉冲，不能持续保持
    // 否则熵编码器无法返回空闲，顶层 S_ABORT 到 S_DRAIN 的转换会停滞
    // 编码器中止状态停止后续帧发布
    assign aborting = (state == S_ABORT) && !abort_released;
    assign private_rst_n = i_rst_n && !aborting;
    assign o_rgb_ready = i_rst_n && ((state == S_RUN && !input_done && color_ready) ||
                         (state == S_IDLE && i_sof && fmt_start_ready &&
                          ent_idle && pack_idle && fmt_queue_empty && color_ready));
    assign start_fire = i_rgb_valid && o_rgb_ready && state == S_IDLE;
    assign o_frame_status_ready = i_rst_n;
    assign status_fire = i_frame_status_valid && o_frame_status_ready;
    assign matching_status = status_fire && state == S_RUN &&
                             i_frame_status_id == frame_id;
    assign input_changed = i_rgb_valid && o_rgb_ready && state == S_RUN &&
                           (i_capture_id != frame_id || i_width != frame_width ||
                            i_height != frame_height || i_sof);
    assign axis_fire = o_axis_tvalid && i_axis_tready;
    assign o_result_valid = state == S_RESULT;
    assign o_result_id = frame_id;
    assign o_result_ok = state == S_RESULT && error_code == ERR_NONE;
    assign o_payload_length = byte_count;
    assign o_error_code = error_code;
    assign o_result_quality = quality;
    assign o_result_epoch = mode_epoch;
    assign o_idle = state==S_IDLE;

    // 按字节使能统计输出载荷长度
    always @(*) begin
        beat_bytes = 0;
        for (k=0; k<16; k=k+1)
            beat_bytes = beat_bytes + o_axis_tkeep[k];
    end

    // Only occupancy/indices reset; payload is owned by the valid count.
    // Abort discards unpresented candidate bytes while the existing packer
    // preserves any AXIS beat already exposed to its consumer.
    always @(posedge i_clk) begin
        if (!i_rst_n || aborting) begin
            fmt_read_slot <= 0;
            fmt_write_slot <= 0;
            fmt_count <= 0;
        end else begin
            if (fmt_push) begin
                if (fmt_write_slot) fmt_slot1 <= {fmt_last,fmt_byte};
                else fmt_slot0 <= {fmt_last,fmt_byte};
                fmt_write_slot <= !fmt_write_slot;
            end
            if (fmt_pop) fmt_read_slot <= !fmt_read_slot;
            case ({fmt_push,fmt_pop})
                2'b10: fmt_count <= fmt_count + 1'b1;
                2'b01: fmt_count <= fmt_count - 1'b1;
                default: begin end
            endcase
        end
    end

    jpeg_rgb_to_ycbcr_422 #(.SHARED_LUMA_ENABLE(SHARED_STREAM_ENABLE)) u_color (
        .i_clk(i_clk), .i_rst_n(private_rst_n), .i_valid(i_rgb_valid && o_rgb_ready),
        .o_ready(color_ready), .i_rgb(i_rgb), .i_luma(i_luma), .i_sof(i_sof), .i_eol(i_eol),
        .i_capture_id(i_capture_id), .o_valid(color_valid), .i_ready(mcu_ready),
        .o_y(color_y), .o_cb(color_cb), .o_cr(color_cr), .o_sof(color_sof),
        .o_eol(color_eol), .o_capture_id(color_id));
    wire mcu_row_valid,mcu_row_ready;
    wire [63:0] mcu_row_data;
    wire [2:0] mcu_row_index;
    generate if(MCU_ROW_STREAM_ENABLE!=0 && SHARED_STREAM_ENABLE==0) begin:invalid_row_mode
        JPEG_ROW_STREAM_REQUIRES_SHARED_PIPELINE invalid_configuration();
    end endgenerate
    jpeg_mcu_422 #(.MAX_WIDTH(MAX_WIDTH),.MAX_HEIGHT(MAX_HEIGHT),
        .ROW_STREAM_ENABLE(MCU_ROW_STREAM_ENABLE),.FIXED_GEOMETRY_ENABLE(FIXED_GEOMETRY_ENABLE),
        .DUAL_GEOMETRY_ENABLE(DUAL_GEOMETRY_ENABLE)) u_mcu (
        .i_clk(i_clk), .i_rst_n(private_rst_n), .i_valid(color_valid),
        .o_ready(mcu_ready), .i_y(color_y), .i_cb(color_cb), .i_cr(color_cr),
        .i_sof(color_sof), .i_eol(color_eol), .i_capture_id(color_id),
        .i_width(frame_width), .i_height(frame_height),
        .o_block_valid(mcu_valid), .i_block_ready(dct_ready),
        .o_samples(mcu_samples), .o_component(mcu_comp), .o_block_index(mcu_index),
        .o_mcu_x(mcu_x), .o_mcu_y(mcu_y), .o_frame_last(mcu_last),
        .o_capture_id(mcu_id), .o_error_valid(mcu_error),
        .o_error_capture_id(mcu_error_id), .o_error_code(mcu_error_code),
        .o_row_valid(mcu_row_valid),.i_row_ready(mcu_row_ready),
        .o_row_data(mcu_row_data),.o_row_index(mcu_row_index));
    generate if(SHARED_STREAM_ENABLE == 0) begin : legacy
    assign coeff_token_valid=0;assign coeff_token=0;assign quant_error=0;
    assign table_quantizers=0;
    assign mcu_row_ready=0;
    jpeg_dct8x8 u_dct (
        .i_clk(i_clk), .i_rst_n(private_rst_n), .i_block_valid(mcu_valid),
        .o_block_ready(dct_ready), .i_samples(mcu_samples), .i_component(mcu_comp),
        .i_mcu_x(mcu_x), .i_mcu_y(mcu_y), .i_block_index(mcu_index),
        .i_frame_last(mcu_last), .i_capture_id(mcu_id), .o_block_valid(dct_valid),
        .i_block_ready(quant_ready), .o_coeffs(dct_coeff), .o_component(dct_comp),
        .o_mcu_x(dct_x), .o_mcu_y(dct_y), .o_block_index(dct_index),
        .o_frame_last(dct_last), .o_capture_id(dct_id));
    jpeg_quant_zigzag u_quant (
        .i_clk(i_clk), .i_rst_n(private_rst_n), .i_block_valid(dct_valid),
        .o_block_ready(quant_ready), .i_coeffs(dct_coeff), .i_component(dct_comp),
        .i_block_index(dct_index), .i_mcu_x(dct_x), .i_mcu_y(dct_y),
        .i_frame_last(dct_last), .i_capture_id(dct_id), .o_block_valid(quant_valid),
        .i_block_ready(ent_ready), .o_coeffs(quant_coeff), .o_component(quant_comp),
        .o_block_index(quant_index), .o_mcu_x(quant_x), .o_mcu_y(quant_y),
        .o_frame_last(quant_last), .o_capture_id(quant_id));
    end else begin : stream
        wire col_valid,col_ready,col_last;
        wire [127:0] col_data;
        wire [2:0] col_index;
        wire [1:0] col_component,col_block;
        wire [8:0] col_x,col_y;
        wire [31:0] col_id;
        assign quant_valid=0;assign quant_coeff=0;assign quant_comp=0;assign quant_index=0;
        assign quant_x=0;assign quant_y=0;assign quant_last=0;assign quant_id=0;
        jpeg_dct8x8_pipeline #(.OUTPUT_STREAM_MODE(1),
            .TINY_DISTRIBUTED_RAM_ENABLE(TINY_DISTRIBUTED_RAM_ENABLE),
            .INPUT_ROW_STREAM_ENABLE(MCU_ROW_STREAM_ENABLE)) u_dct (
            .i_clk(i_clk),.i_rst_n(private_rst_n),.i_block_valid(mcu_valid),.o_block_ready(dct_ready),
            .i_samples(mcu_samples),.i_component(mcu_comp),.i_mcu_x(mcu_x),.i_mcu_y(mcu_y),
            .i_block_index(mcu_index),.i_frame_last(mcu_last),.i_capture_id(mcu_id),
            .o_block_valid(),.i_block_ready(1'b0),.o_coeffs(),.o_component(),.o_mcu_x(),.o_mcu_y(),
            .o_block_index(),.o_frame_last(),.o_capture_id(),.o_column_valid(col_valid),
            .i_column_ready(col_ready),.o_column_data(col_data),.o_column_index(col_index),
            .o_column_component(col_component),.o_column_mcu_x(col_x),.o_column_mcu_y(col_y),
            .o_column_block_index(col_block),.o_column_frame_last(col_last),.o_column_capture_id(col_id),
            .i_row_valid(mcu_row_valid),.o_row_ready(mcu_row_ready),
            .i_row_data(mcu_row_data),.i_row_index(mcu_row_index));
        jpeg_quant_stream #(.MAX_WIDTH(MAX_WIDTH),.MAX_HEIGHT(MAX_HEIGHT),
            .TINY_DISTRIBUTED_RAM_ENABLE(TINY_DISTRIBUTED_RAM_ENABLE),
            .ROM_INIT_ROOT(ROM_INIT_ROOT),.ROM_INIT_SUFFIX(ROM_INIT_SUFFIX)) u_quant (
            .i_clk(i_clk),.i_rst_n(private_rst_n),.i_column_valid(col_valid),.o_column_ready(col_ready),
            .i_column_data(col_data),.i_column_index(col_index),.i_component(col_component),
            .i_mcu_x(col_x),.i_mcu_y(col_y),.i_block_index(col_block),.i_frame_last(col_last),
            .i_capture_id(col_id),.i_quality(quality[6:0]),.i_epoch(mode_epoch),
            .i_session_id(session_id),.i_camera_id(camera_id),
            .o_token_valid(coeff_token_valid),.i_token_ready(coeff_token_ready),
            .o_token_data(coeff_token),.o_error(quant_error),
            .i_table_quality(table_quality),.i_table_component(table_component),
            .i_table_column(table_column),.i_table_enable(table_enable),.o_table_quantizers(table_quantizers));
    end endgenerate
    jpeg_entropy #(.STREAM_INPUT_ENABLE(SHARED_STREAM_ENABLE),.RESTART_ENABLE(SHARED_STREAM_ENABLE),
        .COEFF_BANKED_STORAGE_ENABLE(COEFF_BANKED_STORAGE_ENABLE),
        .ROM_INIT_ROOT(ROM_INIT_ROOT),.ROM_INIT_SUFFIX(ROM_INIT_SUFFIX)) u_entropy (
        .i_clk(i_clk), .i_rst_n(i_rst_n), .i_abort(aborting),
        .i_block_valid(quant_valid), .o_block_ready(ent_ready),
        .i_coeffs(quant_coeff), .i_component(quant_comp), .i_block_index(quant_index),
        .i_mcu_x(quant_x), .i_mcu_y(quant_y), .i_frame_last(quant_last),
        .i_capture_id(quant_id), .o_byte_valid(ent_valid),
        .i_token_valid(coeff_token_valid),.o_token_ready(coeff_token_ready),
        .i_token_data(coeff_token[127:0]),.i_token_keep(coeff_token[143:128]),
        .i_token_last(coeff_token[144]),.i_token_user(coeff_token[146:145]),.i_restart_mcus(restart_mcus),
        .i_byte_ready(aborting ? 1'b1 : fmt_ent_ready), .o_byte(ent_byte), .o_byte_last(ent_last),
        .o_entropy_done(ent_done), .o_error_valid(ent_error),
        .o_error_capture_id(ent_error_id), .o_error_code(ent_error_code),
        .o_idle(ent_idle));
    jpeg_file_formatter #(.DYNAMIC_ENABLE(SHARED_STREAM_ENABLE)) u_formatter (
        .i_clk(i_clk), .i_reset_n(i_rst_n), .i_start_valid(start_fire),
        .o_start_ready(fmt_start_ready), .i_width(i_width), .i_height(i_height),
        .i_capture_id(i_capture_id), .i_abort(aborting),
        .i_quality(i_quality[6:0]),.i_restart_mcus(i_restart_mcus),
        .o_table_quality(table_quality),.o_table_component(table_component),
        .o_table_column(table_column),.o_table_enable(table_enable),.i_table_quantizers(table_quantizers),
        .i_entropy_valid(ent_valid), .o_entropy_ready(), .o_entropy_ready_core(fmt_ent_ready),
        .i_entropy_byte(ent_byte), .i_entropy_last(ent_last),
        .o_byte_valid(fmt_valid), .i_byte_ready(aborting ? 1'b1 : fmt_queue_ready), .o_byte(fmt_byte),
        .o_last(fmt_last), .o_capture_id(fmt_id), .o_idle(fmt_idle),
        .o_error_invalid_size(fmt_error));
    jpeg_byte_packer u_packer (
        .i_clk(i_clk), .i_rst_n(i_rst_n), .i_abort(aborting),
        .i_byte(fmt_queue_data[7:0]), .i_valid(fmt_queue_valid), .o_ready(pack_ready),
        .i_last(fmt_queue_data[8]), .o_axis_tdata(o_axis_tdata),
        .o_axis_tkeep(o_axis_tkeep), .o_axis_tvalid(o_axis_tvalid),
        .i_axis_tready(i_axis_tready), .o_axis_tlast(o_axis_tlast),
        .o_frame_error(pack_error), .o_overflow(pack_overflow), .o_idle(pack_idle));

    // 跟踪单帧流水线结束和编码结果
    always @(posedge i_clk) begin
        if (!i_rst_n) begin
            state <= S_IDLE;
            frame_id <= 0; frame_width <= 0; frame_height <= 0;
            quality<=75;session_id<=0;mode_epoch<=0;camera_id<=0;restart_mcus<=0;
            status_seen <= 0; status_ok <= 0; last_seen <= 0;
            input_done <= 0; rows_seen <= 0;
            byte_count <= 0; error_code <= ERR_NONE;
            abort_released <= 1'b0;
        end else begin
            case (state)
                S_IDLE: if (start_fire) begin
                    frame_id <= i_capture_id;
                    frame_width <= i_width; frame_height <= i_height;
                    quality<=SHARED_STREAM_ENABLE ? i_quality : 8'd75;
                    session_id<=SHARED_STREAM_ENABLE ? i_session_id : 32'd0;
                    mode_epoch<=SHARED_STREAM_ENABLE ? i_mode_epoch : 32'd0;
                    camera_id<=SHARED_STREAM_ENABLE ? i_camera_id : 1'b0;
                    restart_mcus<=SHARED_STREAM_ENABLE ? i_restart_mcus : 16'd0;
                    status_seen <= 0; status_ok <= 0; last_seen <= 0;
                    input_done <= i_eol && i_height == 13'd1;
                    rows_seen <= i_eol ? 13'd1 : 13'd0;
                    byte_count <= 0; error_code <= ERR_NONE;
                    abort_released <= 1'b0;
                    state <= S_RUN;
                end
                S_RUN: begin
                    if (i_rgb_valid && o_rgb_ready && i_eol) begin
                        rows_seen <= rows_seen + 13'd1;
                        if (rows_seen + 13'd1 >= frame_height)
                            input_done <= 1'b1;
                    end
                    if (axis_fire) begin
                        byte_count <= byte_count + beat_bytes;
                        if (o_axis_tlast) last_seen <= 1;
                    end
                    if (matching_status && !status_seen) begin
                        status_seen <= 1;
                        status_ok <= i_frame_ok;
                    end
                    if (input_changed || (matching_status && !i_frame_ok) || mcu_error ||
                        quant_error || ent_error || fmt_error || pack_error || pack_overflow) begin
                        error_code <= input_changed ? ERR_INPUT :
                                      (matching_status && !i_frame_ok) ? ERR_STATUS :
                                      mcu_error ? ERR_MCU : (ent_error || quant_error) ? ERR_ENTROPY :
                                      fmt_error ? ERR_FORMAT : ERR_PACKER;
                        state <= S_ABORT;
                        abort_released <= 1'b0;
                    end else if ((last_seen || (axis_fire && o_axis_tlast)) &&
                                 (status_seen || matching_status) &&
                                 (status_ok || (matching_status && i_frame_ok))) begin
                        state <= S_RESULT;
                    end
                end
                // 打包器在 i_abort 有效时有意保持 o_idle 为低
                // 其可见输出拍排空后才释放中止
                S_ABORT: begin
                    abort_released <= 1'b1;
                    if (ent_idle && fmt_idle && fmt_queue_empty && !o_axis_tvalid)
                        state <= S_DRAIN;
                end
                S_DRAIN: if (ent_idle && fmt_idle && fmt_queue_empty && pack_idle) begin
                    byte_count <= 0;
                    state <= S_RESULT;
                end
                S_RESULT: if (i_result_ready) state <= S_IDLE;
                default: state <= S_IDLE;
            endcase
        end
    end
endmodule
