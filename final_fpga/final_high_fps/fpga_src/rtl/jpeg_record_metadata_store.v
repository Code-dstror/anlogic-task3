`timescale 1ns / 1ps
`include "pcie_protocol_v1.vh"

// One fixed official SDP RAM stores six owned v2 metadata records.
module jpeg_record_metadata_store #(
    parameter integer RECORD_EXTENSION_WIDTH=1024,
    // The ordered egress owns s_extension until this store is quiescent.
    parameter integer BORROW_PENDING_EXTENSION=0,
    parameter integer STAGING_EXTENSION_ENABLE=0,
    parameter integer STREAM_READ=0,
    // Caller retains the accepted request tuple/version through real release.
    parameter integer BORROW_READ_IDENTITY=0,
    parameter integer MASK_READ=0
) (
    input wire i_clk,i_rst_n,
    input wire s_begin_valid,
    output wire s_begin_ready,
    input wire [31:0] s_begin_writer_tag,s_begin_sequence,s_begin_session,s_begin_epoch,
    input wire s_begin_camera,
    input wire [RECORD_EXTENSION_WIDTH-1:0] s_extension,
    input wire s_extension_valid,
    output wire s_extension_ready,
    input wire s_extension_shape_valid,
    output wire o_extension_read_enable,
    output wire [8:0] o_extension_read_index,
    input wire [39:0] i_extension_read_data,
    input wire s_write_result_valid,
    output wire s_write_result_ready,
    input wire [31:0] s_write_result_tag,s_write_result_sequence,s_write_result_session,s_write_result_epoch,
    input wire s_write_result_camera,
    input wire [15:0] s_write_result_slot,
    input wire [31:0] s_write_result_generation,
    input wire s_write_result_ok,
    input wire [7:0] s_write_result_error,
    output wire o_write_quiescent,
    output wire o_read_quiescent,
    output reg o_protocol_fault,
    output reg [31:0] o_stale_write_count,o_bad_extension_count,
    output reg o_bad_extension_seen,
    output reg [7:0] o_write_error,
    input wire s_read_req_valid,
    output wire s_read_req_ready,
    input wire [15:0] s_read_req_slot,
    input wire [31:0] s_read_req_generation,s_read_req_session,s_read_req_sequence,s_read_req_epoch,
    input wire s_read_req_camera,
    output wire o_metadata_available,
    output reg m_read_rsp_valid,
    input wire m_read_rsp_ready,
    output reg m_read_rsp_ok,
    output reg [7:0] m_read_rsp_error,
    output wire [15:0] m_read_rsp_slot,
    output wire [31:0] m_read_rsp_generation,m_read_rsp_session,m_read_rsp_sequence,m_read_rsp_epoch,
    output wire m_read_rsp_camera,
    output wire [RECORD_EXTENSION_WIDTH-1:0] m_read_rsp_extension,
    input wire [15:0] s_read_req_version,
    output wire m_read_rsp_shape_valid,
    input wire s_read_stream_start,
    output wire [127:0] m_read_stream_data,
    output wire m_read_stream_valid,m_read_stream_last,
    input wire m_read_stream_ready,
    input wire s_read_req_mask,
    output wire m_read_rsp_mask_qualified,
    output wire [23:0] m_read_rsp_mask_pixels,
    output wire [2:0] m_read_rsp_source_type
);
    generate if(RECORD_EXTENSION_WIDTH!=1024 && RECORD_EXTENSION_WIDTH!=3072 && RECORD_EXTENSION_WIDTH!=16384) begin : invalid_record_width
        RECORD_EXTENSION_REQUIRES_1024_3072_OR_16384 u_invalid_record_width();
    end endgenerate
    generate if(MASK_READ!=0 && (STREAM_READ==0 || RECORD_EXTENSION_WIDTH!=3072))begin : invalid_mask_profile
        MASK_READ_REQUIRES_STREAM_3072 u_invalid_mask_profile();
    end endgenerate
    generate if(RECORD_EXTENSION_WIDTH==16384 && (STREAM_READ==0 || STAGING_EXTENSION_ENABLE==0 || BORROW_PENDING_EXTENSION==0))begin : invalid_v4_lifetime
        SPARSE_V4_REQUIRES_STAGED_STREAM_NO_VECTOR_COPY u_invalid_v4_lifetime();
    end endgenerate
    localparam integer RAM_WORD_WIDTH=RECORD_EXTENSION_WIDTH==1024 ? 32 : 40;
    localparam integer RAM_WORDS=(RECORD_EXTENSION_WIDTH+RAM_WORD_WIDTH-1)/RAM_WORD_WIDTH;
    localparam integer RAM_PADDED_WIDTH=RAM_WORDS*RAM_WORD_WIDTH;
    localparam integer SLOT_STRIDE=RECORD_EXTENSION_WIDTH==3072 ? 80 : 32;
    localparam integer RAM_INDEX_WIDTH=RECORD_EXTENSION_WIDTH==16384 ? 9 : (RECORD_EXTENSION_WIDTH==3072 ? 7 : 5);
    reg [RECORD_EXTENSION_WIDTH-1:0] pending_extension;
    wire [RECORD_EXTENSION_WIDTH-1:0] write_extension;
    wire [RAM_PADDED_WIDTH-1:0] write_storage={{(RAM_PADDED_WIDTH-RECORD_EXTENSION_WIDTH){1'b0}},write_extension};
    wire [2047:0] sparse_extension=s_extension >> 1024;
    `include "pcie_record_v3_validate.vh"
    function [8:0] ram_address;
        input [2:0] slot;
        input [RAM_INDEX_WIDTH-1:0] index;
        begin ram_address=slot*SLOT_STRIDE+index;end
    endfunction
    localparam [7:0] E_STALE=1,E_BUSY=2,E_INVALID=3,E_EXTENSION=8'he5;
    generate if(BORROW_READ_IDENTITY!=0 && (STREAM_READ==0 || MASK_READ!=0))begin:g_invalid_identity_borrow
        BORROW_READ_IDENTITY_REQUIRES_SINGLE_STREAM_OWNER u_invalid();
    end endgenerate
    reg [15:0] held_m_read_rsp_slot;
    reg [31:0] held_m_read_rsp_generation,held_m_read_rsp_session,held_m_read_rsp_sequence,held_m_read_rsp_epoch;
    reg held_m_read_rsp_camera;
    // A qualified caller's held owner is also the shape-check identity. The
    // valid/catalog result remains local; no live READY tuple is borrowed.
    assign m_read_rsp_slot=BORROW_READ_IDENTITY!=0 ? s_read_req_slot : held_m_read_rsp_slot;
    assign m_read_rsp_generation=BORROW_READ_IDENTITY!=0 ? s_read_req_generation : held_m_read_rsp_generation;
    assign m_read_rsp_session=BORROW_READ_IDENTITY!=0 ? s_read_req_session : held_m_read_rsp_session;
    assign m_read_rsp_sequence=BORROW_READ_IDENTITY!=0 ? s_read_req_sequence : held_m_read_rsp_sequence;
    assign m_read_rsp_epoch=BORROW_READ_IDENTITY!=0 ? s_read_req_epoch : held_m_read_rsp_epoch;
    assign m_read_rsp_camera=BORROW_READ_IDENTITY!=0 ? s_read_req_camera : held_m_read_rsp_camera;
    reg owner,extension_owned,extension_bad,proof_seen,write_busy;
    reg [31:0] writer_tag,sequence_id,session_id,epoch_id,proof_generation;
    // Real writer session/generation overlay never modifies the borrowed source.
    assign write_extension = BORROW_PENDING_EXTENSION != 0 ?
        {s_extension[RECORD_EXTENSION_WIDTH-1:256],proof_generation,session_id,s_extension[191:0]} :
        pending_extension;
    reg camera_id;
    reg [2:0] proof_slot;
    reg [RAM_INDEX_WIDTH-1:0] write_index;
    // Six valid bits retain publication ownership; the cold identity catalog
    // has one asynchronous probe port and no resettable payload registers.
    reg [5:0] slot_valid;
    wire [127:0] selected_catalog;
    reg read_busy,read_pending;
    wire read_probe_pending,read_payload_pending;
    reg [2:0] read_slot;
    reg [RAM_INDEX_WIDTH-1:0] read_index,read_capture_index;
    reg copy_pending,copy_issued_all,copy_identity_good;
    reg [RAM_INDEX_WIDTH-1:0] copy_capture_index;
    wire [RAM_INDEX_WIDTH-1:0] ram_write_index=STAGING_EXTENSION_ENABLE!=0 ? copy_capture_index : write_index;
    wire ram_write_enable=i_rst_n && write_busy && (STAGING_EXTENSION_ENABLE==0 || copy_pending);
    assign o_extension_read_enable=i_rst_n && STAGING_EXTENSION_ENABLE!=0 && write_busy && !copy_issued_all;
    assign o_extension_read_index={{(9-RAM_INDEX_WIDTH){1'b0}},write_index};
    reg [39:0] copied_word;
    reg copy_identity_word_good;
    always @* begin
        copied_word=i_extension_read_data;
        copy_identity_word_good=1'b1;
        if(RECORD_EXTENSION_WIDTH!=1024)begin
            case(copy_capture_index)
                1:copy_identity_word_good=i_extension_read_data[39:24]==session_id[15:0];
                2:copy_identity_word_good=i_extension_read_data[15:0]==session_id[31:16] &&
                    i_extension_read_data[39:16]==epoch_id[23:0];
                3:copy_identity_word_good=i_extension_read_data[7:0]==epoch_id[31:24] &&
                    i_extension_read_data[39:8]==sequence_id;
                4:begin copy_identity_word_good=i_extension_read_data[7:0]=={7'd0,camera_id};
                    copied_word[39:32]=session_id[7:0];end
                5:begin copied_word[23:0]=session_id[31:8];copied_word[39:24]=proof_generation[15:0];end
                6:copied_word[15:0]=proof_generation[31:16];
                default:begin end
            endcase
        end else begin
            case(copy_capture_index)
                2:copy_identity_word_good=i_extension_read_data[31:0]==session_id;
                3:copy_identity_word_good=i_extension_read_data[31:0]==epoch_id;
                4:copy_identity_word_good=i_extension_read_data[31:0]==sequence_id;
                5:copy_identity_word_good=i_extension_read_data[7:0]=={7'd0,camera_id};
                6:copied_word=session_id;
                7:copied_word=proof_generation;
                default:begin end
            endcase
        end
    end
    always @(posedge i_clk)begin
        if(!i_rst_n)begin copy_pending<=0;copy_capture_index<=0;end
        else begin
            copy_pending<=o_extension_read_enable;
            if(o_extension_read_enable)copy_capture_index<=write_index;
        end
    end
    wire read_issue;
    wire ram_read_enable=i_rst_n && read_issue;
    wire [RAM_WORD_WIDTH-1:0] ram_read_data;
    // Publication retains the exact last-word and staged-copy identity fence.
    // slot_valid masks every uninitialized entry after reset; probe/read
    // exclusion already rejects the slot whose extension is being written.
    wire catalog_publish=ram_write_enable && ram_write_index==RAM_WORDS-1 &&
        (STAGING_EXTENSION_ENABLE==0 || (copy_identity_good && copy_identity_word_good));
    PH1_LOGIC_DRAM #(
        .DATA_WIDTH_W(128),.ADDR_WIDTH_W(4),.DATA_DEPTH_W(16),
        .DATA_WIDTH_R(128),.ADDR_WIDTH_R(4),.DATA_DEPTH_R(16),
        .INIT_FILE("NONE"),.FILL_ALL("NONE"),
        .READREG("DISABLE"),.RESETMODE("SYNC")
    ) u_identity_catalog (
        .di({proof_generation,session_id,sequence_id,epoch_id}),
        .waddr({1'b0,proof_slot}),.we(catalog_publish),.wclk(i_clk),
        .raddr({1'b0,s_read_req_slot[2:0]}),.rdo(selected_catalog),.rdoq(),
        .rclk(i_clk),.rrst(1'b0),.rce(1'b0)
    );
    generate if(RECORD_EXTENSION_WIDTH==16384)begin : g_six_slot_banks
        wire [39:0] bank_data[0:5];
        reg [2:0] returned_slot;
        always @(posedge i_clk)if(ram_read_enable)returned_slot<=read_slot;
        genvar bank;
        for(bank=0;bank<6;bank=bank+1)begin : g_bank
            td_sdp_ram40 #(.WIDTH(40),.DEPTH(512),.ADDR_WIDTH(9)) u_metadata_ram (
                .clk(i_clk),.wr_en(ram_write_enable && proof_slot==bank),
                .wr_addr(ram_write_index),.wr_data(copied_word),
                .rd_en(ram_read_enable && read_slot==bank),.rd_addr(read_index),.rd_data(bank_data[bank]));
        end
        assign ram_read_data=bank_data[returned_slot];
    end else begin : g_packed_slot_ram
    td_sdp_ram40 #(.WIDTH(RAM_WORD_WIDTH),.DEPTH(512),.ADDR_WIDTH(9)) u_metadata_ram (
        .clk(i_clk),.wr_en(ram_write_enable),.wr_addr(ram_address(proof_slot,ram_write_index)),
        .wr_data(STAGING_EXTENSION_ENABLE!=0 ? copied_word[RAM_WORD_WIDTH-1:0] : write_storage[write_index*RAM_WORD_WIDTH+:RAM_WORD_WIDTH]),
        .rd_en(ram_read_enable),.rd_addr(ram_address(read_slot,read_index)),.rd_data(ram_read_data));
    end endgenerate

    wire begin_fire=s_begin_valid && s_begin_ready;
    wire extension_fire=s_extension_valid && s_extension_ready;
    wire write_fire=s_write_result_valid && s_write_result_ready;
    wire read_fire=s_read_req_valid && s_read_req_ready;
    assign o_write_quiescent=i_rst_n && !owner && !write_busy && !o_protocol_fault;
    assign o_read_quiescent=i_rst_n && !read_busy && !read_pending &&
        !read_probe_pending && !read_payload_pending && !m_read_rsp_valid;
    assign s_begin_ready=o_write_quiescent && o_read_quiescent;
    assign s_extension_ready=i_rst_n && !o_protocol_fault && owner && !extension_owned && !write_busy;
    assign s_write_result_ready=i_rst_n && !o_protocol_fault;
    // Before actual B the selected ring slot is unknown, so all new reads wait.
    assign s_read_req_ready=i_rst_n && !o_protocol_fault && o_read_quiescent &&
                            (!owner || write_busy);
    wire write_matches=owner && !proof_seen && !write_busy &&
        s_write_result_tag==writer_tag && s_write_result_sequence==sequence_id &&
        s_write_result_session==session_id && s_write_result_epoch==epoch_id &&
        s_write_result_camera==camera_id;
    wire write_slot_legal=s_write_result_slot<6 && s_write_result_generation!=0 &&
        (s_write_result_camera ? s_write_result_slot>=3 : s_write_result_slot<3);
    wire extension_matches=STAGING_EXTENSION_ENABLE!=0 ? s_extension_shape_valid : s_extension[31:0]==`PCIE_RECORD_V2_EXTENSION_MAGIC &&
        s_extension[47:32]==`PCIE_RECORD_V2_SCHEMA_VERSION && s_extension[48+`PCIE_RECORD_V2_FLAG_SOURCE_IDENTITY] &&
        s_extension[63:60]==0 && s_extension[95:64]==session_id &&
        s_extension[127:96]==epoch_id && s_extension[159:128]==sequence_id &&
        s_extension[167:160]=={7'd0,camera_id} && s_extension[255:192]==0 &&
        s_extension[959:947]==0 && s_extension[1023:960]==0 &&
        (RECORD_EXTENSION_WIDTH==1024 || sparse_extension==0 || sparse_v3_valid(sparse_extension));
    wire read_slot_legal=s_read_req_slot<6 && s_read_req_generation!=0 &&
        (s_read_req_camera ? s_read_req_slot>=3 : s_read_req_slot<3);
    reg read_identity_matches;
    always @(*)begin
        read_identity_matches=0;
        if(read_slot_legal)read_identity_matches=slot_valid[s_read_req_slot[2:0]] &&
            selected_catalog=={s_read_req_generation,s_read_req_session,s_read_req_sequence,s_read_req_epoch};
    end
    // A live catalog probe never owns a request or manufactures a response.
    assign o_metadata_available=i_rst_n && !o_protocol_fault && (!owner || write_busy) &&
        !(write_busy && s_read_req_slot=={13'd0,proof_slot}) && read_identity_matches;
    always @(posedge i_clk)begin
        if(!i_rst_n)begin
            owner<=0;extension_owned<=0;extension_bad<=0;proof_seen<=0;write_busy<=0;
            writer_tag<=0;sequence_id<=0;session_id<=0;epoch_id<=0;camera_id<=0;
            proof_slot<=0;proof_generation<=0;write_index<=0;copy_issued_all<=0;copy_identity_good<=1;
            if(BORROW_PENDING_EXTENSION==0)pending_extension<=0;
            slot_valid<=0;
            o_protocol_fault<=0;o_stale_write_count<=0;o_bad_extension_count<=0;o_bad_extension_seen<=0;o_write_error<=0;
        end else begin
            // Before proof is valid these fields have no enabled consumer.
            // The real successful result edge still samples its current data;
            // proof_seen and all identity/slot qualification remain authoritative.
            if(!proof_seen && !write_busy)begin
                proof_slot<=s_write_result_slot[2:0];proof_generation<=s_write_result_generation;
            end
            if(begin_fire)begin
                owner<=1;writer_tag<=s_begin_writer_tag;sequence_id<=s_begin_sequence;
                session_id<=s_begin_session;epoch_id<=s_begin_epoch;camera_id<=s_begin_camera;
                extension_owned<=0;extension_bad<=0;proof_seen<=0;o_write_error<=0;
            end
            if(extension_fire)begin
                if(BORROW_PENDING_EXTENSION==0)pending_extension<=s_extension;
                extension_owned<=1;extension_bad<=!extension_matches;
                // Exact nonzero witness: same reset and first-error edge as
                // the original saturating counter, without its wide reduction.
                if(!extension_matches)begin
                    o_bad_extension_seen<=1;
                    if(!(&o_bad_extension_count))o_bad_extension_count<=o_bad_extension_count+1'b1;
                end
            end
            if(write_fire)begin
                if(!write_matches)begin
                    if(!(&o_stale_write_count))o_stale_write_count<=o_stale_write_count+1'b1;
                end else if(!write_slot_legal)begin
                    o_protocol_fault<=1;o_write_error<=E_INVALID;
                end else begin
                    slot_valid[s_write_result_slot[2:0]]<=0;
                    if(!s_write_result_ok)begin
                        owner<=0;extension_owned<=0;proof_seen<=0;o_write_error<=s_write_result_error;
                    end else begin
                        proof_seen<=1;
                    end
                end
            end
            if(owner && proof_seen && extension_owned && !write_busy)begin
                if(extension_bad)begin
                    owner<=0;proof_seen<=0;extension_owned<=0;o_write_error<=E_EXTENSION;
                end else begin
                    // These two fields are from the actual owned ring result.
                    if(BORROW_PENDING_EXTENSION==0)begin
                        pending_extension[223:192]<=session_id;
                        pending_extension[255:224]<=proof_generation;
                    end
                    write_index<=0;write_busy<=1;copy_issued_all<=0;copy_identity_good<=1;
                end
            end
            if(o_extension_read_enable)begin
                if(write_index==RAM_WORDS-1)copy_issued_all<=1;
                else write_index<=write_index+1'b1;
            end
            if(ram_write_enable)begin
                if(STAGING_EXTENSION_ENABLE!=0)
                    copy_identity_good<=copy_identity_good && copy_identity_word_good;
                if(ram_write_index==RAM_WORDS-1)begin
                    if(STAGING_EXTENSION_ENABLE==0 || (copy_identity_good && copy_identity_word_good))begin
                        slot_valid[proof_slot]<=1;
                    end else begin
                        o_bad_extension_seen<=1;o_write_error<=E_EXTENSION;
                        if(!(&o_bad_extension_count))o_bad_extension_count<=o_bad_extension_count+1'b1;
                    end
                    write_busy<=0;owner<=0;proof_seen<=0;extension_owned<=0;
                end else if(STAGING_EXTENSION_ENABLE==0)write_index<=write_index+1'b1;
            end

        end
    end
    // The legacy public vector exists only in this non-MAIN specialization.
    generate if(STREAM_READ==0)begin : g_legacy_read
        assign read_probe_pending=1'b0;
        assign read_payload_pending=1'b0;
        reg [RAM_PADDED_WIDTH-1:0] read_storage;
        assign m_read_rsp_extension=read_storage[RECORD_EXTENSION_WIDTH-1:0];
        assign m_read_rsp_shape_valid=1'b0;
        assign m_read_stream_data=128'd0;
        assign m_read_stream_valid=1'b0;
        assign m_read_stream_last=1'b0;
        assign m_read_rsp_mask_qualified=1'b0;
        assign m_read_rsp_mask_pixels=24'd0;
        assign m_read_rsp_source_type=3'd0;
        assign read_issue=read_busy;
        always @(posedge i_clk)begin
            if(!i_rst_n)begin
            read_busy<=0;read_pending<=0;read_slot<=0;read_index<=0;read_capture_index<=0;
            m_read_rsp_valid<=0;m_read_rsp_ok<=0;m_read_rsp_error<=0;held_m_read_rsp_slot<=0;
            held_m_read_rsp_generation<=0;held_m_read_rsp_session<=0;held_m_read_rsp_sequence<=0;held_m_read_rsp_epoch<=0;
            held_m_read_rsp_camera<=0;
                read_storage<=0;
            end else begin
                if(m_read_rsp_valid && m_read_rsp_ready)m_read_rsp_valid<=0;
            if(read_fire)begin
                held_m_read_rsp_slot<=s_read_req_slot;held_m_read_rsp_generation<=s_read_req_generation;
                held_m_read_rsp_session<=s_read_req_session;held_m_read_rsp_sequence<=s_read_req_sequence;
                held_m_read_rsp_epoch<=s_read_req_epoch;held_m_read_rsp_camera<=s_read_req_camera;
                read_storage<=0;
                if(!read_slot_legal || (write_busy && s_read_req_slot=={13'd0,proof_slot}) || !read_identity_matches)begin
                    m_read_rsp_valid<=1;m_read_rsp_ok<=0;
                    m_read_rsp_error<=!read_slot_legal ? E_INVALID :
                        ((write_busy && s_read_req_slot=={13'd0,proof_slot}) ? E_BUSY : E_STALE);
                end else begin
                    read_slot<=s_read_req_slot[2:0];read_index<=0;read_busy<=1;
                    m_read_rsp_ok<=1;m_read_rsp_error<=0;
                end
            end
            read_pending<=ram_read_enable;
            if(ram_read_enable)begin
                read_capture_index<=read_index;
                if(read_index==RAM_WORDS-1)read_busy<=0;
                else read_index<=read_index+1'b1;
            end
            if(read_pending)begin
                read_storage[read_capture_index*RAM_WORD_WIDTH+:RAM_WORD_WIDTH]<=ram_read_data;
                if(read_capture_index==RAM_WORDS-1)m_read_rsp_valid<=1;
            end
            end
        end
    end else begin : g_stream_read
        localparam [1:0] READ_VALIDATE=0,READ_CHECKED=1,READ_REPLAY=2,READ_DRAIN=3;
        reg [1:0] read_phase;
        reg [15:0] held_read_version;
        wire [15:0] read_version=BORROW_READ_IDENTITY!=0 ? s_read_req_version : held_read_version;
        reg shape_bad,shape_valid;
        reg [3:0] sparse_enabled;
        // Reuse the response tuple; retain only the accepted catalog decision.
        reg request_pending,request_slot_legal,request_slot_busy,request_identity_good;
        assign read_probe_pending=request_pending;
        // Cut the six-bank return mux from shape/checker and replay logic.
        reg [39:0] captured_word_q;
        reg [RAM_INDEX_WIDTH-1:0] captured_index;
        reg captured_valid;
        assign read_payload_pending=captured_valid;
        // Replay is deliberately byte serial. The existing 40-bit RAM word
        // and one 128-bit output shifter retain all bytes under sink stalls.
        // VALID/LAST still hold until the consumer's real handshake.
        reg [39:0] replay_word;
        reg [2:0] replay_bytes;
        reg replay_word_valid,flit_valid,flit_last;
        reg [127:0] flit_data;
        reg [3:0] flit_byte;
        reg [7:0] built_flits;
        wire [39:0] captured_word=captured_word_q;
        wire [RAM_INDEX_WIDTH-1:0] replay_last_index=(read_version==3 || read_version==4) ? RAM_WORDS-1 :
            ((1024+RAM_WORD_WIDTH-1)/RAM_WORD_WIDTH)-1;
        wire [6:0] captured_bits=captured_index==replay_last_index ?
            (read_version==4 ? 16384-(RAM_WORDS-1)*RAM_WORD_WIDTH :
             read_version==3 ? 3072-(RAM_WORDS-1)*RAM_WORD_WIDTH :
             1024-(((1024+RAM_WORD_WIDTH-1)/RAM_WORD_WIDTH)-1)*RAM_WORD_WIDTH) : RAM_WORD_WIDTH;
        wire queue_pop=m_read_stream_valid && m_read_stream_ready;
        wire byte_step=read_phase==READ_REPLAY && replay_word_valid && !flit_valid;
        always @(posedge i_clk)begin
            if(captured_valid && read_phase==READ_REPLAY)replay_word<=captured_word;
            else if(byte_step)replay_word<={8'd0,replay_word[39:8]};
            if(byte_step)flit_data<={replay_word[7:0],flit_data[127:8]};
        end
        assign m_read_rsp_extension={RECORD_EXTENSION_WIDTH{1'b0}};
        assign m_read_rsp_shape_valid=shape_valid;
        assign m_read_stream_data=flit_data;
        assign m_read_stream_valid=i_rst_n && read_phase==READ_REPLAY && flit_valid;
        assign m_read_stream_last=flit_last;
        // One synchronous return is reserved before each CE; no unselected
        // client's READY can consume this transaction (shared hook is future).
        assign read_issue=read_busy && !(m_read_rsp_valid && m_read_rsp_ready) &&
            (read_phase==READ_VALIDATE || (read_phase==READ_REPLAY &&
             !read_pending && !captured_valid && !replay_word_valid && !flit_valid));
        always @(posedge i_clk)begin
            if(!i_rst_n)captured_valid<=0;
            else begin
                captured_valid<=read_pending;
                if(read_pending)begin
                    captured_word_q<={{(40-RAM_WORD_WIDTH){1'b0}},ram_read_data};
                    captured_index<=read_capture_index;
                end
                if(m_read_rsp_valid && m_read_rsp_ready)captured_valid<=0;
            end
        end
        wire v4_shape_good;
        if(RECORD_EXTENSION_WIDTH==16384)begin : g_v4_check
            lane_sparse_extension_checker u_check (
                .i_clk(i_clk),.i_rst_n(i_rst_n),.i_begin(read_fire),
                .i_valid(captured_valid && read_phase==READ_VALIDATE),
                .i_index(captured_index),.i_data(captured_word),.o_good(v4_shape_good));
        end else begin : g_no_v4_check
            assign v4_shape_good=1'b1;
        end

        // Exact old gate shape checks, split at fixed physical word edges.
        // Opaque tags, contexts and numeric payload are preserved in pass two.
        function word_shape_valid;
            input [RAM_INDEX_WIDTH-1:0] index;
            input [39:0] word;
            input [15:0] checked_version;
            input [3:0] checked_enabled;
            begin
                word_shape_valid=1'b1;
                if(RAM_WORD_WIDTH==40)begin
                    case(index)
                    0:word_shape_valid=word[31:0]==((`PCIE_RECORD_V2_EXTENSION_MAGIC >> 0) & 32'hffffffff) &&
                        word[39:32]==((`PCIE_RECORD_V2_SCHEMA_VERSION >> 0) & 8'hff);
                    1:word_shape_valid=word[7:0]==((`PCIE_RECORD_V2_SCHEMA_VERSION >> 8) & 8'hff) &&
                        word[8:8]==((1'b1 >> 0) & 1'h1) &&
                        word[23:20]==0 &&
                        word[39:24]==m_read_rsp_session[15:0];
                    2:word_shape_valid=word[15:0]==m_read_rsp_session[31:16] &&
                        word[39:16]==m_read_rsp_epoch[23:0];
                    3:word_shape_valid=word[7:0]==m_read_rsp_epoch[31:24] &&
                        word[39:8]==m_read_rsp_sequence[31:0];
                    4:word_shape_valid=word[7:0]=={7'd0,m_read_rsp_camera} &&
                        word[39:32]==m_read_rsp_session[7:0] &&
                        word[15:8]<=`PCIE_RECORD_V2_SOURCE_PHYSICAL &&
                        (word[23:16]==`PCIE_RECORD_V2_FORMAT_RAW10 || word[23:16]==`PCIE_RECORD_V2_FORMAT_RAW14) &&
                        word[31:24]<=`PCIE_RECORD_V2_ROLE_SHORT;
                    5:word_shape_valid=word[23:0]==m_read_rsp_session[31:8] &&
                        word[39:24]==m_read_rsp_generation[15:0];
                    6:word_shape_valid=word[15:0]==m_read_rsp_generation[31:16];
                    23:word_shape_valid=word[39:27]==0;
                    24:word_shape_valid=word[39:0]==0;
                    25:word_shape_valid=word[23:0]==0 &&
                        (checked_version!=3 || (word[39:24]==((`PCIE_RECORD_V3_SPARSE_MAGIC >> 0) & 16'hffff)));
                    26:word_shape_valid=(checked_version!=3 || (word[15:0]==((`PCIE_RECORD_V3_SPARSE_MAGIC >> 16) & 16'hffff))) &&
                        (checked_version!=3 || (word[23:16]==((`PCIE_RECORD_V3_SPARSE_SCHEMA >> 0) & 8'hff))) &&
                        (checked_version!=3 || (word[31:24]==((`PCIE_RECORD_V3_STRIPS >> 0) & 8'hff))) &&
                        (checked_version!=3 || word[39:36]==word[35:32]) &&
                        (checked_version!=3 || (!(|word[35:33]) || word[32]));
                    27:word_shape_valid=(checked_version!=3 || (word[39:1]==0));
                    28:word_shape_valid=(checked_version!=3 || (word[31:0]==0)) &&
                        (checked_version!=3 || checked_enabled[0] || word[39:32]==0);
                    29:word_shape_valid=(checked_version!=3 || checked_enabled[0] || word[39:0]==0);
                    30:word_shape_valid=(checked_version!=3 || checked_enabled[0] || word[39:0]==0);
                    31:word_shape_valid=(checked_version!=3 || checked_enabled[0] || word[39:0]==0);
                    32:word_shape_valid=(checked_version!=3 || checked_enabled[0] || word[39:0]==0);
                    33:word_shape_valid=(checked_version!=3 || checked_enabled[0] || word[39:0]==0);
                    34:word_shape_valid=(checked_version!=3 || checked_enabled[0] || word[39:0]==0);
                    35:word_shape_valid=(checked_version!=3 || checked_enabled[0] || word[39:0]==0);
                    36:word_shape_valid=(checked_version!=3 || checked_enabled[0] || word[39:0]==0);
                    37:word_shape_valid=(checked_version!=3 || checked_enabled[0] || word[39:0]==0);
                    38:word_shape_valid=(checked_version!=3 || checked_enabled[0] || word[39:0]==0);
                    39:word_shape_valid=(checked_version!=3 || checked_enabled[0] || word[39:0]==0);
                    40:word_shape_valid=(checked_version!=3 || checked_enabled[0] || word[39:0]==0);
                    41:word_shape_valid=(checked_version!=3 || checked_enabled[0] || word[35:0]==0) &&
                        (checked_version!=3 || checked_enabled[1] || word[39:36]==0);
                    42:word_shape_valid=(checked_version!=3 || checked_enabled[1] || word[39:0]==0);
                    43:word_shape_valid=(checked_version!=3 || checked_enabled[1] || word[39:0]==0);
                    44:word_shape_valid=(checked_version!=3 || checked_enabled[1] || word[39:0]==0);
                    45:word_shape_valid=(checked_version!=3 || checked_enabled[1] || word[39:0]==0);
                    46:word_shape_valid=(checked_version!=3 || checked_enabled[1] || word[39:0]==0);
                    47:word_shape_valid=(checked_version!=3 || checked_enabled[1] || word[39:0]==0);
                    48:word_shape_valid=(checked_version!=3 || checked_enabled[1] || word[39:0]==0);
                    49:word_shape_valid=(checked_version!=3 || checked_enabled[1] || word[39:0]==0);
                    50:word_shape_valid=(checked_version!=3 || checked_enabled[1] || word[39:0]==0);
                    51:word_shape_valid=(checked_version!=3 || checked_enabled[1] || word[39:0]==0);
                    52:word_shape_valid=(checked_version!=3 || checked_enabled[1] || word[39:0]==0);
                    53:word_shape_valid=(checked_version!=3 || checked_enabled[1] || word[39:0]==0);
                    54:word_shape_valid=(checked_version!=3 || checked_enabled[1] || word[39:0]==0);
                    55:word_shape_valid=(checked_version!=3 || checked_enabled[1] || word[39:0]==0);
                    56:word_shape_valid=(checked_version!=3 || checked_enabled[1] || word[39:0]==0);
                    57:word_shape_valid=(checked_version!=3 || checked_enabled[1] || word[39:0]==0);
                    58:word_shape_valid=(checked_version!=3 || checked_enabled[1] || word[39:0]==0);
                    59:word_shape_valid=(checked_version!=3 || checked_enabled[1] || word[39:0]==0);
                    60:word_shape_valid=(checked_version!=3 || checked_enabled[1] || word[39:0]==0);
                    61:word_shape_valid=(checked_version!=3 || checked_enabled[1] || word[39:0]==0);
                    62:word_shape_valid=(checked_version!=3 || checked_enabled[1] || word[39:0]==0);
                    63:word_shape_valid=(checked_version!=3 || checked_enabled[1] || word[39:0]==0);
                    64:word_shape_valid=(checked_version!=3 || checked_enabled[1] || word[39:0]==0);
                    65:word_shape_valid=(checked_version!=3 || checked_enabled[1] || word[39:0]==0);
                    66:word_shape_valid=(checked_version!=3 || checked_enabled[1] || word[39:0]==0);
                    67:word_shape_valid=(checked_version!=3 || checked_enabled[1] || word[39:0]==0);
                    68:word_shape_valid=(checked_version!=3 || checked_enabled[1] || word[39:0]==0);
                    69:word_shape_valid=(checked_version!=3 || checked_enabled[1] || word[39:0]==0);
                    70:word_shape_valid=(checked_version!=3 || checked_enabled[1] || word[39:0]==0);
                    71:word_shape_valid=(checked_version!=3 || checked_enabled[1] || word[31:0]==0) &&
                        (checked_version!=3 || checked_enabled[2] || word[39:32]==0);
                    72:word_shape_valid=(checked_version!=3 || checked_enabled[2] || word[39:0]==0);
                    73:word_shape_valid=(checked_version!=3 || checked_enabled[3] || word[39:0]==0);
                    74:word_shape_valid=(checked_version!=3 || checked_enabled[3] || word[39:0]==0);
                    75:word_shape_valid=(checked_version!=3 || (word[39:25]==0)) &&
                        (checked_version!=3 || checked_enabled[3] || word[24:0]==0);
                    76:word_shape_valid=(checked_version!=3 || (word[31:0]==0));
                    default:word_shape_valid=1'b1;
                    endcase
                end else begin
                    case(index)
                    0:word_shape_valid=word[31:0]==((`PCIE_RECORD_V2_EXTENSION_MAGIC >> 0) & 32'hffffffff);
                    1:word_shape_valid=word[15:0]==((`PCIE_RECORD_V2_SCHEMA_VERSION >> 0) & 16'hffff) &&
                        word[16:16]==((1'b1 >> 0) & 1'h1) &&
                        word[31:28]==0;
                    2:word_shape_valid=word[31:0]==m_read_rsp_session[31:0];
                    3:word_shape_valid=word[31:0]==m_read_rsp_epoch[31:0];
                    4:word_shape_valid=word[31:0]==m_read_rsp_sequence[31:0];
                    5:word_shape_valid=word[7:0]=={7'd0,m_read_rsp_camera} &&
                        word[15:8]<=`PCIE_RECORD_V2_SOURCE_PHYSICAL &&
                        (word[23:16]==`PCIE_RECORD_V2_FORMAT_RAW10 || word[23:16]==`PCIE_RECORD_V2_FORMAT_RAW14) &&
                        word[31:24]<=`PCIE_RECORD_V2_ROLE_SHORT;
                    6:word_shape_valid=word[31:0]==m_read_rsp_session[31:0];
                    7:word_shape_valid=word[31:0]==m_read_rsp_generation[31:0];
                    29:word_shape_valid=word[31:19]==0;
                    30:word_shape_valid=word[31:0]==0;
                    31:word_shape_valid=word[31:0]==0;
                    default:word_shape_valid=1'b1;
                    endcase
                end
            end
        endfunction

        // MASK authenticates the full canonical SOURCE and terminal. JPEG
        // keeps its original opaque SOURCE contract in word_shape_valid.
        if(MASK_READ!=0)begin : g_mask_summary
            reg mask_owned,mask_bad;
            reg [23:0] mask_pixels;
            reg [2:0] source_type;
            function mask_word_shape_valid;
                input [RAM_INDEX_WIDTH-1:0] index;
                input [39:0] word;
                begin
                    mask_word_shape_valid=1'b1;
                    case(index)
                    14:mask_word_shape_valid=word[39:16]==m_read_rsp_session[23:0];
                    15:mask_word_shape_valid=word[7:0]==m_read_rsp_session[31:24] &&
                        word[39:8]==m_read_rsp_epoch;
                    16:mask_word_shape_valid=word[31:0]==m_read_rsp_sequence &&
                        word[39:32]=={7'd0,m_read_rsp_camera};
                    17:mask_word_shape_valid=word[7:1]==0 &&
                        (word[15:8]==`PCIE_RAW_FORMAT_RAW10 || word[15:8]==`PCIE_RAW_FORMAT_RAW14) &&
                        word[23:16]==`PCIE_MASK_EXPORT_SOURCE_CONTEXT_TYPE && word[39:24]==0;
                    18:mask_word_shape_valid=word[15:0]==`PCIE_MASK_EXPORT_SOURCE_CONTEXT_VERSION;
                    26:mask_word_shape_valid=word[34];
                    27:mask_word_shape_valid=!word[0];
                    71:mask_word_shape_valid=!word[32];
                    72:mask_word_shape_valid=word[39] && word[38:31]==0;
                    default:mask_word_shape_valid=1'b1;
                    endcase
                end
            endfunction
            assign m_read_rsp_mask_qualified=mask_owned && shape_valid && !mask_bad &&
                read_version==3 && mask_pixels!=0 && mask_pixels<=518400;
            assign m_read_rsp_mask_pixels=mask_pixels;
            assign m_read_rsp_source_type=source_type;
            always @(posedge i_clk)begin
                if(!i_rst_n)begin mask_owned<=0;mask_bad<=0;mask_pixels<=0;source_type<=0;end
                else begin
                    if(read_fire)begin mask_owned<=s_read_req_mask;mask_bad<=0;mask_pixels<=0;source_type<=0;end
                    if(captured_valid && read_phase==READ_VALIDATE && mask_owned)begin
                        if(!mask_word_shape_valid(captured_index,captured_word))mask_bad<=1;
                        if(captured_index==17)source_type<={captured_word[0],captured_word[9:8]};
                        if(captured_index==71)mask_pixels[6:0]<=captured_word[39:33];
                        if(captured_index==72)mask_pixels[23:7]<=captured_word[16:0];
                    end
                    if(m_read_rsp_valid && m_read_rsp_ready)mask_owned<=0;
                end
            end
        end else begin : g_no_mask_summary
            assign m_read_rsp_mask_qualified=1'b0;
            assign m_read_rsp_mask_pixels=24'd0;
            assign m_read_rsp_source_type=3'd0;
        end

        always @(posedge i_clk)begin
            if(!i_rst_n)begin
            read_busy<=0;read_pending<=0;read_slot<=0;read_index<=0;read_capture_index<=0;
            m_read_rsp_valid<=0;m_read_rsp_ok<=0;m_read_rsp_error<=0;held_m_read_rsp_slot<=0;
            held_m_read_rsp_generation<=0;held_m_read_rsp_session<=0;held_m_read_rsp_sequence<=0;held_m_read_rsp_epoch<=0;
            held_m_read_rsp_camera<=0;
                read_phase<=READ_CHECKED;held_read_version<=0;shape_bad<=0;shape_valid<=0;
                request_pending<=0;request_slot_legal<=0;request_slot_busy<=0;request_identity_good<=0;
                sparse_enabled<=0;replay_bytes<=0;replay_word_valid<=0;
                flit_valid<=0;flit_last<=0;flit_byte<=0;built_flits<=0;
            end else begin
                request_pending<=read_fire;
                read_pending<=ram_read_enable;
                if(ram_read_enable)begin
                    read_capture_index<=read_index;
                    if(read_index==(read_phase==READ_VALIDATE ? RAM_WORDS-1 : replay_last_index))read_busy<=0;
                    else read_index<=read_index+1'b1;
                end
                if(read_fire)begin
                held_m_read_rsp_slot<=s_read_req_slot;held_m_read_rsp_generation<=s_read_req_generation;
                held_m_read_rsp_session<=s_read_req_session;held_m_read_rsp_sequence<=s_read_req_sequence;
                held_m_read_rsp_epoch<=s_read_req_epoch;held_m_read_rsp_camera<=s_read_req_camera;
                    shape_bad<=0;shape_valid<=0;sparse_enabled<=0;held_read_version<=s_read_req_version;
                    replay_bytes<=0;replay_word_valid<=0;flit_valid<=0;flit_byte<=0;built_flits<=0;
                    read_slot<=s_read_req_slot[2:0];
                    request_slot_legal<=read_slot_legal;
                    request_slot_busy<=write_busy && s_read_req_slot=={13'd0,proof_slot};
                    request_identity_good<=read_identity_matches;
                end
                if(request_pending)begin
                    if(!request_slot_legal || request_slot_busy || !request_identity_good)begin
                        m_read_rsp_valid<=1;m_read_rsp_ok<=0;read_phase<=READ_CHECKED;
                        m_read_rsp_error<=!request_slot_legal ? E_INVALID :
                            (request_slot_busy ? E_BUSY : E_STALE);
                    end else begin
                        read_index<=0;read_busy<=1;read_phase<=READ_VALIDATE;
                        m_read_rsp_ok<=1;m_read_rsp_error<=0;
                    end
                end
                if(captured_valid && read_phase==READ_VALIDATE)begin
                    if(!word_shape_valid(captured_index,captured_word,read_version,sparse_enabled))shape_bad<=1;
                    if(captured_index==1072/RAM_WORD_WIDTH)
                        sparse_enabled<=captured_word[(1072%RAM_WORD_WIDTH)+:4];
                    if(captured_index==RAM_WORDS-1)begin
                        shape_valid<=!shape_bad && word_shape_valid(captured_index,captured_word,read_version,sparse_enabled) &&
                            (read_version==2 || (RECORD_EXTENSION_WIDTH==3072 && read_version==3) ||
                             (RECORD_EXTENSION_WIDTH==16384 && read_version==4 && v4_shape_good));
                        m_read_rsp_valid<=1;read_phase<=READ_CHECKED;
                    end
                end
                if(s_read_stream_start && m_read_rsp_valid && shape_valid && read_phase==READ_CHECKED)begin
                    read_phase<=READ_REPLAY;read_index<=0;read_busy<=1;
                    replay_bytes<=0;replay_word_valid<=0;flit_valid<=0;flit_byte<=0;built_flits<=0;
                end
                if(read_phase==READ_REPLAY)begin
                    if(captured_valid)begin
                        replay_bytes<=captured_bits[5:3];replay_word_valid<=1;
                    end
                    if(byte_step)begin
                        replay_bytes<=replay_bytes-1'b1;
                        if(replay_bytes==1)replay_word_valid<=0;
                        if(flit_byte==15)begin
                            flit_byte<=0;flit_valid<=1;
                            flit_last<=built_flits==(read_version==4 ? 127 : (read_version==3 ? 23:7));
                            built_flits<=built_flits+1'b1;
                        end else flit_byte<=flit_byte+1'b1;
                    end
                    if(queue_pop)flit_valid<=0;
                end
                // Release is the actual final header output or formatter abort,
                // never local last-flit admission. Discard the outstanding RAM
                // return before o_read_quiescent can authorize a new BEGIN.
                if(m_read_rsp_valid && m_read_rsp_ready)begin
                    m_read_rsp_valid<=0;read_busy<=0;shape_valid<=0;
                    flit_valid<=0;replay_word_valid<=0;replay_bytes<=0;read_phase<=READ_DRAIN;
                end else if(read_phase==READ_DRAIN && !read_pending && !captured_valid && !read_fire)read_phase<=READ_CHECKED;
            end
        end
    end endgenerate
endmodule
