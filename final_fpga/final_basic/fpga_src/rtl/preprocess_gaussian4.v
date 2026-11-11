// Four RGB888 pixels per accepted beat, separable 3x3 Gaussian with replicated
// borders. Row storage uses existing PH1 ERAM IP, without port collisions.
module preprocess_gaussian4 #(
    parameter integer MAX_WIDTH = 3840,
    parameter integer MAX_HEIGHT = 2160,
    parameter integer MONOCHROME_STORAGE = 0,
    parameter integer WINDOW_TAP_ENABLE = 0,
    parameter integer WINDOW_STRIP_ENABLE = 0
) (
    input clk,
    input rst_n,
    input clear,
    input enable,
    input [12:0] width,
    input [12:0] height,
    input s_valid,
    output s_ready,
    input [95:0] s_data,
    input s_sof,
    input s_eol,
    output m_valid,
    input m_ready,
    output [95:0] m_data,
    output m_sof,
    output m_eol,
    input [31:0] s_luma,
    output [31:0] m_luma,
    output wire m_window_valid,
    output wire [(WINDOW_STRIP_ENABLE ? 144 : 288)-1:0] m_window
);
    localparam [1:0] ST_INPUT = 2'd0;
    localparam [1:0] ST_FLUSH = 2'd1;
    localparam [1:0] ST_BOTTOM = 2'd2;
    localparam [1:0] ST_DRAIN = 2'd3;

    reg [1:0] state;
    reg [12:0] row_index;
    reg [10:0] beat_index;
    reg [1:0] write_bank;
    wire [10:0] last_beat = width[12:2] - 11'd1;
    wire [1:0] previous_bank = (write_bank == 2'd0) ? 2'd2 : write_bank - 2'd1;
    wire [1:0] earlier_bank = (write_bank == 2'd2) ? 2'd0 : write_bank + 2'd1;

    reg bypass_valid;
    reg [95:0] bypass_data;
    reg [31:0] bypass_luma;
    reg bypass_sof, bypass_eol;
    reg output_valid;
    wire [95:0] output_data;
    reg output_sof, output_eol, output_eof;
    wire run = rst_n && !clear;
    // One common clock enable freezes the complete RAM/read/arithmetic path.
    // It depends only on the last valid register, not on pixel arithmetic.
    wire advance = enable && run && (!output_valid || m_ready);
    assign s_ready = run && (enable ? (advance && state == ST_INPUT)
                                         : (!bypass_valid || m_ready));
    assign m_valid = run && (enable ? output_valid : bypass_valid);
    assign m_data = enable ? output_data : bypass_data;
    assign m_sof = enable ? output_sof : bypass_sof;
    assign m_eol = enable ? output_eol : bypass_eol;
    assign m_luma = enable ?
        {output_data[79:72],output_data[55:48],output_data[31:24],output_data[7:0]} : bypass_luma;

    wire take_input = s_valid && s_ready && enable;
    wire take_bottom = advance && state == ST_BOTTOM;
    wire take_flush = advance && state == ST_FLUSH;
    wire request_read = (take_input && row_index != 13'd0) || take_bottom;
    wire [95:0] bank_data [0:2];
    genvar bank;
    generate
        for (bank = 0; bank < 3; bank = bank + 1) begin : g_line
            // Current input row writes a third bank. Neither historical row is
            // overwritten until it is no longer needed by the 3x3 window.
            if (MONOCHROME_STORAGE == 0) begin : g_rgb
            preprocess_line_ram96x1024 u_ram (
                .clk(clk), .wr_en(take_input && write_bank == bank),
                .wr_addr(beat_index[9:0]), .wr_data(s_data),
                .rd_en(request_read && ((previous_bank == bank) ||
                    ((row_index > 13'd1) && earlier_bank == bank))),
                .rd_addr(beat_index[9:0]), .rd_data(bank_data[bank])
            );
            end else begin : g_luma
                wire [31:0] row_luma;
                preprocess_line_ram32x1024 #(.DEPTH((MAX_WIDTH+3)/4)) u_ram (
                    .clk(clk),.wr_en(take_input && write_bank == bank),
                    .wr_addr(beat_index[9:0]),.wr_data(s_luma),
                    .rd_en(request_read && ((previous_bank == bank) ||
                        ((row_index > 13'd1) && earlier_bank == bank))),
                    .rd_addr(beat_index[9:0]),.rd_data(row_luma));
                assign bank_data[bank] = {{3{row_luma[31:24]}},{3{row_luma[23:16]}},
                                         {3{row_luma[15:8]}},{3{row_luma[7:0]}}};
            end
        end
    endgenerate

    // RAM request metadata. Row zero only fills storage; output row y-1 is
    // generated while input row y arrives. A virtual bottom row completes EOF.
    reg read_valid, read_first, read_last, read_flush;
    reg read_row_first, read_row_final, read_top_repeat, read_bottom_repeat;
    reg [1:0] read_previous_bank, read_earlier_bank;
    reg [95:0] read_input;
    wire [95:0] middle_pixels = bank_data[read_previous_bank];
    wire [95:0] top_pixels = read_top_repeat ? middle_pixels : bank_data[read_earlier_bank];
    wire [95:0] bottom_pixels = read_bottom_repeat ? middle_pixels : read_input;
    wire [95:0] input_gray = {{3{s_luma[31:24]}},{3{s_luma[23:16]}},
                              {3{s_luma[15:8]}},{3{s_luma[7:0]}}};

    // First arithmetic stage: top+bottom and 2*middle, each 9 unsigned bits.
    reg vertical1_valid, vertical1_first, vertical1_last, vertical1_flush;
    reg vertical1_row_first, vertical1_row_final;
    reg [107:0] vertical_sides;
    reg [107:0] vertical_middle;
    // Second arithmetic stage: 10-bit vertical sum, with no intermediate round.
    reg vertical2_valid, vertical2_first, vertical2_last, vertical2_flush;
    reg vertical2_row_first, vertical2_row_final;
    reg [119:0] vertical_sum;

    // One beat of lookahead provides the right neighbour of lane 3. The first
    // and final neighbours of every line repeat the actual boundary pixel.
    reg [119:0] center_pixels;
    reg [29:0] left_pixel;
    reg center_first, center_last, center_row_first, center_row_final;
    wire [29:0] right_pixel = vertical2_flush ? center_pixels[119:90]
                                                        : vertical_sum[29:0];
    reg horizontal_valid, horizontal_sof, horizontal_eol, horizontal_eof;
    reg [143:0] rounded_sides;

    // MREG at the former side-sum edge, PREG at its following edge.
    // Common ADVANCE holds data and row/window metadata through backpressure.
    // Global reset alone reaches DSP RST; CLEAR flushes the public valid path.
    localparam integer ARITH_CHANNELS=MONOCHROME_STORAGE ? 4 : 12;
    genvar arithmetic;
    generate for(arithmetic=0;arithmetic<ARITH_CHANNELS;arithmetic=arithmetic+1)begin:g_dsp_sum
        localparam integer CHANNEL=MONOCHROME_STORAGE ? arithmetic*3 : arithmetic;
        wire [33:0] horizontal_mac;
        fdct_mac19s14s_z33s_p34_m1p1 u_horizontal(
            .CLK(clk),.CE(advance),.RST(!rst_n),
            .A({9'd0,center_pixels[CHANNEL*10+:10]}),.Y(14'd2),
            .Z({21'd0,rounded_sides[CHANNEL*12+:12]}),.P(horizontal_mac));
        if(MONOCHROME_STORAGE)begin:g_h_repeat
            assign output_data[arithmetic*24+:24]={3{horizontal_mac[11:4]}};
        end else begin:g_h_rgb
            assign output_data[arithmetic*8+:8]=horizontal_mac[11:4];
        end
    end endgenerate

    integer c;
    integer lane;
    integer component;
    reg [9:0] left_component;
    reg [9:0] right_component;
    always @(posedge clk) begin
        if (!rst_n || clear) begin
            state <= ST_INPUT;
            row_index <= 13'd0;
            beat_index <= 11'd0;
            write_bank <= 2'd0;
            bypass_valid <= 1'b0;
            output_valid <= 1'b0;
            read_valid <= 1'b0;
            vertical1_valid <= 1'b0;
            vertical2_valid <= 1'b0;
            horizontal_valid <= 1'b0;
            output_sof <= 1'b0;
            output_eol <= 1'b0;
            output_eof <= 1'b0;
            bypass_sof <= 1'b0;
            bypass_eol <= 1'b0;
        end else begin
            if (!enable && (!bypass_valid || m_ready)) begin
                bypass_valid <= s_valid;
                if (s_valid) begin
                    bypass_data <= s_data;
                    bypass_luma <= s_luma;
                    bypass_sof <= s_sof;
                    bypass_eol <= s_eol;
                end
            end

            if (advance) begin
                read_valid <= request_read || (take_flush && row_index != 13'd0);
                if (request_read || take_flush) begin
                    read_first <= !take_flush && beat_index == 11'd0;
                    read_last <= !take_flush && beat_index == last_beat;
                    read_flush <= take_flush;
                    read_row_first <= row_index == 13'd1;
                    read_row_final <= row_index == height;
                    read_top_repeat <= row_index == 13'd1;
                    read_bottom_repeat <= take_bottom;
                    read_previous_bank <= previous_bank;
                    read_earlier_bank <= earlier_bank;
                    read_input <= MONOCHROME_STORAGE ? input_gray : s_data;
                end

                vertical1_valid <= read_valid;
                if (read_valid) begin
                    vertical1_first <= read_first;
                    vertical1_last <= read_last;
                    vertical1_flush <= read_flush;
                    vertical1_row_first <= read_row_first;
                    vertical1_row_final <= read_row_final;
                    for (c = 0; c < 12; c = c + 1) begin
                        vertical_sides[c*9 +: 9] <=
                            {1'b0, top_pixels[c*8 +: 8]} +
                            {1'b0, bottom_pixels[c*8 +: 8]};
                        vertical_middle[c*9 +: 9] <= {middle_pixels[c*8 +: 8], 1'b0};
                    end
                end

                vertical2_valid <= vertical1_valid;
                if (vertical1_valid) begin
                    vertical2_first <= vertical1_first;
                    vertical2_last <= vertical1_last;
                    vertical2_flush <= vertical1_flush;
                    vertical2_row_first <= vertical1_row_first;
                    vertical2_row_final <= vertical1_row_final;
                    for (c = 0; c < 12; c = c + 1) begin
                        vertical_sum[c*10 +: 10] <=
                            {1'b0, vertical_sides[c*9 +: 9]} +
                            {1'b0, vertical_middle[c*9 +: 9]};
                    end
                end

                horizontal_valid <= vertical2_valid && !vertical2_first;
                if (vertical2_valid) begin
                    if (!vertical2_flush) begin
                        center_pixels <= vertical_sum;
                        left_pixel <= vertical2_first ? vertical_sum[29:0] : center_pixels[119:90];
                        center_first <= vertical2_first;
                        center_last <= vertical2_last;
                        center_row_first <= vertical2_row_first;
                        center_row_final <= vertical2_row_final;
                    end
                    if (!vertical2_first) begin
                        horizontal_sof <= center_first && center_row_first;
                        horizontal_eol <= center_last;
                        horizontal_eof <= center_last && center_row_final;
                        for (lane = 0; lane < 4; lane = lane + 1) begin
                            for (component = 0; component < 3; component = component + 1) begin
                                if (lane == 0)
                                    left_component = left_pixel[component*10 +: 10];
                                else
                                    left_component = center_pixels[((lane-1)*3+component)*10 +: 10];
                                if (lane == 3)
                                    right_component = right_pixel[component*10 +: 10];
                                else
                                    right_component = center_pixels[((lane+1)*3+component)*10 +: 10];
                                rounded_sides[(lane*3+component)*12 +: 12] <=
                                    {2'b0,left_component}+{2'b0,right_component}+12'd8;
                            end
                        end
                    end
                end

                output_valid <= horizontal_valid;
                if (horizontal_valid) begin
                    output_sof <= horizontal_sof;
                    output_eol <= horizontal_eol;
                    output_eof <= horizontal_eof;
                end

                if (take_input || take_bottom) begin
                    if (beat_index == last_beat)
                        state <= ST_FLUSH;
                    else
                        beat_index <= beat_index + 11'd1;
                end else if (take_flush) begin
                    beat_index <= 11'd0;
                    if (row_index == height) begin
                        state <= ST_DRAIN;
                    end else begin
                        row_index <= row_index + 13'd1;
                        write_bank <= (write_bank == 2'd2) ? 2'd0 : write_bank + 2'd1;
                        state <= (row_index == height - 13'd1) ? ST_BOTTOM : ST_INPUT;
                    end
                end

                // No subsequent frame is accepted before the visible final
                // output beat handshakes. clear is the explicit cancel path.
                if (output_valid && m_ready && output_eof) begin
                    state <= ST_INPUT;
                    row_index <= 13'd0;
                    beat_index <= 11'd0;
                    write_bank <= 2'd0;
                end
            end
        end
    end

    // Optional reusable Y window, sharing the exact row and lookahead service.
    // Lane n owns 72 bits; byte0 is top-left, then row-major through bottom-right.
    generate if (WINDOW_TAP_ENABLE && MONOCHROME_STORAGE) begin : g_window
        reg [95:0] rows1,rows2,center_rows;
        reg [23:0] left_column;
        localparam integer WINDOW_BITS=WINDOW_STRIP_ENABLE ? 144 : 288;
        reg [WINDOW_BITS-1:0] horizontal_window,output_window;
        integer row,lane_index;
        always @(posedge clk) begin
            if (advance) begin
                if (read_valid) begin
                    rows1 <= {bottom_pixels[79:72],bottom_pixels[55:48],bottom_pixels[31:24],bottom_pixels[7:0],
                              middle_pixels[79:72],middle_pixels[55:48],middle_pixels[31:24],middle_pixels[7:0],
                              top_pixels[79:72],top_pixels[55:48],top_pixels[31:24],top_pixels[7:0]};
                end
                if (vertical1_valid) rows2 <= rows1;
                if (vertical2_valid) begin
                    if (!vertical2_flush) begin
                        center_rows <= rows2;
                        for (row=0;row<3;row=row+1)
                            left_column[row*8 +:8] <= vertical2_first ?
                                rows2[row*32 +:8] : center_rows[row*32+24 +:8];
                    end
                    if (!vertical2_first) begin
                        if (WINDOW_STRIP_ENABLE) begin
                            // Row-major union of four adjacent windows: 3 x 6 Y.
                            for (row=0;row<3;row=row+1) begin
                                horizontal_window[(row*6)*8 +:8] <= left_column[row*8 +:8];
                                horizontal_window[(row*6+1)*8 +:32] <= center_rows[row*32 +:32];
                                horizontal_window[(row*6+5)*8 +:8] <= vertical2_flush ?
                                    center_rows[row*32+24 +:8] : rows2[row*32 +:8];
                            end
                        end else begin
                        for (lane_index=0;lane_index<4;lane_index=lane_index+1) begin
                            for (row=0;row<3;row=row+1) begin
                                horizontal_window[lane_index*72+row*24 +:8] <= lane_index==0 ?
                                    left_column[row*8 +:8] : center_rows[row*32+(lane_index-1)*8 +:8];
                                horizontal_window[lane_index*72+row*24+8 +:8] <= center_rows[row*32+lane_index*8 +:8];
                                horizontal_window[lane_index*72+row*24+16 +:8] <= lane_index==3 ?
                                    (vertical2_flush ? center_rows[row*32+24 +:8] : rows2[row*32 +:8]) :
                                    center_rows[row*32+(lane_index+1)*8 +:8];
                            end
                        end
                        end
                    end
                end
                if (horizontal_valid) output_window <= horizontal_window;
            end
        end
        assign m_window_valid = m_valid && enable;
        assign m_window = output_window;
    end else begin : g_no_window
        assign m_window_valid = 1'b0;
        assign m_window = {(WINDOW_STRIP_ENABLE ? 144 : 288){1'b0}};
    end endgenerate
endmodule
