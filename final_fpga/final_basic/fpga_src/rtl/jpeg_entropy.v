`include "jpeg_quant_config.vh"
// 对量化系数执行JPEG熵编码和字节输出
module jpeg_entropy #(
    parameter integer STREAM_INPUT_ENABLE = 0,
    parameter integer RESTART_ENABLE = 0,
    parameter ROM_INIT_ROOT = `JPEG_QUANT_DEFAULT_ROOT,
    parameter ROM_INIT_SUFFIX = ".mif",
    parameter integer COEFF_BANKED_STORAGE_ENABLE = 0
) (
    // 时钟与复位
    input wire i_clk,
    input wire i_rst_n,

    // 中止控制
    input wire i_abort,

    // 输入量化系数
    input wire i_block_valid,
    output wire o_block_ready,
    input wire [1023:0] i_coeffs,
    input wire [1:0] i_component,
    input wire [1:0] i_block_index,
    input wire [8:0] i_mcu_x,
    input wire [8:0] i_mcu_y,
    input wire i_frame_last,
    input wire [31:0] i_capture_id,

    // Optional narrow coefficient stream: HEADER then eight batches.
    input wire i_token_valid,
    output wire o_token_ready,
    input wire [127:0] i_token_data,
    input wire [15:0] i_token_keep,
    input wire i_token_last,
    input wire [1:0] i_token_user,
    input wire [15:0] i_restart_mcus,

    // 输出熵编码字节
    output wire o_byte_valid,
    input wire i_byte_ready,
    output reg [7:0] o_byte,
    output reg o_byte_last,

    // 完成与错误状态
    output wire o_entropy_done, // 当前帧熵数据已完成输出
    output wire o_error_valid,
    output reg [31:0] o_error_capture_id,
    output reg [7:0] o_error_code,
    output wire o_idle
);
    // Keep the external asynchronous isolation, while the ROM/advance logic
    // uses only the synchronously reset local state. The caller holds reset
    // through local edges before releasing its upstream reset synchronizer.
    reg byte_valid_reg, entropy_done_reg, error_valid_reg;
    assign o_byte_valid = i_rst_n && byte_valid_reg;
    assign o_entropy_done = i_rst_n && entropy_done_reg;
    assign o_error_valid = i_rst_n && error_valid_reg;

    localparam [3:0] S_IDLE=0, S_DC=1, S_AC=2, S_BLOCK=3,
                     S_FINISH=4, S_FINAL=5, S_ABORT=6,
                     S_RESTART_PAD=7, S_RESTART_FF=8,
                     S_RESTART_ID=9, S_RESTART_DONE=10,
                     S_COLLECT=11, S_LOAD=12;
    localparam integer BANKED_STORAGE = STREAM_INPUT_ENABLE && COEFF_BANKED_STORAGE_ENABLE;
    reg [3:0] state;
    reg [1023:0] coeffs;
    reg [1:0] component;
    reg frame_last;
    reg [31:0] capture_id;
    reg [127:0] token_header;
    reg [2:0] token_batch;
    reg [63:0] pending_nonzero_mask;
    reg collecting, pending_valid, collector_closed;
    reg token_frame_active;
    reg [127:0] token_frame_header;
    reg [1:0] block_index;
    reg [15:0] restart_interval;
    // Freeze the terminal MCU count beside the frame interval so the live
    // ready/advance chain contains a comparison, not a 16-bit subtraction.
    reg [15:0] restart_last_count;
    reg [15:0] restart_count;
    reg [2:0] restart_marker;
    wire [1023:0] accepted_coeffs;
    wire [1:0] accepted_component = STREAM_INPUT_ENABLE ? token_header[115:114] : i_component;
    wire [1:0] accepted_block = STREAM_INPUT_ENABLE ? token_header[117:116] : i_block_index;
    wire [8:0] accepted_x = STREAM_INPUT_ENABLE ? token_header[104:96] : i_mcu_x;
    wire [8:0] accepted_y = STREAM_INPUT_ENABLE ? token_header[113:105] : i_mcu_y;
    wire accepted_last = STREAM_INPUT_ENABLE ? token_header[118] : i_frame_last;
    wire [31:0] accepted_capture = STREAM_INPUT_ENABLE ? token_header[31:0] : i_capture_id;
    wire first_block = accepted_x == 0 && accepted_y == 0 && accepted_block == 0;
    wire header_identity_bad = token_frame_active &&
        (i_token_data[95:0] != token_frame_header[95:0] ||
         i_token_data[126:119] != token_frame_header[126:119]);
    wire token_header_bad = i_token_user != 2'd1 || i_token_last ||
        i_token_keep != 16'hffff || i_token_data[127] ||
        i_token_data[115:114] > 2 || i_token_data[125:119] == 0 ||
        i_token_data[125:119] > 100 || header_identity_bad;
    wire token_data_bad = i_token_user != 0 || i_token_keep != 16'hffff ||
        i_token_last != (token_batch == 7);
    wire restart_boundary = RESTART_ENABLE && block_index == 3 && restart_interval != 0 &&
                            restart_count == restart_last_count;
    // The pending vector is internal algorithm state, not an interface FIFO.
    // Its collection overlaps active AC processing; RST/final output still owns
    // predictor/frame retirement before a pending vector can become active.
    wire pending_launch = STREAM_INPUT_ENABLE && pending_valid &&
        (!byte_valid_reg || i_byte_ready) &&
        ((state == S_IDLE) || (state == S_BLOCK && !frame_last && !restart_boundary));
    wire load_working_block = pending_launch ||
        (!STREAM_INPUT_ENABLE && i_block_valid && o_block_ready);
    reg signed [15:0] pred_y, pred_cb, pred_cr;
    (* preserve *) reg signed [16:0] dc_diff_reg;
    reg [6:0] scan_index;
    reg [63:0] reservoir;
    reg [6:0] reservoir_count;
    reg stuffing_pending;
    reg hold_valid;
    reg [7:0] hold_byte;
    reg pad_done;
    reg [63:0] nonzero_mask;
    (* preserve *) reg dc_pending_valid;
    (* preserve *) reg [5:0] dc_pending_length;
    (* preserve *) reg [31:0] dc_pending_bits;
    reg search_valid;
    reg search_done;
    reg [1:0] search_count;
    reg [1:0] search_kind [0:1]; // 0=EOB，1=ZRL，2=非零 AC
    reg [3:0] search_run [0:1];
    reg signed [15:0] legacy_search_coeff [0:1];
    wire signed [15:0] search_coeff [0:1];

    // AC 弹性流水线各级依次处理符号类别、幅值与 Huffman 地址、表读取、码字拼接、双符号合并及位储备追加
    // 下游未就绪时每级保留载荷和元数据，因此反压只增加周期，不改变输出字节流
    reg ac1_valid;
    reg [1:0] ac1_count;
    reg [2:0] ac1_kind [0:1];
    reg [7:0] ac1_addr [0:1];
    reg [3:0] ac1_magnitude [0:1];
    reg [9:0] ac1_amplitude [0:1];

    reg ac2_valid;
    reg [1:0] ac2_count;
    reg [2:0] ac2_kind [0:1];
    reg [3:0] ac2_magnitude [0:1];
    reg [9:0] ac2_amplitude [0:1];
    reg [15:0] ac2_legacy_code [0:1];
    reg [4:0] ac2_legacy_length [0:1];
    wire [15:0] ac2_code [0:1];
    wire [4:0] ac2_length [0:1];

    reg ac3_valid;
    reg [1:0] ac3_count;
    reg [25:0] ac3_bits [0:1];
    reg [4:0] ac3_length [0:1];

    reg ac4_valid;
    // AC4 holds a right-aligned pair, allowing one shared append shifter.
    reg [51:0] ac4_bits;
    reg [5:0] ac4_length;

    // 位储备下一状态与复位及中止选择分别计算
    reg [63:0] bits_work;
    reg [6:0] count_work;
    reg [7:0] next_byte;
    reg byte_generated;
    reg [20:0] lookup;
    reg signed [16:0] dc_diff;
    reg [16:0] absolute_dc;
    reg [4:0] magnitude;
    reg [15:0] amplitude;
    reg [31:0] symbol_bits;
    reg [5:0] symbol_length;
    reg symbol_valid;
    reg [6:0] tree_first [1:127];
    reg [6:0] tree_second [1:127];
    reg tree_first_valid [1:127];
    reg tree_second_valid [1:127];
    reg signed [15:0] tree_first_coeff [1:127];
    reg signed [15:0] tree_second_coeff [1:127];
    reg [1:0] pair_plan_count;
    reg [1:0] pair_plan_kind [0:1];
    reg [3:0] pair_plan_run [0:1];
    reg signed [15:0] pair_plan_coeff [0:1];
    reg [5:0] pair_plan_index [0:1];
    reg [6:0] pair_plan_next_scan;
    reg pair_plan_done;
    reg [10:0] ac1_adjusted,ac1_absolute;
    reg ac1_out_of_range;
    reg [3:0] ac1_magnitude_next;
    reg [9:0] ac1_amplitude_next;
    reg [20:0] ac2_lookup;
    integer n;
    integer k;
    integer tree_index;

    `include "jpeg_huff_rom.vh"

    // AC 弹性流水线按本周期排出字节后的 count_after_drain 判断追加容量
    // 一对符号最多 52 位，因此追加级最多等待两个周期即可再次接收
    wire ac_byte_out = (!byte_valid_reg || i_byte_ready) && !stuffing_pending &&
                       (reservoir_count >= 7'd8);
    wire [6:0] count_after_drain = ac_byte_out ? (reservoir_count - 7'd8) :
                                                 reservoir_count;
    // 在下游 ready 到达前先准备符号对
    // 额外的低 8 位容纳仅在本周期排字节后才能放入的 65..72 位情形
    // ready 只选择固定切片，不驱动可变移位量
    wire [7:0] count_with_pair = {1'b0, reservoir_count} +
                                 {2'b0, ac4_length};
    wire ac4_append = ac4_valid && ((count_with_pair <= 8'd64) ||
                                  (ac_byte_out && count_with_pair <= 8'd72));
    wire ac4_accept = !ac4_valid || ac4_append;
    wire ac3_advance = ac3_valid && ac4_accept;
    wire ac3_accept = !ac3_valid || ac3_advance;
    wire ac2_advance = ac2_valid && ac3_accept;
    wire ac2_accept = !ac2_valid || ac2_advance;
    wire ac1_advance = ac1_valid && ac2_accept;
    wire ac1_accept = !ac1_valid || ac1_advance;
    generate
        if (STREAM_INPUT_ENABLE) begin : g_ac_rom
            jpeg_huff_ac_rom #(.INIT_FILE({ROM_INIT_ROOT,"/ac_huffman",ROM_INIT_SUFFIX})) u_rom (
                // Reads are discarded by local validity on reset/abort. Only an
                // actual AC1 transfer advances the ROM, preserving AC2 on stall.
                .i_clk(i_clk),.i_read_enable(state == S_AC && ac1_advance),
                .i_chroma(component != 0),.i_symbol0(ac1_addr[0]),.i_symbol1(ac1_addr[1]),
                .o_code0(ac2_code[0]),.o_code1(ac2_code[1]),
                .o_length0(ac2_length[0]),.o_length1(ac2_length[1]));
        end else begin : g_ac_legacy
            assign ac2_code[0] = ac2_legacy_code[0];
            assign ac2_code[1] = ac2_legacy_code[1];
            assign ac2_length[0] = ac2_legacy_length[0];
            assign ac2_length[1] = ac2_legacy_length[1];
        end
    endgenerate
    wire search_advance = search_valid && ac1_accept;
    wire search_space = !search_valid || search_advance;
    wire coefficient_search = i_rst_n && !i_abort && state == S_AC &&
                              search_space && !search_done;
    wire coefficient_write = i_rst_n && !i_abort && state != S_ABORT &&
        i_token_valid && o_token_ready && collecting && !token_data_bad;
    // Only the unbanked token interface collects a flat vector. The banked
    // implementation below owns its DC and both indexed AC read ports.
    generate if (STREAM_INPUT_ENABLE && !BANKED_STORAGE) begin : g_flat_collector
        reg [1023:0] pending_coeffs;
        always @(posedge i_clk)
            if (coefficient_write)
                pending_coeffs[token_batch*128 +:128] <= i_token_data;
        assign accepted_coeffs = pending_coeffs;
    end else begin : g_no_flat_collector
        assign accepted_coeffs = BANKED_STORAGE ? 1024'd0 : i_coeffs;
    end endgenerate
    wire signed [15:0] accepted_dc;
    wire signed [15:0] working_dc;
    generate if (BANKED_STORAGE) begin : g_banked_coefficients
        // Each token writes eight lanes. The two slot roles exchange only when
        // a complete pending block launches, never by copying its payload.
        reg collector_bank, working_bank;
        reg signed [15:0] pending_dc, active_dc;
        reg [2:0] read_lane0, read_lane1;
        wire [127:0] read_words0, read_words1;
        assign accepted_dc = pending_dc;
        assign working_dc = active_dc;
        // AC categories 1..10 use signed eleven bits. One extra bit
        // identifies all inputs that differ from the eleven-bit sign extension.
        // Reconstruct any invalid value outside +/-1023 so AC2 retains its
        // existing error cycle. DC has its own full sixteen-bit predictor path.
        function signed [15:0] expand_ac;
            input [15:0] stored;
            begin expand_ac={{4{stored[10]}},stored[10]^stored[11],stored[10:0]};end
        endfunction
        assign search_coeff[0] = search_kind[0] == 2 ?
            expand_ac(read_words0[read_lane0*16 +:16]) : 16'sd0;
        assign search_coeff[1] = search_kind[1] == 2 ?
            expand_ac(read_words1[read_lane1*16 +:16]) : 16'sd0;
        genvar lane;
        for (lane=0; lane<8; lane=lane+1) begin : g_lane
            wire [15:0] value=i_token_data[lane*16+:16];
            wire range_escape=(|value[15:10]) && !(&value[15:10]);
            wire [15:0] stored_ac={4'd0,range_escape,value[10:0]};
            // Mirroring supplies two arbitrary coefficient reads even when
            // both selected positions use the same lane/bank. Storage and
            // synchronous read registers are not reset; validity owns them.
            td_sdp_ram #(.WIDTH(16),.DEPTH(16),.ADDR_WIDTH(4),
                .DISTRIBUTED_ENABLE(1)) u_read0 (
                .clk(i_clk),.wr_en(coefficient_write),
                .wr_addr({collector_bank,token_batch}),
                .wr_data(stored_ac),
                .rd_en(coefficient_search && pair_plan_count > 0 &&
                    pair_plan_kind[0] == 2 && pair_plan_index[0][2:0] == lane),
                .rd_addr({working_bank,pair_plan_index[0][5:3]}),
                .rd_data(read_words0[lane*16 +:16]));
            td_sdp_ram #(.WIDTH(16),.DEPTH(16),.ADDR_WIDTH(4),
                .DISTRIBUTED_ENABLE(1)) u_read1 (
                .clk(i_clk),.wr_en(coefficient_write),
                .wr_addr({collector_bank,token_batch}),
                .wr_data(stored_ac),
                .rd_en(coefficient_search && pair_plan_count > 1 &&
                    pair_plan_kind[1] == 2 && pair_plan_index[1][2:0] == lane),
                .rd_addr({working_bank,pair_plan_index[1][5:3]}),
                .rd_data(read_words1[lane*16 +:16]));
        end
        always @(posedge i_clk) begin
            if (!i_rst_n) begin
                collector_bank <= 0; working_bank <= 1;
                pending_dc <= 0; active_dc <= 0;
                read_lane0 <= 0; read_lane1 <= 0;
            end else if (i_abort || state == S_ABORT) begin
                collector_bank <= 0; working_bank <= 1;
            end else begin
                if (pending_launch) begin
                    working_bank <= collector_bank;
                    collector_bank <= !collector_bank;
                    active_dc <= pending_dc;
                end
                if (coefficient_write && token_batch == 0)
                    pending_dc <= i_token_data[15:0];
                // These selections advance with the existing search metadata.
                // CE holds every RAM output while that search slot is stalled.
                if (coefficient_search) begin
                    read_lane0 <= pair_plan_index[0][2:0];
                    read_lane1 <= pair_plan_index[1][2:0];
                end
            end
        end
    end else begin : g_vector_coefficients
        assign accepted_dc = accepted_coeffs[15:0];
        assign working_dc = coeffs[15:0];
        assign search_coeff[0] = legacy_search_coeff[0];
        assign search_coeff[1] = legacy_search_coeff[1];
    end endgenerate
    wire ac_pipeline_empty = !ac1_valid && !ac2_valid && !ac3_valid &&
                             !ac4_valid;
    wire [7:0] count_with_symbol = {1'b0, reservoir_count} +
                                   {2'b0, symbol_length};
    // DC/pad and a completed AC pair cannot append on the same valid cycle.
    // Select their right-aligned payload before one shared 72-bit aligner.
    wire [51:0] append_payload = symbol_valid ? {20'd0,symbol_bits} : ac4_bits;
    wire [7:0] append_count = symbol_valid ? count_with_symbol : count_with_pair;
    // Counts with bit 7 set shift the original 72-bit word entirely
    // out of range. Keep that zero case explicit and use a seven-bit subtract.
    wire [6:0] append_shift = 7'd72 - append_count[6:0];
    wire [71:0] aligned_append = append_count[7] ? 72'd0 :
        ({20'd0,append_payload} << append_shift);
    // 查表未命中即码长为零，或 AC 类别不受支持时明确报错
    // 不得静默截断符号
    wire ac2_error = ac2_valid &&
                     (((ac2_count > 0) &&
                       ((ac2_length[0] == 5'd0) ||
                        ((ac2_kind[0] == 3'd2) && (ac2_magnitude[0] > 5'd10)))) ||
                      ((ac2_count > 1) &&
                       ((ac2_length[1] == 5'd0) ||
                        ((ac2_kind[1] == 3'd2) && (ac2_magnitude[1] > 5'd10)))));
    // Only the selected roots need a next index. Carrying p+1 through every
    // tree node duplicates the index-selection network in the banked profile.
    wire [6:0] first_after = tree_first[1] + 7'd1;
    wire [6:0] second_after = tree_second[1] + 7'd1;
    wire [6:0] pair_first_gap = tree_first[1] - scan_index;
    wire [6:0] pair_second_gap = tree_second[1] - first_after;
    // The run nibble and the two scheduling limits have different needs.
    // Only a four-bit borrow and the two upper index bits decide 16/32.
    function [1:0] ac_gap_limits;
        input [1:0] position_high, origin_high;
        input low_borrow;
        reg [2:0] high_gap;
        begin
            high_gap = {1'b0,position_high} - {1'b0,origin_high} - low_borrow;
            ac_gap_limits = {|high_gap[2:1], |high_gap};
        end
    endfunction
    wire [1:0] first_gap_limits = scan_index[6] ? 2'b11 :
        ac_gap_limits(tree_first[1][5:4],scan_index[5:4],
                      tree_first[1][3:0] < scan_index[3:0]);
    wire [1:0] second_gap_limits = first_after[6] ? 2'b11 :
        ac_gap_limits(tree_second[1][5:4],first_after[5:4],
                      tree_second[1][3:0] < first_after[3:0]);
    // 掩码只记录尚未被已规划 NZ 符号消费的非零系数
    // 仅含 ZRL 的规划推进 scan_index，但不清除掩码
    wire pair_consumes_first = (scan_index != 7'd64) &&
                               tree_first_valid[1] &&
                               (!first_gap_limits[1]);
    wire pair_consumes_second = pair_consumes_first &&
                                (!first_gap_limits[0]) &&
                                (first_after != 7'd64) &&
                                tree_second_valid[1] &&
                                (!second_gap_limits[0]);

    // 排字节和追加的下一状态独立于架构状态复位及中止
    // 下游 ready 本身可能含复位限定
    // 保持先排字节、再追加 AC 对、最后追加 DC 或填充位的顺序
    // 计算待写入码字与位储备的下一状态
    always @(*) begin
        bits_work = ac_byte_out ? (reservoir << 8) : reservoir;
        count_work = count_after_drain;
        symbol_bits = 32'd0;
        symbol_length = 6'd0;
        symbol_valid = 1'b0;
        if (state == S_AC) begin
            if (!ac2_error && ac4_append) begin
                bits_work = bits_work | (ac_byte_out ?
                    aligned_append[63:0] : aligned_append[71:8]);
                count_work = ac_byte_out ? (count_with_pair-8'd8) :
                                          count_with_pair;
            end
            if (dc_pending_valid) begin
                symbol_bits = dc_pending_bits;
                symbol_length = dc_pending_length;
                symbol_valid = 1'b1;
            end
        end else if ((state == S_FINISH || state == S_RESTART_PAD) && !pad_done &&
                     reservoir_count[2:0] != 0) begin
            symbol_length = 8-reservoir_count[2:0];
            symbol_bits = (32'd1 << symbol_length)-1;
            symbol_valid = 1'b1;
        end
        if (symbol_valid) begin
            bits_work = bits_work | (ac_byte_out ?
                aligned_append[63:0] : aligned_append[71:8]);
            count_work = ac_byte_out ? (count_with_symbol-8'd8) :
                                       count_with_symbol;
        end
    end

    // 空闲且未中止时接受下一个系数块
    assign o_block_ready = !STREAM_INPUT_ENABLE && i_rst_n && (state == S_IDLE) && !i_abort &&
                           (!byte_valid_reg || i_byte_ready);
    assign o_token_ready = STREAM_INPUT_ENABLE && i_rst_n && !i_abort &&
        state != S_ABORT && (!pending_valid || pending_launch) &&
        (!collector_closed || collecting);
    assign o_idle = i_rst_n && (state == S_IDLE) && !byte_valid_reg &&
                    !hold_valid && (reservoir_count == 0) && !stuffing_pending &&
                    !dc_pending_valid && !search_valid && ac_pipeline_empty &&
                    !collecting && !pending_valid;

    // 平衡树查找前两个尚未消费的非零位置
    // 显式有效位避免每层使用宽哨兵比较
    // 固定索引叶节点同时提供系数；下一个扫描索引只在根节点计算
    // 寻找每段交流系数中的首个非零位置
    always @(*) begin
        for (tree_index=0; tree_index<64; tree_index=tree_index+1) begin
            tree_first_valid[64+tree_index] = nonzero_mask[tree_index];
            tree_first[64+tree_index] = tree_index[6:0];
            tree_first_coeff[64+tree_index] = BANKED_STORAGE ? 16'sd0 :
                coeffs[tree_index*16 +: 16];
            tree_second_valid[64+tree_index] = 1'b0;
            tree_second[64+tree_index] = 7'd0;
            tree_second_coeff[64+tree_index] = 16'sd0;
        end
        for (tree_index=63; tree_index>0; tree_index=tree_index-1) begin
            if (tree_first_valid[2*tree_index]) begin
                tree_first_valid[tree_index] = 1'b1;
                tree_first[tree_index] = tree_first[2*tree_index];
                tree_first_coeff[tree_index] =
                    tree_first_coeff[2*tree_index];
            end else begin
                tree_first_valid[tree_index] =
                    tree_first_valid[2*tree_index+1];
                tree_first[tree_index] = tree_first[2*tree_index+1];
                tree_first_coeff[tree_index] =
                    tree_first_coeff[2*tree_index+1];
            end
            if (tree_second_valid[2*tree_index]) begin
                tree_second_valid[tree_index] = 1'b1;
                tree_second[tree_index] = tree_second[2*tree_index];
                tree_second_coeff[tree_index] =
                    tree_second_coeff[2*tree_index];
            end else if (tree_first_valid[2*tree_index]) begin
                tree_second_valid[tree_index] =
                    tree_first_valid[2*tree_index+1];
                tree_second[tree_index] = tree_first[2*tree_index+1];
                tree_second_coeff[tree_index] =
                    tree_first_coeff[2*tree_index+1];
            end else begin
                tree_second_valid[tree_index] =
                    tree_second_valid[2*tree_index+1];
                tree_second[tree_index] = tree_second[2*tree_index+1];
                tree_second_coeff[tree_index] =
                    tree_second_coeff[2*tree_index+1];
            end
        end
    end

    // 两个符号从同一树根快照并行规划
    // 有效计数之外的描述字段使用定义好的默认值
    // 两个根索引各计算一次 p+1，不改变同拍双符号调度
    // 规划零游程和非零系数码字
    always @(*) begin
        pair_plan_count = 2'd0;
        pair_plan_kind[0] = 2'd0;
        pair_plan_kind[1] = 2'd0;
        pair_plan_run[0] = 4'd0;
        pair_plan_run[1] = 4'd0;
        pair_plan_coeff[0] = 16'sd0;
        pair_plan_coeff[1] = 16'sd0;
        pair_plan_index[0] = 6'd0;
        pair_plan_index[1] = 6'd0;
        pair_plan_next_scan = scan_index;
        pair_plan_done = 1'b0;
        if (scan_index == 7'd64) begin
            pair_plan_done = 1'b1;
        end else if (!tree_first_valid[1]) begin
            pair_plan_count = 2'd1;
            pair_plan_next_scan = 7'd64;
            pair_plan_done = 1'b1;
        end else if (first_gap_limits[1]) begin
            pair_plan_count = 2'd2;
            pair_plan_kind[0] = 2'd1;
            pair_plan_kind[1] = 2'd1;
            pair_plan_next_scan = scan_index + 7'd32;
        end else if (first_gap_limits[0]) begin
            pair_plan_count = 2'd2;
            pair_plan_kind[0] = 2'd1;
            pair_plan_kind[1] = 2'd2;
            pair_plan_run[1] = pair_first_gap[3:0];
            pair_plan_coeff[1] = tree_first_coeff[1];
            pair_plan_index[1] = tree_first[1][5:0];
            pair_plan_next_scan = first_after;
            pair_plan_done = (first_after == 7'd64);
        end else begin
            pair_plan_count = 2'd1;
            pair_plan_kind[0] = 2'd2;
            pair_plan_run[0] = pair_first_gap[3:0];
            pair_plan_coeff[0] = tree_first_coeff[1];
            pair_plan_index[0] = tree_first[1][5:0];
            pair_plan_next_scan = first_after;
            if (first_after == 7'd64) begin
                pair_plan_done = 1'b1;
            end else if (!tree_second_valid[1]) begin
                pair_plan_count = 2'd2;
                pair_plan_next_scan = 7'd64;
                pair_plan_done = 1'b1;
            end else if (second_gap_limits[0]) begin
                pair_plan_count = 2'd2;
                pair_plan_kind[1] = 2'd1;
                pair_plan_next_scan = first_after + 7'd16;
            end else begin
                pair_plan_count = 2'd2;
                pair_plan_kind[1] = 2'd2;
                pair_plan_run[1] = pair_second_gap[3:0];
                pair_plan_coeff[1] = tree_second_coeff[1];
                pair_plan_index[1] = tree_second[1][5:0];
                pair_plan_next_scan = second_after;
                pair_plan_done = (second_after == 7'd64);
            end
        end
    end

    // 按输出握手推进熵编码状态与位储备
    always @(posedge i_clk) begin
        if (!i_rst_n) begin
            state <= S_IDLE;
            if (!BANKED_STORAGE) coeffs <= 0;
            component <= 0;
            frame_last <= 0;
            capture_id <= 0;
            token_header <= 0;
            token_batch <= 0;
            collecting <= 0;
            pending_valid <= 0;
            collector_closed <= 0;
            pending_nonzero_mask <= 0;
            token_frame_active <= 0;
            token_frame_header <= 0;
            block_index <= 0;
            restart_interval <= 0;
            restart_last_count <= 0;
            restart_count <= 0;
            restart_marker <= 0;
            pred_y <= 0;
            pred_cb <= 0;
            pred_cr <= 0;
            dc_diff_reg <= 0;
            scan_index <= 0;
            reservoir <= 0;
            reservoir_count <= 0;
            stuffing_pending <= 0;
            hold_valid <= 0;
            hold_byte <= 0;
            pad_done <= 0;
            nonzero_mask <= 0;
            dc_pending_valid <= 0;
            dc_pending_length <= 0;
            dc_pending_bits <= 0;
            search_valid <= 0;
            search_done <= 0;
            search_count <= 0;
            ac1_valid <= 0;
            ac1_count <= 0;
            ac2_valid <= 0;
            ac2_count <= 0;
            ac3_valid <= 0;
            ac3_count <= 0;
            ac4_valid <= 0;
            ac4_bits <= 0;
            ac4_length <= 0;
            byte_valid_reg <= 0;
            o_byte <= 0;
            o_byte_last <= 0;
            entropy_done_reg <= 0;
            error_valid_reg <= 0;
            o_error_capture_id <= 0;
            o_error_code <= 0;
            // 临时表达式在有效分支使用前均已赋值
            // 只复位架构状态，复位这些临时量会在算术和追加路径前增加复位多路选择
        end else begin
            entropy_done_reg <= 0;
            error_valid_reg <= 0;
            if (byte_valid_reg && i_byte_ready) begin
                byte_valid_reg <= 0;
                if (o_byte_last) begin
                    o_byte_last <= 0;
                    if (!i_abort && state != S_ABORT)
                        entropy_done_reg <= 1;
                end
            end
            if (i_abort || state == S_ABORT) begin
                state <= S_ABORT;
                reservoir <= 0;
                reservoir_count <= 0;
                stuffing_pending <= 0;
                hold_valid <= 0;
                pad_done <= 0;
                dc_pending_valid <= 0;
                search_valid <= 0;
                search_done <= 0;
                ac1_valid <= 0;
                ac2_valid <= 0;
                ac3_valid <= 0;
                ac4_valid <= 0;
                pred_y <= 0;
                pred_cb <= 0;
                pred_cr <= 0;
                token_frame_active <= 0;
                token_batch <= 0;
                collecting <= 0;
                pending_valid <= 0;
                collector_closed <= 0;
                restart_count <= 0;
                restart_marker <= 0;
                entropy_done_reg <= 0;
                if (!byte_valid_reg || i_byte_ready) begin
                    byte_valid_reg <= 0;
                    o_byte_last <= 0;
                    state <= S_IDLE;
                end
            end else begin
                byte_generated = 0;

                // 每次排出完整字节，包括填充的零字节
                // 延迟保留一字节以准确标识真正末字节的 o_byte_last
                if (!byte_valid_reg || i_byte_ready) begin
                    if (stuffing_pending) begin
                        next_byte = 0;
                        stuffing_pending <= 0;
                        byte_generated = 1;
                    end else if (reservoir_count >= 8) begin
                        next_byte = reservoir[63:56];
                        byte_generated = 1;
                        if (next_byte == 8'hff) stuffing_pending <= 1;
                    end
                    if (byte_generated) begin
                        if (hold_valid) begin
                            o_byte <= hold_byte;
                            byte_valid_reg <= 1;
                            o_byte_last <= 0;
                        end
                        hold_byte <= next_byte;
                        hold_valid <= 1;
                    end
                end

                case (state)
                    S_IDLE: begin end
                    S_DC: if (count_after_drain <= 32) begin
                        dc_diff = dc_diff_reg;
                        absolute_dc = dc_diff < 0 ? -dc_diff : dc_diff;
                        magnitude = 0;
                        for (n=0; n<17; n=n+1)
                            if (absolute_dc[n]) magnitude = n+1;
                        lookup = component == 0 ? huff_dc_y({3'b0,magnitude}) :
                                                  huff_dc_c({3'b0,magnitude});
                        if (magnitude > 11 || lookup[20:16] == 0) begin
                            error_valid_reg <= 1;
                            o_error_capture_id <= capture_id;
                            o_error_code <= 8'd2;
                            state <= S_ABORT;
                        end else begin
                            amplitude = dc_diff < 0 ?
                                        (dc_diff[15:0]-16'd1) :
                                        dc_diff[15:0];
                            // DC 准备阶段不得驱动追加侧临时量
                            dc_pending_length <= lookup[20:16] + magnitude;
                            dc_pending_bits <=
                                ({16'd0,lookup[15:0]} << magnitude) |
                                (amplitude & ((16'd1 << magnitude)-1));
                            dc_pending_valid <= 1;
                            if (component == 0) pred_y <= working_dc;
                            else if (component == 1) pred_cb <= working_dc;
                            else pred_cr <= working_dc;
                            state <= S_AC;
                        end
                    end
                    S_AC: begin
                        // 寄存的 DC 码字在首次 AC 搜索推进时追加
                        // 此时 AC 追加级仍为空，因此两处写入不会在同周期争用位储备
                        if (dc_pending_valid) begin
                            dc_pending_valid <= 0;
                        end
                        // 零游程搜索连接四级弹性 AC 流水线
                        // 避免形成查表、移位、合并、追加的单条组合链
                        if (ac2_error) begin
                            error_valid_reg <= 1;
                            o_error_capture_id <= capture_id;
                            o_error_code <= 8'd3;
                            state <= S_ABORT;
                        end else begin
                            // S1 计算类别、幅值及 Huffman 地址
                            if (ac1_accept) begin
                                ac1_valid <= search_valid;
                                if (search_valid) begin
                                    ac1_count <= search_count;
                                    for (k=0; k<2; k=k+1) begin
                                        ac1_kind[k] <= search_kind[k];
                                        if (search_kind[k] == 2) begin
                                            // For negative n, ~(n-1) equals |n| and the
                                            // low category bits of n-1 are the JPEG payload.
                                            ac1_adjusted = search_coeff[k][10:0] - search_coeff[k][15];
                                            ac1_absolute = ac1_adjusted ^ {11{search_coeff[k][15]}};
                                            ac1_out_of_range = ((|search_coeff[k][15:10]) &&
                                                !(&search_coeff[k][15:10])) || ac1_absolute[10];
                                            ac1_magnitude_next = 0;
                                            for (n=0; n<10; n=n+1)
                                                if (ac1_absolute[n]) ac1_magnitude_next = n+1;
                                            if (ac1_out_of_range) ac1_magnitude_next = 4'd11;
                                            ac1_amplitude_next = ac1_adjusted[9:0];
                                            ac1_addr[k] <= {search_run[k],
                                                ac1_magnitude_next[3:0]};
                                            ac1_magnitude[k] <=
                                                ac1_magnitude_next;
                                            ac1_amplitude[k] <=
                                                ac1_amplitude_next;
                                        end else begin
                                            ac1_addr[k] <=
                                                (search_kind[k] == 1) ?
                                                8'hf0 : 8'h00;
                                            ac1_magnitude[k] <= 5'd0;
                                            ac1_amplitude[k] <= 16'd0;
                                        end
                                    end
                                end
                            end
                            // S2 使用寄存地址读取 Huffman 表
                            if (ac2_accept) begin
                                ac2_valid <= ac1_valid;
                                if (ac1_valid) begin
                                    ac2_count <= ac1_count;
                                    for (k=0; k<2; k=k+1) begin
                                        ac2_kind[k] <= ac1_kind[k];
                                        ac2_magnitude[k] <= ac1_magnitude[k];
                                        ac2_amplitude[k] <= ac1_amplitude[k];
                                        if (!STREAM_INPUT_ENABLE) begin
                                            ac2_lookup = component == 0 ?
                                                huff_ac_y(ac1_addr[k]) : huff_ac_c(ac1_addr[k]);
                                            ac2_legacy_code[k] <= ac2_lookup[15:0];
                                            ac2_legacy_length[k] <= ac2_lookup[20:16];
                                        end
                                    end
                                end
                            end
                            // S3 合并码字与幅值形成单个符号位串
                            if (ac3_accept) begin
                                ac3_valid <= ac2_valid;
                                if (ac2_valid) begin
                                    ac3_count <= ac2_count;
                                    for (k=0; k<2; k=k+1) begin
                                        if (ac2_kind[k] == 2) begin
                                            ac3_bits[k] <=
                                                ({10'd0, ac2_code[k]} <<
                                                 ac2_magnitude[k]) |
                                                ({16'd0,ac2_amplitude[k]} &
                                                 {16'd0,((10'd1 << ac2_magnitude[k])-10'd1)});
                                            ac3_length[k] <=
                                                {1'b0, ac2_length[k]} +
                                                {1'b0, ac2_magnitude[k]};
                                        end else begin
                                            ac3_bits[k] <=
                                                {10'd0, ac2_code[k]};
                                            ac3_length[k] <=
                                                {1'b0, ac2_length[k]};
                                        end
                                    end
                                end
                            end
                            // S4 concatenates the pair with one shifter; capacity/handshake is unchanged.
                            if (ac4_accept) begin
                                ac4_valid <= ac3_valid;
                                if (ac3_valid) begin
                                    if (ac3_count == 2) begin
                                        ac4_bits <=
                                            ({26'd0,ac3_bits[0]} << ac3_length[1]) |
                                            {26'd0,ac3_bits[1]};
                                        ac4_length <=
                                            {1'b0, ac3_length[0]} +
                                            {1'b0, ac3_length[1]};
                                    end else begin
                                        ac4_bits <= {26'd0,ac3_bits[0]};
                                        ac4_length <=
                                            {1'b0, ac3_length[0]};
                                    end
                                end
                            end
                            // S5 数据追加由组合下一状态块执行
                            // 上面的 S4 负责产生下一周期的 ac4_valid
                            if (search_advance) search_valid <= 0;
                        end
                        if (search_space && !search_done) begin
                            search_kind[0] <= pair_plan_kind[0];
                            search_kind[1] <= pair_plan_kind[1];
                            search_run[0] <= pair_plan_run[0];
                            search_run[1] <= pair_plan_run[1];
                            if (!BANKED_STORAGE) begin
                                legacy_search_coeff[0] <= pair_plan_coeff[0];
                                legacy_search_coeff[1] <= pair_plan_coeff[1];
                            end
                            scan_index <= pair_plan_next_scan;
                            // 常量比较使综合能在无需可变掩码移位的情况下清除选定项
                            // 仅在规划被接受时更新，流水线停顿不会重复消费
                            for (n=0; n<64; n=n+1) begin
                                if ((pair_consumes_first &&
                                     tree_first[1] == n[6:0]) ||
                                    (pair_consumes_second &&
                                     tree_second[1] == n[6:0]))
                                    nonzero_mask[n] <= 1'b0;
                            end
                            if (pair_plan_count != 0) begin
                                search_count <= pair_plan_count;
                                search_valid <= 1;
                            end
                            if (pair_plan_done) search_done <= 1;
                        end
                        if (search_done && !search_valid && ac_pipeline_empty)
                            state <= S_BLOCK;
                    end
                    S_BLOCK: begin
                        if (frame_last) state <= S_FINISH;
                        else if (RESTART_ENABLE && block_index == 3 && restart_interval != 0 &&
                                 restart_count == restart_last_count) begin
                            pad_done <= 0;
                            state <= S_RESTART_PAD;
                        end else begin
                            if (RESTART_ENABLE && block_index == 3)
                                restart_count <= restart_count + 1'b1;
                            state <= S_IDLE;
                        end
                    end
                    S_RESTART_PAD: begin
                        if (!pad_done) pad_done <= 1;
                        else if (count_after_drain == 0 && !stuffing_pending && !byte_generated &&
                                 (!byte_valid_reg || i_byte_ready)) begin
                            if (hold_valid) begin
                                o_byte <= hold_byte;
                                byte_valid_reg <= 1;
                                o_byte_last <= 0;
                                hold_valid <= 0;
                            end
                            state <= S_RESTART_FF;
                        end
                    end
                    S_RESTART_FF: if (!byte_valid_reg || i_byte_ready) begin
                        o_byte <= 8'hff;
                        byte_valid_reg <= 1;
                        o_byte_last <= 0;
                        state <= S_RESTART_ID;
                    end
                    S_RESTART_ID: if (byte_valid_reg && i_byte_ready) begin
                        o_byte <= {5'b11010, restart_marker};
                        byte_valid_reg <= 1;
                        o_byte_last <= 0;
                        state <= S_RESTART_DONE;
                    end
                    S_RESTART_DONE: if (byte_valid_reg && i_byte_ready) begin
                        pred_y <= 0;
                        pred_cb <= 0;
                        pred_cr <= 0;
                        restart_count <= 0;
                        restart_marker <= restart_marker + 1'b1;
                        pad_done <= 0;
                        state <= S_IDLE;
                    end
                    S_FINISH: begin
                        if (!pad_done) begin
                            pad_done <= 1;
                        end else if (count_after_drain == 0 && !stuffing_pending &&
                                     !byte_generated && hold_valid &&
                                     (!byte_valid_reg || i_byte_ready)) begin
                            o_byte <= hold_byte;
                            byte_valid_reg <= 1;
                            o_byte_last <= 1;
                            hold_valid <= 0;
                            state <= S_FINAL;
                        end
                    end
                    S_FINAL: if (byte_valid_reg && i_byte_ready) begin
                        state <= S_IDLE;
                        pad_done <= 0;
                        token_frame_active <= 0;
                        collector_closed <= 0;
                    end
                    default: state <= S_ABORT;
                endcase

                // A complete vector replaces only retired working coefficients.
                // Loading at an ordinary BLOCK boundary hides the old IDLE/LOAD
                // dispatch cycle; restart retirement must first clear predictors.
                if (load_working_block) begin
                    if (!BANKED_STORAGE) coeffs <= accepted_coeffs;
                    component <= accepted_component;
                    block_index <= accepted_block;
                    frame_last <= accepted_last;
                    capture_id <= accepted_capture;
                    if (first_block)
                        dc_diff_reg <= $signed({accepted_dc[15],accepted_dc});
                    else if (accepted_component == 0)
                        dc_diff_reg <= $signed({accepted_dc[15],accepted_dc}) -
                                       $signed({pred_y[15],pred_y});
                    else if (accepted_component == 1)
                        dc_diff_reg <= $signed({accepted_dc[15],accepted_dc}) -
                                       $signed({pred_cb[15],pred_cb});
                    else
                        dc_diff_reg <= $signed({accepted_dc[15],accepted_dc}) -
                                       $signed({pred_cr[15],pred_cr});
                    scan_index <= 7'd1;
                    dc_pending_valid <= 0;
                    search_valid <= 0;
                    search_done <= 0;
                    ac1_valid <= 0;
                    ac2_valid <= 0;
                    ac3_valid <= 0;
                    ac4_valid <= 0;
                    if (STREAM_INPUT_ENABLE) begin
                        nonzero_mask <= pending_nonzero_mask;
                        pending_valid <= 0;
                    end else begin
                        for (n=1; n<64; n=n+1)
                            nonzero_mask[n] <= (accepted_coeffs[n*16 +: 16] != 0);
                    end
                    if (first_block) begin
                        pred_y <= 0;
                        pred_cb <= 0;
                        pred_cr <= 0;
                        if (!STREAM_INPUT_ENABLE) begin
                            restart_interval <= RESTART_ENABLE ? i_restart_mcus : 16'd0;
                            restart_last_count <= (RESTART_ENABLE && i_restart_mcus != 0) ?
                                                  i_restart_mcus - 16'd1 : 16'd0;
                        end
                        restart_count <= 0;
                        restart_marker <= 0;
                    end
                    if (accepted_component > 2) begin
                        error_valid_reg <= 1;
                        o_error_capture_id <= accepted_capture;
                        o_error_code <= 8'd1;
                        state <= S_ABORT;
                    end else state <= S_DC;
                end

                // Independent HEADER/eight-DATA collector. No second frame may
                // be prefetched past the first final HEADER until FINAL retires.
                // Validation is last so a malformed prefetched token overrides
                // an active-state transition without losing the visible byte.
                if (i_token_valid && o_token_ready) begin
                    if (!collecting) begin
                        if (token_header_bad) begin
                            error_valid_reg <= 1;
                            o_error_capture_id <= token_frame_active ? token_frame_header[31:0] : i_token_data[31:0];
                            o_error_code <= 8'd4;
                            state <= S_ABORT;
                        end else begin
                            token_header <= i_token_data;
                            token_batch <= 0;
                            collecting <= 1;
                            pending_valid <= 0;
                            pending_nonzero_mask <= 0;
                            collector_closed <= i_token_data[118];
                            if (!token_frame_active) begin
                                token_frame_header <= i_token_data;
                                token_frame_active <= 1;
                                restart_interval <= RESTART_ENABLE ? i_restart_mcus : 16'd0;
                                restart_last_count <= (RESTART_ENABLE && i_restart_mcus != 0) ?
                                                      i_restart_mcus - 16'd1 : 16'd0;
                            end
                        end
                    end else if (token_data_bad) begin
                        error_valid_reg <= 1;
                        o_error_capture_id <= token_frame_header[31:0];
                        o_error_code <= 8'd4;
                        state <= S_ABORT;
                    end else begin
                        for (n=0; n<8; n=n+1)
                            pending_nonzero_mask[token_batch*8+n] <=
                                (token_batch != 0 || n != 0) && i_token_data[n*16 +:16] != 0;
                        if (token_batch == 7) begin
                            pending_valid <= 1;
                            collecting <= 0;
                        end else token_batch <= token_batch + 1'b1;
                    end
                end
                reservoir <= bits_work;
                reservoir_count <= count_work;
            end
        end
    end
endmodule
