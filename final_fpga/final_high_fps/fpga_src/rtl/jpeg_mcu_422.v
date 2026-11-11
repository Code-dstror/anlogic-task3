`timescale 1ns / 1ps

// 将四像素输入组装为JPEG四二二最小编码单元
module jpeg_mcu_422 #(
    parameter integer MAX_WIDTH = 3840,
    parameter integer MAX_HEIGHT = 2160,
    parameter integer ROW_STREAM_ENABLE = 0,
    parameter integer FIXED_GEOMETRY_ENABLE = 0,
    parameter integer DUAL_GEOMETRY_ENABLE = 0
) (
    // 时钟与复位
    input wire i_clk,
    input wire i_rst_n,

    // 输入四二二像素
    input wire i_valid,
    output wire o_ready,
    input wire [31:0] i_y,
    input wire [15:0] i_cb,
    input wire [15:0] i_cr,
    input wire i_sof,
    input wire i_eol,
    input wire [31:0] i_capture_id,
    input wire [12:0] i_width,
    input wire [12:0] i_height,

    // 输出编码块
    output reg o_block_valid,
    input wire i_block_ready,
    output reg [511:0] o_samples,
    output reg [1:0] o_component,
    output reg [1:0] o_block_index,
    output reg [8:0] o_mcu_x,
    output reg [8:0] o_mcu_y,
    output reg o_frame_last, // 当前块是本帧最后一个编码块
    output reg [31:0] o_capture_id,

    // 错误状态
    output reg o_error_valid,
    output reg [31:0] o_error_capture_id,
    output reg [2:0] o_error_code,

    // Optional row stream: eight low-byte-first rows per block.
    output wire o_row_valid,
    input wire i_row_ready,
    output wire [63:0] o_row_data,
    output wire [2:0] o_row_index
);
    localparam [2:0] ERR_DIM = 3'd1;
    localparam [2:0] ERR_MARKER = 3'd2;
    localparam [2:0] ERR_ID = 3'd3;
    localparam integer ALIGNED_ROWS = FIXED_GEOMETRY_ENABLE || DUAL_GEOMETRY_ENABLE;
    localparam integer STREAM_PREFETCH = ROW_STREAM_ENABLE && ALIGNED_ROWS;
    localparam integer DUAL_HD_WIDTH = MAX_WIDTH / 2;
    localparam integer DUAL_HD_HEIGHT = MAX_HEIGHT / 2;

    // Preserve both complete eight-row groups; pack five samples per RAM40 word.
    reg [1:0] rd_block;
    wire read_enable;
    wire [119:0] y_bank_words,cb_bank_words,cr_bank_words;
    wire [14:0] y_byte_select,cb_byte_select,cr_byte_select;
    // The aligned request cursor may already point to the following block.
    // The RAM response and its selectors hold together during a row stall.
    (* preserve="true" *) reg response_y_q,response_cb_q;
    always @(posedge i_clk) begin
        if (!STREAM_PREFETCH || read_enable) begin
            response_y_q<=rd_block<2;
            response_cb_q<=rd_block==2;
        end
    end
    wire [119:0] selected_bank_words=response_y_q ? y_bank_words :
        response_cb_q ? cb_bank_words : cr_bank_words;
    wire [14:0] selected_byte_select=response_y_q ? y_byte_select :
        response_cb_q ? cb_byte_select : cr_byte_select;
    wire [63:0] shared_read_bus;
    jpeg_mcu_read_align8 u_read_align (
        .i_bank_words(selected_bank_words),.i_byte_select(selected_byte_select),
        .o_data(shared_read_bus));
    reg [1:0] bank_full;
    reg [8:0] bank_group [0:1];
    reg [3:0] bank_rows [0:1];
    reg wr_active;
    reg frame_busy;
    reg drop_mode;
    reg wr_bank;
    reg [12:0] wr_x;
    reg [12:0] wr_y;
    reg [12:0] frame_width;
    reg [12:0] frame_height;
    reg [31:0] frame_id;
    reg rd_active;
    reg rd_bank;
    reg [8:0] rd_next_group;
    reg [8:0] rd_x;
    reg [2:0] rd_row;
    reg rd_pending;
    reg [2:0] pending_row;
    reg pending_group_last;
    reg [511:0] block_build;
    // Both profiles fill complete MCU rows. MAX sizes the RAM pitch.
    // The highest bit of MAX_WIDTH distinguishes it from half width.
    wire frame_uhd = frame_width[$clog2(MAX_WIDTH)-1];
    wire [8:0] mcu_count = FIXED_GEOMETRY_ENABLE ? MAX_WIDTH/16 :
        (frame_width + 13'd15) >> 4;
    wire rd_last_column = DUAL_GEOMETRY_ENABLE ?
        rd_x == (frame_uhd ? MAX_WIDTH/16-1 : DUAL_HD_WIDTH/16-1) :
        rd_x == mcu_count - 1'b1;
    wire rd_last_block = rd_last_column && rd_block == 2'd3;
    wire rd_last_group = DUAL_GEOMETRY_ENABLE ?
        rd_next_group == (frame_uhd ? MAX_HEIGHT/8-1 : DUAL_HD_HEIGHT/8-1) :
        FIXED_GEOMETRY_ENABLE ? rd_next_group==MAX_HEIGHT/8-1 :
        (({rd_next_group, 3'b000} + 13'd8) >= frame_height);
    wire accept = i_valid && o_ready;
    wire dual_dimensions_ok = (i_width == DUAL_HD_WIDTH && i_height == DUAL_HD_HEIGHT) ||
                              (i_width == MAX_WIDTH && i_height == MAX_HEIGHT);
    wire dimensions_ok = DUAL_GEOMETRY_ENABLE ? dual_dimensions_ok : FIXED_GEOMETRY_ENABLE ?
                         (i_width == MAX_WIDTH && i_height == MAX_HEIGHT) :
                         (i_width >= 13'd4) && (i_width <= MAX_WIDTH) &&
                         (i_width[1:0] == 2'b00) &&
                         (i_height >= 13'd1) && (i_height <= MAX_HEIGHT);
    wire wr_last_column = DUAL_GEOMETRY_ENABLE ?
        wr_x == (frame_uhd ? MAX_WIDTH-4 : DUAL_HD_WIDTH-4) :
        wr_x + 13'd4 == (FIXED_GEOMETRY_ENABLE ? MAX_WIDTH : frame_width);
    wire wr_last_row = DUAL_GEOMETRY_ENABLE ?
        wr_y == (frame_uhd ? MAX_HEIGHT-1 : DUAL_HD_HEIGHT-1) :
        wr_y + 1'b1 == (FIXED_GEOMETRY_ENABLE ? MAX_HEIGHT : frame_height);
    wire marker_ok = i_eol == wr_last_column;
    wire start_ok = ALIGNED_ROWS ? !i_eol : i_eol == (i_width == 13'd4);
    wire free_fill_bank = !bank_full[wr_bank] && !(rd_active && rd_bank == wr_bank);

    // 上一帧最后一个块必须输出完成，才能接收下一帧 SOF
    // 按行缓存空闲情况反压像素输入
    assign o_ready = i_rst_n && (wr_active ? free_fill_bank :
                     (!frame_busy && !rd_active && bank_full == 2'b00 &&
                      (ROW_STREAM_ENABLE ? (!rd_pending || i_row_ready) :
                       (!o_block_valid || i_block_ready))));

    wire [12:0] sample_width = (rd_block < 2) ? frame_width : (frame_width >> 1);
    wire [12:0] left_x = (rd_block == 2'd0) ? {rd_x, 4'b0000} :
                         (rd_block == 2'd1) ? ({rd_x, 4'b0000} + 13'd8) :
                         {rd_x, 3'b000};
    wire [2:0] physical_row = ALIGNED_ROWS ? rd_row :
                              (rd_row < bank_rows[rd_bank]) ?
                              rd_row : bank_rows[rd_bank] - 1'b1;
    wire issue_read = rd_active && !rd_pending && (!o_block_valid || i_block_ready);
    // 块读取开始后，其余七次请求连续进行，不插入空拍
    wire issue_following = rd_active && rd_pending && (rd_row != 3'd0);
    // 读端只由同步状态控制；复位期间偶发的旧行读取不会被发布。
    // 不将异步断言的上游复位直接送入 ERAM 片选。
    wire row_fire = o_row_valid && i_row_ready;
    wire response_group_last = STREAM_PREFETCH ? pending_group_last : rd_last_block;
    wire stream_read = rd_active && (!rd_pending ||
        (i_row_ready && (pending_row != 3'd7 || (STREAM_PREFETCH && !response_group_last))));
    // Precompute the next address when row7 is requested. A row7 handshake
    // can then replace the response with row0 without a READY-to-address mux.
    wire advance_block = STREAM_PREFETCH ? stream_read && rd_row == 3'd7 && !rd_last_block :
        row_fire && rd_active && pending_row == 3'd7 && !rd_last_block;
    assign read_enable = ROW_STREAM_ENABLE ? stream_read : issue_read || issue_following;
    wire [12:0] read_y_start = ALIGNED_ROWS ? left_x :
        left_x < frame_width ? left_x :
        ((frame_width-1'b1) & 13'h1ff8);
    wire [12:0] read_c_start = ALIGNED_ROWS ? left_x :
        left_x < (frame_width>>1) ? left_x :
        (((frame_width>>1)-1'b1) & 13'h1ff8);
    wire write_first = accept && !wr_active && i_sof && dimensions_ok && start_ok;
    wire write_rest = accept && wr_active && !i_sof && marker_ok &&
                      i_capture_id == frame_id && i_width == frame_width && i_height == frame_height;
    wire packed_write = write_first || write_rest;
    wire packed_bank = !write_first && wr_bank;
    wire [2:0] packed_row = write_first ? 3'd0 : wr_y[2:0];
    wire packed_first = write_first || wr_x==0;
    jpeg_mcu_packed_plane #(.MAX_SAMPLES(MAX_WIDTH),.IN_BYTES(4),
        .FULL_ROW_ENABLE(ALIGNED_ROWS),.PACKED_READ_ENABLE(1),
        .REGISTER_WRITE_PORTS(ALIGNED_ROWS)) u_y (
        .clk(i_clk),.rst_n(i_rst_n),.wr_valid(packed_write),.wr_bank(packed_bank),
        .wr_row(packed_row),.wr_first(packed_first),.wr_last(i_eol),.wr_data(i_y),
        .rd_enable(read_enable),.rd_bank(rd_bank),.rd_row(physical_row),
        .rd_start(read_y_start),.rd_data(),.o_bank_words(y_bank_words),.o_byte_select(y_byte_select));
    jpeg_mcu_packed_plane #(.MAX_SAMPLES(MAX_WIDTH/2),.IN_BYTES(2),
        .FULL_ROW_ENABLE(ALIGNED_ROWS),.PACKED_READ_ENABLE(1),
        .REGISTER_WRITE_PORTS(ALIGNED_ROWS)) u_cb (
        .clk(i_clk),.rst_n(i_rst_n),.wr_valid(packed_write),.wr_bank(packed_bank),
        .wr_row(packed_row),.wr_first(packed_first),.wr_last(i_eol),.wr_data(i_cb),
        .rd_enable(read_enable),.rd_bank(rd_bank),.rd_row(physical_row),
        .rd_start(read_c_start),.rd_data(),.o_bank_words(cb_bank_words),.o_byte_select(cb_byte_select));
    jpeg_mcu_packed_plane #(.MAX_SAMPLES(MAX_WIDTH/2),.IN_BYTES(2),
        .FULL_ROW_ENABLE(ALIGNED_ROWS),.PACKED_READ_ENABLE(1),
        .REGISTER_WRITE_PORTS(ALIGNED_ROWS)) u_cr (
        .clk(i_clk),.rst_n(i_rst_n),.wr_valid(packed_write),.wr_bank(packed_bank),
        .wr_row(packed_row),.wr_first(packed_first),.wr_last(i_eol),.wr_data(i_cr),
        .rd_enable(read_enable),.rd_bank(rd_bank),.rd_row(physical_row),
        .rd_start(read_c_start),.rd_data(),.o_bank_words(cr_bank_words),.o_byte_select(cr_byte_select));
    integer col;
    integer pick;
    reg [63:0] row_value;
    // 按块位置选择边界填充后的输出像素
    always @(*) begin
        row_value = 0;
        if (ALIGNED_ROWS) begin
            row_value = shared_read_bus;
        end else for (col=0; col<8; col=col+1) begin
            pick = (left_x + col < sample_width) ? col : (sample_width-1'b1) % 8;
            row_value[col*8 +: 8] = shared_read_bus[pick*8 +: 8];
        end
    end
    // The synchronous RAM result is the holding slot. Disable CE while stalled.
    assign o_row_valid = ROW_STREAM_ENABLE && i_rst_n && rd_pending;
    assign o_row_data = ROW_STREAM_ENABLE ? row_value : 64'd0;
    assign o_row_index = ROW_STREAM_ENABLE ? pending_row : 3'd0;

    // 协调双缓存写入和编码块读取
    always @(posedge i_clk) begin
        if (!i_rst_n) begin
            bank_full <= 2'b00;
            bank_group[0] <= 0;
            bank_group[1] <= 0;
            bank_rows[0] <= 0;
            bank_rows[1] <= 0;
            wr_active <= 1'b0;
            frame_busy <= 1'b0;
            drop_mode <= 1'b0;
            wr_bank <= 1'b0;
            wr_x <= 0;
            wr_y <= 0;
            frame_width <= 0;
            frame_height <= 0;
            frame_id <= 0;
            rd_active <= 1'b0;
            rd_bank <= 1'b0;
            rd_next_group <= 0;
            rd_x <= 0;
            rd_block <= 0;
            rd_row <= 0;
            rd_pending <= 1'b0;
            pending_row <= 0;
            pending_group_last <= 1'b0;
            block_build <= 0;
            o_block_valid <= 1'b0;
            o_samples <= 0;
            o_component <= 0;
            o_block_index <= 0;
            o_mcu_x <= 0;
            o_mcu_y <= 0;
            o_frame_last <= 1'b0;
            o_capture_id <= 0;
            o_error_valid <= 1'b0;
            o_error_capture_id <= 0;
            o_error_code <= 0;
        end else begin
            o_error_valid <= 1'b0;
            if ((ROW_STREAM_ENABLE ? (row_fire && pending_row==3'd7) :
                (o_block_valid && i_block_ready)) && o_frame_last)
                frame_busy <= 1'b0;

            if (!rd_active && bank_full[0] && bank_group[0] == rd_next_group) begin
                rd_active <= 1'b1;
                rd_bank <= 1'b0;
                rd_x <= 0;
                rd_block <= 0;
                rd_row <= 0;
                rd_pending <= 1'b0;
            end else if (!rd_active && bank_full[1] && bank_group[1] == rd_next_group) begin
                rd_active <= 1'b1;
                rd_bank <= 1'b1;
                rd_x <= 0;
                rd_block <= 0;
                rd_row <= 0;
                rd_pending <= 1'b0;
            end
            if (o_block_valid && i_block_ready)
                o_block_valid <= 1'b0;
            if (ROW_STREAM_ENABLE) begin
                if (stream_read) begin
                    rd_pending <= 1'b1;
                    pending_row <= rd_row;
                    rd_row <= rd_row + 1'b1;
                    if (!rd_pending || pending_row == 3'd7) begin
                        pending_group_last <= rd_last_block;
                        o_component <= (rd_block < 2) ? 2'd0 :
                                       (rd_block == 2'd2) ? 2'd1 : 2'd2;
                        o_block_index <= rd_block;
                        o_mcu_x <= rd_x;
                        o_mcu_y <= rd_next_group;
                        o_frame_last <= rd_last_block && rd_last_group;
                        o_capture_id <= frame_id;
                    end
                end
                if (row_fire && (!rd_active || pending_row==3'd7)) begin
                    if (!stream_read) rd_pending <= 1'b0;
                    if (rd_active && response_group_last) begin
                        bank_full[rd_bank] <= 1'b0;
                        rd_active <= 1'b0;
                        rd_next_group <= rd_next_group + 1'b1;
                    end
                end
                if (advance_block) begin
                    rd_block <= rd_block + 1'b1;
                    if (rd_block == 2'd3) rd_x <= rd_x + 1'b1;
                end
            end else if (rd_active && !rd_pending && (!o_block_valid || i_block_ready)) begin
                // 请求同步 RAM 的第零行
                rd_pending <= 1'b1;
                rd_row <= 3'd1;
                pending_row <= 0;
            end else if (rd_active && rd_pending) begin
                block_build[pending_row*64 +: 64] <= row_value;
                if (rd_row != 0) begin
                    pending_row <= rd_row;
                    rd_row <= rd_row + 1'b1;
                end else begin
                    // 上一周期请求的是第七行，此时发布完整块
                    o_samples <= {row_value, block_build[447:0]};
                    o_block_valid <= 1'b1;
                    o_component <= (rd_block < 2) ? 2'd0 :
                                   (rd_block == 2'd2) ? 2'd1 : 2'd2;
                    o_block_index <= rd_block;
                    o_mcu_x <= rd_x;
                    o_mcu_y <= rd_next_group;
                    o_frame_last <= rd_last_block && rd_last_group;
                    o_capture_id <= frame_id;
                    rd_pending <= 1'b0;
                    if (rd_last_block) begin
                        bank_full[rd_bank] <= 1'b0;
                        rd_active <= 1'b0;
                        rd_next_group <= rd_next_group + 1'b1;
                    end else if (rd_block == 2'd3) begin
                        rd_block <= 0;
                        rd_x <= rd_x + 1'b1;
                    end else begin
                        rd_block <= rd_block + 1'b1;
                    end
                end
            end

            if (accept) begin
                if (!wr_active) begin
                    if (drop_mode && !i_sof) begin
                        // 丢弃格式错误帧的剩余输入
                    end else if (!i_sof || !dimensions_ok || !start_ok) begin
                        o_error_valid <= 1'b1;
                        o_error_capture_id <= i_capture_id;
                        o_error_code <= !dimensions_ok ? ERR_DIM : ERR_MARKER;
                        drop_mode <= 1'b1;
                    end else begin
                        drop_mode <= 1'b0;
                        frame_busy <= 1'b1;
                        wr_active <= 1'b1;
                        wr_bank <= 1'b0;
                        wr_x <= 13'd4;
                        wr_y <= 0;
                        frame_width <= i_width;
                        frame_height <= i_height;
                        frame_id <= i_capture_id;
                        rd_next_group <= 0;
                        if (i_eol) begin
                            wr_x <= 0;
                            wr_y <= 1;
                            if (i_height == 1) begin
                                bank_full[0] <= 1'b1;
                                bank_group[0] <= 0;
                                bank_rows[0] <= 1;
                                wr_active <= 1'b0;
                            end
                        end
                    end
                end else if (i_sof || !marker_ok || i_capture_id != frame_id ||
                             i_width != frame_width || i_height != frame_height) begin
                    o_error_valid <= 1'b1;
                    o_error_capture_id <= frame_id;
                    o_error_code <= (i_capture_id != frame_id) ? ERR_ID : ERR_MARKER;
                    wr_active <= 1'b0;
                    frame_busy <= 1'b0;
                    drop_mode <= 1'b1;
                    rd_active <= 1'b0;
                    if (!ROW_STREAM_ENABLE || !o_row_valid || i_row_ready)
                        rd_pending <= 1'b0;
                    bank_full <= 2'b00;
                    // 接收端未取走前，受阻输出保持稳定
                end else begin
                    if (i_eol) begin
                        wr_x <= 0;
                        wr_y <= wr_y + 1'b1;
                        if (wr_y[2:0] == 3'd7 || (!ALIGNED_ROWS && wr_last_row)) begin
                            bank_full[wr_bank] <= 1'b1;
                            bank_group[wr_bank] <= wr_y >> 3;
                            bank_rows[wr_bank] <= {1'b0,wr_y[2:0]} + 1'b1;
                            wr_bank <= !wr_bank;
                            if (wr_last_row) wr_active <= 1'b0;
                        end
                    end else
                        wr_x <= wr_x + 13'd4;
                end
            end
        end
    end
    generate if (FIXED_GEOMETRY_ENABLE &&
        (MAX_WIDTH%240!=0 || MAX_HEIGHT%8!=0 || MAX_HEIGHT<8)) begin:g_bad_fixed_geometry
        JPEG_MCU_FIXED_GEOMETRY_REQUIRES_COMPLETE_ALIGNED_ROWS invalid_configuration();
    end endgenerate
    generate if (DUAL_GEOMETRY_ENABLE &&
        (DUAL_GEOMETRY_ENABLE!=1 || FIXED_GEOMETRY_ENABLE ||
         MAX_WIDTH<480 || MAX_WIDTH>3840 || MAX_WIDTH%480!=0 ||
         MAX_HEIGHT<16 || MAX_HEIGHT>2160 || MAX_HEIGHT%16!=0)) begin:g_bad_dual_geometry
        JPEG_MCU_DUAL_GEOMETRY_REQUIRES_TWO_ALIGNED_PROFILES invalid_configuration();
    end endgenerate
endmodule
