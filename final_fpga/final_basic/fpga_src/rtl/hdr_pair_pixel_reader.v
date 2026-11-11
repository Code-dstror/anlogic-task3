`timescale 1ns/1ps

// Immutable pair cursors -> shared RAW10 decoder -> two same-clock 512-group member queues
// -> unchanged numerical HDR merge. No duplicated full metadata envelopes.
module hdr_pair_pixel_reader #(
    parameter integer WIDTH=1920,HEIGHT=1080,
    parameter integer EXTERNAL_DECODER=0
) (
    input wire i_clk,i_identity_rst_n,
    input wire i_start_valid,i_pair_bank,i_pair_camera,output wire o_start_ready,
    input wire [2:0] i_ratio_log2,
    input wire [9:0] i_black_long,i_black_short,
    input wire [13:0] i_motion_base,input wire [3:0] i_motion_shift,
    input wire i_cancel,
    output wire [55:0] m_raw,output wire [3:0] m_motion,
    output wire m_valid,m_sof,m_eol,m_eof,output wire [31:0] m_index,
    input wire m_ready,
    output wire o_result_valid,o_result_ok,input wire i_result_ready,
    output wire o_read_quiet,output wire o_protocol_fault,
    output wire [9:0] o_long_occupancy,o_short_occupancy,
    // Optional DFI decode body. All burst/FIFO/merge ownership stays here.
    output wire o_decode_start_valid,input wire i_decode_start_ready,
    output wire o_decode_release,output wire [1:0] o_decode_abort,
    output wire o_decode_member,output wire [127:0] o_decode_data,
    output wire [15:0] o_decode_keep,output wire o_decode_valid,o_decode_last,
    input wire i_decode_ready,
    input wire i_decode_raw_member,input wire [39:0] i_decode_raw,
    input wire i_decode_raw_valid,output wire o_decode_raw_ready,
    input wire [1:0] i_decode_done,i_decode_aborted,
    output wire [3:0] m_axi_arid,output wire [27:0] m_axi_araddr,
    output wire [7:0] m_axi_arlen,output wire [2:0] m_axi_arsize,
    output wire [1:0] m_axi_arburst,output wire m_axi_arvalid,
    input wire m_axi_arready,
    input wire [3:0] m_axi_rid,input wire [127:0] m_axi_rdata,
    input wire [1:0] m_axi_rresp,input wire m_axi_rlast,m_axi_rvalid,
    output wire m_axi_rready
);
    localparam integer GROUPS=WIDTH*HEIGHT/4,BYTES=GROUPS*5,ROW_GROUPS=WIDTH/4;
    reg active,failed,cursor_finished,fifo_fault;
    reg [1:0] decoder_closed;
    reg [2:0] ratio;
    reg [9:0] black_long,black_short;
    reg [13:0] motion_base;
    reg [3:0] motion_shift,inflight;
    reg [11:0] pushed_long,pushed_short;
    reg first_group;
    reg [31:0] output_index;
    reg [15:0] column;
    reg [9:0] long_occupancy,short_occupancy;
    // Public reset isolates stale data immediately. The local release and
    // registered run gate allow synchronous merge clear after DFI resumes.
    (* preserve="true", ASYNC_REG="TRUE" *) reg [2:0] fifo_release;
    (* preserve="true" *) reg fifo_reset=1'b1;
    // The two synchronous RAM outputs hold one matched pair. One spill
    // register accepts the preceding pair if READY falls on a prefetch edge.
    reg [79:0] spill_pair;
    reg [8:0] pair_address;
    reg ram_valid,spill_valid;
    wire buffered=ram_valid||spill_valid;
    reg discard_reads=1'b0;
    reg read_quiet;
    wire [31:0] long_offset,short_offset;
    wire [127:0] cursor_data;
    wire [15:0] cursor_keep;
    wire cursor_member,cursor_valid,cursor_last,cursor_ready;
    wire cursor_start_ready,cursor_result_valid,cursor_result_ok,cursor_quiet,cursor_fault;
    wire [39:0] native_data;
    wire native_member,native_valid,native_ready;
    wire [1:0] native_done,native_abort;
    wire [39:0] long_data,short_data;
    wire fifo_ready=fifo_release[2] && !fifo_reset;
    wire long_head=fifo_ready && long_occupancy!=0;
    wire short_head=fifo_ready && short_occupancy!=0;
    wire long_full=long_occupancy==512,short_full=short_occupancy==512;
    wire start_fire=i_start_valid && o_start_ready;
    // failed belongs to the active job. After its actual RESULT handshake,
    // the retained old value must not cancel a newly accepted cursor START
    // on the same edge that this reader clears failed. External cancel,
    // protocol quarantine and the current cursor result remain authoritative.
    wire failure=(active && failed) || (i_cancel && !o_result_valid) ||
        o_protocol_fault || (cursor_result_valid && !cursor_result_ok);
    wire [11:0] long_progress=pushed_long+{pushed_long[9:0],2'b00};
    wire [11:0] short_progress=pushed_short+{pushed_short[9:0],2'b00};
    // Each grant advances at most 160 AXI words (2,560 bytes). Until the
    // next empty-queue grant the accepted offset is at most that far ahead
    // of emitted bytes, strictly below 4096. Therefore low-12 equality
    // identifies the exact drained position, including a wrap. A canceled
    // or faulted cursor finishes/drains its issued R debt without new grants.
    wire [1:0] member_credit={short_occupancy==0 &&
        (!native_valid || !native_member) && short_progress==short_offset[11:0],
        long_occupancy==0 && (!native_valid || native_member) && long_progress==long_offset[11:0]};
    wire push_long=native_valid && native_ready && !native_member;
    wire push_short=native_valid && native_ready && native_member;
    wire merge_ready;
    wire merge_valid=active && !failure && fifo_ready && buffered;
    wire merge_fire=merge_valid && merge_ready;
    // Issue independent of merge_ready. A newly arriving stall is absorbed
    // by spill_pair, after which the visible RAM result is held as well.
    wire pair_fetch=long_head && short_head && !spill_valid && !discard_reads && !failure;
    wire pop_long=pair_fetch || (discard_reads && long_head);
    wire pop_short=pair_fetch || (discard_reads && short_head);
    wire [79:0] next_pair=spill_valid ? spill_pair : {short_data,long_data};
    wire output_fire=m_valid && m_ready;
    assign native_ready=fifo_ready && !(native_member ? short_full : long_full);
    wire local_start_ready=!active && cursor_start_ready && fifo_ready &&
        long_occupancy==0 && short_occupancy==0 && !buffered &&
        !discard_reads && inflight==0 && !o_protocol_fault;
    assign o_decode_start_valid=i_start_valid && local_start_ready;
    assign o_start_ready=local_start_ready && (EXTERNAL_DECODER==0 || i_decode_start_ready);
    assign o_protocol_fault=cursor_fault || fifo_fault;
    wire read_drained=fifo_ready && cursor_quiet && decoder_closed==3 && !native_valid &&
        long_occupancy==0 && short_occupancy==0 && !long_head && !short_head &&
        !pop_long && !pop_short && !buffered && inflight==0 && !m_valid && !o_protocol_fault;
    // This proof is registered only after every real debt is absent. START
    // revokes it immediately; one extra quiet cycle cannot release an owner
    // before its final FIFO read / merge output / actual DDR response.
    assign o_read_quiet=read_quiet && !start_fire && !o_protocol_fault;
    assign o_result_valid=active && cursor_finished && o_read_quiet;
    assign o_result_ok=!failed && output_index==GROUPS;
    assign m_index=output_index;
    assign m_eof=m_valid && output_index==GROUPS-1;
    assign o_long_occupancy=long_occupancy;
    assign o_short_occupancy=short_occupancy;
    hdr_pair_read_cursor #(.WIDTH(WIDTH),.HEIGHT(HEIGHT)) u_cursor(
        .i_clk(i_clk),.i_identity_rst_n(i_identity_rst_n),
        .i_start_valid(start_fire),.i_pair_bank(i_pair_bank),.i_pair_camera(i_pair_camera),.o_start_ready(cursor_start_ready),
        .i_cancel(failure),.i_member_credit(member_credit),
        .o_long_offset(long_offset),.o_short_offset(short_offset),
        .m_data(cursor_data),.m_keep(cursor_keep),.m_member(cursor_member),
        .m_valid(cursor_valid),.m_last(cursor_last),.m_ready(cursor_ready),
        .o_result_valid(cursor_result_valid),.o_result_ok(cursor_result_ok),.i_result_ready(1'b1),
        .o_bus_quiet(cursor_quiet),.o_protocol_fault(cursor_fault),
        .m_axi_arid(m_axi_arid),.m_axi_araddr(m_axi_araddr),.m_axi_arlen(m_axi_arlen),
        .m_axi_arsize(m_axi_arsize),.m_axi_arburst(m_axi_arburst),.m_axi_arvalid(m_axi_arvalid),.m_axi_arready(m_axi_arready),
        .m_axi_rid(m_axi_rid),.m_axi_rdata(m_axi_rdata),.m_axi_rresp(m_axi_rresp),.m_axi_rlast(m_axi_rlast),.m_axi_rvalid(m_axi_rvalid),.m_axi_rready(m_axi_rready));
    // On failure the cursor's already presented beat must still handshake,
    // while decoder abort independently preserves any presented native group.
    wire decoder_ready;
    assign cursor_ready=failure || decoder_ready;
    assign o_decode_release=o_result_valid && i_result_ready;
    assign o_decode_abort={2{active && failure}};
    assign o_decode_member=cursor_member;
    assign o_decode_data=cursor_data;assign o_decode_keep=cursor_keep;
    assign o_decode_valid=cursor_valid && !failure;assign o_decode_last=cursor_last;
    assign o_decode_raw_ready=native_ready;
    generate if(EXTERNAL_DECODER!=0)begin:g_external_decoder
        assign decoder_ready=i_decode_ready;
        assign native_member=i_decode_raw_member;assign native_data=i_decode_raw;
        assign native_valid=i_decode_raw_valid;
        assign native_done=i_decode_done;assign native_abort=i_decode_aborted;
    end else begin:g_local_decoder
    shared_raw10_decoder u_decoder(
        .i_clk(i_clk),.i_rst_n(i_identity_rst_n),.i_start(start_fire),
        .i_total_bytes(BYTES),.i_total_groups(GROUPS),.i_abort({2{active && failure}}),
        .i_axis_member(cursor_member),.i_axis_data(cursor_data),.i_axis_keep(cursor_keep),
        .i_axis_valid(cursor_valid && !failure),.i_axis_last(cursor_last),.o_axis_ready(decoder_ready),
        .o_member(native_member),.o_data(native_data),.o_valid(native_valid),.i_ready(native_ready),
        .o_done(native_done),.o_abort(native_abort));
    end endgenerate
    // Accepted groups are numbered from zero independently per member.
    // A common read address advances only when both heads are present.
    td_sdp_ram40 #(.WIDTH(40),.DEPTH(512),.ADDR_WIDTH(9)) u_long_fifo(
        .clk(i_clk),.wr_en(push_long),.wr_addr(pushed_long[8:0]),.wr_data(native_data),
        .rd_en(pair_fetch),.rd_addr(pair_address),.rd_data(long_data));
    td_sdp_ram40 #(.WIDTH(40),.DEPTH(512),.ADDR_WIDTH(9)) u_short_fifo(
        .clk(i_clk),.wr_en(push_short),.wr_addr(pushed_short[8:0]),.wr_data(native_data),
        .rd_en(pair_fetch),.rd_addr(pair_address),.rd_data(short_data));
    hdr_merge4 u_merge(
        // Its valid pipeline clears synchronously. A reset pulse while i_clk
        // is stopped must keep public output isolated until that clear ran.
        .clk(i_clk),.rst_n(fifo_ready),.clear(start_fire),
        .cfg_ratio_log2(ratio),.cfg_black_long(black_long),.cfg_black_short(black_short),
        .cfg_motion_base(motion_base),.cfg_motion_shift(motion_shift),
        .s_long(next_pair[39:0]),.s_short(next_pair[79:40]),.s_valid(merge_valid),.s_ready(merge_ready),
        .s_sof(first_group),.s_eol(column==ROW_GROUPS-1),
        .m_raw(m_raw),.m_valid(m_valid),.m_ready(m_ready),.m_sof(m_sof),.m_eol(m_eol),.m_motion(m_motion));
    always @(posedge i_clk or negedge i_identity_rst_n)begin
        if(!i_identity_rst_n)fifo_release<=0;
        else fifo_release<={fifo_release[1:0],1'b1};
    end
    always @(posedge i_clk)begin
        fifo_reset<=!fifo_release[2];
        if(!fifo_ready)discard_reads<=0;
        else discard_reads<=active && failure;
        if(!fifo_ready || failure || start_fire)begin
            spill_valid<=0;ram_valid<=0;pair_address<=0;
        end else begin
            if(pair_fetch)begin
                pair_address<=pair_address+1'b1;
                ram_valid<=1;
                if(ram_valid && !merge_fire)begin
                    spill_pair<={short_data,long_data};spill_valid<=1;
                end
            end else if(merge_fire)begin
                if(spill_valid)spill_valid<=0;
                else ram_valid<=0;
            end
        end
    end
    always @(posedge i_clk or negedge i_identity_rst_n)begin
        if(!i_identity_rst_n)read_quiet<=0;
        else if(start_fire)read_quiet<=0;
        else read_quiet<=read_drained;
    end
    always @(posedge i_clk or negedge i_identity_rst_n)begin
        if(!i_identity_rst_n)begin
            active<=0;failed<=0;cursor_finished<=0;decoder_closed<=3;fifo_fault<=0;
            ratio<=0;black_long<=0;black_short<=0;motion_base<=0;motion_shift<=0;
            pushed_long<=0;pushed_short<=0;first_group<=1;output_index<=0;column<=0;
            long_occupancy<=0;short_occupancy<=0;inflight<=0;
        end else begin
            if(long_occupancy>512 || short_occupancy>512)fifo_fault<=1;
            if(start_fire)begin
                active<=1;failed<=i_ratio_log2==0 || i_ratio_log2>4;
                cursor_finished<=0;decoder_closed<=0;
                ratio<=i_ratio_log2;black_long<=i_black_long;black_short<=i_black_short;
                motion_base<=i_motion_base;motion_shift<=i_motion_shift;
                pushed_long<=0;pushed_short<=0;first_group<=1;output_index<=0;column<=0;
            end else begin
                decoder_closed<=decoder_closed | native_done | native_abort;
                if(active && (failure || |native_abort))failed<=1;
                if(push_long)pushed_long<=pushed_long+1'b1;
                if(push_short)pushed_short<=pushed_short+1'b1;
                if(merge_fire)begin first_group<=0;column<=column==ROW_GROUPS-1 ? 0 : column+1'b1;end
                if(output_fire)output_index<=output_index+1'b1;
            end
            if(cursor_result_valid)begin cursor_finished<=1;if(!cursor_result_ok)failed<=1;end
            if(o_result_valid && i_result_ready)active<=0;
            case({push_long,pop_long})
                2'b10:long_occupancy<=long_occupancy+1'b1;
                2'b01:long_occupancy<=long_occupancy-1'b1;
                default:begin end
            endcase
            case({push_short,pop_short})
                2'b10:short_occupancy<=short_occupancy+1'b1;
                2'b01:short_occupancy<=short_occupancy-1'b1;
                default:begin end
            endcase
            case({merge_fire,output_fire})
                2'b10:inflight<=inflight+1'b1;
                2'b01:inflight<=inflight-1'b1;
                default:begin end
            endcase
        end
    end
endmodule
