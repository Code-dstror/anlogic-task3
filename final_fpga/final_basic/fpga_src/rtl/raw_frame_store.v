`timescale 1ns / 1ps

// Two logical RAW10 camera rings. Payload storage is exclusively external DDR.
module raw_frame_store #(
    parameter integer SLOTS_PER_CAMERA = 4,
    parameter [31:0] SLOT_BYTES = 32'h01000000,
    parameter [27:0] RAW_BASE = 28'h2000000,
    parameter [3:0] AXI_ID = 4'd1,
    parameter integer CONTEXT_ENABLE = 0,
    parameter integer DUAL_CAPTURE_ENABLE = 0,
    parameter integer PAIR_METADATA_ENABLE = 0,
    parameter integer PHYSICAL_MONO_CURRENT_ENABLE = 0,
    parameter integer CFS_ENABLE = 0,
    parameter integer OFFICIAL_CRC_QUALIFIED = 0,
    parameter integer CAMERA_COUNT = 2
) (
    input wire i_clk, i_rst_n,
    // DFI-domain runtime control, locked at actual START.
    input wire i_cfs_enable,
    input wire i_physical_mono_current_enable,
    output wire [31:0] o_cfs_compressed_count,o_cfs_no_benefit_count,o_cfs_overflow_count,o_cfs_busy_count,
    output wire o_cfs_protocol_fault,
    input wire [127:0] i_tdata,
    input wire [15:0] i_tkeep,
    input wire i_tvalid, i_tlast,
    input wire [1:0] i_tuser,
    output reg o_tready,
    // Dual mode requires real conservative FIFO counts, including FWFT head.
    input wire [9:0] i_tavailable,
    input wire [127:0] i_t1data,
    input wire [15:0] i_t1keep,
    input wire i_t1valid, i_t1last,
    input wire [1:0] i_t1user,
    output reg o_t1ready,
    input wire [9:0] i_t1available,
    output reg o_commit_valid,
    output reg [383:0] o_commit_frame,
    output reg [63:0] o_commit_lease,
    input wire i_commit_ready,
    input wire i_ref_valid, output wire o_ref_ready,
    input wire [1:0] i_ref_op, i_ref_mask,
    input wire [383:0] i_ref_frame0, i_ref_frame1,
    input wire [63:0] i_ref_lease0, i_ref_lease1, i_ref_job_id,
    output reg o_reference_fault,
    input wire i_req_valid,
    output wire o_req_ready,
    input wire [2:0] i_req_op,
    input wire i_req_camera,
    input wire [1:0] i_req_slot,
    input wire [31:0] i_req_generation, i_req_offset, i_req_length, i_req_session,
    input wire i_req_private,
    input wire [63:0] i_req_lease, i_req_job_id,
    output reg o_rsp_valid,
    input wire i_rsp_ready,
    output reg [3:0] o_rsp_code,
    output reg o_rsp_camera,
    output reg [1:0] o_rsp_slot,
    output reg [31:0] o_rsp_generation, o_rsp_sequence, o_rsp_epoch, o_rsp_session,
    output reg [7:0] o_rsp_format,
    output reg [15:0] o_rsp_width, o_rsp_height,
    output reg [31:0] o_rsp_sample_count, o_rsp_payload_bytes,
    output reg o_rsp_pinned,
    output reg [2:0] o_rsp_state,
    output reg [383:0] o_rsp_descriptor,
    output reg o_rsp_metadata_valid,
    output wire [127:0] o_read_data,
    output wire [15:0] o_read_keep,
    output wire o_read_last, o_read_valid,
    input wire i_read_ready,
    output reg o_read_error,
    output wire o_read_complete,
    output reg [31:0] o_capture_count, o_read_count, o_drop_count, o_error_count,
    output wire o_capture_write_quiescent,
    output wire o_private_ownership_quiescent,
    output wire [3:0] m_axi_awid,
    output wire [27:0] m_axi_awaddr,
    output wire [7:0] m_axi_awlen,
    output wire [2:0] m_axi_awsize,
    output wire [1:0] m_axi_awburst,
    output wire m_axi_awvalid,
    input wire m_axi_awready,
    output wire [127:0] m_axi_wdata,
    output wire [15:0] m_axi_wstrb,
    output wire m_axi_wlast, m_axi_wvalid,
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
    input wire m_axi_rlast, m_axi_rvalid,
    output wire m_axi_rready
);
    wire [3:0] raw_axi_awid;
    wire [27:0] raw_axi_awaddr;
    wire [7:0] raw_axi_awlen;
    wire [2:0] raw_axi_awsize;
    wire [1:0] raw_axi_awburst;
    wire raw_axi_awvalid;
    wire raw_axi_awready;
    wire [127:0] raw_axi_wdata;
    wire [15:0] raw_axi_wstrb;
    wire raw_axi_wlast;
    wire raw_axi_wready;
    wire [3:0] raw_axi_bid;
    wire [1:0] raw_axi_bresp;
    wire raw_axi_bvalid;
    wire raw_axi_bready;
    wire [3:0] raw_axi_arid;
    wire [27:0] raw_axi_araddr;
    wire [7:0] raw_axi_arlen;
    wire [2:0] raw_axi_arsize;
    wire [1:0] raw_axi_arburst;
    wire raw_axi_arvalid;
    wire raw_axi_arready;
    wire [3:0] raw_axi_rid;
    wire [127:0] raw_axi_rdata;
    wire [1:0] raw_axi_rresp;
    wire raw_axi_rlast;
    wire raw_axi_rready;
    wire [3:0] cfs_axi_awid;
    wire [27:0] cfs_axi_awaddr;
    wire [7:0] cfs_axi_awlen;
    wire [2:0] cfs_axi_awsize;
    wire [1:0] cfs_axi_awburst;
    wire cfs_axi_awvalid;
    wire cfs_axi_awready;
    wire [127:0] cfs_axi_wdata;
    wire [15:0] cfs_axi_wstrb;
    wire cfs_axi_wlast;
    wire cfs_axi_wready;
    wire [3:0] cfs_axi_bid;
    wire [1:0] cfs_axi_bresp;
    wire cfs_axi_bvalid;
    wire cfs_axi_bready;
    wire [3:0] cfs_axi_arid;
    wire [27:0] cfs_axi_araddr;
    wire [7:0] cfs_axi_arlen;
    wire [2:0] cfs_axi_arsize;
    wire [1:0] cfs_axi_arburst;
    wire cfs_axi_arvalid;
    wire cfs_axi_arready;
    wire [3:0] cfs_axi_rid;
    wire [127:0] cfs_axi_rdata;
    wire [1:0] cfs_axi_rresp;
    wire cfs_axi_rlast;
    wire cfs_axi_rready;

    // RAW and CFS share one physical AXI writer. AW presentation acquires the
    // grant; accepted actual B releases it. No logical ACK releases a burst.
    reg [1:0] write_mux;
    wire [1:0] write_aw_select = write_mux!=0 ? write_mux :
        (raw_axi_awvalid ? 2'd1 : (cfs_axi_awvalid ? 2'd2 : 2'd0));
    wire raw_axi_wvalid,cfs_axi_wvalid,raw_axi_rvalid,cfs_axi_rvalid;
    wire cfs_write_idle,cfs_read_request_ready,cfs_read_valid,cfs_read_done,cfs_read_error;
    wire [127:0] cfs_read_data;
    wire [15:0] cfs_read_keep;
    wire cfs_read_last;
    wire [1:0] cfs_begin_valid,cfs_begin_ready,cfs_valid,cfs_ready,cfs_end_valid,cfs_end_ready;
    wire [1:0] cfs_result_valid,cfs_result_ok,cfs_result_ready,cfs_finish,cfs_finish_ok;
    wire cfs_read_request_valid,cfs_read_retire;
    function [4:0] count_keep;
        input [15:0] keep;integer k;
        begin count_keep=0;for(k=0;k<16;k=k+1)count_keep=count_keep+keep[k];end
    endfunction
    localparam integer SLOT_INDEX_WIDTH=CAMERA_COUNT==1 ? 2 : 3;
    localparam integer ACTIVE_SLOT_COUNT=CAMERA_COUNT*4;
    generate if((CAMERA_COUNT!=1 && CAMERA_COUNT!=2) ||
        (DUAL_CAPTURE_ENABLE!=0 && CAMERA_COUNT!=2))begin:invalid_camera_count
        RAW_STORE_CAMERA_COUNT_MUST_MATCH_CAPTURE_PORTS invalid_configuration();
    end endgenerate
    localparam [2:0] EMPTY=0, COMPLETE=1, WRITING=2, ABORTED=3;
    localparam [3:0] W_IDLE=0, W_AW=1, W_DATA=2, W_B=3, W_END=4, W_DRAIN=5, W_CONTEXT=6,
        W_CFS_BEGIN=7,W_CFS_DATA=8,W_CFS_END=9, W_CONTEXT_WRITE=10;
    localparam [2:0] R_IDLE=0, R_AR=1, R_DATA=2, R_HOLD=3, R_PREPARE=4, R_BURST=5,R_CFS=6;
    localparam [2:0] Q_IDLE=0, Q_SCAN=1, Q_SNAPSHOT=2, Q_RANGE=3, Q_CHECK=4, Q_VERIFY=5, Q_COMMIT=6, Q_COLD=7;
    localparam [3:0] OK=0, NO_FRAME=1, STALE=2, BUSY=3, RANGE=4, AXI_ERROR=5, INVALID=6;
    // Asynchronously reset descriptor/control registers; no payload RAM/FIFO.
    reg [2:0] slot_state [0:7];
    reg slot_pin [0:7];
    reg [31:0] slot_gen [0:7], slot_seq [0:7], slot_epoch [0:7];
    reg [31:0] slot_session [0:7];
    reg [7:0] slot_format [0:7];
    reg [15:0] slot_width [0:7], slot_height [0:7];
    reg [31:0] slot_samples [0:7], slot_bytes [0:7], slot_stamp [0:7];
    reg [63:0] slot_lease [0:7], slot_job_id [0:7];
    reg [1:0] slot_cold_valid [0:7];
    reg slot_meta_valid [0:7], slot_qualified [0:7], slot_source [0:7];
    reg [7:0] slot_physical_current;
    reg [1:0] slot_role [0:7], context_index [0:1];
    reg [7:0] slot_candidate, slot_job, slot_pending;
    reg [63:0] lease_counter;
    localparam [1:0] C_IDLE=0,C_SCAN=1,C_PUBLISH=2;
    reg [1:0] commit_state;
    reg [7:0] commit_snapshot;
    reg [SLOT_INDEX_WIDTH-1:0] commit_scan, commit_best, commit_slot;
    reg commit_best_valid;
    reg [63:0] commit_best_lease;
    localparam [1:0] F_IDLE=0,F_CHECK=1,F_APPLY=2;
    reg [1:0] reference_state, reference_op, reference_mask;
    reg [383:0] reference_frame0,reference_frame1;
    reg [63:0] reference_lease0,reference_lease1,reference_job_id;
    wire [SLOT_INDEX_WIDTH-1:0] reference_slot0={reference_frame0[4],reference_frame0[6:5]};
    wire [SLOT_INDEX_WIDTH-1:0] reference_slot1={reference_frame1[4],reference_frame1[6:5]};
    function [383:0] pair_descriptor;
        input [2:0] index;
        begin
            pair_descriptor=0;
            pair_descriptor[0]=slot_qualified[index]; pair_descriptor[2:1]=slot_role[index];
            pair_descriptor[3]=slot_source[index]; pair_descriptor[4]=index[2];
            pair_descriptor[12:5]={6'd0,index[1:0]}; pair_descriptor[44:13]=slot_gen[index];
            pair_descriptor[76:45]=slot_session[index]; pair_descriptor[108:77]=slot_seq[index];
            pair_descriptor[140:109]=slot_epoch[index];
            pair_descriptor[220:205]=slot_width[index]; pair_descriptor[236:221]=slot_height[index];
            pair_descriptor[238:237]=slot_format[index][1:0];
        end
    endfunction
    function reference_matches;
        input [383:0] frame;
        input [63:0] lease;
        input [1:0] operation;
        input [63:0] job_id;
        input [2:0] state;
        input [31:0] session,generation;
        input [63:0] stored_lease,stored_job;
        input candidate,job;
        begin
            reference_matches=frame[4]<CAMERA_COUNT && frame[12:5]<SLOTS_PER_CAMERA && lease!=0 &&
                state==COMPLETE && session==frame[76:45] &&
                generation==frame[44:13] && stored_lease==lease &&
                (operation==2 ? (job && job_id!=0 && stored_job==job_id) : candidate);
        end
    endfunction
    wire reference_legal=(reference_op<=2 && (reference_mask==1 || reference_mask==3) &&
        (reference_op==0 ? reference_job_id==0 : reference_job_id!=0) &&
        reference_matches(reference_frame0,reference_lease0,reference_op,reference_job_id,
            slot_state[reference_slot0],slot_session[reference_slot0],slot_gen[reference_slot0],
            slot_lease[reference_slot0],slot_job_id[reference_slot0],slot_candidate[reference_slot0],slot_job[reference_slot0]) &&
        (reference_mask!=3 || (reference_slot0!=reference_slot1 &&
            reference_matches(reference_frame1,reference_lease1,reference_op,reference_job_id,
                slot_state[reference_slot1],slot_session[reference_slot1],slot_gen[reference_slot1],
                slot_lease[reference_slot1],slot_job_id[reference_slot1],slot_candidate[reference_slot1],slot_job[reference_slot1]))));
    wire reference_waiting_pending=slot_pending[reference_slot0] ||
        (reference_mask==3 && slot_pending[reference_slot1]);
    wire reference_read_barrier=PAIR_METADATA_ENABLE!=0 && !o_reference_fault &&
        ((reference_state!=F_IDLE && reference_op==2) || (i_ref_valid && i_ref_op==2));
    reg [1:0] next_slot [0:1];
    reg [3:0] capture_state [0:1];
    reg [SLOT_INDEX_WIDTH-1:0] capture_slot [0:1];
    reg slot_cfs [0:7];
    reg [383:0] capture_cfs_frame [0:1];
    reg [1:0] cfs_begin_staged;
    reg [27:0] capture_address [0:1];
    reg [31:0] capture_left [0:1], capture_received [0:1];
    reg [31:0] capture_expected [0:1], capture_samples [0:1];
    reg capture_bad [0:1], capture_fill [0:1], capture_end_seen [0:1];
    // One shared burst writer, locked from AW presentation through accepted B.
    localparam [1:0] B_IDLE=0, B_AW=1, B_DATA=2, B_RESP=3;
    reg [1:0] burst_state;
    reg write_owner, write_turn;
    reg [27:0] write_address;
    reg [4:0] write_beats, write_index;
    wire [3:0] write_state = capture_state[0]; // legacy bench/debug state name
    // No accepted capture or promised AW/W/B remains, including error drain.
    // FIFO emptiness and old committed/pinned descriptors are separate facts.
    assign o_capture_write_quiescent = i_rst_n && burst_state==B_IDLE &&
        capture_state[0]==W_IDLE && cfs_write_idle && write_mux==0 &&
        (DUAL_CAPTURE_ENABLE==0 || capture_state[1]==W_IDLE);
    // RAW END precedes publication of its scanned commit descriptor. Pending
    // candidates still own the old epoch, even while commit_valid is low.
    // Host PINs are independent and are never released by this observation.
    assign o_private_ownership_quiescent = i_rst_n && !o_reference_fault &&
        !o_commit_valid && !(|slot_pending) && !(|slot_candidate) &&
        !(|slot_job) && reference_state==F_IDLE && !i_ref_valid;
    reg [2:0] read_state;
    reg [SLOT_INDEX_WIDTH-1:0] read_slot;
    wire [2:0] read_slot_full=read_slot;
    reg [27:0] read_address;
    reg [31:0] read_left;
    reg [4:0] read_beats, read_index;
    reg read_bad;
    reg read_cfs,read_cfs_started;
    reg [383:0] read_cfs_frame;
    reg [31:0] read_cfs_offset;
    reg read_private;
    reg [63:0] read_lease, read_job_id;
    integer allocate_index, allocate_scan, allocate_candidate, allocate_lane;
    integer reset_index, candidate_index, capture_lane, decode_lane;
    integer allocate_slot [0:1];
    reg [2:0] request_state;
    reg [SLOT_INDEX_WIDTH-1:0] request_slot;
    wire selected_request_camera=CAMERA_COUNT==1 ? 1'b0 : i_req_camera;
    reg [2:0] req_op;
    reg req_camera;
    reg [1:0] req_slot, scan_slot;
    reg [31:0] req_generation, req_session, req_offset, req_length;
    reg req_private;
    reg [63:0] req_lease, req_job_id;
    reg [3:0] candidate_valid;
    reg [31:0] candidate_stamp [0:3];
    reg best_valid;
    reg [31:0] best_stamp;
    reg [27:0] request_base;
    reg [4:0] read_candidate_beats, read_boundary_beats;
    reg [1:0] allocation_valid;
    reg [3:0] request_code;
    reg [3:0] pending_code;
    reg [31:0] requested_bytes;
    reg [32:0] requested_end;
    reg [27:0] requested_address;
    wire [32:0] arena_limit = {5'd0,RAW_BASE} + SLOT_BYTES * (2*SLOTS_PER_CAMERA);
    wire config_legal = SLOTS_PER_CAMERA >= 1 && SLOTS_PER_CAMERA <= 4 &&
                        SLOT_BYTES >= 256 && SLOT_BYTES <= 32'h10000000 && SLOT_BYTES[7:0] == 0 &&
                        RAW_BASE >= 28'h1000000 && RAW_BASE[7:0] == 0 &&
                        arena_limit <= 33'h010000000 && (PAIR_METADATA_ENABLE==0 || CONTEXT_ENABLE!=0);
    wire [127:0] token_data [0:1];
    wire [15:0] token_keep [0:1];
    wire [1:0] token_user [0:1];
    wire [1:0] token_valid, token_last, token_camera;
    wire [9:0] token_available [0:1];
    reg [1:0] token_ready;
    wire [1:0] source_fire = token_valid & token_ready;
    wire [1:0] start_fire;
    wire [31:0] start_samples [0:1], start_geometry [0:1], start_bytes [0:1];
    wire [34:0] start_bits [0:1];
    wire [15:0] capture_keep [0:1];
    wire [4:0] candidate_beats [0:1];
    wire [4:0] remaining_beats [0:1], boundary_beats [0:1], available_beats [0:1], span_beats [0:1];
    wire [1:0] context_legal, data_legal, end_legal, raw_end_legal, start_legal;
    wire [1:0] pair_end_requested;
    wire [1:0] lease_demand={1'b0,pair_end_requested[0]}+{1'b0,pair_end_requested[1]};
    wire lease_space_ok=lease_counter<=64'hffffffffffffffff-{62'd0,lease_demand};
    wire [1:0] burst_eligible;
    reg [1:0] capture_event, drop_event, context_error_event;
    wire burst_select = (&burst_eligible) ? write_turn : burst_eligible[1];
    assign token_data[0]=i_tdata; assign token_data[1]=i_t1data;
    assign token_keep[0]=i_tkeep; assign token_keep[1]=i_t1keep;
    assign token_user[0]=i_tuser; assign token_user[1]=i_t1user;
    assign token_valid={DUAL_CAPTURE_ENABLE != 0 && i_t1valid,i_tvalid};
    assign token_last={i_t1last,i_tlast};
    assign token_camera={1'b1,DUAL_CAPTURE_ENABLE != 0 ? 1'b0 : i_tdata[96]};
    assign token_available[0]=i_tavailable; assign token_available[1]=i_t1available;
    genvar capture_port;
    generate for(capture_port=0;capture_port<2;capture_port=capture_port+1) begin : g_capture_contract
        assign start_samples[capture_port]={1'b0,token_data[capture_port][127:97]};
        assign start_geometry[capture_port]=token_data[capture_port][47:32]*token_data[capture_port][63:48];
        assign start_bits[capture_port]={4'd0,start_samples[capture_port][30:0]}*4'd10;
        assign start_bytes[capture_port]=(start_bits[capture_port]+35'd7)>>3;
        assign remaining_beats[capture_port]=capture_left[capture_port]>=256 ? 5'd16 :
            {1'b0,capture_left[capture_port][7:4]}+(|capture_left[capture_port][3:0]);
        assign boundary_beats[capture_port]=capture_address[capture_port][11:8]==4'hf ?
            5'd16-{1'b0,capture_address[capture_port][7:4]} : 5'd16;
        assign available_beats[capture_port]=token_available[capture_port]>=16 ? 5'd16 : token_available[capture_port][4:0];
        assign span_beats[capture_port]=remaining_beats[capture_port]<boundary_beats[capture_port] ?
            remaining_beats[capture_port] : boundary_beats[capture_port];
        // Short reserved bursts also drain a partial frame followed by ABORT;
        // demanding sixteen tokens would otherwise hide that ABORT forever.
        assign candidate_beats[capture_port]=DUAL_CAPTURE_ENABLE!=0 && available_beats[capture_port]<span_beats[capture_port] ?
            available_beats[capture_port] : span_beats[capture_port];
        assign capture_keep[capture_port]=capture_left[capture_port]>=16 ? 16'hffff :
            (16'hffff>>(16-capture_left[capture_port]));
        assign context_legal[capture_port]=token_user[capture_port]==1 && token_last[capture_port] &&
            token_keep[capture_port]==16'hffff &&
            ((PAIR_METADATA_ENABLE==0 || context_index[capture_port]==0) ?
                (token_data[capture_port][39:32]==1 &&
                 token_data[capture_port][71:40]==slot_seq[capture_slot[capture_port]] &&
                 token_data[capture_port][103:72]==slot_epoch[capture_slot[capture_port]] &&
                 (PAIR_METADATA_ENABLE!=0 ? (token_data[capture_port][107:104]==1 &&
                    token_data[capture_port][127:113]==0 && token_data[capture_port][110:109]!=3) :
                    token_data[capture_port][127:104]==0)) :
                (context_index[capture_port]==1 ||
                 (token_data[capture_port][95:64]==slot_seq[capture_slot[capture_port]] &&
                  token_data[capture_port][127:96]==slot_epoch[capture_slot[capture_port]])));
        assign data_legal[capture_port]=token_keep[capture_port]==capture_keep[capture_port] &&
            token_last[capture_port]==(capture_left[capture_port]<=16);
        assign raw_end_legal[capture_port]=token_user[capture_port]==2 && token_keep[capture_port]==16'hffff &&
            !token_last[capture_port] && token_data[capture_port][64] &&
            token_data[capture_port][31:0]==capture_expected[capture_port] &&
            token_data[capture_port][63:32]==capture_samples[capture_port] &&
            capture_received[capture_port]==capture_expected[capture_port] && !capture_bad[capture_port];
        assign pair_end_requested[capture_port]=PAIR_METADATA_ENABLE!=0 &&
            ((capture_state[capture_port]==W_END && source_fire[capture_port] && raw_end_legal[capture_port]) ||
             cfs_finish_ok[capture_port]) &&
            (slot_meta_valid[capture_slot[capture_port]] ||
             (slot_physical_current[capture_slot[capture_port]] && capture_port==0 &&
              slot_source[capture_slot[capture_port]] && slot_role[capture_slot[capture_port]]==0));
        assign end_legal[capture_port]=raw_end_legal[capture_port] &&
            (!pair_end_requested[capture_port] || (lease_space_ok && !o_reference_fault));
        assign start_fire[capture_port]=source_fire[capture_port] && token_user[capture_port]==1 &&
            !token_last[capture_port] && capture_state[capture_port]==W_IDLE;
        assign start_legal[capture_port]=config_legal && token_camera[capture_port]<CAMERA_COUNT && allocation_valid[capture_port] &&
            token_keep[capture_port]==16'hffff && start_samples[capture_port]!=0 &&
            start_samples[capture_port]==start_geometry[capture_port] && start_bytes[capture_port]!=0 &&
            start_bytes[capture_port]<=SLOT_BYTES &&
            (!(CFS_ENABLE!=0 && i_cfs_enable) ||
                (((((({1'b0,start_samples[capture_port]}+2047)>>11)*32+63)&64'hffffffffffffffc0)+
                (({1'b0,start_samples[capture_port]}+2047)>>11)*2560)<=SLOT_BYTES)) &&
            (DUAL_CAPTURE_ENABLE==0 || token_data[capture_port][96]==token_camera[capture_port]);
        assign burst_eligible[capture_port]=capture_state[capture_port]==W_AW &&
            (capture_port==0 || DUAL_CAPTURE_ENABLE!=0) &&
            (DUAL_CAPTURE_ENABLE==0 || (token_valid[capture_port] && token_user[capture_port]==0 &&
                candidate_beats[capture_port]!=0 && token_available[capture_port]>=candidate_beats[capture_port]));
    end endgenerate
    // Immutable CONTEXT1/2 directory: six 32-bit words at an eight-word
    // stride. One official SDP ERAM supplies one write and one read port.
    // RAM is never reset; valid groups mask unwritten or reused words to zero.
    reg cold_write_busy, cold_write_owner, cold_write_group, cold_write_turn;
    reg [2:0] cold_write_slot, cold_write_word;
    reg [127:0] cold_write_holding;
    wire [1:0] cold_write_want;
    wire cold_write_select=(cold_write_want==3) ? cold_write_turn : cold_write_want[1];
    wire cold_write_grant=PAIR_METADATA_ENABLE!=0 && !cold_write_busy && |cold_write_want;
    wire cold_write_last=cold_write_busy && cold_write_word==(cold_write_group ? 1 : 3);
    wire [5:0] cold_write_address={cold_write_slot,3'b000}+
        (cold_write_group ? 6'd4 : 6'd0)+cold_write_word;
    reg cold_read_active, cold_read_pending;
    reg [1:0] cold_read_owner, cold_read_turn, cold_read_groups;
    reg [2:0] cold_read_slot, cold_read_issue, cold_read_word;
    reg [31:0] cold_read_generation;
    wire [3:0] cold_read_want={request_state==Q_SNAPSHOT && req_camera<CAMERA_COUNT,
        capture_state[1]==W_CFS_BEGIN && !cfs_begin_staged[1],
        capture_state[0]==W_CFS_BEGIN && !cfs_begin_staged[0],
        commit_state==C_PUBLISH && commit_best_valid && !o_commit_valid};
    reg cold_read_grant;
    reg [1:0] cold_read_select;
    reg [2:0] cold_read_selected_slot;
    integer cold_scan, cold_candidate;
    reg [2:0] cold_candidate_slot;
    wire cold_read_enable=cold_read_active && cold_read_issue<6;
    wire [5:0] cold_read_address={cold_read_slot,3'b000}+cold_read_issue;
    wire [31:0] cold_read_data;
    wire [31:0] cold_read_masked=cold_read_groups[cold_read_word>=4] ? cold_read_data : 32'd0;
    wire cold_read_last=cold_read_active && cold_read_pending && cold_read_word==5;
    wire cold_read_same=slot_gen[cold_read_slot]==cold_read_generation &&
        slot_cold_valid[cold_read_slot]==cold_read_groups;
    assign cold_write_want[0]=token_valid[0] && capture_state[0]==W_CONTEXT &&
        context_index[0]!=0 && context_legal[0] && (!cold_read_active || cold_read_slot!=capture_slot[0]);
    assign cold_write_want[1]=DUAL_CAPTURE_ENABLE!=0 && token_valid[1] && capture_state[1]==W_CONTEXT &&
        context_index[1]!=0 && context_legal[1] && (!cold_read_active || cold_read_slot!=capture_slot[1]);
    generate if(PAIR_METADATA_ENABLE!=0)begin:g_cold_directory
        td_sdp_ram40 #(.WIDTH(32),.DEPTH(64),.ADDR_WIDTH(6)) u_ram(
            .clk(i_clk),.wr_en(i_rst_n && cold_write_busy),.wr_addr(cold_write_address),
            .wr_data(cold_write_holding[31:0]),.rd_en(i_rst_n && cold_read_enable),
            .rd_addr(cold_read_address),.rd_data(cold_read_data));
    end else begin:g_no_cold_directory
        assign cold_read_data=0;
    end endgenerate
    // Lock acquisition excludes both the active writer and a cold token
    // accepted on this edge, as well as same-edge slot reallocation. There
    // is no read/write collision, even with both capture heads requesting.
    always @(*)begin
        cold_read_grant=0;cold_read_select=0;cold_read_selected_slot=0;
        cold_candidate=0;cold_candidate_slot=0;
        for(cold_scan=0;cold_scan<4;cold_scan=cold_scan+1)begin
            cold_candidate=(cold_read_turn+cold_scan)%4;
            case(cold_candidate)
                0:cold_candidate_slot=commit_best;
                1:cold_candidate_slot=capture_slot[0];
                2:cold_candidate_slot=capture_slot[1];
                default:cold_candidate_slot=request_slot;
            endcase
            if(PAIR_METADATA_ENABLE!=0 && !cold_read_active && !cold_read_grant &&
                cold_read_want[cold_candidate] &&
                (!cold_write_busy || cold_write_slot!=cold_candidate_slot) &&
                (!cold_write_grant || capture_slot[cold_write_select]!=cold_candidate_slot) &&
                !(start_fire[0] && allocate_slot[0]==cold_candidate_slot) &&
                !(start_fire[1] && allocate_slot[1]==cold_candidate_slot))begin
                cold_read_grant=1;cold_read_select=cold_candidate;
                cold_read_selected_slot=cold_candidate_slot;
            end
        end
    end
    wire [15:0] read_keep = read_left >= 16 ? 16'hffff : (16'hffff >> (16-read_left));
    wire write_fire = m_axi_wvalid && raw_axi_wready;
    wire read_response_bad = raw_axi_rresp != 0 || raw_axi_rid != AXI_ID ||
                             raw_axi_rlast != (read_index == read_beats-1'b1);
    wire write_error_event = raw_axi_bvalid && raw_axi_bready &&
                             (raw_axi_bid != AXI_ID || raw_axi_bresp != 0);
    wire read_error_event = read_state == R_DATA && m_axi_rvalid && raw_axi_rready &&
                            read_index == read_beats-1'b1 && (read_bad || read_response_bad);

    genvar cfs_lane;
    assign cfs_read_request_valid=read_state==R_CFS&&!read_cfs_started&&!o_rsp_valid;
    assign cfs_read_retire=request_state==Q_COMMIT&&pending_code==OK&&req_op==5&&read_cfs;
    generate for(cfs_lane=0;cfs_lane<2;cfs_lane=cfs_lane+1)begin:g_cfs_source
        assign cfs_begin_valid[cfs_lane]=capture_state[cfs_lane]==W_CFS_BEGIN&&cfs_begin_staged[cfs_lane];
        assign cfs_valid[cfs_lane]=capture_state[cfs_lane]==W_CFS_DATA&&token_valid[cfs_lane]&&token_user[cfs_lane]==0;
        // A new START proves the old ordered source is closed, but stays at
        // the FIFO head until the old negative result has drained its jobs.
        assign cfs_end_valid[cfs_lane]=capture_state[cfs_lane]==W_CFS_DATA&&token_valid[cfs_lane]&&token_user[cfs_lane]!=0;
        assign cfs_result_ready[cfs_lane]=capture_state[cfs_lane]==W_CFS_END;
        assign cfs_finish[cfs_lane]=cfs_result_valid[cfs_lane]&&cfs_result_ready[cfs_lane];
        assign cfs_finish_ok[cfs_lane]=cfs_finish[cfs_lane]&&cfs_result_ok[cfs_lane]&&
            capture_end_seen[cfs_lane]&&!capture_bad[cfs_lane];
    end endgenerate
    always @(posedge i_clk or negedge i_rst_n)begin
        if(!i_rst_n)write_mux<=0;
        else if(CFS_ENABLE==0)write_mux<=0;
        else case(write_mux)
            0:if(raw_axi_awvalid)write_mux<=1;else if(cfs_axi_awvalid)write_mux<=2;
            1:if(raw_axi_bvalid&&raw_axi_bready)write_mux<=0;
            2:if(cfs_axi_bvalid&&cfs_axi_bready&&m_axi_bid==AXI_ID)write_mux<=0;
            default:write_mux<=0;
        endcase
    end
    assign m_axi_wvalid=CFS_ENABLE==0?raw_axi_wvalid:(write_mux==2?cfs_axi_wvalid:(write_mux==1?raw_axi_wvalid:1'b0));
    assign raw_axi_rvalid=!read_cfs&&m_axi_rvalid;assign cfs_axi_rvalid=read_cfs&&m_axi_rvalid;
    // The first registered source AW can present and handshake immediately.
    // That presentation locks write_mux at the edge even when AWREADY is low;
    // later priority changes cannot replace the held address. W/B still use
    // only the registered grant and the source's accepted-AW state.
    assign m_axi_awid=CFS_ENABLE==0?raw_axi_awid:(write_aw_select==2?cfs_axi_awid:(write_aw_select==1?raw_axi_awid:0));
    assign m_axi_awaddr=CFS_ENABLE==0?raw_axi_awaddr:(write_aw_select==2?cfs_axi_awaddr:(write_aw_select==1?raw_axi_awaddr:0));
    assign m_axi_awlen=CFS_ENABLE==0?raw_axi_awlen:(write_aw_select==2?cfs_axi_awlen:(write_aw_select==1?raw_axi_awlen:0));
    assign m_axi_awsize=CFS_ENABLE==0?raw_axi_awsize:(write_aw_select==2?cfs_axi_awsize:(write_aw_select==1?raw_axi_awsize:0));
    assign m_axi_awburst=CFS_ENABLE==0?raw_axi_awburst:(write_aw_select==2?cfs_axi_awburst:(write_aw_select==1?raw_axi_awburst:0));
    assign m_axi_awvalid=CFS_ENABLE==0?raw_axi_awvalid:(write_aw_select==2?cfs_axi_awvalid:(write_aw_select==1?raw_axi_awvalid:1'b0));
    assign raw_axi_awready=(CFS_ENABLE==0||write_aw_select==1)&&m_axi_awready;assign cfs_axi_awready=write_aw_select==2&&m_axi_awready;
    assign m_axi_wdata=CFS_ENABLE==0?raw_axi_wdata:(write_mux==2?cfs_axi_wdata:(write_mux==1?raw_axi_wdata:0));
    assign m_axi_wstrb=CFS_ENABLE==0?raw_axi_wstrb:(write_mux==2?cfs_axi_wstrb:(write_mux==1?raw_axi_wstrb:0));
    assign m_axi_wlast=CFS_ENABLE==0?raw_axi_wlast:(write_mux==2?cfs_axi_wlast:(write_mux==1?raw_axi_wlast:1'b0));
    assign raw_axi_wready=(CFS_ENABLE==0||write_mux==1)&&m_axi_wready;assign cfs_axi_wready=write_mux==2&&m_axi_wready;
    assign raw_axi_bid=m_axi_bid;assign cfs_axi_bid=m_axi_bid;
    assign raw_axi_bresp=m_axi_bresp;assign cfs_axi_bresp=m_axi_bresp;
    assign raw_axi_bvalid=(CFS_ENABLE==0||write_mux==1)&&m_axi_bvalid;assign cfs_axi_bvalid=write_mux==2&&m_axi_bvalid;
    assign m_axi_bready=CFS_ENABLE==0?raw_axi_bready:(write_mux==2?cfs_axi_bready:(write_mux==1?raw_axi_bready:1'b0));
    assign m_axi_arid=read_cfs?cfs_axi_arid:raw_axi_arid;
    assign m_axi_araddr=read_cfs?cfs_axi_araddr:raw_axi_araddr;
    assign m_axi_arlen=read_cfs?cfs_axi_arlen:raw_axi_arlen;
    assign m_axi_arsize=read_cfs?cfs_axi_arsize:raw_axi_arsize;
    assign m_axi_arburst=read_cfs?cfs_axi_arburst:raw_axi_arburst;
    assign m_axi_arvalid=read_cfs?cfs_axi_arvalid:raw_axi_arvalid;
    assign raw_axi_arready=!read_cfs&&m_axi_arready;assign cfs_axi_arready=read_cfs&&m_axi_arready;
    assign raw_axi_rid=m_axi_rid;assign cfs_axi_rid=m_axi_rid;
    assign raw_axi_rdata=m_axi_rdata;assign cfs_axi_rdata=m_axi_rdata;
    assign raw_axi_rresp=m_axi_rresp;assign cfs_axi_rresp=m_axi_rresp;
    assign raw_axi_rlast=m_axi_rlast;assign cfs_axi_rlast=m_axi_rlast;
    assign m_axi_rready=read_cfs?cfs_axi_rready:raw_axi_rready;
    generate if(CFS_ENABLE!=0)begin:g_cfs
        wire [27:0] read_base=RAW_BASE+(read_slot_full[2]*SLOTS_PER_CAMERA+read_slot[1:0])*SLOT_BYTES;
        raw_cfs_frame_backend #(.OFFICIAL_CRC_QUALIFIED(OFFICIAL_CRC_QUALIFIED),.AXI_ID(AXI_ID)) u_backend(
            .i_clk(i_clk),.i_rst_n(i_rst_n),.i_begin_valid(cfs_begin_valid),.o_begin_ready(cfs_begin_ready),
            .i_frame0(capture_cfs_frame[0]),.i_frame1(capture_cfs_frame[1]),
            .i_base0(capture_address[0]),.i_base1(capture_address[1]),.i_slot_span(SLOT_BYTES),
            .i_samples0(capture_samples[0]),.i_samples1(capture_samples[1]),
            .i_width0(slot_width[capture_slot[0]]),.i_width1(slot_width[capture_slot[1]]),
            .i_valid(cfs_valid),.o_ready(cfs_ready),.i_data({token_data[1],token_data[0]}),
            .i_keep({token_keep[1],token_keep[0]}),.i_last(token_last),.i_available({token_available[1],token_available[0]}),
            .i_end_valid(cfs_end_valid),.i_end_ok(raw_end_legal),.o_end_ready(cfs_end_ready),
            .o_result_valid(cfs_result_valid),.o_result_ok(cfs_result_ok),.i_result_ready(cfs_result_ready),
            .i_read_request_valid(cfs_read_request_valid),.o_read_request_ready(cfs_read_request_ready),
            .i_read_frame(read_cfs_frame),.i_read_base(read_base),
            .i_read_samples(slot_samples[read_slot]),.i_read_offset(read_cfs_offset),.i_read_length(read_left),
            .i_read_width(slot_width[read_slot]),.i_read_retire(cfs_read_retire),
            .o_read_valid(cfs_read_valid),.i_read_ready(i_read_ready),.o_read_data(cfs_read_data),
            .o_read_keep(cfs_read_keep),.o_read_last(cfs_read_last),.o_read_done(cfs_read_done),.o_read_error(cfs_read_error),
            .o_compressed_count(o_cfs_compressed_count),.o_no_benefit_count(o_cfs_no_benefit_count),
            .o_overflow_count(o_cfs_overflow_count),.o_busy_count(o_cfs_busy_count),
            .o_protocol_fault(o_cfs_protocol_fault),.o_write_idle(cfs_write_idle),
            .m_axi_awid(cfs_axi_awid),
            .m_axi_awaddr(cfs_axi_awaddr),
            .m_axi_awlen(cfs_axi_awlen),
            .m_axi_awsize(cfs_axi_awsize),
            .m_axi_awburst(cfs_axi_awburst),
            .m_axi_awvalid(cfs_axi_awvalid),
            .m_axi_awready(cfs_axi_awready),
            .m_axi_wdata(cfs_axi_wdata),
            .m_axi_wstrb(cfs_axi_wstrb),
            .m_axi_wlast(cfs_axi_wlast),.m_axi_wvalid(cfs_axi_wvalid),
            .m_axi_wready(cfs_axi_wready),
            .m_axi_bid(cfs_axi_bid),
            .m_axi_bresp(cfs_axi_bresp),
            .m_axi_bvalid(cfs_axi_bvalid),
            .m_axi_bready(cfs_axi_bready),
            .m_axi_arid(cfs_axi_arid),
            .m_axi_araddr(cfs_axi_araddr),
            .m_axi_arlen(cfs_axi_arlen),
            .m_axi_arsize(cfs_axi_arsize),
            .m_axi_arburst(cfs_axi_arburst),
            .m_axi_arvalid(cfs_axi_arvalid),
            .m_axi_arready(cfs_axi_arready),
            .m_axi_rid(cfs_axi_rid),
            .m_axi_rdata(cfs_axi_rdata),
            .m_axi_rresp(cfs_axi_rresp),
            .m_axi_rlast(cfs_axi_rlast),.m_axi_rvalid(cfs_axi_rvalid),
            .m_axi_rready(cfs_axi_rready));
    end else begin:g_raw_only
        assign cfs_axi_awid=0;
        assign cfs_axi_awaddr=0;
        assign cfs_axi_awlen=0;
        assign cfs_axi_awsize=0;
        assign cfs_axi_awburst=0;
        assign cfs_axi_awvalid=0;
        assign cfs_axi_wdata=0;
        assign cfs_axi_wstrb=0;
        assign cfs_axi_wlast=0;assign cfs_axi_wvalid=0;
        assign cfs_axi_bready=0;
        assign cfs_axi_arid=0;
        assign cfs_axi_araddr=0;
        assign cfs_axi_arlen=0;
        assign cfs_axi_arsize=0;
        assign cfs_axi_arburst=0;
        assign cfs_axi_arvalid=0;
        assign cfs_axi_rready=0;
        assign cfs_begin_ready=0;assign cfs_ready=0;assign cfs_end_ready=0;
        assign cfs_result_valid=0;assign cfs_result_ok=0;assign cfs_write_idle=1;
        assign cfs_read_request_ready=0;assign cfs_read_valid=0;assign cfs_read_done=0;assign cfs_read_error=0;
        assign cfs_read_data=0;assign cfs_read_keep=0;assign cfs_read_last=0;
        assign o_cfs_compressed_count=0;assign o_cfs_no_benefit_count=0;assign o_cfs_overflow_count=0;
        assign o_cfs_busy_count=0;assign o_cfs_protocol_fault=0;
    end endgenerate
    // Rotate only among unpinned complete/empty descriptors. Reader ownership
    // protects its descriptor even after all data have left this clock domain.
    always @(*) begin
        allocation_valid = 0;
        allocate_index=0; allocate_candidate=0;
        for(allocate_lane=0;allocate_lane<2;allocate_lane=allocate_lane+1) begin
            allocate_slot[allocate_lane]=0;
            for (allocate_scan=0; allocate_scan<4; allocate_scan=allocate_scan+1) begin
                allocate_candidate = (next_slot[token_camera[allocate_lane]] + allocate_scan) % SLOTS_PER_CAMERA;
                allocate_index = (CAMERA_COUNT==1 ? 0 : token_camera[allocate_lane])*4 + allocate_candidate;
                if (!allocation_valid[allocate_lane] && allocate_scan < SLOTS_PER_CAMERA && !slot_pin[allocate_index] &&
                    slot_state[allocate_index] != WRITING &&
                    (PAIR_METADATA_ENABLE==0 || (!slot_candidate[allocate_index] && !slot_job[allocate_index])) &&
                    (read_state == R_IDLE || read_slot != allocate_index) &&
                    (!cold_read_active || cold_read_slot != allocate_index)) begin
                    allocate_slot[allocate_lane] = allocate_index;
                    allocation_valid[allocate_lane] = 1;
                end
            end
        end
    end
    always @(*) begin
        token_ready=0; capture_event=0; drop_event=0; context_error_event=0;
        for(decode_lane=0;decode_lane<2;decode_lane=decode_lane+1) begin
            if(i_rst_n && (decode_lane==0 || DUAL_CAPTURE_ENABLE!=0)) begin
                case(capture_state[decode_lane])
                    W_IDLE,W_END: token_ready[decode_lane]=1;
                    W_CFS_DATA: token_ready[decode_lane]=token_user[decode_lane]==0 ? cfs_ready[decode_lane] :
                        (cfs_end_ready[decode_lane] && (token_user[decode_lane]!=1 || token_last[decode_lane]));
                    W_AW: begin
                        if(burst_state==B_AW && write_owner==decode_lane)
                            token_ready[decode_lane]=token_user[decode_lane]==3;
                        else if(DUAL_CAPTURE_ENABLE!=0 &&
                            !(burst_state!=B_IDLE && write_owner==decode_lane))
                            token_ready[decode_lane]=token_user[decode_lane]!=0 &&
                                (token_user[decode_lane]!=1 || token_last[decode_lane]);
                    end
                    W_DATA: token_ready[decode_lane]=burst_state==B_DATA && write_owner==decode_lane &&
                        !capture_fill[decode_lane] && (token_user[decode_lane]!=0 || raw_axi_wready);
                    W_DRAIN,W_CONTEXT: token_ready[decode_lane]=token_user[decode_lane]!=1 || token_last[decode_lane];
                    default: token_ready[decode_lane]=0;
                endcase
                // A cold CONTEXT transfers once into the one shared holding
                // register. The FIFO head can advance only on this grant.
                if(PAIR_METADATA_ENABLE!=0 && capture_state[decode_lane]==W_CONTEXT &&
                    context_index[decode_lane]!=0 && context_legal[decode_lane])
                    token_ready[decode_lane]=cold_write_grant && cold_write_select==decode_lane;
                // In dual mode a pending request wins one START admission edge;
                // DATA and END remain independent so requests cannot starve.
                if(capture_state[decode_lane]==W_IDLE && token_user[decode_lane]==1 && !token_last[decode_lane] &&
                    (request_state!=Q_IDLE || (DUAL_CAPTURE_ENABLE!=0 && i_req_valid && o_req_ready)))
                    token_ready[decode_lane]=0;
            end
            if(start_fire[decode_lane] && !start_legal[decode_lane]) drop_event[decode_lane]=1;
            if(capture_state[decode_lane]==W_CONTEXT) begin
                if(token_valid[decode_lane] && token_user[decode_lane]==1 && !token_last[decode_lane])
                    drop_event[decode_lane]=1;
                else if(source_fire[decode_lane] && !context_legal[decode_lane]) begin
                    drop_event[decode_lane]=1; context_error_event[decode_lane]=1;
                end
            end
            if(DUAL_CAPTURE_ENABLE!=0 && capture_state[decode_lane]==W_AW &&
                !(burst_state!=B_IDLE && write_owner==decode_lane) &&
                ((token_valid[decode_lane] && token_user[decode_lane]==1 && !token_last[decode_lane]) ||
                 (source_fire[decode_lane] && token_user[decode_lane]!=0))) drop_event[decode_lane]=1;
            if(capture_state[decode_lane]==W_B && write_owner==decode_lane && raw_axi_bvalid && raw_axi_bready &&
                (capture_bad[decode_lane] || raw_axi_bid!=AXI_ID || raw_axi_bresp!=0)) drop_event[decode_lane]=1;
            if(capture_state[decode_lane]==W_END && source_fire[decode_lane] &&
                (token_user[decode_lane]==2 || token_user[decode_lane]==3)) begin
                capture_event[decode_lane]=end_legal[decode_lane];
                drop_event[decode_lane]=!end_legal[decode_lane];
            end
        end
        for(decode_lane=0;decode_lane<2;decode_lane=decode_lane+1)begin
            if(cfs_finish[decode_lane])begin
                capture_event[decode_lane]=cfs_finish_ok[decode_lane] &&
                    (!pair_end_requested[decode_lane] || (lease_space_ok && !o_reference_fault));
                drop_event[decode_lane]=!capture_event[decode_lane];
                context_error_event[decode_lane]=!capture_event[decode_lane];
            end
        end
        o_tready=token_ready[0]; o_t1ready=token_ready[1];
    end
    assign raw_axi_awid = AXI_ID;
    assign raw_axi_awaddr = write_address;
    assign raw_axi_awlen = {3'd0,write_beats}-1'b1;
    assign raw_axi_awsize = 3'd4;
    assign raw_axi_awburst = 2'b01;
    assign raw_axi_awvalid = i_rst_n && burst_state == B_AW;
    assign raw_axi_wdata = capture_fill[write_owner] ? 128'd0 : token_data[write_owner];
    assign raw_axi_wstrb = capture_fill[write_owner] ? 16'd0 : token_keep[write_owner];
    assign raw_axi_wlast = write_index == write_beats-1'b1;
    assign raw_axi_wvalid = i_rst_n && burst_state == B_DATA &&
                          (capture_fill[write_owner] || (token_valid[write_owner] && token_user[write_owner] == 0));
    assign raw_axi_bready = i_rst_n && burst_state == B_RESP;
    assign raw_axi_arid = AXI_ID;
    assign raw_axi_araddr = read_address;
    assign raw_axi_arlen = {3'd0,read_beats}-1'b1;
    assign raw_axi_arsize = 3'd4;
    assign raw_axi_arburst = 2'b01;
    assign raw_axi_arvalid = i_rst_n && read_state == R_AR && !o_rsp_valid;
    assign o_read_complete = i_rst_n && read_state == R_HOLD;
    assign o_read_data = read_cfs ? cfs_read_data : raw_axi_rdata;
    assign o_read_keep = read_cfs ? cfs_read_keep : read_keep;
    assign o_read_last = read_cfs ? cfs_read_last : read_left <= 16;
    assign o_read_valid = read_cfs ? (read_state==R_CFS&&cfs_read_valid) :
        (i_rst_n&&read_state==R_DATA&&raw_axi_rvalid&&!read_bad&&!read_response_bad);
    assign raw_axi_rready = i_rst_n && read_state == R_DATA &&
                         (read_bad || read_response_bad || i_read_ready);
    // FETCH/REPLAY responses acknowledge admission only. The destination must
    // qualify completion with the final read beat and sticky read_error.
    assign o_req_ready = i_rst_n && request_state == Q_IDLE && !o_rsp_valid &&
                         (read_state == R_IDLE || read_state == R_HOLD) &&
                         (!reference_read_barrier || (i_req_op!=3 && i_req_op!=4)) &&
                         (DUAL_CAPTURE_ENABLE!=0 || !source_fire[0]);
    // Busy reads wait for their actual RETIRE. An invalid identity never ACKs.
    assign o_ref_ready=PAIR_METADATA_ENABLE!=0 && i_rst_n && !o_reference_fault &&
        reference_state==F_APPLY && i_ref_valid && reference_legal && !reference_waiting_pending &&
        (reference_op!=2 || (request_state==Q_IDLE &&
            (read_state==R_IDLE || (read_slot!=reference_slot0 &&
                (reference_mask!=3 || read_slot!=reference_slot1)))));
    wire private_request_authorized=!req_private ||
        (slot_job[request_slot] && req_lease!=0 && req_job_id!=0 &&
         slot_lease[request_slot]==req_lease && slot_job_id[request_slot]==req_job_id);
    wire retire_owner_matches=req_private==read_private &&
        (!req_private || (req_lease==read_lease && req_job_id==read_job_id));
    // Applied DFI policy owns the processing pool. Reject a queued public
    // REPLAY before creating any reader; public FETCH and existing RETIRE
    // remain available, and authenticated private REPLAY keeps its JOB owner.
    wire public_replay_blocked=PHYSICAL_MONO_CURRENT_ENABLE!=0 &&
        i_physical_mono_current_enable && req_op==4 && !req_private;
    always @(*) begin
        request_code = OK;
        if (req_camera>=CAMERA_COUNT || req_op > 5 || (req_private && req_op<3) ||
            (req_slot >= SLOTS_PER_CAMERA && !(req_op == 1 && req_generation == 0)))
            request_code = INVALID;
        else if (CONTEXT_ENABLE && req_op != 0 && o_rsp_session != req_session)
            request_code = STALE;
        else if (o_rsp_state == WRITING)
            request_code = BUSY;
        else if (o_rsp_state != COMPLETE)
            request_code = NO_FRAME;
        else if (req_op != 0 && !(req_op == 1 && req_generation == 0) &&
                 req_generation != o_rsp_generation)
            request_code = STALE;
        else if (!private_request_authorized)
            request_code = STALE;
        else if (public_replay_blocked)
            request_code = BUSY;
        else if (req_op == 2 && read_state != R_IDLE && read_slot == request_slot)
            request_code = BUSY;
        else if ((req_op == 3 || req_op == 4) && read_state != R_IDLE)
            request_code = BUSY;
        else if ((req_op == 3 || req_op == 4) && !req_private && !o_rsp_pinned)
            request_code = INVALID;
        else if (req_op == 3 && (req_offset[3:0] != 0 || requested_bytes == 0 ||
                 requested_bytes > 2560 || requested_end > {1'b0,o_rsp_payload_bytes}))
            request_code = RANGE;
        else if (req_op == 5 && (read_state != R_HOLD || read_slot != request_slot || !retire_owner_matches))
            request_code = INVALID;
    end

    // Capture state advances only on token or AXI handshakes. A discarded frame
    // cannot withdraw AW; zero-strobe filler finishes its reserved W burst.
    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            cold_write_busy<=0;cold_write_owner<=0;cold_write_group<=0;cold_write_turn<=0;
            cold_write_slot<=0;cold_write_word<=0;cold_write_holding<=0;
            cold_read_active<=0;cold_read_pending<=0;cold_read_owner<=0;cold_read_turn<=0;
            cold_read_slot<=0;cold_read_issue<=0;cold_read_word<=0;
            cold_read_generation<=0;cold_read_groups<=0;
            burst_state<=B_IDLE; write_owner<=0; write_turn<=0;
            cfs_begin_staged<=0;read_cfs_frame<=0;
            write_address<=RAW_BASE; write_beats<=0; write_index<=0;
            for(capture_lane=0;capture_lane<2;capture_lane=capture_lane+1) begin
                capture_state[capture_lane]<=W_IDLE; capture_slot[capture_lane]<=0;
                capture_address[capture_lane]<=RAW_BASE; capture_left[capture_lane]<=0;
                capture_received[capture_lane]<=0; capture_expected[capture_lane]<=0;
                capture_samples[capture_lane]<=0; capture_bad[capture_lane]<=0;
                capture_fill[capture_lane]<=0; capture_end_seen[capture_lane]<=0;
                context_index[capture_lane]<=0;
                capture_cfs_frame[capture_lane]<=0;
            end
            slot_candidate<=0;slot_job<=0;slot_pending<=0;lease_counter<=0;
            commit_state<=C_IDLE;commit_snapshot<=0;commit_scan<=0;commit_best<=0;commit_slot<=0;
            commit_best_valid<=0;commit_best_lease<=0;
            o_commit_valid<=0;o_commit_frame<=0;o_commit_lease<=0;o_reference_fault<=0;
            reference_state<=F_IDLE;reference_op<=0;reference_mask<=0;
            reference_frame0<=0;reference_frame1<=0;reference_lease0<=0;reference_lease1<=0;reference_job_id<=0;
            read_state <= R_IDLE; read_slot <= 0; read_address <= RAW_BASE;
            read_left <= 0; read_beats <= 0; read_index <= 0; read_bad <= 0; o_read_error <= 0;
            read_private<=0;read_lease<=0;read_job_id<=0;read_cfs<=0;read_cfs_started<=0;read_cfs_offset<=0;
            read_candidate_beats <= 0; read_boundary_beats <= 0;
            request_state <= Q_IDLE; request_slot <= 0; req_op <= 0; req_camera <= 0; req_slot <= 0;
            req_generation <= 0; req_session <= 0; req_offset <= 0; req_length <= 0;
            req_private<=0;req_lease<=0;req_job_id<=0;
            candidate_valid <= 0; scan_slot <= 0; best_stamp <= 0; best_valid <= 0;
            request_base <= RAW_BASE; requested_address <= RAW_BASE;
            requested_bytes <= 0; requested_end <= 0; pending_code <= OK;
            o_capture_count <= 0; o_read_count <= 0; o_drop_count <= 0; o_error_count <= 0;
            o_rsp_valid <= 0; o_rsp_code <= 0; o_rsp_camera <= 0; o_rsp_slot <= 0;
            o_rsp_generation <= 0; o_rsp_sequence <= 0; o_rsp_epoch <= 0;
            o_rsp_session <= 0; o_rsp_format <= 0;
            o_rsp_width <= 0; o_rsp_height <= 0; o_rsp_sample_count <= 0;
            o_rsp_payload_bytes <= 0; o_rsp_pinned <= 0; o_rsp_state <= 0;
            o_rsp_descriptor <= 0; o_rsp_metadata_valid <= 0;
            next_slot[0] <= 0; next_slot[1] <= 0;
            for (reset_index=0; reset_index<8; reset_index=reset_index+1) begin
                slot_cfs[reset_index]<=0;
                slot_state[reset_index] <= EMPTY; slot_pin[reset_index] <= 0; slot_gen[reset_index] <= 0;
                slot_session[reset_index] <= 0; slot_format[reset_index] <= 0;
                slot_seq[reset_index] <= 0; slot_epoch[reset_index] <= 0; slot_width[reset_index] <= 0;
                slot_height[reset_index] <= 0; slot_samples[reset_index] <= 0; slot_bytes[reset_index] <= 0; slot_stamp[reset_index] <= 0;
                slot_cold_valid[reset_index]<=0;
                slot_meta_valid[reset_index]<=0;slot_qualified[reset_index]<=0;slot_source[reset_index]<=0;
                slot_physical_current[reset_index]<=0;
                slot_role[reset_index]<=0;slot_lease[reset_index]<=0;slot_job_id[reset_index]<=0;
                if (reset_index < 4) candidate_stamp[reset_index] <= 0;
            end
        end else begin
            if(cold_write_grant && source_fire[cold_write_select])begin
                cold_write_busy<=1;cold_write_owner<=cold_write_select;
                cold_write_slot<=capture_slot[cold_write_select];
                cold_write_group<=context_index[cold_write_select]==2;
                cold_write_word<=0;cold_write_holding<=token_data[cold_write_select];
                cold_write_turn<=!cold_write_select;
            end else if(cold_write_busy)begin
                cold_write_holding<={32'd0,cold_write_holding[127:32]};
                if(cold_write_last)begin
                    cold_write_busy<=0;slot_cold_valid[cold_write_slot][cold_write_group]<=1;
                end else cold_write_word<=cold_write_word+1'b1;
            end
            if(cold_read_grant)begin
                cold_read_active<=1;cold_read_owner<=cold_read_select;
                cold_read_slot<=cold_read_selected_slot;cold_read_issue<=0;cold_read_word<=0;
                cold_read_pending<=0;cold_read_generation<=slot_gen[cold_read_selected_slot];
                cold_read_groups<=slot_cold_valid[cold_read_selected_slot];
                case(cold_read_select)
                    0:begin
                        o_commit_frame<=pair_descriptor(cold_read_selected_slot);
                        o_commit_lease<=slot_lease[cold_read_selected_slot];commit_slot<=cold_read_selected_slot;
                    end
                    1:capture_cfs_frame[0]<=pair_descriptor(cold_read_selected_slot);
                    2:capture_cfs_frame[1]<=pair_descriptor(cold_read_selected_slot);
                    default:begin end // Q_SNAPSHOT fills the existing response.
                endcase
            end else if(cold_read_active)begin
                cold_read_pending<=cold_read_enable;
                if(cold_read_enable)cold_read_issue<=cold_read_issue+1'b1;
                if(cold_read_pending)begin
                    // Direct assembly into the existing destination registers;
                    // no extra 192-bit or 384-bit read holding register.
                    case(cold_read_owner)
                        0:case(cold_read_word)
                            0:o_commit_frame[172:141]<=cold_read_masked;
                            1:o_commit_frame[204:173]<=cold_read_masked;
                            2:o_commit_frame[302:271]<=cold_read_masked;
                            3:o_commit_frame[334:303]<=cold_read_masked;
                            4:o_commit_frame[270:239]<=cold_read_masked;
                            5:o_commit_frame[366:335]<=cold_read_masked;
                        endcase
                        1,2:case(cold_read_word)
                            0:capture_cfs_frame[cold_read_owner-1][172:141]<=cold_read_masked;
                            1:capture_cfs_frame[cold_read_owner-1][204:173]<=cold_read_masked;
                            2:capture_cfs_frame[cold_read_owner-1][302:271]<=cold_read_masked;
                            3:capture_cfs_frame[cold_read_owner-1][334:303]<=cold_read_masked;
                            4:capture_cfs_frame[cold_read_owner-1][270:239]<=cold_read_masked;
                            5:capture_cfs_frame[cold_read_owner-1][366:335]<=cold_read_masked;
                        endcase
                        3:case(cold_read_word)
                            0:o_rsp_descriptor[172:141]<=cold_read_masked;
                            1:o_rsp_descriptor[204:173]<=cold_read_masked;
                            2:o_rsp_descriptor[302:271]<=cold_read_masked;
                            3:o_rsp_descriptor[334:303]<=cold_read_masked;
                            4:o_rsp_descriptor[270:239]<=cold_read_masked;
                            5:o_rsp_descriptor[366:335]<=cold_read_masked;
                        endcase
                    endcase
                    cold_read_word<=cold_read_word+1'b1;
                end
                if(cold_read_last)begin
                    cold_read_active<=0;cold_read_pending<=0;cold_read_turn<=cold_read_owner+1'b1;
                    if(cold_read_same)case(cold_read_owner)
                        0:begin o_commit_valid<=1;commit_state<=C_IDLE;end
                        1:cfs_begin_staged[0]<=1;
                        2:cfs_begin_staged[1]<=1;
                        3:request_state<=Q_RANGE;
                    endcase
                    else if(cold_read_owner==3)request_state<=Q_SNAPSHOT;
                end
            end
            if(PAIR_METADATA_ENABLE!=0) begin
                if(lease_demand!=0) begin
                    if(!lease_space_ok || o_reference_fault) o_reference_fault<=1;
                    else lease_counter<=lease_counter+{62'd0,lease_demand};
                end
                if(o_commit_valid && i_commit_ready) begin
                    o_commit_valid<=0;slot_pending[commit_slot]<=0;
                end
                // Snapshot the pending bitmap before scanning: newcomers have
                // later leases and cannot jump an older unscanned commit.
                if(!o_commit_valid) case(commit_state)
                    C_IDLE: begin
                        commit_snapshot<=slot_pending;commit_scan<=0;
                        commit_best_valid<=0;commit_best_lease<=64'hffffffffffffffff;
                        commit_state<=C_SCAN;
                    end
                    C_SCAN: begin
                        if(commit_snapshot[commit_scan] &&
                            (!commit_best_valid || slot_lease[commit_scan]<commit_best_lease)) begin
                            commit_best_valid<=1;commit_best<=commit_scan;commit_best_lease<=slot_lease[commit_scan];
                        end
                        if(commit_scan==ACTIVE_SLOT_COUNT-1) commit_state<=C_PUBLISH;
                        else commit_scan<=commit_scan+1'b1;
                    end
                    C_PUBLISH: begin
                        if(!commit_best_valid) commit_state<=C_IDLE;
                        // The shared directory reader fills the existing
                        // commit holding register and publishes only at done.
                    end
                    default: commit_state<=C_IDLE;
                endcase
                if(!o_reference_fault) case(reference_state)
                    F_IDLE: if(i_ref_valid) begin
                        reference_op<=i_ref_op;reference_mask<=i_ref_mask;
                        reference_frame0<=i_ref_frame0;reference_frame1<=i_ref_frame1;
                        reference_lease0<=i_ref_lease0;reference_lease1<=i_ref_lease1;
                        reference_job_id<=i_ref_job_id;reference_state<=F_CHECK;
                    end
                    F_CHECK: begin
                        if(!reference_legal) o_reference_fault<=1;
                        else reference_state<=F_APPLY;
                    end
                    F_APPLY: if(i_ref_valid && o_ref_ready) begin
                        // Entire mask was validated before this one atomic edge.
                        if(reference_op==0) slot_candidate[reference_slot0]<=0;
                        else if(reference_op==1) begin
                            slot_candidate[reference_slot0]<=0;slot_job[reference_slot0]<=1;
                            slot_job_id[reference_slot0]<=reference_job_id;
                        end else begin slot_job[reference_slot0]<=0;slot_job_id[reference_slot0]<=0;end
                        if(reference_mask==3) begin
                            if(reference_op==0) slot_candidate[reference_slot1]<=0;
                            else if(reference_op==1) begin
                                slot_candidate[reference_slot1]<=0;slot_job[reference_slot1]<=1;
                                slot_job_id[reference_slot1]<=reference_job_id;
                            end else begin slot_job[reference_slot1]<=0;slot_job_id[reference_slot1]<=0;end
                        end
                        reference_state<=F_IDLE;
                    end
                    default: o_reference_fault<=1;
                endcase
            end
            if (o_rsp_valid && i_rsp_ready) o_rsp_valid <= 0;
            if (|capture_event) o_capture_count<=o_capture_count+{31'd0,capture_event[0]}+{31'd0,capture_event[1]};
            if (|drop_event) o_drop_count<=o_drop_count+{31'd0,drop_event[0]}+{31'd0,drop_event[1]};
            if (write_error_event || read_error_event || (|context_error_event))
                o_error_count <= o_error_count + {31'd0,write_error_event} +
                                 {31'd0,read_error_event} + {31'd0,context_error_event[0]}+
                                 {31'd0,context_error_event[1]};
            case(burst_state)
                B_IDLE: if(|burst_eligible) begin
                    write_owner<=burst_select;
                    write_address<=capture_address[burst_select];
                    write_beats<=candidate_beats[burst_select]; write_index<=0;
                    burst_state<=B_AW;
                end
                B_AW: if(raw_axi_awvalid && raw_axi_awready) begin
                    burst_state<=B_DATA; capture_state[write_owner]<=W_DATA;
                end
                B_DATA: if(write_fire) begin
                    write_index<=write_index+1'b1;
                    if(raw_axi_wlast) begin burst_state<=B_RESP; capture_state[write_owner]<=W_B; end
                end
                B_RESP: if(raw_axi_bvalid && raw_axi_bready) begin
                    burst_state<=B_IDLE; write_turn<=!write_owner;
                end
                default: burst_state<=B_IDLE;
            endcase
            for(capture_lane=0;capture_lane<2;capture_lane=capture_lane+1) begin
                case(capture_state[capture_lane])
                    W_IDLE: if(start_fire[capture_lane]) begin
                        if(!start_legal[capture_lane]) capture_state[capture_lane]<=W_DRAIN;
                        else begin
                            capture_slot[capture_lane]<=allocate_slot[capture_lane];
                            cfs_begin_staged[capture_lane]<=0;
                            slot_state[allocate_slot[capture_lane]]<=WRITING;
                            slot_cfs[allocate_slot[capture_lane]]<=CFS_ENABLE!=0 && i_cfs_enable;
                            slot_gen[allocate_slot[capture_lane]]<=slot_gen[allocate_slot[capture_lane]]==32'hffffffff ?
                                32'd1 : slot_gen[allocate_slot[capture_lane]]+1'b1;
                            slot_session[allocate_slot[capture_lane]]<=0;
                            slot_cold_valid[allocate_slot[capture_lane]]<=0;slot_meta_valid[allocate_slot[capture_lane]]<=0;
                            slot_physical_current[allocate_slot[capture_lane]]<=PHYSICAL_MONO_CURRENT_ENABLE!=0 &&
                                capture_lane==0 && i_physical_mono_current_enable;
                            slot_qualified[allocate_slot[capture_lane]]<=0;slot_source[allocate_slot[capture_lane]]<=0;
                            slot_role[allocate_slot[capture_lane]]<=0;slot_lease[allocate_slot[capture_lane]]<=0;
                            slot_job_id[allocate_slot[capture_lane]]<=0;context_index[capture_lane]<=0;
                            slot_format[allocate_slot[capture_lane]]<=CONTEXT_ENABLE ? 0 : 1;
                            slot_seq[allocate_slot[capture_lane]]<=token_data[capture_lane][31:0];
                            slot_epoch[allocate_slot[capture_lane]]<=token_data[capture_lane][95:64];
                            slot_width[allocate_slot[capture_lane]]<=token_data[capture_lane][47:32];
                            slot_height[allocate_slot[capture_lane]]<=token_data[capture_lane][63:48];
                            slot_samples[allocate_slot[capture_lane]]<=start_samples[capture_lane];
                            slot_bytes[allocate_slot[capture_lane]]<=start_bytes[capture_lane];
                            next_slot[token_camera[capture_lane]]<=(allocate_slot[capture_lane]%4+1)%SLOTS_PER_CAMERA;
                            capture_address[capture_lane]<=RAW_BASE+
                                (token_camera[capture_lane]*SLOTS_PER_CAMERA+allocate_slot[capture_lane]%4)*SLOT_BYTES;
                            capture_left[capture_lane]<=start_bytes[capture_lane];
                            capture_expected[capture_lane]<=start_bytes[capture_lane];
                            capture_samples[capture_lane]<=start_samples[capture_lane]; capture_received[capture_lane]<=0;
                            capture_bad[capture_lane]<=0; capture_fill[capture_lane]<=0; capture_end_seen[capture_lane]<=0;
                            capture_state[capture_lane]<=CONTEXT_ENABLE ? W_CONTEXT :
                                (CFS_ENABLE!=0 && i_cfs_enable ? W_CFS_BEGIN : W_AW);
                        end
                    end
                    W_CONTEXT: begin
                        if(token_valid[capture_lane] && token_user[capture_lane]==1 && !token_last[capture_lane]) begin
                            slot_state[capture_slot[capture_lane]]<=ABORTED; capture_state[capture_lane]<=W_IDLE;
                        end else if(source_fire[capture_lane]) begin
                            if(context_legal[capture_lane]) begin
                                if(PAIR_METADATA_ENABLE==0 || context_index[capture_lane]==0) begin
                                    slot_session[capture_slot[capture_lane]]<=token_data[capture_lane][31:0];
                                    slot_format[capture_slot[capture_lane]]<=token_data[capture_lane][39:32];
                                    if(PAIR_METADATA_ENABLE!=0) begin
                                        slot_source[capture_slot[capture_lane]]<=token_data[capture_lane][108];
                                        slot_role[capture_slot[capture_lane]]<=token_data[capture_lane][110:109];
                                        slot_qualified[capture_slot[capture_lane]]<=token_data[capture_lane][111];
                                        slot_meta_valid[capture_slot[capture_lane]]<=token_data[capture_lane][112];
                                    end
                                end
                                if(PAIR_METADATA_ENABLE==0) capture_state[capture_lane]<=
                                    slot_cfs[capture_slot[capture_lane]] ? W_CFS_BEGIN : W_AW;
                                else if(context_index[capture_lane]==0) context_index[capture_lane]<=1;
                                else capture_state[capture_lane]<=W_CONTEXT_WRITE;
                            end else begin
                                slot_state[capture_slot[capture_lane]]<=ABORTED;
                                capture_state[capture_lane]<=token_user[capture_lane]==2 || token_user[capture_lane]==3 ? W_IDLE : W_DRAIN;
                            end
                        end
                    end
                    W_CONTEXT_WRITE: if(cold_write_last && cold_write_owner==capture_lane) begin
                        if(context_index[capture_lane]==1) begin
                            context_index[capture_lane]<=2;capture_state[capture_lane]<=W_CONTEXT;
                        end else capture_state[capture_lane]<=slot_cfs[capture_slot[capture_lane]] ? W_CFS_BEGIN : W_AW;
                    end
                    W_CFS_BEGIN:begin
                        if(PAIR_METADATA_ENABLE==0 && !cfs_begin_staged[capture_lane])begin
                            capture_cfs_frame[capture_lane]<=pair_descriptor(capture_slot[capture_lane]);
                            cfs_begin_staged[capture_lane]<=1;
                        end else if(cfs_begin_staged[capture_lane] && cfs_begin_ready[capture_lane])
                            capture_state[capture_lane]<=W_CFS_DATA;
                    end
                    W_CFS_DATA:begin
                        if(source_fire[capture_lane] && token_user[capture_lane]==0)begin
                            capture_received[capture_lane]<=capture_received[capture_lane]+count_keep(token_keep[capture_lane]);
                            capture_left[capture_lane]<=capture_left[capture_lane]>16?capture_left[capture_lane]-16:0;
                            if(!data_legal[capture_lane])capture_bad[capture_lane]<=1;
                        end
                        if(cfs_end_valid[capture_lane]&&cfs_end_ready[capture_lane])begin
                            capture_end_seen[capture_lane]<=raw_end_legal[capture_lane];
                            capture_state[capture_lane]<=W_CFS_END;
                        end
                    end
                    W_CFS_END:if(cfs_finish[capture_lane])begin
                        if(capture_event[capture_lane])begin
                            slot_state[capture_slot[capture_lane]]<=COMPLETE;
                            if(pair_end_requested[capture_lane])begin
                                slot_candidate[capture_slot[capture_lane]]<=1;slot_pending[capture_slot[capture_lane]]<=1;
                                slot_lease[capture_slot[capture_lane]]<=lease_counter+64'd1+
                                    (capture_lane==1?{63'd0,pair_end_requested[0]}:64'd0);
                            end
                            slot_stamp[capture_slot[capture_lane]]<=o_capture_count+1'b1+
                                (capture_lane==1?{31'd0,capture_event[0]}:32'd0);
                        end else slot_state[capture_slot[capture_lane]]<=ABORTED;
                        capture_state[capture_lane]<=W_IDLE;
                    end
                    W_AW: begin
                        if(burst_state==B_AW && write_owner==capture_lane) begin
                            if(source_fire[capture_lane]) begin
                                capture_bad[capture_lane]<=1; capture_fill[capture_lane]<=1; capture_end_seen[capture_lane]<=1;
                            end
                        end else if(DUAL_CAPTURE_ENABLE!=0 && !(burst_state!=B_IDLE && write_owner==capture_lane)) begin
                            if(token_valid[capture_lane] && token_user[capture_lane]==1 && !token_last[capture_lane]) begin
                                slot_state[capture_slot[capture_lane]]<=ABORTED; capture_state[capture_lane]<=W_IDLE;
                            end else if(source_fire[capture_lane] && token_user[capture_lane]!=0) begin
                                slot_state[capture_slot[capture_lane]]<=ABORTED;
                                capture_state[capture_lane]<=token_user[capture_lane]==2 || token_user[capture_lane]==3 ? W_IDLE : W_DRAIN;
                            end
                        end
                    end
                    W_DATA: begin
                        if(source_fire[capture_lane] && token_user[capture_lane]!=0) begin
                            capture_bad[capture_lane]<=1; capture_fill[capture_lane]<=1;
                            if(token_user[capture_lane]==2 || token_user[capture_lane]==3) capture_end_seen[capture_lane]<=1;
                        end
                        if(write_fire && write_owner==capture_lane) begin
                            if(!capture_fill[capture_lane]) begin
                                capture_received[capture_lane]<=capture_received[capture_lane]+(capture_left[capture_lane]>=16 ? 16 : capture_left[capture_lane]);
                                if(!data_legal[capture_lane]) begin capture_bad[capture_lane]<=1; capture_fill[capture_lane]<=1; end
                            end
                            capture_left[capture_lane]<=capture_left[capture_lane]>16 ? capture_left[capture_lane]-16 : 0;
                        end
                    end
                    W_B: if(raw_axi_bvalid && raw_axi_bready && write_owner==capture_lane) begin
                        if(capture_bad[capture_lane] || raw_axi_bid!=AXI_ID || raw_axi_bresp!=0) begin
                            slot_state[capture_slot[capture_lane]]<=ABORTED;
                            capture_state[capture_lane]<=capture_end_seen[capture_lane] ? W_IDLE : W_DRAIN;
                        end else if(capture_left[capture_lane]==0) capture_state[capture_lane]<=W_END;
                        else begin
                            capture_address[capture_lane]<=capture_address[capture_lane]+{write_beats,4'd0};
                            capture_state[capture_lane]<=W_AW;
                        end
                    end
                    W_END: if(source_fire[capture_lane]) begin
                        if(token_user[capture_lane]==2 || token_user[capture_lane]==3) begin
                            if(end_legal[capture_lane]) begin
                                slot_state[capture_slot[capture_lane]]<=COMPLETE;
                                if(pair_end_requested[capture_lane]) begin
                                    slot_candidate[capture_slot[capture_lane]]<=1;
                                    slot_pending[capture_slot[capture_lane]]<=1;
                                    slot_lease[capture_slot[capture_lane]]<=lease_counter+64'd1+
                                        (capture_lane==1 ? {63'd0,pair_end_requested[0]} : 64'd0);
                                end
                                slot_stamp[capture_slot[capture_lane]]<=o_capture_count+1'b1+
                                    (capture_lane==1 ? {31'd0,capture_event[0]} : 32'd0);
                            end else slot_state[capture_slot[capture_lane]]<=ABORTED;
                            capture_state[capture_lane]<=W_IDLE;
                        end else capture_bad[capture_lane]<=1;
                    end
                    W_DRAIN: begin
                        if(token_valid[capture_lane] && token_user[capture_lane]==1 && !token_last[capture_lane]) capture_state[capture_lane]<=W_IDLE;
                        else if(source_fire[capture_lane] && (token_user[capture_lane]==2 || token_user[capture_lane]==3)) capture_state[capture_lane]<=W_IDLE;
                    end
                    default: capture_state[capture_lane]<=W_IDLE;
                endcase
            end
            case (request_state)
            Q_IDLE: if (i_req_valid && o_req_ready) begin
                req_op <= i_req_op; req_camera <= i_req_camera; req_slot <= i_req_slot;
                req_generation <= i_req_generation; req_session <= i_req_session;
                req_private<=PAIR_METADATA_ENABLE!=0 && i_req_private;
                req_lease<=PAIR_METADATA_ENABLE!=0 && i_req_private ? i_req_lease : 64'd0;
                req_job_id<=PAIR_METADATA_ENABLE!=0 && i_req_private ? i_req_job_id : 64'd0;
                req_offset <= i_req_offset; req_length <= i_req_length;
                request_slot <= {i_req_camera,i_req_slot};
                // One admission-time latest snapshot, not a rolling scan of
                // writer commits. The public BAR still uses exact slot/gen.
                for (candidate_index=0; candidate_index<4; candidate_index=candidate_index+1) begin
                    candidate_valid[candidate_index] <= i_req_camera<CAMERA_COUNT && candidate_index < SLOTS_PER_CAMERA &&
                        slot_state[selected_request_camera*4+candidate_index] == COMPLETE &&
                        (!CONTEXT_ENABLE || slot_session[selected_request_camera*4+candidate_index] == i_req_session);
                    candidate_stamp[candidate_index] <= slot_stamp[selected_request_camera*4+candidate_index];
                end
                scan_slot <= 0; best_valid <= 0; best_stamp <= 0;
                request_state <= i_req_op == 1 && i_req_generation == 0 ? Q_SCAN : Q_SNAPSHOT;
            end
            Q_SCAN: begin
                if (candidate_valid[scan_slot] &&
                    (!best_valid || $signed(candidate_stamp[scan_slot]-best_stamp) > 0)) begin
                    best_valid <= 1; best_stamp <= candidate_stamp[scan_slot];
                    request_slot <= {req_camera,scan_slot};
                end
                if (scan_slot == 3) request_state <= Q_SNAPSHOT;
                else scan_slot <= scan_slot+1'b1;
            end
            Q_SNAPSHOT: if(PAIR_METADATA_ENABLE==0 || req_camera>=CAMERA_COUNT ||
                (cold_read_grant && cold_read_select==3)) begin
                o_rsp_camera <= req_camera;
                o_rsp_slot <= request_slot[1:0];
                o_rsp_generation <= slot_gen[request_slot]; o_rsp_sequence <= slot_seq[request_slot];
                o_rsp_session <= slot_session[request_slot]; o_rsp_format <= slot_format[request_slot];
                o_rsp_epoch <= slot_epoch[request_slot]; o_rsp_width <= slot_width[request_slot];
                o_rsp_height <= slot_height[request_slot]; o_rsp_sample_count <= slot_samples[request_slot];
                o_rsp_payload_bytes <= slot_bytes[request_slot]; o_rsp_pinned <= slot_pin[request_slot];
                o_rsp_state <= slot_state[request_slot];
                // Same immutable Q_SNAPSHOT as the public response fields;
                // a later capture/config change cannot relabel this response.
                o_rsp_descriptor <= pair_descriptor(request_slot);
                o_rsp_metadata_valid <= slot_meta_valid[request_slot];
                if(req_camera>=CAMERA_COUNT)begin
                    o_rsp_generation<=0;o_rsp_sequence<=0;o_rsp_session<=0;o_rsp_format<=0;
                    o_rsp_epoch<=0;o_rsp_width<=0;o_rsp_height<=0;o_rsp_sample_count<=0;
                    o_rsp_payload_bytes<=0;o_rsp_pinned<=0;o_rsp_state<=EMPTY;
                    o_rsp_descriptor<=0;o_rsp_metadata_valid<=0;
                end
                request_base <= RAW_BASE + (req_camera*SLOTS_PER_CAMERA + request_slot[1:0])*SLOT_BYTES;
                request_state <= PAIR_METADATA_ENABLE!=0 && req_camera<CAMERA_COUNT ? Q_COLD : Q_RANGE;
            end
            Q_COLD: begin end // Directory completion owns the next state.
            Q_RANGE: begin
                requested_bytes <= req_op == 4 ? o_rsp_payload_bytes : req_length;
                requested_end <= {1'b0,req_offset} + {1'b0,(req_op == 4 ? o_rsp_payload_bytes : req_length)};
                requested_address <= request_base + (req_op == 4 ? 0 : req_offset);
                request_state <= Q_CHECK;
            end
            Q_CHECK: begin pending_code <= request_code; request_state <= Q_VERIFY; end
            Q_VERIFY: begin
                // Snapshot metadata never follows a later slot reuse. Recheck
                // before side effects even though new START is held pending.
                if (pending_code == OK && req_op != 0) begin
                    if (slot_gen[request_slot] != o_rsp_generation ||
                        (CONTEXT_ENABLE && slot_session[request_slot] != req_session)) pending_code <= STALE;
                    else if (slot_state[request_slot] != COMPLETE) pending_code <= BUSY;
                    else if (!private_request_authorized) pending_code <= STALE;
                    else if (public_replay_blocked) pending_code <= BUSY;
                    else if (req_op == 2 && read_state != R_IDLE && read_slot == request_slot) pending_code <= BUSY;
                    else if ((req_op == 3 || req_op == 4) &&
                             (read_state != R_IDLE || (!req_private && !slot_pin[request_slot]))) pending_code <= BUSY;
                    else if (req_op == 5 && (read_state != R_HOLD || read_slot != request_slot || !retire_owner_matches)) pending_code <= INVALID;
                end
                request_state <= Q_COMMIT;
            end
            Q_COMMIT: begin
                o_rsp_code <= pending_code; o_rsp_valid <= 1; request_state <= Q_IDLE;
                if (pending_code == OK) case (req_op)
                    1: begin slot_pin[request_slot] <= 1; o_rsp_pinned <= 1; end
                    2: begin slot_pin[request_slot] <= 0; o_rsp_pinned <= 0; end
                    3,4: begin
                        read_slot <= request_slot; read_state <= slot_cfs[request_slot] ? R_CFS : R_PREPARE;
                        read_cfs<=slot_cfs[request_slot];read_cfs_started<=0;
                        read_cfs_frame<=o_rsp_descriptor;
                        read_cfs_offset<=req_op==4?32'd0:req_offset;
                        read_private<=req_private;read_lease<=req_lease;read_job_id<=req_job_id;
                        read_address <= requested_address;
                        read_left <= requested_bytes;
                        read_bad <= 0; o_read_error <= 0; read_index <= 0;
                    end
                    5: begin
                        read_state <= R_IDLE; o_read_error <= 0;
                        read_private<=0;read_lease<=0;read_job_id<=0;
                    end
                    default: begin end
                endcase
            end
            default: request_state <= Q_IDLE;
            endcase
            if(read_state==R_CFS)begin
                if(cfs_read_request_valid&&cfs_read_request_ready)read_cfs_started<=1;
                if(cfs_read_done)begin read_state<=R_HOLD;if(!cfs_read_error)o_read_count<=o_read_count+1'b1;
                    if(cfs_read_error)o_read_error<=1;end
            end
            if (read_state == R_PREPARE) begin
                // Only the final <=256 bytes need a small ceil(/16). Above
                // that threshold each candidate burst is exactly 16 beats.
                read_candidate_beats <= read_left >= 256 ? 5'd16 :
                    {1'b0,read_left[7:4]} + (|read_left[3:0]);
                read_boundary_beats <= read_address[11:8] == 4'hf ?
                    5'd16-{1'b0,read_address[7:4]} : 5'd16;
                read_state <= R_BURST;
            end
            if (read_state == R_BURST) begin
                read_beats <= read_candidate_beats < read_boundary_beats ?
                              read_candidate_beats : read_boundary_beats;
                read_state <= R_AR;
            end
            if (read_state == R_AR && raw_axi_arvalid && raw_axi_arready) begin
                read_state <= R_DATA; read_index <= 0;
            end
            if (read_state == R_DATA && raw_axi_rvalid && raw_axi_rready) begin
                if (read_response_bad) begin read_bad <= 1; o_read_error <= 1; end
                read_left <= read_left > 16 ? read_left-16 : 0;
                read_index <= read_index+1'b1;
                if (read_index == read_beats-1'b1) begin
                    if (read_left <= 16 || read_bad || read_response_bad) begin
                        read_state <= R_HOLD;
                        if (!read_bad && !read_response_bad) o_read_count <= o_read_count+1'b1;
                    end else begin
                        read_state <= R_PREPARE;
                        read_address <= read_address + {read_beats,4'd0};
                    end
                end
            end
        end
    end
endmodule
