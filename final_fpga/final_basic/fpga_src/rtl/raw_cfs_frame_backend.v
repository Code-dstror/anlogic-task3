`timescale 1ns/1ps
// Slot allocation/reference/publication remain in raw_frame_store.
module raw_cfs_frame_backend #(
    parameter integer OFFICIAL_CRC_QUALIFIED=0,
    parameter [3:0] AXI_ID=4'd1
) (
    input wire i_clk,i_rst_n,
    input wire [1:0] i_begin_valid,output wire [1:0] o_begin_ready,
    input wire [383:0] i_frame0,i_frame1,
    input wire [27:0] i_base0,i_base1,input wire [31:0] i_slot_span,
    input wire [31:0] i_samples0,i_samples1,input wire [15:0] i_width0,i_width1,
    input wire [1:0] i_valid,output wire [1:0] o_ready,
    input wire [255:0] i_data,input wire [31:0] i_keep,input wire [1:0] i_last,
    input wire [19:0] i_available,
    input wire [1:0] i_end_valid,i_end_ok,output wire [1:0] o_end_ready,
    output wire [1:0] o_result_valid,o_result_ok,input wire [1:0] i_result_ready,
    input wire i_read_request_valid,output wire o_read_request_ready,
    input wire [383:0] i_read_frame,input wire [27:0] i_read_base,
    input wire [31:0] i_read_samples,i_read_offset,i_read_length,
    input wire [15:0] i_read_width,input wire i_read_retire,
    output wire o_read_valid,input wire i_read_ready,output wire [127:0] o_read_data,
    output wire [15:0] o_read_keep,output wire o_read_last,o_read_done,o_read_error,
    output reg [31:0] o_compressed_count,o_no_benefit_count,o_overflow_count,o_busy_count,
    output wire o_protocol_fault,o_write_idle,
    output wire [3:0] m_axi_awid,output wire [27:0] m_axi_awaddr,
    output wire [7:0] m_axi_awlen,output wire [2:0] m_axi_awsize,
    output wire [1:0] m_axi_awburst,output wire m_axi_awvalid,input wire m_axi_awready,
    output wire [127:0] m_axi_wdata,output wire [15:0] m_axi_wstrb,
    output wire m_axi_wlast,m_axi_wvalid,input wire m_axi_wready,
    input wire [3:0] m_axi_bid,input wire [1:0] m_axi_bresp,input wire m_axi_bvalid,
    output wire m_axi_bready,
    output wire [3:0] m_axi_arid,output wire [27:0] m_axi_araddr,
    output wire [7:0] m_axi_arlen,output wire [2:0] m_axi_arsize,
    output wire [1:0] m_axi_arburst,output wire m_axi_arvalid,input wire m_axi_arready,
    input wire [3:0] m_axi_rid,input wire [127:0] m_axi_rdata,
    input wire [1:0] m_axi_rresp,input wire m_axi_rlast,m_axi_rvalid,
    output wire m_axi_rready
);
    wire  n_i_cancel;
    wire  n_i_source_abort;
    wire  n_i_plan_valid;
    wire  n_o_plan_ready;
    wire [383:0] n_i_frame;
    wire [159:0] n_i_context;
    wire [63:0] n_i_tag;
    wire [31:0] n_i_generation;
    wire [31:0] n_i_block_id;
    wire [27:0] n_i_slot_base;
    wire [31:0] n_i_slot_span;
    wire [31:0] n_i_data_offset;
    wire [11:0] n_i_samples;
    wire [15:0] n_i_width;
    wire [15:0] n_i_start_x;
    wire  n_i_valid;
    wire  n_o_ready;
    wire [31:0] n_i_data;
    wire [3:0] n_i_keep;
    wire  n_i_last;
    wire  n_i_fast_plan_valid;
    wire  n_o_fast_plan_ready;
    wire [383:0] n_i_fast_frame;
    wire [159:0] n_i_fast_context;
    wire [63:0] n_i_fast_tag;
    wire [31:0] n_i_fast_generation;
    wire [31:0] n_i_fast_block_id;
    wire [27:0] n_i_fast_slot_base;
    wire [31:0] n_i_fast_slot_span;
    wire [31:0] n_i_fast_data_offset;
    wire [11:0] n_i_fast_samples;
    wire  n_i_fast_cancel;
    wire  n_i_fast_source_abort;
    wire  n_o_fast_ready;
    wire n_i_fast_valid,n_i_fast_last;
    wire [127:0] n_i_fast_data;
    wire [15:0] n_i_fast_keep;
    wire [9:0] n_i_fast_available;
    wire  n_o_fast_crc_start_valid;
    wire  n_i_fast_crc_start_ready;
    wire [11:0] n_o_fast_crc_length;
    wire  n_o_fast_crc_tap_valid;
    wire  n_i_fast_crc_tap_ready;
    wire [127:0] n_o_fast_crc_tap_data;
    wire [15:0] n_o_fast_crc_tap_keep;
    wire  n_o_fast_crc_tap_last;
    wire  n_i_fast_crc_result_valid;
    wire  n_o_fast_crc_result_ready;
    wire [383:0] n_i_fast_crc_frame;
    wire [159:0] n_i_fast_crc_context;
    wire [63:0] n_i_fast_crc_tag;
    wire [31:0] n_i_fast_crc_generation;
    wire [31:0] n_i_fast_crc_block_id;
    wire [31:0] n_i_fast_crc;
    wire [11:0] n_i_fast_crc_length;
    wire  n_i_fast_crc_ok;
    wire  n_o_crc_request_valid;
    wire  n_i_crc_request_ready;
    wire [383:0] n_o_crc_frame;
    wire [159:0] n_o_crc_context;
    wire [63:0] n_o_crc_tag;
    wire [31:0] n_o_crc_generation;
    wire [31:0] n_o_crc_block_id;
    wire  n_o_crc_stored;
    wire [11:0] n_o_crc_length;
    wire  n_o_crc_data_valid;
    wire  n_i_crc_data_ready;
    wire [31:0] n_o_crc_data;
    wire [3:0] n_o_crc_keep;
    wire  n_o_crc_last;
    wire  n_i_crc_result_valid;
    wire  n_o_crc_result_ready;
    wire [383:0] n_i_crc_frame;
    wire [159:0] n_i_crc_context;
    wire [63:0] n_i_crc_tag;
    wire [31:0] n_i_crc_generation;
    wire [31:0] n_i_crc_block_id;
    wire [31:0] n_i_crc;
    wire [11:0] n_i_crc_length;
    wire  n_i_crc_stored;
    wire  n_i_crc_ok;
    wire [1:0] n_o_cache_write_enable;
    wire [19:0] n_o_cache_write_address;
    wire [63:0] n_o_cache_write_data;
    wire [1:0] n_o_cache_read_enable;
    wire [19:0] n_o_cache_read_address;
    wire [3:0] n_m_axi_awid;
    wire [27:0] n_m_axi_awaddr;
    wire [7:0] n_m_axi_awlen;
    wire [2:0] n_m_axi_awsize;
    wire [1:0] n_m_axi_awburst;
    wire  n_m_axi_awvalid;
    wire  n_m_axi_awready;
    wire [127:0] n_m_axi_wdata;
    wire [15:0] n_m_axi_wstrb;
    wire  n_m_axi_wlast;
    wire  n_m_axi_wvalid;
    wire  n_m_axi_wready;
    wire [3:0] n_m_axi_bid;
    wire [1:0] n_m_axi_bresp;
    wire  n_m_axi_bvalid;
    wire  n_m_axi_bready;
    wire  n_o_ack_valid;
    wire  n_i_ack_ready;
    wire  n_o_ack_ok;
    wire [7:0] n_o_ack_error;
    wire [1:0] n_o_ack_reason;
    wire [383:0] n_o_ack_frame;
    wire [159:0] n_o_ack_context;
    wire [63:0] n_o_ack_tag;
    wire [31:0] n_o_ack_generation;
    wire [31:0] n_o_ack_block_id;
    wire [11:0] n_o_ack_stored_length;
    wire  n_o_ack_compressed;
    wire  n_o_fast_ack_valid;
    wire  n_i_fast_ack_ready;
    wire  n_o_fast_ack_ok;
    wire [7:0] n_o_fast_ack_error;
    wire [383:0] n_o_fast_ack_frame;
    wire [159:0] n_o_fast_ack_context;
    wire [63:0] n_o_fast_ack_tag;
    wire [31:0] n_o_fast_ack_generation;
    wire [31:0] n_o_fast_ack_block_id;
    wire [31:0] n_o_stale_crc_count;
    wire  n_o_protocol_fault;
    wire  n_o_idle;
    wire  r_i_cancel;
    wire  r_i_plan_valid;
    wire  r_o_plan_ready;
    wire [383:0] r_i_frame;
    wire [159:0] r_i_context;
    wire [63:0] r_i_tag;
    wire [31:0] r_i_generation;
    wire [31:0] r_i_total_samples;
    wire [31:0] r_i_block_count;
    wire [27:0] r_i_slot_base;
    wire [31:0] r_i_slot_span;
    wire [31:0] r_i_data_offset;
    wire [31:0] r_i_range_offset;
    wire [31:0] r_i_first_block;
    wire [11:0] r_i_range_length;
    wire [11:0] r_i_first_offset;
    wire [15:0] r_i_width;
    wire [15:0] r_i_first_start_x;
    wire [15:0] r_i_second_start_x;
    wire [2:0] r_o_cache_write_enable;
    wire [29:0] r_o_cache_write_address;
    wire [95:0] r_o_cache_write_data;
    wire [2:0] r_o_cache_read_enable;
    wire [29:0] r_o_cache_read_address;
    wire  r_o_crc_request_valid;
    wire  r_i_crc_request_ready;
    wire [383:0] r_o_crc_frame;
    wire [159:0] r_o_crc_context;
    wire [63:0] r_o_crc_tag;
    wire [31:0] r_o_crc_generation;
    wire [31:0] r_o_crc_block_id;
    wire  r_o_crc_stored;
    wire [11:0] r_o_crc_length;
    wire  r_o_crc_data_valid;
    wire  r_i_crc_data_ready;
    wire [31:0] r_o_crc_data;
    wire [3:0] r_o_crc_keep;
    wire  r_o_crc_last;
    wire  r_i_crc_result_valid;
    wire  r_o_crc_result_ready;
    wire [383:0] r_i_crc_frame;
    wire [159:0] r_i_crc_context;
    wire [63:0] r_i_crc_tag;
    wire [31:0] r_i_crc_generation;
    wire [31:0] r_i_crc_block_id;
    wire [31:0] r_i_crc;
    wire [11:0] r_i_crc_length;
    wire  r_i_crc_stored;
    wire  r_i_crc_ok;
    wire [3:0] r_m_axi_arid;
    wire [27:0] r_m_axi_araddr;
    wire [7:0] r_m_axi_arlen;
    wire [2:0] r_m_axi_arsize;
    wire [1:0] r_m_axi_arburst;
    wire  r_m_axi_arvalid;
    wire  r_m_axi_arready;
    wire [3:0] r_m_axi_rid;
    wire [127:0] r_m_axi_rdata;
    wire [1:0] r_m_axi_rresp;
    wire  r_m_axi_rlast;
    wire  r_m_axi_rvalid;
    wire  r_m_axi_rready;
    wire  r_o_valid;
    wire  r_i_ready;
    wire [127:0] r_o_data;
    wire [15:0] r_o_keep;
    wire  r_o_last;
    wire [383:0] r_o_frame;
    wire [159:0] r_o_context;
    wire [63:0] r_o_tag;
    wire  r_o_ack_valid;
    wire  r_i_ack_ready;
    wire  r_o_ack_ok;
    wire [7:0] r_o_ack_error;
    wire [11:0] r_o_ack_count;
    wire [31:0] r_o_stale_crc_count;
    wire  r_o_protocol_fault;
    wire  r_o_idle;
    localparam [1:0] C_SELECT=0,C_NORMAL=1,C_FAST=2;
    reg [1:0] lane_state[0:1];
    reg [1:0] active,closed,source_ok,failed,result;
    reg [383:0] frame[0:1];
    reg [27:0] base[0:1];
    reg [31:0] total_samples[0:1],block_count[0:1],data_offset[0:1];
    reg [31:0] next_block[0:1],accepted_bytes[0:1],acked_blocks[0:1];
    reg [15:0] width[0:1];
    reg [31:0] next_x[0:1];
    reg turn,normal_owner,fast_owner;
    reg normal_offer,fast_offer,normal_pending,fast_pending;
    reg normal_closed,fast_closed;
    reg [31:0] normal_block,fast_block;
    reg [11:0] normal_samples,fast_samples,normal_left,fast_left;
    reg [15:0] normal_x;
    reg [127:0] held_data;
    reg [15:0] held_keep;
    reg held_valid,held_block_last;
    reg [1:0] held_lane;
    reg [1:0] cache_owner;
    wire fetch_phase=cache_owner==2;
    wire [95:0] cache_read_data;
    wire [127:0] input_data[0:1];
    wire [15:0] input_keep[0:1];
    wire [9:0] input_available[0:1];
    assign input_data[0]=i_data[127:0];assign input_data[1]=i_data[255:128];
    assign input_keep[0]=i_keep[15:0];assign input_keep[1]=i_keep[31:16];
    assign input_available[0]=i_available[9:0];assign input_available[1]=i_available[19:10];
    function [4:0] bytes16;
        input [15:0] keep;integer b;
        begin bytes16=0;for(b=0;b<16;b=b+1)bytes16=bytes16+keep[b];end
    endfunction
    wire [1:0] source_fire=i_valid&o_ready;
    wire normal_fire=n_i_valid&&n_o_ready;
    wire normal_last_word=held_block_last&&(held_keep>>(held_lane*4+4))==0;
    wire normal_ack=n_o_ack_valid&&normal_pending;
    wire fast_ack=n_o_fast_ack_valid&&fast_pending;
    wire normal_match=n_o_ack_frame==frame[normal_owner]&&n_o_ack_generation==frame[normal_owner][44:13]&&
        n_o_ack_block_id==normal_block&&n_o_ack_context==frame[normal_owner][159:0]&&
        n_o_ack_tag=={frame[normal_owner][76:45],frame[normal_owner][108:77]};
    wire fast_match=n_o_fast_ack_frame==frame[fast_owner]&&n_o_fast_ack_generation==frame[fast_owner][44:13]&&
        n_o_fast_ack_block_id==fast_block&&n_o_fast_ack_context==frame[fast_owner][159:0]&&
        n_o_fast_ack_tag=={frame[fast_owner][76:45],frame[fast_owner][108:77]};
    wire [1:0] runnable;
    genvar p;
    generate for(p=0;p<2;p=p+1)begin:g_lane
        assign runnable[p]=active[p]&&!closed[p]&&!failed[p]&&lane_state[p]==C_SELECT&&
            next_block[p]<block_count[p]&&next_x[p]<width[p]&&i_valid[p];
        assign o_begin_ready[p]=i_rst_n&&!active[p]&&!result[p]&&!o_protocol_fault;
        assign o_end_ready[p]=i_rst_n&&active[p]&&!closed[p];
        assign o_result_valid[p]=i_rst_n&&result[p];
        assign o_result_ok[p]=!failed[p]&&source_ok[p]&&acked_blocks[p]==block_count[p]&&
            accepted_bytes[p]==((total_samples[p]*64'd10+7)>>3);
        assign o_ready[p]=i_rst_n&&active[p]&&!closed[p]&&
            (failed[p] ? 1'b1 : (lane_state[p]==C_NORMAL ? (!held_valid&&normal_pending&&!normal_offer) :
            (lane_state[p]==C_FAST ? (fast_pending&&!fast_offer&&n_o_fast_ready) :
            (lane_state[p]==C_SELECT&&next_block[p]>=block_count[p]))));
    end endgenerate
    wire selected_lane=(&runnable)?turn:runnable[1];
    wire fast_available=!fast_pending&&!fast_offer;
    wire [31:0] selected_remaining=total_samples[selected_lane]-(next_block[selected_lane]<<11);
    wire [11:0] selected_samples=selected_remaining>=2048?12'd2048:selected_remaining[11:0];
    localparam [3:0] D_IDLE=0,D_MAP=1,D_X=2,D_SECOND_X=3,D_CACHE=4,D_PLAN=5,D_RUN=6,D_DONE=7;
    reg [3:0] read_state;
    wire normal_available=!normal_pending&&!normal_offer&&cache_owner==0&&read_state!=D_CACHE;
    reg [383:0] read_frame;
    reg [27:0] read_base;
    reg [31:0] read_samples,read_blocks,read_data_offset,read_offset,read_left,read_block,map_offset;
    reg [15:0] read_x,read_second_x,read_step_x;
    reg [15:0] read_width;
    reg [11:0] read_local,read_chunk;
    reg read_error,map_cold;
    wire locator_ready,locator_valid,locator_error;
    wire [31:0] locator_block;
    wire [11:0] locator_local;
    wire [15:0] locator_first_x,locator_second_x,locator_step_x;
    wire [16:0] replay_x_sum={1'b0,read_second_x}+{1'b0,read_step_x};
    wire [16:0] replay_x_wrapped=replay_x_sum-{1'b0,read_width};
    wire [15:0] replay_next_x=replay_x_sum>={1'b0,read_width}?
                              replay_x_wrapped[15:0]:replay_x_sum[15:0];
    assign o_read_request_ready=i_rst_n&&read_state==D_IDLE&&!o_protocol_fault&&locator_ready;
    assign o_read_valid=r_o_valid&&read_state==D_RUN;
    assign o_read_data=r_o_data;assign o_read_keep=r_o_keep;
    assign o_read_last=r_o_last&&read_left<=16;
    assign o_read_done=i_rst_n&&read_state==D_DONE;assign o_read_error=read_error;
    assign o_protocol_fault=n_o_protocol_fault||r_o_protocol_fault;
    assign o_write_idle=n_o_idle&&!normal_offer&&!fast_offer&&active==0;
    integer lane;
    cfs_read_locator u_read_locator (
        .i_clk(i_clk),.i_rst_n(i_rst_n),
        .i_request_valid(read_state==D_MAP&&map_cold),.o_request_ready(locator_ready),
        .i_offset(read_offset),.i_width(read_width),
        .o_result_valid(locator_valid),.i_result_ready(read_state==D_X),
        .o_block(locator_block),.o_local(locator_local),
        .o_first_x(locator_first_x),.o_second_x(locator_second_x),.o_step_x(locator_step_x),
        .o_error(locator_error)
    );
    cfs_block_transaction #(.OFFICIAL_CRC_QUALIFIED(OFFICIAL_CRC_QUALIFIED),.AXI_ID(AXI_ID)) u_n (
        .i_clk(i_clk),
        .i_rst_n(i_rst_n),
        .i_cancel(n_i_cancel),
        .i_source_abort(n_i_source_abort),
        .i_plan_valid(n_i_plan_valid),
        .o_plan_ready(n_o_plan_ready),
        .i_frame(n_i_frame),
        .i_context(n_i_context),
        .i_tag(n_i_tag),
        .i_generation(n_i_generation),
        .i_block_id(n_i_block_id),
        .i_slot_base(n_i_slot_base),
        .i_slot_span(n_i_slot_span),
        .i_data_offset(n_i_data_offset),
        .i_samples(n_i_samples),
        .i_width(n_i_width),
        .i_start_x(n_i_start_x),
        .i_valid(n_i_valid),
        .o_ready(n_o_ready),
        .i_data(n_i_data),
        .i_keep(n_i_keep),
        .i_last(n_i_last),
        .i_fast_plan_valid(n_i_fast_plan_valid),
        .o_fast_plan_ready(n_o_fast_plan_ready),
        .i_fast_frame(n_i_fast_frame),
        .i_fast_context(n_i_fast_context),
        .i_fast_tag(n_i_fast_tag),
        .i_fast_generation(n_i_fast_generation),
        .i_fast_block_id(n_i_fast_block_id),
        .i_fast_slot_base(n_i_fast_slot_base),
        .i_fast_slot_span(n_i_fast_slot_span),
        .i_fast_data_offset(n_i_fast_data_offset),
        .i_fast_samples(n_i_fast_samples),
        .i_fast_cancel(n_i_fast_cancel),
        .i_fast_source_abort(n_i_fast_source_abort),
        .i_fast_valid(n_i_fast_valid),
        .o_fast_ready(n_o_fast_ready),
        .i_fast_data(n_i_fast_data),
        .i_fast_keep(n_i_fast_keep),
        .i_fast_last(n_i_fast_last),
        .i_fast_available(n_i_fast_available),
        .o_fast_crc_start_valid(n_o_fast_crc_start_valid),
        .i_fast_crc_start_ready(n_i_fast_crc_start_ready),
        .o_fast_crc_length(n_o_fast_crc_length),
        .o_fast_crc_tap_valid(n_o_fast_crc_tap_valid),
        .i_fast_crc_tap_ready(n_i_fast_crc_tap_ready),
        .o_fast_crc_tap_data(n_o_fast_crc_tap_data),
        .o_fast_crc_tap_keep(n_o_fast_crc_tap_keep),
        .o_fast_crc_tap_last(n_o_fast_crc_tap_last),
        .i_fast_crc_result_valid(n_i_fast_crc_result_valid),
        .o_fast_crc_result_ready(n_o_fast_crc_result_ready),
        .i_fast_crc_frame(n_i_fast_crc_frame),
        .i_fast_crc_context(n_i_fast_crc_context),
        .i_fast_crc_tag(n_i_fast_crc_tag),
        .i_fast_crc_generation(n_i_fast_crc_generation),
        .i_fast_crc_block_id(n_i_fast_crc_block_id),
        .i_fast_crc(n_i_fast_crc),
        .i_fast_crc_length(n_i_fast_crc_length),
        .i_fast_crc_ok(n_i_fast_crc_ok),
        .o_crc_request_valid(n_o_crc_request_valid),
        .i_crc_request_ready(n_i_crc_request_ready),
        .o_crc_frame(n_o_crc_frame),
        .o_crc_context(n_o_crc_context),
        .o_crc_tag(n_o_crc_tag),
        .o_crc_generation(n_o_crc_generation),
        .o_crc_block_id(n_o_crc_block_id),
        .o_crc_stored(n_o_crc_stored),
        .o_crc_length(n_o_crc_length),
        .o_crc_data_valid(n_o_crc_data_valid),
        .i_crc_data_ready(n_i_crc_data_ready),
        .o_crc_data(n_o_crc_data),
        .o_crc_keep(n_o_crc_keep),
        .o_crc_last(n_o_crc_last),
        .i_crc_result_valid(n_i_crc_result_valid),
        .o_crc_result_ready(n_o_crc_result_ready),
        .i_crc_frame(n_i_crc_frame),
        .i_crc_context(n_i_crc_context),
        .i_crc_tag(n_i_crc_tag),
        .i_crc_generation(n_i_crc_generation),
        .i_crc_block_id(n_i_crc_block_id),
        .i_crc(n_i_crc),
        .i_crc_length(n_i_crc_length),
        .i_crc_stored(n_i_crc_stored),
        .i_crc_ok(n_i_crc_ok),
        .o_cache_write_enable(n_o_cache_write_enable),
        .o_cache_write_address(n_o_cache_write_address),
        .o_cache_write_data(n_o_cache_write_data),
        .o_cache_read_enable(n_o_cache_read_enable),
        .o_cache_read_address(n_o_cache_read_address),
        .i_cache_read_data(cache_read_data[63:0]),
        .m_axi_awid(n_m_axi_awid),
        .m_axi_awaddr(n_m_axi_awaddr),
        .m_axi_awlen(n_m_axi_awlen),
        .m_axi_awsize(n_m_axi_awsize),
        .m_axi_awburst(n_m_axi_awburst),
        .m_axi_awvalid(n_m_axi_awvalid),
        .m_axi_awready(n_m_axi_awready),
        .m_axi_wdata(n_m_axi_wdata),
        .m_axi_wstrb(n_m_axi_wstrb),
        .m_axi_wlast(n_m_axi_wlast),
        .m_axi_wvalid(n_m_axi_wvalid),
        .m_axi_wready(n_m_axi_wready),
        .m_axi_bid(n_m_axi_bid),
        .m_axi_bresp(n_m_axi_bresp),
        .m_axi_bvalid(n_m_axi_bvalid),
        .m_axi_bready(n_m_axi_bready),
        .o_ack_valid(n_o_ack_valid),
        .i_ack_ready(n_i_ack_ready),
        .o_ack_ok(n_o_ack_ok),
        .o_ack_error(n_o_ack_error),
        .o_ack_reason(n_o_ack_reason),
        .o_ack_frame(n_o_ack_frame),
        .o_ack_context(n_o_ack_context),
        .o_ack_tag(n_o_ack_tag),
        .o_ack_generation(n_o_ack_generation),
        .o_ack_block_id(n_o_ack_block_id),
        .o_ack_stored_length(n_o_ack_stored_length),
        .o_ack_compressed(n_o_ack_compressed),
        .o_fast_ack_valid(n_o_fast_ack_valid),
        .i_fast_ack_ready(n_i_fast_ack_ready),
        .o_fast_ack_ok(n_o_fast_ack_ok),
        .o_fast_ack_error(n_o_fast_ack_error),
        .o_fast_ack_frame(n_o_fast_ack_frame),
        .o_fast_ack_context(n_o_fast_ack_context),
        .o_fast_ack_tag(n_o_fast_ack_tag),
        .o_fast_ack_generation(n_o_fast_ack_generation),
        .o_fast_ack_block_id(n_o_fast_ack_block_id),
        .o_stale_crc_count(n_o_stale_crc_count),
        .o_protocol_fault(n_o_protocol_fault),
        .o_idle(n_o_idle)
    );
    cfs_block_fetch #(.OFFICIAL_CRC_QUALIFIED(OFFICIAL_CRC_QUALIFIED),.AXI_ID(AXI_ID)) u_r (
        .i_clk(i_clk),
        .i_rst_n(i_rst_n),
        .i_cancel(r_i_cancel),
        .i_plan_valid(r_i_plan_valid),
        .o_plan_ready(r_o_plan_ready),
        .i_frame(r_i_frame),
        .i_context(r_i_context),
        .i_tag(r_i_tag),
        .i_generation(r_i_generation),
        .i_total_samples(r_i_total_samples),
        .i_block_count(r_i_block_count),
        .i_slot_base(r_i_slot_base),
        .i_slot_span(r_i_slot_span),
        .i_data_offset(r_i_data_offset),
        .i_range_offset(r_i_range_offset),
        .i_first_block(r_i_first_block),
        .i_range_length(r_i_range_length),
        .i_first_offset(r_i_first_offset),
        .i_width(r_i_width),
        .i_first_start_x(r_i_first_start_x),
        .i_second_start_x(r_i_second_start_x),
        .o_cache_write_enable(r_o_cache_write_enable),
        .o_cache_write_address(r_o_cache_write_address),
        .o_cache_write_data(r_o_cache_write_data),
        .o_cache_read_enable(r_o_cache_read_enable),
        .o_cache_read_address(r_o_cache_read_address),
        .i_cache_read_data(cache_read_data),
        .o_crc_request_valid(r_o_crc_request_valid),
        .i_crc_request_ready(r_i_crc_request_ready),
        .o_crc_frame(r_o_crc_frame),
        .o_crc_context(r_o_crc_context),
        .o_crc_tag(r_o_crc_tag),
        .o_crc_generation(r_o_crc_generation),
        .o_crc_block_id(r_o_crc_block_id),
        .o_crc_stored(r_o_crc_stored),
        .o_crc_length(r_o_crc_length),
        .o_crc_data_valid(r_o_crc_data_valid),
        .i_crc_data_ready(r_i_crc_data_ready),
        .o_crc_data(r_o_crc_data),
        .o_crc_keep(r_o_crc_keep),
        .o_crc_last(r_o_crc_last),
        .i_crc_result_valid(r_i_crc_result_valid),
        .o_crc_result_ready(r_o_crc_result_ready),
        .i_crc_frame(r_i_crc_frame),
        .i_crc_context(r_i_crc_context),
        .i_crc_tag(r_i_crc_tag),
        .i_crc_generation(r_i_crc_generation),
        .i_crc_block_id(r_i_crc_block_id),
        .i_crc(r_i_crc),
        .i_crc_length(r_i_crc_length),
        .i_crc_stored(r_i_crc_stored),
        .i_crc_ok(r_i_crc_ok),
        .m_axi_arid(r_m_axi_arid),
        .m_axi_araddr(r_m_axi_araddr),
        .m_axi_arlen(r_m_axi_arlen),
        .m_axi_arsize(r_m_axi_arsize),
        .m_axi_arburst(r_m_axi_arburst),
        .m_axi_arvalid(r_m_axi_arvalid),
        .m_axi_arready(r_m_axi_arready),
        .m_axi_rid(r_m_axi_rid),
        .m_axi_rdata(r_m_axi_rdata),
        .m_axi_rresp(r_m_axi_rresp),
        .m_axi_rlast(r_m_axi_rlast),
        .m_axi_rvalid(r_m_axi_rvalid),
        .m_axi_rready(r_m_axi_rready),
        .o_valid(r_o_valid),
        .i_ready(r_i_ready),
        .o_data(r_o_data),
        .o_keep(r_o_keep),
        .o_last(r_o_last),
        .o_frame(r_o_frame),
        .o_context(r_o_context),
        .o_tag(r_o_tag),
        .o_ack_valid(r_o_ack_valid),
        .i_ack_ready(r_i_ack_ready),
        .o_ack_ok(r_o_ack_ok),
        .o_ack_error(r_o_ack_error),
        .o_ack_count(r_o_ack_count),
        .o_stale_crc_count(r_o_stale_crc_count),
        .o_protocol_fault(r_o_protocol_fault),
        .o_idle(r_o_idle)
    );
    wire crc_request_ready,crc_data_ready,crc_result_valid,crc_result_ready,crc_result_ok;
    wire [383:0] actual_crc_frame;
    wire [159:0] actual_crc_context;
    wire [63:0] actual_crc_tag;
    wire [31:0] actual_crc_generation,actual_crc_block,actual_crc;
    wire [11:0] actual_crc_length;
    wire actual_crc_stored;
    assign n_i_crc_request_ready=!fetch_phase && crc_request_ready;
    assign r_i_crc_request_ready=fetch_phase && crc_request_ready;
    assign n_i_crc_data_ready=!fetch_phase && crc_data_ready;
    assign r_i_crc_data_ready=fetch_phase && crc_data_ready;
    assign n_i_crc_result_valid=crc_result_valid && !fetch_phase;
    assign r_i_crc_result_valid=crc_result_valid && fetch_phase;
    assign crc_result_ready=(fetch_phase ? r_o_crc_result_ready : n_o_crc_result_ready);
    assign n_i_crc_frame=actual_crc_frame;assign r_i_crc_frame=actual_crc_frame;
    assign n_i_crc_context=actual_crc_context;assign r_i_crc_context=actual_crc_context;
    assign n_i_crc_tag=actual_crc_tag;
    assign r_i_crc_tag=n_i_crc_tag;
    assign n_i_crc_generation=actual_crc_generation;assign r_i_crc_generation=actual_crc_generation;
    assign n_i_crc_block_id=actual_crc_block;assign r_i_crc_block_id=actual_crc_block;
    assign n_i_crc_length=actual_crc_length;assign r_i_crc_length=actual_crc_length;
    assign n_i_crc_stored=actual_crc_stored;assign r_i_crc_stored=actual_crc_stored;
    assign n_i_crc=actual_crc;assign r_i_crc=actual_crc;
    assign n_i_crc_ok=crc_result_ok;assign r_i_crc_ok=crc_result_ok;
    cfs_crc32_adapter #(.INPUT_BYTES(4),.PREFIX_CORES(1)) u_actual_crc(
        .i_clk(i_clk),.i_rst_n(i_rst_n),.i_abort(1'b0),
        .i_request_valid(fetch_phase ? r_o_crc_request_valid : n_o_crc_request_valid),
        .o_request_ready(crc_request_ready),
        .i_frame(fetch_phase ? r_o_crc_frame : n_o_crc_frame),
        .i_context(fetch_phase ? r_o_crc_context : n_o_crc_context),
        .i_tag(fetch_phase ? r_o_crc_tag : n_o_crc_tag),
        .i_generation(fetch_phase ? r_o_crc_generation : n_o_crc_generation),
        .i_block_id(fetch_phase ? r_o_crc_block_id : n_o_crc_block_id),
        .i_stored(fetch_phase ? r_o_crc_stored : n_o_crc_stored),
        .i_length(fetch_phase ? r_o_crc_length : n_o_crc_length),
        .i_data_valid(fetch_phase ? r_o_crc_data_valid : n_o_crc_data_valid),
        .o_data_ready(crc_data_ready),.i_data(fetch_phase ? r_o_crc_data : n_o_crc_data),
        .i_keep(fetch_phase ? r_o_crc_keep : n_o_crc_keep),
        .i_last(fetch_phase ? r_o_crc_last : n_o_crc_last),
        .o_result_valid(crc_result_valid),.i_result_ready(crc_result_ready),
        .o_frame(actual_crc_frame),.o_context(actual_crc_context),.o_tag(actual_crc_tag),
        .o_generation(actual_crc_generation),.o_block_id(actual_crc_block),
        .o_stored(actual_crc_stored),.o_length(actual_crc_length),.o_crc(actual_crc),.o_ok(crc_result_ok));
    cfs_crc32_adapter #(.INPUT_BYTES(16),.PREFIX_CORES(1)) u_actual_fast_crc(
        .i_clk(i_clk),.i_rst_n(i_rst_n),.i_abort(n_i_fast_source_abort),
        .i_request_valid(n_o_fast_crc_start_valid),.o_request_ready(n_i_fast_crc_start_ready),
        .i_frame(n_o_fast_ack_frame),.i_context(n_o_fast_ack_context),.i_tag(n_o_fast_ack_tag),
        .i_generation(n_o_fast_ack_generation),.i_block_id(n_o_fast_ack_block_id),
        .i_stored(1'b0),.i_length(n_o_fast_crc_length),
        .i_data_valid(n_o_fast_crc_tap_valid),.o_data_ready(n_i_fast_crc_tap_ready),
        .i_data(n_o_fast_crc_tap_data),.i_keep(n_o_fast_crc_tap_keep),.i_last(n_o_fast_crc_tap_last),
        .o_result_valid(n_i_fast_crc_result_valid),.i_result_ready(n_o_fast_crc_result_ready),
        .o_frame(n_i_fast_crc_frame),.o_context(n_i_fast_crc_context),.o_tag(n_i_fast_crc_tag),
        .o_generation(n_i_fast_crc_generation),.o_block_id(n_i_fast_crc_block_id),
        .o_stored(),.o_length(n_i_fast_crc_length),.o_crc(n_i_fast_crc),.o_ok(n_i_fast_crc_ok));

    assign n_i_cancel=1'b0;assign n_i_fast_cancel=1'b0;
    assign n_i_plan_valid=normal_offer;assign n_i_fast_plan_valid=fast_offer;
    assign n_i_frame=frame[normal_owner];assign n_i_context=frame[normal_owner][159:0];
    assign n_i_tag={frame[normal_owner][76:45],frame[normal_owner][108:77]};
    assign n_i_generation=frame[normal_owner][44:13];assign n_i_block_id=normal_block;
    assign n_i_slot_base=base[normal_owner];assign n_i_slot_span=i_slot_span;
    assign n_i_data_offset=data_offset[normal_owner];assign n_i_samples=normal_samples;
    assign n_i_width=width[normal_owner];assign n_i_start_x=normal_x;
    assign n_i_valid=held_valid&&normal_pending&&!normal_offer;
    assign n_i_data=held_data>>(held_lane*32);assign n_i_keep=held_keep>>(held_lane*4);
    assign n_i_last=normal_last_word;
    assign n_i_source_abort=normal_pending&&!normal_offer&&closed[normal_owner]&&!held_valid&&!normal_closed;
    assign n_i_ack_ready=normal_pending;
    assign n_i_fast_frame=frame[fast_owner];assign n_i_fast_context=frame[fast_owner][159:0];
    assign n_i_fast_tag={frame[fast_owner][76:45],frame[fast_owner][108:77]};
    assign n_i_fast_generation=frame[fast_owner][44:13];assign n_i_fast_block_id=fast_block;
    assign n_i_fast_slot_base=base[fast_owner];assign n_i_fast_slot_span=i_slot_span;
    assign n_i_fast_data_offset=data_offset[fast_owner];assign n_i_fast_samples=fast_samples;
    assign n_i_fast_valid=i_valid[fast_owner]&&lane_state[fast_owner]==C_FAST&&
        fast_pending&&!fast_offer&&!closed[fast_owner]&&!failed[fast_owner];
    assign n_i_fast_data=input_data[fast_owner];assign n_i_fast_keep=input_keep[fast_owner];
    assign n_i_fast_last=fast_left<=16;
    assign n_i_fast_available=input_available[fast_owner];
    assign n_i_fast_source_abort=fast_pending&&!fast_offer&&closed[fast_owner]&&!fast_closed;
    assign n_i_fast_ack_ready=fast_pending;
    assign r_i_cancel=1'b0;assign r_i_plan_valid=read_state==D_PLAN;
    assign r_i_frame=read_frame;assign r_i_context=read_frame[159:0];
    assign r_i_tag={read_frame[76:45],read_frame[108:77]};assign r_i_generation=read_frame[44:13];
    assign r_i_total_samples=read_samples;assign r_i_block_count=read_blocks;
    assign r_i_slot_base=read_base;assign r_i_slot_span=i_slot_span;assign r_i_data_offset=read_data_offset;
    assign r_i_range_offset=read_offset;assign r_i_first_block=read_block;
    assign r_i_range_length=read_chunk;assign r_i_first_offset=read_local;
    assign r_i_width=read_width;assign r_i_first_start_x=read_x[15:0];
    assign r_i_second_start_x=read_second_x[15:0];
    assign r_i_ready=i_read_ready&&read_state==D_RUN;assign r_i_ack_ready=read_state==D_RUN;
    assign n_m_axi_awready=m_axi_awready;assign n_m_axi_wready=m_axi_wready;
    assign n_m_axi_bid=m_axi_bid;assign n_m_axi_bresp=m_axi_bresp;assign n_m_axi_bvalid=m_axi_bvalid;
    assign m_axi_awid=n_m_axi_awid;assign m_axi_awaddr=n_m_axi_awaddr;assign m_axi_awlen=n_m_axi_awlen;
    assign m_axi_awsize=n_m_axi_awsize;assign m_axi_awburst=n_m_axi_awburst;assign m_axi_awvalid=n_m_axi_awvalid;
    assign m_axi_wdata=n_m_axi_wdata;assign m_axi_wstrb=n_m_axi_wstrb;
    assign m_axi_wlast=n_m_axi_wlast;assign m_axi_wvalid=n_m_axi_wvalid;assign m_axi_bready=n_m_axi_bready;
    assign r_m_axi_arready=m_axi_arready;assign r_m_axi_rid=m_axi_rid;assign r_m_axi_rdata=m_axi_rdata;
    assign r_m_axi_rresp=m_axi_rresp;assign r_m_axi_rlast=m_axi_rlast;assign r_m_axi_rvalid=m_axi_rvalid;
    assign m_axi_arid=r_m_axi_arid;assign m_axi_araddr=r_m_axi_araddr;assign m_axi_arlen=r_m_axi_arlen;
    assign m_axi_arsize=r_m_axi_arsize;assign m_axi_arburst=r_m_axi_arburst;assign m_axi_arvalid=r_m_axi_arvalid;
    assign m_axi_rready=r_m_axi_rready;
    wire [2:0] cache_we=fetch_phase?r_o_cache_write_enable:{1'b0,n_o_cache_write_enable};
    wire [29:0] cache_wa=fetch_phase?r_o_cache_write_address:{10'd0,n_o_cache_write_address};
    wire [95:0] cache_wd=fetch_phase?r_o_cache_write_data:{32'd0,n_o_cache_write_data};
    wire [2:0] cache_re=fetch_phase?r_o_cache_read_enable:{1'b0,n_o_cache_read_enable};
    wire [29:0] cache_ra=fetch_phase?r_o_cache_read_address:{10'd0,n_o_cache_read_address};
    cfs_block_cache3 u_cache(.i_clk(i_clk),.i_write_enable(cache_we),.i_write_address(cache_wa),
        .i_write_data(cache_wd),.i_read_enable(cache_re),.i_read_address(cache_ra),.o_read_data(cache_read_data));
    always @(posedge i_clk or negedge i_rst_n)begin
        if(!i_rst_n)begin
            active<=0;closed<=0;source_ok<=0;failed<=0;result<=0;turn<=0;
            normal_owner<=0;fast_owner<=0;normal_offer<=0;fast_offer<=0;
            normal_pending<=0;fast_pending<=0;normal_closed<=0;fast_closed<=0;
            normal_block<=0;fast_block<=0;normal_samples<=0;fast_samples<=0;
            normal_left<=0;fast_left<=0;normal_x<=0;held_data<=0;held_keep<=0;
            held_valid<=0;held_block_last<=0;held_lane<=0;cache_owner<=0;
            read_state<=D_IDLE;read_frame<=0;read_base<=0;read_samples<=0;read_blocks<=0;
            read_data_offset<=0;read_offset<=0;read_left<=0;read_block<=0;map_offset<=0;
            read_x<=0;read_second_x<=0;read_step_x<=0;map_cold<=0;
            read_width<=0;read_local<=0;read_chunk<=0;read_error<=0;
            o_compressed_count<=0;o_no_benefit_count<=0;o_overflow_count<=0;o_busy_count<=0;
            for(lane=0;lane<2;lane=lane+1)begin
                frame[lane]<=0;base[lane]<=0;total_samples[lane]<=0;block_count[lane]<=0;data_offset[lane]<=0;
                next_block[lane]<=0;accepted_bytes[lane]<=0;acked_blocks[lane]<=0;width[lane]<=0;
                next_x[lane]<=0;lane_state[lane]<=C_SELECT;
            end
        end else begin
            for(lane=0;lane<2;lane=lane+1)begin
                if(i_begin_valid[lane]&&o_begin_ready[lane])begin
                    frame[lane]<=lane==0?i_frame0:i_frame1;base[lane]<=lane==0?i_base0:i_base1;
                    total_samples[lane]<=lane==0?i_samples0:i_samples1;width[lane]<=lane==0?i_width0:i_width1;
                    block_count[lane]<=((lane==0?{1'b0,i_samples0}:{1'b0,i_samples1})+2047)>>11;
                    data_offset[lane]<=(((((lane==0?{1'b0,i_samples0}:{1'b0,i_samples1})+2047)>>11)*32+63)&32'hffffffc0);
                    active[lane]<=1;closed[lane]<=0;source_ok[lane]<=0;failed[lane]<=0;
                    next_block[lane]<=0;accepted_bytes[lane]<=0;acked_blocks[lane]<=0;next_x[lane]<=0;
                    lane_state[lane]<=C_SELECT;
                end
                if(next_x[lane]>=width[lane]&&width[lane]!=0)next_x[lane]<=next_x[lane]-width[lane];
                if(source_fire[lane])begin
                    accepted_bytes[lane]<=accepted_bytes[lane]+bytes16(input_keep[lane]);
                    if(input_keep[lane]==0||(input_keep[lane]&(input_keep[lane]+16'd1))!=0||
                        accepted_bytes[lane]+bytes16(input_keep[lane])>((total_samples[lane]*64'd10+7)>>3)||
                        (accepted_bytes[lane]+bytes16(input_keep[lane])<((total_samples[lane]*64'd10+7)>>3)&&input_keep[lane]!=16'hffff)||
                        i_last[lane]!=(accepted_bytes[lane]+bytes16(input_keep[lane])==((total_samples[lane]*64'd10+7)>>3)))failed[lane]<=1;
                end
                if(i_end_valid[lane]&&o_end_ready[lane])begin closed[lane]<=1;source_ok[lane]<=i_end_ok[lane];end
                if(normal_ack&&normal_owner==lane)begin
                    if(!n_o_ack_ok||!normal_match)failed[lane]<=1;
                    if(lane_state[lane]==C_NORMAL)lane_state[lane]<=C_SELECT;
                end
                if(fast_ack&&fast_owner==lane)begin
                    if(!n_o_fast_ack_ok||!fast_match)failed[lane]<=1;
                    if(lane_state[lane]==C_FAST)lane_state[lane]<=C_SELECT;
                end
                if((normal_ack&&normal_owner==lane&&n_o_ack_ok&&normal_match)||
                    (fast_ack&&fast_owner==lane&&n_o_fast_ack_ok&&fast_match))
                    acked_blocks[lane]<=acked_blocks[lane]+(normal_ack&&normal_owner==lane&&n_o_ack_ok&&normal_match)+
                        (fast_ack&&fast_owner==lane&&n_o_fast_ack_ok&&fast_match);
                if(active[lane]&&closed[lane]&&!(normal_pending&&normal_owner==lane)&&
                    !(fast_pending&&fast_owner==lane))begin result[lane]<=1;active[lane]<=0;end
                if(result[lane]&&i_result_ready[lane])result[lane]<=0;
            end
            if((|runnable)&&(normal_available||fast_available))begin
                turn<=!selected_lane;
                if(normal_available)begin
                    normal_owner<=selected_lane;normal_block<=next_block[selected_lane];
                    normal_samples<=selected_samples;normal_left<=(selected_samples*16'd10+7)>>3;
                    normal_x<=next_x[selected_lane][15:0];normal_offer<=1;normal_pending<=1;normal_closed<=0;
                    lane_state[selected_lane]<=C_NORMAL;cache_owner<=1;
                end else begin
                    fast_owner<=selected_lane;fast_block<=next_block[selected_lane];fast_samples<=selected_samples;
                    fast_left<=(selected_samples*16'd10+7)>>3;fast_offer<=1;fast_pending<=1;fast_closed<=0;
                    lane_state[selected_lane]<=C_FAST;
                end
            end
            if(normal_offer&&n_o_plan_ready)normal_offer<=0;
            if(fast_offer&&n_o_fast_plan_ready)fast_offer<=0;
            if(source_fire[normal_owner]&&lane_state[normal_owner]==C_NORMAL&&!failed[normal_owner])begin
                held_valid<=1;held_data<=input_data[normal_owner];held_keep<=input_keep[normal_owner];held_lane<=0;
                held_block_last<=normal_left<=16;normal_left<=normal_left>16?normal_left-16:0;
            end
            if(normal_fire)begin
                if(held_lane==3||(held_keep>>(held_lane*4+4))==0)begin held_valid<=0;held_lane<=0;end
                else held_lane<=held_lane+1'b1;
                if(n_i_last)begin
                    normal_closed<=1;lane_state[normal_owner]<=C_SELECT;
                    next_block[normal_owner]<=next_block[normal_owner]+1'b1;next_x[normal_owner]<=next_x[normal_owner]+2048;
                end
            end
            if(source_fire[fast_owner]&&lane_state[fast_owner]==C_FAST&&!failed[fast_owner])begin
                fast_left<=fast_left>16?fast_left-16:0;
                if(fast_left<=16)begin
                    fast_closed<=1;lane_state[fast_owner]<=C_SELECT;
                    next_block[fast_owner]<=next_block[fast_owner]+1'b1;next_x[fast_owner]<=next_x[fast_owner]+2048;
                end
            end
            if(normal_ack)begin
                normal_pending<=0;cache_owner<=0;
                if(n_o_ack_ok&&normal_match)case(n_o_ack_reason)
                    0:o_compressed_count<=o_compressed_count+1'b1;
                    1:o_no_benefit_count<=o_no_benefit_count+1'b1;
                    2:o_overflow_count<=o_overflow_count+1'b1;
                    default:begin end
                endcase
            end
            if(fast_ack)begin fast_pending<=0;if(n_o_fast_ack_ok&&fast_match)o_busy_count<=o_busy_count+1'b1;end
            case(read_state)
                D_IDLE:if(i_read_request_valid&&o_read_request_ready)begin
                    read_frame<=i_read_frame;read_base<=i_read_base;read_samples<=i_read_samples;
                    read_blocks<=({1'b0,i_read_samples}+2047)>>11;
                    read_data_offset<=((((({1'b0,i_read_samples}+2047)>>11)*32+63)&32'hffffffc0));
                    read_offset<=i_read_offset;map_offset<=i_read_offset;read_left<=i_read_length;
                    read_width<=i_read_width;read_block<=0;read_x<=0;read_error<=0;
                    map_cold<=1;read_state<=D_MAP;
                end
                D_MAP:begin
                    if(map_cold)begin
                        if(locator_ready)read_state<=D_X;
                    end else begin
                        // A successful chunk advances by at most one block.
                        // Keep REPLAY incremental; no cold divide or frame scan.
                        if(map_offset>=2560)begin
                            map_offset<=map_offset-2560;read_block<=read_block+1'b1;
                            read_x<=read_second_x;read_second_x<=replay_next_x;
                        end
                        read_state<=D_SECOND_X;
                    end
                end
                D_X:if(locator_valid)begin
                    map_cold<=0;
                    if(locator_error)begin read_error<=1;read_state<=D_DONE;end
                    else begin
                        read_block<=locator_block;map_offset<={20'd0,locator_local};
                        read_x<=locator_first_x;read_second_x<=locator_second_x;read_step_x<=locator_step_x;
                        read_state<=D_SECOND_X;
                    end
                end
                D_SECOND_X:begin
                    read_local<=map_offset[11:0];
                    read_chunk<=read_left>=2560?12'd2560:read_left[11:0];read_state<=D_CACHE;
                end
                D_CACHE:if(cache_owner==0)begin cache_owner<=2;read_state<=D_PLAN;end
                D_PLAN:if(r_o_plan_ready)read_state<=D_RUN;
                D_RUN:begin
                    if(o_read_valid&&i_read_ready)read_left<=read_left-bytes16(r_o_keep);
                    if(r_o_ack_valid)begin
                        cache_owner<=0;
                        if(!r_o_ack_ok)begin read_error<=1;read_state<=D_DONE;end
                        else if(read_left==0)read_state<=D_DONE;
                        else begin
                            read_offset<=read_offset+read_chunk;
                            map_offset<={20'd0,read_local}+read_chunk;read_state<=D_MAP;
                        end
                    end
                end
                D_DONE:if(i_read_retire)read_state<=D_IDLE;
                default:begin read_error<=1;read_state<=D_DONE;end
            endcase
        end
    end
endmodule
