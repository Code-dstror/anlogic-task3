`timescale 1ns / 1ps

// 仅替代物理时钟生成，顶层复位与会话逻辑保持真实 RTL。
module sys_pll_125m_25m (
    input wire refclk, input wire reset, output reg lock = 1'b0,
    output reg clk0_out = 1'b0, output wire clk1_out
);
    integer refs = 0;
    always #4 clk0_out = ~clk0_out;
    assign clk1_out = refclk;
    always @(posedge refclk or posedge reset)
        if (reset) begin refs <= 0; lock <= 0; end
        else if (refs < 8) begin
            refs <= refs + 1;
            if (refs == 7) lock <= 1;
        end
endmodule

module camera_ref_pll_25m (
    input wire refclk, input wire reset, output reg lock = 1'b0,
    output wire clk0_out, output wire clk1_out
);
    integer refs = 0;
    assign clk0_out = refclk;
    assign clk1_out = refclk;
    always @(posedge refclk or posedge reset)
        if (reset) begin refs <= 0; lock <= 0; end
        else if (refs < 8) begin
            refs <= refs + 1;
            if (refs == 7) lock <= 1;
        end
endmodule

module physical_imx415_camera_observe_axis #(
    // 传感器采集模式
    parameter integer MODE_4K = 0,
    parameter integer FRAME_EVENTS_ENABLE = 0,
    parameter integer CONTROLLED_ABORT_ENABLE = 0,
    parameter integer CONTROLLED_REPLAY_ABORT_ENABLE = 0,
    // RGB 输出路径
    parameter integer RGB_TAP = 0,
    // 裁剪起点与 Bayer 相位
    parameter integer FIRST_ROW = MODE_4K ? 36 : 20,
    parameter integer FIRST_GROUP = 1,
    parameter [1:0] BAYER_PHASE = 2'b00,
    parameter integer COLOR_CONFIG_ENABLE = 0,
    parameter integer RAW_REPLAY_ENABLE = 0,
    parameter integer RAW_REPLAY_SAMPLE_BITS = 10,
    parameter integer SHARED_WIDE_ISP_ENABLE = 0,
    parameter integer JOB_CONTROL_ENABLE = 0,
    parameter integer SEPARATE_REPLAY_JOB_CONTROL = 0,
    // 时钟与时序配置
    parameter integer SILENCE_CYCLES = 12500000
) (
    // 时钟与复位
    input wire i_pixel_clk,
    input wire i_sensor_clk,
    input wire i_ref_clk,
    input wire i_reset_n,
    input wire i_processing_reset_n,
    input wire [29:0] i_wb_gains,
    input wire [1:0] i_bayer_phase, // Pixel-domain configuration, stable for session
    input wire [7:0] i_gain_code,   // Sensor-domain configuration, stable for session
    input wire i_job_enable, input wire i_job_pause,
    input wire i_replay_job_enable, input wire i_replay_job_pause,
    output wire o_job_start, output wire o_job_idle, output wire o_job_replay,
    // CSI 与传感器引脚
    input wire mipi_clk_hs_rx_p,
    input wire [3:0] mipi_data_hs_p,
    output wire cam_scl,
    inout wire cam_sda,
    output wire cam_mclk,
    output wire cam_xclr,
    // AXIS 输出流
    output wire [127:0] o_axis_tdata,
    output wire [15:0] o_axis_tkeep,
    output wire o_axis_tvalid,
    input wire i_axis_tready,
    output wire o_axis_tlast,
    output wire m_frame_event_valid,
    input wire m_frame_event_ready,
    output wire [1:0] m_frame_event_kind,
    output wire m_frame_event_ok,
    output wire [3:0] m_frame_event_error,
    output wire [31:0] m_frame_event_sequence,output wire m_frame_event_identity_valid,
    output wire o_source_identity_fault,
    // 配置、帧状态与接收错误
    output wire o_frame_error,
    output wire o_frame_done,
    output wire o_config_done,
    output wire o_config_error,
    output wire [31:0] o_ecc_errors,
    output wire [31:0] o_crc_errors,
    output wire [31:0] o_overflows,
    output wire [31:0] o_format_errors,
    output wire o_delay_ready,
    output reg [7:0] o_delay_debug,
    output reg [5:0] o_delay_window,
    output reg o_delay_status_valid,
    output wire o_phy_ready,
    // RGB 像素流
    output wire [95:0] o_rgb_tdata,
    output wire o_rgb_tvalid,
    input wire i_rgb_tready,
    output wire o_rgb_tuser,
    output wire o_rgb_tlast,
    // S04 crop tap and replay share the original pixel-domain ISP.
    output wire [39:0] o_cropped_raw_data,
    output wire o_cropped_raw_valid, o_cropped_raw_ready,
    output wire o_cropped_raw_sof, o_cropped_raw_eol, o_cropped_raw_abort,
    output wire [31:0] o_cropped_raw_sequence,output wire o_cropped_raw_identity_valid,
    input wire i_replay_active,
    input wire [4*RAW_REPLAY_SAMPLE_BITS-1:0] i_replay_data,
    input wire i_replay_hdr_enable,
    input wire [3:0] i_replay_tone_shift,
    input wire i_replay_valid, i_replay_sof, i_replay_eol, i_replay_abort,
    output wire o_replay_ready, o_replay_safe,
    // Passive pixel-domain receiver taps; never drive functional READY/data.
    output wire o_observe_raw_valid,
    output wire o_observe_raw_ready,
    output wire o_observe_raw_sof,
    output wire o_observe_raw_eol,
    output wire o_observe_raw_abort,
    output wire o_observe_receive_fault
);
    // Test-only sensor/crop boundary. Defaults keep virtual qualification
    // unchanged. The physical bench drives one native4 RAW stream here,
    // through the real crop into both live ISP and configured RAW storage.
    // PHY/calibration boundary only: real word parser, official async FIFO,
    // crop and shared ISP remain in the actual instantiated data path.
    reg word_clk=0;always #5 word_clk=~word_clk;
    reg [31:0] word_data=0;reg word_valid=0,decoder_reset_n=1,phy_up=1;
    wire [39:0] raw_data;wire [31:0] raw_sequence;
    wire raw_valid,raw_sof,raw_eol,raw_abort,raw_identity_valid;
    reg identity_fault_seen=0,receive_fault=0;
    wire pipeline_raw_ready;
    always @(posedge i_pixel_clk or negedge i_reset_n)begin
        if(!i_reset_n)begin identity_fault_seen<=0;receive_fault<=0;end
        else begin
            receive_fault<=o_source_identity_fault&&!identity_fault_seen;
            if(o_source_identity_fault)identity_fault_seen<=1;
        end
    end
    physical_csi_rx_stream #(.FRAME_EVENTS_ENABLE(1)) u_receiver(
        .i_word_clk(word_clk),.i_pixel_clk(i_pixel_clk),.i_reset_n(i_reset_n&&phy_up),
        .i_decoder_reset_n(decoder_reset_n),.i_identity_rst_n(i_reset_n),
        .i_publish_enable(1'b1),.o_fifo_write_ready(),.i_aligned_word(word_data),.i_aligned_valid(word_valid),
        .o_raw_data(raw_data),.o_raw_valid(raw_valid),.i_raw_ready(pipeline_raw_ready&&!receive_fault),
        .o_raw_sof(raw_sof),.o_raw_eol(raw_eol),.o_raw_sequence(raw_sequence),.o_raw_identity_valid(raw_identity_valid),
        .m_frame_event_valid(m_frame_event_valid),.m_frame_event_ready(m_frame_event_ready),
        .m_frame_event_kind(m_frame_event_kind),.m_frame_event_ok(m_frame_event_ok),.m_frame_event_error(m_frame_event_error),
        .m_frame_event_sequence(m_frame_event_sequence),.m_frame_event_identity_valid(m_frame_event_identity_valid),
        .o_identity_diag(),.o_identity_fault(o_source_identity_fault),.o_frame_abort(raw_abort),.o_error_code(),
        .o_header_ecc_error_count(o_ecc_errors),.o_payload_crc_error_count(o_crc_errors),
        .o_overflow_error_count(o_overflows),.o_length_error_count(o_format_errors),.o_wait_for_sync(),.o_packet_done());
    assign cam_scl=1'b1; assign cam_mclk=i_sensor_clk;assign cam_xclr=i_reset_n;
    assign o_config_done=i_reset_n;assign o_config_error=0;

    assign o_delay_ready=i_reset_n;assign o_phy_ready=i_reset_n;
    always @* begin o_delay_debug=0;o_delay_window=0;o_delay_status_valid=i_reset_n;end
`ifndef S08_SIM_WIDTH
`define S08_SIM_WIDTH 20
`endif
`ifndef S08_SIM_HEIGHT
`define S08_SIM_HEIGHT 17
`endif
    physical_camera_rgb_pipeline #(.WIDTH(`S08_SIM_WIDTH),.HEIGHT(`S08_SIM_HEIGHT),.FIRST_ROW(2),
        .RGB_TAP(RGB_TAP),
        .FIRST_GROUP(1),.BAYER_PHASE(BAYER_PHASE),
        .RUNTIME_BAYER_ENABLE(COLOR_CONFIG_ENABLE),
        .RUNTIME_WB_ENABLE(COLOR_CONFIG_ENABLE),
        .RAW_REPLAY_ENABLE(RAW_REPLAY_ENABLE),.RAW_REPLAY_SAMPLE_BITS(RAW_REPLAY_SAMPLE_BITS),.SHARED_WIDE_ISP_ENABLE(SHARED_WIDE_ISP_ENABLE),
        .JOB_CONTROL_ENABLE(JOB_CONTROL_ENABLE),
        .SEPARATE_REPLAY_JOB_CONTROL(SEPARATE_REPLAY_JOB_CONTROL),
        .CONTROLLED_ABORT_ENABLE(CONTROLLED_ABORT_ENABLE),
        .CONTROLLED_REPLAY_ABORT_ENABLE(CONTROLLED_REPLAY_ABORT_ENABLE)) u_pipeline (
        .i_clk(i_pixel_clk),.i_rst_n(i_reset_n),.i_processing_reset_n(i_processing_reset_n),.i_raw_data(raw_data),
        .i_bayer_phase(i_bayer_phase), .i_wb_gains(i_wb_gains),
        .i_job_enable(i_job_enable),.i_job_pause(i_job_pause),
        .i_replay_job_enable(i_replay_job_enable),.i_replay_job_pause(i_replay_job_pause),
        .o_job_start(o_job_start),.o_job_idle(o_job_idle),.o_job_replay(o_job_replay),
        .i_raw_valid(raw_valid || receive_fault),.o_raw_ready(pipeline_raw_ready),
        .i_raw_sof(raw_sof && !receive_fault),
        .i_raw_sequence(raw_sequence),.i_raw_identity_valid(raw_identity_valid&&!receive_fault),
        .i_raw_eol(raw_eol && !receive_fault),.i_raw_abort(raw_abort || receive_fault),
        .o_axis_tdata(o_axis_tdata),.o_axis_tkeep(o_axis_tkeep),
        .o_axis_tvalid(o_axis_tvalid),.i_axis_tready(i_axis_tready),
        .o_axis_tlast(o_axis_tlast),.o_frame_error(o_frame_error),.o_frame_done(o_frame_done),
        .o_rgb_tdata(o_rgb_tdata),.o_rgb_tvalid(o_rgb_tvalid),
        .i_rgb_tready(i_rgb_tready),.o_rgb_tuser(o_rgb_tuser),
        .o_rgb_tlast(o_rgb_tlast),
        .o_cropped_raw_data(o_cropped_raw_data),
        .o_cropped_raw_valid(o_cropped_raw_valid),
        .o_cropped_raw_ready(o_cropped_raw_ready),
        .i_cropped_raw_ready(1'b1),
        .o_cropped_raw_sof(o_cropped_raw_sof),
        .o_cropped_raw_eol(o_cropped_raw_eol),
        .o_cropped_raw_abort(o_cropped_raw_abort),
        .o_cropped_raw_sequence(o_cropped_raw_sequence),.o_cropped_raw_identity_valid(o_cropped_raw_identity_valid),
        .i_replay_active(i_replay_active), .i_replay_data(i_replay_data),
        .i_replay_hdr_enable(i_replay_hdr_enable),.i_replay_tone_shift(i_replay_tone_shift),
        .i_replay_valid(i_replay_valid), .i_replay_sof(i_replay_sof),
        .i_replay_eol(i_replay_eol), .i_replay_abort(i_replay_abort),
        .o_replay_ready(o_replay_ready), .o_replay_safe(o_replay_safe),
        .i_external_rgb_data(96'd0), .i_external_rgb_valid(1'b0),
        .i_external_rgb_sof(1'b0), .i_external_rgb_eol(1'b0),
        .i_external_rgb_abort(1'b0), .o_external_rgb_ready()
    );
    assign o_observe_raw_valid=raw_valid;
    assign o_observe_raw_ready=pipeline_raw_ready;
    assign o_observe_raw_sof=raw_sof;assign o_observe_raw_eol=raw_eol;
    assign o_observe_raw_abort=raw_abort;assign o_observe_receive_fault=receive_fault;
endmodule

// 用字节寻址的 AXI 存储器替代物理 DDR IP。
// 帧槽所有权、写完成屏障及突发生成仍由真实 ddr3_jpeg_store 负责。
module ui_ddr #(
    parameter integer RAW_ARENA_ENABLE = 0,
    parameter integer JPEG_RING_ARENA_ENABLE = 0,
    parameter integer NR_ARENA_ENABLE = 0
) (
    input wire sys_rst_n, sys_clk,
    output wire [0:0] ddr_ck_p, ddr_ck_n, output wire ddr_reset_n,
    output wire [0:0] ddr_cke, ddr_odt, ddr_cs_n,
    output wire ddr_ras_n, ddr_cas_n, ddr_we_n,
    output wire [2:0] ddr_ba, output wire [13:0] ddr_addr,
    inout wire [1:0] ddr_dqs_p, ddr_dqs_n,
    inout wire [15:0] ddr_dq, inout wire [1:0] ddr_dm,
    output wire ctl_ram_rst_n, ctl_ram_cke,
    output reg dfi_clk=1'b0, output reg pll_locked = 1'b0,
    output wire ddrphy_rst_n, output reg ddr_init_cal_done = 1'b0,
    output wire [7:0] ddr_init_cal_err, ddr_init_cal_step,
    input wire axi_aclk, axi_aresetn,
    input wire [3:0] axi_awid, input wire [27:0] axi_awaddr,
    input wire [7:0] axi_awlen, input wire [2:0] axi_awsize,
    input wire [1:0] axi_awburst, input wire axi_awlock,
    input wire [3:0] axi_awcache, input wire [2:0] axi_awprot,
    input wire [3:0] axi_awqos, input wire axi_awvalid,
    output wire axi_awready,
    input wire [127:0] axi_wdata, input wire [15:0] axi_wstrb,
    input wire axi_wlast, axi_wvalid, output wire axi_wready,
    output reg [3:0] axi_bid, output wire [1:0] axi_bresp,
    output reg axi_bvalid, input wire axi_bready,
    input wire [3:0] axi_arid, input wire [27:0] axi_araddr,
    input wire [7:0] axi_arlen, input wire [2:0] axi_arsize,
    input wire [1:0] axi_arburst, input wire axi_arlock,
    input wire [3:0] axi_arcache, input wire [2:0] axi_arprot,
    input wire [3:0] axi_arqos, input wire axi_arvalid,
    output wire axi_arready,
    output reg [3:0] axi_rid, output reg [127:0] axi_rdata,
    output wire [1:0] axi_rresp, output reg axi_rlast,
    output reg axi_rvalid, input wire axi_rready,
    input wire pzq_cal_done_i, output wire pzq_cal_done_o,
    output wire user_clk, apb_clk, mcu_busy,
    input wire user_update, input wire [7:0] user_ram_addr,
    input wire user_ram_wr_en, user_ram_rd_en,
    input wire [31:0] user_ram_wr_data,
    output wire [31:0] user_ram_rd_data,
    input wire uart_rxd, output wire uart_txd
);
    localparam integer WINDOW_BYTES = 1048576;
    localparam integer RAW_WINDOW_BYTES=2592000;
    localparam integer RAW_MEMORY_BASE = (JPEG_RING_ARENA_ENABLE ? 7 : 2)*WINDOW_BYTES;
    localparam integer NR_MEMORY_BASE=RAW_MEMORY_BASE+(RAW_ARENA_ENABLE ? 8*RAW_WINDOW_BYTES : 0);
    // Sparse small-frame windows retain the real production bank addresses.
    localparam integer MEMORY_BYTES=NR_MEMORY_BASE+(NR_ARENA_ENABLE ? 22528 : 0);
    reg [7:0] mem [0:MEMORY_BYTES-1];
    reg [5:0] cal_count = 0;
    reg wr_active, rd_active;
    reg hold_b=0,b_pending=0;
    reg [31:0] finite_cycle=0;
    always @(posedge dfi_clk)if(!sys_rst_n)finite_cycle<=0;else finite_cycle<=finite_cycle+1;
    reg hold_jpeg_b=0,fail_jpeg_b=0;
    reg [1:0] bresp_q=0;
    integer accepted_aw=0,accepted_b=0,accepted_ar=0,accepted_r=0;
    reg [27:0] wr_addr, rd_addr;
    reg [8:0] wr_total, rd_total, wr_index, rd_index;
    integer lane;
    // Independent 133.333 MHz service clock; reset/calibration are controlled
    // by the board reference clock, and are still a PHY contract fixture.
    always #3.75 dfi_clk=~dfi_clk;
    assign ddrphy_rst_n = sys_rst_n;
    assign ddr_ck_p = sys_clk;
    assign ddr_ck_n = ~sys_clk;
    assign ddr_reset_n = sys_rst_n;
    assign ddr_cke = 1'b1;
    assign ddr_odt = 1'b0;
    assign ddr_cs_n = 1'b0;
    assign ddr_ras_n = 1'b1;
    assign ddr_cas_n = 1'b1;
    assign ddr_we_n = 1'b1;
    assign ddr_ba = 0;
    assign ddr_addr = 0;
    assign ctl_ram_rst_n = sys_rst_n;
    assign ctl_ram_cke = 1'b1;
    assign ddr_init_cal_err = 0;
    assign ddr_init_cal_step = {2'b00, cal_count};
    // This fixture owns one BID register. Keep its address credit until the
    // corresponding B is consumed, including the pending-to-VALID cycle.
    assign axi_awready = sys_rst_n && !wr_active && !b_pending && !axi_bvalid && finite_cycle%11>=2;
    assign axi_wready = sys_rst_n && wr_active && !axi_bvalid && finite_cycle%7>=2;
    assign axi_bresp = bresp_q;
    assign axi_arready = sys_rst_n && !rd_active && !axi_rvalid && finite_cycle%13>=3;
    assign axi_rresp = 2'b00;
    assign pzq_cal_done_o = 1'b1;
    assign user_clk = sys_clk;
    assign apb_clk = sys_clk;
    assign mcu_busy = 1'b0;
    assign user_ram_rd_data = 0;
    assign uart_txd = 1'b1;
    function integer nr_memory_offset(input [27:0] address);
        reg [31:0] logical;
        integer bank;
        begin
            logical=32'hffffffff;nr_memory_offset=-1;
            if(NR_ARENA_ENABLE && address>=28'h1800000 && address<28'h2000000)
                logical={4'd0,address}-32'h01800000;
            else if(NR_ARENA_ENABLE && address>=28'hf000000)
                logical={4'd0,address}-32'h0f000000+32'h00800000;
            for(bank=0;bank<4;bank=bank+1)begin
                if(logical>=bank*6221824 && logical<bank*6221824+4096)
                    nr_memory_offset=bank*4096+logical-bank*6221824;
                if(logical>=24887296+bank*61440 && logical<24887296+bank*61440+1024)
                    nr_memory_offset=16384+bank*1024+logical-24887296-bank*61440;
            end
            if(logical>=25133056 && logical<25133056+1024)
                nr_memory_offset=20480+logical-25133056;
            if(logical>=25147456 && logical<25147456+1024)
                nr_memory_offset=21504+logical-25147456;
        end
    endfunction
    function integer memory_index(input [27:0] address);
        begin
            if(address<WINDOW_BYTES) memory_index=address;
            else if(address>=28'h1000000&&address<28'h1000000+WINDOW_BYTES)
                memory_index=WINDOW_BYTES+(address-28'h1000000);
            else if(JPEG_RING_ARENA_ENABLE && address>=28'ha000000 && address<28'hf000000 && address[23:0]<WINDOW_BYTES)
                memory_index=(2+((address-28'ha000000)>>24))*WINDOW_BYTES+address[23:0];
            else if(RAW_ARENA_ENABLE && address>=28'h2000000 && address<28'ha000000 && address[23:0]<RAW_WINDOW_BYTES)
                memory_index=RAW_MEMORY_BASE+((address-28'h2000000)>>24)*RAW_WINDOW_BYTES+address[23:0];
            else if(nr_memory_offset(address)>=0) memory_index=NR_MEMORY_BASE+nr_memory_offset(address);
            else begin
                $fatal(1,"ui_ddr BFM address outside JPEG/RAW test windows: %h",address);
                memory_index=0;
            end
        end
    endfunction
    function bit legal_window(input [27:0] address,input [7:0] length);
        reg [28:0] finish;
        begin
            finish={1'b0,address}+(length+1)*16;
            legal_window=finish<=WINDOW_BYTES||
                (address>=28'h1000000&&finish<=28'h1000000+WINDOW_BYTES)||
                (JPEG_RING_ARENA_ENABLE && address>=28'ha000000 && address<28'hf000000 &&
                 ({1'b0,address[23:0]}+(length+1)*16)<=WINDOW_BYTES)||
                (RAW_ARENA_ENABLE && address>=28'h2000000 && address<28'ha000000 &&
                 ({1'b0,address[23:0]}+(length+1)*16)<=RAW_WINDOW_BYTES) ||
                (nr_memory_offset(address)>=0 && nr_memory_offset(address+(length+1)*16-1)==
                    nr_memory_offset(address)+(length+1)*16-1);
        end
    endfunction
    always @(posedge sys_clk or negedge sys_rst_n) begin
        if (!sys_rst_n) begin
            cal_count <= 0; pll_locked <= 0; ddr_init_cal_done <= 0;
        end else if (!ddr_init_cal_done) begin
            cal_count <= cal_count + 1'b1;
            if (cal_count == 4) pll_locked <= 1;
            if (cal_count == 12) ddr_init_cal_done <= 1;
        end
    end
    always @(posedge axi_aclk or negedge sys_rst_n) begin
        if (!sys_rst_n) begin
            wr_active <= 0; rd_active <= 0;b_pending<=0;accepted_aw<=0;accepted_b<=0;accepted_ar<=0;accepted_r<=0;
            wr_addr <= 0; rd_addr <= 0;
            wr_total <= 0; rd_total <= 0;
            wr_index <= 0; rd_index <= 0;
            axi_bid <= 0; axi_bvalid <= 0;bresp_q<=0;
            axi_rid <= 0; axi_rdata <= 0;
            axi_rlast <= 0; axi_rvalid <= 0;
        end else begin
            if (axi_awvalid && axi_awready) begin
                if (axi_awsize != 3'd4 || axi_awburst != 2'd1 ||
                    axi_awaddr[3:0] != 0 ||
                    !legal_window(axi_awaddr,axi_awlen))
                    $fatal(1, "ui_ddr model illegal AW addr=%h len=%0d", axi_awaddr, axi_awlen);
                accepted_aw<=accepted_aw+1;
                wr_active <= 1;
                wr_addr <= axi_awaddr;
                wr_total <= {1'b0, axi_awlen} + 1'b1;
                wr_index <= 0;
                axi_bid <= axi_awid;
            end
            if (axi_wvalid && axi_wready) begin
                if (axi_wlast !== (wr_index == wr_total - 1))
                    $fatal(1, "ui_ddr model incorrect WLAST");
                for (lane = 0; lane < 16; lane = lane + 1)
                    if (axi_wstrb[lane])
                        mem[memory_index(wr_addr + wr_index * 16 + lane)] <= axi_wdata[lane*8 +: 8];
                if (axi_wlast) begin
                    wr_active <= 0;
                    b_pending <= 1;
                end else wr_index <= wr_index + 1'b1;
            end
            if(b_pending && finite_cycle%17>=3 && !hold_b && !(hold_jpeg_b && (wr_addr<28'h1800000 ||
                (wr_addr>=28'ha000000 && wr_addr<28'hf000000)))) begin
                axi_bvalid<=1;b_pending<=0;
                bresp_q<=fail_jpeg_b && (wr_addr<28'h1800000 ||
                    (wr_addr>=28'ha000000 && wr_addr<28'hf000000)) ? 2'b10 : 2'b00;
            end
            if (axi_bvalid && axi_bready) begin axi_bvalid <= 0;accepted_b<=accepted_b+1;end
            if (axi_arvalid && axi_arready) begin
                if (axi_arsize != 3'd4 || axi_arburst != 2'd1 ||
                    axi_araddr[3:0] != 0 ||
                    !legal_window(axi_araddr,axi_arlen))
                    $fatal(1, "ui_ddr model illegal AR addr=%h len=%0d", axi_araddr, axi_arlen);
                accepted_ar<=accepted_ar+1;
                rd_active <= 1;
                rd_addr <= axi_araddr;
                rd_total <= {1'b0, axi_arlen} + 1'b1;
                rd_index <= 0;
                axi_rid <= axi_arid;
            end
            if (rd_active && !axi_rvalid && finite_cycle%5!=0) begin
                for (lane = 0; lane < 16; lane = lane + 1)
                    axi_rdata[lane*8 +: 8] <= mem[memory_index(rd_addr + rd_index * 16 + lane)];
                axi_rlast <= rd_index == rd_total - 1;
                axi_rvalid <= 1;
            end
            if (axi_rvalid && axi_rready) begin
                accepted_r<=accepted_r+1;
                axi_rvalid <= 0;
                if (axi_rlast) rd_active <= 0;
                else rd_index <= rd_index + 1'b1;
            end
        end
    end
endmodule
