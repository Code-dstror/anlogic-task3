`timescale 1ns / 1ps

////////////////////////////////////English///////////////////////////////////////
// Company:         AnLu ISP Optimized
// Engineer:        RAW front-end agent
//
// Create Date:     2026/02/14 12:00:00
// Design Name:     raw_demosaic
// Module Name:     raw_demosaic
// Description:     description/raw_demosaic_Design.pdf
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
// 设计名称:        raw_demosaic
// 模块名称:        raw_demosaic
// 模块说明:        Description/raw_demosaic_Design.pdf
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

// 去马赛克：3x3 窗口、圆整双线性或边缘导向 G，保留 10bit 精度，输出 4xRGB101010。
// 所有加法中间量按位宽扩展（两值 11bit、四值 12bit、梯度 12bit），仅输出裁回 10bit。
// Demosaic: 3x3 window, rounded bilinear or edge-directed green, 10bit precision kept,
// output 4xRGB101010. Every adder intermediate is widened (2 values 11bit, 4 values 12bit,
// gradient 12bit); only the output is narrowed back to 10bit.
module raw_demosaic
(
	//-----------------全局信号-----------------//
	input  wire         clk,                    // 同步时钟 / synchronous clock
	input  wire         rst_n,                  // 同步低有效复位 / synchronous active low reset

	//-----------------配置信号-----------------//
	input  wire [1:0]   cfg_bayer_phase,        // Bayer 相位，帧首锁存 / Bayer phase latched at frame start
	input  wire         cfg_edge_g,             // G 插值模式，0=圆整双线性 1=边缘导向 / green mode

	//-----------------从端窗口接口-----------------//
	input  wire [179:0] s_window,               // 3 行 x 6 列 x 10bit 窗 / 3 row x 6 col x 10bit window
	input  wire         s_valid,                // 窗口有效 / window valid
	output wire         s_ready,                // 可接收新窗 / can accept a new window
	input  wire         s_sof,                  // 输出帧首拍标记 / output frame first beat marker
	input  wire         s_last,                 // 输出行末拍标记 / output line last beat marker
	input  wire         s_row_parity,           // 输出行行号奇偶 / output row index parity

	//-----------------主端接口-----------------//
	output wire [119:0] m_tdata,                // 4xRGB101010 / four pixels RGB101010
	output wire         m_tvalid,               // 主端数据有效 / master data valid
	input  wire         m_tready,               // 主端可接收 / master ready
	output wire         m_tuser,                // 输出帧首拍 / output frame first beat
	output wire         m_tlast,                // 输出行末拍 / output line last beat
	output wire         m_busy                  // 内部仍有在途数据 / internal data still in flight
);

	//---------------配置参数区域---------------//
	localparam [1:0]    COL_R = 2'd0;           // 红色编码 / red color code
	localparam [1:0]    COL_G = 2'd1;           // 绿色编码 / green color code
	localparam [1:0]    COL_B = 2'd2;           // 蓝色编码 / blue color code

	//-----------------标志信号-----------------//
	wire                win_fire;               // 窗口握手成功 / window handshake fires
	wire                pipe_en;                // 流水线推进使能 / pipeline advance enable
	wire                stage_v1;               // 第 1 级有效 / stage 1 valid
	wire                stage_v2;               // 第 2 级有效 / stage 2 valid
	wire                stage_v3;               // 第 3 级有效 / stage 3 valid
	wire                stage_v4;               // 第 4 级有效 / stage 4 valid
	wire                stage_v5;               // 第 5 级有效 / stage 5 valid

	//---------------寄存器信号---------------//
	reg                 v1_r;                   // 第 1 级有效寄存器 / stage 1 valid register
	reg                 v2_r;                   // 第 2 级有效寄存器 / stage 2 valid register
	reg                 v3_r;                   // 第 3 级有效寄存器 / stage 3 valid register
	reg                 v4_r;                   // 第 4 级有效寄存器 / stage 4 valid register
	reg                 v5_r;                   // 第 5 级有效寄存器 / stage 5 valid register
	reg                 p1_r;                   // 第 1 级行奇偶 / stage 1 row parity
	reg                 p2_r;                   // 第 2 级行奇偶 / stage 2 row parity
	reg                 p3_r;                   // 第 3 级行奇偶 / stage 3 row parity
	reg                 sof1_r;                 // 第 1 级帧首标记 / stage 1 frame start flag
	reg                 sof2_r;                 // 第 2 级帧首标记 / stage 2 frame start flag
	reg                 sof3_r;                 // 第 3 级帧首标记 / stage 3 frame start flag
	reg                 sof4_r;                 // 第 4 级帧首标记 / stage 4 frame start flag
	reg                 sof5_r;                 // 第 5 级帧首标记 / stage 5 frame start flag
	reg                 last1_r;                // 第 1 级行末标记 / stage 1 line last flag
	reg                 last2_r;                // 第 2 级行末标记 / stage 2 line last flag
	reg                 last3_r;                // 第 3 级行末标记 / stage 3 line last flag
	reg                 last4_r;                // 第 4 级行末标记 / stage 4 line last flag
	reg                 last5_r;                // 第 5 级行末标记 / stage 5 line last flag
	reg [1:0]           ph00_r;                 // 相位 (偶行偶列) / phase color at even row even col
	reg [1:0]           ph01_r;                 // 相位 (偶行奇列) / phase color at even row odd col
	reg [1:0]           ph10_r;                 // 相位 (奇行偶列) / phase color at odd row even col
	reg [1:0]           ph11_r;                 // 相位 (奇行奇列) / phase color at odd row odd col
	reg                 edge_r;                 // 边缘导向模式锁存 / latched edge directed mode
	reg [119:0]         m_tdata_r;              // 输出数据寄存器 / output data register

	//---------------输出信号连线---------------//
	wire [119:0]        pack_data;              // 四 lane 打包数据 / packed four lane data

	//--------------主要任务处理区域--------------//
	// 相位颜色查表：00=RGGB 01=BGGR 10=GRBG 11=GBRG。
	// Phase color decode: 00=RGGB 01=BGGR 10=GRBG 11=GBRG.
	wire [1:0]          dec_ph00 = (cfg_bayer_phase == 2'd0) ? COL_R : ((cfg_bayer_phase == 2'd1) ? COL_B : COL_G);
	wire [1:0]          dec_ph01 = (cfg_bayer_phase == 2'd2) ? COL_R : ((cfg_bayer_phase == 2'd3) ? COL_B : COL_G);
	wire [1:0]          dec_ph10 = (cfg_bayer_phase == 2'd2) ? COL_B : ((cfg_bayer_phase == 2'd3) ? COL_R : COL_G);
	wire [1:0]          dec_ph11 = (cfg_bayer_phase == 2'd0) ? COL_B : ((cfg_bayer_phase == 2'd1) ? COL_R : COL_G);

	// 流水线在手标志与推进条件：末级空槽或下游接收即可推进，产生 valid 不等待 ready。
	// Pipeline occupancy and advance: advance when the last stage is empty or the consumer accepts,
	// so valid generation never waits for ready.
	assign stage_v1 = v1_r;
	assign stage_v2 = v2_r;
	assign stage_v3 = v3_r;
	assign stage_v4 = v4_r;
	assign stage_v5 = v5_r;
	assign pipe_en = (~v5_r) | m_tready;
	assign win_fire = s_valid & s_ready;
	assign s_ready = pipe_en;
	assign m_busy = v1_r | v2_r | v3_r | v4_r | v5_r;

	// 相位与模式只在输出帧首拍锁存，保证上一帧在途数据仍用旧相位。
	// Phase and mode are latched at the output frame start so in-flight beats keep the old phase.
	always@(posedge clk)begin
		if(!rst_n)begin
			ph00_r <= COL_R;
			ph01_r <= COL_G;
			ph10_r <= COL_G;
			ph11_r <= COL_B;
			edge_r <= 1'b0;
		end
		else if(win_fire & s_sof)begin
			ph00_r <= dec_ph00;
			ph01_r <= dec_ph01;
			ph10_r <= dec_ph10;
			ph11_r <= dec_ph11;
			edge_r <= cfg_edge_g;
		end
	end

	// 有效与标记流水：与数据同步推进，气泡不改变计数语义。
	// Valid and marker pipeline: advances with data, bubbles never change counting semantics.
	always@(posedge clk)begin
		if(!rst_n)begin
			v1_r <= 1'b0;
			v2_r <= 1'b0;
			v3_r <= 1'b0;
			v4_r <= 1'b0;
			v5_r <= 1'b0;
			p1_r <= 1'b0;
			p2_r <= 1'b0;
			p3_r <= 1'b0;
			sof1_r <= 1'b0;
			sof2_r <= 1'b0;
			sof3_r <= 1'b0;
			sof4_r <= 1'b0;
			sof5_r <= 1'b0;
			last1_r <= 1'b0;
			last2_r <= 1'b0;
			last3_r <= 1'b0;
			last4_r <= 1'b0;
			last5_r <= 1'b0;
		end
		else if(pipe_en)begin
			v1_r <= s_valid;
			v2_r <= v1_r;
			v3_r <= v2_r;
			v4_r <= v3_r;
			v5_r <= v4_r;
			p1_r <= s_row_parity;
			p2_r <= p1_r;
			p3_r <= p2_r;
			sof1_r <= s_sof;
			sof2_r <= sof1_r;
			sof3_r <= sof2_r;
			sof4_r <= sof3_r;
			sof5_r <= sof4_r;
			last1_r <= s_last;
			last2_r <= last1_r;
			last3_r <= last2_r;
			last4_r <= last3_r;
			last5_r <= last4_r;
			m_tdata_r <= pack_data;
		end
	end

	//--------------生成块区域--------------//
	// 四个 lane 各自独立完成 3x3 重建，列索引 l / l+1 / l+2 对应左右邻与中心。
	// Each of the four lanes reconstructs its own 3x3 neighbourhood; window columns l / l+1 / l+2
	// map to left neighbour, centre and right neighbour.
	genvar g_l;
	generate
		for(g_l = 0; g_l < 4; g_l = g_l + 1)begin : GEN_LANE

			// 第 1 级：两两和与绝对差，和扩展到 11bit，差保持 10bit。
			// Stage 1: pair sums widened to 11bit and absolute differences kept at 10bit.
			wire [9:0]  w_nw = s_window[120 + g_l * 10 +: 10];   // 左上邻 / north west neighbour
			wire [9:0]  w_n  = s_window[130 + g_l * 10 +: 10];   // 上邻 / north neighbour
			wire [9:0]  w_ne = s_window[140 + g_l * 10 +: 10];   // 右上邻 / north east neighbour
			wire [9:0]  w_w  = s_window[60 + g_l * 10 +: 10];    // 左邻 / west neighbour
			wire [9:0]  w_c  = s_window[70 + g_l * 10 +: 10];    // 中心 / centre pixel
			wire [9:0]  w_e  = s_window[80 + g_l * 10 +: 10];    // 右邻 / east neighbour
			wire [9:0]  w_sw = s_window[g_l * 10 +: 10];         // 左下邻 / south west neighbour
			wire [9:0]  w_s  = s_window[10 + g_l * 10 +: 10];    // 下邻 / south neighbour
			wire [9:0]  w_se = s_window[20 + g_l * 10 +: 10];    // 右下邻 / south east neighbour
			wire [10:0] d1_sum_ns = w_n + w_s;                   // 上下两值之和 / north plus south
			wire [10:0] d1_sum_we = w_w + w_e;                   // 左右两值之和 / west plus east
			wire [10:0] d1_sum_d1 = w_nw + w_se;                 // 主对角之和 / main diagonal sum
			wire [10:0] d1_sum_d2 = w_ne + w_sw;                 // 副对角之和 / anti diagonal sum
			wire [9:0]  d1_dif_we = (w_w > w_e) ? (w_w - w_e) : (w_e - w_w);   // 左右差 / west east difference
			wire [9:0]  d1_dif_ns = (w_n > w_s) ? (w_n - w_s) : (w_s - w_n);   // 上下差 / north south difference
			wire [9:0]  d1_dif_nw = (w_nw > w_ne) ? (w_nw - w_ne) : (w_ne - w_nw);   // 上排差 / top row difference
			wire [9:0]  d1_dif_sw = (w_sw > w_se) ? (w_sw - w_se) : (w_se - w_sw);   // 下排差 / bottom row difference
			wire [9:0]  d1_dif_wn = (w_nw > w_sw) ? (w_nw - w_sw) : (w_sw - w_nw);   // 左列差 / left column difference
			wire [9:0]  d1_dif_en = (w_ne > w_se) ? (w_ne - w_se) : (w_se - w_ne);   // 右列差 / right column difference
			reg  [10:0] r1_sum_ns;                               // 第 1 级上下和 / stage 1 north south sum
			reg  [10:0] r1_sum_we;                               // 第 1 级左右和 / stage 1 west east sum
			reg  [10:0] r1_sum_d1;                               // 第 1 级主对角和 / stage 1 main diagonal sum
			reg  [10:0] r1_sum_d2;                               // 第 1 级副对角和 / stage 1 anti diagonal sum
			reg  [9:0]  r1_dif_we;                               // 第 1 级左右差 / stage 1 west east difference
			reg  [9:0]  r1_dif_ns;                               // 第 1 级上下差 / stage 1 north south difference
			reg  [9:0]  r1_dif_nw;                               // 第 1 级上排差 / stage 1 top row difference
			reg  [9:0]  r1_dif_sw;                               // 第 1 级下排差 / stage 1 bottom row difference
			reg  [9:0]  r1_dif_wn;                               // 第 1 级左列差 / stage 1 left column difference
			reg  [9:0]  r1_dif_en;                               // 第 1 级右列差 / stage 1 right column difference
			reg  [9:0]  r1_w;                                    // 第 1 级左邻 / stage 1 west neighbour
			reg  [9:0]  r1_e;                                    // 第 1 级右邻 / stage 1 east neighbour
			reg  [9:0]  r1_n;                                    // 第 1 级上邻 / stage 1 north neighbour
			reg  [9:0]  r1_s;                                    // 第 1 级下邻 / stage 1 south neighbour
			reg  [9:0]  r1_ctr;                                  // 第 1 级中心 / stage 1 centre pixel

			// 第 2 级：四值和扩展到 12bit，梯度三项两两相加，两抽平均和扩展到 11bit。
			// Stage 2: four-value sums widened to 12bit, gradient terms added pairwise,
			// two-tap averages widened to 11bit.
			wire [11:0] d2_cross = r1_sum_ns + r1_sum_we;        // 十字四值之和 / cross four value sum
			wire [11:0] d2_diag = r1_sum_d1 + r1_sum_d2;         // 对角四值之和 / diagonal four value sum
			wire [11:0] d2_gh_a = r1_dif_we + r1_dif_nw;         // 水平梯度前两项 / partial horizontal gradient
			wire [11:0] d2_gv_a = r1_dif_ns + r1_dif_wn;         // 垂直梯度前两项 / partial vertical gradient
			wire [11:0] d2_grad_h = d2_gh_a + r1_dif_sw;         // 水平梯度三项 / horizontal gradient sum
			wire [11:0] d2_grad_v = d2_gv_a + r1_dif_en;         // 垂直梯度三项 / vertical gradient sum
			wire [10:0] d2_sum_we = r1_w + r1_e;                 // 左右两抽和 / west east two tap sum
			wire [10:0] d2_sum_ns = r1_n + r1_s;                 // 上下两抽和 / north south two tap sum
			reg  [11:0] r2_cross;                                // 第 2 级十字和 / stage 2 cross sum
			reg  [11:0] r2_diag;                                 // 第 2 级对角和 / stage 2 diagonal sum
			reg  [11:0] r2_grad_h;                               // 第 2 级水平梯度 / stage 2 horizontal gradient
			reg  [11:0] r2_grad_v;                               // 第 2 级垂直梯度 / stage 2 vertical gradient
			reg  [10:0] r2_sum_we;                               // 第 2 级左右和 / stage 2 west east sum
			reg  [10:0] r2_sum_ns;                               // 第 2 级上下和 / stage 2 north south sum
			reg  [9:0]  r2_ctr;                                  // 第 2 级中心 / stage 2 centre pixel

			// 第 3 级：圆整平均、方向判决与颜色译码。
			// Stage 3: rounded averages, direction decision and colour decode.
			wire [9:0]  d3_g_we = (r2_sum_we + 11'd1) >> 1;      // 左右两抽平均 / west east average
			wire [9:0]  d3_g_ns = (r2_sum_ns + 11'd1) >> 1;      // 上下两抽平均 / north south average
			wire [9:0]  d3_g_flat = (r2_cross + 12'd2) >> 2;     // 圆整四抽平均 / rounded cross average
			wire [9:0]  d3_c_avg = (r2_diag + 12'd2) >> 2;       // 圆整对角平均 / rounded diagonal average
			wire        d3_dir_h = (r2_grad_h < r2_grad_v);      // 水平方向更平坦 / horizontal is flatter
			wire [9:0]  d3_g_edge = d3_dir_h ? d3_g_we : d3_g_ns;   // 边缘导向绿 / edge directed green
			wire [9:0]  d3_g_sel = edge_r ? d3_g_edge : d3_g_flat;  // 选定绿 / selected green
			wire [1:0]  d3_cen_col = g_l[0] ? (p3_r ? ph11_r : ph01_r) : (p3_r ? ph10_r : ph00_r);   // 中心色 / centre colour
			wire [1:0]  d3_hor_col = g_l[0] ? (p3_r ? ph10_r : ph00_r) : (p3_r ? ph11_r : ph01_r);   // 水平邻色 / horizontal colour
			wire        d3_is_r = (d3_cen_col == COL_R);         // 中心为红 / centre is red
			wire        d3_is_g = (d3_cen_col == COL_G);         // 中心为绿 / centre is green
			wire        d3_is_b = (d3_cen_col == COL_B);         // 中心为蓝 / centre is blue
			wire        d3_hor_r = (d3_hor_col == COL_R);        // 水平邻为红 / horizontal neighbour is red
			reg  [9:0]  r3_g_we;                                 // 第 3 级左右平均 / stage 3 west east average
			reg  [9:0]  r3_g_ns;                                 // 第 3 级上下平均 / stage 3 north south average
			reg  [9:0]  r3_g_sel;                                // 第 3 级选定绿 / stage 3 selected green
			reg  [9:0]  r3_c_avg;                                // 第 3 级对角平均 / stage 3 diagonal average
			reg  [9:0]  r3_ctr;                                  // 第 3 级中心 / stage 3 centre pixel
			reg         r3_is_r;                                 // 第 3 级中心为红 / stage 3 centre is red
			reg         r3_is_g;                                 // 第 3 级中心为绿 / stage 3 centre is green
			reg         r3_is_b;                                 // 第 3 级中心为蓝 / stage 3 centre is blue
			reg         r3_hor_r;                                // 第 3 级水平邻为红 / stage 3 horizontal is red

			// 第 4 级：按中心色分配三通道，本位色始终透传原始 RAW10。
			// Stage 4: assign the three channels according to the centre colour; the native colour
			// always passes the original RAW10 sample through.
			wire [9:0]  d4_r = r3_is_r ? r3_ctr : (r3_is_b ? r3_c_avg : (r3_hor_r ? r3_g_we : r3_g_ns));   // 红通道 / red channel
			wire [9:0]  d4_g = r3_is_g ? r3_ctr : r3_g_sel;      // 绿通道 / green channel
			wire [9:0]  d4_b = r3_is_b ? r3_ctr : (r3_is_r ? r3_c_avg : (r3_hor_r ? r3_g_ns : r3_g_we));   // 蓝通道 / blue channel
			reg  [9:0]  r4_r_ch;                                 // 第 4 级红通道 / stage 4 red channel
			reg  [9:0]  r4_g_ch;                                 // 第 4 级绿通道 / stage 4 green channel
			reg  [9:0]  r4_b_ch;                                 // 第 4 级蓝通道 / stage 4 blue channel

			// 数据流水寄存器：所有级共用 pipe_en，气泡随数据同步流动。
			// Data pipeline registers: all stages share pipe_en so bubbles travel with the data.
			always@(posedge clk)begin
				if(pipe_en)begin
					r1_sum_ns <= d1_sum_ns;
					r1_sum_we <= d1_sum_we;
					r1_sum_d1 <= d1_sum_d1;
					r1_sum_d2 <= d1_sum_d2;
					r1_dif_we <= d1_dif_we;
					r1_dif_ns <= d1_dif_ns;
					r1_dif_nw <= d1_dif_nw;
					r1_dif_sw <= d1_dif_sw;
					r1_dif_wn <= d1_dif_wn;
					r1_dif_en <= d1_dif_en;
					r1_w <= w_w;
					r1_e <= w_e;
					r1_n <= w_n;
					r1_s <= w_s;
					r1_ctr <= w_c;
					r2_cross <= d2_cross;
					r2_diag <= d2_diag;
					r2_grad_h <= d2_grad_h;
					r2_grad_v <= d2_grad_v;
					r2_sum_we <= d2_sum_we;
					r2_sum_ns <= d2_sum_ns;
					r2_ctr <= r1_ctr;
					r3_g_we <= d3_g_we;
					r3_g_ns <= d3_g_ns;
					r3_g_sel <= d3_g_sel;
					r3_c_avg <= d3_c_avg;
					r3_ctr <= r2_ctr;
					r3_is_r <= d3_is_r;
					r3_is_g <= d3_is_g;
					r3_is_b <= d3_is_b;
					r3_hor_r <= d3_hor_r;
					r4_r_ch <= d4_r;
					r4_g_ch <= d4_g;
					r4_b_ch <= d4_b;
				end
			end

			// 第 5 级：拼装 30bit lane，R 在高位、B 在低位。
			// Stage 5: assemble the 30bit lane, red in the high bits and blue in the low bits.
			assign pack_data[g_l * 30 +: 30] = {r4_r_ch, r4_g_ch, r4_b_ch};
		end
	endgenerate

	//---------------输出信号连线---------------//
	assign m_tdata = m_tdata_r;
	assign m_tvalid = stage_v5;
	assign m_tuser = sof5_r;
	assign m_tlast = last5_r;

endmodule
