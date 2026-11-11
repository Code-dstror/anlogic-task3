`timescale 1ns / 1ps

// Four native RAW10 lanes, independent block-local Bayer x-2 transform.
module cfs_raw10_predictor (
    input wire clk,
    input wire rst_n,
    input wire abort,
    input wire start_valid,
    output wire start_ready,
    input wire inverse_mode,
    input wire [11:0] sample_count,
    input wire [15:0] width,
    input wire [15:0] block_start_x,
    input wire [159:0] i_context,
    input wire [39:0] input_data,
    input wire [3:0] input_keep,
    input wire input_last,
    input wire input_valid,
    output wire input_ready,
    output wire [39:0] output_data,
    output wire [3:0] output_keep,
    output wire output_last,
    output wire output_valid,
    input wire output_ready,
    output wire [159:0] result_context,
    output wire busy,
    output wire done,
    output wire error,
    output wire [11:0] output_count,
    output wire [31:0] service_cycles
);
    // Final output and ordinary errors drain the one registered alignment beat.
    localparam [2:0] IDLE = 3'd0, ACTIVE = 3'd1, FINISH = 3'd2, ERROR = 3'd3;
    reg [2:0] state, state_next;
    reg mode_inverse;
    reg [11:0] length_locked, received_count;
    reg [15:0] width_locked, row_position;
    reg [9:0] history_old, history_recent;
    reg [159:0] context_o;
    reg [39:0] output_data_o;
    reg [3:0] output_keep_o;
    reg output_valid_o, output_last_o;
    reg done_o, error_o;
    reg [11:0] output_count_o;
    reg [31:0] service_cycles_o;

    // Combinational work registers describe two histories, never indexed RAM.
    reg [9:0] work_old, work_recent, lane_input, lane_result, lane_history;
    reg [15:0] work_position;
    reg [39:0] transformed_data;
    reg [2:0] input_samples, output_samples;
    integer lane;

    wire start_fire = start_valid && start_ready;
    wire input_fire = input_valid && input_ready;
    wire output_fire = output_valid && output_ready;
    wire output_slot = !output_valid_o || output_ready;
    wire metadata_fault = sample_count == 0 || sample_count > 2048 ||
                          width == 0 || block_start_x >= width;
    wire [11:0] input_total = received_count + input_samples;
    wire input_final = input_total == length_locked;
    wire input_fault = input_samples == 0 || input_total > length_locked ||
                       input_last != input_final;
    wire error_drained = !output_valid_o || output_fire;

    assign start_ready = state == IDLE;
    assign input_ready = state == ACTIVE && output_slot && !abort;
    assign output_data = output_data_o;
    assign output_keep = output_keep_o;
    assign output_last = output_last_o;
    assign output_valid = output_valid_o;
    assign result_context = context_o;
    assign busy = state != IDLE;
    assign done = done_o;
    assign error = error_o;
    assign output_count = output_count_o;
    assign service_cycles = service_cycles_o;

    // Keep identifies samples, not bytes. All partial nonfinal beats are legal.
    always @(*) begin
        case (input_keep)
            4'h1: input_samples = 1;
            4'h3: input_samples = 2;
            4'h7: input_samples = 3;
            4'hf: input_samples = 4;
            default: input_samples = 0;
        endcase
        case (output_keep_o)
            4'h1: output_samples = 1;
            4'h3: output_samples = 2;
            4'h7: output_samples = 3;
            4'hf: output_samples = 4;
            default: output_samples = 0;
        endcase
    end

    // Lane order unfolds forward-overlap of the two-sample predictor. Each
    // lane updates history with original/recovered data, never residual data.
    always @(*) begin
        work_old = history_old;
        work_recent = history_recent;
        work_position = row_position;
        transformed_data = 0;
        lane_input = 0;
        lane_result = 0;
        lane_history = 0;
        for (lane = 0; lane < 4; lane = lane + 1) begin
            if (input_keep[lane]) begin
                lane_input = input_data[lane * 10 +: 10];
                lane_result = lane_input;
                if (received_count + lane >= 2 && work_position >= 2) begin
                    if (mode_inverse) lane_result = lane_input + work_old;
                    else lane_result = lane_input - work_old;
                end
                lane_history = mode_inverse ? lane_result : lane_input;
                transformed_data[lane * 10 +: 10] = lane_result;
                work_old = work_recent;
                work_recent = lane_history;
                if (work_position == width_locked - 1'b1) work_position = 0;
                else work_position = work_position + 1'b1;
            end
        end
    end

    // Abort may cancel output; ordinary errors wait for presented data to drain.
    always @(*) begin
        state_next = state;
        if (abort && state != IDLE) state_next = ERROR;
        else begin
            case (state)
                IDLE: if (start_fire) state_next = metadata_fault ? ERROR : ACTIVE;
                ACTIVE: if (input_fire) begin
                    if (input_fault) state_next = ERROR;
                    else if (input_final) state_next = FINISH;
                end
                FINISH: if (output_fire) state_next = IDLE;
                ERROR: if (error_drained) state_next = IDLE;
                default: state_next = ERROR;
            endcase
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) state <= IDLE;
        else state <= state_next;
    end

    // Only accepted samples advance x/history. The output register holds all
    // stream fields through stall and carries the locked block identity.
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            mode_inverse <= 0; length_locked <= 0; received_count <= 0;
            width_locked <= 0; row_position <= 0;
            history_old <= 0; history_recent <= 0; context_o <= 0;
            output_data_o <= 0; output_keep_o <= 0;
            output_valid_o <= 0; output_last_o <= 0;
            done_o <= 0; error_o <= 0; output_count_o <= 0; service_cycles_o <= 0;
        end else begin
            done_o <= 0;
            if (state != IDLE && service_cycles_o != 32'hffffffff)
                service_cycles_o <= service_cycles_o + 1'b1;
            if (start_fire) begin
                mode_inverse <= inverse_mode; length_locked <= sample_count;
                width_locked <= width; row_position <= block_start_x;
                context_o <= i_context; received_count <= 0;
                history_old <= 0; history_recent <= 0;
                output_data_o <= 0; output_keep_o <= 0;
                output_valid_o <= 0; output_last_o <= 0;
                error_o <= metadata_fault; output_count_o <= 0; service_cycles_o <= 1;
            end else begin
                if (output_fire) begin
                    output_valid_o <= 0;
                    output_count_o <= output_count_o + output_samples;
                end
                if (input_fire && !input_fault) begin
                    output_data_o <= transformed_data;
                    output_keep_o <= input_keep; output_last_o <= input_final;
                    output_valid_o <= 1;
                    history_old <= work_old; history_recent <= work_recent;
                    row_position <= work_position; received_count <= input_total;
                end
                if (input_fire && input_fault) error_o <= 1;
                if (state > ERROR) error_o <= 1;
                if (state == FINISH && output_fire && !abort) done_o <= 1;
                if (state == ERROR && error_drained && !abort) done_o <= 1;
                if (abort && state != IDLE) begin
                    error_o <= 1; output_valid_o <= 0;
                    output_data_o <= 0; output_keep_o <= 0; output_last_o <= 0;
                    history_old <= 0; history_recent <= 0; row_position <= 0;
                    received_count <= 0; mode_inverse <= 0;
                end
            end
        end
    end
endmodule
