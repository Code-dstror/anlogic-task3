`timescale 1ns / 1ps
`default_nettype none

// Associate an independent neutral observation with actual record admission.
module neutral_record_observer4 #(
    parameter integer SOURCE_WIDTH = 1920,
    parameter integer SOURCE_HEIGHT = 1080
) (
    input wire i_clk, i_rst_n,
    input wire i_tap_valid,
    input wire [95:0] i_tap_rgb,
    input wire [31:0] i_tap_luma,
    input wire i_tap_sof, i_tap_eol, i_tap_eof,
    input wire i_source_abort,
    input wire [159:0] i_context,
    input wire [31:0] i_exposure,input wire [15:0] i_gain,
    input wire i_product_begin, i_frame_released,
    output wire o_pixel_valid,
    input wire i_pixel_ready,
    output wire [23:0] o_pixel_rgb,
    output wire [7:0] o_pixel_luma,
    output wire o_pixel_sof, o_pixel_eol, o_pixel_last,
    output wire m_stats_valid,
    input wire m_stats_ready,
    output wire [159:0] m_stats_context,
    output wire [183:0] m_statistics,
    input wire i_f20_required,
    output wire o_f20_pending,output wire o_f20_owner_start,output wire o_f20_status_valid,input wire i_f20_status_ready,
    output wire [159:0] o_f20_context,output wire o_f20_status_ok,
    output wire [7:0] o_f20_status_error,
    output wire [15:0] o_f20_sampled,o_f20_delivered,
    output wire [12:0] o_f20_width,o_f20_height,
    output wire [31:0] o_f20_exposure,output wire [15:0] o_f20_gain,
    output wire o_observer_busy,
    output wire [31:0] o_dropped_frames
);
    wire observer_ready, status_valid, status_ready, status_ok;
    wire [7:0] status_error, min_y, max_y;
    wire [15:0] sampled, delivered, dark_count, bright_count;
    wire [31:0] sum_y;
    wire [159:0] observer_context;
    wire [12:0] observation_width, observation_height;
    reg tap_seen, tap_accepted, product_owned, negative_pending;
    reg f20_required,f20_done,stats_status_done;
    reg [159:0] tap_context, product_context;
    wire tap_start = i_tap_valid && i_tap_sof;
    wire accepted_start = tap_start && observer_ready && !o_observer_busy;
    wire matching_tap = (tap_seen && tap_accepted && tap_context == i_context) || accepted_start;
    wire matching_status = observer_context == product_context;
    wire stats_fire = m_stats_valid && m_stats_ready;

    assign m_stats_valid = i_rst_n && product_owned &&
        (negative_pending || (status_valid && matching_status && !stats_status_done));
    assign m_stats_context = product_context;
    assign m_statistics = negative_pending ? {8'd1,8'd9,168'd0} :
        {8'd1,status_error,{7'd0,status_ok},3'd0,observation_height,
         3'd0,observation_width,8'd224,8'd32,max_y,min_y,
         bright_count,dark_count,sum_y,delivered,sampled};
    wire f20_fire=o_f20_status_valid&&i_f20_status_ready;
    wire observer_status_fire=status_valid&&status_ready;
    assign o_f20_pending=i_rst_n&&f20_required&&!f20_done;
    assign o_f20_owner_start=accepted_start&&i_f20_required;
    assign o_f20_status_valid=i_rst_n&&status_valid&&f20_required&&!f20_done;
    assign o_f20_context=observer_context;assign o_f20_status_ok=status_ok;
    assign o_f20_status_error=status_error;assign o_f20_sampled=sampled;
    assign o_f20_delivered=delivered;assign o_f20_width=observation_width;
    assign o_f20_height=observation_height;
    assign status_ready = (stats_status_done || (product_owned ?
        (negative_pending || !matching_status || m_stats_ready) : i_frame_released)) &&
        (!f20_required || f20_done || f20_fire);

    neutral_observer #(.SOURCE_WIDTH(SOURCE_WIDTH),.SOURCE_HEIGHT(SOURCE_HEIGHT)) u_observer (
        .i_clk(i_clk),.i_rst_n(i_rst_n),.i_tap_valid(i_tap_valid),
        .i_tap_rgb(i_tap_rgb),.i_tap_luma(i_tap_luma),.i_tap_keep(4'hf),
        .i_tap_sof(i_tap_sof),.i_tap_eol(i_tap_eol),.i_tap_eof(i_tap_eof),
        .i_source_abort(i_source_abort),.i_context(i_context),.i_exposure(i_exposure),.i_gain(i_gain),
        .i_width(SOURCE_WIDTH[12:0]),.i_height(SOURCE_HEIGHT[12:0]),
        .o_pixel_valid(o_pixel_valid),.i_pixel_ready(i_pixel_ready),.o_pixel_rgb(o_pixel_rgb),
        .o_pixel_luma(o_pixel_luma),.o_pixel_sof(o_pixel_sof),.o_pixel_eol(o_pixel_eol),.o_pixel_last(o_pixel_last),
        .o_context(observer_context),.o_exposure(o_f20_exposure),.o_gain(o_f20_gain),.o_source_width(),.o_source_height(),
        .o_observation_width(observation_width),.o_observation_height(observation_height),
        .o_status_valid(status_valid),.i_status_ready(status_ready),.o_status_ok(status_ok),
        .o_status_error(status_error),.o_status_pixels(sampled),.o_status_delivered(delivered),
        .o_status_sum_y(sum_y),.o_status_min_y(min_y),.o_status_max_y(max_y),
        .o_status_dark(dark_count),.o_status_bright(bright_count),
        .o_busy(o_observer_busy),.o_reset_done(observer_ready),.o_dropped_frames(o_dropped_frames)
    );

    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            tap_seen <= 0; tap_accepted <= 0; product_owned <= 0; negative_pending <= 0;
            tap_context <= 0; product_context <= 0;
            f20_required<=0;f20_done<=0;stats_status_done<=0;
        end else begin
            if(f20_fire)f20_done<=1;
            if(stats_fire&&!negative_pending&&status_valid&&matching_status)stats_status_done<=1;
            if(observer_status_fire)begin f20_required<=0;f20_done<=0;stats_status_done<=0;end
            if(accepted_start)begin f20_required<=i_f20_required;f20_done<=0;stats_status_done<=0;end
            if (i_frame_released) begin tap_seen <= 0; tap_accepted <= 0; end
            if (tap_start) begin
                tap_seen <= 1; tap_accepted <= accepted_start; tap_context <= i_context;
            end
            if (stats_fire) begin product_owned <= 0; negative_pending <= 0; end
            if (i_product_begin) begin
                product_owned <= 1; product_context <= i_context;
                negative_pending <= !matching_tap;
            end
        end
    end
endmodule
`default_nettype wire
