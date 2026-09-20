`timescale 1ns / 1ps

////////////////////////////////////English///////////////////////////////////////
// Company:         anlu_ips
// Engineer:        color_agent
//
// Create Date:     2026/09/12 17:00:00
// Design Name:     color_pipeline_axis
// Module Name:     color_pipeline_axis
// Description:     description/color_pipeline_axis_Design.pdf
// Simulations:     testbench/vivado/2021.1/color_pipeline_axis
//
// Referrences:     isp_optimized/docs/color_design.md
//
// Dependencies:    None
//
// Version:         V1.0
// Revision Date:   2026/09/12 17:00:00
// History:
// Time             Version     Revised by        Contents
// 2026/09/12       V1.0        color_agent       Create file.
///////////////////////////////////Chinese////////////////////////////////////////
// 版权归属:        anlu_ips
// 开发人员:        color_agent
//
// 创建日期:        2026/09/12
// 设计名称:        color_pipeline_axis
// 模块名称:        color_pipeline_axis
// 模块说明:        Description/color_pipeline_axis_Design.pdf
// 仿真工程:        TestBench/Vivado/2021.1/color_pipeline_axis
//
// 参考资料:        isp_optimized/docs/color_design.md
//
// 依赖文件:        None
//
// 当前版本:        V1.0
// 修订日期:        2026/09/12
// 修订历史:
// 时间             版本        修订人            修订内容
// 2026/09/12       V1.0        color_agent       创建文件

module color_pipeline_axis
#(
	parameter C_WB_GAIN_R = 10'd256,                            // 红色通道白平衡增益(定点 Q8)
	parameter C_WB_GAIN_G = 10'd256,                            // 绿色通道白平衡增益(定点 Q8)
	parameter C_WB_GAIN_B = 10'd256,                            // 蓝色通道白平衡增益(定点 Q8)
	parameter C_WB_SHIFT = 8,                                   // 白平衡定点小数位
	parameter C_WB_MAX = 10'd1023,                              // 白平衡上限饱和值
	parameter C_CCM_M00 = 11'sd256,                             // 色彩矩阵第 1 行第 1 列
	parameter C_CCM_M01 = 11'sd0,                               // 色彩矩阵第 1 行第 2 列
	parameter C_CCM_M02 = 11'sd0,                               // 色彩矩阵第 1 行第 3 列
	parameter C_CCM_M10 = 11'sd0,                               // 色彩矩阵第 2 行第 1 列
	parameter C_CCM_M11 = 11'sd256,                             // 色彩矩阵第 2 行第 2 列
	parameter C_CCM_M12 = 11'sd0,                               // 色彩矩阵第 2 行第 3 列
	parameter C_CCM_M20 = 11'sd0,                               // 色彩矩阵第 3 行第 1 列
	parameter C_CCM_M21 = 11'sd0,                               // 色彩矩阵第 3 行第 2 列
	parameter C_CCM_M22 = 11'sd256,                             // 色彩矩阵第 3 行第 3 列
	parameter C_CCM_SHIFT = 8,                                  // 色彩矩阵定点小数位
	parameter C_CCM_MAX = 10'd1023,                             // 色彩矩阵上限饱和值
	parameter C_GAMMA_LINEAR_BYPASS = 1'b0                      // 1 表示线性 bypass 查表
)
(
	//-----------------全局信号-----------------//
	input i_clk,                                                // 工作时钟
	input i_rstn,                                               // 低有效复位

	//-----------------AXIS接口-----------------//
	input i_s_axis_tvalid,                                      // 输入 beat 有效
	output o_s_axis_tready,                                     // 输入 beat 就绪
	input i_s_axis_tlast,                                       // 输入行尾标志
	input i_s_axis_tuser,                                       // 输入帧首标志
	input [119:0]i_s_axis_tdata,                                // 输入 4 像素 RGB101010
	output o_m_axis_tvalid,                                     // 输出 beat 有效
	input i_m_axis_tready,                                      // 输出 beat 就绪
	output o_m_axis_tlast,                                      // 输出行尾标志
	output o_m_axis_tuser,                                      // 输出帧首标志
	output [95:0]o_m_axis_tdata,                                // 输出 4 像素 RGB888

	//-----------------用户接口-----------------//
	output [31:0]o_stat_beat_total,                             // 累计已传输 beat 数
	output [31:0]o_stat_frame_total,                            // 累计帧起始数(传输且 tuser)
	output [31:0]o_stat_saturate_total                          // 累计饱和 beat 数
);

	//---------------配置参数区域---------------//
	localparam WB_ROUND_VALUE = (1 << (C_WB_SHIFT - 1)); // 白平衡圆整常量
	localparam CCM_ROUND_VALUE = (1 << (C_CCM_SHIFT - 1)); // 矩阵圆整常量
	localparam PIXEL_WIDTH = 10; // 单通道码值位宽
	localparam LANE_WIDTH = 24; // 输出单像素位宽
	localparam WORD_WIDTH = 96; // 输出 beat 位宽

	//----------------寄存器信号----------------//
	reg [119:0]reg_word_input = 120'd0; // 输入 beat 数据缓存
	reg [2:0]reg_ctrl_input = 3'd0; // 输入 beat 控制位缓存
	reg [9:0]reg_in_red_left = 10'd0; // red 通道 left 像素输入码值
	reg [9:0]reg_in_red_center_left = 10'd0; // red 通道 center_left 像素输入码值
	reg [9:0]reg_in_red_center_right = 10'd0; // red 通道 center_right 像素输入码值
	reg [9:0]reg_in_red_right = 10'd0; // red 通道 right 像素输入码值
	reg [9:0]reg_in_green_left = 10'd0; // green 通道 left 像素输入码值
	reg [9:0]reg_in_green_center_left = 10'd0; // green 通道 center_left 像素输入码值
	reg [9:0]reg_in_green_center_right = 10'd0; // green 通道 center_right 像素输入码值
	reg [9:0]reg_in_green_right = 10'd0; // green 通道 right 像素输入码值
	reg [9:0]reg_in_blue_left = 10'd0; // blue 通道 left 像素输入码值
	reg [9:0]reg_in_blue_center_left = 10'd0; // blue 通道 center_left 像素输入码值
	reg [9:0]reg_in_blue_center_right = 10'd0; // blue 通道 center_right 像素输入码值
	reg [9:0]reg_in_blue_right = 10'd0; // blue 通道 right 像素输入码值
	reg [19:0]reg_wb_product_red_left = 20'd0; // red 通道 left 像素白平衡乘积
	reg [19:0]reg_wb_product_red_center_left = 20'd0; // red 通道 center_left 像素白平衡乘积
	reg [19:0]reg_wb_product_red_center_right = 20'd0; // red 通道 center_right 像素白平衡乘积
	reg [19:0]reg_wb_product_red_right = 20'd0; // red 通道 right 像素白平衡乘积
	reg [19:0]reg_wb_round_red_left = 20'd0; // red 通道 left 像素白平衡圆整值
	reg [19:0]reg_wb_round_red_center_left = 20'd0; // red 通道 center_left 像素白平衡圆整值
	reg [19:0]reg_wb_round_red_center_right = 20'd0; // red 通道 center_right 像素白平衡圆整值
	reg [19:0]reg_wb_round_red_right = 20'd0; // red 通道 right 像素白平衡圆整值
	reg [19:0]reg_wb_scale_red_left = 20'd0; // red 通道 left 像素白平衡缩放值
	reg [19:0]reg_wb_scale_red_center_left = 20'd0; // red 通道 center_left 像素白平衡缩放值
	reg [19:0]reg_wb_scale_red_center_right = 20'd0; // red 通道 center_right 像素白平衡缩放值
	reg [19:0]reg_wb_scale_red_right = 20'd0; // red 通道 right 像素白平衡缩放值
	reg [19:0]reg_wb_delay_red_left = 20'd0; // red 通道 left 像素白平衡缩放延迟值
	reg [19:0]reg_wb_delay_red_center_left = 20'd0; // red 通道 center_left 像素白平衡缩放延迟值
	reg [19:0]reg_wb_delay_red_center_right = 20'd0; // red 通道 center_right 像素白平衡缩放延迟值
	reg [19:0]reg_wb_delay_red_right = 20'd0; // red 通道 right 像素白平衡缩放延迟值
	reg [9:0]reg_wb_level_red_left = 10'd0; // red 通道 left 像素白平衡输出码值
	reg [9:0]reg_wb_level_red_center_left = 10'd0; // red 通道 center_left 像素白平衡输出码值
	reg [9:0]reg_wb_level_red_center_right = 10'd0; // red 通道 center_right 像素白平衡输出码值
	reg [9:0]reg_wb_level_red_right = 10'd0; // red 通道 right 像素白平衡输出码值
	reg [19:0]reg_wb_product_green_left = 20'd0; // green 通道 left 像素白平衡乘积
	reg [19:0]reg_wb_product_green_center_left = 20'd0; // green 通道 center_left 像素白平衡乘积
	reg [19:0]reg_wb_product_green_center_right = 20'd0; // green 通道 center_right 像素白平衡乘积
	reg [19:0]reg_wb_product_green_right = 20'd0; // green 通道 right 像素白平衡乘积
	reg [19:0]reg_wb_round_green_left = 20'd0; // green 通道 left 像素白平衡圆整值
	reg [19:0]reg_wb_round_green_center_left = 20'd0; // green 通道 center_left 像素白平衡圆整值
	reg [19:0]reg_wb_round_green_center_right = 20'd0; // green 通道 center_right 像素白平衡圆整值
	reg [19:0]reg_wb_round_green_right = 20'd0; // green 通道 right 像素白平衡圆整值
	reg [19:0]reg_wb_scale_green_left = 20'd0; // green 通道 left 像素白平衡缩放值
	reg [19:0]reg_wb_scale_green_center_left = 20'd0; // green 通道 center_left 像素白平衡缩放值
	reg [19:0]reg_wb_scale_green_center_right = 20'd0; // green 通道 center_right 像素白平衡缩放值
	reg [19:0]reg_wb_scale_green_right = 20'd0; // green 通道 right 像素白平衡缩放值
	reg [19:0]reg_wb_delay_green_left = 20'd0; // green 通道 left 像素白平衡缩放延迟值
	reg [19:0]reg_wb_delay_green_center_left = 20'd0; // green 通道 center_left 像素白平衡缩放延迟值
	reg [19:0]reg_wb_delay_green_center_right = 20'd0; // green 通道 center_right 像素白平衡缩放延迟值
	reg [19:0]reg_wb_delay_green_right = 20'd0; // green 通道 right 像素白平衡缩放延迟值
	reg [9:0]reg_wb_level_green_left = 10'd0; // green 通道 left 像素白平衡输出码值
	reg [9:0]reg_wb_level_green_center_left = 10'd0; // green 通道 center_left 像素白平衡输出码值
	reg [9:0]reg_wb_level_green_center_right = 10'd0; // green 通道 center_right 像素白平衡输出码值
	reg [9:0]reg_wb_level_green_right = 10'd0; // green 通道 right 像素白平衡输出码值
	reg [19:0]reg_wb_product_blue_left = 20'd0; // blue 通道 left 像素白平衡乘积
	reg [19:0]reg_wb_product_blue_center_left = 20'd0; // blue 通道 center_left 像素白平衡乘积
	reg [19:0]reg_wb_product_blue_center_right = 20'd0; // blue 通道 center_right 像素白平衡乘积
	reg [19:0]reg_wb_product_blue_right = 20'd0; // blue 通道 right 像素白平衡乘积
	reg [19:0]reg_wb_round_blue_left = 20'd0; // blue 通道 left 像素白平衡圆整值
	reg [19:0]reg_wb_round_blue_center_left = 20'd0; // blue 通道 center_left 像素白平衡圆整值
	reg [19:0]reg_wb_round_blue_center_right = 20'd0; // blue 通道 center_right 像素白平衡圆整值
	reg [19:0]reg_wb_round_blue_right = 20'd0; // blue 通道 right 像素白平衡圆整值
	reg [19:0]reg_wb_scale_blue_left = 20'd0; // blue 通道 left 像素白平衡缩放值
	reg [19:0]reg_wb_scale_blue_center_left = 20'd0; // blue 通道 center_left 像素白平衡缩放值
	reg [19:0]reg_wb_scale_blue_center_right = 20'd0; // blue 通道 center_right 像素白平衡缩放值
	reg [19:0]reg_wb_scale_blue_right = 20'd0; // blue 通道 right 像素白平衡缩放值
	reg [19:0]reg_wb_delay_blue_left = 20'd0; // blue 通道 left 像素白平衡缩放延迟值
	reg [19:0]reg_wb_delay_blue_center_left = 20'd0; // blue 通道 center_left 像素白平衡缩放延迟值
	reg [19:0]reg_wb_delay_blue_center_right = 20'd0; // blue 通道 center_right 像素白平衡缩放延迟值
	reg [19:0]reg_wb_delay_blue_right = 20'd0; // blue 通道 right 像素白平衡缩放延迟值
	reg [9:0]reg_wb_level_blue_left = 10'd0; // blue 通道 left 像素白平衡输出码值
	reg [9:0]reg_wb_level_blue_center_left = 10'd0; // blue 通道 center_left 像素白平衡输出码值
	reg [9:0]reg_wb_level_blue_center_right = 10'd0; // blue 通道 center_right 像素白平衡输出码值
	reg [9:0]reg_wb_level_blue_right = 10'd0; // blue 通道 right 像素白平衡输出码值
	reg [23:0]reg_ccm_first_red_left = 24'd0; // red 通道 left 像素矩阵首项
	reg [23:0]reg_ccm_first_red_center_left = 24'd0; // red 通道 center_left 像素矩阵首项
	reg [23:0]reg_ccm_first_red_center_right = 24'd0; // red 通道 center_right 像素矩阵首项
	reg [23:0]reg_ccm_first_red_right = 24'd0; // red 通道 right 像素矩阵首项
	reg [23:0]reg_ccm_second_red_left = 24'd0; // red 通道 left 像素矩阵次项
	reg [23:0]reg_ccm_second_red_center_left = 24'd0; // red 通道 center_left 像素矩阵次项
	reg [23:0]reg_ccm_second_red_center_right = 24'd0; // red 通道 center_right 像素矩阵次项
	reg [23:0]reg_ccm_second_red_right = 24'd0; // red 通道 right 像素矩阵次项
	reg [23:0]reg_ccm_third_red_left = 24'd0; // red 通道 left 像素矩阵末项
	reg [23:0]reg_ccm_third_red_center_left = 24'd0; // red 通道 center_left 像素矩阵末项
	reg [23:0]reg_ccm_third_red_center_right = 24'd0; // red 通道 center_right 像素矩阵末项
	reg [23:0]reg_ccm_third_red_right = 24'd0; // red 通道 right 像素矩阵末项
	reg [23:0]reg_ccm_partial_red_left = 24'd0; // red 通道 left 像素矩阵前两项和
	reg [23:0]reg_ccm_partial_red_center_left = 24'd0; // red 通道 center_left 像素矩阵前两项和
	reg [23:0]reg_ccm_partial_red_center_right = 24'd0; // red 通道 center_right 像素矩阵前两项和
	reg [23:0]reg_ccm_partial_red_right = 24'd0; // red 通道 right 像素矩阵前两项和
	reg [23:0]reg_ccm_third_hold_red_left = 24'd0; // red 通道 left 像素矩阵末项延迟值
	reg [23:0]reg_ccm_third_hold_red_center_left = 24'd0; // red 通道 center_left 像素矩阵末项延迟值
	reg [23:0]reg_ccm_third_hold_red_center_right = 24'd0; // red 通道 center_right 像素矩阵末项延迟值
	reg [23:0]reg_ccm_third_hold_red_right = 24'd0; // red 通道 right 像素矩阵末项延迟值
	reg [23:0]reg_ccm_total_red_left = 24'd0; // red 通道 left 像素矩阵三项和
	reg [23:0]reg_ccm_total_red_center_left = 24'd0; // red 通道 center_left 像素矩阵三项和
	reg [23:0]reg_ccm_total_red_center_right = 24'd0; // red 通道 center_right 像素矩阵三项和
	reg [23:0]reg_ccm_total_red_right = 24'd0; // red 通道 right 像素矩阵三项和
	reg [23:0]reg_ccm_round_red_left = 24'd0; // red 通道 left 像素矩阵圆整值
	reg [23:0]reg_ccm_round_red_center_left = 24'd0; // red 通道 center_left 像素矩阵圆整值
	reg [23:0]reg_ccm_round_red_center_right = 24'd0; // red 通道 center_right 像素矩阵圆整值
	reg [23:0]reg_ccm_round_red_right = 24'd0; // red 通道 right 像素矩阵圆整值
	reg [23:0]reg_ccm_shift_red_left = 24'd0; // red 通道 left 像素矩阵移位值
	reg [23:0]reg_ccm_shift_red_center_left = 24'd0; // red 通道 center_left 像素矩阵移位值
	reg [23:0]reg_ccm_shift_red_center_right = 24'd0; // red 通道 center_right 像素矩阵移位值
	reg [23:0]reg_ccm_shift_red_right = 24'd0; // red 通道 right 像素矩阵移位值
	reg [23:0]reg_ccm_delay_low_red_left = 24'd0; // red 通道 left 像素矩阵下钳位延迟值
	reg [23:0]reg_ccm_delay_low_red_center_left = 24'd0; // red 通道 center_left 像素矩阵下钳位延迟值
	reg [23:0]reg_ccm_delay_low_red_center_right = 24'd0; // red 通道 center_right 像素矩阵下钳位延迟值
	reg [23:0]reg_ccm_delay_low_red_right = 24'd0; // red 通道 right 像素矩阵下钳位延迟值
	reg [23:0]reg_ccm_low_red_left = 24'd0; // red 通道 left 像素矩阵下钳位值
	reg [23:0]reg_ccm_low_red_center_left = 24'd0; // red 通道 center_left 像素矩阵下钳位值
	reg [23:0]reg_ccm_low_red_center_right = 24'd0; // red 通道 center_right 像素矩阵下钳位值
	reg [23:0]reg_ccm_low_red_right = 24'd0; // red 通道 right 像素矩阵下钳位值
	reg [23:0]reg_ccm_delay_level_red_left = 24'd0; // red 通道 left 像素矩阵上钳位延迟值
	reg [23:0]reg_ccm_delay_level_red_center_left = 24'd0; // red 通道 center_left 像素矩阵上钳位延迟值
	reg [23:0]reg_ccm_delay_level_red_center_right = 24'd0; // red 通道 center_right 像素矩阵上钳位延迟值
	reg [23:0]reg_ccm_delay_level_red_right = 24'd0; // red 通道 right 像素矩阵上钳位延迟值
	reg [9:0]reg_ccm_level_red_left = 10'd0; // red 通道 left 像素矩阵输出码值
	reg [9:0]reg_ccm_level_red_center_left = 10'd0; // red 通道 center_left 像素矩阵输出码值
	reg [9:0]reg_ccm_level_red_center_right = 10'd0; // red 通道 center_right 像素矩阵输出码值
	reg [9:0]reg_ccm_level_red_right = 10'd0; // red 通道 right 像素矩阵输出码值
	reg [23:0]reg_ccm_first_green_left = 24'd0; // green 通道 left 像素矩阵首项
	reg [23:0]reg_ccm_first_green_center_left = 24'd0; // green 通道 center_left 像素矩阵首项
	reg [23:0]reg_ccm_first_green_center_right = 24'd0; // green 通道 center_right 像素矩阵首项
	reg [23:0]reg_ccm_first_green_right = 24'd0; // green 通道 right 像素矩阵首项
	reg [23:0]reg_ccm_second_green_left = 24'd0; // green 通道 left 像素矩阵次项
	reg [23:0]reg_ccm_second_green_center_left = 24'd0; // green 通道 center_left 像素矩阵次项
	reg [23:0]reg_ccm_second_green_center_right = 24'd0; // green 通道 center_right 像素矩阵次项
	reg [23:0]reg_ccm_second_green_right = 24'd0; // green 通道 right 像素矩阵次项
	reg [23:0]reg_ccm_third_green_left = 24'd0; // green 通道 left 像素矩阵末项
	reg [23:0]reg_ccm_third_green_center_left = 24'd0; // green 通道 center_left 像素矩阵末项
	reg [23:0]reg_ccm_third_green_center_right = 24'd0; // green 通道 center_right 像素矩阵末项
	reg [23:0]reg_ccm_third_green_right = 24'd0; // green 通道 right 像素矩阵末项
	reg [23:0]reg_ccm_partial_green_left = 24'd0; // green 通道 left 像素矩阵前两项和
	reg [23:0]reg_ccm_partial_green_center_left = 24'd0; // green 通道 center_left 像素矩阵前两项和
	reg [23:0]reg_ccm_partial_green_center_right = 24'd0; // green 通道 center_right 像素矩阵前两项和
	reg [23:0]reg_ccm_partial_green_right = 24'd0; // green 通道 right 像素矩阵前两项和
	reg [23:0]reg_ccm_third_hold_green_left = 24'd0; // green 通道 left 像素矩阵末项延迟值
	reg [23:0]reg_ccm_third_hold_green_center_left = 24'd0; // green 通道 center_left 像素矩阵末项延迟值
	reg [23:0]reg_ccm_third_hold_green_center_right = 24'd0; // green 通道 center_right 像素矩阵末项延迟值
	reg [23:0]reg_ccm_third_hold_green_right = 24'd0; // green 通道 right 像素矩阵末项延迟值
	reg [23:0]reg_ccm_total_green_left = 24'd0; // green 通道 left 像素矩阵三项和
	reg [23:0]reg_ccm_total_green_center_left = 24'd0; // green 通道 center_left 像素矩阵三项和
	reg [23:0]reg_ccm_total_green_center_right = 24'd0; // green 通道 center_right 像素矩阵三项和
	reg [23:0]reg_ccm_total_green_right = 24'd0; // green 通道 right 像素矩阵三项和
	reg [23:0]reg_ccm_round_green_left = 24'd0; // green 通道 left 像素矩阵圆整值
	reg [23:0]reg_ccm_round_green_center_left = 24'd0; // green 通道 center_left 像素矩阵圆整值
	reg [23:0]reg_ccm_round_green_center_right = 24'd0; // green 通道 center_right 像素矩阵圆整值
	reg [23:0]reg_ccm_round_green_right = 24'd0; // green 通道 right 像素矩阵圆整值
	reg [23:0]reg_ccm_shift_green_left = 24'd0; // green 通道 left 像素矩阵移位值
	reg [23:0]reg_ccm_shift_green_center_left = 24'd0; // green 通道 center_left 像素矩阵移位值
	reg [23:0]reg_ccm_shift_green_center_right = 24'd0; // green 通道 center_right 像素矩阵移位值
	reg [23:0]reg_ccm_shift_green_right = 24'd0; // green 通道 right 像素矩阵移位值
	reg [23:0]reg_ccm_delay_low_green_left = 24'd0; // green 通道 left 像素矩阵下钳位延迟值
	reg [23:0]reg_ccm_delay_low_green_center_left = 24'd0; // green 通道 center_left 像素矩阵下钳位延迟值
	reg [23:0]reg_ccm_delay_low_green_center_right = 24'd0; // green 通道 center_right 像素矩阵下钳位延迟值
	reg [23:0]reg_ccm_delay_low_green_right = 24'd0; // green 通道 right 像素矩阵下钳位延迟值
	reg [23:0]reg_ccm_low_green_left = 24'd0; // green 通道 left 像素矩阵下钳位值
	reg [23:0]reg_ccm_low_green_center_left = 24'd0; // green 通道 center_left 像素矩阵下钳位值
	reg [23:0]reg_ccm_low_green_center_right = 24'd0; // green 通道 center_right 像素矩阵下钳位值
	reg [23:0]reg_ccm_low_green_right = 24'd0; // green 通道 right 像素矩阵下钳位值
	reg [23:0]reg_ccm_delay_level_green_left = 24'd0; // green 通道 left 像素矩阵上钳位延迟值
	reg [23:0]reg_ccm_delay_level_green_center_left = 24'd0; // green 通道 center_left 像素矩阵上钳位延迟值
	reg [23:0]reg_ccm_delay_level_green_center_right = 24'd0; // green 通道 center_right 像素矩阵上钳位延迟值
	reg [23:0]reg_ccm_delay_level_green_right = 24'd0; // green 通道 right 像素矩阵上钳位延迟值
	reg [9:0]reg_ccm_level_green_left = 10'd0; // green 通道 left 像素矩阵输出码值
	reg [9:0]reg_ccm_level_green_center_left = 10'd0; // green 通道 center_left 像素矩阵输出码值
	reg [9:0]reg_ccm_level_green_center_right = 10'd0; // green 通道 center_right 像素矩阵输出码值
	reg [9:0]reg_ccm_level_green_right = 10'd0; // green 通道 right 像素矩阵输出码值
	reg [23:0]reg_ccm_first_blue_left = 24'd0; // blue 通道 left 像素矩阵首项
	reg [23:0]reg_ccm_first_blue_center_left = 24'd0; // blue 通道 center_left 像素矩阵首项
	reg [23:0]reg_ccm_first_blue_center_right = 24'd0; // blue 通道 center_right 像素矩阵首项
	reg [23:0]reg_ccm_first_blue_right = 24'd0; // blue 通道 right 像素矩阵首项
	reg [23:0]reg_ccm_second_blue_left = 24'd0; // blue 通道 left 像素矩阵次项
	reg [23:0]reg_ccm_second_blue_center_left = 24'd0; // blue 通道 center_left 像素矩阵次项
	reg [23:0]reg_ccm_second_blue_center_right = 24'd0; // blue 通道 center_right 像素矩阵次项
	reg [23:0]reg_ccm_second_blue_right = 24'd0; // blue 通道 right 像素矩阵次项
	reg [23:0]reg_ccm_third_blue_left = 24'd0; // blue 通道 left 像素矩阵末项
	reg [23:0]reg_ccm_third_blue_center_left = 24'd0; // blue 通道 center_left 像素矩阵末项
	reg [23:0]reg_ccm_third_blue_center_right = 24'd0; // blue 通道 center_right 像素矩阵末项
	reg [23:0]reg_ccm_third_blue_right = 24'd0; // blue 通道 right 像素矩阵末项
	reg [23:0]reg_ccm_partial_blue_left = 24'd0; // blue 通道 left 像素矩阵前两项和
	reg [23:0]reg_ccm_partial_blue_center_left = 24'd0; // blue 通道 center_left 像素矩阵前两项和
	reg [23:0]reg_ccm_partial_blue_center_right = 24'd0; // blue 通道 center_right 像素矩阵前两项和
	reg [23:0]reg_ccm_partial_blue_right = 24'd0; // blue 通道 right 像素矩阵前两项和
	reg [23:0]reg_ccm_third_hold_blue_left = 24'd0; // blue 通道 left 像素矩阵末项延迟值
	reg [23:0]reg_ccm_third_hold_blue_center_left = 24'd0; // blue 通道 center_left 像素矩阵末项延迟值
	reg [23:0]reg_ccm_third_hold_blue_center_right = 24'd0; // blue 通道 center_right 像素矩阵末项延迟值
	reg [23:0]reg_ccm_third_hold_blue_right = 24'd0; // blue 通道 right 像素矩阵末项延迟值
	reg [23:0]reg_ccm_total_blue_left = 24'd0; // blue 通道 left 像素矩阵三项和
	reg [23:0]reg_ccm_total_blue_center_left = 24'd0; // blue 通道 center_left 像素矩阵三项和
	reg [23:0]reg_ccm_total_blue_center_right = 24'd0; // blue 通道 center_right 像素矩阵三项和
	reg [23:0]reg_ccm_total_blue_right = 24'd0; // blue 通道 right 像素矩阵三项和
	reg [23:0]reg_ccm_round_blue_left = 24'd0; // blue 通道 left 像素矩阵圆整值
	reg [23:0]reg_ccm_round_blue_center_left = 24'd0; // blue 通道 center_left 像素矩阵圆整值
	reg [23:0]reg_ccm_round_blue_center_right = 24'd0; // blue 通道 center_right 像素矩阵圆整值
	reg [23:0]reg_ccm_round_blue_right = 24'd0; // blue 通道 right 像素矩阵圆整值
	reg [23:0]reg_ccm_shift_blue_left = 24'd0; // blue 通道 left 像素矩阵移位值
	reg [23:0]reg_ccm_shift_blue_center_left = 24'd0; // blue 通道 center_left 像素矩阵移位值
	reg [23:0]reg_ccm_shift_blue_center_right = 24'd0; // blue 通道 center_right 像素矩阵移位值
	reg [23:0]reg_ccm_shift_blue_right = 24'd0; // blue 通道 right 像素矩阵移位值
	reg [23:0]reg_ccm_delay_low_blue_left = 24'd0; // blue 通道 left 像素矩阵下钳位延迟值
	reg [23:0]reg_ccm_delay_low_blue_center_left = 24'd0; // blue 通道 center_left 像素矩阵下钳位延迟值
	reg [23:0]reg_ccm_delay_low_blue_center_right = 24'd0; // blue 通道 center_right 像素矩阵下钳位延迟值
	reg [23:0]reg_ccm_delay_low_blue_right = 24'd0; // blue 通道 right 像素矩阵下钳位延迟值
	reg [23:0]reg_ccm_low_blue_left = 24'd0; // blue 通道 left 像素矩阵下钳位值
	reg [23:0]reg_ccm_low_blue_center_left = 24'd0; // blue 通道 center_left 像素矩阵下钳位值
	reg [23:0]reg_ccm_low_blue_center_right = 24'd0; // blue 通道 center_right 像素矩阵下钳位值
	reg [23:0]reg_ccm_low_blue_right = 24'd0; // blue 通道 right 像素矩阵下钳位值
	reg [23:0]reg_ccm_delay_level_blue_left = 24'd0; // blue 通道 left 像素矩阵上钳位延迟值
	reg [23:0]reg_ccm_delay_level_blue_center_left = 24'd0; // blue 通道 center_left 像素矩阵上钳位延迟值
	reg [23:0]reg_ccm_delay_level_blue_center_right = 24'd0; // blue 通道 center_right 像素矩阵上钳位延迟值
	reg [23:0]reg_ccm_delay_level_blue_right = 24'd0; // blue 通道 right 像素矩阵上钳位延迟值
	reg [9:0]reg_ccm_level_blue_left = 10'd0; // blue 通道 left 像素矩阵输出码值
	reg [9:0]reg_ccm_level_blue_center_left = 10'd0; // blue 通道 center_left 像素矩阵输出码值
	reg [9:0]reg_ccm_level_blue_center_right = 10'd0; // blue 通道 center_right 像素矩阵输出码值
	reg [9:0]reg_ccm_level_blue_right = 10'd0; // blue 通道 right 像素矩阵输出码值
	reg [23:0]reg_pack_lane_left = 24'd0; // left 像素打包值
	reg [23:0]reg_pack_lane_center_left = 24'd0; // center_left 像素打包值
	reg [23:0]reg_pack_lane_center_right = 24'd0; // center_right 像素打包值
	reg [23:0]reg_pack_lane_right = 24'd0; // right 像素打包值
	reg [47:0]reg_pack_low = 48'd0; // 低半幅打包值
	reg [47:0]reg_pack_high = 48'd0; // 高半幅打包值
	reg [95:0]reg_word_output = 96'd0; // 输出 beat 数据缓存
	reg [95:0]reg_word_final = 96'd0; // 输出 beat 数据末级缓存
	reg [2:0]reg_ctrl_stagealpha = 3'd0; // 第2级流水控制位缓存
	reg [2:0]reg_ctrl_stagebravo = 3'd0; // 第3级流水控制位缓存
	reg [2:0]reg_ctrl_stagecharlie = 3'd0; // 第4级流水控制位缓存
	reg [2:0]reg_ctrl_stagedelta = 3'd0; // 第5级流水控制位缓存
	reg [2:0]reg_ctrl_stageecho = 3'd0; // 第6级流水控制位缓存
	reg [2:0]reg_ctrl_stagefoxtrot = 3'd0; // 第7级流水控制位缓存
	reg [2:0]reg_ctrl_stagegolf = 3'd0; // 第8级流水控制位缓存
	reg [2:0]reg_ctrl_stagehotel = 3'd0; // 第9级流水控制位缓存
	reg [2:0]reg_ctrl_stageindia = 3'd0; // 第10级流水控制位缓存
	reg [2:0]reg_ctrl_stagejuliet = 3'd0; // 第11级流水控制位缓存
	reg [2:0]reg_ctrl_stagekilo = 3'd0; // 第12级流水控制位缓存
	reg [2:0]reg_ctrl_stagelima = 3'd0; // 第13级流水控制位缓存
	reg [2:0]reg_ctrl_stagemike = 3'd0; // 第14级流水控制位缓存
	reg [2:0]reg_ctrl_stagenovember = 3'd0; // 第15级流水控制位缓存
	reg [2:0]reg_ctrl_stageoscar = 3'd0; // 第16级流水控制位缓存
	reg [2:0]reg_ctrl_stagepapa = 3'd0; // 第17级流水控制位缓存
	reg [2:0]reg_ctrl_stagequebec = 3'd0; // 第18级流水控制位缓存
	reg [2:0]reg_ctrl_stageromeo = 3'd0; // 第19级流水控制位缓存
	reg [2:0]reg_ctrl_stagesierra = 3'd0; // 第20级流水控制位缓存
	reg [2:0]reg_ctrl_stagetango = 3'd0; // 第21级流水控制位缓存

	//-----------------标志信号-----------------//
	reg flag_wb_over_red_left = 1'b0; // red 通道 left 像素白平衡饱和标志
	reg flag_wb_over_red_center_left = 1'b0; // red 通道 center_left 像素白平衡饱和标志
	reg flag_wb_over_red_center_right = 1'b0; // red 通道 center_right 像素白平衡饱和标志
	reg flag_wb_over_red_right = 1'b0; // red 通道 right 像素白平衡饱和标志
	reg flag_wb_over_green_left = 1'b0; // green 通道 left 像素白平衡饱和标志
	reg flag_wb_over_green_center_left = 1'b0; // green 通道 center_left 像素白平衡饱和标志
	reg flag_wb_over_green_center_right = 1'b0; // green 通道 center_right 像素白平衡饱和标志
	reg flag_wb_over_green_right = 1'b0; // green 通道 right 像素白平衡饱和标志
	reg flag_wb_over_blue_left = 1'b0; // blue 通道 left 像素白平衡饱和标志
	reg flag_wb_over_blue_center_left = 1'b0; // blue 通道 center_left 像素白平衡饱和标志
	reg flag_wb_over_blue_center_right = 1'b0; // blue 通道 center_right 像素白平衡饱和标志
	reg flag_wb_over_blue_right = 1'b0; // blue 通道 right 像素白平衡饱和标志
	reg flag_wb_pair_left = 1'b0; // left 像素红绿通道白平衡饱和归并标志
	reg flag_wb_pair_center_left = 1'b0; // center_left 像素红绿通道白平衡饱和归并标志
	reg flag_wb_pair_center_right = 1'b0; // center_right 像素红绿通道白平衡饱和归并标志
	reg flag_wb_pair_right = 1'b0; // right 像素红绿通道白平衡饱和归并标志
	reg flag_wb_blue_left = 1'b0; // left 像素蓝通道白平衡饱和延迟标志
	reg flag_wb_blue_center_left = 1'b0; // center_left 像素蓝通道白平衡饱和延迟标志
	reg flag_wb_blue_center_right = 1'b0; // center_right 像素蓝通道白平衡饱和延迟标志
	reg flag_wb_blue_right = 1'b0; // right 像素蓝通道白平衡饱和延迟标志
	reg flag_wb_lane_left = 1'b0; // left 像素白平衡饱和归并标志
	reg flag_wb_lane_center_left = 1'b0; // center_left 像素白平衡饱和归并标志
	reg flag_wb_lane_center_right = 1'b0; // center_right 像素白平衡饱和归并标志
	reg flag_wb_lane_right = 1'b0; // right 像素白平衡饱和归并标志
	reg flag_wb_group_low = 1'b0; // 低半幅白平衡饱和归并标志
	reg flag_wb_group_high = 1'b0; // 高半幅白平衡饱和归并标志
	reg flag_wb_beat = 1'b0; // 白平衡饱和 beat 标志
	reg flag_ccm_low_red_left = 1'b0; // red 通道 left 像素矩阵下溢标志
	reg flag_ccm_low_red_center_left = 1'b0; // red 通道 center_left 像素矩阵下溢标志
	reg flag_ccm_low_red_center_right = 1'b0; // red 通道 center_right 像素矩阵下溢标志
	reg flag_ccm_low_red_right = 1'b0; // red 通道 right 像素矩阵下溢标志
	reg flag_ccm_low_hold_first_red_left = 1'b0; // red 通道 left 像素矩阵下溢延迟标志
	reg flag_ccm_low_hold_first_red_center_left = 1'b0; // red 通道 center_left 像素矩阵下溢延迟标志
	reg flag_ccm_low_hold_first_red_center_right = 1'b0; // red 通道 center_right 像素矩阵下溢延迟标志
	reg flag_ccm_low_hold_first_red_right = 1'b0; // red 通道 right 像素矩阵下溢延迟标志
	reg flag_ccm_high_red_left = 1'b0; // red 通道 left 像素矩阵上溢标志
	reg flag_ccm_high_red_center_left = 1'b0; // red 通道 center_left 像素矩阵上溢标志
	reg flag_ccm_high_red_center_right = 1'b0; // red 通道 center_right 像素矩阵上溢标志
	reg flag_ccm_high_red_right = 1'b0; // red 通道 right 像素矩阵上溢标志
	reg flag_ccm_low_hold_second_red_left = 1'b0; // red 通道 left 像素矩阵下溢二次延迟标志
	reg flag_ccm_low_hold_second_red_center_left = 1'b0; // red 通道 center_left 像素矩阵下溢二次延迟标志
	reg flag_ccm_low_hold_second_red_center_right = 1'b0; // red 通道 center_right 像素矩阵下溢二次延迟标志
	reg flag_ccm_low_hold_second_red_right = 1'b0; // red 通道 right 像素矩阵下溢二次延迟标志
	reg flag_ccm_channel_red_left = 1'b0; // red 通道 left 像素矩阵饱和标志
	reg flag_ccm_channel_red_center_left = 1'b0; // red 通道 center_left 像素矩阵饱和标志
	reg flag_ccm_channel_red_center_right = 1'b0; // red 通道 center_right 像素矩阵饱和标志
	reg flag_ccm_channel_red_right = 1'b0; // red 通道 right 像素矩阵饱和标志
	reg flag_ccm_low_green_left = 1'b0; // green 通道 left 像素矩阵下溢标志
	reg flag_ccm_low_green_center_left = 1'b0; // green 通道 center_left 像素矩阵下溢标志
	reg flag_ccm_low_green_center_right = 1'b0; // green 通道 center_right 像素矩阵下溢标志
	reg flag_ccm_low_green_right = 1'b0; // green 通道 right 像素矩阵下溢标志
	reg flag_ccm_low_hold_first_green_left = 1'b0; // green 通道 left 像素矩阵下溢延迟标志
	reg flag_ccm_low_hold_first_green_center_left = 1'b0; // green 通道 center_left 像素矩阵下溢延迟标志
	reg flag_ccm_low_hold_first_green_center_right = 1'b0; // green 通道 center_right 像素矩阵下溢延迟标志
	reg flag_ccm_low_hold_first_green_right = 1'b0; // green 通道 right 像素矩阵下溢延迟标志
	reg flag_ccm_high_green_left = 1'b0; // green 通道 left 像素矩阵上溢标志
	reg flag_ccm_high_green_center_left = 1'b0; // green 通道 center_left 像素矩阵上溢标志
	reg flag_ccm_high_green_center_right = 1'b0; // green 通道 center_right 像素矩阵上溢标志
	reg flag_ccm_high_green_right = 1'b0; // green 通道 right 像素矩阵上溢标志
	reg flag_ccm_low_hold_second_green_left = 1'b0; // green 通道 left 像素矩阵下溢二次延迟标志
	reg flag_ccm_low_hold_second_green_center_left = 1'b0; // green 通道 center_left 像素矩阵下溢二次延迟标志
	reg flag_ccm_low_hold_second_green_center_right = 1'b0; // green 通道 center_right 像素矩阵下溢二次延迟标志
	reg flag_ccm_low_hold_second_green_right = 1'b0; // green 通道 right 像素矩阵下溢二次延迟标志
	reg flag_ccm_channel_green_left = 1'b0; // green 通道 left 像素矩阵饱和标志
	reg flag_ccm_channel_green_center_left = 1'b0; // green 通道 center_left 像素矩阵饱和标志
	reg flag_ccm_channel_green_center_right = 1'b0; // green 通道 center_right 像素矩阵饱和标志
	reg flag_ccm_channel_green_right = 1'b0; // green 通道 right 像素矩阵饱和标志
	reg flag_ccm_low_blue_left = 1'b0; // blue 通道 left 像素矩阵下溢标志
	reg flag_ccm_low_blue_center_left = 1'b0; // blue 通道 center_left 像素矩阵下溢标志
	reg flag_ccm_low_blue_center_right = 1'b0; // blue 通道 center_right 像素矩阵下溢标志
	reg flag_ccm_low_blue_right = 1'b0; // blue 通道 right 像素矩阵下溢标志
	reg flag_ccm_low_hold_first_blue_left = 1'b0; // blue 通道 left 像素矩阵下溢延迟标志
	reg flag_ccm_low_hold_first_blue_center_left = 1'b0; // blue 通道 center_left 像素矩阵下溢延迟标志
	reg flag_ccm_low_hold_first_blue_center_right = 1'b0; // blue 通道 center_right 像素矩阵下溢延迟标志
	reg flag_ccm_low_hold_first_blue_right = 1'b0; // blue 通道 right 像素矩阵下溢延迟标志
	reg flag_ccm_high_blue_left = 1'b0; // blue 通道 left 像素矩阵上溢标志
	reg flag_ccm_high_blue_center_left = 1'b0; // blue 通道 center_left 像素矩阵上溢标志
	reg flag_ccm_high_blue_center_right = 1'b0; // blue 通道 center_right 像素矩阵上溢标志
	reg flag_ccm_high_blue_right = 1'b0; // blue 通道 right 像素矩阵上溢标志
	reg flag_ccm_low_hold_second_blue_left = 1'b0; // blue 通道 left 像素矩阵下溢二次延迟标志
	reg flag_ccm_low_hold_second_blue_center_left = 1'b0; // blue 通道 center_left 像素矩阵下溢二次延迟标志
	reg flag_ccm_low_hold_second_blue_center_right = 1'b0; // blue 通道 center_right 像素矩阵下溢二次延迟标志
	reg flag_ccm_low_hold_second_blue_right = 1'b0; // blue 通道 right 像素矩阵下溢二次延迟标志
	reg flag_ccm_channel_blue_left = 1'b0; // blue 通道 left 像素矩阵饱和标志
	reg flag_ccm_channel_blue_center_left = 1'b0; // blue 通道 center_left 像素矩阵饱和标志
	reg flag_ccm_channel_blue_center_right = 1'b0; // blue 通道 center_right 像素矩阵饱和标志
	reg flag_ccm_channel_blue_right = 1'b0; // blue 通道 right 像素矩阵饱和标志
	reg flag_ccm_pair_left = 1'b0; // left 像素红绿通道矩阵饱和归并标志
	reg flag_ccm_pair_center_left = 1'b0; // center_left 像素红绿通道矩阵饱和归并标志
	reg flag_ccm_pair_center_right = 1'b0; // center_right 像素红绿通道矩阵饱和归并标志
	reg flag_ccm_pair_right = 1'b0; // right 像素红绿通道矩阵饱和归并标志
	reg flag_ccm_blue_left = 1'b0; // left 像素蓝通道矩阵饱和延迟标志
	reg flag_ccm_blue_center_left = 1'b0; // center_left 像素蓝通道矩阵饱和延迟标志
	reg flag_ccm_blue_center_right = 1'b0; // center_right 像素蓝通道矩阵饱和延迟标志
	reg flag_ccm_blue_right = 1'b0; // right 像素蓝通道矩阵饱和延迟标志
	reg flag_ccm_lane_left = 1'b0; // left 像素矩阵饱和归并标志
	reg flag_ccm_lane_center_left = 1'b0; // center_left 像素矩阵饱和归并标志
	reg flag_ccm_lane_center_right = 1'b0; // center_right 像素矩阵饱和归并标志
	reg flag_ccm_lane_right = 1'b0; // right 像素矩阵饱和归并标志
	reg flag_ccm_group_low = 1'b0; // 低半幅矩阵饱和归并标志
	reg flag_ccm_group_high = 1'b0; // 高半幅矩阵饱和归并标志
	reg flag_ccm_beat = 1'b0; // 矩阵饱和 beat 标志
	reg flag_wb_pendingalpha = 1'b0; // 白平衡饱和标志第1级延迟
	reg flag_wb_pendingbravo = 1'b0; // 白平衡饱和标志第2级延迟
	reg flag_wb_pendingcharlie = 1'b0; // 白平衡饱和标志第3级延迟
	reg flag_wb_pendingdelta = 1'b0; // 白平衡饱和标志第4级延迟
	reg flag_wb_pendingecho = 1'b0; // 白平衡饱和标志第5级延迟
	reg flag_wb_pendingfoxtrot = 1'b0; // 白平衡饱和标志第6级延迟
	reg flag_wb_pendinggolf = 1'b0; // 白平衡饱和标志第7级延迟
	reg flag_wb_pendinghotel = 1'b0; // 白平衡饱和标志第8级延迟
	reg flag_wb_pendingindia = 1'b0; // 白平衡饱和标志第9级延迟
	reg flag_wb_pendingjuliet = 1'b0; // 白平衡饱和标志第10级延迟
	reg flag_sat_output = 1'b0; // 输出 beat 饱和标志
	reg flag_transfer = 1'b0; // 输出 beat 传输事件
	reg flag_user_snapshot = 1'b0; // 输出帧首快照
	reg flag_sat_snapshot = 1'b0; // 输出饱和快照
	reg flag_frame_event = 1'b0; // 帧起始事件
	reg flag_sat_event = 1'b0; // 饱和 beat 事件

	//-----------------计数信号-----------------//
	reg [31:0]cnt_beat_total = 32'd0; // 累计已传输 beat 数
	reg [31:0]cnt_frame_start_total = 32'd0; // 累计帧起始数
	reg [31:0]cnt_saturate_total = 32'd0; // 累计饱和 beat 数

	//-----------------其他信号-----------------//
	wire [2:0]data_input_ctrl; // 输入 beat 控制位组装
	wire [7:0]data_gamma_red_left; // red 通道 left 查表结果
	wire [7:0]data_gamma_red_center_left; // red 通道 center_left 查表结果
	wire [7:0]data_gamma_red_center_right; // red 通道 center_right 查表结果
	wire [7:0]data_gamma_red_right; // red 通道 right 查表结果
	wire [7:0]data_gamma_green_left; // green 通道 left 查表结果
	wire [7:0]data_gamma_green_center_left; // green 通道 center_left 查表结果
	wire [7:0]data_gamma_green_center_right; // green 通道 center_right 查表结果
	wire [7:0]data_gamma_green_right; // green 通道 right 查表结果
	wire [7:0]data_gamma_blue_left; // blue 通道 left 查表结果
	wire [7:0]data_gamma_blue_center_left; // blue 通道 center_left 查表结果
	wire [7:0]data_gamma_blue_center_right; // blue 通道 center_right 查表结果
	wire [7:0]data_gamma_blue_right; // blue 通道 right 查表结果
	wire flag_wb_saturate; // 白平衡饱和 beat 末级标志
	wire flag_saturation; // 输出 beat 饱和归并标志
	wire flag_freeze; // 流水停顿条件
	wire data_user_output; // 输出帧首掩码值
	wire data_last_output; // 输出行尾掩码值

	//-----------------输出信号-----------------//
	wire flag_freeze_o; // 流水停顿桥接值

	//---------------其他信号连线---------------//
	assign data_input_ctrl = {i_s_axis_tvalid, i_s_axis_tuser, i_s_axis_tlast}; // 按序组装有效帧首与行尾位
	assign flag_wb_saturate = flag_wb_pendingjuliet; // 取白平衡饱和末级延迟值
	assign flag_saturation = flag_wb_saturate | flag_ccm_beat; // 归并白平衡与矩阵饱和
	assign flag_freeze = reg_ctrl_stagetango[2] & (~i_m_axis_tready); // 输出未被取走时立即停顿流水
	assign flag_freeze_o = ~flag_freeze; // 停顿取反得到输入就绪
	assign data_user_output = reg_ctrl_stagetango[1] & reg_ctrl_stagetango[2]; // 无有效时清零帧首
	assign data_last_output = reg_ctrl_stagetango[0] & reg_ctrl_stagetango[2]; // 无有效时清零行尾

	//---------------输出信号连线---------------//
	assign o_s_axis_tready = flag_freeze_o; // 输出输入就绪
	assign o_m_axis_tdata = reg_word_final; // 输出 beat 数据
	assign o_m_axis_tvalid = reg_ctrl_stagetango[2]; // 输出 beat 有效
	assign o_m_axis_tuser = data_user_output; // 输出帧首
	assign o_m_axis_tlast = data_last_output; // 输出行尾
	assign o_stat_beat_total = cnt_beat_total; // 输出累计 beat 数
	assign o_stat_frame_total = cnt_frame_start_total; // 输出累计帧起始数
	assign o_stat_saturate_total = cnt_saturate_total; // 输出累计饱和 beat 数

	//-------------输出信号处理区域-------------//
	//输出 beat 数据末级缓存更新逻辑
	always@(posedge i_clk)begin
		if(i_rstn == 1'b0)begin
			reg_word_final <= 96'd0; // 复位清空末级 beat 数据
		end else begin
			case(flag_freeze)
				1'b1:begin
					reg_word_final <= reg_word_final; // 输出未取走时保持本级
				end
				default:begin
					reg_word_final <= reg_word_output; // 对齐输出控制位
				end
			endcase
		end
	end

	//输出 beat 饱和标志更新逻辑
	always@(posedge i_clk)begin
		if(i_rstn == 1'b0)begin
			flag_sat_output <= 1'b0; // 复位清除饱和标志
		end else begin
			case(flag_freeze)
				1'b1:begin
					flag_sat_output <= flag_sat_output; // 输出未取走时保持本级
				end
				default:begin
					flag_sat_output <= flag_saturation; // 缓存 beat 饱和结果
				end
			endcase
		end
	end

	//输出 beat 传输事件更新逻辑
	always@(posedge i_clk)begin
		if(i_rstn == 1'b0)begin
			flag_transfer <= 1'b0; // 复位清除传输事件
		end else begin
			case(flag_freeze)
				1'b1:begin
					flag_transfer <= flag_transfer; // 输出未取走时保持本级
				end
				default:begin
					flag_transfer <= reg_ctrl_stagetango[2] & i_m_axis_tready; // 采样有效与下游就绪
				end
			endcase
		end
	end

	//输出帧首快照更新逻辑
	always@(posedge i_clk)begin
		if(i_rstn == 1'b0)begin
			flag_user_snapshot <= 1'b0; // 复位清除帧首快照
		end else begin
			case(flag_freeze)
				1'b1:begin
					flag_user_snapshot <= flag_user_snapshot; // 输出未取走时保持本级
				end
				default:begin
					flag_user_snapshot <= reg_ctrl_stagetango[1]; // 采样当前帧首位
				end
			endcase
		end
	end

	//输出饱和快照更新逻辑
	always@(posedge i_clk)begin
		if(i_rstn == 1'b0)begin
			flag_sat_snapshot <= 1'b0; // 复位清除饱和快照
		end else begin
			case(flag_freeze)
				1'b1:begin
					flag_sat_snapshot <= flag_sat_snapshot; // 输出未取走时保持本级
				end
				default:begin
					flag_sat_snapshot <= flag_sat_output; // 采样当前饱和位
				end
			endcase
		end
	end

	//帧起始事件更新逻辑
	always@(posedge i_clk)begin
		if(i_rstn == 1'b0)begin
			flag_frame_event <= 1'b0; // 复位清除帧起始事件
		end else begin
			case(flag_freeze)
				1'b1:begin
					flag_frame_event <= flag_frame_event; // 输出未取走时保持本级
				end
				default:begin
					flag_frame_event <= flag_transfer & flag_user_snapshot; // 传输且帧首时计帧开始
				end
			endcase
		end
	end

	//饱和 beat 事件更新逻辑
	always@(posedge i_clk)begin
		if(i_rstn == 1'b0)begin
			flag_sat_event <= 1'b0; // 复位清除饱和事件
		end else begin
			case(flag_freeze)
				1'b1:begin
					flag_sat_event <= flag_sat_event; // 输出未取走时保持本级
				end
				default:begin
					flag_sat_event <= flag_transfer & flag_sat_snapshot; // 传输且饱和时计饱和 beat
				end
			endcase
		end
	end

	//累计已传输 beat 数更新逻辑
	always@(posedge i_clk)begin
		if(i_rstn == 1'b0)begin
			cnt_beat_total <= 32'd0; // 复位清空 beat 计数
		end else begin
			case(flag_freeze)
				1'b1:begin
					cnt_beat_total <= cnt_beat_total; // 输出未取走时保持本级
				end
				default:begin
					cnt_beat_total <= cnt_beat_total + flag_transfer; // 仅在传输时累加
				end
			endcase
		end
	end

	//累计帧起始数更新逻辑
	always@(posedge i_clk)begin
		if(i_rstn == 1'b0)begin
			cnt_frame_start_total <= 32'd0; // 复位清空帧起始计数
		end else begin
			case(flag_freeze)
				1'b1:begin
					cnt_frame_start_total <= cnt_frame_start_total; // 输出未取走时保持本级
				end
				default:begin
					cnt_frame_start_total <= cnt_frame_start_total + flag_frame_event; // 仅在帧首传输时累加
				end
			endcase
		end
	end

	//累计饱和 beat 数更新逻辑
	always@(posedge i_clk)begin
		if(i_rstn == 1'b0)begin
			cnt_saturate_total <= 32'd0; // 复位清空饱和计数
		end else begin
			case(flag_freeze)
				1'b1:begin
					cnt_saturate_total <= cnt_saturate_total; // 输出未取走时保持本级
				end
				default:begin
					cnt_saturate_total <= cnt_saturate_total + flag_sat_event; // 仅在饱和传输时累加
				end
			endcase
		end
	end
	//-------------主要任务处理区域-------------//
	//输入 beat 数据缓存更新逻辑
	always@(posedge i_clk)begin
		if(i_rstn == 1'b0)begin
			reg_word_input <= 120'd0; // 复位清空输入 beat 数据
		end else begin
			case(flag_freeze)
				1'b1:begin
					reg_word_input <= reg_word_input; // 下游未取走时保持输入数据
				end
				default:begin
					reg_word_input <= i_s_axis_tdata; // 非拥塞时采样输入 beat 数据
				end
			endcase
		end
	end

	//输入 beat 控制位缓存更新逻辑
	always@(posedge i_clk)begin
		if(i_rstn == 1'b0)begin
			reg_ctrl_input <= 3'd0; // 复位清空输入控制位
		end else begin
			case(flag_freeze)
				1'b1:begin
					reg_ctrl_input <= reg_ctrl_input; // 下游未取走时保持控制位
				end
				default:begin
					reg_ctrl_input <= data_input_ctrl; // 非拥塞时采样帧首行尾与有效位
				end
			endcase
		end
	end

	//red 通道 left 像素输入码值更新逻辑
	always@(posedge i_clk)begin
		if(i_rstn == 1'b0)begin
			reg_in_red_left <= 10'd0; // 复位清空输入码值
		end else begin
			case(flag_freeze)
				1'b1:begin
					reg_in_red_left <= reg_in_red_left; // 输出未取走时保持本级
				end
				default:begin
					reg_in_red_left <= reg_word_input[29:20]; // 解包输入 beat 的码值
				end
			endcase
		end
	end

	//red 通道 center_left 像素输入码值更新逻辑
	always@(posedge i_clk)begin
		if(i_rstn == 1'b0)begin
			reg_in_red_center_left <= 10'd0; // 复位清空输入码值
		end else begin
			case(flag_freeze)
				1'b1:begin
					reg_in_red_center_left <= reg_in_red_center_left; // 输出未取走时保持本级
				end
				default:begin
					reg_in_red_center_left <= reg_word_input[59:50]; // 解包输入 beat 的码值
				end
			endcase
		end
	end

	//red 通道 center_right 像素输入码值更新逻辑
	always@(posedge i_clk)begin
		if(i_rstn == 1'b0)begin
			reg_in_red_center_right <= 10'd0; // 复位清空输入码值
		end else begin
			case(flag_freeze)
				1'b1:begin
					reg_in_red_center_right <= reg_in_red_center_right; // 输出未取走时保持本级
				end
				default:begin
					reg_in_red_center_right <= reg_word_input[89:80]; // 解包输入 beat 的码值
				end
			endcase
		end
	end

	//red 通道 right 像素输入码值更新逻辑
	always@(posedge i_clk)begin
		if(i_rstn == 1'b0)begin
			reg_in_red_right <= 10'd0; // 复位清空输入码值
		end else begin
			case(flag_freeze)
				1'b1:begin
					reg_in_red_right <= reg_in_red_right; // 输出未取走时保持本级
				end
				default:begin
					reg_in_red_right <= reg_word_input[119:110]; // 解包输入 beat 的码值
				end
			endcase
		end
	end

	//green 通道 left 像素输入码值更新逻辑
	always@(posedge i_clk)begin
		if(i_rstn == 1'b0)begin
			reg_in_green_left <= 10'd0; // 复位清空输入码值
		end else begin
			case(flag_freeze)
				1'b1:begin
					reg_in_green_left <= reg_in_green_left; // 输出未取走时保持本级
				end
				default:begin
					reg_in_green_left <= reg_word_input[19:10]; // 解包输入 beat 的码值
				end
			endcase
		end
	end

	//green 通道 center_left 像素输入码值更新逻辑
	always@(posedge i_clk)begin
		if(i_rstn == 1'b0)begin
			reg_in_green_center_left <= 10'd0; // 复位清空输入码值
		end else begin
			case(flag_freeze)
				1'b1:begin
					reg_in_green_center_left <= reg_in_green_center_left; // 输出未取走时保持本级
				end
				default:begin
					reg_in_green_center_left <= reg_word_input[49:40]; // 解包输入 beat 的码值
				end
			endcase
		end
	end

	//green 通道 center_right 像素输入码值更新逻辑
	always@(posedge i_clk)begin
		if(i_rstn == 1'b0)begin
			reg_in_green_center_right <= 10'd0; // 复位清空输入码值
		end else begin
			case(flag_freeze)
				1'b1:begin
					reg_in_green_center_right <= reg_in_green_center_right; // 输出未取走时保持本级
				end
				default:begin
					reg_in_green_center_right <= reg_word_input[79:70]; // 解包输入 beat 的码值
				end
			endcase
		end
	end

	//green 通道 right 像素输入码值更新逻辑
	always@(posedge i_clk)begin
		if(i_rstn == 1'b0)begin
			reg_in_green_right <= 10'd0; // 复位清空输入码值
		end else begin
			case(flag_freeze)
				1'b1:begin
					reg_in_green_right <= reg_in_green_right; // 输出未取走时保持本级
				end
				default:begin
					reg_in_green_right <= reg_word_input[109:100]; // 解包输入 beat 的码值
				end
			endcase
		end
	end

	//blue 通道 left 像素输入码值更新逻辑
	always@(posedge i_clk)begin
		if(i_rstn == 1'b0)begin
			reg_in_blue_left <= 10'd0; // 复位清空输入码值
		end else begin
			case(flag_freeze)
				1'b1:begin
					reg_in_blue_left <= reg_in_blue_left; // 输出未取走时保持本级
				end
				default:begin
					reg_in_blue_left <= reg_word_input[9:0]; // 解包输入 beat 的码值
				end
			endcase
		end
	end

	//blue 通道 center_left 像素输入码值更新逻辑
	always@(posedge i_clk)begin
		if(i_rstn == 1'b0)begin
			reg_in_blue_center_left <= 10'd0; // 复位清空输入码值
		end else begin
			case(flag_freeze)
				1'b1:begin
					reg_in_blue_center_left <= reg_in_blue_center_left; // 输出未取走时保持本级
				end
				default:begin
					reg_in_blue_center_left <= reg_word_input[39:30]; // 解包输入 beat 的码值
				end
			endcase
		end
	end

	//blue 通道 center_right 像素输入码值更新逻辑
	always@(posedge i_clk)begin
		if(i_rstn == 1'b0)begin
			reg_in_blue_center_right <= 10'd0; // 复位清空输入码值
		end else begin
			case(flag_freeze)
				1'b1:begin
					reg_in_blue_center_right <= reg_in_blue_center_right; // 输出未取走时保持本级
				end
				default:begin
					reg_in_blue_center_right <= reg_word_input[69:60]; // 解包输入 beat 的码值
				end
			endcase
		end
	end

	//blue 通道 right 像素输入码值更新逻辑
	always@(posedge i_clk)begin
		if(i_rstn == 1'b0)begin
			reg_in_blue_right <= 10'd0; // 复位清空输入码值
		end else begin
			case(flag_freeze)
				1'b1:begin
					reg_in_blue_right <= reg_in_blue_right; // 输出未取走时保持本级
				end
				default:begin
					reg_in_blue_right <= reg_word_input[99:90]; // 解包输入 beat 的码值
				end
			endcase
		end
	end

	//red 通道 left 像素白平衡乘积更新逻辑
	always@(posedge i_clk)begin
		if(i_rstn == 1'b0)begin
			reg_wb_product_red_left <= 20'd0; // 复位清空白平衡乘积
		end else begin
			case(flag_freeze)
				1'b1:begin
					reg_wb_product_red_left <= reg_wb_product_red_left; // 输出未取走时保持本级
				end
				default:begin
					reg_wb_product_red_left <= reg_in_red_left * C_WB_GAIN_R; // 定点增益相乘
				end
			endcase
		end
	end

	//red 通道 center_left 像素白平衡乘积更新逻辑
	always@(posedge i_clk)begin
		if(i_rstn == 1'b0)begin
			reg_wb_product_red_center_left <= 20'd0; // 复位清空白平衡乘积
		end else begin
			case(flag_freeze)
				1'b1:begin
					reg_wb_product_red_center_left <= reg_wb_product_red_center_left; // 输出未取走时保持本级
				end
				default:begin
					reg_wb_product_red_center_left <= reg_in_red_center_left * C_WB_GAIN_R; // 定点增益相乘
				end
			endcase
		end
	end

	//red 通道 center_right 像素白平衡乘积更新逻辑
	always@(posedge i_clk)begin
		if(i_rstn == 1'b0)begin
			reg_wb_product_red_center_right <= 20'd0; // 复位清空白平衡乘积
		end else begin
			case(flag_freeze)
				1'b1:begin
					reg_wb_product_red_center_right <= reg_wb_product_red_center_right; // 输出未取走时保持本级
				end
				default:begin
					reg_wb_product_red_center_right <= reg_in_red_center_right * C_WB_GAIN_R; // 定点增益相乘
				end
			endcase
		end
	end

	//red 通道 right 像素白平衡乘积更新逻辑
	always@(posedge i_clk)begin
		if(i_rstn == 1'b0)begin
			reg_wb_product_red_right <= 20'd0; // 复位清空白平衡乘积
		end else begin
			case(flag_freeze)
				1'b1:begin
					reg_wb_product_red_right <= reg_wb_product_red_right; // 输出未取走时保持本级
				end
				default:begin
					reg_wb_product_red_right <= reg_in_red_right * C_WB_GAIN_R; // 定点增益相乘
				end
			endcase
		end
	end

	//red 通道 left 像素白平衡圆整值更新逻辑
	always@(posedge i_clk)begin
		if(i_rstn == 1'b0)begin
			reg_wb_round_red_left <= 20'd0; // 复位清空白平衡圆整值
		end else begin
			case(flag_freeze)
				1'b1:begin
					reg_wb_round_red_left <= reg_wb_round_red_left; // 输出未取走时保持本级
				end
				default:begin
					reg_wb_round_red_left <= reg_wb_product_red_left + WB_ROUND_VALUE[19:0]; // 叠加圆整常量
				end
			endcase
		end
	end

	//red 通道 center_left 像素白平衡圆整值更新逻辑
	always@(posedge i_clk)begin
		if(i_rstn == 1'b0)begin
			reg_wb_round_red_center_left <= 20'd0; // 复位清空白平衡圆整值
		end else begin
			case(flag_freeze)
				1'b1:begin
					reg_wb_round_red_center_left <= reg_wb_round_red_center_left; // 输出未取走时保持本级
				end
				default:begin
					reg_wb_round_red_center_left <= reg_wb_product_red_center_left + WB_ROUND_VALUE[19:0]; // 叠加圆整常量
				end
			endcase
		end
	end

	//red 通道 center_right 像素白平衡圆整值更新逻辑
	always@(posedge i_clk)begin
		if(i_rstn == 1'b0)begin
			reg_wb_round_red_center_right <= 20'd0; // 复位清空白平衡圆整值
		end else begin
			case(flag_freeze)
				1'b1:begin
					reg_wb_round_red_center_right <= reg_wb_round_red_center_right; // 输出未取走时保持本级
				end
				default:begin
					reg_wb_round_red_center_right <= reg_wb_product_red_center_right + WB_ROUND_VALUE[19:0]; // 叠加圆整常量
				end
			endcase
		end
	end

	//red 通道 right 像素白平衡圆整值更新逻辑
	always@(posedge i_clk)begin
		if(i_rstn == 1'b0)begin
			reg_wb_round_red_right <= 20'd0; // 复位清空白平衡圆整值
		end else begin
			case(flag_freeze)
				1'b1:begin
					reg_wb_round_red_right <= reg_wb_round_red_right; // 输出未取走时保持本级
				end
				default:begin
					reg_wb_round_red_right <= reg_wb_product_red_right + WB_ROUND_VALUE[19:0]; // 叠加圆整常量
				end
			endcase
		end
	end

	//red 通道 left 像素白平衡缩放值更新逻辑
	always@(posedge i_clk)begin
		if(i_rstn == 1'b0)begin
			reg_wb_scale_red_left <= 20'd0; // 复位清空白平衡缩放值
		end else begin
			case(flag_freeze)
				1'b1:begin
					reg_wb_scale_red_left <= reg_wb_scale_red_left; // 输出未取走时保持本级
				end
				default:begin
					reg_wb_scale_red_left <= reg_wb_round_red_left >> C_WB_SHIFT; // 右移定点小数位
				end
			endcase
		end
	end

	//red 通道 center_left 像素白平衡缩放值更新逻辑
	always@(posedge i_clk)begin
		if(i_rstn == 1'b0)begin
			reg_wb_scale_red_center_left <= 20'd0; // 复位清空白平衡缩放值
		end else begin
			case(flag_freeze)
				1'b1:begin
					reg_wb_scale_red_center_left <= reg_wb_scale_red_center_left; // 输出未取走时保持本级
				end
				default:begin
					reg_wb_scale_red_center_left <= reg_wb_round_red_center_left >> C_WB_SHIFT; // 右移定点小数位
				end
			endcase
		end
	end

	//red 通道 center_right 像素白平衡缩放值更新逻辑
	always@(posedge i_clk)begin
		if(i_rstn == 1'b0)begin
			reg_wb_scale_red_center_right <= 20'd0; // 复位清空白平衡缩放值
		end else begin
			case(flag_freeze)
				1'b1:begin
					reg_wb_scale_red_center_right <= reg_wb_scale_red_center_right; // 输出未取走时保持本级
				end
				default:begin
					reg_wb_scale_red_center_right <= reg_wb_round_red_center_right >> C_WB_SHIFT; // 右移定点小数位
				end
			endcase
		end
	end

	//red 通道 right 像素白平衡缩放值更新逻辑
	always@(posedge i_clk)begin
		if(i_rstn == 1'b0)begin
			reg_wb_scale_red_right <= 20'd0; // 复位清空白平衡缩放值
		end else begin
			case(flag_freeze)
				1'b1:begin
					reg_wb_scale_red_right <= reg_wb_scale_red_right; // 输出未取走时保持本级
				end
				default:begin
					reg_wb_scale_red_right <= reg_wb_round_red_right >> C_WB_SHIFT; // 右移定点小数位
				end
			endcase
		end
	end

	//red 通道 left 像素白平衡饱和标志更新逻辑
	always@(posedge i_clk)begin
		if(i_rstn == 1'b0)begin
			flag_wb_over_red_left <= 1'b0; // 复位清除白平衡饱和标志
		end else begin
			case(flag_freeze)
				1'b1:begin
					flag_wb_over_red_left <= flag_wb_over_red_left; // 输出未取走时保持本级
				end
				default:begin
					flag_wb_over_red_left <= (reg_wb_scale_red_left > C_WB_MAX); // 比较白平衡上限
				end
			endcase
		end
	end

	//red 通道 center_left 像素白平衡饱和标志更新逻辑
	always@(posedge i_clk)begin
		if(i_rstn == 1'b0)begin
			flag_wb_over_red_center_left <= 1'b0; // 复位清除白平衡饱和标志
		end else begin
			case(flag_freeze)
				1'b1:begin
					flag_wb_over_red_center_left <= flag_wb_over_red_center_left; // 输出未取走时保持本级
				end
				default:begin
					flag_wb_over_red_center_left <= (reg_wb_scale_red_center_left > C_WB_MAX); // 比较白平衡上限
				end
			endcase
		end
	end

	//red 通道 center_right 像素白平衡饱和标志更新逻辑
	always@(posedge i_clk)begin
		if(i_rstn == 1'b0)begin
			flag_wb_over_red_center_right <= 1'b0; // 复位清除白平衡饱和标志
		end else begin
			case(flag_freeze)
				1'b1:begin
					flag_wb_over_red_center_right <= flag_wb_over_red_center_right; // 输出未取走时保持本级
				end
				default:begin
					flag_wb_over_red_center_right <= (reg_wb_scale_red_center_right > C_WB_MAX); // 比较白平衡上限
				end
			endcase
		end
	end

	//red 通道 right 像素白平衡饱和标志更新逻辑
	always@(posedge i_clk)begin
		if(i_rstn == 1'b0)begin
			flag_wb_over_red_right <= 1'b0; // 复位清除白平衡饱和标志
		end else begin
			case(flag_freeze)
				1'b1:begin
					flag_wb_over_red_right <= flag_wb_over_red_right; // 输出未取走时保持本级
				end
				default:begin
					flag_wb_over_red_right <= (reg_wb_scale_red_right > C_WB_MAX); // 比较白平衡上限
				end
			endcase
		end
	end

	//red 通道 left 像素白平衡缩放延迟值更新逻辑
	always@(posedge i_clk)begin
		if(i_rstn == 1'b0)begin
			reg_wb_delay_red_left <= 20'd0; // 复位清空白平衡缩放延迟值
		end else begin
			case(flag_freeze)
				1'b1:begin
					reg_wb_delay_red_left <= reg_wb_delay_red_left; // 输出未取走时保持本级
				end
				default:begin
					reg_wb_delay_red_left <= reg_wb_scale_red_left; // 与饱和标志对齐延迟缩放值
				end
			endcase
		end
	end

	//red 通道 center_left 像素白平衡缩放延迟值更新逻辑
	always@(posedge i_clk)begin
		if(i_rstn == 1'b0)begin
			reg_wb_delay_red_center_left <= 20'd0; // 复位清空白平衡缩放延迟值
		end else begin
			case(flag_freeze)
				1'b1:begin
					reg_wb_delay_red_center_left <= reg_wb_delay_red_center_left; // 输出未取走时保持本级
				end
				default:begin
					reg_wb_delay_red_center_left <= reg_wb_scale_red_center_left; // 与饱和标志对齐延迟缩放值
				end
			endcase
		end
	end

	//red 通道 center_right 像素白平衡缩放延迟值更新逻辑
	always@(posedge i_clk)begin
		if(i_rstn == 1'b0)begin
			reg_wb_delay_red_center_right <= 20'd0; // 复位清空白平衡缩放延迟值
		end else begin
			case(flag_freeze)
				1'b1:begin
					reg_wb_delay_red_center_right <= reg_wb_delay_red_center_right; // 输出未取走时保持本级
				end
				default:begin
					reg_wb_delay_red_center_right <= reg_wb_scale_red_center_right; // 与饱和标志对齐延迟缩放值
				end
			endcase
		end
	end

	//red 通道 right 像素白平衡缩放延迟值更新逻辑
	always@(posedge i_clk)begin
		if(i_rstn == 1'b0)begin
			reg_wb_delay_red_right <= 20'd0; // 复位清空白平衡缩放延迟值
		end else begin
			case(flag_freeze)
				1'b1:begin
					reg_wb_delay_red_right <= reg_wb_delay_red_right; // 输出未取走时保持本级
				end
				default:begin
					reg_wb_delay_red_right <= reg_wb_scale_red_right; // 与饱和标志对齐延迟缩放值
				end
			endcase
		end
	end

	//red 通道 left 像素白平衡输出码值更新逻辑
	always@(posedge i_clk)begin
		if(i_rstn == 1'b0)begin
			reg_wb_level_red_left <= 10'd0; // 复位清空白平衡输出码值
		end else begin
			case(flag_freeze)
				1'b1:begin
					reg_wb_level_red_left <= reg_wb_level_red_left; // 输出未取走时保持本级
				end
				default:begin
					reg_wb_level_red_left <= flag_wb_over_red_left ? C_WB_MAX : reg_wb_delay_red_left[9:0]; // 按饱和标志选择上限
				end
			endcase
		end
	end

	//red 通道 center_left 像素白平衡输出码值更新逻辑
	always@(posedge i_clk)begin
		if(i_rstn == 1'b0)begin
			reg_wb_level_red_center_left <= 10'd0; // 复位清空白平衡输出码值
		end else begin
			case(flag_freeze)
				1'b1:begin
					reg_wb_level_red_center_left <= reg_wb_level_red_center_left; // 输出未取走时保持本级
				end
				default:begin
					reg_wb_level_red_center_left <= flag_wb_over_red_center_left ? C_WB_MAX : reg_wb_delay_red_center_left[9:0]; // 按饱和标志选择上限
				end
			endcase
		end
	end

	//red 通道 center_right 像素白平衡输出码值更新逻辑
	always@(posedge i_clk)begin
		if(i_rstn == 1'b0)begin
			reg_wb_level_red_center_right <= 10'd0; // 复位清空白平衡输出码值
		end else begin
			case(flag_freeze)
				1'b1:begin
					reg_wb_level_red_center_right <= reg_wb_level_red_center_right; // 输出未取走时保持本级
				end
				default:begin
					reg_wb_level_red_center_right <= flag_wb_over_red_center_right ? C_WB_MAX : reg_wb_delay_red_center_right[9:0]; // 按饱和标志选择上限
				end
			endcase
		end
	end

	//red 通道 right 像素白平衡输出码值更新逻辑
	always@(posedge i_clk)begin
		if(i_rstn == 1'b0)begin
			reg_wb_level_red_right <= 10'd0; // 复位清空白平衡输出码值
		end else begin
			case(flag_freeze)
				1'b1:begin
					reg_wb_level_red_right <= reg_wb_level_red_right; // 输出未取走时保持本级
				end
				default:begin
					reg_wb_level_red_right <= flag_wb_over_red_right ? C_WB_MAX : reg_wb_delay_red_right[9:0]; // 按饱和标志选择上限
				end
			endcase
		end
	end

	//green 通道 left 像素白平衡乘积更新逻辑
	always@(posedge i_clk)begin
		if(i_rstn == 1'b0)begin
			reg_wb_product_green_left <= 20'd0; // 复位清空白平衡乘积
		end else begin
			case(flag_freeze)
				1'b1:begin
					reg_wb_product_green_left <= reg_wb_product_green_left; // 输出未取走时保持本级
				end
				default:begin
					reg_wb_product_green_left <= reg_in_green_left * C_WB_GAIN_G; // 定点增益相乘
				end
			endcase
		end
	end

	//green 通道 center_left 像素白平衡乘积更新逻辑
	always@(posedge i_clk)begin
		if(i_rstn == 1'b0)begin
			reg_wb_product_green_center_left <= 20'd0; // 复位清空白平衡乘积
		end else begin
			case(flag_freeze)
				1'b1:begin
					reg_wb_product_green_center_left <= reg_wb_product_green_center_left; // 输出未取走时保持本级
				end
				default:begin
					reg_wb_product_green_center_left <= reg_in_green_center_left * C_WB_GAIN_G; // 定点增益相乘
				end
			endcase
		end
	end

	//green 通道 center_right 像素白平衡乘积更新逻辑
	always@(posedge i_clk)begin
		if(i_rstn == 1'b0)begin
			reg_wb_product_green_center_right <= 20'd0; // 复位清空白平衡乘积
		end else begin
			case(flag_freeze)
				1'b1:begin
					reg_wb_product_green_center_right <= reg_wb_product_green_center_right; // 输出未取走时保持本级
				end
				default:begin
					reg_wb_product_green_center_right <= reg_in_green_center_right * C_WB_GAIN_G; // 定点增益相乘
				end
			endcase
		end
	end

	//green 通道 right 像素白平衡乘积更新逻辑
	always@(posedge i_clk)begin
		if(i_rstn == 1'b0)begin
			reg_wb_product_green_right <= 20'd0; // 复位清空白平衡乘积
		end else begin
			case(flag_freeze)
				1'b1:begin
					reg_wb_product_green_right <= reg_wb_product_green_right; // 输出未取走时保持本级
				end
				default:begin
					reg_wb_product_green_right <= reg_in_green_right * C_WB_GAIN_G; // 定点增益相乘
				end
			endcase
		end
	end

	//green 通道 left 像素白平衡圆整值更新逻辑
	always@(posedge i_clk)begin
		if(i_rstn == 1'b0)begin
			reg_wb_round_green_left <= 20'd0; // 复位清空白平衡圆整值
		end else begin
			case(flag_freeze)
				1'b1:begin
					reg_wb_round_green_left <= reg_wb_round_green_left; // 输出未取走时保持本级
				end
				default:begin
					reg_wb_round_green_left <= reg_wb_product_green_left + WB_ROUND_VALUE[19:0]; // 叠加圆整常量
				end
			endcase
		end
	end

	//green 通道 center_left 像素白平衡圆整值更新逻辑
	always@(posedge i_clk)begin
		if(i_rstn == 1'b0)begin
			reg_wb_round_green_center_left <= 20'd0; // 复位清空白平衡圆整值
		end else begin
			case(flag_freeze)
				1'b1:begin
					reg_wb_round_green_center_left <= reg_wb_round_green_center_left; // 输出未取走时保持本级
				end
				default:begin
					reg_wb_round_green_center_left <= reg_wb_product_green_center_left + WB_ROUND_VALUE[19:0]; // 叠加圆整常量
				end
			endcase
		end
	end

	//green 通道 center_right 像素白平衡圆整值更新逻辑
	always@(posedge i_clk)begin
		if(i_rstn == 1'b0)begin
			reg_wb_round_green_center_right <= 20'd0; // 复位清空白平衡圆整值
		end else begin
			case(flag_freeze)
				1'b1:begin
					reg_wb_round_green_center_right <= reg_wb_round_green_center_right; // 输出未取走时保持本级
				end
				default:begin
					reg_wb_round_green_center_right <= reg_wb_product_green_center_right + WB_ROUND_VALUE[19:0]; // 叠加圆整常量
				end
			endcase
		end
	end

	//green 通道 right 像素白平衡圆整值更新逻辑
	always@(posedge i_clk)begin
		if(i_rstn == 1'b0)begin
			reg_wb_round_green_right <= 20'd0; // 复位清空白平衡圆整值
		end else begin
			case(flag_freeze)
				1'b1:begin
					reg_wb_round_green_right <= reg_wb_round_green_right; // 输出未取走时保持本级
				end
				default:begin
					reg_wb_round_green_right <= reg_wb_product_green_right + WB_ROUND_VALUE[19:0]; // 叠加圆整常量
				end
			endcase
		end
	end

	//green 通道 left 像素白平衡缩放值更新逻辑
	always@(posedge i_clk)begin
		if(i_rstn == 1'b0)begin
			reg_wb_scale_green_left <= 20'd0; // 复位清空白平衡缩放值
		end else begin
			case(flag_freeze)
				1'b1:begin
					reg_wb_scale_green_left <= reg_wb_scale_green_left; // 输出未取走时保持本级
				end
				default:begin
					reg_wb_scale_green_left <= reg_wb_round_green_left >> C_WB_SHIFT; // 右移定点小数位
				end
			endcase
		end
	end

	//green 通道 center_left 像素白平衡缩放值更新逻辑
	always@(posedge i_clk)begin
		if(i_rstn == 1'b0)begin
			reg_wb_scale_green_center_left <= 20'd0; // 复位清空白平衡缩放值
		end else begin
			case(flag_freeze)
				1'b1:begin
					reg_wb_scale_green_center_left <= reg_wb_scale_green_center_left; // 输出未取走时保持本级
				end
				default:begin
					reg_wb_scale_green_center_left <= reg_wb_round_green_center_left >> C_WB_SHIFT; // 右移定点小数位
				end
			endcase
		end
	end

	//green 通道 center_right 像素白平衡缩放值更新逻辑
	always@(posedge i_clk)begin
		if(i_rstn == 1'b0)begin
			reg_wb_scale_green_center_right <= 20'd0; // 复位清空白平衡缩放值
		end else begin
			case(flag_freeze)
				1'b1:begin
					reg_wb_scale_green_center_right <= reg_wb_scale_green_center_right; // 输出未取走时保持本级
				end
				default:begin
					reg_wb_scale_green_center_right <= reg_wb_round_green_center_right >> C_WB_SHIFT; // 右移定点小数位
				end
			endcase
		end
	end

	//green 通道 right 像素白平衡缩放值更新逻辑
	always@(posedge i_clk)begin
		if(i_rstn == 1'b0)begin
			reg_wb_scale_green_right <= 20'd0; // 复位清空白平衡缩放值
		end else begin
			case(flag_freeze)
				1'b1:begin
					reg_wb_scale_green_right <= reg_wb_scale_green_right; // 输出未取走时保持本级
				end
				default:begin
					reg_wb_scale_green_right <= reg_wb_round_green_right >> C_WB_SHIFT; // 右移定点小数位
				end
			endcase
		end
	end

	//green 通道 left 像素白平衡饱和标志更新逻辑
	always@(posedge i_clk)begin
		if(i_rstn == 1'b0)begin
			flag_wb_over_green_left <= 1'b0; // 复位清除白平衡饱和标志
		end else begin
			case(flag_freeze)
				1'b1:begin
					flag_wb_over_green_left <= flag_wb_over_green_left; // 输出未取走时保持本级
				end
				default:begin
					flag_wb_over_green_left <= (reg_wb_scale_green_left > C_WB_MAX); // 比较白平衡上限
				end
			endcase
		end
	end

	//green 通道 center_left 像素白平衡饱和标志更新逻辑
	always@(posedge i_clk)begin
		if(i_rstn == 1'b0)begin
			flag_wb_over_green_center_left <= 1'b0; // 复位清除白平衡饱和标志
		end else begin
			case(flag_freeze)
				1'b1:begin
					flag_wb_over_green_center_left <= flag_wb_over_green_center_left; // 输出未取走时保持本级
				end
				default:begin
					flag_wb_over_green_center_left <= (reg_wb_scale_green_center_left > C_WB_MAX); // 比较白平衡上限
				end
			endcase
		end
	end

	//green 通道 center_right 像素白平衡饱和标志更新逻辑
	always@(posedge i_clk)begin
		if(i_rstn == 1'b0)begin
			flag_wb_over_green_center_right <= 1'b0; // 复位清除白平衡饱和标志
		end else begin
			case(flag_freeze)
				1'b1:begin
					flag_wb_over_green_center_right <= flag_wb_over_green_center_right; // 输出未取走时保持本级
				end
				default:begin
					flag_wb_over_green_center_right <= (reg_wb_scale_green_center_right > C_WB_MAX); // 比较白平衡上限
				end
			endcase
		end
	end

	//green 通道 right 像素白平衡饱和标志更新逻辑
	always@(posedge i_clk)begin
		if(i_rstn == 1'b0)begin
			flag_wb_over_green_right <= 1'b0; // 复位清除白平衡饱和标志
		end else begin
			case(flag_freeze)
				1'b1:begin
					flag_wb_over_green_right <= flag_wb_over_green_right; // 输出未取走时保持本级
				end
				default:begin
					flag_wb_over_green_right <= (reg_wb_scale_green_right > C_WB_MAX); // 比较白平衡上限
				end
			endcase
		end
	end

	//green 通道 left 像素白平衡缩放延迟值更新逻辑
	always@(posedge i_clk)begin
		if(i_rstn == 1'b0)begin
			reg_wb_delay_green_left <= 20'd0; // 复位清空白平衡缩放延迟值
		end else begin
			case(flag_freeze)
				1'b1:begin
					reg_wb_delay_green_left <= reg_wb_delay_green_left; // 输出未取走时保持本级
				end
				default:begin
					reg_wb_delay_green_left <= reg_wb_scale_green_left; // 与饱和标志对齐延迟缩放值
				end
			endcase
		end
	end

	//green 通道 center_left 像素白平衡缩放延迟值更新逻辑
	always@(posedge i_clk)begin
		if(i_rstn == 1'b0)begin
			reg_wb_delay_green_center_left <= 20'd0; // 复位清空白平衡缩放延迟值
		end else begin
			case(flag_freeze)
				1'b1:begin
					reg_wb_delay_green_center_left <= reg_wb_delay_green_center_left; // 输出未取走时保持本级
				end
				default:begin
					reg_wb_delay_green_center_left <= reg_wb_scale_green_center_left; // 与饱和标志对齐延迟缩放值
				end
			endcase
		end
	end

	//green 通道 center_right 像素白平衡缩放延迟值更新逻辑
	always@(posedge i_clk)begin
		if(i_rstn == 1'b0)begin
			reg_wb_delay_green_center_right <= 20'd0; // 复位清空白平衡缩放延迟值
		end else begin
			case(flag_freeze)
				1'b1:begin
					reg_wb_delay_green_center_right <= reg_wb_delay_green_center_right; // 输出未取走时保持本级
				end
				default:begin
					reg_wb_delay_green_center_right <= reg_wb_scale_green_center_right; // 与饱和标志对齐延迟缩放值
				end
			endcase
		end
	end

	//green 通道 right 像素白平衡缩放延迟值更新逻辑
	always@(posedge i_clk)begin
		if(i_rstn == 1'b0)begin
			reg_wb_delay_green_right <= 20'd0; // 复位清空白平衡缩放延迟值
		end else begin
			case(flag_freeze)
				1'b1:begin
					reg_wb_delay_green_right <= reg_wb_delay_green_right; // 输出未取走时保持本级
				end
				default:begin
					reg_wb_delay_green_right <= reg_wb_scale_green_right; // 与饱和标志对齐延迟缩放值
				end
			endcase
		end
	end

	//green 通道 left 像素白平衡输出码值更新逻辑
	always@(posedge i_clk)begin
		if(i_rstn == 1'b0)begin
			reg_wb_level_green_left <= 10'd0; // 复位清空白平衡输出码值
		end else begin
			case(flag_freeze)
				1'b1:begin
					reg_wb_level_green_left <= reg_wb_level_green_left; // 输出未取走时保持本级
				end
				default:begin
					reg_wb_level_green_left <= flag_wb_over_green_left ? C_WB_MAX : reg_wb_delay_green_left[9:0]; // 按饱和标志选择上限
				end
			endcase
		end
	end

	//green 通道 center_left 像素白平衡输出码值更新逻辑
	always@(posedge i_clk)begin
		if(i_rstn == 1'b0)begin
			reg_wb_level_green_center_left <= 10'd0; // 复位清空白平衡输出码值
		end else begin
			case(flag_freeze)
				1'b1:begin
					reg_wb_level_green_center_left <= reg_wb_level_green_center_left; // 输出未取走时保持本级
				end
				default:begin
					reg_wb_level_green_center_left <= flag_wb_over_green_center_left ? C_WB_MAX : reg_wb_delay_green_center_left[9:0]; // 按饱和标志选择上限
				end
			endcase
		end
	end

	//green 通道 center_right 像素白平衡输出码值更新逻辑
	always@(posedge i_clk)begin
		if(i_rstn == 1'b0)begin
			reg_wb_level_green_center_right <= 10'd0; // 复位清空白平衡输出码值
		end else begin
			case(flag_freeze)
				1'b1:begin
					reg_wb_level_green_center_right <= reg_wb_level_green_center_right; // 输出未取走时保持本级
				end
				default:begin
					reg_wb_level_green_center_right <= flag_wb_over_green_center_right ? C_WB_MAX : reg_wb_delay_green_center_right[9:0]; // 按饱和标志选择上限
				end
			endcase
		end
	end

	//green 通道 right 像素白平衡输出码值更新逻辑
	always@(posedge i_clk)begin
		if(i_rstn == 1'b0)begin
			reg_wb_level_green_right <= 10'd0; // 复位清空白平衡输出码值
		end else begin
			case(flag_freeze)
				1'b1:begin
					reg_wb_level_green_right <= reg_wb_level_green_right; // 输出未取走时保持本级
				end
				default:begin
					reg_wb_level_green_right <= flag_wb_over_green_right ? C_WB_MAX : reg_wb_delay_green_right[9:0]; // 按饱和标志选择上限
				end
			endcase
		end
	end

	//blue 通道 left 像素白平衡乘积更新逻辑
	always@(posedge i_clk)begin
		if(i_rstn == 1'b0)begin
			reg_wb_product_blue_left <= 20'd0; // 复位清空白平衡乘积
		end else begin
			case(flag_freeze)
				1'b1:begin
					reg_wb_product_blue_left <= reg_wb_product_blue_left; // 输出未取走时保持本级
				end
				default:begin
					reg_wb_product_blue_left <= reg_in_blue_left * C_WB_GAIN_B; // 定点增益相乘
				end
			endcase
		end
	end

	//blue 通道 center_left 像素白平衡乘积更新逻辑
	always@(posedge i_clk)begin
		if(i_rstn == 1'b0)begin
			reg_wb_product_blue_center_left <= 20'd0; // 复位清空白平衡乘积
		end else begin
			case(flag_freeze)
				1'b1:begin
					reg_wb_product_blue_center_left <= reg_wb_product_blue_center_left; // 输出未取走时保持本级
				end
				default:begin
					reg_wb_product_blue_center_left <= reg_in_blue_center_left * C_WB_GAIN_B; // 定点增益相乘
				end
			endcase
		end
	end

	//blue 通道 center_right 像素白平衡乘积更新逻辑
	always@(posedge i_clk)begin
		if(i_rstn == 1'b0)begin
			reg_wb_product_blue_center_right <= 20'd0; // 复位清空白平衡乘积
		end else begin
			case(flag_freeze)
				1'b1:begin
					reg_wb_product_blue_center_right <= reg_wb_product_blue_center_right; // 输出未取走时保持本级
				end
				default:begin
					reg_wb_product_blue_center_right <= reg_in_blue_center_right * C_WB_GAIN_B; // 定点增益相乘
				end
			endcase
		end
	end

	//blue 通道 right 像素白平衡乘积更新逻辑
	always@(posedge i_clk)begin
		if(i_rstn == 1'b0)begin
			reg_wb_product_blue_right <= 20'd0; // 复位清空白平衡乘积
		end else begin
			case(flag_freeze)
				1'b1:begin
					reg_wb_product_blue_right <= reg_wb_product_blue_right; // 输出未取走时保持本级
				end
				default:begin
					reg_wb_product_blue_right <= reg_in_blue_right * C_WB_GAIN_B; // 定点增益相乘
				end
			endcase
		end
	end

	//blue 通道 left 像素白平衡圆整值更新逻辑
	always@(posedge i_clk)begin
		if(i_rstn == 1'b0)begin
			reg_wb_round_blue_left <= 20'd0; // 复位清空白平衡圆整值
		end else begin
			case(flag_freeze)
				1'b1:begin
					reg_wb_round_blue_left <= reg_wb_round_blue_left; // 输出未取走时保持本级
				end
				default:begin
					reg_wb_round_blue_left <= reg_wb_product_blue_left + WB_ROUND_VALUE[19:0]; // 叠加圆整常量
				end
			endcase
		end
	end

	//blue 通道 center_left 像素白平衡圆整值更新逻辑
	always@(posedge i_clk)begin
		if(i_rstn == 1'b0)begin
			reg_wb_round_blue_center_left <= 20'd0; // 复位清空白平衡圆整值
		end else begin
			case(flag_freeze)
				1'b1:begin
					reg_wb_round_blue_center_left <= reg_wb_round_blue_center_left; // 输出未取走时保持本级
				end
				default:begin
					reg_wb_round_blue_center_left <= reg_wb_product_blue_center_left + WB_ROUND_VALUE[19:0]; // 叠加圆整常量
				end
			endcase
		end
	end

	//blue 通道 center_right 像素白平衡圆整值更新逻辑
	always@(posedge i_clk)begin
		if(i_rstn == 1'b0)begin
			reg_wb_round_blue_center_right <= 20'd0; // 复位清空白平衡圆整值
		end else begin
			case(flag_freeze)
				1'b1:begin
					reg_wb_round_blue_center_right <= reg_wb_round_blue_center_right; // 输出未取走时保持本级
				end
				default:begin
					reg_wb_round_blue_center_right <= reg_wb_product_blue_center_right + WB_ROUND_VALUE[19:0]; // 叠加圆整常量
				end
			endcase
		end
	end

	//blue 通道 right 像素白平衡圆整值更新逻辑
	always@(posedge i_clk)begin
		if(i_rstn == 1'b0)begin
			reg_wb_round_blue_right <= 20'd0; // 复位清空白平衡圆整值
		end else begin
			case(flag_freeze)
				1'b1:begin
					reg_wb_round_blue_right <= reg_wb_round_blue_right; // 输出未取走时保持本级
				end
				default:begin
					reg_wb_round_blue_right <= reg_wb_product_blue_right + WB_ROUND_VALUE[19:0]; // 叠加圆整常量
				end
			endcase
		end
	end

	//blue 通道 left 像素白平衡缩放值更新逻辑
	always@(posedge i_clk)begin
		if(i_rstn == 1'b0)begin
			reg_wb_scale_blue_left <= 20'd0; // 复位清空白平衡缩放值
		end else begin
			case(flag_freeze)
				1'b1:begin
					reg_wb_scale_blue_left <= reg_wb_scale_blue_left; // 输出未取走时保持本级
				end
				default:begin
					reg_wb_scale_blue_left <= reg_wb_round_blue_left >> C_WB_SHIFT; // 右移定点小数位
				end
			endcase
		end
	end

	//blue 通道 center_left 像素白平衡缩放值更新逻辑
	always@(posedge i_clk)begin
		if(i_rstn == 1'b0)begin
			reg_wb_scale_blue_center_left <= 20'd0; // 复位清空白平衡缩放值
		end else begin
			case(flag_freeze)
				1'b1:begin
					reg_wb_scale_blue_center_left <= reg_wb_scale_blue_center_left; // 输出未取走时保持本级
				end
				default:begin
					reg_wb_scale_blue_center_left <= reg_wb_round_blue_center_left >> C_WB_SHIFT; // 右移定点小数位
				end
			endcase
		end
	end

	//blue 通道 center_right 像素白平衡缩放值更新逻辑
	always@(posedge i_clk)begin
		if(i_rstn == 1'b0)begin
			reg_wb_scale_blue_center_right <= 20'd0; // 复位清空白平衡缩放值
		end else begin
			case(flag_freeze)
				1'b1:begin
					reg_wb_scale_blue_center_right <= reg_wb_scale_blue_center_right; // 输出未取走时保持本级
				end
				default:begin
					reg_wb_scale_blue_center_right <= reg_wb_round_blue_center_right >> C_WB_SHIFT; // 右移定点小数位
				end
			endcase
		end
	end

	//blue 通道 right 像素白平衡缩放值更新逻辑
	always@(posedge i_clk)begin
		if(i_rstn == 1'b0)begin
			reg_wb_scale_blue_right <= 20'd0; // 复位清空白平衡缩放值
		end else begin
			case(flag_freeze)
				1'b1:begin
					reg_wb_scale_blue_right <= reg_wb_scale_blue_right; // 输出未取走时保持本级
				end
				default:begin
					reg_wb_scale_blue_right <= reg_wb_round_blue_right >> C_WB_SHIFT; // 右移定点小数位
				end
			endcase
		end
	end

	//blue 通道 left 像素白平衡饱和标志更新逻辑
	always@(posedge i_clk)begin
		if(i_rstn == 1'b0)begin
			flag_wb_over_blue_left <= 1'b0; // 复位清除白平衡饱和标志
		end else begin
			case(flag_freeze)
				1'b1:begin
					flag_wb_over_blue_left <= flag_wb_over_blue_left; // 输出未取走时保持本级
				end
				default:begin
					flag_wb_over_blue_left <= (reg_wb_scale_blue_left > C_WB_MAX); // 比较白平衡上限
				end
			endcase
		end
	end

	//blue 通道 center_left 像素白平衡饱和标志更新逻辑
	always@(posedge i_clk)begin
		if(i_rstn == 1'b0)begin
			flag_wb_over_blue_center_left <= 1'b0; // 复位清除白平衡饱和标志
		end else begin
			case(flag_freeze)
				1'b1:begin
					flag_wb_over_blue_center_left <= flag_wb_over_blue_center_left; // 输出未取走时保持本级
				end
				default:begin
					flag_wb_over_blue_center_left <= (reg_wb_scale_blue_center_left > C_WB_MAX); // 比较白平衡上限
				end
			endcase
		end
	end

	//blue 通道 center_right 像素白平衡饱和标志更新逻辑
	always@(posedge i_clk)begin
		if(i_rstn == 1'b0)begin
			flag_wb_over_blue_center_right <= 1'b0; // 复位清除白平衡饱和标志
		end else begin
			case(flag_freeze)
				1'b1:begin
					flag_wb_over_blue_center_right <= flag_wb_over_blue_center_right; // 输出未取走时保持本级
				end
				default:begin
					flag_wb_over_blue_center_right <= (reg_wb_scale_blue_center_right > C_WB_MAX); // 比较白平衡上限
				end
			endcase
		end
	end

	//blue 通道 right 像素白平衡饱和标志更新逻辑
	always@(posedge i_clk)begin
		if(i_rstn == 1'b0)begin
			flag_wb_over_blue_right <= 1'b0; // 复位清除白平衡饱和标志
		end else begin
			case(flag_freeze)
				1'b1:begin
					flag_wb_over_blue_right <= flag_wb_over_blue_right; // 输出未取走时保持本级
				end
				default:begin
					flag_wb_over_blue_right <= (reg_wb_scale_blue_right > C_WB_MAX); // 比较白平衡上限
				end
			endcase
		end
	end

	//blue 通道 left 像素白平衡缩放延迟值更新逻辑
	always@(posedge i_clk)begin
		if(i_rstn == 1'b0)begin
			reg_wb_delay_blue_left <= 20'd0; // 复位清空白平衡缩放延迟值
		end else begin
			case(flag_freeze)
				1'b1:begin
					reg_wb_delay_blue_left <= reg_wb_delay_blue_left; // 输出未取走时保持本级
				end
				default:begin
					reg_wb_delay_blue_left <= reg_wb_scale_blue_left; // 与饱和标志对齐延迟缩放值
				end
			endcase
		end
	end

	//blue 通道 center_left 像素白平衡缩放延迟值更新逻辑
	always@(posedge i_clk)begin
		if(i_rstn == 1'b0)begin
			reg_wb_delay_blue_center_left <= 20'd0; // 复位清空白平衡缩放延迟值
		end else begin
			case(flag_freeze)
				1'b1:begin
					reg_wb_delay_blue_center_left <= reg_wb_delay_blue_center_left; // 输出未取走时保持本级
				end
				default:begin
					reg_wb_delay_blue_center_left <= reg_wb_scale_blue_center_left; // 与饱和标志对齐延迟缩放值
				end
			endcase
		end
	end

	//blue 通道 center_right 像素白平衡缩放延迟值更新逻辑
	always@(posedge i_clk)begin
		if(i_rstn == 1'b0)begin
			reg_wb_delay_blue_center_right <= 20'd0; // 复位清空白平衡缩放延迟值
		end else begin
			case(flag_freeze)
				1'b1:begin
					reg_wb_delay_blue_center_right <= reg_wb_delay_blue_center_right; // 输出未取走时保持本级
				end
				default:begin
					reg_wb_delay_blue_center_right <= reg_wb_scale_blue_center_right; // 与饱和标志对齐延迟缩放值
				end
			endcase
		end
	end

	//blue 通道 right 像素白平衡缩放延迟值更新逻辑
	always@(posedge i_clk)begin
		if(i_rstn == 1'b0)begin
			reg_wb_delay_blue_right <= 20'd0; // 复位清空白平衡缩放延迟值
		end else begin
			case(flag_freeze)
				1'b1:begin
					reg_wb_delay_blue_right <= reg_wb_delay_blue_right; // 输出未取走时保持本级
				end
				default:begin
					reg_wb_delay_blue_right <= reg_wb_scale_blue_right; // 与饱和标志对齐延迟缩放值
				end
			endcase
		end
	end

	//blue 通道 left 像素白平衡输出码值更新逻辑
	always@(posedge i_clk)begin
		if(i_rstn == 1'b0)begin
			reg_wb_level_blue_left <= 10'd0; // 复位清空白平衡输出码值
		end else begin
			case(flag_freeze)
				1'b1:begin
					reg_wb_level_blue_left <= reg_wb_level_blue_left; // 输出未取走时保持本级
				end
				default:begin
					reg_wb_level_blue_left <= flag_wb_over_blue_left ? C_WB_MAX : reg_wb_delay_blue_left[9:0]; // 按饱和标志选择上限
				end
			endcase
		end
	end

	//blue 通道 center_left 像素白平衡输出码值更新逻辑
	always@(posedge i_clk)begin
		if(i_rstn == 1'b0)begin
			reg_wb_level_blue_center_left <= 10'd0; // 复位清空白平衡输出码值
		end else begin
			case(flag_freeze)
				1'b1:begin
					reg_wb_level_blue_center_left <= reg_wb_level_blue_center_left; // 输出未取走时保持本级
				end
				default:begin
					reg_wb_level_blue_center_left <= flag_wb_over_blue_center_left ? C_WB_MAX : reg_wb_delay_blue_center_left[9:0]; // 按饱和标志选择上限
				end
			endcase
		end
	end

	//blue 通道 center_right 像素白平衡输出码值更新逻辑
	always@(posedge i_clk)begin
		if(i_rstn == 1'b0)begin
			reg_wb_level_blue_center_right <= 10'd0; // 复位清空白平衡输出码值
		end else begin
			case(flag_freeze)
				1'b1:begin
					reg_wb_level_blue_center_right <= reg_wb_level_blue_center_right; // 输出未取走时保持本级
				end
				default:begin
					reg_wb_level_blue_center_right <= flag_wb_over_blue_center_right ? C_WB_MAX : reg_wb_delay_blue_center_right[9:0]; // 按饱和标志选择上限
				end
			endcase
		end
	end

	//blue 通道 right 像素白平衡输出码值更新逻辑
	always@(posedge i_clk)begin
		if(i_rstn == 1'b0)begin
			reg_wb_level_blue_right <= 10'd0; // 复位清空白平衡输出码值
		end else begin
			case(flag_freeze)
				1'b1:begin
					reg_wb_level_blue_right <= reg_wb_level_blue_right; // 输出未取走时保持本级
				end
				default:begin
					reg_wb_level_blue_right <= flag_wb_over_blue_right ? C_WB_MAX : reg_wb_delay_blue_right[9:0]; // 按饱和标志选择上限
				end
			endcase
		end
	end

	//left 像素红绿通道白平衡饱和归并逻辑
	always@(posedge i_clk)begin
		if(i_rstn == 1'b0)begin
			flag_wb_pair_left <= 1'b0; // 复位清除红绿归并标志
		end else begin
			case(flag_freeze)
				1'b1:begin
					flag_wb_pair_left <= flag_wb_pair_left; // 输出未取走时保持本级
				end
				default:begin
					flag_wb_pair_left <= flag_wb_over_red_left | flag_wb_over_green_left; // 归并红绿两通道饱和
				end
			endcase
		end
	end

	//center_left 像素红绿通道白平衡饱和归并逻辑
	always@(posedge i_clk)begin
		if(i_rstn == 1'b0)begin
			flag_wb_pair_center_left <= 1'b0; // 复位清除红绿归并标志
		end else begin
			case(flag_freeze)
				1'b1:begin
					flag_wb_pair_center_left <= flag_wb_pair_center_left; // 输出未取走时保持本级
				end
				default:begin
					flag_wb_pair_center_left <= flag_wb_over_red_center_left | flag_wb_over_green_center_left; // 归并红绿两通道饱和
				end
			endcase
		end
	end

	//center_right 像素红绿通道白平衡饱和归并逻辑
	always@(posedge i_clk)begin
		if(i_rstn == 1'b0)begin
			flag_wb_pair_center_right <= 1'b0; // 复位清除红绿归并标志
		end else begin
			case(flag_freeze)
				1'b1:begin
					flag_wb_pair_center_right <= flag_wb_pair_center_right; // 输出未取走时保持本级
				end
				default:begin
					flag_wb_pair_center_right <= flag_wb_over_red_center_right | flag_wb_over_green_center_right; // 归并红绿两通道饱和
				end
			endcase
		end
	end

	//right 像素红绿通道白平衡饱和归并逻辑
	always@(posedge i_clk)begin
		if(i_rstn == 1'b0)begin
			flag_wb_pair_right <= 1'b0; // 复位清除红绿归并标志
		end else begin
			case(flag_freeze)
				1'b1:begin
					flag_wb_pair_right <= flag_wb_pair_right; // 输出未取走时保持本级
				end
				default:begin
					flag_wb_pair_right <= flag_wb_over_red_right | flag_wb_over_green_right; // 归并红绿两通道饱和
				end
			endcase
		end
	end

	//left 像素蓝通道白平衡饱和延迟逻辑
	always@(posedge i_clk)begin
		if(i_rstn == 1'b0)begin
			flag_wb_blue_left <= 1'b0; // 复位清除蓝通道延迟标志
		end else begin
			case(flag_freeze)
				1'b1:begin
					flag_wb_blue_left <= flag_wb_blue_left; // 输出未取走时保持本级
				end
				default:begin
					flag_wb_blue_left <= flag_wb_over_blue_left; // 对齐红绿归并级延迟蓝通道
				end
			endcase
		end
	end

	//center_left 像素蓝通道白平衡饱和延迟逻辑
	always@(posedge i_clk)begin
		if(i_rstn == 1'b0)begin
			flag_wb_blue_center_left <= 1'b0; // 复位清除蓝通道延迟标志
		end else begin
			case(flag_freeze)
				1'b1:begin
					flag_wb_blue_center_left <= flag_wb_blue_center_left; // 输出未取走时保持本级
				end
				default:begin
					flag_wb_blue_center_left <= flag_wb_over_blue_center_left; // 对齐红绿归并级延迟蓝通道
				end
			endcase
		end
	end

	//center_right 像素蓝通道白平衡饱和延迟逻辑
	always@(posedge i_clk)begin
		if(i_rstn == 1'b0)begin
			flag_wb_blue_center_right <= 1'b0; // 复位清除蓝通道延迟标志
		end else begin
			case(flag_freeze)
				1'b1:begin
					flag_wb_blue_center_right <= flag_wb_blue_center_right; // 输出未取走时保持本级
				end
				default:begin
					flag_wb_blue_center_right <= flag_wb_over_blue_center_right; // 对齐红绿归并级延迟蓝通道
				end
			endcase
		end
	end

	//right 像素蓝通道白平衡饱和延迟逻辑
	always@(posedge i_clk)begin
		if(i_rstn == 1'b0)begin
			flag_wb_blue_right <= 1'b0; // 复位清除蓝通道延迟标志
		end else begin
			case(flag_freeze)
				1'b1:begin
					flag_wb_blue_right <= flag_wb_blue_right; // 输出未取走时保持本级
				end
				default:begin
					flag_wb_blue_right <= flag_wb_over_blue_right; // 对齐红绿归并级延迟蓝通道
				end
			endcase
		end
	end

	//left 像素白平衡饱和归并逻辑
	always@(posedge i_clk)begin
		if(i_rstn == 1'b0)begin
			flag_wb_lane_left <= 1'b0; // 复位清除像素归并标志
		end else begin
			case(flag_freeze)
				1'b1:begin
					flag_wb_lane_left <= flag_wb_lane_left; // 输出未取走时保持本级
				end
				default:begin
					flag_wb_lane_left <= flag_wb_pair_left | flag_wb_blue_left; // 并入已对齐的蓝通道饱和
				end
			endcase
		end
	end

	//center_left 像素白平衡饱和归并逻辑
	always@(posedge i_clk)begin
		if(i_rstn == 1'b0)begin
			flag_wb_lane_center_left <= 1'b0; // 复位清除像素归并标志
		end else begin
			case(flag_freeze)
				1'b1:begin
					flag_wb_lane_center_left <= flag_wb_lane_center_left; // 输出未取走时保持本级
				end
				default:begin
					flag_wb_lane_center_left <= flag_wb_pair_center_left | flag_wb_blue_center_left; // 并入已对齐的蓝通道饱和
				end
			endcase
		end
	end

	//center_right 像素白平衡饱和归并逻辑
	always@(posedge i_clk)begin
		if(i_rstn == 1'b0)begin
			flag_wb_lane_center_right <= 1'b0; // 复位清除像素归并标志
		end else begin
			case(flag_freeze)
				1'b1:begin
					flag_wb_lane_center_right <= flag_wb_lane_center_right; // 输出未取走时保持本级
				end
				default:begin
					flag_wb_lane_center_right <= flag_wb_pair_center_right | flag_wb_blue_center_right; // 并入已对齐的蓝通道饱和
				end
			endcase
		end
	end

	//right 像素白平衡饱和归并逻辑
	always@(posedge i_clk)begin
		if(i_rstn == 1'b0)begin
			flag_wb_lane_right <= 1'b0; // 复位清除像素归并标志
		end else begin
			case(flag_freeze)
				1'b1:begin
					flag_wb_lane_right <= flag_wb_lane_right; // 输出未取走时保持本级
				end
				default:begin
					flag_wb_lane_right <= flag_wb_pair_right | flag_wb_blue_right; // 并入已对齐的蓝通道饱和
				end
			endcase
		end
	end

	//低半幅白平衡饱和归并逻辑
	always@(posedge i_clk)begin
		if(i_rstn == 1'b0)begin
			flag_wb_group_low <= 1'b0; // 复位清除低半幅标志
		end else begin
			case(flag_freeze)
				1'b1:begin
					flag_wb_group_low <= flag_wb_group_low; // 输出未取走时保持本级
				end
				default:begin
					flag_wb_group_low <= flag_wb_lane_left | flag_wb_lane_center_left; // 归并低半幅两像素
				end
			endcase
		end
	end

	//高半幅白平衡饱和归并逻辑
	always@(posedge i_clk)begin
		if(i_rstn == 1'b0)begin
			flag_wb_group_high <= 1'b0; // 复位清除高半幅标志
		end else begin
			case(flag_freeze)
				1'b1:begin
					flag_wb_group_high <= flag_wb_group_high; // 输出未取走时保持本级
				end
				default:begin
					flag_wb_group_high <= flag_wb_lane_center_right | flag_wb_lane_right; // 归并高半幅两像素
				end
			endcase
		end
	end

	//白平衡饱和 beat 标志更新逻辑
	always@(posedge i_clk)begin
		if(i_rstn == 1'b0)begin
			flag_wb_beat <= 1'b0; // 复位清除 beat 饱和标志
		end else begin
			case(flag_freeze)
				1'b1:begin
					flag_wb_beat <= flag_wb_beat; // 输出未取走时保持本级
				end
				default:begin
					flag_wb_beat <= flag_wb_group_low | flag_wb_group_high; // 归并整个 beat
				end
			endcase
		end
	end

	//red 通道 left 像素矩阵首项更新逻辑
	always@(posedge i_clk)begin
		if(i_rstn == 1'b0)begin
			reg_ccm_first_red_left <= 24'd0; // 复位清空矩阵首项
		end else begin
			case(flag_freeze)
				1'b1:begin
					reg_ccm_first_red_left <= reg_ccm_first_red_left; // 输出未取走时保持本级
				end
				default:begin
					reg_ccm_first_red_left <= $signed({1'b0, reg_wb_level_red_left}) * $signed(C_CCM_M00); // 首项乘加系数
				end
			endcase
		end
	end

	//red 通道 center_left 像素矩阵首项更新逻辑
	always@(posedge i_clk)begin
		if(i_rstn == 1'b0)begin
			reg_ccm_first_red_center_left <= 24'd0; // 复位清空矩阵首项
		end else begin
			case(flag_freeze)
				1'b1:begin
					reg_ccm_first_red_center_left <= reg_ccm_first_red_center_left; // 输出未取走时保持本级
				end
				default:begin
					reg_ccm_first_red_center_left <= $signed({1'b0, reg_wb_level_red_center_left}) * $signed(C_CCM_M00); // 首项乘加系数
				end
			endcase
		end
	end

	//red 通道 center_right 像素矩阵首项更新逻辑
	always@(posedge i_clk)begin
		if(i_rstn == 1'b0)begin
			reg_ccm_first_red_center_right <= 24'd0; // 复位清空矩阵首项
		end else begin
			case(flag_freeze)
				1'b1:begin
					reg_ccm_first_red_center_right <= reg_ccm_first_red_center_right; // 输出未取走时保持本级
				end
				default:begin
					reg_ccm_first_red_center_right <= $signed({1'b0, reg_wb_level_red_center_right}) * $signed(C_CCM_M00); // 首项乘加系数
				end
			endcase
		end
	end

	//red 通道 right 像素矩阵首项更新逻辑
	always@(posedge i_clk)begin
		if(i_rstn == 1'b0)begin
			reg_ccm_first_red_right <= 24'd0; // 复位清空矩阵首项
		end else begin
			case(flag_freeze)
				1'b1:begin
					reg_ccm_first_red_right <= reg_ccm_first_red_right; // 输出未取走时保持本级
				end
				default:begin
					reg_ccm_first_red_right <= $signed({1'b0, reg_wb_level_red_right}) * $signed(C_CCM_M00); // 首项乘加系数
				end
			endcase
		end
	end

	//red 通道 left 像素矩阵次项更新逻辑
	always@(posedge i_clk)begin
		if(i_rstn == 1'b0)begin
			reg_ccm_second_red_left <= 24'd0; // 复位清空矩阵次项
		end else begin
			case(flag_freeze)
				1'b1:begin
					reg_ccm_second_red_left <= reg_ccm_second_red_left; // 输出未取走时保持本级
				end
				default:begin
					reg_ccm_second_red_left <= $signed({1'b0, reg_wb_level_green_left}) * $signed(C_CCM_M01); // 次项乘加系数
				end
			endcase
		end
	end

	//red 通道 center_left 像素矩阵次项更新逻辑
	always@(posedge i_clk)begin
		if(i_rstn == 1'b0)begin
			reg_ccm_second_red_center_left <= 24'd0; // 复位清空矩阵次项
		end else begin
			case(flag_freeze)
				1'b1:begin
					reg_ccm_second_red_center_left <= reg_ccm_second_red_center_left; // 输出未取走时保持本级
				end
				default:begin
					reg_ccm_second_red_center_left <= $signed({1'b0, reg_wb_level_green_center_left}) * $signed(C_CCM_M01); // 次项乘加系数
				end
			endcase
		end
	end

	//red 通道 center_right 像素矩阵次项更新逻辑
	always@(posedge i_clk)begin
		if(i_rstn == 1'b0)begin
			reg_ccm_second_red_center_right <= 24'd0; // 复位清空矩阵次项
		end else begin
			case(flag_freeze)
				1'b1:begin
					reg_ccm_second_red_center_right <= reg_ccm_second_red_center_right; // 输出未取走时保持本级
				end
				default:begin
					reg_ccm_second_red_center_right <= $signed({1'b0, reg_wb_level_green_center_right}) * $signed(C_CCM_M01); // 次项乘加系数
				end
			endcase
		end
	end

	//red 通道 right 像素矩阵次项更新逻辑
	always@(posedge i_clk)begin
		if(i_rstn == 1'b0)begin
			reg_ccm_second_red_right <= 24'd0; // 复位清空矩阵次项
		end else begin
			case(flag_freeze)
				1'b1:begin
					reg_ccm_second_red_right <= reg_ccm_second_red_right; // 输出未取走时保持本级
				end
				default:begin
					reg_ccm_second_red_right <= $signed({1'b0, reg_wb_level_green_right}) * $signed(C_CCM_M01); // 次项乘加系数
				end
			endcase
		end
	end

	//red 通道 left 像素矩阵末项更新逻辑
	always@(posedge i_clk)begin
		if(i_rstn == 1'b0)begin
			reg_ccm_third_red_left <= 24'd0; // 复位清空矩阵末项
		end else begin
			case(flag_freeze)
				1'b1:begin
					reg_ccm_third_red_left <= reg_ccm_third_red_left; // 输出未取走时保持本级
				end
				default:begin
					reg_ccm_third_red_left <= $signed({1'b0, reg_wb_level_blue_left}) * $signed(C_CCM_M02); // 末项乘加系数
				end
			endcase
		end
	end

	//red 通道 center_left 像素矩阵末项更新逻辑
	always@(posedge i_clk)begin
		if(i_rstn == 1'b0)begin
			reg_ccm_third_red_center_left <= 24'd0; // 复位清空矩阵末项
		end else begin
			case(flag_freeze)
				1'b1:begin
					reg_ccm_third_red_center_left <= reg_ccm_third_red_center_left; // 输出未取走时保持本级
				end
				default:begin
					reg_ccm_third_red_center_left <= $signed({1'b0, reg_wb_level_blue_center_left}) * $signed(C_CCM_M02); // 末项乘加系数
				end
			endcase
		end
	end

	//red 通道 center_right 像素矩阵末项更新逻辑
	always@(posedge i_clk)begin
		if(i_rstn == 1'b0)begin
			reg_ccm_third_red_center_right <= 24'd0; // 复位清空矩阵末项
		end else begin
			case(flag_freeze)
				1'b1:begin
					reg_ccm_third_red_center_right <= reg_ccm_third_red_center_right; // 输出未取走时保持本级
				end
				default:begin
					reg_ccm_third_red_center_right <= $signed({1'b0, reg_wb_level_blue_center_right}) * $signed(C_CCM_M02); // 末项乘加系数
				end
			endcase
		end
	end

	//red 通道 right 像素矩阵末项更新逻辑
	always@(posedge i_clk)begin
		if(i_rstn == 1'b0)begin
			reg_ccm_third_red_right <= 24'd0; // 复位清空矩阵末项
		end else begin
			case(flag_freeze)
				1'b1:begin
					reg_ccm_third_red_right <= reg_ccm_third_red_right; // 输出未取走时保持本级
				end
				default:begin
					reg_ccm_third_red_right <= $signed({1'b0, reg_wb_level_blue_right}) * $signed(C_CCM_M02); // 末项乘加系数
				end
			endcase
		end
	end

	//red 通道 left 像素矩阵前两项和更新逻辑
	always@(posedge i_clk)begin
		if(i_rstn == 1'b0)begin
			reg_ccm_partial_red_left <= 24'd0; // 复位清空矩阵前两项和
		end else begin
			case(flag_freeze)
				1'b1:begin
					reg_ccm_partial_red_left <= reg_ccm_partial_red_left; // 输出未取走时保持本级
				end
				default:begin
					reg_ccm_partial_red_left <= $signed(reg_ccm_first_red_left) + $signed(reg_ccm_second_red_left); // 累加前两项
				end
			endcase
		end
	end

	//red 通道 center_left 像素矩阵前两项和更新逻辑
	always@(posedge i_clk)begin
		if(i_rstn == 1'b0)begin
			reg_ccm_partial_red_center_left <= 24'd0; // 复位清空矩阵前两项和
		end else begin
			case(flag_freeze)
				1'b1:begin
					reg_ccm_partial_red_center_left <= reg_ccm_partial_red_center_left; // 输出未取走时保持本级
				end
				default:begin
					reg_ccm_partial_red_center_left <= $signed(reg_ccm_first_red_center_left) + $signed(reg_ccm_second_red_center_left); // 累加前两项
				end
			endcase
		end
	end

	//red 通道 center_right 像素矩阵前两项和更新逻辑
	always@(posedge i_clk)begin
		if(i_rstn == 1'b0)begin
			reg_ccm_partial_red_center_right <= 24'd0; // 复位清空矩阵前两项和
		end else begin
			case(flag_freeze)
				1'b1:begin
					reg_ccm_partial_red_center_right <= reg_ccm_partial_red_center_right; // 输出未取走时保持本级
				end
				default:begin
					reg_ccm_partial_red_center_right <= $signed(reg_ccm_first_red_center_right) + $signed(reg_ccm_second_red_center_right); // 累加前两项
				end
			endcase
		end
	end

	//red 通道 right 像素矩阵前两项和更新逻辑
	always@(posedge i_clk)begin
		if(i_rstn == 1'b0)begin
			reg_ccm_partial_red_right <= 24'd0; // 复位清空矩阵前两项和
		end else begin
			case(flag_freeze)
				1'b1:begin
					reg_ccm_partial_red_right <= reg_ccm_partial_red_right; // 输出未取走时保持本级
				end
				default:begin
					reg_ccm_partial_red_right <= $signed(reg_ccm_first_red_right) + $signed(reg_ccm_second_red_right); // 累加前两项
				end
			endcase
		end
	end

	//red 通道 left 像素矩阵末项延迟值更新逻辑
	always@(posedge i_clk)begin
		if(i_rstn == 1'b0)begin
			reg_ccm_third_hold_red_left <= 24'd0; // 复位清空矩阵末项延迟值
		end else begin
			case(flag_freeze)
				1'b1:begin
					reg_ccm_third_hold_red_left <= reg_ccm_third_hold_red_left; // 输出未取走时保持本级
				end
				default:begin
					reg_ccm_third_hold_red_left <= reg_ccm_third_red_left; // 与前两项和对齐延迟末项
				end
			endcase
		end
	end

	//red 通道 center_left 像素矩阵末项延迟值更新逻辑
	always@(posedge i_clk)begin
		if(i_rstn == 1'b0)begin
			reg_ccm_third_hold_red_center_left <= 24'd0; // 复位清空矩阵末项延迟值
		end else begin
			case(flag_freeze)
				1'b1:begin
					reg_ccm_third_hold_red_center_left <= reg_ccm_third_hold_red_center_left; // 输出未取走时保持本级
				end
				default:begin
					reg_ccm_third_hold_red_center_left <= reg_ccm_third_red_center_left; // 与前两项和对齐延迟末项
				end
			endcase
		end
	end

	//red 通道 center_right 像素矩阵末项延迟值更新逻辑
	always@(posedge i_clk)begin
		if(i_rstn == 1'b0)begin
			reg_ccm_third_hold_red_center_right <= 24'd0; // 复位清空矩阵末项延迟值
		end else begin
			case(flag_freeze)
				1'b1:begin
					reg_ccm_third_hold_red_center_right <= reg_ccm_third_hold_red_center_right; // 输出未取走时保持本级
				end
				default:begin
					reg_ccm_third_hold_red_center_right <= reg_ccm_third_red_center_right; // 与前两项和对齐延迟末项
				end
			endcase
		end
	end

	//red 通道 right 像素矩阵末项延迟值更新逻辑
	always@(posedge i_clk)begin
		if(i_rstn == 1'b0)begin
			reg_ccm_third_hold_red_right <= 24'd0; // 复位清空矩阵末项延迟值
		end else begin
			case(flag_freeze)
				1'b1:begin
					reg_ccm_third_hold_red_right <= reg_ccm_third_hold_red_right; // 输出未取走时保持本级
				end
				default:begin
					reg_ccm_third_hold_red_right <= reg_ccm_third_red_right; // 与前两项和对齐延迟末项
				end
			endcase
		end
	end

	//red 通道 left 像素矩阵三项和更新逻辑
	always@(posedge i_clk)begin
		if(i_rstn == 1'b0)begin
			reg_ccm_total_red_left <= 24'd0; // 复位清空矩阵三项和
		end else begin
			case(flag_freeze)
				1'b1:begin
					reg_ccm_total_red_left <= reg_ccm_total_red_left; // 输出未取走时保持本级
				end
				default:begin
					reg_ccm_total_red_left <= $signed(reg_ccm_partial_red_left) + $signed(reg_ccm_third_hold_red_left); // 累加已对齐的末项
				end
			endcase
		end
	end

	//red 通道 center_left 像素矩阵三项和更新逻辑
	always@(posedge i_clk)begin
		if(i_rstn == 1'b0)begin
			reg_ccm_total_red_center_left <= 24'd0; // 复位清空矩阵三项和
		end else begin
			case(flag_freeze)
				1'b1:begin
					reg_ccm_total_red_center_left <= reg_ccm_total_red_center_left; // 输出未取走时保持本级
				end
				default:begin
					reg_ccm_total_red_center_left <= $signed(reg_ccm_partial_red_center_left) + $signed(reg_ccm_third_hold_red_center_left); // 累加已对齐的末项
				end
			endcase
		end
	end

	//red 通道 center_right 像素矩阵三项和更新逻辑
	always@(posedge i_clk)begin
		if(i_rstn == 1'b0)begin
			reg_ccm_total_red_center_right <= 24'd0; // 复位清空矩阵三项和
		end else begin
			case(flag_freeze)
				1'b1:begin
					reg_ccm_total_red_center_right <= reg_ccm_total_red_center_right; // 输出未取走时保持本级
				end
				default:begin
					reg_ccm_total_red_center_right <= $signed(reg_ccm_partial_red_center_right) + $signed(reg_ccm_third_hold_red_center_right); // 累加已对齐的末项
				end
			endcase
		end
	end

	//red 通道 right 像素矩阵三项和更新逻辑
	always@(posedge i_clk)begin
		if(i_rstn == 1'b0)begin
			reg_ccm_total_red_right <= 24'd0; // 复位清空矩阵三项和
		end else begin
			case(flag_freeze)
				1'b1:begin
					reg_ccm_total_red_right <= reg_ccm_total_red_right; // 输出未取走时保持本级
				end
				default:begin
					reg_ccm_total_red_right <= $signed(reg_ccm_partial_red_right) + $signed(reg_ccm_third_hold_red_right); // 累加已对齐的末项
				end
			endcase
		end
	end

	//red 通道 left 像素矩阵圆整值更新逻辑
	always@(posedge i_clk)begin
		if(i_rstn == 1'b0)begin
			reg_ccm_round_red_left <= 24'd0; // 复位清空矩阵圆整值
		end else begin
			case(flag_freeze)
				1'b1:begin
					reg_ccm_round_red_left <= reg_ccm_round_red_left; // 输出未取走时保持本级
				end
				default:begin
					reg_ccm_round_red_left <= $signed(reg_ccm_total_red_left) + $signed(CCM_ROUND_VALUE[23:0]); // 叠加矩阵圆整常量
				end
			endcase
		end
	end

	//red 通道 center_left 像素矩阵圆整值更新逻辑
	always@(posedge i_clk)begin
		if(i_rstn == 1'b0)begin
			reg_ccm_round_red_center_left <= 24'd0; // 复位清空矩阵圆整值
		end else begin
			case(flag_freeze)
				1'b1:begin
					reg_ccm_round_red_center_left <= reg_ccm_round_red_center_left; // 输出未取走时保持本级
				end
				default:begin
					reg_ccm_round_red_center_left <= $signed(reg_ccm_total_red_center_left) + $signed(CCM_ROUND_VALUE[23:0]); // 叠加矩阵圆整常量
				end
			endcase
		end
	end

	//red 通道 center_right 像素矩阵圆整值更新逻辑
	always@(posedge i_clk)begin
		if(i_rstn == 1'b0)begin
			reg_ccm_round_red_center_right <= 24'd0; // 复位清空矩阵圆整值
		end else begin
			case(flag_freeze)
				1'b1:begin
					reg_ccm_round_red_center_right <= reg_ccm_round_red_center_right; // 输出未取走时保持本级
				end
				default:begin
					reg_ccm_round_red_center_right <= $signed(reg_ccm_total_red_center_right) + $signed(CCM_ROUND_VALUE[23:0]); // 叠加矩阵圆整常量
				end
			endcase
		end
	end

	//red 通道 right 像素矩阵圆整值更新逻辑
	always@(posedge i_clk)begin
		if(i_rstn == 1'b0)begin
			reg_ccm_round_red_right <= 24'd0; // 复位清空矩阵圆整值
		end else begin
			case(flag_freeze)
				1'b1:begin
					reg_ccm_round_red_right <= reg_ccm_round_red_right; // 输出未取走时保持本级
				end
				default:begin
					reg_ccm_round_red_right <= $signed(reg_ccm_total_red_right) + $signed(CCM_ROUND_VALUE[23:0]); // 叠加矩阵圆整常量
				end
			endcase
		end
	end

	//red 通道 left 像素矩阵移位值更新逻辑
	always@(posedge i_clk)begin
		if(i_rstn == 1'b0)begin
			reg_ccm_shift_red_left <= 24'd0; // 复位清空矩阵移位值
		end else begin
			case(flag_freeze)
				1'b1:begin
					reg_ccm_shift_red_left <= reg_ccm_shift_red_left; // 输出未取走时保持本级
				end
				default:begin
					reg_ccm_shift_red_left <= $signed(reg_ccm_round_red_left) >>> C_CCM_SHIFT; // 算术右移定点小数位
				end
			endcase
		end
	end

	//red 通道 center_left 像素矩阵移位值更新逻辑
	always@(posedge i_clk)begin
		if(i_rstn == 1'b0)begin
			reg_ccm_shift_red_center_left <= 24'd0; // 复位清空矩阵移位值
		end else begin
			case(flag_freeze)
				1'b1:begin
					reg_ccm_shift_red_center_left <= reg_ccm_shift_red_center_left; // 输出未取走时保持本级
				end
				default:begin
					reg_ccm_shift_red_center_left <= $signed(reg_ccm_round_red_center_left) >>> C_CCM_SHIFT; // 算术右移定点小数位
				end
			endcase
		end
	end

	//red 通道 center_right 像素矩阵移位值更新逻辑
	always@(posedge i_clk)begin
		if(i_rstn == 1'b0)begin
			reg_ccm_shift_red_center_right <= 24'd0; // 复位清空矩阵移位值
		end else begin
			case(flag_freeze)
				1'b1:begin
					reg_ccm_shift_red_center_right <= reg_ccm_shift_red_center_right; // 输出未取走时保持本级
				end
				default:begin
					reg_ccm_shift_red_center_right <= $signed(reg_ccm_round_red_center_right) >>> C_CCM_SHIFT; // 算术右移定点小数位
				end
			endcase
		end
	end

	//red 通道 right 像素矩阵移位值更新逻辑
	always@(posedge i_clk)begin
		if(i_rstn == 1'b0)begin
			reg_ccm_shift_red_right <= 24'd0; // 复位清空矩阵移位值
		end else begin
			case(flag_freeze)
				1'b1:begin
					reg_ccm_shift_red_right <= reg_ccm_shift_red_right; // 输出未取走时保持本级
				end
				default:begin
					reg_ccm_shift_red_right <= $signed(reg_ccm_round_red_right) >>> C_CCM_SHIFT; // 算术右移定点小数位
				end
			endcase
		end
	end

	//red 通道 left 像素矩阵下溢标志更新逻辑
	always@(posedge i_clk)begin
		if(i_rstn == 1'b0)begin
			flag_ccm_low_red_left <= 1'b0; // 复位清除下溢标志
		end else begin
			case(flag_freeze)
				1'b1:begin
					flag_ccm_low_red_left <= flag_ccm_low_red_left; // 输出未取走时保持本级
				end
				default:begin
					flag_ccm_low_red_left <= ($signed(reg_ccm_shift_red_left) < 0); // 判断负值下钳位
				end
			endcase
		end
	end

	//red 通道 center_left 像素矩阵下溢标志更新逻辑
	always@(posedge i_clk)begin
		if(i_rstn == 1'b0)begin
			flag_ccm_low_red_center_left <= 1'b0; // 复位清除下溢标志
		end else begin
			case(flag_freeze)
				1'b1:begin
					flag_ccm_low_red_center_left <= flag_ccm_low_red_center_left; // 输出未取走时保持本级
				end
				default:begin
					flag_ccm_low_red_center_left <= ($signed(reg_ccm_shift_red_center_left) < 0); // 判断负值下钳位
				end
			endcase
		end
	end

	//red 通道 center_right 像素矩阵下溢标志更新逻辑
	always@(posedge i_clk)begin
		if(i_rstn == 1'b0)begin
			flag_ccm_low_red_center_right <= 1'b0; // 复位清除下溢标志
		end else begin
			case(flag_freeze)
				1'b1:begin
					flag_ccm_low_red_center_right <= flag_ccm_low_red_center_right; // 输出未取走时保持本级
				end
				default:begin
					flag_ccm_low_red_center_right <= ($signed(reg_ccm_shift_red_center_right) < 0); // 判断负值下钳位
				end
			endcase
		end
	end

	//red 通道 right 像素矩阵下溢标志更新逻辑
	always@(posedge i_clk)begin
		if(i_rstn == 1'b0)begin
			flag_ccm_low_red_right <= 1'b0; // 复位清除下溢标志
		end else begin
			case(flag_freeze)
				1'b1:begin
					flag_ccm_low_red_right <= flag_ccm_low_red_right; // 输出未取走时保持本级
				end
				default:begin
					flag_ccm_low_red_right <= ($signed(reg_ccm_shift_red_right) < 0); // 判断负值下钳位
				end
			endcase
		end
	end

	//red 通道 left 像素矩阵下钳位延迟值更新逻辑
	always@(posedge i_clk)begin
		if(i_rstn == 1'b0)begin
			reg_ccm_delay_low_red_left <= 24'd0; // 复位清空下钳位延迟值
		end else begin
			case(flag_freeze)
				1'b1:begin
					reg_ccm_delay_low_red_left <= reg_ccm_delay_low_red_left; // 输出未取走时保持本级
				end
				default:begin
					reg_ccm_delay_low_red_left <= reg_ccm_shift_red_left; // 与下溢标志对齐延迟移位值
				end
			endcase
		end
	end

	//red 通道 center_left 像素矩阵下钳位延迟值更新逻辑
	always@(posedge i_clk)begin
		if(i_rstn == 1'b0)begin
			reg_ccm_delay_low_red_center_left <= 24'd0; // 复位清空下钳位延迟值
		end else begin
			case(flag_freeze)
				1'b1:begin
					reg_ccm_delay_low_red_center_left <= reg_ccm_delay_low_red_center_left; // 输出未取走时保持本级
				end
				default:begin
					reg_ccm_delay_low_red_center_left <= reg_ccm_shift_red_center_left; // 与下溢标志对齐延迟移位值
				end
			endcase
		end
	end

	//red 通道 center_right 像素矩阵下钳位延迟值更新逻辑
	always@(posedge i_clk)begin
		if(i_rstn == 1'b0)begin
			reg_ccm_delay_low_red_center_right <= 24'd0; // 复位清空下钳位延迟值
		end else begin
			case(flag_freeze)
				1'b1:begin
					reg_ccm_delay_low_red_center_right <= reg_ccm_delay_low_red_center_right; // 输出未取走时保持本级
				end
				default:begin
					reg_ccm_delay_low_red_center_right <= reg_ccm_shift_red_center_right; // 与下溢标志对齐延迟移位值
				end
			endcase
		end
	end

	//red 通道 right 像素矩阵下钳位延迟值更新逻辑
	always@(posedge i_clk)begin
		if(i_rstn == 1'b0)begin
			reg_ccm_delay_low_red_right <= 24'd0; // 复位清空下钳位延迟值
		end else begin
			case(flag_freeze)
				1'b1:begin
					reg_ccm_delay_low_red_right <= reg_ccm_delay_low_red_right; // 输出未取走时保持本级
				end
				default:begin
					reg_ccm_delay_low_red_right <= reg_ccm_shift_red_right; // 与下溢标志对齐延迟移位值
				end
			endcase
		end
	end

	//red 通道 left 像素矩阵下钳位值更新逻辑
	always@(posedge i_clk)begin
		if(i_rstn == 1'b0)begin
			reg_ccm_low_red_left <= 24'd0; // 复位清空下钳位值
		end else begin
			case(flag_freeze)
				1'b1:begin
					reg_ccm_low_red_left <= reg_ccm_low_red_left; // 输出未取走时保持本级
				end
				default:begin
					reg_ccm_low_red_left <= flag_ccm_low_red_left ? 24'd0 : reg_ccm_delay_low_red_left; // 负值钳位到零
				end
			endcase
		end
	end

	//red 通道 center_left 像素矩阵下钳位值更新逻辑
	always@(posedge i_clk)begin
		if(i_rstn == 1'b0)begin
			reg_ccm_low_red_center_left <= 24'd0; // 复位清空下钳位值
		end else begin
			case(flag_freeze)
				1'b1:begin
					reg_ccm_low_red_center_left <= reg_ccm_low_red_center_left; // 输出未取走时保持本级
				end
				default:begin
					reg_ccm_low_red_center_left <= flag_ccm_low_red_center_left ? 24'd0 : reg_ccm_delay_low_red_center_left; // 负值钳位到零
				end
			endcase
		end
	end

	//red 通道 center_right 像素矩阵下钳位值更新逻辑
	always@(posedge i_clk)begin
		if(i_rstn == 1'b0)begin
			reg_ccm_low_red_center_right <= 24'd0; // 复位清空下钳位值
		end else begin
			case(flag_freeze)
				1'b1:begin
					reg_ccm_low_red_center_right <= reg_ccm_low_red_center_right; // 输出未取走时保持本级
				end
				default:begin
					reg_ccm_low_red_center_right <= flag_ccm_low_red_center_right ? 24'd0 : reg_ccm_delay_low_red_center_right; // 负值钳位到零
				end
			endcase
		end
	end

	//red 通道 right 像素矩阵下钳位值更新逻辑
	always@(posedge i_clk)begin
		if(i_rstn == 1'b0)begin
			reg_ccm_low_red_right <= 24'd0; // 复位清空下钳位值
		end else begin
			case(flag_freeze)
				1'b1:begin
					reg_ccm_low_red_right <= reg_ccm_low_red_right; // 输出未取走时保持本级
				end
				default:begin
					reg_ccm_low_red_right <= flag_ccm_low_red_right ? 24'd0 : reg_ccm_delay_low_red_right; // 负值钳位到零
				end
			endcase
		end
	end

	//red 通道 left 像素矩阵下溢延迟标志更新逻辑
	always@(posedge i_clk)begin
		if(i_rstn == 1'b0)begin
			flag_ccm_low_hold_first_red_left <= 1'b0; // 复位清除下溢延迟标志
		end else begin
			case(flag_freeze)
				1'b1:begin
					flag_ccm_low_hold_first_red_left <= flag_ccm_low_hold_first_red_left; // 输出未取走时保持本级
				end
				default:begin
					flag_ccm_low_hold_first_red_left <= flag_ccm_low_red_left; // 延迟下溢标志以待合并
				end
			endcase
		end
	end

	//red 通道 center_left 像素矩阵下溢延迟标志更新逻辑
	always@(posedge i_clk)begin
		if(i_rstn == 1'b0)begin
			flag_ccm_low_hold_first_red_center_left <= 1'b0; // 复位清除下溢延迟标志
		end else begin
			case(flag_freeze)
				1'b1:begin
					flag_ccm_low_hold_first_red_center_left <= flag_ccm_low_hold_first_red_center_left; // 输出未取走时保持本级
				end
				default:begin
					flag_ccm_low_hold_first_red_center_left <= flag_ccm_low_red_center_left; // 延迟下溢标志以待合并
				end
			endcase
		end
	end

	//red 通道 center_right 像素矩阵下溢延迟标志更新逻辑
	always@(posedge i_clk)begin
		if(i_rstn == 1'b0)begin
			flag_ccm_low_hold_first_red_center_right <= 1'b0; // 复位清除下溢延迟标志
		end else begin
			case(flag_freeze)
				1'b1:begin
					flag_ccm_low_hold_first_red_center_right <= flag_ccm_low_hold_first_red_center_right; // 输出未取走时保持本级
				end
				default:begin
					flag_ccm_low_hold_first_red_center_right <= flag_ccm_low_red_center_right; // 延迟下溢标志以待合并
				end
			endcase
		end
	end

	//red 通道 right 像素矩阵下溢延迟标志更新逻辑
	always@(posedge i_clk)begin
		if(i_rstn == 1'b0)begin
			flag_ccm_low_hold_first_red_right <= 1'b0; // 复位清除下溢延迟标志
		end else begin
			case(flag_freeze)
				1'b1:begin
					flag_ccm_low_hold_first_red_right <= flag_ccm_low_hold_first_red_right; // 输出未取走时保持本级
				end
				default:begin
					flag_ccm_low_hold_first_red_right <= flag_ccm_low_red_right; // 延迟下溢标志以待合并
				end
			endcase
		end
	end

	//red 通道 left 像素矩阵上溢标志更新逻辑
	always@(posedge i_clk)begin
		if(i_rstn == 1'b0)begin
			flag_ccm_high_red_left <= 1'b0; // 复位清除上溢标志
		end else begin
			case(flag_freeze)
				1'b1:begin
					flag_ccm_high_red_left <= flag_ccm_high_red_left; // 输出未取走时保持本级
				end
				default:begin
					flag_ccm_high_red_left <= (reg_ccm_low_red_left > C_CCM_MAX); // 比较矩阵上限
				end
			endcase
		end
	end

	//red 通道 center_left 像素矩阵上溢标志更新逻辑
	always@(posedge i_clk)begin
		if(i_rstn == 1'b0)begin
			flag_ccm_high_red_center_left <= 1'b0; // 复位清除上溢标志
		end else begin
			case(flag_freeze)
				1'b1:begin
					flag_ccm_high_red_center_left <= flag_ccm_high_red_center_left; // 输出未取走时保持本级
				end
				default:begin
					flag_ccm_high_red_center_left <= (reg_ccm_low_red_center_left > C_CCM_MAX); // 比较矩阵上限
				end
			endcase
		end
	end

	//red 通道 center_right 像素矩阵上溢标志更新逻辑
	always@(posedge i_clk)begin
		if(i_rstn == 1'b0)begin
			flag_ccm_high_red_center_right <= 1'b0; // 复位清除上溢标志
		end else begin
			case(flag_freeze)
				1'b1:begin
					flag_ccm_high_red_center_right <= flag_ccm_high_red_center_right; // 输出未取走时保持本级
				end
				default:begin
					flag_ccm_high_red_center_right <= (reg_ccm_low_red_center_right > C_CCM_MAX); // 比较矩阵上限
				end
			endcase
		end
	end

	//red 通道 right 像素矩阵上溢标志更新逻辑
	always@(posedge i_clk)begin
		if(i_rstn == 1'b0)begin
			flag_ccm_high_red_right <= 1'b0; // 复位清除上溢标志
		end else begin
			case(flag_freeze)
				1'b1:begin
					flag_ccm_high_red_right <= flag_ccm_high_red_right; // 输出未取走时保持本级
				end
				default:begin
					flag_ccm_high_red_right <= (reg_ccm_low_red_right > C_CCM_MAX); // 比较矩阵上限
				end
			endcase
		end
	end

	//red 通道 left 像素矩阵上钳位延迟值更新逻辑
	always@(posedge i_clk)begin
		if(i_rstn == 1'b0)begin
			reg_ccm_delay_level_red_left <= 24'd0; // 复位清空上钳位延迟值
		end else begin
			case(flag_freeze)
				1'b1:begin
					reg_ccm_delay_level_red_left <= reg_ccm_delay_level_red_left; // 输出未取走时保持本级
				end
				default:begin
					reg_ccm_delay_level_red_left <= reg_ccm_low_red_left; // 与上溢标志对齐延迟下钳位值
				end
			endcase
		end
	end

	//red 通道 center_left 像素矩阵上钳位延迟值更新逻辑
	always@(posedge i_clk)begin
		if(i_rstn == 1'b0)begin
			reg_ccm_delay_level_red_center_left <= 24'd0; // 复位清空上钳位延迟值
		end else begin
			case(flag_freeze)
				1'b1:begin
					reg_ccm_delay_level_red_center_left <= reg_ccm_delay_level_red_center_left; // 输出未取走时保持本级
				end
				default:begin
					reg_ccm_delay_level_red_center_left <= reg_ccm_low_red_center_left; // 与上溢标志对齐延迟下钳位值
				end
			endcase
		end
	end

	//red 通道 center_right 像素矩阵上钳位延迟值更新逻辑
	always@(posedge i_clk)begin
		if(i_rstn == 1'b0)begin
			reg_ccm_delay_level_red_center_right <= 24'd0; // 复位清空上钳位延迟值
		end else begin
			case(flag_freeze)
				1'b1:begin
					reg_ccm_delay_level_red_center_right <= reg_ccm_delay_level_red_center_right; // 输出未取走时保持本级
				end
				default:begin
					reg_ccm_delay_level_red_center_right <= reg_ccm_low_red_center_right; // 与上溢标志对齐延迟下钳位值
				end
			endcase
		end
	end

	//red 通道 right 像素矩阵上钳位延迟值更新逻辑
	always@(posedge i_clk)begin
		if(i_rstn == 1'b0)begin
			reg_ccm_delay_level_red_right <= 24'd0; // 复位清空上钳位延迟值
		end else begin
			case(flag_freeze)
				1'b1:begin
					reg_ccm_delay_level_red_right <= reg_ccm_delay_level_red_right; // 输出未取走时保持本级
				end
				default:begin
					reg_ccm_delay_level_red_right <= reg_ccm_low_red_right; // 与上溢标志对齐延迟下钳位值
				end
			endcase
		end
	end

	//red 通道 left 像素矩阵下溢二次延迟标志更新逻辑
	always@(posedge i_clk)begin
		if(i_rstn == 1'b0)begin
			flag_ccm_low_hold_second_red_left <= 1'b0; // 复位清除下溢二次延迟标志
		end else begin
			case(flag_freeze)
				1'b1:begin
					flag_ccm_low_hold_second_red_left <= flag_ccm_low_hold_second_red_left; // 输出未取走时保持本级
				end
				default:begin
					flag_ccm_low_hold_second_red_left <= flag_ccm_low_hold_first_red_left; // 二级延迟对齐上溢标志
				end
			endcase
		end
	end

	//red 通道 center_left 像素矩阵下溢二次延迟标志更新逻辑
	always@(posedge i_clk)begin
		if(i_rstn == 1'b0)begin
			flag_ccm_low_hold_second_red_center_left <= 1'b0; // 复位清除下溢二次延迟标志
		end else begin
			case(flag_freeze)
				1'b1:begin
					flag_ccm_low_hold_second_red_center_left <= flag_ccm_low_hold_second_red_center_left; // 输出未取走时保持本级
				end
				default:begin
					flag_ccm_low_hold_second_red_center_left <= flag_ccm_low_hold_first_red_center_left; // 二级延迟对齐上溢标志
				end
			endcase
		end
	end

	//red 通道 center_right 像素矩阵下溢二次延迟标志更新逻辑
	always@(posedge i_clk)begin
		if(i_rstn == 1'b0)begin
			flag_ccm_low_hold_second_red_center_right <= 1'b0; // 复位清除下溢二次延迟标志
		end else begin
			case(flag_freeze)
				1'b1:begin
					flag_ccm_low_hold_second_red_center_right <= flag_ccm_low_hold_second_red_center_right; // 输出未取走时保持本级
				end
				default:begin
					flag_ccm_low_hold_second_red_center_right <= flag_ccm_low_hold_first_red_center_right; // 二级延迟对齐上溢标志
				end
			endcase
		end
	end

	//red 通道 right 像素矩阵下溢二次延迟标志更新逻辑
	always@(posedge i_clk)begin
		if(i_rstn == 1'b0)begin
			flag_ccm_low_hold_second_red_right <= 1'b0; // 复位清除下溢二次延迟标志
		end else begin
			case(flag_freeze)
				1'b1:begin
					flag_ccm_low_hold_second_red_right <= flag_ccm_low_hold_second_red_right; // 输出未取走时保持本级
				end
				default:begin
					flag_ccm_low_hold_second_red_right <= flag_ccm_low_hold_first_red_right; // 二级延迟对齐上溢标志
				end
			endcase
		end
	end

	//red 通道 left 像素矩阵输出码值更新逻辑
	always@(posedge i_clk)begin
		if(i_rstn == 1'b0)begin
			reg_ccm_level_red_left <= 10'd0; // 复位清空矩阵输出码值
		end else begin
			case(flag_freeze)
				1'b1:begin
					reg_ccm_level_red_left <= reg_ccm_level_red_left; // 输出未取走时保持本级
				end
				default:begin
					reg_ccm_level_red_left <= flag_ccm_high_red_left ? C_CCM_MAX : reg_ccm_delay_level_red_left[9:0]; // 按上溢标志选择上限
				end
			endcase
		end
	end

	//red 通道 center_left 像素矩阵输出码值更新逻辑
	always@(posedge i_clk)begin
		if(i_rstn == 1'b0)begin
			reg_ccm_level_red_center_left <= 10'd0; // 复位清空矩阵输出码值
		end else begin
			case(flag_freeze)
				1'b1:begin
					reg_ccm_level_red_center_left <= reg_ccm_level_red_center_left; // 输出未取走时保持本级
				end
				default:begin
					reg_ccm_level_red_center_left <= flag_ccm_high_red_center_left ? C_CCM_MAX : reg_ccm_delay_level_red_center_left[9:0]; // 按上溢标志选择上限
				end
			endcase
		end
	end

	//red 通道 center_right 像素矩阵输出码值更新逻辑
	always@(posedge i_clk)begin
		if(i_rstn == 1'b0)begin
			reg_ccm_level_red_center_right <= 10'd0; // 复位清空矩阵输出码值
		end else begin
			case(flag_freeze)
				1'b1:begin
					reg_ccm_level_red_center_right <= reg_ccm_level_red_center_right; // 输出未取走时保持本级
				end
				default:begin
					reg_ccm_level_red_center_right <= flag_ccm_high_red_center_right ? C_CCM_MAX : reg_ccm_delay_level_red_center_right[9:0]; // 按上溢标志选择上限
				end
			endcase
		end
	end

	//red 通道 right 像素矩阵输出码值更新逻辑
	always@(posedge i_clk)begin
		if(i_rstn == 1'b0)begin
			reg_ccm_level_red_right <= 10'd0; // 复位清空矩阵输出码值
		end else begin
			case(flag_freeze)
				1'b1:begin
					reg_ccm_level_red_right <= reg_ccm_level_red_right; // 输出未取走时保持本级
				end
				default:begin
					reg_ccm_level_red_right <= flag_ccm_high_red_right ? C_CCM_MAX : reg_ccm_delay_level_red_right[9:0]; // 按上溢标志选择上限
				end
			endcase
		end
	end

	//red 通道 left 像素矩阵饱和标志更新逻辑
	always@(posedge i_clk)begin
		if(i_rstn == 1'b0)begin
			flag_ccm_channel_red_left <= 1'b0; // 复位清除通道饱和标志
		end else begin
			case(flag_freeze)
				1'b1:begin
					flag_ccm_channel_red_left <= flag_ccm_channel_red_left; // 输出未取走时保持本级
				end
				default:begin
					flag_ccm_channel_red_left <= flag_ccm_low_hold_second_red_left | flag_ccm_high_red_left; // 归并同拍矩阵上下溢
				end
			endcase
		end
	end

	//red 通道 center_left 像素矩阵饱和标志更新逻辑
	always@(posedge i_clk)begin
		if(i_rstn == 1'b0)begin
			flag_ccm_channel_red_center_left <= 1'b0; // 复位清除通道饱和标志
		end else begin
			case(flag_freeze)
				1'b1:begin
					flag_ccm_channel_red_center_left <= flag_ccm_channel_red_center_left; // 输出未取走时保持本级
				end
				default:begin
					flag_ccm_channel_red_center_left <= flag_ccm_low_hold_second_red_center_left | flag_ccm_high_red_center_left; // 归并同拍矩阵上下溢
				end
			endcase
		end
	end

	//red 通道 center_right 像素矩阵饱和标志更新逻辑
	always@(posedge i_clk)begin
		if(i_rstn == 1'b0)begin
			flag_ccm_channel_red_center_right <= 1'b0; // 复位清除通道饱和标志
		end else begin
			case(flag_freeze)
				1'b1:begin
					flag_ccm_channel_red_center_right <= flag_ccm_channel_red_center_right; // 输出未取走时保持本级
				end
				default:begin
					flag_ccm_channel_red_center_right <= flag_ccm_low_hold_second_red_center_right | flag_ccm_high_red_center_right; // 归并同拍矩阵上下溢
				end
			endcase
		end
	end

	//red 通道 right 像素矩阵饱和标志更新逻辑
	always@(posedge i_clk)begin
		if(i_rstn == 1'b0)begin
			flag_ccm_channel_red_right <= 1'b0; // 复位清除通道饱和标志
		end else begin
			case(flag_freeze)
				1'b1:begin
					flag_ccm_channel_red_right <= flag_ccm_channel_red_right; // 输出未取走时保持本级
				end
				default:begin
					flag_ccm_channel_red_right <= flag_ccm_low_hold_second_red_right | flag_ccm_high_red_right; // 归并同拍矩阵上下溢
				end
			endcase
		end
	end

	//green 通道 left 像素矩阵首项更新逻辑
	always@(posedge i_clk)begin
		if(i_rstn == 1'b0)begin
			reg_ccm_first_green_left <= 24'd0; // 复位清空矩阵首项
		end else begin
			case(flag_freeze)
				1'b1:begin
					reg_ccm_first_green_left <= reg_ccm_first_green_left; // 输出未取走时保持本级
				end
				default:begin
					reg_ccm_first_green_left <= $signed({1'b0, reg_wb_level_red_left}) * $signed(C_CCM_M10); // 首项乘加系数
				end
			endcase
		end
	end

	//green 通道 center_left 像素矩阵首项更新逻辑
	always@(posedge i_clk)begin
		if(i_rstn == 1'b0)begin
			reg_ccm_first_green_center_left <= 24'd0; // 复位清空矩阵首项
		end else begin
			case(flag_freeze)
				1'b1:begin
					reg_ccm_first_green_center_left <= reg_ccm_first_green_center_left; // 输出未取走时保持本级
				end
				default:begin
					reg_ccm_first_green_center_left <= $signed({1'b0, reg_wb_level_red_center_left}) * $signed(C_CCM_M10); // 首项乘加系数
				end
			endcase
		end
	end

	//green 通道 center_right 像素矩阵首项更新逻辑
	always@(posedge i_clk)begin
		if(i_rstn == 1'b0)begin
			reg_ccm_first_green_center_right <= 24'd0; // 复位清空矩阵首项
		end else begin
			case(flag_freeze)
				1'b1:begin
					reg_ccm_first_green_center_right <= reg_ccm_first_green_center_right; // 输出未取走时保持本级
				end
				default:begin
					reg_ccm_first_green_center_right <= $signed({1'b0, reg_wb_level_red_center_right}) * $signed(C_CCM_M10); // 首项乘加系数
				end
			endcase
		end
	end

	//green 通道 right 像素矩阵首项更新逻辑
	always@(posedge i_clk)begin
		if(i_rstn == 1'b0)begin
			reg_ccm_first_green_right <= 24'd0; // 复位清空矩阵首项
		end else begin
			case(flag_freeze)
				1'b1:begin
					reg_ccm_first_green_right <= reg_ccm_first_green_right; // 输出未取走时保持本级
				end
				default:begin
					reg_ccm_first_green_right <= $signed({1'b0, reg_wb_level_red_right}) * $signed(C_CCM_M10); // 首项乘加系数
				end
			endcase
		end
	end

	//green 通道 left 像素矩阵次项更新逻辑
	always@(posedge i_clk)begin
		if(i_rstn == 1'b0)begin
			reg_ccm_second_green_left <= 24'd0; // 复位清空矩阵次项
		end else begin
			case(flag_freeze)
				1'b1:begin
					reg_ccm_second_green_left <= reg_ccm_second_green_left; // 输出未取走时保持本级
				end
				default:begin
					reg_ccm_second_green_left <= $signed({1'b0, reg_wb_level_green_left}) * $signed(C_CCM_M11); // 次项乘加系数
				end
			endcase
		end
	end

	//green 通道 center_left 像素矩阵次项更新逻辑
	always@(posedge i_clk)begin
		if(i_rstn == 1'b0)begin
			reg_ccm_second_green_center_left <= 24'd0; // 复位清空矩阵次项
		end else begin
			case(flag_freeze)
				1'b1:begin
					reg_ccm_second_green_center_left <= reg_ccm_second_green_center_left; // 输出未取走时保持本级
				end
				default:begin
					reg_ccm_second_green_center_left <= $signed({1'b0, reg_wb_level_green_center_left}) * $signed(C_CCM_M11); // 次项乘加系数
				end
			endcase
		end
	end

	//green 通道 center_right 像素矩阵次项更新逻辑
	always@(posedge i_clk)begin
		if(i_rstn == 1'b0)begin
			reg_ccm_second_green_center_right <= 24'd0; // 复位清空矩阵次项
		end else begin
			case(flag_freeze)
				1'b1:begin
					reg_ccm_second_green_center_right <= reg_ccm_second_green_center_right; // 输出未取走时保持本级
				end
				default:begin
					reg_ccm_second_green_center_right <= $signed({1'b0, reg_wb_level_green_center_right}) * $signed(C_CCM_M11); // 次项乘加系数
				end
			endcase
		end
	end

	//green 通道 right 像素矩阵次项更新逻辑
	always@(posedge i_clk)begin
		if(i_rstn == 1'b0)begin
			reg_ccm_second_green_right <= 24'd0; // 复位清空矩阵次项
		end else begin
			case(flag_freeze)
				1'b1:begin
					reg_ccm_second_green_right <= reg_ccm_second_green_right; // 输出未取走时保持本级
				end
				default:begin
					reg_ccm_second_green_right <= $signed({1'b0, reg_wb_level_green_right}) * $signed(C_CCM_M11); // 次项乘加系数
				end
			endcase
		end
	end

	//green 通道 left 像素矩阵末项更新逻辑
	always@(posedge i_clk)begin
		if(i_rstn == 1'b0)begin
			reg_ccm_third_green_left <= 24'd0; // 复位清空矩阵末项
		end else begin
			case(flag_freeze)
				1'b1:begin
					reg_ccm_third_green_left <= reg_ccm_third_green_left; // 输出未取走时保持本级
				end
				default:begin
					reg_ccm_third_green_left <= $signed({1'b0, reg_wb_level_blue_left}) * $signed(C_CCM_M12); // 末项乘加系数
				end
			endcase
		end
	end

	//green 通道 center_left 像素矩阵末项更新逻辑
	always@(posedge i_clk)begin
		if(i_rstn == 1'b0)begin
			reg_ccm_third_green_center_left <= 24'd0; // 复位清空矩阵末项
		end else begin
			case(flag_freeze)
				1'b1:begin
					reg_ccm_third_green_center_left <= reg_ccm_third_green_center_left; // 输出未取走时保持本级
				end
				default:begin
					reg_ccm_third_green_center_left <= $signed({1'b0, reg_wb_level_blue_center_left}) * $signed(C_CCM_M12); // 末项乘加系数
				end
			endcase
		end
	end

	//green 通道 center_right 像素矩阵末项更新逻辑
	always@(posedge i_clk)begin
		if(i_rstn == 1'b0)begin
			reg_ccm_third_green_center_right <= 24'd0; // 复位清空矩阵末项
		end else begin
			case(flag_freeze)
				1'b1:begin
					reg_ccm_third_green_center_right <= reg_ccm_third_green_center_right; // 输出未取走时保持本级
				end
				default:begin
					reg_ccm_third_green_center_right <= $signed({1'b0, reg_wb_level_blue_center_right}) * $signed(C_CCM_M12); // 末项乘加系数
				end
			endcase
		end
	end

	//green 通道 right 像素矩阵末项更新逻辑
	always@(posedge i_clk)begin
		if(i_rstn == 1'b0)begin
			reg_ccm_third_green_right <= 24'd0; // 复位清空矩阵末项
		end else begin
			case(flag_freeze)
				1'b1:begin
					reg_ccm_third_green_right <= reg_ccm_third_green_right; // 输出未取走时保持本级
				end
				default:begin
					reg_ccm_third_green_right <= $signed({1'b0, reg_wb_level_blue_right}) * $signed(C_CCM_M12); // 末项乘加系数
				end
			endcase
		end
	end

	//green 通道 left 像素矩阵前两项和更新逻辑
	always@(posedge i_clk)begin
		if(i_rstn == 1'b0)begin
			reg_ccm_partial_green_left <= 24'd0; // 复位清空矩阵前两项和
		end else begin
			case(flag_freeze)
				1'b1:begin
					reg_ccm_partial_green_left <= reg_ccm_partial_green_left; // 输出未取走时保持本级
				end
				default:begin
					reg_ccm_partial_green_left <= $signed(reg_ccm_first_green_left) + $signed(reg_ccm_second_green_left); // 累加前两项
				end
			endcase
		end
	end

	//green 通道 center_left 像素矩阵前两项和更新逻辑
	always@(posedge i_clk)begin
		if(i_rstn == 1'b0)begin
			reg_ccm_partial_green_center_left <= 24'd0; // 复位清空矩阵前两项和
		end else begin
			case(flag_freeze)
				1'b1:begin
					reg_ccm_partial_green_center_left <= reg_ccm_partial_green_center_left; // 输出未取走时保持本级
				end
				default:begin
					reg_ccm_partial_green_center_left <= $signed(reg_ccm_first_green_center_left) + $signed(reg_ccm_second_green_center_left); // 累加前两项
				end
			endcase
		end
	end

	//green 通道 center_right 像素矩阵前两项和更新逻辑
	always@(posedge i_clk)begin
		if(i_rstn == 1'b0)begin
			reg_ccm_partial_green_center_right <= 24'd0; // 复位清空矩阵前两项和
		end else begin
			case(flag_freeze)
				1'b1:begin
					reg_ccm_partial_green_center_right <= reg_ccm_partial_green_center_right; // 输出未取走时保持本级
				end
				default:begin
					reg_ccm_partial_green_center_right <= $signed(reg_ccm_first_green_center_right) + $signed(reg_ccm_second_green_center_right); // 累加前两项
				end
			endcase
		end
	end

	//green 通道 right 像素矩阵前两项和更新逻辑
	always@(posedge i_clk)begin
		if(i_rstn == 1'b0)begin
			reg_ccm_partial_green_right <= 24'd0; // 复位清空矩阵前两项和
		end else begin
			case(flag_freeze)
				1'b1:begin
					reg_ccm_partial_green_right <= reg_ccm_partial_green_right; // 输出未取走时保持本级
				end
				default:begin
					reg_ccm_partial_green_right <= $signed(reg_ccm_first_green_right) + $signed(reg_ccm_second_green_right); // 累加前两项
				end
			endcase
		end
	end

	//green 通道 left 像素矩阵末项延迟值更新逻辑
	always@(posedge i_clk)begin
		if(i_rstn == 1'b0)begin
			reg_ccm_third_hold_green_left <= 24'd0; // 复位清空矩阵末项延迟值
		end else begin
			case(flag_freeze)
				1'b1:begin
					reg_ccm_third_hold_green_left <= reg_ccm_third_hold_green_left; // 输出未取走时保持本级
				end
				default:begin
					reg_ccm_third_hold_green_left <= reg_ccm_third_green_left; // 与前两项和对齐延迟末项
				end
			endcase
		end
	end

	//green 通道 center_left 像素矩阵末项延迟值更新逻辑
	always@(posedge i_clk)begin
		if(i_rstn == 1'b0)begin
			reg_ccm_third_hold_green_center_left <= 24'd0; // 复位清空矩阵末项延迟值
		end else begin
			case(flag_freeze)
				1'b1:begin
					reg_ccm_third_hold_green_center_left <= reg_ccm_third_hold_green_center_left; // 输出未取走时保持本级
				end
				default:begin
					reg_ccm_third_hold_green_center_left <= reg_ccm_third_green_center_left; // 与前两项和对齐延迟末项
				end
			endcase
		end
	end

	//green 通道 center_right 像素矩阵末项延迟值更新逻辑
	always@(posedge i_clk)begin
		if(i_rstn == 1'b0)begin
			reg_ccm_third_hold_green_center_right <= 24'd0; // 复位清空矩阵末项延迟值
		end else begin
			case(flag_freeze)
				1'b1:begin
					reg_ccm_third_hold_green_center_right <= reg_ccm_third_hold_green_center_right; // 输出未取走时保持本级
				end
				default:begin
					reg_ccm_third_hold_green_center_right <= reg_ccm_third_green_center_right; // 与前两项和对齐延迟末项
				end
			endcase
		end
	end

	//green 通道 right 像素矩阵末项延迟值更新逻辑
	always@(posedge i_clk)begin
		if(i_rstn == 1'b0)begin
			reg_ccm_third_hold_green_right <= 24'd0; // 复位清空矩阵末项延迟值
		end else begin
			case(flag_freeze)
				1'b1:begin
					reg_ccm_third_hold_green_right <= reg_ccm_third_hold_green_right; // 输出未取走时保持本级
				end
				default:begin
					reg_ccm_third_hold_green_right <= reg_ccm_third_green_right; // 与前两项和对齐延迟末项
				end
			endcase
		end
	end

	//green 通道 left 像素矩阵三项和更新逻辑
	always@(posedge i_clk)begin
		if(i_rstn == 1'b0)begin
			reg_ccm_total_green_left <= 24'd0; // 复位清空矩阵三项和
		end else begin
			case(flag_freeze)
				1'b1:begin
					reg_ccm_total_green_left <= reg_ccm_total_green_left; // 输出未取走时保持本级
				end
				default:begin
					reg_ccm_total_green_left <= $signed(reg_ccm_partial_green_left) + $signed(reg_ccm_third_hold_green_left); // 累加已对齐的末项
				end
			endcase
		end
	end

	//green 通道 center_left 像素矩阵三项和更新逻辑
	always@(posedge i_clk)begin
		if(i_rstn == 1'b0)begin
			reg_ccm_total_green_center_left <= 24'd0; // 复位清空矩阵三项和
		end else begin
			case(flag_freeze)
				1'b1:begin
					reg_ccm_total_green_center_left <= reg_ccm_total_green_center_left; // 输出未取走时保持本级
				end
				default:begin
					reg_ccm_total_green_center_left <= $signed(reg_ccm_partial_green_center_left) + $signed(reg_ccm_third_hold_green_center_left); // 累加已对齐的末项
				end
			endcase
		end
	end

	//green 通道 center_right 像素矩阵三项和更新逻辑
	always@(posedge i_clk)begin
		if(i_rstn == 1'b0)begin
			reg_ccm_total_green_center_right <= 24'd0; // 复位清空矩阵三项和
		end else begin
			case(flag_freeze)
				1'b1:begin
					reg_ccm_total_green_center_right <= reg_ccm_total_green_center_right; // 输出未取走时保持本级
				end
				default:begin
					reg_ccm_total_green_center_right <= $signed(reg_ccm_partial_green_center_right) + $signed(reg_ccm_third_hold_green_center_right); // 累加已对齐的末项
				end
			endcase
		end
	end

	//green 通道 right 像素矩阵三项和更新逻辑
	always@(posedge i_clk)begin
		if(i_rstn == 1'b0)begin
			reg_ccm_total_green_right <= 24'd0; // 复位清空矩阵三项和
		end else begin
			case(flag_freeze)
				1'b1:begin
					reg_ccm_total_green_right <= reg_ccm_total_green_right; // 输出未取走时保持本级
				end
				default:begin
					reg_ccm_total_green_right <= $signed(reg_ccm_partial_green_right) + $signed(reg_ccm_third_hold_green_right); // 累加已对齐的末项
				end
			endcase
		end
	end

	//green 通道 left 像素矩阵圆整值更新逻辑
	always@(posedge i_clk)begin
		if(i_rstn == 1'b0)begin
			reg_ccm_round_green_left <= 24'd0; // 复位清空矩阵圆整值
		end else begin
			case(flag_freeze)
				1'b1:begin
					reg_ccm_round_green_left <= reg_ccm_round_green_left; // 输出未取走时保持本级
				end
				default:begin
					reg_ccm_round_green_left <= $signed(reg_ccm_total_green_left) + $signed(CCM_ROUND_VALUE[23:0]); // 叠加矩阵圆整常量
				end
			endcase
		end
	end

	//green 通道 center_left 像素矩阵圆整值更新逻辑
	always@(posedge i_clk)begin
		if(i_rstn == 1'b0)begin
			reg_ccm_round_green_center_left <= 24'd0; // 复位清空矩阵圆整值
		end else begin
			case(flag_freeze)
				1'b1:begin
					reg_ccm_round_green_center_left <= reg_ccm_round_green_center_left; // 输出未取走时保持本级
				end
				default:begin
					reg_ccm_round_green_center_left <= $signed(reg_ccm_total_green_center_left) + $signed(CCM_ROUND_VALUE[23:0]); // 叠加矩阵圆整常量
				end
			endcase
		end
	end

	//green 通道 center_right 像素矩阵圆整值更新逻辑
	always@(posedge i_clk)begin
		if(i_rstn == 1'b0)begin
			reg_ccm_round_green_center_right <= 24'd0; // 复位清空矩阵圆整值
		end else begin
			case(flag_freeze)
				1'b1:begin
					reg_ccm_round_green_center_right <= reg_ccm_round_green_center_right; // 输出未取走时保持本级
				end
				default:begin
					reg_ccm_round_green_center_right <= $signed(reg_ccm_total_green_center_right) + $signed(CCM_ROUND_VALUE[23:0]); // 叠加矩阵圆整常量
				end
			endcase
		end
	end

	//green 通道 right 像素矩阵圆整值更新逻辑
	always@(posedge i_clk)begin
		if(i_rstn == 1'b0)begin
			reg_ccm_round_green_right <= 24'd0; // 复位清空矩阵圆整值
		end else begin
			case(flag_freeze)
				1'b1:begin
					reg_ccm_round_green_right <= reg_ccm_round_green_right; // 输出未取走时保持本级
				end
				default:begin
					reg_ccm_round_green_right <= $signed(reg_ccm_total_green_right) + $signed(CCM_ROUND_VALUE[23:0]); // 叠加矩阵圆整常量
				end
			endcase
		end
	end

	//green 通道 left 像素矩阵移位值更新逻辑
	always@(posedge i_clk)begin
		if(i_rstn == 1'b0)begin
			reg_ccm_shift_green_left <= 24'd0; // 复位清空矩阵移位值
		end else begin
			case(flag_freeze)
				1'b1:begin
					reg_ccm_shift_green_left <= reg_ccm_shift_green_left; // 输出未取走时保持本级
				end
				default:begin
					reg_ccm_shift_green_left <= $signed(reg_ccm_round_green_left) >>> C_CCM_SHIFT; // 算术右移定点小数位
				end
			endcase
		end
	end

	//green 通道 center_left 像素矩阵移位值更新逻辑
	always@(posedge i_clk)begin
		if(i_rstn == 1'b0)begin
			reg_ccm_shift_green_center_left <= 24'd0; // 复位清空矩阵移位值
		end else begin
			case(flag_freeze)
				1'b1:begin
					reg_ccm_shift_green_center_left <= reg_ccm_shift_green_center_left; // 输出未取走时保持本级
				end
				default:begin
					reg_ccm_shift_green_center_left <= $signed(reg_ccm_round_green_center_left) >>> C_CCM_SHIFT; // 算术右移定点小数位
				end
			endcase
		end
	end

	//green 通道 center_right 像素矩阵移位值更新逻辑
	always@(posedge i_clk)begin
		if(i_rstn == 1'b0)begin
			reg_ccm_shift_green_center_right <= 24'd0; // 复位清空矩阵移位值
		end else begin
			case(flag_freeze)
				1'b1:begin
					reg_ccm_shift_green_center_right <= reg_ccm_shift_green_center_right; // 输出未取走时保持本级
				end
				default:begin
					reg_ccm_shift_green_center_right <= $signed(reg_ccm_round_green_center_right) >>> C_CCM_SHIFT; // 算术右移定点小数位
				end
			endcase
		end
	end

	//green 通道 right 像素矩阵移位值更新逻辑
	always@(posedge i_clk)begin
		if(i_rstn == 1'b0)begin
			reg_ccm_shift_green_right <= 24'd0; // 复位清空矩阵移位值
		end else begin
			case(flag_freeze)
				1'b1:begin
					reg_ccm_shift_green_right <= reg_ccm_shift_green_right; // 输出未取走时保持本级
				end
				default:begin
					reg_ccm_shift_green_right <= $signed(reg_ccm_round_green_right) >>> C_CCM_SHIFT; // 算术右移定点小数位
				end
			endcase
		end
	end

	//green 通道 left 像素矩阵下溢标志更新逻辑
	always@(posedge i_clk)begin
		if(i_rstn == 1'b0)begin
			flag_ccm_low_green_left <= 1'b0; // 复位清除下溢标志
		end else begin
			case(flag_freeze)
				1'b1:begin
					flag_ccm_low_green_left <= flag_ccm_low_green_left; // 输出未取走时保持本级
				end
				default:begin
					flag_ccm_low_green_left <= ($signed(reg_ccm_shift_green_left) < 0); // 判断负值下钳位
				end
			endcase
		end
	end

	//green 通道 center_left 像素矩阵下溢标志更新逻辑
	always@(posedge i_clk)begin
		if(i_rstn == 1'b0)begin
			flag_ccm_low_green_center_left <= 1'b0; // 复位清除下溢标志
		end else begin
			case(flag_freeze)
				1'b1:begin
					flag_ccm_low_green_center_left <= flag_ccm_low_green_center_left; // 输出未取走时保持本级
				end
				default:begin
					flag_ccm_low_green_center_left <= ($signed(reg_ccm_shift_green_center_left) < 0); // 判断负值下钳位
				end
			endcase
		end
	end

	//green 通道 center_right 像素矩阵下溢标志更新逻辑
	always@(posedge i_clk)begin
		if(i_rstn == 1'b0)begin
			flag_ccm_low_green_center_right <= 1'b0; // 复位清除下溢标志
		end else begin
			case(flag_freeze)
				1'b1:begin
					flag_ccm_low_green_center_right <= flag_ccm_low_green_center_right; // 输出未取走时保持本级
				end
				default:begin
					flag_ccm_low_green_center_right <= ($signed(reg_ccm_shift_green_center_right) < 0); // 判断负值下钳位
				end
			endcase
		end
	end

	//green 通道 right 像素矩阵下溢标志更新逻辑
	always@(posedge i_clk)begin
		if(i_rstn == 1'b0)begin
			flag_ccm_low_green_right <= 1'b0; // 复位清除下溢标志
		end else begin
			case(flag_freeze)
				1'b1:begin
					flag_ccm_low_green_right <= flag_ccm_low_green_right; // 输出未取走时保持本级
				end
				default:begin
					flag_ccm_low_green_right <= ($signed(reg_ccm_shift_green_right) < 0); // 判断负值下钳位
				end
			endcase
		end
	end

	//green 通道 left 像素矩阵下钳位延迟值更新逻辑
	always@(posedge i_clk)begin
		if(i_rstn == 1'b0)begin
			reg_ccm_delay_low_green_left <= 24'd0; // 复位清空下钳位延迟值
		end else begin
			case(flag_freeze)
				1'b1:begin
					reg_ccm_delay_low_green_left <= reg_ccm_delay_low_green_left; // 输出未取走时保持本级
				end
				default:begin
					reg_ccm_delay_low_green_left <= reg_ccm_shift_green_left; // 与下溢标志对齐延迟移位值
				end
			endcase
		end
	end

	//green 通道 center_left 像素矩阵下钳位延迟值更新逻辑
	always@(posedge i_clk)begin
		if(i_rstn == 1'b0)begin
			reg_ccm_delay_low_green_center_left <= 24'd0; // 复位清空下钳位延迟值
		end else begin
			case(flag_freeze)
				1'b1:begin
					reg_ccm_delay_low_green_center_left <= reg_ccm_delay_low_green_center_left; // 输出未取走时保持本级
				end
				default:begin
					reg_ccm_delay_low_green_center_left <= reg_ccm_shift_green_center_left; // 与下溢标志对齐延迟移位值
				end
			endcase
		end
	end

	//green 通道 center_right 像素矩阵下钳位延迟值更新逻辑
	always@(posedge i_clk)begin
		if(i_rstn == 1'b0)begin
			reg_ccm_delay_low_green_center_right <= 24'd0; // 复位清空下钳位延迟值
		end else begin
			case(flag_freeze)
				1'b1:begin
					reg_ccm_delay_low_green_center_right <= reg_ccm_delay_low_green_center_right; // 输出未取走时保持本级
				end
				default:begin
					reg_ccm_delay_low_green_center_right <= reg_ccm_shift_green_center_right; // 与下溢标志对齐延迟移位值
				end
			endcase
		end
	end

	//green 通道 right 像素矩阵下钳位延迟值更新逻辑
	always@(posedge i_clk)begin
		if(i_rstn == 1'b0)begin
			reg_ccm_delay_low_green_right <= 24'd0; // 复位清空下钳位延迟值
		end else begin
			case(flag_freeze)
				1'b1:begin
					reg_ccm_delay_low_green_right <= reg_ccm_delay_low_green_right; // 输出未取走时保持本级
				end
				default:begin
					reg_ccm_delay_low_green_right <= reg_ccm_shift_green_right; // 与下溢标志对齐延迟移位值
				end
			endcase
		end
	end

	//green 通道 left 像素矩阵下钳位值更新逻辑
	always@(posedge i_clk)begin
		if(i_rstn == 1'b0)begin
			reg_ccm_low_green_left <= 24'd0; // 复位清空下钳位值
		end else begin
			case(flag_freeze)
				1'b1:begin
					reg_ccm_low_green_left <= reg_ccm_low_green_left; // 输出未取走时保持本级
				end
				default:begin
					reg_ccm_low_green_left <= flag_ccm_low_green_left ? 24'd0 : reg_ccm_delay_low_green_left; // 负值钳位到零
				end
			endcase
		end
	end

	//green 通道 center_left 像素矩阵下钳位值更新逻辑
	always@(posedge i_clk)begin
		if(i_rstn == 1'b0)begin
			reg_ccm_low_green_center_left <= 24'd0; // 复位清空下钳位值
		end else begin
			case(flag_freeze)
				1'b1:begin
					reg_ccm_low_green_center_left <= reg_ccm_low_green_center_left; // 输出未取走时保持本级
				end
				default:begin
					reg_ccm_low_green_center_left <= flag_ccm_low_green_center_left ? 24'd0 : reg_ccm_delay_low_green_center_left; // 负值钳位到零
				end
			endcase
		end
	end

	//green 通道 center_right 像素矩阵下钳位值更新逻辑
	always@(posedge i_clk)begin
		if(i_rstn == 1'b0)begin
			reg_ccm_low_green_center_right <= 24'd0; // 复位清空下钳位值
		end else begin
			case(flag_freeze)
				1'b1:begin
					reg_ccm_low_green_center_right <= reg_ccm_low_green_center_right; // 输出未取走时保持本级
				end
				default:begin
					reg_ccm_low_green_center_right <= flag_ccm_low_green_center_right ? 24'd0 : reg_ccm_delay_low_green_center_right; // 负值钳位到零
				end
			endcase
		end
	end

	//green 通道 right 像素矩阵下钳位值更新逻辑
	always@(posedge i_clk)begin
		if(i_rstn == 1'b0)begin
			reg_ccm_low_green_right <= 24'd0; // 复位清空下钳位值
		end else begin
			case(flag_freeze)
				1'b1:begin
					reg_ccm_low_green_right <= reg_ccm_low_green_right; // 输出未取走时保持本级
				end
				default:begin
					reg_ccm_low_green_right <= flag_ccm_low_green_right ? 24'd0 : reg_ccm_delay_low_green_right; // 负值钳位到零
				end
			endcase
		end
	end

	//green 通道 left 像素矩阵下溢延迟标志更新逻辑
	always@(posedge i_clk)begin
		if(i_rstn == 1'b0)begin
			flag_ccm_low_hold_first_green_left <= 1'b0; // 复位清除下溢延迟标志
		end else begin
			case(flag_freeze)
				1'b1:begin
					flag_ccm_low_hold_first_green_left <= flag_ccm_low_hold_first_green_left; // 输出未取走时保持本级
				end
				default:begin
					flag_ccm_low_hold_first_green_left <= flag_ccm_low_green_left; // 延迟下溢标志以待合并
				end
			endcase
		end
	end

	//green 通道 center_left 像素矩阵下溢延迟标志更新逻辑
	always@(posedge i_clk)begin
		if(i_rstn == 1'b0)begin
			flag_ccm_low_hold_first_green_center_left <= 1'b0; // 复位清除下溢延迟标志
		end else begin
			case(flag_freeze)
				1'b1:begin
					flag_ccm_low_hold_first_green_center_left <= flag_ccm_low_hold_first_green_center_left; // 输出未取走时保持本级
				end
				default:begin
					flag_ccm_low_hold_first_green_center_left <= flag_ccm_low_green_center_left; // 延迟下溢标志以待合并
				end
			endcase
		end
	end

	//green 通道 center_right 像素矩阵下溢延迟标志更新逻辑
	always@(posedge i_clk)begin
		if(i_rstn == 1'b0)begin
			flag_ccm_low_hold_first_green_center_right <= 1'b0; // 复位清除下溢延迟标志
		end else begin
			case(flag_freeze)
				1'b1:begin
					flag_ccm_low_hold_first_green_center_right <= flag_ccm_low_hold_first_green_center_right; // 输出未取走时保持本级
				end
				default:begin
					flag_ccm_low_hold_first_green_center_right <= flag_ccm_low_green_center_right; // 延迟下溢标志以待合并
				end
			endcase
		end
	end

	//green 通道 right 像素矩阵下溢延迟标志更新逻辑
	always@(posedge i_clk)begin
		if(i_rstn == 1'b0)begin
			flag_ccm_low_hold_first_green_right <= 1'b0; // 复位清除下溢延迟标志
		end else begin
			case(flag_freeze)
				1'b1:begin
					flag_ccm_low_hold_first_green_right <= flag_ccm_low_hold_first_green_right; // 输出未取走时保持本级
				end
				default:begin
					flag_ccm_low_hold_first_green_right <= flag_ccm_low_green_right; // 延迟下溢标志以待合并
				end
			endcase
		end
	end

	//green 通道 left 像素矩阵上溢标志更新逻辑
	always@(posedge i_clk)begin
		if(i_rstn == 1'b0)begin
			flag_ccm_high_green_left <= 1'b0; // 复位清除上溢标志
		end else begin
			case(flag_freeze)
				1'b1:begin
					flag_ccm_high_green_left <= flag_ccm_high_green_left; // 输出未取走时保持本级
				end
				default:begin
					flag_ccm_high_green_left <= (reg_ccm_low_green_left > C_CCM_MAX); // 比较矩阵上限
				end
			endcase
		end
	end

	//green 通道 center_left 像素矩阵上溢标志更新逻辑
	always@(posedge i_clk)begin
		if(i_rstn == 1'b0)begin
			flag_ccm_high_green_center_left <= 1'b0; // 复位清除上溢标志
		end else begin
			case(flag_freeze)
				1'b1:begin
					flag_ccm_high_green_center_left <= flag_ccm_high_green_center_left; // 输出未取走时保持本级
				end
				default:begin
					flag_ccm_high_green_center_left <= (reg_ccm_low_green_center_left > C_CCM_MAX); // 比较矩阵上限
				end
			endcase
		end
	end

	//green 通道 center_right 像素矩阵上溢标志更新逻辑
	always@(posedge i_clk)begin
		if(i_rstn == 1'b0)begin
			flag_ccm_high_green_center_right <= 1'b0; // 复位清除上溢标志
		end else begin
			case(flag_freeze)
				1'b1:begin
					flag_ccm_high_green_center_right <= flag_ccm_high_green_center_right; // 输出未取走时保持本级
				end
				default:begin
					flag_ccm_high_green_center_right <= (reg_ccm_low_green_center_right > C_CCM_MAX); // 比较矩阵上限
				end
			endcase
		end
	end

	//green 通道 right 像素矩阵上溢标志更新逻辑
	always@(posedge i_clk)begin
		if(i_rstn == 1'b0)begin
			flag_ccm_high_green_right <= 1'b0; // 复位清除上溢标志
		end else begin
			case(flag_freeze)
				1'b1:begin
					flag_ccm_high_green_right <= flag_ccm_high_green_right; // 输出未取走时保持本级
				end
				default:begin
					flag_ccm_high_green_right <= (reg_ccm_low_green_right > C_CCM_MAX); // 比较矩阵上限
				end
			endcase
		end
	end

	//green 通道 left 像素矩阵上钳位延迟值更新逻辑
	always@(posedge i_clk)begin
		if(i_rstn == 1'b0)begin
			reg_ccm_delay_level_green_left <= 24'd0; // 复位清空上钳位延迟值
		end else begin
			case(flag_freeze)
				1'b1:begin
					reg_ccm_delay_level_green_left <= reg_ccm_delay_level_green_left; // 输出未取走时保持本级
				end
				default:begin
					reg_ccm_delay_level_green_left <= reg_ccm_low_green_left; // 与上溢标志对齐延迟下钳位值
				end
			endcase
		end
	end

	//green 通道 center_left 像素矩阵上钳位延迟值更新逻辑
	always@(posedge i_clk)begin
		if(i_rstn == 1'b0)begin
			reg_ccm_delay_level_green_center_left <= 24'd0; // 复位清空上钳位延迟值
		end else begin
			case(flag_freeze)
				1'b1:begin
					reg_ccm_delay_level_green_center_left <= reg_ccm_delay_level_green_center_left; // 输出未取走时保持本级
				end
				default:begin
					reg_ccm_delay_level_green_center_left <= reg_ccm_low_green_center_left; // 与上溢标志对齐延迟下钳位值
				end
			endcase
		end
	end

	//green 通道 center_right 像素矩阵上钳位延迟值更新逻辑
	always@(posedge i_clk)begin
		if(i_rstn == 1'b0)begin
			reg_ccm_delay_level_green_center_right <= 24'd0; // 复位清空上钳位延迟值
		end else begin
			case(flag_freeze)
				1'b1:begin
					reg_ccm_delay_level_green_center_right <= reg_ccm_delay_level_green_center_right; // 输出未取走时保持本级
				end
				default:begin
					reg_ccm_delay_level_green_center_right <= reg_ccm_low_green_center_right; // 与上溢标志对齐延迟下钳位值
				end
			endcase
		end
	end

	//green 通道 right 像素矩阵上钳位延迟值更新逻辑
	always@(posedge i_clk)begin
		if(i_rstn == 1'b0)begin
			reg_ccm_delay_level_green_right <= 24'd0; // 复位清空上钳位延迟值
		end else begin
			case(flag_freeze)
				1'b1:begin
					reg_ccm_delay_level_green_right <= reg_ccm_delay_level_green_right; // 输出未取走时保持本级
				end
				default:begin
					reg_ccm_delay_level_green_right <= reg_ccm_low_green_right; // 与上溢标志对齐延迟下钳位值
				end
			endcase
		end
	end

	//green 通道 left 像素矩阵下溢二次延迟标志更新逻辑
	always@(posedge i_clk)begin
		if(i_rstn == 1'b0)begin
			flag_ccm_low_hold_second_green_left <= 1'b0; // 复位清除下溢二次延迟标志
		end else begin
			case(flag_freeze)
				1'b1:begin
					flag_ccm_low_hold_second_green_left <= flag_ccm_low_hold_second_green_left; // 输出未取走时保持本级
				end
				default:begin
					flag_ccm_low_hold_second_green_left <= flag_ccm_low_hold_first_green_left; // 二级延迟对齐上溢标志
				end
			endcase
		end
	end

	//green 通道 center_left 像素矩阵下溢二次延迟标志更新逻辑
	always@(posedge i_clk)begin
		if(i_rstn == 1'b0)begin
			flag_ccm_low_hold_second_green_center_left <= 1'b0; // 复位清除下溢二次延迟标志
		end else begin
			case(flag_freeze)
				1'b1:begin
					flag_ccm_low_hold_second_green_center_left <= flag_ccm_low_hold_second_green_center_left; // 输出未取走时保持本级
				end
				default:begin
					flag_ccm_low_hold_second_green_center_left <= flag_ccm_low_hold_first_green_center_left; // 二级延迟对齐上溢标志
				end
			endcase
		end
	end

	//green 通道 center_right 像素矩阵下溢二次延迟标志更新逻辑
	always@(posedge i_clk)begin
		if(i_rstn == 1'b0)begin
			flag_ccm_low_hold_second_green_center_right <= 1'b0; // 复位清除下溢二次延迟标志
		end else begin
			case(flag_freeze)
				1'b1:begin
					flag_ccm_low_hold_second_green_center_right <= flag_ccm_low_hold_second_green_center_right; // 输出未取走时保持本级
				end
				default:begin
					flag_ccm_low_hold_second_green_center_right <= flag_ccm_low_hold_first_green_center_right; // 二级延迟对齐上溢标志
				end
			endcase
		end
	end

	//green 通道 right 像素矩阵下溢二次延迟标志更新逻辑
	always@(posedge i_clk)begin
		if(i_rstn == 1'b0)begin
			flag_ccm_low_hold_second_green_right <= 1'b0; // 复位清除下溢二次延迟标志
		end else begin
			case(flag_freeze)
				1'b1:begin
					flag_ccm_low_hold_second_green_right <= flag_ccm_low_hold_second_green_right; // 输出未取走时保持本级
				end
				default:begin
					flag_ccm_low_hold_second_green_right <= flag_ccm_low_hold_first_green_right; // 二级延迟对齐上溢标志
				end
			endcase
		end
	end

	//green 通道 left 像素矩阵输出码值更新逻辑
	always@(posedge i_clk)begin
		if(i_rstn == 1'b0)begin
			reg_ccm_level_green_left <= 10'd0; // 复位清空矩阵输出码值
		end else begin
			case(flag_freeze)
				1'b1:begin
					reg_ccm_level_green_left <= reg_ccm_level_green_left; // 输出未取走时保持本级
				end
				default:begin
					reg_ccm_level_green_left <= flag_ccm_high_green_left ? C_CCM_MAX : reg_ccm_delay_level_green_left[9:0]; // 按上溢标志选择上限
				end
			endcase
		end
	end

	//green 通道 center_left 像素矩阵输出码值更新逻辑
	always@(posedge i_clk)begin
		if(i_rstn == 1'b0)begin
			reg_ccm_level_green_center_left <= 10'd0; // 复位清空矩阵输出码值
		end else begin
			case(flag_freeze)
				1'b1:begin
					reg_ccm_level_green_center_left <= reg_ccm_level_green_center_left; // 输出未取走时保持本级
				end
				default:begin
					reg_ccm_level_green_center_left <= flag_ccm_high_green_center_left ? C_CCM_MAX : reg_ccm_delay_level_green_center_left[9:0]; // 按上溢标志选择上限
				end
			endcase
		end
	end

	//green 通道 center_right 像素矩阵输出码值更新逻辑
	always@(posedge i_clk)begin
		if(i_rstn == 1'b0)begin
			reg_ccm_level_green_center_right <= 10'd0; // 复位清空矩阵输出码值
		end else begin
			case(flag_freeze)
				1'b1:begin
					reg_ccm_level_green_center_right <= reg_ccm_level_green_center_right; // 输出未取走时保持本级
				end
				default:begin
					reg_ccm_level_green_center_right <= flag_ccm_high_green_center_right ? C_CCM_MAX : reg_ccm_delay_level_green_center_right[9:0]; // 按上溢标志选择上限
				end
			endcase
		end
	end

	//green 通道 right 像素矩阵输出码值更新逻辑
	always@(posedge i_clk)begin
		if(i_rstn == 1'b0)begin
			reg_ccm_level_green_right <= 10'd0; // 复位清空矩阵输出码值
		end else begin
			case(flag_freeze)
				1'b1:begin
					reg_ccm_level_green_right <= reg_ccm_level_green_right; // 输出未取走时保持本级
				end
				default:begin
					reg_ccm_level_green_right <= flag_ccm_high_green_right ? C_CCM_MAX : reg_ccm_delay_level_green_right[9:0]; // 按上溢标志选择上限
				end
			endcase
		end
	end

	//green 通道 left 像素矩阵饱和标志更新逻辑
	always@(posedge i_clk)begin
		if(i_rstn == 1'b0)begin
			flag_ccm_channel_green_left <= 1'b0; // 复位清除通道饱和标志
		end else begin
			case(flag_freeze)
				1'b1:begin
					flag_ccm_channel_green_left <= flag_ccm_channel_green_left; // 输出未取走时保持本级
				end
				default:begin
					flag_ccm_channel_green_left <= flag_ccm_low_hold_second_green_left | flag_ccm_high_green_left; // 归并同拍矩阵上下溢
				end
			endcase
		end
	end

	//green 通道 center_left 像素矩阵饱和标志更新逻辑
	always@(posedge i_clk)begin
		if(i_rstn == 1'b0)begin
			flag_ccm_channel_green_center_left <= 1'b0; // 复位清除通道饱和标志
		end else begin
			case(flag_freeze)
				1'b1:begin
					flag_ccm_channel_green_center_left <= flag_ccm_channel_green_center_left; // 输出未取走时保持本级
				end
				default:begin
					flag_ccm_channel_green_center_left <= flag_ccm_low_hold_second_green_center_left | flag_ccm_high_green_center_left; // 归并同拍矩阵上下溢
				end
			endcase
		end
	end

	//green 通道 center_right 像素矩阵饱和标志更新逻辑
	always@(posedge i_clk)begin
		if(i_rstn == 1'b0)begin
			flag_ccm_channel_green_center_right <= 1'b0; // 复位清除通道饱和标志
		end else begin
			case(flag_freeze)
				1'b1:begin
					flag_ccm_channel_green_center_right <= flag_ccm_channel_green_center_right; // 输出未取走时保持本级
				end
				default:begin
					flag_ccm_channel_green_center_right <= flag_ccm_low_hold_second_green_center_right | flag_ccm_high_green_center_right; // 归并同拍矩阵上下溢
				end
			endcase
		end
	end

	//green 通道 right 像素矩阵饱和标志更新逻辑
	always@(posedge i_clk)begin
		if(i_rstn == 1'b0)begin
			flag_ccm_channel_green_right <= 1'b0; // 复位清除通道饱和标志
		end else begin
			case(flag_freeze)
				1'b1:begin
					flag_ccm_channel_green_right <= flag_ccm_channel_green_right; // 输出未取走时保持本级
				end
				default:begin
					flag_ccm_channel_green_right <= flag_ccm_low_hold_second_green_right | flag_ccm_high_green_right; // 归并同拍矩阵上下溢
				end
			endcase
		end
	end

	//blue 通道 left 像素矩阵首项更新逻辑
	always@(posedge i_clk)begin
		if(i_rstn == 1'b0)begin
			reg_ccm_first_blue_left <= 24'd0; // 复位清空矩阵首项
		end else begin
			case(flag_freeze)
				1'b1:begin
					reg_ccm_first_blue_left <= reg_ccm_first_blue_left; // 输出未取走时保持本级
				end
				default:begin
					reg_ccm_first_blue_left <= $signed({1'b0, reg_wb_level_red_left}) * $signed(C_CCM_M20); // 首项乘加系数
				end
			endcase
		end
	end

	//blue 通道 center_left 像素矩阵首项更新逻辑
	always@(posedge i_clk)begin
		if(i_rstn == 1'b0)begin
			reg_ccm_first_blue_center_left <= 24'd0; // 复位清空矩阵首项
		end else begin
			case(flag_freeze)
				1'b1:begin
					reg_ccm_first_blue_center_left <= reg_ccm_first_blue_center_left; // 输出未取走时保持本级
				end
				default:begin
					reg_ccm_first_blue_center_left <= $signed({1'b0, reg_wb_level_red_center_left}) * $signed(C_CCM_M20); // 首项乘加系数
				end
			endcase
		end
	end

	//blue 通道 center_right 像素矩阵首项更新逻辑
	always@(posedge i_clk)begin
		if(i_rstn == 1'b0)begin
			reg_ccm_first_blue_center_right <= 24'd0; // 复位清空矩阵首项
		end else begin
			case(flag_freeze)
				1'b1:begin
					reg_ccm_first_blue_center_right <= reg_ccm_first_blue_center_right; // 输出未取走时保持本级
				end
				default:begin
					reg_ccm_first_blue_center_right <= $signed({1'b0, reg_wb_level_red_center_right}) * $signed(C_CCM_M20); // 首项乘加系数
				end
			endcase
		end
	end

	//blue 通道 right 像素矩阵首项更新逻辑
	always@(posedge i_clk)begin
		if(i_rstn == 1'b0)begin
			reg_ccm_first_blue_right <= 24'd0; // 复位清空矩阵首项
		end else begin
			case(flag_freeze)
				1'b1:begin
					reg_ccm_first_blue_right <= reg_ccm_first_blue_right; // 输出未取走时保持本级
				end
				default:begin
					reg_ccm_first_blue_right <= $signed({1'b0, reg_wb_level_red_right}) * $signed(C_CCM_M20); // 首项乘加系数
				end
			endcase
		end
	end

	//blue 通道 left 像素矩阵次项更新逻辑
	always@(posedge i_clk)begin
		if(i_rstn == 1'b0)begin
			reg_ccm_second_blue_left <= 24'd0; // 复位清空矩阵次项
		end else begin
			case(flag_freeze)
				1'b1:begin
					reg_ccm_second_blue_left <= reg_ccm_second_blue_left; // 输出未取走时保持本级
				end
				default:begin
					reg_ccm_second_blue_left <= $signed({1'b0, reg_wb_level_green_left}) * $signed(C_CCM_M21); // 次项乘加系数
				end
			endcase
		end
	end

	//blue 通道 center_left 像素矩阵次项更新逻辑
	always@(posedge i_clk)begin
		if(i_rstn == 1'b0)begin
			reg_ccm_second_blue_center_left <= 24'd0; // 复位清空矩阵次项
		end else begin
			case(flag_freeze)
				1'b1:begin
					reg_ccm_second_blue_center_left <= reg_ccm_second_blue_center_left; // 输出未取走时保持本级
				end
				default:begin
					reg_ccm_second_blue_center_left <= $signed({1'b0, reg_wb_level_green_center_left}) * $signed(C_CCM_M21); // 次项乘加系数
				end
			endcase
		end
	end

	//blue 通道 center_right 像素矩阵次项更新逻辑
	always@(posedge i_clk)begin
		if(i_rstn == 1'b0)begin
			reg_ccm_second_blue_center_right <= 24'd0; // 复位清空矩阵次项
		end else begin
			case(flag_freeze)
				1'b1:begin
					reg_ccm_second_blue_center_right <= reg_ccm_second_blue_center_right; // 输出未取走时保持本级
				end
				default:begin
					reg_ccm_second_blue_center_right <= $signed({1'b0, reg_wb_level_green_center_right}) * $signed(C_CCM_M21); // 次项乘加系数
				end
			endcase
		end
	end

	//blue 通道 right 像素矩阵次项更新逻辑
	always@(posedge i_clk)begin
		if(i_rstn == 1'b0)begin
			reg_ccm_second_blue_right <= 24'd0; // 复位清空矩阵次项
		end else begin
			case(flag_freeze)
				1'b1:begin
					reg_ccm_second_blue_right <= reg_ccm_second_blue_right; // 输出未取走时保持本级
				end
				default:begin
					reg_ccm_second_blue_right <= $signed({1'b0, reg_wb_level_green_right}) * $signed(C_CCM_M21); // 次项乘加系数
				end
			endcase
		end
	end

	//blue 通道 left 像素矩阵末项更新逻辑
	always@(posedge i_clk)begin
		if(i_rstn == 1'b0)begin
			reg_ccm_third_blue_left <= 24'd0; // 复位清空矩阵末项
		end else begin
			case(flag_freeze)
				1'b1:begin
					reg_ccm_third_blue_left <= reg_ccm_third_blue_left; // 输出未取走时保持本级
				end
				default:begin
					reg_ccm_third_blue_left <= $signed({1'b0, reg_wb_level_blue_left}) * $signed(C_CCM_M22); // 末项乘加系数
				end
			endcase
		end
	end

	//blue 通道 center_left 像素矩阵末项更新逻辑
	always@(posedge i_clk)begin
		if(i_rstn == 1'b0)begin
			reg_ccm_third_blue_center_left <= 24'd0; // 复位清空矩阵末项
		end else begin
			case(flag_freeze)
				1'b1:begin
					reg_ccm_third_blue_center_left <= reg_ccm_third_blue_center_left; // 输出未取走时保持本级
				end
				default:begin
					reg_ccm_third_blue_center_left <= $signed({1'b0, reg_wb_level_blue_center_left}) * $signed(C_CCM_M22); // 末项乘加系数
				end
			endcase
		end
	end

	//blue 通道 center_right 像素矩阵末项更新逻辑
	always@(posedge i_clk)begin
		if(i_rstn == 1'b0)begin
			reg_ccm_third_blue_center_right <= 24'd0; // 复位清空矩阵末项
		end else begin
			case(flag_freeze)
				1'b1:begin
					reg_ccm_third_blue_center_right <= reg_ccm_third_blue_center_right; // 输出未取走时保持本级
				end
				default:begin
					reg_ccm_third_blue_center_right <= $signed({1'b0, reg_wb_level_blue_center_right}) * $signed(C_CCM_M22); // 末项乘加系数
				end
			endcase
		end
	end

	//blue 通道 right 像素矩阵末项更新逻辑
	always@(posedge i_clk)begin
		if(i_rstn == 1'b0)begin
			reg_ccm_third_blue_right <= 24'd0; // 复位清空矩阵末项
		end else begin
			case(flag_freeze)
				1'b1:begin
					reg_ccm_third_blue_right <= reg_ccm_third_blue_right; // 输出未取走时保持本级
				end
				default:begin
					reg_ccm_third_blue_right <= $signed({1'b0, reg_wb_level_blue_right}) * $signed(C_CCM_M22); // 末项乘加系数
				end
			endcase
		end
	end

	//blue 通道 left 像素矩阵前两项和更新逻辑
	always@(posedge i_clk)begin
		if(i_rstn == 1'b0)begin
			reg_ccm_partial_blue_left <= 24'd0; // 复位清空矩阵前两项和
		end else begin
			case(flag_freeze)
				1'b1:begin
					reg_ccm_partial_blue_left <= reg_ccm_partial_blue_left; // 输出未取走时保持本级
				end
				default:begin
					reg_ccm_partial_blue_left <= $signed(reg_ccm_first_blue_left) + $signed(reg_ccm_second_blue_left); // 累加前两项
				end
			endcase
		end
	end

	//blue 通道 center_left 像素矩阵前两项和更新逻辑
	always@(posedge i_clk)begin
		if(i_rstn == 1'b0)begin
			reg_ccm_partial_blue_center_left <= 24'd0; // 复位清空矩阵前两项和
		end else begin
			case(flag_freeze)
				1'b1:begin
					reg_ccm_partial_blue_center_left <= reg_ccm_partial_blue_center_left; // 输出未取走时保持本级
				end
				default:begin
					reg_ccm_partial_blue_center_left <= $signed(reg_ccm_first_blue_center_left) + $signed(reg_ccm_second_blue_center_left); // 累加前两项
				end
			endcase
		end
	end

	//blue 通道 center_right 像素矩阵前两项和更新逻辑
	always@(posedge i_clk)begin
		if(i_rstn == 1'b0)begin
			reg_ccm_partial_blue_center_right <= 24'd0; // 复位清空矩阵前两项和
		end else begin
			case(flag_freeze)
				1'b1:begin
					reg_ccm_partial_blue_center_right <= reg_ccm_partial_blue_center_right; // 输出未取走时保持本级
				end
				default:begin
					reg_ccm_partial_blue_center_right <= $signed(reg_ccm_first_blue_center_right) + $signed(reg_ccm_second_blue_center_right); // 累加前两项
				end
			endcase
		end
	end

	//blue 通道 right 像素矩阵前两项和更新逻辑
	always@(posedge i_clk)begin
		if(i_rstn == 1'b0)begin
			reg_ccm_partial_blue_right <= 24'd0; // 复位清空矩阵前两项和
		end else begin
			case(flag_freeze)
				1'b1:begin
					reg_ccm_partial_blue_right <= reg_ccm_partial_blue_right; // 输出未取走时保持本级
				end
				default:begin
					reg_ccm_partial_blue_right <= $signed(reg_ccm_first_blue_right) + $signed(reg_ccm_second_blue_right); // 累加前两项
				end
			endcase
		end
	end

	//blue 通道 left 像素矩阵末项延迟值更新逻辑
	always@(posedge i_clk)begin
		if(i_rstn == 1'b0)begin
			reg_ccm_third_hold_blue_left <= 24'd0; // 复位清空矩阵末项延迟值
		end else begin
			case(flag_freeze)
				1'b1:begin
					reg_ccm_third_hold_blue_left <= reg_ccm_third_hold_blue_left; // 输出未取走时保持本级
				end
				default:begin
					reg_ccm_third_hold_blue_left <= reg_ccm_third_blue_left; // 与前两项和对齐延迟末项
				end
			endcase
		end
	end

	//blue 通道 center_left 像素矩阵末项延迟值更新逻辑
	always@(posedge i_clk)begin
		if(i_rstn == 1'b0)begin
			reg_ccm_third_hold_blue_center_left <= 24'd0; // 复位清空矩阵末项延迟值
		end else begin
			case(flag_freeze)
				1'b1:begin
					reg_ccm_third_hold_blue_center_left <= reg_ccm_third_hold_blue_center_left; // 输出未取走时保持本级
				end
				default:begin
					reg_ccm_third_hold_blue_center_left <= reg_ccm_third_blue_center_left; // 与前两项和对齐延迟末项
				end
			endcase
		end
	end

	//blue 通道 center_right 像素矩阵末项延迟值更新逻辑
	always@(posedge i_clk)begin
		if(i_rstn == 1'b0)begin
			reg_ccm_third_hold_blue_center_right <= 24'd0; // 复位清空矩阵末项延迟值
		end else begin
			case(flag_freeze)
				1'b1:begin
					reg_ccm_third_hold_blue_center_right <= reg_ccm_third_hold_blue_center_right; // 输出未取走时保持本级
				end
				default:begin
					reg_ccm_third_hold_blue_center_right <= reg_ccm_third_blue_center_right; // 与前两项和对齐延迟末项
				end
			endcase
		end
	end

	//blue 通道 right 像素矩阵末项延迟值更新逻辑
	always@(posedge i_clk)begin
		if(i_rstn == 1'b0)begin
			reg_ccm_third_hold_blue_right <= 24'd0; // 复位清空矩阵末项延迟值
		end else begin
			case(flag_freeze)
				1'b1:begin
					reg_ccm_third_hold_blue_right <= reg_ccm_third_hold_blue_right; // 输出未取走时保持本级
				end
				default:begin
					reg_ccm_third_hold_blue_right <= reg_ccm_third_blue_right; // 与前两项和对齐延迟末项
				end
			endcase
		end
	end

	//blue 通道 left 像素矩阵三项和更新逻辑
	always@(posedge i_clk)begin
		if(i_rstn == 1'b0)begin
			reg_ccm_total_blue_left <= 24'd0; // 复位清空矩阵三项和
		end else begin
			case(flag_freeze)
				1'b1:begin
					reg_ccm_total_blue_left <= reg_ccm_total_blue_left; // 输出未取走时保持本级
				end
				default:begin
					reg_ccm_total_blue_left <= $signed(reg_ccm_partial_blue_left) + $signed(reg_ccm_third_hold_blue_left); // 累加已对齐的末项
				end
			endcase
		end
	end

	//blue 通道 center_left 像素矩阵三项和更新逻辑
	always@(posedge i_clk)begin
		if(i_rstn == 1'b0)begin
			reg_ccm_total_blue_center_left <= 24'd0; // 复位清空矩阵三项和
		end else begin
			case(flag_freeze)
				1'b1:begin
					reg_ccm_total_blue_center_left <= reg_ccm_total_blue_center_left; // 输出未取走时保持本级
				end
				default:begin
					reg_ccm_total_blue_center_left <= $signed(reg_ccm_partial_blue_center_left) + $signed(reg_ccm_third_hold_blue_center_left); // 累加已对齐的末项
				end
			endcase
		end
	end

	//blue 通道 center_right 像素矩阵三项和更新逻辑
	always@(posedge i_clk)begin
		if(i_rstn == 1'b0)begin
			reg_ccm_total_blue_center_right <= 24'd0; // 复位清空矩阵三项和
		end else begin
			case(flag_freeze)
				1'b1:begin
					reg_ccm_total_blue_center_right <= reg_ccm_total_blue_center_right; // 输出未取走时保持本级
				end
				default:begin
					reg_ccm_total_blue_center_right <= $signed(reg_ccm_partial_blue_center_right) + $signed(reg_ccm_third_hold_blue_center_right); // 累加已对齐的末项
				end
			endcase
		end
	end

	//blue 通道 right 像素矩阵三项和更新逻辑
	always@(posedge i_clk)begin
		if(i_rstn == 1'b0)begin
			reg_ccm_total_blue_right <= 24'd0; // 复位清空矩阵三项和
		end else begin
			case(flag_freeze)
				1'b1:begin
					reg_ccm_total_blue_right <= reg_ccm_total_blue_right; // 输出未取走时保持本级
				end
				default:begin
					reg_ccm_total_blue_right <= $signed(reg_ccm_partial_blue_right) + $signed(reg_ccm_third_hold_blue_right); // 累加已对齐的末项
				end
			endcase
		end
	end

	//blue 通道 left 像素矩阵圆整值更新逻辑
	always@(posedge i_clk)begin
		if(i_rstn == 1'b0)begin
			reg_ccm_round_blue_left <= 24'd0; // 复位清空矩阵圆整值
		end else begin
			case(flag_freeze)
				1'b1:begin
					reg_ccm_round_blue_left <= reg_ccm_round_blue_left; // 输出未取走时保持本级
				end
				default:begin
					reg_ccm_round_blue_left <= $signed(reg_ccm_total_blue_left) + $signed(CCM_ROUND_VALUE[23:0]); // 叠加矩阵圆整常量
				end
			endcase
		end
	end

	//blue 通道 center_left 像素矩阵圆整值更新逻辑
	always@(posedge i_clk)begin
		if(i_rstn == 1'b0)begin
			reg_ccm_round_blue_center_left <= 24'd0; // 复位清空矩阵圆整值
		end else begin
			case(flag_freeze)
				1'b1:begin
					reg_ccm_round_blue_center_left <= reg_ccm_round_blue_center_left; // 输出未取走时保持本级
				end
				default:begin
					reg_ccm_round_blue_center_left <= $signed(reg_ccm_total_blue_center_left) + $signed(CCM_ROUND_VALUE[23:0]); // 叠加矩阵圆整常量
				end
			endcase
		end
	end

	//blue 通道 center_right 像素矩阵圆整值更新逻辑
	always@(posedge i_clk)begin
		if(i_rstn == 1'b0)begin
			reg_ccm_round_blue_center_right <= 24'd0; // 复位清空矩阵圆整值
		end else begin
			case(flag_freeze)
				1'b1:begin
					reg_ccm_round_blue_center_right <= reg_ccm_round_blue_center_right; // 输出未取走时保持本级
				end
				default:begin
					reg_ccm_round_blue_center_right <= $signed(reg_ccm_total_blue_center_right) + $signed(CCM_ROUND_VALUE[23:0]); // 叠加矩阵圆整常量
				end
			endcase
		end
	end

	//blue 通道 right 像素矩阵圆整值更新逻辑
	always@(posedge i_clk)begin
		if(i_rstn == 1'b0)begin
			reg_ccm_round_blue_right <= 24'd0; // 复位清空矩阵圆整值
		end else begin
			case(flag_freeze)
				1'b1:begin
					reg_ccm_round_blue_right <= reg_ccm_round_blue_right; // 输出未取走时保持本级
				end
				default:begin
					reg_ccm_round_blue_right <= $signed(reg_ccm_total_blue_right) + $signed(CCM_ROUND_VALUE[23:0]); // 叠加矩阵圆整常量
				end
			endcase
		end
	end

	//blue 通道 left 像素矩阵移位值更新逻辑
	always@(posedge i_clk)begin
		if(i_rstn == 1'b0)begin
			reg_ccm_shift_blue_left <= 24'd0; // 复位清空矩阵移位值
		end else begin
			case(flag_freeze)
				1'b1:begin
					reg_ccm_shift_blue_left <= reg_ccm_shift_blue_left; // 输出未取走时保持本级
				end
				default:begin
					reg_ccm_shift_blue_left <= $signed(reg_ccm_round_blue_left) >>> C_CCM_SHIFT; // 算术右移定点小数位
				end
			endcase
		end
	end

	//blue 通道 center_left 像素矩阵移位值更新逻辑
	always@(posedge i_clk)begin
		if(i_rstn == 1'b0)begin
			reg_ccm_shift_blue_center_left <= 24'd0; // 复位清空矩阵移位值
		end else begin
			case(flag_freeze)
				1'b1:begin
					reg_ccm_shift_blue_center_left <= reg_ccm_shift_blue_center_left; // 输出未取走时保持本级
				end
				default:begin
					reg_ccm_shift_blue_center_left <= $signed(reg_ccm_round_blue_center_left) >>> C_CCM_SHIFT; // 算术右移定点小数位
				end
			endcase
		end
	end

	//blue 通道 center_right 像素矩阵移位值更新逻辑
	always@(posedge i_clk)begin
		if(i_rstn == 1'b0)begin
			reg_ccm_shift_blue_center_right <= 24'd0; // 复位清空矩阵移位值
		end else begin
			case(flag_freeze)
				1'b1:begin
					reg_ccm_shift_blue_center_right <= reg_ccm_shift_blue_center_right; // 输出未取走时保持本级
				end
				default:begin
					reg_ccm_shift_blue_center_right <= $signed(reg_ccm_round_blue_center_right) >>> C_CCM_SHIFT; // 算术右移定点小数位
				end
			endcase
		end
	end

	//blue 通道 right 像素矩阵移位值更新逻辑
	always@(posedge i_clk)begin
		if(i_rstn == 1'b0)begin
			reg_ccm_shift_blue_right <= 24'd0; // 复位清空矩阵移位值
		end else begin
			case(flag_freeze)
				1'b1:begin
					reg_ccm_shift_blue_right <= reg_ccm_shift_blue_right; // 输出未取走时保持本级
				end
				default:begin
					reg_ccm_shift_blue_right <= $signed(reg_ccm_round_blue_right) >>> C_CCM_SHIFT; // 算术右移定点小数位
				end
			endcase
		end
	end

	//blue 通道 left 像素矩阵下溢标志更新逻辑
	always@(posedge i_clk)begin
		if(i_rstn == 1'b0)begin
			flag_ccm_low_blue_left <= 1'b0; // 复位清除下溢标志
		end else begin
			case(flag_freeze)
				1'b1:begin
					flag_ccm_low_blue_left <= flag_ccm_low_blue_left; // 输出未取走时保持本级
				end
				default:begin
					flag_ccm_low_blue_left <= ($signed(reg_ccm_shift_blue_left) < 0); // 判断负值下钳位
				end
			endcase
		end
	end

	//blue 通道 center_left 像素矩阵下溢标志更新逻辑
	always@(posedge i_clk)begin
		if(i_rstn == 1'b0)begin
			flag_ccm_low_blue_center_left <= 1'b0; // 复位清除下溢标志
		end else begin
			case(flag_freeze)
				1'b1:begin
					flag_ccm_low_blue_center_left <= flag_ccm_low_blue_center_left; // 输出未取走时保持本级
				end
				default:begin
					flag_ccm_low_blue_center_left <= ($signed(reg_ccm_shift_blue_center_left) < 0); // 判断负值下钳位
				end
			endcase
		end
	end

	//blue 通道 center_right 像素矩阵下溢标志更新逻辑
	always@(posedge i_clk)begin
		if(i_rstn == 1'b0)begin
			flag_ccm_low_blue_center_right <= 1'b0; // 复位清除下溢标志
		end else begin
			case(flag_freeze)
				1'b1:begin
					flag_ccm_low_blue_center_right <= flag_ccm_low_blue_center_right; // 输出未取走时保持本级
				end
				default:begin
					flag_ccm_low_blue_center_right <= ($signed(reg_ccm_shift_blue_center_right) < 0); // 判断负值下钳位
				end
			endcase
		end
	end

	//blue 通道 right 像素矩阵下溢标志更新逻辑
	always@(posedge i_clk)begin
		if(i_rstn == 1'b0)begin
			flag_ccm_low_blue_right <= 1'b0; // 复位清除下溢标志
		end else begin
			case(flag_freeze)
				1'b1:begin
					flag_ccm_low_blue_right <= flag_ccm_low_blue_right; // 输出未取走时保持本级
				end
				default:begin
					flag_ccm_low_blue_right <= ($signed(reg_ccm_shift_blue_right) < 0); // 判断负值下钳位
				end
			endcase
		end
	end

	//blue 通道 left 像素矩阵下钳位延迟值更新逻辑
	always@(posedge i_clk)begin
		if(i_rstn == 1'b0)begin
			reg_ccm_delay_low_blue_left <= 24'd0; // 复位清空下钳位延迟值
		end else begin
			case(flag_freeze)
				1'b1:begin
					reg_ccm_delay_low_blue_left <= reg_ccm_delay_low_blue_left; // 输出未取走时保持本级
				end
				default:begin
					reg_ccm_delay_low_blue_left <= reg_ccm_shift_blue_left; // 与下溢标志对齐延迟移位值
				end
			endcase
		end
	end

	//blue 通道 center_left 像素矩阵下钳位延迟值更新逻辑
	always@(posedge i_clk)begin
		if(i_rstn == 1'b0)begin
			reg_ccm_delay_low_blue_center_left <= 24'd0; // 复位清空下钳位延迟值
		end else begin
			case(flag_freeze)
				1'b1:begin
					reg_ccm_delay_low_blue_center_left <= reg_ccm_delay_low_blue_center_left; // 输出未取走时保持本级
				end
				default:begin
					reg_ccm_delay_low_blue_center_left <= reg_ccm_shift_blue_center_left; // 与下溢标志对齐延迟移位值
				end
			endcase
		end
	end

	//blue 通道 center_right 像素矩阵下钳位延迟值更新逻辑
	always@(posedge i_clk)begin
		if(i_rstn == 1'b0)begin
			reg_ccm_delay_low_blue_center_right <= 24'd0; // 复位清空下钳位延迟值
		end else begin
			case(flag_freeze)
				1'b1:begin
					reg_ccm_delay_low_blue_center_right <= reg_ccm_delay_low_blue_center_right; // 输出未取走时保持本级
				end
				default:begin
					reg_ccm_delay_low_blue_center_right <= reg_ccm_shift_blue_center_right; // 与下溢标志对齐延迟移位值
				end
			endcase
		end
	end

	//blue 通道 right 像素矩阵下钳位延迟值更新逻辑
	always@(posedge i_clk)begin
		if(i_rstn == 1'b0)begin
			reg_ccm_delay_low_blue_right <= 24'd0; // 复位清空下钳位延迟值
		end else begin
			case(flag_freeze)
				1'b1:begin
					reg_ccm_delay_low_blue_right <= reg_ccm_delay_low_blue_right; // 输出未取走时保持本级
				end
				default:begin
					reg_ccm_delay_low_blue_right <= reg_ccm_shift_blue_right; // 与下溢标志对齐延迟移位值
				end
			endcase
		end
	end

	//blue 通道 left 像素矩阵下钳位值更新逻辑
	always@(posedge i_clk)begin
		if(i_rstn == 1'b0)begin
			reg_ccm_low_blue_left <= 24'd0; // 复位清空下钳位值
		end else begin
			case(flag_freeze)
				1'b1:begin
					reg_ccm_low_blue_left <= reg_ccm_low_blue_left; // 输出未取走时保持本级
				end
				default:begin
					reg_ccm_low_blue_left <= flag_ccm_low_blue_left ? 24'd0 : reg_ccm_delay_low_blue_left; // 负值钳位到零
				end
			endcase
		end
	end

	//blue 通道 center_left 像素矩阵下钳位值更新逻辑
	always@(posedge i_clk)begin
		if(i_rstn == 1'b0)begin
			reg_ccm_low_blue_center_left <= 24'd0; // 复位清空下钳位值
		end else begin
			case(flag_freeze)
				1'b1:begin
					reg_ccm_low_blue_center_left <= reg_ccm_low_blue_center_left; // 输出未取走时保持本级
				end
				default:begin
					reg_ccm_low_blue_center_left <= flag_ccm_low_blue_center_left ? 24'd0 : reg_ccm_delay_low_blue_center_left; // 负值钳位到零
				end
			endcase
		end
	end

	//blue 通道 center_right 像素矩阵下钳位值更新逻辑
	always@(posedge i_clk)begin
		if(i_rstn == 1'b0)begin
			reg_ccm_low_blue_center_right <= 24'd0; // 复位清空下钳位值
		end else begin
			case(flag_freeze)
				1'b1:begin
					reg_ccm_low_blue_center_right <= reg_ccm_low_blue_center_right; // 输出未取走时保持本级
				end
				default:begin
					reg_ccm_low_blue_center_right <= flag_ccm_low_blue_center_right ? 24'd0 : reg_ccm_delay_low_blue_center_right; // 负值钳位到零
				end
			endcase
		end
	end

	//blue 通道 right 像素矩阵下钳位值更新逻辑
	always@(posedge i_clk)begin
		if(i_rstn == 1'b0)begin
			reg_ccm_low_blue_right <= 24'd0; // 复位清空下钳位值
		end else begin
			case(flag_freeze)
				1'b1:begin
					reg_ccm_low_blue_right <= reg_ccm_low_blue_right; // 输出未取走时保持本级
				end
				default:begin
					reg_ccm_low_blue_right <= flag_ccm_low_blue_right ? 24'd0 : reg_ccm_delay_low_blue_right; // 负值钳位到零
				end
			endcase
		end
	end

	//blue 通道 left 像素矩阵下溢延迟标志更新逻辑
	always@(posedge i_clk)begin
		if(i_rstn == 1'b0)begin
			flag_ccm_low_hold_first_blue_left <= 1'b0; // 复位清除下溢延迟标志
		end else begin
			case(flag_freeze)
				1'b1:begin
					flag_ccm_low_hold_first_blue_left <= flag_ccm_low_hold_first_blue_left; // 输出未取走时保持本级
				end
				default:begin
					flag_ccm_low_hold_first_blue_left <= flag_ccm_low_blue_left; // 延迟下溢标志以待合并
				end
			endcase
		end
	end

	//blue 通道 center_left 像素矩阵下溢延迟标志更新逻辑
	always@(posedge i_clk)begin
		if(i_rstn == 1'b0)begin
			flag_ccm_low_hold_first_blue_center_left <= 1'b0; // 复位清除下溢延迟标志
		end else begin
			case(flag_freeze)
				1'b1:begin
					flag_ccm_low_hold_first_blue_center_left <= flag_ccm_low_hold_first_blue_center_left; // 输出未取走时保持本级
				end
				default:begin
					flag_ccm_low_hold_first_blue_center_left <= flag_ccm_low_blue_center_left; // 延迟下溢标志以待合并
				end
			endcase
		end
	end

	//blue 通道 center_right 像素矩阵下溢延迟标志更新逻辑
	always@(posedge i_clk)begin
		if(i_rstn == 1'b0)begin
			flag_ccm_low_hold_first_blue_center_right <= 1'b0; // 复位清除下溢延迟标志
		end else begin
			case(flag_freeze)
				1'b1:begin
					flag_ccm_low_hold_first_blue_center_right <= flag_ccm_low_hold_first_blue_center_right; // 输出未取走时保持本级
				end
				default:begin
					flag_ccm_low_hold_first_blue_center_right <= flag_ccm_low_blue_center_right; // 延迟下溢标志以待合并
				end
			endcase
		end
	end

	//blue 通道 right 像素矩阵下溢延迟标志更新逻辑
	always@(posedge i_clk)begin
		if(i_rstn == 1'b0)begin
			flag_ccm_low_hold_first_blue_right <= 1'b0; // 复位清除下溢延迟标志
		end else begin
			case(flag_freeze)
				1'b1:begin
					flag_ccm_low_hold_first_blue_right <= flag_ccm_low_hold_first_blue_right; // 输出未取走时保持本级
				end
				default:begin
					flag_ccm_low_hold_first_blue_right <= flag_ccm_low_blue_right; // 延迟下溢标志以待合并
				end
			endcase
		end
	end

	//blue 通道 left 像素矩阵上溢标志更新逻辑
	always@(posedge i_clk)begin
		if(i_rstn == 1'b0)begin
			flag_ccm_high_blue_left <= 1'b0; // 复位清除上溢标志
		end else begin
			case(flag_freeze)
				1'b1:begin
					flag_ccm_high_blue_left <= flag_ccm_high_blue_left; // 输出未取走时保持本级
				end
				default:begin
					flag_ccm_high_blue_left <= (reg_ccm_low_blue_left > C_CCM_MAX); // 比较矩阵上限
				end
			endcase
		end
	end

	//blue 通道 center_left 像素矩阵上溢标志更新逻辑
	always@(posedge i_clk)begin
		if(i_rstn == 1'b0)begin
			flag_ccm_high_blue_center_left <= 1'b0; // 复位清除上溢标志
		end else begin
			case(flag_freeze)
				1'b1:begin
					flag_ccm_high_blue_center_left <= flag_ccm_high_blue_center_left; // 输出未取走时保持本级
				end
				default:begin
					flag_ccm_high_blue_center_left <= (reg_ccm_low_blue_center_left > C_CCM_MAX); // 比较矩阵上限
				end
			endcase
		end
	end

	//blue 通道 center_right 像素矩阵上溢标志更新逻辑
	always@(posedge i_clk)begin
		if(i_rstn == 1'b0)begin
			flag_ccm_high_blue_center_right <= 1'b0; // 复位清除上溢标志
		end else begin
			case(flag_freeze)
				1'b1:begin
					flag_ccm_high_blue_center_right <= flag_ccm_high_blue_center_right; // 输出未取走时保持本级
				end
				default:begin
					flag_ccm_high_blue_center_right <= (reg_ccm_low_blue_center_right > C_CCM_MAX); // 比较矩阵上限
				end
			endcase
		end
	end

	//blue 通道 right 像素矩阵上溢标志更新逻辑
	always@(posedge i_clk)begin
		if(i_rstn == 1'b0)begin
			flag_ccm_high_blue_right <= 1'b0; // 复位清除上溢标志
		end else begin
			case(flag_freeze)
				1'b1:begin
					flag_ccm_high_blue_right <= flag_ccm_high_blue_right; // 输出未取走时保持本级
				end
				default:begin
					flag_ccm_high_blue_right <= (reg_ccm_low_blue_right > C_CCM_MAX); // 比较矩阵上限
				end
			endcase
		end
	end

	//blue 通道 left 像素矩阵上钳位延迟值更新逻辑
	always@(posedge i_clk)begin
		if(i_rstn == 1'b0)begin
			reg_ccm_delay_level_blue_left <= 24'd0; // 复位清空上钳位延迟值
		end else begin
			case(flag_freeze)
				1'b1:begin
					reg_ccm_delay_level_blue_left <= reg_ccm_delay_level_blue_left; // 输出未取走时保持本级
				end
				default:begin
					reg_ccm_delay_level_blue_left <= reg_ccm_low_blue_left; // 与上溢标志对齐延迟下钳位值
				end
			endcase
		end
	end

	//blue 通道 center_left 像素矩阵上钳位延迟值更新逻辑
	always@(posedge i_clk)begin
		if(i_rstn == 1'b0)begin
			reg_ccm_delay_level_blue_center_left <= 24'd0; // 复位清空上钳位延迟值
		end else begin
			case(flag_freeze)
				1'b1:begin
					reg_ccm_delay_level_blue_center_left <= reg_ccm_delay_level_blue_center_left; // 输出未取走时保持本级
				end
				default:begin
					reg_ccm_delay_level_blue_center_left <= reg_ccm_low_blue_center_left; // 与上溢标志对齐延迟下钳位值
				end
			endcase
		end
	end

	//blue 通道 center_right 像素矩阵上钳位延迟值更新逻辑
	always@(posedge i_clk)begin
		if(i_rstn == 1'b0)begin
			reg_ccm_delay_level_blue_center_right <= 24'd0; // 复位清空上钳位延迟值
		end else begin
			case(flag_freeze)
				1'b1:begin
					reg_ccm_delay_level_blue_center_right <= reg_ccm_delay_level_blue_center_right; // 输出未取走时保持本级
				end
				default:begin
					reg_ccm_delay_level_blue_center_right <= reg_ccm_low_blue_center_right; // 与上溢标志对齐延迟下钳位值
				end
			endcase
		end
	end

	//blue 通道 right 像素矩阵上钳位延迟值更新逻辑
	always@(posedge i_clk)begin
		if(i_rstn == 1'b0)begin
			reg_ccm_delay_level_blue_right <= 24'd0; // 复位清空上钳位延迟值
		end else begin
			case(flag_freeze)
				1'b1:begin
					reg_ccm_delay_level_blue_right <= reg_ccm_delay_level_blue_right; // 输出未取走时保持本级
				end
				default:begin
					reg_ccm_delay_level_blue_right <= reg_ccm_low_blue_right; // 与上溢标志对齐延迟下钳位值
				end
			endcase
		end
	end

	//blue 通道 left 像素矩阵下溢二次延迟标志更新逻辑
	always@(posedge i_clk)begin
		if(i_rstn == 1'b0)begin
			flag_ccm_low_hold_second_blue_left <= 1'b0; // 复位清除下溢二次延迟标志
		end else begin
			case(flag_freeze)
				1'b1:begin
					flag_ccm_low_hold_second_blue_left <= flag_ccm_low_hold_second_blue_left; // 输出未取走时保持本级
				end
				default:begin
					flag_ccm_low_hold_second_blue_left <= flag_ccm_low_hold_first_blue_left; // 二级延迟对齐上溢标志
				end
			endcase
		end
	end

	//blue 通道 center_left 像素矩阵下溢二次延迟标志更新逻辑
	always@(posedge i_clk)begin
		if(i_rstn == 1'b0)begin
			flag_ccm_low_hold_second_blue_center_left <= 1'b0; // 复位清除下溢二次延迟标志
		end else begin
			case(flag_freeze)
				1'b1:begin
					flag_ccm_low_hold_second_blue_center_left <= flag_ccm_low_hold_second_blue_center_left; // 输出未取走时保持本级
				end
				default:begin
					flag_ccm_low_hold_second_blue_center_left <= flag_ccm_low_hold_first_blue_center_left; // 二级延迟对齐上溢标志
				end
			endcase
		end
	end

	//blue 通道 center_right 像素矩阵下溢二次延迟标志更新逻辑
	always@(posedge i_clk)begin
		if(i_rstn == 1'b0)begin
			flag_ccm_low_hold_second_blue_center_right <= 1'b0; // 复位清除下溢二次延迟标志
		end else begin
			case(flag_freeze)
				1'b1:begin
					flag_ccm_low_hold_second_blue_center_right <= flag_ccm_low_hold_second_blue_center_right; // 输出未取走时保持本级
				end
				default:begin
					flag_ccm_low_hold_second_blue_center_right <= flag_ccm_low_hold_first_blue_center_right; // 二级延迟对齐上溢标志
				end
			endcase
		end
	end

	//blue 通道 right 像素矩阵下溢二次延迟标志更新逻辑
	always@(posedge i_clk)begin
		if(i_rstn == 1'b0)begin
			flag_ccm_low_hold_second_blue_right <= 1'b0; // 复位清除下溢二次延迟标志
		end else begin
			case(flag_freeze)
				1'b1:begin
					flag_ccm_low_hold_second_blue_right <= flag_ccm_low_hold_second_blue_right; // 输出未取走时保持本级
				end
				default:begin
					flag_ccm_low_hold_second_blue_right <= flag_ccm_low_hold_first_blue_right; // 二级延迟对齐上溢标志
				end
			endcase
		end
	end

	//blue 通道 left 像素矩阵输出码值更新逻辑
	always@(posedge i_clk)begin
		if(i_rstn == 1'b0)begin
			reg_ccm_level_blue_left <= 10'd0; // 复位清空矩阵输出码值
		end else begin
			case(flag_freeze)
				1'b1:begin
					reg_ccm_level_blue_left <= reg_ccm_level_blue_left; // 输出未取走时保持本级
				end
				default:begin
					reg_ccm_level_blue_left <= flag_ccm_high_blue_left ? C_CCM_MAX : reg_ccm_delay_level_blue_left[9:0]; // 按上溢标志选择上限
				end
			endcase
		end
	end

	//blue 通道 center_left 像素矩阵输出码值更新逻辑
	always@(posedge i_clk)begin
		if(i_rstn == 1'b0)begin
			reg_ccm_level_blue_center_left <= 10'd0; // 复位清空矩阵输出码值
		end else begin
			case(flag_freeze)
				1'b1:begin
					reg_ccm_level_blue_center_left <= reg_ccm_level_blue_center_left; // 输出未取走时保持本级
				end
				default:begin
					reg_ccm_level_blue_center_left <= flag_ccm_high_blue_center_left ? C_CCM_MAX : reg_ccm_delay_level_blue_center_left[9:0]; // 按上溢标志选择上限
				end
			endcase
		end
	end

	//blue 通道 center_right 像素矩阵输出码值更新逻辑
	always@(posedge i_clk)begin
		if(i_rstn == 1'b0)begin
			reg_ccm_level_blue_center_right <= 10'd0; // 复位清空矩阵输出码值
		end else begin
			case(flag_freeze)
				1'b1:begin
					reg_ccm_level_blue_center_right <= reg_ccm_level_blue_center_right; // 输出未取走时保持本级
				end
				default:begin
					reg_ccm_level_blue_center_right <= flag_ccm_high_blue_center_right ? C_CCM_MAX : reg_ccm_delay_level_blue_center_right[9:0]; // 按上溢标志选择上限
				end
			endcase
		end
	end

	//blue 通道 right 像素矩阵输出码值更新逻辑
	always@(posedge i_clk)begin
		if(i_rstn == 1'b0)begin
			reg_ccm_level_blue_right <= 10'd0; // 复位清空矩阵输出码值
		end else begin
			case(flag_freeze)
				1'b1:begin
					reg_ccm_level_blue_right <= reg_ccm_level_blue_right; // 输出未取走时保持本级
				end
				default:begin
					reg_ccm_level_blue_right <= flag_ccm_high_blue_right ? C_CCM_MAX : reg_ccm_delay_level_blue_right[9:0]; // 按上溢标志选择上限
				end
			endcase
		end
	end

	//blue 通道 left 像素矩阵饱和标志更新逻辑
	always@(posedge i_clk)begin
		if(i_rstn == 1'b0)begin
			flag_ccm_channel_blue_left <= 1'b0; // 复位清除通道饱和标志
		end else begin
			case(flag_freeze)
				1'b1:begin
					flag_ccm_channel_blue_left <= flag_ccm_channel_blue_left; // 输出未取走时保持本级
				end
				default:begin
					flag_ccm_channel_blue_left <= flag_ccm_low_hold_second_blue_left | flag_ccm_high_blue_left; // 归并同拍矩阵上下溢
				end
			endcase
		end
	end

	//blue 通道 center_left 像素矩阵饱和标志更新逻辑
	always@(posedge i_clk)begin
		if(i_rstn == 1'b0)begin
			flag_ccm_channel_blue_center_left <= 1'b0; // 复位清除通道饱和标志
		end else begin
			case(flag_freeze)
				1'b1:begin
					flag_ccm_channel_blue_center_left <= flag_ccm_channel_blue_center_left; // 输出未取走时保持本级
				end
				default:begin
					flag_ccm_channel_blue_center_left <= flag_ccm_low_hold_second_blue_center_left | flag_ccm_high_blue_center_left; // 归并同拍矩阵上下溢
				end
			endcase
		end
	end

	//blue 通道 center_right 像素矩阵饱和标志更新逻辑
	always@(posedge i_clk)begin
		if(i_rstn == 1'b0)begin
			flag_ccm_channel_blue_center_right <= 1'b0; // 复位清除通道饱和标志
		end else begin
			case(flag_freeze)
				1'b1:begin
					flag_ccm_channel_blue_center_right <= flag_ccm_channel_blue_center_right; // 输出未取走时保持本级
				end
				default:begin
					flag_ccm_channel_blue_center_right <= flag_ccm_low_hold_second_blue_center_right | flag_ccm_high_blue_center_right; // 归并同拍矩阵上下溢
				end
			endcase
		end
	end

	//blue 通道 right 像素矩阵饱和标志更新逻辑
	always@(posedge i_clk)begin
		if(i_rstn == 1'b0)begin
			flag_ccm_channel_blue_right <= 1'b0; // 复位清除通道饱和标志
		end else begin
			case(flag_freeze)
				1'b1:begin
					flag_ccm_channel_blue_right <= flag_ccm_channel_blue_right; // 输出未取走时保持本级
				end
				default:begin
					flag_ccm_channel_blue_right <= flag_ccm_low_hold_second_blue_right | flag_ccm_high_blue_right; // 归并同拍矩阵上下溢
				end
			endcase
		end
	end

	//left 像素红绿通道矩阵饱和归并逻辑
	always@(posedge i_clk)begin
		if(i_rstn == 1'b0)begin
			flag_ccm_pair_left <= 1'b0; // 复位清除红绿归并标志
		end else begin
			case(flag_freeze)
				1'b1:begin
					flag_ccm_pair_left <= flag_ccm_pair_left; // 输出未取走时保持本级
				end
				default:begin
					flag_ccm_pair_left <= flag_ccm_channel_red_left | flag_ccm_channel_green_left; // 归并红绿两通道
				end
			endcase
		end
	end

	//center_left 像素红绿通道矩阵饱和归并逻辑
	always@(posedge i_clk)begin
		if(i_rstn == 1'b0)begin
			flag_ccm_pair_center_left <= 1'b0; // 复位清除红绿归并标志
		end else begin
			case(flag_freeze)
				1'b1:begin
					flag_ccm_pair_center_left <= flag_ccm_pair_center_left; // 输出未取走时保持本级
				end
				default:begin
					flag_ccm_pair_center_left <= flag_ccm_channel_red_center_left | flag_ccm_channel_green_center_left; // 归并红绿两通道
				end
			endcase
		end
	end

	//center_right 像素红绿通道矩阵饱和归并逻辑
	always@(posedge i_clk)begin
		if(i_rstn == 1'b0)begin
			flag_ccm_pair_center_right <= 1'b0; // 复位清除红绿归并标志
		end else begin
			case(flag_freeze)
				1'b1:begin
					flag_ccm_pair_center_right <= flag_ccm_pair_center_right; // 输出未取走时保持本级
				end
				default:begin
					flag_ccm_pair_center_right <= flag_ccm_channel_red_center_right | flag_ccm_channel_green_center_right; // 归并红绿两通道
				end
			endcase
		end
	end

	//right 像素红绿通道矩阵饱和归并逻辑
	always@(posedge i_clk)begin
		if(i_rstn == 1'b0)begin
			flag_ccm_pair_right <= 1'b0; // 复位清除红绿归并标志
		end else begin
			case(flag_freeze)
				1'b1:begin
					flag_ccm_pair_right <= flag_ccm_pair_right; // 输出未取走时保持本级
				end
				default:begin
					flag_ccm_pair_right <= flag_ccm_channel_red_right | flag_ccm_channel_green_right; // 归并红绿两通道
				end
			endcase
		end
	end

	//left 像素蓝通道矩阵饱和延迟逻辑
	always@(posedge i_clk)begin
		if(i_rstn == 1'b0)begin
			flag_ccm_blue_left <= 1'b0; // 复位清除蓝通道延迟标志
		end else begin
			case(flag_freeze)
				1'b1:begin
					flag_ccm_blue_left <= flag_ccm_blue_left; // 输出未取走时保持本级
				end
				default:begin
					flag_ccm_blue_left <= flag_ccm_channel_blue_left; // 对齐红绿归并级延迟蓝通道
				end
			endcase
		end
	end

	//center_left 像素蓝通道矩阵饱和延迟逻辑
	always@(posedge i_clk)begin
		if(i_rstn == 1'b0)begin
			flag_ccm_blue_center_left <= 1'b0; // 复位清除蓝通道延迟标志
		end else begin
			case(flag_freeze)
				1'b1:begin
					flag_ccm_blue_center_left <= flag_ccm_blue_center_left; // 输出未取走时保持本级
				end
				default:begin
					flag_ccm_blue_center_left <= flag_ccm_channel_blue_center_left; // 对齐红绿归并级延迟蓝通道
				end
			endcase
		end
	end

	//center_right 像素蓝通道矩阵饱和延迟逻辑
	always@(posedge i_clk)begin
		if(i_rstn == 1'b0)begin
			flag_ccm_blue_center_right <= 1'b0; // 复位清除蓝通道延迟标志
		end else begin
			case(flag_freeze)
				1'b1:begin
					flag_ccm_blue_center_right <= flag_ccm_blue_center_right; // 输出未取走时保持本级
				end
				default:begin
					flag_ccm_blue_center_right <= flag_ccm_channel_blue_center_right; // 对齐红绿归并级延迟蓝通道
				end
			endcase
		end
	end

	//right 像素蓝通道矩阵饱和延迟逻辑
	always@(posedge i_clk)begin
		if(i_rstn == 1'b0)begin
			flag_ccm_blue_right <= 1'b0; // 复位清除蓝通道延迟标志
		end else begin
			case(flag_freeze)
				1'b1:begin
					flag_ccm_blue_right <= flag_ccm_blue_right; // 输出未取走时保持本级
				end
				default:begin
					flag_ccm_blue_right <= flag_ccm_channel_blue_right; // 对齐红绿归并级延迟蓝通道
				end
			endcase
		end
	end

	//left 像素矩阵饱和归并逻辑
	always@(posedge i_clk)begin
		if(i_rstn == 1'b0)begin
			flag_ccm_lane_left <= 1'b0; // 复位清除像素归并标志
		end else begin
			case(flag_freeze)
				1'b1:begin
					flag_ccm_lane_left <= flag_ccm_lane_left; // 输出未取走时保持本级
				end
				default:begin
					flag_ccm_lane_left <= flag_ccm_pair_left | flag_ccm_blue_left; // 并入已对齐的蓝通道饱和
				end
			endcase
		end
	end

	//center_left 像素矩阵饱和归并逻辑
	always@(posedge i_clk)begin
		if(i_rstn == 1'b0)begin
			flag_ccm_lane_center_left <= 1'b0; // 复位清除像素归并标志
		end else begin
			case(flag_freeze)
				1'b1:begin
					flag_ccm_lane_center_left <= flag_ccm_lane_center_left; // 输出未取走时保持本级
				end
				default:begin
					flag_ccm_lane_center_left <= flag_ccm_pair_center_left | flag_ccm_blue_center_left; // 并入已对齐的蓝通道饱和
				end
			endcase
		end
	end

	//center_right 像素矩阵饱和归并逻辑
	always@(posedge i_clk)begin
		if(i_rstn == 1'b0)begin
			flag_ccm_lane_center_right <= 1'b0; // 复位清除像素归并标志
		end else begin
			case(flag_freeze)
				1'b1:begin
					flag_ccm_lane_center_right <= flag_ccm_lane_center_right; // 输出未取走时保持本级
				end
				default:begin
					flag_ccm_lane_center_right <= flag_ccm_pair_center_right | flag_ccm_blue_center_right; // 并入已对齐的蓝通道饱和
				end
			endcase
		end
	end

	//right 像素矩阵饱和归并逻辑
	always@(posedge i_clk)begin
		if(i_rstn == 1'b0)begin
			flag_ccm_lane_right <= 1'b0; // 复位清除像素归并标志
		end else begin
			case(flag_freeze)
				1'b1:begin
					flag_ccm_lane_right <= flag_ccm_lane_right; // 输出未取走时保持本级
				end
				default:begin
					flag_ccm_lane_right <= flag_ccm_pair_right | flag_ccm_blue_right; // 并入已对齐的蓝通道饱和
				end
			endcase
		end
	end

	//低半幅矩阵饱和归并逻辑
	always@(posedge i_clk)begin
		if(i_rstn == 1'b0)begin
			flag_ccm_group_low <= 1'b0; // 复位清除低半幅标志
		end else begin
			case(flag_freeze)
				1'b1:begin
					flag_ccm_group_low <= flag_ccm_group_low; // 输出未取走时保持本级
				end
				default:begin
					flag_ccm_group_low <= flag_ccm_lane_left | flag_ccm_lane_center_left; // 归并低半幅两像素
				end
			endcase
		end
	end

	//高半幅矩阵饱和归并逻辑
	always@(posedge i_clk)begin
		if(i_rstn == 1'b0)begin
			flag_ccm_group_high <= 1'b0; // 复位清除高半幅标志
		end else begin
			case(flag_freeze)
				1'b1:begin
					flag_ccm_group_high <= flag_ccm_group_high; // 输出未取走时保持本级
				end
				default:begin
					flag_ccm_group_high <= flag_ccm_lane_center_right | flag_ccm_lane_right; // 归并高半幅两像素
				end
			endcase
		end
	end

	//矩阵饱和 beat 标志更新逻辑
	always@(posedge i_clk)begin
		if(i_rstn == 1'b0)begin
			flag_ccm_beat <= 1'b0; // 复位清除 beat 饱和标志
		end else begin
			case(flag_freeze)
				1'b1:begin
					flag_ccm_beat <= flag_ccm_beat; // 输出未取走时保持本级
				end
				default:begin
					flag_ccm_beat <= flag_ccm_group_low | flag_ccm_group_high; // 归并整个 beat
				end
			endcase
		end
	end

	//left 像素打包值更新逻辑
	always@(posedge i_clk)begin
		if(i_rstn == 1'b0)begin
			reg_pack_lane_left <= 24'd0; // 复位清空像素打包值
		end else begin
			case(flag_freeze)
				1'b1:begin
					reg_pack_lane_left <= reg_pack_lane_left; // 输出未取走时保持本级
				end
				default:begin
					reg_pack_lane_left <= {data_gamma_red_left, data_gamma_green_left, data_gamma_blue_left}; // 同拍拼接三通道
				end
			endcase
		end
	end

	//center_left 像素打包值更新逻辑
	always@(posedge i_clk)begin
		if(i_rstn == 1'b0)begin
			reg_pack_lane_center_left <= 24'd0; // 复位清空像素打包值
		end else begin
			case(flag_freeze)
				1'b1:begin
					reg_pack_lane_center_left <= reg_pack_lane_center_left; // 输出未取走时保持本级
				end
				default:begin
					reg_pack_lane_center_left <= {data_gamma_red_center_left, data_gamma_green_center_left, data_gamma_blue_center_left}; // 同拍拼接三通道
				end
			endcase
		end
	end

	//center_right 像素打包值更新逻辑
	always@(posedge i_clk)begin
		if(i_rstn == 1'b0)begin
			reg_pack_lane_center_right <= 24'd0; // 复位清空像素打包值
		end else begin
			case(flag_freeze)
				1'b1:begin
					reg_pack_lane_center_right <= reg_pack_lane_center_right; // 输出未取走时保持本级
				end
				default:begin
					reg_pack_lane_center_right <= {data_gamma_red_center_right, data_gamma_green_center_right, data_gamma_blue_center_right}; // 同拍拼接三通道
				end
			endcase
		end
	end

	//right 像素打包值更新逻辑
	always@(posedge i_clk)begin
		if(i_rstn == 1'b0)begin
			reg_pack_lane_right <= 24'd0; // 复位清空像素打包值
		end else begin
			case(flag_freeze)
				1'b1:begin
					reg_pack_lane_right <= reg_pack_lane_right; // 输出未取走时保持本级
				end
				default:begin
					reg_pack_lane_right <= {data_gamma_red_right, data_gamma_green_right, data_gamma_blue_right}; // 同拍拼接三通道
				end
			endcase
		end
	end

	//低半幅打包值更新逻辑
	always@(posedge i_clk)begin
		if(i_rstn == 1'b0)begin
			reg_pack_low <= 48'd0; // 复位清空低半幅打包值
		end else begin
			case(flag_freeze)
				1'b1:begin
					reg_pack_low <= reg_pack_low; // 输出未取走时保持本级
				end
				default:begin
					reg_pack_low <= {reg_pack_lane_center_left, reg_pack_lane_left}; // 拼接左侧两像素
				end
			endcase
		end
	end

	//高半幅打包值更新逻辑
	always@(posedge i_clk)begin
		if(i_rstn == 1'b0)begin
			reg_pack_high <= 48'd0; // 复位清空高半幅打包值
		end else begin
			case(flag_freeze)
				1'b1:begin
					reg_pack_high <= reg_pack_high; // 输出未取走时保持本级
				end
				default:begin
					reg_pack_high <= {reg_pack_lane_right, reg_pack_lane_center_right}; // 拼接右侧两像素
				end
			endcase
		end
	end

	//输出 beat 数据缓存更新逻辑
	always@(posedge i_clk)begin
		if(i_rstn == 1'b0)begin
			reg_word_output <= 96'd0; // 复位清空输出 beat 数据
		end else begin
			case(flag_freeze)
				1'b1:begin
					reg_word_output <= reg_word_output; // 输出未取走时保持本级
				end
				default:begin
					reg_word_output <= {reg_pack_high, reg_pack_low}; // 拼接左右半幅
				end
			endcase
		end
	end

	//第2级流水控制位缓存更新逻辑
	always@(posedge i_clk)begin
		if(i_rstn == 1'b0)begin
			reg_ctrl_stagealpha <= 3'd0; // 复位清空控制位
		end else begin
			case(flag_freeze)
				1'b1:begin
					reg_ctrl_stagealpha <= reg_ctrl_stagealpha; // 输出未取走时保持本级
				end
				default:begin
					reg_ctrl_stagealpha <= reg_ctrl_input; // 随流水传递控制位
				end
			endcase
		end
	end

	//第3级流水控制位缓存更新逻辑
	always@(posedge i_clk)begin
		if(i_rstn == 1'b0)begin
			reg_ctrl_stagebravo <= 3'd0; // 复位清空控制位
		end else begin
			case(flag_freeze)
				1'b1:begin
					reg_ctrl_stagebravo <= reg_ctrl_stagebravo; // 输出未取走时保持本级
				end
				default:begin
					reg_ctrl_stagebravo <= reg_ctrl_stagealpha; // 随流水传递控制位
				end
			endcase
		end
	end

	//第4级流水控制位缓存更新逻辑
	always@(posedge i_clk)begin
		if(i_rstn == 1'b0)begin
			reg_ctrl_stagecharlie <= 3'd0; // 复位清空控制位
		end else begin
			case(flag_freeze)
				1'b1:begin
					reg_ctrl_stagecharlie <= reg_ctrl_stagecharlie; // 输出未取走时保持本级
				end
				default:begin
					reg_ctrl_stagecharlie <= reg_ctrl_stagebravo; // 随流水传递控制位
				end
			endcase
		end
	end

	//第5级流水控制位缓存更新逻辑
	always@(posedge i_clk)begin
		if(i_rstn == 1'b0)begin
			reg_ctrl_stagedelta <= 3'd0; // 复位清空控制位
		end else begin
			case(flag_freeze)
				1'b1:begin
					reg_ctrl_stagedelta <= reg_ctrl_stagedelta; // 输出未取走时保持本级
				end
				default:begin
					reg_ctrl_stagedelta <= reg_ctrl_stagecharlie; // 随流水传递控制位
				end
			endcase
		end
	end

	//第6级流水控制位缓存更新逻辑
	always@(posedge i_clk)begin
		if(i_rstn == 1'b0)begin
			reg_ctrl_stageecho <= 3'd0; // 复位清空控制位
		end else begin
			case(flag_freeze)
				1'b1:begin
					reg_ctrl_stageecho <= reg_ctrl_stageecho; // 输出未取走时保持本级
				end
				default:begin
					reg_ctrl_stageecho <= reg_ctrl_stagedelta; // 随流水传递控制位
				end
			endcase
		end
	end

	//第7级流水控制位缓存更新逻辑
	always@(posedge i_clk)begin
		if(i_rstn == 1'b0)begin
			reg_ctrl_stagefoxtrot <= 3'd0; // 复位清空控制位
		end else begin
			case(flag_freeze)
				1'b1:begin
					reg_ctrl_stagefoxtrot <= reg_ctrl_stagefoxtrot; // 输出未取走时保持本级
				end
				default:begin
					reg_ctrl_stagefoxtrot <= reg_ctrl_stageecho; // 随流水传递控制位
				end
			endcase
		end
	end

	//第8级流水控制位缓存更新逻辑
	always@(posedge i_clk)begin
		if(i_rstn == 1'b0)begin
			reg_ctrl_stagegolf <= 3'd0; // 复位清空控制位
		end else begin
			case(flag_freeze)
				1'b1:begin
					reg_ctrl_stagegolf <= reg_ctrl_stagegolf; // 输出未取走时保持本级
				end
				default:begin
					reg_ctrl_stagegolf <= reg_ctrl_stagefoxtrot; // 随流水传递控制位
				end
			endcase
		end
	end

	//第9级流水控制位缓存更新逻辑
	always@(posedge i_clk)begin
		if(i_rstn == 1'b0)begin
			reg_ctrl_stagehotel <= 3'd0; // 复位清空控制位
		end else begin
			case(flag_freeze)
				1'b1:begin
					reg_ctrl_stagehotel <= reg_ctrl_stagehotel; // 输出未取走时保持本级
				end
				default:begin
					reg_ctrl_stagehotel <= reg_ctrl_stagegolf; // 随流水传递控制位
				end
			endcase
		end
	end

	//第10级流水控制位缓存更新逻辑
	always@(posedge i_clk)begin
		if(i_rstn == 1'b0)begin
			reg_ctrl_stageindia <= 3'd0; // 复位清空控制位
		end else begin
			case(flag_freeze)
				1'b1:begin
					reg_ctrl_stageindia <= reg_ctrl_stageindia; // 输出未取走时保持本级
				end
				default:begin
					reg_ctrl_stageindia <= reg_ctrl_stagehotel; // 随流水传递控制位
				end
			endcase
		end
	end

	//第11级流水控制位缓存更新逻辑
	always@(posedge i_clk)begin
		if(i_rstn == 1'b0)begin
			reg_ctrl_stagejuliet <= 3'd0; // 复位清空控制位
		end else begin
			case(flag_freeze)
				1'b1:begin
					reg_ctrl_stagejuliet <= reg_ctrl_stagejuliet; // 输出未取走时保持本级
				end
				default:begin
					reg_ctrl_stagejuliet <= reg_ctrl_stageindia; // 随流水传递控制位
				end
			endcase
		end
	end

	//第12级流水控制位缓存更新逻辑
	always@(posedge i_clk)begin
		if(i_rstn == 1'b0)begin
			reg_ctrl_stagekilo <= 3'd0; // 复位清空控制位
		end else begin
			case(flag_freeze)
				1'b1:begin
					reg_ctrl_stagekilo <= reg_ctrl_stagekilo; // 输出未取走时保持本级
				end
				default:begin
					reg_ctrl_stagekilo <= reg_ctrl_stagejuliet; // 随流水传递控制位
				end
			endcase
		end
	end

	//第13级流水控制位缓存更新逻辑
	always@(posedge i_clk)begin
		if(i_rstn == 1'b0)begin
			reg_ctrl_stagelima <= 3'd0; // 复位清空控制位
		end else begin
			case(flag_freeze)
				1'b1:begin
					reg_ctrl_stagelima <= reg_ctrl_stagelima; // 输出未取走时保持本级
				end
				default:begin
					reg_ctrl_stagelima <= reg_ctrl_stagekilo; // 随流水传递控制位
				end
			endcase
		end
	end

	//第14级流水控制位缓存更新逻辑
	always@(posedge i_clk)begin
		if(i_rstn == 1'b0)begin
			reg_ctrl_stagemike <= 3'd0; // 复位清空控制位
		end else begin
			case(flag_freeze)
				1'b1:begin
					reg_ctrl_stagemike <= reg_ctrl_stagemike; // 输出未取走时保持本级
				end
				default:begin
					reg_ctrl_stagemike <= reg_ctrl_stagelima; // 随流水传递控制位
				end
			endcase
		end
	end

	//第15级流水控制位缓存更新逻辑
	always@(posedge i_clk)begin
		if(i_rstn == 1'b0)begin
			reg_ctrl_stagenovember <= 3'd0; // 复位清空控制位
		end else begin
			case(flag_freeze)
				1'b1:begin
					reg_ctrl_stagenovember <= reg_ctrl_stagenovember; // 输出未取走时保持本级
				end
				default:begin
					reg_ctrl_stagenovember <= reg_ctrl_stagemike; // 随流水传递控制位
				end
			endcase
		end
	end

	//第16级流水控制位缓存更新逻辑
	always@(posedge i_clk)begin
		if(i_rstn == 1'b0)begin
			reg_ctrl_stageoscar <= 3'd0; // 复位清空控制位
		end else begin
			case(flag_freeze)
				1'b1:begin
					reg_ctrl_stageoscar <= reg_ctrl_stageoscar; // 输出未取走时保持本级
				end
				default:begin
					reg_ctrl_stageoscar <= reg_ctrl_stagenovember; // 随流水传递控制位
				end
			endcase
		end
	end

	//第17级流水控制位缓存更新逻辑
	always@(posedge i_clk)begin
		if(i_rstn == 1'b0)begin
			reg_ctrl_stagepapa <= 3'd0; // 复位清空控制位
		end else begin
			case(flag_freeze)
				1'b1:begin
					reg_ctrl_stagepapa <= reg_ctrl_stagepapa; // 输出未取走时保持本级
				end
				default:begin
					reg_ctrl_stagepapa <= reg_ctrl_stageoscar; // 随流水传递控制位
				end
			endcase
		end
	end

	//第18级流水控制位缓存更新逻辑
	always@(posedge i_clk)begin
		if(i_rstn == 1'b0)begin
			reg_ctrl_stagequebec <= 3'd0; // 复位清空控制位
		end else begin
			case(flag_freeze)
				1'b1:begin
					reg_ctrl_stagequebec <= reg_ctrl_stagequebec; // 输出未取走时保持本级
				end
				default:begin
					reg_ctrl_stagequebec <= reg_ctrl_stagepapa; // 随流水传递控制位
				end
			endcase
		end
	end

	//第19级流水控制位缓存更新逻辑
	always@(posedge i_clk)begin
		if(i_rstn == 1'b0)begin
			reg_ctrl_stageromeo <= 3'd0; // 复位清空控制位
		end else begin
			case(flag_freeze)
				1'b1:begin
					reg_ctrl_stageromeo <= reg_ctrl_stageromeo; // 输出未取走时保持本级
				end
				default:begin
					reg_ctrl_stageromeo <= reg_ctrl_stagequebec; // 随流水传递控制位
				end
			endcase
		end
	end

	//第20级流水控制位缓存更新逻辑
	always@(posedge i_clk)begin
		if(i_rstn == 1'b0)begin
			reg_ctrl_stagesierra <= 3'd0; // 复位清空控制位
		end else begin
			case(flag_freeze)
				1'b1:begin
					reg_ctrl_stagesierra <= reg_ctrl_stagesierra; // 输出未取走时保持本级
				end
				default:begin
					reg_ctrl_stagesierra <= reg_ctrl_stageromeo; // 随流水传递控制位
				end
			endcase
		end
	end

	//第21级流水控制位缓存更新逻辑
	always@(posedge i_clk)begin
		if(i_rstn == 1'b0)begin
			reg_ctrl_stagetango <= 3'd0; // 复位清空控制位
		end else begin
			case(flag_freeze)
				1'b1:begin
					reg_ctrl_stagetango <= reg_ctrl_stagetango; // 输出未取走时保持本级
				end
				default:begin
					reg_ctrl_stagetango <= reg_ctrl_stagesierra; // 随流水传递控制位
				end
			endcase
		end
	end

	//白平衡饱和标志第1级延迟更新逻辑
	always@(posedge i_clk)begin
		if(i_rstn == 1'b0)begin
			flag_wb_pendingalpha <= 1'b0; // 复位清除延迟标志
		end else begin
			case(flag_freeze)
				1'b1:begin
					flag_wb_pendingalpha <= flag_wb_pendingalpha; // 输出未取走时保持本级
				end
				default:begin
					flag_wb_pendingalpha <= flag_wb_beat; // 延迟白平衡饱和标志
				end
			endcase
		end
	end

	//白平衡饱和标志第2级延迟更新逻辑
	always@(posedge i_clk)begin
		if(i_rstn == 1'b0)begin
			flag_wb_pendingbravo <= 1'b0; // 复位清除延迟标志
		end else begin
			case(flag_freeze)
				1'b1:begin
					flag_wb_pendingbravo <= flag_wb_pendingbravo; // 输出未取走时保持本级
				end
				default:begin
					flag_wb_pendingbravo <= flag_wb_pendingalpha; // 延迟白平衡饱和标志
				end
			endcase
		end
	end

	//白平衡饱和标志第3级延迟更新逻辑
	always@(posedge i_clk)begin
		if(i_rstn == 1'b0)begin
			flag_wb_pendingcharlie <= 1'b0; // 复位清除延迟标志
		end else begin
			case(flag_freeze)
				1'b1:begin
					flag_wb_pendingcharlie <= flag_wb_pendingcharlie; // 输出未取走时保持本级
				end
				default:begin
					flag_wb_pendingcharlie <= flag_wb_pendingbravo; // 延迟白平衡饱和标志
				end
			endcase
		end
	end

	//白平衡饱和标志第4级延迟更新逻辑
	always@(posedge i_clk)begin
		if(i_rstn == 1'b0)begin
			flag_wb_pendingdelta <= 1'b0; // 复位清除延迟标志
		end else begin
			case(flag_freeze)
				1'b1:begin
					flag_wb_pendingdelta <= flag_wb_pendingdelta; // 输出未取走时保持本级
				end
				default:begin
					flag_wb_pendingdelta <= flag_wb_pendingcharlie; // 延迟白平衡饱和标志
				end
			endcase
		end
	end

	//白平衡饱和标志第5级延迟更新逻辑
	always@(posedge i_clk)begin
		if(i_rstn == 1'b0)begin
			flag_wb_pendingecho <= 1'b0; // 复位清除延迟标志
		end else begin
			case(flag_freeze)
				1'b1:begin
					flag_wb_pendingecho <= flag_wb_pendingecho; // 输出未取走时保持本级
				end
				default:begin
					flag_wb_pendingecho <= flag_wb_pendingdelta; // 延迟白平衡饱和标志
				end
			endcase
		end
	end

	//白平衡饱和标志第6级延迟更新逻辑
	always@(posedge i_clk)begin
		if(i_rstn == 1'b0)begin
			flag_wb_pendingfoxtrot <= 1'b0; // 复位清除延迟标志
		end else begin
			case(flag_freeze)
				1'b1:begin
					flag_wb_pendingfoxtrot <= flag_wb_pendingfoxtrot; // 输出未取走时保持本级
				end
				default:begin
					flag_wb_pendingfoxtrot <= flag_wb_pendingecho; // 延迟白平衡饱和标志
				end
			endcase
		end
	end

	//白平衡饱和标志第7级延迟更新逻辑
	always@(posedge i_clk)begin
		if(i_rstn == 1'b0)begin
			flag_wb_pendinggolf <= 1'b0; // 复位清除延迟标志
		end else begin
			case(flag_freeze)
				1'b1:begin
					flag_wb_pendinggolf <= flag_wb_pendinggolf; // 输出未取走时保持本级
				end
				default:begin
					flag_wb_pendinggolf <= flag_wb_pendingfoxtrot; // 延迟白平衡饱和标志
				end
			endcase
		end
	end

	//白平衡饱和标志第8级延迟更新逻辑
	always@(posedge i_clk)begin
		if(i_rstn == 1'b0)begin
			flag_wb_pendinghotel <= 1'b0; // 复位清除延迟标志
		end else begin
			case(flag_freeze)
				1'b1:begin
					flag_wb_pendinghotel <= flag_wb_pendinghotel; // 输出未取走时保持本级
				end
				default:begin
					flag_wb_pendinghotel <= flag_wb_pendinggolf; // 延迟白平衡饱和标志
				end
			endcase
		end
	end

	//白平衡饱和标志第9级延迟更新逻辑
	always@(posedge i_clk)begin
		if(i_rstn == 1'b0)begin
			flag_wb_pendingindia <= 1'b0; // 复位清除延迟标志
		end else begin
			case(flag_freeze)
				1'b1:begin
					flag_wb_pendingindia <= flag_wb_pendingindia; // 输出未取走时保持本级
				end
				default:begin
					flag_wb_pendingindia <= flag_wb_pendinghotel; // 延迟白平衡饱和标志
				end
			endcase
		end
	end

	//白平衡饱和标志第10级延迟更新逻辑
	always@(posedge i_clk)begin
		if(i_rstn == 1'b0)begin
			flag_wb_pendingjuliet <= 1'b0; // 复位清除延迟标志
		end else begin
			case(flag_freeze)
				1'b1:begin
					flag_wb_pendingjuliet <= flag_wb_pendingjuliet; // 输出未取走时保持本级
				end
				default:begin
					flag_wb_pendingjuliet <= flag_wb_pendingindia; // 延迟白平衡饱和标志
				end
			endcase
		end
	end
	//------------模块实例化区域------------//
	//red 通道 left 像素伽马查表实例
	gamma_lut_10to8
	#(
		.C_GAMMA_LINEAR_BYPASS(C_GAMMA_LINEAR_BYPASS)
	)gamma_lut_10to8_Inst_red_left(
		.i_clk(i_clk),
		.i_rstn(i_rstn),
		.i_index(reg_ccm_level_red_left),
		.o_value(data_gamma_red_left)
	);

	//red 通道 center_left 像素伽马查表实例
	gamma_lut_10to8
	#(
		.C_GAMMA_LINEAR_BYPASS(C_GAMMA_LINEAR_BYPASS)
	)gamma_lut_10to8_Inst_red_center_left(
		.i_clk(i_clk),
		.i_rstn(i_rstn),
		.i_index(reg_ccm_level_red_center_left),
		.o_value(data_gamma_red_center_left)
	);

	//red 通道 center_right 像素伽马查表实例
	gamma_lut_10to8
	#(
		.C_GAMMA_LINEAR_BYPASS(C_GAMMA_LINEAR_BYPASS)
	)gamma_lut_10to8_Inst_red_center_right(
		.i_clk(i_clk),
		.i_rstn(i_rstn),
		.i_index(reg_ccm_level_red_center_right),
		.o_value(data_gamma_red_center_right)
	);

	//red 通道 right 像素伽马查表实例
	gamma_lut_10to8
	#(
		.C_GAMMA_LINEAR_BYPASS(C_GAMMA_LINEAR_BYPASS)
	)gamma_lut_10to8_Inst_red_right(
		.i_clk(i_clk),
		.i_rstn(i_rstn),
		.i_index(reg_ccm_level_red_right),
		.o_value(data_gamma_red_right)
	);

	//green 通道 left 像素伽马查表实例
	gamma_lut_10to8
	#(
		.C_GAMMA_LINEAR_BYPASS(C_GAMMA_LINEAR_BYPASS)
	)gamma_lut_10to8_Inst_green_left(
		.i_clk(i_clk),
		.i_rstn(i_rstn),
		.i_index(reg_ccm_level_green_left),
		.o_value(data_gamma_green_left)
	);

	//green 通道 center_left 像素伽马查表实例
	gamma_lut_10to8
	#(
		.C_GAMMA_LINEAR_BYPASS(C_GAMMA_LINEAR_BYPASS)
	)gamma_lut_10to8_Inst_green_center_left(
		.i_clk(i_clk),
		.i_rstn(i_rstn),
		.i_index(reg_ccm_level_green_center_left),
		.o_value(data_gamma_green_center_left)
	);

	//green 通道 center_right 像素伽马查表实例
	gamma_lut_10to8
	#(
		.C_GAMMA_LINEAR_BYPASS(C_GAMMA_LINEAR_BYPASS)
	)gamma_lut_10to8_Inst_green_center_right(
		.i_clk(i_clk),
		.i_rstn(i_rstn),
		.i_index(reg_ccm_level_green_center_right),
		.o_value(data_gamma_green_center_right)
	);

	//green 通道 right 像素伽马查表实例
	gamma_lut_10to8
	#(
		.C_GAMMA_LINEAR_BYPASS(C_GAMMA_LINEAR_BYPASS)
	)gamma_lut_10to8_Inst_green_right(
		.i_clk(i_clk),
		.i_rstn(i_rstn),
		.i_index(reg_ccm_level_green_right),
		.o_value(data_gamma_green_right)
	);

	//blue 通道 left 像素伽马查表实例
	gamma_lut_10to8
	#(
		.C_GAMMA_LINEAR_BYPASS(C_GAMMA_LINEAR_BYPASS)
	)gamma_lut_10to8_Inst_blue_left(
		.i_clk(i_clk),
		.i_rstn(i_rstn),
		.i_index(reg_ccm_level_blue_left),
		.o_value(data_gamma_blue_left)
	);

	//blue 通道 center_left 像素伽马查表实例
	gamma_lut_10to8
	#(
		.C_GAMMA_LINEAR_BYPASS(C_GAMMA_LINEAR_BYPASS)
	)gamma_lut_10to8_Inst_blue_center_left(
		.i_clk(i_clk),
		.i_rstn(i_rstn),
		.i_index(reg_ccm_level_blue_center_left),
		.o_value(data_gamma_blue_center_left)
	);

	//blue 通道 center_right 像素伽马查表实例
	gamma_lut_10to8
	#(
		.C_GAMMA_LINEAR_BYPASS(C_GAMMA_LINEAR_BYPASS)
	)gamma_lut_10to8_Inst_blue_center_right(
		.i_clk(i_clk),
		.i_rstn(i_rstn),
		.i_index(reg_ccm_level_blue_center_right),
		.o_value(data_gamma_blue_center_right)
	);

	//blue 通道 right 像素伽马查表实例
	gamma_lut_10to8
	#(
		.C_GAMMA_LINEAR_BYPASS(C_GAMMA_LINEAR_BYPASS)
	)gamma_lut_10to8_Inst_blue_right(
		.i_clk(i_clk),
		.i_rstn(i_rstn),
		.i_index(reg_ccm_level_blue_right),
		.o_value(data_gamma_blue_right)
	);
endmodule
