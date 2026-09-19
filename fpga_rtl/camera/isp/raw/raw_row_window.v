`timescale 1ns / 1ps

////////////////////////////////////English///////////////////////////////////////
// Company:         AnLu ISP Optimized
// Engineer:        RAW front-end agent
//
// Create Date:     2026/02/14 12:00:00
// Design Name:     raw_row_window
// Module Name:     raw_row_window
// Description:     description/raw_row_window_Design.pdf
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
// 设计名称:        raw_row_window
// 模块名称:        raw_row_window
// 模块说明:        Description/raw_row_window_Design.pdf
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

// 行缓存与 3x6 列窗：两个 1W1R bank，写相对读延后两个 beat，因此同周期读写地址恒不相等，
// 且每个地址必然先被读作旧行再被写入新行。窗寄存器与 bank 读数据都只在注入拍推进，
// 停顿与气泡既不改拍序号也不错位读数据。
// 边界为 reflect101（保持 CFA 相位）：x=-1->1、x=W->W-2、y=-1->1、y=H->H-2。
// Row buffer and 3x6 window: two 1W1R banks with writes trailing reads by two beats, so the concurrent
// read and write addresses are never equal and every address is read as the old row before it is
// written. Window registers and bank read data advance only on injected beats, so stalls and bubbles
// neither change the beat index nor misalign the read data.
// Boundaries use reflect101 to preserve the Bayer phase: x=-1->1, x=W->W-2, y=-1->1, y=H->H-2.
module raw_row_window
#(
	parameter integer MAX_WIDTH  = 3840,      // 行缓存宽度上限 / maximum allocated width
	parameter integer MAX_HEIGHT = 2160,      // 帧高上限 / maximum frame height
	parameter integer LANE_NUM   = 4          // 每拍像素数 / pixels per beat
)
(
	//-----------------全局信号-----------------//
	input  wire         clk,                    // 同步时钟 / synchronous clock
	input  wire         rst_n,                  // 同步低有效复位 / synchronous active low reset

	//-----------------配置信号-----------------//
	input  wire [12:0]  cfg_width,              // 运行期宽度，帧首锁存 / runtime width latched at frame start
	input  wire [12:0]  cfg_height,             // 运行期高度，帧首锁存 / runtime height latched at frame start

	//-----------------从端接口-----------------//
	input  wire [39:0]  s_tdata,                // 4xRAW10 / four RAW10 samples per beat
	input  wire         s_tvalid,               // 从端数据有效 / slave data valid
	output wire         s_tready,               // 从端可接收 / slave ready
	input  wire         s_tuser,                // 帧首拍标记 / frame first beat marker
	input  wire         s_tlast,                // 行末拍标记 / line last beat marker

	//-----------------主端窗口接口-----------------//
	output wire [179:0] m_window,               // 3 行 x 6 列窗 / three row six column window
	output wire         m_valid,                // 窗口有效 / window valid
	input  wire         m_ready,                // 下游可接收 / downstream ready
	output wire         m_first,                // 输出行首拍 / output row first beat
	output wire         m_last,                 // 输出行末拍 / output row last beat
	output wire         m_sof,                  // 输出帧首拍 / output frame first beat
	output wire         m_row_parity,           // 输出行奇偶 / output row parity
	output wire         m_busy,                 // 内部仍在途 / internal data still in flight

	//-----------------下游占用-----------------//
	input  wire         i_down_busy,            // 下游在途标志 / downstream in-flight flag
	output wire [38:0]  dbg_state               // 调试：读地址/计数/有效 / debug state
);

	//---------------配置参数区域---------------//
	localparam integer  MAX_BEATS = MAX_WIDTH / LANE_NUM;   // 行缓存最大拍数 / maximum beats per line
	localparam [12:0]   BEATS_INIT = MAX_BEATS;                 // 复位拍数初值 / reset beats value
	localparam [12:0]   ROWS_INIT = MAX_HEIGHT;               // 复位行数初值 / reset rows value
	localparam [12:0]   WIDTH_MIN = 13'd8;                      // 最小合法宽度 / minimum legal width
	localparam [12:0]   HEIGHT_MIN = 13'd3;                     // 最小合法高度 / minimum legal height

	//---------------计数器信号---------------//
	reg  [12:0]         frm_nb;                 // 锁存后的每行拍数 / latched beats per line
	reg  [12:0]         frm_h;                  // 锁存后的帧高 / latched frame height
	reg  [12:0]         beat_idx;               // 行内拍序号 / beat index inside a line
	reg  [12:0]         row_idx;                // 帧内行序号 / row index inside a frame

	//---------------标志信号---------------//
	wire                flush_step;             // 行末内部冲刷拍 / internal flush step at line end
	wire                in_virtual;             // 帧末虚拟行 / virtual flush row
	wire                internal_step;          // 不消耗输入的内部拍 / internal step without input
	wire                frame_start;            // 帧首拍位置 / frame start position
	wire                cfg_illegal;            // 配置非法 / illegal configuration
	wire                drop_enter;             // 进入丢弃模式 / enter drop mode
	wire                drop_restart;           // 丢弃模式重新起帧 / restart from drop mode
	wire                drain_ok;               // 旧帧已排空 / old frame fully drained
	wire                start_blocked;          // 帧首等待排空 / frame start waits for drain
	wire                beat_go;                // 引擎推进使能 / engine advance enable
	wire                beat_present;           // 本拍有 beat 注入 / a beat is injected this step
	wire                abort_req;              // 帧中截断检测 / truncated frame detected
	wire                frame_done_enough;      // 当前帧已完整 / current frame already complete
	wire                last_beat_seen;         // 行末拍被接收 / line last beat accepted

	//---------------寄存器信号---------------//
	reg                 drop_mode_r;            // 丢弃模式寄存器 / drop mode register
	reg                 r1_v;                   // 第 1 级有效 / stage 1 valid
	reg                 r2_v;                   // 第 2 级有效 / stage 2 valid
	reg                 w_v;                    // 窗输出有效 / window output valid
	reg                 r1_ge1;                 // 第 1 级拍序号非零 / stage 1 beat index non zero
	reg                 r1_first;               // 第 1 级行首拍 / stage 1 row first beat
	reg                 r1_last;                // 第 1 级行末拍 / stage 1 row last beat
	reg                 r2_ge1;                 // 第 2 级拍序号非零 / stage 2 beat index non zero
	reg                 r2_first;               // 第 2 级行首拍 / stage 2 row first beat
	reg                 r2_last;                // 第 2 级行末拍 / stage 2 row last beat
	reg  [12:0]         r2_row_idx;             // 第 2 级行序号 / stage 2 row index
	reg                 r2_in_virtual;          // 第 2 级虚拟行 / stage 2 virtual row
	reg  [39:0]         r1_data;                // 第 1 级输入 beat / stage 1 input beat
	reg  [12:0]         r1_row_idx;             // 第 1 级行序号 / stage 1 row index
	reg                 r1_in_virtual;          // 第 1 级虚拟行 / stage 1 virtual row
	reg                 r1_bank_lsb;            // 第 1 级行奇偶 / stage 1 row parity
	reg  [39:0]         beat_new [0:2];         // 各行的最新 beat / newest beat of each row
	reg  [39:0]         beat_mid [0:2];         // 各行的中间 beat / middle beat of each row
	reg  [39:0]         beat_old [0:2];         // 各行最旧 beat / oldest beat of each row
	wire [39:0]         rd_b0;                  // bank0 读数据 / bank0 read data
	wire [39:0]         rd_b1;                  // bank1 读数据 / bank1 read data
	reg  [11:0]         w1_addr;                // 写流水第 1 级地址 / write pipe stage 1 address
	reg  [11:0]         w2_addr;                // 写流水第 2 级地址 / write pipe stage 2 address
	reg  [39:0]         w1_data;                // 写流水第 1 级数据 / write pipe stage 1 data
	reg  [39:0]         w2_data;                // 写流水第 2 级数据 / write pipe stage 2 data
	reg                 w1_pend;                // 写流水第 1 级挂起 / write pipe stage 1 pending
	reg                 w2_pend;                // 写流水第 2 级挂起 / write pipe stage 2 pending
	reg                 w2_bank;                // 写流水第 2 级 bank / write pipe stage 2 bank
	reg  [179:0]        win_r;                  // 窗输出寄存器 / window output register
	reg                 m_first_r;              // 行首拍寄存器 / row first beat register
	reg                 m_last_r;               // 行末拍寄存器 / row last beat register
	reg                 m_sof_r;                // 帧首拍寄存器 / frame first beat register
	reg                 m_parity_r;             // 行奇偶寄存器 / row parity register

	//---------------其他信号---------------//
	wire                bank0_write;
	wire                bank1_write;

	//---------------其他信号连线---------------//
	wire [12:0]         rd_addr_c;              // 当前读地址候选 / current read address candidate
	wire [11:0]         rd_addr_p;              // bank 读地址（组合）/ bank read address (combinational)
	wire                wr_enable_c;            // 当前写使能 / current write enable
	wire [39:0]         top_rdata;              // 上上行读数据 / top row read data
	wire [39:0]         mid_rdata;              // 上一行读数据 / middle row read data
	wire [39:0]         top_sel;                // 上上行选择结果 / selected top row
	wire [39:0]         bot_sel;                // 输入行选择结果 / selected bottom row
	wire [179:0]        win_raw;                // 未做列反射的窗 / window before column reflection
	wire [179:0]        win_col;                // 列反射后的窗 / window after column reflection
	wire [179:0]        win_eff;                // 行反射后的窗 / window after row reflection
	wire                r2_top_reflect;         // 输出行 0 的上反射 / top reflection for output row 0
	wire                r2_out_valid;           // 第 2 级输出有效 / stage 2 output valid
	wire [12:0]         width_beats;            // 配置折算拍数 / beats derived from config
	wire                width_bad;              // 宽度非法 / width illegal
	wire                height_bad;             // 高度非法 / height illegal
	wire                size_bad;                // 尺寸超上限 / size above allocation

	//--------------主要任务处理区域--------------//
	// 帧状态判定：冲刷拍、虚拟行、帧首与合法性。
	// Frame state decode: flush step, virtual row, frame start and legality.
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

	// 引擎推进与握手：窗槽为空或下游接收即可推进，valid 产生不等待 ready。
	// Engine advance and handshake: advance when the window slot is empty or accepted, so valid
	// generation never waits for ready.
	assign beat_go = (~w_v) || m_ready;
	assign drain_ok = ~(m_busy || i_down_busy);
	assign start_blocked = frame_start && (~drain_ok);
	assign s_tready = drop_mode_r || drop_enter || (beat_go && (~internal_step) && (~start_blocked));
	assign beat_present = drop_mode_r ? drop_restart : ((~drop_enter) && (internal_step || (s_tvalid && s_tready)));
	// 调试拼接：10+13+13+3 = 39 bit 与端口等宽，rd_addr_p 只取低 10 位（行缓存最大 960 拍）。
	// Debug concatenation: 10+13+13+3 = 39 bit matches the port exactly; rd_addr_p contributes its low
	// 10 bits only, which covers the 960-beat maximum line buffer.
	assign dbg_state = {rd_addr_p[9:0], beat_idx, row_idx, w_v, r1_v, r2_v};
	assign last_beat_seen = s_tvalid && s_tready && s_tlast && (~internal_step) && (~drop_mode_r);

	// 读地址：冲刷拍不越界，固定指向第 0 拍，其数据已被行末反射取代。
	// Read address: the flush step never goes out of range and points at beat 0, whose data is replaced
	// by the line end reflection.
	assign rd_addr_c = flush_step ? 13'd0 : beat_idx;
	assign rd_addr_p = rd_addr_c[11:0];
	assign wr_enable_c = ~internal_step;
	assign bank0_write = w2_pend && (w2_bank == 1'b0);
	assign bank1_write = w2_pend && (w2_bank == 1'b1);
	isp_line_ram_40x1024 u_line_bank0 (
		.clk(clk), .wr_en(bank0_write), .wr_addr(w2_addr[9:0]), .wr_data(w2_data),
		.rd_en(beat_go && beat_present), .rd_addr(rd_addr_p[9:0]), .rd_data(rd_b0)
	);
	isp_line_ram_40x1024 u_line_bank1 (
		.clk(clk), .wr_en(bank1_write), .wr_addr(w2_addr[9:0]), .wr_data(w2_data),
		.rd_en(beat_go && beat_present), .rd_addr(rd_addr_p[9:0]), .rd_data(rd_b1)
	);

	// 读数据与行选择：上上行取自同 bank，上一行取自另一 bank。
	// Read data and row select: the top row comes from the same bank, the middle row from the other bank.
	assign top_rdata = r1_bank_lsb ? rd_b1 : rd_b0;
	assign mid_rdata = r1_bank_lsb ? rd_b0 : rd_b1;
	assign top_sel = (r1_row_idx == 13'd1) ? r1_data : top_rdata;
	assign bot_sel = r1_in_virtual ? top_sel : r1_data;

	// 窗拼装：最旧 beat 的最高 lane 为左列，中间 beat 提供四列，最新 beat 的最低 lane 为右列。
	// Window assembly: the oldest beat highest lane is the left column, the middle beat supplies four
	// columns and the newest beat lowest lane is the right column.
	genvar g_row;
	generate
		for(g_row = 0; g_row < 3; g_row = g_row + 1)begin : GEN_ROW
			assign win_raw[g_row * 60 +: 60] = {beat_new[g_row][9:0], beat_mid[g_row][39:30], beat_mid[g_row][29:20], beat_mid[g_row][19:10], beat_mid[g_row][9:0], beat_old[g_row][39:30]};
		end
	endgenerate

	// 列反射 reflect101：最左列取第 2 列、最右列取第 4 列，列奇偶不变即 CFA 相位不变。
	// Column reflection reflect101: the leftmost column takes column 2 and the rightmost takes column 4,
	// keeping the column parity and therefore the CFA phase.
	generate
		for(g_row = 0; g_row < 3; g_row = g_row + 1)begin : GEN_COL
			wire [59:0] row_win = win_raw[g_row * 60 +: 60];
			assign win_col[g_row * 60 +: 60] = {r2_last ? row_win[39:30] : row_win[59:50], row_win[49:40], row_win[39:30], row_win[29:20], row_win[19:10], r2_first ? row_win[29:20] : row_win[9:0]};
		end
	endgenerate

	// 行反射 reflect101：输出行 0 的上行取下一行（bot 行），帧末虚拟行的下行取上一行（top 行）。
	// Row reflection reflect101: for output row 0 the top row takes the next line (bot row); for the
	// virtual row at frame end the bottom row takes the previous line (top row).
	assign r2_top_reflect = (r2_row_idx == 13'd1);
	wire [59:0] top_eff = r2_top_reflect ? win_col[59:0] : win_col[179:120];
	wire [59:0] bot_eff = r2_in_virtual ? win_col[179:120] : win_col[59:0];
	assign win_eff = {top_eff, win_col[119:60], bot_eff};

	// 输出状态：输出行序号为 row_idx-1，因此第 0 行输出被屏蔽；行奇偶用于 Bayer 判定。
	// Output status: the output row index is row_idx-1 so row 0 outputs are masked; the row parity drives
	// the Bayer decision.
	assign r2_out_valid = r2_v && r2_ge1 && (r2_row_idx != 13'd0);
	assign m_window = win_r;
	assign m_valid = w_v;
	assign m_first = m_first_r;
	assign m_last = m_last_r;
	assign m_sof = m_sof_r;
	assign m_row_parity = m_parity_r;
	assign m_busy = r1_v || r2_v || w_v;

	// bank 读写：写地址相对读地址延后两个 beat，读写地址恒不相等。
	// 读数据寄存器与 beat 流水同步推进：只在注入拍采样，停顿与气泡期间保持。
	// 若每个时钟都采样，冻结拍会把后一次读的数据对齐到仍在途的那个 beat 上（窗口折回行首）。
	// Bank read and write: the write address trails the read address by two beats, so the two addresses in
	// one cycle are never equal. The read data registers advance in lockstep with the beat pipeline: they
	// sample only on injected beats and hold through stalls and bubbles. Sampling every cycle instead
	// slides a later read onto the beat still in flight and folds the row start into the window.
	always@(posedge clk)begin
		// TD-generated SDP memories implement both line-bank ports.
	end

	// 帧内计数：只有 beat 注入才推进，气泡与停顿都不改变行内拍序号；行末拍可提前结束本行。
	// Frame counters: only injected beats advance them, so bubbles and stalls never change the beat index;
	// a line last beat may end the line early.
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

	// 写流水与读地址：只在 beat 注入时推进，读写地址错位关系与停顿和气泡无关。
	// 冲刷拍的读地址不参与有效数据，其采样已由读数据的注入拍使能挡住。
	// Write pipe and read address: they advance only on injected beats, so the read/write address offset is
	// independent of stalls and bubbles. The flush step read address carries no valid data, and its sample
	// is blocked by the injection-beat enable on the read data registers.
	always@(posedge clk)begin
		if(beat_go && beat_present)begin
			w1_addr <= rd_addr_c;
			w1_data <= (flush_step && (~in_virtual)) ? {4{r1_data[39:30]}} : s_tdata;
			w1_pend <= wr_enable_c;
			w2_addr <= w1_addr;
			w2_data <= w1_data;
			w2_pend <= w1_pend;
			w2_bank <= row_idx[0];
		end
	end

	// 数据流水与行缓存历史：历史寄存器只随有效 beat 移位，气泡不污染 3x3 邻域。
	// Data pipeline and line history: history registers shift only for valid beats, so bubbles never
	// pollute the 3x3 neighbourhood.
	always@(posedge clk)begin
		if(beat_go)begin
			r1_v <= beat_present;
			r2_v <= r1_v;
			if(beat_present)begin
				r1_data <= (flush_step && (~in_virtual)) ? {4{r1_data[39:30]}} : s_tdata;
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

	// 窗输出寄存器：下游接收或空槽时更新，反压期间窗与标记保持稳定。
	// Window output register: updated when accepted or empty, so window and markers stay stable under
	// backpressure.
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
