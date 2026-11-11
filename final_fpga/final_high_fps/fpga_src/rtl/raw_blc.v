`timescale 1ns / 1ps

// 对四路 RAW10 像素执行黑电平校正
module raw_blc
#(
    parameter integer SAMPLE_BITS = 10,
    parameter integer RUNTIME_BLC_BYPASS_ENABLE = 0,
    // 黑电平配置
	parameter [SAMPLE_BITS-1:0] BLC_OFFSET_L0 = 10'd50,  // 第0路 黑电平偏移
	parameter [SAMPLE_BITS-1:0] BLC_OFFSET_L1 = 10'd50,  // 第1路 黑电平偏移
	parameter [SAMPLE_BITS-1:0] BLC_OFFSET_L2 = 10'd50,  // 第2路 黑电平偏移
	parameter [SAMPLE_BITS-1:0] BLC_OFFSET_L3 = 10'd50  // 第3路 黑电平偏移
)
(
    // 时钟与复位
	input  wire         clk,  // 同步时钟
	input  wire         rst_n,  // 同步低有效复位
    // The caller freezes this with the actual source SOF. Legacy mode ignores it.
    input wire cfg_bypass,
    // 输入数据流
	input  wire [4*SAMPLE_BITS-1:0]  s_tdata,  // 4xRAW10，lane0 在最低 10bit / 4xRAW10, lane0 at lowest 10 bits
	input  wire         s_tvalid,  // 从端数据有效
	output wire         s_tready,  // 从端可接收
	input  wire         s_tuser,  // 帧首拍标记
	input  wire         s_tlast,  // 行末拍标记
    // 输出数据流
	output wire [4*SAMPLE_BITS-1:0]  m_tdata,  // 校正后 4xRAW10
	output wire         m_tvalid,  // 主端数据有效
	input  wire         m_tready,  // 主端可接收
	output wire         m_tuser,  // 帧首拍标记
	output wire         m_tlast  // 行末拍标记
);

  // 其他信号连线
	wire                load_fire;              // 新输入装入输出槽
	wire                out_fire;               // 输出槽被下游接收
	wire [SAMPLE_BITS-1:0]          sub_l0;                 // 第0路 原始差值
	wire [SAMPLE_BITS-1:0]          sub_l1;                 // 第1路 原始差值
	wire [SAMPLE_BITS-1:0]          sub_l2;                 // 第2路 原始差值
	wire [SAMPLE_BITS-1:0]          sub_l3;                 // 第3路 原始差值
	wire                cmp_l0;                 // 第0路 大于偏移
	wire                cmp_l1;                 // 第1路 大于偏移
	wire                cmp_l2;                 // 第2路 大于偏移
	wire                cmp_l3;                 // 第3路 大于偏移
	wire [SAMPLE_BITS-1:0]          blc_l0;                 // 第0路 饱和结果
	wire [SAMPLE_BITS-1:0]          blc_l1;                 // 第1路 饱和结果
	wire [SAMPLE_BITS-1:0]          blc_l2;                 // 第2路 饱和结果
	wire [SAMPLE_BITS-1:0]          blc_l3;                 // 第3路 饱和结果
	wire [4*SAMPLE_BITS-1:0]         blc_data;               // 四 lane 饱和结果拼装

  // 寄存器信号
	reg  [4*SAMPLE_BITS-1:0]         m_tdata_o;              // 输出数据寄存器
	reg                 m_tvalid_r;             // 输出有效寄存器
	reg                 m_tuser_r;              // 输出帧首拍寄存器
	reg                 m_tlast_r;              // 输出行末拍寄存器

  // 主要任务处理区域
  // 每路像素独立做饱和减法，输入高于偏移时相减，否则输出零
	assign sub_l0 = s_tdata[0 +: SAMPLE_BITS] - BLC_OFFSET_L0;
	assign sub_l1 = s_tdata[1*SAMPLE_BITS +: SAMPLE_BITS] - BLC_OFFSET_L1;
	assign sub_l2 = s_tdata[2*SAMPLE_BITS +: SAMPLE_BITS] - BLC_OFFSET_L2;
	assign sub_l3 = s_tdata[3*SAMPLE_BITS +: SAMPLE_BITS] - BLC_OFFSET_L3;
	assign cmp_l0 = s_tdata[0 +: SAMPLE_BITS] > BLC_OFFSET_L0;
	assign cmp_l1 = s_tdata[1*SAMPLE_BITS +: SAMPLE_BITS] > BLC_OFFSET_L1;
	assign cmp_l2 = s_tdata[2*SAMPLE_BITS +: SAMPLE_BITS] > BLC_OFFSET_L2;
	assign cmp_l3 = s_tdata[3*SAMPLE_BITS +: SAMPLE_BITS] > BLC_OFFSET_L3;
    wire bypass = RUNTIME_BLC_BYPASS_ENABLE != 0 && cfg_bypass;
	assign blc_l0 = bypass ? s_tdata[0 +: SAMPLE_BITS] : (cmp_l0 ? sub_l0 : 10'd0);
	assign blc_l1 = bypass ? s_tdata[SAMPLE_BITS +: SAMPLE_BITS] : (cmp_l1 ? sub_l1 : 10'd0);
	assign blc_l2 = bypass ? s_tdata[2*SAMPLE_BITS +: SAMPLE_BITS] : (cmp_l2 ? sub_l2 : 10'd0);
	assign blc_l3 = bypass ? s_tdata[3*SAMPLE_BITS +: SAMPLE_BITS] : (cmp_l3 ? sub_l3 : 10'd0);
	assign blc_data = {blc_l3, blc_l2, blc_l1, blc_l0};

  // 单拍弹性输出槽在空闲或下游接收时接受新输入
  // 已发送的拍必须清除有效位，否则输入停顿时会重复发送并打乱帧首标记
	assign out_fire = m_tvalid_r & m_tready;
	assign load_fire = s_tvalid & s_tready;
	assign s_tready = (~m_tvalid_r) | m_tready;

	// 在接收握手时流水传递有效位和帧行标记
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

  // 输出信号处理区域
	// 锁存完成黑电平校正的四路像素
	always@(posedge clk)begin
		if(load_fire)begin
			m_tdata_o <= blc_data;
		end
	end

  // 输出信号连线
	assign m_tdata = m_tdata_o;
	assign m_tvalid = m_tvalid_r;
	assign m_tuser = m_tuser_r;
	assign m_tlast = m_tlast_r;

endmodule
