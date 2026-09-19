/*******************************************************************************
 * Company     : anlu_ips isp_optimized
 * Module      : isp_core_top
 * File        : isp_core_top.v
 * Description : ISP 核心顶层:把 RAW 前端与 COLOR 后端连成一条 40bit RAW10 ->
 *               96bit RGB888 的四像素同步流,不含 PCIe / DMA / 板级逻辑
 *
 * Referrences : isp_optimized/ARCHITECTURE.md
 *               isp_optimized/docs/raw_design.md   (raw_isp_top 接口)
 *               isp_optimized/docs/color_design.md (color_pipeline_axis 接口)
 * Simulation  : isp_optimized/tb/tb_isp_core_top.v
 *
 * 交付边界(用户已明确缩减范围):
 *   本模块是 ISP 的交付终点,输出到 96bit RGB888 为止。
 *   后续 AXIS 去向 / 字节打包 / PCIe / DMA 不在本次交付范围。
 *   统计口径:o_stat_beat_total = 输出传输拍数;o_stat_frame_total =
 *   输出传输 && tuser 的"帧开始"计数(不是"完整帧"计数);o_stat_saturate_total
 *   = COLOR 饱和拍数。三者均由 color_pipeline_axis 直接透传。
 *
 * 像素流契约(单时钟,clk 上升沿,rst_n 同步低有效):
 *   RAW 输入  40 bit,lane0 = [9:0] 为组内最左像素,lane k = [10*k +: 10]
 *   中间流   120 bit,lane0 = [29:0],lane k = [30*k +: 30],lane 内 R[29:20] G[19:10] B[9:0]
 *   输出      96 bit,lane0 = [23:0],lane k = [24*k +: 24],lane 内 R[23:16] G[15:8] B[7:0]
 *   tuser 仅标记含整帧第一个有效像素的一拍;tlast 标记含一行最后一个有效像素的一拍。
 *   valid && ready 是唯一传输事件;valid=1 且 ready=0 时发送端必须保持 data/user/last 不变。
 ******************************************************************************/

`timescale 1ns / 1ps

module isp_core_top #(
	parameter integer       C_MAX_WIDTH           = 3840,      // 支持的最大宽度
	parameter integer       C_MAX_HEIGHT          = 2160,      // 支持的最大高度
	parameter [9:0]         C_BLC_OFFSET_L0       = 10'd50,    // 黑电平偏置,lane0
	parameter [9:0]         C_BLC_OFFSET_L1       = 10'd50,    // 黑电平偏置,lane1
	parameter [9:0]         C_BLC_OFFSET_L2       = 10'd50,    // 黑电平偏置,lane2
	parameter [9:0]         C_BLC_OFFSET_L3       = 10'd50,    // 黑电平偏置,lane3
	parameter [15:0]        C_WB_GAIN_R           = 16'd256,   // 白平衡 R 增益,unsigned Q8
	parameter [15:0]        C_WB_GAIN_G           = 16'd256,   // 白平衡 G 增益,unsigned Q8
	parameter [15:0]        C_WB_GAIN_B           = 16'd256,   // 白平衡 B 增益,unsigned Q8
	parameter signed [10:0] C_CCM_M00             = 11'sd256,  // 颜色矩阵 M00,signed Q8
	parameter signed [10:0] C_CCM_M01             = 11'sd0,    // 颜色矩阵 M01,signed Q8
	parameter signed [10:0] C_CCM_M02             = 11'sd0,    // 颜色矩阵 M02,signed Q8
	parameter signed [10:0] C_CCM_M10             = 11'sd0,    // 颜色矩阵 M10,signed Q8
	parameter signed [10:0] C_CCM_M11             = 11'sd256,  // 颜色矩阵 M11,signed Q8
	parameter signed [10:0] C_CCM_M12             = 11'sd0,    // 颜色矩阵 M12,signed Q8
	parameter signed [10:0] C_CCM_M20             = 11'sd0,    // 颜色矩阵 M20,signed Q8
	parameter signed [10:0] C_CCM_M21             = 11'sd0,    // 颜色矩阵 M21,signed Q8
	parameter signed [10:0] C_CCM_M22             = 11'sd256,  // 颜色矩阵 M22,signed Q8
	parameter integer       C_GAMMA_LINEAR_BYPASS = 0          // 0=gamma2.2,1=线性旁路
)(
	input                   clk,                                // 时钟信号
	input                   rst_n,                              // 复位信号,同步低有效
	input       [12:0]      cfg_width,                          // 运行期图像宽度,4 的倍数
	input       [12:0]      cfg_height,                         // 运行期图像高度
	input       [1:0]       cfg_bayer_phase,                    // Bayer 相位选择
	input                   cfg_edge_g,                         // 1=边缘导向 G,0=圆整双线性
	input       [39:0]      s_tdata,                            // RAW10 四像素输入
	input                   s_tvalid,                           // 输入数据有效
	output                  s_tready,                           // 输入就绪
	input                   s_tuser,                            // 帧首像素拍
	input                   s_tlast,                            // 行尾像素拍
	output      [95:0]      m_tdata,                            // RGB888 四像素输出
	output                  m_tvalid,                           // 输出数据有效
	input                   m_tready,                           // 输出就绪
	output                  m_tuser,                            // 帧首像素拍
	output                  m_tlast,                            // 行尾像素拍
	output      [31:0]      o_stat_beat_total,                  // COLOR 累计输出拍数
	output      [31:0]      o_stat_frame_total,                  // COLOR 累计帧开始数(输出传输&&tuser)
	output      [31:0]      o_stat_saturate_total               // COLOR 累计饱和次数
);

	//=====================================================================
	// RAW 前端与 COLOR 后端之间的 120bit 中间流
	//=====================================================================
	wire [119:0]            rgb10_tdata;                        // 120bit RGB10 中间流
	wire                    rgb10_tvalid;                       // 中间流数据有效
	wire                    rgb10_tready;                       // 中间流就绪
	wire                    rgb10_tuser;                        // 中间流帧首像素拍
	wire                    rgb10_tlast;                        // 中间流行尾像素拍

	//=====================================================================
	// RAW10 前端:饱和黑电平校正 + 保留精度去马赛克
	// 运行期 cfg_* 由 RAW 前端在帧首原子锁存
	//=====================================================================
	raw_isp_top #(
		.MAX_WIDTH          (C_MAX_WIDTH          ),
		.MAX_HEIGHT         (C_MAX_HEIGHT         ),
		.BLC_OFFSET_L0      (C_BLC_OFFSET_L0      ),
		.BLC_OFFSET_L1      (C_BLC_OFFSET_L1      ),
		.BLC_OFFSET_L2      (C_BLC_OFFSET_L2      ),
		.BLC_OFFSET_L3      (C_BLC_OFFSET_L3      )
	) u_raw_isp_top (
		.clk                (clk                  ),          // 时钟信号
		.rst_n              (rst_n                ),          // 复位信号,同步低有效
		.cfg_width          (cfg_width            ),          // 运行期宽度
		.cfg_height         (cfg_height           ),          // 运行期高度
		.cfg_bayer_phase    (cfg_bayer_phase      ),          // Bayer 相位
		.cfg_edge_g         (cfg_edge_g           ),          // 边缘导向 G 使能
		.s_tdata            (s_tdata              ),          // RAW10 四像素输入
		.s_tvalid           (s_tvalid             ),          // 输入有效
		.s_tready           (s_tready             ),          // 输入就绪
		.s_tuser            (s_tuser              ),          // 帧首像素拍
		.s_tlast            (s_tlast              ),          // 行尾像素拍
		.m_tdata            (rgb10_tdata          ),          // 120bit RGB10 输出
		.m_tvalid           (rgb10_tvalid         ),          // 输出有效
		.m_tready           (rgb10_tready         ),          // 输出就绪
		.m_tuser            (rgb10_tuser          ),          // 帧首像素拍
		.m_tlast            (rgb10_tlast          )           // 行尾像素拍
	);

	//=====================================================================
	// COLOR 后端:白平衡 + 有符号颜色矩阵 + 10bit 输入 gamma,输出 RGB888
	// 默认增益为 1、CCM 为单位阵,属未标定安全起点,不得称为自动白平衡
	//=====================================================================
	color_pipeline_axis #(
		.C_WB_GAIN_R            (C_WB_GAIN_R            ),   // 白平衡 R 增益
		.C_WB_GAIN_G            (C_WB_GAIN_G            ),   // 白平衡 G 增益
		.C_WB_GAIN_B            (C_WB_GAIN_B            ),   // 白平衡 B 增益
		.C_CCM_M00              (C_CCM_M00              ),   // 颜色矩阵 M00
		.C_CCM_M01              (C_CCM_M01              ),   // 颜色矩阵 M01
		.C_CCM_M02              (C_CCM_M02              ),   // 颜色矩阵 M02
		.C_CCM_M10              (C_CCM_M10              ),   // 颜色矩阵 M10
		.C_CCM_M11              (C_CCM_M11              ),   // 颜色矩阵 M11
		.C_CCM_M12              (C_CCM_M12              ),   // 颜色矩阵 M12
		.C_CCM_M20              (C_CCM_M20              ),   // 颜色矩阵 M20
		.C_CCM_M21              (C_CCM_M21              ),   // 颜色矩阵 M21
		.C_CCM_M22              (C_CCM_M22              ),   // 颜色矩阵 M22
		.C_GAMMA_LINEAR_BYPASS  (C_GAMMA_LINEAR_BYPASS  )    // gamma 线性旁路
	) u_color_pipeline_axis (
		.i_clk                  (clk                    ),   // 时钟信号
		.i_rstn                 (rst_n                  ),   // 复位信号,同步低有效
		.i_s_axis_tdata         (rgb10_tdata            ),   // 120bit RGB10 输入
		.i_s_axis_tvalid        (rgb10_tvalid           ),   // 输入有效
		.o_s_axis_tready        (rgb10_tready           ),   // 输入就绪
		.i_s_axis_tuser         (rgb10_tuser            ),   // 帧首像素拍
		.i_s_axis_tlast         (rgb10_tlast            ),   // 行尾像素拍
		.o_m_axis_tdata         (m_tdata                ),   // 96bit RGB888 输出
		.o_m_axis_tvalid        (m_tvalid               ),   // 输出有效
		.i_m_axis_tready        (m_tready               ),   // 输出就绪
		.o_m_axis_tuser         (m_tuser                ),   // 帧首像素拍
		.o_m_axis_tlast         (m_tlast                ),   // 行尾像素拍
		.o_stat_beat_total      (o_stat_beat_total      ),   // 累计输出拍数
		.o_stat_frame_total     (o_stat_frame_total     ),   // 累计帧开始数(输出传输&&tuser)
		.o_stat_saturate_total  (o_stat_saturate_total  )    // 累计饱和次数
	);

endmodule
