`timescale 1ns/1ps

// Transaction-boundary test for the encrypted vendor SGDMA core.  This does
// not model PCIe LTSSM/configuration space or a Root-Complex driver.
module tb_sgdma_transactions;
    localparam [31:0] CONFIG_IDENTIFIER = 32'h0000_3000;
    localparam [31:0] C2H_CONTROL        = 32'h0000_1004;
    localparam [31:0] C2H_FIRST_DESC_LO  = 32'h0000_5080;
    localparam [31:0] DESC_BUS_ADDRESS   = 32'h0010_0000;

    reg          core_clk;
    reg          core_rstn;
    reg  [127:0] cq_tdata;
    reg  [3:0]   cq_tkeep;
    reg  [87:0]  cq_tuser;
    reg          cq_tvalid;
    reg          cq_tlast;
    wire         cq_tready;
    wire [127:0] cc_tdata;
    wire [3:0]   cc_tkeep;
    wire         cc_tvalid;
    wire         cc_tlast;
    wire [127:0] rq_tdata;
    wire [3:0]   rq_tkeep;
    wire         rq_tvalid;
    wire         rq_tlast;
    wire         c2h_tready;
    reg          c2h_tvalid;
    reg  [127:0] rc_tdata;
    reg  [3:0]   rc_tkeep;
    reg  [74:0]  rc_tuser;
    reg          rc_tvalid;
    reg          rc_tlast;
    wire         rc_tready;
    integer      errors;
    integer      rq_count;
    integer      cc_count;
    integer      c2h_write_count;
    reg          expect_c2h_payload;
    reg          c2h_payload_seen;
    reg          writeback_seen;
    reg          expect_writeback_payload;
    reg [31:0]   config_identifier_value;
    reg [7:0]    descriptor_tag;
    reg [15:0]   descriptor_requester;
    reg          descriptor_seen;

    always #4 core_clk = ~core_clk;

    task cq_header;
        input [31:0] address;
        input [3:0] request_type;
        begin
            cq_tdata = 128'd0;
            cq_tdata[31:0]   = {address[31:2], 2'b00};
            cq_tdata[63:32]  = 32'd0;
            cq_tdata[95:64]  = {16'h0100, 1'b0, request_type, 11'd1};
            // Tag 0x5a, function 0, BAR1, aperture 64 KiB.
            cq_tdata[127:96] = {1'b0, 3'd0, 3'd0, 6'd16, 3'd1, 8'd0, 8'h5a};
            cq_tkeep = 4'hf;
            cq_tuser = 88'd0;
            cq_tuser[3:0] = 4'hf;
            cq_tuser[40] = 1'b1;
        end
    endtask

    task send_cq_read;
        input [31:0] address;
        begin
            @(negedge core_clk);
            cq_header(address, 4'b0000);
            cq_tlast = 1'b1;
            cq_tvalid = 1'b1;
            while (!cq_tready) @(negedge core_clk);
            @(negedge core_clk);
            cq_tvalid = 1'b0;
            cq_tlast = 1'b0;
        end
    endtask

    task send_cq_write;
        input [31:0] address;
        input [31:0] data;
        begin
            @(negedge core_clk);
            cq_header(address, 4'b0001);
            cq_tlast = 1'b0;
            cq_tvalid = 1'b1;
            while (!cq_tready) @(negedge core_clk);
            @(negedge core_clk);
            cq_tdata = {96'd0, data};
            cq_tkeep = 4'b0001;
            cq_tuser = 88'd0;
            cq_tlast = 1'b1;
            while (!cq_tready) @(negedge core_clk);
            @(negedge core_clk);
            cq_tvalid = 1'b0;
            cq_tlast = 1'b0;
        end
    endtask

    task send_descriptor_completion;
        input [15:0] requester;
        input [7:0] tag;
        reg [95:0] header;
        begin
            // RC header is the exact 96-bit format emitted by the vendor
            // pcie_rx_bypass2rc bridge: completed, 32 byte count, 8 DW,
            // requester 01:00.0, completer 00:00.0 and the captured RQ tag.
            header[31:0]  = {1'b0, 1'b1, 1'b0, 13'd32, 4'd0, 12'd0};
            header[63:32] = {requester, 1'b0, 1'b0, 3'd0, 11'd8};
            header[95:64] = {1'b0, 3'd0, 3'd0, 1'b0, 16'd0, tag};
            @(negedge core_clk);
            rc_tdata = {32'had4b0013, header};
            rc_tkeep = 4'hf;
            rc_tuser = 75'd0;
            rc_tuser[42] = 1'b1;
            rc_tuser[58:43] = 16'hffff;
            rc_tvalid = 1'b1;
            rc_tlast = 1'b0;
            @(posedge core_clk);
            if (!rc_tready) begin $display("ERROR: RC header beat not accepted"); errors = errors + 1; end
            @(negedge core_clk);
            // bytes, source address, and destination low word.
            rc_tdata = {32'h0020_0000, 32'd0, 32'h0030_0000, 32'd16};
            // The public PH1A bridge holds SOF/byte-enable tuser throughout
            // DATA state rather than clearing it after the first beat.
            @(posedge core_clk);
            if (!rc_tready) begin $display("ERROR: RC middle beat not accepted"); errors = errors + 1; end
            @(negedge core_clk);
            // destination high word and null next descriptor pointer.
            rc_tdata = {32'd0, 32'd0, 32'd0, 32'd0};
            rc_tkeep = 4'b0111;
            rc_tlast = 1'b1;
            @(posedge core_clk);
            if (!rc_tready) begin $display("ERROR: RC final beat not accepted"); errors = errors + 1; end
            @(negedge core_clk);
            rc_tvalid = 1'b0;
            rc_tlast = 1'b0;
        end
    endtask

    always @(posedge core_clk) begin
        if (rq_tvalid) begin
            rq_count = rq_count + 1;
            $display("RQ beat %0d data=%032h keep=%h last=%b", rq_count,
                     rq_tdata, rq_tkeep, rq_tlast);
            $display("RQ decode addr=%08h type=%h requester=%04h tag=%02h count=%0d",
                     {rq_tdata[31:2], 2'b00}, rq_tdata[78:75],
                     rq_tdata[119:104], rq_tdata[103:96], rq_tdata[74:64]);
            if ((rq_tdata[78:75] == 4'b0000) &&
                (rq_tdata[31:2] == DESC_BUS_ADDRESS[31:2]))
                begin
                    if ((rq_tdata[63:32] != 32'd0) || (rq_tdata[74:64] != 11'd8) ||
                        (rq_tkeep != 4'hf) || !rq_tlast) begin
                        $display("ERROR: descriptor-fetch RQ header mismatch");
                        errors = errors + 1;
                    end
                    descriptor_seen = 1'b1;
                    descriptor_requester = rq_tdata[119:104];
                    descriptor_tag = rq_tdata[103:96];
                end
            if (expect_writeback_payload) begin
                if ((rq_tdata[63:0] == 64'h00000010_52b40001) &&
                    (rq_tkeep == 4'b0011) && rq_tlast)
                    writeback_seen = 1'b1;
                else begin $display("ERROR: C2H result writeback mismatch"); errors = errors + 1; end
                expect_writeback_payload = 1'b0;
            end else if (expect_c2h_payload) begin
                if ((rq_tdata == 128'h00112233445566778899aabbccddeeff) &&
                    (rq_tkeep == 4'hf) && rq_tlast)
                    c2h_payload_seen = 1'b1;
                else begin $display("ERROR: C2H payload mismatch"); errors = errors + 1; end
                expect_c2h_payload = 1'b0;
            end else if ((rq_tdata[78:75] == 4'b0001) &&
                         (rq_tdata[31:2] == 30'h0008_0000)) begin
                if ((rq_tdata[63:32] != 32'd0) || (rq_tdata[74:64] != 11'd4) ||
                    (rq_tkeep != 4'hf) || rq_tlast) begin
                    $display("ERROR: C2H Memory Write RQ header mismatch");
                    errors = errors + 1;
                end
                c2h_write_count = c2h_write_count + 1;
                expect_c2h_payload = 1'b1;
            end else if ((rq_tdata[78:75] == 4'b0001) &&
                         (rq_tdata[31:2] == 30'h000c_0000)) begin
                if ((rq_tdata[63:32] != 32'd0) || (rq_tdata[74:64] != 11'd2) ||
                    (rq_tkeep != 4'hf) || rq_tlast) begin
                    $display("ERROR: result Memory Write RQ header mismatch");
                    errors = errors + 1;
                end
                expect_writeback_payload = 1'b1;
            end else if (!((rq_tdata[78:75] == 4'b0000) &&
                           (rq_tdata[31:2] == DESC_BUS_ADDRESS[31:2]))) begin
                $display("ERROR: unexpected RQ transaction");
                errors = errors + 1;
            end
        end
        if (cc_tvalid) begin
            cc_count = cc_count + 1;
            config_identifier_value = cc_tdata[127:96];
            if ((cc_tkeep != 4'hf) || !cc_tlast || (cc_tdata[71:64] != 8'h5a)) begin
                $display("ERROR: config CC framing/tag mismatch");
                errors = errors + 1;
            end
            $display("CC data=%032h keep=%h last=%b", cc_tdata, cc_tkeep, cc_tlast);
        end
    end

    initial begin
        core_clk = 1'b0;
        core_rstn = 1'b0;
        cq_tdata = 128'd0;
        cq_tkeep = 4'd0;
        cq_tuser = 88'd0;
        cq_tvalid = 1'b0;
        cq_tlast = 1'b0;
        errors = 0;
        rq_count = 0;
        cc_count = 0;
        c2h_write_count = 0;
        expect_c2h_payload = 1'b0;
        c2h_payload_seen = 1'b0;
        writeback_seen = 1'b0;
        expect_writeback_payload = 1'b0;
        config_identifier_value = 32'd0;
        descriptor_tag = 8'd0;
        descriptor_requester = 16'd0;
        descriptor_seen = 1'b0;
        rc_tdata = 128'd0;
        rc_tkeep = 4'd0;
        rc_tuser = 75'd0;
        rc_tvalid = 1'b0;
        rc_tlast = 1'b0;
        c2h_tvalid = 1'b0;
        repeat (20) @(posedge core_clk);
        core_rstn = 1'b1;
        repeat (20) @(posedge core_clk);

        send_cq_read(CONFIG_IDENTIFIER);
        repeat (80) @(posedge core_clk);
        if (cc_count == 0) begin
            $display("ERROR: no CC response after config BAR read");
            errors = errors + 1;
        end
        if (config_identifier_value != 32'h1fc3_0001) begin
            $display("ERROR: config identifier mismatch: %08h", config_identifier_value);
            errors = errors + 1;
        end

        // Official driver layout: C2H0 SGDMA registers begin at channel+0x4000;
        // first_desc_lo is +0x80 and control RUN_STOP is channel+0x04.
        send_cq_write(C2H_FIRST_DESC_LO, DESC_BUS_ADDRESS);
        send_cq_write(C2H_FIRST_DESC_LO + 4, 32'd0);
        send_cq_write(C2H_FIRST_DESC_LO + 8, 32'd0);
        send_cq_write(C2H_CONTROL, 32'd1);
        wait (descriptor_seen);
        $display("RC preflight ready=%b requester=%04h tag=%02h",
                 rc_tready, descriptor_requester, descriptor_tag);
        send_descriptor_completion(descriptor_requester, descriptor_tag);
        wait (c2h_tready);
        @(negedge core_clk);
        c2h_tvalid = 1'b1;
        @(posedge core_clk);
        while (!c2h_tready) @(posedge core_clk);
        @(negedge core_clk);
        c2h_tvalid = 1'b0;
        repeat (500) @(posedge core_clk);

        if (rq_count == 0) begin
            $display("ERROR: SGDMA did not issue an RQ descriptor fetch");
            errors = errors + 1;
        end
        if (c2h_write_count == 0) begin
            $display("ERROR: descriptor completion did not lead to C2H Memory Write RQ");
            errors = errors + 1;
        end
        if (!c2h_payload_seen) begin
            $display("ERROR: exact 16-byte C2H payload was not observed");
            errors = errors + 1;
        end
        if (!writeback_seen) begin
            $display("ERROR: descriptor writeback to 0x00300000 was not observed");
            errors = errors + 1;
        end
        if (errors == 0)
            $display("PASS: encrypted SGDMA CQ/CC, descriptor fetch, C2H payload and writeback");
        else
            $display("FAIL: %0d errors", errors);
        $finish;
    end

    sgdma_ip #(
        .DEVICE_FAMILY("PH1A"), .DATA_WIDTH(128),
        .AXI4MM_BUS_EN(0), .AXI4ST_BUS_EN(1),
        .AXI4L_MBUS_EN(1), .AXI4L_SBUS_EN(0),
        .H2C_CHNL_NUM(1), .C2H_CHNL_NUM(1),
        .H2C_DSC_BYP_MAP(1'b0), .C2H_DSC_BYP_MAP(1'b0),
        .DMA_BAR(1), .AXI4LITE_BAR(0)
    ) dut (
        .core_clk(core_clk), .core_rstn(core_rstn),
        .tl_cfg_busdev_i(13'h100), .tl_cfg_max_payload_size_i(3'd0),
        .tl_cfg_max_read_request_size_i(3'd0),
        .cfg_interrupt_sent(1'b0), .cfg_interrupt_msi_enable(4'd0),
        .cfg_interrupt_msi_mmenable(12'd0), .cfg_interrupt_msi_mask_update(1'b0),
        .cfg_interrupt_msi_data(32'd0), .cfg_interrupt_msi_sent(1'b0),
        .cfg_interrupt_msi_fail(1'b0), .tl_cfg_msix_enable_i(4'd0),
        .tl_cfg_msix_function_mask_i(4'd0), .usr_irq_req_i(1'b0),
        .cfg_mgmt_addr_i(19'd0), .cfg_mgmt_write_i(1'b0),
        .cfg_mgmt_write_data_i(32'd0), .cfg_mgmt_byte_enable_i(4'd0),
        .cfg_mgmt_read_i(1'b0), .cfg_mgmt_type1_cfg_reg_access_i(1'b0),
        .cfg_mgmt_read_data_i(32'd0), .cfg_mgmt_read_write_done_i(1'b0),
        .m_axis_cq_tdata_i(cq_tdata), .m_axis_cq_tkeep_i(cq_tkeep),
        .m_axis_cq_tuser_i(cq_tuser), .m_axis_cq_tvalid_i(cq_tvalid),
        .m_axis_cq_tlast_i(cq_tlast), .m_axis_cq_tready_o(cq_tready),
        .m_axis_cc_tdata_o(cc_tdata), .m_axis_cc_tkeep_o(cc_tkeep),
        .m_axis_cc_tvalid_o(cc_tvalid), .m_axis_cc_tlast_o(cc_tlast),
        .m_axis_cc_tready_i(1'b1), .m_axis_rq_tdata_o(rq_tdata),
        .m_axis_rq_tkeep_o(rq_tkeep), .m_axis_rq_tvalid_o(rq_tvalid),
        .m_axis_rq_tlast_o(rq_tlast), .m_axis_rq_tready_i(1'b1),
        .tuser2rq_i(5'd0), .m_axis_rc_tdata_i(rc_tdata),
        .m_axis_rc_tkeep_i(rc_tkeep), .m_axis_rc_tuser_i(rc_tuser),
        .m_axis_rc_tvalid_i(rc_tvalid), .m_axis_rc_tlast_i(rc_tlast),
        .m_axis_rc_tready_o(rc_tready),
        .m_axil_awready_i(1'b1), .m_axil_wready_i(1'b1),
        .m_axil_bvalid_i(1'b0), .m_axil_bresp_i(2'd0),
        .m_axil_arready_i(1'b1), .m_axil_rdata_i(32'd0),
        .m_axil_rresp_i(2'd0), .m_axil_rvalid_i(1'b0),
        .s_axil_awaddr_i(32'd0), .s_axil_awprot_i(3'd0), .s_axil_awvalid_i(1'b0),
        .s_axil_wdata_i(32'd0), .s_axil_wstrb_i(4'd0), .s_axil_wvalid_i(1'b0),
        .s_axil_bready_i(1'b0), .s_axil_araddr_i(32'd0), .s_axil_arprot_i(3'd0),
        .s_axil_arvalid_i(1'b0), .s_axil_rready_i(1'b0),
        .m_axib_arready_i(1'b0), .m_axib_rid_i(4'd0), .m_axib_rdata_i(128'd0),
        .m_axib_rresp_i(2'd0), .m_axib_rlast_i(1'b0), .m_axib_rvalid_i(1'b0),
        .m_axib_awready_i(1'b0), .m_axib_wready_i(1'b0), .m_axib_bid_i(4'd0),
        .m_axib_bresp_i(2'd0), .m_axib_bvalid_i(1'b0),
        .m_axi_arready_i(1'b0), .m_axi_rid_i(4'd0), .m_axi_rdata_i(128'd0),
        .m_axi_ruser_i(16'd0), .m_axi_rresp_i(2'd0), .m_axi_rlast_i(1'b0),
        .m_axi_rvalid_i(1'b0), .m_axi_awready_i(1'b0), .m_axi_wready_i(1'b0),
        .m_axi_bid_i(4'd0), .m_axi_bresp_i(2'd0), .m_axi_bvalid_i(1'b0),
        .s_axis_tx_tdata_i(128'h00112233445566778899aabbccddeeff),
        .s_axis_tx_tkeep_i(16'hffff), .s_axis_tx_tuser_i(16'd0),
        .s_axis_tx_tlast_i(1'b1), .s_axis_tx_tvalid_i(c2h_tvalid),
        .s_axis_tx_tready_o(c2h_tready),
        .m_axis_rx_tready_i(1'b1),
        .c2h_dsc_byp_load_0_i(1'b0), .c2h_dsc_byp_src_addr_0_i(64'd0),
        .c2h_dsc_byp_dst_addr_0_i(64'd0), .c2h_dsc_byp_len_0_i(28'd0),
        .c2h_dsc_byp_ctl_0_i(16'd0), .h2c_dsc_byp_load_0_i(1'b0),
        .h2c_dsc_byp_src_addr_0_i(64'd0), .h2c_dsc_byp_dst_addr_0_i(64'd0),
        .h2c_dsc_byp_len_0_i(28'd0), .h2c_dsc_byp_ctl_0_i(16'd0)
    );

    initial begin : watchdog
        #100000;
        $display("FAIL: watchdog timeout");
        $finish;
    end
endmodule
