// Independent image selection and shared native Y analysis window.
// See CONTRACT.md. One clock, synchronous active-low reset, no CDC.
module stage3_filter_color4 #(
    parameter integer MAX_WIDTH = 1920,
    parameter integer MAX_HEIGHT = 1080,
    parameter integer WINDOW_STRIP_ENABLE = 0
) (
    input clk, rst_n, cancel,
    input start_valid, output start_ready,
    input [12:0] cfg_width, cfg_height,
    input cfg_gray, cfg_legacy_gaussian, cfg_color_filter, cfg_multiscale, cfg_lane,
    input [159:0] cfg_context,
    output analysis_start_valid, input analysis_start_ready,
    output [12:0] analysis_width, analysis_height,
    output [159:0] analysis_context,
    output analysis_lane, analysis_cancel,
    input analysis_complete, analysis_error, source_error,
    input s_valid, output s_ready,
    input [95:0] s_rgb, input [31:0] s_y, input s_sof, s_eol,
    output m_valid, input m_ready,
    output [95:0] m_rgb, output [31:0] m_y, output m_sof, m_eol,
    output a_valid, input a_ready,
    output [(WINDOW_STRIP_ENABLE ? 144 : 288)-1:0] a_window, output [31:0] a_filtered_y,
    output a_sof, a_eol,
    output reg busy, output reg frame_complete, frame_error,
    output reg [3:0] error_code,
    output [159:0] terminal_context
);
    reg [12:0] width, height, input_y, image_y, analysis_y;
    reg [10:0] input_x;
    reg gray, legacy, color_filter, multiscale, lane;
    wire color_active = color_filter && !legacy;
    wire filtered_image = legacy || color_active;
    reg [159:0] context;
    assign terminal_context = context;
    reg input_done, image_done, tap_done, analysis_done;
    wire cfg_ok = cfg_width >= 4 && cfg_width <= MAX_WIDTH && cfg_width <= 1920 &&
        cfg_width[1:0] == 0 && cfg_height >= 1 && cfg_height <= MAX_HEIGHT &&
        (!cfg_lane || cfg_multiscale);
    assign start_ready = rst_n && !cancel && !busy &&
        (!cfg_ok || !cfg_multiscale || analysis_start_ready);
    assign analysis_start_valid = rst_n && !cancel && !busy &&
        start_valid && cfg_ok && cfg_multiscale;
    assign analysis_width = busy ? width : cfg_width;
    assign analysis_height = busy ? height : cfg_height;
    assign analysis_context = busy ? context : cfg_context;
    assign analysis_lane = busy ? lane : cfg_lane;
    wire expected_sof = input_x == 0 && input_y == 0;
    wire expected_eol = input_x == width[12:2]-1'b1;
    wire bad_mark = s_sof != expected_sof || s_eol != expected_eol;
    wire in_ready;
    wire fault = busy && (source_error || (multiscale && analysis_error) ||
        (s_valid && !input_done && bad_mark) ||
        (multiscale && analysis_complete && !tap_done));
    wire clear = cancel || fault;
    assign analysis_cancel = clear;
    assign s_ready = rst_n && busy && !cancel && !input_done && in_ready;
    wire [1:0] in_valid, in_down_ready;
    wire [129:0] in_payload, work_payload;
    wire [95:0] gray_rgb = {{3{s_y[31:24]}},{3{s_y[23:16]}},
                           {3{s_y[15:8]}},{3{s_y[7:0]}}};
    stage3_stream_fork2 #(.WIDTH(130)) u_input (
        .clk(clk),.rst_n(rst_n),.clear(clear),
        .destinations({filtered_image || multiscale,!filtered_image}),
        .s_valid(s_valid && busy && !input_done && !bad_mark),.s_ready(in_ready),
        .s_payload({s_eol,s_sof,s_y,gray ? gray_rgb : s_rgb}),
        .m_valid(in_valid),.m_ready(in_down_ready),
        .m_payload0(in_payload),.m_payload1(work_payload));
    wire gauss_valid, gauss_ready, gauss_sof, gauss_eol, gauss_window_valid;
    wire gauss_input_ready, rgb_input_ready, rgb_valid, rgb_ready;
    wire [95:0] delayed_rgb;
    wire [9:0] rgb_occupancy;
    assign in_down_ready[1] = gauss_input_ready && (!color_active || rgb_input_ready);
    stage3_rgb_delay96 rgb_delay (
        .clk(clk),.rst_n(rst_n),.clear(clear),
        .s_valid(in_valid[1] && color_active && gauss_input_ready),
        .s_ready(rgb_input_ready),.s_data(work_payload[95:0]),
        .m_valid(rgb_valid),.m_ready(rgb_ready),.m_data(delayed_rgb),
        .occupancy(rgb_occupancy));
    wire [31:0] gauss_y;
    wire [143:0] gauss_strip;
    preprocess_gaussian4 #(.MAX_WIDTH(MAX_WIDTH),.MAX_HEIGHT(MAX_HEIGHT),
        .MONOCHROME_STORAGE(1),.WINDOW_TAP_ENABLE(1),.WINDOW_STRIP_ENABLE(1)) u_gauss (
        .clk(clk),.rst_n(rst_n),.clear(clear),.enable(busy && (filtered_image || multiscale)),
        .width(width),.height(height),.s_valid(in_valid[1] && (!color_active || rgb_input_ready)),.s_ready(gauss_input_ready),
        .s_data(work_payload[95:0]),.s_luma(work_payload[127:96]),
        .s_sof(work_payload[128]),.s_eol(work_payload[129]),
        .m_valid(gauss_valid),.m_ready(gauss_ready),.m_data(),.m_luma(gauss_y),
        .m_sof(gauss_sof),.m_eol(gauss_eol),
        .m_window_valid(gauss_window_valid),.m_window(gauss_strip));
    wire [1:0] result_valid;
    wire [273:0] result_payload, analysis_payload;
    wire result_ready, image_ready;
    assign gauss_ready = result_ready && (!color_active || rgb_valid);
    assign rgb_ready = color_active && gauss_valid && result_ready;
    stage3_stream_fork2 #(.WIDTH(274)) u_result (
        .clk(clk),.rst_n(rst_n),.clear(clear),.destinations({multiscale,filtered_image}),
        .s_valid(gauss_valid && busy && (!color_active || rgb_valid)),.s_ready(result_ready),
        .s_payload({delayed_rgb,gauss_eol,gauss_sof,gauss_strip,gauss_y}),
        .m_valid(result_valid),.m_ready({a_ready,image_ready}),
        .m_payload0(result_payload),.m_payload1(analysis_payload));
    wire blend_valid, blend_ready, blend_sof, blend_eol;
    wire [95:0] blend_rgb;
    wire [31:0] blend_y;
    wire [31:0] center_y;
    genvar center_lane;
    generate for(center_lane=0;center_lane<4;center_lane=center_lane+1) begin : g_center
        assign center_y[center_lane*8 +:8]=result_payload[32+(6+center_lane+1)*8 +:8];
    end endgenerate
    stage3_luma_blend4 blend (
        .clk(clk),.rst_n(rst_n),.clear(clear),
        .s_valid(result_valid[0] && color_active),.s_ready(blend_ready),
        .s_rgb(result_payload[273:178]),.s_center_y(center_y),.s_filtered_y(result_payload[31:0]),
        .s_sof(result_payload[176]),.s_eol(result_payload[177]),
        .m_valid(blend_valid),.m_ready(m_ready && color_active),
        .m_rgb(blend_rgb),.m_y(blend_y),.m_sof(blend_sof),.m_eol(blend_eol));
    assign image_ready = color_active ? blend_ready : m_ready;
    assign in_down_ready[0] = !filtered_image && m_ready;
    assign m_valid = busy && (color_active ? blend_valid : legacy ? result_valid[0] : in_valid[0]);
    assign m_y = color_active ? blend_y : legacy ? result_payload[31:0] : in_payload[127:96];
    assign m_rgb = color_active ? blend_rgb : legacy ? {{3{m_y[31:24]}},{3{m_y[23:16]}},
                            {3{m_y[15:8]}},{3{m_y[7:0]}}} : in_payload[95:0];
    assign m_sof = color_active ? blend_sof : legacy ? result_payload[176] : in_payload[128];
    assign m_eol = color_active ? blend_eol : legacy ? result_payload[177] : in_payload[129];
    assign a_valid = busy && multiscale && result_valid[1];
    wire [143:0] a_strip = analysis_payload[175:32];
    // Default public interface remains compatible. Production uses only strip,
    // with expansion adjacent to native_math rather than across the adapter.
    generate if (WINDOW_STRIP_ENABLE) begin:g_strip_interface
        assign a_window = a_strip;
    end else begin:g_window_interface
        genvar window_lane,window_row,window_column;
        for(window_lane=0;window_lane<4;window_lane=window_lane+1)begin:g_lane
            for(window_row=0;window_row<3;window_row=window_row+1)begin:g_row
                for(window_column=0;window_column<3;window_column=window_column+1)begin:g_column
                    assign a_window[window_lane*72+window_row*24+window_column*8 +:8] =
                        a_strip[(window_row*6+window_lane+window_column)*8 +:8];
                end
            end
        end
    end endgenerate
    assign a_filtered_y = analysis_payload[31:0];
    assign a_sof = analysis_payload[176];
    assign a_eol = analysis_payload[177];
    always @(posedge clk) begin
        if (!rst_n) begin
            busy <= 0; frame_complete <= 0; frame_error <= 0; error_code <= 0;
            width <= 4; height <= 1; gray <= 0; legacy <= 0; color_filter <= 0; multiscale <= 0;
            lane <= 0; context <= 0;
            input_x <= 0; input_y <= 0; image_y <= 0; analysis_y <= 0;
            input_done <= 0; image_done <= 0; tap_done <= 0; analysis_done <= 0;
        end else begin
            frame_complete <= 0; frame_error <= 0;
            if (cancel || fault) begin
                busy <= 0;
                frame_error <= busy;
                error_code <= cancel ? 4'd2 : source_error ? 4'd3 :
                    analysis_error ? 4'd4 : analysis_complete ? 4'd6 : 4'd5;
            end else if (start_valid && start_ready) begin
                context <= cfg_context;
                if (!cfg_ok) begin frame_error <= 1; error_code <= 1; end
                else begin
                    busy <= 1; width <= cfg_width; height <= cfg_height;
                    gray <= cfg_gray; legacy <= cfg_legacy_gaussian; color_filter <= cfg_color_filter;
                    multiscale <= cfg_multiscale; lane <= cfg_lane; context <= cfg_context;
                    input_x <= 0; input_y <= 0; image_y <= 0; analysis_y <= 0;
                    input_done <= 0; image_done <= 0; tap_done <= !cfg_multiscale;
                    analysis_done <= !cfg_multiscale; error_code <= 0;
                end
            end else if (busy) begin
                if (s_valid && s_ready) begin
                    if (s_eol) begin
                        input_x <= 0; input_y <= input_y + 1'b1;
                        if (input_y == height-1'b1) input_done <= 1;
                    end else input_x <= input_x + 1'b1;
                end
                if (m_valid && m_ready && m_eol) begin
                    image_y <= image_y + 1'b1;
                    if (image_y == height-1'b1) image_done <= 1;
                end
                if (a_valid && a_ready && a_eol) begin
                    analysis_y <= analysis_y + 1'b1;
                    if (analysis_y == height-1'b1) tap_done <= 1;
                end
                if (multiscale && analysis_complete) analysis_done <= 1;
                if (input_done && image_done && tap_done && analysis_done) begin
                    busy <= 0; frame_complete <= 1;
                end
            end
        end
    end
endmodule
