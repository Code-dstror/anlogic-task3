`timescale 1ns / 1ps

// Passively capture accepted native RAW10 groups into ordered frame tokens.
module raw10_frame_ingress #(
    parameter integer WIDTH = 1920,
    parameter integer HEIGHT = 1080,
    parameter integer CONTEXT_ENABLE = 0,
    parameter integer EXTERNAL_SEQUENCE_ENABLE = 0,
    parameter integer PAIR_METADATA_ENABLE = 0,
    parameter integer SOURCE_TERMINAL_ENABLE = 0
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
    localparam integer PACK_WIDTH = PACK_CAPACITY * 8;
    localparam PARAMETER_VALID = (WIDTH > 0) && ((WIDTH % 4) == 0) &&
        (WIDTH <= 65535) && (HEIGHT > 0) && (HEIGHT <= 65535) &&
        ((64'd1 * WIDTH * HEIGHT) <= 64'h7fffffff) &&
        (!PAIR_METADATA_ENABLE || CONTEXT_ENABLE);

    reg [2:0] state;
    reg [2:0] state_next;
    reg [PACK_WIDTH-1:0] pack_data;
    reg [PACK_WIDTH-1:0] pack_data_next;
    reg [4:0] pack_bytes;
    reg [4:0] pack_bytes_next;
    reg [15:0] group_column;
    reg [15:0] group_column_next;
    reg [15:0] line_index;
    reg [15:0] line_index_next;
    reg [31:0] sequence_number;
    reg [31:0] sequence_number_next;
    reg [31:0] drop_count;
    reg [31:0] drop_count_next;
    reg [31:0] error_count;
    reg [31:0] error_count_next;
    reg [127:0] axis_data;
    reg [127:0] axis_data_next;
    reg [15:0] axis_keep;
    reg [15:0] axis_keep_next;
    reg axis_valid;
    reg axis_valid_next;
    reg axis_last;
    reg axis_last_next;
    reg [1:0] axis_user;
    reg [1:0] axis_user_next;
    reg [1:0] context_pending, context_pending_next;
    reg [127:0] context_data, context_data_next;
    reg [127:0] context_timestamp, context_timestamp_next;
    reg [127:0] context_calibration, context_calibration_next;
    wire [31:0] start_sequence = EXTERNAL_SEQUENCE_ENABLE ? i_external_sequence : sequence_number;
    reg frame_fault;
    reg [96:0] source_identity;
    reg source_seen, source_ok;
    reg [31:0] source_stale_count;
    reg final_group;
    integer append_bit;

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

    // Append before extracting a DATA beat; control headers retain early pixels.
    always @(*) begin
        state_next = state;
        pack_data_next = pack_data;
        pack_bytes_next = pack_bytes;
        group_column_next = group_column;
        line_index_next = line_index;
        sequence_number_next = sequence_number;
        drop_count_next = drop_count;
        error_count_next = error_count;
        axis_data_next = axis_data;
        axis_keep_next = axis_keep;
        axis_valid_next = axis_valid;
        axis_last_next = axis_last;
        axis_user_next = axis_user;
        context_pending_next = context_pending;
        context_data_next = context_data;
        context_timestamp_next = context_timestamp;
        context_calibration_next = context_calibration;
        frame_fault = 1'b0;
        final_group = 1'b0;
        append_bit = 0;

        if (axis_fire)
            axis_valid_next = 1'b0;

        case (state)
            STATE_IDLE: begin
                context_pending_next = 0;
                pack_data_next = {PACK_WIDTH{1'b0}};
                pack_bytes_next = 5'd0;
            end
            STATE_CAPTURE, STATE_DRAIN: begin
                frame_fault = i_abort || !i_enable ||
                              (axis_valid && !i_axis_tready &&
                               (!SOURCE_TERMINAL_ENABLE || state == STATE_CAPTURE)) || source_negative;
                if (raw_fire) begin
                    if (state == STATE_DRAIN || i_sof ||
                        (i_eol != (group_column == GROUPS_PER_ROW - 1)))
                        frame_fault = 1'b1;
                    if (!frame_fault) begin
                        if (pack_bytes > PACK_CAPACITY - 5) begin
                            frame_fault = 1'b1;
                        end else begin
                            append_bit = pack_bytes * 8;
                            pack_data_next[append_bit +: 40] = i_data;
                            pack_bytes_next = pack_bytes + 5'd5;
                            if (i_eol) begin
                                group_column_next = 16'd0;
                                if (line_index == HEIGHT - 1) begin
                                    final_group = 1'b1;
                                    state_next = STATE_DRAIN;
                                end else begin
                                    line_index_next = line_index + 16'd1;
                                end
                            end else begin
                                group_column_next = group_column + 16'd1;
                            end
                        end
                    end
                end
                if (frame_fault) begin
                    context_pending_next = 0;
                    state_next = STATE_ABORT;
                    drop_count_next = drop_count + 32'd1;
                    error_count_next = error_count + 32'd1;
                    pack_data_next = {PACK_WIDTH{1'b0}};
                    pack_bytes_next = 5'd0;
                    if (output_available) begin
                        axis_data_next = 128'd0;
                        axis_keep_next = 16'hffff;
                        axis_valid_next = 1'b1;
                        axis_last_next = 1'b0;
                        axis_user_next = 2'd3;
                    end
                end else if (output_available) begin
                    if (context_pending) begin
                        if (!PAIR_METADATA_ENABLE || context_pending == 2'd3)
                            axis_data_next = context_data;
                        else if (context_pending == 2'd2)
                            axis_data_next = context_timestamp;
                        else
                            axis_data_next = context_calibration;
                        axis_keep_next = 16'hffff;
                        axis_valid_next = 1; axis_last_next = 1; axis_user_next = 1;
                        context_pending_next = context_pending - 2'd1;
                    end else if ((pack_bytes_next >= 5'd16) ||
                        (((state == STATE_DRAIN) || final_group) &&
                         (pack_bytes_next != 5'd0))) begin
                        axis_data_next = pack_data_next[127:0];
                        axis_keep_next = (pack_bytes_next >= 5'd16) ?
                            16'hffff : (16'hffff >> (16 - pack_bytes_next));
                        axis_valid_next = 1'b1;
                        axis_last_next = ((state == STATE_DRAIN) || final_group) &&
                                         (pack_bytes_next <= 5'd16);
                        axis_user_next = 2'd0;
                        pack_data_next = pack_data_next >> 128;
                        pack_bytes_next = (pack_bytes_next > 5'd16) ?
                                           pack_bytes_next - 5'd16 : 5'd0;
                    end else if ((state == STATE_DRAIN) &&
                                 (pack_bytes_next == 5'd0)) begin
                        if (SOURCE_TERMINAL_ENABLE && !source_seen) begin
                            state_next = STATE_WAIT_SOURCE;
                        end else begin
                        axis_data_next = {63'd0, 1'b1, FRAME_SAMPLES, FRAME_BYTES};
                        axis_keep_next = 16'hffff;
                        axis_valid_next = 1'b1;
                        axis_last_next = 1'b0;
                        axis_user_next = 2'd2;
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
                        axis_data_next = 128'd0;
                        axis_keep_next = 16'hffff;
                        axis_valid_next = 1'b1;
                        axis_last_next = 1'b0;
                        axis_user_next = 2'd3;
                    end
                end else if (source_seen && source_ok && output_available) begin
                    axis_data_next = {63'd0, 1'b1, FRAME_SAMPLES, FRAME_BYTES};
                    axis_keep_next = 16'hffff;
                    axis_valid_next = 1'b1;
                    axis_last_next = 1'b0;
                    axis_user_next = 2'd2;
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
                    axis_data_next = 128'd0;
                    axis_keep_next = 16'hffff;
                    axis_valid_next = 1'b1;
                    axis_last_next = 1'b0;
                    axis_user_next = 2'd3;
                end
            end
            default: begin
                state_next = STATE_IDLE;
                pack_data_next = {PACK_WIDTH{1'b0}};
                pack_bytes_next = 5'd0;
                axis_valid_next = 1'b0;
            end
        endcase

        // Admission may immediately follow a terminal control handshake.
        if (start_allowed && i_enable && !i_abort && raw_fire && i_sof) begin
            axis_data_next = {FRAME_SAMPLES[30:0], i_camera, i_epoch,
                              FRAME_HEIGHT, FRAME_WIDTH, start_sequence};
            context_pending_next = CONTEXT_ENABLE ?
                (PAIR_METADATA_ENABLE ? 2'd3 : 2'd1) : 2'd0;
            if (PAIR_METADATA_ENABLE) begin
                context_data_next = {15'd0, i_metadata_valid, i_source_qualified,
                    i_exposure_role, i_source_kind, 4'd1, i_epoch,
                    start_sequence, 8'd1, i_session_id};
                context_timestamp_next = {i_gain, i_actual_exposure, i_timestamp};
                context_calibration_next = {i_epoch, start_sequence,
                    i_exposure_group, i_calibration_id};
            end else begin
                context_data_next = {24'd0,i_epoch,start_sequence,8'd1,i_session_id};
                context_timestamp_next = 128'd0;
                context_calibration_next = 128'd0;
            end
            axis_keep_next = 16'hffff;
            axis_valid_next = 1'b1;
            axis_last_next = 1'b0;
            axis_user_next = 2'd1;
            sequence_number_next = sequence_number + 32'd1;
            pack_data_next = {{(PACK_WIDTH-40){1'b0}}, i_data};
            pack_bytes_next = 5'd5;
            group_column_next = 16'd1;
            line_index_next = 16'd0;
            state_next = STATE_CAPTURE;
            if (!PARAMETER_VALID || (i_eol != (GROUPS_PER_ROW == 1))) begin
                pack_data_next = {PACK_WIDTH{1'b0}};
                pack_bytes_next = 5'd0;
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
            if (o_frame_accept) begin
                source_identity <= {i_camera,i_session_id,i_epoch,start_sequence};
                source_seen <= 1'b0;
                source_ok <= 1'b0;
            end
        end
    end

    // State and all payload registers share the pixel-domain session reset.
    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            context_pending <= 0; context_data <= 0;
            context_timestamp <= 0; context_calibration <= 0;
            pack_data <= {PACK_WIDTH{1'b0}};
            pack_bytes <= 5'd0;
            group_column <= 16'd0;
            line_index <= 16'd0;
            sequence_number <= 32'd0;
            drop_count <= 32'd0;
            error_count <= 32'd0;
            axis_data <= 128'd0;
            axis_keep <= 16'd0;
            axis_valid <= 1'b0;
            axis_last <= 1'b0;
            axis_user <= 2'd0;
        end else begin
            context_pending <= context_pending_next; context_data <= context_data_next;
            context_timestamp <= context_timestamp_next;
            context_calibration <= context_calibration_next;
            pack_data <= pack_data_next;
            pack_bytes <= pack_bytes_next;
            group_column <= group_column_next;
            line_index <= line_index_next;
            sequence_number <= sequence_number_next;
            drop_count <= drop_count_next;
            error_count <= error_count_next;
            axis_data <= axis_data_next;
            axis_keep <= axis_keep_next;
            axis_valid <= axis_valid_next;
            axis_last <= axis_last_next;
            axis_user <= axis_user_next;
        end
    end

endmodule
