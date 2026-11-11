`timescale 1ns / 1ps

// Broadcast one control identity; only actual destination application replies
// satisfy the two-owner barrier. A SAME_CLOCK destination must be physically
// driven by i_source_clk; its true application handshake still owns the ACK.
module frame_config_fanout_cdc #(
    parameter integer EXT_WIDTH=0,
    parameter integer DEST0_SAME_CLOCK=0, DEST1_SAME_CLOCK=0
) (
    input wire i_source_clk, input wire i_source_rst_n,
    input wire [159+EXT_WIDTH:0] s_config_data, input wire s_config_valid,
    output wire s_config_ready,
    output wire [159+EXT_WIDTH:0] m_config_ack_data, output wire m_config_ack_valid,
    output wire m_config_ack_ok, input wire m_config_ack_ready,
    output wire o_source_reset_done, output wire [31:0] o_stale_ack_count,
    input wire i_dest0_clk, input wire i_dest0_rst_n,
    output wire [159+EXT_WIDTH:0] m_dest0_config_data, output wire m_dest0_config_valid,
    input wire m_dest0_config_ready,
    input wire [159+EXT_WIDTH:0] s_dest0_applied_data, input wire s_dest0_applied_valid,
    input wire s_dest0_applied_ok, output wire s_dest0_applied_ready,
    output wire o_dest0_reset_done,
    input wire i_dest1_clk, input wire i_dest1_rst_n,
    output wire [159+EXT_WIDTH:0] m_dest1_config_data, output wire m_dest1_config_valid,
    input wire m_dest1_config_ready,
    input wire [159+EXT_WIDTH:0] s_dest1_applied_data, input wire s_dest1_applied_valid,
    input wire s_dest1_applied_ok, output wire s_dest1_applied_ready,
    output wire o_dest1_reset_done
);
    wire cohort_rst_n = i_source_rst_n && i_dest0_rst_n && i_dest1_rst_n;
    generate if ((DEST0_SAME_CLOCK != 0 && DEST0_SAME_CLOCK != 1) ||
                 (DEST1_SAME_CLOCK != 0 && DEST1_SAME_CLOCK != 1)) begin:bad_same_clock
        FANOUT_SAME_CLOCK_MUST_BE_0_OR_1 invalid_configuration();
    end endgenerate
    reg [2:0] source_release, dest0_release, dest1_release;
    wire source_local_rst_n = source_release[2];
    wire dest0_local_rst_n = dest0_release[2];
    wire dest1_local_rst_n = dest1_release[2];
    reg owned, seen0, seen1, ok0, ok1;
    reg plan0_sent,plan1_sent;
    reg dest0_pending, dest1_pending;
    reg [159+EXT_WIDTH:0] owned_tuple;
    reg [31:0] stale_count;
    wire plan0_ready, plan1_ready, plan0_source_done, plan1_source_done;
    wire plan0_valid, plan1_valid, plan0_sink_done, plan1_sink_done;
    wire ack0_ready, ack1_ready, ack0_source_done, ack1_source_done;
    wire ack0_valid, ack1_valid, ack0_sink_done, ack1_sink_done;
    wire [160+EXT_WIDTH:0] ack0_data, ack1_data;
    wire plan_fire = s_config_valid && s_config_ready;
    wire dest0_plan_fire = m_dest0_config_valid && m_dest0_config_ready;
    wire dest1_plan_fire = m_dest1_config_valid && m_dest1_config_ready;
    wire dest0_ack_fire = s_dest0_applied_valid && s_dest0_applied_ready;
    wire dest1_ack_fire = s_dest1_applied_valid && s_dest1_applied_ready;
    wire ack0_fire = ack0_valid && o_source_reset_done;
    wire ack1_fire = ack1_valid && o_source_reset_done;
    wire ack0_match = owned && !seen0 && ack0_data[159+EXT_WIDTH:0] == owned_tuple;
    wire ack1_match = owned && !seen1 && ack1_data[159+EXT_WIDTH:0] == owned_tuple;
    wire reject0 = ack0_fire && !ack0_match;
    wire reject1 = ack1_fire && !ack1_match;

    assign o_source_reset_done = source_release[2] && plan0_source_done &&
        plan1_source_done && ack0_sink_done && ack1_sink_done;
    assign o_dest0_reset_done = dest0_release[2] && plan0_sink_done && ack0_source_done;
    assign o_dest1_reset_done = dest1_release[2] && plan1_sink_done && ack1_source_done;
    assign s_config_ready = o_source_reset_done && !owned;
    assign m_config_ack_data = owned_tuple;
    assign m_config_ack_valid = o_source_reset_done && owned && seen0 && seen1;
    assign m_config_ack_ok = ok0 && ok1;
    assign o_stale_ack_count = stale_count;
    assign m_dest0_config_valid = o_dest0_reset_done && plan0_valid && !dest0_pending;
    assign m_dest1_config_valid = o_dest1_reset_done && plan1_valid && !dest1_pending;
    assign s_dest0_applied_ready = o_dest0_reset_done && dest0_pending && ack0_ready;
    assign s_dest1_applied_ready = o_dest1_reset_done && dest1_pending && ack1_ready;

    // Any reset asserts the same packet cohort; only local edges release it.
    always @(posedge i_source_clk or negedge cohort_rst_n) begin
        if (!cohort_rst_n) source_release <= 0;
        else source_release <= {source_release[1:0],1'b1};
    end
    always @(posedge i_dest0_clk or negedge cohort_rst_n) begin
        if (!cohort_rst_n) dest0_release <= 0;
        else dest0_release <= {dest0_release[1:0],1'b1};
    end
    always @(posedge i_dest1_clk or negedge cohort_rst_n) begin
        if (!cohort_rst_n) dest1_release <= 0;
        else dest1_release <= {dest1_release[1:0],1'b1};
    end

    // Only the release chains receive the asynchronous cohort reset directly.
    always @(posedge i_dest0_clk or negedge dest0_local_rst_n) begin
        if (!dest0_local_rst_n) dest0_pending <= 0;
        else if (!o_dest0_reset_done) dest0_pending <= 0;
        else if (dest0_plan_fire) dest0_pending <= 1;
        else if (dest0_ack_fire && s_dest0_applied_data == m_dest0_config_data)
            dest0_pending <= 0;
    end
    always @(posedge i_dest1_clk or negedge dest1_local_rst_n) begin
        if (!dest1_local_rst_n) dest1_pending <= 0;
        else if (!o_dest1_reset_done) dest1_pending <= 0;
        else if (dest1_plan_fire) dest1_pending <= 1;
        else if (dest1_ack_fire && s_dest1_applied_data == m_dest1_config_data)
            dest1_pending <= 0;
    end

    always @(posedge i_source_clk or negedge source_local_rst_n) begin
        if (!source_local_rst_n) begin
            owned <= 0; seen0 <= 0; seen1 <= 0; ok0 <= 0; ok1 <= 0;
            plan0_sent<=0;plan1_sent<=0;
            owned_tuple <= 0; stale_count <= 0;
        end else if (!o_source_reset_done) begin
            owned <= 0; seen0 <= 0; seen1 <= 0; ok0 <= 0; ok1 <= 0;
            plan0_sent<=0;plan1_sent<=0;
            owned_tuple <= 0; stale_count <= 0;
        end else begin
            if (plan_fire) begin
                owned_tuple <= s_config_data; owned <= 1;
                seen0 <= 0; seen1 <= 0; ok0 <= 0; ok1 <= 0;
                plan0_sent<=0;plan1_sent<=0;
            end
            if(owned&&!plan0_sent&&plan0_ready)plan0_sent<=1;
            if(owned&&!plan1_sent&&plan1_ready)plan1_sent<=1;
            if (ack0_fire && ack0_match) begin seen0 <= 1; ok0 <= ack0_data[160+EXT_WIDTH]; end
            if (ack1_fire && ack1_match) begin seen1 <= 1; ok1 <= ack1_data[160+EXT_WIDTH]; end
            if (m_config_ack_valid && m_config_ack_ready) owned <= 0;
            if (reject0 || reject1) begin
                if (stale_count >= 32'hfffffffe) stale_count <= 32'hffffffff;
                else stale_count <= stale_count + (reject0 && reject1 ? 32'd2 : 32'd1);
            end
        end
    end

    generate if (DEST0_SAME_CLOCK != 0) begin:g_dest0_same_clock
        // owned_tuple cannot change until BOTH true applications are accepted
        // and the aggregate callback is consumed. No FIFO enqueue is an ACK.
        assign m_dest0_config_data = owned_tuple;
        assign plan0_valid = owned && !plan0_sent;
        assign plan0_ready = o_dest0_reset_done && !dest0_pending && m_dest0_config_ready;
        assign plan0_source_done = dest0_release[2];
        assign plan0_sink_done = source_release[2];
        assign ack0_source_done = source_release[2];
        assign ack0_sink_done = dest0_release[2];
        assign ack0_data = {s_dest0_applied_ok,s_dest0_applied_data};
        assign ack0_valid = s_dest0_applied_valid && dest0_pending && o_dest0_reset_done;
        assign ack0_ready = o_source_reset_done;
    end else begin:g_dest0_async
        control_message_fifo_ip #(.MESSAGE_WIDTH(160+EXT_WIDTH),.BORROW_SOURCE(1)) u_plan0 (
            .o_sink_flit_read(),.o_sink_flit_data(),.o_sink_flit_index(),
            .i_source_clk(i_source_clk),.i_source_rst_n(cohort_rst_n),
            .i_source_data(owned_tuple),
            .i_source_valid(owned && !plan0_sent && o_source_reset_done),
            .o_source_ready(plan0_ready),.o_source_reset_done(plan0_source_done),
            .i_sink_clk(i_dest0_clk),.i_sink_rst_n(cohort_rst_n),
            .o_sink_data(m_dest0_config_data),.o_sink_valid(plan0_valid),
            .i_sink_ready(m_dest0_config_ready && !dest0_pending && o_dest0_reset_done),
            .o_sink_reset_done(plan0_sink_done));
        control_message_fifo_ip #(.MESSAGE_WIDTH(161+EXT_WIDTH),.BORROW_SOURCE(1)) u_ack0 (
            .o_sink_flit_read(),.o_sink_flit_data(),.o_sink_flit_index(),
            .i_source_clk(i_dest0_clk),.i_source_rst_n(cohort_rst_n),
            .i_source_data({s_dest0_applied_ok,s_dest0_applied_data}),
            .i_source_valid(s_dest0_applied_valid && dest0_pending && o_dest0_reset_done),
            .o_source_ready(ack0_ready),.o_source_reset_done(ack0_source_done),
            .i_sink_clk(i_source_clk),.i_sink_rst_n(cohort_rst_n),
            .o_sink_data(ack0_data),.o_sink_valid(ack0_valid),
            .i_sink_ready(o_source_reset_done),.o_sink_reset_done(ack0_sink_done));
    end endgenerate
    generate if (DEST1_SAME_CLOCK != 0) begin:g_dest1_same_clock
        // owned_tuple cannot change until BOTH true applications are accepted
        // and the aggregate callback is consumed. No FIFO enqueue is an ACK.
        assign m_dest1_config_data = owned_tuple;
        assign plan1_valid = owned && !plan1_sent;
        assign plan1_ready = o_dest1_reset_done && !dest1_pending && m_dest1_config_ready;
        assign plan1_source_done = dest1_release[2];
        assign plan1_sink_done = source_release[2];
        assign ack1_source_done = source_release[2];
        assign ack1_sink_done = dest1_release[2];
        assign ack1_data = {s_dest1_applied_ok,s_dest1_applied_data};
        assign ack1_valid = s_dest1_applied_valid && dest1_pending && o_dest1_reset_done;
        assign ack1_ready = o_source_reset_done;
    end else begin:g_dest1_async
        control_message_fifo_ip #(.MESSAGE_WIDTH(160+EXT_WIDTH),.BORROW_SOURCE(1)) u_plan1 (
            .o_sink_flit_read(),.o_sink_flit_data(),.o_sink_flit_index(),
            .i_source_clk(i_source_clk),.i_source_rst_n(cohort_rst_n),
            .i_source_data(owned_tuple),
            .i_source_valid(owned && !plan1_sent && o_source_reset_done),
            .o_source_ready(plan1_ready),.o_source_reset_done(plan1_source_done),
            .i_sink_clk(i_dest1_clk),.i_sink_rst_n(cohort_rst_n),
            .o_sink_data(m_dest1_config_data),.o_sink_valid(plan1_valid),
            .i_sink_ready(m_dest1_config_ready && !dest1_pending && o_dest1_reset_done),
            .o_sink_reset_done(plan1_sink_done));
        control_message_fifo_ip #(.MESSAGE_WIDTH(161+EXT_WIDTH),.BORROW_SOURCE(1)) u_ack1 (
            .o_sink_flit_read(),.o_sink_flit_data(),.o_sink_flit_index(),
            .i_source_clk(i_dest1_clk),.i_source_rst_n(cohort_rst_n),
            .i_source_data({s_dest1_applied_ok,s_dest1_applied_data}),
            .i_source_valid(s_dest1_applied_valid && dest1_pending && o_dest1_reset_done),
            .o_source_ready(ack1_ready),.o_source_reset_done(ack1_source_done),
            .i_sink_clk(i_source_clk),.i_sink_rst_n(cohort_rst_n),
            .o_sink_data(ack1_data),.o_sink_valid(ack1_valid),
            .i_sink_ready(o_source_reset_done),.o_sink_reset_done(ack1_sink_done));
    end endgenerate
endmodule
