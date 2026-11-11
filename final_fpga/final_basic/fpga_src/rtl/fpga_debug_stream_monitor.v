`timescale 1ns/1ps
`include "pcie_protocol_v1.vh"
// Passive checker for the DFI-domain JPEG payload and complete C2H record.
// All byte counts and digests advance only on accepted stream beats.
module fpga_debug_stream_monitor #(
    parameter integer LOCAL_CLEAR_ENABLE = 0,
    parameter integer FAULT_EVENT_PIPELINE_ENABLE = 0,
    parameter integer SLOT_PROOF_ENABLE = 0
) (
    input wire i_clk,
    input wire i_debug_rst_n,
    input wire i_app_rst_n,
    input wire i_clear,
    input wire i_write_start,
    input wire i_write_valid,
    input wire i_write_ready,
    input wire [127:0] i_write_data,
    input wire [15:0] i_write_keep,
    input wire i_write_last,
    input wire i_write_result,
    input wire i_write_ok,
    input wire [24:0] i_write_length,
    input wire i_read_start,
    input wire i_read_valid,
    input wire i_read_ready,
    input wire [127:0] i_read_data,
    input wire [15:0] i_read_keep,
    input wire i_read_last,
    input wire i_record_start,
    input wire [24:0] i_record_length,
    input wire i_record_valid,
    input wire i_record_ready,
    input wire [127:0] i_record_data,
    input wire [15:0] i_record_keep,
    input wire i_record_last,
    output wire [511:0] o_status,
    output reg o_frame_event,
    output reg o_error_event,
    input wire i_clear_local,
    output reg [31:0] o_fault_causes,
    output wire [255:0] o_fault_context,
    // All added identity ports belong to i_clk. COMMIT is the actual ring
    // writer completion after successful AXI B responses, not encoder RESULT.
    input wire [31:0] i_write_sequence,
    input wire [31:0] i_write_session,
    input wire [31:0] i_write_epoch,
    input wire [31:0] i_write_tag,
    input wire [15:0] i_write_slot,
    input wire [31:0] i_write_generation,
    input wire i_commit_valid,
    input wire i_commit_ok,
    input wire [15:0] i_commit_slot,
    input wire [31:0] i_commit_generation,
    input wire [31:0] i_commit_sequence,
    input wire [31:0] i_commit_session,
    input wire [31:0] i_commit_epoch,
    input wire [31:0] i_commit_tag,
    input wire [24:0] i_commit_length,
    input wire [15:0] i_read_slot,
    input wire [31:0] i_read_generation,
    input wire [31:0] i_read_sequence,
    input wire [31:0] i_read_session,
    input wire [31:0] i_read_epoch,
    input wire [15:0] i_record_header_length
);
    function [4:0] count_keep;
        input [15:0] mask;
        reg [1:0] sum2 [0:7];
        reg [2:0] sum4 [0:3];
        reg [3:0] sum8 [0:1];
        begin
            sum2[0] = {1'b0, mask[0]} + {1'b0, mask[1]};
            sum2[1] = {1'b0, mask[2]} + {1'b0, mask[3]};
            sum2[2] = {1'b0, mask[4]} + {1'b0, mask[5]};
            sum2[3] = {1'b0, mask[6]} + {1'b0, mask[7]};
            sum2[4] = {1'b0, mask[8]} + {1'b0, mask[9]};
            sum2[5] = {1'b0, mask[10]} + {1'b0, mask[11]};
            sum2[6] = {1'b0, mask[12]} + {1'b0, mask[13]};
            sum2[7] = {1'b0, mask[14]} + {1'b0, mask[15]};
            sum4[0] = {1'b0, sum2[0]} + {1'b0, sum2[1]};
            sum4[1] = {1'b0, sum2[2]} + {1'b0, sum2[3]};
            sum4[2] = {1'b0, sum2[4]} + {1'b0, sum2[5]};
            sum4[3] = {1'b0, sum2[6]} + {1'b0, sum2[7]};
            sum8[0] = {1'b0, sum4[0]} + {1'b0, sum4[1]};
            sum8[1] = {1'b0, sum4[2]} + {1'b0, sum4[3]};
            count_keep = {1'b0, sum8[0]} + {1'b0, sum8[1]};
        end
    endfunction
    function valid_keep;
        input [15:0] mask;
        // A low-lane mask starts with bit zero and never rises again above a
        // zero lane. Adjacent-bit checks avoid a carry chain on the mask.
        begin valid_keep = mask[0] && !(|(mask[15:1] & ~mask[14:0])); end
    endfunction
    // This lightweight rolling digest is for locating corruption; it is not a
    // payload CRC or a replacement for byte-by-byte software verification.
    function [31:0] digest_beat;
        input [31:0] prior;
        input [127:0] data;
        input [15:0] keep;
        reg [127:0] masked;
        integer k;
        begin
            masked = 0;
            for (k = 0; k < 16; k = k + 1)
                if (keep[k]) masked[k*8+:8] = data[k*8+:8];
            digest_beat = {prior[26:0], prior[31:27]} ^
                masked[31:0] ^ {masked[62:32], masked[63]} ^
                {masked[93:64], masked[95:94]} ^
                {masked[124:96], masked[127:125]} ^ 32'h9e3779b9;
        end
    endfunction

    reg clear_meta, clear_sync, clear_seen;
    wire clear_now = clear_sync != clear_seen ||
        (LOCAL_CLEAR_ENABLE != 0 && i_clear_local);
    reg [31:0] cycle_count;
    reg write_active, write_last_seen, write_complete, write_bad;
    reg read_active, read_verified, read_bad;
    reg record_active, record_bad;
    reg [31:0] write_count, read_count, record_count;
    reg [31:0] write_digest, read_digest;
    reg [31:0] expected_count, expected_digest, declared_length;
    reg [31:0] record_expected, last_write_count, last_read_count;
    reg [31:0] last_record_count, last_write_digest, last_read_digest;
    reg [31:0] good_records, faults, write_starts, read_starts;
    // In the optional event path, faults remains the named history owner.
    // The already registered event publishes the same-edge prepared count.
    reg [31:0] fault_count_candidate;
    wire [31:0] fault_count_visible = FAULT_EVENT_PIPELINE_ENABLE != 0 && o_error_event ?
        fault_count_candidate : faults;
    reg [31:0] record_starts, app_aborts;
    reg [9:0] first_code_causes;
    reg [191:0] context_candidate, context_history;
    reg first_fault;
    reg [31:0] frame_fault_bits;
    wire wr_fire = i_write_valid && i_write_ready;
    wire rd_fire = i_read_valid && i_read_ready;
    wire rec_fire = i_record_valid && i_record_ready;
    // A single physical writer may overlap one physical reader. Keep the
    // encoder evidence until its immutable ring completion first appears.
    // Observing valid does not acknowledge or retire that producer.
    reg commit_seen, write_proof_pending;
    reg [31:0] write_sequence, write_session, write_epoch, write_tag;
    reg [15:0] write_slot;
    reg [31:0] write_generation;
    reg [5:0] proof_valid;
    // RAM contents survive resets; six initialized bits restore the original
    // debug-reset zero view without resetting 1152 certificate payload bits.
    reg [5:0] proof_initialized;
    wire [191:0] proof_ram_data;
    wire [191:0] proof_read_data = proof_initialized[i_read_slot[2:0]] ?
        proof_ram_data : 192'd0;
    wire [31:0] proof_generation = proof_read_data[191:160];
    wire [31:0] proof_session = proof_read_data[159:128];
    wire [31:0] proof_sequence = proof_read_data[127:96];
    wire [31:0] proof_epoch = proof_read_data[95:64];
    wire [31:0] proof_count = proof_read_data[63:32];
    wire [31:0] proof_digest = proof_read_data[31:0];
    reg read_proof_valid;
    reg [31:0] read_expected_count, read_expected_digest;
    reg [15:0] read_slot, record_header_length;
    wire commit_pulse = SLOT_PROOF_ENABLE != 0 && i_commit_valid && !commit_seen;
    wire commit_slot_valid = i_commit_slot < 16'd6;
    wire read_slot_valid = i_read_slot < 16'd6;
    // Preserve the original certificate write even for a failed completion;
    // proof_valid alone authorizes it. Application reset retains these bytes.
    generate if (SLOT_PROOF_ENABLE != 0) begin : g_proof_ram
        PH1_LOGIC_DRAM #(
            .DATA_WIDTH_W(192),.ADDR_WIDTH_W(4),.DATA_DEPTH_W(16),
            .DATA_WIDTH_R(192),.ADDR_WIDTH_R(4),.DATA_DEPTH_R(16),
            .INIT_FILE("NONE"),.FILL_ALL("NONE"),
            .READREG("DISABLE"),.RESETMODE("SYNC")
        ) u_certificates (
            .di({i_commit_generation,i_commit_session,i_commit_sequence,
                 i_commit_epoch,expected_count,expected_digest}),
            .waddr({1'b0,i_commit_slot[2:0]}),
            .we(i_debug_rst_n && i_app_rst_n && commit_pulse && commit_slot_valid),
            .wclk(i_clk),.raddr({1'b0,i_read_slot[2:0]}),.rdo(proof_ram_data),
            .rdoq(),.rclk(i_clk),.rrst(1'b0),.rce(1'b0)
        );
    end else begin : g_no_proof_ram
        assign proof_ram_data = 192'd0;
    end endgenerate
    wire write_owner_bad = SLOT_PROOF_ENABLE != 0 && i_write_start &&
        (i_write_slot >= 16'd6 || i_write_generation == 0 || write_proof_pending ||
         ((read_active || record_active) && i_write_slot == read_slot));
    wire commit_identity_match = i_commit_sequence == write_sequence &&
        i_commit_session == write_session && i_commit_epoch == write_epoch &&
        i_commit_tag == write_tag && i_commit_generation == write_generation &&
        i_commit_slot == write_slot && i_commit_generation != 0;
    wire commit_bad = commit_pulse &&
        (!commit_slot_valid || !i_commit_ok || !write_complete || !write_proof_pending || i_write_start ||
         !commit_identity_match || {7'd0, i_commit_length} != expected_count ||
         ((read_active || record_active) && i_commit_slot == read_slot));
    wire read_identity_match = read_slot_valid && proof_valid[i_read_slot[2:0]] &&
        proof_generation == i_read_generation &&
        proof_session == i_read_session &&
        proof_sequence == i_read_sequence &&
        proof_epoch == i_read_epoch;
    wire read_identity_bad = SLOT_PROOF_ENABLE != 0 && i_read_start &&
        (!read_identity_match || read_active || record_active ||
         (i_write_start && i_write_slot == i_read_slot) ||
         (commit_pulse && i_commit_slot == i_read_slot));
    wire [31:0] read_check_count = SLOT_PROOF_ENABLE == 0 ? expected_count :
        (i_read_start ? proof_count : read_expected_count);
    wire [31:0] read_check_digest = SLOT_PROOF_ENABLE == 0 ? expected_digest :
        (i_read_start ? proof_digest : read_expected_digest);
    wire read_check_valid = SLOT_PROOF_ENABLE == 0 ? write_complete :
        (i_read_start ? !read_identity_bad : read_proof_valid);
    wire [31:0] record_header_bytes = SLOT_PROOF_ENABLE == 0 ? `PCIE_HEADER_LENGTH :
        {16'd0, (i_record_start ? i_record_header_length : record_header_length)};
    integer proof_index;
    always @(posedge i_clk or negedge i_debug_rst_n) begin
        if (!i_debug_rst_n) begin
            commit_seen <= 0; write_proof_pending <= 0; proof_valid <= 0; read_proof_valid <= 0;
            write_sequence <= 0; write_session <= 0; write_epoch <= 0; write_tag <= 0;
            write_slot <= 0; write_generation <= 0;
            read_expected_count <= 0; read_expected_digest <= 0;
            read_slot <= 0; record_header_length <= 0;
            proof_initialized <= 0;
        end else if (!i_app_rst_n) begin
            commit_seen <= 0; write_proof_pending <= 0; proof_valid <= 0; read_proof_valid <= 0;
        end else if (SLOT_PROOF_ENABLE != 0) begin
            if (!i_commit_valid) commit_seen <= 0;
            else if (commit_pulse) begin commit_seen <= 1; write_proof_pending <= 0; end
            if (i_write_start) begin
                write_proof_pending <= !write_owner_bad;
                write_sequence <= i_write_sequence; write_session <= i_write_session;
                write_epoch <= i_write_epoch; write_tag <= i_write_tag;
                write_slot <= i_write_slot; write_generation <= i_write_generation;
            end
            for (proof_index = 0; proof_index < 6; proof_index = proof_index + 1) begin
                if (commit_pulse && i_commit_slot == proof_index) begin
                    proof_valid[proof_index] <= !commit_bad;
                    proof_initialized[proof_index] <= 1;
                end
                // Reallocation retires the old generation immediately, even
                // before this new writer has an encoder result or AXI B proof.
                if (i_write_start && i_write_slot == proof_index)
                    proof_valid[proof_index] <= 0;
            end
            if (i_read_start) begin
                read_proof_valid <= !read_identity_bad;
                read_expected_count <= read_check_count;
                read_expected_digest <= read_check_digest;
                read_slot <= i_read_slot;
            end
            if (i_record_start) record_header_length <= i_record_header_length;
        end
    end
    // Compute both histories before selecting a start. Late owner/start
    // controls must not traverse a wide adder and then a wide comparison.
    wire [31:0] wr_bytes = {27'd0, count_keep(i_write_keep)};
    wire [31:0] rd_bytes = {27'd0, count_keep(i_read_keep)};
    wire [31:0] rec_bytes = {27'd0, count_keep(i_record_keep)};
    // Only the low byte depends on this beat's 0..16 byte count. Prepare the
    // upper increment and both upper comparisons in parallel, then select
    // with the low-byte carry; KEEP does not traverse a 32-bit carry chain.
    wire [8:0] wr_low_sum = {1'b0, write_count[7:0]} + {4'd0, wr_bytes[4:0]};
    wire [8:0] rd_low_sum = {1'b0, read_count[7:0]} + {4'd0, rd_bytes[4:0]};
    wire [8:0] rec_low_sum = {1'b0, record_count[7:0]} + {4'd0, rec_bytes[4:0]};
    wire [23:0] wr_high_inc = write_count[31:8] + 24'd1;
    wire [23:0] rd_high_inc = read_count[31:8] + 24'd1;
    wire [23:0] rec_high_inc = record_count[31:8] + 24'd1;
    wire [31:0] wr_acc_count = {
        wr_low_sum[8] ? wr_high_inc : write_count[31:8], wr_low_sum[7:0]};
    wire [31:0] rd_acc_count = {
        rd_low_sum[8] ? rd_high_inc : read_count[31:8], rd_low_sum[7:0]};
    wire [31:0] rec_acc_count = {
        rec_low_sum[8] ? rec_high_inc : record_count[31:8], rec_low_sum[7:0]};
    wire wr_acc_mismatch = wr_low_sum[7:0] != i_write_length[7:0] ||
        (wr_low_sum[8] ? wr_high_inc != {7'd0, i_write_length[24:8]} :
                         write_count[31:8] != {7'd0, i_write_length[24:8]});
    wire rd_acc_mismatch = rd_low_sum[7:0] != read_check_count[7:0] ||
        (rd_low_sum[8] ? rd_high_inc != read_check_count[31:8] :
                         read_count[31:8] != read_check_count[31:8]);
    wire rec_acc_mismatch = rec_low_sum[7:0] != record_expected[7:0] ||
        (rec_low_sum[8] ? rec_high_inc != record_expected[31:8] :
                          record_count[31:8] != record_expected[31:8]);
    wire [31:0] wr_next_count = i_write_start ? wr_bytes : wr_acc_count;
    wire [31:0] rd_next_count = i_read_start ? rd_bytes : rd_acc_count;
    wire [31:0] rec_next_count = i_record_start ? rec_bytes : rec_acc_count;
    wire [31:0] wr_first_digest = digest_beat(32'd0, i_write_data, i_write_keep);
    wire [31:0] rd_first_digest = digest_beat(32'd0, i_read_data, i_read_keep);
    wire [31:0] wr_acc_digest = digest_beat(write_digest, i_write_data, i_write_keep);
    wire [31:0] rd_acc_digest = digest_beat(read_digest, i_read_data, i_read_keep);
    wire [31:0] wr_next_digest = i_write_start ? wr_first_digest : wr_acc_digest;
    wire [31:0] rd_next_digest = i_read_start ? rd_first_digest : rd_acc_digest;
    wire wr_count_mismatch = wr_fire ?
        (i_write_start ? wr_bytes != {7'd0, i_write_length} :
                        wr_acc_mismatch) :
        write_count != {7'd0, i_write_length};
    wire rd_count_mismatch = i_read_start ? rd_bytes != read_check_count :
                                           rd_acc_mismatch;
    wire rd_digest_mismatch = i_read_start ? rd_first_digest != read_check_digest :
                                            rd_acc_digest != read_check_digest;
    wire rec_count_mismatch = i_record_start ? rec_bytes != record_expected :
                                              rec_acc_mismatch;
    wire wr_bad_beat = wr_fire && (!valid_keep(i_write_keep) ||
                      !(write_active || i_write_start) || write_last_seen);
    wire rd_bad_beat = rd_fire && (!valid_keep(i_read_keep) ||
                      !(read_active || i_read_start));
    wire rec_bad_beat = rec_fire && (!valid_keep(i_record_keep) ||
                       !(record_active || i_record_start) ||
                       ((i_record_start || record_count == 0) && i_record_data[31:0] != `PCIE_FRAME_MAGIC) ||
                       ((i_record_start || record_count < record_header_bytes) &&
                        (i_record_keep != 16'hffff || i_record_last)));
    wire wr_bad_result = i_write_result &&
        (!i_write_ok || write_bad || wr_bad_beat ||
         !(write_last_seen || (wr_fire && i_write_last)) ||
         wr_count_mismatch);
    wire rd_bad_last = rd_fire && i_read_last &&
        (read_bad || rd_bad_beat || !read_check_valid ||
         rd_count_mismatch || rd_digest_mismatch);
    wire rec_bad_last = rec_fire && i_record_last &&
        (record_bad || rec_bad_beat || !read_verified ||
         rec_count_mismatch);
    wire any_fault = wr_bad_beat || rd_bad_beat || rec_bad_beat ||
                     wr_bad_result || rd_bad_last || rec_bad_last || commit_bad || read_identity_bad || write_owner_bad;
    wire [31:0] fault_bitmap = {22'd0,write_owner_bad,read_identity_bad,commit_bad,1'b0,rec_bad_last,rec_bad_beat,
        rd_bad_last,rd_bad_beat,wr_bad_result,wr_bad_beat};
    // Encode after capture: a late fault must not traverse priority encoding
    // and first-fault feedback before reaching its evidence register.
    wire [31:0] first_fault_code = first_code_causes[9] ? 32'd10 : first_code_causes[8] ? 32'd9 :
        first_code_causes[7] ? 32'd8 : first_code_causes[5] ? 32'd7 :
        first_code_causes[4] ? 32'd6 : first_code_causes[3] ? 32'd5 :
        first_code_causes[2] ? 32'd4 : first_code_causes[1] ? 32'd3 :
        first_code_causes[0] ? 32'd1 : 32'd0;
    // Both payload banks advance without an any_fault clock enable. The
    // registered cause selects this edge's complete candidate; on a quiet
    // edge history has already copied the prior externally visible tuple.
    assign o_fault_context = {64'd0,
        (|o_fault_causes) ? context_candidate : context_history};
    assign o_status = {
        frame_fault_bits, record_expected, app_aborts, first_fault_code,
        last_read_digest, last_write_digest, last_record_count,
        last_read_count, last_write_count, declared_length, record_starts,
        read_starts, write_starts, fault_count_visible, good_records,
        {27'd0, first_fault, record_active, read_active, write_active,
         write_complete}
    };
    always @(posedge i_clk or negedge i_debug_rst_n) begin
        if (!i_debug_rst_n) begin
            clear_meta <= 0; clear_sync <= 0; clear_seen <= 0;
            write_active <= 0; write_last_seen <= 0;
            write_complete <= 0; write_bad <= 0;
            read_active <= 0; read_verified <= 0; read_bad <= 0;
            record_active <= 0; record_bad <= 0;
            write_count <= 0; read_count <= 0; record_count <= 0;
            write_digest <= 0; read_digest <= 0;
            expected_count <= 0; expected_digest <= 0; declared_length <= 0;
            record_expected <= 0; last_write_count <= 0; last_read_count <= 0;
            last_record_count <= 0; last_write_digest <= 0; last_read_digest <= 0;
            good_records <= 0; faults <= 0; write_starts <= 0;
            read_starts <= 0; record_starts <= 0; app_aborts <= 0;
            first_code_causes <= 0; first_fault <= 0; frame_fault_bits <= 0;
            o_frame_event <= 0; o_error_event <= 0;
            cycle_count<=0; o_fault_causes<=0;
            context_candidate <= 0; context_history <= 0;
            fault_count_candidate <= 0;
        end else begin
            clear_meta <= i_clear; clear_sync <= clear_meta;
            if (FAULT_EVENT_PIPELINE_ENABLE != 0) begin
                // No current-cycle stream/owner signal controls these bits.
                // CLEAR plus a normal fault selects old-count-plus-one, as
                // in the original last-NBA priority; an abort selects history.
                fault_count_candidate[7:0] <= fault_count_visible[7:0] + 8'd1;
                fault_count_candidate[15:8] <= fault_count_visible[15:8] + {7'd0, (&fault_count_visible[7:0])};
                fault_count_candidate[23:16] <= fault_count_visible[23:16] + {7'd0, (&fault_count_visible[15:0])};
                fault_count_candidate[31:24] <= fault_count_visible[31:24] + {7'd0, (&fault_count_visible[23:0])};
                faults <= clear_now ? 32'd0 : fault_count_visible;
            end
            o_frame_event <= 0; o_error_event <= 0;
            cycle_count<=cycle_count+1'b1; o_fault_causes<=0;
            context_history <= o_fault_context[191:0];
            context_candidate <= i_app_rst_n ?
                {record_expected,rec_next_count,rd_next_count,wr_next_count,
                 declared_length,cycle_count} :
                {record_expected,record_count,read_count,write_count,
                 declared_length,cycle_count};
            if (clear_now) begin
                clear_seen <= clear_sync;
                good_records <= 0; faults <= 0; write_starts <= 0;
                read_starts <= 0; record_starts <= 0; app_aborts <= 0;
                first_fault <= 0; first_code_causes <= 0;
                last_write_count <= 0; last_read_count <= 0;
                last_record_count <= 0; last_write_digest <= 0;
                last_read_digest <= 0; frame_fault_bits <= 0;
            end
            if (!i_app_rst_n) begin
                if (write_active || read_active || record_active)
                    app_aborts <= app_aborts + 1'b1;
                if (write_active || read_active || record_active) begin
                    o_fault_causes<=32'h40;
                end
                write_active <= 0; write_last_seen <= 0;
                write_complete <= 0; write_bad <= 0;
                read_active <= 0; read_verified <= 0; read_bad <= 0;
                record_active <= 0; record_bad <= 0;
                write_count <= 0; read_count <= 0; record_count <= 0;
                write_digest <= 0; read_digest <= 0;
                expected_count <= 0; expected_digest <= 0;
                frame_fault_bits <= 0;
            end else begin
                o_fault_causes <= fault_bitmap;
                // A zero bitmap is safe before the first fault. Preserve the
                // legacy clear overlap, which does not reopen an old latch
                // until the next edge; local CLEAR does reopen it immediately.
                if (!first_fault || (LOCAL_CLEAR_ENABLE != 0 && clear_now))
                    first_code_causes <= fault_bitmap[9:0];
                if (i_write_start) begin
                    write_starts <= write_starts + 1'b1;
                    write_active <= 1; write_last_seen <= 0;
                    write_complete <= 0; write_bad <= 0;
                    write_count <= 0; write_digest <= 0;
                    frame_fault_bits <= 0;
                end
                if (wr_fire) begin
                    write_count <= wr_next_count;
                    write_digest <= wr_next_digest;
                    if (i_write_last) write_last_seen <= 1;
                    if (wr_bad_beat) begin write_bad <= 1; frame_fault_bits[0] <= 1; end
                end
                if (i_write_result) begin
                    write_active <= 0;
                    declared_length <= {7'd0, i_write_length};
                    last_write_count <= wr_fire ? wr_next_count : write_count;
                    last_write_digest <= wr_fire ? wr_next_digest : write_digest;
                    expected_count <= {7'd0, i_write_length};
                    expected_digest <= wr_fire ? wr_next_digest : write_digest;
                    write_complete <= !wr_bad_result;
                    if (wr_bad_result) frame_fault_bits[1] <= 1;
                end
                if (i_read_start) begin
                    read_starts <= read_starts + 1'b1;
                    read_active <= 1; read_verified <= 0; read_bad <= 0;
                    read_count <= 0; read_digest <= 0;
                end
                if (rd_fire) begin
                    read_count <= rd_next_count;
                    read_digest <= rd_next_digest;
                    if (rd_bad_beat) begin read_bad <= 1; frame_fault_bits[2] <= 1; end
                    if (i_read_last) begin
                        read_active <= 0;
                        last_read_count <= rd_next_count;
                        last_read_digest <= rd_next_digest;
                        read_verified <= !rd_bad_last;
                        if (rd_bad_last) frame_fault_bits[3] <= 1;
                    end
                end
                if (i_record_start) begin
                    record_starts <= record_starts + 1'b1;
                    record_active <= 1; record_bad <= 0; record_count <= 0;
                    record_expected <= {7'd0, i_record_length} + record_header_bytes;
                end
                if (rec_fire) begin
                    record_count <= rec_next_count;
                    if (rec_bad_beat) begin record_bad <= 1; frame_fault_bits[4] <= 1; end
                    if (i_record_last) begin
                        record_active <= 0;
                        last_record_count <= rec_next_count;
                        if (rec_bad_last) frame_fault_bits[5] <= 1;
                        else begin
                            good_records <= good_records + 1'b1;
                            o_frame_event <= 1;
                        end
                    end
                end
                if (commit_bad) frame_fault_bits[7] <= 1;
                if (read_identity_bad) frame_fault_bits[8] <= 1;
                if (write_owner_bad) frame_fault_bits[9] <= 1;
                if (any_fault) begin
                    o_error_event <= 1;
                    if (FAULT_EVENT_PIPELINE_ENABLE == 0) begin
                        faults[7:0] <= faults[7:0] + 8'd1;
                        faults[15:8] <= faults[15:8] + {7'd0, (&faults[7:0])};
                        faults[23:16] <= faults[23:16] + {7'd0, (&faults[15:0])};
                        faults[31:24] <= faults[31:24] + {7'd0, (&faults[23:0])};
                    end
                    if (!first_fault || (LOCAL_CLEAR_ENABLE != 0 && clear_now)) begin
                        first_fault <= 1;
                    end
                end
            end
        end
    end
endmodule
