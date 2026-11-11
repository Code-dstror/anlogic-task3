`timescale 1ns/1ps
`default_nettype none
`include "pcie_protocol_v1.vh"

// Sequential frontend-applied -> actual DFI CONFIG done -> source whole ACK.
module frame_job_config_cdc #(
    parameter integer EXT_WIDTH=0,WIDTH=1920,HEIGHT=1080,EXT_STRIPS=4,
    parameter integer DEHAZE_LUT_GUARD_ENABLE=0,
    parameter [31:0] EXT_COMBINATIONS=0,
    parameter [7:0] EXT_SUPPORTED=0,
    parameter integer COMPACT_EMPTY_EXTENSION_ENABLE=0,
    parameter integer COMPACT_STAGE2_EXTENSION_ENABLE=0,
    parameter integer TRUSTED_INPUT=0
) (
    input wire i_pixel_clk,i_pixel_rst_n,i_dfi_clk,i_dfi_rst_n,
    // Actual algorithm-domain LUT owner, not the USER cached QUERY result.
    input wire i_dehaze_lut_valid,input wire [31:0] i_dehaze_lut_generation,
    input wire i_dehaze_update_busy,
    output wire o_dehaze_lut_update_inhibit,
    input wire [159+EXT_WIDTH:0] s_frontend_applied_data,
    input wire s_frontend_applied_valid,s_frontend_applied_ok,
    output wire s_frontend_applied_ready,
    output wire [159+EXT_WIDTH:0] m_whole_ack_data,
    output wire m_whole_ack_valid,m_whole_ack_ok,
    input wire m_whole_ack_ready,
    // These policy inputs belong to DFI and are snapshotted, not CFG.MODE bits.
    input wire [1:0] i_pair_mode,
    input wire i_mono_enable,
    input wire [63:0] i_max_delta_ns,
    input wire [31:0] i_max_wait_ns,i_max_age_ns,
    output wire o_job_config_valid,
    input wire i_job_config_ready,
    output wire [31:0] o_job_session,o_job_epoch,
    output wire [1:0] o_job_mode,
    output wire o_job_mono_enable,
    output wire [63:0] o_job_max_delta_ns,
    output wire [31:0] o_job_max_wait_ns,o_job_max_age_ns,
    // Complete frozen pending policy for actual DFI algorithm configuration.
    // Valid with o_job_config_valid; no active publication before true done.
    output wire [159+EXT_WIDTH:0] o_job_config_snapshot,
    input wire i_job_config_done,i_job_config_error,i_job_config_busy,
    output wire o_source_reset_done,o_dfi_reset_done,
    output wire o_source_busy,o_dfi_busy,
    // DFI proof of the last actually completed CONFIG, not a queued callback.
    output wire [31:0] o_active_session,o_active_epoch,
    output wire o_active_valid,
    output reg [159+EXT_WIDTH:0] o_active_config,
    output reg o_active_hdr,
    output reg o_source_fault,o_dfi_fault,
    output reg [31:0] o_stale_ack_count,o_stale_job_done_count
);
    `include "analysis_config_transport.vh"
    // The compact interface is a cold capability specialization. Its single
    // extension bit represents only 1024'd0 or 1024'd1, never truncated policy.
    // An invalid combination intentionally fails module resolution at elaboration.
    generate if((COMPACT_EMPTY_EXTENSION_ENABLE!=0 &&
        (EXT_WIDTH!=1 || EXT_SUPPORTED!=0 || DEHAZE_LUT_GUARD_ENABLE!=0)) ||
        (EXT_WIDTH==1 && COMPACT_EMPTY_EXTENSION_ENABLE==0) ||
        (COMPACT_STAGE2_EXTENSION_ENABLE!=0 && (EXT_WIDTH!=MONO_EXTENSION_BITS || EXT_SUPPORTED!=8'h34 ||
         EXT_COMBINATIONS!=0 || EXT_STRIPS!=4 || COMPACT_EMPTY_EXTENSION_ENABLE!=0)) ||
        (EXT_WIDTH==MONO_EXTENSION_BITS && COMPACT_STAGE2_EXTENSION_ENABLE==0)) begin:g_invalid_compact_parameters
        frame_job_config_cdc_invalid_compact_parameters invalid_parameters();
    end endgenerate
    wire cohort_rst_n=i_pixel_rst_n&&i_dfi_rst_n;
    wire pixel_rst_n,dfi_rst_n;
    reset_release_sync u_pixel_reset(.i_clk(i_pixel_clk),.i_async_rst_n(cohort_rst_n),.o_rst_n(pixel_rst_n));
    reset_release_sync u_dfi_reset(.i_clk(i_dfi_clk),.i_async_rst_n(cohort_rst_n),.o_rst_n(dfi_rst_n));
    wire request_ready,request_valid,request_sink_ready;
    wire request_source_done,request_sink_done,ack_source_done,ack_sink_done;
    wire [160+EXT_WIDTH:0] request_data,ack_data;
    wire ack_valid,ack_ready;
    wire return_pop;
    wire [39:0] return_word;
    wire [4:0] return_index;
    reg source_owned,source_expected_ok,source_result_valid,source_result_ok;
    reg [159+EXT_WIDTH:0] source_tuple;
    reg fault_meta,fault_sync;
    localparam [1:0] D_IDLE=0,D_REQUEST=1,D_WAIT=2,D_RESULT=3;
    reg [1:0] state;
    // The request adapter holds its complete published head until sink_ready.
    // Borrow that storage through CONFIG and the final real ACK write flit.
    wire [159+EXT_WIDTH:0] dfi_tuple=request_data[159+EXT_WIDTH:0];
    reg result_ok,configured;
    reg [31:0] configured_session,configured_epoch;
    reg [1:0] pair_mode;
    reg mono_enable;
    reg [63:0] max_delta;
    reg [31:0] max_wait,max_age;
    wire [159+EXT_WIDTH:0] canonical_boot={32'd0,6'd0,16'd0,25'd0,7'd1,1'b0,7'd75,
                                 2'd0,request_data[63:32],32'd0};
    wire extension_legal,legacy_extension_legal,legacy_unsupported;
    wire [1023:0] request_extension;
    wire request_schema2=request_extension[7:0]==`PCIE_CFG_V2_SCHEMA;
    assign extension_legal=request_schema2 ? mono_v2_error(request_extension,{30'd0,request_data[65:64]},3'b101,6'h3f)==0 : legacy_extension_legal&&!legacy_unsupported;
    generate if(EXT_WIDTH==1024) begin:g_extension
        assign request_extension=request_data[1183:160];
        frame_config_extension_validate #(.WIDTH(WIDTH),.HEIGHT(HEIGHT),.STRIPS(EXT_STRIPS),
            .COMBINATIONS(EXT_COMBINATIONS),.SUPPORTED(EXT_SUPPORTED),.CAMERA_PRESENT(2'b11)) validator(
            .extension(request_extension),.valid(legacy_extension_legal),.unsupported(legacy_unsupported));
    end else if(COMPACT_STAGE2_EXTENSION_ENABLE!=0 && EXT_WIDTH==MONO_EXTENSION_BITS) begin:g_stage2_extension
        assign request_extension=mono_unpack_extension(request_data[159+MONO_EXTENSION_BITS:160]);
        frame_config_extension_validate #(.WIDTH(WIDTH),.HEIGHT(HEIGHT),.STRIPS(EXT_STRIPS),
            .COMBINATIONS(EXT_COMBINATIONS),.SUPPORTED(EXT_SUPPORTED),.CAMERA_PRESENT(2'b11)) validator(
            .extension(request_extension),.valid(legacy_extension_legal),.unsupported(legacy_unsupported));
    end else if(COMPACT_EMPTY_EXTENSION_ENABLE!=0 && EXT_WIDTH==1) begin:g_compact_extension
        assign request_extension={{1023{1'b0}},request_data[160]};
        frame_config_extension_validate #(.WIDTH(WIDTH),.HEIGHT(HEIGHT),.STRIPS(EXT_STRIPS),
            .COMBINATIONS(EXT_COMBINATIONS),.SUPPORTED(EXT_SUPPORTED),.CAMERA_PRESENT(2'b11)) validator(
            .extension(request_extension),.valid(legacy_extension_legal),.unsupported(legacy_unsupported));
    end else begin:g_legacy_extension
        assign request_extension=0;
        assign legacy_extension_legal=EXT_WIDTH==0;assign legacy_unsupported=0;
    end endgenerate
    wire [1023:0] pending_extension=request_extension;
    wire request_hdr=analysis_hdr_enabled(request_extension);
    wire [1023:0] active_extension;
    generate if(COMPACT_STAGE2_EXTENSION_ENABLE!=0) begin:g_stage2_active_extension
        assign active_extension=mono_unpack_extension(o_active_config[159+MONO_EXTENSION_BITS:160]);
    end else begin:g_full_active_extension
        assign active_extension=o_active_config>>160;
    end endgenerate
    wire request_dehaze=DEHAZE_LUT_GUARD_ENABLE!=0 &&
        analysis_dehaze_enabled(request_extension);
    wire pending_dehaze=DEHAZE_LUT_GUARD_ENABLE!=0 &&
        analysis_dehaze_enabled(pending_extension);
    wire active_dehaze=DEHAZE_LUT_GUARD_ENABLE!=0 && configured &&
        analysis_dehaze_enabled(active_extension);
    wire request_lut_legal=!request_dehaze || (i_dehaze_lut_valid && !i_dehaze_update_busy &&
        i_dehaze_lut_generation==analysis_dehaze_lut_generation(request_extension));
    wire pending_lut_legal=!pending_dehaze || (i_dehaze_lut_valid && !i_dehaze_update_busy &&
        i_dehaze_lut_generation==analysis_dehaze_lut_generation(pending_extension));
    wire active_lut_legal=!active_dehaze || (i_dehaze_lut_valid && !i_dehaze_update_busy &&
        i_dehaze_lut_generation==analysis_dehaze_lut_generation(active_extension));
    // Include the waiting FIFO head to arbitrate simultaneous BEGIN/CONFIG.
    // An already admitted loader may finish WORD/COMMIT while CONFIG waits.
    assign o_dehaze_lut_update_inhibit=o_dfi_reset_done && DEHAZE_LUT_GUARD_ENABLE!=0 &&
        (active_dehaze || (state!=D_IDLE && pending_dehaze) || (request_valid && request_dehaze));
    wire packed_extension_canonical=COMPACT_STAGE2_EXTENSION_ENABLE==0 ||
        request_data[159+MONO_EXTENSION_BITS:160]==mono_pack_extension(request_extension);
    wire preset_mode_legal=COMPACT_STAGE2_EXTENSION_ENABLE==0 || request_schema2 ||
        !request_extension[`PCIE_CFG_EXT_OFFSET_ENABLE+`PCIE_CFG_EXT_FEATURE_F22] || request_data[65:64]==2;
    // Only the production path from the BAR validator/constant LOCAL BOOT
    // selects TRUSTED_INPUT. Identity, real CONFIG completion and live LUT
    // generation are still checked here; crossing a FIFO does not apply it.
    wire request_fields_legal=request_lut_legal&&(TRUSTED_INPUT!=0 ||
        (packed_extension_canonical&&preset_mode_legal&&extension_legal&&request_data[63:32]!=0&&request_data[127:122]==0&&
        request_data[72:66]>=1&&request_data[72:66]<=100&&
        request_data[80:74]>=1&&request_data[80:74]<=request_data[72:66]&&
        request_data[105:81]<=25'd16777216&&(!request_data[73]||request_data[105:81]!=0)));
    wire request_identity_legal=!configured?request_data[159+EXT_WIDTH:0]==canonical_boot:
        request_data[63:32]==configured_session&&request_data[159:128]==configured_epoch+32'd1&&
        request_data[31:0]!=0;
    assign o_source_reset_done=pixel_rst_n&&request_source_done&&ack_sink_done;
    assign o_dfi_reset_done=dfi_rst_n&&request_sink_done&&ack_source_done;
    assign s_frontend_applied_ready=o_source_reset_done&&!source_owned&&!o_source_fault&&request_ready;
    assign o_source_busy=source_owned;
    assign o_dfi_busy=state!=D_IDLE;
    assign o_active_session=configured_session;
    assign o_active_epoch=configured_epoch;
    assign o_active_valid=o_dfi_reset_done&&configured;
    wire request_head_available=o_dfi_reset_done&&state==D_IDLE&&!o_dfi_fault&&
        (!request_dehaze || !i_dehaze_update_busy);
    // An invalid positive head also owns a negative ACK after setting fault.
    // Do not gate release with that fault or release before ACK serialization.
    assign request_sink_ready=o_dfi_reset_done&&state==D_RESULT&&ack_ready;
    assign o_job_config_valid=o_dfi_reset_done&&state==D_REQUEST;
    assign o_job_session=dfi_tuple[63:32];assign o_job_epoch=dfi_tuple[159:128];
    assign o_job_mode=pair_mode;assign o_job_mono_enable=mono_enable;
    assign o_job_max_delta_ns=max_delta;assign o_job_max_wait_ns=max_wait;assign o_job_max_age_ns=max_age;
    assign o_job_config_snapshot=dfi_tuple;
    assign m_whole_ack_data=source_tuple;
    assign m_whole_ack_valid=o_source_reset_done&&source_result_valid;
    assign m_whole_ack_ok=source_result_ok;
    control_message_fifo_ip #(.MESSAGE_WIDTH(161+EXT_WIDTH),.BORROW_SOURCE(1)) u_request(
        .i_source_clk(i_pixel_clk),.i_source_rst_n(cohort_rst_n),
        .i_source_data({s_frontend_applied_ok,s_frontend_applied_data}),
        .i_source_valid(s_frontend_applied_valid&&!source_owned&&!o_source_fault&&o_source_reset_done),
        .o_sink_flit_read(),.o_sink_flit_data(),.o_sink_flit_index(),
        .o_source_ready(request_ready),.o_source_reset_done(request_source_done),
        .i_sink_clk(i_dfi_clk),.i_sink_rst_n(cohort_rst_n),
        .o_sink_data(request_data),.o_sink_valid(request_valid),
        .i_sink_ready(request_sink_ready),.o_sink_reset_done(request_sink_done));
    control_message_fifo_ip #(.MESSAGE_WIDTH(161+EXT_WIDTH),.BORROW_SOURCE(1)) u_ack(
        .i_source_clk(i_dfi_clk),.i_source_rst_n(cohort_rst_n),
        .i_source_data({result_ok,dfi_tuple}),.i_source_valid(o_dfi_reset_done&&state==D_RESULT),
        .o_source_ready(ack_ready),.o_source_reset_done(ack_source_done),
        .i_sink_clk(i_pixel_clk),.i_sink_rst_n(cohort_rst_n),
        .o_sink_flit_read(return_pop),.o_sink_flit_data(return_word),.o_sink_flit_index(return_index),
        .o_sink_data(ack_data),.o_sink_valid(ack_valid),
        .i_sink_ready(o_source_reset_done&&!source_result_valid),.o_sink_reset_done(ack_sink_done));
    wire echo_equal,echo_ok;
    generate if (COMPACT_STAGE2_EXTENSION_ENABLE != 0) begin : g_check_flits
        // Each PIX transaction owns the original complete source tuple until
        // its whole callback is consumed. On every actual return FIFO pop,
        // compare the corresponding immutable source chunk. The adapter
        // publishes ack_valid only after all ten chunk results are present.
        wire [9:0] chunk_matches;
        genvar chunk;
        for (chunk=0; chunk<10; chunk=chunk+1) begin : g_chunk
            localparam integer PAYLOAD_BITS = chunk==9 ? 14 : 40;
            reg equal_q;
            always @(posedge i_pixel_clk)
                if (return_pop && return_index==chunk)
                    equal_q <= source_tuple[chunk*40+:PAYLOAD_BITS] == return_word[PAYLOAD_BITS-1:0];
            assign chunk_matches[chunk] = equal_q;
        end
        // The verdict is outside the 374-bit identity. Padding is unused.
        reg verdict;
        always @(posedge i_pixel_clk)
            if (return_pop && return_index==9) verdict <= return_word[14];
        assign echo_equal = &chunk_matches;
        assign echo_ok = verdict;
    end else begin : g_check_full
        assign echo_equal = ack_data[159+EXT_WIDTH:0] == source_tuple;
        assign echo_ok = ack_data[160+EXT_WIDTH];
    end endgenerate

    always @(posedge i_pixel_clk or negedge pixel_rst_n)begin
        if(!pixel_rst_n)begin
            source_owned<=0;source_expected_ok<=0;source_result_valid<=0;source_result_ok<=0;
            source_tuple<=0;fault_meta<=0;fault_sync<=0;o_source_fault<=0;o_stale_ack_count<=0;
        end else begin
            fault_meta<=o_dfi_fault;fault_sync<=fault_meta;
            if(fault_sync)o_source_fault<=1;
            if(s_frontend_applied_valid&&s_frontend_applied_ready)begin
                source_owned<=1;source_tuple<=s_frontend_applied_data;source_expected_ok<=s_frontend_applied_ok;
            end
            if(ack_valid&&o_source_reset_done&&!source_result_valid)begin
                if(source_owned&&echo_equal)begin
                    source_result_valid<=1;
                    source_result_ok<=echo_ok&&source_expected_ok;
                    if(echo_ok&&!source_expected_ok)o_source_fault<=1;
                end else if(!(&o_stale_ack_count))o_stale_ack_count<=o_stale_ack_count+1'b1;
            end
            if(m_whole_ack_valid&&m_whole_ack_ready)begin source_owned<=0;source_result_valid<=0;end
        end
    end
    always @(posedge i_dfi_clk or negedge dfi_rst_n)begin
        if(!dfi_rst_n)begin
            state<=D_IDLE;result_ok<=0;configured<=0;configured_session<=0;configured_epoch<=0;
            o_active_config<=0;o_active_hdr<=0;
            pair_mode<=0;mono_enable<=0;max_delta<=0;max_wait<=0;max_age<=0;
            o_dfi_fault<=0;o_stale_job_done_count<=0;
        end else begin
            if(!active_lut_legal)o_dfi_fault<=1;
            if(i_job_config_done&&state!=D_WAIT&&!(&o_stale_job_done_count))
                o_stale_job_done_count<=o_stale_job_done_count+1'b1;
            case(state)
                D_IDLE:if(request_valid&&request_head_available)begin
                    result_ok<=0;
                    pair_mode<=request_hdr ? 2'd2 : i_pair_mode;
                    mono_enable<=request_hdr ? 1'b0 : i_mono_enable;
                    max_delta<=request_hdr ?
                        request_extension[`PCIE_CFG_EXT_OFFSET_HDR_MAX_DELTA_NS+:64] : i_max_delta_ns;
                    max_wait<=request_hdr ?
                        request_extension[`PCIE_CFG_EXT_OFFSET_HDR_MAX_WAIT_NS+:32] : i_max_wait_ns;
                    max_age<=request_hdr ?
                        request_extension[`PCIE_CFG_EXT_OFFSET_HDR_MAX_AGE_NS+:32] : i_max_age_ns;
                    if(!request_data[160+EXT_WIDTH])state<=D_RESULT;
                    else if(!request_fields_legal||!request_identity_legal)begin
                        o_dfi_fault<=1;state<=D_RESULT;
                    end else state<=D_REQUEST;
                end
                D_REQUEST:if(o_job_config_valid&&i_job_config_ready)state<=D_WAIT;
                D_WAIT:if(i_job_config_done)begin
                    result_ok<=!i_job_config_error&&!i_job_config_busy&&pending_lut_legal;state<=D_RESULT;
                    if(!pending_lut_legal)o_dfi_fault<=1;
                    if(!i_job_config_error&&!i_job_config_busy&&pending_lut_legal)begin
                        configured<=1;configured_session<=dfi_tuple[63:32];configured_epoch<=dfi_tuple[159:128];
                        o_active_config<=dfi_tuple;
                        // Publish the route with its epoch before scheduler fanout.
                        o_active_hdr<=request_hdr;
                    end
                end
                D_RESULT:if(o_dfi_reset_done&&ack_ready)state<=D_IDLE;
                default:begin o_dfi_fault<=1;state<=D_IDLE;end
            endcase
        end
    end
endmodule
`default_nettype wire
