`timescale 1ns / 1ps
// Standalone capture verification top. Camera/clock/UART pins match the
// reference. AXIS stays inside the FPGA and is consumed by a frame monitor.
module imx415_camera_board_top #(
    parameter integer MODE_4K = 0
) (
    input wire sys_clk,
    input wire mipi_ref_clk_p,
    input wire mipi_clk_hs_rx_p,
    input wire [3:0] mipi_data_hs_p,
    output wire cam_scl,
    inout wire cam_sda,
    output wire cam_mclk,
    output wire cam_xclr,
    output wire uart_tx,
    input wire uart_rx
);
    wire pixel_clk, sensor_clk, pixel_lock, camera_lock;
    wire unused_aux, unused_camera_pixel, ref_clk;
    wire [127:0] data;
    wire [15:0] keep;
    wire valid, last, frame_error, frame_done;
    wire config_done, config_error, delay_ready;
    wire [31:0] ecc_errors, crc_errors, overflows, format_errors;
    reg [1:0] reset_sync;
    reg [31:0] frames, errors, digest, last_digest;
    wire reset_n = reset_sync[1];
    wire pll_reset_n = pixel_lock && camera_lock;
    wire [31:0] beat_digest = data[31:0] ^ data[63:32] ^ data[95:64] ^ data[127:96];
    sgdma_pll u_pixel_pll (.refclk(sys_clk),.reset(1'b0),.lock(pixel_lock),
        .clk0_out(pixel_clk),.clk1_out(unused_aux));
    ui_pll u_camera_pll (.refclk(mipi_ref_clk_p),.reset(1'b0),.lock(camera_lock),
        .clk0_out(unused_camera_pixel),.clk1_out(ref_clk),.clk2_out(sensor_clk));
    always @(posedge pixel_clk or negedge pll_reset_n) begin
        if (!pll_reset_n) reset_sync <= 0;
        else reset_sync <= {reset_sync[0],1'b1};
    end
    imx415_camera_axis #(.MODE_4K(MODE_4K)) u_camera (
        .i_pixel_clk(pixel_clk),.i_sensor_clk(sensor_clk),.i_ref_clk(ref_clk),
        .i_reset_n(reset_n),.mipi_clk_hs_rx_p(mipi_clk_hs_rx_p),
        .mipi_data_hs_p(mipi_data_hs_p),.cam_scl(cam_scl),.cam_sda(cam_sda),
        .cam_mclk(cam_mclk),.cam_xclr(cam_xclr),.o_axis_tdata(data),
        .o_axis_tkeep(keep),.o_axis_tvalid(valid),.i_axis_tready(1'b1),
        .o_axis_tlast(last),.o_frame_error(frame_error),.o_frame_done(frame_done),
        .o_config_done(config_done),.o_config_error(config_error),
        .o_ecc_errors(ecc_errors),.o_crc_errors(crc_errors),
        .o_overflows(overflows),.o_format_errors(format_errors),.o_delay_ready(delay_ready)
    );
    always @(posedge pixel_clk) begin
        if (!reset_n) begin frames <= 0; errors <= 0; digest <= 0; last_digest <= 0; end
        else begin
            if (frame_done) frames <= frames + 1'b1;
            if (frame_error) begin errors <= errors + 1'b1; digest <= 0; end
            else if (valid) begin
                if (last) begin last_digest <= digest ^ beat_digest; digest <= 0; end
                else digest <= digest ^ beat_digest;
            end
        end
    end
    camera_uart_status u_status (.i_clk(pixel_clk),.i_rst_n(reset_n),.i_frames(frames),
        .i_errors({config_done,config_error,delay_ready,errors[28:0]}),
        .i_digest(last_digest),.o_tx(uart_tx));
endmodule
