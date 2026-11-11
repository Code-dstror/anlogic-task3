`timescale 1ns / 1ps

// Passively capture accepted native RAW10 groups into ordered frame tokens.
module shared_raw10_frame_ingress #(
    parameter integer WIDTH = 1920,
    parameter integer HEIGHT = 1080,
    parameter integer CONTEXT_ENABLE = 0,
    parameter integer EXTERNAL_SEQUENCE_ENABLE = 0,
    parameter integer PAIR_METADATA_ENABLE = 0,
    parameter integer SOURCE_TERMINAL_ENABLE = 0, FIXED_HDR_ROLE=0, COMPACT_CAPTURE_HEADER=0
) (
    input  wire         i_clk,
    input  wire         i_rst_n,
    input  wire         i_enable,
    input  wire [39:0]  i_data,
    input  wire         i_valid,
    input  wire         i_accept,
    input  wire         i_sof,
    input  wire         i_eol,
    input  wire         i_abort,
    input  wire         i_camera,
    input  wire [31:0]  i_epoch,
    input  wire [31:0]  i_external_sequence, i_session_id,
    input wire i_sdr_profile,i_bayer_valid,i_time_valid,
    input wire [1:0] i_bayer_pattern,
    input  wire         i_metadata_valid,
    input  wire [63:0]  i_timestamp,
    input  wire [31:0]  i_actual_exposure,
    input  wire [31:0]  i_gain,
    input  wire [31:0]  i_calibration_id,
    input  wire         i_source_kind,
    input  wire [1:0]   i_exposure_role,
    input  wire [31:0]  i_exposure_group,
    input  wire         i_source_qualified,
    // Same-domain terminal from a true sensor-frame owner, not geometric EOF.
    input  wire         i_source_valid,
    output wire         o_source_ready,
    input  wire [31:0]  i_source_session, i_source_epoch, i_source_sequence,
    input  wire         i_source_camera, i_source_ok,
    input  wire [7:0]   i_source_error,
    output wire [31:0]  o_source_stale_count,
    output wire [127:0] o_axis_tdata,
    output wire [15:0]  o_axis_tkeep,
    output wire         o_axis_tvalid,
    input  wire         i_axis_tready,
    output wire         o_axis_tlast,
    output wire [1:0]   o_axis_tuser,
    output wire         o_capture_idle,
    output wire         o_frame_accept,
    output wire [31:0]  o_drop_count,
    output wire [31:0]  o_error_count
);

    localparam [2:0] STATE_IDLE = 3'd0;
    localparam [2:0] STATE_CAPTURE = 3'd1;
    localparam [2:0] STATE_DRAIN = 3'd2;
    localparam [2:0] STATE_FINISH = 3'd3;
    localparam [2:0] STATE_ABORT = 3'd4;
    localparam [2:0] STATE_WAIT_SOURCE = 3'd5;
    localparam integer GROUPS_PER_ROW = WIDTH / 4;
    localparam [31:0] FRAME_SAMPLES = WIDTH * HEIGHT;
    localparam [31:0] FRAME_BYTES = (WIDTH / 4) * HEIGHT * 5;
    localparam [15:0] FRAME_WIDTH = WIDTH;
    localparam [15:0] FRAME_HEIGHT = HEIGHT;
    localparam integer PACK_CAPACITY = PAIR_METADATA_ENABLE ? 25 : 21;
    localparam PARAMETER_VALID = (WIDTH > 0) && ((WIDTH % 4) == 0) &&
        (WIDTH <= 65535) && (HEIGHT > 0) && (HEIGHT <= 65535) &&
        ((64'd1 * WIDTH * HEIGHT) <= 64'h7fffffff) &&
        (!PAIR_METADATA_ENABLE || CONTEXT_ENABLE);

    // Legal accepted geometry bounds these counters before any increment.
    // Keep one bit for WIDTH=4/HEIGHT=1; invalid parameters never admit frames.
    function integer counter_bits;
        input integer count;
        integer value;
        begin
            value = count > 1 ? count - 1 : 1;
            counter_bits = 0;
            while (value > 0) begin
                counter_bits = counter_bits + 1;
                value = value >> 1;
            end
        end
    endfunction
    localparam integer GROUP_COLUMN_BITS = counter_bits(GROUPS_PER_ROW);
    localparam integer LINE_INDEX_BITS = counter_bits(HEIGHT);

    reg [2:0] state;
    reg [2:0] state_next;
    // During the metadata beats at most four 5-byte groups accumulate.
    // Subsequent full DATA transfers leave at most 15 bytes in the history.
    localparam integer HISTORY_BYTES = PACK_CAPACITY - 5;
    reg [HISTORY_BYTES*8-1:0] raw_history;

    reg [4:0] pack_bytes;
    reg [4:0] pack_bytes_next;
    reg [GROUP_COLUMN_BITS-1:0] group_column;
    reg [GROUP_COLUMN_BITS-1:0] group_column_next;
    reg [LINE_INDEX_BITS-1:0] line_index;
    reg [LINE_INDEX_BITS-1:0] line_index_next;
    reg [31:0] sequence_number;
    reg [31:0] sequence_number_next;
    reg [31:0] drop_count;
    reg [31:0] drop_count_next;
    reg [31:0] error_count;
    reg [31:0] error_count_next;
    reg [127:0] axis_data;
    wire [127:0] axis_data_next;
    reg [15:0] axis_keep;
    wire [15:0] axis_keep_next;
    reg axis_valid;
    reg axis_valid_next;
    reg axis_last;
    wire axis_last_next;
    reg [1:0] axis_user;
    wire [1:0] axis_user_next;
    reg [1:0] context_pending, context_pending_next;
    reg [127:0] context_data, context_data_next;
    reg [127:0] context_timestamp, context_timestamp_next;
    reg [127:0] context_calibration, context_calibration_next;
    wire [31:0] start_sequence = EXTERNAL_SEQUENCE_ENABLE ? i_external_sequence : sequence_number;
    reg frame_fault;
    reg [96:0] source_identity;
    reg source_seen, source_ok;
    reg [31:0] source_stale_count;
    wire raw_fire;
    wire axis_fire;
    wire output_available;
    wire terminal_fire;
    wire start_allowed;
    wire source_fire = i_source_valid && o_source_ready;
    wire source_match = !source_seen &&
        ((state == STATE_CAPTURE) || (state == STATE_DRAIN) || (state == STATE_WAIT_SOURCE)) &&
        {i_source_camera,i_source_session,i_source_epoch,i_source_sequence} == source_identity;
    wire source_negative = SOURCE_TERMINAL_ENABLE &&
        ((source_seen && !source_ok) || (source_fire && source_match && (!i_source_ok || |i_source_error)));
    assign o_source_ready = SOURCE_TERMINAL_ENABLE && i_rst_n;
    assign o_source_stale_count = source_stale_count;

    assign raw_fire = i_valid && i_accept;
    assign axis_fire = axis_valid && i_axis_tready;
    assign output_available = !axis_valid || i_axis_tready;
    assign terminal_fire = axis_fire &&
        (((state == STATE_FINISH) && (axis_user == 2'd2)) ||
         ((state == STATE_ABORT) && (axis_user == 2'd3)));
    assign start_allowed = (state == STATE_IDLE) || terminal_fire;
    assign o_axis_tdata = axis_data;
    assign o_axis_tkeep = axis_keep;
    assign o_axis_tvalid = axis_valid;
    assign o_axis_tlast = axis_last;
    assign o_axis_tuser = axis_user;
    // Includes the held final token/reservoir, not just pixel EOF observation.
    assign o_capture_idle = state == STATE_IDLE && !axis_valid &&
                            pack_bytes == 0 && context_pending == 0;
    assign o_frame_accept = PARAMETER_VALID && i_rst_n && start_allowed &&
        i_enable && !i_abort && raw_fire && i_sof;
    assign o_drop_count = drop_count;
    assign o_error_count = error_count;

    // Parallel token-write decode. No state, RAW acceptance, or SOURCE timing
    // changes: an arriving RAW group still participates in this cycle's DATA.
    // Separate the payload CE from the serial reservoir/priority next-data mux.
    wire token_active = state == STATE_CAPTURE || state == STATE_DRAIN;
    wire token_fault_base = i_abort || !i_enable || source_negative ||
        (axis_valid && !i_axis_tready &&
         (!SOURCE_TERMINAL_ENABLE || state == STATE_CAPTURE));
    wire token_raw_bad = state == STATE_DRAIN || i_sof ||
        (i_eol != (group_column == GROUPS_PER_ROW - 1)) ||
        (pack_bytes > PACK_CAPACITY - 5);
    wire token_fault = token_fault_base || (raw_fire && token_raw_bad);
    // With no fault, an accepted group adds exactly five bytes. On the last
    // group those nonzero bytes may emit a partial DATA; otherwise 16 are due.
    wire token_data_due = raw_fire ?
        ((pack_bytes >= 5'd11) || (i_eol && line_index == HEIGHT - 1)) :
        ((pack_bytes >= 5'd16) || (state == STATE_DRAIN && pack_bytes != 0));
    wire token_end_due = state == STATE_DRAIN && !raw_fire && pack_bytes == 0 &&
        (!SOURCE_TERMINAL_ENABLE || source_seen);
    wire token_abort_due = state == STATE_ABORT &&
        !(axis_fire && axis_user == 2'd3);
    wire token_start_due = start_allowed && i_enable && !i_abort && raw_fire && i_sof;

    // Parallel candidates depend on registered byte count, never late RAW
    // acceptance. The real raw_fire chooses them only after the arithmetic,
    // keep comparisons and post-DATA residual have already been computed.
    wire [4:0] bytes_with_raw = pack_bytes + 5'd5;
    wire [4:0] residual_with_raw = pack_bytes > 5'd11 ? pack_bytes - 5'd11 : 5'd0;
    wire [4:0] residual_without_raw = pack_bytes > 5'd16 ? pack_bytes - 5'd16 : 5'd0;
    wire raw_final = i_eol && line_index == HEIGHT - 1;
    wire data_last_with_raw = raw_final && pack_bytes <= 5'd11;
    wire data_last_without_raw = state == STATE_DRAIN && pack_bytes <= 5'd16;
    wire [15:0] keep_with_raw, keep_without_raw;
    genvar keep_lane;
    generate for (keep_lane = 0; keep_lane < 16; keep_lane = keep_lane + 1) begin: keep_decode
        assign keep_without_raw[keep_lane] = pack_bytes > keep_lane;
        if (keep_lane < 5) begin: initial_five
            assign keep_with_raw[keep_lane] = 1'b1;
        end else begin: remaining_lanes
            assign keep_with_raw[keep_lane] = pack_bytes > keep_lane - 5;
        end
    end endgenerate

    // Payload ownership is still decided by axis_valid_next below. Decode
    // mutually exclusive token sources in parallel instead of routing the
    // late RAW acceptance/fault priority through every payload register CE.
    wire payload_context = !token_start_due && token_active && !token_fault &&
        context_pending != 0;
    wire payload_data = !token_start_due && token_active && !token_fault &&
        context_pending == 0 && token_data_due;
    wire payload_end = !token_start_due &&
        ((token_active && !token_fault && context_pending == 0 &&
          !token_data_due && token_end_due) ||
         (state == STATE_WAIT_SOURCE && !i_abort && i_enable && !raw_fire &&
          !source_negative && source_seen && source_ok));
    wire payload_abort = !token_start_due &&
        ((token_active && token_fault) ||
         (state == STATE_WAIT_SOURCE && (i_abort || !i_enable || raw_fire || source_negative)) ||
         token_abort_due);
    // Capture-only DOL2 lane. Both proof bits belong to the exact accepted
    // SOF. The generic four-control-token format remains the default.
    reg [1:0] header_proof;
    always @(posedge i_clk)if(start_allowed)begin
        header_proof[0]<=!i_sdr_profile && i_metadata_valid && i_source_qualified &&
                          (i_exposure_role==1 || i_exposure_role==2);
        header_proof[1]<=i_camera && i_source_kind && i_exposure_role==FIXED_HDR_ROLE &&
            i_gain==32'd256 && i_calibration_id==32'h56a3d02f &&
            i_actual_exposure==(FIXED_HDR_ROLE==1 ? 32'd3200 : 32'd200);
    end
    wire [127:0] start_payload = (FIXED_HDR_ROLE!=0 || COMPACT_CAPTURE_HEADER!=0) ?
        {i_exposure_group,i_epoch,i_session_id,start_sequence} : {FRAME_SAMPLES[30:0],i_camera,i_epoch,
                                  FRAME_HEIGHT,FRAME_WIDTH,start_sequence};
    // Repeat both independent source-frame sequence and config epoch after START.
    // Timestamp is captured at the true member's SOF; never borrow the other VC.
    wire [127:0] context_payload = FIXED_HDR_ROLE!=0 ?
        {source_identity[63:0],context_timestamp[63:0]} :
        COMPACT_CAPTURE_HEADER!=0 ?
          (context_pending==2 ? context_timestamp :
            {source_identity[63:0],context_calibration[31:0],7'd0,source_identity[96],context_data[127:104]}) :
        ({128{!PAIR_METADATA_ENABLE || context_pending == 2'd3}} & context_data) |
        ({128{PAIR_METADATA_ENABLE && context_pending == 2'd2}} & context_timestamp) |
        ({128{PAIR_METADATA_ENABLE && context_pending == 2'd1}} & context_calibration);
    // Data only: START (IDLE or a consumed terminal), ACTIVE and WAIT_SOURCE
    // are mutually exclusive. Keep their common run mask at the last gate;
    // no late enable/abort needs to pass START exclusion and candidate decode.
    // Control/ownership and all sideband equations above/below stay unchanged.
    wire data_run=i_enable&&!i_abort;
    wire data_active_healthy=token_active&&!source_negative&&
        !(axis_valid&&!i_axis_tready&&(!SOURCE_TERMINAL_ENABLE||state==STATE_CAPTURE))&&
        !(raw_fire&&token_raw_bad);
    wire data_start_select=start_allowed&&raw_fire&&i_sof;
    wire data_context_select=data_active_healthy&&context_pending!=0;
    wire data_word_select=data_active_healthy&&context_pending==0&&token_data_due;
    wire data_end_select=(data_active_healthy&&context_pending==0&&!token_data_due&&token_end_due)||
        (state==STATE_WAIT_SOURCE&&!raw_fire&&!source_negative&&source_seen&&source_ok);
    // Position the newest stored byte at lane 30. Then the oldest owned byte
    // is at 31-pack_bytes, the bitwise complement of the five-bit count.
    // The next five bytes come directly from this input beat; unused tail
    // lanes are cleared so all bits of a presented DATA token stay identical.
    wire [287:0] window_data={i_data,raw_history,{((31-HISTORY_BYTES)*8){1'b0}}};
    wire [4:0] oldest_byte=~pack_bytes;
    wire [127:0] aligned_word=window_data >> {oldest_byte,3'b000};
    wire [127:0] qualified_word;
    genvar data_lane;
    generate for(data_lane=0; data_lane<16; data_lane=data_lane+1)begin:g_align
        wire present=raw_fire ? keep_with_raw[data_lane] : keep_without_raw[data_lane];
        assign qualified_word[data_lane*8+:8]=aligned_word[data_lane*8+:8] & {8{present}};
    end endgenerate
    wire [127:0] data_payload=({128{data_start_select}} & start_payload) |
        ({128{data_context_select}} & context_payload) |
        ({128{data_word_select}} & qualified_word) |
        ({128{data_end_select}} & {63'd0,1'b1,FRAME_SAMPLES,FRAME_BYTES});
    assign axis_data_next={128{data_run}} & data_payload;
    assign axis_keep_next = COMPACT_CAPTURE_HEADER!=0 && token_start_due ? 16'hc030 :
        FIXED_HDR_ROLE!=0 && payload_context ?
        {12'hca1,FIXED_HDR_ROLE[1:0],header_proof} : payload_data ? (raw_fire ? keep_with_raw : keep_without_raw) :
        {16{token_start_due || payload_context || payload_end || payload_abort}};
    assign axis_last_next = payload_context ||
        (payload_data && (raw_fire ? data_last_with_raw : data_last_without_raw));
    assign axis_user_next = ({2{token_start_due || payload_context}} & 2'd1) |
        ({2{payload_end}} & 2'd2) | ({2{payload_abort}} & 2'd3);

    wire reservoir_append = token_active && !token_fault && raw_fire;
    wire reservoir_emit = token_active && !token_fault && output_available &&
        context_pending == 0 && token_data_due;
    wire reservoir_clear = state == STATE_IDLE || state > STATE_WAIT_SOURCE ||
        (token_active && token_fault);
    wire start_geometry_bad = !PARAMETER_VALID || (i_eol != (GROUPS_PER_ROW == 1));

    // Accepted RAW groups shift on fixed byte lanes; emitting changes the count only.
    always @(posedge i_clk) if(raw_fire) raw_history<={i_data,raw_history[HISTORY_BYTES*8-1:40]};
    always @(*) begin
        pack_bytes_next = pack_bytes;
        if (token_start_due) begin
            pack_bytes_next = start_geometry_bad ? 5'd0 : 5'd5;
        end else if (reservoir_clear) begin
            pack_bytes_next = 5'd0;
        end else if (reservoir_emit) begin
            pack_bytes_next = raw_fire ? residual_with_raw : residual_without_raw;
        end else if (reservoir_append) begin
            pack_bytes_next = bytes_with_raw;
        end
    end

    // Append before extracting a DATA beat; control headers retain early pixels.
    always @(*) begin
        state_next = state;
        group_column_next = group_column;
        line_index_next = line_index;
        sequence_number_next = sequence_number;
        drop_count_next = drop_count;
        error_count_next = error_count;
        axis_valid_next = axis_valid;
        context_pending_next = context_pending;
        context_data_next = context_data;
        context_timestamp_next = context_timestamp;
        context_calibration_next = context_calibration;
        frame_fault = 1'b0;
        if (axis_fire)
            axis_valid_next = 1'b0;
        case (state)
            STATE_IDLE: begin
                context_pending_next = 0;
            end
            STATE_CAPTURE, STATE_DRAIN: begin
                frame_fault = token_fault;
                if (raw_fire && !token_fault) begin
                    if (i_eol) begin
                        group_column_next = 16'd0;
                        if (line_index == HEIGHT - 1)
                            state_next = STATE_DRAIN;
                        else
                            line_index_next = line_index + 16'd1;
                    end else begin
                        group_column_next = group_column + 16'd1;
                    end
                end
                if (frame_fault) begin
                    context_pending_next = 0;
                    state_next = STATE_ABORT;
                    drop_count_next = drop_count + 32'd1;
                    error_count_next = error_count + 32'd1;
                    if (output_available) begin
                        axis_valid_next = 1'b1;
                    end
                end else if (output_available) begin
                    if (context_pending) begin
                        axis_valid_next = 1'b1;
                        context_pending_next = context_pending - 2'd1;
                    end else if (token_data_due) begin
                        axis_valid_next = 1'b1;
                    end else if ((state == STATE_DRAIN) &&
                                 (pack_bytes == 5'd0)) begin
                        if (SOURCE_TERMINAL_ENABLE && !source_seen) begin
                            state_next = STATE_WAIT_SOURCE;
                        end else begin
                            axis_valid_next = 1'b1;
                            state_next = STATE_FINISH;
                        end
                    end
                end
            end
            STATE_WAIT_SOURCE: begin
                if (i_abort || !i_enable || raw_fire || source_negative) begin
                    state_next = STATE_ABORT;
                    drop_count_next = drop_count + 32'd1;
                    error_count_next = error_count + 32'd1;
                    if (output_available) begin
                        axis_valid_next = 1'b1;
                    end
                end else if (source_seen && source_ok && output_available) begin
                    axis_valid_next = 1'b1;
                    state_next = STATE_FINISH;
                end
            end
            STATE_FINISH: begin
                if (axis_fire)
                    state_next = STATE_IDLE;
                else if (raw_fire && i_sof) begin
                    drop_count_next = drop_count + 32'd1;
                    error_count_next = error_count + 32'd1;
                end
            end
            STATE_ABORT: begin
                if (axis_fire && (axis_user == 2'd3)) begin
                    state_next = STATE_IDLE;
                end else if (output_available) begin
                    axis_valid_next = 1'b1;
                end
            end
            default: begin
                state_next = STATE_IDLE;
                axis_valid_next = 1'b0;
            end
        endcase
        // These snapshots are private until the exact START admits the
        // context count. While IDLE, or on a consumed terminal, capture the
        // candidate regardless of late RAW acceptance/enable/abort. A real
        // START still freezes the same-cycle fields before any context token.
        if (start_allowed) begin
            if (PAIR_METADATA_ENABLE) begin
                context_data_next = i_sdr_profile ?
                    {11'd0,i_time_valid,i_bayer_valid,i_bayer_pattern,i_metadata_valid,i_source_qualified,
                    i_exposure_role,i_source_kind,4'd3,i_epoch,start_sequence,8'd1,i_session_id} :
                    {15'd0,i_metadata_valid,i_source_qualified,i_exposure_role,i_source_kind,
                    4'd1,i_epoch,start_sequence,8'd1,i_session_id};
                context_timestamp_next = {i_gain, i_actual_exposure,
                    (i_sdr_profile&&!i_time_valid)?64'd0:i_timestamp};
                context_calibration_next = {i_epoch, start_sequence,
                    i_exposure_group, i_calibration_id};
            end else begin
                context_data_next = {24'd0,i_epoch,start_sequence,8'd1,i_session_id};
                context_timestamp_next = 128'd0;
                context_calibration_next = 128'd0;
            end
        end
        // Admission may immediately follow a terminal control handshake.
        if (start_allowed && i_enable && !i_abort && raw_fire && i_sof) begin
            context_pending_next = CONTEXT_ENABLE ?
                (FIXED_HDR_ROLE!=0 ? 2'd1 : COMPACT_CAPTURE_HEADER!=0 ? 2'd2 : PAIR_METADATA_ENABLE ? 2'd3 : 2'd1) : 2'd0;
            axis_valid_next = 1'b1;
            sequence_number_next = sequence_number + 32'd1;
            group_column_next = 16'd1;
            line_index_next = 16'd0;
            state_next = STATE_CAPTURE;
            if (!PARAMETER_VALID || (i_eol != (GROUPS_PER_ROW == 1))) begin
                state_next = STATE_ABORT;
                drop_count_next = drop_count + 32'd1;
                error_count_next = error_count + 32'd1;
            end else if (i_eol) begin
                group_column_next = 16'd0;
                if (HEIGHT == 1)
                    state_next = STATE_DRAIN;
                else
                    line_index_next = 16'd1;
            end
        end
    end
    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n)
            state <= STATE_IDLE;
        else
            state <= state_next;
    end

    // Tuple remains owned until terminal transfer. Source errors never retract
    // the output holding register; only the coordinated local reset may do so.
    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            source_identity <= 97'd0;
            source_seen <= 1'b0;
            source_ok <= 1'b0;
            source_stale_count <= 32'd0;
        end else begin
            if (terminal_fire) begin
                source_seen <= 1'b0;
                source_ok <= 1'b0;
            end
            if (source_fire) begin
                if (source_match) begin
                    source_seen <= 1'b1;
                    source_ok <= i_source_ok && !(|i_source_error);
                end else if (source_stale_count != 32'hffffffff) begin
                    source_stale_count <= source_stale_count + 32'd1;
                end
            end
            // No matcher uses an IDLE/retiring identity; the first exact
            // accepted START freezes this candidate on its original edge.
            if (start_allowed)
                source_identity <= {i_camera,i_session_id,i_epoch,start_sequence};
            if (o_frame_accept) begin
                source_seen <= 1'b0;
                source_ok <= 1'b0;
            end
        end
    end

    // Reset ownership/control; invalid payload has no reset requirement.
    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            context_pending <= 0; context_data <= 0;
            context_timestamp <= 0; context_calibration <= 0;
            pack_bytes <= 5'd0;
            group_column <= 16'd0;
            line_index <= 16'd0;
            sequence_number <= 32'd0;
            drop_count <= 32'd0;
            error_count <= 32'd0;
            axis_valid <= 1'b0;
        end else begin
            context_pending <= context_pending_next; context_data <= context_data_next;
            context_timestamp <= context_timestamp_next;
            context_calibration <= context_calibration_next;
            pack_bytes <= pack_bytes_next;
            group_column <= group_column_next;
            line_index <= line_index_next;
            sequence_number <= sequence_number_next;
            drop_count <= drop_count_next;
            error_count <= error_count_next;
            axis_valid <= axis_valid_next;
        end
    end

    // Capacity-only speculative writes are hidden while axis_valid is clear.
    // Every valid token is selected on its original edge, including a START
    // replacing an accepted terminal; an occupied stalled token stays stable.
    // IDLE owns no valid token; terminal_fire requires ready. Therefore every
    // reachable token_start_due also has output_available, without a late CE.
    always @(posedge i_clk) begin
        if (output_available) begin
            axis_data <= axis_data_next;
            axis_keep <= axis_keep_next;
            axis_last <= axis_last_next;
            axis_user <= axis_user_next;
        end
    end

endmodule
