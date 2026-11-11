`timescale 1ns / 1ps

// 连接 RAW 黑电平、行窗口和去马赛克流水线
module raw_isp_top
#(
    parameter integer SAMPLE_BITS = 10,
    parameter integer RUNTIME_BLC_BYPASS_ENABLE = 0,
    // 行缓存与帧尺寸上限
	parameter integer MAX_WIDTH  = 3840,  // 行缓存宽度上限
	parameter integer MAX_HEIGHT = 2160,  // 帧高上限
    // 黑电平配置
	parameter [SAMPLE_BITS-1:0]   BLC_OFFSET_L0 = 10'd50,  // 第0路 黑电平偏移
	parameter [SAMPLE_BITS-1:0]   BLC_OFFSET_L1 = 10'd50,  // 第1路 黑电平偏移
	parameter [SAMPLE_BITS-1:0]   BLC_OFFSET_L2 = 10'd50,  // 第2路 黑电平偏移
	parameter [SAMPLE_BITS-1:0]   BLC_OFFSET_L3 = 10'd50  // 第3路 黑电平偏移
)
(
    // 时钟与复位
	input  wire         clk,  // 同步时钟
	input  wire         rst_n,  // 同步低有效复位
    // 运行配置
	input  wire [12:0]  cfg_width,  // 运行期宽度，帧首锁存
	input  wire [12:0]  cfg_height,  // 运行期高度，帧首锁存
	input  wire [1:0]   cfg_bayer_phase,  // Bayer 相位，帧首锁存
	input  wire         cfg_edge_g,  // G 插值模式，0=圆整双线性 1=边缘导向
    input wire cfg_blc_bypass,
    // 输入数据流
	input  wire [4*SAMPLE_BITS-1:0]  s_tdata,  // 4xRAW10，lane0 在最低 10bit / 4xRAW10, lane0 lowest
	input  wire         s_tvalid,  // 从端数据有效
	output wire         s_tready,  // 从端可接收
	input  wire         s_tuser,  // 帧首拍标记
	input  wire         s_tlast,  // 行末拍标记
    // 输出数据流
	output wire [12*SAMPLE_BITS-1:0] m_tdata,  // 每拍四个 RGB101010 像素
	output wire         m_tvalid,  // 主端数据有效
	input  wire         m_tready,  // 主端可接收
	output wire         m_tuser,  // 输出帧首拍
	output wire         m_tlast,  // 输出行末拍
    // 行窗口调试状态
	output wire [38:0]  dbg_state  // 调试状态
);

  // 其他信号连线
	wire [4*SAMPLE_BITS-1:0]         blc_tdata;              // BLC 输出数据
	wire                blc_tvalid;             // BLC 输出有效
	wire                blc_tready;             // BLC 输出可接收
	wire                blc_tuser;              // BLC 输出帧首拍
	wire                blc_tlast;              // BLC 输出行末拍
	wire [18*SAMPLE_BITS-1:0]        win_tdata;              // 窗数据
	wire                win_tvalid;             // 窗有效
	wire                win_tready;             // 窗可接收
	wire                win_first;              // 输出行首拍
	wire                win_last;               // 输出行末拍
	wire                win_sof;                // 输出帧首拍
	wire                win_parity;             // 输出行奇偶
	wire                win_busy;               // 行窗在途
	wire                demo_busy;              // 去马赛克在途

  // 模块实例化区域
  // 黑电平校正对每路像素做饱和减法，保留十位精度
	raw_blc
	#(
		.SAMPLE_BITS(SAMPLE_BITS),
        .RUNTIME_BLC_BYPASS_ENABLE(RUNTIME_BLC_BYPASS_ENABLE),
		.BLC_OFFSET_L0(BLC_OFFSET_L0),
		.BLC_OFFSET_L1(BLC_OFFSET_L1),
		.BLC_OFFSET_L2(BLC_OFFSET_L2),
		.BLC_OFFSET_L3(BLC_OFFSET_L3)
	)
	u_raw_blc
	(
		.clk(clk),
		.rst_n(rst_n),
        .cfg_bypass(cfg_blc_bypass),
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

  // 行缓存与三行六列窗口生成与输入同尺寸的三乘三邻域
	raw_row_window
	#(
		.SAMPLE_BITS(SAMPLE_BITS),
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

  // 去马赛克对邻域做三乘三重建，打包为四路十位精度的 RGB101010 像素
	raw_demosaic #(.SAMPLE_BITS(SAMPLE_BITS))
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
