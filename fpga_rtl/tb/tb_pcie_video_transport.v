`timescale 1ns / 1ps

module tb_pcie_video_transport;
    reg clk = 1'b0;
    reg pcie_reset_n = 1'b0;
    reg app_enable = 1'b0;
    reg app_reset_n = 1'b0;
    reg [127:0] src_data = 128'd0;
    reg [15:0] src_keep = 16'd0;
    reg src_valid = 1'b0;
    reg src_last = 1'b0;
    wire src_ready;
    wire [127:0] h2c_data;
    wire [15:0] h2c_keep;
    wire [15:0] h2c_user;
    wire h2c_valid;
    reg h2c_ready = 1'b0;
    wire h2c_last;
    wire [31:0] awaddr;
    wire [2:0] awprot;
    wire awvalid;
    reg awready = 1'b0;
    wire [31:0] wdata;
    wire [3:0] wstrb;
    wire wvalid;
    reg wready = 1'b0;
    reg [1:0] bresp = 2'd0;
    reg bvalid = 1'b0;
    wire bready;
    wire [31:0] araddr;
    wire [2:0] arprot;
    wire arvalid;
    reg arready = 1'b0;
    reg [31:0] rdata = 32'd0;
    reg [1:0] rresp = 2'd0;
    reg rvalid = 1'b0;
    wire rready;
    wire user_clk, user_rst_n, link_up, c2h_running;
    wire [7:0] c2h_status, h2c_status;
    wire tx_busy, recovery_required;
    wire [31:0] last_error;
    wire frame_accept, frame_done, frame_abort;
    integer errors = 0;
    integer input_fires = 0;
    integer output_fires = 0;
    integer done_count = 0;
    reg check_expected_output = 1'b1;
    reg [127:0] expected [0:31];
    integer expected_count = 0;

    always #4 clk = ~clk;

    pcie_video_transport dut (
        .i_sys_clk(clk), .i_refclk_p(1'b0), .i_refclk_n(1'b1),
        .i_pcie_mperst(pcie_reset_n), .i_pcie_rxp(1'b0), .i_pcie_rxn(1'b0),
        .o_pcie_txp(), .o_pcie_txn(), .i_app_enable(app_enable),
        .i_app_reset_n(app_reset_n), .i_src_tdata(src_data),
        .i_src_tkeep(src_keep), .i_src_tvalid(src_valid),
        .o_src_tready(src_ready), .i_src_tlast(src_last),
        .o_h2c_tdata(h2c_data), .o_h2c_tkeep(h2c_keep),
        .o_h2c_tuser(h2c_user), .o_h2c_tvalid(h2c_valid),
        .i_h2c_tready(h2c_ready), .o_h2c_tlast(h2c_last),
        .o_axil_awaddr(awaddr), .o_axil_awprot(awprot),
        .o_axil_awvalid(awvalid), .i_axil_awready(awready),
        .o_axil_wdata(wdata), .o_axil_wstrb(wstrb),
        .o_axil_wvalid(wvalid), .i_axil_wready(wready),
        .i_axil_bresp(bresp), .i_axil_bvalid(bvalid), .o_axil_bready(bready),
        .o_axil_araddr(araddr), .o_axil_arprot(arprot),
        .o_axil_arvalid(arvalid), .i_axil_arready(arready),
        .i_axil_rdata(rdata), .i_axil_rresp(rresp),
        .i_axil_rvalid(rvalid), .o_axil_rready(rready),
        .o_user_clk(user_clk), .o_user_rst_n(user_rst_n),
        .o_user_link_up(link_up), .o_c2h_status(c2h_status),
        .o_h2c_status(h2c_status), .o_c2h_running(c2h_running),
        .o_tx_busy(tx_busy), .o_recovery_required(recovery_required),
        .o_last_error(last_error), .o_frame_accept(frame_accept),
        .o_frame_done(frame_done), .o_frame_abort(frame_abort)
    );

    always @(posedge clk) begin
        if (src_valid && src_ready) input_fires <= input_fires + 1;
        if (dut.c2h_tvalid && dut.c2h_tready && check_expected_output) begin
            if (output_fires >= expected_count) begin
                $display("[TB] ERROR unexpected C2H beat %0d", output_fires);
                errors <= errors + 1;
            end else if (dut.c2h_tdata !== expected[output_fires]) begin
                $display("[TB] ERROR C2H data mismatch beat %0d", output_fires);
                errors <= errors + 1;
            end
            output_fires <= output_fires + 1;
        end
        if (frame_done) done_count <= done_count + 1;
    end

    task check;
        input condition;
        input [8*80-1:0] message;
        begin
            if (!condition) begin
                $display("[TB] ERROR %0s", message);
                errors = errors + 1;
            end
        end
    endtask

    task send_beat;
        input [127:0] data_value;
        input [15:0] keep_value;
        input last_value;
        begin
            @(negedge clk);
            src_data = data_value; src_keep = keep_value;
            src_last = last_value; src_valid = 1'b1;
            while (!src_ready) @(negedge clk);
            @(negedge clk);
            src_valid = 1'b0; src_last = 1'b0;
        end
    endtask

    task send_header;
        input [31:0] sequence;
        input [31:0] length;
        reg [127:0] beat0, beat1, beat2;
        begin
            beat0 = {length, sequence, 16'd64, `PCIE_PROTOCOL_VERSION, `PCIE_FRAME_MAGIC};
            beat1 = {64'h0123456789abcdef, 8'h01, 8'h4b, 8'h01, 8'h01, 16'd480, 16'd640};
            beat2 = {32'h89abcdef, 16'd0, 16'h0002, 32'h12345678, 32'h87654321};
            send_beat(beat0, 16'hffff, 1'b0);
            send_beat(beat1, 16'hffff, 1'b0);
            send_beat(beat2, 16'hffff, 1'b0);
            send_beat(128'd0, 16'hffff, 1'b0);
        end
    endtask

    task add_expected_record;
        input [31:0] sequence;
        input [127:0] payload;
        begin
            expected[expected_count] = {32'd16, sequence, 16'd64,
                                        `PCIE_PROTOCOL_VERSION, `PCIE_FRAME_MAGIC};
            expected[expected_count+1] = {64'h0123456789abcdef, 8'h01, 8'h4b, 8'h01, 8'h01, 16'd480, 16'd640};
            expected[expected_count+2] = {32'h89abcdef, 16'd0, 16'h0002, 32'h12345678, 32'h87654321};
            expected[expected_count+3] = 128'd0;
            expected[expected_count+4] = payload;
            expected_count = expected_count + 5;
        end
    endtask

    task reset_application;
        begin
            @(negedge clk); app_reset_n = 1'b0;
            repeat (2) @(negedge clk);
            app_reset_n = 1'b1;
            repeat (2) @(negedge clk);
        end
    endtask

    initial begin
        repeat (3) @(negedge clk);
        pcie_reset_n = 1'b1; app_reset_n = 1'b1; app_enable = 1'b1;
        dut.u_pcie_sgdma_endpoint.link_up = 1'b1;
        dut.u_pcie_sgdma_endpoint.c2h_running = 1'b1;
        dut.u_pcie_sgdma_endpoint.c2h_ready = 1'b1;
        repeat (3) @(negedge clk);

        // Exact AXI4-Lite channel passthrough, including independent stalls.
        dut.u_pcie_sgdma_endpoint.axil_awaddr = 32'h0008_0124;
        dut.u_pcie_sgdma_endpoint.axil_awprot = 3'b101;
        dut.u_pcie_sgdma_endpoint.axil_awvalid = 1'b1;
        dut.u_pcie_sgdma_endpoint.axil_wdata = 32'ha5c3_5a3c;
        dut.u_pcie_sgdma_endpoint.axil_wstrb = 4'b0101;
        dut.u_pcie_sgdma_endpoint.axil_wvalid = 1'b0;
        #1 check(awaddr === 32'h0008_0124 && awprot === 3'b101 && awvalid && !wvalid,
                 "AXIL AW independent passthrough");
        awready = 1'b0; #1 check(!dut.u_pcie_sgdma_endpoint.i_axil_awready, "AXIL AW stall return");
        awready = 1'b1; dut.u_pcie_sgdma_endpoint.axil_awvalid = 1'b0;
        dut.u_pcie_sgdma_endpoint.axil_wvalid = 1'b1;
        #1 check(wdata === 32'ha5c3_5a3c && wstrb === 4'b0101 && wvalid,
                 "AXIL W data/WSTRB passthrough");
        wready = 1'b0; #1 check(!dut.u_pcie_sgdma_endpoint.i_axil_wready, "AXIL W stall return");
        wready = 1'b1;
        bresp = 2'b10; bvalid = 1'b1; dut.u_pcie_sgdma_endpoint.axil_bready = 1'b0;
        #1 check(dut.u_pcie_sgdma_endpoint.i_axil_bresp === 2'b10 &&
                 dut.u_pcie_sgdma_endpoint.i_axil_bvalid && !bready, "AXIL B passthrough/stall");
        dut.u_pcie_sgdma_endpoint.axil_bready = 1'b1;
        dut.u_pcie_sgdma_endpoint.axil_araddr = 32'h0008_0ffc;
        dut.u_pcie_sgdma_endpoint.axil_arprot = 3'b011;
        dut.u_pcie_sgdma_endpoint.axil_arvalid = 1'b1; arready = 1'b0;
        #1 check(araddr === 32'h0008_0ffc && arprot === 3'b011 && arvalid &&
                 !dut.u_pcie_sgdma_endpoint.i_axil_arready, "AXIL AR passthrough/stall");
        arready = 1'b1; rdata = 32'hdead_beef; rresp = 2'b01; rvalid = 1'b1;
        dut.u_pcie_sgdma_endpoint.axil_rready = 1'b0;
        #1 check(dut.u_pcie_sgdma_endpoint.i_axil_rdata === 32'hdead_beef &&
                 dut.u_pcie_sgdma_endpoint.i_axil_rresp === 2'b01 &&
                 dut.u_pcie_sgdma_endpoint.i_axil_rvalid && !rready, "AXIL R passthrough/stall");
        dut.u_pcie_sgdma_endpoint.axil_rready = 1'b1;

        // H2C exact passthrough and returned ready.
        dut.u_pcie_sgdma_endpoint.h2c_data = 128'hfedcba98765432100123456789abcdef;
        dut.u_pcie_sgdma_endpoint.h2c_keep = 16'h55aa;
        dut.u_pcie_sgdma_endpoint.h2c_user = 16'ha55a;
        dut.u_pcie_sgdma_endpoint.h2c_valid = 1'b1;
        dut.u_pcie_sgdma_endpoint.h2c_last = 1'b1; h2c_ready = 1'b0;
        #1 check(h2c_data === 128'hfedcba98765432100123456789abcdef &&
                 h2c_keep === 16'h55aa && h2c_user === 16'ha55a && h2c_valid &&
                 h2c_last && !dut.u_pcie_sgdma_endpoint.i_h2c_tready, "H2C passthrough/stall");
        h2c_ready = 1'b1; #1 check(dut.u_pcie_sgdma_endpoint.i_h2c_tready, "H2C ready return");
        dut.u_pcie_sgdma_endpoint.h2c_valid = 1'b0;

        // Normal and immediate consecutive records preserve all header bytes.
        $display("[TB] normal records");
        add_expected_record(32'd1, 128'h11112222333344445555666677778888);
        send_header(32'd1, 32'd16);
        send_beat(128'h11112222333344445555666677778888, 16'hffff, 1'b1);
        add_expected_record(32'd2, 128'haaaabbbbccccddddeeeeffff00001234);
        send_header(32'd2, 32'd16);
        send_beat(128'haaaabbbbccccddddeeeeffff00001234, 16'hffff, 1'b1);
        repeat (12) @(negedge clk);
        check(done_count == 2, "rapid records complete exactly twice");
        check(output_fires == expected_count, "all expected record beats emitted");
        check_expected_output = 1'b0;

        // Partial header is intentionally paused and preserved across app disable.
        $display("[TB] partial-header pause");
        send_beat({32'd16,32'd3,16'd64,`PCIE_PROTOCOL_VERSION,
                   `PCIE_FRAME_MAGIC},16'hffff,1'b0);
        @(negedge clk); app_enable = 1'b0; src_valid = 1'b1; src_data = 128'h55;
        repeat (3) @(negedge clk);
        check(!src_ready, "partial-header pause holds ready low");
        src_valid = 1'b0; app_enable = 1'b1;
        send_beat({64'h0123456789abcdef,8'h01,8'h4b,8'h01,8'h01,16'd480,16'd640},16'hffff,1'b0);
        send_beat({32'h89abcdef,16'd0,16'h0002,32'h12345678,32'h87654321},16'hffff,1'b0);
        send_beat(128'd0,16'hffff,1'b0);
        send_beat(128'h3333,16'hffff,1'b1);
        repeat (10) @(negedge clk);
        check(!recovery_required, "premetadata app pause is nonfatal");

        // Payload protocol error becomes sticky recovery and blocks handshakes.
        $display("[TB] payload protocol fault");
        send_header(32'd4, 32'd16);
        send_beat(128'h4444, 16'h00ff, 1'b1);
        // Present the next header immediately, with no idle cycle after bad TLAST.
        src_data = {32'd16, 32'd41, 16'd64,
                    `PCIE_PROTOCOL_VERSION, `PCIE_FRAME_MAGIC};
        src_valid = 1'b1; src_keep = 16'hffff; src_last = 1'b0;
        begin : abort_admission
            reg [2:0] state_snapshot;
            reg [1:0] index_snapshot;
            reg [127:0] header_zero_snapshot;
            state_snapshot = dut.u_pcie_inband_header_adapter.state_current;
            index_snapshot = dut.u_pcie_inband_header_adapter.header_index;
            header_zero_snapshot = dut.u_pcie_inband_header_adapter.header_zero;
            #1;
            check(frame_abort && !src_ready,
                  "frame_abort pulse closes admission before recovery register");
            @(negedge clk);
            check(dut.u_pcie_inband_header_adapter.state_current === state_snapshot &&
                  dut.u_pcie_inband_header_adapter.header_index === index_snapshot &&
                  dut.u_pcie_inband_header_adapter.header_zero === header_zero_snapshot,
                  "immediate next header is not consumed on abort edge");
        end
        repeat (2) @(negedge clk);
        check(recovery_required, "payload error enters sticky recovery");
        src_last = 1'b1;
        begin : no_phantom
            integer fire_snapshot;
            reg [2:0] state_snapshot;
            reg [1:0] index_snapshot;
            reg [127:0] header_zero_snapshot;
            reg [127:0] header_one_snapshot;
            reg [127:0] header_two_snapshot;
            fire_snapshot = input_fires;
            state_snapshot = dut.u_pcie_inband_header_adapter.state_current;
            index_snapshot = dut.u_pcie_inband_header_adapter.header_index;
            header_zero_snapshot = dut.u_pcie_inband_header_adapter.header_zero;
            header_one_snapshot = dut.u_pcie_inband_header_adapter.header_one;
            header_two_snapshot = dut.u_pcie_inband_header_adapter.header_two;
            repeat (4) @(negedge clk);
            check(!src_ready && input_fires == fire_snapshot &&
                  dut.u_pcie_inband_header_adapter.state_current === state_snapshot &&
                  dut.u_pcie_inband_header_adapter.header_index === index_snapshot &&
                  dut.u_pcie_inband_header_adapter.header_zero === header_zero_snapshot &&
                  dut.u_pcie_inband_header_adapter.header_one === header_one_snapshot &&
                  dut.u_pcie_inband_header_adapter.header_two === header_two_snapshot,
                  "no external or internal phantom handshake in recovery");
        end
        src_valid = 1'b0;
        reset_application();
        check(!recovery_required && src_ready, "application reset clears recovery");

        // Disabling when completion is observed must not retroactively abort it.
        send_header(32'd40, 32'd16);
        send_beat(128'h4040, 16'hffff, 1'b1);
        wait (frame_done === 1'b1);
        app_enable = 1'b0;
        repeat (3) @(negedge clk);
        check(!recovery_required, "disable on observed frame_done is not false recovery");
        app_enable = 1'b1;

        // Fault while transmitter is emitting its header.
        $display("[TB] link fault");
        send_header(32'd5, 32'd16);
        repeat (2) @(negedge clk);
        dut.u_pcie_sgdma_endpoint.link_up = 1'b0;
        repeat (3) @(negedge clk);
        check(recovery_required, "link loss after metadata acceptance is fatal");
        dut.u_pcie_sgdma_endpoint.link_up = 1'b1; reset_application();

        // Final payload held by SGDMA backpressure, then C2H/app faults.
        $display("[TB] final-stall faults");
        send_header(32'd6, 32'd16);
        repeat (6) @(negedge clk);
        dut.u_pcie_sgdma_endpoint.c2h_ready = 1'b0;
        send_beat(128'h6666, 16'hffff, 1'b1);
        repeat (2) @(negedge clk);
        dut.u_pcie_sgdma_endpoint.c2h_running = 1'b0;
        repeat (3) @(negedge clk);
        check(recovery_required, "C2H stop during final stall is fatal");
        dut.u_pcie_sgdma_endpoint.c2h_running = 1'b1; reset_application();
        dut.u_pcie_sgdma_endpoint.c2h_ready = 1'b1;

        // A fault presented on the actual stalled final-beat handshake aborts.
        send_header(32'd60, 32'd16);
        repeat (6) @(negedge clk);
        dut.u_pcie_sgdma_endpoint.c2h_ready = 1'b0;
        send_beat(128'h6060, 16'hffff, 1'b1);
        repeat (2) @(negedge clk);
        @(negedge clk);
        dut.u_pcie_sgdma_endpoint.c2h_ready = 1'b1;
        app_enable = 1'b0;
        repeat (3) @(negedge clk);
        check(recovery_required && !frame_done,
              "same-cycle final handshake and disable follows abort priority");
        app_enable = 1'b1; reset_application();

        send_header(32'd7, 32'd16);
        repeat (2) @(negedge clk); app_enable = 1'b0;
        repeat (3) @(negedge clk);
        check(recovery_required, "app disable after metadata acceptance is fatal");
        app_enable = 1'b1; reset_application();

        if (errors == 0) $display("[TB] RESULT: PASS");
        else $display("[TB] RESULT: FAIL errors=%0d", errors);
        $finish;
    end

    initial begin
        #200000;
        $display("[TB] ERROR timeout");
        $display("[TB] RESULT: FAIL errors=%0d", errors + 1);
        $finish;
    end
endmodule
