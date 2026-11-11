`timescale 1ns/1ps
`include "pcie_protocol_v1.vh"
`include "stereo_control_v1.vh"
`include "raw_video_v1.vh"
`define RAW_TOP_EP dut.u_pcie.endpoint
`define RAW_TOP_HOST dut.u_pcie.endpoint.host
`define RAW_TOP_DDR dut.u_ddr_store.u_ddr
`define RAW_TOP_STORE dut.g_s04.u_raw_service.g_stereo.u_store

module tb_raw_top_short #(
    parameter ROM_ROOT="rom_init",
    parameter integer TEST_CASE=0
);
    localparam integer WIDTH=`S08_SIM_WIDTH, HEIGHT=`S08_SIM_HEIGHT;
    localparam integer GROUPS=WIDTH*HEIGHT/4, PAYLOAD=5*GROUPS;
    localparam integer RECORD_BYTES=`PCIE_RAW_VIDEO_HEADER_BYTES+PAYLOAD;
    localparam integer JPEG_CASE=2;
    localparam bit DUAL=TEST_CASE!=0;

    reg sys_clk=0, board_ref_clk_100m=0, pcie_mperst=0;
    always #20 sys_clk=~sys_clk;
    always #5 board_ref_clk_100m=~board_ref_clk_100m;
    tri1 cam_sda,cam1_sda;
    anlogic2026 #(.FRAME_WIDTH(WIDTH),.FRAME_HEIGHT(HEIGHT),.SOURCE_SELECT(0),
        .DUAL_CAMERA_ENABLE(1),.STEREO_CAPTURE_DIVISOR(2),.READONLY_UART_ENABLE(0),
        .COLOR_CONFIG_DEFAULT(10'h040),.COLOR_WB_DEFAULT(30'h10040100)) dut(
        .sys_clk(sys_clk),.board_ref_clk_100m(board_ref_clk_100m),
        .mipi_clk_hs_rx_p(1'b0),.mipi_data_hs_p(4'd0),.cam_sda(cam_sda),
        .cam_scl(),.cam_mclk(),.cam_xclr(),
        .mipi1_clk_hs_rx_p(1'b0),.mipi1_data_hs_p(4'd0),.cam1_sda(cam1_sda),
        .cam1_scl(),.cam1_mclk(),.cam1_xclr(),.uart_tx(),.uart_rx(1'b1),
        .ddr_ck_p(),.ddr_ck_n(),.ddr_reset_n(),.ddr_cke(),.ddr_odt(),.ddr_cs_n(),
        .ddr_ras_n(),.ddr_cas_n(),.ddr_we_n(),.ddr_ba(),.ddr_addr(),
        .ddr_dqs_p(),.ddr_dqs_n(),.ddr_dq(),.ddr_dm(),
        .refclk_p(1'b0),.refclk_n(1'b1),.pcie_mperst(pcie_mperst),
        .rxp(1'b0),.rxn(1'b1),.txp(),.txn());

    // Acknowledge the actual shared controller's electrical writes. Shorter
    // waits preserve all recipe words and the 2-stage SDA sampling path.
    assign cam_sda=(dut.u_camera.u_config.u_i2c.state==4||dut.u_camera.u_config.u_i2c.state==5)?1'b0:1'bz;
    assign cam1_sda=(dut.u_camera1.u_config.u_i2c.state==4||dut.u_camera1.u_config.u_i2c.state==5)?1'b0:1'bz;
    defparam dut.u_camera.u_config.SDR_RESET_HOLD_CYCLES=4;
    defparam dut.u_camera.u_config.SDR_RELEASE_WAIT_CYCLES=4;
    defparam dut.u_camera.u_config.SDR_WAKE_CYCLES=4;
    defparam dut.u_camera.u_config.I2C_HALF_PERIOD=2;
    defparam dut.u_camera1.u_config.SDR_RESET_HOLD_CYCLES=4;
    defparam dut.u_camera1.u_config.SDR_RELEASE_WAIT_CYCLES=4;
    defparam dut.u_camera1.u_config.SDR_WAKE_CYCLES=4;
    defparam dut.u_camera1.u_config.I2C_HALF_PERIOD=2;
    defparam dut.u_ddr_store.u_ddr.RAW_ARENA_ENABLE=1;
    defparam dut.u_ddr_store.u_ddr.JPEG_RING_ARENA_ENABLE=1;
    defparam dut.u_jpeg.ROM_INIT_ROOT=ROM_ROOT;
    defparam dut.u_jpeg.ROM_INIT_SUFFIX=".mif.dath";
`ifdef RAW_TOP_TINY
    // The inactive JPEG ingress keeps its HD extension width. The preset
    // CFG frontend retains the original HD geometry and capability contract
    // while RAW uses the small TOP geometry through the stereo source fence.
    defparam dut.u_jpeg_to_ddr.u_ingress.RECORD_EXTENSION_WIDTH=16384;
    defparam dut.g_configured_capture.u_frontend.WIDTH=1920;
    defparam dut.g_configured_capture.u_frontend.HEIGHT=1080;
    defparam dut.g_configured_capture.u_frontend.EXT_SUPPORTED=8'h34;
    defparam dut.g_config.u_config.COMPACT_STAGE2_EXTENSION_ENABLE=1;
    defparam dut.g_private_processing.u_original_source.u_adapter.MAX_WIDTH=1920;
    defparam dut.g_private_processing.u_original_source.u_adapter.MAX_HEIGHT=1080;
`endif

    reg [39:0] crop_data0=0,crop_data1=0;
    reg [1:0] crop_valid=0,crop_sof=0,crop_eol=0,event_valid=0;
    reg [1:0] event_kind0=0,event_kind1=0;
    reg [31:0] sequence0=0,sequence1=0;
    wire fixture_bayer_valid=dut.camera_config_done&&!dut.camera_config_error;
    initial begin
`ifdef RAW_TOP_TINY
        // The injected crop has known Bayer alignment. The hardware's normal
        // qualification additionally requires the fixed 1920x1080 raster.
        force dut.raw_bayer_valid=fixture_bayer_valid;
`endif
        force dut.cropped_raw_data=crop_data0;
        force dut.cropped_raw_valid=crop_valid[0];
        force dut.cropped_raw_sof=crop_sof[0];
        force dut.cropped_raw_eol=crop_eol[0];
        force dut.cropped_raw_abort=1'b0;
        force dut.cropped_raw_sequence=sequence0;
        force dut.cropped_raw_identity_valid=1'b1;
        force dut.physical_event_valid=event_valid[0];
        force dut.physical_event_kind=event_kind0;
        force dut.physical_event_ok=1'b1;
        force dut.physical_event_error=4'd0;
        force dut.physical_event_sequence=sequence0;
        force dut.physical_event_identity_valid=1'b1;

        force dut.camera1_raw=crop_data1;
        force dut.camera1_valid=crop_valid[1];
        force dut.camera1_sof=crop_sof[1];
        force dut.camera1_eol=crop_eol[1];
        force dut.camera1_abort=1'b0;
        force dut.camera1_sequence=sequence1;
        force dut.camera1_identity_valid=1'b1;
        force dut.camera1_event_valid=event_valid[1];
        force dut.camera1_event_kind=event_kind1;
        force dut.camera1_event_ok=1'b1;
        force dut.camera1_event_error=4'd0;
        force dut.camera1_event_sequence=sequence1;
        force dut.camera1_event_identity_valid=1'b1;
    end

    integer checks=0,phase=0,offers=0,retires=0,records=0,routed=0,sources=0,begins=0,finishes=0;
    integer stall_remaining=0,stall_checks=0,wire_beats=0,wire_headers=0;
    reg stalled=0;
    reg [127:0] current_identity=0,stalled_data=0;
    reg [15:0] stalled_keep=0;
    reg [31:0] session;

    task automatic check(input logic condition,input string reason);
        checks++;
        if(condition!==1'b1)$fatal(1,"RAW_TOP_SHORT case=%0d phase=%0d %s t=%0t",TEST_CASE,phase,reason,$time);
    endtask

    task automatic write_bar(input [11:0] offset,input [31:0] word);
        `RAW_TOP_HOST.write_reg(20'h80000+offset,word);
    endtask

    task automatic read_bar(input [11:0] offset,output [31:0] word);
        `RAW_TOP_HOST.read_reg(20'h80000+offset,word);
    endtask

    task automatic expect_bar(input [11:0] offset,input [31:0] expected);
        reg [31:0] got;
        read_bar(offset,got);
        check(got===expected,$sformatf("BAR %03h = %08h, expected %08h",offset,got,expected));
    endtask

    task automatic select_jpeg(input integer version,input integer req,input integer header_bytes);
        integer polls;
        reg [31:0] status;
        wait(dut.record_source_active_valid&&dut.record_source_active_session==session&&dut.record_dfi_select_quiescent);
        write_bar(`PCIE_REG_RECORD_REQUEST_VERSION,version);
        write_bar(`PCIE_REG_RECORD_REQUEST_SEQUENCE,req);
        write_bar(`PCIE_REG_RECORD_REQUEST_SESSION,session);
        write_bar(`PCIE_REG_RECORD_COMMAND,`PCIE_RECORD_V2_COMMAND_SELECT);
        polls=0;
        do begin read_bar(`PCIE_REG_RECORD_STATUS,status);polls++;end
        while(!status[`PCIE_RECORD_V2_STATUS_DONE]&&polls<300);
        check(polls<300&&status[`PCIE_RECORD_V2_STATUS_DONE],"legacy record SELECT ACK");
        expect_bar(`PCIE_REG_RECORD_ERROR,0);
        expect_bar(`PCIE_REG_RECORD_SELECTED_HEADER_LENGTH,header_bytes);
        expect_bar(`PCIE_REG_RECORD_RESPONSE_SEQUENCE,req);
    endtask

    task automatic apply_topology(input bit raw_selected);
        integer polls;
        reg [31:0] status;
        if(DUAL)begin
            write_bar(`PCIE_REG_STEREO_REQUEST_MODE,1);
            write_bar(`PCIE_REG_STEREO_REQUEST_DIVISOR,2);
        end
        if(raw_selected)begin
            write_bar(`PCIE_RAW_VIDEO_REQUEST_PRODUCT,1);
            expect_bar(`PCIE_RAW_VIDEO_REQUEST_PRODUCT,1);
            expect_bar(`PCIE_RAW_VIDEO_ACTIVE_PRODUCT,0);
        end
        write_bar(`PCIE_REG_STEREO_COMMAND,`STEREO_COMMANDS_APPLY);
        polls=0;
        do begin read_bar(`PCIE_REG_STEREO_STATUS,status);polls++;end
        while(!status[`STEREO_STATUS_BITS_DONE]&&polls<300);
        check(polls<300&&status[`STEREO_STATUS_BITS_DONE]&&!status[`STEREO_STATUS_BITS_BUSY],"two-domain STEREO APPLY");
        expect_bar(`PCIE_REG_STEREO_ERROR,0);
        expect_bar(`PCIE_REG_STEREO_ACTIVE_MODE,{31'd0,DUAL});
        expect_bar(`PCIE_REG_STEREO_ACTIVE_DIVISOR,2);
        expect_bar(`PCIE_RAW_VIDEO_ACTIVE_PRODUCT,{31'd0,raw_selected});
        expect_bar(`PCIE_REG_CFG_ACTIVE_SESSION,session);
        expect_bar(`PCIE_REG_CFG_MODE_EPOCH,0);
        check({dut.raw_mode_user,dut.raw_mode_pixel,dut.raw_mode_dfi}=={3{raw_selected}},"all domains agree on the selected product");
    endtask

    function automatic [39:0] group_pattern(input bit eye,input integer index);
        for(integer lane=0;lane<4;lane++)group_pattern[10*lane+:10]=10'(23+index*31+lane*11+(eye?517:0));
    endfunction

    function automatic [63:0] host_field(input integer offset,input integer size);
        host_field=0;
        for(integer b=0;b<size;b++)host_field[8*b+:8]=`RAW_TOP_HOST.host_memory[offset+b];
    endfunction

    task automatic source_event(input bit eye,input [1:0] kind);
        @(negedge dut.pixel_clk);
        if(eye)event_kind1=kind;else event_kind0=kind;
        event_valid[eye]=1;
        do @(posedge dut.pixel_clk);while(!(eye?dut.camera1_event_ready:dut.stereo_event0_ready));
        @(negedge dut.pixel_clk);event_valid[eye]=0;
    endtask

    task automatic send_frame(input bit eye,input [31:0] seq);
        @(negedge dut.pixel_clk);
        if(eye)sequence1=seq;else sequence0=seq;
        source_event(eye,0);
        repeat(4)@(negedge dut.pixel_clk);
        check(eye?dut.u_stereo_capture1.registered_frame:dut.u_stereo_capture0.registered_frame,"actual trusted FS captured");
        for(integer g=0;g<GROUPS;g++)begin
            if(eye)crop_data1=group_pattern(eye,g);else crop_data0=group_pattern(eye,g);
            crop_valid[eye]=1;crop_sof[eye]=g==0;crop_eol[eye]=g%(WIDTH/4)==WIDTH/4-1;
            do @(posedge dut.pixel_clk);while(!eye&&!dut.cropped_raw_ready);
            @(negedge dut.pixel_clk);
        end
        crop_valid[eye]=0;crop_sof[eye]=0;crop_eol[eye]=0;
        source_event(eye,1);
    endtask

    always @(posedge dut.pixel_clk)if(phase==5)begin
        if(dut.stereo_capture0_valid&&dut.stereo_capture0_accept)routed++;
        if(dut.stereo_capture1_valid&&dut.stereo_capture1_accept)routed++;
        if(dut.stereo_source0_valid&&dut.stereo_source0_ready)begin
            check(dut.stereo_source0_ok&&dut.stereo_source0_error==0,"qualified CAM0 SOURCE terminal");
            sources++;
        end
        if(dut.stereo_source1_valid&&dut.stereo_source1_ready)begin
            check(dut.stereo_source1_ok&&dut.stereo_source1_error==0,"qualified CAM1 SOURCE terminal");
            sources++;
        end
    end

    always @(posedge dut.dfi_clk)if(dut.dfi_rst_n&&dut.raw_mode_dfi)begin
        if(`RAW_TOP_STORE.s_begin_valid&&`RAW_TOP_STORE.s_begin_ready)begin
            check(`RAW_TOP_STORE.o_begin_accepted,"matching session/raster and qualified Bayer allocate RAW");
            begins++;
        end
        if(|(`RAW_TOP_STORE.i_finish_valid&`RAW_TOP_STORE.o_finish_ready))begin
            check((`RAW_TOP_STORE.i_finish_valid&`RAW_TOP_STORE.o_finish_ready&~`RAW_TOP_STORE.i_finish_ok)==0,
                  "actual RAW writer terminal has successful SOURCE/B");
            finishes++;
        end
        if(dut.raw_record_valid&&dut.raw_record_ready)begin
            check(offers==retires,"one RAW lease in flight");
            current_identity=dut.raw_record_identity;offers++;
            check(current_identity[127:112]==16'h5241,"native RAW owner marker");
        end
        if(dut.raw_retire_valid&&dut.raw_retire_ready)begin
            check(offers==retires+1&&dut.raw_retire_identity===current_identity,"exact RAW identity returns after ACK");
            retires++;
        end
    end

    always @(negedge dut.user_clk)if(dut.user_rst_n&&phase==5)begin
        if(stall_remaining!=0)begin
            check(dut.actual_c2h_valid&&dut.actual_c2h_last&&`RAW_TOP_EP.i_axis_data===stalled_data&&
                  `RAW_TOP_EP.i_axis_keep===stalled_keep,"native final beat held under endpoint stall");
            stall_checks++;
            stall_remaining--;
            if(stall_remaining==0)`RAW_TOP_EP.hold_axis=0;
        end else if(!stalled&&dut.actual_c2h_valid&&dut.actual_c2h_last)begin
            stalled=1;stall_remaining=5;`RAW_TOP_EP.hold_axis=1;
            stalled_data=`RAW_TOP_EP.i_axis_data;stalled_keep=`RAW_TOP_EP.i_axis_keep;
            check(stalled_keep==16'h03ff,"90-byte payload has a ten-byte tail");
        end
    end

    always @(posedge dut.user_clk)if(phase==5&&dut.actual_c2h_valid&&dut.actual_c2h_ready)begin
        if(wire_beats==0)begin
            check(`RAW_TOP_EP.i_axis_keep==16'hffff&&
                  `RAW_TOP_EP.i_axis_data=={16'(HEIGHT),16'(WIDTH),32'(PAYLOAD),
                    16'(`PCIE_RAW_VIDEO_HEADER_BYTES),16'(`PCIE_RAW_VIDEO_VERSION),32'(`PCIE_RAW_VIDEO_MAGIC)},
                  "native first beat binds ARAW header and length before posted writes");
            wire_headers++;
        end
        wire_beats=dut.actual_c2h_last?0:wire_beats+1;
    end

    task automatic transfer(input bit eye,input [31:0] seq);
        integer aw_before,ar_before,retire_before;
        aw_before=`RAW_TOP_DDR.accepted_aw;ar_before=`RAW_TOP_DDR.accepted_ar;
        retire_before=retires;
        stalled=0;
        if(!DUAL)`RAW_TOP_HOST.record_path="mono_cam0.araw.bin";
        else if(eye)`RAW_TOP_HOST.record_path="dual_cam1.araw.bin";
        else `RAW_TOP_HOST.record_path="dual_cam0.araw.bin";
        `RAW_TOP_HOST.grant(records+1,4096);
        send_frame(eye,seq);
        `RAW_TOP_HOST.wait_safe(0,RECORD_BYTES);
        check(`RAW_TOP_HOST.committed==RECORD_BYTES&&`RAW_TOP_HOST.fence_count==1,"MRd fence commits exact bytes");
        check(`RAW_TOP_DDR.accepted_aw>aw_before&&`RAW_TOP_DDR.accepted_ar>ar_before,"capture write and RAW read reached DDR");
        check(host_field(0,4)==`PCIE_RAW_VIDEO_MAGIC&&host_field(4,2)==`PCIE_RAW_VIDEO_VERSION&&
              host_field(6,2)==`PCIE_RAW_VIDEO_HEADER_BYTES,"ARAW magic, version and 64-byte header");
        check(host_field(8,4)==PAYLOAD&&host_field(12,2)==WIDTH&&host_field(14,2)==HEIGHT,"length and raster identity");
        check(host_field(16,4)==seq&&host_field(20,4)==session&&host_field(24,4)==0&&host_field(28,1)==eye,
              "real SOURCE sequence, session, epoch and camera");
        check(host_field(29,1)==`PCIE_RAW_VIDEO_FORMAT_RAW10&&host_field(30,1)<=3&&
              host_field(31,1)==`PCIE_RAW_VIDEO_FLAG_TIMESTAMP_VALID&&host_field(32,8)!=0&&host_field(40,8)!=0&&
              host_field(48,8)==0&&host_field(56,8)==0,"format, Bayer, actual time/job and reserved header bytes");
        for(integer g=0;g<GROUPS;g++)
            check(host_field(64+5*g,5)=={24'd0,group_pattern(eye,g)},$sformatf("RAW10 LE5 group %0d",g));
        repeat(13)begin
            @(negedge dut.user_clk);
            check(retires==retire_before&&`RAW_TOP_STORE.read_owned&&`RAW_TOP_STORE.owner_job_owned,
                  "SAFE without host ACK cannot release RAW slot");
        end
        `RAW_TOP_HOST.ack;
        wait(retires==retire_before+1&&dut.stereo_empty&&!dut.jpeg_cdc_user_busy);
        records++;
        $display("RAW_TOP_RECORD eye=%0d seq=%0d session=%0d bytes=%0d",eye,seq,session,RECORD_BYTES);
    endtask

    initial begin
        pcie_mperst=1;`RAW_TOP_EP.link_up=1;`RAW_TOP_EP.hold_axis=0;
        // The shared BFM still checks posted bytes, fence and SAFE. Its
        // format-specific AJPG/LZ header checker is replaced above for ARAW.
        `RAW_TOP_HOST.check_header=(TEST_CASE==JPEG_CASE);
        phase=1;
        wait(dut.debug_rst_n&&dut.debug_app_rst_n&&dut.session_rearm_ready&&dut.cfg_user_initialized);
        read_bar(`PCIE_REG_CFG_SESSION,session);
        check(session!=0,"actual CFG BOOT session");
        expect_bar(`PCIE_REG_CFG_ACTIVE_SESSION,session);
        expect_bar(`PCIE_RAW_VIDEO_ACTIVE_PRODUCT,0);
        expect_bar(`PCIE_REG_RECORD_SELECTED_VERSION,1);
        phase=2;
        if(TEST_CASE==JPEG_CASE)begin
            select_jpeg(2,21,192);
            apply_topology(0);
            select_jpeg(4,22,2112);
            check(offers==0&&retires==0&&!`RAW_TOP_EP.o_result_pending,"legacy cold selection does not manufacture frames");
            $display("RESULT: PASS RAW_TOP_SHORT jpeg checks=%0d v2=192 v4=2112",checks);
            $finish;
        end
        apply_topology(1);
        expect_bar(`PCIE_REG_RECORD_SELECTED_VERSION,1);
        expect_bar(`PCIE_REG_RECORD_SELECTED_HEADER_LENGTH,64);
        phase=3;
        `RAW_TOP_HOST.write_reg(12'h008,8);
        write_bar(`PCIE_REG_CONTROL,1);
        wait(dut.session_armed&&dut.stereo_capture_enable&&dut.common_pixel_time_valid);
        check(!dut.camera_config_error&&(!DUAL||!dut.camera1_config_error),"shared I2C startup ACK");
        check(dut.stereo_sensor_30_pixel==DUAL&&dut.camera_sdr_30_mode==DUAL&&
              (!DUAL||dut.cam1_sdr_30_mode)&&dut.stereo_capture_divisor_pixel==1,
              "actual mono SDR60 or dual native SDR30, capture divisor one");
        phase=5;
        $display("RAW_TOP_READY dual=%b t=%0t",DUAL,$time);
        transfer(0,32'h101);
        if(DUAL)transfer(1,32'h209);
        check(records==(DUAL?2:1)&&offers==records&&retires==records&&wire_headers==records&&stall_checks==5*records,
              "each admitted eye committed and retired one complete held-tail record");
        check(routed==GROUPS*records&&sources==records&&begins==records&&finishes==records,
              "all injected crop groups and genuine SOURCE/BEGIN/FINISH handshakes retained");
        check(!dut.raw_processing_fault&&!`RAW_TOP_EP.o_quarantine,"no storage or native transport fault");
        $display("RESULT: PASS RAW_TOP_SHORT raw dual=%b checks=%0d records=%0d stalls=%0d",DUAL,checks,records,stall_checks);
        $finish;
    end

    initial begin
        wait(phase==5);
        #50000;
        $fatal(1,"RAW_TOP_SHORT transfer timeout case=%0d routed=%0d source=%0d begin=%0d finish=%0d AW/B/AR/R=%0d/%0d/%0d/%0d offers=%0d retires=%0d Bayer=%b empty=%b owned=%b ctrl=%b%b%b",
            TEST_CASE,routed,sources,begins,finishes,`RAW_TOP_DDR.accepted_aw,`RAW_TOP_DDR.accepted_b,
            `RAW_TOP_DDR.accepted_ar,`RAW_TOP_DDR.accepted_r,offers,retires,dut.raw_bayer_valid,dut.stereo_empty,
            `RAW_TOP_STORE.read_owned,dut.raw_policy_admit,dut.raw_mode_busy,dut.raw_route_sdr);
    end

    initial begin
        #5000000;
        $fatal(1,"RAW_TOP_SHORT watchdog case=%0d phase=%0d app/armed=%b%b cfg_ready/pause=%b%b mode=%b%b%b cap=%b sensor=%b%b fault=%b offers=%0d retires=%0d rawV/R/done=%b%b%b",
            TEST_CASE,phase,dut.app_enable,dut.session_armed,dut.cfg_source_ready,dut.cfg_pause,
            dut.raw_mode_user,dut.raw_mode_pixel,dut.raw_mode_dfi,dut.stereo_capture_enable,
            dut.camera_config_done,dut.camera1_config_done,dut.raw_processing_fault,
            offers,retires,dut.raw_record_valid,dut.raw_record_ready,dut.raw_record_done);
    end
endmodule
