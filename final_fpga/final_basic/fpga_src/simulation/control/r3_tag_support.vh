    // Included after the real admission instance in the fixed R1 fixture.
    localparam integer RECORD_METADATA_ENABLE=1;
    reg private_processing_selected=0;
    reg [31:0] processing_write_tag=32'he0010001;
    wire record_format_busy=1'b0;
    wire host_replay_context_valid=1'b0,host_replay_context_ready=1'b0;
    wire [383:0] host_replay_context_frame=0;
    wire host_replay_metadata_valid=1'b0;
    wire native_job_start=1'b0,native_job_replay=1'b0;
    wire raw_replay_native_done=1'b0,raw_replay_native_error=1'b0;
    `include "r3_tag_declarations.vh"
    `include "r3_actual_tag_logic.vh"
    `include "r3_reference_tag_logic.vh"
    reg r3_metadata_ready=1;
    wire r3_begin_ready,r3_ref_begin_ready,r3_extension_valid,r3_ref_extension_valid;
    wire [1023:0] r3_extension,r3_ref_extension;
    wire r3_input_fault,r3_ref_input_fault;
    // Other capacity consumers are ready in this bounded fixture. Production
    // PRIVATE_PROCESSING_ENABLE=1 selects writer tags from its own authority.
    assign record_product_available=r3_begin_ready&&!record_product_tag_exhausted;
    wire [159:0] r3_stats_context={16'd1,16'd0,8'd1,8'd1,8'd1,8'd0,sequence_id,32'd3,32'd7};
    wire [183:0] r3_statistics={8'd1,8'd0,8'd1,16'd1,16'd1,96'd0,16'd1,16'd1};
    frame_record_extension_builder #(.NEUTRAL_STATS_ENABLE(R3_STATS_ENABLE),
        .OBSERVATION_WIDTH(1),.OBSERVATION_HEIGHT(1)) r3_actual_builder(
        .i_clk(pixel_clk),.i_rst_n(pixel_rst_n),.s_begin_valid(admission_take),.o_begin_ready(r3_begin_ready),
        .i_source_session(32'd7),.i_source_epoch(32'd3),.i_source_sequence(sequence_id),
        .i_source_camera(8'd0),.i_source_kind(8'd1),.i_source_format(8'd1),.i_exposure_role(8'd0),
        .i_exposure_valid(1'b0),.i_actual_exposure(32'd0),.i_exposure_group(32'd0),
        .i_gain_valid(1'b0),.i_actual_gain(32'd0),.i_calibration_valid(1'b0),.i_calibration_id(32'd0),
        .i_time_quality(8'd0),.i_pair_valid(1'b0),.i_pair_id(64'd0),.i_job_valid(1'b0),.i_job_id(64'd0),
        .i_write_tag_valid(1'b1),.i_write_tag(record_product_next_tag),.i_qualified(1'b1),
        .i_processing_member(8'd0),.i_processing_mode(8'd0),.i_record_flags(16'd0),
        .s_stats_valid(1'b1),.o_stats_ready(),.s_stats_context(r3_stats_context),.s_statistics(r3_statistics),
        .m_extension_valid(r3_extension_valid),.m_extension_ready(r3_metadata_ready),.m_extension_data(r3_extension),
        .o_stale_count(),.o_error_count(),.o_input_fault(r3_input_fault));
    frame_record_extension_builder #(.NEUTRAL_STATS_ENABLE(R3_STATS_ENABLE),
        .OBSERVATION_WIDTH(1),.OBSERVATION_HEIGHT(1)) r3_reference_builder(
        .i_clk(pixel_clk),.i_rst_n(pixel_rst_n),.s_begin_valid(admission_take),.o_begin_ready(r3_ref_begin_ready),
        .i_source_session(32'd7),.i_source_epoch(32'd3),.i_source_sequence(sequence_id),
        .i_source_camera(8'd0),.i_source_kind(8'd1),.i_source_format(8'd1),.i_exposure_role(8'd0),
        .i_exposure_valid(1'b0),.i_actual_exposure(32'd0),.i_exposure_group(32'd0),
        .i_gain_valid(1'b0),.i_actual_gain(32'd0),.i_calibration_valid(1'b0),.i_calibration_id(32'd0),
        .i_time_quality(8'd0),.i_pair_valid(1'b0),.i_pair_id(64'd0),.i_job_valid(1'b0),.i_job_id(64'd0),
        .i_write_tag_valid(1'b1),.i_write_tag(r1_record_product_next_tag),.i_qualified(1'b1),
        .i_processing_member(8'd0),.i_processing_mode(8'd0),.i_record_flags(16'd0),
        .s_stats_valid(1'b1),.o_stats_ready(),.s_stats_context(r3_stats_context),.s_statistics(r3_statistics),
        .m_extension_valid(r3_ref_extension_valid),.m_extension_ready(r3_metadata_ready),.m_extension_data(r3_ref_extension),
        .o_stale_count(),.o_error_count(),.o_input_fault(r3_ref_input_fault));
    integer r3_tag_checks=0,r3_tag_takes=0,r3_metadata_transfers=0,r3_metadata_stalls=0;
    integer r3_private_takes=0,r3_product_max_takes=0,r3_writer_max_takes=0,r3_pending_reset=0;
    integer r3_cycle=0,r3_previous_take=-100,r3_blocked=0;
    reg r3_meta_owned=0;
    reg [63:0] r3_expected_product=0,r3_last_product=0;
    reg [31:0] r3_expected_writer=0;
    task r3_check(input bit okay,input string why);
        begin r3_tag_checks++;if(!okay)$fatal(1,"R3 tags stats=%0d: %s product=%h/%h writer=%h/%h pending=%b%b",R3_STATS_ENABLE,why,
            record_product_next_tag,r1_record_product_next_tag,record_writer_next_tag,r1_record_writer_next_tag,
            record_product_advance_pending,record_writer_advance_pending);end
    endtask
    always @(posedge pixel_clk)begin
        r3_cycle++;
        if(!pixel_rst_n)r3_meta_owned=0;
        else begin
            if(r3_extension_valid&&r3_metadata_ready)begin r3_meta_owned=0;r3_metadata_transfers++;end
            if(r3_extension_valid&&!r3_metadata_ready)r3_metadata_stalls++;
            if(admission_take)begin
                r3_check(r3_cycle-r3_previous_take>=2,"real admission cannot take consecutive cycles");r3_previous_take=r3_cycle;
                r3_check(record_product_next_tag==r1_record_product_next_tag&&record_writer_next_tag==r1_record_writer_next_tag,
                    "both next namespaces exact on the real allocation edge");
                r3_expected_product=r1_record_product_next_tag;r3_last_product=r3_expected_product;
                r3_expected_writer=private_processing_selected?processing_write_tag:r1_record_writer_next_tag;
                r3_meta_owned=1;r3_tag_takes++;
                if(private_processing_selected)r3_private_takes++;
                if(&record_product_next_tag)r3_product_max_takes++;
                if(!private_processing_selected&&(&record_writer_next_tag))r3_writer_max_takes++;
            end
        end
        #1;
        r3_check({record_admitted_write_tag,record_admitted_writer_tag,record_product_tag_exhausted,record_writer_tag_exhausted,
            record_replay_binding_fault,host_replay_context_owned}===
            {r1_record_admitted_write_tag,r1_record_admitted_writer_tag,r1_record_product_tag_exhausted,r1_record_writer_tag_exhausted,
            r1_record_replay_binding_fault,r1_host_replay_context_owned},"allocated tags, exhaustion and authority controls exact every cycle");
        r3_check((record_product_next_tag+{63'd0,record_product_advance_pending})==r1_record_product_next_tag,
            "only the documented one-cycle unowned product increment may differ");
        r3_check((record_writer_next_tag+{31'd0,record_writer_advance_pending})==r1_record_writer_next_tag,
            "only the documented one-cycle unowned writer increment may differ");
        r3_check({r3_begin_ready,r3_extension_valid,r3_input_fault}==={r3_ref_begin_ready,r3_ref_extension_valid,r3_ref_input_fault},
            "actual metadata handshakes remain cycle-equivalent");
        if(r3_extension_valid)r3_check(r3_extension===r3_ref_extension,"all1024 owned record metadata bits exact including stalls");
        if(r3_meta_owned)begin
            r3_check(record_admitted_write_tag==r3_expected_product&&record_admitted_writer_tag==r3_expected_writer,
                "take edge owns exact PRODUCT64 and writer32 tags");
            r3_check(r3_extension[(`PCIE_RECORD_V2_OFFSET_WRITE_TAG-64)*8+:64]==r3_expected_product,
                "builder never rereads changed next tag after accepted begin");
        end
    end
    task r3_seed_counters(input [63:0] product,input [31:0] writer);
        begin
            wait(admission_state_idle&&r3_begin_ready);@(negedge pixel_clk);
            r3_check(!record_product_advance_pending&&!record_writer_advance_pending,"force boundary only after pending drains");
            force record_product_next_tag=product;force r1_record_product_next_tag=product;
            force record_writer_next_tag=writer;force r1_record_writer_next_tag=writer;
            #1;release record_product_next_tag;release r1_record_product_next_tag;
            release record_writer_next_tag;release r1_record_writer_next_tag;
            @(negedge pixel_clk);
        end
    endtask
    task r3_extra_cases;
        begin
            // A private take does not consume the local writer namespace;
            // changing selection after take cannot alter the latched decision.
            reset_case();private_processing_selected=1;processing_write_tag=32'he1234567;
            begin_frame(16'd4,0);private_processing_selected=0;processing_write_tag=32'hdeadbeef;
            complete_frame(0,0);r3_check(record_writer_next_tag==1,"private writer bypass survives post-take input noise");
            private_processing_selected=0;begin_frame(16'd5,0);private_processing_selected=1;
            complete_frame(0,0);r3_check(record_writer_next_tag==2,"nonprivate pending remembers its admission-edge owner");
            private_processing_selected=0;
            // Hold metadata past JPEG credit retirement; no second allocation
            // is permitted until the original full record tuple transfers.
            reset_case();r3_metadata_ready=0;begin_frame(16'd6,0);complete_frame(0,0);
            cycle_noise(20);r3_check(r3_extension_valid&&!record_product_available,"held metadata keeps capacity reserved");
            grant=1;rgb_valid=1;sof=1;done=1;#1;r3_check(!admission_take,"blocked offer cannot consume a namespace");
            @(negedge pixel_clk);grant=0;rgb_valid=0;sof=0;done=0;r3_blocked++;
            r3_metadata_ready=1;cycle_noise(3);begin_frame(16'd7,0);complete_frame(0,0);
            // Last PRODUCT64 value is allocated once, with MAX flag immediate.
            reset_case();r3_seed_counters(64'hfffffffffffffffe,32'd100);
            begin_frame(16'd8,0);complete_frame(0,0);
            begin_frame(16'd9,0);r3_check(record_product_tag_exhausted&&r3_last_product==64'hffffffffffffffff,
                "last product tag and exhaustion published on original take edge");complete_frame(0,0);
            grant=1;rgb_valid=1;sof=1;done=1;#1;r3_check(!admission_take&&record_product_next_tag==64'hffffffffffffffff,
                "exhausted product neither wraps nor allocates again");
            @(negedge pixel_clk);grant=0;rgb_valid=0;sof=0;done=0;r3_blocked++;
            // Writer MAX is retained; the private writer still supplies its
            // independent32-bit namespace instead of consuming the exhausted one.
            reset_case();r3_seed_counters(64'd1000,32'hfffffffe);
            begin_frame(16'd10,0);complete_frame(0,0);
            begin_frame(16'd11,0);r3_check(record_writer_tag_exhausted&&record_admitted_writer_tag==32'hffffffff,
                "last local writer tag and flag immediate");complete_frame(0,0);
            private_processing_selected=1;processing_write_tag=32'he7654321;
            begin_frame(16'd12,0);complete_frame(0,0);
            r3_check(record_writer_next_tag==32'hffffffff&&record_admitted_writer_tag==32'he7654321,
                "private writer bypasses without local counter wrap");private_processing_selected=0;
            // Assert reset after take, before its pending increment edge.
            reset_case();r3_seed_counters(64'd40,32'd400);begin_frame(16'd13,0);
            r3_check(record_product_advance_pending&&record_writer_advance_pending,"pending exists before interrupt");
            pixel_rst_n=0;#1;r3_pending_reset++;
            r3_check(!record_product_advance_pending&&!record_writer_advance_pending&&record_product_next_tag==1&&record_writer_next_tag==1,
                "async reset cancels pending without replay into a new cohort");
            reset_case();begin_frame(16'd14,0);r3_check(r3_last_product==1&&record_admitted_writer_tag==1,"new cohort starts with namespace1");
            complete_frame(0,0);cycle_noise(3);
            r3_check(r3_private_takes>=2&&r3_product_max_takes==1&&r3_writer_max_takes==1&&r3_pending_reset==1&&r3_blocked==2&&r3_metadata_stalls>20,
                "all namespace risk cases covered");
            $display("RESULT: PASS r3_tags stats=%0d checks=%0d takes=%0d private=%0d product_max=%0d writer_max=%0d pending_reset=%0d metadata_transfers=%0d metadata_stalls=%0d blocked=%0d",
                R3_STATS_ENABLE,r3_tag_checks,r3_tag_takes,r3_private_takes,r3_product_max_takes,r3_writer_max_takes,r3_pending_reset,r3_metadata_transfers,r3_metadata_stalls,r3_blocked);
        end
    endtask
