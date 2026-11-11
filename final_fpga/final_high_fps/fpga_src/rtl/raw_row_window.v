`timescale 1ns / 1ps

// 缓存 RAW 图像行并产生去马赛克所需邻域窗口
module raw_row_window
#(
    parameter integer SAMPLE_BITS = 10,
    // 行缓存尺寸与每拍像素数
	parameter integer MAX_WIDTH  = 3840,  // 行缓存宽度上限
	parameter integer MAX_HEIGHT = 2160,  // 帧高上限
	parameter integer LANE_NUM   = 4  // 每拍像素数
)
(
    // 时钟与复位
	input  wire         clk,  // 同步时钟
	input  wire         rst_n,  // 同步低有效复位
    // 运行配置
	input  wire [12:0]  cfg_width,  // 运行期宽度，帧首锁存
	input  wire [12:0]  cfg_height,  // 运行期高度，帧首锁存
    // 输入数据流
	input  wire [4*SAMPLE_BITS-1:0]  s_tdata,  // 每拍四个 RAW10 像素
	input  wire         s_tvalid,  // 从端数据有效
	output wire         s_tready,  // 从端可接收
	input  wire         s_tuser,  // 帧首拍标记
	input  wire         s_tlast,  // 行末拍标记
    // 输出数据流
	output wire [18*SAMPLE_BITS-1:0] m_window,  // 3 行 x 6 列窗
	output wire         m_valid,  // 窗口有效
	input  wire         m_ready,  // 下游可接收
	output wire         m_first,  // 输出行首拍
	output wire         m_last,  // 输出行末拍
	output wire         m_sof,  // 输出帧首拍
	output wire         m_row_parity,  // 输出行奇偶

    // 下游占用与调试
	output wire         m_busy,  // 内部仍在途
	input  wire         i_down_busy,  // 下游在途标志
	output wire [38:0]  dbg_state  // 调试：读地址/计数/有效
);

  // 配置参数区域
	localparam integer  MAX_BEATS = MAX_WIDTH / LANE_NUM;   // 行缓存最大拍数
	localparam [12:0]   BEATS_INIT = MAX_BEATS;                 // 复位拍数初值
	localparam [12:0]   ROWS_INIT = MAX_HEIGHT;               // 复位行数初值
	localparam [12:0]   WIDTH_MIN = 13'd8;                      // 最小合法宽度
	localparam [12:0]   HEIGHT_MIN = 13'd3;                     // 最小合法高度

  // 计数器信号
	reg  [12:0]         frm_nb;                 // 锁存后的每行拍数
	reg  [12:0]         frm_h;                  // 锁存后的帧高
	reg  [12:0]         beat_idx;               // 行内拍序号
	reg  [12:0]         row_idx;                // 帧内行序号

  // 标志信号
	wire                flush_step;             // 行末内部冲刷拍
	wire                in_virtual;             // 帧末虚拟行
	wire                internal_step;          // 不消耗输入的内部拍
	wire                frame_start;            // 帧首拍位置
	wire                cfg_illegal;            // 配置非法
	wire                drop_enter;             // 进入丢弃模式
	wire                drop_restart;           // 丢弃模式重新起帧
	wire                drain_ok;               // 旧帧已排空
	wire                start_blocked;          // 帧首等待排空
	wire                beat_go;                // 引擎推进使能
	wire                beat_present;           // 本拍有 beat 注入
	wire                abort_req;              // 帧中截断检测
	wire                frame_done_enough;      // 当前帧已完整
	wire                last_beat_seen;         // 行末拍被接收

  // 寄存器信号
	reg                 drop_mode_r;            // 丢弃模式寄存器
	reg                 r1_v;                   // 第 1 级有效
	reg                 r2_v;                   // 第 2 级有效
	reg                 w_v;                    // 窗输出有效
	reg                 r1_ge1;                 // 第 1 级拍序号非零
	reg                 r1_first;               // 第 1 级行首拍
	reg                 r1_last;                // 第 1 级行末拍
	reg                 r2_ge1;                 // 第 2 级拍序号非零
	reg                 r2_first;               // 第 2 级行首拍
	reg                 r2_last;                // 第 2 级行末拍
	reg  [12:0]         r2_row_idx;             // 第 2 级行序号
	reg                 r2_in_virtual;          // 第 2 级虚拟行
	reg  [4*SAMPLE_BITS-1:0]         r1_data;                // 第 1 级输入 beat
	reg  [12:0]         r1_row_idx;             // 第 1 级行序号
	reg                 r1_in_virtual;          // 第 1 级虚拟行
	reg                 r1_bank_lsb;            // 第 1 级行奇偶
	reg  [4*SAMPLE_BITS-1:0]         beat_new [0:2];         // 各行的最新 beat
	reg  [4*SAMPLE_BITS-1:0]         beat_mid [0:2];         // 各行的中间 beat
	reg  [4*SAMPLE_BITS-1:0]         beat_old [0:2];         // 各行最旧 beat
	wire [4*SAMPLE_BITS-1:0]         rd_b0;                  // 第0行缓存 读数据
	wire [4*SAMPLE_BITS-1:0]         rd_b1;                  // 第1行缓存 读数据
	reg  [11:0]         w1_addr;                // 写流水第 1 级地址
	reg  [11:0]         w2_addr;                // 写流水第 2 级地址
	reg  [4*SAMPLE_BITS-1:0]         w1_data;                // 写流水第 1 级数据
	reg  [4*SAMPLE_BITS-1:0]         w2_data;                // 写流水第 2 级数据
	reg                 w1_pend;                // 写流水第 1 级挂起
	reg                 w2_pend;                // 写流水第 2 级挂起
	reg                 w2_bank;                // 写流水第 2 级 bank
	reg  [18*SAMPLE_BITS-1:0]        win_r;                  // 窗输出寄存器
	reg                 m_first_r;              // 行首拍寄存器
	reg                 m_last_r;               // 行末拍寄存器
	reg                 m_sof_r;                // 帧首拍寄存器
	reg                 m_parity_r;             // 行奇偶寄存器

  // 其他信号
	wire                bank0_write;
	wire                bank1_write;

  // 其他信号连线
	wire [12:0]         rd_addr_c;              // 当前读地址候选
	wire [11:0]         rd_addr_p;              // 行缓存组合读地址
	wire                wr_enable_c;            // 当前写使能
	wire [4*SAMPLE_BITS-1:0]         top_rdata;              // 上上行读数据
	wire [4*SAMPLE_BITS-1:0]         mid_rdata;              // 上一行读数据
	wire [4*SAMPLE_BITS-1:0]         top_sel;                // 上上行选择结果
	wire [4*SAMPLE_BITS-1:0]         bot_sel;                // 输入行选择结果
	wire [18*SAMPLE_BITS-1:0]        win_raw;                // 未做列反射的窗
	wire [18*SAMPLE_BITS-1:0]        win_col;                // 列反射后的窗
	wire [18*SAMPLE_BITS-1:0]        win_eff;                // 行反射后的窗
	wire                r2_top_reflect;         // 输出行 0 的上反射
	wire                r2_out_valid;           // 第 2 级输出有效
	wire [12:0]         width_beats;            // 配置折算拍数
	wire                width_bad;              // 宽度非法
	wire                height_bad;             // 高度非法
	wire                size_bad;                // 尺寸超上限

  // 主要任务处理区域
  // 帧状态判定：冲刷拍、虚拟行、帧首与合法性
  // 组合译码冲刷拍、虚拟行、帧首以及尺寸是否合法
	assign width_beats = {2'b00, cfg_width[12:2]};
	assign flush_step = (beat_idx == frm_nb);
	assign in_virtual = (row_idx == frm_h);
	assign internal_step = in_virtual || flush_step;
	assign frame_start = (row_idx == 13'd0) && (beat_idx == 13'd0);
	assign width_bad = (cfg_width[1:0] != 2'd0) || (cfg_width < WIDTH_MIN);
	assign height_bad = (cfg_height < HEIGHT_MIN) || (cfg_height > MAX_HEIGHT);
	assign size_bad = (width_beats > MAX_BEATS);
	assign cfg_illegal = width_bad || height_bad || size_bad;
	assign frame_done_enough = in_virtual || frame_start || ((row_idx == (frm_h - 13'd1)) && flush_step);
	assign abort_req = s_tvalid && s_tuser && (~frame_done_enough) && (~drop_mode_r);
	assign drop_enter = frame_start && cfg_illegal && s_tvalid && (~drop_mode_r);
	assign drop_restart = drop_mode_r && s_tvalid && s_tuser && (~cfg_illegal);

  // 窗口输出槽为空或已被接收时推进引擎，内部有效位生成不额外等待 ready
	assign beat_go = (~w_v) || m_ready;
	assign drain_ok = ~(m_busy || i_down_busy);
	assign start_blocked = frame_start && (~drain_ok);
	assign s_tready = drop_mode_r || drop_enter || (beat_go && (~internal_step) && (~start_blocked));
	assign beat_present = drop_mode_r ? drop_restart : ((~drop_enter) && (internal_step || (s_tvalid && s_tready)));
  // 调试字段宽度为 10+13+13+3=39 位，rd_addr_p 只取低十位，足以覆盖最多 960 拍的行缓存
	assign dbg_state = {rd_addr_p[9:0], beat_idx, row_idx, w_v, r1_v, r2_v};
	assign last_beat_seen = s_tvalid && s_tready && s_tlast && (~internal_step) && (~drop_mode_r);

  // 冲刷拍的读地址固定为第零拍且不越界，其读出数据会由行末反射值取代
	assign rd_addr_c = flush_step ? 13'd0 : beat_idx;
	assign rd_addr_p = rd_addr_c[11:0];
	assign wr_enable_c = ~internal_step;
	assign bank0_write = w2_pend && (w2_bank == 1'b0);
	assign bank1_write = w2_pend && (w2_bank == 1'b1);
	isp_line_ram_native4 #(.SAMPLE_BITS(SAMPLE_BITS)) u_line_bank0 (
		.clk(clk), .wr_en(bank0_write), .wr_addr(w2_addr[9:0]), .wr_data(w2_data),
		.rd_en(beat_go && beat_present), .rd_addr(rd_addr_p[9:0]), .rd_data(rd_b0)
	);
	isp_line_ram_native4 #(.SAMPLE_BITS(SAMPLE_BITS)) u_line_bank1 (
		.clk(clk), .wr_en(bank1_write), .wr_addr(w2_addr[9:0]), .wr_data(w2_data),
		.rd_en(beat_go && beat_present), .rd_addr(rd_addr_p[9:0]), .rd_data(rd_b1)
	);

  // 读数据与行选择：上上行取自同 bank，上一行取自另一 bank
  // 上方行取自当前行缓存，中央行取自另一行缓存
	assign top_rdata = r1_bank_lsb ? rd_b1 : rd_b0;
	assign mid_rdata = r1_bank_lsb ? rd_b0 : rd_b1;
	assign top_sel = (r1_row_idx == 13'd1) ? r1_data : top_rdata;
	assign bot_sel = r1_in_virtual ? top_sel : r1_data;

  // 窗拼装：最旧 beat 的最高 lane 为左列，中间 beat 提供四列，最新 beat 的最低 lane 为右列
  // 最旧拍的最高路构成左列，中间拍提供中间四列，最新拍的最低路构成右列
	genvar g_row;
	generate
		for(g_row = 0; g_row < 3; g_row = g_row + 1)begin : GEN_ROW
			assign win_raw[g_row * 6*SAMPLE_BITS +: 6*SAMPLE_BITS] = {beat_new[g_row][0 +: SAMPLE_BITS], beat_mid[g_row], beat_old[g_row][3*SAMPLE_BITS +: SAMPLE_BITS]};
		end
	endgenerate

  // 列反射 reflect101：最左列取第 2 列、最右列取第 4 列，列奇偶不变即 CFA 相位不变
  // 列边界按 reflect101 反射，最左列取第 2 列、最右列取第 4 列
  // 这种取法保持列奇偶性，因此也保持 CFA 相位
	generate
		for(g_row = 0; g_row < 3; g_row = g_row + 1)begin : GEN_COL
			wire [6*SAMPLE_BITS-1:0] row_win = win_raw[g_row * 6*SAMPLE_BITS +: 6*SAMPLE_BITS];
			assign win_col[g_row * 6*SAMPLE_BITS +: 6*SAMPLE_BITS] = {r2_last ? row_win[3*SAMPLE_BITS +: SAMPLE_BITS] : row_win[5*SAMPLE_BITS +: SAMPLE_BITS], row_win[SAMPLE_BITS +: 4*SAMPLE_BITS], r2_first ? row_win[2*SAMPLE_BITS +: SAMPLE_BITS] : row_win[0 +: SAMPLE_BITS]};
		end
	endgenerate

  // 行反射 reflect101：输出行 0 的上行取下一行（bot 行），帧末虚拟行的下行取上一行（top 行）
  // 行边界按 reflect101 反射：输出第零行时上方行取下一行
  // 帧末虚拟行时下方行取上一行
	assign r2_top_reflect = (r2_row_idx == 13'd1);
	wire [6*SAMPLE_BITS-1:0] top_eff = r2_top_reflect ? win_col[0 +: 6*SAMPLE_BITS] : win_col[12*SAMPLE_BITS +: 6*SAMPLE_BITS];
	wire [6*SAMPLE_BITS-1:0] bot_eff = r2_in_virtual ? win_col[12*SAMPLE_BITS +: 6*SAMPLE_BITS] : win_col[0 +: 6*SAMPLE_BITS];
	assign win_eff = {top_eff, win_col[6*SAMPLE_BITS +: 6*SAMPLE_BITS], bot_eff};

  // 输出状态：输出行序号为 row_idx-1，因此第 0 行输出被屏蔽；行奇偶用于 Bayer 判定
  // 输出行号比当前行号小一，因此首行未就绪时屏蔽输出
  // 行号奇偶性用于后续 Bayer 颜色判定
	assign r2_out_valid = r2_v && r2_ge1 && (r2_row_idx != 13'd0);
	assign m_window = win_r;
	assign m_valid = w_v;
	assign m_first = m_first_r;
	assign m_last = m_last_r;
	assign m_sof = m_sof_r;
	assign m_row_parity = m_parity_r;
	assign m_busy = r1_v || r2_v || w_v;

  // 行缓存写地址比读地址落后两拍，同一周期的读写地址始终不同
  // 读数据寄存器只在注入拍与流水线同步采样，停顿和气泡期间保持原值
  // 若每周期采样，后续读值会错配到仍在途的拍，导致窗口折回行首
	// 按照待处理行选择缓存读写阶段
	always@(posedge clk)begin
  // 两个行缓存端口均由 TD 生成的简单双端口存储器实现
	end

  // 帧内计数仅随注入拍推进，气泡和停顿不改变拍序号，行末标记可提前结束当前行
	// 按输入握手更新帧行坐标和行缓存状态
	always@(posedge clk)begin
		if(!rst_n)begin
			frm_nb <= BEATS_INIT;
			frm_h <= ROWS_INIT;
			beat_idx <= 13'd0;
			row_idx <= 13'd0;
			drop_mode_r <= 1'b0;
		end
		else if(abort_req)begin
			beat_idx <= 13'd0;
			row_idx <= 13'd0;
			drop_mode_r <= 1'b0;
		end
		else if(drop_enter)begin
			beat_idx <= 13'd0;
			row_idx <= 13'd0;
			drop_mode_r <= 1'b1;
		end
		else if(beat_go && beat_present)begin
			if(flush_step)begin
				beat_idx <= 13'd0;
				if(row_idx == frm_h)begin
					row_idx <= 13'd0;
				end
				else if(row_idx == (frm_h - 13'd1))begin
					row_idx <= frm_h;
				end
				else begin
					row_idx <= row_idx + 13'd1;
				end
			end
			else begin
				beat_idx <= last_beat_seen ? frm_nb : (beat_idx + 13'd1);
			end
			if(frame_start)begin
				frm_nb <= width_beats;
				frm_h <= cfg_height;
				drop_mode_r <= cfg_illegal;
			end
		end
	end

  // 写流水与读地址：只在 beat 注入时推进，读写地址错位关系与停顿和气泡无关
  // 冲刷拍的读地址不参与有效数据，其采样已由读数据的注入拍使能挡住
  // 写流水与读地址只在注入拍推进，读写地址间隔不受停顿和气泡影响
  // 冲刷拍读地址不承载有效数据，读数据寄存器的注入拍使能会阻止其采样
	// 将写入请求与邻域读取请求分别暂存
	always@(posedge clk)begin
		if(!rst_n)begin
			w1_pend <= 1'b0;
			w2_pend <= 1'b0;
		end
		else if(beat_go && beat_present)begin
			w1_addr <= rd_addr_c;
			w1_data <= (flush_step && (~in_virtual)) ? {4{r1_data[3*SAMPLE_BITS +: SAMPLE_BITS]}} : s_tdata;
			w1_pend <= wr_enable_c;
			w2_addr <= w1_addr;
			w2_data <= w1_data;
			w2_pend <= w1_pend;
			w2_bank <= row_idx[0];
		end
	end

  // 数据流水与行缓存历史：历史寄存器只随有效 beat 移位，气泡不污染 3x3 邻域
  // 行历史寄存器仅在有效拍移位，气泡不会污染三乘三邻域
	// 对齐行缓存读出的邻域数据
	always@(posedge clk)begin
		if(!rst_n)begin
			r1_v <= 1'b0;
			r2_v <= 1'b0;
		end
		else if(beat_go)begin
			r1_v <= beat_present;
			r2_v <= r1_v;
			if(beat_present)begin
				r1_data <= (flush_step && (~in_virtual)) ? {4{r1_data[3*SAMPLE_BITS +: SAMPLE_BITS]}} : s_tdata;
				r1_row_idx <= row_idx;
				r1_in_virtual <= in_virtual;
				r1_bank_lsb <= row_idx[0];
				r1_ge1 <= (beat_idx != 13'd0);
				r1_first <= (beat_idx == 13'd1);
				r1_last <= flush_step;
			end
			if(r1_v)begin
				beat_new[0] <= bot_sel;
				beat_mid[0] <= beat_new[0];
				beat_old[0] <= beat_mid[0];
				beat_new[1] <= mid_rdata;
				beat_mid[1] <= beat_new[1];
				beat_old[1] <= beat_mid[1];
				beat_new[2] <= top_sel;
				beat_mid[2] <= beat_new[2];
				beat_old[2] <= beat_mid[2];
				r2_ge1 <= r1_ge1;
				r2_first <= r1_first;
				r2_last <= r1_last;
				r2_row_idx <= r1_row_idx;
				r2_in_virtual <= r1_in_virtual;
			end
		end
	end

  // 窗输出寄存器：下游接收或空槽时更新，反压期间窗与标记保持稳定
  // 窗口输出槽仅在空闲或下游接收时更新，反压期间窗口和边界标记保持稳定
	// 在下游可接收时推进窗口和边界标记
	always@(posedge clk)begin
		if(!rst_n)begin
			w_v <= 1'b0;
			m_first_r <= 1'b0;
			m_last_r <= 1'b0;
			m_sof_r <= 1'b0;
			m_parity_r <= 1'b0;
		end
		else if(beat_go)begin
			w_v <= r2_out_valid;
			win_r <= win_eff;
			m_first_r <= r2_first;
			m_last_r <= r2_last;
			m_sof_r <= r2_first && r2_top_reflect;
			m_parity_r <= ~r2_row_idx[0];
		end
	end

endmodule
