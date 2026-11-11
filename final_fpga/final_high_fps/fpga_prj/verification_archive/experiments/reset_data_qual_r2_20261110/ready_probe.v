module uhd_probe (
    input wire clk, rst_n, write_word,
    input wire [4:0] word_index,
    input wire [31:0] stimulus_word,
    input wire [3:0] observe_word,
    output reg [31:0] observe,
    output wire [2:0] qualification
);
    // Narrow carrier IO. Independent sampled fields retain control and data cones.
    reg [1023:0] stimulus;
    genvar word_number;
    generate for (word_number=0; word_number<32; word_number=word_number+1) begin : g_word
        always @(posedge clk)
            if (write_word && word_index == word_number)
                stimulus[word_number*32 +: 32] <= stimulus_word;
    end endgenerate

    wire [31:0] control = stimulus[31:0];
    wire [31:0] options = stimulus[63:32];
    wire [31:0] session = stimulus[95:64], epoch = stimulus[127:96];
    wire [31:0] sequence_number = stimulus[159:128];
    wire [63:0] job = {32'd0,stimulus[191:160]}, pair = {32'd0,stimulus[223:192]};
    wire [63:0] lease = {32'd0,stimulus[255:224]}, tag = {32'd0,stimulus[287:256]};
    wire [31:0] writer_tag = stimulus[319:288];
    wire [55:0] replay_raw = stimulus[375:320];
    wire [39:0] cropped_raw = stimulus[415:376];
    wire [95:0] isp_rgb = stimulus[511:416];
    wire [7:0] replay_source_error = stimulus[519:512], capture_source_error = stimulus[527:520];
    wire [1:0] bayer_phase = stimulus[529:528];
    wire uhd = control[31];
    wire camera = options[8], member = options[9];
    wire [15:0] width = uhd ? 16'd3840 : 16'd1920;
    wire [15:0] height = uhd ? 16'd2160 : 16'd1080;
    wire [383:0] frame = {147'd0,height,width,96'd0,sequence_number,session,40'd0,camera,4'd0};
    wire [63:0] key = {session,31'd0,camera};

    wire context_available, payload_enable, pool_idle, raw_ready, source_ready;
    wire private_raw_valid, private_raw_sof, private_raw_eol;
    wire isp_reset_n, isp_release_n, isp_rgb_ready, cleanup, pixel_fault;
    wire [95:0] output_rgb;
    wire output_valid, output_context_valid, output_status_valid, output_status_ok;
    wire [7:0] output_status_error;
    wire [31:0] output_groups, output_index, stale_count;

    // The production wide ISP uses a separate release chain and a registered
    // kernel enable. The input-room condition is an external sampled field here.
    reset_release_sync u_model_isp_reset (
        .i_clk(clk), .i_async_rst_n(rst_n && isp_reset_n), .o_rst_n(isp_release_n)
    );
    reg core_run;
    always @(posedge clk) core_run <= isp_release_n;
    wire isp_input_ready = isp_release_n && core_run && options[4];
    wire isp_idle = isp_release_n && core_run && control[21];

    // Same replay SOF and crop accept relationships as the production wrapper.
    wire private_selected = control[9], replay_selected = control[10];
    wire replay_valid = private_selected ? private_raw_valid : control[5];
    wire replay_sof = private_selected ? private_raw_sof : control[6];
    wire replay_abort = private_selected ? 1'b0 : control[11];
    wire replay_enabled = private_selected ? payload_enable && control[3] : options[10];
    wire replay_paused = !private_selected && options[11];
    wire replay_start_allowed = !replay_sof || (replay_enabled && !replay_paused);
    wire isp_raw_ready = replay_selected && !replay_abort && replay_start_allowed && isp_input_ready;
    wire crop_ready = replay_selected ? !(replay_valid && replay_sof && isp_raw_ready) :
        (!control[12] || control[13] ? 1'b1 : isp_input_ready);

    private_raw_isp_borrow4 #(.MAX_WIDTH(3840), .MAX_HEIGHT(2160),
        .RAW_SAMPLE_BITS(14), .EXTERNAL_ISP_ENABLE(1), .ORIGINAL_SYNC_CLEAR_ENABLE(1)) u_original (
        .i_pixel_clk(clk), .i_pixel_rst_n(rst_n),
        .i_context_fire(control[0]), .i_context_private(control[1]),
        .i_context_frame(frame ^ {383'd0,options[2]}), .i_context_job(job),
        .i_context_pair(pair), .i_context_key(key), .i_context_aux(job), .i_context_member(member),
        .o_context_available(context_available), .o_payload_enable(payload_enable), .o_pool_idle(pool_idle),
        .i_owner_published(control[2]), .i_owner_valid(control[3]), .i_owner_frame(frame),
        .i_owner_lease(lease), .i_owner_job(job), .i_owner_pair(pair), .i_owner_native_tag(tag),
        .i_owner_writer_tag(writer_tag), .i_owner_member(member),
        .i_bayer_phase(bayer_phase), .i_wb_gains({3{10'd256}}), .i_hdr_enable(control[4]), .i_tone_shift(4'd4),
        .o_isp_raw_data(), .o_isp_raw_valid(private_raw_valid), .o_isp_raw_sof(private_raw_sof),
        .o_isp_raw_eol(private_raw_eol), .i_isp_raw_ready(isp_raw_ready), .i_isp_rgb(isp_rgb),
        .i_isp_rgb_valid(control[18]), .i_isp_rgb_sof(control[19]), .i_isp_rgb_eol(control[20]), .i_isp_idle(isp_idle),
        .o_isp_rgb_ready(isp_rgb_ready), .o_isp_reset_n(isp_reset_n), .o_isp_bayer_phase(), .o_isp_wb_gains(),
        .o_isp_hdr_enable(), .o_isp_tone_shift(),
        .s_raw_data(replay_raw), .s_raw_valid(control[5]), .s_raw_sof(control[6]), .s_raw_eol(control[7]),
        .s_raw_ready(raw_ready), .s_raw_source_valid(control[8]), .s_raw_source_ready(source_ready),
        .s_raw_source_frame(frame ^ {383'd0,options[3]}), .s_raw_source_lease(lease),
        .s_raw_source_job(job), .s_raw_source_pair(pair), .s_raw_source_tag(tag ^ {63'd0,options[14]}),
        .s_raw_source_member(member ^ options[1]), .s_raw_source_ok(options[0]),
        .s_raw_source_error(replay_source_error), .i_raw_source_read_quiescent(control[22]),
        .i_pixel_cancel(control[23]), .i_pipeline_quiescent(control[24]), .i_post_pool_idle(control[25]),
        .i_post_pixel_fault(control[26]), .i_processed_source_fire(control[27]),
        .m_context(), .m_context_valid(output_context_valid), .m_context_ready(control[28]),
        .m_rgb(output_rgb), .m_keep(), .m_sof(), .m_eol(), .m_last(), .m_valid(output_valid), .m_ready(control[29]),
        .m_tag(), .m_index(output_index), .m_status_valid(output_status_valid), .m_status_ready(control[30]),
        .m_status_context(), .m_status_tag(), .m_status_ok(output_status_ok), .m_status_error(output_status_error),
        .m_status_groups(output_groups), .o_original_read_quiescent(), .o_locked_owner_valid(), .o_locked_frame(),
        .o_locked_lease(), .o_locked_job(), .o_locked_pair(), .o_locked_native_tag(), .o_locked_writer_tag(),
        .o_locked_member(), .o_pixel_fault(pixel_fault), .o_isp_idle(), .o_isp_cleanup(cleanup),
        .o_stale_raw_source_count(stale_count)
    );

    wire [127:0] axis_data;
    wire [15:0] axis_keep;
    wire axis_valid, axis_last, ingress_accept, ingress_idle;
    wire [1:0] axis_user;
    shared_raw10_frame_ingress #(.CONTEXT_ENABLE(1), .EXTERNAL_SEQUENCE_ENABLE(1),
        .PAIR_METADATA_ENABLE(1), .SOURCE_TERMINAL_ENABLE(1), .COMPACT_CAPTURE_HEADER(1),
        .UHD_WIDTH(3840), .UHD_HEIGHT(2160)) u_ingress (
        .i_clk(clk), .i_rst_n(rst_n), .i_enable(options[5]), .i_data(cropped_raw),
        .i_valid(control[14]), .i_accept(crop_ready), .i_sof(control[15]), .i_eol(control[16]),
        .i_abort(control[17]), .i_camera(camera), .i_epoch(epoch), .i_external_sequence(sequence_number),
        .i_session_id(session), .i_sdr_profile(options[12]), .i_bayer_valid(1'b1), .i_time_valid(1'b1),
        .i_bayer_pattern(bayer_phase), .i_metadata_valid(1'b1), .i_timestamp(stimulus[607:544]),
        .i_actual_exposure(stimulus[639:608]), .i_gain(stimulus[671:640]),
        .i_calibration_id(stimulus[703:672]), .i_source_kind(options[15]), .i_exposure_role(options[17:16]),
        .i_exposure_group(stimulus[735:704]), .i_source_qualified(options[18]),
        .i_source_valid(options[6]), .o_source_ready(), .i_source_session(session),
        .i_source_epoch(epoch ^ {31'd0,options[13]}), .i_source_sequence(sequence_number),
        .i_source_camera(camera), .i_source_ok(options[7]), .i_source_error(capture_source_error),
        .o_source_stale_count(), .o_axis_tdata(axis_data), .o_axis_tkeep(axis_keep),
        .o_axis_tvalid(axis_valid), .i_axis_tready(options[19]), .o_axis_tlast(axis_last),
        .o_axis_tuser(axis_user), .o_capture_idle(ingress_idle), .o_frame_accept(ingress_accept),
        .o_drop_count(), .o_error_count(), .i_uhd(uhd)
    );

    (* preserve="true" *) reg [2:0] qualification_q;
    always @(posedge clk) qualification_q <= {payload_enable,source_ready,raw_ready};
    assign qualification = qualification_q;

    always @(*) begin
        case (observe_word)
            4'd0: observe = axis_data[31:0];
            4'd1: observe = axis_data[63:32];
            4'd2: observe = axis_data[95:64];
            4'd3: observe = axis_data[127:96];
            4'd4: observe = output_rgb[31:0];
            4'd5: observe = output_rgb[63:32];
            4'd6: observe = output_rgb[95:64];
            4'd7: observe = output_groups;
            4'd8: observe = output_index;
            4'd9: observe = stale_count;
            4'd10: observe = {12'd0,axis_keep,axis_valid,axis_last,axis_user};
            default: observe = {12'd0,context_available,pool_idle,cleanup,pixel_fault,
                isp_reset_n,isp_rgb_ready,output_valid,output_context_valid,
                output_status_valid,output_status_ok,ingress_idle,ingress_accept,output_status_error};
        endcase
    end
endmodule
