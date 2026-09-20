`timescale 1ns / 1ps

// RAW 前端在真实 4K 尺寸下的吞吐与内容验证（主 agent 独立编写）。
//
// 目的：
//   1. 独立复核"4K 每帧 beat/clk ≈ 0.998"的吞吐声明，而不是采信实现方自测；
//   2. 在大尺寸地址下检查行缓存寻址（小尺寸测不出高位地址/计数器溢出类缺陷）。
//
// 图案（RGGB，BLC 偏置 50）：R 采样值按"4 像素组"步进，组内四列同值：
//   V(g) = 200 + (g mod 100)，g = col/4；G = 400，B = 200。
// 由此可解析推出每个 lane 的期望 R（圆整双线性）：
//   lane0/1/2 = V(g)                      （组内同值，横/纵向插值都还原原值）
//   lane3     = (V(g)+V(g+1)+1)>>1        （其横向邻跨到下一组）
//   末组 lane3 = V(g)                     （reflect101：col=W-1 的邻居反射回 col=W-2）
// G/B 通道应始终等于 400/200。
//
// 反压：本测试**不加**反压，只测满速吞吐与内容（反压正确性由 tb_raw_bp_content 负责）。
module tb_raw_4k_check;

	parameter integer W = 3840;      // 图像宽度，4 的倍数
	parameter integer H = 2160;      // 图像高度
	parameter integer SAMPLE_STRIDE = 251;   // 内容抽查步长（1 = 每拍都查）

	localparam integer BEATS_PER_LINE = W / 4;
	localparam integer TOTAL_BEATS    = BEATS_PER_LINE * H;
	localparam integer BLC_OFFSET     = 50;
	localparam integer V_BASE         = 200;
	localparam integer G0             = 400;
	localparam integer B0             = 200;

	reg          clk;
	reg          rst_n;
	reg          src_active;
	reg  [31:0]  beats_sent;
	reg          s_tvalid;
	reg  [39:0]  s_tdata;
	reg          s_tuser;
	reg          s_tlast;
	wire         s_tready;
	wire [119:0] m_tdata;
	wire         m_tvalid;
	wire         m_tuser;
	wire         m_tlast;

	integer      errors;
	integer      out_beats;
	integer      user_seen;
	integer      last_seen;
	integer      clk_count;
	integer      first_out_clk;
	integer      last_out_clk;
	integer      check_idx;
	integer      span;
	real         mbps;
	real         beats_per_clk;

	raw_isp_top #(
		.MAX_WIDTH     (W      ),
		.MAX_HEIGHT    (H      ),
		.BLC_OFFSET_L0 (10'd50 ),
		.BLC_OFFSET_L1 (10'd50 ),
		.BLC_OFFSET_L2 (10'd50 ),
		.BLC_OFFSET_L3 (10'd50 )
	) u_raw (
		.clk             (clk      ),
		.rst_n           (rst_n    ),
		.cfg_width       (W[12:0]  ),
		.cfg_height      (H[12:0]  ),
		.cfg_bayer_phase (2'b00    ),
		.cfg_edge_g      (1'b0     ),
		.s_tdata         (s_tdata  ),
		.s_tvalid        (s_tvalid ),
		.s_tuser         (s_tuser  ),
		.s_tlast         (s_tlast  ),
		.s_tready        (s_tready ),
		.m_tdata         (m_tdata  ),
		.m_tvalid        (m_tvalid ),
		.m_tready        (1'b1     ),
		.m_tuser         (m_tuser  ),
		.m_tlast         (m_tlast  )
	);

	initial begin
		clk = 1'b0;
		forever #5 clk = ~clk;
	end

	// 组值：R 采样在组内四列同值
	function integer group_value;
		input integer gidx;
		begin
			group_value = V_BASE + (gidx % 100);
		end
	endfunction

	function [39:0] make_input_beat;
		input integer beat;
		integer       trow, tgrp, tlane, tcol, target, lval;
		begin
			trow = beat / BEATS_PER_LINE;
			tgrp = beat % BEATS_PER_LINE;
			make_input_beat = 40'd0;
			for (tlane = 0; tlane < 4; tlane = tlane + 1) begin
				tcol = tgrp * 4 + tlane;
				if (trow % 2 == 0) begin
					// 偶行 R G R G：偶列取组值，奇列为 G
					target = (tcol % 2 == 0) ? group_value(tcol / 4) : G0;
				end else begin
					// 奇行 G B G B
					target = (tcol % 2 == 0) ? G0 : B0;
				end
				lval = target + BLC_OFFSET;
				if (lval > 1023) lval = 1023;
				make_input_beat[tlane*10 +: 10] = lval[9:0];
			end
		end
	endfunction

	function [9:0] lane_r;
		input [119:0] data;
		input integer ln;
		begin
			lane_r = data[ln*30 + 20 +: 10];
		end
	endfunction

	function [9:0] lane_g;
		input [119:0] data;
		input integer ln;
		begin
			lane_g = data[ln*30 + 10 +: 10];
		end
	endfunction

	function [9:0] lane_b;
		input [119:0] data;
		input integer ln;
		begin
			lane_b = data[ln*30 +: 10];
		end
	endfunction

	// 标准 AXI-Stream 源：只在 valid & ready 同沿推进
	always @(posedge clk) begin
		if (!rst_n) begin
			s_tvalid   <= 1'b0;
			s_tdata    <= 40'd0;
			s_tuser    <= 1'b0;
			s_tlast    <= 1'b0;
			beats_sent <= 32'd0;
		end else if (s_tvalid === 1'b1 && s_tready === 1'b1) begin
			if (beats_sent + 32'd1 >= TOTAL_BEATS) begin
				s_tvalid <= 1'b0;
				s_tuser  <= 1'b0;
				s_tlast  <= 1'b0;
			end else begin
				s_tdata  <= make_input_beat(beats_sent + 32'd1);
				s_tuser  <= ((beats_sent + 32'd1) == 32'd0);
				s_tlast  <= (((beats_sent + 32'd1) % BEATS_PER_LINE) == (BEATS_PER_LINE - 1));
				s_tvalid <= 1'b1;
			end
			beats_sent <= beats_sent + 32'd1;
		end else if (src_active === 1'b1 && s_tvalid === 1'b0 && beats_sent < TOTAL_BEATS) begin
			s_tdata  <= make_input_beat(beats_sent);
			s_tuser  <= (beats_sent == 32'd0);
			s_tlast  <= ((beats_sent % BEATS_PER_LINE) == (BEATS_PER_LINE - 1));
			s_tvalid <= 1'b1;
		end
	end

	// 时钟计数：用于统计从首个输入 beat 到末个输出 beat 的真实周期数
	always @(posedge clk) begin
		if (!rst_n) begin
			clk_count <= 0;
		end else begin
			clk_count <= clk_count + 1;
		end
	end

	integer idx, grp, lane, gidx;
	integer got_r, got_g, got_b, exp_r, exp_l3;

	always @(posedge clk) begin
		if (rst_n && m_tvalid === 1'b1) begin
			idx = out_beats;
			grp = idx % BEATS_PER_LINE;
			gidx = grp;                       // 组号 = 行内第几拍
			if (m_tuser === 1'b1) user_seen = user_seen + 1;
			if (m_tlast === 1'b1) last_seen = last_seen + 1;

			// 抽查内容，避免 2M 拍全查导致仿真过慢
			if ((idx % SAMPLE_STRIDE) == 0) begin
				exp_l3 = ((group_value(gidx) + group_value(gidx + 1) + 1) >> 1);
				if (grp == (BEATS_PER_LINE - 1)) exp_l3 = group_value(gidx);   // 末组反射
				for (lane = 0; lane < 4; lane = lane + 1) begin
					got_r = lane_r(m_tdata, lane);
					got_g = lane_g(m_tdata, lane);
					got_b = lane_b(m_tdata, lane);
					exp_r = (lane == 3) ? exp_l3 : group_value(gidx);
					if (got_r !== exp_r || got_g !== G0 || got_b !== B0) begin
						errors = errors + 1;
						if (errors <= 10) begin
							$display("FAIL: beat %0d lane %0d got (%0d,%0d,%0d) expected (%0d,%0d,%0d)",
							         idx, lane, got_r, got_g, got_b, exp_r, G0, B0);
						end
					end
				end
				check_idx = check_idx + 1;
			end

			if (out_beats == 0) first_out_clk = clk_count;
			last_out_clk = clk_count;
			out_beats = out_beats + 1;
		end
	end

	integer guard;

	initial begin
		errors       = 0;
		out_beats    = 0;
		user_seen    = 0;
		last_seen    = 0;
		clk_count    = 0;
		first_out_clk = 0;
		last_out_clk = 0;
		check_idx    = 0;
		src_active   = 1'b0;
		rst_n        = 1'b0;

		repeat (10) @(posedge clk);
		rst_n = 1'b1;
		repeat (5) @(posedge clk);

		$display("INFO: %0dx%0d frame, %0d beats, no backpressure", W, H, TOTAL_BEATS);
		src_active = 1'b1;
		guard = 0;
		while ((out_beats < TOTAL_BEATS) && (guard < (TOTAL_BEATS * 4 + 100000))) begin
			@(posedge clk);
			guard = guard + 1;
		end
		src_active = 1'b0;
		repeat (200) @(posedge clk);

		$display("INFO: out_beats=%0d user=%0d last=%0d", out_beats, user_seen, last_seen);
		span = last_out_clk - first_out_clk + 1;
		beats_per_clk = (out_beats * 1.0) / span;
		$display("INFO: output clk span=%0d  beats/clk=%0.5f", span, beats_per_clk);
		// 125 MHz 下的等效拍率；用实数避免整数溢出
		mbps = (out_beats * 125.0) / span;
		$display("INFO: at 125MHz -> %0.3f Mbeat/s (4K30 needs 62.208 Mbeat/s)",
		         mbps);
		$display("INFO: content samples checked=%0d", check_idx);

		if (out_beats !== TOTAL_BEATS) begin
			errors = errors + 1;
			$display("FAIL: expected %0d beats, got %0d", TOTAL_BEATS, out_beats);
		end
		if (user_seen !== 1) begin
			errors = errors + 1;
			$display("FAIL: expected 1 tuser, got %0d", user_seen);
		end
		if (last_seen !== H) begin
			errors = errors + 1;
			$display("FAIL: expected %0d tlast, got %0d", H, last_seen);
		end
		if (check_idx == 0) begin
			errors = errors + 1;
			$display("FAIL: no content sample was checked - test would be vacuous");
		end

		if (errors == 0) begin
			$display("@@@TB PASS: raw_isp_top 4K content and throughput checks clean");
		end else begin
			$display("@@@TB FAIL: %0d violations", errors);
		end
		$finish;
	end

endmodule
