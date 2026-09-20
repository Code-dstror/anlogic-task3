`timescale 1ns / 1ps

////////////////////////////////////English///////////////////////////////////////
// Company:         AnLu ISP Optimized
// Engineer:        RAW front-end agent
//
// Create Date:     2026/02/14 12:00:00
// Design Name:     raw_isp_top
// Module Name:     raw_isp_top
// Description:     description/raw_isp_top_Design.pdf
// Simulations:     isp_optimized/sim/raw/tb_raw_isp_top.v
//
// Referrences:     isp_optimized/docs/raw_design.md
//
// Dependencies:    raw_blc.v raw_row_window.v raw_demosaic.v
//
// Version:         V1.0
// Revision Date:   2026/02/14 12:00:00
// History:
// Time             Version     Revised by        Contents
// 2026/02/14       V1.0        RAW agent         Create file.
///////////////////////////////////Chinese////////////////////////////////////////
// 版权归属:        AnLu ISP Optimized
// 开发人员:        RAW 前端 agent
//
// 创建日期:        2026年2月14日
// 设计名称:        raw_isp_top
// 模块名称:        raw_isp_top
// 模块说明:        Description/raw_isp_top_Design.pdf
// 仿真工程:        isp_optimized/sim/raw/tb_raw_isp_top.v
//
// 参考资料:        isp_optimized/docs/raw_design.md
//
// 依赖文件:        raw_blc.v raw_row_window.v raw_demosaic.v
//
// 当前版本:        V1.0
// 修订日期:        2026年2月14日
// 修订历史:
// 时间             版本        修订人            修订内容
// 2026年2月14日    V1.0        RAW agent         创建文件

// RAW 前端顶层：BLC 黑电平 -> 行缓存与列窗 -> 去马赛克，输出与输入同尺寸的 4xRGB101010。
// 配置在帧首原子锁存，非法尺寸整帧丢弃，换档必须在帧间进行。
// RAW front end top: BLC -> line buffer and column window -> demosaic, producing 4xRGB101010 at the
// same size as the input. Configuration is latched atomically at the frame start, an illegal size drops
// the whole frame, and a size switch is only allowed between frames.
module raw_isp_top
#(
	parameter integer MAX_WIDTH  = 3840,      // 行缓存宽度上限 / maximum allocated width
	parameter integer MAX_HEIGHT = 2160,      // 帧高上限 / maximum frame height
	parameter [9:0]   BLC_OFFSET_L0 = 10'd50, // lane0 黑电平偏移 / lane0 black level offset
	parameter [9:0]   BLC_OFFSET_L1 = 10'd50, // lane1 黑电平偏移 / lane1 black level offset
	parameter [9:0]   BLC_OFFSET_L2 = 10'd50, // lane2 黑电平偏移 / lane2 black level offset
	parameter [9:0]   BLC_OFFSET_L3 = 10'd50  // lane3 黑电平偏移 / lane3 black level offset
)
(
	//-----------------全局信号-----------------//
	input  wire         clk,                    // 同步时钟 / synchronous clock
	input  wire         rst_n,                  // 同步低有效复位 / synchronous active low reset

	//-----------------配置信号-----------------//
	input  wire [12:0]  cfg_width,              // 运行期宽度，帧首锁存 / runtime width latched at frame start
	input  wire [12:0]  cfg_height,             // 运行期高度，帧首锁存 / runtime height latched at frame start
	input  wire [1:0]   cfg_bayer_phase,        // Bayer 相位，帧首锁存 / Bayer phase latched at frame start
	input  wire         cfg_edge_g,             // G 插值模式，0=圆整双线性 1=边缘导向 / green interpolation mode

	//-----------------从端接口-----------------//
	input  wire [39:0]  s_tdata,                // 4xRAW10，lane0 在最低 10bit / 4xRAW10, lane0 lowest
	input  wire         s_tvalid,               // 从端数据有效 / slave data valid
	output wire         s_tready,               // 从端可接收 / slave ready
	input  wire         s_tuser,                // 帧首拍标记 / frame first beat marker
	input  wire         s_tlast,                // 行末拍标记 / line last beat marker

	//-----------------主端接口-----------------//
	output wire [119:0] m_tdata,                // 4xRGB101010 / four pixels RGB101010
	output wire         m_tvalid,               // 主端数据有效 / master data valid
	input  wire         m_tready,               // 主端可接收 / master ready
	output wire         m_tuser,                // 输出帧首拍 / output frame first beat
	output wire         m_tlast,                // 输出行末拍 / output line last beat
	output wire [38:0]  dbg_state               // 调试状态 / debug state
);

	//---------------其他信号连线---------------//
	wire [39:0]         blc_tdata;              // BLC 输出数据 / BLC output data
	wire                blc_tvalid;             // BLC 输出有效 / BLC output valid
	wire                blc_tready;             // BLC 输出可接收 / BLC output ready
	wire                blc_tuser;              // BLC 输出帧首拍 / BLC output frame first beat
	wire                blc_tlast;              // BLC 输出行末拍 / BLC output line last beat
	wire [179:0]        win_tdata;              // 窗数据 / window data
	wire                win_tvalid;             // 窗有效 / window valid
	wire                win_tready;             // 窗可接收 / window ready
	wire                win_first;              // 输出行首拍 / output row first beat
	wire                win_last;               // 输出行末拍 / output row last beat
	wire                win_sof;                // 输出帧首拍 / output frame first beat
	wire                win_parity;             // 输出行奇偶 / output row parity
	wire                win_busy;               // 行窗在途 / row window in flight
	wire                demo_busy;              // 去马赛克在途 / demosaic in flight

	//--------------模块实例化区域--------------//
	// 黑电平校正：逐 lane 饱和减法，保留 10bit。
	// Black level correction: per lane saturating subtract keeping 10bit.
	raw_blc
	#(
		.BLC_OFFSET_L0(BLC_OFFSET_L0),
		.BLC_OFFSET_L1(BLC_OFFSET_L1),
		.BLC_OFFSET_L2(BLC_OFFSET_L2),
		.BLC_OFFSET_L3(BLC_OFFSET_L3)
	)
	u_raw_blc
	(
		.clk(clk),
		.rst_n(rst_n),
		.s_tdata(s_tdata),
		.s_tvalid(s_tvalid),
		.s_tready(s_tready),
		.s_tuser(s_tuser),
		.s_tlast(s_tlast),
		.m_tdata(blc_tdata),
		.m_tvalid(blc_tvalid),
		.m_tready(blc_tready),
		.m_tuser(blc_tuser),
		.m_tlast(blc_tlast)
	);

	// 行缓存与 3x6 列窗：产生与输入同尺寸的 3x3 邻域窗。
	// Line buffer and 3x6 column window producing the 3x3 neighbourhood window at the input size.
	raw_row_window
	#(
		.MAX_WIDTH(MAX_WIDTH),
		.MAX_HEIGHT(MAX_HEIGHT)
	)
	u_raw_row_window
	(
		.clk(clk),
		.rst_n(rst_n),
		.cfg_width(cfg_width),
		.cfg_height(cfg_height),
		.s_tdata(blc_tdata),
		.s_tvalid(blc_tvalid),
		.s_tready(blc_tready),
		.s_tuser(blc_tuser),
		.s_tlast(blc_tlast),
		.m_window(win_tdata),
		.m_valid(win_tvalid),
		.m_ready(win_tready),
		.m_first(win_first),
		.m_last(win_last),
		.m_sof(win_sof),
		.m_row_parity(win_parity),
		.m_busy(win_busy),
		.i_down_busy(demo_busy),
		.dbg_state(dbg_state)
	);

	// 去马赛克：3x3 重建并打包成 4xRGB101010，全 10bit 精度。
	// Demosaic: 3x3 reconstruction packed into 4xRGB101010 with full 10bit precision.
	raw_demosaic
	u_raw_demosaic
	(
		.clk(clk),
		.rst_n(rst_n),
		.cfg_bayer_phase(cfg_bayer_phase),
		.cfg_edge_g(cfg_edge_g),
		.s_window(win_tdata),
		.s_valid(win_tvalid),
		.s_ready(win_tready),
		.s_sof(win_sof),
		.s_last(win_last),
		.s_row_parity(win_parity),
		.m_tdata(m_tdata),
		.m_tvalid(m_tvalid),
		.m_tready(m_tready),
		.m_tuser(m_tuser),
		.m_tlast(m_tlast),
		.m_busy(demo_busy)
	);

endmodule
