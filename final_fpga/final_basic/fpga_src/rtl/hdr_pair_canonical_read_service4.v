`timescale 1ns/1ps
`default_nettype none
// Caller owns both real JOB references; this reader owns one canonical FETCH.
module hdr_pair_canonical_read_service4 #(
    parameter integer MAX_WIDTH=1920, MAX_HEIGHT=1080
)(
    input wire clk, rst_n,
    input wire s_start_valid, output wire s_start_ready,
    input wire [383:0] s_long_frame, s_short_frame,
    input wire [63:0] s_long_tag,s_short_tag,s_long_lease,s_short_lease,s_job_id,s_pair_id,
    input wire [2:0] s_ratio_log2,
    input wire [9:0] s_black_long,s_black_short,
    input wire [13:0] s_motion_base,
    input wire [3:0] s_motion_shift,
    input wire [63:0] s_max_delta_ns,
    output wire m_context_valid,input wire m_context_ready,
    output wire [383:0] o_long_frame,o_short_frame,
    output wire [63:0] o_long_tag,o_short_tag,o_job_id,o_pair_id,
    output reg [63:0] o_long_lease,o_short_lease,
    output wire [55:0] m_raw,
    output wire [31:0] m_index,
    output wire [3:0] m_keep,m_motion,
    output wire m_valid,m_sof,m_eol,m_eof,input wire m_ready,
    input wire i_cancel_valid,output wire o_cancel_ready,
    input wire [63:0] i_cancel_job_id,i_cancel_pair_id,
    output wire m_result_valid,input wire m_result_ready,
    output wire m_result_ok,output wire [7:0] o_first_error,
    output reg [7:0] o_service_error,
    output reg o_protocol_fault,
    output wire o_long_read_quiescent,o_short_read_quiescent,o_read_quiescent,o_quiescent,
    output wire o_long_source_valid,o_short_source_valid,
    output wire [31:0] o_long_pixels,o_short_pixels,o_output_pixels,
    output wire m_req_valid,input wire m_req_ready,
    output wire [2:0] m_req_op,
    output wire m_req_camera,output wire [1:0] m_req_slot,
    output wire [31:0] m_req_generation,m_req_session,m_req_offset,m_req_length,
    output wire m_req_private,output wire [63:0] m_req_lease,m_req_job_id,
    input wire s_rsp_valid,output wire s_rsp_ready,
    input wire [3:0] s_rsp_code,input wire [383:0] s_rsp_descriptor,
    input wire s_rsp_metadata_valid,
    input wire [127:0] s_read_data,input wire [15:0] s_read_keep,
    input wire s_read_valid,s_read_last,output wire s_read_ready,
    input wire i_read_complete,i_read_error,i_store_protocol_fault
);
    localparam [1:0] IDLE=0,PREPARE=1,ACTIVE=2,FINISH=3;
    localparam [2:0] FETCH_IDLE=0,FETCH_REQ=1,FETCH_RSP=2,FETCH_DATA=3,
        RETIRE_REQ=4,RETIRE_RSP=5,QUARANTINE=6;
    reg [1:0] state;
    reg [2:0] fetch_state;
    reg prepared,started,failed,range_error;
    reg [15:0] rows_left,row_groups;
    reg [31:0] row_bytes,total_bytes,total_groups;
    reg [31:0] offset_long,offset_short,pushed_long,pushed_short;
    reg fetch_owner,round_robin;
    reg [31:0] fetch_offset,fetch_length,fetch_received;
    reg closed_long,closed_short,abort_long,abort_short;
    reg source_long_valid,source_short_valid,source_long_sent,source_short_sent;
    reg source_long_ok,source_short_ok;
    reg [7:0] source_long_error,source_short_error;
    reg [31:0] source_long_pixels,source_short_pixels,long_index,short_index;
    reg [15:0] long_column,short_column;
    reg [9:0] long_occupancy,short_occupancy;
    reg internal_cancel_sent;
    wire fifo_rst_n;
    wire long_full,short_full,long_empty,short_empty,long_fifo_valid,short_fifo_valid;
    wire long_wr_done,long_rd_done,short_wr_done,short_rd_done;
    wire [39:0] long_fifo_data,short_fifo_data;
    wire long_pair_ready,short_pair_ready,adapter_cancel_ready;
    wire fifos_ready=fifo_rst_n && long_wr_done && long_rd_done && short_wr_done && short_rd_done;
    wire long_fifo_head=fifos_ready && long_fifo_valid && !long_empty;
    wire short_fifo_head=fifos_ready && short_fifo_valid && !short_empty;
    wire internal_cancel_valid=failed && state!=IDLE && !internal_cancel_sent && !m_result_valid;
    wire long_fifo_pop=long_fifo_head && long_pair_ready;
    wire short_fifo_pop=short_fifo_head && short_pair_ready;
    wire adapter_start_ready,adapter_context_valid;
    wire adapter_context_ready=prepared && (range_error || m_context_ready);
    wire start_fire=s_start_valid && s_start_ready;
    wire context_fire=adapter_context_valid && adapter_context_ready;
    wire replay_start=context_fire && !range_error && !failed;
    wire [39:0] long_native,short_native;
    wire long_native_valid,short_native_valid,long_native_ready,short_native_ready;
    wire long_sof,long_eol,long_abort,long_done,short_sof,short_eol,short_abort,short_done;
    wire long_axis_ready,short_axis_ready;
    wire long_abort_start=failed && started && !closed_long && !abort_long && !long_done;
    wire short_abort_start=failed && started && !closed_short && !abort_short && !short_done;
    wire source_long_ready,source_short_ready;
    wire long_native_fire=long_native_valid && long_native_ready;
    wire short_native_fire=short_native_valid && short_native_ready;
    wire cancel_match=i_cancel_job_id==o_job_id && i_cancel_pair_id==o_pair_id;
    wire cancel_fire=i_cancel_valid && o_cancel_ready && cancel_match;
    wire transaction_failed=failed || range_error || o_first_error!=0;
    wire request_fire=m_req_valid && m_req_ready;
    wire response_fire=s_rsp_valid && s_rsp_ready;
    wire read_fire=s_read_valid && s_read_ready;
    wire [383:0] fetch_frame=fetch_owner ? o_short_frame : o_long_frame;
    wire fetch_active=fetch_state!=FETCH_IDLE;
    // A chunk contains at most 512 native groups. Admission uses all real
    // pushes, an empty FIFO and an empty decoder reservoir; no extra FWFT
    // or pair-adapter head capacity is credited to the reservation.
    wire long_capacity=long_occupancy==0 && !long_native_valid &&
        (pushed_long+(pushed_long<<2))==offset_long;
    wire short_capacity=short_occupancy==0 && !short_native_valid &&
        (pushed_short+(pushed_short<<2))==offset_short;
    wire long_candidate=offset_long<total_bytes && long_capacity;
    wire short_candidate=offset_short<total_bytes && short_capacity;
    wire selected_owner=short_candidate && (!long_candidate || round_robin);
    wire [31:0] selected_offset=selected_owner ? offset_short : offset_long;
    wire [31:0] selected_left=total_bytes-selected_offset;
    wire [31:0] selected_length=selected_left>2560 ? 32'd2560 : selected_left;
    wire [31:0] read_left=fetch_length-fetch_received;
    wire [4:0] expected_bytes=read_left>=16 ? 5'd16 : read_left[4:0];
    wire [15:0] expected_keep=expected_bytes==16 ? 16'hffff : (16'hffff>>(16-expected_bytes));
    wire read_shape_ok=read_left!=0 && s_read_keep==expected_keep && s_read_last==(read_left<=16);
    wire [127:0] long_word=s_read_data,short_word=s_read_data;
    wire [15:0] long_keep=s_read_keep,short_keep=s_read_keep;
    // Store TLAST closes a FETCH range. Only the final range closes RAW10.
    wire long_last=s_read_last && fetch_offset+fetch_length==total_bytes;
    wire short_last=long_last;
    wire long_word_valid=fetch_state==FETCH_DATA && !fetch_owner && s_read_valid && !transaction_failed;
    wire short_word_valid=fetch_state==FETCH_DATA && fetch_owner && s_read_valid && !transaction_failed;
    assign s_start_ready=rst_n && fifos_ready && state==IDLE && adapter_start_ready && !o_protocol_fault;
    assign o_cancel_ready=adapter_cancel_ready && !internal_cancel_valid;
    assign long_native_ready=fifos_ready && !long_full;
    assign short_native_ready=fifos_ready && !short_full;
    assign m_context_valid=adapter_context_valid && prepared && !range_error;
    assign m_req_valid=rst_n && (fetch_state==FETCH_REQ || fetch_state==RETIRE_REQ);
    assign m_req_op=fetch_state==RETIRE_REQ ? 3'd5 : 3'd3;
    assign m_req_camera=fetch_frame[4];assign m_req_slot=fetch_frame[6:5];
    assign m_req_generation=fetch_frame[44:13];assign m_req_session=fetch_frame[76:45];
    assign m_req_offset=fetch_offset;assign m_req_length=fetch_length;
    assign m_req_private=1'b1;assign m_req_job_id=o_job_id;
    assign m_req_lease=fetch_owner ? o_short_lease : o_long_lease;
    assign s_rsp_ready=rst_n && (fetch_state==FETCH_RSP || fetch_state==RETIRE_RSP);
    assign s_read_ready=rst_n && fetch_state==FETCH_DATA && !o_protocol_fault &&
        (transaction_failed || (fetch_owner ? short_axis_ready : long_axis_ready));
    assign o_long_read_quiescent=closed_long && !(fetch_active && !fetch_owner) &&
        !long_native_valid && long_occupancy==0 && !long_fifo_head && !o_protocol_fault;
    assign o_short_read_quiescent=closed_short && !(fetch_active && fetch_owner) &&
        !short_native_valid && short_occupancy==0 && !short_fifo_head && !o_protocol_fault;
    assign o_read_quiescent=o_long_read_quiescent && o_short_read_quiescent;
    assign o_quiescent=rst_n && state==IDLE && o_read_quiescent;
    assign o_long_source_valid=source_long_valid;assign o_short_source_valid=source_short_valid;

    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)begin
            state<=IDLE;prepared<=0;started<=0;failed<=0;range_error<=0;
            rows_left<=0;row_groups<=0;row_bytes<=0;total_bytes<=0;total_groups<=0;
            o_long_lease<=0;o_short_lease<=0;o_service_error<=0;o_protocol_fault<=0;
        end else begin
            case(state)
                IDLE:if(start_fire)state<=PREPARE;
                PREPARE:if(prepared)state<=ACTIVE;
                ACTIVE:if(m_result_valid)state<=FINISH;
                FINISH:if(m_result_valid && m_result_ready)state<=IDLE;
                default:state<=IDLE;
            endcase
            if(m_result_valid && m_result_ready)state<=IDLE;
            if(start_fire)begin
                prepared<=0;started<=0;failed<=0;range_error<=0;
                rows_left<=s_long_frame[236:221];row_groups<=s_long_frame[220:205]>>2;
                row_bytes<=(s_long_frame[220:205]>>2)+((s_long_frame[220:205]>>2)<<2);
                total_bytes<=0;total_groups<=0;o_long_lease<=s_long_lease;o_short_lease<=s_short_lease;
                o_service_error<=0;
            end
            if(state==PREPARE && !prepared)begin
                if(rows_left!=0)begin
                    total_bytes<=total_bytes+row_bytes;total_groups<=total_groups+row_groups;rows_left<=rows_left-1'b1;
                end else begin
                    prepared<=1;
                    if(total_bytes==0 || o_long_lease==0 || o_short_lease==0)begin
                        range_error<=1;failed<=1;o_service_error<=8'he0;
                    end
                end
            end
            if(replay_start)started<=1;
            if((o_first_error!=0 && state!=IDLE && !m_result_valid) || cancel_fire)begin
                failed<=1;if(o_service_error==0)o_service_error<=8'he2;
            end
            if(long_abort || short_abort)begin failed<=1;if(o_service_error==0)o_service_error<=8'he3;end
            if(response_fire && s_rsp_code!=0)begin
                failed<=1;if(o_service_error==0)o_service_error<=8'he5;
            end
            if(fetch_state==FETCH_DATA && i_read_error)begin
                failed<=1;if(o_service_error==0)o_service_error<=8'he1;
            end
            if(read_fire && !read_shape_ok)begin failed<=1;o_service_error<=8'he6;o_protocol_fault<=1;end
            if(response_fire && s_rsp_code==0 && (!s_rsp_metadata_valid || s_rsp_descriptor!=fetch_frame))begin
                failed<=1;o_service_error<=8'he6;o_protocol_fault<=1;
            end
            if(i_store_protocol_fault)begin failed<=1;o_service_error<=8'he4;o_protocol_fault<=1;end
            if(response_fire && fetch_state==RETIRE_RSP && s_rsp_code!=0)begin
                o_protocol_fault<=1;o_service_error<=8'he7;
            end
            if(fetch_state==FETCH_DATA && i_read_complete && !transaction_failed &&
                fetch_received!=fetch_length)begin failed<=1;o_service_error<=8'he1;end
        end
    end
    // A presented request is immutable through cancellation. Actual positive
    // FETCH admission creates ownership; only the matching real RETIRE removes
    // it. Admission denial creates no read owner. RETIRE denial quarantines it.
    always @(posedge clk or negedge rst_n)begin
        if(!rst_n || start_fire)begin
            fetch_state<=FETCH_IDLE;fetch_owner<=0;round_robin<=0;
            fetch_offset<=0;fetch_length<=0;fetch_received<=0;offset_long<=0;offset_short<=0;
            pushed_long<=0;pushed_short<=0;
        end else begin
            if(long_native_fire)pushed_long<=pushed_long+1'b1;
            if(short_native_fire)pushed_short<=pushed_short+1'b1;
            case(fetch_state)
                FETCH_IDLE:if(state==ACTIVE && started && !transaction_failed && !cancel_fire &&
                    !o_protocol_fault && (long_candidate || short_candidate))begin
                    fetch_owner<=selected_owner;fetch_offset<=selected_offset;
                    fetch_length<=selected_length;fetch_received<=0;fetch_state<=FETCH_REQ;
                end
                FETCH_REQ:if(request_fire)fetch_state<=FETCH_RSP;
                FETCH_RSP:if(response_fire)fetch_state<=s_rsp_code==0 ? FETCH_DATA : FETCH_IDLE;
                FETCH_DATA:begin
                    if(read_fire)fetch_received<=fetch_received+expected_bytes;
                    if(i_read_complete)fetch_state<=RETIRE_REQ;
                end
                RETIRE_REQ:if(request_fire)fetch_state<=RETIRE_RSP;
                RETIRE_RSP:if(response_fire)begin
                    if(s_rsp_code==0)begin
                        if(fetch_owner)offset_short<=fetch_offset+fetch_length;
                        else offset_long<=fetch_offset+fetch_length;
                        round_robin<=!fetch_owner;fetch_state<=FETCH_IDLE;
                    end else fetch_state<=QUARANTINE;
                end
                default:fetch_state<=fetch_state;
            endcase
        end
    end
    // Explicit decoder abort retains any presented native group. The existing
    // pair adapter becomes the real discard consumer while the store drains.
    always @(posedge clk or negedge rst_n)begin
        if(!rst_n || start_fire)begin
            closed_long<=1;closed_short<=1;abort_long<=0;abort_short<=0;
            long_index<=0;short_index<=0;long_column<=0;short_column<=0;internal_cancel_sent<=0;
            source_long_valid<=0;source_short_valid<=0;source_long_sent<=0;source_short_sent<=0;
            source_long_ok<=0;source_short_ok<=0;source_long_error<=0;source_short_error<=0;
            source_long_pixels<=0;source_short_pixels<=0;
        end else begin
            if(replay_start)begin closed_long<=0;closed_short<=0;end
            if(long_abort_start)abort_long<=1;if(short_abort_start)abort_short<=1;
            if(long_done || long_abort)closed_long<=1;if(short_done || short_abort)closed_short<=1;
            if((internal_cancel_valid && adapter_cancel_ready) || cancel_fire)internal_cancel_sent<=1;
            if(long_fifo_pop)begin long_index<=long_index+1'b1;long_column<=long_column==row_groups-1'b1 ? 0 : long_column+1'b1;end
            if(short_fifo_pop)begin short_index<=short_index+1'b1;short_column<=short_column==row_groups-1'b1 ? 0 : short_column+1'b1;end
            if(state!=IDLE && !source_long_sent && !source_long_valid && o_long_read_quiescent &&
                (transaction_failed || (started && long_index==total_groups)))begin
                source_long_valid<=1;source_long_ok<=!transaction_failed;
                source_long_error<=transaction_failed ? (o_service_error==0 ? 8'he2 : o_service_error) : 0;
                source_long_pixels<=long_index<<2;
            end
            if(state!=IDLE && !source_short_sent && !source_short_valid && o_short_read_quiescent &&
                (transaction_failed || (started && short_index==total_groups)))begin
                source_short_valid<=1;source_short_ok<=!transaction_failed;
                source_short_error<=transaction_failed ? (o_service_error==0 ? 8'he2 : o_service_error) : 0;
                source_short_pixels<=short_index<<2;
            end
            if(source_long_valid && source_long_ready)begin source_long_valid<=0;source_long_sent<=1;end
            if(source_short_valid && source_short_ready)begin source_short_valid<=0;source_short_sent<=1;end
        end
    end
    reset_release_sync u_fifo_reset(.i_clk(clk),.i_async_rst_n(rst_n),.o_rst_n(fifo_rst_n));
    control_fifo_40x512 u_long_native_fifo(
        .di(long_native),.clkw(clk),.wrst(!fifo_rst_n),.we(long_native_fire),
        .clkr(clk),.rrst(!fifo_rst_n),.re(long_fifo_pop),.dout(long_fifo_data),
        .empty_flag(long_empty),.aempty(),.full_flag(long_full),.afull(),
        .valid(long_fifo_valid),.overflow(),.underflow(),.wr_success(),.rdusedw(),.wrusedw(),
        .wr_rst_done(long_wr_done),.rd_rst_done(long_rd_done));
    control_fifo_40x512 u_short_native_fifo(
        .di(short_native),.clkw(clk),.wrst(!fifo_rst_n),.we(short_native_fire),
        .clkr(clk),.rrst(!fifo_rst_n),.re(short_fifo_pop),.dout(short_fifo_data),
        .empty_flag(short_empty),.aempty(),.full_flag(short_full),.afull(),
        .valid(short_fifo_valid),.overflow(),.underflow(),.wr_success(),.rdusedw(),.wrusedw(),
        .wr_rst_done(short_wr_done),.rd_rst_done(short_rd_done));
    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)begin long_occupancy<=0;short_occupancy<=0;end
        else begin
            case({long_native_fire,long_fifo_pop})
                2'b10:long_occupancy<=long_occupancy+1'b1;
                2'b01:long_occupancy<=long_occupancy-1'b1;
                default:long_occupancy<=long_occupancy;
            endcase
            case({short_native_fire,short_fifo_pop})
                2'b10:short_occupancy<=short_occupancy+1'b1;
                2'b01:short_occupancy<=short_occupancy-1'b1;
                default:short_occupancy<=short_occupancy;
            endcase
        end
    end
    raw10_frame_replay u_long_replay(
        .i_clk(clk),.i_rst_n(rst_n),.i_start(replay_start || long_abort_start),
        .i_width(o_long_frame[220:205]),.i_height(o_long_frame[236:221]),
        .i_axis_tdata(long_word),.i_axis_tkeep(long_keep),.i_axis_tvalid(long_word_valid && !closed_long),
        .o_axis_tready(long_axis_ready),.i_axis_tlast(long_last),.o_data(long_native),.o_valid(long_native_valid),
        .i_ready(long_native_ready),.o_sof(long_sof),.o_eol(long_eol),.o_abort(long_abort),.o_done(long_done));
    raw10_frame_replay u_short_replay(
        .i_clk(clk),.i_rst_n(rst_n),.i_start(replay_start || short_abort_start),
        .i_width(o_short_frame[220:205]),.i_height(o_short_frame[236:221]),
        .i_axis_tdata(short_word),.i_axis_tkeep(short_keep),.i_axis_tvalid(short_word_valid && !closed_short),
        .o_axis_tready(short_axis_ready),.i_axis_tlast(short_last),.o_data(short_native),.o_valid(short_native_valid),
        .i_ready(short_native_ready),.o_sof(short_sof),.o_eol(short_eol),.o_abort(short_abort),.o_done(short_done));
    hdr_raw14_pair_adapter4 #(.MAX_WIDTH(MAX_WIDTH),.MAX_HEIGHT(MAX_HEIGHT)) u_pair(
        .clk(clk),.rst_n(rst_n),.s_start_valid(s_start_valid && fifos_ready && state==IDLE && !o_protocol_fault),.s_start_ready(adapter_start_ready),
        .s_long_frame(s_long_frame),.s_short_frame(s_short_frame),.s_long_tag(s_long_tag),.s_short_tag(s_short_tag),
        .s_job_id(s_job_id),.s_pair_id(s_pair_id),.s_ratio_log2(s_ratio_log2),.s_black_long(s_black_long),.s_black_short(s_black_short),
        .s_motion_base(s_motion_base),.s_motion_shift(s_motion_shift),.s_max_delta_ns(s_max_delta_ns),
        .m_context_valid(adapter_context_valid),.m_context_ready(adapter_context_ready),
        .o_long_frame(o_long_frame),.o_short_frame(o_short_frame),.o_long_tag(o_long_tag),.o_short_tag(o_short_tag),
        .o_job_id(o_job_id),.o_pair_id(o_pair_id),.o_radiance_format(),.o_radiance_bits(),.o_black_corrected(),.o_ratio_log2(),
        .s_long_data(long_fifo_data),.s_short_data(short_fifo_data),.s_long_index(long_index),.s_short_index(short_index),
        .s_long_data_tag(o_long_tag),.s_short_data_tag(o_short_tag),.s_long_keep(4'hf),.s_short_keep(4'hf),
        .s_long_sof(long_index==0),.s_long_eol(long_column==row_groups-1'b1),.s_long_eof(long_index==total_groups-1'b1),
        .s_short_sof(short_index==0),.s_short_eol(short_column==row_groups-1'b1),.s_short_eof(short_index==total_groups-1'b1),
        .s_long_valid(long_fifo_head),.s_short_valid(short_fifo_head),.s_long_ready(long_pair_ready),.s_short_ready(short_pair_ready),
        .m_raw(m_raw),.m_index(m_index),.m_keep(m_keep),.m_motion(m_motion),
        .m_sof(m_sof),.m_eol(m_eol),.m_eof(m_eof),.m_valid(m_valid),.m_ready(m_ready),
        .s_long_source_valid(source_long_valid),.s_short_source_valid(source_short_valid),
        .s_long_source_ready(source_long_ready),.s_short_source_ready(source_short_ready),
        .s_long_source_frame(o_long_frame),.s_short_source_frame(o_short_frame),
        .s_long_source_tag(o_long_tag),.s_short_source_tag(o_short_tag),
        .s_long_source_job_id(o_job_id),.s_short_source_job_id(o_job_id),
        .s_long_source_pair_id(o_pair_id),.s_short_source_pair_id(o_pair_id),
        .s_long_source_pixels(source_long_pixels),.s_short_source_pixels(source_short_pixels),
        .s_long_source_ok(source_long_ok),.s_short_source_ok(source_short_ok),
        .s_long_source_error(source_long_error),.s_short_source_error(source_short_error),
        .i_long_read_quiescent(o_long_read_quiescent),.i_short_read_quiescent(o_short_read_quiescent),
        .i_cancel_valid(internal_cancel_valid || i_cancel_valid),.o_cancel_ready(adapter_cancel_ready),
        .i_cancel_job_id(internal_cancel_valid ? o_job_id : i_cancel_job_id),
        .i_cancel_pair_id(internal_cancel_valid ? o_pair_id : i_cancel_pair_id),
        .m_result_valid(m_result_valid),.m_result_ready(m_result_ready),.m_result_ok(m_result_ok),.o_first_error(o_first_error),
        .o_long_source_error(),.o_short_source_error(),.o_long_pixels(o_long_pixels),.o_short_pixels(o_short_pixels),
        .o_output_pixels(o_output_pixels),.o_stale_source_count(),.o_stale_cancel_count(),.o_busy(),.o_quiescent());
endmodule
`default_nettype wire
