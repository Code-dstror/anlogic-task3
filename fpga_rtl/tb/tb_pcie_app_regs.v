`timescale 1ns / 1ps

module tb_pcie_app_regs;

    reg clk;
    reg rst_n;
    reg [31:0] awaddr;
    reg [2:0] awprot;
    reg awvalid;
    reg [31:0] wdata;
    reg [3:0] wstrb;
    reg wvalid;
    reg bready;
    reg [31:0] araddr;
    reg [2:0] arprot;
    reg arvalid;
    reg rready;
    integer error_count;
    reg [31:0] read_data;
    reg [1:0] read_resp;
    reg observed_test_trigger;

    wire awready;
    wire wready;
    wire [1:0] bresp;
    wire bvalid;
    wire arready;
    wire [31:0] rdata;
    wire [1:0] rresp;
    wire rvalid;
    wire app_enable;
    wire soft_reset;
    wire [31:0] test_length;
    wire [1:0] test_pattern;
    wire test_trigger;

    pcie_app_regs u_dut (
        .i_clk(clk), .i_rst_n(rst_n),
        .i_axil_awaddr(awaddr), .i_axil_awprot(awprot),
        .i_axil_awvalid(awvalid), .o_axil_awready(awready),
        .i_axil_wdata(wdata), .i_axil_wstrb(wstrb),
        .i_axil_wvalid(wvalid), .o_axil_wready(wready),
        .o_axil_bresp(bresp), .o_axil_bvalid(bvalid), .i_axil_bready(bready),
        .i_axil_araddr(araddr), .i_axil_arprot(arprot),
        .i_axil_arvalid(arvalid), .o_axil_arready(arready),
        .o_axil_rdata(rdata), .o_axil_rresp(rresp),
        .o_axil_rvalid(rvalid), .i_axil_rready(rready),
        .i_status(32'h0000_000f), .i_ready_mask(32'h1),
        .i_sending_mask(32'h0), .i_producer_sequence(32'h11),
        .i_consumed_sequence(32'h10), .i_drop_count(32'h2),
        .i_overflow_count(32'h3), .i_dma_error_count(32'h4),
        .i_last_error(32'h5), .i_h2c_byte_count(32'h100),
        .i_h2c_frame_count(32'h6), .i_h2c_error_count(32'h7),
        .i_h2c_first_error(32'h8), .o_app_enable(app_enable),
        .o_soft_reset(soft_reset), .o_test_length(test_length),
        .o_test_pattern(test_pattern), .o_test_trigger(test_trigger)
    );

    task report_error;
        input [8 * 80 - 1:0] message;
        begin
            error_count = error_count + 1;
            $display("[TB] ERROR: %0s at %0t", message, $time);
        end
    endtask

    task axil_write;
        input [31:0] address;
        input [31:0] data_value;
        input [3:0] strobes;
        input integer ordering;
        begin
            awaddr = address;
            wdata = data_value;
            wstrb = strobes;
            if (ordering == 0) begin
                awvalid = 1'b1;
                while (!awready) @(posedge clk);
                @(posedge clk);
                awvalid = 1'b0;
                repeat (2) @(posedge clk);
                wvalid = 1'b1;
                while (!wready) @(posedge clk);
                @(posedge clk);
                wvalid = 1'b0;
            end else if (ordering == 1) begin
                wvalid = 1'b1;
                while (!wready) @(posedge clk);
                @(posedge clk);
                wvalid = 1'b0;
                repeat (2) @(posedge clk);
                awvalid = 1'b1;
                while (!awready) @(posedge clk);
                @(posedge clk);
                awvalid = 1'b0;
            end else begin
                awvalid = 1'b1;
                wvalid = 1'b1;
                while (!awready || !wready) @(posedge clk);
                @(posedge clk);
                awvalid = 1'b0;
                wvalid = 1'b0;
            end
            while (!bvalid) @(posedge clk);
            @(posedge clk);
        end
    endtask

    task axil_read;
        input [31:0] address;
        begin
            araddr = address;
            arvalid = 1'b1;
            while (!arready) @(posedge clk);
            @(posedge clk);
            arvalid = 1'b0;
            while (!rvalid) @(posedge clk);
            read_data = rdata;
            read_resp = rresp;
            @(posedge clk);
        end
    endtask

    initial begin
        clk = 1'b0;
        forever #4 clk = ~clk;
    end

    always @(posedge clk) begin
        if (!rst_n) begin
            observed_test_trigger <= 1'b0;
        end else if (test_trigger) begin
            observed_test_trigger <= 1'b1;
        end
    end

    initial begin
        rst_n = 1'b0;
        awaddr = 32'd0;
        awprot = 3'd0;
        awvalid = 1'b0;
        wdata = 32'd0;
        wstrb = 4'd0;
        wvalid = 1'b0;
        bready = 1'b1;
        araddr = 32'd0;
        arprot = 3'd0;
        arvalid = 1'b0;
        rready = 1'b1;
        error_count = 0;
        read_data = 32'd0;
        read_resp = 2'd0;
        observed_test_trigger = 1'b0;
        repeat (8) @(posedge clk);
        rst_n = 1'b1;
        repeat (2) @(posedge clk);

        axil_read(32'h0008_0000);
        if (read_resp != 2'b00 || read_data != 32'h3343_4641)
            report_error("DEVICE_MAGIC read failed");

        axil_write(32'h0008_0018, 32'h0000_0001, 4'hf, 0);
        if (!app_enable) report_error("AW-first CONTROL write failed");

        axil_write(32'h0008_0040, 32'h1234_5678, 4'hf, 1);
        if (test_length != 32'h1234_5678) report_error("W-first TEST_LENGTH write failed");

        axil_write(32'h0008_0040, 32'h0000_abcd, 4'b0011, 2);
        if (test_length != 32'h1234_abcd) report_error("WSTRB partial write failed");

        axil_read(32'h0018_0000);
        if (read_resp != 2'b10) report_error("high address alias was accepted");

        axil_write(32'h0008_0048, 32'h0000_0001, 4'h1, 2);
        if (!observed_test_trigger) report_error("TEST_TRIGGER pulse missing");

        if (error_count == 0)
            $display("[TB] RESULT: PASS - AXI4-Lite ordering, WSTRB and address decode");
        else
            $display("[TB] RESULT: FAIL - %0d errors", error_count);
        $finish;
    end

endmodule
