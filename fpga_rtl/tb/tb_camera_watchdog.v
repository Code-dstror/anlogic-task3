`timescale 1ns / 1ps

// Control-focused test for the watchdog inside imx415_camera_axis.  The DUT is
// the production top-level module; the child blocks below are behavioral port
// shells so this test can isolate watchdog sequencing from CSI/ISP behavior.
module tb_camera_watchdog;
    localparam integer SILENCE_CYCLES = 4;

    reg pixel_clk = 1'b0;
    reg sensor_clk = 1'b0;
    reg ref_clk = 1'b0;
    reg reset_n = 1'b0;
    reg axis_ready = 1'b1;
    reg config_done_drive = 1'b0;
    reg raw_valid_drive = 1'b0;
    reg phy_ready_drive = 1'b1;
    reg pipeline_ready_drive = 1'b1;
    integer fault_count = 0;
    integer expected_count;
    integer guard;
    reg previous_fault = 1'b0;

    always #5 pixel_clk = ~pixel_clk;
    always #7 sensor_clk = ~sensor_clk;
    always #4 ref_clk = ~ref_clk;

    imx415_camera_axis #(
        .SILENCE_CYCLES(SILENCE_CYCLES)
    ) dut (
        .i_pixel_clk(pixel_clk), .i_sensor_clk(sensor_clk), .i_ref_clk(ref_clk),
        .i_reset_n(reset_n), .mipi_clk_hs_rx_p(1'b0),
        .mipi_data_hs_p(4'b0), .cam_scl(), .cam_sda(), .cam_mclk(),
        .cam_xclr(), .o_axis_tdata(), .o_axis_tkeep(), .o_axis_tvalid(),
        .i_axis_tready(axis_ready), .o_axis_tlast(), .o_frame_error(),
        .o_frame_done(), .o_config_done(), .o_config_error(), .o_ecc_errors(),
        .o_crc_errors(), .o_overflows(), .o_format_errors(), .o_delay_ready()
    );

    // Sample after DUT nonblocking assignments have settled.
    always @(posedge pixel_clk) begin
        #1;
        if (dut.receive_fault)
            fault_count = fault_count + 1;
        if (dut.receive_fault && previous_fault) begin
            $display("[TB] ERROR watchdog abort wider than one pixel clock");
            $display("[TB] RESULT: FAIL");
            $finish;
        end
        previous_fault = dut.receive_fault;
    end

    task wait_pixel_cycles;
        input integer count;
        integer index;
        begin
            for (index = 0; index < count; index = index + 1)
                @(posedge pixel_clk);
            #2;
        end
    endtask

    task expect_fault_count;
        input integer wanted;
        input [8*48-1:0] context;
        begin
            if (fault_count !== wanted) begin
                $display("[TB] ERROR %0s: aborts=%0d expected=%0d",
                         context, fault_count, wanted);
                $display("[TB] RESULT: FAIL");
                $finish;
            end
        end
    endtask

    task wait_for_next_fault;
        input integer old_count;
        input [8*48-1:0] context;
        begin
            guard = 0;
            while ((fault_count == old_count) && (guard < SILENCE_CYCLES + 4)) begin
                wait_pixel_cycles(1);
                guard = guard + 1;
            end
            if (fault_count != old_count + 1) begin
                $display("[TB] ERROR %0s: aborts=%0d expected=%0d",
                         context, fault_count, old_count + 1);
                $display("[TB] RESULT: FAIL");
                $finish;
            end
        end
    endtask

    initial begin
        // Force only the child-block boundary signals used by the watchdog.
        force dut.sensor_done = config_done_drive;
        force dut.raw_valid = raw_valid_drive;
        force dut.phy_ready = phy_ready_drive;
        force dut.pipeline_raw_ready = pipeline_ready_drive;

        wait_pixel_cycles(3);
        reset_n = 1'b1;
        wait_pixel_cycles(4);
        config_done_drive = 1'b1;
        wait (dut.done_sync[1] === 1'b1);

        // A silent configured receiver reports exactly once for the episode.
        wait_for_next_fault(0, "initial silent-source timeout");
        wait_pixel_cycles(SILENCE_CYCLES * 2);
        expect_fault_count(1, "silent episode must not repeat");

        // A valid word held under backpressure is activity, not silence.
        raw_valid_drive = 1'b1;
        pipeline_ready_drive = 1'b0;
        wait_pixel_cycles(1);
        if (dut.raw_ready !== 1'b0) begin
            $display("[TB] ERROR stalled setup did not deassert raw_ready");
            $display("[TB] RESULT: FAIL");
            $finish;
        end
        wait_pixel_cycles(SILENCE_CYCLES * 2);
        expect_fault_count(1, "stalled raw_valid must suppress timeout");

        // One valid cycle rearms the watchdog; renewed silence reports once.
        pipeline_ready_drive = 1'b1;
        raw_valid_drive = 1'b0;
        expected_count = fault_count;
        wait_for_next_fault(expected_count, "raw activity must rearm timeout");
        wait_pixel_cycles(SILENCE_CYCLES * 2);
        expect_fault_count(expected_count + 1, "rearmed silence must not repeat");

        // Keep raw_valid asserted to exclude the timer, then drop PHY ready.
        raw_valid_drive = 1'b1;
        phy_ready_drive = 1'b1;
        wait_pixel_cycles(3);
        expected_count = fault_count;
        phy_ready_drive = 1'b0;
        wait_for_next_fault(expected_count, "PHY-ready falling edge");
        wait_pixel_cycles(SILENCE_CYCLES * 2);
        expect_fault_count(expected_count + 1, "low PHY level must not repeat");

        $display("[TB] watchdog abort pulses=%0d", fault_count);
        $display("[TB] RESULT: PASS");
        $finish;
    end
endmodule

// Behavioral port shells used only by tb_camera_watchdog.
module imx415_config #(parameter integer MODE_4K = 0) (
    input wire i_clk, input wire i_rst_n, output wire o_xclr,
    output wire o_scl, inout wire io_sda, output wire o_done,
    output wire o_error
);
    assign o_xclr = i_rst_n;
    assign o_scl = 1'b1;
    assign io_sda = 1'bz;
    assign o_done = 1'b0;
    assign o_error = 1'b0;
endmodule

module csi2_raw10_rx #(
    parameter integer MIPI_LAN = 4,
    parameter DEVICE = "PH1A"
) (
    input wire i_ref_clk, input wire i_mipi_clk_p,
    input wire [3:0] i_mipi_data_p, input wire i_pixel_clk,
    input wire i_reset_n, input wire i_enable, input wire i_debug_button,
    output wire [39:0] o_raw_data, output wire o_raw_valid,
    input wire i_raw_ready, output wire o_raw_sof, output wire o_raw_eol,
    output wire o_frame_abort, output wire [3:0] o_error_code,
    output wire [31:0] o_header_ecc_error_count,
    output wire [31:0] o_payload_crc_error_count,
    output wire [31:0] o_overflow_error_count,
    output wire [31:0] o_length_error_count, output wire o_hs_word_clk,
    output wire o_auto_delay_done, output wire [7:0] o_delay_debug,
    output wire [5:0] o_delay_window, output wire o_phy_ready
);
    assign o_raw_data = 40'b0;
    assign o_raw_valid = 1'b0;
    assign o_raw_sof = 1'b0;
    assign o_raw_eol = 1'b0;
    assign o_frame_abort = 1'b0;
    assign o_error_code = 4'b0;
    assign o_header_ecc_error_count = 32'b0;
    assign o_payload_crc_error_count = 32'b0;
    assign o_overflow_error_count = 32'b0;
    assign o_length_error_count = 32'b0;
    assign o_hs_word_clk = 1'b0;
    assign o_auto_delay_done = 1'b1;
    assign o_delay_debug = 8'b0;
    assign o_delay_window = 6'b0;
    assign o_phy_ready = 1'b0;
endmodule

module camera_rgb_pipeline #(
    parameter integer WIDTH = 1920, parameter integer HEIGHT = 1080,
    parameter integer FIRST_ROW = 20, parameter integer FIRST_GROUP = 1,
    parameter [1:0] BAYER_PHASE = 2'b00
) (
    input wire i_clk, input wire i_rst_n, input wire [39:0] i_raw_data,
    input wire i_raw_valid, output wire o_raw_ready, input wire i_raw_sof,
    input wire i_raw_eol, input wire i_raw_abort,
    output wire [127:0] o_axis_tdata, output wire [15:0] o_axis_tkeep,
    output wire o_axis_tvalid, input wire i_axis_tready,
    output wire o_axis_tlast, output wire o_frame_error,
    output wire o_frame_done
);
    assign o_raw_ready = 1'b1;
    assign o_axis_tdata = 128'b0;
    assign o_axis_tkeep = 16'b0;
    assign o_axis_tvalid = 1'b0;
    assign o_axis_tlast = 1'b0;
    assign o_frame_error = 1'b0;
    assign o_frame_done = 1'b0;
endmodule
