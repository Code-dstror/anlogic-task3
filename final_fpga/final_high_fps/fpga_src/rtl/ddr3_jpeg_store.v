`timescale 1ns / 1ps

// 封装DDR3接口并提供单帧JPEG存取通道
module ddr3_jpeg_store #(
    // 存储与时序参数
    parameter [31:0] SLOT_BASE = 32'h00000000,
    parameter [31:0] SLOT_BYTES = 32'h01000000,
    parameter integer AXI_TIMEOUT_CYCLES = 4096,
    parameter integer HDR_PORT_ENABLE = 0,
    parameter integer FOUR_CLIENT_ENABLE = 0,
    parameter integer JPEG_RING_ENABLE = 0,
    parameter integer WRITE_RESULT_ENABLE = 0,
    parameter integer WRITE_TAG_ENABLE = 0,
    parameter integer MASK_ENABLE = 0,
    parameter integer JPEG_CAMERA_COUNT = 2
) (
    // 时钟与复位
    input wire i_sys_clk_100m,
    input wire i_sys_rst_n,
    input wire i_session_rst_n,
    input wire i_record_ownership_rst_n,input wire i_memory_fault,

    // DDR物理引脚
    output wire [0:0] o_ddr_ck_p,
    output wire [0:0] o_ddr_ck_n,
    output wire o_ddr_reset_n,
    output wire [0:0] o_ddr_cke,
    output wire [0:0] o_ddr_odt,
    output wire [0:0] o_ddr_cs_n,
    output wire o_ddr_ras_n,
    output wire o_ddr_cas_n,
    output wire o_ddr_we_n,
    output wire [2:0] o_ddr_ba,
    output wire [13:0] o_ddr_addr,
    inout wire [1:0] io_ddr_dqs_p,
    inout wire [1:0] io_ddr_dqs_n,
    inout wire [15:0] io_ddr_dq,
    inout wire [1:0] io_ddr_dm,

    // DDR就绪状态
    output wire o_dfi_clk,
    output wire o_pll_locked,
    output wire o_ddrphy_rst_n,
    output wire o_ddr_init_cal_done,
    output wire [7:0] o_ddr_init_cal_err,
    output wire [7:0] o_ddr_init_cal_step,
    output wire o_app_ready, // 完成锁相与校准同步后可接受新帧

    // 帧启动与元数据
    input wire i_start_valid,
    output wire o_start_ready,
    input wire [31:0] i_capture_id,
    input wire [15:0] i_width,
    input wire [15:0] i_height,
    input wire [63:0] i_timestamp_ns,
    input wire [31:0] i_write_tag,

    // JPEG输入流
    input wire [127:0] i_jpeg_tdata,
    input wire [15:0] i_jpeg_tkeep,
    input wire i_jpeg_tvalid,
    output wire o_jpeg_tready,
    input wire i_jpeg_tlast,

    // 编码结果
    input wire i_result_valid,
    output wire o_result_ready,
    input wire [31:0] i_result_id,
    input wire i_result_ok,
    input wire [24:0] i_result_length,

    // Optional ring writer completion; entirely in o_dfi_clk domain.
    output wire o_write_result_valid,
    input wire i_write_result_ready,
    output wire o_write_result_ok,
    output wire [7:0] o_write_result_error,
    output wire [31:0] o_write_result_capture_id,o_write_result_session,o_write_result_epoch,
    output wire o_write_result_camera,
    output wire [15:0] o_write_result_slot,
    output wire [31:0] o_write_result_generation,
    output wire [24:0] o_write_result_payload_length,
    output wire [31:0] o_write_result_tag,
    output wire o_record_quiescent,
    output wire o_write_quiescent,

    // 待发送帧描述
    output wire o_ready_valid,
    input wire i_ready_claim,
    output wire [31:0] o_capture_id,
    output wire [24:0] o_payload_length,
    output wire [15:0] o_width,
    output wire [15:0] o_height,
    output wire [63:0] o_timestamp_ns,

    // 载荷输出流
    output wire [127:0] o_payload_tdata,
    output wire [15:0] o_payload_tkeep,
    output wire o_payload_tvalid,
    input wire i_payload_tready,
    output wire o_payload_tlast,

    // 错误与统计
    output wire o_drop_pulse,
    output wire o_read_done_pulse,
    output wire [7:0] o_error_code,
    output wire o_stream_recovery_required, // 读出故障后需重建会话
    output wire [3:0] o_store_state,
    output wire [15:0] o_wr_burst_count,
    output wire [15:0] o_rd_burst_count,
    output wire [15:0] o_berr_count,
    output wire [15:0] o_rerr_count,
    output wire [15:0] o_drop_count,
    output wire [27:0] o_last_error_addr,

    // Optional DFI-domain HDR AXI master. Disabled by default; unused inputs
    // cannot affect the original JPEG path. Enable only with a disjoint arena.
    input wire [3:0] i_hdr_axi_awid,
    input wire [27:0] i_hdr_axi_awaddr,
    input wire [7:0] i_hdr_axi_awlen,
    input wire [2:0] i_hdr_axi_awsize,
    input wire [1:0] i_hdr_axi_awburst,
    input wire i_hdr_axi_awvalid,
    output wire o_hdr_axi_awready,
    input wire [127:0] i_hdr_axi_wdata,
    input wire [15:0] i_hdr_axi_wstrb,
    input wire i_hdr_axi_wlast,
    input wire i_hdr_axi_wvalid,
    output wire o_hdr_axi_wready,
    output wire [3:0] o_hdr_axi_bid,
    output wire [1:0] o_hdr_axi_bresp,
    output wire o_hdr_axi_bvalid,
    input wire i_hdr_axi_bready,
    input wire [3:0] i_hdr_axi_arid,
    input wire [27:0] i_hdr_axi_araddr,
    input wire [7:0] i_hdr_axi_arlen,
    input wire [2:0] i_hdr_axi_arsize,
    input wire [1:0] i_hdr_axi_arburst,
    input wire i_hdr_axi_arvalid,
    output wire o_hdr_axi_arready,
    output wire [3:0] o_hdr_axi_rid,
    output wire [127:0] o_hdr_axi_rdata,
    output wire [1:0] o_hdr_axi_rresp,
    output wire o_hdr_axi_rlast,
    output wire o_hdr_axi_rvalid,
    input wire i_hdr_axi_rready,
    output wire o_hdr_arbiter_fault,
    // Optional clients2 RGB staging and3 Y/map; both use this DFI clock.
    input wire [3:0] i_rgb_axi_awid,
    input wire [27:0] i_rgb_axi_awaddr,
    input wire [7:0] i_rgb_axi_awlen,
    input wire [2:0] i_rgb_axi_awsize,
    input wire [1:0] i_rgb_axi_awburst,
    input wire i_rgb_axi_awvalid,
    output wire o_rgb_axi_awready,
    input wire [127:0] i_rgb_axi_wdata,
    input wire [15:0] i_rgb_axi_wstrb,
    input wire i_rgb_axi_wlast,
    input wire i_rgb_axi_wvalid,
    output wire o_rgb_axi_wready,
    output wire [3:0] o_rgb_axi_bid,
    output wire [1:0] o_rgb_axi_bresp,
    output wire o_rgb_axi_bvalid,
    input wire i_rgb_axi_bready,
    input wire [3:0] i_rgb_axi_arid,
    input wire [27:0] i_rgb_axi_araddr,
    input wire [7:0] i_rgb_axi_arlen,
    input wire [2:0] i_rgb_axi_arsize,
    input wire [1:0] i_rgb_axi_arburst,
    input wire i_rgb_axi_arvalid,
    output wire o_rgb_axi_arready,
    output wire [3:0] o_rgb_axi_rid,
    output wire [127:0] o_rgb_axi_rdata,
    output wire [1:0] o_rgb_axi_rresp,
    output wire o_rgb_axi_rlast,
    output wire o_rgb_axi_rvalid,
    input wire i_rgb_axi_rready,
    input wire [3:0] i_map_axi_awid,
    input wire [27:0] i_map_axi_awaddr,
    input wire [7:0] i_map_axi_awlen,
    input wire [2:0] i_map_axi_awsize,
    input wire [1:0] i_map_axi_awburst,
    input wire i_map_axi_awvalid,
    output wire o_map_axi_awready,
    input wire [127:0] i_map_axi_wdata,
    input wire [15:0] i_map_axi_wstrb,
    input wire i_map_axi_wlast,
    input wire i_map_axi_wvalid,
    output wire o_map_axi_wready,
    output wire [3:0] o_map_axi_bid,
    output wire [1:0] o_map_axi_bresp,
    output wire o_map_axi_bvalid,
    input wire i_map_axi_bready,
    input wire [3:0] i_map_axi_arid,
    input wire [27:0] i_map_axi_araddr,
    input wire [7:0] i_map_axi_arlen,
    input wire [2:0] i_map_axi_arsize,
    input wire [1:0] i_map_axi_arburst,
    input wire i_map_axi_arvalid,
    output wire o_map_axi_arready,
    output wire [3:0] o_map_axi_rid,
    output wire [127:0] o_map_axi_rdata,
    output wire [1:0] o_map_axi_rresp,
    output wire o_map_axi_rlast,
    output wire o_map_axi_rvalid,
    input wire i_map_axi_rready,
    // All identity/control/retirement ports belong to i_clk (DFI), not PCIe.
    input wire [31:0] i_session_id, i_mode_epoch,
    input wire i_camera_id,
    input wire [7:0] i_quality, i_result_quality,
    input wire [31:0] i_result_epoch,
    output wire [15:0] o_slot_id,
    output wire [31:0] o_generation, o_session_id, o_mode_epoch,
    output wire o_camera_id,
    output wire [7:0] o_quality,
    input wire i_retire_valid,
    output wire o_retire_ready,
    input wire [31:0] i_retire_session, i_retire_generation,
    input wire [15:0] i_retire_slot,
    input wire i_retire_error,
    output wire o_retire_rsp_valid,
    input wire i_retire_rsp_ready,
    output wire [3:0] o_retire_rsp_code,
    output wire o_read_complete,
    output wire o_read_error,
    input wire i_req_valid,
    output wire o_req_ready,
    input wire [1:0] i_req_op,
    input wire i_req_camera,
    input wire [15:0] i_req_slot,
    input wire [31:0] i_req_generation, i_req_session,
    output wire o_rsp_valid,
    input wire i_rsp_ready,
    output wire [3:0] o_rsp_code,
    output wire [15:0] o_rsp_slot,
    output wire [31:0] o_rsp_generation, o_rsp_session, o_rsp_epoch, o_rsp_capture_id,
    output wire o_rsp_camera,
    output wire [7:0] o_rsp_quality,
    output wire [15:0] o_rsp_width, o_rsp_height,
    output wire [24:0] o_rsp_payload_length,
    output wire o_rsp_pinned,
    output wire [2:0] o_rsp_state,
    input wire i_start_mask,i_mask_allocation_ready,
    input wire [2:0] i_start_source_type,
    output wire o_mask_allocation_valid,
    output wire [15:0] o_mask_allocation_slot,
    output wire [31:0] o_mask_allocation_generation,
    output wire [27:0] o_mask_allocation_base,
    output wire [24:0] o_mask_allocation_bytes,
    input wire i_mask_result_valid,
    output wire o_mask_result_ready,
    input wire [159:0] i_mask_result_context,
    input wire [31:0] i_mask_result_tag,i_mask_result_generation,
    input wire [15:0] i_mask_result_slot,
    input wire i_mask_result_ok,
    input wire [7:0] i_mask_result_error,
    input wire [12:0] i_mask_result_width,i_mask_result_height,
    input wire [16:0] i_mask_result_written_bytes,
    input wire [47:0] i_mask_result_terminal_body,
    input wire i_req_mask,i_req_read_lock,i_mask_read_lease_release,
    output wire o_mask_read_lease_active,o_rsp_read_authorized,
    output wire o_rsp_mask_present,o_rsp_mask_pinned,
    output wire [27:0] o_rsp_mask_tail_base,
    // Optional mask shares the existing JPEG global master, never a fifth port.
    input wire [3:0] i_mask_axi_awid,
    input wire [27:0] i_mask_axi_awaddr,
    input wire [7:0] i_mask_axi_awlen,
    input wire [2:0] i_mask_axi_awsize,
    input wire [1:0] i_mask_axi_awburst,
    input wire i_mask_axi_awvalid,
    output wire o_mask_axi_awready,
    input wire [127:0] i_mask_axi_wdata,
    input wire [15:0] i_mask_axi_wstrb,
    input wire i_mask_axi_wlast,
    input wire i_mask_axi_wvalid,
    output wire o_mask_axi_wready,
    output wire [3:0] o_mask_axi_bid,
    output wire [1:0] o_mask_axi_bresp,
    output wire o_mask_axi_bvalid,
    input wire i_mask_axi_bready,
    input wire [3:0] i_mask_axi_arid,
    input wire [27:0] i_mask_axi_araddr,
    input wire [7:0] i_mask_axi_arlen,
    input wire [2:0] i_mask_axi_arsize,
    input wire [1:0] i_mask_axi_arburst,
    input wire i_mask_axi_arvalid,
    output wire o_mask_axi_arready,
    output wire [3:0] o_mask_axi_rid,
    output wire [127:0] o_mask_axi_rdata,
    output wire [1:0] o_mask_axi_rresp,
    output wire o_mask_axi_rlast,
    output wire o_mask_axi_rvalid,
    input wire i_mask_axi_rready,
    output wire o_mask_axi_quiescent,o_mask_axi_fault
);
    wire [3:0] awid, arid, bid, rid;
    wire [27:0] awaddr, araddr;
    wire [7:0] awlen, arlen;
    wire [2:0] awsize, arsize;
    wire [1:0] awburst, arburst, bresp, rresp;
    wire awvalid, awready, wvalid, wready, wlast;
    wire bvalid, bready, arvalid, arready, rvalid, rready, rlast;
    wire [127:0] wdata, rdata;
    wire [15:0] wstrb;
    wire [3:0] store_awid, store_arid, store_bid, store_rid;
    wire [27:0] store_awaddr, store_araddr;
    wire [7:0] store_awlen, store_arlen;
    wire [2:0] store_awsize, store_arsize;
    wire [1:0] store_awburst, store_arburst, store_bresp, store_rresp;
    wire store_awvalid, store_awready, store_wvalid, store_wready, store_wlast;
    wire store_bvalid, store_bready, store_arvalid, store_arready;
    wire store_rvalid, store_rready, store_rlast;
    wire [127:0] store_wdata, store_rdata;
    wire [15:0] store_wstrb;
    wire store_stream_recovery_required;
    wire ring_record_quiescent;
    assign o_record_quiescent=ring_record_quiescent && o_mask_axi_quiescent;
    wire arbiter_recovery_required;
    reg [2:0] ready_sync;
    wire session_rst_n;

    // 此版 IP 的 AXI 桥由内部 dfi_clk 驱动
    // 校准就绪信号在本地同步，DDR 自身复位不依赖该信号
    // 在DDR用户时钟域同步采样锁相和校准完成状态
    always @(posedge o_dfi_clk or negedge o_ddrphy_rst_n) begin
        if (!o_ddrphy_rst_n) ready_sync <= 3'b000;
        else ready_sync <= {ready_sync[1:0],
                            o_pll_locked && o_ddr_init_cal_done};
    end
    // 校准完成经同步后才允许新帧进入存储槽
    assign o_app_ready = ready_sync[2];

    // 会话复位由系统或 PHY 异步断言，在应用时钟域同步释放
    reset_release_sync u_session_reset (
        .i_clk(o_dfi_clk),
        .i_async_rst_n(o_ddrphy_rst_n && i_sys_rst_n && i_session_rst_n),
        .o_rst_n(session_rst_n)
    );

    ui_ddr u_ddr (
        // 此 IP 快照忽略外部 axi_aresetn，实际使用 PHY 复位
        // 事务两端须同时复位，不得只重启 AXI 主机
        .sys_rst_n(i_sys_rst_n && i_session_rst_n), .sys_clk(i_sys_clk_100m),
        .ddr_ck_p(o_ddr_ck_p), .ddr_ck_n(o_ddr_ck_n),
        .ddr_reset_n(o_ddr_reset_n), .ddr_cke(o_ddr_cke),
        .ddr_odt(o_ddr_odt), .ddr_cs_n(o_ddr_cs_n),
        .ddr_ras_n(o_ddr_ras_n), .ddr_cas_n(o_ddr_cas_n),
        .ddr_we_n(o_ddr_we_n), .ddr_ba(o_ddr_ba), .ddr_addr(o_ddr_addr),
        .ddr_dqs_p(io_ddr_dqs_p), .ddr_dqs_n(io_ddr_dqs_n),
        .ddr_dq(io_ddr_dq), .ddr_dm(io_ddr_dm),
        .ctl_ram_rst_n(), .ctl_ram_cke(),
        .dfi_clk(o_dfi_clk), .pll_locked(o_pll_locked),
        .ddrphy_rst_n(o_ddrphy_rst_n),
        .ddr_init_cal_done(o_ddr_init_cal_done),
        .ddr_init_cal_err(o_ddr_init_cal_err),
        .ddr_init_cal_step(o_ddr_init_cal_step),
        .axi_aclk(o_dfi_clk), .axi_aresetn(o_ddrphy_rst_n),
        .axi_awid(awid), .axi_awaddr(awaddr), .axi_awlen(awlen),
        .axi_awsize(awsize), .axi_awburst(awburst),
        .axi_awlock(1'b0), .axi_awcache(4'b0000),
        .axi_awprot(3'b000), .axi_awqos(4'b0000),
        .axi_awvalid(awvalid), .axi_awready(awready),
        .axi_wdata(wdata), .axi_wstrb(wstrb), .axi_wlast(wlast),
        .axi_wvalid(wvalid), .axi_wready(wready),
        .axi_bid(bid), .axi_bresp(bresp),
        .axi_bvalid(bvalid), .axi_bready(bready),
        .axi_arid(arid), .axi_araddr(araddr), .axi_arlen(arlen),
        .axi_arsize(arsize), .axi_arburst(arburst),
        .axi_arlock(1'b0), .axi_arcache(4'b0000),
        .axi_arprot(3'b000), .axi_arqos(4'b0000),
        .axi_arvalid(arvalid), .axi_arready(arready),
        .axi_rid(rid), .axi_rdata(rdata), .axi_rresp(rresp),
        .axi_rlast(rlast), .axi_rvalid(rvalid), .axi_rready(rready),
        .pzq_cal_done_i(1'b0), .pzq_cal_done_o(),
        .user_clk(), .apb_clk(), .mcu_busy(),
        .user_update(1'b0), .user_ram_addr(8'd0),
        .user_ram_wr_en(1'b0), .user_ram_rd_en(1'b0),
        .user_ram_wr_data(32'd0), .user_ram_rd_data(),
        .uart_rxd(1'b1), .uart_txd()
    );

    generate if (JPEG_RING_ENABLE == 0) begin : g_legacy_store
    jpeg_ddr_frame_store #(
        .SLOT_BASE(SLOT_BASE), .SLOT_BYTES(SLOT_BYTES),
        .AXI_TIMEOUT_CYCLES(AXI_TIMEOUT_CYCLES)
    ) u_store (
        .i_clk(o_dfi_clk), .i_rst_n(session_rst_n), .i_ddr_ready(o_app_ready),
        .i_start_valid(i_start_valid), .o_start_ready(o_start_ready),
        .i_capture_id(i_capture_id), .i_width(i_width),
        .i_height(i_height), .i_timestamp_ns(i_timestamp_ns),
        .i_jpeg_tdata(i_jpeg_tdata), .i_jpeg_tkeep(i_jpeg_tkeep),
        .i_jpeg_tvalid(i_jpeg_tvalid), .o_jpeg_tready(o_jpeg_tready),
        .i_jpeg_tlast(i_jpeg_tlast),
        .i_result_valid(i_result_valid), .o_result_ready(o_result_ready),
        .i_result_id(i_result_id), .i_result_ok(i_result_ok),
        .i_result_length(i_result_length),
        .o_ready_valid(o_ready_valid), .i_ready_claim(i_ready_claim),
        .o_capture_id(o_capture_id), .o_payload_length(o_payload_length),
        .o_width(o_width), .o_height(o_height),
        .o_timestamp_ns(o_timestamp_ns),
        .o_payload_tdata(o_payload_tdata), .o_payload_tkeep(o_payload_tkeep),
        .o_payload_tvalid(o_payload_tvalid), .i_payload_tready(i_payload_tready),
        .o_payload_tlast(o_payload_tlast),
        .o_drop_pulse(o_drop_pulse), .o_read_done_pulse(o_read_done_pulse),
        .o_error_code(o_error_code),
        .o_stream_recovery_required(store_stream_recovery_required),
        .o_state(o_store_state),
        .o_wr_burst_count(o_wr_burst_count),
        .o_rd_burst_count(o_rd_burst_count),
        .o_berr_count(o_berr_count), .o_rerr_count(o_rerr_count),
        .o_drop_count(o_drop_count),
        .o_last_error_addr(o_last_error_addr),
        .o_axi_awid(store_awid), .o_axi_awaddr(store_awaddr), .o_axi_awlen(store_awlen),
        .o_axi_awsize(store_awsize), .o_axi_awburst(store_awburst),
        .o_axi_awvalid(store_awvalid), .i_axi_awready(store_awready),
        .o_axi_wdata(store_wdata), .o_axi_wstrb(store_wstrb), .o_axi_wlast(store_wlast),
        .o_axi_wvalid(store_wvalid), .i_axi_wready(store_wready),
        .i_axi_bid(store_bid), .i_axi_bresp(store_bresp),
        .i_axi_bvalid(store_bvalid), .o_axi_bready(store_bready),
        .o_axi_arid(store_arid), .o_axi_araddr(store_araddr), .o_axi_arlen(store_arlen),
        .o_axi_arsize(store_arsize), .o_axi_arburst(store_arburst),
        .o_axi_arvalid(store_arvalid), .i_axi_arready(store_arready),
        .i_axi_rid(store_rid), .i_axi_rdata(store_rdata), .i_axi_rresp(store_rresp),
        .i_axi_rlast(store_rlast), .i_axi_rvalid(store_rvalid), .o_axi_rready(store_rready)
    );

        assign o_write_result_valid=0;assign o_write_result_ok=0;assign o_write_result_error=0;
        assign o_write_result_capture_id=0;assign o_write_result_session=0;assign o_write_result_epoch=0;
        assign o_write_result_camera=0;assign o_write_result_slot=0;assign o_write_result_generation=0;
        assign o_write_result_payload_length=0;
        assign o_write_result_tag=0;
        // Legacy store does not implement the six-slot ownership proof.
        assign ring_record_quiescent=1'b0;
        assign o_write_quiescent=1'b0;
        assign o_slot_id = 'd0;
        assign o_generation = 'd0;
        assign o_session_id = 'd0;
        assign o_mode_epoch = 'd0;
        assign o_camera_id = 'd0;
        assign o_quality = 'd0;
        assign o_retire_ready = 'd0;
        assign o_retire_rsp_valid = 'd0;
        assign o_retire_rsp_code = 'd0;
        assign o_read_complete = 'd0;
        assign o_read_error = 'd0;
        assign o_req_ready = 'd0;
        assign o_rsp_valid = 'd0;
        assign o_rsp_code = 'd0;
        assign o_rsp_slot = 'd0;
        assign o_rsp_generation = 'd0;
        assign o_rsp_session = 'd0;
        assign o_rsp_epoch = 'd0;
        assign o_rsp_capture_id = 'd0;
        assign o_rsp_camera = 'd0;
        assign o_rsp_quality = 'd0;
        assign o_rsp_width = 'd0;
        assign o_rsp_height = 'd0;
        assign o_rsp_payload_length = 'd0;
        assign o_rsp_pinned = 'd0;
        assign o_rsp_state = 'd0;
        assign o_mask_allocation_valid=0;assign o_mask_allocation_slot=0;
        assign o_mask_allocation_generation=0;assign o_mask_allocation_base=0;assign o_mask_allocation_bytes=0;
        assign o_mask_result_ready=0;assign o_mask_read_lease_active=0;assign o_rsp_read_authorized=0;
        assign o_rsp_mask_present=0;assign o_rsp_mask_pinned=0;assign o_rsp_mask_tail_base=0;
    end else begin : g_ring_store
    wire record_owner_reset_n, record_owner_data_reset_n;
    // Local rising-edge owners first sample on the same fourth edge; move
    // ASR deassertion between edges to give the large ring tree min margin.
    reset_release_sync_data #(.DATA_RESET_COPIES(0),.FALLING_RELEASE(1)) u_record_owner_reset(
        .i_clk(o_dfi_clk),.i_async_rst_n(i_record_ownership_rst_n),
        .o_rst_n(record_owner_reset_n),.o_data_rst_n(record_owner_data_reset_n));
    jpeg_frame_ring #(.SLOT_BYTES(SLOT_BYTES),.WRITE_RESULT_ENABLE(WRITE_RESULT_ENABLE),
        .WRITE_TAG_ENABLE(WRITE_TAG_ENABLE),.MASK_ENABLE(MASK_ENABLE),
        .CAMERA_COUNT(JPEG_CAMERA_COUNT),.SEPARATE_DATA_RESET(1)) u_store (

        .i_clk(o_dfi_clk), .i_rst_n(record_owner_reset_n), .i_data_reset_n(record_owner_data_reset_n),
        .i_ddr_ready(o_app_ready&&!i_memory_fault),
        .i_start_valid(i_start_valid), .o_start_ready(o_start_ready),
        .i_capture_id(i_capture_id), .i_width(i_width),
        .i_height(i_height), .i_timestamp_ns(i_timestamp_ns),
        .i_jpeg_tdata(i_jpeg_tdata), .i_jpeg_tkeep(i_jpeg_tkeep),
        .i_jpeg_tvalid(i_jpeg_tvalid), .o_jpeg_tready(o_jpeg_tready),
        .i_jpeg_tlast(i_jpeg_tlast),
        .i_result_valid(i_result_valid), .o_result_ready(o_result_ready),
        .i_result_id(i_result_id), .i_result_ok(i_result_ok),
        .i_result_length(i_result_length),
        .o_write_result_valid(o_write_result_valid),.i_write_result_ready(i_write_result_ready),
        .o_write_result_ok(o_write_result_ok),.o_write_result_error(o_write_result_error),
        .o_write_result_capture_id(o_write_result_capture_id),.o_write_result_session(o_write_result_session),
        .o_write_result_epoch(o_write_result_epoch),.o_write_result_camera(o_write_result_camera),
        .o_write_result_slot(o_write_result_slot),.o_write_result_generation(o_write_result_generation),
        .o_write_result_payload_length(o_write_result_payload_length),
        .o_write_result_tag(o_write_result_tag),.i_write_tag(i_write_tag),
        .o_record_quiescent(ring_record_quiescent),
        .o_write_quiescent(o_write_quiescent),
        .o_ready_valid(o_ready_valid), .i_ready_claim(i_ready_claim),
        .o_capture_id(o_capture_id), .o_payload_length(o_payload_length),
        .o_width(o_width), .o_height(o_height),
        .o_timestamp_ns(o_timestamp_ns),
        .o_payload_tdata(o_payload_tdata), .o_payload_tkeep(o_payload_tkeep),
        .o_payload_tvalid(o_payload_tvalid), .i_payload_tready(i_payload_tready),
        .o_payload_tlast(o_payload_tlast),
        .o_drop_pulse(o_drop_pulse), .o_read_done_pulse(o_read_done_pulse),
        .o_error_code(o_error_code),
        .o_stream_recovery_required(store_stream_recovery_required),
        .o_state(o_store_state),
        .o_wr_burst_count(o_wr_burst_count),
        .o_rd_burst_count(o_rd_burst_count),
        .o_berr_count(o_berr_count), .o_rerr_count(o_rerr_count),
        .o_drop_count(o_drop_count),
        .o_last_error_addr(o_last_error_addr),
        .o_axi_awid(store_awid), .o_axi_awaddr(store_awaddr), .o_axi_awlen(store_awlen),
        .o_axi_awsize(store_awsize), .o_axi_awburst(store_awburst),
        .o_axi_awvalid(store_awvalid), .i_axi_awready(store_awready),
        .o_axi_wdata(store_wdata), .o_axi_wstrb(store_wstrb), .o_axi_wlast(store_wlast),
        .o_axi_wvalid(store_wvalid), .i_axi_wready(store_wready),
        .i_axi_bid(store_bid), .i_axi_bresp(store_bresp),
        .i_axi_bvalid(store_bvalid), .o_axi_bready(store_bready),
        .o_axi_arid(store_arid), .o_axi_araddr(store_araddr), .o_axi_arlen(store_arlen),
        .o_axi_arsize(store_arsize), .o_axi_arburst(store_arburst),
        .o_axi_arvalid(store_arvalid), .i_axi_arready(store_arready),
        .i_axi_rid(store_rid), .i_axi_rdata(store_rdata), .i_axi_rresp(store_rresp),
        .i_axi_rlast(store_rlast), .i_axi_rvalid(store_rvalid), .o_axi_rready(store_rready),
        .i_session_id(i_session_id),
        .i_mode_epoch(i_mode_epoch),
        .i_camera_id(i_camera_id),
        .i_quality(i_quality),
        .i_result_quality(i_result_quality),
        .i_result_epoch(i_result_epoch),
        .o_slot_id(o_slot_id),
        .o_generation(o_generation),
        .o_session_id(o_session_id),
        .o_mode_epoch(o_mode_epoch),
        .o_camera_id(o_camera_id),
        .o_quality(o_quality),
        .i_retire_valid(i_retire_valid),
        .o_retire_ready(o_retire_ready),
        .i_retire_session(i_retire_session),
        .i_retire_generation(i_retire_generation),
        .i_retire_slot(i_retire_slot),
        .i_retire_error(i_retire_error),
        .o_retire_rsp_valid(o_retire_rsp_valid),
        .i_retire_rsp_ready(i_retire_rsp_ready),
        .o_retire_rsp_code(o_retire_rsp_code),
        .o_read_complete(o_read_complete),
        .o_read_error(o_read_error),
        .i_req_valid(i_req_valid),
        .o_req_ready(o_req_ready),
        .i_req_op(i_req_op),
        .i_req_camera(i_req_camera),
        .i_req_slot(i_req_slot),
        .i_req_generation(i_req_generation),
        .i_req_session(i_req_session),
        .o_rsp_valid(o_rsp_valid),
        .i_rsp_ready(i_rsp_ready),
        .o_rsp_code(o_rsp_code),
        .o_rsp_slot(o_rsp_slot),
        .o_rsp_generation(o_rsp_generation),
        .o_rsp_session(o_rsp_session),
        .o_rsp_epoch(o_rsp_epoch),
        .o_rsp_capture_id(o_rsp_capture_id),
        .o_rsp_camera(o_rsp_camera),
        .o_rsp_quality(o_rsp_quality),
        .o_rsp_width(o_rsp_width),
        .o_rsp_height(o_rsp_height),
        .o_rsp_payload_length(o_rsp_payload_length),
        .o_rsp_pinned(o_rsp_pinned),
        .o_rsp_state(o_rsp_state),
        .i_start_mask(i_start_mask),.i_mask_allocation_ready(i_mask_allocation_ready),
        .i_start_source_type(i_start_source_type),
        .o_mask_allocation_valid(o_mask_allocation_valid),.o_mask_allocation_slot(o_mask_allocation_slot),
        .o_mask_allocation_generation(o_mask_allocation_generation),.o_mask_allocation_base(o_mask_allocation_base),
        .o_mask_allocation_bytes(o_mask_allocation_bytes),.i_mask_result_valid(i_mask_result_valid),
        .o_mask_result_ready(o_mask_result_ready),.i_mask_result_context(i_mask_result_context),
        .i_mask_result_tag(i_mask_result_tag),.i_mask_result_generation(i_mask_result_generation),
        .i_mask_result_slot(i_mask_result_slot),.i_mask_result_ok(i_mask_result_ok),.i_mask_result_error(i_mask_result_error),
        .i_mask_result_width(i_mask_result_width),.i_mask_result_height(i_mask_result_height),
        .i_mask_result_written_bytes(i_mask_result_written_bytes),.i_mask_result_terminal_body(i_mask_result_terminal_body),
        .i_req_mask(i_req_mask),.i_req_read_lock(i_req_read_lock),.i_mask_read_lease_release(i_mask_read_lease_release),
        .o_mask_read_lease_active(o_mask_read_lease_active),.o_rsp_read_authorized(o_rsp_read_authorized),
        .o_rsp_mask_present(o_rsp_mask_present),.o_rsp_mask_pinned(o_rsp_mask_pinned),.o_rsp_mask_tail_base(o_rsp_mask_tail_base)
    );
    end endgenerate

    wire [3:0] shared_awid;
    wire [27:0] shared_awaddr;
    wire [7:0] shared_awlen;
    wire [2:0] shared_awsize;
    wire [1:0] shared_awburst;
    wire shared_awvalid;
    wire shared_awready;
    wire [127:0] shared_wdata;
    wire [15:0] shared_wstrb;
    wire shared_wlast;
    wire shared_wvalid;
    wire shared_wready;
    wire [3:0] shared_bid;
    wire [1:0] shared_bresp;
    wire shared_bvalid;
    wire shared_bready;
    wire [3:0] shared_arid;
    wire [27:0] shared_araddr;
    wire [7:0] shared_arlen;
    wire [2:0] shared_arsize;
    wire [1:0] shared_arburst;
    wire shared_arvalid;
    wire shared_arready;
    wire [3:0] shared_rid;
    wire [127:0] shared_rdata;
    wire [1:0] shared_rresp;
    wire shared_rlast;
    wire shared_rvalid;
    wire shared_rready;
    generate if(MASK_ENABLE!=0 && JPEG_RING_ENABLE!=0) begin : g_mask_axi
        wire write_quiet;
        axi_write_two_client_arbiter u_write(
            .i_clk(o_dfi_clk),.i_axi_rst_n(session_rst_n),
            .s_awid({i_mask_axi_awid,store_awid}),
            .s_awaddr({i_mask_axi_awaddr,store_awaddr}),
            .s_awlen({i_mask_axi_awlen,store_awlen}),
            .s_awsize({i_mask_axi_awsize,store_awsize}),
            .s_awburst({i_mask_axi_awburst,store_awburst}),
            .s_awvalid({i_mask_axi_awvalid,store_awvalid}),
            .s_awready({o_mask_axi_awready,store_awready}),
            .s_wdata({i_mask_axi_wdata,store_wdata}),
            .s_wstrb({i_mask_axi_wstrb,store_wstrb}),
            .s_wlast({i_mask_axi_wlast,store_wlast}),
            .s_wvalid({i_mask_axi_wvalid,store_wvalid}),
            .s_wready({o_mask_axi_wready,store_wready}),
            .s_bid({o_mask_axi_bid,store_bid}),
            .s_bresp({o_mask_axi_bresp,store_bresp}),
            .s_bvalid({o_mask_axi_bvalid,store_bvalid}),
            .s_bready({i_mask_axi_bready,store_bready}),
            .m_awid(shared_awid),
            .m_awaddr(shared_awaddr),
            .m_awlen(shared_awlen),
            .m_awsize(shared_awsize),
            .m_awburst(shared_awburst),
            .m_awvalid(shared_awvalid),
            .m_awready(shared_awready),
            .m_wdata(shared_wdata),
            .m_wstrb(shared_wstrb),
            .m_wlast(shared_wlast),
            .m_wvalid(shared_wvalid),
            .m_wready(shared_wready),
            .m_bid(shared_bid),
            .m_bresp(shared_bresp),
            .m_bvalid(shared_bvalid),
            .m_bready(shared_bready),
            .o_quiescent(write_quiet),.o_protocol_fault(o_mask_axi_fault));
        // The real ring grants this lease only at reader IDLE and retains it
        // through all R beats, cache RETIRE and the final host reply.
        assign shared_arid=o_mask_read_lease_active ? i_mask_axi_arid : store_arid;
        assign shared_araddr=o_mask_read_lease_active ? i_mask_axi_araddr : store_araddr;
        assign shared_arlen=o_mask_read_lease_active ? i_mask_axi_arlen : store_arlen;
        assign shared_arsize=o_mask_read_lease_active ? i_mask_axi_arsize : store_arsize;
        assign shared_arburst=o_mask_read_lease_active ? i_mask_axi_arburst : store_arburst;
        assign shared_arvalid=o_mask_read_lease_active ? i_mask_axi_arvalid : store_arvalid;
        assign o_mask_axi_arready=o_mask_read_lease_active ? shared_arready : 'd0;
        assign store_arready=o_mask_read_lease_active ? 'd0 : shared_arready;
        assign o_mask_axi_rid=o_mask_read_lease_active ? shared_rid : 'd0;
        assign store_rid=o_mask_read_lease_active ? 'd0 : shared_rid;
        assign o_mask_axi_rdata=o_mask_read_lease_active ? shared_rdata : 'd0;
        assign store_rdata=o_mask_read_lease_active ? 'd0 : shared_rdata;
        assign o_mask_axi_rresp=o_mask_read_lease_active ? shared_rresp : 'd0;
        assign store_rresp=o_mask_read_lease_active ? 'd0 : shared_rresp;
        assign o_mask_axi_rlast=o_mask_read_lease_active ? shared_rlast : 'd0;
        assign store_rlast=o_mask_read_lease_active ? 'd0 : shared_rlast;
        assign o_mask_axi_rvalid=o_mask_read_lease_active ? shared_rvalid : 'd0;
        assign store_rvalid=o_mask_read_lease_active ? 'd0 : shared_rvalid;
        assign shared_rready=o_mask_read_lease_active ? i_mask_axi_rready : store_rready;
        assign o_mask_axi_quiescent=write_quiet && !o_mask_read_lease_active &&
            !i_mask_axi_arvalid && !shared_rvalid;
    end else begin : g_no_mask_axi
        assign shared_awid=store_awid;
        assign shared_awaddr=store_awaddr;
        assign shared_awlen=store_awlen;
        assign shared_awsize=store_awsize;
        assign shared_awburst=store_awburst;
        assign shared_awvalid=store_awvalid;
        assign store_awready=shared_awready;
        assign o_mask_axi_awready='d0;
        assign shared_wdata=store_wdata;
        assign shared_wstrb=store_wstrb;
        assign shared_wlast=store_wlast;
        assign shared_wvalid=store_wvalid;
        assign store_wready=shared_wready;
        assign o_mask_axi_wready='d0;
        assign store_bid=shared_bid;
        assign o_mask_axi_bid='d0;
        assign store_bresp=shared_bresp;
        assign o_mask_axi_bresp='d0;
        assign store_bvalid=shared_bvalid;
        assign o_mask_axi_bvalid='d0;
        assign shared_bready=store_bready;
        assign shared_arid=store_arid;
        assign shared_araddr=store_araddr;
        assign shared_arlen=store_arlen;
        assign shared_arsize=store_arsize;
        assign shared_arburst=store_arburst;
        assign shared_arvalid=store_arvalid;
        assign store_arready=shared_arready;
        assign o_mask_axi_arready='d0;
        assign store_rid=shared_rid;
        assign o_mask_axi_rid='d0;
        assign store_rdata=shared_rdata;
        assign o_mask_axi_rdata='d0;
        assign store_rresp=shared_rresp;
        assign o_mask_axi_rresp='d0;
        assign store_rlast=shared_rlast;
        assign o_mask_axi_rlast='d0;
        assign store_rvalid=shared_rvalid;
        assign o_mask_axi_rvalid='d0;
        assign shared_rready=store_rready;
        assign o_mask_axi_quiescent=1'b1;assign o_mask_axi_fault=1'b0;
    end endgenerate

    // With HDR disabled, this elaborates exactly the original direct connection.
    // With HDR enabled, both clients and the arbiter share PHY/session reset.
    generate
        if (FOUR_CLIENT_ENABLE != 0) begin : g_four_client_shared
            ddr_axi_four_client_arbiter #(
                .TIMEOUT_CYCLES(AXI_TIMEOUT_CYCLES)
            ) u_arbiter (
                .clk(o_dfi_clk), .rst_n(session_rst_n),
                .fault(o_hdr_arbiter_fault),
                .o_recovery_required(arbiter_recovery_required),
                .s0_awid(shared_awid),
                .s0_awaddr(shared_awaddr),
                .s0_awlen(shared_awlen),
                .s0_awsize(shared_awsize),
                .s0_awburst(shared_awburst),
                .s0_awvalid(shared_awvalid),
                .s0_awready(shared_awready),
                .s0_wdata(shared_wdata),
                .s0_wstrb(shared_wstrb),
                .s0_wlast(shared_wlast),
                .s0_wvalid(shared_wvalid),
                .s0_wready(shared_wready),
                .s0_bid(shared_bid),
                .s0_bresp(shared_bresp),
                .s0_bvalid(shared_bvalid),
                .s0_bready(shared_bready),
                .s0_arid(shared_arid),
                .s0_araddr(shared_araddr),
                .s0_arlen(shared_arlen),
                .s0_arsize(shared_arsize),
                .s0_arburst(shared_arburst),
                .s0_arvalid(shared_arvalid),
                .s0_arready(shared_arready),
                .s0_rid(shared_rid),
                .s0_rdata(shared_rdata),
                .s0_rresp(shared_rresp),
                .s0_rlast(shared_rlast),
                .s0_rvalid(shared_rvalid),
                .s0_rready(shared_rready),
                .s1_awid(i_hdr_axi_awid),
                .s1_awaddr(i_hdr_axi_awaddr),
                .s1_awlen(i_hdr_axi_awlen),
                .s1_awsize(i_hdr_axi_awsize),
                .s1_awburst(i_hdr_axi_awburst),
                .s1_awvalid(i_hdr_axi_awvalid),
                .s1_awready(o_hdr_axi_awready),
                .s1_wdata(i_hdr_axi_wdata),
                .s1_wstrb(i_hdr_axi_wstrb),
                .s1_wlast(i_hdr_axi_wlast),
                .s1_wvalid(i_hdr_axi_wvalid),
                .s1_wready(o_hdr_axi_wready),
                .s1_bid(o_hdr_axi_bid),
                .s1_bresp(o_hdr_axi_bresp),
                .s1_bvalid(o_hdr_axi_bvalid),
                .s1_bready(i_hdr_axi_bready),
                .s1_arid(i_hdr_axi_arid),
                .s1_araddr(i_hdr_axi_araddr),
                .s1_arlen(i_hdr_axi_arlen),
                .s1_arsize(i_hdr_axi_arsize),
                .s1_arburst(i_hdr_axi_arburst),
                .s1_arvalid(i_hdr_axi_arvalid),
                .s1_arready(o_hdr_axi_arready),
                .s1_rid(o_hdr_axi_rid),
                .s1_rdata(o_hdr_axi_rdata),
                .s1_rresp(o_hdr_axi_rresp),
                .s1_rlast(o_hdr_axi_rlast),
                .s1_rvalid(o_hdr_axi_rvalid),
                .s1_rready(i_hdr_axi_rready),
                .s2_awid(i_rgb_axi_awid),
                .s2_awaddr(i_rgb_axi_awaddr),
                .s2_awlen(i_rgb_axi_awlen),
                .s2_awsize(i_rgb_axi_awsize),
                .s2_awburst(i_rgb_axi_awburst),
                .s2_awvalid(i_rgb_axi_awvalid),
                .s2_awready(o_rgb_axi_awready),
                .s2_wdata(i_rgb_axi_wdata),
                .s2_wstrb(i_rgb_axi_wstrb),
                .s2_wlast(i_rgb_axi_wlast),
                .s2_wvalid(i_rgb_axi_wvalid),
                .s2_wready(o_rgb_axi_wready),
                .s2_bid(o_rgb_axi_bid),
                .s2_bresp(o_rgb_axi_bresp),
                .s2_bvalid(o_rgb_axi_bvalid),
                .s2_bready(i_rgb_axi_bready),
                .s2_arid(i_rgb_axi_arid),
                .s2_araddr(i_rgb_axi_araddr),
                .s2_arlen(i_rgb_axi_arlen),
                .s2_arsize(i_rgb_axi_arsize),
                .s2_arburst(i_rgb_axi_arburst),
                .s2_arvalid(i_rgb_axi_arvalid),
                .s2_arready(o_rgb_axi_arready),
                .s2_rid(o_rgb_axi_rid),
                .s2_rdata(o_rgb_axi_rdata),
                .s2_rresp(o_rgb_axi_rresp),
                .s2_rlast(o_rgb_axi_rlast),
                .s2_rvalid(o_rgb_axi_rvalid),
                .s2_rready(i_rgb_axi_rready),
                .s3_awid(i_map_axi_awid),
                .s3_awaddr(i_map_axi_awaddr),
                .s3_awlen(i_map_axi_awlen),
                .s3_awsize(i_map_axi_awsize),
                .s3_awburst(i_map_axi_awburst),
                .s3_awvalid(i_map_axi_awvalid),
                .s3_awready(o_map_axi_awready),
                .s3_wdata(i_map_axi_wdata),
                .s3_wstrb(i_map_axi_wstrb),
                .s3_wlast(i_map_axi_wlast),
                .s3_wvalid(i_map_axi_wvalid),
                .s3_wready(o_map_axi_wready),
                .s3_bid(o_map_axi_bid),
                .s3_bresp(o_map_axi_bresp),
                .s3_bvalid(o_map_axi_bvalid),
                .s3_bready(i_map_axi_bready),
                .s3_arid(i_map_axi_arid),
                .s3_araddr(i_map_axi_araddr),
                .s3_arlen(i_map_axi_arlen),
                .s3_arsize(i_map_axi_arsize),
                .s3_arburst(i_map_axi_arburst),
                .s3_arvalid(i_map_axi_arvalid),
                .s3_arready(o_map_axi_arready),
                .s3_rid(o_map_axi_rid),
                .s3_rdata(o_map_axi_rdata),
                .s3_rresp(o_map_axi_rresp),
                .s3_rlast(o_map_axi_rlast),
                .s3_rvalid(o_map_axi_rvalid),
                .s3_rready(i_map_axi_rready),
                .m_awid(awid),
                .m_awaddr(awaddr),
                .m_awlen(awlen),
                .m_awsize(awsize),
                .m_awburst(awburst),
                .m_awvalid(awvalid),
                .m_awready(awready),
                .m_wdata(wdata),
                .m_wstrb(wstrb),
                .m_wlast(wlast),
                .m_wvalid(wvalid),
                .m_wready(wready),
                .m_bid(bid),
                .m_bresp(bresp),
                .m_bvalid(bvalid),
                .m_bready(bready),
                .m_arid(arid),
                .m_araddr(araddr),
                .m_arlen(arlen),
                .m_arsize(arsize),
                .m_arburst(arburst),
                .m_arvalid(arvalid),
                .m_arready(arready),
                .m_rid(rid),
                .m_rdata(rdata),
                .m_rresp(rresp),
                .m_rlast(rlast),
                .m_rvalid(rvalid),
                .m_rready(rready)
            );
        end else if (HDR_PORT_ENABLE != 0) begin : g_hdr_shared
            ddr_axi_two_client_arbiter #(
                .TIMEOUT_CYCLES(AXI_TIMEOUT_CYCLES)
            ) u_arbiter (
                .clk(o_dfi_clk), .rst_n(session_rst_n),
                .fault(o_hdr_arbiter_fault),
                .o_recovery_required(arbiter_recovery_required),
                .s0_awid(shared_awid),
                .s0_awaddr(shared_awaddr),
                .s0_awlen(shared_awlen),
                .s0_awsize(shared_awsize),
                .s0_awburst(shared_awburst),
                .s0_awvalid(shared_awvalid),
                .s0_awready(shared_awready),
                .s0_wdata(shared_wdata),
                .s0_wstrb(shared_wstrb),
                .s0_wlast(shared_wlast),
                .s0_wvalid(shared_wvalid),
                .s0_wready(shared_wready),
                .s0_bid(shared_bid),
                .s0_bresp(shared_bresp),
                .s0_bvalid(shared_bvalid),
                .s0_bready(shared_bready),
                .s0_arid(shared_arid),
                .s0_araddr(shared_araddr),
                .s0_arlen(shared_arlen),
                .s0_arsize(shared_arsize),
                .s0_arburst(shared_arburst),
                .s0_arvalid(shared_arvalid),
                .s0_arready(shared_arready),
                .s0_rid(shared_rid),
                .s0_rdata(shared_rdata),
                .s0_rresp(shared_rresp),
                .s0_rlast(shared_rlast),
                .s0_rvalid(shared_rvalid),
                .s0_rready(shared_rready),
                .s1_awid(i_hdr_axi_awid),
                .s1_awaddr(i_hdr_axi_awaddr),
                .s1_awlen(i_hdr_axi_awlen),
                .s1_awsize(i_hdr_axi_awsize),
                .s1_awburst(i_hdr_axi_awburst),
                .s1_awvalid(i_hdr_axi_awvalid),
                .s1_awready(o_hdr_axi_awready),
                .s1_wdata(i_hdr_axi_wdata),
                .s1_wstrb(i_hdr_axi_wstrb),
                .s1_wlast(i_hdr_axi_wlast),
                .s1_wvalid(i_hdr_axi_wvalid),
                .s1_wready(o_hdr_axi_wready),
                .s1_bid(o_hdr_axi_bid),
                .s1_bresp(o_hdr_axi_bresp),
                .s1_bvalid(o_hdr_axi_bvalid),
                .s1_bready(i_hdr_axi_bready),
                .s1_arid(i_hdr_axi_arid),
                .s1_araddr(i_hdr_axi_araddr),
                .s1_arlen(i_hdr_axi_arlen),
                .s1_arsize(i_hdr_axi_arsize),
                .s1_arburst(i_hdr_axi_arburst),
                .s1_arvalid(i_hdr_axi_arvalid),
                .s1_arready(o_hdr_axi_arready),
                .s1_rid(o_hdr_axi_rid),
                .s1_rdata(o_hdr_axi_rdata),
                .s1_rresp(o_hdr_axi_rresp),
                .s1_rlast(o_hdr_axi_rlast),
                .s1_rvalid(o_hdr_axi_rvalid),
                .s1_rready(i_hdr_axi_rready),
                .m_awid(awid),
                .m_awaddr(awaddr),
                .m_awlen(awlen),
                .m_awsize(awsize),
                .m_awburst(awburst),
                .m_awvalid(awvalid),
                .m_awready(awready),
                .m_wdata(wdata),
                .m_wstrb(wstrb),
                .m_wlast(wlast),
                .m_wvalid(wvalid),
                .m_wready(wready),
                .m_bid(bid),
                .m_bresp(bresp),
                .m_bvalid(bvalid),
                .m_bready(bready),
                .m_arid(arid),
                .m_araddr(araddr),
                .m_arlen(arlen),
                .m_arsize(arsize),
                .m_arburst(arburst),
                .m_arvalid(arvalid),
                .m_arready(arready),
                .m_rid(rid),
                .m_rdata(rdata),
                .m_rresp(rresp),
                .m_rlast(rlast),
                .m_rvalid(rvalid),
                .m_rready(rready)
            );
        end else begin : g_jpeg_only
            assign awid = shared_awid;
            assign awaddr = shared_awaddr;
            assign awlen = shared_awlen;
            assign awsize = shared_awsize;
            assign awburst = shared_awburst;
            assign awvalid = shared_awvalid;
            assign shared_awready = awready;
            assign wdata = shared_wdata;
            assign wstrb = shared_wstrb;
            assign wlast = shared_wlast;
            assign wvalid = shared_wvalid;
            assign shared_wready = wready;
            assign shared_bid = bid;
            assign shared_bresp = bresp;
            assign shared_bvalid = bvalid;
            assign bready = shared_bready;
            assign arid = shared_arid;
            assign araddr = shared_araddr;
            assign arlen = shared_arlen;
            assign arsize = shared_arsize;
            assign arburst = shared_arburst;
            assign arvalid = shared_arvalid;
            assign shared_arready = arready;
            assign shared_rid = rid;
            assign shared_rdata = rdata;
            assign shared_rresp = rresp;
            assign shared_rlast = rlast;
            assign shared_rvalid = rvalid;
            assign rready = shared_rready;
            assign o_hdr_axi_awready = 'd0;
            assign o_hdr_axi_wready = 'd0;
            assign o_hdr_axi_bid = 'd0;
            assign o_hdr_axi_bresp = 'd0;
            assign o_hdr_axi_bvalid = 'd0;
            assign o_hdr_axi_arready = 'd0;
            assign o_hdr_axi_rid = 'd0;
            assign o_hdr_axi_rdata = 'd0;
            assign o_hdr_axi_rresp = 'd0;
            assign o_hdr_axi_rlast = 'd0;
            assign o_hdr_axi_rvalid = 'd0;
            assign o_hdr_arbiter_fault = 1'b0;
            assign arbiter_recovery_required = 1'b0;
        end
    endgenerate
    generate
        if (FOUR_CLIENT_ENABLE != 0 && HDR_PORT_ENABLE == 0) begin : bad_four_client_config
            FOUR_CLIENT_DDR_REQUIRES_RAW_HDR_PORT invalid_configuration();
        end
        if (FOUR_CLIENT_ENABLE == 0) begin : g_unused_extra_clients
            assign o_rgb_axi_awready = 1'd0;
            assign o_rgb_axi_wready = 1'd0;
            assign o_rgb_axi_bid = 4'd0;
            assign o_rgb_axi_bresp = 2'd0;
            assign o_rgb_axi_bvalid = 1'd0;
            assign o_rgb_axi_arready = 1'd0;
            assign o_rgb_axi_rid = 4'd0;
            assign o_rgb_axi_rdata = 128'd0;
            assign o_rgb_axi_rresp = 2'd0;
            assign o_rgb_axi_rlast = 1'd0;
            assign o_rgb_axi_rvalid = 1'd0;
            assign o_map_axi_awready = 1'd0;
            assign o_map_axi_wready = 1'd0;
            assign o_map_axi_bid = 4'd0;
            assign o_map_axi_bresp = 2'd0;
            assign o_map_axi_bvalid = 1'd0;
            assign o_map_axi_arready = 1'd0;
            assign o_map_axi_rid = 4'd0;
            assign o_map_axi_rdata = 128'd0;
            assign o_map_axi_rresp = 2'd0;
            assign o_map_axi_rlast = 1'd0;
            assign o_map_axi_rvalid = 1'd0;
        end
    endgenerate
    assign o_stream_recovery_required = i_memory_fault || store_stream_recovery_required ||
                                        arbiter_recovery_required || o_mask_axi_fault;
endmodule
