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
module tb_stereo_hdr_top #(
    parameter ROM_ROOT="../../../src_fpga/simulation/assets/rom_init",
    parameter integer JPEG_QUALITY=75, JPEG_RESTART=0, THROUGHPUT_FRAMES=4, STARTUP_ONLY=0, EYE_PHASE_NS=329
);
    localparam integer WIDTH=1920,HEIGHT=1080;
    localparam integer CAPTURE_DIVISOR=2;
    localparam integer EXPECTED_RECORDS=THROUGHPUT_FRAMES!=0?THROUGHPUT_FRAMES*2:2;
    localparam integer MAX_RECORDS=128;
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
    assign cam_sda=(dut.u_camera.u_config.u_i2c.state==4||dut.u_camera.u_config.u_i2c.state==5)?1'b0:1'bz;
    assign cam1_sda=(dut.u_camera1.u_config.u_i2c.state==4||dut.u_camera1.u_config.u_i2c.state==5)?1'b0:1'bz;
    defparam dut.u_camera.u_config.SDR_RESET_HOLD_CYCLES=4;
    defparam dut.u_camera.u_config.SDR_RELEASE_WAIT_CYCLES=4;
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
    dual_hdr_word_source #(.CAMERA(0)) source0(
        .word_clk(dut.u_camera.u_receiver.o_hs_word_clk),.word(word0),.valid(valid0));
    dual_hdr_word_source #(.CAMERA(1)) source1(
        .word_clk(dut.u_camera1.u_receiver.o_hs_word_clk),.word(word1),.valid(valid1));
    initial begin
        force dut.u_camera.u_receiver.geared_word=word0;
        force dut.u_camera.u_receiver.geared_word_valid=valid0;
        force dut.u_camera1.u_receiver.geared_word=word1;
        force dut.u_camera1.u_receiver.geared_word_valid=valid1;
    end
    defparam dut.u_camera.HDR_WARMUP_PAIRS=1;
    defparam dut.u_camera.HDR_I2C_HALF_PERIOD=4;
    defparam dut.u_camera.HDR_RESET_HOLD_CYCLES=4;
    defparam dut.u_camera.HDR_RELEASE_WAIT_CYCLES=4;
    defparam dut.u_camera.HDR_REGULATOR_WAIT_CYCLES=4;
    defparam dut.u_camera1.HDR_WARMUP_PAIRS=1;
    defparam dut.u_camera1.HDR_I2C_HALF_PERIOD=4;
    defparam dut.u_camera1.HDR_RESET_HOLD_CYCLES=4;
    defparam dut.u_camera1.HDR_RELEASE_WAIT_CYCLES=4;
    defparam dut.u_camera1.HDR_REGULATOR_WAIT_CYCLES=4;

    integer checks=0,guard=0,phase=0;
    reg [31:0] session,value;
    reg [15:0] f;
    reg [1:0] records=0;
    task automatic check(input bit condition,input string reason);
        begin checks++;if(!condition)$fatal(1,"STEREO_HDR_TOP %s phase=%0d",reason,phase);end
    endtask
    task automatic write_bar(input [11:0] offset,input [31:0] value);
        `DUAL_HOST.write_reg(20'h80000+offset,value);
    endtask
    task automatic read_bar(input [11:0] offset,output [31:0] value);
        `DUAL_HOST.read_reg(20'h80000+offset,value);
    endtask

    task automatic configure_hdr;
        reg [1023:0] extension;
        begin
            extension=0;extension[7:0]=2;extension[9:8]=`PCIE_CFG_V2_MODES_MONO_HDR;
            extension[`PCIE_CFG_V2_OFFSET_HDR_RATIO+:3]=4;
            extension[`PCIE_CFG_V2_OFFSET_HDR_BLACK_LONG+:10]=50;
            extension[`PCIE_CFG_V2_OFFSET_HDR_BLACK_SHORT+:10]=50;
            extension[`PCIE_CFG_V2_OFFSET_HDR_MOTION_BASE+:14]=64;
            extension[`PCIE_CFG_V2_OFFSET_HDR_MOTION_SHIFT+:4]=3;
            extension[`PCIE_CFG_V2_OFFSET_HDR_QUALIFICATION+:4]=15;
            extension[`PCIE_CFG_V2_OFFSET_HDR_MAX_DELTA_NS+:64]=50000000;
            extension[`PCIE_CFG_V2_OFFSET_HDR_MAX_WAIT_NS+:32]=100000000;
            extension[`PCIE_CFG_V2_OFFSET_HDR_MAX_AGE_NS+:32]=1000000000;
            write_bar(`PCIE_REG_CFG_HOST_CAPABILITIES,1);
            write_bar(`PCIE_REG_CFG_REQUEST_SEQUENCE,1);write_bar(`PCIE_REG_CFG_REQUEST_SESSION,session);
            write_bar(`PCIE_REG_CFG_REQUEST_MODE,0);write_bar(`PCIE_REG_CFG_REQUEST_QUALITY,75);
            write_bar(`PCIE_REG_CFG_REQUEST_MIN_QUALITY,1);write_bar(`PCIE_REG_CFG_REQUEST_FLAGS,0);
            write_bar(`PCIE_REG_CFG_REQUEST_RESTART_MCUS,0);write_bar(`PCIE_REG_CFG_REQUEST_FRAME_BUDGET,0);
            for(integer w=0;w<32;w++)write_bar(`PCIE_REG_CFG_EXT_SHADOW_BASE+4*w,extension[32*w+:32]);
            write_bar(`PCIE_REG_CFG_COMMAND,`PCIE_CFG_COMMAND_PREPARE_EXT);
            guard=0;do begin read_bar(`PCIE_REG_CFG_STATUS,value);guard++;
                if(value[`PCIE_CFG_STATUS_ERROR])begin read_bar(`PCIE_REG_CFG_ERROR,value);$fatal(1,"PREPARE error=%h",value);end
            end while(!value[`PCIE_CFG_STATUS_READY]&&guard<4000);
            check(guard<4000,"schema2 HDR prepare");
            write_bar(`PCIE_REG_CFG_COMMAND,`PCIE_CFG_COMMAND_COMMIT);
            $display("HDR_TOP CFG_COMMIT session=%0d",session);
        end
    endtask
    function automatic [63:0] host_field(input integer offset,input integer size);
        reg [63:0] v;
        begin v=0;for(integer b=0;b<size;b++)v[b*8+:8]=`DUAL_HOST.host_memory[offset+b];return v;end
    endfunction
    task automatic receive_hdr(input integer n);
        integer camera,fd;reg [63:0] pairid,jobid,flags;
        begin
            `DUAL_HOST.grant(n+1,4194304);
            wait(`DUAL_EP.o_result_pending);`DUAL_HOST.wait_safe(0,-1);
            camera=host_field(`PCIE_RECORD_V2_OFFSET_SOURCE_CAMERA,1);
            check(camera<2&&!records[camera],"two different cameras");
            flags=host_field(`PCIE_RECORD_V2_OFFSET_VALIDITY_FLAGS,2);
            check(flags[`PCIE_RECORD_V2_FLAG_HDR_PRODUCT]&&flags[`PCIE_RECORD_V2_FLAG_QUALIFIED]&&
                  flags[`PCIE_RECORD_V2_FLAG_PAIR]&&flags[`PCIE_RECORD_V2_FLAG_JOB],"HDR product flags");
            pairid=host_field(`PCIE_RECORD_V2_OFFSET_PAIR_ID,8);
            jobid=host_field(`PCIE_RECORD_V2_OFFSET_JOB_ID,8);
            check(pairid!=0&&pairid==jobid&&pairid[31]==camera[0],"same-eye pair/job identity");
            check(host_field(`PCIE_RECORD_V2_OFFSET_EXPOSURE_ROLE,1)==`PCIE_RECORD_V2_ROLE_LONG&&
                host_field(`PCIE_RECORD_V2_OFFSET_SOURCE_FORMAT,1)==`PCIE_RECORD_V2_FORMAT_RAW10,"RAW10 LONG");
            check(host_field(2112,2)==16'hd8ff&&host_field(`DUAL_HOST.committed-2,2)==16'hd9ff,"SOI/EOI");
            fd=$fopen($sformatf("camera%0d.hdr.record.bin",camera),"wb");
            for(integer i=0;i<`DUAL_HOST.committed;i++)$fwrite(fd,"%c",`DUAL_HOST.host_memory[i]);
            $fclose(fd);records[camera]=1;
            $display("HDR_TOP RECORD eye=%0d job=%h bytes=%0d",camera,jobid,`DUAL_HOST.committed);
            `DUAL_HOST.ack;wait(!dut.jpeg_cdc_user_busy);repeat(8)@(negedge dut.user_clk);
        end
    endtask
    initial begin
        pcie_mperst=1;`DUAL_EP.link_up=1;`DUAL_EP.hold_axis=0;
        phase=1;
        wait(dut.debug_rst_n&&dut.debug_app_rst_n&&dut.session_rearm_ready&&dut.cfg_user_initialized);
        read_bar(`PCIE_REG_CFG_SESSION,session);

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
        // Select retained v4 through the actual record version owner while cold.
        write_bar(`PCIE_REG_RECORD_REQUEST_VERSION,4);write_bar(`PCIE_REG_RECORD_REQUEST_SEQUENCE,22);
        write_bar(`PCIE_REG_RECORD_REQUEST_SESSION,session);write_bar(`PCIE_REG_RECORD_COMMAND,`PCIE_RECORD_V2_COMMAND_SELECT);
        guard=0;do begin read_bar(`PCIE_REG_RECORD_STATUS,value);guard++;end while(!value[`PCIE_RECORD_V2_STATUS_DONE]&&guard<2000);
        check(guard<2000,"actual dual v4 SELECT completes");read_bar(`PCIE_REG_RECORD_ERROR,value);check(value==0,"v4 selection error-free");
        read_bar(`PCIE_REG_RECORD_SELECTED_HEADER_LENGTH,value);check(value==2112,"retained sparse v4 2112-byte header");

        phase=6;
        `DUAL_HOST.write_reg(12'h008,8);write_bar(`PCIE_REG_CONTROL,1);
        wait(dut.session_armed&&dut.cfg_source_ready&&!dut.cfg_pause);
        wait(dut.camera_config_done&&dut.camera1_config_done);$display("HDR_TOP both SDR sensors configured time=%0t",$time);
        configure_hdr();phase=7;
        wait(dut.stereo_hdr_pixel&&dut.stereo_hdr_dfi&&dut.camera_hdr_mode&&dut.cam1_hdr_mode&&
            dut.camera_mode_running&&dut.cam1_hdr_mode_running&&dut.u_camera.u_config.o_config_written&&
            dut.u_camera1.u_config.o_config_written);
        wait(dut.u_camera.u_receiver.publish_enable&&dut.u_camera1.u_receiver.publish_enable&&
            dut.u_camera.u_receiver.u_hdr_stream.decoder_release[1]&&dut.u_camera1.u_receiver.u_hdr_stream.decoder_release[1]&&
            dut.u_camera.u_receiver.u_hdr_stream.word_release[1]&&dut.u_camera1.u_receiver.u_hdr_stream.word_release[1]&&
            dut.u_camera.u_receiver.u_hdr_stream.pixel_release[1]&&dut.u_camera1.u_receiver.u_hdr_stream.pixel_release[1]);
        phase=8;
        fork source0.start_pair(10); begin #(EYE_PHASE_NS);source1.start_pair(10);end join
        wait(dut.u_camera.u_receiver.u_hdr_stream.o_sequence_count0==1&&dut.u_camera.u_receiver.u_hdr_stream.o_sequence_count1==1&&
            dut.u_camera1.u_receiver.u_hdr_stream.o_sequence_count0==1&&dut.u_camera1.u_receiver.u_hdr_stream.o_sequence_count1==1);
        read_bar(`PCIE_REG_CFG_RESPONSE_SEQUENCE,value);check(value==1,"command identity");
        read_bar(`PCIE_REG_STEREO_ACTIVE_MODE,value);check(value==1,"dual topology retained");
        read_bar(`PCIE_REG_RECORD_SELECTED_HEADER_LENGTH,value);check(value==2112,"v4 header retained");
        check(!dut.camera_config_error&&!dut.camera1_config_error,"both I2C configurations");
        if(STARTUP_ONLY==0)$display("HDR_TOP trusted four physical FS, starting real warmup");
        if(STARTUP_ONLY!=0)begin
            $display("RESULT: PASS STEREO_HDR_TOP_STARTUP checks=%0d four trusted physical FS, both I2C recipes, pre-warmup",checks);$finish;
        end
        fork source0.finish_pair(10);source1.finish_pair(10); join
        wait(dut.camera_hdr_stable&&dut.cam1_hdr_stable);phase=9;$display("HDR_TOP both warmup pairs qualified t=%0t",$time);
        fork
            begin source0.start_pair(11);source0.finish_pair(11);end
            begin #(EYE_PHASE_NS);source1.start_pair(11);source1.finish_pair(11);end
            begin receive_hdr(0);receive_hdr(1);end
        join
        read_bar(`PCIE_REG_CFG_STATUS,value);check(value[`PCIE_CFG_STATUS_APPLIED]&&!value[`PCIE_CFG_STATUS_ERROR],"HDR applied");
        read_bar(`PCIE_REG_CFG_EXT_ACTIVE_BASE,value);check(value==32'h202,"active HDR schema2 readback");
        check(records==3,"two full HDR JPEG records");
        $display("RESULT: PASS STEREO_HDR_TOP_RECORDS checks=%0d one 1080p HDR JPEG each eye",checks);$finish;
    end
    initial begin
        #(STARTUP_ONLY?18000000:160000000);
        $fatal(1,"HDR TOP watchdog phase=%0d cfg=%h mode=%b%b dfi=%b armed=%b sensor=%b%b pair=%h scheduler=%h writer_fault=%b",
            phase,value,dut.camera_hdr_mode,dut.cam1_hdr_mode,dut.stereo_hdr_dfi,dut.session_armed,dut.camera_config_done,
            dut.camera1_config_done,dut.pairbank_id,dut.g_private_processing.u_processing.u_job_service.dispatch_state,dut.raw_reference_fault);
    end
endmodule

module dual_hdr_word_source #(parameter integer CAMERA=0)(input wire word_clk,output reg [31:0] word=0,output reg valid=0);
    function automatic [5:0] ecc(input [23:0] d);
        begin
            ecc[0]=d[0]^d[1]^d[2]^d[4]^d[5]^d[7]^d[10]^d[11]^d[13]^d[16]^d[20]^d[21]^d[22]^d[23];
            ecc[1]=d[0]^d[1]^d[3]^d[4]^d[6]^d[8]^d[10]^d[12]^d[14]^d[17]^d[20]^d[21]^d[23];
            ecc[2]=d[0]^d[2]^d[3]^d[5]^d[6]^d[9]^d[11]^d[12]^d[15]^d[18]^d[20]^d[21]^d[22];
            ecc[3]=d[1]^d[2]^d[3]^d[7]^d[8]^d[9]^d[13]^d[14]^d[15]^d[19]^d[20]^d[21]^d[23];
            ecc[4]=d[4]^d[5]^d[6]^d[7]^d[8]^d[9]^d[16]^d[17]^d[18]^d[19]^d[20]^d[22]^d[23];
            ecc[5]=d[10]^d[11]^d[12]^d[13]^d[14]^d[15]^d[16]^d[17]^d[18]^d[19]^d[21]^d[22]^d[23];
        end
    endfunction
    function automatic [15:0] crc_byte(input [15:0] c,input [7:0] b);
        reg [15:0] v;
        begin v=c^b;for(integer k=0;k<8;k++)v=v[0]?((v>>1)^16'h8408):(v>>1);crc_byte=v;end
    endfunction

    reg [31:0] payload[0:1][0:729];
    initial begin:build_lines
        reg [7:0] bytes[0:2919];reg [11:0] sample;reg [15:0] crc;
        for(integer v=0;v<2;v++)begin
            sample=(v?264:1224)+32*CAMERA;
            for(integer i=0;i<2916;i+=3)begin bytes[i]=sample[11:4];bytes[i+1]=sample[11:4];bytes[i+2]={sample[3:0],sample[3:0]};end
            crc=16'hffff;for(integer i=0;i<2916;i++)crc=crc_byte(crc,bytes[i]);
            bytes[2916]=crc[7:0];bytes[2917]=crc[15:8];bytes[2918]=255;bytes[2919]=255;
            for(integer i=0;i<730;i++)payload[v][i]={bytes[4*i+3],bytes[4*i+2],bytes[4*i+1],bytes[4*i]};
        end
    end
    task automatic send(input [31:0] w);@(negedge word_clk);word=w;valid=1;endtask
    task automatic gap;@(negedge word_clk);valid=0;repeat(30)@(negedge word_clk);endtask
    task automatic header(input bit vc,input [5:0] dt,input [15:0] number);
        reg [23:0] h;begin h={number,1'b0,vc,dt};send({2'b00,ecc(h),h});end
    endtask
    task automatic start_pair(input [15:0] n);
        header(0,0,n+7);gap();header(1,0,n+101);gap();
    endtask
    task automatic finish_pair(input [15:0] n);
        for(integer row=0;row<1097;row++)for(integer v=0;v<2;v++)begin
            if(row%128==0&&v==0&&CAMERA==0)$display("HDR_TOP CSI pair=%0d row=%0d time=%0t",n,row,$time);
            header(v,6'h2c,2916);for(integer w=0;w<730;w++)send(payload[v][w]);gap();
        end
        header(0,1,n+7);gap();header(1,1,n+101);gap();
    endtask
endmodule
