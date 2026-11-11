`timescale 1ns/1ps
`include "pcie_protocol_v1.vh"
`include "stereo_control_v1.vh"
`define DUAL_MEM dut.u_ddr_store.u_ddr
`define DUAL_EP dut.u_pcie.endpoint
`define DUAL_HOST dut.u_pcie.endpoint.host
`define DUAL_STORE dut.g_s04.u_raw_service.g_stereo.u_store
`define DUAL_NORMAL dut.g_private_processing.u_processing.u_job_service.u_scheduler.g_normal_replay.u_normal
`define DUAL_F21 dut.g_preprocess.g_live_f21.u_live
`define DUAL_RAW dut.g_s04.u_raw_service
module tb_dual_imx415 #(
    parameter ROM_ROOT="../../../src_fpga/simulation/assets/rom_init",
    parameter integer JPEG_QUALITY=80, THROUGHPUT_FRAMES=0
);
    localparam integer WIDTH=1920,HEIGHT=1080;
    localparam integer CAPTURE_DIVISOR=THROUGHPUT_FRAMES!=0?2:1;
    localparam integer EXPECTED_RECORDS=THROUGHPUT_FRAMES!=0?THROUGHPUT_FRAMES*2:2;
    localparam integer MAX_RECORDS=16;
    localparam integer HOST_BYTES=THROUGHPUT_FRAMES!=0?4194304:1048576;
    localparam string RAW_PATTERN=THROUGHPUT_FRAMES!=0?"hashed_detail_v1":"dual_raw10_rggb_v1";
    reg sys_clk=0,board_ref_clk_100m=0,pcie_mperst=0,uart_rx=1;
    always #20 sys_clk=~sys_clk;
    always #5 board_ref_clk_100m=~board_ref_clk_100m;
    wire cam_scl,cam_sda,cam_mclk,cam_xclr,cam1_scl,cam1_sda,cam1_mclk,cam1_xclr,uart_tx;
    wire [0:0] ddr_ck_p,ddr_ck_n,ddr_cke,ddr_odt,ddr_cs_n,txp,txn;
    wire ddr_reset_n,ddr_ras_n,ddr_cas_n,ddr_we_n;
    wire [2:0] ddr_ba;wire [13:0] ddr_addr;
    wire [1:0] ddr_dqs_p,ddr_dqs_n,ddr_dm;wire [15:0] ddr_dq;
    anlogic2026 #(.FRAME_WIDTH(WIDTH),.FRAME_HEIGHT(HEIGHT),.SOURCE_SELECT(0),
        .DUAL_CAMERA_ENABLE(1),.STEREO_CAPTURE_DIVISOR(CAPTURE_DIVISOR),
        .READONLY_UART_ENABLE(1),.READONLY_UART_REPORT_CYCLES(250000),
        .COLOR_CONFIG_DEFAULT(10'h040),.COLOR_WB_DEFAULT(30'h10040100)) dut(
        .sys_clk(sys_clk),.board_ref_clk_100m(board_ref_clk_100m),
        .mipi_clk_hs_rx_p(1'b0),.mipi_data_hs_p(4'd0),
        .cam_scl(cam_scl),.cam_sda(cam_sda),.cam_mclk(cam_mclk),.cam_xclr(cam_xclr),
        .mipi1_clk_hs_rx_p(1'b0),.mipi1_data_hs_p(4'd0),
        .cam1_scl(cam1_scl),.cam1_sda(cam1_sda),.cam1_mclk(cam1_mclk),.cam1_xclr(cam1_xclr),
        .uart_tx(uart_tx),.uart_rx(uart_rx),.ddr_ck_p(ddr_ck_p),.ddr_ck_n(ddr_ck_n),
        .ddr_reset_n(ddr_reset_n),.ddr_cke(ddr_cke),.ddr_odt(ddr_odt),.ddr_cs_n(ddr_cs_n),
        .ddr_ras_n(ddr_ras_n),.ddr_cas_n(ddr_cas_n),.ddr_we_n(ddr_we_n),.ddr_ba(ddr_ba),
        .ddr_addr(ddr_addr),.ddr_dqs_p(ddr_dqs_p),.ddr_dqs_n(ddr_dqs_n),.ddr_dq(ddr_dq),.ddr_dm(ddr_dm),
        .refclk_p(1'b0),.refclk_n(1'b1),.pcie_mperst(pcie_mperst),.rxp(1'b0),.rxn(1'b1),.txp(txp),.txn(txn));
    // Real sensor I2C masters run; only their slave ACK electrical input is modeled.
    assign cam_sda=(dut.u_camera.u_hdr_config.u_i2c.state==4||dut.u_camera.u_hdr_config.u_i2c.state==5||
        dut.u_camera.u_config.u_i2c.state==4||dut.u_camera.u_config.u_i2c.state==5)?1'b0:1'bz;
    assign cam1_sda=(dut.u_camera1.u_config.u_i2c.state==4||dut.u_camera1.u_config.u_i2c.state==5)?1'b0:1'bz;
    defparam dut.u_camera.u_config.WAIT_CYCLES=4;
    defparam dut.u_camera.SDR_WAKE_CYCLES=4;
    defparam dut.u_camera1.SDR_WAKE_CYCLES=4;
    defparam dut.u_camera.u_config.I2C_HALF_PERIOD=4;
    defparam dut.u_camera1.CONFIG_WAIT_CYCLES=4;
    defparam dut.u_camera1.I2C_HALF_PERIOD=4;
    defparam dut.u_ddr_store.u_ddr.RAW_ARENA_ENABLE=1;
    defparam dut.u_ddr_store.u_ddr.JPEG_RING_ARENA_ENABLE=1;
    defparam dut.u_jpeg.ROM_INIT_ROOT=ROM_ROOT;
    defparam dut.u_jpeg.ROM_INIT_SUFFIX=".mif.dath";
    wire [31:0] word0,word1;wire valid0,valid1;
    dual_csi_word_source #(.CAMERA(0),.WIDTH(WIDTH),.HEIGHT(HEIGHT),.HIGH_DETAIL(THROUGHPUT_FRAMES!=0)) source0(
        .word_clk(dut.u_camera.u_receiver.o_hs_word_clk),.word(word0),.valid(valid0));
    dual_csi_word_source #(.CAMERA(1),.WIDTH(WIDTH),.HEIGHT(HEIGHT),.HIGH_DETAIL(THROUGHPUT_FRAMES!=0)) source1(
        .word_clk(dut.u_camera1.u_receiver.o_hs_word_clk),.word(word1),.valid(valid1));
    initial begin
        force dut.u_camera.u_receiver.geared_word=word0;
        force dut.u_camera.u_receiver.geared_word_valid=valid0;
        force dut.u_camera1.u_receiver.geared_word=word1;
        force dut.u_camera1.u_receiver.geared_word_valid=valid1;
    end
    integer checks=0,event_fd,source_count=0,writer_count=0,retire_count=0,host_count=0;
    integer processing_count=0,raw_retire_count=0,backend_index;
    integer local_fd=0,local_index=-1,user_index=-1,held_checks=0,ack_hold_checks=0;
    integer cameras[0:MAX_RECORDS-1],slots[0:MAX_RECORDS-1];
    reg [31:0] sessions[0:MAX_RECORDS-1],epochs[0:MAX_RECORDS-1],sequences[0:MAX_RECORDS-1],generations[0:MAX_RECORDS-1],tags[0:MAX_RECORDS-1];
    reg [63:0] timestamps[0:MAX_RECORDS-1];
    reg [63:0] jobs[0:MAX_RECORDS-1];
    reg written[0:MAX_RECORDS-1],last_seen[0:MAX_RECORDS-1],safe_seen[0:MAX_RECORDS-1],ack_seen[0:MAX_RECORDS-1],retired[0:MAX_RECORDS-1];
    reg private_ack_consumed[0:MAX_RECORDS-1],processing_seen[0:MAX_RECORDS-1],raw_retire_accepted[0:MAX_RECORDS-1],raw_retired[0:MAX_RECORDS-1];
    reg done=0,held=0;reg [144:0] held_axis;
    reg [31:0] value,session;
    integer phase=0,q_frame_phase=0,q_reply_phase=0;
    integer cfg_observed_sofs=0;reg [31:0] cfg_observed_sequence=0;
    task automatic check(input bit condition,input string message);
        begin checks++;if(!condition)$fatal(1,"DUAL_MAIN %s t=%0t",message,$time);end
    endtask
    task automatic event_log(input string event_name,input integer index);
        begin
            $fdisplay(event_fd,"{\"event\":\"%s\",\"camera\":%0d,\"session\":%0d,\"epoch\":%0d,\"sequence\":%0d,\"time\":%0t}",
                event_name,cameras[index],sessions[index],epochs[index],sequences[index],$time);
            $fflush(event_fd);
            if(THROUGHPUT_FRAMES!=0)throughput_identity(event_name,index);
        end
    endtask
    // Readonly diagnostics: sampled progress plus actual DFI terminal pulses.
    // These observations neither drive DUT state nor supply expected results.
    task automatic progress;
        begin
            $display("DUAL_PROGRESS sources=%0d writers=%0d host=%0d retire=%0d processing=%0d raw_retire=%0d time=%0t",source_count,writer_count,host_count,retire_count,processing_count,raw_retire_count,$time);
            $display("DUAL_CONTROL phase=%0d qFrame=%0d qReply=%0d cfgReady/pause/idle=%b%b%b app/armed=%b%b sensor/publish/decoder=%b%b%b captureV/R/SOF=%b%b%b physicalEnable=%b epoch=%0d",
                phase,q_frame_phase,q_reply_phase,dut.cfg_source_ready,dut.cfg_pause,dut.cfg_pipeline_idle,
                dut.app_enable,dut.session_armed,dut.camera_config_done,dut.u_camera.u_receiver.publish_enable,
                dut.u_camera.u_receiver.decoder_reset_n,dut.capture0_valid,dut.capture0_accept,dut.capture0_sof,
                dut.physical_frame_enable,dut.cfg_epoch);
            $display("DUAL_DIAG_JOB time=%0t job_v/r=%b%b empty=%b job=%h camera=%b seq=%0d retire_v/r/d/e=%b%b%b%b retire_job=%h",
                $time,dut.stereo_job_valid,dut.stereo_job_ready,dut.stereo_empty,dut.stereo_job_id,
                dut.stereo_job_frame[4],dut.stereo_job_frame[108:77],dut.stereo_retire_valid,dut.stereo_retire_ready,
                dut.stereo_retire_done,dut.stereo_retire_error,dut.stereo_retire_id);
            $display("DUAL_DIAG_PROCESS time=%0t pixel_busy/owned/pool_idle=%b%b%b native_done/error=%b%b native_job=%h read_quiet=%b result_v/e=%b%b result_job=%h hdr_source/reader/pixel_fault=%b%b%b processing_fault=%b",
                $time,dut.processing_pixel_busy,dut.processing_context_owned,dut.processing_pool_idle,
                dut.raw_private_native_done,dut.raw_private_native_error,dut.raw_private_native_job,dut.raw_read_quiescent,
                dut.stereo_processing_result_valid,dut.stereo_processing_result_error,dut.stereo_processing_result_job,
                dut.hdr_source_fault,dut.hdr_reader_fault,dut.hdr_pixel_fault,dut.raw_processing_fault);
            $display("DUAL_DIAG_STORE time=%0t read_owned/start/read_complete/processing_seen/native_sent=%b%b%b%b%b reader_state=%0d reader_fault=%b owner_state=%0d owner_slots=%b%b%b%b normal_state=%0d normal_ctx/read/native/processing/failed=%b%b%b%b%b normal_fault/code=%b/%h",
                $time,`DUAL_STORE.read_owned,`DUAL_STORE.start_pending,`DUAL_STORE.read_complete,
                `DUAL_STORE.processing_seen,`DUAL_STORE.native_sent,`DUAL_STORE.u_reader.state,`DUAL_STORE.reader_fault,
                `DUAL_STORE.u_owner.job_state,`DUAL_STORE.u_owner.slots[3],`DUAL_STORE.u_owner.slots[2],
                `DUAL_STORE.u_owner.slots[1],`DUAL_STORE.u_owner.slots[0],`DUAL_NORMAL.state,
                `DUAL_NORMAL.context_accepted,`DUAL_NORMAL.read_admitted,`DUAL_NORMAL.native_seen,
                `DUAL_NORMAL.processing_seen,`DUAL_NORMAL.failed,`DUAL_NORMAL.o_fault,`DUAL_NORMAL.o_error_code);
            $display("DUAL_DIAG_SOURCE time=%0t eye0_v/r/ok/idle/fault=%b%b%b%b%b seq=%0d error=%h eye1_v/r/ok/idle/fault=%b%b%b%b%b seq=%0d error=%h",
                $time,dut.stereo_source0_valid,dut.stereo_source0_ready,dut.stereo_source0_ok,dut.stereo_source0_idle,
                dut.stereo_source0_fault,dut.stereo_source0_sequence,dut.stereo_source0_error,
                dut.stereo_source1_valid,dut.stereo_source1_ready,dut.stereo_source1_ok,dut.stereo_source1_idle,
                dut.stereo_source1_fault,dut.stereo_source1_sequence,dut.stereo_source1_error);
            $display("DUAL_DIAG_PREPROCESS time=%0t pipeline_ready/owned=%b%b input_v/r=%b%b output_v/r=%b%b cfg_he_eligible=%b fault=%b",
                $time,`DUAL_F21.pipeline_ready,`DUAL_F21.pipeline_owned,
                `DUAL_F21.s_valid,`DUAL_F21.s_ready,`DUAL_F21.m_valid,`DUAL_F21.m_ready,
                `DUAL_F21.cfg_he_history_eligible,`DUAL_F21.o_fault);
        end
    endtask
    function automatic integer find_identity(input [127:0] identity);
        begin
            find_identity=-1;
            for(integer n=0;n<source_count;n++)
                if(written[n]&&identity==={16'h4a50,sessions[n],generations[n],16'(slots[n]),sequences[n]})
                    find_identity=n;
        end
    endfunction
    function automatic integer find_job(input [63:0] job_id);
        begin
            find_job=-1;
            for(integer n=0;n<source_count;n++)if(jobs[n]===job_id)find_job=n;
        end
    endfunction
    function automatic integer find_source(input [31:0] session_id,epoch,sequence_id,input bit camera);
        begin
            find_source=-1;
            for(integer n=0;n<source_count;n++)
                if(sessions[n]===session_id&&epochs[n]===epoch&&sequences[n]===sequence_id&&cameras[n]==camera)
                    find_source=n;
        end
    endfunction
    task automatic write_bar(input [11:0] offset,input [31:0] value);
        `DUAL_HOST.write_reg(20'h80000+offset,value);
    endtask
    task automatic read_bar(input [11:0] offset,output [31:0] value);
        `DUAL_HOST.read_reg(20'h80000+offset,value);
    endtask
    // Change Q through the original complete CFG transaction while still
    // MONO/cold. Cold mode control carries topology/cadence, never another Q.
    task automatic set_jpeg_quality;
        reg [31:0] active[0:4],extension[0:31];
        reg [31:0] prior_epoch,request_sequence,current,reply,active_session;
        integer count;
        reg extension_nonzero;
        begin
            phase=2;
            read_bar(`PCIE_REG_CFG_MODE_EPOCH,prior_epoch);
            read_bar(`PCIE_REG_CFG_ACTIVE_MODE,active[0]);
            read_bar(`PCIE_REG_CFG_ACTIVE_FLAGS,active[1]);
            read_bar(`PCIE_REG_CFG_ACTIVE_MIN_QUALITY,active[2]);
            read_bar(`PCIE_REG_CFG_ACTIVE_FRAME_BUDGET,active[3]);
            read_bar(`PCIE_REG_CFG_ACTIVE_RESTART_MCUS,active[4]);
            extension_nonzero=0;
            for(integer word=0;word<32;word++)begin
                read_bar(`PCIE_REG_CFG_EXT_ACTIVE_BASE+4*word,extension[word]);
                extension_nonzero=extension_nonzero||extension[word]!=0;
            end
            read_bar(`PCIE_REG_CFG_RESPONSE_SEQUENCE,request_sequence);
            request_sequence=request_sequence+1;if(request_sequence==0)request_sequence=1;
            write_bar(`PCIE_REG_CFG_REQUEST_SEQUENCE,request_sequence);
            write_bar(`PCIE_REG_CFG_REQUEST_SESSION,session);
            write_bar(`PCIE_REG_CFG_REQUEST_MODE,active[0]);
            write_bar(`PCIE_REG_CFG_REQUEST_FLAGS,active[1]);
            write_bar(`PCIE_REG_CFG_REQUEST_MIN_QUALITY,active[2]);
            write_bar(`PCIE_REG_CFG_REQUEST_FRAME_BUDGET,active[3]);
            write_bar(`PCIE_REG_CFG_REQUEST_RESTART_MCUS,active[4]);
            write_bar(`PCIE_REG_CFG_REQUEST_QUALITY,JPEG_QUALITY);
            read_bar(`PCIE_REG_CFG_HOST_CAPABILITIES,current);
            write_bar(`PCIE_REG_CFG_HOST_CAPABILITIES,current|1);
            for(integer word=0;word<32;word++)write_bar(`PCIE_REG_CFG_EXT_SHADOW_BASE+4*word,extension[word]);
            write_bar(`PCIE_REG_CFG_COMMAND,extension_nonzero?`PCIE_CFG_COMMAND_PREPARE_EXT:`PCIE_CFG_COMMAND_PREPARE);
            count=0;do begin read_bar(`PCIE_REG_CFG_STATUS,current);count++;end while(!current[`PCIE_CFG_STATUS_READY]&&count<4000);
            check(count<4000&&!current[`PCIE_CFG_STATUS_ERROR],"real complete CFG Q PREPARE_EXT");
            read_bar(`PCIE_REG_CFG_ERROR,reply);check(reply==0,"Q prepare error-free");
            read_bar(`PCIE_REG_CFG_RESPONSE_SEQUENCE,reply);check(reply==request_sequence,"Q prepare response identity");
            write_bar(`PCIE_REG_CFG_COMMAND,`PCIE_CFG_COMMAND_COMMIT);
            phase=3;
            // The sensor is free-running while APP/DMA is closed. Deliver a
            // real MONO frame so APPLIED can bind the actual primary RAW SOF;
            // no synthetic cfg_applied/frame_accept or JPEG is injected.
            fork
                begin
                    q_frame_phase=1;
                    wait(dut.u_camera.o_config_done&&dut.u_camera.u_receiver.publish_enable&&dut.u_camera.u_receiver.decoder_reset_n);
                    q_frame_phase=2;
                    source0.frame(16'h080,-1);
                    q_frame_phase=3;
                end
                begin
                    q_reply_phase=1;
                    count=0;do begin read_bar(`PCIE_REG_CFG_STATUS,current);count++;end while((!current[`PCIE_CFG_STATUS_APPLIED]||current[`PCIE_CFG_STATUS_BUSY])&&count<40000);
                    check(count<40000&&!current[`PCIE_CFG_STATUS_ERROR],"real Q COMMIT/APPLIED before cold product lock");
                    q_reply_phase=2;
                end
            join
            check(source_count==0&&writer_count==0,"preparatory MONO frame cannot produce a closed-APP product");
            phase=4;
            read_bar(`PCIE_REG_CFG_ERROR,reply);check(reply==0,"Q commit error-free");
            read_bar(`PCIE_REG_CFG_RESPONSE_SEQUENCE,reply);check(reply==request_sequence,"Q commit response identity");
            read_bar(`PCIE_REG_CFG_MODE_EPOCH,reply);check(reply==prior_epoch+1,"Q changes the actual mode epoch once");
            read_bar(`PCIE_REG_CFG_ACTIVE_SESSION,active_session);check(active_session==session,"Q preserves active session");
            read_bar(`PCIE_REG_CFG_ACTIVE_QUALITY,reply);check(reply==JPEG_QUALITY,"Q active readback");
            read_bar(`PCIE_REG_CFG_APPLIED_FIRST_SEQUENCE,reply);
            check(cfg_observed_sofs!=0&&reply==cfg_observed_sequence,"Q APPLIED binds the actual observed cropped RAW SOF sequence");
            $fdisplay(event_fd,"{\"event\":\"cfg_applied\",\"quality\":%0d,\"first_sequence\":%0d,\"epoch\":%0d,\"time\":%0t}",JPEG_QUALITY,reply,prior_epoch+1,$time);$fflush(event_fd);
            read_bar(`PCIE_REG_CFG_ACTIVE_MODE,reply);check(reply==active[0],"Q preserves mode");
            read_bar(`PCIE_REG_CFG_ACTIVE_FLAGS,reply);check(reply==active[1],"Q preserves flags");
            read_bar(`PCIE_REG_CFG_ACTIVE_MIN_QUALITY,reply);check(reply==active[2],"Q preserves minimum");
            read_bar(`PCIE_REG_CFG_ACTIVE_FRAME_BUDGET,reply);check(reply==active[3],"Q preserves frame budget");
            read_bar(`PCIE_REG_CFG_ACTIVE_RESTART_MCUS,reply);check(reply==active[4],"Q preserves restart policy");
            for(integer word=0;word<32;word++)begin
                read_bar(`PCIE_REG_CFG_EXT_ACTIVE_BASE+4*word,reply);check(reply==extension[word],"Q preserves every extension word");
            end
            $display("DUAL_CFG_QUALITY PASS quality=%0d epoch=%0d request=%0d",JPEG_QUALITY,prior_epoch+1,request_sequence);
        end
    endtask
    always @(posedge dut.pixel_clk)if(dut.pixel_rst_n&&dut.cold_config_sof)begin
        check(phase==3&&!dut.app_enable&&!dut.session_armed&&source_count==0&&writer_count==0,
            "prestart CFG SOF is a real observation while every product remains closed");
        cfg_observed_sofs++;cfg_observed_sequence=dut.cropped_raw_sequence;
        $fdisplay(event_fd,"{\"event\":\"cfg_sof\",\"raw_sequence\":%0d,\"time\":%0t}",dut.cropped_raw_sequence,$time);$fflush(event_fd);
    end
    // Expected SOURCE is sampled before JPEG encoding, not from its output header.
    always @(posedge dut.pixel_clk)if(dut.pixel_rst_n&&dut.start_valid&&dut.start_ready)begin
        check(source_count<MAX_RECORDS&&dut.private_processing_selected&&dut.processing_frame[76:45]!=0&&
              dut.processing_job_id[63],"real stored stereo source owns admission without optical qualification");
        cameras[source_count]=dut.processing_frame[4];sessions[source_count]=dut.processing_frame[76:45];
        epochs[source_count]=dut.processing_frame[140:109];sequences[source_count]=dut.processing_frame[108:77];
        timestamps[source_count]=dut.processing_frame[204:141];
        jobs[source_count]=dut.processing_job_id;
        $fdisplay(event_fd,"{\"event\":\"source\",\"camera\":%0d,\"session\":%0d,\"epoch\":%0d,\"sequence\":%0d,\"timestamp_ns\":%0d,\"time\":%0t}",
            cameras[source_count],sessions[source_count],epochs[source_count],sequences[source_count],timestamps[source_count],$time);
        $fflush(event_fd);
        if(THROUGHPUT_FRAMES!=0)throughput_identity("processing_start",source_count);
        source_count++;
    end
    always @(posedge dut.dfi_clk)if(dut.dfi_rst_n)begin
        if(dut.raw_private_native_done||dut.raw_private_native_error||dut.stereo_processing_result_valid||
           dut.stereo_retire_valid&&dut.stereo_retire_ready||dut.stereo_retire_done)
            $display("DUAL_DFI_EVENT time=%0t native_d/e=%b%b native_job=%h result_v/e=%b%b result_job=%h retire_v/r/d/e=%b%b%b%b retire_job=%h read_quiet=%b normal_state=%0d store_owned/complete/processed=%b%b%b",
                $time,dut.raw_private_native_done,dut.raw_private_native_error,dut.raw_private_native_job,
                dut.stereo_processing_result_valid,dut.stereo_processing_result_error,dut.stereo_processing_result_job,
                dut.stereo_retire_valid,dut.stereo_retire_ready,dut.stereo_retire_done,dut.stereo_retire_error,dut.stereo_retire_id,
                dut.raw_read_quiescent,`DUAL_NORMAL.state,`DUAL_STORE.read_owned,`DUAL_STORE.read_complete,`DUAL_STORE.processing_seen);
        if(dut.private_writer_ack_valid&&dut.private_writer_ack_ready)begin
            backend_index=find_source(dut.writer_ack_session,dut.writer_ack_epoch,dut.writer_ack_sequence,dut.writer_ack_camera);
            check(backend_index>=0&&dut.private_writer_required,"stereo JPEG ACK is required by its real processing ticket");
            check(!private_ack_consumed[backend_index],"exactly one private processing ACK per stored source");
            private_ack_consumed[backend_index]=1;
        end
        if(dut.writer_ack_valid&&dut.writer_ack_ready)begin
            check(writer_count<source_count&&dut.writer_ack_ok&&!dut.writer_ack_error,"one successful writer per independent admission");
            check(dut.writer_ack_session==sessions[writer_count]&&dut.writer_ack_epoch==epochs[writer_count]&&
                  dut.writer_ack_sequence==sequences[writer_count],"writer exact SOURCE identity");
            check(dut.writer_ack_slot/3==cameras[writer_count]&&dut.writer_ack_generation!=0&&dut.writer_ack_tag!=0,
                  "writer has actual camera slot/generation/tag");
            // Other RAW captures can have live B debt during this JPEG ACK.
            check(jpeg_aw_count==jpeg_b_count,"successful JPEG writer has no JPEG AXI B debt");
            check(dut.private_writer_required&&private_ack_consumed[writer_count],"actual JPEG writer ACK reaches stereo processing completion");
            slots[writer_count]=dut.writer_ack_slot;generations[writer_count]=dut.writer_ack_generation;
            tags[writer_count]=dut.writer_ack_tag;written[writer_count]=1;
            $fdisplay(event_fd,"{\"event\":\"writer\",\"camera\":%0d,\"session\":%0d,\"epoch\":%0d,\"sequence\":%0d,\"slot\":%0d,\"generation\":%0d,\"tag\":%0d,\"ok\":1,\"error\":0,\"aw\":%0d,\"b\":%0d,\"jpeg_aw\":%0d,\"jpeg_b\":%0d,\"time\":%0t}",
                cameras[writer_count],sessions[writer_count],epochs[writer_count],sequences[writer_count],
                slots[writer_count],generations[writer_count],tags[writer_count],`DUAL_MEM.accepted_aw,`DUAL_MEM.accepted_b,jpeg_aw_count,jpeg_b_count,$time);
            $fflush(event_fd);
            if(THROUGHPUT_FRAMES!=0)throughput_identity("writer",writer_count);
            writer_count++;
        end
        if(dut.stereo_processing_result_valid)begin
            backend_index=find_job(dut.stereo_processing_result_job);
            check(backend_index>=0&&written[backend_index]&&private_ack_consumed[backend_index]&&
                  !processing_seen[backend_index]&&!dut.stereo_processing_result_error,
                  "successful processing result follows the exact source JPEG B/ACK");
            processing_seen[backend_index]=1;processing_count++;
        end
        if(dut.stereo_retire_valid&&dut.stereo_retire_ready)begin
            backend_index=find_job(dut.stereo_retire_id);
            check(backend_index>=0&&processing_seen[backend_index]&&!raw_retire_accepted[backend_index]&&dut.raw_read_quiescent,
                  "exact RAW job retirement follows processing completion and read quiescence");
            raw_retire_accepted[backend_index]=1;
        end
        if(dut.stereo_retire_done)begin
            backend_index=find_job(dut.stereo_retire_id);
            check(backend_index>=0&&raw_retire_accepted[backend_index]&&!raw_retired[backend_index]&&!dut.stereo_retire_error,
                  "exact RAW source owner confirms one successful retirement");
            raw_retired[backend_index]=1;raw_retire_count++;
            if(THROUGHPUT_FRAMES!=0)throughput_identity("raw_retire",backend_index);
        end
        if(dut.jpeg_offer&&dut.jpeg_source_record_ready)begin
            local_index=find_identity(dut.jpeg_record_identity);check(local_index>=0,"DFI record bound to actual successful writer");
            local_fd=$fopen($sformatf("camera%0d_sequence%0d.local.record.bin",cameras[local_index],sequences[local_index]),"wb");
        end
        if(dut.record_valid&&dut.record_ready&&!dut.local_dfi[1])begin
            check(local_fd!=0&&local_index>=0,"ordered local data has prior record binding");
            for(integer lane=0;lane<16;lane++)if(dut.record_keep[lane])$fwrite(local_fd,"%c",dut.record_data[lane*8+:8]);
            if(dut.record_last)begin $fclose(local_fd);local_fd=0;end
        end
    end
    always @(posedge dut.user_clk)if(dut.user_rst_n)begin
        if(dut.jpeg_user_record_valid&&dut.jpeg_user_record_ready)begin
            user_index=find_identity(dut.jpeg_user_record_identity);
            if(dut.jpeg_user_record_identity[127:112]==16'h4a50)begin
                check(user_index>=0,"USER JPEG retains exact writer identity");
                check(!retired[user_index],"no duplicate native JPEG owner");
            end
        end
        if(held)begin
            check(dut.actual_c2h_valid&&{dut.jpeg_user_axis_data,dut.jpeg_user_axis_keep,dut.actual_c2h_last}===held_axis,
                  "C2H VALID/data/keep/last stable under finite stall");held_checks++;
        end
        held=dut.actual_c2h_valid&&!dut.actual_c2h_ready;
        held_axis={dut.jpeg_user_axis_data,dut.jpeg_user_axis_keep,dut.actual_c2h_last};
        if(dut.actual_c2h_valid&&dut.actual_c2h_ready&&dut.actual_c2h_last)begin
            check(user_index>=0&&!last_seen[user_index],"one actual last beat per record");
            last_seen[user_index]=1;event_log("user_last",user_index);
        end
        if(`DUAL_EP.transport.ack&&`DUAL_EP.o_result_pending)begin
            check(user_index>=0&&safe_seen[user_index]&&last_seen[user_index]&&!ack_seen[user_index],"actual native ACK follows SAFE and final data");
            ack_seen[user_index]=1;event_log("ack",user_index);
        end
        if(dut.jpeg_user_retire_valid&&dut.jpeg_user_retire_ready)begin
            check(user_index>=0&&ack_seen[user_index]&&safe_seen[user_index]&&!retired[user_index],"native retirement requires actual host SAFE/ACK");
            check(dut.jpeg_user_retire_identity==={16'h4a50,sessions[user_index],generations[user_index],16'(slots[user_index]),sequences[user_index]}&&
                  dut.jpeg_user_retire_status==0,"retire exact writer identity with success");
            retired[user_index]=1;retire_count++;event_log("retire",user_index);
        end
    end
    task automatic receive_records;
        integer fd,index,before_retire;
        begin
            for(integer received=0;received<EXPECTED_RECORDS;
                received++
            )begin
                `DUAL_HOST.grant(received+1,HOST_BYTES);
                wait(`DUAL_EP.o_result_pending);`DUAL_HOST.wait_safe(0,-1);
                index=user_index;check(index>=0&&last_seen[index]&&!retired[index],"real host memory commit precedes release");
                safe_seen[index]=1;event_log("safe",index);
                fd=$fopen($sformatf("camera%0d_sequence%0d.actual.record.bin",cameras[index],sequences[index]),"wb");
                for(integer k=0;k<`DUAL_HOST.committed;k++)$fwrite(fd,"%c",`DUAL_HOST.host_memory[k]);
                $fclose(fd);before_retire=retire_count;
                repeat(13)begin @(negedge dut.user_clk);check(retire_count==before_retire&&!retired[index],"withheld host ACK cannot retire JPEG");ack_hold_checks++;end
                `DUAL_HOST.ack;wait(retired[index]);host_count++;
                wait(!dut.jpeg_cdc_user_busy);repeat(8)@(negedge dut.user_clk);
            end
        end
    endtask
    integer guard,old_crc;
    // Bench-only completion alias for the passive UART RX-noise task.
    wire done_o=done;
    localparam integer OBSERVER_EXPECT_DUAL=1;
    time observer_mode_ready_at=0;
    `include "readonly_uart_main_decode.vh"
    `include "dual_throughput_monitor.vh"
    initial begin
        for(integer n=0;n<MAX_RECORDS;n++)begin
            written[n]=0;last_seen[n]=0;safe_seen[n]=0;ack_seen[n]=0;retired[n]=0;
            private_ack_consumed[n]=0;processing_seen[n]=0;raw_retire_accepted[n]=0;raw_retired[n]=0;
        end
        event_fd=$fopen("dual_events.jsonl","w");
        check(THROUGHPUT_FRAMES==0,"rate testing is outside this bounded candidate fixture");
        $fdisplay(event_fd,"{\"event\":\"fixture\",\"width\":1920,\"height\":1080,\"record_version\":2,\"quality\":%0d,\"pattern\":\"%s\",\"blc\":50,\"unity_wb\":1}",JPEG_QUALITY,RAW_PATTERN);
        $fflush(event_fd);
        pcie_mperst=1;`DUAL_EP.link_up=1;`DUAL_EP.hold_axis=0;
        phase=1;
        wait(dut.debug_rst_n&&dut.debug_app_rst_n&&dut.session_rearm_ready&&dut.cfg_user_initialized);
        read_bar(`PCIE_REG_CFG_SESSION,session);
`ifndef DUAL_COLD_SHORT
        set_jpeg_quality();
`endif
        phase=5;
        wait(dut.record_source_active_valid&&dut.record_source_active_session==session&&dut.record_dfi_select_quiescent);
        write_bar(`PCIE_REG_RECORD_REQUEST_VERSION,2);write_bar(`PCIE_REG_RECORD_REQUEST_SEQUENCE,21);
        write_bar(`PCIE_REG_RECORD_REQUEST_SESSION,session);write_bar(`PCIE_REG_RECORD_COMMAND,`PCIE_RECORD_V2_COMMAND_SELECT);
        guard=0;do begin read_bar(`PCIE_REG_RECORD_STATUS,value);guard++;end while(!value[`PCIE_RECORD_V2_STATUS_DONE]&&guard<2000);
        check(guard<2000,"actual v2 SELECT completes");read_bar(`PCIE_REG_RECORD_ERROR,value);check(value==0,"v2 select error-free");
        read_bar(`PCIE_REG_RECORD_SELECTED_HEADER_LENGTH,value);check(value==192,"v2 complete header selected");
        write_bar(`PCIE_REG_STEREO_REQUEST_MODE,`STEREO_MODES_DUAL_SDR);
        write_bar(`PCIE_REG_STEREO_REQUEST_DIVISOR,CAPTURE_DIVISOR);
        write_bar(`PCIE_REG_STEREO_COMMAND,`STEREO_COMMANDS_APPLY);
        guard=0;do begin read_bar(`PCIE_REG_STEREO_STATUS,value);guard++;end while(!value[`STEREO_STATUS_BITS_DONE]&&guard<2000);
        check(guard<2000&&!value[`STEREO_STATUS_BITS_BUSY],"cold dual mode applied by both recipients");
        read_bar(`PCIE_REG_STEREO_ACTIVE_MODE,value);check(value==1,"dual active readback");
        read_bar(`PCIE_REG_STEREO_ACTIVE_DIVISOR,value);check(value==CAPTURE_DIVISOR,"explicit JPEG test cadence");
`ifdef DUAL_COLD_SHORT
        check(dut.cfg_user_stereo_compatible&&dut.cfg_user_transaction_idle,"actual applied basic CFG qualifies cold dual");
        // Select retained v4 through the actual record version owner while cold.
        write_bar(`PCIE_REG_RECORD_REQUEST_VERSION,4);write_bar(`PCIE_REG_RECORD_REQUEST_SEQUENCE,22);
        write_bar(`PCIE_REG_RECORD_REQUEST_SESSION,session);write_bar(`PCIE_REG_RECORD_COMMAND,`PCIE_RECORD_V2_COMMAND_SELECT);
        guard=0;do begin read_bar(`PCIE_REG_RECORD_STATUS,value);guard++;end while(!value[`PCIE_RECORD_V2_STATUS_DONE]&&guard<2000);
        check(guard<2000,"actual dual v4 SELECT completes");read_bar(`PCIE_REG_RECORD_ERROR,value);check(value==0,"v4 selection error-free");
        read_bar(`PCIE_REG_RECORD_SELECTED_HEADER_LENGTH,value);check(value==2112,"retained sparse v4 2112-byte header");
        for(integer cold_mode=0;cold_mode<2;cold_mode++)begin
            write_bar(`PCIE_REG_STEREO_REQUEST_MODE,cold_mode);
            write_bar(`PCIE_REG_STEREO_COMMAND,`STEREO_COMMANDS_APPLY);
            guard=0;do begin read_bar(`PCIE_REG_STEREO_STATUS,value);guard++;end while(!value[`STEREO_STATUS_BITS_DONE]&&guard<2000);
            check(guard<2000&&!value[`STEREO_STATUS_BITS_BUSY],"both clock-domain cold recipients complete");
            read_bar(`PCIE_REG_STEREO_ERROR,value);check(value==0,"cold mode no fault");
            read_bar(`PCIE_REG_STEREO_ACTIVE_MODE,value);check(value==cold_mode,"mono/dual cold active readback");
        end
        check(source_count==0&&writer_count==0&&host_count==0,"cold control creates no fake products");
        $fclose(event_fd);done=1;$display("RESULT: PASS DUAL_COLD_TOP checks=%0d v4=2112 modes=dual_mono_dual",checks);$finish;
`endif
        phase=6;
        `DUAL_HOST.write_reg(12'h008,8);write_bar(`PCIE_REG_CONTROL,1);
        wait(dut.session_armed&&dut.cfg_source_ready&&!dut.cfg_pause);
        phase=7;
        wait(dut.u_camera.o_config_done&&dut.u_camera1.o_config_done);
        wait(dut.u_camera.u_receiver.publish_enable&&dut.u_camera.u_receiver.decoder_reset_n);
        wait(dut.u_camera1.u_receiver.publish_enable&&dut.u_camera1.u_receiver.decoder_reset_n);
        observer_mode_ready_at=$time;
        $display("DUAL_MAIN sensors/config/record ready time=%0t",$time);
        // Camera1's corrupted pre-crop packet must not turn into an output image.
        if(THROUGHPUT_FRAMES==0)begin
            old_crc=dut.u_camera1.o_crc_errors;source1.event_word(0,16'h100);source1.line(0,1);source1.event_word(1,16'h100);
            repeat(1000)@(negedge dut.pixel_clk);
            check(dut.u_camera1.o_crc_errors>old_crc&&source_count==0&&writer_count==0,"bad camera1 frame cannot publish JPEG");
        end
        phase=8;
        th_origin=$realtime+1000.0;
        fork
            begin if(THROUGHPUT_FRAMES!=0)periodic_camera(0);else source0.frame(16'h101,-1);end
            begin if(THROUGHPUT_FRAMES!=0)periodic_camera(1);else begin repeat(37)@(negedge dut.u_camera1.u_receiver.o_hs_word_clk);source1.frame(16'h201,-1);end end
            receive_records();
        join
        wait(retire_count==EXPECTED_RECORDS&&raw_retire_count==EXPECTED_RECORDS&&dut.record_ring_quiescent&&dut.record_metadata_quiescent&&!dut.jpeg_cdc_source_busy);
        check(source_count==EXPECTED_RECORDS&&writer_count==EXPECTED_RECORDS&&host_count==EXPECTED_RECORDS,"every independent full product delivered");
        check(processing_count==EXPECTED_RECORDS&&raw_retire_count==EXPECTED_RECORDS,"all actual processing tickets and RAW source owners retire");
        check(cameras[0]!=cameras[1],"both camera identities reach the host");
        check(ack_hold_checks==EXPECTED_RECORDS*13,"every product tested with withheld native ACK");
        check(`DUAL_MEM.accepted_aw==`DUAL_MEM.accepted_b,"all RAW/JPEG write debt drained");
        write_bar(`PCIE_REG_CONTROL,0);wait(dut.raw_region_quiet);
        if(THROUGHPUT_FRAMES!=0)finish_throughput();
        readonly_uart_finish();
        $fclose(event_fd);done=1;
        $display("RESULT: PASS DUAL IMX415 MAIN checks=%0d sources=%0d writers=%0d host=%0d retire=%0d processing=%0d rawRetire=%0d stallChecks=%0d ackHold=%0d",
                 checks,source_count,writer_count,host_count,retire_count,processing_count,raw_retire_count,held_checks,ack_hold_checks);$finish;
    end
    initial begin #(THROUGHPUT_FRAMES!=0?400000000:120000000);if(!done)begin progress();$fatal(1,"DUAL MAIN watchdog sources=%0d writers=%0d hosts=%0d retire=%0d",source_count,writer_count,host_count,retire_count);end end
    initial begin while(!done)begin #2000000;progress();end end
endmodule
