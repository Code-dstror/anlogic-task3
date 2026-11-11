`timescale 1ns / 1ps
`include "pcie_protocol_v1.vh"

// HDR and stored SDR share the existing capture region and replay FIFO.
module full_raw_store #(
    parameter integer WIDTH = 1920, parameter integer HEIGHT = 1080,
    parameter integer DESCRIPTOR_ENABLE = 0,
    parameter integer DUAL_CAPTURE_ENABLE = 0,
    parameter integer PAIR_METADATA_ENABLE = 0,
    parameter integer PHYSICAL_MONO_CURRENT_ENABLE = 0,
    parameter integer CAMERA_COUNT = 2,
    parameter integer CANONICAL_PRIVATE_FETCH_ENABLE = 0,
    parameter integer MASK_EXPORT_ENABLE = 0,
    parameter integer SHARED_REPLAY_FIFO_ENABLE = 0,
    parameter integer PRIVATE_REPLAY_ENABLE = 0,
    parameter integer HOST_REPLAY_CONTEXT_ENABLE = 0,
    parameter integer SOURCE_TERMINAL_ENABLE = 0,
    parameter integer CFS_ENABLE = 0,
    parameter integer OFFICIAL_CRC_QUALIFIED = 0,
    parameter integer STEREO_ENABLE=0,STEREO_CAPTURE_DIVISOR=4,
    parameter integer STEREO_RUNTIME_CADENCE=0, SECOND_HDR_CAMERA=0,
    parameter integer SHARED_DECODE_ENABLE=0, RAW_EXPORT_ENABLE=0,
    parameter integer STEREO_SLOT_LOCAL_RETIRE_ENABLE=1,
    parameter integer HDR_SLOT_LOCAL_RETIRE_ENABLE=1,
    parameter integer SEPARATE_DFI_DATA_RESET=0,
    parameter integer UHD_WIDTH=0,UHD_HEIGHT=0
) (
    // Additional simultaneous LONG/SHORT capture lanes. Bit/slice zero is LONG.
    input wire i_cam1_hdr_enable,
    input wire [79:0] i_cam1_hdr_data,
    input wire [1:0] i_cam1_hdr_valid,i_cam1_hdr_sof,i_cam1_hdr_eol,i_cam1_hdr_abort,
    input wire [63:0] i_cam1_hdr_sequence,
    input wire [393:0] i_cam1_hdr_metadata,
    input wire [1:0] i_cam1_hdr_source_valid,i_cam1_hdr_source_ok,
    input wire [63:0] i_cam1_hdr_source_session,i_cam1_hdr_source_epoch,i_cam1_hdr_source_sequence,
    input wire [15:0] i_cam1_hdr_source_error,
    output wire [1:0] o_cam1_hdr_source_ready,o_cam1_hdr_idle,
    output wire [1:0] o_cam1_hdr_admit,o_sdr_begin_reject,o_sdr_bad_finish,
    input wire i_stereo_mode,
    input wire i_raw_export,i_raw_cancel,
    output wire o_raw_record_valid,input wire i_raw_record_ready,
    output wire [31:0] o_raw_record_length,output wire [127:0] o_raw_record_identity,
    output wire [127:0] o_raw_data,output wire [15:0] o_raw_keep,
    output wire o_raw_valid,o_raw_last,input wire i_raw_ready,
    output wire o_raw_done_valid,o_raw_done_ok,o_raw_drained,
    input wire i_raw_retire_valid,output wire o_raw_retire_ready,
    input wire [127:0] i_raw_retire_identity,
    // Separate local mailbox copies: owners use DFI, capture uses PIX.
    input wire i_stereo_mode_pixel,
    input wire [7:0] i_stereo_frame_divisor_pixel,
    output wire o_stereo_job_valid,input wire i_stereo_job_ready,
    output wire [383:0] o_stereo_job_frame,
    output wire [63:0] o_stereo_job_lease,o_stereo_job_id,
    output wire [1:0] o_stereo_job_bayer,output wire o_stereo_job_time_valid,
    input wire i_stereo_retire_valid,input wire [63:0] i_stereo_retire_job_id,
    output wire o_stereo_retire_ready,o_stereo_retire_done,o_stereo_retire_error,o_stereo_empty,
    input wire i_stereo_processing_done,i_stereo_processing_error,
    input wire [63:0] i_stereo_processing_job_id,
    // Stereo decode shares only the DFI body; owner and replay CDC stay local.
    output wire o_decode_start_valid,input wire i_decode_start_ready,
    output wire o_decode_release,o_decode_cancel,o_decode_run,
    output wire [127:0] o_decode_data,output wire [15:0] o_decode_keep,
    output wire o_decode_valid,o_decode_last,input wire i_decode_ready,
    input wire [39:0] i_decode_raw,input wire i_decode_raw_valid,
    output wire o_decode_raw_ready,input wire i_decode_sof,i_decode_eol,
    input wire i_decode_done,i_decode_aborted,i_decode_quiet,i_decode_active,
    // New configuration is borrowed with the existing held pair-config request.
    input wire i_sdr_lz_enable,i_lz_fault,i_lz_region_quiet,
    input wire i_capture_time_valid,
    input wire i_bayer_valid,input wire [1:0] i_isp_bayer_phase,
    output wire o_raw_route_sdr,o_raw_mode_busy,o_raw_mode_applied,o_raw_policy_admit,o_raw_region_quiet,
    output wire o_lz_region_grant,o_lz_stop,
    output wire o_sdr_offer_valid,output wire [447:0] o_sdr_frame_context,
    input wire i_sdr_read_request_valid,input wire [447:0] i_sdr_read_request_context,
    output wire o_sdr_read_request_ready,
    output wire [127:0] o_sdr_read_data,output wire [15:0] o_sdr_read_keep,
    output wire o_sdr_read_valid,o_sdr_read_last,input wire i_sdr_read_ready,
    output wire o_sdr_read_owned,o_sdr_read_done_valid,o_sdr_read_done_ok,
    input wire i_sdr_reader_cancel,i_sdr_release_valid,input wire [447:0] i_sdr_release_context,
    input wire i_sdr_consumer_quiet,output wire o_sdr_release_ready,
    // The HDR pixel reader remains real and external; this mux holds its route.
    input wire [3:0] s_hdr_axi_arid,input wire [27:0] s_hdr_axi_araddr,
    input wire [7:0] s_hdr_axi_arlen,input wire [2:0] s_hdr_axi_arsize,
    input wire [1:0] s_hdr_axi_arburst,input wire s_hdr_axi_arvalid,
    output wire s_hdr_axi_arready,output wire [3:0] s_hdr_axi_rid,
    output wire [127:0] s_hdr_axi_rdata,output wire [1:0] s_hdr_axi_rresp,
    output wire s_hdr_axi_rlast,s_hdr_axi_rvalid,input wire s_hdr_axi_rready,

    input wire i_identity_rst_n,i_pair_stop,i_pair_fault,
    input wire i_pair_config_valid,output wire o_pair_config_ready,o_pair_config_error,
    input wire [31:0] i_pair_session,i_pair_epoch,i_pair_max_wait,i_pair_max_age,
    input wire [63:0] i_pair_max_delta,input wire [2:0] i_pair_ratio,
    input wire i_pair_hdr_enable,
    output wire o_pair_valid,o_pair_bank,input wire i_pair_ready,
    output wire [63:0] o_pair_id,
    input wire i_pair_release_valid,i_pair_release_bank,
    input wire [63:0] i_pair_release_id,
    input wire i_pair_read_quiet,i_pair_product_quiet,i_pair_ticket_released,
    output wire o_pair_release_ready,
    input wire i_pair_directory_valid,input wire [1:0] i_pair_directory_slot,
    output wire o_pair_directory_ready,
    output wire [31:0] m_pair_directory_data,output wire [3:0] m_pair_directory_word,
    output wire m_pair_directory_valid,m_pair_directory_last,input wire m_pair_directory_ready,
    input wire [63:0] i_pair_now,
    output wire [1:0] o_hdr_begin_reject,o_hdr_pair_expire,
    output wire [3:0] o_hdr_bad_finish,output wire [7:0] o_hdr_bank_states,
    input wire i_capture_enable,
    input wire i_pixel_clk, input wire i_pixel_rst_n,
    input wire i_dfi_clk, input wire i_dfi_rst_n, input wire i_ddr_ready,
    input wire i_cfs_enable,
    input wire i_physical_mono_current_enable,
    output wire [31:0] o_cfs_compressed_count,o_cfs_no_benefit_count,o_cfs_overflow_count,o_cfs_busy_count,
    output wire o_cfs_protocol_fault,
    input wire i_user_clk, input wire i_user_rst_n,
    input wire [39:0] i_capture_data,
    input wire i_capture_valid, input wire i_capture_accept,
    input wire i_capture_sof, input wire i_capture_eol, input wire i_capture_abort,
    input wire [31:0] i_capture_epoch,
    input wire [31:0] i_session_id, i_frame_sequence, i_mode_epoch,
    input wire [196:0] i_capture_metadata,
    input wire i_capture_source_valid, output wire o_capture_source_ready,
    input wire [31:0] i_capture_source_session, i_capture_source_epoch, i_capture_source_sequence,
    input wire i_capture_source_camera, i_capture_source_ok,
    input wire [7:0] i_capture_source_error,
    output wire [31:0] o_capture_source_stale_count,
    // Optional independent capture domain; absent in the default board profile.
    input wire i_capture1_clk, input wire i_capture1_rst_n,
    input wire [39:0] i_capture1_data,
    input wire i_capture1_valid, input wire i_capture1_accept,
    input wire i_capture1_sof, input wire i_capture1_eol, input wire i_capture1_abort,
    input wire [31:0] i_capture1_session, i_capture1_sequence, i_capture1_epoch,
    input wire [196:0] i_capture1_metadata,
    input wire i_capture1_source_valid, output wire o_capture1_source_ready,
    input wire [31:0] i_capture1_source_session, i_capture1_source_epoch, i_capture1_source_sequence,
    input wire i_capture1_source_camera, i_capture1_source_ok,
    input wire [7:0] i_capture1_source_error,
    output wire [31:0] o_capture1_source_stale_count,
    // Local handshake observations for the independent count-fence owner.
    // capture0 outputs belong to pixel; capture1 outputs to capture1; consume
    // and global write-quiescent belong to DFI. None performs CDC by itself.
    output wire o_capture0_enqueue_fire, o_capture1_enqueue_fire,
    output wire o_capture0_consume_fire, o_capture1_consume_fire,
    output wire o_capture0_idle, o_capture1_idle,
    output wire o_capture0_frame_accept, o_capture1_frame_accept,
    output wire o_capture_write_quiescent,
    output wire o_private_ownership_quiescent,
    // Private DFI-domain candidate/job owner; host pins are independent.
    output wire o_commit_valid,
    output wire [383:0] o_commit_frame,
    output wire [63:0] o_commit_lease,
    input wire i_commit_ready,
    input wire i_ref_valid,
    output wire o_ref_ready,
    input wire [1:0] i_ref_op, i_ref_mask,
    input wire [383:0] i_ref_frame0, i_ref_frame1,
    input wire [63:0] i_ref_lease0, i_ref_lease1, i_ref_job_id,
    output wire o_reference_fault,
    output wire o_read_quiescent,
    // Optional held phase reuses the complete 147x512 replay FIFO. DFI and
    // PIX selects belong to their respective domains and remain held until
    // the real source/product/reference owners have retired.
    input wire i_shared_replay_source_select,i_shared_replay_sink_select,
    input wire [146:0] s_shared_replay_data,input wire s_shared_replay_valid,
    output wire s_shared_replay_ready,o_shared_replay_source_reset_done,
    output wire [146:0] m_shared_replay_data,output wire m_shared_replay_valid,
    input wire m_shared_replay_ready,
    output wire o_shared_replay_sink_reset_done,
    // DFI-domain private read client. This interface has no BAR ABI exposure.
    input wire i_private_req_valid, output wire o_private_req_ready,
    input wire [2:0] i_private_req_op,
    input wire i_private_req_camera,
    input wire [1:0] i_private_req_slot,
    input wire [31:0] i_private_req_generation, i_private_req_session,
    input wire [63:0] i_private_req_lease, i_private_req_job_id,
    input wire [31:0] i_private_req_offset,i_private_req_length,
    input wire i_public_read_admission_enable,
    output wire o_public_read_quiescent,
    // Optional public MASK target in DFI. These packets borrow the existing
    // command/response/block transport; the target owns it through cache RETIRE.
    output wire [133:0] o_mask_command_data,
    output wire o_mask_command_valid,
    input wire i_mask_command_ready,
    input wire [146:0] i_mask_response_data,
    input wire i_mask_response_valid,
    output wire o_mask_response_ready,
    input wire [146:0] i_mask_block_data,
    input wire i_mask_block_valid,
    output wire o_mask_block_ready,
    output wire o_mask_cache_retire,
    input wire i_mask_owner_complete,
    input wire [383:0] i_private_descriptor,
    input wire [63:0] i_private_pair_id,
    input wire i_private_member_index,
    output wire o_private_rsp_valid, input wire i_private_rsp_ready,
    output wire [3:0] o_private_rsp_code,
    output wire o_private_rsp_camera,
    output wire [1:0] o_private_rsp_slot,
    output wire [31:0] o_private_rsp_generation, o_private_rsp_session,
    output wire [31:0] o_private_rsp_sequence, o_private_rsp_epoch,
    output wire [383:0] o_private_rsp_descriptor,
    output wire o_private_rsp_metadata_valid,
    output wire [127:0] o_private_read_data,
    output wire [15:0] o_private_read_keep,
    output wire o_private_read_valid,o_private_read_last,
    input wire i_private_read_ready,
    output wire o_private_read_complete,o_private_read_error,o_private_read_protocol_fault,
    output wire o_private_native_done, o_private_native_error,
    output wire [63:0] o_private_native_job_id,
    output wire o_private_native_member_index,
    // Pixel-domain original frame context, admitted before native SOF.
    output wire o_replay_context_valid, input wire i_replay_context_ready,
    output wire [383:0] o_replay_descriptor,
    output wire [63:0] o_replay_job_id, o_replay_pair_id,
    output wire o_replay_member_index, o_replay_private,
    output wire o_replay_protocol_fault,
    output wire o_host_replay_context_valid,
    input wire i_host_replay_context_ready,
    output wire [383:0] o_host_replay_descriptor,
    output wire o_host_replay_metadata_valid,
    // Pixel-domain true private source completion, including a zero-pixel error.
    output wire o_replay_native_done,o_replay_native_error,
    input wire i_replay_safe,
    output wire o_replay_active,
    output wire [39:0] o_replay_data, output wire o_replay_valid,
    input wire i_replay_ready,
    output wire o_replay_sof, output wire o_replay_eol, output wire o_replay_abort,
    input wire i_bar_write_valid, input wire [11:0] i_bar_write_offset,
    input wire [31:0] i_bar_write_data, input wire [3:0] i_bar_write_strobes,
    output wire [1:0] o_bar_write_response,
    input wire i_bar_read_valid, input wire [11:0] i_bar_read_offset,
    output wire o_bar_read_response_valid, output wire [31:0] o_bar_read_data,
    output wire [1:0] o_bar_read_response,
    output wire [3:0] m_axi_awid,
    output wire [27:0] m_axi_awaddr,
    output wire [7:0] m_axi_awlen,
    output wire [2:0] m_axi_awsize,
    output wire [1:0] m_axi_awburst,
    output wire m_axi_awvalid,
    input wire m_axi_awready,
    output wire [127:0] m_axi_wdata,
    output wire [15:0] m_axi_wstrb,
    output wire m_axi_wlast,
    output wire m_axi_wvalid,
    input wire m_axi_wready,
    input wire [3:0] m_axi_bid,
    input wire [1:0] m_axi_bresp,
    input wire m_axi_bvalid,
    output wire m_axi_bready,
    output wire [3:0] m_axi_arid,
    output wire [27:0] m_axi_araddr,
    output wire [7:0] m_axi_arlen,
    output wire [2:0] m_axi_arsize,
    output wire [1:0] m_axi_arburst,
    output wire m_axi_arvalid,
    input wire m_axi_arready,
    input wire [3:0] m_axi_rid,
    input wire [127:0] m_axi_rdata,
    input wire [1:0] m_axi_rresp,
    input wire m_axi_rlast,
    input wire m_axi_rvalid,
    output wire m_axi_rready,
    input wire i_identity_data_rst_n,
    // Cold committed geometry in each local domain. The capture FIFO carries
    // the geometry that actually produced each descriptor to the DFI owner.
    input wire i_uhd_pixel,i_uhd_dfi,
    output wire o_decode_uhd
);

    localparam UHD_ENABLED=UHD_WIDTH!=0||UHD_HEIGHT!=0;
    // CFS, MASK, public RAW and stored-MONO are absent in this application
    // profile. A separate generic raw_frame_service remains in the repository.
    generate if((SECOND_HDR_CAMERA!=0 && (DUAL_CAPTURE_ENABLE==0||STEREO_ENABLE==0))||CAMERA_COUNT!=1||(DUAL_CAPTURE_ENABLE!=0&&DUAL_CAPTURE_ENABLE!=1)||CFS_ENABLE!=0||
        MASK_EXPORT_ENABLE!=0||PHYSICAL_MONO_CURRENT_ENABLE!=0||
        CANONICAL_PRIVATE_FETCH_ENABLE!=1||SHARED_REPLAY_FIFO_ENABLE!=1||
        DESCRIPTOR_ENABLE!=1||PAIR_METADATA_ENABLE!=1||
        (UHD_ENABLED&&(STEREO_ENABLE==0||DUAL_CAPTURE_ENABLE==0)))begin:g_bad_profile
        HDR_STORE_REQUIRES_SINGLE_QUALIFIED_CANONICAL_PROFILE invalid_profile();
    end endgenerate
    localparam [2:0] CFG_IDLE=0,CFG_SELECT=1,CFG_APPLY=2,CFG_OWNER=3,CFG_REPLY=4,CFG_VERIFY=5,CFG_REJECT=6;
    reg [2:0] cfg_state;
    reg configured,hdr_enabled,cfg_error;
    wire route_sdr,select_ready,select_applied,select_error,frontend_stop,frontend_quiet;
    wire [31:0] active_session,active_epoch;
    wire hdr_empty,hdr_owner_fault,writer_fault;
    wire [7:0] cap_awid;
    wire [55:0] cap_awaddr;
    wire [15:0] cap_awlen;
    wire [5:0] cap_awsize;
    wire [3:0] cap_awburst;
    wire [1:0] cap_awvalid;
    wire [1:0] cap_awready;
    wire [255:0] cap_wdata;
    wire [31:0] cap_wstrb;
    wire [1:0] cap_wlast;
    wire [1:0] cap_wvalid;
    wire [1:0] cap_wready;
    wire [7:0] cap_bid;
    wire [3:0] cap_bresp;
    wire [1:0] cap_bvalid;
    wire [1:0] cap_bready;
    // Each eye owns its in-flight exposure writers and pair directory. Only the
    // selected, acquired eye can supply the shared job cache, reader or release.
    wire [1:0] eye_empty,eye_owner_fault,eye_writer_fault,eye_stop,eye_quiet,eye_wr_quiet;
    wire [1:0] eye_sel_ready,eye_applied,eye_cfg_ready,eye_cfg_error;
    wire [1:0] eye_pair_valid,eye_bank,eye_rel_ready,eye_dir_ready,eye_dir_valid,eye_dir_last;
    wire [127:0] eye_id;
    wire [63:0] eye_dir_data;
    wire [7:0] eye_dir_word;
    wire eye,offer,acquired;
    wire outer_bus_quiet,outer_bus_fault;
    wire [1:0] take_eye,release_eye,ask_directory,consume_directory;
    reg [1:0] selection_done;
    always @(posedge i_dfi_clk or negedge i_identity_rst_n)begin
        if(!i_identity_rst_n)selection_done<=0;
        else if(cfg_state==CFG_SELECT)selection_done<=0;
        else if(cfg_state==CFG_APPLY)selection_done<=selection_done|eye_applied;
    end
    assign select_ready=&eye_sel_ready;
    assign select_applied=&(selection_done|eye_applied);
    assign hdr_empty=(&eye_empty)&&!offer;
    assign hdr_owner_fault=|eye_owner_fault;
    assign writer_fault=(|eye_writer_fault)||outer_bus_fault;
    assign frontend_stop=|eye_stop;
    assign frontend_quiet=(&eye_quiet)&&outer_bus_quiet;
    assign o_capture_write_quiescent=(&eye_wr_quiet)&&outer_bus_quiet;
    assign o_pair_valid=offer&&!acquired&&eye_pair_valid[eye];
    assign o_pair_id=eye_id[eye*64+:64];
    assign o_pair_bank=eye_bank[eye];
    assign take_eye=(eye ? 2'b10:2'b01)&{2{o_pair_valid&&i_pair_ready}};
    assign o_pair_release_ready=acquired&&eye_rel_ready[eye];
    assign release_eye=(eye ? 2'b10:2'b01)&{2{acquired&&i_pair_release_valid}};
    assign ask_directory=(eye ? 2'b10:2'b01)&{2{acquired&&i_pair_directory_valid}};
    assign o_pair_directory_ready=acquired&&eye_dir_ready[eye];
    assign m_pair_directory_valid=acquired&&eye_dir_valid[eye];
    assign m_pair_directory_data=eye_dir_data[eye*32+:32];
    assign m_pair_directory_word=eye_dir_word[eye*4+:4];
    assign m_pair_directory_last=eye_dir_last[eye];
    assign consume_directory=(eye ? 2'b10:2'b01)&{2{acquired&&m_pair_directory_ready}};

    generate if(SECOND_HDR_CAMERA!=0)begin:g_eye_dispatch
        reg held,selected,owned,next_eye;
        assign eye=selected;assign offer=held;assign acquired=owned;
        always @(posedge i_dfi_clk or negedge i_identity_rst_n)begin
            if(!i_identity_rst_n)begin held<=0;selected<=0;owned<=0;next_eye<=0;end
            else if(!held)begin
                if(|eye_pair_valid)begin
                    held<=1;
                    selected<=(&eye_pair_valid)?next_eye:eye_pair_valid[1];
                end
            end else if(!owned)begin
                if(o_pair_valid&&i_pair_ready)owned<=1;
                else if(!eye_pair_valid[selected])held<=0;
            end else if(i_pair_release_valid&&o_pair_release_ready)begin
                held<=0;owned<=0;next_eye<=!selected;
            end
        end
    end else begin:g_mono_dispatch
        assign eye=0;assign offer=eye_pair_valid[0];assign acquired=!eye_pair_valid[0];
    end endgenerate
    wire stereo_mode=STEREO_ENABLE!=0&&i_stereo_mode;
    wire stereo_fault,stereo_read_quiet;
    wire raw_fault=i_pair_fault||hdr_owner_fault||writer_fault||stereo_fault;
    wire stop_fault=raw_fault;
    wire [383:0] capture_frame;
    wire begin_valid,begin_ready,begin_accepted,finish_valid,finish_ok,finish_ready;
    wire [1:0] capture_slot,hdr_slot;
    wire hdr_begin_ready,hdr_begin_accepted,hdr_finish_ready;
    wire [31:0] hdr_generation;wire [63:0] hdr_lease;
    wire [383:0] capture_frame1;
    wire begin_valid1,finish_valid1,finish_ok1,hdr_finish1_ready;
    wire stereo_begin_ready,stereo_begin_accepted;
    wire [1:0] stereo_slot,stereo_finish_ready;
    reg begin_owner_valid,begin_owner1,begin_next;
    wire authority_begin_ready=stereo_mode?stereo_begin_ready:hdr_begin_ready;
    wire authority_begin_accepted=stereo_mode?stereo_begin_accepted:hdr_begin_accepted;
    wire [1:0] authority_slot=stereo_mode?stereo_slot:hdr_slot;
    wire authority_ready1=authority_begin_ready&&begin_owner_valid&&begin_owner1&&(!route_sdr||stereo_mode);
    assign o_sdr_begin_reject=(begin_owner1?2'b10:2'b01)&
        {2{stereo_mode&&begin_owner_valid&&authority_begin_ready&&!authority_begin_accepted}};
    assign o_sdr_bad_finish={finish_valid1&&stereo_finish_ready[1]&&!finish_ok1,
        finish_valid&&stereo_finish_ready[0]&&!finish_ok}&{2{stereo_mode}};
    wire hdr_begin_request=!stereo_mode&&(DUAL_CAPTURE_ENABLE!=0?begin_owner_valid:(begin_valid&&!route_sdr));
    wire [383:0] hdr_begin_frame=DUAL_CAPTURE_ENABLE!=0&&begin_owner1?capture_frame1:capture_frame;
    wire hdr_ready0=hdr_begin_ready&&(DUAL_CAPTURE_ENABLE==0||(begin_owner_valid&&!begin_owner1));
    wire hdr_ready1=hdr_begin_ready&&begin_owner_valid&&begin_owner1&&!route_sdr;
    reg [1:0] commit_slot0;
    reg [31:0] commit_generation0;
    reg [63:0] commit_lease0;
    always @(posedge i_dfi_clk or negedge i_identity_rst_n)begin
        if(!i_identity_rst_n)begin begin_owner_valid<=0;begin_owner1<=0;begin_next<=0;commit_slot0<=0;commit_generation0<=0;commit_lease0<=0;end
        else begin
            if(!begin_owner_valid&&(!route_sdr||stereo_mode)&&(begin_valid||begin_valid1))begin
                begin_owner_valid<=1;
                begin_owner1<=begin_valid&&begin_valid1?begin_next:begin_valid1;
            end
            if(begin_owner_valid&&authority_begin_ready)begin begin_owner_valid<=0;begin_next<=!begin_owner1;end
            if(begin_valid&&begin_ready&&begin_accepted&&!route_sdr)begin
                commit_slot0<=hdr_slot;commit_generation0<=hdr_generation;commit_lease0<=hdr_lease;
            end
        end
    end

    wire hdr_cfg_ready=&eye_cfg_ready;
    wire hdr_cfg_error=|eye_cfg_error;
    wire invalid_config=i_pair_session==0||(|i_pair_max_delta[63:32])||
        i_sdr_lz_enable||i_pair_max_wait==0||i_pair_max_age==0||
        (UHD_ENABLED&&i_uhd_dfi&&i_pair_hdr_enable)||
        (i_pair_hdr_enable&&(DUAL_CAPTURE_ENABLE!=0?i_pair_ratio!=4:(i_pair_ratio==0||i_pair_ratio>4)));
    wire all_policy_quiet=hdr_empty&&o_stereo_empty&&i_pair_read_quiet&&
        i_pair_product_quiet&&i_pair_ticket_released&&!stop_fault;
    wire policy_admit=configured&&(cfg_state==CFG_IDLE||cfg_state==CFG_REJECT)&&!stop_fault&&
        ((!route_sdr&&hdr_enabled)||(route_sdr&&stereo_mode));
    // i_pair_config_valid and all config fields remain held by the existing
    // config service until CFG_REPLY. No fabricated early APPLY ACK is returned.
    assign o_pair_config_ready=cfg_state==CFG_REPLY||cfg_state==CFG_REJECT;
    assign o_pair_config_error=cfg_error;
    assign o_raw_mode_busy=cfg_state!=CFG_IDLE;
    assign o_raw_mode_applied=cfg_state==CFG_REPLY&&i_pair_config_valid&&!cfg_error;
    assign o_raw_route_sdr=route_sdr;
    assign o_raw_policy_admit=policy_admit;
    assign o_raw_region_quiet=frontend_quiet&&all_policy_quiet&&cfg_state==CFG_IDLE;
    assign o_lz_region_grant=1'b0;
    assign o_lz_stop=1'b1;
    always @(posedge i_dfi_clk or negedge i_identity_rst_n)begin
        if(!i_identity_rst_n)begin cfg_state<=CFG_IDLE;configured<=0;hdr_enabled<=0;cfg_error<=0;end
        else case(cfg_state)
            CFG_IDLE:if(i_pair_config_valid)begin
                cfg_error<=invalid_config;
                cfg_state<=invalid_config?CFG_REJECT:CFG_SELECT;
            end
            CFG_SELECT:if(select_ready)begin
                hdr_enabled<=i_pair_hdr_enable;configured<=0;cfg_state<=CFG_APPLY;
            end
            CFG_APPLY:if(select_applied)cfg_state<=CFG_OWNER;
            CFG_OWNER:if(hdr_cfg_ready)cfg_state<=CFG_VERIFY;
            // The unchanged HDR owner's config_error is a registered response.
            CFG_VERIFY:begin cfg_error<=hdr_cfg_error;configured<=!hdr_cfg_error;cfg_state<=CFG_REPLY;end
            CFG_REPLY:if(i_pair_config_valid)cfg_state<=CFG_IDLE;
            CFG_REJECT:if(i_pair_config_valid)cfg_state<=CFG_IDLE;
            default:begin configured<=0;cfg_error<=1;cfg_state<=CFG_REPLY;end
        endcase
    end
    // Application reset is a STOP request, never the cold ownership reset.
    // Wait for the existing real HDR drain/owner/SAFE proofs before reopening.
    wire application_stop_dfi;
    raw_application_stop_dfi u_application_stop(
        .i_dfi_clk(i_dfi_clk),.i_cold_rst_n(i_identity_rst_n),
        .i_pixel_rst_n(i_pixel_rst_n),.i_dfi_rst_n(i_dfi_rst_n),
        .i_quiet(frontend_quiet && all_policy_quiet),.o_stop(application_stop_dfi));
    wire [1:0] dense_bayer=i_isp_bayer_phase==0?2'd0:i_isp_bayer_phase==1?2'd3:i_isp_bayer_phase==2?2'd1:2'd2;
    generate if(DUAL_CAPTURE_ENABLE!=0)begin:g_dol2_capture
    dual_raw_capture_frontend #(.WIDTH(WIDTH),.HEIGHT(HEIGHT),.STEREO_ENABLE(STEREO_ENABLE),.COMPACT_CAPTURE_HEADER(1),
        .SEPARATE_DFI_DATA_RESET(SEPARATE_DFI_DATA_RESET),
        .STEREO_CAPTURE_DIVISOR(STEREO_CAPTURE_DIVISOR),.STEREO_RUNTIME_CADENCE(STEREO_RUNTIME_CADENCE),
        .UHD_WIDTH(UHD_WIDTH),.UHD_HEIGHT(UHD_HEIGHT)) u_capture(
        .i_dfi_data_rst_n(i_identity_data_rst_n),
        .i_stereo_mode_pixel(STEREO_ENABLE!=0&&i_stereo_mode_pixel),
        .i_uhd_pixel(i_uhd_pixel),
        .i_stereo_frame_divisor_pixel(i_stereo_frame_divisor_pixel),
        .source_frames1(),.selected_frames1(),.skipped_frames1(),
        .raw_data1(i_capture1_data),.raw_valid1(i_capture1_valid),.raw_accept1(i_capture1_accept),.raw_sof1(i_capture1_sof),.raw_eol1(i_capture1_eol),.raw_abort1(i_capture1_abort),
        .raw_sequence1(i_capture1_sequence),.raw_metadata1(i_capture1_metadata),
        .source_valid1(i_capture1_source_valid),.source_ready1(o_capture1_source_ready),
        .source_session1(i_capture1_source_session),.source_epoch1(i_capture1_source_epoch),.source_sequence1(i_capture1_source_sequence),
        .source_camera1(i_capture1_source_camera),.source_ok1(i_capture1_source_ok),.source_error1(i_capture1_source_error),.source_stale_count1(o_capture1_source_stale_count),
        .capture_frame1(capture_frame1),.begin_valid1(begin_valid1),.begin_ready1(authority_ready1),.begin_accepted1(authority_begin_accepted),.capture_slot1(authority_slot),
        .finish_valid1(finish_valid1),.finish_ok1(finish_ok1),.finish_ready1(stereo_mode?stereo_finish_ready[1]:hdr_finish1_ready),
        .capture_enqueue_fire1(o_capture1_enqueue_fire),.capture_consume_fire1(o_capture1_consume_fire),.capture_idle1(o_capture1_idle),.capture_frame_accept1(o_capture1_frame_accept),
        .pixel_clk(i_pixel_clk),.dfi_clk(i_dfi_clk),.cold_rst_n(i_identity_rst_n),
        .region_grant(i_ddr_ready),.stop(i_pair_stop||stop_fault||cfg_state==CFG_SELECT||cfg_state==CFG_OWNER||cfg_state==CFG_VERIFY||cfg_state==CFG_REPLY),
        .app_reset(application_stop_dfi),.capture_enable(i_capture_enable),
        .select_valid(cfg_state==CFG_SELECT&&select_ready),.select_sdr(!i_pair_hdr_enable),.select_session(i_pair_session),.select_epoch(i_pair_epoch),
        .select_ready(eye_sel_ready[0]),.select_applied(eye_applied[0]),.select_error(select_error),
        .route_sdr(route_sdr),.active_session(active_session),.active_epoch(active_epoch),
        .policy_quiet(all_policy_quiet),.policy_admit(policy_admit),.policy_stop(eye_stop[0]),.local_quiet(eye_quiet[0]),.region_quiet(),
        .raw_data(i_capture_data),.raw_valid(i_capture_valid),.raw_accept(i_capture_accept),.raw_sof(i_capture_sof),.raw_eol(i_capture_eol),.raw_abort(i_capture_abort),
        .raw_sequence(i_frame_sequence),.raw_metadata(i_capture_metadata),.time_valid(i_capture_time_valid),.bayer_valid(i_bayer_valid),.bayer_pattern(dense_bayer),
        .source_valid(i_capture_source_valid),.source_ready(o_capture_source_ready),.source_session(i_capture_source_session),.source_epoch(i_capture_source_epoch),.source_sequence(i_capture_source_sequence),
        .source_camera(i_capture_source_camera),.source_ok(i_capture_source_ok),.source_error(i_capture_source_error),.source_stale_count(o_capture_source_stale_count),
        .capture_frame(capture_frame),.begin_valid(begin_valid),.begin_ready(begin_ready),.begin_accepted(begin_accepted),.capture_slot(capture_slot),
        .finish_valid(finish_valid),.finish_ok(finish_ok),.finish_ready(finish_ready),.fault(eye_writer_fault[0]),
        .capture_drops(),.capture_errors(),.source_frames(),.selected_frames(),.skipped_frames(),
        .capture_enqueue_fire(o_capture0_enqueue_fire),.capture_consume_fire(o_capture0_consume_fire),
        .capture_idle(o_capture0_idle),.capture_frame_accept(o_capture0_frame_accept),.capture_writer_quiet(eye_wr_quiet[0]),
        .m_axi_awid(cap_awid[0+:4]),.m_axi_awaddr(cap_awaddr[0+:28]),.m_axi_awlen(cap_awlen[0+:8]),.m_axi_awsize(cap_awsize[0+:3]),.m_axi_awburst(cap_awburst[0+:2]),.m_axi_awvalid(cap_awvalid[0+:1]),.m_axi_awready(cap_awready[0+:1]),
        .m_axi_wdata(cap_wdata[0+:128]),.m_axi_wstrb(cap_wstrb[0+:16]),.m_axi_wlast(cap_wlast[0+:1]),.m_axi_wvalid(cap_wvalid[0+:1]),.m_axi_wready(cap_wready[0+:1]),
        .m_axi_bid(cap_bid[0+:4]),.m_axi_bresp(cap_bresp[0+:2]),.m_axi_bvalid(cap_bvalid[0+:1]),.m_axi_bready(cap_bready[0+:1]));
    end else begin:g_serial_capture
    full_raw_capture_frontend #(.WIDTH(WIDTH),.HEIGHT(HEIGHT)) u_capture(
        .i_stereo_mode_pixel(1'b0),.i_stereo_frame_divisor_pixel(8'd1),.i_uhd_pixel(1'b0),
        .pixel_clk(i_pixel_clk),.dfi_clk(i_dfi_clk),.cold_rst_n(i_identity_rst_n),
        .region_grant(i_ddr_ready),.stop(i_pair_stop||stop_fault||cfg_state==CFG_SELECT||cfg_state==CFG_OWNER||cfg_state==CFG_VERIFY||cfg_state==CFG_REPLY),
        .app_reset(application_stop_dfi),.capture_enable(i_capture_enable),
        .select_valid(cfg_state==CFG_SELECT&&select_ready),.select_sdr(!i_pair_hdr_enable),.select_session(i_pair_session),.select_epoch(i_pair_epoch),
        .select_ready(eye_sel_ready[0]),.select_applied(eye_applied[0]),.select_error(select_error),
        .route_sdr(route_sdr),.active_session(active_session),.active_epoch(active_epoch),
        .policy_quiet(all_policy_quiet),.policy_admit(policy_admit),.policy_stop(eye_stop[0]),.local_quiet(eye_quiet[0]),.region_quiet(),
        .raw_data(i_capture_data),.raw_valid(i_capture_valid),.raw_accept(i_capture_accept),.raw_sof(i_capture_sof),.raw_eol(i_capture_eol),.raw_abort(i_capture_abort),
        .raw_sequence(i_frame_sequence),.raw_metadata(i_capture_metadata),.time_valid(i_capture_time_valid),.bayer_valid(i_bayer_valid),.bayer_pattern(dense_bayer),
        .source_valid(i_capture_source_valid),.source_ready(o_capture_source_ready),.source_session(i_capture_source_session),.source_epoch(i_capture_source_epoch),.source_sequence(i_capture_source_sequence),
        .source_camera(i_capture_source_camera),.source_ok(i_capture_source_ok),.source_error(i_capture_source_error),.source_stale_count(o_capture_source_stale_count),
        .capture_frame(capture_frame),.begin_valid(begin_valid),.begin_ready(begin_ready),.begin_accepted(begin_accepted),.capture_slot(capture_slot),
        .finish_valid(finish_valid),.finish_ok(finish_ok),.finish_ready(finish_ready),.fault(eye_writer_fault[0]),
        .capture_drops(),.capture_errors(),.source_frames(),.selected_frames(),.skipped_frames(),
        .capture_enqueue_fire(o_capture0_enqueue_fire),.capture_consume_fire(o_capture0_consume_fire),
        .capture_idle(o_capture0_idle),.capture_frame_accept(o_capture0_frame_accept),.capture_writer_quiet(eye_wr_quiet[0]),
        .m_axi_awid(cap_awid[0+:4]),.m_axi_awaddr(cap_awaddr[0+:28]),.m_axi_awlen(cap_awlen[0+:8]),.m_axi_awsize(cap_awsize[0+:3]),.m_axi_awburst(cap_awburst[0+:2]),.m_axi_awvalid(cap_awvalid[0+:1]),.m_axi_awready(cap_awready[0+:1]),
        .m_axi_wdata(cap_wdata[0+:128]),.m_axi_wstrb(cap_wstrb[0+:16]),.m_axi_wlast(cap_wlast[0+:1]),.m_axi_wvalid(cap_wvalid[0+:1]),.m_axi_wready(cap_wready[0+:1]),
        .m_axi_bid(cap_bid[0+:4]),.m_axi_bresp(cap_bresp[0+:2]),.m_axi_bvalid(cap_bvalid[0+:1]),.m_axi_bready(cap_bready[0+:1]));
    assign capture_frame1=0;assign begin_valid1=0;assign finish_valid1=0;assign finish_ok1=0;
    assign o_capture1_enqueue_fire=0;assign o_capture1_consume_fire=0;assign o_capture1_idle=1;assign o_capture1_frame_accept=0;
    assign o_capture1_source_ready=0;assign o_capture1_source_stale_count=0;
    end endgenerate
    assign begin_ready=(!route_sdr||stereo_mode)&&authority_begin_ready&&
        (DUAL_CAPTURE_ENABLE==0||(begin_owner_valid&&!begin_owner1));
    assign begin_accepted=(!route_sdr||stereo_mode)&&authority_begin_accepted;
    assign capture_slot=authority_slot;
    assign finish_ready=stereo_mode?stereo_finish_ready[0]:(!route_sdr&&hdr_finish_ready);
    generate if(SECOND_HDR_CAMERA==0)begin:g_mono_hdr_owner
    hdr_pair_bank_owner #(.WIDTH(WIDTH),.HEIGHT(HEIGHT),.CAMERA_COUNT(1),.DOL2_ENABLE(DUAL_CAPTURE_ENABLE)) u_pair_owner(
        .i_clk(i_dfi_clk),.i_identity_rst_n(i_identity_rst_n),.i_stop(frontend_stop||route_sdr),.i_transport_fault(i_pair_fault||writer_fault),.i_now(i_pair_now),
        .i_config_valid(cfg_state==CFG_OWNER&&hdr_cfg_ready),.o_config_ready(eye_cfg_ready[0]),.o_config_error(eye_cfg_error[0]),
        .i_session(i_pair_session),.i_epoch(i_pair_epoch),.i_max_delta(i_pair_max_delta[31:0]),.i_max_wait(i_pair_max_wait),.i_max_age(i_pair_max_age),.i_ratio_log2(i_pair_ratio),.i_hdr_enable(hdr_enabled),
        .s_frame(hdr_begin_frame),.s_begin_valid(hdr_begin_request),.s_begin_ready(hdr_begin_ready),.o_begin_accepted(hdr_begin_accepted),.o_capture_slot(hdr_slot),.o_capture_generation(hdr_generation),.o_capture_lease(hdr_lease),
        .i_begin_member(DUAL_CAPTURE_ENABLE!=0&&begin_owner1),
        .i_finish_valid(finish_valid&&!route_sdr),.i_finish_ok(finish_ok),.o_finish_ready(hdr_finish_ready),
        .i_finish1_valid(finish_valid1&&!route_sdr),.i_finish1_ok(finish_ok1),.o_finish1_ready(hdr_finish1_ready),
        .o_pair_valid(eye_pair_valid[0]),.i_pair_ready(take_eye[0]),.o_pair_bank(eye_bank[0]),.o_pair_id(eye_id[0*64+:64]),
        .i_release_valid(release_eye[0]),.i_release_bank(i_pair_release_bank),.i_release_pair_id(i_pair_release_id),
        .i_read_quiet(i_pair_read_quiet),.i_write_quiet(eye_wr_quiet[0]&&i_pair_product_quiet),.i_ticket_released(i_pair_ticket_released),.o_release_ready(eye_rel_ready[0]),
        .i_directory_read_valid(ask_directory[0]),.i_directory_read_slot(i_pair_directory_slot),.o_directory_read_ready(eye_dir_ready[0]),
        .m_directory_data(eye_dir_data[0*32+:32]),.m_directory_word(eye_dir_word[0*4+:4]),.m_directory_valid(eye_dir_valid[0]),.m_directory_last(eye_dir_last[0]),.m_directory_ready(consume_directory[0]),
        .o_empty(eye_empty[0]),.o_capture_busy(),.o_exhausted(),.o_fault(eye_owner_fault[0]),.o_bank_states(),.o_reject_count(),.o_expire_count());
    end endgenerate
    generate if(SECOND_HDR_CAMERA!=0)begin:g_cam1_hdr
        wire [767:0] frames;
        wire [1:0] start_valid,start_ready,slot,done_valid,done_ready,done_ok;
        wire grant_ready,accept;
        reg offering,member,next_member;
        // Writers hold BEGIN and their own immutable member descriptor to REPLY.
        // An outstanding negative grant still drains on STOP.
        assign start_ready=(member ? 2'b10:2'b01)&{2{offering&&grant_ready}};
        always @(posedge i_dfi_clk or negedge i_identity_rst_n)begin
            if(!i_identity_rst_n)begin offering<=0;member<=0;next_member<=0;end
            else if(offering&&grant_ready)begin offering<=0;next_member<=!member;end
            else if(!offering&&|start_valid)begin
                offering<=1;member<=(&start_valid)?next_member:start_valid[1];
            end
        end
        dual_raw_capture_frontend #(.WIDTH(WIDTH),.HEIGHT(HEIGHT),.STEREO_ENABLE(0),.HDR_CAMERA_ID(1),.COMPACT_CAM1_HDR(1),
            .SEPARATE_DFI_DATA_RESET(SEPARATE_DFI_DATA_RESET),
            .STEREO_CAPTURE_DIVISOR(STEREO_CAPTURE_DIVISOR),.STEREO_RUNTIME_CADENCE(STEREO_RUNTIME_CADENCE)) u_capture(
            .i_dfi_data_rst_n(i_identity_data_rst_n),
            .i_stereo_mode_pixel(1'b0),.i_uhd_pixel(1'b0),
            .i_stereo_frame_divisor_pixel(i_stereo_frame_divisor_pixel),
            .source_frames1(),.selected_frames1(),.skipped_frames1(),
            .raw_data1(i_cam1_hdr_data[40+:40]),.raw_valid1(i_cam1_hdr_valid[1+:1]),.raw_accept1(1'b1),.raw_sof1(i_cam1_hdr_sof[1+:1]),.raw_eol1(i_cam1_hdr_eol[1+:1]),.raw_abort1(i_cam1_hdr_abort[1+:1]),
            .raw_sequence1(i_cam1_hdr_sequence[32+:32]),.raw_metadata1(i_cam1_hdr_metadata[197+:197]),
            .source_valid1(i_cam1_hdr_source_valid[1+:1]),.source_ready1(o_cam1_hdr_source_ready[1]),
            .source_session1(i_cam1_hdr_source_session[32+:32]),.source_epoch1(i_cam1_hdr_source_epoch[32+:32]),.source_sequence1(i_cam1_hdr_source_sequence[32+:32]),
            .source_camera1(1'b1),.source_ok1(i_cam1_hdr_source_ok[1+:1]),.source_error1(i_cam1_hdr_source_error[8+:8]),.source_stale_count1(),
            .capture_frame1(frames[1*384+:384]),.begin_valid1(start_valid[1]),.begin_ready1(start_ready[1]),.begin_accepted1(accept),.capture_slot1(slot),
            .finish_valid1(done_valid[1]),.finish_ok1(done_ok[1]),.finish_ready1(done_ready[1]),
            .capture_enqueue_fire1(),.capture_consume_fire1(),.capture_idle1(o_cam1_hdr_idle[1]),.capture_frame_accept1(o_cam1_hdr_admit[1]),
            .pixel_clk(i_pixel_clk),.dfi_clk(i_dfi_clk),.cold_rst_n(i_identity_rst_n),
            .region_grant(i_ddr_ready),.stop(i_pair_stop||stop_fault||cfg_state==CFG_SELECT||cfg_state==CFG_OWNER||cfg_state==CFG_VERIFY||cfg_state==CFG_REPLY),
            .app_reset(application_stop_dfi),.capture_enable(i_cam1_hdr_enable),
            .select_valid(cfg_state==CFG_SELECT&&select_ready),.select_sdr(!i_pair_hdr_enable),.select_session(i_pair_session),.select_epoch(i_pair_epoch),
            .select_ready(eye_sel_ready[1]),.select_applied(eye_applied[1]),.select_error(),
            .route_sdr(),.active_session(),.active_epoch(),
            .policy_quiet(all_policy_quiet),.policy_admit(policy_admit),.policy_stop(eye_stop[1]),.local_quiet(eye_quiet[1]),.region_quiet(),
            .raw_data(i_cam1_hdr_data[0+:40]),.raw_valid(i_cam1_hdr_valid[0+:1]),.raw_accept(1'b1),.raw_sof(i_cam1_hdr_sof[0+:1]),.raw_eol(i_cam1_hdr_eol[0+:1]),.raw_abort(i_cam1_hdr_abort[0+:1]),
            .raw_sequence(i_cam1_hdr_sequence[0+:32]),.raw_metadata(i_cam1_hdr_metadata[0+:197]),.time_valid(i_capture_time_valid),.bayer_valid(i_bayer_valid),.bayer_pattern(dense_bayer),
            .source_valid(i_cam1_hdr_source_valid[0+:1]),.source_ready(o_cam1_hdr_source_ready[0]),.source_session(i_cam1_hdr_source_session[0+:32]),.source_epoch(i_cam1_hdr_source_epoch[0+:32]),.source_sequence(i_cam1_hdr_source_sequence[0+:32]),
            .source_camera(1'b1),.source_ok(i_cam1_hdr_source_ok[0+:1]),.source_error(i_cam1_hdr_source_error[0+:8]),.source_stale_count(),
            .capture_frame(frames[0*384+:384]),.begin_valid(start_valid[0]),.begin_ready(start_ready[0]),.begin_accepted(accept),.capture_slot(slot),
            .finish_valid(done_valid[0]),.finish_ok(done_ok[0]),.finish_ready(done_ready[0]),.fault(eye_writer_fault[1]),
            .capture_drops(),.capture_errors(),.source_frames(),.selected_frames(),.skipped_frames(),
            .capture_enqueue_fire(),.capture_consume_fire(),
            .capture_idle(o_cam1_hdr_idle[0]),.capture_frame_accept(o_cam1_hdr_admit[0]),.capture_writer_quiet(eye_wr_quiet[1]),
            .m_axi_awid(cap_awid[4+:4]),.m_axi_awaddr(cap_awaddr[28+:28]),.m_axi_awlen(cap_awlen[8+:8]),.m_axi_awsize(cap_awsize[3+:3]),.m_axi_awburst(cap_awburst[2+:2]),.m_axi_awvalid(cap_awvalid[1+:1]),.m_axi_awready(cap_awready[1+:1]),
            .m_axi_wdata(cap_wdata[128+:128]),.m_axi_wstrb(cap_wstrb[16+:16]),.m_axi_wlast(cap_wlast[1+:1]),.m_axi_wvalid(cap_wvalid[1+:1]),.m_axi_wready(cap_wready[1+:1]),
            .m_axi_bid(cap_bid[4+:4]),.m_axi_bresp(cap_bresp[2+:2]),.m_axi_bvalid(cap_bvalid[1+:1]),.m_axi_bready(cap_bready[1+:1]));
        wire common_ready,common_error,common_fault;
        assign eye_cfg_ready={2{common_ready}};
        assign eye_cfg_error={2{common_error}};
        assign eye_owner_fault={2{common_fault}};
        hdr_eye_shared #(.WIDTH(WIDTH),.HEIGHT(HEIGHT)) shared_owner(
            .clk(i_dfi_clk),.rst_n(i_identity_rst_n),.stop(frontend_stop||route_sdr),
            .transport_fault(i_pair_fault||writer_fault),.now_ns(i_pair_now),
            .config_valid(cfg_state==CFG_OWNER&&hdr_cfg_ready),.config_ready(common_ready),.config_error(common_error),
            .cfg_session(i_pair_session),.cfg_epoch(i_pair_epoch),.cfg_delta(i_pair_max_delta[31:0]),
            .cfg_wait(i_pair_max_wait),.cfg_age(i_pair_max_age),.cfg_ratio(i_pair_ratio),.cfg_hdr(hdr_enabled),
            .frames({frames[member*384+:384],hdr_begin_frame}),.begin_valid({offering,hdr_begin_request}),
            .member({member,begin_owner1}),.begin_ready({grant_ready,hdr_begin_ready}),.accepted({accept,hdr_begin_accepted}),
            .capture_slots({slot,hdr_slot}),.camera0_generation(hdr_generation),.camera0_lease(hdr_lease),
            .finish_valid({done_valid,finish_valid1&&!route_sdr,finish_valid&&!route_sdr}),
            .finish_ok({done_ok,finish_ok1,finish_ok}),.finish_ready({done_ready,hdr_finish1_ready,hdr_finish_ready}),
            .pair_valid(eye_pair_valid),.pair_bank(eye_bank),.pair_ids(eye_id),.pair_take(take_eye),
            .release_valid(release_eye),.release_bank(i_pair_release_bank),.release_id(i_pair_release_id),
            .read_quiet(i_pair_read_quiet),.ticket_released(i_pair_ticket_released),
            // OWNED follows complete paired SOURCE/B terminals. Its bank
            // cannot be a new capture target; another bank may keep writing.
            // Keep malformed RELEASE handshakes in the owner's fault path.
            .write_quiet({2{i_pair_product_quiet}} &
                (eye_wr_quiet | {2{HDR_SLOT_LOCAL_RETIRE_ENABLE!=0&&configured&&
                  !stereo_mode&&!route_sdr&&hdr_enabled&&cfg_state==CFG_IDLE&&
                  !i_pair_config_valid&&!i_pair_stop&&!application_stop_dfi&&
                  !frontend_stop&&!stop_fault}})),.release_ready(eye_rel_ready),
            .ext_req(ask_directory),.ext_slot(i_pair_directory_slot),.ext_consume(consume_directory),
            .ext_ready(eye_dir_ready),.ext_valid(eye_dir_valid),.ext_last(eye_dir_last),
            .ext_data(eye_dir_data),.ext_word(eye_dir_word),.empty(eye_empty),.fault(common_fault),
            .diag_begin_reject(o_hdr_begin_reject),.diag_pair_expire(o_hdr_pair_expire),
            .diag_bad_finish(o_hdr_bad_finish),.diag_bank_states(o_hdr_bank_states));
        dol2_axi_write_arbiter #(.SEPARATE_DATA_RESET(SEPARATE_DFI_DATA_RESET)) u_eye_write_arbiter(
            .i_clk(i_dfi_clk),.i_axi_rst_n(i_identity_rst_n),.i_data_reset_n(i_identity_data_rst_n),
            .s_awid(cap_awid),.m_awid(m_axi_awid),.s_awaddr(cap_awaddr),.m_awaddr(m_axi_awaddr),.s_awlen(cap_awlen),.m_awlen(m_axi_awlen),
            .s_awsize(cap_awsize),.m_awsize(m_axi_awsize),.s_awburst(cap_awburst),.m_awburst(m_axi_awburst),.s_awvalid(cap_awvalid),.m_awvalid(m_axi_awvalid),.s_awready(cap_awready),.m_awready(m_axi_awready),
            .s_wdata(cap_wdata),.m_wdata(m_axi_wdata),.s_wstrb(cap_wstrb),.m_wstrb(m_axi_wstrb),.s_wlast(cap_wlast),.m_wlast(m_axi_wlast),
            .s_wvalid(cap_wvalid),.m_wvalid(m_axi_wvalid),.s_wready(cap_wready),.m_wready(m_axi_wready),
            .s_bid(cap_bid),.m_bid(m_axi_bid),.s_bresp(cap_bresp),.m_bresp(m_axi_bresp),.s_bvalid(cap_bvalid),.m_bvalid(m_axi_bvalid),.s_bready(cap_bready),.m_bready(m_axi_bready),
            .o_quiescent(outer_bus_quiet),.o_protocol_fault(outer_bus_fault));
    end else begin:g_no_cam1_hdr
        assign o_cam1_hdr_admit=0;
        assign o_hdr_begin_reject=0;assign o_hdr_pair_expire=0;
        assign o_hdr_bad_finish=0;assign o_hdr_bank_states=0;
        assign eye_sel_ready[1]=1;assign eye_applied[1]=1;assign eye_cfg_ready[1]=1;assign eye_cfg_error[1]=0;
        assign eye_empty[1]=1;assign eye_quiet[1]=1;assign eye_wr_quiet[1]=1;assign eye_stop[1]=0;
        assign eye_writer_fault[1]=0;assign eye_owner_fault[1]=0;
        assign eye_pair_valid[1]=0;assign eye_bank[1]=0;assign eye_id[127:64]=0;assign eye_rel_ready[1]=0;
        assign eye_dir_data[63:32]=0;assign eye_dir_word[7:4]=0;assign eye_dir_ready[1]=0;
        assign eye_dir_valid[1]=0;assign eye_dir_last[1]=0;assign o_cam1_hdr_idle=3;assign o_cam1_hdr_source_ready=0;
        assign outer_bus_quiet=1;assign outer_bus_fault=0;
        assign m_axi_awid=cap_awid[0+:4];
        assign m_axi_awaddr=cap_awaddr[0+:28];
        assign m_axi_awlen=cap_awlen[0+:8];
        assign m_axi_awsize=cap_awsize[0+:3];
        assign m_axi_awburst=cap_awburst[0+:2];
        assign m_axi_awvalid=cap_awvalid[0+:1];
        assign cap_awready[0+:1]=m_axi_awready;
        assign m_axi_wdata=cap_wdata[0+:128];
        assign m_axi_wstrb=cap_wstrb[0+:16];
        assign m_axi_wlast=cap_wlast[0+:1];
        assign m_axi_wvalid=cap_wvalid[0+:1];
        assign cap_wready[0+:1]=m_axi_wready;
        assign cap_bid[0+:4]=m_axi_bid;
        assign cap_bresp[0+:2]=m_axi_bresp;
        assign cap_bvalid[0+:1]=m_axi_bvalid;
        assign m_axi_bready=cap_bready[0+:1];
    end endgenerate
    // Compatibility outputs explicitly report absence; no SDR directory or read transaction exists.
    assign o_sdr_offer_valid=1'b0;assign o_sdr_frame_context=448'd0;
    assign o_sdr_read_request_ready=1'b0;assign o_sdr_read_data=128'd0;assign o_sdr_read_keep=16'd0;
    assign o_sdr_read_valid=1'b0;assign o_sdr_read_last=1'b0;assign o_sdr_read_owned=1'b0;
    assign o_sdr_read_done_valid=1'b0;assign o_sdr_read_done_ok=1'b0;assign o_sdr_release_ready=1'b0;
    // Mode may change only after the existing read/owner drain proof. A promised
    // HDR AR/R transaction is never disconnected by a withdrawn admission grant.
    wire [3:0] stereo_arid;
    wire [27:0] stereo_araddr;
    wire [7:0] stereo_arlen;
    wire [2:0] stereo_arsize;
    wire [1:0] stereo_arburst;
    wire stereo_arvalid,stereo_rready,stereo_fifo_valid;
    wire [146:0] stereo_fifo_data;
    wire replay_valid,replay_ready;
    wire stereo_native_done,stereo_native_error;
    wire [63:0] stereo_native_job;
    assign m_axi_arid=stereo_mode?stereo_arid:s_hdr_axi_arid;
    assign m_axi_araddr=stereo_mode?stereo_araddr:s_hdr_axi_araddr;
    assign m_axi_arlen=stereo_mode?stereo_arlen:s_hdr_axi_arlen;
    assign m_axi_arsize=stereo_mode?stereo_arsize:s_hdr_axi_arsize;
    assign m_axi_arburst=stereo_mode?stereo_arburst:s_hdr_axi_arburst;
    assign m_axi_arvalid=stereo_mode?stereo_arvalid:(s_hdr_axi_arvalid&&!route_sdr);
    assign m_axi_rready=stereo_mode?stereo_rready:(s_hdr_axi_rready&&!route_sdr);
    assign s_hdr_axi_arready=m_axi_arready&&!route_sdr&&!stereo_mode;
    assign s_hdr_axi_rid=m_axi_rid;assign s_hdr_axi_rdata=m_axi_rdata;assign s_hdr_axi_rresp=m_axi_rresp;
    assign s_hdr_axi_rlast=m_axi_rlast;assign s_hdr_axi_rvalid=m_axi_rvalid&&!route_sdr&&!stereo_mode;

    generate if(STEREO_ENABLE!=0)begin:g_stereo
        stereo_raw_store #(.WIDTH(WIDTH),.HEIGHT(HEIGHT),.EXTERNAL_DECODER(SHARED_DECODE_ENABLE),
            .RAW_EXPORT_ENABLE(RAW_EXPORT_ENABLE),.VERIFY_DECODE_ACTIVE(SHARED_DECODE_ENABLE),
            .UHD_WIDTH(UHD_WIDTH),.UHD_HEIGHT(UHD_HEIGHT)) u_store(
            .clk(i_dfi_clk),.rst_n(i_identity_rst_n),.i_enable(stereo_mode&&configured),
            .i_stop(frontend_stop||!stereo_mode),.i_session(active_session),.i_epoch(active_epoch),.i_uhd(i_uhd_dfi),
            .i_raw_export(i_raw_export),.i_raw_cancel(i_raw_cancel),
            .o_raw_record_valid(o_raw_record_valid),.i_raw_record_ready(i_raw_record_ready),
            .o_raw_record_length(o_raw_record_length),.o_raw_record_identity(o_raw_record_identity),
            .o_raw_data(o_raw_data),.o_raw_keep(o_raw_keep),.o_raw_valid(o_raw_valid),.o_raw_last(o_raw_last),.i_raw_ready(i_raw_ready),
            .o_raw_done_valid(o_raw_done_valid),.o_raw_done_ok(o_raw_done_ok),.o_raw_drained(o_raw_drained),
            .i_raw_retire_valid(i_raw_retire_valid),.o_raw_retire_ready(o_raw_retire_ready),.i_raw_retire_identity(i_raw_retire_identity),
            .s_frame(hdr_begin_frame),.s_begin_valid(begin_owner_valid&&stereo_mode),.i_begin_camera(begin_owner1),
            .s_begin_ready(stereo_begin_ready),.o_begin_accepted(stereo_begin_accepted),.o_capture_slot(stereo_slot),
            .i_finish_valid({finish_valid1,finish_valid}&{2{stereo_mode}}),
            .i_finish_ok({finish_ok1,finish_ok}),.o_finish_ready(stereo_finish_ready),
            .o_job_valid(o_stereo_job_valid),.i_job_ready(i_stereo_job_ready),.o_job_frame(o_stereo_job_frame),
            .o_job_lease(o_stereo_job_lease),.o_job_id(o_stereo_job_id),
            .o_job_bayer(o_stereo_job_bayer),.o_job_time_valid(o_stereo_job_time_valid),
            .i_retire_valid(i_stereo_retire_valid),.i_retire_job_id(i_stereo_retire_job_id),
            // Normal Stereo releases only its already completed OWNED slot.
            // STOP, configuration, application recovery and faults retain the
            // original global writer/arbiter drain. Product/ticket always gate.
            .i_release_quiet(i_pair_product_quiet&&i_pair_ticket_released&&
                ((STEREO_SLOT_LOCAL_RETIRE_ENABLE!=0&&stereo_mode&&configured&&
                  cfg_state==CFG_IDLE&&!i_pair_config_valid&&!i_pair_stop&&
                  !application_stop_dfi&&!frontend_stop&&!stop_fault) ||
                 o_capture_write_quiescent)),
            .o_retire_ready(o_stereo_retire_ready),.o_retire_done(o_stereo_retire_done),.o_retire_error(o_stereo_retire_error),
            .i_req_valid(i_private_req_valid&&stereo_mode),.o_req_ready(o_private_req_ready),
            .i_req_op(i_private_req_op),.i_req_camera(i_private_req_camera),.i_req_slot(i_private_req_slot),
            .i_req_generation(i_private_req_generation),.i_req_session(i_private_req_session),
            .i_req_lease(i_private_req_lease),.i_req_job_id(i_private_req_job_id),
            .o_rsp_valid(o_private_rsp_valid),.i_rsp_ready(i_private_rsp_ready),.o_rsp_code(o_private_rsp_code),
            .o_rsp_camera(o_private_rsp_camera),.o_rsp_slot(o_private_rsp_slot),
            .o_rsp_generation(o_private_rsp_generation),.o_rsp_session(o_private_rsp_session),
            .o_rsp_sequence(o_private_rsp_sequence),.o_rsp_epoch(o_private_rsp_epoch),
            .i_processing_done(i_stereo_processing_done),.i_processing_error(i_stereo_processing_error),
            .i_processing_job_id(i_stereo_processing_job_id),
            .o_native_done(stereo_native_done),.o_native_error(stereo_native_error),.o_native_job_id(stereo_native_job),
            .m_fifo_data(stereo_fifo_data),.m_fifo_valid(stereo_fifo_valid),.m_fifo_ready(replay_ready&&stereo_mode),
            .o_read_quiet(stereo_read_quiet),.o_empty(o_stereo_empty),.o_fault(stereo_fault),
            .o_decode_start_valid(o_decode_start_valid),.i_decode_start_ready(i_decode_start_ready),.o_decode_uhd(o_decode_uhd),
            .o_decode_release(o_decode_release),.o_decode_cancel(o_decode_cancel),.o_decode_run(o_decode_run),
            .o_decode_data(o_decode_data),.o_decode_keep(o_decode_keep),
            .o_decode_valid(o_decode_valid),.o_decode_last(o_decode_last),.i_decode_ready(i_decode_ready),
            .i_decode_raw(i_decode_raw),.i_decode_raw_valid(i_decode_raw_valid),.o_decode_raw_ready(o_decode_raw_ready),
            .i_decode_sof(i_decode_sof),.i_decode_eol(i_decode_eol),
            .i_decode_done(i_decode_done),.i_decode_aborted(i_decode_aborted),.i_decode_quiet(i_decode_quiet),
            .i_decode_active(i_decode_active),
            .m_axi_arid(stereo_arid),.m_axi_araddr(stereo_araddr),.m_axi_arlen(stereo_arlen),
            .m_axi_arsize(stereo_arsize),.m_axi_arburst(stereo_arburst),.m_axi_arvalid(stereo_arvalid),
            .m_axi_arready(m_axi_arready&&stereo_mode),.m_axi_rid(m_axi_rid),.m_axi_rdata(m_axi_rdata),
            .m_axi_rresp(m_axi_rresp),.m_axi_rlast(m_axi_rlast),.m_axi_rvalid(m_axi_rvalid&&stereo_mode),.m_axi_rready(stereo_rready));
    end else begin:g_no_stereo
        assign o_raw_record_valid=0;assign o_raw_record_length=0;assign o_raw_record_identity=0;
        assign o_raw_data=0;assign o_raw_keep=0;assign o_raw_valid=0;assign o_raw_last=0;
        assign o_raw_done_valid=0;assign o_raw_done_ok=0;assign o_raw_drained=1;assign o_raw_retire_ready=0;
        assign o_decode_start_valid=0;assign o_decode_uhd=0;assign o_decode_release=0;assign o_decode_cancel=0;assign o_decode_run=0;
        assign o_decode_data=0;assign o_decode_keep=0;assign o_decode_valid=0;assign o_decode_last=0;
        assign o_decode_raw_ready=0;
        assign stereo_begin_ready=0;assign stereo_begin_accepted=0;assign stereo_slot=0;assign stereo_finish_ready=0;
        assign o_stereo_job_valid=0;assign o_stereo_job_frame=0;assign o_stereo_job_lease=0;assign o_stereo_job_id=0;
        assign o_stereo_job_bayer=0;assign o_stereo_job_time_valid=0;
        assign o_stereo_retire_ready=0;assign o_stereo_retire_done=0;assign o_stereo_retire_error=0;
        assign o_stereo_empty=1;assign stereo_fault=0;assign stereo_read_quiet=1;
        assign stereo_arid=0;assign stereo_araddr=0;assign stereo_arlen=0;assign stereo_arsize=0;assign stereo_arburst=0;
        assign stereo_arvalid=0;assign stereo_rready=0;assign stereo_fifo_data=0;assign stereo_fifo_valid=0;
        assign stereo_native_done=0;assign stereo_native_error=0;assign stereo_native_job=0;
        assign o_private_req_ready=0;assign o_private_rsp_valid=0;assign o_private_rsp_code=4'd6;
        assign o_private_rsp_camera=0;assign o_private_rsp_slot=0;assign o_private_rsp_generation=0;
        assign o_private_rsp_session=0;assign o_private_rsp_sequence=0;assign o_private_rsp_epoch=0;
    end endgenerate
    assign o_reference_fault=raw_fault;
    assign o_private_ownership_quiescent=hdr_empty&&o_stereo_empty;

    // Legacy COMMIT is observation only and never supplies SDR authority.
    assign o_commit_valid=finish_valid&&finish_ready&&finish_ok&&!route_sdr;
    assign o_commit_frame={capture_frame[383:45],(DUAL_CAPTURE_ENABLE!=0?commit_generation0:hdr_generation),6'd0,(DUAL_CAPTURE_ENABLE!=0?commit_slot0:hdr_slot),capture_frame[4:0]};
    assign o_commit_lease=DUAL_CAPTURE_ENABLE!=0?commit_lease0:hdr_lease;
    assign o_ref_ready=0;
    assign o_cfs_compressed_count=0;assign o_cfs_no_benefit_count=0;
    assign o_cfs_overflow_count=0;assign o_cfs_busy_count=0;assign o_cfs_protocol_fault=0;
    assign o_private_rsp_descriptor=stereo_mode?o_stereo_job_frame:384'd0;assign o_private_rsp_metadata_valid=0;
    assign o_private_read_data=0;assign o_private_read_keep=0;assign o_private_read_valid=0;
    assign o_private_read_last=0;assign o_private_read_complete=0;assign o_private_read_error=0;
    assign o_private_read_protocol_fault=raw_fault;
    assign o_read_quiescent=stereo_mode?stereo_read_quiet:i_pair_read_quiet;
    assign o_public_read_quiescent=1;
    // Actual read routing is held by the capture mode authority above.

    // The sole DFI->PIX payload FIFO remains official and phase-owned. Its
    // entries are never consumed by a public or ordinary RAW10 replay path.
    wire [146:0] replay_sink;
    axis_frame_fifo_ip u_replay_fifo(
        .i_source_clk(i_dfi_clk),.i_source_rst_n(i_dfi_rst_n),
        .i_source_data(stereo_mode?stereo_fifo_data:s_shared_replay_data),
        .i_source_valid(stereo_mode?stereo_fifo_valid:(s_shared_replay_valid&&i_shared_replay_source_select)),
        .o_source_ready(replay_ready),.o_source_reset_done(o_shared_replay_source_reset_done),
        .i_sink_clk(i_pixel_clk),.i_sink_rst_n(i_pixel_rst_n),
        .o_sink_data(replay_sink),.o_sink_valid(replay_valid),
        .i_sink_ready(m_shared_replay_ready&&i_shared_replay_sink_select),
        .o_sink_reset_done(o_shared_replay_sink_reset_done));
    assign s_shared_replay_ready=replay_ready&&i_shared_replay_source_select&&!stereo_mode;
    assign m_shared_replay_data=replay_sink;
    assign m_shared_replay_valid=replay_valid&&i_shared_replay_sink_select;
    // Public RAW register access has a deterministic negative response. The
    // general profile provides this capability; no silent success is returned.
    reg bar_read_pending;
    always @(posedge i_user_clk or negedge i_user_rst_n)begin
        if(!i_user_rst_n)bar_read_pending<=0;else bar_read_pending<=i_bar_read_valid;
    end
    assign o_bar_write_response=2'b10;assign o_bar_read_response=2'b10;
    assign o_bar_read_response_valid=bar_read_pending;
    assign o_mask_command_data=0;
    assign o_mask_command_valid=0;
    assign o_mask_response_ready=0;
    assign o_mask_block_ready=0;
    assign o_mask_cache_retire=0;
    assign o_private_native_done=stereo_mode&&stereo_native_done;
    assign o_private_native_error=stereo_mode&&stereo_native_error;
    assign o_private_native_job_id=stereo_mode?stereo_native_job:64'd0;
    assign o_private_native_member_index=0;
    assign o_replay_context_valid=0;
    assign o_replay_descriptor=0;
    assign o_replay_job_id=0;
    assign o_replay_pair_id=0;
    assign o_replay_member_index=0;
    assign o_replay_private=0;
    assign o_replay_protocol_fault=0;
    assign o_host_replay_context_valid=0;
    assign o_host_replay_descriptor=0;
    assign o_host_replay_metadata_valid=0;
    assign o_replay_native_done=0;
    assign o_replay_native_error=0;
    assign o_replay_active=0;
    assign o_replay_data=0;
    assign o_replay_valid=0;
    assign o_replay_sof=0;
    assign o_replay_eol=0;
    assign o_replay_abort=0;
    assign o_bar_read_data=0;
endmodule
