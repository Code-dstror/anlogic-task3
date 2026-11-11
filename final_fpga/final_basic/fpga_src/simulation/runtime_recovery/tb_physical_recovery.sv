`timescale 1ns/1ps
module tb_physical_recovery;
    parameter integer EXPECT_RECOVERY=0;
    parameter [31:0] INITIAL_SEQUENCE=0;
    reg word_clk=0,pixel_clk=0,rst_n=0,decoder_rst_n=0,phy_stream_reset_n=1;
    always #5 word_clk=~word_clk;always #6.5 pixel_clk=~pixel_clk;
    reg [31:0] word_data=0;reg word_valid=0;
    wire [39:0] raw_data,crop_data,route_data;
    wire raw_valid,raw_ready,raw_sof,raw_eol,raw_abort,raw_identity_valid;
    wire [31:0] raw_sequence,crop_sequence,route_sequence,route_session,route_epoch;
    wire crop_valid,crop_sof,crop_eol,crop_abort,crop_identity_valid;
    wire route_valid,route_accept,route_sof,route_eol,route_eof,route_abort,route_idle,route_fault;
    wire [196:0] route_metadata;
    reg test_quiet_allow=1;
    reg crop_allow=1,event_allow=1,admit_enable=1,axis_allow=1,native_ready=1;
    reg inject_stale_terminal=0,corrupt_context=0;
    reg phy_ready=1,receive_fault=0;wire parser_fault,quarantine;reg [31:0] product_sequence;reg [196:0] product_metadata;
    wire event_valid,event_ready,fence_event_ready,event_ok,event_identity_valid;
    wire [1:0] event_kind;wire [3:0] event_error;wire [31:0] event_sequence;
    wire capture_enable,source_idle,context_ready;
    reg [31:0] session=32'h92345678,epoch=32'h81234567;
    wire [159:0] active_config={epoch,64'd0,session,32'd0};
    wire [31:0] bound_sequence=route_sequence^(corrupt_context?32'd1:32'd0);
    wire [575:0] context_value={route_metadata,route_session,route_epoch,bound_sequence,283'd0};
    wire [63:0] context_tag={32'habcdef98,bound_sequence};
    wire source_valid,source_ready,ingress_source_ready,source_ok,source_camera;reg source_allow=1;
    assign source_ready=source_allow&&ingress_source_ready;
    wire [31:0] source_session,source_epoch,source_sequence;wire [7:0] source_error;
    wire native_valid,native_ok;wire [575:0] native_context;wire [63:0] native_tag;wire [7:0] native_error;
    wire [127:0] axis_data;wire [15:0] axis_keep;wire axis_valid,axis_last;wire [1:0] axis_user;
    wire ingress_idle;
    reg [31:0] planned_sequence=INITIAL_SEQUENCE,last_announced=INITIAL_SEQUENCE;
    integer seed=10,checks=0,pixel_cycles=0,starts=0,ends=0,aborts=0,native_count=0,source_count=0,good_native=0;
    integer crop_groups=0,byte_count=0,fs_count=0,invalid_fs=0;
    reg [31:0] last_source_sequence=0,last_native_sequence=0;
    reg [648:0] held_native;reg native_held=0;reg [105:0] held_source;reg source_held=0;reg [146:0] held_axis;reg axis_held=0;
    wire geometry_pulse=route_valid&&route_accept&&route_eol&&crop_groups==3;
    physical_csi_rx_stream #(.SEQUENCE_INITIAL(INITIAL_SEQUENCE)
`ifdef RECOVERY_GUARD
        ,.FRAME_RESYNC_ENABLE(1)
`endif
    ) rx(
        .i_word_clk(word_clk),.i_pixel_clk(pixel_clk),.i_reset_n(rst_n&&phy_stream_reset_n),.i_decoder_reset_n(decoder_rst_n),.i_identity_rst_n(rst_n),
        .o_identity_fault(parser_fault),.o_identity_diag(),.o_trace_parser(),.o_trace_trigger(),.i_publish_enable(rst_n),.o_fifo_write_ready(),.i_aligned_word(word_data),.i_aligned_valid(word_valid),
        .o_raw_data(raw_data),.o_raw_valid(raw_valid),.i_raw_ready(raw_ready),.o_raw_sof(raw_sof),.o_raw_eol(raw_eol),
        .o_raw_sequence(raw_sequence),.o_raw_identity_valid(raw_identity_valid),
        .m_frame_event_valid(event_valid),.m_frame_event_ready(event_ready),.m_frame_event_kind(event_kind),
        .m_frame_event_ok(event_ok),.m_frame_event_error(event_error),.m_frame_event_sequence(event_sequence),.m_frame_event_identity_valid(event_identity_valid),
        .o_frame_abort(raw_abort),.o_error_code(),.o_header_ecc_error_count(),.o_payload_crc_error_count(),
        .o_overflow_error_count(),.o_length_error_count(),.o_wait_for_sync(),.o_packet_done());
    production_source_identity_guard guard(.clk(pixel_clk),.rst_n(rst_n),.phy_ready(phy_ready),.receive_fault(receive_fault),.parser_identity_fault(parser_fault),
        .event_valid(event_valid&&event_ready),.event_kind(event_kind),.event_identity_valid(event_identity_valid),.quarantine(quarantine)
`ifdef RECOVERY_GUARD
        ,.i_recovery_quiet(test_quiet_allow&&source_idle&&route_idle&&ingress_idle&&!crop_valid&&!raw_valid)
`endif
    );
    assign event_ready=event_allow&&fence_event_ready&&!inject_stale_terminal;
    physical_camera_crop #(.WIDTH(8),.HEIGHT(2),.FIRST_ROW(1),.FIRST_GROUP(1)) crop(
        .i_clk(pixel_clk),.i_rst_n(rst_n),.i_raw_data(raw_data),.i_raw_valid(raw_valid),.o_raw_ready(raw_ready),
        .i_raw_sof(raw_sof),.i_raw_eol(raw_eol),.i_raw_abort(raw_abort),.i_raw_sequence(raw_sequence),.i_raw_identity_valid(raw_identity_valid),
        .o_data(crop_data),.o_valid(crop_valid),.i_ready(crop_allow),.o_sof(crop_sof),.o_eol(crop_eol),.o_abort(crop_abort),
        .o_sequence(crop_sequence),.o_identity_valid(crop_identity_valid));
    physical_capture_router #(.WIDTH(8),.HEIGHT(2)) router(
        .clk(pixel_clk),.rst_n(rst_n),.i_future_enable(capture_enable),.i_initialized(1'b1),.i_active_config(active_config),
        .i_data(crop_data),.i_valid(crop_valid),.i_accept(crop_allow),.i_sof(crop_sof),.i_eol(crop_eol),.i_abort(crop_abort),
        .i_source_sequence(crop_sequence),.i_source_identity_valid(crop_identity_valid),
        .i_metadata({1'b1,1'b1,2'b01,1'b0,64'd0,32'd100,32'd2,32'h12345678,planned_sequence}),
        .o_data(route_data),.o_valid(route_valid),.o_accept(route_accept),.o_sof(route_sof),.o_eol(route_eol),
        .o_eof(route_eof),.o_abort(route_abort),.o_frame_idle(route_idle),.o_session(route_session),.o_epoch(route_epoch),
        .o_sequence(route_sequence),.o_metadata(route_metadata),.o_fault(route_fault));
    physical_identity_source_fence fence(
        .i_clk(pixel_clk),.i_rst_n(rst_n),.i_data_reset_n(rst_n),.i_admit_enable(admit_enable&&!quarantine),.i_continuity_fault(quarantine),.i_event_valid(inject_stale_terminal||(event_valid&&event_allow)),
        .o_event_ready(fence_event_ready),.i_event_kind(inject_stale_terminal?2'd1:event_kind),.i_event_ok(inject_stale_terminal?1'b1:event_ok),.i_event_error(inject_stale_terminal?8'd0:{4'd0,event_error}),
        .i_event_sequence(inject_stale_terminal?planned_sequence-1'b1:event_sequence),.i_event_identity_valid(inject_stale_terminal?1'b1:event_identity_valid),
        .i_context_valid(route_valid&&route_accept&&route_sof),.o_context_ready(context_ready),.i_context(context_value),.i_context_tag(context_tag),
        .i_context_session(route_session),.i_context_epoch(route_epoch),.i_context_sequence(bound_sequence),.i_context_camera(1'b0),
        .i_crop_geometry_done(geometry_pulse),.i_crop_input_quiet(!crop_valid),.i_rgb_geometry_done(geometry_pulse),.i_rgb_output_quiet(!crop_valid),
        .i_source_fault(crop_abort),.i_source_error(8'd2),.o_capture_frame_enable(capture_enable),.o_source_idle(source_idle),
        .o_raw_source_valid(source_valid),.i_raw_source_ready(source_ready),.o_raw_source_session(source_session),.o_raw_source_epoch(source_epoch),
        .o_raw_source_sequence(source_sequence),.o_raw_source_camera(source_camera),.o_raw_source_ok(source_ok),.o_raw_source_error(source_error),
        .o_native_source_valid(native_valid),.i_native_source_ready(native_ready),.o_native_source_context(native_context),.o_native_source_tag(native_tag),
        .o_native_source_ok(native_ok),.o_native_source_error(native_error),.o_drop_count(),.o_stale_event_count());
    raw10_frame_ingress #(.WIDTH(8),.HEIGHT(2),.CONTEXT_ENABLE(1),.EXTERNAL_SEQUENCE_ENABLE(1),.SOURCE_TERMINAL_ENABLE(1)) ingress(
        .i_clk(pixel_clk),.i_rst_n(rst_n),.i_enable(1'b1),.i_data(route_data),.i_valid(route_valid),.i_accept(route_accept),
        .i_sof(route_sof),.i_eol(route_eol),.i_abort(route_abort),.i_camera(1'b0),.i_epoch(route_epoch),
        .i_external_sequence(bound_sequence),.i_session_id(route_session),.i_metadata_valid(1'b0),.i_timestamp(64'd0),
        .i_actual_exposure(32'd0),.i_gain(32'd0),.i_calibration_id(32'd0),.i_source_kind(1'b1),.i_exposure_role(2'd0),
        .i_exposure_group(32'd0),.i_source_qualified(1'b0),.i_source_valid(source_valid&&source_allow),.o_source_ready(ingress_source_ready),
        .i_source_session(source_session),.i_source_epoch(source_epoch),.i_source_sequence(source_sequence),.i_source_camera(source_camera),
        .i_source_ok(source_ok),.i_source_error(source_error),.o_source_stale_count(),.o_axis_tdata(axis_data),.o_axis_tkeep(axis_keep),
        .o_axis_tvalid(axis_valid),.i_axis_tready(axis_allow),.o_axis_tlast(axis_last),.o_axis_tuser(axis_user),
        .o_capture_idle(ingress_idle),.o_frame_accept(),.o_drop_count(),.o_error_count());
    function [5:0] ecc(input [23:0] d);
        begin
            ecc[0]=d[0]^d[1]^d[2]^d[4]^d[5]^d[7]^d[10]^d[11]^d[13]^d[16]^d[20]^d[21]^d[22]^d[23];
            ecc[1]=d[0]^d[1]^d[3]^d[4]^d[6]^d[8]^d[10]^d[12]^d[14]^d[17]^d[20]^d[21]^d[23];
            ecc[2]=d[0]^d[2]^d[3]^d[5]^d[6]^d[9]^d[11]^d[12]^d[15]^d[18]^d[20]^d[21]^d[22];
            ecc[3]=d[1]^d[2]^d[3]^d[7]^d[8]^d[9]^d[13]^d[14]^d[15]^d[19]^d[20]^d[21]^d[23];
            ecc[4]=d[4]^d[5]^d[6]^d[7]^d[8]^d[9]^d[16]^d[17]^d[18]^d[19]^d[20]^d[22]^d[23];
            ecc[5]=d[10]^d[11]^d[12]^d[13]^d[14]^d[15]^d[16]^d[17]^d[18]^d[19]^d[21]^d[22]^d[23];
        end
    endfunction
    function [15:0] crc_byte(input [15:0] c,input [7:0] b);
        reg [15:0] v;begin v=c^b;for(integer k=0;k<8;k=k+1)v=v[0]?((v>>1)^16'h8408):(v>>1);crc_byte=v;end
    endfunction
    function [9:0] expected_sample(input integer index);
        integer row,group,lane,high,low;
        begin row=1+index/8;group=1+(index%8)/4;lane=index%4;high=(seed+row*20+group*5+lane)&255;low=(seed+row*20+group*5+4)&255;
            expected_sample=(high<<2)|((low>>(lane*2))&3);end
    endfunction
    function [7:0] expected_byte(input integer offset);
        reg [9:0] s;begin expected_byte=0;for(integer k=0;k<8;k=k+1)begin s=expected_sample((offset*8+k)/10);expected_byte[k]=(s>>((offset*8+k)%10))&1;end end
    endfunction
    task check(input bit ok,input string why);begin checks=checks+1;if(!ok)$fatal(1,"%s seq=%h parser=%0d fence=%0d starts=%0d ends=%0d aborts=%0d native=%0d good=%0d invalid_fs=%0d routerfault=%b trusted=%b time=%t",why,planned_sequence,rx.u_word_core.state,fence.state,starts,ends,aborts,native_count,good_native,invalid_fs,route_fault,rx.u_word_core.sequence_trusted,$time);end endtask
    task word(input [31:0] value);begin @(negedge word_clk);word_data=value;word_valid=1;@(negedge word_clk);word_valid=0;end endtask
    task header(input [7:0] dt,input bit corrected);
        reg [23:0] h;begin h={16'h37a1,dt};word({2'b0,ecc(h),h}^(corrected?32'd1:0));repeat(2)@(negedge word_clk);end
    endtask
    task line(input integer line_seed,input bit bad_crc);
        reg [23:0] h;reg [31:0] w;reg [15:0] c;reg [7:0] v;
        begin h={16'd20,8'h2b};word({2'b0,ecc(h),h});repeat(2)@(negedge word_clk);c=16'hffff;
            for(integer g=0;g<5;g=g+1)begin w=0;for(integer k=0;k<4;k=k+1)begin v=(line_seed+g*4+k)&255;c=crc_byte(c,v);w[k*8+:8]=v;end word(w);end
            word({16'd0,c[15:8],c[7:0]^{7'd0,bad_crc}});repeat(4)@(negedge word_clk);end
    endtask
    task start_frame(input bit corrected);
        begin if(planned_sequence!=32'hffffffff)planned_sequence=planned_sequence+1'b1;seed=seed+7;header(0,corrected);end
    endtask
    task rows;begin line(seed,0);line(seed+20,0);line(seed+40,0);end endtask
    task quiet;
        integer n;begin n=0;repeat(15)@(negedge pixel_clk);while((!source_idle||!ingress_idle||event_valid||crop_valid)&&n<20000)begin @(negedge pixel_clk);n=n+1;end
            check(n<20000,"real event/crop/source/RAW drain");repeat(5)@(negedge pixel_clk);end
    endtask
    task cold_restart;
        begin @(negedge word_clk);rst_n=0;decoder_rst_n=0;repeat(8)@(negedge word_clk);session=session+1;epoch=epoch+1;planned_sequence=INITIAL_SEQUENCE;
            rst_n=1;decoder_rst_n=1;repeat(30)@(negedge pixel_clk);end
    endtask
    always @(posedge pixel_clk)begin
        pixel_cycles=pixel_cycles+1;if(pixel_cycles>200000)$fatal(1,"timeout");
        if(!rst_n)begin crop_groups<=0;byte_count=0;last_announced=INITIAL_SEQUENCE;axis_held=0;native_held=0;source_held=0;end
        else begin
            if(axis_held)check(axis_valid&&{axis_user,axis_last,axis_keep,axis_data}===held_axis,"RAW token stable");
            if(native_held)check(native_valid&&{native_context,native_tag,native_ok,native_error}===held_native,"native SOURCE payload, identity, tag and status stable");
            if(source_held)check(source_valid&&{source_session,source_epoch,source_sequence,source_camera,source_ok,source_error}===held_source,"RAW SOURCE payload, identity and status stable");
            axis_held=axis_valid&&!axis_allow;held_axis={axis_user,axis_last,axis_keep,axis_data};native_held=native_valid&&!native_ready;held_native={native_context,native_tag,native_ok,native_error};
            source_held=source_valid&&!source_ready;held_source={source_session,source_epoch,source_sequence,source_camera,source_ok,source_error};
            if(event_valid&&event_ready&&event_kind==0)begin
                crop_groups<=0;fs_count=fs_count+1;
                if(event_identity_valid)begin check(event_sequence>last_announced,"published FS strict physical ordering");last_announced=event_sequence;end
                else invalid_fs=invalid_fs+1;
            end
            if(route_valid&&route_accept)begin
                if(route_sof)begin product_sequence=route_sequence;product_metadata=route_metadata;end
                check(route_sequence==last_announced&&crop_identity_valid,"crop/router inherits same parser FS identity");
                check(route_sof==(crop_groups==0)&&route_eol==(crop_groups%2==1),"crop raster");
                for(integer k=0;k<4;k=k+1)check(route_data[k*10+:10]===expected_sample(crop_groups*4+k),"real MIPI sample decode");
                crop_groups<=crop_groups+1;
            end
            if(axis_valid&&axis_allow)begin
                if(axis_user==0)begin
                    for(integer k=0;k<16;k=k+1)if(axis_keep[k])begin check(axis_data[k*8+:8]===expected_byte(byte_count),"RAW10 bit packing");byte_count=byte_count+1;end
                end else if(axis_user==1&&!axis_last)begin starts=starts+1;byte_count=0;check(axis_data[31:0]==(product_sequence^(corrupt_context?32'd1:0)),"RAW START bound source number");end
                else if(axis_user==2)begin ends=ends+1;check(axis_data[64]&&byte_count==20,"actual good END");end
                else if(axis_user==3)aborts=aborts+1;
            end
            if(source_valid&&source_ready)begin source_count=source_count+1;last_source_sequence=source_sequence;
                check(source_sequence==(last_announced^(corrupt_context?32'd1:0))&&source_session==session&&source_epoch==epoch,"RAW SOURCE same full source identity");
                if(corrupt_context)check(!source_ok&&source_error==7,"mismatched crop context fails RAW source");end
            if(native_valid&&native_ready)begin native_count=native_count+1;last_native_sequence=native_context[314:283];
                check(native_context[378:347]==session&&native_context[346:315]==epoch&&native_context[314:283]==(product_sequence^(corrupt_context?32'd1:0))&&native_tag[31:0]==native_context[314:283],"JPEG SOURCE same bound identity");
                check(native_context[575:379]===product_metadata&&native_context[410:379]==product_sequence,"native metadata frozen with its admitted source generation");
                if(corrupt_context)check(!native_ok&&native_error==7,"mismatched crop context fails JPEG source");
                if(native_ok)good_native=good_native+1;end
        end
    end
    integer owned[0:255],raw_retired[0:255],native_retired[0:255];
    integer raw_status[0:255],native_status[0:255];integer si,sq;
    reg [31:0] previous_parser_count=0;
    always @(posedge pixel_clk)begin
        if(!rst_n)begin
            previous_parser_count=INITIAL_SEQUENCE;
            for(si=0;si<256;si=si+1)begin owned[si]=0;raw_retired[si]=0;native_retired[si]=0;raw_status[si]=-1;native_status[si]=-1;end
        end else begin
            check(rx.u_word_core.sequence_counter>=previous_parser_count,"source sequence never rewinds within cohort");
            previous_parser_count=rx.u_word_core.sequence_counter;
            if(route_valid&&route_accept&&route_sof)begin
                sq=route_sequence;check(sq<256&&owned[sq]==0,"unique crop context owner");owned[sq]=owned[sq]+1;
            end
            if(source_valid&&source_ready)begin
                sq=source_sequence;check(sq<256&&owned[sq]==1&&raw_retired[sq]==0,"RAW SOURCE exactly once for admitted crop");
                raw_retired[sq]=raw_retired[sq]+1;raw_status[sq]=source_ok;
            end
            if(native_valid&&native_ready)begin
                sq=native_tag[31:0];check(sq<256&&owned[sq]==1&&native_retired[sq]==0,"native SOURCE exactly once for admitted crop");
                native_retired[sq]=native_retired[sq]+1;native_status[sq]=native_ok;
            end
        end
    end
    integer a,b,c,base_fs,repeat_case;reg [31:0] saved_count;
    task clean_frame;begin start_frame(0);rows();header(1,0);quiet();end endtask
    task malformed;begin word(32'h80000000);repeat(15)@(negedge pixel_clk);end endtask
    initial begin
        repeat(5)@(negedge word_clk);rst_n=1;decoder_rst_n=1;repeat(30)@(negedge pixel_clk);
        malformed();a=starts;clean_frame();clean_frame();
        check(starts==a+2,"b68 startup protection preserves both first clean frames");
        $display("EVIDENCE startup_unknown_then_two_frames starts=%0d quarantine=%b parserfault=%b routerfault=%b",starts-a,quarantine,parser_fault,route_fault);
        cold_restart();phy_ready=1;repeat(5)@(negedge pixel_clk);phy_ready=0;repeat(5)@(negedge pixel_clk);phy_ready=1;
        a=starts;clean_frame();clean_frame();check(starts==a+2,"b68 pre-cohort PHY training preserves both first clean frames");
        $display("EVIDENCE PHY_ready_low_ready_then_two_frames starts=%0d quarantine=%b parserfault=%b",starts-a,quarantine,parser_fault);
        if(!EXPECT_RECOVERY)begin $display("RESULT: PASS physical recovery baseline counterexamples checks=%0d",checks);$finish;end
        // Already published positive native SOURCE is immutable across PHY loss.
        source_allow=0;native_ready=0;start_frame(0);rows();header(1,0);repeat(40)@(negedge pixel_clk);
        check(source_valid&&source_ok&&native_valid&&native_ok,"actual positive RAW/native SOURCE presented before PHY fault");a=native_count;b=good_native;
        phy_ready=0;repeat(8)@(negedge pixel_clk);check(quarantine&&source_valid&&source_ok&&native_valid&&native_ok,"fault preserves stalled positive RAW/native SOURCE");
        // A real next FS queues behind the old owner; it cannot clear quarantine.
        start_frame(0);rows();header(1,0);repeat(30)@(negedge pixel_clk);
        check(quarantine&&native_valid&&native_ok&&native_count==a,"queued FS cannot clear while old source owner is blocked");
        phy_ready=1;source_allow=1;native_ready=1;quiet();check(native_count==a+1&&good_native==b+1,"old positive terminal retires exactly once");
        // The queued FS may have been consumed while RAW END was still pending.
        // Supply a fresh FS after the complete RAW/native owner is really idle.
        a=starts;if(quarantine)begin clean_frame();check(starts==a&&!quarantine,"fresh quiet FS clears quarantine after old RAW END");end
        a=good_native;clean_frame();check(good_native==a+1,"next frame after PHY drain completes positively");
        // Runtime undecodable header must terminate current crop product negatively.
        a=ends;b=aborts;c=good_native;start_frame(0);rows();malformed();quiet();
        check(ends==a&&aborts==b+1&&good_native==c&&quarantine,"unknown header yields negative RAW/native current-frame terminal");
        a=starts;clean_frame();check(starts==a&&!quarantine,"first recovery FS drains as ignored boundary");clean_frame();
        check(starts==a+1&&last_source_sequence==planned_sequence&&last_native_sequence==planned_sequence,"post-header recovery uses new matching RAW/native identity");
        // A bad CRC after the selected crop still cannot create good product.
        a=ends;b=aborts;c=good_native;start_frame(0);rows();line(seed+60,1);header(1,0);quiet();
        check(ends==a&&aborts==b+1&&good_native==c,"late uncropped bad CRC negatively closes owner");
        clean_frame();check(good_native==c+1,"CRC next clean frame succeeds");
        // Lose PHY/FIFO/parser in the middle of selected raster: no FE/ABORT
        // can survive that reset. Guard continuity must retire the old owner.
        a=ends;b=aborts;c=good_native;start_frame(0);line(seed,0);line(seed+20,0);
        repeat(20)@(negedge pixel_clk);check(!source_idle&&!route_idle,"partial real crop has an owned unfinished product");
        saved_count=rx.u_word_core.sequence_counter;phy_ready=0;phy_stream_reset_n=0;decoder_rst_n=0;
        repeat(12)@(negedge word_clk);phy_stream_reset_n=1;decoder_rst_n=1;phy_ready=1;quiet();
        check(ends==a&&aborts==b+1&&good_native==c&&rx.u_word_core.sequence_counter==saved_count&&quarantine,"PHY reset lost terminal but old partial owner retires negatively without count rewind");
        clean_frame();check(quarantine&&route_idle&&!route_fault&&good_native==c,"real new raw SOF cleans abandoned raster before guard may recover");
        clean_frame();check(!quarantine&&!route_fault&&good_native==c,"fresh quiet FS clears quarantine after abandoned raster cleanup");
        clean_frame();check(good_native==c+1,"next complete frame after midraster PHY reset succeeds");
        // External receive fault during a held native failure is not recovery authority.
        native_ready=0;start_frame(0);rows();receive_fault=1;repeat(8)@(negedge pixel_clk);header(1,0);repeat(30)@(negedge pixel_clk);
        check(native_valid&&!native_ok&&quarantine,"receive fault authenticated negative terminal held");a=native_count;
        start_frame(0);rows();header(1,0);repeat(15)@(negedge pixel_clk);check(native_valid&&!native_ok&&quarantine,"later FS cannot steal negative source identity");
        receive_fault=0;native_ready=1;quiet();check(native_count==a+1,"negative source retired exactly once");
        a=starts;if(quarantine)begin clean_frame();check(starts==a&&!quarantine,"fresh quiet FS clears after negative terminal");end
        a=good_native;clean_frame();check(good_native==a+1,"final recovery good source");
        // Same live cohort: four repeated losses, no power/reset escape.
        for(repeat_case=0;repeat_case<4;repeat_case=repeat_case+1)begin
            a=ends;b=aborts;c=good_native;start_frame(0);rows();malformed();quiet();
            check(ends==a&&aborts==b+1&&good_native==c&&quarantine,"repeat unknown header has one negative product");
            repeat(200)@(negedge pixel_clk);check(quarantine,"silence cannot rearm a fault");
            a=starts;test_quiet_allow=0;clean_frame();clean_frame();
            check(starts==a&&quarantine&&good_native==c,"valid FS cannot override missing recovery quiet");
            test_quiet_allow=1;clean_frame();check(starts==a&&!quarantine,"recovery boundary is ignored before future admission");
            clean_frame();check(starts==a+1&&good_native==c+1,"next complete repeated-recovery frame succeeds");
        end
        for(si=0;si<256;si=si+1)if(owned[si])check(raw_retired[si]==1&&native_retired[si]==1&&raw_status[si]==native_status[si],"all real crop owners retired once with matching result");
        $display("EVIDENCE repeated_runtime_loss_same_cohort faults=4 quiet_denied_FS=8 silent_PIX_cycles_each=200 exact_owner_retirement=1");
        $display("RESULT: PASS physical recovery checks=%0d FS=%0d RAW_END=%0d RAW_ABORT=%0d native=%0d good=%0d",checks,fs_count,ends,aborts,native_count,good_native);$finish;
    end
endmodule
