`timescale 1ns / 1ps

// Stage3 exact reuse: first-stage pair sums carry the rounding bias.
// Pair(a,b)=a+b+1; Quad=Pair(a,b)+Pair(c,d), so later averages only shift.
// Same five stages, four lanes, configuration and global CE as frozen source.
module raw_demosaic #(parameter integer SAMPLE_BITS = 10)
(
    // 时钟与复位
	input  wire         clk,  // 同步时钟
	input  wire         rst_n,  // 同步低有效复位
    // 运行配置
	input  wire [1:0]   cfg_bayer_phase,  // Bayer 相位，帧首锁存
	input  wire         cfg_edge_g,  // G 插值模式，0=圆整双线性 1=边缘导向
    // 输入数据流
	input  wire [18*SAMPLE_BITS-1:0] s_window,  // 三行六列、每像素十位的邻域窗口
	input  wire         s_valid,  // 窗口有效
	output wire         s_ready,  // 可接收新窗
	input  wire         s_sof,  // 输出帧首拍标记
	input  wire         s_last,  // 输出行末拍标记
	input  wire         s_row_parity,  // 输出行行号奇偶
    // 输出数据流
	output wire [12*SAMPLE_BITS-1:0] m_tdata,  // 每拍四个 RGB101010 像素
	output wire         m_tvalid,  // 主端数据有效
	input  wire         m_tready,  // 主端可接收
	output wire         m_tuser,  // 输出帧首拍
	output wire         m_tlast,  // 输出行末拍

    // 流水线占用状态
	output wire         m_busy  // 内部仍有在途数据
);

  // 配置参数区域
	localparam [1:0]    COL_R = 2'd0;           // 红色编码
	localparam [1:0]    COL_G = 2'd1;           // 绿色编码
	localparam [1:0]    COL_B = 2'd2;           // 蓝色编码

  // 标志信号
	wire                win_fire;               // 窗口握手成功
	wire                pipe_en;                // 流水线推进使能
	wire                stage_v1;               // 第 1 级有效
	wire                stage_v2;               // 第 2 级有效
	wire                stage_v3;               // 第 3 级有效
	wire                stage_v4;               // 第 4 级有效
	wire                stage_v5;               // 第 5 级有效

  // 寄存器信号
	reg                 v1_r;                   // 第 1 级有效寄存器
	reg                 v2_r;                   // 第 2 级有效寄存器
	reg                 v3_r;                   // 第 3 级有效寄存器
	reg                 v4_r;                   // 第 4 级有效寄存器
	reg                 v5_r;                   // 第 5 级有效寄存器
	reg                 p1_r;                   // 第 1 级行奇偶
	reg                 p2_r;                   // 第 2 级行奇偶
	reg                 p3_r;                   // 第 3 级行奇偶
	reg                 sof1_r;                 // 第 1 级帧首标记
	reg                 sof2_r;                 // 第 2 级帧首标记
	reg                 sof3_r;                 // 第 3 级帧首标记
	reg                 sof4_r;                 // 第 4 级帧首标记
	reg                 sof5_r;                 // 第 5 级帧首标记
	reg                 last1_r;                // 第 1 级行末标记
	reg                 last2_r;                // 第 2 级行末标记
	reg                 last3_r;                // 第 3 级行末标记
	reg                 last4_r;                // 第 4 级行末标记
	reg                 last5_r;                // 第 5 级行末标记
	reg [1:0]           ph00_r;                 // 相位 (偶行偶列)
	reg [1:0]           ph01_r;                 // 相位 (偶行奇列)
	reg [1:0]           ph10_r;                 // 相位 (奇行偶列)
	reg [1:0]           ph11_r;                 // 相位 (奇行奇列)
	reg                 edge_r;                 // 边缘导向模式锁存
	reg [12*SAMPLE_BITS-1:0]         m_tdata_r;              // 输出数据寄存器

  // 输出信号连线
	wire [12*SAMPLE_BITS-1:0]        pack_data;              // 四 lane 打包数据

  // 主要任务处理区域
  // 相位颜色译码：00=RGGB、01=BGGR、10=GRBG、11=GBRG
	wire [1:0]          dec_ph00 = (cfg_bayer_phase == 2'd0) ? COL_R : ((cfg_bayer_phase == 2'd1) ? COL_B : COL_G);
	wire [1:0]          dec_ph01 = (cfg_bayer_phase == 2'd2) ? COL_R : ((cfg_bayer_phase == 2'd3) ? COL_B : COL_G);
	wire [1:0]          dec_ph10 = (cfg_bayer_phase == 2'd2) ? COL_B : ((cfg_bayer_phase == 2'd3) ? COL_R : COL_G);
	wire [1:0]          dec_ph11 = (cfg_bayer_phase == 2'd0) ? COL_B : ((cfg_bayer_phase == 2'd1) ? COL_R : COL_G);

  // 末级空槽或下游接收时整条流水线推进，内部有效位的生成不额外等待 ready
	assign stage_v1 = v1_r;
	assign stage_v2 = v2_r;
	assign stage_v3 = v3_r;
	assign stage_v4 = v4_r;
	assign stage_v5 = v5_r;
	assign pipe_en = (~v5_r) | m_tready;
	assign win_fire = s_valid & s_ready;
	assign s_ready = pipe_en;
	assign m_busy = v1_r | v2_r | v3_r | v4_r | v5_r;

  // 相位与插值模式仅在输出帧首拍锁存，上一帧在途数据继续使用旧设置
	// 在帧首锁存 Bayer 相位及绿色插值模式
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

  // 有效位和帧行标记随数据同步推进，流水线气泡不改变计数语义
	// 将有效位和帧行边界与像素流水线同步
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

  // 生成块区域
  // 四路像素分别做三乘三邻域重建，窗口列 l、l+1、l+2 对应左邻、中心和右邻
	genvar g_l;
	generate
		for(g_l = 0; g_l < 4; g_l = g_l + 1)begin : GEN_LANE

  // 第一级计算成对求和与绝对差，和扩展到十一位，差保持十位
			wire [SAMPLE_BITS-1:0]  w_nw = s_window[12*SAMPLE_BITS + g_l * SAMPLE_BITS +: SAMPLE_BITS];   // 左上邻
			wire [SAMPLE_BITS-1:0]  w_n  = s_window[13*SAMPLE_BITS + g_l * SAMPLE_BITS +: SAMPLE_BITS];   // 上邻
			wire [SAMPLE_BITS-1:0]  w_ne = s_window[14*SAMPLE_BITS + g_l * SAMPLE_BITS +: SAMPLE_BITS];   // 右上邻
			wire [SAMPLE_BITS-1:0]  w_w  = s_window[6*SAMPLE_BITS + g_l * SAMPLE_BITS +: SAMPLE_BITS];    // 左邻
			wire [SAMPLE_BITS-1:0]  w_c  = s_window[7*SAMPLE_BITS + g_l * SAMPLE_BITS +: SAMPLE_BITS];    // 中心
			wire [SAMPLE_BITS-1:0]  w_e  = s_window[8*SAMPLE_BITS + g_l * SAMPLE_BITS +: SAMPLE_BITS];    // 右邻
			wire [SAMPLE_BITS-1:0]  w_sw = s_window[g_l * SAMPLE_BITS +: SAMPLE_BITS];         // 左下邻
			wire [SAMPLE_BITS-1:0]  w_s  = s_window[1*SAMPLE_BITS + g_l * SAMPLE_BITS +: SAMPLE_BITS];    // 下邻
			wire [SAMPLE_BITS-1:0]  w_se = s_window[2*SAMPLE_BITS + g_l * SAMPLE_BITS +: SAMPLE_BITS];    // 右下邻
			wire [SAMPLE_BITS:0] d1_sum_ns = w_n + w_s + {{SAMPLE_BITS{1'b0}},1'b1};                   // 上下两值之和
			wire [SAMPLE_BITS:0] d1_sum_we = w_w + w_e + {{SAMPLE_BITS{1'b0}},1'b1};                   // 左右两值之和
			wire [SAMPLE_BITS:0] d1_sum_d1 = w_nw + w_se + {{SAMPLE_BITS{1'b0}},1'b1};                 // 主对角之和
			wire [SAMPLE_BITS:0] d1_sum_d2 = w_ne + w_sw + {{SAMPLE_BITS{1'b0}},1'b1};                 // 副对角之和
			wire [SAMPLE_BITS-1:0]  d1_dif_we = (w_w > w_e) ? (w_w - w_e) : (w_e - w_w);   // 左右差
			wire [SAMPLE_BITS-1:0]  d1_dif_ns = (w_n > w_s) ? (w_n - w_s) : (w_s - w_n);   // 上下差
			wire [SAMPLE_BITS-1:0]  d1_dif_nw = (w_nw > w_ne) ? (w_nw - w_ne) : (w_ne - w_nw);   // 上排差
			wire [SAMPLE_BITS-1:0]  d1_dif_sw = (w_sw > w_se) ? (w_sw - w_se) : (w_se - w_sw);   // 下排差
			wire [SAMPLE_BITS-1:0]  d1_dif_wn = (w_nw > w_sw) ? (w_nw - w_sw) : (w_sw - w_nw);   // 左列差
			wire [SAMPLE_BITS-1:0]  d1_dif_en = (w_ne > w_se) ? (w_ne - w_se) : (w_se - w_ne);   // 右列差
			reg  [SAMPLE_BITS:0] r1_sum_ns;                               // 第 1 级上下和
			reg  [SAMPLE_BITS:0] r1_sum_we;                               // 第 1 级左右和
			reg  [SAMPLE_BITS:0] r1_sum_d1;                               // 第 1 级主对角和
			reg  [SAMPLE_BITS:0] r1_sum_d2;                               // 第 1 级副对角和
			reg  [SAMPLE_BITS-1:0]  r1_dif_we;                               // 第 1 级左右差
			reg  [SAMPLE_BITS-1:0]  r1_dif_ns;                               // 第 1 级上下差
			reg  [SAMPLE_BITS-1:0]  r1_dif_nw;                               // 第 1 级上排差
			reg  [SAMPLE_BITS-1:0]  r1_dif_sw;                               // 第 1 级下排差
			reg  [SAMPLE_BITS-1:0]  r1_dif_wn;                               // 第 1 级左列差
			reg  [SAMPLE_BITS-1:0]  r1_dif_en;                               // 第 1 级右列差
			reg  [SAMPLE_BITS-1:0]  r1_ctr;                                  // 第 1 级中心

  // 第二级将四值和扩展到十二位，梯度项逐级相加，两点平均和扩展到十一位
			wire [SAMPLE_BITS+1:0] d2_cross = r1_sum_ns + r1_sum_we;        // 十字四值之和
			wire [SAMPLE_BITS+1:0] d2_diag = r1_sum_d1 + r1_sum_d2;         // 对角四值之和
			wire [SAMPLE_BITS+1:0] d2_gh_a = r1_dif_we + r1_dif_nw;         // 水平梯度前两项
			wire [SAMPLE_BITS+1:0] d2_gv_a = r1_dif_ns + r1_dif_wn;         // 垂直梯度前两项
			wire [SAMPLE_BITS+1:0] d2_grad_h = d2_gh_a + r1_dif_sw;         // 水平梯度三项
			wire [SAMPLE_BITS+1:0] d2_grad_v = d2_gv_a + r1_dif_en;         // 垂直梯度三项
			wire [SAMPLE_BITS:0] d2_sum_we = r1_sum_we;                 // 复用含圆整偏置的左右对和
			wire [SAMPLE_BITS:0] d2_sum_ns = r1_sum_ns;                 // 复用含圆整偏置的上下对和
			reg  [SAMPLE_BITS+1:0] r2_cross;                                // 第 2 级十字和
			reg  [SAMPLE_BITS+1:0] r2_diag;                                 // 第 2 级对角和
			reg  [SAMPLE_BITS+1:0] r2_grad_h;                               // 第 2 级水平梯度
			reg  [SAMPLE_BITS+1:0] r2_grad_v;                               // 第 2 级垂直梯度
			reg  [SAMPLE_BITS:0] r2_sum_we;                               // 第 2 级左右和
			reg  [SAMPLE_BITS:0] r2_sum_ns;                               // 第 2 级上下和
			reg  [SAMPLE_BITS-1:0]  r2_ctr;                                  // 第 2 级中心

  // 第三级计算圆整平均值，判定较平坦方向并译码中心颜色
			wire [SAMPLE_BITS-1:0]  d3_g_we = r2_sum_we >> 1;      // 左右两抽平均
			wire [SAMPLE_BITS-1:0]  d3_g_ns = r2_sum_ns >> 1;      // 上下两抽平均
			wire [SAMPLE_BITS-1:0]  d3_g_flat = r2_cross >> 2;     // 圆整四抽平均
			wire [SAMPLE_BITS-1:0]  d3_c_avg = r2_diag >> 2;       // 圆整对角平均
			wire        d3_dir_h = (r2_grad_h < r2_grad_v);      // 水平方向更平坦
			wire [SAMPLE_BITS-1:0]  d3_g_edge = d3_dir_h ? d3_g_we : d3_g_ns;   // 边缘导向绿
			wire [SAMPLE_BITS-1:0]  d3_g_sel = edge_r ? d3_g_edge : d3_g_flat;  // 选定绿
            // d3 consumes r2 data: use the same second-stage row parity.
            // A third-stage parity can select the preceding row at a bubble.
			wire [1:0]  d3_cen_col = g_l[0] ? (p2_r ? ph11_r : ph01_r) : (p2_r ? ph10_r : ph00_r);   // 中心色
			wire [1:0]  d3_hor_col = g_l[0] ? (p2_r ? ph10_r : ph00_r) : (p2_r ? ph11_r : ph01_r);   // 水平邻色
			wire        d3_is_r = (d3_cen_col == COL_R);         // 中心为红
			wire        d3_is_g = (d3_cen_col == COL_G);         // 中心为绿
			wire        d3_is_b = (d3_cen_col == COL_B);         // 中心为蓝
			wire        d3_hor_r = (d3_hor_col == COL_R);        // 水平邻为红
			reg  [SAMPLE_BITS-1:0]  r3_g_we;                                 // 第 3 级左右平均
			reg  [SAMPLE_BITS-1:0]  r3_g_ns;                                 // 第 3 级上下平均
			reg  [SAMPLE_BITS-1:0]  r3_g_sel;                                // 第 3 级选定绿
			reg  [SAMPLE_BITS-1:0]  r3_c_avg;                                // 第 3 级对角平均
			reg  [SAMPLE_BITS-1:0]  r3_ctr;                                  // 第 3 级中心
			reg         r3_is_r;                                 // 第 3 级中心为红
			reg         r3_is_g;                                 // 第 3 级中心为绿
			reg         r3_is_b;                                 // 第 3 级中心为蓝
			reg         r3_hor_r;                                // 第 3 级水平邻为红

  // 第四级按中心颜色分配三通道，中心原有颜色直接透传 RAW10 样本
			wire [SAMPLE_BITS-1:0]  d4_r = r3_is_r ? r3_ctr : (r3_is_b ? r3_c_avg : (r3_hor_r ? r3_g_we : r3_g_ns));   // 红通道
			wire [SAMPLE_BITS-1:0]  d4_g = r3_is_g ? r3_ctr : r3_g_sel;      // 绿通道
			wire [SAMPLE_BITS-1:0]  d4_b = r3_is_b ? r3_ctr : (r3_is_r ? r3_c_avg : (r3_hor_r ? r3_g_ns : r3_g_we));   // 蓝通道
			reg  [SAMPLE_BITS-1:0]  r4_r_ch;                                 // 第 4 级红通道
			reg  [SAMPLE_BITS-1:0]  r4_g_ch;                                 // 第 4 级绿通道
			reg  [SAMPLE_BITS-1:0]  r4_b_ch;                                 // 第 4 级蓝通道

  // 所有数据级共用 pipe_en，流水线气泡与数据保持对齐
			// 在流水线使能时寄存各级插值结果
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

  // 第五级拼装三十位像素，红色分量在高位，蓝色分量在低位
			assign pack_data[g_l * 3*SAMPLE_BITS +: 3*SAMPLE_BITS] = {r4_r_ch, r4_g_ch, r4_b_ch};
		end
	endgenerate

  // 输出信号连线
	assign m_tdata = m_tdata_r;
	assign m_tvalid = stage_v5;
	assign m_tuser = sof5_r;
	assign m_tlast = last5_r;

endmodule
