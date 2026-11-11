`timescale 1ns/1ps
`include "pcie_protocol_v1.vh"
`default_nettype none
// Complete source configuration/drain barrier; no payload buffering or PHY READY.
module physical_configured_capture_frontend #(
    parameter integer SOURCE_SELECT=0, WIDTH=1920, HEIGHT=1080,
    parameter integer EXT_WIDTH=0,EXT_STRIPS=4,
    parameter integer DEST0_SAME_CLOCK=0,DEST1_SAME_CLOCK=0,
    parameter [31:0] EXT_COMBINATIONS=0,
    parameter [7:0] EXT_SUPPORTED=0,
    parameter integer PHYSICAL_FRAME_FENCE_ENABLE=0,
    parameter integer PRESET_MONO_ENABLE=1,
    parameter integer JOINT_CONFIG_OWNER_ENABLE=0,
    parameter integer TRUSTED_INPUT=0,
    parameter integer VIRTUAL0_PHASE=0,VIRTUAL1_PHASE=7,
    parameter integer LINE_GAP_CYCLES=8,
    parameter integer VIRTUAL0_PERIOD=1666667,VIRTUAL1_PERIOD=1666667
)(
    input wire i_pixel_clk,i_pixel_rst_n,i_capture1_clk,i_capture1_rst_n,i_dfi_clk,i_dfi_rst_n,
    input wire [159+EXT_WIDTH:0] s_config_data,
    input wire s_config_valid,
    output wire s_config_ready,
    output wire [159+EXT_WIDTH:0] m_config_ack_data,
    output wire m_config_ack_valid,m_config_ack_ok,
    input wire m_config_ack_ready,
    input wire i_source_ready,i_pause_new_frames,
    input wire [39:0] i_physical_data,
    input wire i_physical_valid,i_physical_accept,i_physical_sof,i_physical_eol,i_physical_abort,
    input wire [196:0] i_physical_metadata,
    input wire [31:0] i_physical_sequence,input wire i_physical_identity_valid,
    input wire i_physical_frame_enable,i_physical_source_idle,
    output wire o_physical_admit_enable,
    input wire i_capture0_enqueue_fire,i_capture1_enqueue_fire,i_capture0_consume_fire,i_capture1_consume_fire,
    input wire i_capture0_idle,i_capture1_idle,i_capture0_frame_accept,i_capture1_frame_accept,
    input wire i_capture_write_quiescent,i_old_processing_quiescent,
    input wire i_virtual0_enable,i_virtual0_abort_now,i_virtual0_drop_frame,i_virtual0_bad_eol,i_virtual0_abort_frame,
    input wire [1:0] i_virtual0_pattern,i_virtual0_exposure_role,
    input wire [15:0] i_virtual0_seed,i_virtual0_bad_line,
    input wire [31:0] i_virtual0_abort_after_groups,i_virtual0_actual_exposure,i_virtual0_gain,i_virtual0_calibration_id,i_virtual0_exposure_group,
    input wire i_virtual0_metadata_valid,i_virtual0_source_qualified,
    output wire [39:0] o_capture0_data,
    output wire o_capture0_valid,o_capture0_accept,o_capture0_sof,o_capture0_eol,o_capture0_eof,o_capture0_abort,
    output wire [31:0] o_capture0_session,o_capture0_sequence,o_capture0_epoch,
    output wire [196:0] o_capture0_metadata,
    output wire o_capture0_frame_accept,o_capture0_source_idle,
    output wire [159+EXT_WIDTH:0] o_active_config0,
    output wire [63:0] o_enqueued_count0,o_consumed_count0,
    input wire i_virtual1_enable,i_virtual1_abort_now,i_virtual1_drop_frame,i_virtual1_bad_eol,i_virtual1_abort_frame,
    input wire [1:0] i_virtual1_pattern,i_virtual1_exposure_role,
    input wire [15:0] i_virtual1_seed,i_virtual1_bad_line,
    input wire [31:0] i_virtual1_abort_after_groups,i_virtual1_actual_exposure,i_virtual1_gain,i_virtual1_calibration_id,i_virtual1_exposure_group,
    input wire i_virtual1_metadata_valid,i_virtual1_source_qualified,
    output wire [39:0] o_capture1_data,
    output wire o_capture1_valid,o_capture1_accept,o_capture1_sof,o_capture1_eol,o_capture1_eof,o_capture1_abort,
    output wire [31:0] o_capture1_session,o_capture1_sequence,o_capture1_epoch,
    output wire [196:0] o_capture1_metadata,
    output wire o_capture1_frame_accept,o_capture1_source_idle,
    output wire [159+EXT_WIDTH:0] o_active_config1,
    output wire [63:0] o_enqueued_count1,o_consumed_count1,
    output wire [63:0] o_pixel_time_ns,o_capture1_time_ns,o_dfi_time_ns,
    output wire o_pixel_time_valid,o_capture1_time_valid,o_dfi_time_valid,
    output wire [1:0] o_initialized,o_source_fault,o_dfi_fault,o_local_reset_done,
    output wire o_config_reset_done,o_config_busy,
    output wire [31:0] o_stale_ack_count
);
    `include "analysis_config_transport.vh"
    generate if(SOURCE_SELECT!=0 || PRESET_MONO_ENABLE!=1)begin:bad_source_select
        CAPTURE_FRONTEND_SOURCE_SELECT_MUST_BE_0_1_2_3 invalid_configuration();
    end endgenerate
    generate if(PRESET_MONO_ENABLE!=0&&(SOURCE_SELECT==2||EXT_WIDTH!=1024||EXT_SUPPORTED!=8'h34||
        DEST0_SAME_CLOCK!=1||DEST1_SAME_CLOCK!=1||WIDTH!=1920||HEIGHT!=1080))begin:bad_preset_mono
        PRESET_MONO_REQUIRES_SINGLE_HD_AND_IDENTICAL_SOURCE_CLOCKS invalid_preset_mono();
    end endgenerate
    generate if(JOINT_CONFIG_OWNER_ENABLE!=0 && (JOINT_CONFIG_OWNER_ENABLE!=1 ||
        SOURCE_SELECT!=0 || PRESET_MONO_ENABLE!=1 || DEST0_SAME_CLOCK!=1 || DEST1_SAME_CLOCK!=1 ||
        EXT_WIDTH!=1024 || WIDTH!=1920 || HEIGHT!=1080))begin:bad_joint_profile
        JOINT_CONFIG_REQUIRES_ONE_PHYSICAL_CAMERA_AND_IDENTICAL_PIXEL_CLOCKS invalid_joint_profile();
    end endgenerate
    wire cohort_rst_n=i_pixel_rst_n&&i_capture1_rst_n&&i_dfi_rst_n;
    wire reset0,reset1;
    reset_release_sync u_reset0(.i_clk(i_pixel_clk),.i_async_rst_n(cohort_rst_n),.o_rst_n(reset0));
    reset_release_sync u_reset1(.i_clk(i_capture1_clk),.i_async_rst_n(cohort_rst_n),.o_rst_n(reset1));
    wire time_overflow;
    frame_common_time_cdc u_time(.i_source_clk(i_pixel_clk),.i_source_rst_n(cohort_rst_n),
        .i_sink0_clk(i_capture1_clk),.i_sink0_rst_n(cohort_rst_n),
        .i_sink1_clk(i_dfi_clk),.i_sink1_rst_n(cohort_rst_n),
        .o_source_ns(o_pixel_time_ns),.o_source_valid(o_pixel_time_valid),.o_source_overflow(time_overflow),
        .o_sink0_ns(o_capture1_time_ns),.o_sink0_valid(o_capture1_time_valid),
        .o_sink1_ns(o_dfi_time_ns),.o_sink1_valid(o_dfi_time_valid));
    wire [159+EXT_WIDTH:0] plan[0:1],applied[0:1],active[0:1];
    wire [1:0] plan_valid,plan_ready,applied_valid,applied_ready,applied_ok,dest_done;
    wire [1:0] cfg_fault,drain_fault,virtual_idle,proof_valid,proof_quiet,proof_ready,drain_ready;
    wire [31:0] proof_session[0:1],proof_epoch[0:1];
    wire [1:0] local_plan_busy,drain_dfi_done;
    wire absent_source_fault,absent_dfi_fault;
    // Two logical exposure capture routes share physical camera0. Both have
    // real enqueue/consume debts; neither is an absent physical-camera alias.
    assign absent_source_fault=0;assign absent_dfi_fault=0;
    wire [39:0] virtual_data[0:1];
    wire [1:0] virtual_valid,virtual_sof,virtual_eol,virtual_eof,virtual_abort;
    wire [31:0] virtual_session[0:1],virtual_epoch[0:1],virtual_sequence[0:1];
    wire [196:0] virtual_metadata[0:1];
    reg global_owned;
    reg permit1_meta,permit1_sync,fault1_meta,fault1_sync;
    wire permit0=i_source_ready&&!i_pause_new_frames&&!global_owned&&!s_config_valid&&
        !o_source_fault[0]&&!fault1_sync;
    always @(posedge i_pixel_clk or negedge reset0)begin
        if(!reset0)begin global_owned<=0;fault1_meta<=0;fault1_sync<=0;end
        else begin
            fault1_meta<=o_source_fault[1];fault1_sync<=fault1_meta;
            if(s_config_valid&&s_config_ready)global_owned<=1;
            if(m_config_ack_valid&&m_config_ack_ready)global_owned<=0;
        end
    end
    always @(posedge i_capture1_clk or negedge reset1)begin
        if(!reset1)begin permit1_meta<=0;permit1_sync<=0;end
        else begin permit1_meta<=permit0;permit1_sync<=permit1_meta;end
    end
    assign o_config_busy=global_owned;
    wire lab_hdr_selected=1'b0;
    wire physical_selected=SOURCE_SELECT==0;
    genvar c;
    generate if(JOINT_CONFIG_OWNER_ENABLE==0)begin:g_separate_config_owners
    frame_config_fanout_cdc #(.EXT_WIDTH(EXT_WIDTH),
        .DEST0_SAME_CLOCK(DEST0_SAME_CLOCK),.DEST1_SAME_CLOCK(DEST1_SAME_CLOCK)) u_fanout(
        .i_source_clk(i_pixel_clk),.i_source_rst_n(cohort_rst_n),
        .s_config_data(s_config_data),.s_config_valid(s_config_valid),.s_config_ready(s_config_ready),
        .m_config_ack_data(m_config_ack_data),.m_config_ack_valid(m_config_ack_valid),
        .m_config_ack_ok(m_config_ack_ok),.m_config_ack_ready(m_config_ack_ready),
        .o_source_reset_done(o_config_reset_done),.o_stale_ack_count(o_stale_ack_count),
        .i_dest0_clk(i_pixel_clk),.i_dest0_rst_n(cohort_rst_n),
        .m_dest0_config_data(plan[0]),.m_dest0_config_valid(plan_valid[0]),.m_dest0_config_ready(plan_ready[0]),
        .s_dest0_applied_data(applied[0]),.s_dest0_applied_valid(applied_valid[0]),
        .s_dest0_applied_ok(applied_ok[0]),.s_dest0_applied_ready(applied_ready[0]),.o_dest0_reset_done(dest_done[0]),
        .i_dest1_clk(i_capture1_clk),.i_dest1_rst_n(cohort_rst_n),
        .m_dest1_config_data(plan[1]),.m_dest1_config_valid(plan_valid[1]),.m_dest1_config_ready(plan_ready[1]),
        .s_dest1_applied_data(applied[1]),.s_dest1_applied_valid(applied_valid[1]),
        .s_dest1_applied_ok(applied_ok[1]),.s_dest1_applied_ready(applied_ready[1]),.o_dest1_reset_done(dest_done[1]));
    // Production SDR capture route. Real HDR has an independent physical
    // two-member receiver; no virtual pixel producer is instantiated here.
    // A local fence owns its proof until that exact local CFG ACK is accepted.
    for(c=0;c<2;c=c+1)begin:receiver
        wire clk=c==0?i_pixel_clk:i_capture1_clk;
        wire rst_n=c==0?reset0:reset1;
        wire ingress_idle=c==0?i_capture0_idle:i_capture1_idle;
        wire selected_idle=c==0?o_capture0_source_idle:o_capture1_source_idle;
        wire enqueue=c==0?i_capture0_enqueue_fire:i_capture1_enqueue_fire;
        wire consume=c==0?i_capture0_consume_fire:i_capture1_consume_fire;
        wire [63:0] time_ns=c==0?o_pixel_time_ns:o_capture1_time_ns;
        wire time_valid=c==0?o_pixel_time_valid:o_capture1_time_valid;
        wire [63:0] enqueued_count,consumed_count;
        if(c==0)begin:counts0
            assign o_enqueued_count0=enqueued_count;assign o_consumed_count0=consumed_count;
        end else begin:counts1
            assign o_enqueued_count1=enqueued_count;assign o_consumed_count1=consumed_count;
        end
        reg owned,sent;
        // Borrow the fanout-owned plan head. No following packet may be sent
        // until BOTH real applications and the aggregate callback complete;
        // this receiver releases owned on its actual application handshake.
        // Cohort reset cancels the lease, including partially assembled heads.
        wire [159+EXT_WIDTH:0] tuple=plan[c];
        wire exact_proof=owned&&proof_valid[c]&&proof_quiet[c]&&
            proof_session[c]==tuple[63:32]&&proof_epoch[c]==tuple[159:128];
        wire applied_fire=applied_valid[c]&&applied_ready[c];
        // Sharing changes only proof lifetime: release follows BOTH true
        // local applications and their accepted aggregate callback. That callback
        // never creates quiescence; the retained cam0 DFI proof supplies it.
        assign proof_ready[c]=m_config_ack_valid&&m_config_ack_ready&&m_config_ack_ok&&
            proof_valid[c]&&proof_quiet[c]&&m_config_ack_data[63:32]==proof_session[c]&&
            m_config_ack_data[159:128]==proof_epoch[c];
        always @(posedge clk or negedge rst_n)begin
            if(!rst_n)begin owned<=0;sent<=0;end
            else begin
                if(plan_valid[c]&&plan_ready[c])begin owned<=1;sent<=0;end
                if(owned&&!sent&&drain_ready[c])sent<=1;
                if(applied_fire)begin owned<=0;sent<=0;end
            end
        end
        raw_capture_drain_cdc #(.CAMERA_ID(c),.CAPTURE_ENABLE(1)) u_drain(
            .i_source_clk(clk),.i_source_rst_n(cohort_rst_n),.i_dfi_clk(i_dfi_clk),.i_dfi_rst_n(cohort_rst_n),
            .i_enqueue_fire(enqueue),.i_consume_fire(consume),.i_source_idle(selected_idle&&ingress_idle),
            .i_write_quiescent(i_capture_write_quiescent&&i_old_processing_quiescent),
            .s_drain_valid(owned&&!sent),.s_drain_ready(drain_ready[c]),
            .s_drain_session(tuple[63:32]),.s_drain_epoch(tuple[159:128]),
            .m_drain_valid(proof_valid[c]),.m_drain_ready(proof_ready[c]),
            .m_drain_session(proof_session[c]),.m_drain_epoch(proof_epoch[c]),
            .m_drain_target(),.m_drain_id(),.o_apply_quiescent(proof_quiet[c]),
            .o_enqueued_count(enqueued_count),
            .o_consumed_count(consumed_count),
            .o_source_fault(drain_fault[c]),.o_dfi_fault(o_dfi_fault[c]),.o_stale_ack_count(),
            .o_source_reset_done(o_local_reset_done[c]),.o_dfi_reset_done(drain_dfi_done[c]));
        if(PRESET_MONO_ENABLE!=0)begin:g_preset_owner
            frame_config_preset_owner u_owner(.i_clk(clk),.i_rst_n(rst_n),
                .s_config_data(plan[c]),.s_config_valid(plan_valid[c]),.s_config_ready(plan_ready[c]),
                .m_applied_data(applied[c]),.m_applied_valid(applied_valid[c]),.m_applied_ok(applied_ok[c]),
                .m_applied_ready(applied_ready[c]),.i_config_reset_done(dest_done[c]),
                .i_source_idle(selected_idle&&ingress_idle&&!absent_source_fault),.i_apply_quiescent(exact_proof),
                .o_active_config(active[c]),.o_initialized(o_initialized[c]),.o_config_fault(cfg_fault[c]),
                .o_plan_busy(local_plan_busy[c]));
            assign virtual_data[c]=0;assign virtual_valid[c]=0;assign virtual_sof[c]=0;
            assign virtual_eol[c]=0;assign virtual_eof[c]=0;assign virtual_abort[c]=0;
            assign virtual_session[c]=0;assign virtual_epoch[c]=0;assign virtual_sequence[c]=0;
            assign virtual_metadata[c]=0;assign virtual_idle[c]=1;
        end
    end
    end else begin:g_joint_config_owner
        wire joint_initialized,joint_busy,joint_fault;
        assign plan_valid=0;
        assign virtual_idle=2'b11;
        assign virtual_valid=0;assign virtual_sof=0;assign virtual_eol=0;
        assign virtual_eof=0;assign virtual_abort=0;
        assign virtual_data[0]=0;assign virtual_data[1]=0;
        assign virtual_session[0]=0;assign virtual_session[1]=0;
        assign virtual_epoch[0]=0;assign virtual_epoch[1]=0;
        assign virtual_sequence[0]=0;assign virtual_sequence[1]=0;
        assign virtual_metadata[0]=0;assign virtual_metadata[1]=0;
        physical_pair_config_owner #(.TRUSTED_INPUT(TRUSTED_INPUT)) u_joint(
            .clk(i_pixel_clk),.owner_rst_n(reset0),.cohort_rst_n(cohort_rst_n),.dfi_clk(i_dfi_clk),
            .s_config_data(s_config_data),.s_config_valid(s_config_valid),.s_config_ready(s_config_ready),
            .m_config_ack_data(m_config_ack_data),.m_config_ack_valid(m_config_ack_valid),
            .m_config_ack_ok(m_config_ack_ok),.m_config_ack_ready(m_config_ack_ready),
            .source0_idle(o_capture0_source_idle&&i_capture0_idle),.source1_idle(o_capture1_source_idle&&i_capture1_idle),
            .enqueue0(i_capture0_enqueue_fire),.enqueue1(i_capture1_enqueue_fire),
            .consume0(i_capture0_consume_fire),.consume1(i_capture1_consume_fire),
            .write_quiet(i_capture_write_quiescent&&i_old_processing_quiescent),
            .active_config(active[0]),.initialized(joint_initialized),.busy(joint_busy),.config_fault(joint_fault),
            .drain_fault(drain_fault),.dfi_fault(o_dfi_fault),.local_reset_done(o_local_reset_done),
            .config_reset_done(o_config_reset_done),
            .enqueued0(o_enqueued_count0),.enqueued1(o_enqueued_count1),
            .consumed0(o_consumed_count0),.consumed1(o_consumed_count1));
        assign active[1]=active[0];
        assign o_initialized={2{joint_initialized}};
        assign cfg_fault={2{joint_fault}};
        assign local_plan_busy={2{joint_busy}};
        // No asynchronous application reply remains in this same-clock owner.
        // Per-member drain stale ACK detection remains in each real drain.
        assign o_stale_ack_count=0;
    end endgenerate
    wire physical_fault;
    wire [39:0] physical_data;
    wire physical_valid,physical_accept,physical_sof,physical_eol,physical_eof,physical_abort,physical_idle;
    wire [31:0] physical_session,physical_epoch,physical_sequence;
    wire [196:0] physical_metadata;
    // The optional whole-frame owner freezes this permission at the actual FS.
    // Later CFG pause cannot split the cropped SOF from its sensor frame.
    assign o_physical_admit_enable=physical_selected&&permit0&&o_pixel_time_valid&&
        !local_plan_busy[0]&&!plan_valid[0]&&o_initialized[0];
    physical_capture_router #(.WIDTH(WIDTH),.HEIGHT(HEIGHT)) u_physical(
        .clk(i_pixel_clk),.rst_n(reset0),.i_future_enable(PHYSICAL_FRAME_FENCE_ENABLE!=0 ?
            (physical_selected&&i_physical_frame_enable) : o_physical_admit_enable),
        .i_initialized(o_initialized[0]),.i_active_config(active[0][159:0]),
        .i_data(i_physical_data),.i_valid(i_physical_valid),.i_accept(i_physical_accept),
        .i_sof(i_physical_sof),.i_eol(i_physical_eol),.i_abort(i_physical_abort),.i_metadata(i_physical_metadata),
        .i_source_sequence(i_physical_sequence),.i_source_identity_valid(i_physical_identity_valid),
        .o_data(physical_data),.o_valid(physical_valid),.o_accept(physical_accept),.o_sof(physical_sof),
        .o_eol(physical_eol),.o_eof(physical_eof),.o_abort(physical_abort),.o_frame_idle(physical_idle),
        .o_session(physical_session),.o_epoch(physical_epoch),.o_sequence(physical_sequence),
        .o_metadata(physical_metadata),.o_fault(physical_fault));
    assign o_source_fault={cfg_fault[1]||drain_fault[1],cfg_fault[0]||drain_fault[0]||physical_fault||time_overflow};
    assign o_active_config0=active[0];assign o_active_config1=active[1];
    assign o_capture0_data=physical_selected?physical_data:virtual_data[0];
    assign o_capture0_valid=physical_selected?physical_valid:virtual_valid[0];
    assign o_capture0_accept=physical_selected?physical_accept:1'b1;
    assign o_capture0_sof=physical_selected?physical_sof:virtual_sof[0];
    assign o_capture0_eol=physical_selected?physical_eol:virtual_eol[0];
    assign o_capture0_eof=physical_selected?physical_eof:virtual_eof[0];
    assign o_capture0_abort=physical_selected?physical_abort:virtual_abort[0];
    assign o_capture0_session=physical_selected?physical_session:virtual_session[0];
    assign o_capture0_epoch=physical_selected?physical_epoch:virtual_epoch[0];
    assign o_capture0_sequence=physical_selected?physical_sequence:virtual_sequence[0];
    assign o_capture0_metadata=physical_selected?physical_metadata:virtual_metadata[0];
    assign o_capture0_source_idle=physical_selected ?
        (physical_idle&&(PHYSICAL_FRAME_FENCE_ENABLE==0||i_physical_source_idle)) : virtual_idle[0];
    assign o_capture1_data=virtual_data[1];
    assign o_capture1_valid=SOURCE_SELECT==2&&virtual_valid[1];
    assign o_capture1_accept=1'b1;
    assign o_capture1_sof=SOURCE_SELECT==2&&virtual_sof[1];
    assign o_capture1_eol=SOURCE_SELECT==2&&virtual_eol[1];
    assign o_capture1_eof=SOURCE_SELECT==2&&virtual_eof[1];
    assign o_capture1_abort=SOURCE_SELECT==2&&virtual_abort[1];
    assign o_capture1_session=virtual_session[1];assign o_capture1_epoch=virtual_epoch[1];
    assign o_capture1_sequence=virtual_sequence[1];assign o_capture1_metadata=virtual_metadata[1];
    assign o_capture1_source_idle=virtual_idle[1];
    // Only the ingress' real start handshake constitutes capture acceptance.
    assign o_capture0_frame_accept=i_capture0_frame_accept&&o_capture0_valid&&o_capture0_accept&&o_capture0_sof;
    assign o_capture1_frame_accept=i_capture1_frame_accept&&o_capture1_valid&&o_capture1_accept&&o_capture1_sof;
endmodule
`default_nettype wire
