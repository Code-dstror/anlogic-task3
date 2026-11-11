`timescale 1ns/1ps
`include "pcie_protocol_v1.vh"
// Actual producer/owner/JOIN/ingress contract: pixel4 is RGB96/Y32, lane0
// in low bits, SOF/EOL accepted only on valid&&ready, no input EOF wire.
// One synchronous pixel clock/reset domain; the real soft-reset fence retains
// its CDC synchronizers. F22=684b, F23=1356b with 160b owning identity.
// Source faults cancel pixel work but must retain terminal records to JOIN.
// All test stalls are finite; the final extension beat is explicitly held.
module r6_abort_tb #(parameter integer PRODUCTION=0);
    localparam integer WIDTH=PRODUCTION?1920:32,HEIGHT=PRODUCTION?1080:32;
    localparam integer GROUPS=WIDTH*HEIGHT/4;
    reg [5:0] enables=48;
    reg expected_error=0,external_cancel=0,image_ready=1;
    reg [159:0] frame_identity;
    `include "analysis_config_transport.vh"
    reg clk=0;always #4 clk=~clk;
    reg rst_n=0,begin_valid=0,product_begin=0,abort_frame=0,source_fire=0;
    reg s_valid=0,s_sof=0,s_eol=0,start_valid=0,data_valid=0,result_valid=0,token_ready=1;
    reg [31:0] source_y=0;
    reg [95:0] source_rgb=0;
    wire [1023:0] parameters=analysis_algorithm_extension({1008'd0,16'hc002});
    localparam [31:0] SESSION=2,EPOCH=1;
    reg [31:0] SEQUENCE=26854;
    localparam [7:0] SOURCE_FORMAT=`PCIE_RECORD_V2_FORMAT_RAW10,SOURCE_KIND=`PCIE_RECORD_V2_SOURCE_PHYSICAL;
    wire [159:0] IDENTITY={16'd1,16'd0,8'd1,SOURCE_FORMAT,
        SOURCE_KIND,8'd0,SEQUENCE,EPOCH,SESSION};
    reg [1023:0] context2=0;
    wire owner_ready,filter_start,filter_start_ready,filter_busy,filter_complete,filter_error;
    wire source_error,terminal_valid,terminal_error,product_owned,lane_quiet,owner_fault;
    wire [3:0] features;
    wire [159:0] terminal_context;
    wire s_ready,image_valid,image_sof,image_eol;
    wire [95:0] image_rgb;
    wire [31:0] image_y;
    wire f22_valid,f22_pending,f22_ready,f23_valid,f23_ready;
    wire [683:0] f22_data;
    wire [1355:0] f23_data;
    wire [3071:0] extension;
    wire extension_valid,extension_ready,join_ready,join_fault,context2_ready;
    wire start_ready,data_ready,result_ready,ingress_fault,token_valid;
    wire [146:0] token_data;
    integer cycles=0,checks=0,pixels_in=0,pixels_out=0,f22_seen=0,f23_seen=0,result_fires=0;
    integer terminal_errors=0,extension_fires=0,guard=0;
    reg soft_request=0;
    reg data_reset_n=1;reg [31:0] soft_session=SESSION;
    wire soft_pause,soft_marker,soft_pending,soft_execute;
    // Same owned context is borrowed by every actual candidate module.
    preprocess_live_lane_owner owner(
        .clk(clk),.rst_n(rst_n),.begin_valid(begin_valid),.begin_ready(owner_ready),
        .frame_context(IDENTITY),.begin_features(enables[5:4]),.lane_start_ready(filter_start_ready),
        .pyramid_valid(f22_valid),.lane_valid(f23_valid),.join_begin_ready(join_ready),
        .lane_start_valid(filter_start),.frame_features(features),.product_begin(product_begin),
        .extension_fire(extension_valid&&extension_ready),.source_fire(source_fire),.source_ok(!expected_error),
        .foreground_done(filter_complete),.foreground_error(filter_error),.foreground_quiet(!filter_busy),
        .abort_frame(abort_frame),.lane_complete(filter_complete),.lane_error(filter_error),
        .lane_event_context(terminal_context),.lane_source_error(source_error),.tap_observe(),
        .discard_records(),.product_owned(product_owned),.terminal_valid(terminal_valid),
        .terminal_error(terminal_error),.o_quiet(lane_quiet),.o_fault(owner_fault));
    // This is the existing LIVE pipeline's filter_error -> cancel feedback.
    stage3_filter_color_analysis4 #(.LANE_MONO_PRESET(PRODUCTION),.F22_FIXED1080P_ENABLE(PRODUCTION)) filter(
        .clk(clk),.rst_n(rst_n),.cancel(filter_error || external_cancel),.start_valid(filter_start),.start_ready(filter_start_ready),
        .cfg_width(13'(WIDTH)),.cfg_height(13'(HEIGHT)),.cfg_gray(enables[0]),.cfg_legacy_gaussian(1'b0),
        .cfg_color_filter(enables[3]),.cfg_multiscale(enables[4]),.cfg_lane(enables[5]),.cfg_context(IDENTITY),
        .cfg_threshold(parameters[`PCIE_CFG_EXT_OFFSET_THRESHOLD+:11]),
        .cfg_gx_min(parameters[`PCIE_CFG_EXT_OFFSET_GX_MIN+:11]),
        .cfg_ratio(parameters[`PCIE_CFG_EXT_OFFSET_RATIO_SHIFT+:2]),
        .cfg_sign(parameters[`PCIE_CFG_EXT_OFFSET_DIRECTION_SIGN+:2]),
        .cfg_min_count(parameters[`PCIE_CFG_EXT_OFFSET_MIN_COUNT+:20]),
        .cfg_min_strips(parameters[`PCIE_CFG_EXT_OFFSET_MIN_PAIRED_STRIPS+:4]),
        .cfg_y_begin(PRODUCTION?parameters[`PCIE_CFG_EXT_OFFSET_STRIP_Y_BEGIN+:52]:{13'd6,13'd4,13'd2,13'd0}),
        .cfg_y_end(PRODUCTION?parameters[`PCIE_CFG_EXT_OFFSET_STRIP_Y_END+:52]:{13'd8,13'd6,13'd4,13'd2}),
        .cfg_left(parameters[`PCIE_CFG_EXT_OFFSET_ROI_LEFT+:52]),
        .cfg_split(PRODUCTION?parameters[`PCIE_CFG_EXT_OFFSET_ROI_SPLIT+:52]:{4{13'd4}}),
        .cfg_right(PRODUCTION?parameters[`PCIE_CFG_EXT_OFFSET_ROI_RIGHT+:52]:{4{13'd8}}),
        .source_error(source_error),.s_valid(s_valid),.s_ready(s_ready),.s_rgb(source_rgb),.s_y(source_y),
        .s_sof(s_sof),.s_eol(s_eol),.m_valid(image_valid),.m_ready(image_ready),.m_rgb(image_rgb),
        .m_y(image_y),.m_sof(image_sof),.m_eol(image_eol),.busy(filter_busy),
        .frame_complete(filter_complete),.frame_error(filter_error),.error_code(),.terminal_context(terminal_context),
        .pyramid_valid(f22_valid),.pyramid_pending(f22_pending),.pyramid_ready(f22_ready),.pyramid_data(f22_data),
        .lane_valid(f23_valid),.lane_ready(f23_ready),.lane_data(f23_data),
        .pyramid_drops(),.lane_drops(),.lane_started(),.lane_finished(),.lane_failed());
    frame_record_v3_join joiner(
        .i_clk(clk),.i_rst_n(rst_n),.s_begin_valid(product_begin),.o_begin_ready(join_ready),
        .s_begin_context(IDENTITY),.s_begin_features(features),.s_terminal_valid(terminal_valid),
        .s_terminal_error(terminal_error),.s_terminal_context(IDENTITY),
        .s_context2_extension(context2),.s_context2_valid(1'b1),.o_context2_ready(context2_ready),
        .s_f22_record(f22_data),.s_f22_valid(f22_valid&&product_owned),.o_f22_ready(f22_ready),
        .s_f23_record(f23_data),.s_f23_valid(f23_valid&&product_owned),.o_f23_ready(f23_ready),
        .s_f24_record(208'd0),.s_f24_valid(1'b0),.o_f24_ready(),
        .s_f25_record(265'd0),.s_f25_valid(1'b0),.o_f25_ready(),
        .m_extension(extension),.m_extension_valid(extension_valid),.m_extension_ready(extension_ready),
        .o_fault(join_fault),.o_stale_count());
    // Protocol driver, not a JPEG algorithm model: one candidate byte beat and
    // a held RESULT exercise the real extension/RESULT retirement dependency.
    ordered_frame_ingress #(.CONTEXT_ENABLE(1),.WRITE_TAG_ENABLE(1),
        .RECORD_EXTENSION_ENABLE(1),.RECORD_EXTENSION_WIDTH(3072),.BORROW_EXTENSION(1)) ingress(
        .i_clk(clk),.i_rst_n(rst_n),.i_start_valid(start_valid),.o_start_ready(start_ready),
        .i_capture_id(SEQUENCE),.i_width(16'(WIDTH)),.i_height(16'(HEIGHT)),.i_timestamp_ns(64'd1234),
        .i_session_id(SESSION),.i_mode_epoch(EPOCH),.i_camera_id(1'b0),.i_quality(8'd75),.i_format(8'd1),
        .i_write_tag(32'd1),.i_start_mask(1'b0),.i_start_source_type(3'd0),
        .i_jpeg_tdata(128'hffd8_ffd9),.i_jpeg_tkeep(16'hffff),.i_jpeg_tlast(1'b1),
        .i_jpeg_tvalid(data_valid),.o_jpeg_tready(data_ready),.i_result_valid(result_valid),.o_result_ready(result_ready),
        .i_result_id(SEQUENCE),.i_result_ok(!expected_error),.i_result_length(!expected_error?25'd16:25'd0),
        .i_result_error(!expected_error?8'd0:8'd1),.i_result_quality(8'd75),.i_result_epoch(EPOCH),
        .i_record_extension(extension),.i_record_extension_valid(extension_valid),.o_record_extension_ready(extension_ready),
        .o_protocol_fault(ingress_fault),.o_token_data(token_data),.o_token_valid(token_valid),.i_token_ready(token_ready));
    // Give the real online soft-reset fence the most favorable host condition:
    // USER is quiet. An owned producer/ingress still prevents global drain.
    wire pixel_quiet=!owner.owned&&!joiner.owned&&!ingress.active&&!filter_busy;
    production_soft_reset_fence soft_fence(
        .user_clk(clk),.pixel_clk(clk),.dfi_clk(clk),.cold_reset_n(rst_n),.soft_reset_request(soft_request),
        .pixel_quiet(pixel_quiet),.dfi_quiet(!ingress.active),.user_quiet(1'b1),
        .token_drain_proven_pixel(!ingress.active),.pixel_data_reset_n(rst_n&&data_reset_n),
        .user_initialized(1'b1),.user_session(soft_session),.rearm_ready_async(1'b1),
        .pause_pixel(soft_pause),.marker_request_pixel(soft_marker),.pending_user(soft_pending),.execute_reset_user(soft_execute));

    integer cases=0,terminal_seen=0,complete_seen=0,error_seen=0;
    integer f22_fires=0,f23_fires=0,last_stalls=0;
    reg [683:0] held22;reg [1355:0] held23;
    reg [3071:0] held_extension;reg [146:0] held_token;
    reg stalled22=0,stalled23=0,stalled_extension=0,stalled_token=0;
    reg finite_stalls=0;
    task check(input bit condition,input string why);
        begin checks++;if(!condition)$fatal(1,"R6_ABORT production=%0d mask=%0d seq=%0d %s",PRODUCTION,enables,SEQUENCE,why);end
    endtask
    task tick(input integer n);repeat(n)begin @(posedge clk);#0.2;end endtask
    always @(negedge clk)if(finite_stalls)image_ready=cycles%11!=0&&cycles%11!=1;
    always @(posedge clk)begin
        cycles++;
        if(rst_n)begin
            if(s_valid&&s_ready)pixels_in+=4;
            if(image_valid&&image_ready)pixels_out+=4;
            if(f22_valid&&f22_ready)f22_fires++;
            if(f23_valid&&f23_ready)f23_fires++;
            if(result_valid&&result_ready)result_fires++;
            if(terminal_valid)begin terminal_seen++;if(terminal_error)terminal_errors++;end
            if(extension_valid&&extension_ready)extension_fires++;
            if(filter_complete)complete_seen++;
            if(filter_error)error_seen++;
            if(f22_valid)begin
                check(f22_data[683:524]===IDENTITY,"F22 real owning identity");
                if(stalled22)check(f22_data===held22,"F22 record stable while JOIN stalls");
            end
            if(f23_valid)begin
                check(enables[5]&&f23_data[1355:1196]===IDENTITY,"F23 real enabled owning identity");
                if(stalled23)check(f23_data===held23,"F23 record stable while JOIN stalls");
            end
            if(stalled_extension)check(extension_valid&&extension===held_extension,"extension stable through final-beat stall");
            if(stalled_token)check(token_valid&&token_data===held_token,"ordered token stable under finite backpressure");
            stalled22=f22_valid&&!f22_ready;held22=f22_data;
            stalled23=f23_valid&&!f23_ready;held23=f23_data;
            stalled_extension=extension_valid&&!extension_ready;held_extension=extension;
            stalled_token=token_valid&&!token_ready;held_token=token_data;
            if(owner_fault||join_fault||ingress_fault)$fatal(1,"Unexpected identity/protocol fault");
        end else begin stalled22=0;stalled23=0;stalled_extension=0;stalled_token=0;end
        if(cycles%500000==0)$display("PROGRESS production=%0d cycles=%0d cases=%0d input=%0d",PRODUCTION,cycles,cases,pixels_in);
    end
    task bounded_ready(input integer which);
        begin
            guard=0;
            while(!(which==0?owner_ready:which==1?start_ready:data_ready)&&guard<1000)begin tick(1);guard++;end
            check(guard<1000,"bounded initial ready");
        end
    endtask
    task begin_frame;
        begin
            SEQUENCE++;frame_identity=IDENTITY;
            context2[31:0]=`PCIE_RECORD_V2_EXTENSION_MAGIC;
            context2[47:32]=`PCIE_RECORD_V2_SCHEMA_VERSION;
            context2[48+`PCIE_RECORD_V2_FLAG_SOURCE_IDENTITY]=1;
            context2[95:64]=SESSION;context2[127:96]=EPOCH;context2[159:128]=SEQUENCE;
            context2[183:160]={SOURCE_FORMAT,SOURCE_KIND,8'd0};
            pixels_in=0;pixels_out=0;f22_fires=0;f23_fires=0;terminal_seen=0;
            terminal_errors=0;complete_seen=0;error_seen=0;result_fires=0;extension_fires=0;
            @(negedge clk);begin_valid=1;bounded_ready(0);tick(1);
            @(negedge clk);begin_valid=0;product_begin=1;
            tick(1);@(negedge clk);product_begin=0;start_valid=1;bounded_ready(1);tick(1);
            @(negedge clk);start_valid=0;data_valid=1;bounded_ready(2);tick(1);
            @(negedge clk);data_valid=0;
        end
    endtask
    task send_groups(input integer count,input bit bad_last);
        integer n,x,y,waited;
        begin
            for(n=0;n<count;n++)begin
                x=n%(WIDTH/4);y=n/(WIDTH/4);
                @(negedge clk);s_valid=1;s_sof=n==0;s_eol=(x==WIDTH/4-1)^(bad_last&&n==count-1);
                source_y={4{8'((x+y)&255)}};source_rgb={12{8'((x+y)&255)}};
                waited=0;
                do begin @(posedge clk);waited++;end while(!s_ready&&!filter_error&&waited<20000);
                check(waited<20000,"bounded source acceptance");
            end
            @(negedge clk);s_valid=0;s_sof=0;s_eol=0;
        end
    endtask
    task pulse_abort(input bit direct);
        begin
            @(negedge clk);abort_frame=1;external_cancel=direct;tick(1);
            @(negedge clk);abort_frame=0;external_cancel=0;
        end
    endtask
    task drain_frame(input integer kind);
        integer wait_cycles,base_errors;
        reg [683:0] result22;reg [1355:0] result23;
        begin
            guard=0;
            while((filter_busy||!f22_valid||(enables[5]&&!f23_valid))&&guard<30000)begin tick(1);guard++;end
            check(guard<30000,"actual F22/F23 terminals become available");
            check(f22_data[523]==(kind==0||kind==8),"F22 success only for completed analysis");
            check((f22_data[522:515]==0)==(kind==0||kind==8),"F22 truthful failure code");
            if(enables[5])begin
                check(f23_data[1195]==(kind==0||kind==8),"F23 success only for completed analysis");
                check((f23_data[1194:1187]==0)==(kind==0||kind==8),"F23 truthful failure code");
            end
            result22=f22_data;result23=f23_data;
            // The failed frame remains owned while the online reset requests
            // drain. The same fence must reach EXECUTE after genuine retirement.
            if(kind!=0)begin @(negedge clk);soft_request=1;tick(1);@(negedge clk);soft_request=0;end
            tick(24);check(!soft_execute,"reset cannot execute while the actual frame is owned");
            if(kind!=0)check(soft_pending,"soft reset waits for owned result");
            check(!filter_start_ready,"pending results reserve analysis START");
            @(negedge clk);source_fire=1;tick(1);@(negedge clk);source_fire=0;result_valid=1;
            // Hold extension before transport begins, then stall its last flit.
            token_ready=0;tick(17);check(extension_valid&&!result_ready,"JOIN has all genuine results before RESULT");
            @(negedge clk);token_ready=1;
            guard=0;
            while(!(ingress.extension_latched&&ingress.extension_index==23)&&guard<1000)begin
                @(negedge clk);token_ready=cycles%5!=0;tick(1);guard++;
            end
            check(guard<1000,"extension reaches final actual flit");
            @(negedge clk);token_ready=0;tick(13);last_stalls++;
            check(owner.owned&&joiner.owned&&ingress.active&&f22_valid&&(!enables[5]||f23_valid),"last stall retains every owner");
            check(f22_data===result22&&(!enables[5]||f23_data===result23),"last stall preserves analysis payloads");
            check(!result_ready&&f22_fires==0&&f23_fires==0,"no premature sparse/result consumption");
            @(negedge clk);token_ready=1;
            guard=0;while(result_fires==0&&guard<1000)begin tick(1);guard++;end
            check(guard<1000,"RESULT retires after extension");
            @(negedge clk);result_valid=0;finite_stalls=0;image_ready=1;tick(16);
            check(extension_fires==1&&result_fires==1&&terminal_seen==1,"single terminal/extension/RESULT");
            check(f22_fires==1&&f23_fires==(enables[5]?1:0),"enabled records consumed exactly once");
            check(terminal_errors==(kind==0?0:1),"owner reports truthful global error");
            check(!owner.owned&&!joiner.owned&&!ingress.active&&!filter_busy&&!f22_valid&&!f22_pending&&!f23_valid,"real ownership drains empty");
            if(kind!=0)begin
                guard=0;while(!soft_execute&&guard<100)begin tick(1);guard++;end
                check(guard<100,"online soft reset reaches EXECUTE after real drain");
                @(negedge clk);data_reset_n=0;tick(8);@(negedge clk);soft_session++;data_reset_n=1;tick(16);
                check(!soft_pending&&!soft_execute,"soft fence completes new-session rearm");
            end
            cases++;$display("RESULT: PASS R6_CASE production=%0d mask=%0d kind=%0d input=%0d output=%0d",PRODUCTION,enables,kind,pixels_in,pixels_out);
        end
    endtask
    task frame_case(input integer mask,input integer kind);
        integer count;
        begin
            enables=6'(mask);expected_error=kind!=0;finite_stalls=kind%2==1;
            begin_frame();
            count=kind==1?0:kind==2?1:kind==3||kind==6||kind==7?GROUPS/2:kind==4?GROUPS-1:GROUPS;
            // Exact deployed reproduction: 1000 four-pixel transfers.
            if(PRODUCTION&&kind==3)count=1000;
            send_groups(count,kind==7);
            if(kind==8)begin
                guard=0;while((filter_busy||!f22_valid||(enables[5]&&!f23_valid))&&guard<30000)begin tick(1);guard++;end
                check(guard<30000,"finished success result held before later abort");
            end
            if(kind!=0&&kind!=7)pulse_abort(kind==6);
            drain_frame(kind);
        end
    endtask
    initial begin
        tick(32);@(negedge clk);rst_n=1;tick(16);
        if(PRODUCTION)begin
            frame_case(48,0);frame_case(48,3);frame_case(48,5);frame_case(48,0);
        end else begin
            for(integer m=0;m<3;m++)begin
                for(integer k=0;k<=8;k++)frame_case(m==0?16:m==1?48:61,k);
                frame_case(m==0?16:m==1?48:61,0);
            end
        end
        check(last_stalls==cases,"each frame exercised extension final-beat stall");
        $display("RESULT: PASS R6_ABORT_ALL production=%0d cases=%0d checks=%0d last_stalls=%0d cycles=%0d",PRODUCTION,cases,checks,last_stalls,cycles);$finish;
    end
    initial begin #90000000;$fatal(1,"R6 abort bounded watchdog");end
endmodule
