`timescale 1ns/1ps
`default_nettype none

// Two physical CSI VC members. No pixel, exposure or frame cadence generator.
// Outputs remain in the PHY word clock domain, before official event FIFOs.
module real_hdr_csi_dual_word_rx #(
    parameter integer SAMPLE_BITS=12,
    parameter integer EXPECTED_RAW_BYTES=(1944*SAMPLE_BITS)/8,
    parameter [1:0] LONG_VC=0, SHORT_VC=1
) (
    input wire i_clk, i_reset_n, i_identity_rst_n, i_cycle_enable,
    input wire [31:0] i_word,
    input wire i_word_valid,
    input wire i_long_ready, i_short_ready,
    output wire [47:0] o_long_data, o_short_data,
    output wire o_long_valid, o_short_valid,
    output wire o_long_sof, o_short_sof, o_long_eol, o_short_eol,
    output wire o_long_abort, o_short_abort,
    output wire [3:0] o_long_error, o_short_error,
    output wire [31:0] o_long_sequence_count, o_short_sequence_count,
    output wire [31:0] o_long_group,o_short_group,o_long_event_sequence,o_short_event_sequence,
    output wire o_long_identity_valid,o_short_identity_valid,o_long_cycle_valid,o_short_cycle_valid,
    output wire [15:0] o_long_event_frame_number,o_short_event_frame_number,
    output wire o_long_fs_observe_valid, o_short_fs_observe_valid,
    output wire [15:0] o_long_fs_number, o_short_fs_number,
    output wire [31:0] o_long_fs_observe_sequence, o_short_fs_observe_sequence,
    output wire o_long_fs_observe_trusted, o_short_fs_observe_trusted,
    output wire o_identity_fault, o_wait_for_sync, o_packet_done, o_packet_continue,
    output wire o_header_ecc_error, o_payload_crc_error, o_length_error
);
    wire [1:0] fault,wait_sync,done,packet_continue,ecc,crc,length_error;
    wire [15:0] packet_crc;
    wire [15:0] crc_byte1,crc_byte2,crc_byte3,crc_byte4;
    wire [31:0] packet_word;
    wire packet_valid,header_good,boundary_reject;
    wire [23:0] header_corrected;
    wire [5:0] header_syndrome;
    wire [1:0] boundary_open;
    hdr_csi_boundary_adapter #(.EXPECTED_RAW_BYTES(EXPECTED_RAW_BYTES),
        .RAW_DT(SAMPLE_BITS==12?6'h2c:6'h2b),.LONG_VC(LONG_VC),.SHORT_VC(SHORT_VC)) u_boundary(
        .i_clk(i_clk),.i_reset_n(i_reset_n),.i_word(i_word),.i_word_valid(i_word_valid),
        .i_boundary_open(&boundary_open),.o_word(packet_word),.o_word_valid(packet_valid),
        .o_header_corrected(header_corrected),.o_header_syndrome(header_syndrome),
        .o_header_good(header_good),.o_boundary_reject(boundary_reject));
    // Both VC parsers consume every physical packet with the same decoder
    // reset, word-valid and payload length. TARGET_VC only qualifies output,
    // so their CRC recurrence is identical even while one output is stalled.
    // Use the long parser's existing state; no additional packet owner/state.
    function [15:0] crc_byte;
        input [15:0] prior;
        input [7:0] data;
        integer bit_index;
        reg [15:0] value;
        begin
            value=prior^data;
            for(bit_index=0;bit_index<8;bit_index=bit_index+1)
                value=value[0] ? ((value>>1)^16'h8408) : (value>>1);
            crc_byte=value;
        end
    endfunction
    assign crc_byte1=crc_byte(packet_crc,packet_word[7:0]);
    assign crc_byte2=crc_byte(crc_byte1,packet_word[15:8]);
    assign crc_byte3=crc_byte(crc_byte2,packet_word[23:16]);
    assign crc_byte4=crc_byte(crc_byte3,packet_word[31:24]);
    wire [63:0] shared_crc={crc_byte4,crc_byte3,crc_byte2,crc_byte1};
    // A CSI long packet occupies the physical wire exclusively until its
    // CRC trailer. One 32-bit residue handles both DOL2 VC payloads.
    // phase 1 has four saved bytes, phase 2 has two saved bytes.
    reg [1:0] pack_phase;
    reg [31:0] pack_bytes;
    wire pack_begin,pack_advance;
    wire [15:0] pack_left;
    wire pack_emit=(pack_phase==1 && pack_left>=2) || (pack_phase==2 && pack_left>=4);
    wire pack_eol=(pack_phase==1 && pack_left==2) || (pack_phase==2 && pack_left==4);
    wire [47:0] packed12=pack_phase==1 ? {packet_word[15:0],pack_bytes} :
                                        {packet_word,pack_bytes[15:0]};
    always @(posedge i_clk or negedge i_reset_n)begin
        if(!i_reset_n)pack_phase<=0;
        else if(pack_begin)pack_phase<=0;
        else if(pack_advance)pack_phase<=pack_phase==2 ? 0 : pack_phase+1'b1;
    end
    always @(posedge i_clk)if(pack_advance)begin
        if(pack_phase==0)pack_bytes<=packet_word;
        else if(pack_phase==1)pack_bytes[15:0]<=packet_word[31:16];
    end
    reg [31:0] group_counter;
    reg cycle_open,short_seen;
    wire [31:0] next_group=group_counter==32'hffffffff ? group_counter : group_counter+32'd1;
    wire long_cycle_valid=i_cycle_enable && !o_identity_fault && group_counter!=32'hffffffff;
    wire short_cycle_valid=i_cycle_enable && !o_identity_fault && cycle_open && !short_seen;
    always @(posedge i_clk or negedge i_identity_rst_n)begin
        if(!i_identity_rst_n)begin group_counter<=0;cycle_open<=0;short_seen<=0;end
        else if(!i_reset_n || !i_cycle_enable)begin cycle_open<=0;short_seen<=0;end
        else begin
            // Original packet order is authoritative before independent FIFOs.
            // Any missing old member is cancelled by the pixel pair-cycle gate.
            if(o_long_fs_observe_valid)begin
                group_counter<=next_group;cycle_open<=1;short_seen<=0;
            end
            if(o_short_fs_observe_valid)short_seen<=1;
        end
    end
    real_hdr_csi_word_core #(.SAMPLE_BITS(SAMPLE_BITS),.TARGET_VC(LONG_VC),.SHARED_CRC_ENABLE(1),.SHARED_HEADER_ENABLE(1),.SHARED_RAW12(SAMPLE_BITS==12)) u_long(
        .i_clk(i_clk),.i_reset_n(i_reset_n),.i_identity_rst_n(i_identity_rst_n),
        .i_fs_group(next_group),.i_fs_cycle_valid(long_cycle_valid),
        .o_event_group(o_long_group),.o_event_sequence(o_long_event_sequence),
        .o_event_identity_valid(o_long_identity_valid),.o_event_cycle_valid(o_long_cycle_valid),
        .o_event_frame_number(o_long_event_frame_number),
        .o_source_sequence_count(o_long_sequence_count),.o_identity_fault(fault[0]),
        .o_fs_observe_valid(o_long_fs_observe_valid),.o_fs_observe_number(o_long_fs_number),
        .o_fs_observe_sequence(o_long_fs_observe_sequence),.o_fs_observe_trusted(o_long_fs_observe_trusted),
        .i_word(packet_word),.i_word_valid(packet_valid),.i_shared_crc(shared_crc),.i_shared_crc_state(packet_crc),.o_crc_state(packet_crc),.i_sink_ready(i_long_ready),
        .i_packed12(packed12),.i_pack_emit(pack_emit),.i_pack_eol(pack_eol),
        .o_pack_begin(pack_begin),.o_pack_advance(pack_advance),.o_pack_left(pack_left),
        .i_shared_header(header_corrected),.i_shared_header_syndrome(header_syndrome),.i_shared_header_good(header_good),
        .i_boundary_reject(boundary_reject),.o_boundary_open(boundary_open[0]),
        .o_data(o_long_data),.o_valid(o_long_valid),.o_sof(o_long_sof),.o_eol(o_long_eol),
        .o_abort(o_long_abort),.o_error_code(o_long_error),.o_header_ecc_error(ecc[0]),
        .o_payload_crc_error(crc[0]),.o_length_error(length_error[0]),
        .o_wait_for_sync(wait_sync[0]),.o_packet_done(done[0]),.o_packet_continue(packet_continue[0]));
    real_hdr_csi_word_core #(.SAMPLE_BITS(SAMPLE_BITS),.TARGET_VC(SHORT_VC),.SHARED_CRC_ENABLE(1),.SHARED_HEADER_ENABLE(1),.SHARED_RAW12(SAMPLE_BITS==12)) u_short(
        .i_clk(i_clk),.i_reset_n(i_reset_n),.i_identity_rst_n(i_identity_rst_n),
        .i_fs_group(group_counter),.i_fs_cycle_valid(short_cycle_valid),
        .o_event_group(o_short_group),.o_event_sequence(o_short_event_sequence),
        .o_event_identity_valid(o_short_identity_valid),.o_event_cycle_valid(o_short_cycle_valid),
        .o_event_frame_number(o_short_event_frame_number),
        .o_source_sequence_count(o_short_sequence_count),.o_identity_fault(fault[1]),
        .o_fs_observe_valid(o_short_fs_observe_valid),.o_fs_observe_number(o_short_fs_number),
        .o_fs_observe_sequence(o_short_fs_observe_sequence),.o_fs_observe_trusted(o_short_fs_observe_trusted),
        .i_word(packet_word),.i_word_valid(packet_valid),.i_shared_crc(shared_crc),.i_shared_crc_state(packet_crc),.o_crc_state(),.i_sink_ready(i_short_ready),
        .i_packed12(packed12),.i_pack_emit(pack_emit),.i_pack_eol(pack_eol),
        .o_pack_begin(),.o_pack_advance(),.o_pack_left(),
        .i_shared_header(header_corrected),.i_shared_header_syndrome(header_syndrome),.i_shared_header_good(header_good),
        .i_boundary_reject(boundary_reject),.o_boundary_open(boundary_open[1]),
        .o_data(o_short_data),.o_valid(o_short_valid),.o_sof(o_short_sof),.o_eol(o_short_eol),
        .o_abort(o_short_abort),.o_error_code(o_short_error),.o_header_ecc_error(ecc[1]),
        .o_payload_crc_error(crc[1]),.o_length_error(length_error[1]),
        .o_wait_for_sync(wait_sync[1]),.o_packet_done(done[1]),.o_packet_continue(packet_continue[1]));
    assign o_identity_fault=|fault;
    assign o_wait_for_sync=&wait_sync;
    assign o_packet_done=(|done)||boundary_reject;
    assign o_packet_continue=&packet_continue;
    assign o_header_ecc_error=|ecc;
    assign o_payload_crc_error=|crc;
    assign o_length_error=|length_error;
    generate if(LONG_VC==SHORT_VC)begin:g_invalid_vc
        REAL_HDR_MEMBERS_REQUIRE_DISTINCT_VC invalid_vc();
    end endgenerate
endmodule
`default_nettype wire
