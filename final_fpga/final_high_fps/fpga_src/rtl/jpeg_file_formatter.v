// 拼接JPEG文件头熵数据和结束标记
module jpeg_file_formatter #(
    parameter integer DYNAMIC_ENABLE = 0
) (
    // 时钟与复位
    input wire i_clk,
    input wire i_reset_n,

    // 帧启动与尺寸
    input wire i_start_valid,
    output wire o_start_ready,
    input wire [12:0] i_width,
    input wire [12:0] i_height,
    input wire [31:0] i_capture_id,
    input wire [6:0] i_quality,
    input wire [15:0] i_restart_mcus,
    output wire [6:0] o_table_quality,
    output wire o_table_component,
    output wire [2:0] o_table_column,
    output wire o_table_enable,
    input wire [63:0] i_table_quantizers,

    // 中止控制
    input wire i_abort,

    // 输入熵编码字节
    input wire i_entropy_valid,
    output wire o_entropy_ready,
    // Same-clock feedback before the public reset mask; never exported to CDC.
    output wire o_entropy_ready_core,
    input wire [7:0] i_entropy_byte,
    input wire i_entropy_last,

    // JPEG文件字节输出
    output wire o_byte_valid,
    input wire i_byte_ready,
    output wire [7:0] o_byte,
    output wire o_last,
    output wire [31:0] o_capture_id,

    // 状态与错误
    output wire o_idle,
    output wire o_error_invalid_size // 输入尺寸超出文件头支持范围
);

    localparam [2:0] STATE_IDLE = 3'd0;
    localparam [2:0] STATE_HEADER = 3'd1;
    localparam [2:0] STATE_ENTROPY = 3'd2;
    localparam [2:0] STATE_EOI = 3'd3;
    localparam [2:0] STATE_DRI = 3'd4;

    reg [2:0] state_reg;
    reg [9:0] header_index_reg;
    reg [12:0] width_reg;
    reg [12:0] height_reg;
    reg [31:0] capture_id_reg;
    reg entropy_buffer_valid_reg;
    reg [7:0] entropy_buffer_byte_reg;
    reg entropy_buffer_last_reg;
    reg error_invalid_size_reg;
    reg abort_pending_reg;
    reg [6:0] quality_reg;
    reg [15:0] restart_reg;
    reg [2:0] dri_index;
    reg table_pending;
    reg [2:0] table_lane;
    reg dqt_valid;
    reg [7:0] dqt_byte;

`include "jpeg_header_rom.vh"
    // Standard zigzag position to natural table row/column.
    function [5:0] zigzag_natural;
        input [5:0] position;
        begin
            case (position)
                6'd0: zigzag_natural = 6'd0;
                6'd1: zigzag_natural = 6'd1;
                6'd2: zigzag_natural = 6'd8;
                6'd3: zigzag_natural = 6'd16;
                6'd4: zigzag_natural = 6'd9;
                6'd5: zigzag_natural = 6'd2;
                6'd6: zigzag_natural = 6'd3;
                6'd7: zigzag_natural = 6'd10;
                6'd8: zigzag_natural = 6'd17;
                6'd9: zigzag_natural = 6'd24;
                6'd10: zigzag_natural = 6'd32;
                6'd11: zigzag_natural = 6'd25;
                6'd12: zigzag_natural = 6'd18;
                6'd13: zigzag_natural = 6'd11;
                6'd14: zigzag_natural = 6'd4;
                6'd15: zigzag_natural = 6'd5;
                6'd16: zigzag_natural = 6'd12;
                6'd17: zigzag_natural = 6'd19;
                6'd18: zigzag_natural = 6'd26;
                6'd19: zigzag_natural = 6'd33;
                6'd20: zigzag_natural = 6'd40;
                6'd21: zigzag_natural = 6'd48;
                6'd22: zigzag_natural = 6'd41;
                6'd23: zigzag_natural = 6'd34;
                6'd24: zigzag_natural = 6'd27;
                6'd25: zigzag_natural = 6'd20;
                6'd26: zigzag_natural = 6'd13;
                6'd27: zigzag_natural = 6'd6;
                6'd28: zigzag_natural = 6'd7;
                6'd29: zigzag_natural = 6'd14;
                6'd30: zigzag_natural = 6'd21;
                6'd31: zigzag_natural = 6'd28;
                6'd32: zigzag_natural = 6'd35;
                6'd33: zigzag_natural = 6'd42;
                6'd34: zigzag_natural = 6'd49;
                6'd35: zigzag_natural = 6'd56;
                6'd36: zigzag_natural = 6'd57;
                6'd37: zigzag_natural = 6'd50;
                6'd38: zigzag_natural = 6'd43;
                6'd39: zigzag_natural = 6'd36;
                6'd40: zigzag_natural = 6'd29;
                6'd41: zigzag_natural = 6'd22;
                6'd42: zigzag_natural = 6'd15;
                6'd43: zigzag_natural = 6'd23;
                6'd44: zigzag_natural = 6'd30;
                6'd45: zigzag_natural = 6'd37;
                6'd46: zigzag_natural = 6'd44;
                6'd47: zigzag_natural = 6'd51;
                6'd48: zigzag_natural = 6'd58;
                6'd49: zigzag_natural = 6'd59;
                6'd50: zigzag_natural = 6'd52;
                6'd51: zigzag_natural = 6'd45;
                6'd52: zigzag_natural = 6'd38;
                6'd53: zigzag_natural = 6'd31;
                6'd54: zigzag_natural = 6'd39;
                6'd55: zigzag_natural = 6'd46;
                6'd56: zigzag_natural = 6'd53;
                6'd57: zigzag_natural = 6'd60;
                6'd58: zigzag_natural = 6'd61;
                6'd59: zigzag_natural = 6'd54;
                6'd60: zigzag_natural = 6'd47;
                6'd61: zigzag_natural = 6'd55;
                6'd62: zigzag_natural = 6'd62;
                6'd63: zigzag_natural = 6'd63;
                default: zigzag_natural = 0;
            endcase
        end
    endfunction

    wire valid_size;
    wire header_handshake;
    wire entropy_output_handshake;
    wire eoi_handshake;
    wire entropy_input_handshake;
    wire header_dqt = (header_index_reg >= 25 && header_index_reg <= 88) ||
                      (header_index_reg >= 90 && header_index_reg <= 153);
    wire [9:0] dqt_index = header_index_reg < 90 ? header_index_reg - 10'd25 :
                                                                  header_index_reg - 10'd90;
    wire [5:0] dqt_natural = zigzag_natural(dqt_index[5:0]);
    assign o_table_quality = quality_reg;
    assign o_table_component = header_index_reg >= 90;
    assign o_table_column = dqt_natural[2:0];
    // Read-only requests need no asynchronous reset/abort gating. Local state
    // invalidates an abandoned response before any byte can be published.
    assign o_table_enable = DYNAMIC_ENABLE && state_reg == STATE_HEADER &&
        header_dqt && !dqt_valid && !table_pending;
    wire [7:0] dri_byte = dri_index == 0 ? 8'hff : dri_index == 1 ? 8'hdd :
        dri_index == 2 ? 8'h00 : dri_index == 3 ? 8'h04 :
        dri_index == 4 ? restart_reg[15:8] : restart_reg[7:0];

    // 先检查尺寸范围再生成JPEG文件头
    assign valid_size = (i_width >= 13'd4) && (i_width <= 13'd3840) &&
                        (i_width[1:0] == 2'b00) && (i_height >= 13'd1) &&
                        (i_height <= 13'd2160) &&
                        (!DYNAMIC_ENABLE || (i_quality >= 1 && i_quality <= 100));
    assign o_start_ready = i_reset_n && (state_reg == STATE_IDLE) && !i_abort;
    // 非末尾暂存字节可在同周期被接收并替换
    // 末尾暂存字节结束数据流，不接受后续字节
    assign o_entropy_ready_core = (state_reg == STATE_ENTROPY) &&
                                  (!entropy_buffer_valid_reg ||
                                   (i_byte_ready && !entropy_buffer_last_reg)) &&
                                  !i_abort;
    assign o_entropy_ready = i_reset_n && o_entropy_ready_core;
    assign o_byte_valid = ((state_reg == STATE_HEADER) &&
                          (!DYNAMIC_ENABLE || !header_dqt || dqt_valid)) ||
                          ((state_reg == STATE_ENTROPY) && entropy_buffer_valid_reg) ||
                          (state_reg == STATE_EOI) || (state_reg == STATE_DRI);
    assign o_byte = (state_reg == STATE_HEADER) ?
                    ((DYNAMIC_ENABLE && header_dqt) ? dqt_byte :
                     (header_index_reg == 10'd159) ? {3'b000, height_reg[12:8]} :
                     (header_index_reg == 10'd160) ? height_reg[7:0] :
                     (header_index_reg == 10'd161) ? {3'b000, width_reg[12:8]} :
                     (header_index_reg == 10'd162) ? width_reg[7:0] :
                     jpeg_header_rom_byte(header_index_reg)) :
                    ((state_reg == STATE_DRI) ? dri_byte :
                     (state_reg == STATE_ENTROPY) ? entropy_buffer_byte_reg :
                     ((state_reg == STATE_EOI) ? ((header_index_reg == 10'd0) ? 8'hFF : 8'hD9) : 8'h00));
    assign o_last = (state_reg == STATE_EOI) && (header_index_reg == 10'd1);
    assign o_capture_id = capture_id_reg;
    assign o_idle = (state_reg == STATE_IDLE);
    assign o_error_invalid_size = error_invalid_size_reg;
    assign header_handshake = (state_reg == STATE_HEADER) && o_byte_valid && i_byte_ready;
    assign entropy_output_handshake = (state_reg == STATE_ENTROPY) &&
                                      entropy_buffer_valid_reg && i_byte_ready;
    assign eoi_handshake = (state_reg == STATE_EOI) && i_byte_ready;
    assign entropy_input_handshake = o_entropy_ready && i_entropy_valid;

    // This payload address is rebuilt in IDLE/at entropy retirement. It needs
    // no global reset mux that TD could absorb into the inferred header ROM.
    // Every presented header/EOI byte still holds its address until handshake.
    always @(posedge i_clk) begin
        if (state_reg == STATE_IDLE ||
            (entropy_output_handshake && entropy_buffer_last_reg))
            header_index_reg <= 10'd0;
        else if (header_handshake || eoi_handshake)
            header_index_reg <= header_index_reg + 1'b1;
    end

    // 按帧头熵数据和结束标记顺序输出文件字节
    always @(posedge i_clk) begin
        if (!i_reset_n) begin
            state_reg <= STATE_IDLE;
            width_reg <= 13'd0;
            height_reg <= 13'd0;
            capture_id_reg <= 32'd0;
            entropy_buffer_valid_reg <= 1'b0;
            entropy_buffer_byte_reg <= 8'd0;
            entropy_buffer_last_reg <= 1'b0;
            error_invalid_size_reg <= 1'b0;
            abort_pending_reg <= 1'b0;
            quality_reg <= 7'd75;
            restart_reg <= 0;
            dri_index <= 0;
            table_pending <= 0;
            table_lane <= 0;
            dqt_valid <= 0;
            dqt_byte <= 0;
        end else begin
            error_invalid_size_reg <= 1'b0;
            if ((i_abort || abort_pending_reg) && (state_reg != STATE_IDLE)) begin
                if (o_byte_valid && !i_byte_ready) begin
                    state_reg <= state_reg;
                    abort_pending_reg <= 1'b1;
                end else begin
                    state_reg <= STATE_IDLE;
                    entropy_buffer_valid_reg <= 1'b0;
                    entropy_buffer_last_reg <= 1'b0;
                    abort_pending_reg <= 1'b0;
                    table_pending <= 0;
                    dqt_valid <= 0;
                end
            end else begin
                table_pending <= o_table_enable;
                if (o_table_enable) table_lane <= dqt_natural[5:3];
                if (table_pending) begin
                    dqt_byte <= i_table_quantizers[table_lane*8 +: 8];
                    dqt_valid <= 1;
                end
                case (state_reg)
                    STATE_IDLE: begin
                        if (i_start_valid && o_start_ready) begin
                            if (valid_size) begin
                                width_reg <= i_width;
                                height_reg <= i_height;
                                capture_id_reg <= i_capture_id;
                                quality_reg <= DYNAMIC_ENABLE ? i_quality : 7'd75;
                                restart_reg <= DYNAMIC_ENABLE ? i_restart_mcus : 16'd0;
                                dqt_valid <= 0;
                                table_pending <= 0;
                                state_reg <= STATE_HEADER;
                            end else begin
                                error_invalid_size_reg <= 1'b1;
                            end
                        end
                    end
                    STATE_HEADER: begin
                        if (header_handshake) begin
                            dqt_valid <= 0;
                            if (header_index_reg == JPEG_HEADER_BYTES - 1'b1) begin
                                state_reg <= STATE_ENTROPY;
                            end else if (DYNAMIC_ENABLE && restart_reg != 0 && header_index_reg == 592) begin
                                dri_index <= 0;
                                state_reg <= STATE_DRI;
                            end
                        end
                    end
                    STATE_DRI: if (i_byte_ready) begin
                        if (dri_index == 5) state_reg <= STATE_HEADER;
                        else dri_index <= dri_index + 1'b1;
                    end
                    STATE_ENTROPY: begin
                        if (entropy_output_handshake) begin
                            if (entropy_buffer_last_reg) begin
                                entropy_buffer_valid_reg <= 1'b0;
                                state_reg <= STATE_EOI;
                            end else if (entropy_input_handshake) begin
                                entropy_buffer_valid_reg <= 1'b1;
                                entropy_buffer_byte_reg <= i_entropy_byte;
                                entropy_buffer_last_reg <= i_entropy_last;
                            end else begin
                                entropy_buffer_valid_reg <= 1'b0;
                            end
                        end else if (entropy_input_handshake) begin
                            entropy_buffer_valid_reg <= 1'b1;
                            entropy_buffer_byte_reg <= i_entropy_byte;
                            entropy_buffer_last_reg <= i_entropy_last;
                        end
                    end
                    STATE_EOI: begin
                        if (eoi_handshake) begin
                            if (header_index_reg == 10'd1) begin
                                state_reg <= STATE_IDLE;
                            end
                        end
                    end
                    default: begin
                        state_reg <= STATE_IDLE;
                        entropy_buffer_valid_reg <= 1'b0;
                        abort_pending_reg <= 1'b0;
                    end
                endcase
            end
        end
    end

endmodule
