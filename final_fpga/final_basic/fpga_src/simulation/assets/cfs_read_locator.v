`timescale 1ns/1ps
// Exact CFS address arithmetic in the DFI domain; no slot or AXI ownership.
module cfs_read_locator (
    input  wire        i_clk,
    input  wire        i_rst_n,
    input  wire        i_request_valid,
    output wire        o_request_ready,
    input  wire [31:0] i_offset,
    input  wire [15:0] i_width,
    output wire        o_result_valid,
    input  wire        i_result_ready,
    output reg  [31:0] o_block,
    output reg  [11:0] o_local,
    output reg  [15:0] o_first_x,
    output reg  [15:0] o_second_x,
    output reg  [15:0] o_step_x,
    output reg         o_error
);
    localparam [3:0] S_IDLE = 0, S_BLOCK_ISSUE = 1, S_BLOCK_WAIT = 2,
                     S_FIRST_ISSUE = 3, S_SECOND_ISSUE = 4,
                     S_X_WAIT = 5, S_RESULT = 6;
    reg [3:0] state;
    reg [6:0] startup_count;
    reg [31:0] offset;
    reg [15:0] width;
    reg first_x_seen;

    // The official pipeline may retain valid results across a short reset.
    // Hold its reset for 32 clocks, then discard a full 32-clock drain window.
    wire core_reset_n = i_rst_n && startup_count >= 7'd32;
    wire core_ready = startup_count == 7'd64;
    wire core_input_valid = core_ready && (state == S_BLOCK_ISSUE ||
                            state == S_FIRST_ISSUE || state == S_SECOND_ISSUE);
    wire [31:0] block_pixel = {o_block[20:0], 11'd0};
    wire [31:0] core_dividend = state == S_BLOCK_ISSUE ? {9'd0, offset[31:9]} :
                                state == S_FIRST_ISSUE ? block_pixel :
                                block_pixel + 32'd2048;
    wire [15:0] core_divisor = state == S_BLOCK_ISSUE ? 16'd5 : width;
    wire [47:0] core_data;
    wire core_valid;
    wire [15:0] core_remainder = core_data[15:0];
    wire [16:0] wrapped_step = {1'b0, core_remainder} + {1'b0, width} -
                               {1'b0, o_first_x};

    assign o_request_ready = i_rst_n && core_ready && state == S_IDLE;
    assign o_result_valid = i_rst_n && state == S_RESULT;

    // Parameters live in the TD-visible generated IP configuration.
    cfs_div_32u16u_l28 u_divider (
        .aclk(i_clk),
        .aresetn(core_reset_n),
        .s_axis_dividend_tdata(core_dividend),
        .s_axis_dividend_tvalid(core_input_valid),
        .s_axis_divisor_tdata(core_divisor),
        .s_axis_divisor_tvalid(core_input_valid),
        .m_axis_dout_tdata(core_data),
        .m_axis_dout_tvalid(core_valid)
    );

    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            state <= S_IDLE;
            startup_count <= 0;
            offset <= 0;
            width <= 0;
            first_x_seen <= 0;
            o_block <= 0;
            o_local <= 0;
            o_first_x <= 0;
            o_second_x <= 0;
            o_step_x <= 0;
            o_error <= 0;
        end else begin
            if (!core_ready)
                startup_count <= startup_count + 1'b1;
            case (state)
                S_IDLE: begin
                    if (i_request_valid && o_request_ready) begin
                        offset <= i_offset;
                        width <= i_width;
                        first_x_seen <= 0;
                        o_error <= i_width == 0;
                        if (i_width == 0) begin
                            o_block <= 0;
                            o_local <= 0;
                            o_first_x <= 0;
                            o_second_x <= 0;
                            o_step_x <= 0;
                            state <= S_RESULT;
                        end else begin
                            state <= S_BLOCK_ISSUE;
                        end
                    end
                end
                S_BLOCK_ISSUE: state <= S_BLOCK_WAIT;
                S_BLOCK_WAIT: begin
                    if (core_valid) begin
                        // offset = 512 * (5 * block + rem5) + low9.
                        o_block <= core_data[47:16];
                        o_local <= {core_remainder[2:0], offset[8:0]};
                        state <= S_FIRST_ISSUE;
                    end
                end
                S_FIRST_ISSUE: state <= S_SECOND_ISSUE;
                S_SECOND_ISSUE: state <= S_X_WAIT;
                S_X_WAIT: begin
                    if (core_valid) begin
                        if (!first_x_seen) begin
                            o_first_x <= core_remainder;
                            first_x_seen <= 1;
                        end else begin
                            o_second_x <= core_remainder;
                            o_step_x <= core_remainder >= o_first_x ?
                                        core_remainder - o_first_x : wrapped_step[15:0];
                            state <= S_RESULT;
                        end
                    end
                end
                S_RESULT: if (i_result_ready) state <= S_IDLE;
                default: begin
                    o_error <= 1;
                    state <= S_RESULT;
                end
            endcase
        end
    end
endmodule
