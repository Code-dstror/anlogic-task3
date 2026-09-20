`timescale 1ns / 1ps

module tb_h2c_stream_checker;

    reg clk;
    reg rst_n;
    reg [127:0] axis_tdata;
    reg [15:0] axis_tkeep;
    reg axis_tvalid;
    reg axis_tlast;
    wire axis_tready;
    wire [31:0] byte_count;
    wire [31:0] frame_count;
    wire [31:0] error_count;
    wire [31:0] first_error_offset;
    integer lane;

    h2c_stream_checker u_dut (
        .i_clk(clk),
        .i_rst_n(rst_n),
        .i_axis_tdata(axis_tdata),
        .i_axis_tkeep(axis_tkeep),
        .i_axis_tvalid(axis_tvalid),
        .o_axis_tready(axis_tready),
        .i_axis_tlast(axis_tlast),
        .o_byte_count(byte_count),
        .o_frame_count(frame_count),
        .o_error_count(error_count),
        .o_first_error_offset(first_error_offset)
    );

    always #4 clk = !clk;

    task send_incrementing_beat;
        input [7:0] base;
        input [15:0] keep;
        input last;
        input [15:0] corrupt_mask;
        begin
            @(negedge clk);
            for (lane = 0; lane < 16; lane = lane + 1) begin
                axis_tdata[(lane * 8) +: 8] = base + lane;
                if (corrupt_mask[lane]) begin
                    axis_tdata[(lane * 8) +: 8] = (base + lane) ^ 8'h5a;
                end
            end
            axis_tkeep = keep;
            axis_tlast = last;
            axis_tvalid = 1'b1;
            while (!axis_tready) begin
                @(negedge clk);
            end
            @(negedge clk);
            axis_tvalid = 1'b0;
            axis_tlast = 1'b0;
            axis_tkeep = 16'd0;
        end
    endtask

    initial begin
        clk = 1'b0;
        rst_n = 1'b0;
        axis_tdata = 128'd0;
        axis_tkeep = 16'd0;
        axis_tvalid = 1'b0;
        axis_tlast = 1'b0;

        repeat (4) @(posedge clk);
        rst_n = 1'b1;

        send_incrementing_beat(8'd0, 16'hffff, 1'b0, 16'h0000);
        send_incrementing_beat(8'd16, 16'h000f, 1'b1, 16'h0000);
        #1;
        if ((byte_count !== 32'd20) || (frame_count !== 32'd1) ||
            (error_count !== 32'd0) ||
            (first_error_offset !== 32'hffff_ffff)) begin
            $display("[TB] ERROR correct frame counters bytes=%0d frames=%0d errors=%0d first=%h",
                     byte_count, frame_count, error_count, first_error_offset);
            $fatal(1);
        end

        // Two bad bytes in one accepted beat must both be counted, while the
        // first-error register captures the lowest bad byte offset only once.
        send_incrementing_beat(8'd0, 16'h000f, 1'b1, 16'h000a);
        #1;
        if ((byte_count !== 32'd24) || (frame_count !== 32'd2) ||
            (error_count !== 32'd2) || (first_error_offset !== 32'd1)) begin
            $display("[TB] ERROR mismatch counters bytes=%0d frames=%0d errors=%0d first=%0d",
                     byte_count, frame_count, error_count, first_error_offset);
            $fatal(1);
        end

        $display("[TB] H2C checker RESULT: PASS");
        $finish;
    end

endmodule
