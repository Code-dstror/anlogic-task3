module uhd_probe (
    input wire clk, pixel_clk, cold_rst_n,
    input wire write_word, pixel_write_word,
    input wire [4:0] word_index,
    input wire [2:0] pixel_word_index,
    input wire [31:0] stimulus_word, pixel_stimulus_word,
    input wire [4:0] observe_word,
    output reg [31:0] observe,
    output wire [3:0] feedback
);
    reg [1023:0] stimulus;
    reg [255:0] pixel_stimulus;
    genvar word_number;
    generate for (word_number=0; word_number<32; word_number=word_number+1) begin : g_dfi_word
        always @(posedge clk)
            if (write_word && word_index == word_number)
                stimulus[word_number*32 +: 32] <= stimulus_word;
    end
    for (word_number=0; word_number<8; word_number=word_number+1) begin : g_pixel_word
        always @(posedge pixel_clk)
            if (pixel_write_word && pixel_word_index == word_number)
                pixel_stimulus[word_number*32 +: 32] <= pixel_stimulus_word;
    end endgenerate

    wire [31:0] control = stimulus[31:0], options = stimulus[63:32];
    wire dfi_data_reset_n, fifo_sink_reset_n;
    // These represent the independent egress and metadata-gate releases,
    // so the tested ring release only reaches them through the real handshake.
    reset_release_sync u_metadata_reset (
        .i_clk(clk), .i_async_rst_n(cold_rst_n), .o_rst_n(dfi_data_reset_n)
    );
    reset_release_sync u_egress_reset (
        .i_clk(clk), .i_async_rst_n(cold_rst_n), .o_rst_n(fifo_sink_reset_n)
    );

    wire [146:0] token_data;
    wire token_valid, egress_token_ready, source_ready, source_done, sink_done;
    wire fence_proven, source_fault, sink_fault;
    wire start_valid, jpeg_valid, result_valid, ring_start_ready, jpeg_ready, result_ready;
    wire record_quiet, write_quiet;
    wire sink_quiet = record_quiet && control[21] && !start_valid && !jpeg_valid && !result_valid;
    ordered_frame_fifo_fence u_fifo_fence (
        .i_source_clk(pixel_clk), .i_source_rst_n(cold_rst_n), .i_source_data(pixel_stimulus[146:0]),
        .i_source_valid(pixel_stimulus[147]), .o_source_ready(source_ready), .o_source_reset_done(source_done),
        .i_sink_clk(clk), .i_sink_rst_n(fifo_sink_reset_n), .o_sink_data(token_data), .o_sink_valid(token_valid),
        .i_sink_ready(egress_token_ready), .o_sink_reset_done(sink_done),
        .i_fence_request(pixel_stimulus[148]), .i_source_idle(pixel_stimulus[149]),
        .i_source_session(pixel_stimulus[181:150]), .i_raw_enqueued(pixel_stimulus[245:182]),
        .i_sink_quiet(sink_quiet), .i_sink_session(stimulus[383:352]), .i_raw_consumed(stimulus[447:384]),
        .i_raw_consume_fire(control[22]), .o_source_proven(fence_proven),
        .o_source_fault(source_fault), .o_sink_fault(sink_fault)
    );

    // Same combinational START credit and take qualification as the metadata
    // gate/TOP. The already-reserved bit stands in for its surrounding owner.
    wire metadata_reserved = dfi_data_reset_n && control[1] && !control[2] && control[3];
    wire [31:0] capture_id, session_id, mode_epoch, writer_tag, result_id, result_epoch;
    wire [15:0] width, height, jpeg_keep;
    wire [63:0] timestamp_ns;
    wire camera_id, jpeg_last, result_ok, extension_valid, extension_shape_valid, egress_fault, token_pending;
    wire [7:0] quality, result_quality;
    wire [24:0] result_length;
    wire [127:0] jpeg_data;
    wire [39:0] extension_data;
    ordered_frame_egress #(.CONTEXT_ENABLE(1), .WRITE_TAG_ENABLE(1),
        .RECORD_EXTENSION_ENABLE(1), .RECORD_EXTENSION_WIDTH(16384), .EXTENSION_RAM_ENABLE(1)) u_egress (
        .i_clk(clk), .i_rst_n(fifo_sink_reset_n), .i_token_data(token_data), .i_token_valid(token_valid),
        .o_token_ready(egress_token_ready), .o_token_pending(token_pending), .o_start_valid(start_valid),
        .i_start_ready(metadata_reserved && ring_start_ready), .o_capture_id(capture_id),
        .o_width(width), .o_height(height), .o_timestamp_ns(timestamp_ns), .o_session_id(session_id),
        .o_mode_epoch(mode_epoch), .o_camera_id(camera_id), .o_quality(quality), .o_format(),
        .o_write_tag(writer_tag), .o_start_mask(), .o_start_source_type(),
        .o_jpeg_tdata(jpeg_data), .o_jpeg_tkeep(jpeg_keep), .o_jpeg_tlast(jpeg_last),
        .o_jpeg_tvalid(jpeg_valid), .i_jpeg_tready(jpeg_ready), .o_result_valid(result_valid),
        .i_result_ready(result_ready), .o_result_id(result_id), .o_result_ok(result_ok),
        .o_result_length(result_length), .o_result_error(), .o_result_quality(result_quality),
        .o_result_epoch(result_epoch), .o_record_extension(), .o_record_extension_valid(extension_valid),
        .i_record_extension_ready(control[19]), .o_extension_shape_valid(extension_shape_valid),
        .i_extension_read_enable(control[20]), .i_extension_read_index(options[22:14]),
        .o_extension_read_data(extension_data), .o_protocol_fault(egress_fault)
    );

    wire [31:0] ack_id, ack_generation, ack_tag;
    wire [31:0] ready_id, ready_generation, ready_session, ready_epoch, reply_generation;
    wire [63:0] ready_time;
    wire [15:0] ready_width, ready_height, ready_slot, payload_keep, write_strobe;
    wire [24:0] ready_length, ack_length;
    wire [7:0] ready_quality, ack_error, awlen, arlen;
    wire [27:0] awaddr, araddr;
    wire [3:0] retire_code, reply_code;
    wire [127:0] write_data, payload_data;
    wire ack_valid, ack_ok, ready_valid, ready_camera, payload_valid, payload_last;
    wire recovery, awvalid, wvalid, wlast, bready, arvalid, rready;
    wire retire_ready, retire_valid, read_complete, read_error, request_ready, reply_valid;
    jpeg_ring_reset_boundary #(.WRITE_RESULT_ENABLE(1), .WRITE_TAG_ENABLE(1), .CAMERA_COUNT(2)) u_ring (
        .i_clk(clk), .i_cold_rst_n(cold_rst_n), .i_ddr_ready(control[0]),
        .i_start_valid(metadata_reserved), .o_start_ready(ring_start_ready),
        .i_capture_id(capture_id), .i_width(width), .i_height(height), .i_timestamp_ns(timestamp_ns),
        .i_write_tag(writer_tag), .i_session_id(session_id), .i_mode_epoch(mode_epoch), .i_camera_id(camera_id),
        .i_quality(quality), .i_jpeg_tdata(jpeg_data), .i_jpeg_tkeep(jpeg_keep), .i_jpeg_tvalid(jpeg_valid),
        .o_jpeg_tready(jpeg_ready), .i_jpeg_tlast(jpeg_last), .i_result_valid(result_valid),
        .o_result_ready(result_ready), .i_result_id(result_id), .i_result_ok(result_ok),
        .i_result_length(result_length),
        .i_result_quality(result_quality), .i_result_epoch(result_epoch),
        .o_write_result_valid(ack_valid), .i_write_result_ready(control[4]), .o_write_result_ok(ack_ok),
        .o_write_result_error(ack_error), .o_write_result_capture_id(ack_id), .o_write_result_session(),
        .o_write_result_epoch(), .o_write_result_camera(), .o_write_result_slot(),
        .o_write_result_generation(ack_generation), .o_write_result_payload_length(ack_length),
        .o_write_result_tag(ack_tag), .o_ready_valid(ready_valid), .i_ready_claim(control[5]),
        .o_capture_id(ready_id), .o_payload_length(ready_length), .o_width(ready_width),
        .o_height(ready_height), .o_timestamp_ns(ready_time), .o_slot_id(ready_slot),
        .o_generation(ready_generation), .o_session_id(ready_session), .o_mode_epoch(ready_epoch),
        .o_camera_id(ready_camera), .o_quality(ready_quality),
        .o_payload_tdata(payload_data), .o_payload_tkeep(payload_keep), .o_payload_tvalid(payload_valid),
        .i_payload_tready(control[6]), .o_payload_tlast(payload_last),
        .o_stream_recovery_required(recovery),
        .o_axi_awaddr(awaddr), .o_axi_awlen(awlen), .o_axi_awvalid(awvalid), .i_axi_awready(control[7]),
        .o_axi_wdata(write_data), .o_axi_wstrb(write_strobe), .o_axi_wlast(wlast), .o_axi_wvalid(wvalid),
        .i_axi_wready(control[8]), .i_axi_bid(options[3:0]), .i_axi_bresp(options[5:4]),
        .i_axi_bvalid(control[9]), .o_axi_bready(bready), .o_axi_araddr(araddr),
        .o_axi_arlen(arlen), .o_axi_arvalid(arvalid), .i_axi_arready(control[10]),
        .i_axi_rid(options[9:6]), .i_axi_rdata(stimulus[191:64]), .i_axi_rresp(options[11:10]),
        .i_axi_rlast(control[12]), .i_axi_rvalid(control[11]), .o_axi_rready(rready),
        .i_retire_valid(control[13]), .o_retire_ready(retire_ready), .i_retire_slot(stimulus[287:272]),
        .i_retire_generation(stimulus[319:288]), .i_retire_session(stimulus[351:320]),
        .i_retire_error(control[14]), .o_retire_rsp_valid(retire_valid), .i_retire_rsp_ready(control[15]),
        .o_retire_rsp_code(retire_code), .o_read_complete(read_complete), .o_read_error(read_error),
        .o_record_quiescent(record_quiet), .o_write_quiescent(write_quiet),
        .i_req_valid(control[16]), .o_req_ready(request_ready), .i_req_op(options[13:12]),
        .i_req_camera(control[17]), .i_req_slot(stimulus[207:192]), .i_req_generation(stimulus[239:208]),
        .i_req_session(stimulus[271:240]), .o_rsp_valid(reply_valid), .i_rsp_ready(control[18]),
        .o_rsp_code(reply_code), .o_rsp_generation(reply_generation),
        .i_start_mask(1'b0), .i_mask_allocation_ready(1'b0), .i_start_source_type(3'd0),
        .i_mask_result_valid(1'b0), .i_mask_result_context(160'd0), .i_mask_result_tag(32'd0),
        .i_mask_result_generation(32'd0), .i_mask_result_slot(16'd0), .i_mask_result_ok(1'b0),
        .i_mask_result_error(8'd0), .i_mask_result_width(13'd0), .i_mask_result_height(13'd0),
        .i_mask_result_written_bytes(17'd0), .i_mask_result_terminal_body(48'd0),
        .i_req_mask(1'b0), .i_req_read_lock(1'b0), .i_mask_read_lease_release(1'b0)
    );

    // The full_raw_store normal-retirement terms are prequalified by the
    // sampled mode field. The release/clear decision matches hdr_eye_shared.
    wire hdr_write_quiet = write_quiet && (control[30] || control[31]);
    wire hdr_release_ready = !control[26] && control[23] && hdr_write_quiet && control[24] && !control[25];
    (* preserve="true" *) reg token_ready_q, write_quiet_q, hdr_release_q, hdr_clear_q;
    always @(posedge clk) begin
        token_ready_q <= egress_token_ready;
        write_quiet_q <= write_quiet;
        hdr_release_q <= hdr_release_ready && control[27];
        hdr_clear_q <= hdr_release_ready && control[27] && control[28] && control[29];
    end
    assign feedback = {token_ready_q, write_quiet_q, hdr_release_q, hdr_clear_q};

    always @(*) begin
        case (observe_word)
            5'd0: observe = write_data[31:0];
            5'd1: observe = write_data[63:32];
            5'd2: observe = write_data[95:64];
            5'd3: observe = write_data[127:96];
            5'd4: observe = payload_data[31:0];
            5'd5: observe = payload_data[63:32];
            5'd6: observe = payload_data[95:64];
            5'd7: observe = payload_data[127:96];
            5'd8: observe = {4'd0,awaddr};
            5'd9: observe = {4'd0,araddr};
            5'd10: observe = {awlen,arlen,write_strobe};
            5'd11: observe = ready_id;
            5'd12: observe = ready_generation;
            5'd13: observe = ready_session;
            5'd14: observe = ready_epoch;
            5'd15: observe = ready_time[31:0];
            5'd16: observe = ready_time[63:32];
            5'd17: observe = {ready_width,ready_height};
            5'd18: observe = {ready_slot,payload_keep};
            5'd19: observe = {ready_length,ready_camera,ready_quality[5:0]};
            5'd20: observe = ack_id;
            5'd21: observe = ack_generation;
            5'd22: observe = ack_tag;
            5'd23: observe = {ack_length,ack_error[6:0]};
            5'd24: observe = extension_data[31:0];
            5'd25: observe = {24'd0,extension_data[39:32]};
            5'd26: observe = reply_generation;
            5'd27: observe = {17'd0,reply_code,retire_code,read_complete,read_error,
                retire_ready,retire_valid,request_ready,reply_valid,recovery};
            5'd28: observe = {16'd0,source_ready,source_done,sink_done,fence_proven,
                source_fault,sink_fault,token_pending,extension_valid,extension_shape_valid,
                egress_fault,ring_start_ready,jpeg_ready,result_ready,record_quiet,write_quiet,ready_valid};
            5'd29: observe = {16'd0,ready_quality,ack_error};
            default: observe = {22'd0,ack_valid,ack_ok,payload_valid,payload_last,
                awvalid,wvalid,wlast,bready,arvalid,rready};
        endcase
    end
endmodule
