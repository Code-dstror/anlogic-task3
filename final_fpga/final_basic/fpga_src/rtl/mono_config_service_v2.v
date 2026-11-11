// Sparse candidate profile: legacy four-ROI analysis requests are unsupported.
`timescale 1ns/1ps
// Stage3 FULL/HDR-only replacement, with the unchanged public service API.
// Dedicated words use the two existing official 40x512 FIFO instances.
module mono_config_service_v2 #(
    parameter integer PROFILE=1,MAX_WIDTH=1920,MAX_HEIGHT=1080,
    parameter integer REMOTE_CONFIG_ENABLE=1,EXT_WIDTH=1024,EXT_STRIPS=4,
    parameter [31:0] EXT_COMBINATIONS=0,parameter [7:0] EXT_SUPPORTED=0,
    parameter [2:0] V2_SUPPORTED_MODES=0,parameter [5:0] V2_SUPPORTED_ENABLES=0,
    parameter integer LIVE_GRAY_FIXED_ENABLE=0,LIVE_BASIC_MODES_ENABLE=1,
    parameter integer COMPACT_EMPTY_EXTENSION_ENABLE=0,COMPACT_STAGE2_EXTENSION_ENABLE=1,
    parameter integer LANE_GAUSSIAN_ONLY=1,CFG_DIAG_ENABLE=0,STEREO_CAPABLE=0,
    parameter integer APPLY_SOURCE_FAULT_ENABLE=0
) (
    input wire user_clk,user_rst_n,pixel_clk,pixel_rst_n,
    input wire i_stereo_mode,output wire o_user_transaction_idle,output wire o_user_stereo_compatible,
    input wire write_valid,input wire [11:0] write_offset,input wire [31:0] write_data,input wire [3:0] write_strobes,
    output wire [1:0] write_response,input wire read_valid,input wire [11:0] read_offset,
    output wire read_response_valid,output wire [31:0] read_data,output wire [1:0] read_response,
    input wire pipeline_idle,frame_accept,input wire [31:0] frame_sequence,
    output wire source_ready,pause_new_jobs,output wire [1:0] active_mode,
    output wire [7:0] active_quality,output wire adaptive_quality,output wire [7:0] minimum_quality,
    output wire [24:0] frame_budget,output wire [15:0] restart_mcus,
    output wire [31:0] source_session,mode_epoch,user_session,output wire user_initialized,pixel_initialized,
    output wire [159+EXT_WIDTH:0] m_config_data,output wire m_config_valid,input wire m_config_ready,
    input wire [159+EXT_WIDTH:0] s_config_ack_data,input wire s_config_ack_valid,s_config_ack_ok,
    output wire s_config_ack_ready,config_fault,output wire [31:0] config_stale_ack_count,
    output wire [159+EXT_WIDTH:0] active_config,
    output wire active_schema2,active_legacy_gaussian,
    output wire [1:0] active_product_mode,
    output wire [5:0] active_processing_enables,
    input wire [1:0] diag_observer_rst_n,
    input wire diag_source_fs,
    input wire [15:0] diag_source_gates,
    output wire [447:0] diag_domains,
    output wire [1:0] diag_domain_reset_n,
    input wire i_apply_source_fault,
    output wire [11:0] o_apply_diagnostics
);
    generate if(PROFILE!=1||REMOTE_CONFIG_ENABLE!=1||EXT_WIDTH!=1024||EXT_STRIPS!=4||EXT_COMBINATIONS!=0||
        (EXT_SUPPORTED&8'hc3)!=0||LIVE_GRAY_FIXED_ENABLE!=0||LIVE_BASIC_MODES_ENABLE!=1||COMPACT_EMPTY_EXTENSION_ENABLE!=0||COMPACT_STAGE2_EXTENSION_ENABLE!=1)begin:g_invalid_profile
        config_store_requires_full_hdr_profile invalid_configuration();
    end endgenerate
    // Legacy FULL couples F22/F23 to an explicit four-ROI tuple.
    // Schema2 retains every mode and independent processing-enable bit.
    localparam [7:0] PROFILE_LEGACY_SUPPORTED = EXT_SUPPORTED & 8'hcf;
    wire cohort=user_rst_n&&pixel_rst_n;
    wire user_local,pixel_local;
    reset_release_sync u_user_reset(.i_clk(user_clk),.i_async_rst_n(cohort),.o_rst_n(user_local));
    reset_release_sync #(.FALLING_RELEASE(1)) u_pixel_reset(.i_clk(pixel_clk),.i_async_rst_n(cohort),.o_rst_n(pixel_local));
    assign diag_domain_reset_n={pixel_local,user_rst_n};
    wire [39:0] command_source,command_sink,response_source,response_sink;
    wire command_source_valid,command_source_ready,command_sink_valid,command_sink_ready;
    wire response_source_valid,response_source_ready,response_sink_valid,response_sink_ready;
    wire command_user_done,command_pixel_done,response_user_done,response_pixel_done;
    control_message_fifo_ip #(.MESSAGE_WIDTH(40),.BORROW_SOURCE(1)) u_command_fifo(
        .o_sink_flit_read(),.o_sink_flit_data(),.o_sink_flit_index(),
        .i_source_clk(user_clk),.i_source_rst_n(user_local),.i_source_data(command_source),.i_source_valid(command_source_valid),
        .o_source_ready(command_source_ready),.o_source_reset_done(command_user_done),
        .i_sink_clk(pixel_clk),.i_sink_rst_n(pixel_local),.o_sink_data(command_sink),.o_sink_valid(command_sink_valid),
        .i_sink_ready(command_sink_ready),.o_sink_reset_done(command_pixel_done));
    control_message_fifo_ip #(.MESSAGE_WIDTH(40),.BORROW_SOURCE(1)) u_response_fifo(
        .o_sink_flit_read(),.o_sink_flit_data(),.o_sink_flit_index(),
        .i_source_clk(pixel_clk),.i_source_rst_n(pixel_local),.i_source_data(response_source),.i_source_valid(response_source_valid),
        .o_source_ready(response_source_ready),.o_source_reset_done(response_pixel_done),
        .i_sink_clk(user_clk),.i_sink_rst_n(user_local),.o_sink_data(response_sink),.o_sink_valid(response_sink_valid),
        .i_sink_ready(response_sink_ready),.o_sink_reset_done(response_user_done));
    mono_config_bar_v2 #(.STEREO_CAPABLE(STEREO_CAPABLE),.PROFILE(PROFILE),.WIDTH(MAX_WIDTH),.HEIGHT(MAX_HEIGHT),.LANE_GAUSSIAN_ONLY(LANE_GAUSSIAN_ONLY),.CFG_DIAG_ENABLE(CFG_DIAG_ENABLE),
        .LEGACY_SUPPORTED(PROFILE_LEGACY_SUPPORTED),.V2_SUPPORTED_MODES(V2_SUPPORTED_MODES),.V2_SUPPORTED_ENABLES(V2_SUPPORTED_ENABLES)) u_bar(
        .clk(user_clk),.rst_n(user_rst_n),.stream_ready(command_user_done&&response_user_done),
        .i_stereo_mode(i_stereo_mode),.o_transaction_idle(o_user_transaction_idle),.o_stereo_compatible(o_user_stereo_compatible),
        .write_valid(write_valid),.write_offset(write_offset),.write_data(write_data),.write_strobes(write_strobes),.write_response(write_response),
        .read_valid(read_valid),.read_offset(read_offset),.read_response_valid(read_response_valid),.read_data(read_data),.read_response(read_response),
        .command_data(command_source),.command_valid(command_source_valid),.command_ready(command_source_ready),
        .response_data(response_sink),.response_valid(response_sink_valid),.response_ready(response_sink_ready),
        .initialized(user_initialized),.session_id(user_session),
        .diag_observer_rst_n(diag_observer_rst_n[0]),.diag_data(diag_domains[223:0]));
    mono_config_engine_v2 #(.WIDTH(MAX_WIDTH),.HEIGHT(MAX_HEIGHT),.LANE_GAUSSIAN_ONLY(LANE_GAUSSIAN_ONLY),
        .TRUSTED_COMMANDS(1),.CFG_DIAG_ENABLE(CFG_DIAG_ENABLE),.APPLY_SOURCE_FAULT_ENABLE(APPLY_SOURCE_FAULT_ENABLE),
        // This profile requires the remote capture/DFI whole-ACK barrier.
        // PREPARE still requires pipeline_idle; after its matching ACK, new
        // stored captures must not wait for newly started processing to idle.
        .FRAME_APPLY_REQUIRE_IDLE(0),
        .LEGACY_SUPPORTED(PROFILE_LEGACY_SUPPORTED),.V2_SUPPORTED_MODES(V2_SUPPORTED_MODES),.V2_SUPPORTED_ENABLES(V2_SUPPORTED_ENABLES)) u_engine(
        .clk(pixel_clk),.rst_n(pixel_local),.command_data(command_sink),.command_valid(command_sink_valid),.command_ready(command_sink_ready),
        .response_data(response_source),.response_valid(response_source_valid),.response_ready(response_source_ready),
        .pipeline_idle(pipeline_idle),.frame_accept(frame_accept),.frame_sequence(frame_sequence),.source_ready(source_ready),.pause_new_jobs(pause_new_jobs),
        .active_mode(active_mode),.active_quality(active_quality),.adaptive_quality(adaptive_quality),.minimum_quality(minimum_quality),
        .frame_budget(frame_budget),.restart_mcus(restart_mcus),.source_session(source_session),.mode_epoch(mode_epoch),.pixel_initialized(pixel_initialized),
        .m_config_data(m_config_data),.m_config_valid(m_config_valid),.m_config_ready(m_config_ready),
        .s_config_ack_data(s_config_ack_data),.s_config_ack_valid(s_config_ack_valid),.s_config_ack_ok(s_config_ack_ok),.s_config_ack_ready(s_config_ack_ready),
        .config_fault(config_fault),.config_stale_ack_count(config_stale_ack_count),.active_config(active_config),
        .active_schema2(active_schema2),.active_legacy_gaussian(active_legacy_gaussian),
        .active_product_mode(active_product_mode),.active_processing_enables(active_processing_enables),
        .diag_observer_rst_n(diag_observer_rst_n[1]),.diag_source_fs(diag_source_fs),
        .diag_source_gates(diag_source_gates),.diag_data(diag_domains[447:224]),
        .i_apply_source_fault(i_apply_source_fault),.o_apply_diagnostics(o_apply_diagnostics));
endmodule
