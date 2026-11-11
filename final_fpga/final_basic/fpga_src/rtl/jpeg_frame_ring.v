`timescale 1ns / 1ps
// Three descriptors per present camera; protocol slot IDs stay global0..5.
module jpeg_frame_ring #(
    parameter [31:0] SLOT_BYTES = 32'h01000000,
    parameter [27:0] SLOT0_BASE = 28'h0000000,
    parameter [27:0] SLOT1_BASE = 28'hA000000,
    parameter [27:0] SLOT2_BASE = 28'hB000000,
    parameter [27:0] SLOT3_BASE = 28'hC000000,
    parameter [27:0] SLOT4_BASE = 28'hD000000,
    parameter [27:0] SLOT5_BASE = 28'hE000000,
    parameter integer WRITE_RESULT_ENABLE = 0,
    parameter integer WRITE_TAG_ENABLE = 0,
    parameter integer MASK_ENABLE = 0,
    parameter integer CAMERA_COUNT = 2
) (
    // 时钟与就绪
    input wire i_clk,
    input wire i_rst_n,
    input wire i_ddr_ready,

    // 帧启动与元数据
    input wire i_start_valid,
    output wire o_start_ready,
    input wire [31:0] i_capture_id,
    input wire [15:0] i_width,
    input wire [15:0] i_height,
    input wire [63:0] i_timestamp_ns,
    input wire [31:0] i_write_tag,

    // JPEG输入流
    input wire [127:0] i_jpeg_tdata,
    input wire [15:0] i_jpeg_tkeep,
    input wire i_jpeg_tvalid,
    output wire o_jpeg_tready,
    input wire i_jpeg_tlast,

    // 编码结果
    input wire i_result_valid,
    output wire o_result_ready,
    input wire [31:0] i_result_id,
    input wire i_result_ok,
    input wire [24:0] i_result_length,

    // DFI-domain writer completion, after all promised AXI writes and drain.
    // Encoding RESULT acceptance above is only a fence, not this completion.
    output reg o_write_result_valid,
    input wire i_write_result_ready,
    output reg o_write_result_ok,
    output reg [7:0] o_write_result_error,
    output wire [31:0] o_write_result_capture_id,
    output wire [31:0] o_write_result_session,
    output wire [31:0] o_write_result_epoch,
    output wire o_write_result_camera,
    output wire [15:0] o_write_result_slot,
    output wire [31:0] o_write_result_generation,
    output wire [24:0] o_write_result_payload_length,
    output wire [31:0] o_write_result_tag,

    // 待发送帧描述
    output wire o_ready_valid,
    input wire i_ready_claim,
    output wire [31:0] o_capture_id,
    output wire [24:0] o_payload_length,
    output wire [15:0] o_width,
    output wire [15:0] o_height,
    output wire [63:0] o_timestamp_ns,

    // 载荷输出流
    output wire [127:0] o_payload_tdata,
    output wire [15:0] o_payload_tkeep,
    output wire o_payload_tvalid,
    input wire i_payload_tready,
    output wire o_payload_tlast,

    // 错误与统计
    output reg o_drop_pulse,
    output reg o_read_done_pulse,
    output reg [7:0] o_error_code,
    output reg o_stream_recovery_required, // 读取故障后禁止继续发布帧
    output wire [3:0] o_state,
    output reg [15:0] o_wr_burst_count,
    output reg [15:0] o_rd_burst_count,
    output reg [15:0] o_berr_count,
    output reg [15:0] o_rerr_count,
    output reg [15:0] o_drop_count,
    output reg [27:0] o_last_error_addr,

    // AXI写地址
    output wire [3:0] o_axi_awid,
    output wire [27:0] o_axi_awaddr,
    output wire [7:0] o_axi_awlen,
    output wire [2:0] o_axi_awsize,
    output wire [1:0] o_axi_awburst,
    output wire o_axi_awvalid,
    input wire i_axi_awready,

    // AXI写数据
    output wire [127:0] o_axi_wdata,
    output wire [15:0] o_axi_wstrb,
    output wire o_axi_wlast,
    output wire o_axi_wvalid,
    input wire i_axi_wready,

    // AXI写响应
    input wire [3:0] i_axi_bid,
    input wire [1:0] i_axi_bresp,
    input wire i_axi_bvalid,
    output wire o_axi_bready,

    // AXI读地址
    output wire [3:0] o_axi_arid,
    output wire [27:0] o_axi_araddr,
    output wire [7:0] o_axi_arlen,
    output wire [2:0] o_axi_arsize,
    output wire [1:0] o_axi_arburst,
    output wire o_axi_arvalid,
    input wire i_axi_arready,

    // AXI读数据
    input wire [3:0] i_axi_rid,
    input wire [127:0] i_axi_rdata,
    input wire [1:0] i_axi_rresp,
    input wire i_axi_rlast,
    input wire i_axi_rvalid,
    output wire o_axi_rready,
    // All identity/control/retirement ports belong to i_clk (DFI), not PCIe.
    input wire [31:0] i_session_id, i_mode_epoch,
    input wire i_camera_id,
    input wire [7:0] i_quality, i_result_quality,
    input wire [31:0] i_result_epoch,
    output wire [15:0] o_slot_id,
    output wire [31:0] o_generation, o_session_id, o_mode_epoch,
    output wire o_camera_id,
    output wire [7:0] o_quality,
    input wire i_retire_valid,
    output wire o_retire_ready,
    input wire [31:0] i_retire_session, i_retire_generation,
    input wire [15:0] i_retire_slot,
    input wire i_retire_error,
    output reg o_retire_rsp_valid,
    input wire i_retire_rsp_ready,
    output reg [3:0] o_retire_rsp_code,
    output wire o_read_complete,
    // True DFI local record ownership/drain proof; READY is not quiet.
    output wire o_record_quiescent,
    output wire o_write_quiescent,
    output reg o_read_error,
    input wire i_req_valid,
    output wire o_req_ready,
    input wire [1:0] i_req_op,
    input wire i_req_camera,
    input wire [15:0] i_req_slot,
    input wire [31:0] i_req_generation, i_req_session,
    output reg o_rsp_valid,
    input wire i_rsp_ready,
    output reg [3:0] o_rsp_code,
    output reg [15:0] o_rsp_slot,
    output reg [31:0] o_rsp_generation, o_rsp_session, o_rsp_epoch, o_rsp_capture_id,
    output reg o_rsp_camera,
    output reg [7:0] o_rsp_quality,
    output reg [15:0] o_rsp_width, o_rsp_height,
    output reg [24:0] o_rsp_payload_length,
    output reg o_rsp_pinned,
    output reg [2:0] o_rsp_state,
    // Optional mask: allocation is an atomic START take, not a second owner.
    input wire i_start_mask,i_mask_allocation_ready,
    input wire [2:0] i_start_source_type,
    output wire o_mask_allocation_valid,
    output wire [15:0] o_mask_allocation_slot,
    output wire [31:0] o_mask_allocation_generation,
    output wire [27:0] o_mask_allocation_base,
    output wire [24:0] o_mask_allocation_bytes,
    input wire i_mask_result_valid,
    output wire o_mask_result_ready,
    input wire [159:0] i_mask_result_context,
    input wire [31:0] i_mask_result_tag,i_mask_result_generation,
    input wire [15:0] i_mask_result_slot,
    input wire i_mask_result_ok,
    input wire [7:0] i_mask_result_error,
    input wire [12:0] i_mask_result_width,i_mask_result_height,
    input wire [16:0] i_mask_result_written_bytes,
    input wire [47:0] i_mask_result_terminal_body,
    input wire i_req_mask,i_req_read_lock,i_mask_read_lease_release,
    output wire o_mask_read_lease_active,
    output reg o_rsp_read_authorized,
    output reg o_rsp_mask_present,o_rsp_mask_pinned,
    output wire [27:0] o_rsp_mask_tail_base
);

    localparam integer SLOT_COUNT=CAMERA_COUNT*3;
    localparam integer AGE_BITS=CAMERA_COUNT==1 ? 2 : 3;
    localparam [AGE_BITS-1:0] YOUNGEST_RANK=SLOT_COUNT-1;
    generate if(CAMERA_COUNT!=1 && CAMERA_COUNT!=2)begin:g_invalid_camera_count
        JPEG_RING_REQUIRES_ONE_OR_TWO_CAMERAS invalid_camera_count();
    end endgenerate
    localparam [2:0] EMPTY=0, COMMITTED=1, WRITING=2, ABORTED=3, SENDING=4;
    localparam [3:0] W_IDLE=0,W_COLLECT=1,W_AW=2,W_DATA=3,W_B=4,W_FINAL=5,W_DRAIN=6;
    localparam [2:0] R_IDLE=0,R_AR=1,R_DATA=2,R_HOLD=3,R_PREPARE=4,R_BURST=5,R_CLAIM=6;
    localparam [2:0] Q_IDLE=0,Q_SCAN=1,Q_SNAPSHOT=2,Q_CHECK=3,Q_VERIFY=4,Q_COMMIT=5;
    localparam [1:0] S_IDLE=0,S_SCAN=1,S_VERIFY=2,S_READY=3;
    localparam [3:0] OK=0,NO_FRAME=1,STALE=2,BUSY=3,AXI_ERROR=5,INVALID=6;
    reg [2:0] slot_state [0:SLOT_COUNT-1];
    reg slot_pin [0:SLOT_COUNT-1], slot_pending [0:SLOT_COUNT-1];
    reg slot_pin_mask [0:SLOT_COUNT-1],slot_mask [0:SLOT_COUNT-1];
    reg [31:0] hot_generation,hot_session;
    reg [AGE_BITS-1:0] slot_stamp [0:SLOT_COUNT-1];
    wire [63:0] selected_slot_time;
    // One hot writer and one shared readback view. Queries keep their snapshot edge.
    reg [31:0] hot_id,hot_epoch;
    reg [15:0] hot_width,hot_height;
    reg [7:0] hot_quality;
    reg [24:0] hot_bytes;
    reg [SLOT_COUNT-1:0] cold_valid;
    wire [128:0] cold_read_ram;
    reg ready_prefetched,cold_dirty;
    wire ready_read_reservation;
    reg [3:0] ws;
    reg [2:0] rs;
    reg [2:0] writer,reader;
    reg [1:0] next_slot [0:CAMERA_COUNT-1];
    reg [27:0] wa,ra,ready_base;
    reg [127:0] input_data;
    reg [15:0] input_keep;
    reg input_valid,input_tail,input_keep_legal;
    reg [4:0] input_count;
    // Every accepted nonterminal JPEG transfer is a complete 16-byte
    // word. Only its terminal transfer may leave a low-four-bit tail.
    reg [20:0] input_full_words;
    reg [3:0] input_tail_bytes;
    wire [24:0] input_bytes={input_full_words,input_tail_bytes};
    reg [24:0] result_bytes,read_left;
    reg [4:0] staged,write_index,read_beats,read_index;
    reg write_bad,input_last,result_seen,result_good,read_bad;
    reg read_drain;
    reg [7:0] write_error;
    reg [31:0] writer_tag;
    reg writer_mask;
    reg [2:0] writer_source_type;
    wire [146:0] fifo_data;
    wire fifo_ready,fifo_valid,fifo_sr_done,fifo_rr_done;
    wire source_fire=i_jpeg_tvalid && o_jpeg_tready;
    wire input_consume=input_valid && ((ws==W_COLLECT && fifo_ready) || ws==W_DRAIN);
    wire result_fire=i_result_valid && o_result_ready;
    wire start_fire=i_start_valid && o_start_ready;
    wire mask_result_matches=writer_source_type[1:0]!=0 &&
        i_mask_result_context[159:120]=={16'd1,16'd0,8'd1} &&
        i_mask_result_context[119:112]=={6'd0,writer_source_type[1:0]} &&
        i_mask_result_context[111:104]=={7'd0,writer_source_type[2]} &&
        i_mask_result_context[95:0]==
        {hot_id,hot_epoch,hot_session} &&
        i_mask_result_context[103:96]==(writer>=3 ? 8'd1 : 8'd0) &&
        i_mask_result_tag==writer_tag && i_mask_result_slot=={13'd0,writer} &&
        i_mask_result_generation==hot_generation;
    wire mask_terminal=MASK_ENABLE==0 || !writer_mask ||
        (i_mask_result_valid && mask_result_matches);
    wire [24:0] mask_pixel_bytes=({1'b0,i_mask_result_terminal_body[24:1]}+25'd7)>>3;
    wire mask_shape_matches=i_mask_result_width==(({1'b0,hot_width}+17'd3)>>2) &&
        i_mask_result_height==(({1'b0,hot_height}+17'd3)>>2) &&
        i_mask_result_terminal_body[47] && i_mask_result_terminal_body[46:39]==0 &&
        !i_mask_result_terminal_body[0] && i_mask_result_terminal_body[24:1]!=0 &&
        mask_pixel_bytes<=65536 && {8'd0,i_mask_result_written_bytes}==mask_pixel_bytes;
    wire mask_good=i_mask_result_ok && mask_shape_matches;
    wire write_qualified=i_ddr_ready && !write_bad && result_good && input_last &&
                         input_bytes!=0 && result_bytes==input_bytes &&
                         (!writer_mask || mask_good);
    wire data_legal;
    wire fifo_push=input_consume && ws==W_COLLECT && data_legal;
    wire fifo_pop=(ws==W_DATA && o_axi_wvalid && i_axi_wready) || (ws==W_DRAIN && fifo_valid);
    reg [4:0] collect_limit,read_limit;
    // An accepted legal KEEP is a nonempty low-byte prefix. Decode
    // its final byte directly. Illegal masks still fail input_keep_legal.
    wire [15:0] keep_end=i_jpeg_tkeep & ~{1'b0,i_jpeg_tkeep[15:1]};
    wire [4:0] keep_bytes={keep_end[15],|(keep_end & 16'h7f80),
        |(keep_end & 16'h7878),|(keep_end & 16'h6666),|(keep_end & 16'h5555)};
    reg [15:0] expected_keep;
    integer a,b,allocation,snapshot_index;
    reg [1:0] allocation_local;
    reg [2:0] allocation_available;
    reg [2:0] ready_slot,request_slot,ready_scan,request_scan;
    wire [128:0] cold_ready=cold_valid[ready_slot] ? cold_read_ram : 129'd0;
    wire [128:0] cold_query=cold_valid[request_slot] ? cold_read_ram : 129'd0;
    reg [1:0] select_state,req_op;
    reg [2:0] request_state;
    reg req_camera,req_latest,request_found,ready_found,req_mask,req_read_lock,mask_read_lease;
    reg [15:0] req_slot;
    reg [31:0] req_generation,req_session;
    reg [AGE_BITS-1:0] request_best_stamp,ready_best_stamp;
    reg [SLOT_COUNT-1:0] request_candidates,request_pins,ready_candidates;
    reg [AGE_BITS-1:0] request_stamps[0:SLOT_COUNT-1],ready_stamps[0:SLOT_COUNT-1];
    integer age_slot;
    reg [3:0] pending_code;
    reg [31:0] ready_id,ready_generation,ready_session,ready_epoch;
    reg [24:0] ready_bytes;
    reg [15:0] ready_width,ready_height;
    reg [63:0] ready_time;
    reg [7:0] ready_quality;
    reg [4:0] read_candidate_beats,read_boundary_beats;
    reg config_ok;
    reg [3:0] request_code;
    reg [32:0] interval_a,interval_b;
    // Timestamp is written exactly at START and read only for a committed
    // READY candidate. State reset prevents any uninitialized RAM read from
    // reaching ready_time; the held public descriptor still uses that FF.
    PH1_LOGIC_DRAM #(
        .DATA_WIDTH_W(64),.ADDR_WIDTH_W(4),.DATA_DEPTH_W(16),
        .DATA_WIDTH_R(64),.ADDR_WIDTH_R(4),.DATA_DEPTH_R(16),
        .INIT_FILE("NONE"),.FILL_ALL("NONE"),
        .READREG("DISABLE"),.RESETMODE("SYNC")
    ) u_slot_timestamps (
        .di(i_timestamp_ns),.waddr({1'b0,allocation[2:0]}),
        .we(i_rst_n && ws==W_IDLE && start_fire),.wclk(i_clk),
        .raddr({1'b0,ready_slot}),.rdo(selected_slot_time),.rdoq(),
        .rclk(i_clk),.rrst(1'b0),.rce(1'b0)
    );
    wire [SLOT_COUNT-1:0] record_slot_quiet;
    wire [SLOT_COUNT-1:0] slot_pending_vector;
    genvar quiet_slot;
    generate for(quiet_slot=0;quiet_slot<SLOT_COUNT;quiet_slot=quiet_slot+1) begin : g_record_quiet
        assign record_slot_quiet[quiet_slot]=slot_state[quiet_slot]!=WRITING &&
            slot_state[quiet_slot]!=SENDING && !slot_pending[quiet_slot];
        assign slot_pending_vector[quiet_slot]=slot_pending[quiet_slot];
    end endgenerate
    // staged covers every accepted legal FIFO push until the corresponding
    // W burst's final real pop, or each real drain pop. It cannot reach zero
    // merely because an accepted word has not yet crossed the FIFO pointers.
    // Keep the Stage3 writer-only terminal proof. READY/host-read ownership is
    // independent; all accepted staging words and real final B must be quiet.
    assign o_write_quiescent=i_rst_n&&!o_stream_recovery_required&&ws==W_IDLE&&
        !o_write_result_valid&&fifo_sr_done&&fifo_rr_done&&staged==0&&!fifo_valid&&!input_valid&&!i_start_valid;
    assign o_record_quiescent=i_rst_n && !cold_dirty && !o_stream_recovery_required &&
        ws==W_IDLE && rs==R_IDLE && !mask_read_lease && select_state==S_IDLE && request_state==Q_IDLE &&
        !o_write_result_valid && !o_rsp_valid && !o_retire_rsp_valid &&
        fifo_sr_done && fifo_rr_done && staged==0 && !fifo_valid && !input_valid &&
        (&record_slot_quiet) && !i_start_valid && !i_ready_claim &&
        !i_req_valid && !i_retire_valid;
    wire [2:0] camera_one_available;
    wire [1:0] allocation_rotation;
    generate if(CAMERA_COUNT==2)begin:g_dual_allocation
        assign camera_one_available={!slot_pin[5] && (slot_state[5]==EMPTY || slot_state[5]==ABORTED),
            !slot_pin[4] && (slot_state[4]==EMPTY || slot_state[4]==ABORTED),
            !slot_pin[3] && (slot_state[3]==EMPTY || slot_state[3]==ABORTED)};
        assign allocation_rotation=next_slot[i_camera_id];
    end else begin:g_mono_allocation
        assign camera_one_available=3'b000;
        assign allocation_rotation=next_slot[0];
    end endgenerate
    // The only zero result of a 32-bit increment comes from all ones.
    // Higher bits already wrap to zero; only bit zero needs the skip-zero fix.
    function [31:0] increment_generation;
        input [31:0] value;
        reg [30:0] upper;
        begin
            upper=value[31:1]+value[0];
            increment_generation={upper,!value[0] || (&value)};
        end
    endfunction
    // Tiny cold catalogs have no payload reset. The existing cold_valid
    // vector has exactly the original per-slot reset/first-START lifetime.
    // Allocation, READY and QUERY have independent asynchronous views. A
    // late camera/allocation change cannot enter the cold QUERY read-CE cone.
    wire [31:0] allocation_generation_raw;
    wire [63:0] ready_identity_raw,query_identity_raw;
    // This private view stores the NEXT generation, prepared from the
    // registered writer. A first START still uses one after any reset.
    wire [31:0] next_generation=cold_valid[allocation[2:0]] ? allocation_generation_raw : 32'd1;
    wire [63:0] ready_identity=cold_valid[ready_slot] ? ready_identity_raw : 64'd0;
    wire [2:0] identity_query_slot=request_state==Q_SCAN ? request_scan : request_slot;
    wire [63:0] query_identity=cold_valid[identity_query_slot] ? query_identity_raw : 64'd0;
    wire [31:0] following_generation=increment_generation(hot_generation);
    PH1_LOGIC_DRAM #(
        .DATA_WIDTH_W(32),.ADDR_WIDTH_W(4),.DATA_DEPTH_W(16),
        .DATA_WIDTH_R(32),.ADDR_WIDTH_R(4),.DATA_DEPTH_R(16),
        .INIT_FILE("NONE"),.FILL_ALL("NONE"),.READREG("DISABLE"),.RESETMODE("SYNC")
    ) u_allocation_generation (
        // cold_dirty flushes the retained writer one edge after START.
        // No other START can be admitted while this writer is active;
        // RESULT/COMMIT flushes repeat the same successor harmlessly.
        .di(following_generation),.waddr({1'b0,writer}),.we(cold_dirty),.wclk(i_clk),
        .raddr({1'b0,allocation[2:0]}),.rdo(allocation_generation_raw),.rdoq(),
        .rclk(i_clk),.rrst(1'b0),.rce(1'b0));
    PH1_LOGIC_DRAM #(
        .DATA_WIDTH_W(64),.ADDR_WIDTH_W(4),.DATA_DEPTH_W(16),
        .DATA_WIDTH_R(64),.ADDR_WIDTH_R(4),.DATA_DEPTH_R(16),
        .INIT_FILE("NONE"),.FILL_ALL("NONE"),.READREG("DISABLE"),.RESETMODE("SYNC")
    ) u_ready_identity (
        .di({next_generation,i_session_id}),.waddr({1'b0,allocation[2:0]}),.we(start_fire),.wclk(i_clk),
        .raddr({1'b0,ready_slot}),.rdo(ready_identity_raw),.rdoq(),
        .rclk(i_clk),.rrst(1'b0),.rce(1'b0));
    PH1_LOGIC_DRAM #(
        .DATA_WIDTH_W(64),.ADDR_WIDTH_W(4),.DATA_DEPTH_W(16),
        .DATA_WIDTH_R(64),.ADDR_WIDTH_R(4),.DATA_DEPTH_R(16),
        .INIT_FILE("NONE"),.FILL_ALL("NONE"),.READREG("DISABLE"),.RESETMODE("SYNC")
    ) u_query_identity (
        .di({next_generation,i_session_id}),.waddr({1'b0,allocation[2:0]}),.we(start_fire),.wclk(i_clk),
        .raddr({1'b0,identity_query_slot}),.rdo(query_identity_raw),.rdoq(),
        .rclk(i_clk),.rrst(1'b0),.rce(1'b0));
    function [27:0] base;
        input integer slot;
        begin case(slot)
            0:base=SLOT0_BASE; 1:base=SLOT1_BASE; 2:base=SLOT2_BASE;
            3:base=SLOT3_BASE; 4:base=SLOT4_BASE; default:base=SLOT5_BASE;
        endcase end
    endfunction
    function [15:0] sat_inc;
        input [15:0] value;
        begin sat_inc=value==16'hffff ? value : value+1'b1; end
    endfunction
    always @(*) begin
        config_ok=SLOT_BYTES>=16 && SLOT_BYTES<=32'h01000000 && SLOT_BYTES[3:0]==0;
        interval_a=0; interval_b=0;
        for(a=0;a<6;a=a+1) begin
            interval_a={5'd0,base(a)}+SLOT_BYTES;
            if((base(a)&28'hf)!=0 || interval_a>33'h010000000) config_ok=0;
            for(b=0;b<6;b=b+1) begin
                interval_b={5'd0,base(b)}+SLOT_BYTES;
                if(a!=b && {5'd0,base(a)}<interval_b && {5'd0,base(b)}<interval_a) config_ok=0;
            end
        end
        allocation=-1;
        allocation_local=0;
        if(i_camera_id)begin
            allocation_available=camera_one_available;
        end else begin
            allocation_available={!slot_pin[2] && (slot_state[2]==EMPTY || slot_state[2]==ABORTED),
                !slot_pin[1] && (slot_state[1]==EMPTY || slot_state[1]==ABORTED),
                !slot_pin[0] && (slot_state[0]==EMPTY || slot_state[0]==ABORTED)};
        end
        // Exactly three entries per camera: explicit rotations avoid the
        // previous integer-width modulo network in both allocation and advance.
        case(allocation_rotation)
            1: begin
                if(allocation_available[1]) allocation_local=1;
                else if(allocation_available[2]) allocation_local=2;
                else allocation_local=0;
            end
            2: begin
                if(allocation_available[2]) allocation_local=2;
                else if(allocation_available[0]) allocation_local=0;
                else allocation_local=1;
            end
            default: begin
                if(allocation_available[0]) allocation_local=0;
                else if(allocation_available[1]) allocation_local=1;
                else allocation_local=2;
            end
        endcase
        if(|allocation_available) allocation=i_camera_id ? {30'd0,allocation_local}+32'd3 : {30'd0,allocation_local};
        collect_limit=16;
        if(wa[11:4]>8'hf0) collect_limit=9'd256-{1'b0,wa[11:4]};
        read_limit=read_candidate_beats<read_boundary_beats ? read_candidate_beats : read_boundary_beats;
        // Full beats use all lanes; a tail only needs the four low count bits.
        // Keep the 25-bit byte counter out of the tail-mask subtract/shift cone.
        expected_keep=(|read_left[24:4]) ? 16'hffff : ~(16'hffff << read_left[3:0]);
        request_code=OK;
        if(req_op>2 || (req_slot>=SLOT_COUNT && !req_latest) || (req_op==1 && req_generation==0)) request_code=INVALID;
        else if(req_latest && !request_found) request_code=NO_FRAME;
        else if(req_op==0) request_code=OK;
        else if(o_rsp_state==WRITING || o_rsp_state==SENDING) request_code=BUSY;
        else if(o_rsp_generation!=req_generation) request_code=STALE;
        else if(o_rsp_session!=req_session || o_rsp_camera!=req_camera) request_code=STALE;
        else if(o_rsp_state!=COMMITTED && !(req_op==2 && o_rsp_pinned)) request_code=NO_FRAME;
        if(req_mask && !o_rsp_mask_present && request_code==OK) request_code=NO_FRAME;
        if(req_op!=0 && o_rsp_pinned && slot_pin_mask[request_slot]!=req_mask && request_code==OK)
            request_code=BUSY;
        if(req_op!=0 && mask_read_lease && request_code==OK)request_code=BUSY;
        if(req_read_lock && request_code==OK) begin
            if(!req_mask || req_op!=0 || req_latest) request_code=INVALID;
            else if(o_rsp_state==SENDING || o_rsp_state==WRITING || rs!=R_IDLE || mask_read_lease) request_code=BUSY;
            else if(o_rsp_state!=COMMITTED || !o_rsp_mask_pinned) request_code=NO_FRAME;
            else if(o_rsp_generation!=req_generation || o_rsp_session!=req_session || o_rsp_camera!=req_camera)
                request_code=STALE;
        end
    end
    wire start_mask=MASK_ENABLE!=0 && i_start_mask;
    wire [20:0] capacity_words=SLOT_BYTES[24:4]-(writer_mask ? 21'd4096 : 21'd0);
    assign data_legal=input_keep_legal && input_full_words<capacity_words;
    wire read_response_bad=i_axi_rid!=0 || i_axi_rresp!=0 || i_axi_rlast!=(read_index==read_beats-1'b1);
    assign o_start_ready=i_rst_n && i_ddr_ready && config_ok && !o_stream_recovery_required &&
                         ws==W_IDLE && allocation>=0 && fifo_sr_done && fifo_rr_done && !fifo_valid && !input_valid &&
                         (WRITE_RESULT_ENABLE==0 || !o_write_result_valid) &&
                         !i_req_valid && request_state==Q_IDLE && !i_retire_valid &&
                         (!i_start_valid || !start_mask ||
                          (SLOT_BYTES>65536 && i_mask_allocation_ready));
    // Before CONTEXT arrives READY is a slot-credit probe. Gating that probe
    // on a mask BEGIN which itself needs admission would deadlock the owner.
    assign o_mask_allocation_valid=start_fire && start_mask;
    assign o_mask_allocation_slot=allocation<0 ? 16'hffff : allocation;
    assign o_mask_allocation_generation=allocation<0 ? 32'd0 :
        next_generation;
    assign o_mask_allocation_base=base(allocation);
    assign o_mask_allocation_bytes=SLOT_BYTES[24:0];
    assign o_mask_result_ready=MASK_ENABLE!=0 && writer_mask && result_seen &&
        ((ws==W_FINAL)||(ws==W_DRAIN && staged==0 && !fifo_valid)) && mask_result_matches;
    assign o_jpeg_tready=i_rst_n && ws!=W_IDLE && !result_seen &&
        (!input_valid || (input_consume && !input_tail)) && !input_last;
    assign o_result_ready=i_rst_n && ws!=W_IDLE && !result_seen;
    wire ready_identity_ok=slot_state[ready_slot]==COMMITTED && slot_pending[ready_slot] &&
                           ready_identity[63:32]==ready_generation && ready_identity[31:0]==ready_session;
    assign o_ready_valid=i_rst_n && rs==R_IDLE && select_state==S_READY &&
                         ready_identity_ok && !o_stream_recovery_required;
    wire mask_read_grant=MASK_ENABLE!=0 && request_state==Q_COMMIT && pending_code==OK && req_read_lock &&
        rs==R_IDLE && !mask_read_lease && select_state!=S_READY &&
        slot_state[request_slot]==COMMITTED && slot_pin[request_slot] && slot_pin_mask[request_slot];
    assign o_mask_read_lease_active=MASK_ENABLE!=0 && mask_read_lease;
    assign o_rsp_mask_tail_base=MASK_ENABLE!=0 && o_rsp_mask_present ?
        base(o_rsp_slot)+SLOT_BYTES-32'd65536 : 28'd0;
    assign o_capture_id=ready_id;
    assign o_payload_length=ready_bytes;
    assign o_width=ready_width; assign o_height=ready_height;
    assign o_timestamp_ns=ready_time;
    assign o_slot_id=ready_slot; assign o_generation=ready_generation;
    assign o_session_id=ready_session; assign o_mode_epoch=ready_epoch;
    assign o_camera_id=ready_slot>=3; assign o_quality=ready_quality;
    assign o_state=ws;
    assign o_read_complete=i_rst_n && rs==R_HOLD;
    // Decode the retained read owner before the late retirement window.
    // Keep the R_HOLD transition local to the reader FSM; no failed-request
    // response priority chain belongs in the state-update cone.
    wire retire_slot_live=i_retire_slot<SLOT_COUNT && rs!=R_IDLE;
    wire retire_identity_match=i_retire_slot==reader &&
        i_retire_session==ready_session && i_retire_generation==ready_generation;
    wire retire_complete=retire_slot_live && retire_identity_match && rs==R_HOLD;
    wire retire_fire=i_retire_valid && o_retire_ready;
    assign o_retire_ready=i_rst_n && !o_retire_rsp_valid && !start_fire && ws!=W_FINAL && ws!=W_DRAIN;
    assign o_req_ready=i_rst_n && request_state==Q_IDLE && !ready_read_reservation && !o_rsp_valid && !start_fire && !i_ready_claim && !i_retire_valid &&
                       ws!=W_FINAL && ws!=W_DRAIN;
    assign o_axi_awid=0; assign o_axi_awaddr=wa; assign o_axi_awlen=staged-1'b1;
    assign o_axi_awsize=4; assign o_axi_awburst=1; assign o_axi_awvalid=i_rst_n && ws==W_AW;
    assign o_axi_wdata=fifo_data[127:0]; assign o_axi_wstrb=fifo_data[143:128];
    assign o_axi_wlast=write_index==staged-1'b1; assign o_axi_wvalid=i_rst_n && ws==W_DATA && fifo_valid;
    assign o_axi_bready=i_rst_n && ws==W_B;
    assign o_axi_arid=0; assign o_axi_araddr=ra; assign o_axi_arlen=read_beats-1'b1;
    assign o_axi_arsize=4; assign o_axi_arburst=1; assign o_axi_arvalid=i_rst_n && rs==R_AR;
    assign o_payload_tdata=i_axi_rdata; assign o_payload_tkeep=expected_keep;
    assign o_payload_tlast=read_left<=16;
    assign o_payload_tvalid=i_rst_n && rs==R_DATA && i_axi_rvalid && !read_bad && !read_response_bad;
    // Invalid response metadata suppresses payload immediately, then grants a
    // registered drain credit if the consumer is stalled. This cuts the burst
    // shape comparison out of the arbiter response RAM's read-enable cone.
    assign o_axi_rready=i_rst_n && rs==R_DATA && (read_bad || read_drain || i_payload_tready);
    // Same-clock, non-overlapping collection and AXI write phases.
    // At most sixteen accepted words are retained. LAST is already recorded
    // by input_last/staged, so only payload and WSTRB need storage.
    // The asynchronous read has no added W pipeline stage: a held W beat keeps
    // its address, and every W handshake advances to the next word in one cycle.
    (* ram_style="dram" *) reg [127:0] staging_words [0:15];
    always @(posedge i_clk)begin
        if(fifo_push)staging_words[staged[3:0]]<=input_data;
    end
    // Input LAST prevents another capture until this frame is drained.
    // Its held KEEP belongs to the final word of the final accepted burst.
    wire [15:0] write_strobe=input_last && o_axi_wlast ? input_keep : 16'hffff;
    assign fifo_data={3'd0,write_strobe,staging_words[write_index[3:0]]};
    assign fifo_ready=staged<16;
    assign fifo_valid=staged!=0;
    assign fifo_sr_done=i_rst_n;
    assign fifo_rr_done=i_rst_n;
    // Predict the exact slot chosen on the final scan edge. The official
    // synchronous RAM return is available for the unchanged next snapshot
    // edge. Re-read while S_VERIFY is held by a MASK lease.
    wire cold_ready_take=ready_candidates[ready_scan] &&
        (!ready_found || ready_stamps[ready_scan]<ready_best_stamp);
    wire cold_query_take=request_candidates[request_scan] &&
        query_identity[31:0]==req_session &&
        (!request_found || request_stamps[request_scan]>request_best_stamp);
    wire [2:0] cold_ready_address=(select_state==S_SCAN && cold_ready_take) ? ready_scan : ready_slot;
    wire [2:0] cold_query_address=request_state==Q_IDLE ?
        (i_req_slot<SLOT_COUNT ? i_req_slot[2:0] : 3'd0) :
        ((request_state==Q_SCAN && cold_query_take) ? request_scan : request_slot);
    // Reserve only the last READY scan edge or one retry after a collision.
    // Idle QUERY prefetch has the original address/CE timing. A new host request
    // waits one cycle when that read port is reserved; an already active latest
    // query finishes its final scan without resampling candidate identities.
    wire latest_return=request_state==Q_SCAN && request_scan==SLOT_COUNT-1;
    wire want_ready=(select_state==S_SCAN && ready_scan==SLOT_COUNT-1) ||
                    (select_state==S_VERIFY && !ready_prefetched);
    assign ready_read_reservation=want_ready && !latest_return;
    always @(posedge i_clk or negedge i_rst_n)begin
        if(!i_rst_n)ready_prefetched<=0;
        else ready_prefetched<=ready_read_reservation && !start_fire;
    end
    wire cold_commit=ws==W_FINAL && result_seen && mask_terminal && write_qualified;
    // Data belongs to the registered writer. Flush its latest tuple on the
    // following clock, including the final commit before that slot is reused.
    // Forward this hot tuple on same-slot reads. QUERY admission excludes
    // START and READY refetches across START so a forwarded value never
    // changes owners before its consumer takes the registered RAM return.
    always @(posedge i_clk or negedge i_rst_n)begin
        if(!i_rst_n)cold_dirty<=0;
        else cold_dirty<=start_fire || result_fire || cold_commit;
    end
    // A pending write result blocks START. The current writer identity and
    // input byte total therefore remain immutable through its final handshake.
    // QUERY and RETIRE change slot state/pins, never its generation or session.
    assign o_write_result_capture_id=WRITE_RESULT_ENABLE!=0 ? (hot_id) : 32'd0;
    assign o_write_result_session=WRITE_RESULT_ENABLE!=0 ? (hot_session) : 32'd0;
    assign o_write_result_epoch=WRITE_RESULT_ENABLE!=0 ? (hot_epoch) : 32'd0;
    assign o_write_result_camera=WRITE_RESULT_ENABLE!=0 ? (writer>=3) : 1'd0;
    assign o_write_result_slot=WRITE_RESULT_ENABLE!=0 ? ({13'd0,writer}) : 16'd0;
    assign o_write_result_generation=WRITE_RESULT_ENABLE!=0 ? (hot_generation) : 32'd0;
    assign o_write_result_payload_length=WRITE_RESULT_ENABLE!=0 ? (o_write_result_ok ? input_bytes : 25'd0) : 25'd0;
    assign o_write_result_tag=WRITE_RESULT_ENABLE!=0 ? (writer_tag) : 32'd0;

    wire [128:0] cold_hot={hot_quality,hot_bytes,hot_height,hot_width,hot_epoch,hot_id};
    always @(posedge i_clk or negedge i_rst_n)begin
        if(!i_rst_n)cold_valid<=0;
        else if(start_fire)cold_valid[allocation]<=1;
    end
    jpeg_ring_cold_bank #(.FORWARD_LIVE_WRITER(1)) cold_bank(
        .clk(i_clk),.rst_n(i_rst_n),.write_enable({4{cold_dirty}}),
        .write_address(writer),.write_data(cold_hot),.hot_data(cold_hot),
        .read_enable(i_rst_n&&(request_state==Q_IDLE||latest_return||want_ready)),
        .read_address(ready_read_reservation?cold_ready_address:cold_query_address),.read_data(cold_read_ram));
    integer reset_index;
    always @(posedge i_clk or negedge i_rst_n) begin
        if(!i_rst_n) begin
            hot_id<=0;hot_epoch<=0;hot_width<=0;hot_height<=0;hot_quality<=0;hot_bytes<=0;
            hot_generation<=0;hot_session<=0;
            ws<=W_IDLE;rs<=R_IDLE;writer<=0;reader<=0;wa<=0;ra<=0;ready_base<=0;
            input_valid<=0;input_tail<=0;input_keep_legal<=0;input_count<=0;
            input_full_words<=0;input_tail_bytes<=0;result_bytes<=0;read_left<=0;staged<=0;
            write_index<=0;read_beats<=0;read_index<=0;write_bad<=0;input_last<=0;
            result_seen<=0;result_good<=0;read_bad<=0;read_drain<=0;write_error<=0;
            o_write_result_valid<=0;o_write_result_ok<=0;o_write_result_error<=0;
            
            
            
            writer_tag<=0;writer_mask<=0;writer_source_type<=0;
            for(reset_index=0;reset_index<CAMERA_COUNT;reset_index=reset_index+1)next_slot[reset_index]<=0;
            o_drop_pulse<=0;o_read_done_pulse<=0;o_error_code<=0;o_stream_recovery_required<=0;
            o_wr_burst_count<=0;o_rd_burst_count<=0;o_berr_count<=0;o_rerr_count<=0;
            o_drop_count<=0;o_last_error_addr<=0;o_read_error<=0;
            o_rsp_valid<=0;o_rsp_code<=0;o_rsp_slot<=0;o_rsp_generation<=0;o_rsp_session<=0;
            o_rsp_epoch<=0;o_rsp_capture_id<=0;o_rsp_camera<=0;o_rsp_quality<=0;
            o_rsp_width<=0;o_rsp_height<=0;o_rsp_payload_length<=0;o_rsp_pinned<=0;o_rsp_state<=0;
            o_rsp_mask_present<=0;o_rsp_mask_pinned<=0;
            o_rsp_read_authorized<=0;mask_read_lease<=0;
            o_retire_rsp_valid<=0;o_retire_rsp_code<=0;
            request_state<=Q_IDLE;req_op<=0;req_camera<=0;req_latest<=0;req_slot<=0;req_mask<=0;req_read_lock<=0;
            req_generation<=0;req_session<=0;request_slot<=0;request_scan<=0;
            request_found<=0;request_best_stamp<=0;request_candidates<=0;request_pins<=0;pending_code<=OK;
            select_state<=S_IDLE;ready_slot<=0;ready_scan<=0;ready_found<=0;
            ready_candidates<=0;ready_best_stamp<=0;
            ready_id<=0;ready_generation<=0;ready_session<=0;ready_epoch<=0;
            ready_bytes<=0;ready_width<=0;ready_height<=0;ready_time<=0;ready_quality<=0;
            read_candidate_beats<=0;read_boundary_beats<=0;
            for(reset_index=0;reset_index<SLOT_COUNT;reset_index=reset_index+1) begin
                slot_state[reset_index]<=EMPTY;slot_pin[reset_index]<=0;slot_pending[reset_index]<=0;
                slot_pin_mask[reset_index]<=0;slot_mask[reset_index]<=0;

                slot_stamp[reset_index]<=0;
                
                
                request_stamps[reset_index]<=0;ready_stamps[reset_index]<=0;
            end
        end else begin
            read_drain<=rs==R_DATA && i_axi_rvalid && read_response_bad;
            o_drop_pulse<=0;o_read_done_pulse<=0;
            if(input_consume)input_valid<=0;
            if(source_fire)begin
                input_valid<=1;input_data<=i_jpeg_tdata;input_keep<=i_jpeg_tkeep;
                input_tail<=i_jpeg_tlast;input_count<=keep_bytes;
                input_keep_legal<=i_jpeg_tkeep[0] &&
                    !(|(i_jpeg_tkeep[15:1] & ~i_jpeg_tkeep[14:0])) &&
                    (i_jpeg_tlast || i_jpeg_tkeep==16'hffff);
            end
            if(o_write_result_valid && i_write_result_ready) o_write_result_valid<=0;
            if(o_rsp_valid && i_rsp_ready) o_rsp_valid<=0;
            if(MASK_ENABLE!=0 && i_mask_read_lease_release)mask_read_lease<=0;
            if(o_retire_rsp_valid && i_retire_rsp_ready) o_retire_rsp_valid<=0;
            if(!i_ddr_ready && (ws!=W_IDLE || rs!=R_IDLE)) begin
                o_stream_recovery_required<=1; o_error_code<=6;write_bad<=1;
                if(ws!=W_IDLE) write_error<=6;
            end
            if(result_fire) begin
                result_seen<=1;result_bytes<=i_result_length;
                result_good<=i_result_ok && i_result_id==hot_id && i_result_epoch==hot_epoch && i_result_quality==hot_quality;
                hot_quality<=i_result_quality;
            end
            // Automatic reader order uses ONE frozen oldest-pending snapshot.
            // Commits during this scan are left pending for the next scan.
            case(select_state)
                S_IDLE: if(rs==R_IDLE && !mask_read_lease && !mask_read_grant && !o_stream_recovery_required &&
                    (|slot_pending_vector)) begin
                    for(snapshot_index=0;snapshot_index<SLOT_COUNT;snapshot_index=snapshot_index+1) begin
                        ready_candidates[snapshot_index]<=slot_state[snapshot_index]==COMMITTED && slot_pending[snapshot_index];
                        ready_stamps[snapshot_index]<=slot_stamp[snapshot_index];
                    end
                    ready_scan<=0;ready_found<=0;ready_best_stamp<=0;select_state<=S_SCAN;
                end
                S_SCAN: begin
                    if(cold_ready_take) begin
                        ready_slot<=ready_scan;ready_best_stamp<=ready_stamps[ready_scan];ready_found<=1;
                    end
                    if(ready_scan==SLOT_COUNT-1) select_state<=S_VERIFY;
                    else ready_scan<=ready_scan+1'b1;
                end
                S_VERIFY: begin
                    if(!ready_prefetched || mask_read_lease || mask_read_grant)select_state<=S_VERIFY;
                    else if(ready_found && rs==R_IDLE && slot_state[ready_slot]==COMMITTED && slot_pending[ready_slot]) begin
                        ready_id<=cold_ready[31:0];ready_generation<=ready_identity[63:32];
                        ready_session<=ready_identity[31:0];ready_epoch<=cold_ready[63:32];
                        ready_bytes<=cold_ready[120:96];ready_width<=cold_ready[79:64];
                        ready_height<=cold_ready[95:80];ready_time<=selected_slot_time;
                        ready_quality<=cold_ready[128:121];ready_base<=base(ready_slot);select_state<=S_READY;
                    end else select_state<=S_IDLE;
                end
                S_READY: if((o_ready_valid && i_ready_claim) || !ready_identity_ok) select_state<=S_IDLE;
                default: select_state<=S_IDLE;
            endcase
            case(ws)
                W_IDLE: if(start_fire) begin
                    writer_tag<=WRITE_TAG_ENABLE!=0 ? i_write_tag : 32'd0;
                    writer_mask<=start_mask;slot_mask[allocation]<=0;
                    writer_source_type<=start_mask ? i_start_source_type : 3'd0;
                    writer<=allocation;slot_state[allocation]<=WRITING;slot_pending[allocation]<=0;
                    hot_generation<=next_generation;hot_session<=i_session_id;hot_epoch<=i_mode_epoch;
                    hot_id<=i_capture_id;hot_width<=i_width;
                    hot_height<=i_height;
                    hot_quality<=i_quality;hot_bytes<=0;
                    if(CAMERA_COUNT==1)next_slot[0]<=allocation_local==2 ? 0 : allocation_local+2'd1;
                    else next_slot[i_camera_id]<=allocation_local==2 ? 0 : allocation_local+2'd1;
                    wa<=base(allocation);input_full_words<=0;input_tail_bytes<=0;staged<=0;input_last<=0;
                    write_bad<=0;write_error<=0;result_seen<=0;result_good<=0;ws<=W_COLLECT;
                end
                W_COLLECT: begin
                    if(input_consume) begin
                        if(!data_legal) begin write_bad<=1;write_error<=1;ws<=W_DRAIN;o_error_code<=1;end
                        else begin
                            input_full_words<=input_full_words+input_keep[15];
                            input_tail_bytes<=input_count[3:0];
                            staged<=staged+1'b1;
                            if(input_tail) input_last<=1;
                            if(input_tail || staged+1'b1==collect_limit) begin
                                write_index<=0;ws<=W_AW;
                            end
                        end
                    end else if(result_seen && !input_valid) begin
                        write_bad<=1;ws<=W_DRAIN;o_error_code<=2;
                        if(write_error==0) write_error<=2;
                    end
                end
                W_AW: if(o_axi_awvalid && i_axi_awready) begin ws<=W_DATA;o_wr_burst_count<=sat_inc(o_wr_burst_count);end
                W_DATA: if(o_axi_wvalid && i_axi_wready) begin
                    write_index<=write_index+1'b1;
                    if(o_axi_wlast) begin ws<=W_B;staged<=0;end
                end
                W_B: if(i_axi_bvalid && o_axi_bready) begin
                    if(i_axi_bid!=0 || i_axi_bresp!=0) begin
                        write_bad<=1;write_error<=3;o_error_code<=3;o_berr_count<=sat_inc(o_berr_count);
                        o_last_error_addr<=wa;ws<=W_DRAIN;
                    end else if(input_last) ws<=W_FINAL;
                    else begin
                        // Only a nonterminal burst returns to COLLECT. Its
                        // accepted JPEG words were all full, so this is the
                        // address immediately after that real completed B.
                        wa<=base(writer)+{input_bytes[24:4],4'b0000};ws<=W_COLLECT;
                    end
                end
                W_FINAL: if(result_seen && mask_terminal) begin
                    if(write_qualified) begin
                        slot_state[writer]<=COMMITTED;slot_pending[writer]<=1;hot_bytes<=input_bytes;
                        // Remove the reused slot from the total age order and
                        // append it as youngest. Other slots keep their relative
                        // order, including pinned or already selected frames.
                        // Only successful COMMIT changes the order. Frozen scan
                        // snapshots remain unchanged during concurrent commits.
                        for(age_slot=0;age_slot<SLOT_COUNT;age_slot=age_slot+1) begin
                            if(age_slot==writer) slot_stamp[age_slot]<=YOUNGEST_RANK;
                            else if(slot_stamp[age_slot]>slot_stamp[writer])
                                slot_stamp[age_slot]<=slot_stamp[age_slot]-1'b1;
                        end
                        slot_mask[writer]<=writer_mask;
                    end else begin
                        slot_state[writer]<=ABORTED;o_drop_pulse<=1;o_drop_count<=sat_inc(o_drop_count);o_error_code<=2;
                    end
                    if(WRITE_RESULT_ENABLE!=0) begin
                        o_write_result_valid<=1;o_write_result_ok<=write_qualified;
                        o_write_result_error<=write_qualified ? 8'd0 :
                            (!i_ddr_ready ? 8'd6 : (write_error!=0 ? write_error :
                            (writer_mask && !mask_good ?
                            (i_mask_result_error==0 ? 8'd9 : i_mask_result_error) : 8'd2)));
                        
                        
                        
                        
                        
                        
                    end
                    ws<=W_IDLE;
                end
                W_DRAIN: begin
                    // No new payload is stored during drain. Discard each
                    // accepted staging word before releasing this writer.
                    if(fifo_valid && staged!=0) staged<=staged-1'b1;
                    if(result_seen && staged==0 && !fifo_valid && !input_valid && mask_terminal) begin
                        slot_state[writer]<=ABORTED;o_drop_pulse<=1;o_drop_count<=sat_inc(o_drop_count);
                        if(WRITE_RESULT_ENABLE!=0) begin
                            o_write_result_valid<=1;o_write_result_ok<=0;
                            o_write_result_error<=write_error!=0 ? write_error :
                                (writer_mask && !mask_good ?
                                (i_mask_result_error==0 ? 8'd9 : i_mask_result_error) : 8'd2);
                            
                            
                            
                            
                            
                        end
                        ws<=W_IDLE;
                    end
                end
                default: begin ws<=W_IDLE;o_stream_recovery_required<=1;end
            endcase
            case(rs)
                R_IDLE: if(o_ready_valid && i_ready_claim) begin
                    reader<=ready_slot;slot_state[ready_slot]<=SENDING;slot_pending[ready_slot]<=0;
                    o_read_error<=0;read_bad<=0;rs<=R_CLAIM;
                end
                R_CLAIM: begin
                    ra<=ready_base;read_left<=ready_bytes;read_index<=0;rs<=R_PREPARE;
                end
                R_PREPARE: begin
                    read_candidate_beats<=read_left>=256 ? 5'd16 :
                        {1'b0,read_left[7:4]}+(|read_left[3:0]);
                    read_boundary_beats<=ra[11:8]==4'hf ? 5'd16-{1'b0,ra[7:4]} : 5'd16;
                    rs<=R_BURST;
                end
                R_BURST: begin read_beats<=read_limit;rs<=R_AR;end
                R_AR: if(o_axi_arvalid && i_axi_arready) begin rs<=R_DATA;read_index<=0;o_rd_burst_count<=sat_inc(o_rd_burst_count);end
                R_DATA: if(i_axi_rvalid && o_axi_rready) begin
                    read_index<=read_index+1'b1;
                    ra<=ra+28'd16;
                    if(read_response_bad && !read_bad) begin
                        read_bad<=1;o_read_error<=1;o_error_code<=4;
                        o_rerr_count<=sat_inc(o_rerr_count);o_last_error_addr<=ra;
                        o_stream_recovery_required<=1;
                    end
                    if(!read_bad && !read_response_bad) read_left<=read_left-(read_left>=16 ? 25'd16 : read_left);
                    if(read_index==read_beats-1'b1) begin
                        if(read_bad || read_response_bad || read_left<=16) begin rs<=R_HOLD;o_read_done_pulse<=1;end
                        else begin
                            rs<=R_PREPARE;
                        end
                    end
                end
                R_HOLD: if(retire_fire && retire_complete)rs<=R_IDLE;
                default: begin end
            endcase
            if(retire_fire) begin
                o_retire_rsp_valid<=1;o_retire_rsp_code<=OK;
                if(!retire_slot_live) o_retire_rsp_code<=NO_FRAME;
                // CLAIM checked this frozen tuple against the live directory.
                // Selection cannot restart while the reader owns SENDING, so
                // RETIRE need not traverse a second variable directory mux.
                else if(!retire_identity_match) o_retire_rsp_code<=STALE;
                else if(rs!=R_HOLD) o_retire_rsp_code<=BUSY;
                else begin
                    if(o_read_error || i_retire_error) begin slot_state[reader]<=ABORTED;o_retire_rsp_code<=AXI_ERROR;end
                    else if(slot_pin[reader]) slot_state[reader]<=COMMITTED;
                    else slot_state[reader]<=EMPTY;
                    o_read_error<=0;read_bad<=0;
                end
            end
            case(request_state)
            Q_IDLE: begin
                // Scratch selection is invisible in IDLE. Initialize it from
                // the current bus every idle edge; accepted requests still
                // freeze the real tuple and directory snapshot on that edge.
                request_slot<=i_req_slot<SLOT_COUNT ? i_req_slot[2:0] : 0;
                request_found<=0;request_best_stamp<=0;
                if(i_req_valid && o_req_ready) begin
                    req_op<=i_req_op;req_camera<=i_req_camera;req_slot<=i_req_slot;
                    req_mask<=MASK_ENABLE!=0 && i_req_mask;
                    req_read_lock<=MASK_ENABLE!=0 && i_req_read_lock;
                    req_generation<=i_req_generation;req_session<=i_req_session;
                    req_latest<=i_req_op==0 && i_req_slot==16'hffff;
                    request_scan<=0;
                    for(snapshot_index=0;snapshot_index<SLOT_COUNT;snapshot_index=snapshot_index+1) begin
                        request_candidates[snapshot_index]<=(snapshot_index/3)==i_req_camera &&
                            (MASK_ENABLE==0 || !i_req_mask || slot_mask[snapshot_index]) &&
                            slot_state[snapshot_index]==COMMITTED;
                        request_stamps[snapshot_index]<=slot_stamp[snapshot_index];
                        request_pins[snapshot_index]<=slot_pin[snapshot_index];
                    end
                    if(CAMERA_COUNT==1 && (i_req_camera ||
                       (i_req_slot>=SLOT_COUNT && !(i_req_op==0 && i_req_slot==16'hffff))))begin
                        // Absent camera/global slots produce an explicit existing
                        // INVALID response without reading/truncating a cam0 tuple.
                        pending_code<=INVALID;request_state<=Q_COMMIT;
                        o_rsp_slot<=i_req_slot;o_rsp_camera<=i_req_camera;
                        o_rsp_generation<=0;o_rsp_session<=0;o_rsp_epoch<=0;o_rsp_capture_id<=0;
                        o_rsp_quality<=0;o_rsp_width<=0;o_rsp_height<=0;o_rsp_payload_length<=0;
                        o_rsp_pinned<=0;o_rsp_state<=EMPTY;o_rsp_mask_present<=0;
                        o_rsp_mask_pinned<=0;o_rsp_read_authorized<=0;
                    end else request_state<=i_req_op==0 && i_req_slot==16'hffff ? Q_SCAN : Q_SNAPSHOT;
                end
            end
            Q_SCAN: begin
                if(cold_query_take) begin
                    request_slot<=request_scan;request_best_stamp<=request_stamps[request_scan];request_found<=1;
                end
                if(request_scan==SLOT_COUNT-1) request_state<=Q_SNAPSHOT;
                else request_scan<=request_scan+1'b1;
            end
            Q_SNAPSHOT: begin
                o_rsp_slot<=request_slot;
                o_rsp_generation<=query_identity[63:32];o_rsp_session<=query_identity[31:0];
                o_rsp_epoch<=cold_query[63:32];o_rsp_capture_id<=cold_query[31:0];
                o_rsp_camera<=request_slot>=3;o_rsp_quality<=cold_query[128:121];
                o_rsp_width<=cold_query[79:64];o_rsp_height<=cold_query[95:80];
                o_rsp_payload_length<=cold_query[120:96];
                o_rsp_mask_present<=MASK_ENABLE!=0 && slot_mask[request_slot];
                o_rsp_read_authorized<=0;
                o_rsp_mask_pinned<=MASK_ENABLE!=0 && slot_pin[request_slot] && slot_pin_mask[request_slot];
                // Candidates were COMMITTED at admission. START is blocked
                // throughout pending selection, so their identity/payload
                // metadata cannot change even if claim/RETIRE changes state.
                o_rsp_state<=req_latest && request_found ? COMMITTED : slot_state[request_slot];
                o_rsp_pinned<=req_latest && request_found ? request_pins[request_slot] : slot_pin[request_slot];
                request_state<=Q_CHECK;
            end
            Q_CHECK: begin pending_code<=request_code;request_state<=Q_VERIFY;end
            Q_VERIFY: begin
                if(pending_code==OK && req_op!=0) begin
                    if(query_identity[63:32]!=o_rsp_generation || query_identity[31:0]!=req_session) pending_code<=STALE;
                    else if(slot_state[request_slot]==SENDING || slot_state[request_slot]==WRITING) pending_code<=BUSY;
                    else if(slot_state[request_slot]!=COMMITTED && !(req_op==2 && slot_pin[request_slot])) pending_code<=NO_FRAME;
                    else if(slot_pin[request_slot] && slot_pin_mask[request_slot]!=req_mask) pending_code<=BUSY;
                end
                request_state<=Q_COMMIT;
            end
            Q_COMMIT: begin
                o_rsp_valid<=1;o_rsp_code<=pending_code;request_state<=Q_IDLE;
                // A reader claim wins the same edge. A QUERY still returns
                // its frozen snapshot; PIN/RELEASE must not change SENDING.
                if(pending_code==OK && req_read_lock) begin
                    // Do not withdraw an already presented READY token.
                    if(!mask_read_grant)o_rsp_code<=BUSY;
                    else begin mask_read_lease<=1;o_rsp_read_authorized<=1;end
                end else if(pending_code==OK && req_op!=0 &&
                   ((o_ready_valid && i_ready_claim && ready_slot==request_slot) ||
                    slot_state[request_slot]==SENDING || slot_state[request_slot]==WRITING)) o_rsp_code<=BUSY;
                else if(pending_code==OK && req_op==1) begin
                    slot_pin[request_slot]<=1;slot_pin_mask[request_slot]<=req_mask;
                    o_rsp_pinned<=1;o_rsp_mask_pinned<=req_mask;
                end
                else if(pending_code==OK && req_op==2) begin
                    slot_pin[request_slot]<=0;o_rsp_pinned<=0;
                    slot_pin_mask[request_slot]<=0;o_rsp_mask_pinned<=0;
                    if(!slot_pending[request_slot]) slot_state[request_slot]<=EMPTY;
                end
            end
            default: request_state<=Q_IDLE;
            endcase
        end
    end
endmodule
