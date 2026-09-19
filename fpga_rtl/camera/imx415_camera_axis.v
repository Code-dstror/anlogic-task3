`timescale 1ns / 1ps
// Camera IP boundary. Only camera-facing signals become pins in a board top;
// the RGB AXIS and diagnostic ports are internal application interfaces.
module imx415_camera_axis #(
    parameter integer MODE_4K = 0,
    parameter integer FIRST_ROW = MODE_4K ? 36 : 20,
    parameter integer FIRST_GROUP = 1,
    parameter [1:0] BAYER_PHASE = 2'b00,
    parameter integer SILENCE_CYCLES = 12500000
) (
    input wire i_pixel_clk,
    input wire i_sensor_clk,
    input wire i_ref_clk,
    input wire i_reset_n,
    input wire mipi_clk_hs_rx_p,
    input wire [3:0] mipi_data_hs_p,
    output wire cam_scl,
    inout wire cam_sda,
    output wire cam_mclk,
    output wire cam_xclr,
    output wire [127:0] o_axis_tdata,
    output wire [15:0] o_axis_tkeep,
    output wire o_axis_tvalid,
    input wire i_axis_tready,
    output wire o_axis_tlast,
    output wire o_frame_error,
    output wire o_frame_done,
    output wire o_config_done,
    output wire o_config_error,
    output wire [31:0] o_ecc_errors,
    output wire [31:0] o_crc_errors,
    output wire [31:0] o_overflows,
    output wire [31:0] o_format_errors,
    output wire o_delay_ready
);
    localparam integer WIDTH = MODE_4K ? 3840 : 1920;
    localparam integer HEIGHT = MODE_4K ? 2160 : 1080;
    reg [1:0] sensor_reset, pixel_reset, ref_reset;
    reg [1:0] done_sync, error_sync, enable_sync;
    wire sensor_done, sensor_error;
    wire [39:0] raw_data;
    wire raw_valid, raw_ready, raw_sof, raw_eol, raw_abort;
    wire pipeline_raw_ready;
    wire phy_ready;
    reg phy_previous;
    reg [31:0] silence_count;
    reg silence_reported, receive_fault;
    wire [3:0] error_code;
    wire hs_word_clk, delay_ready;
    wire [7:0] delay_debug;
    wire [5:0] delay_window;
    reg [1:0] delay_sync;
    assign cam_mclk = i_sensor_clk;
    assign o_config_done = done_sync[1];
    assign o_config_error = error_sync[1];
    assign o_delay_ready = delay_sync[1];
    assign raw_ready = pipeline_raw_ready && !receive_fault;
    always @(posedge i_sensor_clk or negedge i_reset_n) begin
        if (!i_reset_n) sensor_reset <= 0;
        else sensor_reset <= {sensor_reset[0],1'b1};
    end
    // One abort per lost-clock or silent-source episode. A stalled valid item
    // is not silence; the finite FIFO separately handles receiver overflow.
    always @(posedge i_pixel_clk) begin
        if (!pixel_reset[1]) begin
            phy_previous <= 0;
            silence_count <= 0;
            silence_reported <= 0;
            receive_fault <= 0;
        end else begin
            phy_previous <= phy_ready;
            receive_fault <= 0;
            if (!done_sync[1] || raw_valid) begin
                silence_count <= 0;
                silence_reported <= 0;
            end else if (!silence_reported) begin
                if (silence_count == SILENCE_CYCLES-1) begin
                    receive_fault <= 1;
                    silence_reported <= 1;
                end else silence_count <= silence_count + 1'b1;
            end
            if (phy_previous && !phy_ready) receive_fault <= 1;
        end
    end
    always @(posedge i_ref_clk or negedge i_reset_n) begin
        if (!i_reset_n) begin ref_reset <= 0; enable_sync <= 0; end
        else begin
            ref_reset <= {ref_reset[0],1'b1};
            enable_sync <= {enable_sync[0],sensor_done};
        end
    end
    always @(posedge i_pixel_clk or negedge i_reset_n) begin
        if (!i_reset_n) begin
            pixel_reset <= 0; done_sync <= 0; error_sync <= 0; delay_sync <= 0;
        end else begin
            pixel_reset <= {pixel_reset[0],1'b1};
            done_sync <= {done_sync[0],sensor_done};
            error_sync <= {error_sync[0],sensor_error};
            delay_sync <= {delay_sync[0],delay_ready};
        end
    end
    imx415_config #(.MODE_4K(MODE_4K)) u_config (
        .i_clk(i_sensor_clk),.i_rst_n(sensor_reset[1]),
        .o_xclr(cam_xclr),.o_scl(cam_scl),.io_sda(cam_sda),
        .o_done(sensor_done),.o_error(sensor_error)
    );
    csi2_raw10_rx #(.MIPI_LAN(4),.DEVICE("PH1A")) u_receiver (
        .i_ref_clk(i_ref_clk),.i_mipi_clk_p(mipi_clk_hs_rx_p),
        .i_mipi_data_p(mipi_data_hs_p),.i_pixel_clk(i_pixel_clk),
        .i_reset_n(ref_reset[1]),.i_enable(enable_sync[1]),.i_debug_button(1'b1),
        .o_raw_data(raw_data),.o_raw_valid(raw_valid),.i_raw_ready(raw_ready),
        .o_raw_sof(raw_sof),.o_raw_eol(raw_eol),.o_frame_abort(raw_abort),
        .o_error_code(error_code),.o_header_ecc_error_count(o_ecc_errors),
        .o_payload_crc_error_count(o_crc_errors),.o_overflow_error_count(o_overflows),
        .o_length_error_count(o_format_errors),.o_hs_word_clk(hs_word_clk),
        .o_auto_delay_done(delay_ready),.o_delay_debug(delay_debug),
        .o_delay_window(delay_window),.o_phy_ready(phy_ready)
    );
    camera_rgb_pipeline #(.WIDTH(WIDTH),.HEIGHT(HEIGHT),.FIRST_ROW(FIRST_ROW),
        .FIRST_GROUP(FIRST_GROUP),.BAYER_PHASE(BAYER_PHASE)) u_pipeline (
        .i_clk(i_pixel_clk),.i_rst_n(pixel_reset[1]),.i_raw_data(raw_data),
        .i_raw_valid(raw_valid || receive_fault),.o_raw_ready(pipeline_raw_ready),
        .i_raw_sof(raw_sof && !receive_fault),
        .i_raw_eol(raw_eol && !receive_fault),.i_raw_abort(raw_abort || receive_fault),
        .o_axis_tdata(o_axis_tdata),.o_axis_tkeep(o_axis_tkeep),
        .o_axis_tvalid(o_axis_tvalid),.i_axis_tready(i_axis_tready),
        .o_axis_tlast(o_axis_tlast),.o_frame_error(o_frame_error),.o_frame_done(o_frame_done)
    );
endmodule
