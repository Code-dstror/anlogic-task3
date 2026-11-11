// Four-pixel/clock temporal global histogram equalization.
// A frame uses an atomically selected LUT from a previously completed frame;
// it never claims same-frame equalization without a full-frame store.
module preprocess_hist_eq4 #(
    parameter MAX_WIDTH = 3840,
    parameter MAX_HEIGHT = 2160,
    parameter integer EXTERNAL_LUMA_ENABLE = 0,
    parameter integer HISTORY_RESET_ENABLE = 0,
    parameter integer SOURCE_QUALIFY_ENABLE = 0,
    parameter integer FIXED_CONFIG_SESSION_ENABLE = 0,
    parameter integer HE_COLOR_PRESERVE = 0,
    parameter integer STEREO_HISTORY_ENABLE = 0,
    parameter integer RESET_ALL_EYES_ON_GEOMETRY_CHANGE = 0
) (
    input clk,
    input rst_n,
    input clear,
    input enable,
    input [12:0] width,
    input [12:0] height,
    input s_valid,
    output s_ready,
    input [95:0] s_data,
    input s_sof,
    input s_eol,
    output m_valid,
    input m_ready,
    output [95:0] m_data,
    output m_sof,
    output m_eol,
    output wire lut_valid,
    output wire [31:0] lut_epoch,
    output reg [31:0] stats_skipped_frames,
    input wire [31:0] s_luma,
    input wire history_reset,
    output wire [31:0] m_luma,
    output wire statistics_error,
    output reg [31:0] stats_overflow_count,
    input wire [141:0] s_history_context,
    input wire s_history_eligible,
    input wire [31:0] s_capture_sequence,
    input wire source_valid, source_camera, source_ok,
    input wire [31:0] source_session, source_epoch, source_capture_sequence,
    output wire o_frame_history_used, o_presented_valid, o_divider_ready,
    output wire o_frame_started, o_source_ready,
    output wire o_source_owner_match, o_source_accepted,
    output wire o_source_decision_valid, o_source_decision_collect,
    output wire [31:0] o_source_decision_capture,
    output wire o_source_cancel_done,
    output reg [31:0] stats_unqualified_frames, stats_source_rejects, stats_canceled_jobs
);
    localparam BG_IDLE = 4'd0, BG_DRAIN = 4'd1, BG_READ = 4'd2,
               BG_PAIR = 4'd3, BG_SUM = 4'd4, BG_ACCUM = 4'd5,
               BG_PREP = 4'd6, BG_DIV = 4'd7, BG_WRITE = 4'd8,
               BG_IDENTITY = 4'd9, BG_CLEAR = 4'd10, BG_NUM = 4'd11,
               BG_DIV_WAIT = 4'd12;
    wire cancel_statistics;
    reg initializing;
    reg [8:0] init_addr;
    reg history_request_seen, geometry_valid;
    reg [12:0] history_width, history_height;
    // A complete eye-frame owns the foreground. Only the two eyes' persistent
    // history and LUT address pages are private. Counters, histogram banks,
    // divider and color reconstruction are still a single pipeline.
    localparam EYES = STEREO_HISTORY_ENABLE ? 2 : 1;
    wire eye = STEREO_HISTORY_ENABLE && s_history_context[3];
    reg [141:0] eye_context [0:EYES-1];
    reg [EYES-1:0] context_valid, context_eligible;
    reg [31:0] high_water [0:EYES-1];
    wire [141:0] cohort_context = eye_context[eye];
    wire cohort_valid = context_valid[eye];
    wire cohort_history_eligible = context_eligible[eye];
    wire requested_history_eligible = FIXED_CONFIG_SESSION_ENABLE ? s_history_eligible : s_history_context[0];
    wire cohort_changed = s_history_context != cohort_context ||
                          requested_history_eligible != cohort_history_eligible;
    reg [31:0] capture_pipe0, capture_pipe1;
    wire [31:0] capture_high_water = high_water[eye];
    reg [1:0] bank_source_seen, bank_source_ok;
    reg frame_history_used;
    reg capture_eligible0,capture_eligible1;
    wire capture_eligible = !cohort_valid || cohort_changed ||
                            s_capture_sequence > capture_high_water;
    wire context_changed = SOURCE_QUALIFY_ENABLE && cohort_valid &&
        (cohort_changed || s_capture_sequence <= capture_high_water);
    wire first_group_inflight;
    wire geometry_changed = geometry_valid && (width != history_width || height != history_height);
    wire wants_history_reset = ((HISTORY_RESET_ENABLE || SOURCE_QUALIFY_ENABLE) &&
        (history_reset || geometry_changed)) || context_changed;
    // A new cohort waits for old pixel tokens; it never cancels a held output.
    // One pending SOF slot also prevents the just-accepted ID from comparing
    // against itself before its input owner advances to the next beat.
    wire history_request = s_valid && s_sof && !history_request_seen && !first_group_inflight &&
        wants_history_reset && (!SOURCE_QUALIFY_ENABLE || !o_presented_valid);
    // Qualified cohort comparison ends at this register, before the broad
    // history clear fanout. SOF remains blocked until this pulse completes.
    reg history_flush;
    always @(posedge clk) begin
        if (!rst_n || clear || history_flush) history_flush <= 1'b0;
        else history_flush <= history_request && !initializing;
    end
    wire reset_history = SOURCE_QUALIFY_ENABLE ? history_flush :
                         (history_request && !initializing);
    wire reset_all_eyes = RESET_ALL_EYES_ON_GEOMETRY_CHANGE && reset_history && geometry_changed;
    reg [1:0] bank_free, bank_full;
    reg collecting, collect_bank;
    reg [12:0] row_index, frame_height;
    reg [23:0] frame_pixels;
    reg [31:0] frame_sequence, frame_epoch;
    reg [23:0] bank_total0, bank_total1;
    reg [31:0] bank_epoch0, bank_epoch1;

    reg [3:0] bg_state;
    reg bg_bank, build_lut_bank, next_bg_bank;
    reg [7:0] bg_bin;
    reg [23:0] bg_total, pair01, pair23, bin_total, cdf, cdf_min;
    reg min_found;
    reg [31:0] bg_epoch;
    reg [23:0] denominator, cdf_delta_reg;
    reg [31:0] numerator;
    reg [7:0] lut_write_value;
    reg [1:0] bank_eye;
    reg bg_eye;
    reg [EYES-1:0] active_page, active_valid, pending_valid;
    reg [31:0] active_sequence [0:EYES-1];
    reg [31:0] pending_sequence [0:EYES-1];
    wire active_lut_bank = active_page[eye];
    wire pending_lut = pending_valid[eye];
    wire [31:0] pending_epoch = pending_sequence[eye];
    assign lut_epoch = active_sequence[eye];
    assign lut_valid = active_valid[eye];

    reg [3:0] pipe_valid;
    reg [3:0] pipe_sof, pipe_eol, pipe_enable;
    reg [95:0] rgb0, rgb1, rgb2, rgb3, original_rgb3;
    reg [31:0] original_luma3, mapped_luma3;
    reg apply3;
    wire core_ready, color_busy;
    wire core_valid = pipe_valid[3] && rst_n && !clear && (!SOURCE_QUALIFY_ENABLE || !reset_history);
    reg [31:0] external_luma0;
    reg [15:0] prod_r [0:3];
    reg [15:0] prod_g [0:3];
    reg [15:0] prod_b [0:3];
    reg [15:0] luma_sum [0:3];
    reg [7:0] luma2 [0:3];
    wire [31:0] hist_bins = {luma_sum[3][15:8], luma_sum[2][15:8],
                        luma_sum[1][15:8], luma_sum[0][15:8]};
    wire advance = !pipe_valid[3] || core_ready;
    assign first_group_inflight = SOURCE_QUALIFY_ENABLE && pipe_valid[0] && pipe_sof[0];
    assign s_ready = !initializing && !clear && !history_request && rst_n && advance &&
        (!SOURCE_QUALIFY_ENABLE || !cancel_statistics) &&
        !(SOURCE_QUALIFY_ENABLE && s_sof && (o_presented_valid || first_group_inflight ||
          (!history_request_seen && wants_history_reset)));
    assign o_frame_history_used = frame_history_used;
    assign o_presented_valid = (|pipe_valid) || color_busy;
    generate if (HE_COLOR_PRESERVE) begin : g_color
        wire color_ready;
        reg [3:0] color_tokens;
        assign core_ready = color_ready;
        assign color_busy = color_tokens != 0;
        preprocess_he_color4 u_color (
            .clk(clk),.rst_n(rst_n),.clear(clear || reset_history),.enable(apply3),
            .s_valid(core_valid),.s_ready(color_ready),.s_data(original_rgb3),
            .s_luma(original_luma3),.s_mapped_luma(mapped_luma3),
            .s_sof(pipe_sof[3]),.s_eol(pipe_eol[3]),
            .m_valid(m_valid),.m_ready(m_ready),.m_data(m_data),.m_luma(m_luma),
            .m_sof(m_sof),.m_eol(m_eol),.m_enable());
        always @(posedge clk) begin
            if (!rst_n || clear || reset_history) color_tokens <= 0;
            else case ({core_valid && color_ready,m_valid && m_ready})
                2'b10: color_tokens <= color_tokens + 1'b1;
                2'b01: color_tokens <= color_tokens - 1'b1;
                default: color_tokens <= color_tokens;
            endcase
        end
    end else begin : g_legacy
        assign core_ready=m_ready; assign color_busy=1'b0;
        assign m_valid=core_valid; assign m_data=rgb3; assign m_luma=mapped_luma3;
        assign m_sof=pipe_sof[3]; assign m_eol=pipe_eol[3];
    end endgenerate
    wire process_beat = advance && pipe_valid[1] && !clear && rst_n;
    assign o_frame_started = process_beat && pipe_sof[1];
    assign o_source_ready = rst_n && !initializing && !clear && !reset_history;
    wire chosen_bank = bank_free[0] ? 1'b0 : 1'b1;
    wire metadata_qualified = !SOURCE_QUALIFY_ENABLE || (cohort_valid && cohort_history_eligible &&
        cohort_context[29:17] == width && cohort_context[16:4] == height && capture_eligible1);
    wire can_collect = pipe_sof[1] ? ((|bank_free) && metadata_qualified) : collecting;
    wire selected_bank = pipe_sof[1] ? chosen_bank : collect_bank;
    wire frame_last = pipe_eol[1] &&
                      (pipe_sof[1] ? (height == 13'd1)
                       : (row_index == frame_height - 13'd1));
    wire collect_beat = process_beat && can_collect;
    wire [23:0] completed_pixels = pipe_sof[1] ? 24'd4 : frame_pixels + 24'd4;
    wire [31:0] completed_epoch = pipe_sof[1] ?
        (SOURCE_QUALIFY_ENABLE ? capture_pipe1 : frame_sequence + 32'd1) : frame_epoch;
    wire [31:0] pending_age = capture_pipe1 - pending_epoch;
    wire [31:0] active_age = capture_pipe1 - lut_epoch;
    wire pending_eligible = pending_lut && metadata_qualified &&
        capture_pipe1 > pending_epoch && pending_age <= 4;
    wire active_eligible = lut_valid && metadata_qualified &&
        capture_pipe1 > lut_epoch && active_age <= 4;
    wire select_pending = SOURCE_QUALIFY_ENABLE ?
        (pending_eligible && (!active_eligible || pending_epoch > lut_epoch)) : pending_lut;
    wire history_for_sof = SOURCE_QUALIFY_ENABLE ?
        (pending_eligible || active_eligible) : (lut_valid || pending_lut);
    wire read_lut_bank = (pipe_sof[1] && select_pending) ? !active_lut_bank : active_lut_bank;
    wire read_lut_valid = SOURCE_QUALIFY_ENABLE ?
        (pipe_sof[1] ? history_for_sof : frame_history_used) : (lut_valid || (pipe_sof[1] && pending_lut));
    reg mapped_valid2;
    wire [31:0] mapped_pixels;
    wire lut_wr_en = (bg_state == BG_WRITE || bg_state == BG_IDENTITY)
                    && !initializing && !cancel_statistics && rst_n;
    wire [7:0] lut_wr_data = bg_state == BG_IDENTITY ? bg_bin : lut_write_value;
    wire [95:0] bg_counts;
    wire [3:0] lane_overflow;
    reg collect_write_pending;
    reg divide_error;
    assign statistics_error = (|lane_overflow) || divide_error;
    wire source_eye = STEREO_HISTORY_ENABLE && source_camera;
    wire [141:0] source_cohort = eye_context[source_eye];
    wire source_key_match = SOURCE_QUALIFY_ENABLE && context_valid[source_eye] &&
        context_eligible[source_eye] && source_camera == source_eye &&
        source_session == source_cohort[141:110] && source_epoch == source_cohort[109:78];
    wire source_match0 = source_key_match && source_eye == bank_eye[0] && !bank_free[0] &&
        source_capture_sequence == bank_epoch0 && !bank_source_seen[0];
    wire source_match1 = source_key_match && source_eye == bank_eye[1] && !bank_free[1] &&
        source_capture_sequence == bank_epoch1 && !bank_source_seen[1];
    wire source_accept = source_valid && !initializing && !clear && !reset_history &&
        (source_match0 || source_match1);
    wire source_negative = source_accept && !source_ok;
    // Exact current SOURCE tuple match, independent of SOURCE valid/ready.
    assign o_source_owner_match = o_source_ready && (source_match0 || source_match1);
    assign o_source_accepted = source_accept;
    assign o_source_decision_valid = SOURCE_QUALIFY_ENABLE && o_frame_started;
    assign o_source_decision_collect = (|bank_free) && metadata_qualified;
    assign o_source_decision_capture = completed_epoch;

    assign cancel_statistics = clear || reset_history || statistics_error || source_negative;
    wire [1:0] buildable = bank_full & (SOURCE_QUALIFY_ENABLE ?
        (bank_source_seen & bank_source_ok) : 2'b11);
    wire background_read = bg_state == BG_READ && !collect_beat;
    wire background_clear = bg_state == BG_CLEAR && !collect_write_pending;
    // Each lane has a private bin RAM. BG_PAIR/BG_SUM later add all four
    // counts for the selected bin; equal pixels in one group need no merge.
    wire [23:0] cdf_delta = cdf - cdf_min;
    // Prefer the bank following the last processed bank. If both are full,
    // that bank necessarily contains the older of the two sequential frames.
    wire [1:0] build_ready = buildable & { !pending_valid[bank_eye[1]], !pending_valid[bank_eye[0]] };
    wire next_job_bank = build_ready[next_bg_bank] ? next_bg_bank : !next_bg_bank;

    // Stage3 business-specific exact divider: one owned request, no pixel CE.
    localparam DIV_RESET=2'd0,DIV_DRAIN=2'd1,DIV_READY=2'd2;
    reg [1:0] divider_phase;
    reg [5:0] divider_wait;
    reg divide_inflight;
    assign o_source_cancel_done = rst_n && !clear && !reset_history && !initializing &&
        !o_presented_valid && !collecting && bank_free==2'b11 && bg_state==BG_IDLE && !divide_inflight;
    wire divider_reset_n = rst_n && divider_phase != DIV_RESET;
    wire divide_issue = rst_n && !cancel_statistics && !initializing &&
        bg_state == BG_DIV && divider_phase == DIV_READY && !divide_inflight && denominator != 0;
    wire [55:0] divider_result;
    wire divider_valid;
    assign o_divider_ready = divider_phase == DIV_READY && !cancel_statistics;
    stage3_he_div_32u24u_iter16 u_divider (
        .aclk(clk),.aresetn(divider_reset_n),
        .s_axis_dividend_tdata(numerator),.s_axis_dividend_tvalid(divide_issue),
        .s_axis_divisor_tdata(denominator),.s_axis_divisor_tvalid(divide_issue),
        .m_axis_dout_tdata(divider_result),.m_axis_dout_tvalid(divider_valid));
    always @(posedge clk) begin
        if (!rst_n || cancel_statistics) begin
            divider_phase<=DIV_RESET;divider_wait<=0;divide_inflight<=0;
        end else begin
            case(divider_phase)
                DIV_RESET: if(divider_wait==35) begin divider_phase<=DIV_DRAIN;divider_wait<=0;end
                    else divider_wait<=divider_wait+1'b1;
                DIV_DRAIN: if(divider_wait==35) begin divider_phase<=DIV_READY;divider_wait<=0;end
                    else divider_wait<=divider_wait+1'b1;
                default: begin end
            endcase
            if(divide_issue) divide_inflight<=1;
            if(divider_valid && divide_inflight && bg_state==BG_DIV_WAIT) divide_inflight<=0;
        end
    end

    // The cohort copy survives ordinary frame clear. Only its complete change
    // invalidates all history, so per-bank fingerprint duplication is unnecessary.
    integer ctx;
    always @(posedge clk) begin
        if(!rst_n)begin
            context_valid<=0;context_eligible<=0;
            for(ctx=0;ctx<EYES;ctx=ctx+1) begin
                eye_context[ctx]<=0;
                high_water[ctx]<=0;
            end
            stats_unqualified_frames<=0;stats_source_rejects<=0;stats_canceled_jobs<=0;
        end else begin
            if(reset_all_eyes)begin
                context_valid<=0;context_eligible<=0;
            end else if(reset_history && cohort_changed)context_valid[eye]<=0;
            if(s_valid && s_ready && s_sof && SOURCE_QUALIFY_ENABLE)begin
                eye_context[eye]<=s_history_context;context_valid[eye]<=1;
                context_eligible[eye]<=requested_history_eligible;
                if(capture_eligible)high_water[eye]<=s_capture_sequence;
            end
            if(process_beat && pipe_sof[1] && SOURCE_QUALIFY_ENABLE && !history_for_sof)
                stats_unqualified_frames<=stats_unqualified_frames+1'b1;
            if(SOURCE_QUALIFY_ENABLE && source_valid && !source_accept)
                stats_source_rejects<=stats_source_rejects+1'b1;
            if(cancel_statistics && (bg_state!=BG_IDLE || pending_lut || (|bank_full) || collecting))
                stats_canceled_jobs<=stats_canceled_jobs+1'b1;
        end
    end

    // The four-pixel input contributes at most one count per lane per
    // accepted group. UHD needs 21 bits per lane for 2,073,600 groups.
    // The 24-bit CDF and 32-bit numerator cover all 8,294,400 pixels.
    localparam integer LANE_COUNT_BITS=$clog2(((MAX_WIDTH+3)/4)*MAX_HEIGHT+1);
    localparam integer COUNT_BITS=LANE_COUNT_BITS<24 ? LANE_COUNT_BITS : 24;
    genvar lane;
    generate for (lane = 0; lane < 4; lane = lane + 1) begin : g_lane
        preprocess_hist_lane #(.COUNT_BITS(COUNT_BITS),.UNIT_INCREMENT(1)) u_hist (
            .clk(clk), .cancel(!rst_n || cancel_statistics),
            .inc_valid(collect_beat),.inc_bank(selected_bank),
            .inc_bin(hist_bins[8*lane +: 8]),.inc_amount(3'd1),
            .bg_rd_en(background_read),.bg_rd_bank(bg_bank),.bg_rd_addr(bg_bin),
            .bg_rd_data(bg_counts[24*lane +: 24]),
            .clear_en(initializing || background_clear),
            .clear_bank(initializing ? init_addr[8] : bg_bank),
            .clear_addr(initializing ? init_addr[7:0] : bg_bin),.overflow(lane_overflow[lane])
        );
        preprocess_lut_ram8x512 #(.EYES(EYES)) u_lut (
            .clk(clk),.wr_en(lut_wr_en),.wr_addr({bg_eye,build_lut_bank,bg_bin}),.wr_data(lut_wr_data),
            .rd_en(advance && pipe_valid[1]),.rd_addr({eye,read_lut_bank,hist_bins[8*lane +: 8]}),
            .rd_data(mapped_pixels[8*lane +: 8]));
    end endgenerate

    integer k;
    always @(posedge clk) begin
        if (!rst_n || clear || reset_history) begin
            pipe_valid <= 4'd0;
            pipe_sof <= 4'd0;
            pipe_eol <= 4'd0;
            pipe_enable <= 4'd0;
            mapped_valid2 <= 1'b0;
            rgb0 <= 96'd0; rgb1 <= 96'd0; rgb2 <= 96'd0; rgb3 <= 96'd0;
            external_luma0 <= 32'd0; mapped_luma3 <= 32'd0;
            original_rgb3<=0;original_luma3<=0;apply3<=0;capture_pipe0<=0;capture_pipe1<=0;
            capture_eligible0<=0;capture_eligible1<=0;
            for (k = 0; k < 4; k = k + 1) begin
                prod_r[k] <= 16'd0; prod_g[k] <= 16'd0; prod_b[k] <= 16'd0;
                luma_sum[k] <= 16'd0; luma2[k] <= 8'd0;
            end
        end else if (advance) begin
            pipe_valid <= {pipe_valid[2:0], s_valid && s_ready};
            pipe_sof <= {pipe_sof[2:0], s_sof};
            pipe_eol <= {pipe_eol[2:0], s_eol};
            pipe_enable <= {pipe_enable[2:0], enable};
            rgb0 <= s_data; rgb1 <= rgb0; rgb2 <= rgb1;
            external_luma0 <= s_luma;
            original_rgb3 <= rgb2;
            original_luma3 <= {luma2[3],luma2[2],luma2[1],luma2[0]};
            apply3 <= pipe_enable[2] && mapped_valid2;
            capture_pipe0 <= s_capture_sequence;capture_pipe1 <= capture_pipe0;
            capture_eligible0<=capture_eligible;capture_eligible1<=capture_eligible0;
            mapped_valid2 <= read_lut_valid;
            for (k = 0; k < 4; k = k + 1) begin
                prod_r[k] <= s_data[k*24+16 +: 8] * 8'd77;
                prod_g[k] <= s_data[k*24+8 +: 8] * 8'd150;
                prod_b[k] <= s_data[k*24 +: 8] * 8'd29;
                luma_sum[k] <= EXTERNAL_LUMA_ENABLE ? {external_luma0[k*8 +: 8],8'd0} :
                    (prod_r[k] + prod_g[k]) + (prod_b[k] + 16'd128);
                luma2[k] <= luma_sum[k][15:8];
                mapped_luma3[k*8 +: 8] <= pipe_enable[2] && mapped_valid2 ? mapped_pixels[k*8 +: 8] : luma2[k];
                if (!pipe_enable[2])
                    rgb3[k*24 +: 24] <= rgb2[k*24 +: 24];
                else if (mapped_valid2)
                    rgb3[k*24 +: 24] <= {3{mapped_pixels[k*8 +: 8]}};
                else
                    rgb3[k*24 +: 24] <= {3{luma2[k]}};
            end
        end
    end

    always @(posedge clk) begin
        if (!rst_n) begin
            collect_write_pending <= 1'b0; history_request_seen <= 1'b0;
            geometry_valid <= 1'b0; history_width <= 0; history_height <= 0;
            stats_overflow_count <= 0;
        end else begin
            collect_write_pending <= !cancel_statistics && collect_beat;
            if (!s_valid || !s_sof) history_request_seen <= 1'b0;
            if (reset_history) history_request_seen <= 1'b1;
            if (s_valid && s_ready && s_sof) begin
                if(SOURCE_QUALIFY_ENABLE)history_request_seen<=0;
                geometry_valid <= 1'b1; history_width <= width; history_height <= height;
            end
            if (statistics_error) stats_overflow_count <= stats_overflow_count + 1'b1;
        end
    end

    integer page;
    always @(posedge clk) begin
        if (!rst_n) begin
            active_page <= 0;active_valid <= 0;pending_valid <= 0;
            bank_eye <= 0;bg_eye <= 0;
            for(page=0;page<EYES;page=page+1) begin
                active_sequence[page]<=0;
                pending_sequence[page]<=0;
            end
            stats_skipped_frames <= 32'd0;
            initializing <= 1'b1; init_addr <= 9'd0;
            bank_free <= 2'b00; bank_full <= 2'b00;
            collecting <= 1'b0; collect_bank <= 1'b0;
            row_index <= 13'd0; frame_height <= 13'd0; frame_pixels <= 24'd0;
            frame_sequence <= 32'd0; frame_epoch <= 32'd0;
            bank_total0 <= 24'd0; bank_total1 <= 24'd0;
            bank_epoch0 <= 32'd0; bank_epoch1 <= 32'd0;
            bg_state <= BG_IDLE; bg_bank <= 1'b0; build_lut_bank <= 1'b0;
            next_bg_bank <= 1'b0;
            bg_bin <= 8'd0; bg_total <= 24'd0; bg_epoch <= 32'd0;
            pair01 <= 24'd0; pair23 <= 24'd0; bin_total <= 24'd0;
            cdf <= 24'd0; cdf_min <= 24'd0; min_found <= 1'b0;
            denominator <= 24'd0; cdf_delta_reg <= 24'd0;
            numerator <= 32'd0; lut_write_value <= 8'd0;divide_error<=0;
            bank_source_seen<=0;bank_source_ok<=0;frame_history_used<=0;
        end else if (cancel_statistics) begin
            // A failed capture cannot publish a partly built LUT. The last
            // committed mapping remains valid across this local cancellation.
            initializing <= 1'b1; init_addr <= 9'd0;
            if (reset_history) begin
                active_valid[eye] <= 0; active_sequence[eye] <= 0; active_page[eye] <= 0;
            end
            // A cold raster change invalidates either eye's previous mapping.
            if (reset_all_eyes) begin
                active_valid <= 0; active_page <= 0; pending_valid <= 0;
            end else if (!STEREO_HISTORY_ENABLE || reset_history) pending_valid[eye] <= 0;
            bank_free <= 2'b00; bank_full <= 2'b00;
            collecting <= 1'b0; row_index <= 13'd0; frame_pixels <= 24'd0;
            bg_state <= BG_IDLE; next_bg_bank <= 1'b0;
            bank_source_seen<=0;bank_source_ok<=0;divide_error<=0;
            if(clear || reset_history)frame_history_used<=0;
        end else if (initializing) begin
            if (init_addr == 9'd511) begin
                initializing <= 1'b0;
                bank_free <= 2'b11;
            end else begin
                init_addr <= init_addr + 9'd1;
            end
        end else begin
            if(source_accept)begin
                if(source_match0)begin bank_source_seen[0]<=1;bank_source_ok[0]<=source_ok;end
                if(source_match1)begin bank_source_seen[1]<=1;bank_source_ok[1]<=source_ok;end
            end
            if (process_beat) begin
                frame_pixels <= completed_pixels;
                if (pipe_sof[1]) begin
                    frame_sequence <= frame_sequence + 32'd1;
                    frame_epoch <= completed_epoch;
                    frame_height <= height;
                    row_index <= pipe_eol[1] ? 13'd1 : 13'd0;
                    collecting <= (|bank_free) && metadata_qualified;
                    collect_bank <= chosen_bank;
                    if ((|bank_free) && metadata_qualified) begin
                        bank_free[chosen_bank] <= 1'b0;
                        bank_eye[chosen_bank] <= eye;
                        bank_source_seen[chosen_bank]<=0;bank_source_ok[chosen_bank]<=0;
                        if(chosen_bank)bank_epoch1<=completed_epoch;else bank_epoch0<=completed_epoch;
                    end else if(metadata_qualified)
                        stats_skipped_frames <= stats_skipped_frames + 32'd1;
                    frame_history_used <= history_for_sof;
                    if (pending_lut) begin
                        if(select_pending)begin
                            active_page[eye] <= !active_lut_bank;
                            active_valid[eye] <= 1'b1;
                            active_sequence[eye] <= pending_epoch;
                        end
                        pending_valid[eye] <= 1'b0;
                    end
                end else if (pipe_eol[1]) begin
                    row_index <= row_index + 13'd1;
                end
                if (frame_last) begin
                    collecting <= 1'b0;
                    if (can_collect) begin
                        bank_full[selected_bank] <= 1'b1;
                        if (selected_bank) begin
                            bank_total1 <= completed_pixels;
                            bank_epoch1 <= completed_epoch;
                        end else begin
                            bank_total0 <= completed_pixels;
                            bank_epoch0 <= completed_epoch;
                        end
                    end
                end
            end

            case (bg_state)
                BG_IDLE: if (|build_ready) begin
                    bg_bank <= next_job_bank;
                    next_bg_bank <= !next_job_bank;
                    bg_total <= next_job_bank ? bank_total1 : bank_total0;
                    bg_epoch <= next_job_bank ? bank_epoch1 : bank_epoch0;
                    bank_full[next_job_bank] <= 1'b0;
                    bg_eye <= bank_eye[next_job_bank];
                    build_lut_bank <= !active_page[bank_eye[next_job_bank]];
                    bg_bin <= 8'd0; cdf <= 24'd0; cdf_min <= 24'd0;
                    min_found <= 1'b0;
                    bg_state <= BG_DRAIN;
                end
                BG_DRAIN: bg_state <= BG_READ;
                BG_READ: if (!collect_beat) bg_state <= BG_PAIR;
                BG_PAIR: begin
                    pair01 <= bg_counts[23:0] + bg_counts[47:24];
                    pair23 <= bg_counts[71:48] + bg_counts[95:72];
                    bg_state <= BG_SUM;
                end
                BG_SUM: begin
                    bin_total <= pair01 + pair23;
                    bg_state <= BG_ACCUM;
                end
                BG_ACCUM: begin
                    cdf <= cdf + bin_total;
                    if (!min_found && bin_total != 24'd0) begin
                        cdf_min <= bin_total;
                        min_found <= 1'b1;
                    end
                    bg_state <= BG_PREP;
                end
                BG_PREP: begin
                    if (min_found && bg_total == cdf_min) begin
                        bg_bin <= 8'd0;
                        bg_state <= BG_IDENTITY;
                    end else if (!min_found || cdf == cdf_min) begin
                        lut_write_value <= 8'd0;
                        bg_state <= BG_WRITE;
                    end else begin
                        denominator <= bg_total - cdf_min;
                        cdf_delta_reg <= cdf_delta;
                        bg_state <= BG_NUM;
                    end
                end
                BG_NUM: begin
                    numerator <= {cdf_delta_reg, 8'd0} - {8'd0, cdf_delta_reg};
                    bg_state <= BG_DIV;
                end
                BG_DIV: if(divide_issue)bg_state<=BG_DIV_WAIT;
                BG_DIV_WAIT: if(divider_valid && divide_inflight && divider_phase==DIV_READY)begin
                    if(divider_result[55:24] > 255) divide_error<=1;
                    else begin
                        lut_write_value<=divider_result[31:24];bg_state<=BG_WRITE;
                    end
                end
                BG_WRITE, BG_IDENTITY: begin
                    if (bg_bin == 8'd255) begin
                        pending_valid[bg_eye] <= 1'b1;
                        pending_sequence[bg_eye] <= bg_epoch;
                        bg_bin <= 8'd0;
                        bg_state <= BG_CLEAR;
                    end else begin
                        bg_bin <= bg_bin + 8'd1;
                        if (bg_state == BG_WRITE)
                            bg_state <= BG_READ;
                    end
                end
                BG_CLEAR: if (!collect_write_pending) begin
                    if (bg_bin == 8'd255) begin
                        bank_free[bg_bank] <= 1'b1;
                        bank_source_seen[bg_bank]<=0;bank_source_ok[bg_bank]<=0;
                        bg_state <= BG_IDLE;
                    end else begin
                        bg_bin <= bg_bin + 8'd1;
                    end
                end
                default: bg_state <= BG_IDLE;
            endcase
        end
    end
endmodule
