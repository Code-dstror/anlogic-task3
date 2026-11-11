`timescale 1ns/1ps
`include "pcie_protocol_v1.vh"
// PIX transaction owner for dedicated ordered 40-bit configuration words.
// Prepared storage is the immutable COMMIT callback owner; no remote copy.
module mono_config_engine_v2 #(
    parameter integer WIDTH=1920,HEIGHT=1080,LANE_GAUSSIAN_ONLY=1,
    parameter integer TRUSTED_COMMANDS=0,CFG_DIAG_ENABLE=0,
    parameter [7:0] LEGACY_SUPPORTED=0,
    parameter [2:0] V2_SUPPORTED_MODES=0,
    parameter [5:0] V2_SUPPORTED_ENABLES=0,
    parameter integer APPLY_SOURCE_FAULT_ENABLE=0,
    // Remote owners may have already proved the complete old-frame drain.
    // Their first new capture is independent of the shared processing engine.
    parameter integer FRAME_APPLY_REQUIRE_IDLE=1
) (
    input wire clk,rst_n,
    input wire [39:0] command_data,input wire command_valid,output wire command_ready,
    output wire [39:0] response_data,output wire response_valid,input wire response_ready,
    input wire pipeline_idle,frame_accept,input wire [31:0] frame_sequence,
    output wire source_ready,pause_new_jobs,output wire [1:0] active_mode,
    output wire [7:0] active_quality,minimum_quality,output wire adaptive_quality,
    output wire [24:0] frame_budget,output wire [15:0] restart_mcus,
    output wire [31:0] source_session,mode_epoch,output wire pixel_initialized,
    output wire [1183:0] m_config_data,output wire m_config_valid,input wire m_config_ready,
    input wire [1183:0] s_config_ack_data,input wire s_config_ack_valid,s_config_ack_ok,
    output wire s_config_ack_ready,output wire config_fault,output wire [31:0] config_stale_ack_count,
    output wire [1183:0] active_config,
    output wire active_schema2,active_legacy_gaussian,
    output wire [1:0] active_product_mode,
    output wire [5:0] active_processing_enables,
    input wire diag_observer_rst_n,diag_source_fs,
    input wire [15:0] diag_source_gates,
    output wire [223:0] diag_data,
    input wire i_apply_source_fault,
    output wire [11:0] o_apply_diagnostics
);
    `include "mono_config_transport_v2.vh"
    localparam [2:0] IDLE=0,WAIT_IDLE=1,PREPARED=2,WAIT_FRAME=3,BOOT_BARRIER=4,FAULT=5;
    reg [2:0] state,policy_state_next,policy_pause_state_next;
    reg policy_initialized_next,policy_applied_next,policy_fault_next;
    reg frame_eligibility_next;
    reg pause_policy;
    (* preserve="true" *) reg frame_apply_eligible;
    reg initialized;
    reg [341:0] prepared_fields;
    wire [341:0] prepared={prepared_fields[341],
        prepared_fields[341] ? prepared_fields[340:128] :
        {5'd0,prepared_fields[340:168],prepared_fields[130],
         prepared_fields[167:136],prepared_fields[129:128]},prepared_fields[127:0]};
    reg [373:0] applied;
    reg applied_write_pending;
    reg [31:0] session,epoch,stale_ack_count;
    reg remote_pending,remote_sent,remote_applied,remote_fault,remote_boot,fault_reply_pending;
    reg boot_reply_pending;
    reg [36:0] ack_word_match;
    reg ack_compare_valid,ack_compare_eligible,ack_compare_ok,ack_compare_boot;
    reg ack_result_valid,ack_result_match,ack_result_eligible,ack_result_ok,ack_result_boot;
    integer ack_word_index;
    wire [373:0] prepared_plan={prepared[341:128],epoch+32'd1,prepared[127:0]};
    // The public apply edge still publishes prepared_plan immediately. Its
    // wide bank write uses the following clock's registered enable instead
    // of the late pipeline-idle / response-space / frame-accept predicate.
    // During that one clock epoch has already advanced, while prepared is
    // held by the APPLIED response owner; no second wide snapshot is needed.
    wire [373:0] applied_view=applied_write_pending ?
        {prepared[341:128],epoch,prepared[127:0]} : applied;
    // Decode each immutable compact owner once. BOOT has no extension;
    // selecting its scalar defaults must not select/redecode 214 extension bits.
    wire [1183:0] prepared_tuple=mono_unpack_tuple(prepared_plan);
    wire [1183:0] applied_tuple=mono_unpack_tuple(applied_view);
    wire [1183:0] remote_tuple=remote_boot ? {1024'd0,applied_view[159:0]} : prepared_tuple;
    // The reply owns one bit. The four-flit cursor advances only on a real
    // response handshake and wraps to zero at retirement. A new reply never
    // needs the late frame/idle qualifier on the cursor's enables.
    reg tx_active;
    reg [1:0] tx_index;
    wire [2:0] tx_state=tx_active ? {1'b0,tx_index}+3'd1 : 3'd0;
    reg [1:0] reply_kind;
    reg [2:0] reply_error;
    reg [31:0] reply_last;
    reg rx_active,rx_done,rx_ext,rx_capture,rx_shape_bad,rx_fields_bad,rx_identity_bad;
    reg rx_schema2;
    reg [1:0] rx_kind;
    reg [5:0] rx_index;
    reg [31:0] rx_session,rx_sequence,rx_mode;
    reg [6:0] rx_quality;
    reg rx_adaptive;
    wire scanner_start_ready,scanner_word_ready,scanner_result_valid;
    wire [2:0] scanner_error;
    wire is_header=command_data[39];
    wire [31:0] word=command_data[31:0];
    wire tx_last_fire=response_valid&&response_ready&&tx_state==4;
    wire response_space=tx_state==0||tx_last_fire;
    wire ack_fire=s_config_ack_valid&&s_config_ack_ready;
    wire ack_match=ack_result_valid&&ack_result_eligible&&ack_result_match;
    wire boot_complete=boot_reply_pending&&response_space;
    wire accepting_header=!rx_active&&!rx_done;
    assign command_ready=rst_n&&!rx_done&&
        (rx_active ? (!(rx_ext&&rx_kind==0&&rx_index==8)||scanner_start_ready) &&
                     (!(rx_ext&&rx_kind==0&&rx_index>=9)||scanner_word_ready) :
         (state==IDLE||state==PREPARED)&&response_space);
    wire command_fire=command_valid&&command_ready;
    wire payload_fire=command_fire&&rx_active;
    wire scan_start=payload_fire&&rx_ext&&rx_kind==0&&rx_index==8;
    wire scan_word=payload_fire&&rx_ext&&rx_kind==0&&rx_index>=9;
    wire decide=rx_done&&response_space&&(rx_shape_bad||!rx_ext||rx_kind!=0||scanner_result_valid);
    // The service's sole command producer is the BAR owner: it locks and
    // validates every raw extension word before serializing that same shadow.
    // That private FIFO channel needs one validator at its entrance. Keep the
    // standalone engine strict; packet shape, scalar values, COMMIT identity
    // and the full remote ACK still remain checked in both specializations.
    generate if(TRUSTED_COMMANDS!=0)begin:g_bar_validated
        assign scanner_start_ready=1'b1;
        assign scanner_word_ready=1'b1;
        assign scanner_result_valid=1'b1;
        assign scanner_error=`PCIE_CFG_ERROR_OK;
    end else begin:g_untrusted_commands
        mono_config_scan_v2 #(.WIDTH(WIDTH),.HEIGHT(HEIGHT),.LANE_GAUSSIAN_ONLY(LANE_GAUSSIAN_ONLY),
            .LEGACY_SUPPORTED(LEGACY_SUPPORTED),.V2_SUPPORTED_MODES(V2_SUPPORTED_MODES),.V2_SUPPORTED_ENABLES(V2_SUPPORTED_ENABLES)) u_scan(
            .clk(clk),.rst_n(rst_n),.cancel(rx_done&&rx_shape_bad),.start_valid(scan_start),.start_ready(scanner_start_ready),.start_mode(rx_mode),
            .word_valid(scan_word),.word_ready(scanner_word_ready),.word_data(word),
            .result_valid(scanner_result_valid),.result_ready(decide),.result_error(scanner_error));
    end endgenerate
    // Register only the stable policy portion, from the exact next values
    // installed on the same edge below. This is an invariant of the current
    // state, not a delayed frame/ACK event: actual frame acceptance, pipeline
    // quiet and response capacity still qualify the original apply edge.
    // The digital ACK has committed the new source policy. A terminal sensor
    // error can now preclude the very frame needed to complete this COMMIT.
    wire source_apply_failed=APPLY_SOURCE_FAULT_ENABLE!=0&&frame_apply_eligible&&i_apply_source_fault;
    wire apply_failed=source_apply_failed||(ack_match&&!ack_result_ok);
    wire apply_frame=frame_apply_eligible&&(!FRAME_APPLY_REQUIRE_IDLE||pipeline_idle)&&
        frame_accept&&response_space&&!source_apply_failed;
    // UART-only, sampled by the existing local-domain held snapshot bank.
    assign o_apply_diagnostics={state,frame_apply_eligible,remote_pending,remote_sent,
        remote_applied,remote_fault,response_space,tx_active,source_ready,frame_accept};
    generate if(CFG_DIAG_ENABLE!=0)begin:g_cfg_diag
        // Mirror the existing *completed* COMMIT decision, never a header or
        // ACK-valid approximation. No diagnostic signal returns to policy.
        wire commit_accepted=decide&&!rx_shape_bad&&initialized&&rx_session==session&&
            rx_kind==1&&state==PREPARED&&!rx_identity_bad&&!rx_fields_bad&&
            (rx_ext||prepared[341:128]==0);
        wire [31:0] live_flags=({29'd0,state}<<21)|({31'd0,rst_n}<<25)|
            ({31'd0,frame_accept}<<20)|({31'd0,source_ready}<<19)|({31'd0,remote_fault}<<18)|
            ({31'd0,remote_applied}<<17)|({31'd0,remote_sent}<<16)|({31'd0,remote_pending}<<15)|
            ({31'd0,pause_policy}<<14)|({31'd0,response_space}<<13)|
            ({31'd0,pipeline_idle}<<12)|({31'd0,frame_apply_eligible}<<11);
        cfg_diag_pixel u_capture(
            .i_clk(clk),.i_observer_rst_n(diag_observer_rst_n),.i_app_rst_n(rst_n),
            .i_commit_accepted(commit_accepted),.i_session(session),.i_request_sequence(rx_sequence),
            .i_target_epoch(prepared_plan[159:128]),
            .i_remote_sent(m_config_valid&&m_config_ready&&!remote_boot),
            .i_positive_ack(ack_match&&ack_result_ok&&!ack_result_boot),
            .i_negative_ack(ack_match&&!ack_result_ok&&!ack_result_boot),
            .i_unmatched_ack(ack_result_valid&&!ack_match&&state==WAIT_FRAME&&!remote_boot),
            .i_frame_accept(frame_accept),.i_apply_frame(apply_frame),
            .i_applied_last_sent(tx_last_fire&&reply_kind==2),.i_frame_sequence(frame_sequence),
            .i_frame_gates({response_space,pipeline_idle,frame_apply_eligible}),.i_live_flags(live_flags),
            .i_source_fs(diag_source_fs),.i_source_gates(diag_source_gates),.o_data(diag_data));
    end else begin:g_no_cfg_diag
        assign diag_data=224'd0;
    end endgenerate
    // Policy and transaction state use the same final next values, so pause
    // changes on the original source edge without a combinational state decode.
    always @*begin
        policy_state_next=state;
        policy_initialized_next=initialized;
        policy_applied_next=remote_applied;
        policy_fault_next=remote_fault;
        if(decide && !rx_shape_bad)begin
            if(rx_kind==3&&state==IDLE&&rx_session!=0&&rx_session!=session)begin
                policy_initialized_next=0;policy_applied_next=0;policy_state_next=BOOT_BARRIER;
            end else if(initialized&&rx_session==session)begin
                if(rx_kind==0)begin
                    if(state==IDLE&&!rx_fields_bad&&(!rx_ext||scanner_error==0))policy_state_next=WAIT_IDLE;
                end else if((rx_kind==1||rx_kind==2)&&state==PREPARED&&
                    !rx_identity_bad&&!rx_fields_bad&&(rx_ext||prepared[341:128]==0))begin
                    if(rx_kind==2)policy_state_next=IDLE;
                    else begin policy_state_next=WAIT_FRAME;policy_applied_next=0;end
                end
            end
        end
        // WAIT_IDLE and PREPARED both forbid new jobs. Snapshot the pause
        // projection before their quiet/response-qualified state transition;
        // the actual transaction state below keeps its original priority.
        policy_pause_state_next=policy_state_next;
        if(state==WAIT_IDLE&&pipeline_idle&&response_space)policy_state_next=PREPARED;
        if(ack_match&&ack_result_ok)policy_applied_next=1;
        if(apply_failed)begin policy_fault_next=1;policy_state_next=FAULT;policy_pause_state_next=FAULT;end
        if(boot_complete)begin policy_initialized_next=1;policy_state_next=IDLE;policy_pause_state_next=IDLE;end
        // Evaluate the stable policy before the final frame-apply override.
        // The real apply edge clears eligibility with one final bit gate,
        // rather than feeding late READY through a state mux and its decode.
        frame_eligibility_next=policy_state_next==WAIT_FRAME&&policy_initialized_next&&
            policy_applied_next&&!policy_fault_next;
        // An eligible WAIT_FRAME is already unpaused before this edge.
        // Applying it enters IDLE with the same pause value. Fault and BOOT
        // overrides have already reached both projections above.
        if(apply_frame)policy_state_next=IDLE;
    end
    assign active_config=apply_frame?prepared_tuple:applied_tuple;
    assign active_schema2=active_config[167:160]==`PCIE_CFG_V2_SCHEMA;
    assign active_legacy_gaussian=!active_schema2&&active_config[65:64]==`PCIE_CFG_MODE_GAUSSIAN;
    assign active_product_mode=active_schema2?active_config[169:168]:
        (active_config[160+`PCIE_CFG_EXT_OFFSET_ENABLE+`PCIE_CFG_EXT_FEATURE_HDR]?2'd2:2'd0);
    assign active_processing_enables=active_schema2?active_config[175:170]:
        {active_config[160+`PCIE_CFG_EXT_OFFSET_ENABLE+`PCIE_CFG_EXT_FEATURE_F23],
         active_config[160+`PCIE_CFG_EXT_OFFSET_ENABLE+`PCIE_CFG_EXT_FEATURE_F22],
         active_config[65:64]==`PCIE_CFG_MODE_HISTOGRAM,1'b0,
         active_config[160+`PCIE_CFG_EXT_OFFSET_ENABLE+`PCIE_CFG_EXT_FEATURE_DEHAZE],
         active_config[65:64]==`PCIE_CFG_MODE_GRAY||active_config[65:64]==`PCIE_CFG_MODE_GAUSSIAN};
    assign active_mode=apply_frame?prepared[65:64]:applied_view[65:64];
    assign active_quality=!initialized&&state==IDLE ? 8'd75 : {1'b0,apply_frame?prepared[72:66]:applied_view[72:66]};
    assign adaptive_quality=apply_frame?prepared[73]:applied_view[73];
    assign minimum_quality=!initialized&&state==IDLE ? 8'd1 : {1'b0,apply_frame?prepared[80:74]:applied_view[80:74]};
    assign frame_budget=apply_frame?prepared[105:81]:applied_view[105:81];
    assign restart_mcus=apply_frame?prepared[121:106]:applied_view[121:106];
    assign source_session=session;assign mode_epoch=apply_frame?epoch+1'b1:epoch;
    assign pixel_initialized=initialized;
    assign source_ready=initialized&&!remote_fault&&(state!=WAIT_FRAME||remote_applied)&&!source_apply_failed;
    assign pause_new_jobs=pause_policy;
    assign m_config_data=remote_tuple;
    assign m_config_valid=remote_pending&&!remote_sent&&!remote_fault;
    assign s_config_ack_ready=rst_n&&!ack_compare_valid&&!ack_result_valid;
    assign config_fault=remote_fault;assign config_stale_ack_count=stale_ack_count;
    assign response_valid=tx_state!=0;
    wire [31:0] response_word=tx_state==1 ? session : tx_state==2 ? rx_sequence :
        tx_state==3 ? (reply_kind==3 ? {29'd0,reply_error}:epoch) :
        (reply_kind==2 ? reply_last : 32'd0);
    assign response_data=tx_state==1 ? {2'b10,reply_kind,4'd0,response_word} :
        {1'b0,tx_state==4,(tx_state==2?6'd0:tx_state==3?6'd1:6'd2),response_word};
    // One shared full-width received-word comparator. Select from compact
    // prepared fields or constant decoded preset words, never from a dynamic
    // part-select of a 1024-bit expanded extension. Legal packet indices are
    // 0..40; index 8 carries negotiated capability bits, not tuple identity.
    localparam [1023:0] LEGACY_DEHAZE=stage2_unpack_extension(208'd1);
    localparam [1023:0] LEGACY_LANE=stage2_unpack_extension(208'd2);
    wire schema2=prepared[341];
    wire legacy_hdr=prepared[162];
    wire legacy_dehaze=prepared[128];
    wire legacy_lane=prepared[129];
    reg [31:0] expected_payload_word;
    always @*begin
        expected_payload_word=0;
        case(rx_index)
            0:expected_payload_word=prepared[31:0];
            1:expected_payload_word=session;
            2:expected_payload_word={30'd0,prepared[65:64]};
            3:expected_payload_word={25'd0,prepared[72:66]};
            4:expected_payload_word={31'd0,prepared[73]};
            5:expected_payload_word={25'd0,prepared[80:74]};
            6:expected_payload_word={7'd0,prepared[105:81]};
            7:expected_payload_word={16'd0,prepared[121:106]};
            9:expected_payload_word=schema2 ? {16'd0,prepared[135:128],8'd2} :
                {18'd0,legacy_lane,legacy_lane,legacy_dehaze,legacy_hdr,9'd0,
                 (legacy_hdr||legacy_dehaze||legacy_lane)};
            11:expected_payload_word=schema2 ? prepared[199:168] :
                (legacy_hdr ? prepared[194:163] : 32'd0);
            12:expected_payload_word=schema2 ? {19'd0,prepared[212:200]} :
                (legacy_hdr ? {19'd0,prepared[207:195]} : 32'd0);
            13:expected_payload_word=schema2 ? prepared[244:213] :
                (legacy_hdr ? prepared[239:208] : 32'd0);
            14:expected_payload_word=schema2 ? prepared[276:245] :
                (legacy_hdr ? prepared[271:240] : 32'd0);
            15:expected_payload_word=schema2 ? prepared[308:277] :
                (legacy_hdr ? prepared[303:272] : 32'd0);
            16:expected_payload_word=schema2 ? prepared[340:309] :
                (legacy_hdr ? prepared[335:304] : 32'd0);
            17:expected_payload_word=(!schema2&&legacy_dehaze) ? LEGACY_DEHAZE[256+:32] : 32'd0;
            18:expected_payload_word=(!schema2&&legacy_dehaze) ? LEGACY_DEHAZE[288+:32] : 32'd0;
            19:expected_payload_word=(!schema2&&legacy_dehaze) ? LEGACY_DEHAZE[320+:32] : 32'd0;
            20:expected_payload_word=schema2 ? prepared[167:136] :
                (legacy_dehaze ? prepared[161:130] : 32'd0);
            21:expected_payload_word=(!schema2&&legacy_lane) ? LEGACY_LANE[384+:32] : 32'd0;
            22:expected_payload_word=(!schema2&&legacy_lane) ? LEGACY_LANE[416+:32] : 32'd0;
            23:expected_payload_word=(!schema2&&legacy_lane) ? LEGACY_LANE[448+:32] : 32'd0;
            24:expected_payload_word=(!schema2&&legacy_lane) ? LEGACY_LANE[480+:32] : 32'd0;
            25:expected_payload_word=(!schema2&&legacy_lane) ? LEGACY_LANE[512+:32] : 32'd0;
            26:expected_payload_word=(!schema2&&legacy_lane) ? LEGACY_LANE[544+:32] : 32'd0;
            27:expected_payload_word=(!schema2&&legacy_lane) ? LEGACY_LANE[576+:32] : 32'd0;
            28:expected_payload_word=(!schema2&&legacy_lane) ? LEGACY_LANE[608+:32] : 32'd0;
            29:expected_payload_word=(!schema2&&legacy_lane) ? LEGACY_LANE[640+:32] : 32'd0;
            30:expected_payload_word=(!schema2&&legacy_lane) ? LEGACY_LANE[672+:32] : 32'd0;
            31:expected_payload_word=(!schema2&&legacy_lane) ? LEGACY_LANE[704+:32] : 32'd0;
            32:expected_payload_word=(!schema2&&legacy_lane) ? LEGACY_LANE[736+:32] : 32'd0;
            33:expected_payload_word=(!schema2&&legacy_lane) ? LEGACY_LANE[768+:32] : 32'd0;
            34:expected_payload_word=(!schema2&&legacy_lane) ? LEGACY_LANE[800+:32] : 32'd0;
            35:expected_payload_word=(!schema2&&legacy_lane) ? LEGACY_LANE[832+:32] : 32'd0;
            36:expected_payload_word=(!schema2&&legacy_lane) ? LEGACY_LANE[864+:32] : 32'd0;
            37:expected_payload_word=(!schema2&&legacy_lane) ? LEGACY_LANE[896+:32] : 32'd0;
            38:expected_payload_word=(!schema2&&legacy_lane) ? LEGACY_LANE[928+:32] : 32'd0;
            39:expected_payload_word=(!schema2&&legacy_lane) ? LEGACY_LANE[960+:32] : 32'd0;
            40:expected_payload_word=(!schema2&&legacy_lane) ? LEGACY_LANE[992+:32] : 32'd0;
            default:expected_payload_word=0;
        endcase
    end
    task reply;
        input [1:0] kind;input [2:0] error;
        // Successful replies never publish reply_error. Keeping their frame
        // acceptance event out of this field also removes an unnecessary
        // high-fanout reset/admission path into the error bank.
        begin if(kind!=2)reply_kind<=kind;if(kind==3)reply_error<=error;tx_active<=1;end
    endtask
    // This payload is published only by APPLIED. While WAIT_FRAME owns the
    // transaction, sample the source sequence without the long idle/ACK/reset
    // qualifier. The actual apply edge captures its exact sequence, then IDLE
    // freezes it throughout every response stall. All other replies carry zero.
    always @(posedge clk) if(state==WAIT_FRAME) reply_last<=frame_sequence;

    // This session copy is unowned until a checked PREPARE completes. Capture
    // the offered header without the reset/response-ready/command-valid cone
    // on its 32 payload enables. The real header handshake installs this same
    // word and remains the only authority for rx_capture and packet checks.
    // COMMIT identity word 1 compares the authoritative session, not this copy.
    always @(posedge clk)begin
        if(state==IDLE&&accepting_header&&command_data[37:36]==0)
            prepared_fields[63:32]<=word;
    end
    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)begin
            state<=IDLE;initialized<=0;pause_policy<=1;frame_apply_eligible<=0;
            prepared_fields[341:64]<=0;prepared_fields[31:0]<=0;
            applied<=0;applied_write_pending<=0;session<=0;epoch<=0;stale_ack_count<=0;
            remote_pending<=0;remote_sent<=0;remote_applied<=0;remote_fault<=0;remote_boot<=0;fault_reply_pending<=0;
            boot_reply_pending<=0;ack_word_match<=0;
            ack_compare_valid<=0;ack_compare_eligible<=0;ack_compare_ok<=0;ack_compare_boot<=0;
            ack_result_valid<=0;ack_result_match<=0;ack_result_eligible<=0;ack_result_ok<=0;ack_result_boot<=0;
            tx_active<=0;tx_index<=0;reply_kind<=0;reply_error<=0;
            rx_active<=0;rx_done<=0;rx_ext<=0;rx_capture<=0;rx_shape_bad<=0;rx_fields_bad<=0;rx_identity_bad<=0;rx_schema2<=0;
            rx_kind<=0;rx_index<=0;rx_session<=0;rx_sequence<=0;rx_mode<=0;rx_quality<=0;rx_adaptive<=0;
        end else begin
            applied_write_pending<=apply_frame;
            // WAIT_FRAME has consumed COMMIT's RX packet before applying.
            // On the next edge APPLIED still owns its first reply flit, so
            // command_ready is low and no new PREPARE can overwrite payload.
            // The unowned speculative session write on that edge also reads
            // the old prepared value here, before both NBAs retire together.
            if(applied_write_pending)applied<={prepared[341:128],epoch,prepared[127:0]};
            ack_compare_valid<=ack_fire;
            ack_result_valid<=ack_compare_valid;
            if(ack_fire)begin
                for(ack_word_index=0;ack_word_index<37;ack_word_index=ack_word_index+1)
                    ack_word_match[ack_word_index]<=s_config_ack_data[ack_word_index*32+:32]==remote_tuple[ack_word_index*32+:32];
                ack_compare_eligible<=remote_pending&&remote_sent&&!remote_applied&&!remote_fault&&
                    (state==BOOT_BARRIER||state==WAIT_FRAME);
                ack_compare_ok<=s_config_ack_ok;ack_compare_boot<=state==BOOT_BARRIER;
            end
            if(ack_compare_valid)begin
                ack_result_match<=&ack_word_match;ack_result_eligible<=ack_compare_eligible;
                ack_result_ok<=ack_compare_ok;ack_result_boot<=ack_compare_boot;
            end
            state<=policy_state_next;initialized<=policy_initialized_next;
            remote_applied<=policy_applied_next;remote_fault<=policy_fault_next;
            frame_apply_eligible<=frame_eligibility_next&&!apply_frame;
            pause_policy<=policy_pause_state_next==WAIT_IDLE||policy_pause_state_next==PREPARED||
                !policy_initialized_next||policy_fault_next||
                (policy_pause_state_next==WAIT_FRAME&&!policy_applied_next);
            // WAIT_FRAME has no response owner until apply or failure starts
            // tx_state. Pre-fill APPLIED kind while hidden; a real error reply
            // below still overrides it on the original edge.
            if(state==WAIT_FRAME&&tx_state==0)reply_kind<=2;
            if(response_valid&&response_ready)begin
                tx_index<=tx_index+1'b1;
                if(tx_index==3)tx_active<=0;
            end
            if(command_fire&&accepting_header)begin
                rx_kind<=command_data[37:36];rx_ext<=command_data[35];rx_session<=word;rx_sequence<=0;
                rx_index<=0;rx_fields_bad<=0;rx_identity_bad<=0;rx_schema2<=0;
                rx_shape_bad<=!is_header||command_data[34:32]!=0||command_data[38]!=(command_data[37:36]==3)||
                    (command_data[37:36]==3&&command_data[35]);
                rx_active<=command_data[37:36]!=3;rx_done<=command_data[37:36]==3;
                rx_capture<=command_data[37:36]==0&&state==IDLE&&initialized&&word==session;
                if(command_data[37:36]==0&&state==IDLE)begin prepared_fields[341:128]<=0;prepared_fields[127:122]<=0;end
            end
            if(payload_fire)begin
                if(is_header||command_data[37:32]!=rx_index||command_data[38]!=(rx_index==(rx_ext?40:8)))rx_shape_bad<=1;
                if(command_data[38]||rx_index==(rx_ext?40:8))begin rx_active<=0;rx_done<=1;end
                else rx_index<=rx_index+1'b1;
                case(rx_index)
                    0:begin rx_sequence<=word;if(word==0)rx_fields_bad<=1;if(rx_capture)prepared_fields[31:0]<=word;end
                    1:begin if(word!=rx_session)rx_shape_bad<=1;end
                    2:begin rx_mode<=word;if(word>3)rx_fields_bad<=1;if(rx_capture)prepared_fields[65:64]<=word[1:0];end
                    3:begin rx_quality<=word[6:0];if(word<1||word>100)rx_fields_bad<=1;if(rx_capture)prepared_fields[72:66]<=word[6:0];end
                    4:begin rx_adaptive<=word[0];if(word>1)rx_fields_bad<=1;if(rx_capture)prepared_fields[73]<=word[0];end
                    5:begin if(word<1||word>rx_quality)rx_fields_bad<=1;if(rx_capture)prepared_fields[80:74]<=word[6:0];end
                    6:begin if(word>16777216||(rx_adaptive&&word==0))rx_fields_bad<=1;if(rx_capture)prepared_fields[105:81]<=word[24:0];end
                    7:begin if(word>65535)rx_fields_bad<=1;if(rx_capture)prepared_fields[121:106]<=word[15:0];end
                    8:begin if(!word[0])rx_fields_bad<=1;end
                    9:begin
                        rx_schema2<=word[7:0]==`PCIE_CFG_V2_SCHEMA;
                        if(rx_capture)begin
                            prepared_fields[341]<=word[7:0]==`PCIE_CFG_V2_SCHEMA;
                            if(word[7:0]==`PCIE_CFG_V2_SCHEMA)prepared_fields[135:128]<=word[15:8];
                            else begin prepared_fields[128]<=word[11];prepared_fields[129]<=word[12]||word[13];prepared_fields[130]<=word[10];end
                        end
                    end
                    11:if(rx_capture)begin prepared_fields[199:168]<=word;end
                    12:if(rx_capture)begin prepared_fields[212:200]<=word[12:0];end
                    13:if(rx_capture)begin prepared_fields[244:213]<=word;end
                    14:if(rx_capture)begin prepared_fields[276:245]<=word;end
                    15:if(rx_capture)begin prepared_fields[308:277]<=word;end
                    16:if(rx_capture)begin prepared_fields[340:309]<=word;end
                    20:if(rx_capture)begin prepared_fields[167:136]<=word;end
                    default:begin end
                endcase
                if(rx_index!=8&&word!=expected_payload_word)rx_identity_bad<=1;
            end
            if(decide)begin
                rx_done<=0;
                if(rx_shape_bad)reply(3,`PCIE_CFG_ERROR_INVALID);
                else if(rx_kind==3&&state==IDLE&&rx_session!=0&&rx_session!=session)begin
                    session<=rx_session;epoch<=0;
                    applied<={214'd0,32'd0,6'd0,16'd0,25'd0,7'd1,1'b0,7'd75,2'd0,rx_session,32'd0};
                    remote_boot<=1;remote_pending<=1;remote_sent<=0;
                end else if(!initialized||rx_session!=session)reply(3,`PCIE_CFG_ERROR_SESSION);
                else if(rx_kind==0)begin
                    if(state!=IDLE)reply(3,`PCIE_CFG_ERROR_BUSY);
                    else if(rx_fields_bad)reply(3,`PCIE_CFG_ERROR_INVALID);
                    else if(rx_ext&&scanner_error!=0)reply(3,scanner_error);
                    
                end else if(rx_kind==1||rx_kind==2)begin
                    if(state!=PREPARED||rx_identity_bad||rx_fields_bad||(!rx_ext&&prepared[341:128]!=0))reply(3,`PCIE_CFG_ERROR_STALE);
                    else if(rx_kind==2)begin reply(0,0);end
                    else begin remote_boot<=0;remote_pending<=1;remote_sent<=0;end
                end else reply(3,`PCIE_CFG_ERROR_INVALID);
            end
            if(state==WAIT_IDLE&&pipeline_idle&&response_space)begin reply(1,0);end
            if(m_config_valid&&m_config_ready)remote_sent<=1;
            if(apply_failed)fault_reply_pending<=1;
            if(ack_match&&ack_result_ok&&ack_result_boot)boot_reply_pending<=1;
            if(ack_result_valid&&!ack_match&&!(&stale_ack_count))stale_ack_count<=stale_ack_count+1'b1;
            if(boot_complete)begin remote_pending<=0;boot_reply_pending<=0;reply(0,0);end
            if(fault_reply_pending&&response_space)begin reply(3,`PCIE_CFG_ERROR_RESET);fault_reply_pending<=0;end
            if(apply_frame)begin epoch<=epoch+1'b1;remote_pending<=0;reply(2,0);end
        end
    end
endmodule
