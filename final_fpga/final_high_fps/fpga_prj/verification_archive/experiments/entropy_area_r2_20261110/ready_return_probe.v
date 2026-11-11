module uhd_probe (
    input wire clk, rst_n,
    input wire word_write, token_valid, token_last,
    input wire [1:0] write_word, token_user,
    input wire [31:0] word_data,
    input wire [15:0] token_keep, restart_mcus,
    input wire [2:0] formatter_state, encoder_state,
    input wire [1:0] fmt_count,
    input wire buffer_valid, buffer_last, abort_released,
    output wire block_ready, token_ready, byte_valid, byte_last, done, error_valid, idle,
    output wire [7:0] byte_data, error_code,
    output wire [31:0] error_capture_id
);
    reg [127:0] token_data;
    genvar word_index;
    generate for (word_index=0; word_index<4; word_index=word_index+1) begin : g_word
        always @(posedge clk)
            if (word_write && write_word == word_index)
                token_data[word_index*32 +: 32] <= word_data;
    end endgenerate

    (* preserve="true" *) reg [2:0] formatter_state_q, encoder_state_q;
    (* preserve="true" *) reg [1:0] fmt_count_q;
    (* preserve="true" *) reg buffer_valid_q, buffer_last_q, abort_released_q;
    always @(posedge clk) begin
        formatter_state_q <= formatter_state;
        encoder_state_q <= encoder_state;
        fmt_count_q <= fmt_count;
        buffer_valid_q <= buffer_valid;
        buffer_last_q <= buffer_last;
        abort_released_q <= abort_released;
    end

    localparam [2:0] S_ABORT = 3'd2;
    localparam [2:0] STATE_ENTROPY = 3'd2;
    // Preserve the eade457d READY equations in jpeg_encoder_top and
    // jpeg_file_formatter, with their launch registers modeled at the ports.
    wire aborting = (encoder_state_q == S_ABORT) && !abort_released_q;
    wire fmt_queue_ready = fmt_count_q < 2;
    wire formatter_byte_ready = aborting ? 1'b1 : fmt_queue_ready;
    wire formatter_entropy_ready = (formatter_state_q == STATE_ENTROPY) &&
        (!buffer_valid_q || (formatter_byte_ready && !buffer_last_q)) && !aborting;
    wire entropy_byte_ready = aborting ? 1'b1 : formatter_entropy_ready;

    jpeg_entropy #(.STREAM_INPUT_ENABLE(1), .RESTART_ENABLE(1),
        .COEFF_BANKED_STORAGE_ENABLE(1)) dut (
        .i_clk(clk), .i_rst_n(rst_n), .i_abort(aborting),
        .i_block_valid(1'b0), .o_block_ready(block_ready), .i_coeffs(1024'd0),
        .i_component(2'd0), .i_block_index(2'd0), .i_mcu_x(9'd0), .i_mcu_y(9'd0),
        .i_frame_last(1'b0), .i_capture_id(32'd0),
        .i_token_valid(token_valid), .o_token_ready(token_ready), .i_token_data(token_data),
        .i_token_keep(token_keep), .i_token_last(token_last), .i_token_user(token_user),
        .i_restart_mcus(restart_mcus), .o_byte_valid(byte_valid), .i_byte_ready(entropy_byte_ready),
        .o_byte(byte_data), .o_byte_last(byte_last), .o_entropy_done(done), .o_error_valid(error_valid),
        .o_error_capture_id(error_capture_id), .o_error_code(error_code), .o_idle(idle));
endmodule
