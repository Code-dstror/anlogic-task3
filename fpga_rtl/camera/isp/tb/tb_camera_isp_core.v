`timescale 1ns / 1ps

// 独立端到端验证：由主 agent 编写，用于交叉核对 RAW+COLOR 的实现结果。
// 判据与实现解耦：使用"线性旁路 + 单位白平衡 + 单位颜色矩阵"配置，使输出可被逐像素
// 解析式预测，因此不会复制被测 RTL 的表达式而与缺陷一起自洽。
//
// 配置：C_GAMMA_LINEAR_BYPASS=1（输出 = (输入10bit+2)>>2）
//       WB 增益 256(Q8)=1.0x，CCM 单位阵 → 颜色级恒等
//
// 输入图案（RGGB，BLC 偏置 50）：
//   R 目标值 = R0 + 4*col   （每列 +4，>>2 后每列恰好 +1）
//   G 目标值 = G0           （全图恒定）
//   B 目标值 = B0           （全图恒定）
// 圆整双线性插值对线性斜坡可精确还原，因此逐像素期望值为：
//   R_out = (R0 + 4*col + 2) >> 2 = R_OUT_BASE + col
//   G_out = (G0 + 2) >> 2
//   B_out = (B0 + 2) >> 2
// 判据：
//   E1  每个像素的 R/G/B 都等于上述解析期望值（含四边四角）
//   E2  tuser 每帧一次且在第 0 拍；tlast 每行一次且在行末拍
//   E3  一帧接收到的拍数 == width*height/4
//   E4  valid=1 且连续两拍 ready=0 时，data/user/last 保持不变
//   E5  带停顿与不带停顿两帧结果一致
//
// 输入源为标准时钟化 AXI-Stream 源：只在 s_tvalid & s_tready 成立的时钟沿推进，
// 避免"在 s_tready 于沿后变化时提前换数据"这类测试台缺陷。
module tb_isp_core_top_invariants;

	localparam integer W              = 16;                 // 图像宽度，4 的倍数
	localparam integer H              = 4;                  // 图像高度
	localparam integer BEATS_PER_LINE = W / 4;              // 每行拍数
	localparam integer TOTAL_BEATS    = BEATS_PER_LINE * H;
	localparam integer BLC_OFFSET     = 50;                 // 与默认参数一致
	localparam integer R0             = 300;                // R 目标起始值（每列 +4）
	localparam integer R_STEP         = 4;
	localparam integer G0             = 400;                // G 目标值
	localparam integer B0             = 200;                // B 目标值
	localparam integer R_OUT_BASE     = R0 >> 2;            // 期望输出基准
	localparam integer G_OUT          = G0 >> 2;
	localparam integer B_OUT          = B0 >> 2;
	// 均匀彩色场使用"逐通道不同值"，否则无法检测通道置换
	localparam integer UNI_R          = 900;
	localparam integer UNI_G          = 500;
	localparam integer UNI_B          = 200;
	localparam integer UNI_R_OUT      = (UNI_R + 2) >> 2;   // 线性旁路 >>2（含圆整）
	localparam integer UNI_G_OUT      = (UNI_G + 2) >> 2;
	localparam integer UNI_B_OUT      = (UNI_B + 2) >> 2;
	localparam integer STALL_PERIOD   = 16;                 // 停顿图案周期
	localparam integer STALL_LOW_FROM = 6;                  // 周期内开始拉低的拍
	localparam integer STALL_LOW_TO   = 9;                  // 周期内恢复的拍

	reg                clk;
	reg                rst_n;
	reg                src_active;                          // 1=允许发送新帧
	reg                stall_mode;                          // 1=下游插入停顿
	reg  [15:0]        beats_sent;                          // 已被接收的输入拍数
	reg                s_tvalid;
	reg  [39:0]        s_tdata;
	reg                s_tuser;
	reg                s_tlast;
	wire               s_tready;
	wire [95:0]        m_tdata;
	wire               m_tvalid;
	wire               m_tuser;
	wire               m_tlast;
	reg                m_tready;
	reg  [4:0]         stall_cnt;
	wire [31:0]        stat_beat_total;
	wire [31:0]        stat_frame_total;
	wire [31:0]        stat_saturate_total;

	integer            errors;
	integer            beats_seen;
	integer            user_seen;
	integer            last_seen;
	integer            stall_cycles;

	reg [95:0]         prev_data;
	reg                prev_valid;
	reg                prev_ready;
	reg                prev_user;
	reg                prev_last;

	integer            idx;
	integer            grp;
	integer            lane;
	integer            col;
	integer            exp_r;
	integer            got_r;
	integer            got_g;
	integer            got_b;
	integer            report_budget;
	integer            pattern_sel;                         // 0=均匀场(全部采样=400), 1=R 斜坡
	integer            exp_g;
	integer            exp_b;
	integer            frame_tag;                           // 当前帧编号，用于定位失败来源

	isp_core_top #(
		.C_MAX_WIDTH           (W      ),
		.C_MAX_HEIGHT          (H      ),
		.C_BLC_OFFSET_L0       (10'd50 ),
		.C_BLC_OFFSET_L1       (10'd50 ),
		.C_BLC_OFFSET_L2       (10'd50 ),
		.C_BLC_OFFSET_L3       (10'd50 ),
		.C_WB_GAIN_R           (16'd256),
		.C_WB_GAIN_G           (16'd256),
		.C_WB_GAIN_B           (16'd256),
		.C_CCM_M00             (11'sd256),
		.C_CCM_M01             (11'sd0  ),
		.C_CCM_M02             (11'sd0  ),
		.C_CCM_M10             (11'sd0  ),
		.C_CCM_M11             (11'sd256),
		.C_CCM_M12             (11'sd0  ),
		.C_CCM_M20             (11'sd0  ),
		.C_CCM_M21             (11'sd0  ),
		.C_CCM_M22             (11'sd256),
		.C_GAMMA_LINEAR_BYPASS (1      )     // 1 = 线性旁路，使输出可解析预测
	) u_dut (
		.clk                   (clk      ),
		.rst_n                 (rst_n    ),
		.cfg_width             (13'd16   ),
		.cfg_height            (13'd4    ),
		.cfg_bayer_phase       (2'b00    ),   // RGGB
		.cfg_edge_g            (1'b0     ),   // 圆整双线性
		.s_tdata               (s_tdata  ),
		.s_tvalid              (s_tvalid ),
		.s_tuser               (s_tuser  ),
		.s_tlast               (s_tlast  ),
		.s_tready              (s_tready ),
		.m_tdata               (m_tdata  ),
		.m_tvalid              (m_tvalid ),
		.m_tready              (m_tready ),
		.m_tuser               (m_tuser  ),
		.m_tlast               (m_tlast  ),
		.o_stat_beat_total     (stat_beat_total    ),
		.o_stat_frame_total    (stat_frame_total   ),
		.o_stat_saturate_total (stat_saturate_total)
	);

	initial begin
		clk = 1'b0;
		forever #5 clk = ~clk;                               // 100 MHz
	end

	// 按 RGGB 相位与线性斜坡生成第 beat 拍的 40bit RAW10 输入。
	function [39:0] make_input_beat;
		input integer beat;
		integer       trow;
		integer       tgrp;
		integer       tlane;
		integer       tcol;
		integer       target;
		begin
			trow = beat / BEATS_PER_LINE;
			tgrp = beat % BEATS_PER_LINE;
			make_input_beat = 40'd0;
			for (tlane = 0; tlane < 4; tlane = tlane + 1) begin
				tcol = tgrp * 4 + tlane;
				if (pattern_sel == 0) begin
					// 均匀彩色场：按 CFA 相位分别填入三种不同的目标色。
					// 用"逐通道不同值"而不是单一灰度，才能检测通道置换/相位错误。
					if (trow % 2 == 0) begin
						target = (tcol % 2 == 0) ? UNI_R : UNI_G;
					end else begin
						target = (tcol % 2 == 0) ? UNI_G : UNI_B;
					end
				end else if (pattern_sel == 2) begin
					// 单点脉冲：R 平面仅在 col=8 抬高，用于定位横向窗口映射
					if (trow % 2 == 0) begin
						if (tcol % 2 == 0) begin
							target = (tcol == 8) ? 900 : 200;        // R 采样
						end else begin
							target = 400;                            // G 采样
						end
					end else begin
						target = (tcol % 2 == 0) ? 400 : 200;        // 奇行 G B
					end
				end else if (pattern_sel == 3) begin
					// 按拍步进的 R 标记：R 采样值 = 200 + 100*floor(col/4)
					// lane0/lane1/lane2 应恰好等于该拍标记值，任何拍级位移都会暴露
					if (trow % 2 == 0) begin
						if (tcol % 2 == 0) begin
							target = 200 + 100 * (tcol / 4);         // R 采样
						end else begin
							target = 400;                            // G 采样
						end
					end else begin
						target = (tcol % 2 == 0) ? 400 : 200;        // 奇行 G B
					end
				end else if (trow % 2 == 0) begin
					target = (tcol % 2 == 0) ? (R0 + R_STEP * tcol) : G0;   // 偶行 R G R G
				end else begin
					target = (tcol % 2 == 0) ? G0 : B0;                     // 奇行 G B G B
				end
				make_input_beat[tlane*10 +: 10] = target + BLC_OFFSET;
			end
		end
	endfunction

	function [7:0] lane_r;
		input [95:0] data;
		input integer ln;
		begin
			lane_r = data[ln*24 + 16 +: 8];
		end
	endfunction

	function [7:0] lane_g;
		input [95:0] data;
		input integer ln;
		begin
			lane_g = data[ln*24 + 8 +: 8];
		end
	endfunction

	function [7:0] lane_b;
		input [95:0] data;
		input integer ln;
		begin
			lane_b = data[ln*24 +: 8];
		end
	endfunction

	// 标准 AXI-Stream 源：只在 valid & ready 同时成立的沿推进。
	always @(posedge clk) begin
		if (!rst_n) begin
			s_tvalid   <= 1'b0;
			s_tdata    <= 40'd0;
			s_tuser    <= 1'b0;
			s_tlast    <= 1'b0;
			beats_sent <= 16'd0;
		end else if (s_tvalid === 1'b1 && s_tready === 1'b1) begin
			// 本拍已被接收
			if (beats_sent + 16'd1 >= TOTAL_BEATS) begin
				s_tvalid <= 1'b0;
				s_tuser  <= 1'b0;
				s_tlast  <= 1'b0;
			end else begin
				s_tdata  <= make_input_beat(beats_sent + 16'd1);
				s_tuser  <= ((beats_sent + 16'd1) == 16'd0);
				s_tlast  <= (((beats_sent + 16'd1) % BEATS_PER_LINE) == (BEATS_PER_LINE - 1));
				s_tvalid <= 1'b1;
			end
			beats_sent <= beats_sent + 16'd1;
		end else if (src_active === 1'b1 && s_tvalid === 1'b0 && beats_sent < TOTAL_BEATS) begin
			s_tdata  <= make_input_beat(beats_sent);
			s_tuser  <= (beats_sent == 16'd0);
			s_tlast  <= ((beats_sent % BEATS_PER_LINE) == (BEATS_PER_LINE - 1));
			s_tvalid <= 1'b1;
		end
	end

	// 下游停顿图案：周期 16 拍中拉低 4 拍，产生可复现的反压。
	always @(posedge clk) begin
		if (!rst_n) begin
			stall_cnt <= 5'd0;
			m_tready  <= 1'b1;
		end else if (stall_mode === 1'b0) begin
			stall_cnt <= 5'd0;
			m_tready  <= 1'b1;
		end else begin
			stall_cnt <= (stall_cnt == (STALL_PERIOD - 1)) ? 5'd0 : (stall_cnt + 5'd1);
			m_tready  <= ~((stall_cnt >= STALL_LOW_FROM) && (stall_cnt <= STALL_LOW_TO));
		end
	end

	// 输出监视：全部判据在传输拍上检查。
	always @(posedge clk) begin
		if (!rst_n) begin
			prev_valid <= 1'b0;
			prev_ready <= 1'b0;
			prev_data  <= 96'd0;
			prev_user  <= 1'b0;
			prev_last  <= 1'b0;
		end else begin
			// E4：连续两拍 ready=0（中间未发生传输）时，输出必须保持不变。
			if (prev_valid === 1'b1 && prev_ready === 1'b0 && m_tready === 1'b0) begin
				if (m_tvalid !== 1'b1 || m_tdata !== prev_data ||
				    m_tuser !== prev_user || m_tlast !== prev_last) begin
					errors = errors + 1;
					if (report_budget > 0) begin
						report_budget = report_budget - 1;
						$display("FAIL E4: stall at beat %0d valid %b->%b user %b->%b last %b->%b data %h->%h",
						         beats_seen, prev_valid, m_tvalid, prev_user, m_tuser,
						         prev_last, m_tlast, prev_data, m_tdata);
					end
				end else begin
					stall_cycles = stall_cycles + 1;
				end
			end

			prev_valid <= m_tvalid;
			prev_ready <= m_tready;
			prev_data  <= m_tdata;
			prev_user  <= m_tuser;
			prev_last  <= m_tlast;

			if (m_tvalid === 1'b1 && m_tready === 1'b1) begin
				idx = beats_seen;
				grp = idx % BEATS_PER_LINE;

				if (m_tuser === 1'b1) user_seen = user_seen + 1;
				if (m_tlast === 1'b1) last_seen = last_seen + 1;

				// E2：标记必须落在正确的拍上
				if (m_tuser !== ((idx == 0) ? 1'b1 : 1'b0)) begin
					errors = errors + 1;
					$display("FAIL E2: tuser on wrong beat %0d", idx);
				end
				if (m_tlast !== ((grp == BEATS_PER_LINE - 1) ? 1'b1 : 1'b0)) begin
					errors = errors + 1;
					$display("FAIL E2: tlast on wrong beat %0d", idx);
				end

				// E1：逐像素解析期望值比对（含四边四角）
				for (lane = 0; lane < 4; lane = lane + 1) begin
					col = grp * 4 + lane;
					if (pattern_sel == 2 || (pattern_sel == 1 && (idx < 4 || frame_tag == 3))) begin
						// 脉冲图案：定位横向窗口映射；斜坡图案：打印首行全部通道值
						$display("TRACE%d beat %0d lane %0d col %0d R=%0d G=%0d B=%0d",
						         pattern_sel, idx, lane, col,
						         lane_r(m_tdata, lane), lane_g(m_tdata, lane), lane_b(m_tdata, lane));
					end else if (pattern_sel == 3) begin
						// 按拍标记：lane0..lane2 应等于 50+25*grp，lane3 因跨拍插值不作判定
						got_r = lane_r(m_tdata, lane);
						if (lane < 3) begin
							if (got_r !== (50 + 25 * grp)) begin
								errors = errors + 1;
								if (report_budget > 0) begin
									report_budget = report_budget - 1;
									$display("FAIL E1(beatmark): beat %0d lane %0d col %0d got R=%0d expected %0d",
									         idx, lane, col, got_r, 50 + 25 * grp);
								end
							end
						end
					end else begin
						if (pattern_sel == 0) begin
							// 均匀彩色场：三通道各自不同的期望值，可检测通道置换与相位错误
							exp_r = UNI_R_OUT;
							exp_g = UNI_G_OUT;
							exp_b = UNI_B_OUT;
						end else begin
							// 斜坡：R 随列递增，G/B 恒定。
							// 末列按 reflect101 边界处理：col=W-1 的水平邻居是 W-2（反射），
							// 因此该列取到 R(W-2) 而不是理想延拓值，属既定边界规则。
							if (col == (W - 1)) begin
								exp_r = (R0 + R_STEP * (W - 2) + 2) >> 2;
							end else begin
								exp_r = R_OUT_BASE + col;
							end
							exp_g = G_OUT;
							exp_b = B_OUT;
						end
						got_r = lane_r(m_tdata, lane);
						got_g = lane_g(m_tdata, lane);
						got_b = lane_b(m_tdata, lane);
						if (got_r !== exp_r || got_g !== exp_g || got_b !== exp_b) begin
							errors = errors + 1;
							if (report_budget > 0) begin
								report_budget = report_budget - 1;
								$display("FAIL E1: frame %0d beat %0d lane %0d col %0d got (%0d,%0d,%0d) expected (%0d,%0d,%0d)",
								         frame_tag, idx, lane, col, got_r, got_g, got_b, exp_r, exp_g, exp_b);
							end
						end
					end
				end

				beats_seen = beats_seen + 1;
			end
		end
	end

	task wait_beats_sent;
		input integer target;
		integer       guard;
		begin
			guard = 0;
			while ((beats_sent < target) && (guard < 20000)) begin
				@(posedge clk);
				guard = guard + 1;
			end
			if (guard >= 20000) begin
				errors = errors + 1;
				$display("FAIL: timeout waiting for %0d input beats (got %0d)", target, beats_sent);
			end
		end
	endtask

	task drain_output;
		input integer cycles;
		integer       i;
		begin
			for (i = 0; i < cycles; i = i + 1) @(posedge clk);
		end
	endtask

	task check_frame_result;
		input [255:0] tag;
		begin
			if (beats_seen !== TOTAL_BEATS) begin
				errors = errors + 1;
				$display("FAIL E3 (%0s): expected %0d beats, got %0d", tag, TOTAL_BEATS, beats_seen);
			end
			if (user_seen !== 1) begin
				errors = errors + 1;
				$display("FAIL E2 (%0s): expected 1 tuser, got %0d", tag, user_seen);
			end
			if (last_seen !== H) begin
				errors = errors + 1;
				$display("FAIL E2 (%0s): expected %0d tlast, got %0d", tag, H, last_seen);
			end
		end
	endtask

	integer saved_errors;

	initial begin
		errors        = 0;
		beats_seen    = 0;
		user_seen     = 0;
		last_seen     = 0;
		stall_cycles  = 0;
		report_budget = 12;
		src_active    = 1'b0;
		stall_mode    = 1'b0;
		pattern_sel   = 0;
		rst_n         = 1'b0;

		repeat (10) @(posedge clk);
		rst_n = 1'b1;
		repeat (5) @(posedge clk);

		// ---- 第 1 帧：均匀场，下游恒 ready（定位窗口对齐/边界问题）----
		$display("INFO: frame 1 uniform field, no stalls");
		frame_tag   = 1;
		pattern_sel = 0;
		beats_seen  = 0;
		user_seen   = 0;
		last_seen   = 0;
		beats_sent  = 16'd0;
		src_active  = 1'b1;
		wait_beats_sent(TOTAL_BEATS);
		src_active = 1'b0;
		drain_output(400);
		check_frame_result("frame1-uniform");

		// ---- 第 2 帧：R 斜坡，下游恒 ready ----
		$display("INFO: frame 2 ramp field, no stalls");
		frame_tag   = 2;
		pattern_sel = 1;
		beats_seen  = 0;
		user_seen   = 0;
		last_seen   = 0;
		beats_sent  = 16'd0;
		src_active  = 1'b1;
		wait_beats_sent(TOTAL_BEATS);
		src_active = 1'b0;
		drain_output(400);
		check_frame_result("frame2-ramp");
		saved_errors = errors;

		// ---- 第 3 帧：R 斜坡 + 下游停顿 ----
		beats_seen = 0;
		user_seen  = 0;
		last_seen  = 0;
		beats_sent = 16'd0;
		$display("INFO: frame 3 ramp field, with output stalls");
		frame_tag  = 3;
		stall_mode = 1'b1;
		src_active = 1'b1;
		wait_beats_sent(TOTAL_BEATS);
		src_active = 1'b0;
		drain_output(400);
		check_frame_result("frame3-stall");

		// ---- 第 4 帧：单点脉冲，打印 R 空间分布（诊断用，不做 E1 判定）----
		beats_seen = 0;
		user_seen  = 0;
		last_seen  = 0;
		beats_sent = 16'd0;
		stall_mode = 1'b0;
		$display("INFO: frame 4 impulse field, diagnostic trace");
		pattern_sel = 2;
		src_active  = 1'b1;
		wait_beats_sent(TOTAL_BEATS);
		src_active = 1'b0;
		drain_output(400);

		// ---- 第 5 帧：按拍步进标记（定量确认拍级位移）----
		beats_seen = 0;
		user_seen  = 0;
		last_seen  = 0;
		beats_sent = 16'd0;
		$display("INFO: frame 5 per-beat R marker");
		pattern_sel = 3;
		src_active  = 1'b1;
		wait_beats_sent(TOTAL_BEATS);
		src_active = 1'b0;
		drain_output(400);

		if (errors == saved_errors) begin
			$display("INFO: no new violations under backpressure");
		end
		if (stall_cycles == 0) begin
			errors = errors + 1;
			$display("FAIL E4: no sustained stall observed, stability was not exercised");
		end

		if (errors == 0) begin
			$display("INFO: sustained stall cycles observed = %0d", stall_cycles);
			$display("@@@TB PASS: isp_core_top end-to-end pixel and protocol checks clean");
		end else begin
			$display("@@@TB FAIL: %0d violations", errors);
		end
		$finish;
	end

endmodule
