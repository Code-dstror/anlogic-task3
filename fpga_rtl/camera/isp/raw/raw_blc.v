`timescale 1ns / 1ps

////////////////////////////////////English///////////////////////////////////////
// Company:         AnLu ISP Optimized
// Engineer:        RAW front-end agent
//
// Create Date:     2026/02/14 12:00:00
// Design Name:     raw_blc
// Module Name:     raw_blc
// Description:     description/raw_blc_Design.pdf
// Simulations:     isp_optimized/sim/raw/tb_raw_isp_top.v
//
// Referrences:     isp_optimized/docs/raw_design.md
//
// Dependencies:    None
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
// 设计名称:        raw_blc
// 模块名称:        raw_blc
// 模块说明:        Description/raw_blc_Design.pdf
// 仿真工程:        isp_optimized/sim/raw/tb_raw_isp_top.v
//
// 参考资料:        isp_optimized/docs/raw_design.md
//
// 依赖文件:        None
//
// 当前版本:        V1.0
// 修订日期:        2026年2月14日
// 修订历史:
// 时间             版本        修订人            修订内容
// 2026年2月14日    V1.0        RAW agent         创建文件

// 黑电平校正：逐 lane 饱和减法，保留 10bit 精度，一拍延迟。
// Black level correction: per-lane saturating subtract, 10bit precision kept, one cycle latency.
module raw_blc
#(
	parameter [9:0] BLC_OFFSET_L0 = 10'd50,   // lane0 黑电平偏移 / lane0 black level offset
	parameter [9:0] BLC_OFFSET_L1 = 10'd50,   // lane1 黑电平偏移 / lane1 black level offset
	parameter [9:0] BLC_OFFSET_L2 = 10'd50,   // lane2 黑电平偏移 / lane2 black level offset
	parameter [9:0] BLC_OFFSET_L3 = 10'd50    // lane3 黑电平偏移 / lane3 black level offset
)
(
	//-----------------全局信号-----------------//
	input  wire         clk,                    // 同步时钟 / synchronous clock
	input  wire         rst_n,                  // 同步低有效复位 / synchronous active low reset

	//-----------------从端接口-----------------//
	input  wire [39:0]  s_tdata,                // 4xRAW10，lane0 在最低 10bit / 4xRAW10, lane0 at lowest 10 bits
	input  wire         s_tvalid,               // 从端数据有效 / slave data valid
	output wire         s_tready,               // 从端可接收 / slave ready
	input  wire         s_tuser,                // 帧首拍标记 / frame first beat marker
	input  wire         s_tlast,                // 行末拍标记 / line last beat marker

	//-----------------主端接口-----------------//
	output wire [39:0]  m_tdata,                // 校正后 4xRAW10 / corrected 4xRAW10
	output wire         m_tvalid,               // 主端数据有效 / master data valid
	input  wire         m_tready,               // 主端可接收 / master ready
	output wire         m_tuser,                // 帧首拍标记 / frame first beat marker
	output wire         m_tlast                 // 行末拍标记 / line last beat marker
);

	//---------------其他信号连线---------------//
	wire                load_fire;              // 新输入装入输出槽 / a new input loads the output slot
	wire                out_fire;               // 输出槽被下游接收 / the output slot is consumed
	wire [9:0]          sub_l0;                 // lane0 原始差值 / lane0 raw difference
	wire [9:0]          sub_l1;                 // lane1 原始差值 / lane1 raw difference
	wire [9:0]          sub_l2;                 // lane2 原始差值 / lane2 raw difference
	wire [9:0]          sub_l3;                 // lane3 原始差值 / lane3 raw difference
	wire                cmp_l0;                 // lane0 大于偏移 / lane0 above offset
	wire                cmp_l1;                 // lane1 大于偏移 / lane1 above offset
	wire                cmp_l2;                 // lane2 大于偏移 / lane2 above offset
	wire                cmp_l3;                 // lane3 大于偏移 / lane3 above offset
	wire [9:0]          blc_l0;                 // lane0 饱和结果 / lane0 saturated result
	wire [9:0]          blc_l1;                 // lane1 饱和结果 / lane1 saturated result
	wire [9:0]          blc_l2;                 // lane2 饱和结果 / lane2 saturated result
	wire [9:0]          blc_l3;                 // lane3 饱和结果 / lane3 saturated result
	wire [39:0]         blc_data;               // 四 lane 饱和结果拼装 / assembled four lane result

	//---------------寄存器信号---------------//
	reg  [39:0]         m_tdata_o;              // 输出数据寄存器 / output data register
	reg                 m_tvalid_r;             // 输出有效寄存器 / output valid register
	reg                 m_tuser_r;              // 输出帧首拍寄存器 / output frame start register
	reg                 m_tlast_r;              // 输出行末拍寄存器 / output line last register

	//--------------主要任务处理区域--------------//
	// 逐 lane 饱和减法：输入大于偏移时相减，否则饱和到 0。
	// Per-lane saturating subtract: subtract when above offset, otherwise saturate to zero.
	assign sub_l0 = s_tdata[9:0] - BLC_OFFSET_L0;
	assign sub_l1 = s_tdata[19:10] - BLC_OFFSET_L1;
	assign sub_l2 = s_tdata[29:20] - BLC_OFFSET_L2;
	assign sub_l3 = s_tdata[39:30] - BLC_OFFSET_L3;
	assign cmp_l0 = s_tdata[9:0] > BLC_OFFSET_L0;
	assign cmp_l1 = s_tdata[19:10] > BLC_OFFSET_L1;
	assign cmp_l2 = s_tdata[29:20] > BLC_OFFSET_L2;
	assign cmp_l3 = s_tdata[39:30] > BLC_OFFSET_L3;
	assign blc_l0 = cmp_l0 ? sub_l0 : 10'd0;
	assign blc_l1 = cmp_l1 ? sub_l1 : 10'd0;
	assign blc_l2 = cmp_l2 ? sub_l2 : 10'd0;
	assign blc_l3 = cmp_l3 ? sub_l3 : 10'd0;
	assign blc_data = {blc_l3, blc_l2, blc_l1, blc_l0};

	// 单深度弹性输出槽：槽空或下游接收即可接收输入；被接收的拍必须清 valid，
	// 否则下一拍输入停顿时会重复发送同一拍（会打乱行首标记）。
	// Single depth elastic output slot: accept whenever the slot is empty or consumed, and clear the
	// valid bit once the held beat is consumed, otherwise a stalled input would resend the same beat
	// and corrupt the frame start marker.
	assign out_fire = m_tvalid_r & m_tready;
	assign load_fire = s_tvalid & s_tready;
	assign s_tready = (~m_tvalid_r) | m_tready;

	always@(posedge clk)begin
		if(!rst_n)begin
			m_tvalid_r <= 1'b0;
			m_tuser_r <= 1'b0;
			m_tlast_r <= 1'b0;
		end
		else if(load_fire)begin
			m_tvalid_r <= 1'b1;
			m_tuser_r <= s_tuser;
			m_tlast_r <= s_tlast;
		end
		else if(out_fire)begin
			m_tvalid_r <= 1'b0;
			m_tuser_r <= 1'b0;
			m_tlast_r <= 1'b0;
		end
	end

	//---------------输出信号处理区域---------------//
	always@(posedge clk)begin
		if(load_fire)begin
			m_tdata_o <= blc_data;
		end
	end

	//---------------输出信号连线---------------//
	assign m_tdata = m_tdata_o;
	assign m_tvalid = m_tvalid_r;
	assign m_tuser = m_tuser_r;
	assign m_tlast = m_tlast_r;

endmodule
