`timescale 1ns/1ps
`include "pcie_protocol_v1.vh"
`define R8_MEM dut.u_ddr_store.u_ddr
`define R8_EP dut.u_pcie.endpoint
`define R8_HOST dut.u_pcie.endpoint.host
`define R8_DRAIN dut.g_configured_capture.u_frontend.receiver[1].u_drain
`define R8_BOOT dut.g_config.g_source_bootstrap.u_bootstrap
`define R8_SOURCE dut.g_physical_source
`define R8_CLEAN dut.g_physical_source.g_regular_cleanup.u_cleanup
`define R8_BOOT_RESET dut.g_config.g_source_bootstrap.bootstrap_pixel_rst_n
// One physical receiver-output fixture exercises the actual R8 main composition.
module real_hdr_main_case #(
    parameter integer USER_CASE=0, WIDTH=1920, HEIGHT=1080,
    parameter ROM_ROOT="./rom_init"
) (input wire start_i, output reg done_o=0, output reg [31:0] checks=0);
    localparam integer USER_TEST=0, GROUPS=WIDTH*HEIGHT/4;
    localparam integer SELECTED_VERSION=4, RECORD_HEADER_BYTES=2112;
    reg [31:0] expected_session=1,config_value;
    reg sys_clk=0,board_ref_clk_100m=0,pcie_mperst=0,uart_rx=1;
    always #20 sys_clk=~sys_clk;
    always #5 board_ref_clk_100m=~board_ref_clk_100m;
    wire uart_tx,cam_scl,cam_mclk,cam_xclr;
    initial begin
        if(dut.g_configured_capture.u_frontend.JOINT_CONFIG_OWNER_ENABLE!=1 ||
           dut.g_configured_capture.u_frontend.PRESET_MONO_ENABLE!=1 ||
           dut.g_configured_capture.u_frontend.SOURCE_SELECT!=0 ||
           dut.g_configured_capture.u_frontend.EXT_WIDTH!=1024 ||
           dut.g_configured_capture.u_frontend.WIDTH!=1920 ||
           dut.g_configured_capture.u_frontend.HEIGHT!=1080 ||
           dut.g_configured_capture.u_frontend.DEST0_SAME_CLOCK!=1 ||
           dut.g_configured_capture.u_frontend.DEST1_SAME_CLOCK!=1)
            $fatal(1,"FINAL JOINT activation preconditions");
        $display("FINAL_JOINT_ACTIVATION PASS source0 mono1 ext1024 raster1920x1080 sameclock1 joint1");
    end

    reg [31:0] fixture_word=0;reg fixture_valid=0;
    // Physical I2C slave ACK boundary; actual master transaction FSM is retained.
    assign cam_sda=(dut.u_camera.u_hdr_config.u_i2c.state==4 || dut.u_camera.u_hdr_config.u_i2c.state==5 ||
        dut.u_camera.u_config.u_i2c.state==4 || dut.u_camera.u_config.u_i2c.state==5)?1'b0:1'bz;
    defparam dut.u_camera.u_config.WAIT_CYCLES=4;
    defparam dut.u_camera.SDR_WAKE_CYCLES=4;
    defparam dut.u_camera.u_config.I2C_HALF_PERIOD=4;
    initial begin
        force dut.u_camera.u_receiver.geared_word=fixture_word;
        force dut.u_camera.u_receiver.geared_word_valid=fixture_valid;
    end

    wire [0:0] ddr_ck_p,ddr_ck_n,ddr_cke,ddr_odt,ddr_cs_n,txp,txn;
    wire ddr_reset_n,ddr_ras_n,ddr_cas_n,ddr_we_n;
    wire [2:0] ddr_ba;wire [13:0] ddr_addr;
    wire [1:0] ddr_dqs_p,ddr_dqs_n,ddr_dm;wire [15:0] ddr_dq;
    anlogic2026 #(.FRAME_WIDTH(WIDTH),.FRAME_HEIGHT(HEIGHT),.SOURCE_SELECT(0),
        .VIRTUAL0_PHASE(0),.VIRTUAL1_PHASE(17),
        .VIRTUAL0_PERIOD(700000),.VIRTUAL1_PERIOD(2083333)) dut (
        .sys_clk(sys_clk),.board_ref_clk_100m(board_ref_clk_100m),
        .mipi_clk_hs_rx_p(1'b0),.mipi_data_hs_p(4'd0),
        .cam_scl(cam_scl),.cam_sda(cam_sda),.cam_mclk(cam_mclk),.cam_xclr(cam_xclr),
        .uart_tx(uart_tx),.uart_rx(uart_rx),.ddr_ck_p(ddr_ck_p),.ddr_ck_n(ddr_ck_n),
        .ddr_reset_n(ddr_reset_n),.ddr_cke(ddr_cke),.ddr_odt(ddr_odt),.ddr_cs_n(ddr_cs_n),
        .ddr_ras_n(ddr_ras_n),.ddr_cas_n(ddr_cas_n),.ddr_we_n(ddr_we_n),.ddr_ba(ddr_ba),
        .ddr_addr(ddr_addr),.ddr_dqs_p(ddr_dqs_p),.ddr_dqs_n(ddr_dqs_n),.ddr_dq(ddr_dq),.ddr_dm(ddr_dm),
        .refclk_p(1'b0),.refclk_n(1'b1),.pcie_mperst(pcie_mperst),.rxp(1'b0),.rxn(1'b1),.txp(txp),.txn(txn));
    // The prior reference set these exact fixture values using cold UART.
    // Production has fixed build defaults, so the numerical fixture selects
    // the same neutral values at elaboration; hardware defaults stay measured.
    defparam dut.u_camera.HDR_WARMUP_PAIRS=1;
    defparam dut.u_camera.HDR_I2C_HALF_PERIOD=4;
    defparam dut.u_camera.HDR_RESET_HOLD_CYCLES=4;
    defparam dut.u_camera.HDR_RELEASE_WAIT_CYCLES=4;
    defparam dut.u_camera.HDR_REGULATOR_WAIT_CYCLES=4;
    defparam dut.COLOR_CONFIG_DEFAULT=10'h040;
    defparam dut.COLOR_WB_DEFAULT=30'h10040100;
    defparam dut.u_ddr_store.u_ddr.RAW_ARENA_ENABLE=1;
    defparam dut.u_ddr_store.u_ddr.JPEG_RING_ARENA_ENABLE=1;
    defparam dut.u_jpeg.ROM_INIT_ROOT=ROM_ROOT;
    defparam dut.u_jpeg.ROM_INIT_SUFFIX=".mif.dath";
    `include "anlogic2026_s04_uart_tasks.vh"
`ifdef REFACTOR_READONLY_UART_MAIN
    defparam dut.READONLY_UART_REPORT_CYCLES=`REFACTOR_OBSERVER_REPORT_CYCLES;
    `include "extended_uart_decode.vh"
`endif
    // Real BAR0+0x80000 CQ/CC requests pass the transport's AXI-Lite bridge.
    integer algo_bar_writes=0;
    task automatic write_bar(input [11:0] offset,input [31:0] value);
        begin
            if(offset>=12'hf00&&offset<=12'hf3c)algo_bar_writes++;
            `R8_HOST.write_reg(20'h80000+offset,value);
        end
    endtask
    task automatic read_bar(input [11:0] offset,output [31:0] value);
        begin `R8_HOST.read_reg(20'h80000+offset,value);end
    endtask
    // Score the actual ordered ingress tuple, not a fabricated completion.
    reg [127:0] admitted_identity[0:15];
    reg [127:0] writer_identity;
    reg writer_owned=0;
    integer admitted_owners=0,ring_owners=0,writer_terminals=0;
    always @(posedge dut.pixel_clk) if(dut.pixel_rst_n&&dut.start_valid&&dut.start_ready)begin
        admitted_identity[admitted_owners]={dut.admitted_session,dut.admitted_epoch,dut.capture_id,dut.record_admitted_writer_tag};
        admitted_owners=admitted_owners+1;
    end
    always @(posedge dut.dfi_clk) if(dut.dfi_rst_n)begin
        if(dut.ring_start_valid&&dut.ring_start_ready&&!dut.bridge_fault&&dut.nr_writer_start_permitted)begin
            check(!writer_owned&&ring_owners<admitted_owners,"ring START requires an unmatched actual PIX admission");
            writer_identity={dut.ddr_session,dut.ddr_epoch,dut.ddr_capture_id,dut.ddr_write_tag};
            check(writer_identity===admitted_identity[ring_owners],"ring START identity matches the counted ordered admission");
            writer_owned=1;ring_owners=ring_owners+1;
        end
        if(dut.writer_ack_valid&&dut.writer_ack_ready)begin
            check(writer_owned,"every writer ACK consumes exactly one real ring owner");
            check({dut.writer_ack_session,dut.writer_ack_epoch,dut.writer_ack_sequence,dut.writer_ack_tag}===writer_identity,"writer terminal identity matches the admitted frame");
            check(dut.writer_ack_generation!=0&&dut.writer_ack_slot<6,"writer terminal has a real allocated slot generation");
            if(!dut.writer_ack_ok)begin
                check(dut.u_ddr_store.g_ring_store.u_store.slot_state[dut.writer_ack_slot]==3,"failure ACK owns an ABORTED slot");
                check(`R8_MEM.accepted_aw==`R8_MEM.accepted_b,"failure ACK has no outstanding B");
                if(dut.local_retire_pending&&dut.ring_retire_ready)
                    check(dut.writer_ack_slot!=dut.local_read_slot,"simultaneous success and failure belong to distinct slots");
            end
            writer_owned=0;writer_terminals=writer_terminals+1;
        end
    end
    integer starts=0,good_sources=0,bad_sources=0,good_writers=0,bad_writers=0;
    integer scenario_index=0,isp_fd=0,processed_fd=0,f22_fd=0,f23_fd=0,host_fd=0;
    integer isp_groups=0,processed_groups=0,f22_records=0,f23_records=0;
    reg trace_sdr=0;reg [5:0] scenario_enables;
    // RAW RGGB radiance pattern: neutral road and one white/yellow marking.
    function automatic [9:0] raw_sample(input integer x,y);
        integer linear_value;
        begin
            linear_value=60+((x/80+y/90)%9)*12;
            if(x>=694&&x<=706)linear_value=800;
            else if(x>=1194&&x<=1206)
                linear_value=(!(x%2)&&!(y%2))?700:((x%2)&&(y%2))?60:600;
            raw_sample=linear_value+50;
        end
    endfunction
    always @(posedge dut.pixel_clk)if(trace_sdr&&dut.pixel_rst_n)begin
        if(dut.camera_rgb_valid&&dut.camera_rgb_ready)begin
            $fdisplay(isp_fd,"%024h",dut.camera_rgb);isp_groups++;
        end
        if(dut.processed_valid&&dut.processed_ready)begin
            check(dut.processed_sof==(processed_groups==0),"schema2 processed SOF exactly once");
            check(dut.processed_eol==(processed_groups%(WIDTH/4)==WIDTH/4-1),"schema2 processed EOL exact geometry");
            check(dut.g_preprocess.g_live_f21.u_live.u_pipeline.g_full_preprocess.u_hist.o_frame_history_used==(scenario_index==1),
                "first frame identity HE,second uses actual qualified temporal history");
            $fdisplay(processed_fd,"%08h%024h",dut.processed_luma,dut.processed_rgb);processed_groups++;
        end
        if(dut.advanced_f22_valid&&dut.advanced_f22_ready)begin
            $fdisplay(f22_fd,"%0171h",dut.advanced_f22_record);f22_records++;
        end
        if(dut.advanced_f23_valid&&dut.advanced_f23_ready)begin
            $fdisplay(f23_fd,"%045h",dut.advanced_f23_record);f23_records++;
        end
    end
    integer local_records=0,local_retires=0,user_records=0,ext_fires=0,dfi_ext_fires=0,metadata_ext_fires=0;
    integer phase=0,guard_checks=0,record_fd=0,ext_fd=0,event_fd=0;
    reg local_hold=0,user_hold=0,extension_hold=0,tail_hold=0;
    integer header_ram_writes=0,header_ram_reads=0,header_input_flits=0,header_output_flits=0;
    reg [7:0] dfi_record_bytes[0:1048575];
    integer dfi_record_count=0,user_record_count=0;
    always @(posedge dut.dfi_clk)if(dut.product_dfi_reset_n&&dut.record_valid&&dut.record_ready&&!dut.local_dfi[1])begin
        for(integer lane=0;lane<16;lane++)if(dut.record_keep[lane])begin
            dfi_record_bytes[dfi_record_count]=dut.record_data[lane*8+:8];dfi_record_count++;
        end
    end
    always @(posedge dut.user_clk)if(dut.user_rst_n&&dut.jpeg_user_axis_valid&&dut.jpeg_user_axis_ready)begin
        for(integer lane=0;lane<16;lane++)if(dut.jpeg_user_axis_keep[lane])begin
            check(user_record_count<dfi_record_count,"USER cannot emit a byte absent from the actual DFI record");
            check(dut.jpeg_user_axis_data[lane*8+:8]===dfi_record_bytes[user_record_count],"opaque CDC record is byte-exact DFI to USER");
            user_record_count++;
        end
    end
    reg [127:0] held_c2h_data;
    reg [15:0] held_c2h_keep;
    reg held_c2h_last,was_c2h_held=0;
    reg [2047:0] held_extension;
    reg [16383:0] staged_extension;
    wire [16399:0] padded_staged_extension={16'd0,staged_extension};
    integer staging_input_flits=0,staging_ram_writes=0,staging_copy_words=0;
    reg staging_read_pending=0;
    reg staging_token_frame=0;
    reg [8:0] staging_read_index;
    always @(posedge dut.dfi_clk)begin
        if(!dut.dfi_rst_n)begin
            staging_read_pending<=0;staging_token_frame<=0;staging_input_flits=0;staged_extension=0;
        end else begin
            if(dut.ddr_start_valid&&dut.ddr_start_ready)begin staging_input_flits=0;staged_extension=0;end
            if(dut.u_jpeg_to_ddr.read_valid&&dut.u_jpeg_to_ddr.read_ready)begin
                case(dut.u_jpeg_to_ddr.read_token[146:145])
                    2'b10:staging_token_frame<=1;
                    2'b01:staging_token_frame<=0;
                    2'b11:if(staging_token_frame)begin
                        check(staging_input_flits<128,"DFI staging consumes exactly the ordered 128 EXT tokens");
                        staged_extension[staging_input_flits*128+:128]=dut.u_jpeg_to_ddr.read_token[127:0];
                        staging_input_flits=staging_input_flits+1;
                    end
                endcase
            end
            if(dut.u_jpeg_to_ddr.u_egress.g_staging.u_staging.ram_write)staging_ram_writes=staging_ram_writes+1;
            if(staging_read_pending)begin
                check(dut.record_extension_read_data===padded_staged_extension[staging_read_index*40+:40],
                    "actual synchronous staging RAM data equals accepted token bytes");
                staging_copy_words=staging_copy_words+1;
            end
            staging_read_pending<=dut.record_extension_read_enable;
            if(dut.record_extension_read_enable)staging_read_index<=dut.record_extension_read_index;
            if(dut.ddr_result_valid)check(dut.u_jpeg_to_ddr.u_egress.staging_complete&&
                dut.record_extension_shape_valid&&staging_input_flits==128,
                "actual FENCE waits for all staging RAM writes and real shape proof");
            if(extension_hold)check(!dut.u_jpeg_to_ddr.u_egress.g_staging.u_staging.ram_write&&
                dut.u_jpeg_to_ddr.u_egress.staging_complete,"held EXT retains complete RAM lease without overwrite");
        end
    end
    reg [31:0] selected_sequence=0,old_session=0;
    task check(input bit good,input string reason);
        begin checks=checks+1;if(!good)$fatal(1,"FULL_BOUNDARY case=%0d phase=%0d %s time=%0t",USER_CASE,phase,reason,$time);end
    endtask
    always @(posedge dut.pixel_clk) if(dut.pixel_rst_n) begin
        if(dut.start_valid&&dut.start_ready) begin starts=starts+1;
            $fdisplay(event_fd,"START case=%0d phase=%0d session=%0d sequence=%0d",USER_CASE,phase,dut.job_session,dut.job_sequence);end
        if(dut.physical_source_done) good_sources=good_sources+1;
        if(dut.physical_source_failed) begin bad_sources=bad_sources+1;
            $fdisplay(event_fd,"NEGATIVE case=%0d phase=%0d start_count=%0d source_tag=%0d",USER_CASE,phase,starts,dut.g_physical_source.source_tag);end
        if(dut.record_source_extension_valid&&dut.record_source_extension_ready) ext_fires=ext_fires+1;
    end
    always @(posedge dut.dfi_clk) if(dut.dfi_rst_n) begin
        if(dut.record_dfi_extension_valid&&dut.record_dfi_extension_ready)dfi_ext_fires=dfi_ext_fires+1;
        if(dut.g_record_metadata.u_gate.u_store.extension_fire)metadata_ext_fires=metadata_ext_fires+1;
        if(extension_hold)begin
            check(dut.record_dfi_extension_valid&&!dut.record_dfi_extension_ready,"real assembled EXT remains presented under consumer ready stall");
            check(dut.record_dfi_extension==0&&staged_extension===held_extension,"RAM EXT bytes stay owned; inactive parallel vector is zero");
            check(!dut.record_dfi_data_quiescent,"held EXT cannot report data quiet");
            check(!dut.g_record_metadata.u_gate.u_store.extension_fire&&!dut.g_record_metadata.u_gate.u_store.extension_owned,"actual metadata extension_fire/owner remain unconsumed under hold");
        end
        if(dut.writer_ack_valid&&dut.writer_ack_ready) begin
            if(dut.writer_ack_ok)good_writers=good_writers+1;else bad_writers=bad_writers+1;
            $fdisplay(event_fd,"WRITER case=%0d phase=%0d ok=%b error=%0d slot=%0d gen=%0d session=%0d seq=%0d B=%0d/%0d",USER_CASE,phase,
                dut.writer_ack_ok,dut.writer_ack_error,dut.writer_ack_slot,dut.writer_ack_generation,dut.writer_ack_session,dut.writer_ack_sequence,`R8_MEM.accepted_b,`R8_MEM.accepted_aw);
        end
        if(dut.local_dfi[1]&&dut.record_valid&&dut.record_ready&&dut.record_last)local_records=local_records+1;
        if(dut.local_dfi[1]&&dut.local_retire_pending&&dut.ring_retire_ready)local_retires=local_retires+1;
        if(local_hold)begin check(dut.debug_run&&dut.debug_app_rst_n&&!dut.local_stop_done,"LOCAL pending owner keeps RUN/reset alive");guard_checks=guard_checks+1;end
    end
    always @(posedge dut.user_clk) if(dut.user_rst_n) begin
        if(was_c2h_held)begin
            check(dut.actual_c2h_valid,"held C2H VALID retained");
            check({dut.jpeg_user_axis_data,dut.jpeg_user_axis_keep,dut.actual_c2h_last}==={held_c2h_data,held_c2h_keep,held_c2h_last},"held C2H tuple retained");
        end
        was_c2h_held=dut.actual_c2h_valid&&!dut.actual_c2h_ready;
        held_c2h_data=dut.jpeg_user_axis_data;held_c2h_keep=dut.jpeg_user_axis_keep;held_c2h_last=dut.actual_c2h_last;
        if(dut.actual_c2h_valid&&dut.actual_c2h_ready)begin
            for(integer lane=0;lane<16;lane=lane+1)if(dut.jpeg_user_axis_keep[lane])$fwrite(record_fd,"%c",dut.jpeg_user_axis_data[lane*8+:8]);
            if(dut.actual_c2h_last)user_records=user_records+1;
        end
        if(user_hold)check(!dut.record_dfi_data_quiescent||!dut.record_ring_quiescent||dut.tx_busy,"USER held record has a real outstanding owner");
    end
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
    task csi_word(input [31:0] value);
        begin @(negedge dut.u_camera.u_receiver.o_hs_word_clk);fixture_word=value;fixture_valid=1;
            @(negedge dut.u_camera.u_receiver.o_hs_word_clk);fixture_valid=0;end
    endtask
    task sensor_event(input [1:0] kind,input bit ok,input [3:0] code);
        reg [23:0] h;begin
            h={16'h37a1,6'd0,kind};csi_word({2'd0,ecc(h),h});
            repeat(4)@(negedge dut.u_camera.u_receiver.o_hs_word_clk);
        end
    endtask
    task csi_line(input integer row,input bit bad_crc);
        reg [7:0] bytes[0:WIDTH/4*5+11];reg [15:0] crc;
        reg [23:0] h;reg [31:0] packed_word;reg [9:0] samples[0:3];
        integer groups,byte_count;
        begin
            groups=WIDTH/4+2;byte_count=groups*5;
            for(integer group_index=0;group_index<groups;group_index++)begin
                for(integer lane=0;lane<4;lane++)begin
                    samples[lane]=(row>=16&&group_index>=1&&group_index<=WIDTH/4)?
                        raw_sample((group_index-1)*4+lane,row-16):10'd123;
                    bytes[group_index*5+lane]=samples[lane][9:2];
                end
                bytes[group_index*5+4]={samples[3][1:0],samples[2][1:0],samples[1][1:0],samples[0][1:0]};
            end
            crc=16'hffff;for(integer n=0;n<byte_count;n++)crc=crc_byte(crc,bytes[n]);
            bytes[byte_count]=crc[7:0]^{7'd0,bad_crc};bytes[byte_count+1]=crc[15:8];
            h={16'(byte_count),8'h2b};csi_word({2'd0,ecc(h),h});repeat(2)@(negedge dut.u_camera.u_receiver.o_hs_word_clk);
            for(integer n=0;n<byte_count+2;n+=4)begin
                packed_word={bytes[n+3],bytes[n+2],bytes[n+1],bytes[n]};csi_word(packed_word);
            end
            repeat(4)@(negedge dut.u_camera.u_receiver.o_hs_word_clk);
        end
    endtask
    task source_frame(input integer groups,input bit complete_frame);
        begin
            check(groups==GROUPS&&complete_frame,"word fixture requires one complete native frame");
            wait(dut.cfg_source_ready&&!dut.cfg_pause&&dut.cfg_pipeline_idle&&dut.session_armed&&dut.replay_admission_ready);
            wait(dut.camera_mode_running&&!dut.camera_hdr_mode&&dut.u_camera.o_config_done);
            wait(dut.u_camera.u_receiver.publish_enable&&dut.u_camera.u_receiver.decoder_reset_n);
            repeat(20)@(negedge dut.u_camera.u_receiver.o_hs_word_clk);
            check(dut.u_camera.FIRST_ROW==16&&dut.u_camera.FIRST_GROUP==1,"production SDR crop row16 group1");
            sensor_event(0,1,0);
            for(integer row=0;row<HEIGHT+16;row++)csi_line(row,0);
            sensor_event(1,1,0);
        end
    endtask
    task lost_pre_crop_frame;
        integer old_starts;
        begin
            old_starts=starts;sensor_event(0,1,0);csi_line(0,1);sensor_event(1,1,0);
            repeat(500)@(negedge dut.pixel_clk);wait_quiet();
            check(starts==old_starts&&!dut.physical_identity_quarantine,
                "CRC-bad pre-crop frame consumes real FS2 without native/JPEG admission or continuity reset");
        end
    endtask
    task wait_quiet;
        begin wait(dut.physical_source_idle&&dut.cfg_pipeline_idle&&dut.record_ring_quiescent&&dut.record_metadata_quiescent&&
            dut.live_f21_maintenance_quiet&&!dut.writer_ack_valid);repeat(7)@(negedge dut.pixel_clk);end
    endtask
    task local_start(input [7:0] seq);
        begin uart_command(seq,8'h02,0,0,0);wait(dut.debug_run&&dut.session_armed&&dut.credit_grant_pixel&&dut.cfg_source_ready&&!dut.cfg_pause);end
    endtask
    task send_select(input [31:0] seq);
        begin selected_sequence=seq;
            wait(dut.record_source_active_valid&&dut.record_source_active_session==expected_session&&dut.record_dfi_select_quiescent);
            check(!dut.app_enable&&!dut.c2h_running&&!dut.session_armed&&dut.session_rearm_ready,"actual cold USER SELECT boundary");
            write_bar(`PCIE_REG_RECORD_REQUEST_VERSION,SELECTED_VERSION);write_bar(`PCIE_REG_RECORD_REQUEST_SEQUENCE,seq);
            write_bar(`PCIE_REG_RECORD_REQUEST_SESSION,expected_session);write_bar(`PCIE_REG_RECORD_COMMAND,`PCIE_RECORD_V2_COMMAND_SELECT);
        end
    endtask
    task select_reply(input [31:0] seq);
        integer attempt;
        begin attempt=0;do begin read_bar(`PCIE_REG_RECORD_STATUS,config_value);attempt=attempt+1;end
            while(!config_value[`PCIE_RECORD_V2_STATUS_DONE]&&attempt<1000);
            check(attempt<1000&&config_value==(32'd1<<`PCIE_RECORD_V2_STATUS_DONE),"fresh SELECT DONE");
            read_bar(`PCIE_REG_RECORD_ERROR,config_value);check(config_value==0,"fresh SELECT ACK ok");
            read_bar(`PCIE_REG_RECORD_RESPONSE_SEQUENCE,config_value);check(config_value==seq,"fresh SELECT sequence");
            read_bar(`PCIE_REG_RECORD_RESPONSE_SESSION,config_value);check(config_value==expected_session,"fresh SELECT session");
            read_bar(`PCIE_REG_RECORD_SELECTED_VERSION,config_value);check(config_value==4,"USER selected version4");
            read_bar(`PCIE_REG_RECORD_SELECTED_HEADER_LENGTH,config_value);check(config_value==2112&&dut.record_selected_version_dfi==4,"actual USER/DFI version4/header2112 agree");
            $fdisplay(event_fd,"SELECT session=%0d request=%0d user_version=%0d dfi_version=%0d",expected_session,seq,dut.record_selected_version_user,dut.record_selected_version_dfi);
        end
    endtask
    task configure_full;
        reg [1023:0] extension;integer guard;
        begin extension=0;extension[7:0]=2;extension[15:10]=48;
            write_bar(`PCIE_REG_CFG_HOST_CAPABILITIES,1);write_bar(`PCIE_REG_CFG_REQUEST_SEQUENCE,1);
            write_bar(`PCIE_REG_CFG_REQUEST_SESSION,expected_session);write_bar(`PCIE_REG_CFG_REQUEST_MODE,0);write_bar(`PCIE_REG_CFG_REQUEST_QUALITY,75);
            for(integer n=0;n<32;n=n+1)write_bar(`PCIE_REG_CFG_EXT_SHADOW_BASE+4*n,extension[n*32+:32]);
            write_bar(`PCIE_REG_CFG_COMMAND,`PCIE_CFG_COMMAND_PREPARE_EXT);guard=0;
            do begin read_bar(`PCIE_REG_CFG_STATUS,config_value);guard=guard+1;end while((config_value&3)!=3&&guard<1000);
            check(guard<1000,"real FULL CONFIG READY");write_bar(`PCIE_REG_CFG_COMMAND,`PCIE_CFG_COMMAND_COMMIT);
            wait(dut.cfg_source_ready&&!dut.cfg_pause);check(dut.CONFIG_EXT_SUPPORTED==8'h3c&&dut.RECORD_EXTENSION_WIDTH==16384,"frozen FULL field width/capability");
        end
    endtask


    integer raw_long_fd,raw_short_fd,hdr_raw_fd,hdr_rgb_fd;
    integer long_groups=0,short_groups=0,hdr_groups=0,hdr_rgb_groups=0;
    integer raw_commits=0,raw_pins=0,raw_releases=0,fetches=0,retires=0;
    integer algo_sequence=0;
    reg capture_is_short=0,freeze_final_b=0;
    reg context_borrowed=0;
    integer context_begins=0;
    reg [159:0] stable_product_context;
    always @(posedge dut.pixel_clk)begin
        if(dut.hdr_frame_begin)begin
            stable_product_context=dut.neutral_record_context;context_borrowed=1;context_begins++;
            check(dut.processing_context_owned,"algorithm BEGIN requires published current owner");
        end
        if(context_borrowed&&!dut.lane_quiet)
            check(dut.neutral_record_context===stable_product_context,"borrowed algorithm context cannot change at later replay SOF");
        if(context_borrowed&&dut.lane_quiet&&!dut.hdr_frame_begin)context_borrowed=0;
        if(phase==8&&raw_pins>0&&(!dut.pixel_rst_n||dut.store_recovery||dut.record_source_fault||
            dut.processing_event_fault||dut.raw_processing_fault||dut.raw_reference_fault||
            dut.hdr_reader_fault||dut.hdr_source_fault||dut.admission_protocol_fault))begin
            $fflush();
            $fatal(1,"HDR_LAB FAULT reset=%b recovery=%b record=%b builder=%b ordered=%b metadata=%b processing=%b raw=%b ref=%b reader=%b src=%b admission=%b groups=%0d/%0d",dut.pixel_rst_n,dut.store_recovery,dut.record_source_fault,dut.record_builder_fault,dut.record_ordered_fault,dut.record_metadata_fault,dut.processing_event_fault,dut.raw_processing_fault,dut.raw_reference_fault,dut.hdr_reader_fault,dut.hdr_source_fault,dut.admission_protocol_fault,hdr_groups,hdr_rgb_groups);
        end
    end
    always @(posedge dut.pixel_clk)if(dut.pixel_rst_n)begin
        if(dut.camera_hdr_mode&&dut.capture0_valid&&dut.capture0_accept)begin
            if(dut.capture0_sof)check(dut.capture0_metadata[196:193]==4'b1101&&
                dut.capture0_metadata[192]==`PCIE_RECORD_V2_SOURCE_PHYSICAL&&dut.capture0_metadata[159:128]==32'h56a3d02f,
                "physical fixed-recipe LONG camera0 provenance");
            check(dut.capture0_data=={4{10'd306}},"exact LONG RAW12 quantization");
            $fdisplay(raw_long_fd,"%010h",dut.capture0_data);long_groups++;
        end
        if(dut.camera_hdr_mode&&dut.capture1_valid&&dut.capture1_accept)begin
            if(dut.capture1_sof)check(dut.capture1_metadata[196:193]==4'b1110&&
                dut.capture1_metadata[192]==`PCIE_RECORD_V2_SOURCE_PHYSICAL&&dut.capture1_metadata[159:128]==32'h56a3d02f,
                "physical fixed-recipe SHORT camera0 provenance");
            check(dut.capture1_data=={4{10'd66}},"exact SHORT RAW12 quantization");
            $fdisplay(raw_short_fd,"%010h",dut.capture1_data);short_groups++;
        end
        if(dut.hdr_raw_valid&&dut.hdr_raw_ready)begin
            check(dut.processing_context_owned&&dut.hdr_processing_selected,"HDR payload after genuine context acquisition");
            check(dut.hdr_raw_capsule[55:0]=={4{14'd256}},"independent exact black50 and ratio16 RAW merge");
            $fdisplay(hdr_raw_fd,"%014h",dut.hdr_raw_capsule[55:0]);hdr_groups++;
        end
        if(dut.private_rgb_valid&&dut.private_rgb_ready)begin
            $fdisplay(hdr_rgb_fd,"%024h",dut.private_rgb);hdr_rgb_groups++;
        end
        if(dut.hdr_product_done)good_sources++;
    end
    always @(posedge dut.dfi_clk)if(dut.dfi_rst_n)begin
        if(dut.raw_commit_valid&&dut.raw_commit_ready)begin
            raw_commits++;
            check(dut.raw_commit_frame[3]==`PCIE_RECORD_V2_SOURCE_PHYSICAL&&dut.raw_commit_frame[0]&&!dut.raw_commit_frame[4],"committed HDR descriptor retains protocol PHYSICAL camera0 provenance");
        end
        if(dut.pairbank_valid&&dut.pairbank_ready)begin
            raw_pins++;
            check(dut.pairbank_id!=0,"single atomic acquired pair identity");
        end
        if(dut.pairbank_release_valid&&dut.pairbank_release_ready)begin
            raw_releases++;
            check(good_writers==1&&dut.raw_read_quiescent&&dut.hdr_writer_quiescent&&
                !dut.hdr_ticket_hold,"deterministic pair release waits for actual final JPEG B and ticket/PIX ACK");
        end
        if(dut.hdr_private_req_valid&&dut.hdr_private_req_ready)begin
            if(dut.hdr_private_req_op==3)fetches++;
            if(dut.hdr_private_req_op==5)retires++;
        end
    end
    task algo_command(input [31:0] operation,input [31:0] index,input [31:0] value);
        integer guard;
        begin
            algo_sequence++;
            write_bar(`PCIE_REG_ALGO_TARGET,`PCIE_ALGO_TARGET_F21);
            write_bar(`PCIE_REG_ALGO_SESSION,expected_session);
            write_bar(`PCIE_REG_ALGO_SEQUENCE,algo_sequence);
            write_bar(`PCIE_REG_ALGO_GENERATION,1);
            write_bar(`PCIE_REG_ALGO_INDEX,index);write_bar(`PCIE_REG_ALGO_VALUE,value);
            write_bar(`PCIE_REG_ALGO_COMMAND,operation);guard=0;
            do begin read_bar(`PCIE_REG_ALGO_STATUS,config_value);guard++;end
            while((!config_value[1]||config_value[0])&&guard<2000);
            check(guard<2000&&!config_value[2],"actual F21 LUT command completed without error");
        end
    endtask
    // Observe only the real public service ports and actual capture boundary.
    integer cfg_callbacks=0,cfg_acks=0,cfg_applies=0;
    reg [1183:0] cfg_callback_tuple=0,cfg_stalled_tuple=0;
    reg cfg_callback_pending=0,cfg_ack_seen=0,cfg_was_stalled=0;
    reg [31:0] cfg_epoch_seen=0,cfg_first_sequence=0,expected_shadow_word0=0;
    always @(posedge dut.pixel_clk)begin
        if(!dut.g_config.u_config.pixel_rst_n||!dut.user_rst_n)begin
            cfg_callback_pending=0;cfg_ack_seen=0;cfg_was_stalled=0;cfg_epoch_seen=0;
        end else begin
            if(cfg_was_stalled)check(dut.online_config_valid&&dut.online_config_data===cfg_stalled_tuple,
                "real callback remains valid and immutable across receiver stall");
            cfg_was_stalled=dut.online_config_valid&&!dut.online_config_ready;
            if(cfg_was_stalled)cfg_stalled_tuple=dut.online_config_data;
            if(dut.online_config_valid&&dut.online_config_ready&&dut.online_config_data[31:0]!=0)begin
                check(!cfg_callback_pending,"single callback owner before ACK");
                cfg_callback_tuple=dut.online_config_data;cfg_callback_pending=1;cfg_callbacks++;
            end
            if(dut.online_config_ack_valid&&dut.online_config_ack_ready&&dut.online_config_ack_data[31:0]!=0)begin
                check(cfg_callback_pending&&dut.online_config_ack_ok&&dut.online_config_ack_data===cfg_callback_tuple,
                    "actual frontend/job-config ACK matches the complete accepted callback");
                cfg_callback_pending=0;cfg_ack_seen=1;cfg_acks++;
            end
            if(dut.g_config.online_epoch!=cfg_epoch_seen)begin
                check(cfg_ack_seen&&dut.g_config.u_config.frame_accept&&dut.g_config.u_config.pipeline_idle,
                    "new epoch exists only on actual accepted capture SOF after remote ACK");
                cfg_first_sequence=dut.g_config.u_config.frame_sequence;cfg_applies++;cfg_ack_seen=0;
            end
            cfg_epoch_seen=dut.g_config.online_epoch;
        end
    end
    task prepare_cancel_on_real_bar;
        integer guard,callbacks_before;
        begin
            callbacks_before=cfg_callbacks;
            write_bar(`PCIE_REG_CFG_REQUEST_SEQUENCE,2);write_bar(`PCIE_REG_CFG_REQUEST_SESSION,expected_session);
            write_bar(`PCIE_REG_CFG_REQUEST_MODE,1);write_bar(`PCIE_REG_CFG_REQUEST_QUALITY,73);
            write_bar(`PCIE_REG_CFG_REQUEST_FLAGS,0);write_bar(`PCIE_REG_CFG_REQUEST_MIN_QUALITY,1);
            write_bar(`PCIE_REG_CFG_REQUEST_FRAME_BUDGET,0);write_bar(`PCIE_REG_CFG_REQUEST_RESTART_MCUS,0);
            write_bar(`PCIE_REG_CFG_HOST_CAPABILITIES,1);write_bar(`PCIE_REG_CFG_COMMAND,`PCIE_CFG_COMMAND_PREPARE);
            guard=0;do begin read_bar(`PCIE_REG_CFG_STATUS,config_value);guard++;end
                while(!config_value[`PCIE_CFG_STATUS_READY]&&guard<2000);
            check(guard<2000&&!config_value[`PCIE_CFG_STATUS_ERROR]&&cfg_callbacks==callbacks_before,
                "PREPARE owns an immutable tuple without a callback or new active bank");
            read_bar(`PCIE_REG_CFG_ACTIVE_QUALITY,config_value);check(config_value==75,"prepared quality cannot replace active quality");
            write_bar(`PCIE_REG_CFG_COMMAND,`PCIE_CFG_COMMAND_CANCEL);
            guard=0;do begin read_bar(`PCIE_REG_CFG_STATUS,config_value);guard++;end
                while(config_value[`PCIE_CFG_STATUS_BUSY]&&guard<2000);
            check(guard<2000&&!config_value[`PCIE_CFG_STATUS_READY]&&!config_value[`PCIE_CFG_STATUS_APPLIED]&&
                !config_value[`PCIE_CFG_STATUS_ERROR]&&cfg_callbacks==callbacks_before,"matching CANCEL releases only prepared work");
            read_bar(`PCIE_REG_CFG_ACTIVE_QUALITY,config_value);check(config_value==75,"CANCEL preserves prior active quality");
            write_bar(`PCIE_REG_CFG_COMMAND,`PCIE_CFG_COMMAND_COMMIT);
            guard=0;do begin read_bar(`PCIE_REG_CFG_ERROR,config_value);guard++;end
                while(config_value!=`PCIE_CFG_ERROR_STALE&&guard<1000);
            check(guard<1000&&cfg_callbacks==callbacks_before,"COMMIT after CANCEL is STALE and cannot resurrect callback");
            $display("CONFIG_MAIN PASS PREPARE/CANCEL/stale-COMMIT through native BAR");
        end
    endtask
    task configure_hdr(input bit enable_hdr,input [31:0] command_sequence);
        reg [1023:0] extension;integer guard;
        begin
            extension=0;extension[7:0]=1;extension[15:8]=enable_hdr ? 8'd4 : 8'd0;
            extension[`PCIE_CFG_EXT_OFFSET_HDR_RATIO+:3]=4;
            extension[`PCIE_CFG_EXT_OFFSET_HDR_BLACK_LONG+:10]=50;
            extension[`PCIE_CFG_EXT_OFFSET_HDR_BLACK_SHORT+:10]=50;
            extension[`PCIE_CFG_EXT_OFFSET_HDR_MOTION_BASE+:14]=64;
            extension[`PCIE_CFG_EXT_OFFSET_HDR_MOTION_SHIFT+:4]=3;
            extension[`PCIE_CFG_EXT_OFFSET_HDR_QUALIFICATION+:4]=15;
            extension[`PCIE_CFG_EXT_OFFSET_HDR_MAX_DELTA_NS+:64]=50000000;
            extension[`PCIE_CFG_EXT_OFFSET_HDR_MAX_WAIT_NS+:32]=100000000;
            extension[`PCIE_CFG_EXT_OFFSET_HDR_MAX_AGE_NS+:32]=1000000000;
            write_bar(`PCIE_REG_CFG_HOST_CAPABILITIES,1);write_bar(`PCIE_REG_CFG_REQUEST_SEQUENCE,command_sequence);
            write_bar(`PCIE_REG_CFG_REQUEST_SESSION,expected_session);write_bar(`PCIE_REG_CFG_REQUEST_MODE,`PCIE_CFG_MODE_COLOR);write_bar(`PCIE_REG_CFG_REQUEST_QUALITY,75);
            for(integer n=0;n<32;n++)write_bar(`PCIE_REG_CFG_EXT_SHADOW_BASE+4*n,extension[n*32+:32]);
            write_bar(`PCIE_REG_CFG_COMMAND,`PCIE_CFG_COMMAND_PREPARE_EXT);guard=0;
            do begin read_bar(`PCIE_REG_CFG_STATUS,config_value);guard++;end while((config_value&3)!=3&&guard<2000);
            check(guard<2000&&!config_value[`PCIE_CFG_STATUS_ERROR],"fixed physical HDR preset accepted by actual shadow validator");
            write_bar(`PCIE_REG_CFG_COMMAND,`PCIE_CFG_COMMAND_COMMIT);guard=0;
            do begin read_bar(`PCIE_REG_CFG_STATUS,config_value);guard++;end
            while((!dut.cfg_source_ready||dut.cfg_pause)&&guard<2000);
            check(guard<2000&&!config_value[`PCIE_CFG_STATUS_ERROR],"real HDR config callback applied before sensor qualification");
            expected_shadow_word0=extension[31:0];
        end
    endtask


    task configure_sdr_v2(input [5:0] enables,input [31:0] request_sequence);
        reg [1023:0] extension;reg [1183:0] expected_plan;
        integer guard,old_callbacks,old_acks;
        begin
            extension=0;extension[7:0]=2;extension[9:8]=`PCIE_CFG_V2_MODES_MONO_SDR;extension[15:10]=enables;
            old_callbacks=cfg_callbacks;old_acks=cfg_acks;
            write_bar(`PCIE_REG_CFG_HOST_CAPABILITIES,1);
            write_bar(`PCIE_REG_CFG_REQUEST_SEQUENCE,request_sequence);write_bar(`PCIE_REG_CFG_REQUEST_SESSION,expected_session);
            write_bar(`PCIE_REG_CFG_REQUEST_MODE,0);write_bar(`PCIE_REG_CFG_REQUEST_QUALITY,75);
            write_bar(`PCIE_REG_CFG_REQUEST_FLAGS,0);write_bar(`PCIE_REG_CFG_REQUEST_MIN_QUALITY,1);
            write_bar(`PCIE_REG_CFG_REQUEST_FRAME_BUDGET,0);write_bar(`PCIE_REG_CFG_REQUEST_RESTART_MCUS,0);
            for(integer word=0;word<32;word++)write_bar(`PCIE_REG_CFG_EXT_SHADOW_BASE+4*word,extension[word*32+:32]);
            write_bar(`PCIE_REG_CFG_COMMAND,`PCIE_CFG_COMMAND_PREPARE_EXT);guard=0;
            do begin read_bar(`PCIE_REG_CFG_STATUS,config_value);guard++;
                check(!config_value[`PCIE_CFG_STATUS_ERROR],"schema2 PREPARE error");end
            while((config_value&3)!=3&&guard<3000);
            check(guard<3000&&cfg_callbacks==old_callbacks,"schema2 validates complete shadow without callback");
            write_bar(`PCIE_REG_CFG_COMMAND,`PCIE_CFG_COMMAND_COMMIT);guard=0;
            while((!dut.cfg_source_ready||dut.cfg_pause)&&guard<3000)begin
                read_bar(`PCIE_REG_CFG_STATUS,config_value);guard++;
                check(!config_value[`PCIE_CFG_STATUS_ERROR],"schema2 COMMIT error");
            end
            check(guard<3000&&cfg_callbacks==old_callbacks+1&&cfg_acks==old_acks+1,"schema2 real capture+DFI ACK barrier");
            check(dut.capture0_active_config[1183:160]===extension&&dut.dfi_active_config[1183:160]===extension,
                "schema2 exact raw identity survives capture and214-bit DFI roundtrip");
            check(!dut.camera_hdr_mode&&dut.g_configured_capture.u_frontend.physical_selected,
                "schema2 gray/analysis bits never select legacy virtual HDR");
            read_bar(`PCIE_REG_CFG_STATUS,config_value);
            check(config_value[`PCIE_CFG_STATUS_BUSY]&&!config_value[`PCIE_CFG_STATUS_APPLIED],
                "schema2 remote ACK is not an accepted-frame APPLIED");
        end
    endtask

    integer final_guard;
    integer jpeg_host_records=0,host_products=0,raw_groups=0,jpeg_native_retires=0;
    always @(posedge dut.pixel_clk)if(phase>=30&&dut.pixel_rst_n)
        if(dut.capture0_valid&&dut.capture0_accept)raw_groups++;
    always @(posedge dut.user_clk)if(phase>=30&&dut.user_rst_n)
        if(dut.jpeg_user_retire_valid&&dut.jpeg_user_retire_ready)jpeg_native_retires++;
    task receive_jpeg;
        integer fd;
        begin
            wait(`R8_EP.o_result_pending);`R8_HOST.wait_safe(0,-1);
            check({`R8_HOST.host_memory[3],`R8_HOST.host_memory[2],`R8_HOST.host_memory[1],`R8_HOST.host_memory[0]}==`PCIE_FRAME_MAGIC,
                "only a complete JPEG product reaches the native host");
            fd=$fopen($sformatf("actual_record_%0d.bin",scenario_index),"wb");
            for(integer k=0;k<`R8_HOST.committed;k++)$fwrite(fd,"%c",`R8_HOST.host_memory[k]);
            $fclose(fd);jpeg_host_records++;host_products++;`R8_HOST.ack;
        end
    endtask
    // C2-only integration boundary: observe the real helper and its real quiet
    // inputs during the appended drained application reset. No reset/quiet,
    // ownership or SAFE signal is forced by this fixture.
    reg c2_stop_monitor=0;
    integer c2_release_edges=0,c2_stop_releases=0,c2_stop_assertions=0,c2_stop_checks=0;
    reg c2_before_stop,c2_before_quiet;
    reg [2:0] c2_before_pipe;
    wire c2_app_run=dut.g_s04.u_raw_service.i_identity_rst_n&&
        dut.g_s04.u_raw_service.i_pixel_rst_n&&dut.g_s04.u_raw_service.i_dfi_rst_n;
    always @(negedge c2_app_run)if(c2_stop_monitor)c2_stop_assertions++;
    always @(posedge dut.dfi_clk or negedge c2_app_run)begin
        if(!c2_app_run)begin
            c2_release_edges=0;
            #1;
            if(c2_stop_monitor)begin
                check(dut.g_s04.u_raw_service.application_stop_dfi,
                    "application reset asynchronously asserts real DFI STOP");
                check(!dut.raw_policy_admit,"application reset cannot admit new RAW capture");
                c2_stop_checks++;
            end
        end else begin
            c2_before_stop=dut.g_s04.u_raw_service.application_stop_dfi;
            c2_before_quiet=dut.g_s04.u_raw_service.frontend_quiet&&dut.g_s04.u_raw_service.all_policy_quiet;
            c2_before_pipe=dut.g_s04.u_raw_service.u_application_stop.run_release_pipe;
            if(c2_before_stop)c2_release_edges++;
            #1;
            if(c2_stop_monitor)begin
                if(c2_before_stop&&!dut.g_s04.u_raw_service.application_stop_dfi)begin
                    check(c2_release_edges>=4&&c2_before_pipe==3'b111&&c2_before_quiet,
                        "real STOP release requires three sampled DFI edges and previous-edge genuine quiet");
                    c2_stop_releases++;
                end
                if(dut.g_s04.u_raw_service.application_stop_dfi)
                    check(!dut.raw_policy_admit,"held application STOP prohibits new RAW capture");
                c2_stop_checks++;
            end
        end
    end
    task c2_drained_soft_reset;
        integer old_jpeg_retire,guard;
        reg [31:0] old_session,new_session;
        begin
            check(host_products==2&&jpeg_native_retires==2,
                "C2 reset starts only after all complete products have actual SAFE/ACK and release");
            old_jpeg_retire=jpeg_native_retires;
            read_bar(`PCIE_REG_CFG_SESSION,old_session);
            c2_stop_monitor=1;
            `R8_HOST.write_reg(12'h008,4);
            `R8_HOST.read_reg(12'h00c,config_value);
            check(config_value[4]&&!`R8_EP.o_buffer_armed,"native C2H STOP retains an unarmed host buffer");
            write_bar(`PCIE_REG_CONTROL,2);
            guard=0;
            while(c2_stop_assertions==0&&guard<20000)begin @(negedge dut.dfi_clk);guard++;end
            check(guard<20000,"BAR soft reset actually asserts the application reset observed by STOP");
            guard=0;
            while(!(dut.session_rearm_required&&dut.session_rearm_ready&&dut.cfg_user_initialized&&
                    !dut.reset_pending_user&&!dut.g_s04.u_raw_service.application_stop_dfi)&&guard<20000)begin
                @(negedge dut.dfi_clk);guard++;
            end
            check(guard<20000,"drained soft reset reaches real BOOT/rearm and releases qualified STOP without deadlock");
            check(!dut.session_armed&&!dut.debug_local&&dut.endpoint_rst_n,
                "soft reset preserves HOST endpoint and requires explicit rearm");
            read_bar(`PCIE_REG_CONTROL,config_value);check(config_value==0,"BAR remains available after soft reset");
            read_bar(`PCIE_REG_CFG_SESSION,new_session);
            check(new_session!=0&&new_session!=old_session,"soft reset produces a fresh real BOOT session");
            read_bar(`PCIE_REG_CFG_ACTIVE_QUALITY,config_value);check(config_value==75,"BOOT active quality remains the public default");
            check(cfg_applies==1,"drained reset cannot fabricate another source-frame APPLY");
            write_bar(`PCIE_REG_CONTROL,1);guard=0;
            while(!dut.session_armed&&guard<20000)begin @(negedge dut.dfi_clk);guard++;end
            check(guard<20000,"fresh enable rearms the actual session after STOP release");
            check(!`R8_EP.o_buffer_armed&&!dut.frame_accept,"fresh session still requires a real host buffer grant");
            write_bar(`PCIE_REG_CONTROL,0);guard=0;
            while(!(dut.raw_region_quiet)&&guard<20000)begin @(negedge dut.dfi_clk);guard++;end
            check(guard<20000,"post-reset APP disable again reaches genuine RAW/JPEG quiet");
            check(c2_stop_assertions>0&&c2_stop_releases==1&&c2_stop_checks>4,
                "C2 integration observed actual application-reset assertion and one qualified STOP release");
            check(jpeg_native_retires==old_jpeg_retire,
                "reset and rearm do not fabricate acquisition/release/SAFE retirement");
            $display("C2_STOP_MAIN PASS checks=%0d assertions=%0d releases=%0d old_session=%0d new_session=%0d after_products=%0d",
                c2_stop_checks,c2_stop_assertions,c2_stop_releases,old_session,new_session,host_products);
            c2_stop_monitor=0;
        end
    endtask
    task reject_removed_lz;
        reg [1023:0] extension;integer guard,old_callbacks;
        begin
            extension=0;extension[7:0]=2;extension[9:8]=`PCIE_CFG_V2_MODES_MONO_SDR_LZ;
            old_callbacks=cfg_callbacks;
            read_bar(`PCIE_REG_CFG_EXT_V2_MODES,config_value);
            check(config_value==((1 << `PCIE_CFG_V2_MODES_MONO_SDR) | (1 << `PCIE_CFG_V2_MODES_MONO_HDR)),
                "capability reports SDR and HDR from generated enum values");
            write_bar(`PCIE_REG_CFG_HOST_CAPABILITIES,1);write_bar(`PCIE_REG_CFG_REQUEST_SEQUENCE,99);
            write_bar(`PCIE_REG_CFG_REQUEST_SESSION,expected_session);write_bar(`PCIE_REG_CFG_REQUEST_MODE,0);
            write_bar(`PCIE_REG_CFG_REQUEST_QUALITY,75);write_bar(`PCIE_REG_CFG_REQUEST_FLAGS,0);
            write_bar(`PCIE_REG_CFG_REQUEST_MIN_QUALITY,1);write_bar(`PCIE_REG_CFG_REQUEST_FRAME_BUDGET,0);
            write_bar(`PCIE_REG_CFG_REQUEST_RESTART_MCUS,0);
            for(integer n=0;n<32;n++)write_bar(`PCIE_REG_CFG_EXT_SHADOW_BASE+4*n,extension[n*32+:32]);
            write_bar(`PCIE_REG_CFG_COMMAND,`PCIE_CFG_COMMAND_PREPARE_EXT);guard=0;
            do begin read_bar(`PCIE_REG_CFG_STATUS,config_value);guard++;end
            while(!config_value[`PCIE_CFG_STATUS_ERROR]&&guard<2000);
            check(guard<2000&&cfg_callbacks==old_callbacks,"removed LZ rejected before configuration callback");
            read_bar(`PCIE_REG_CFG_ERROR,config_value);
            check(config_value==`PCIE_CFG_ERROR_UNSUPPORTED,"removed LZ returns UNSUPPORTED");
            $display("REMOVED_LZ_REJECT PASS");
        end
    endtask
`ifdef REFACTOR_RUNTIME_RECOVERY
    `include "runtime_recovery/top_runtime.vh"
`endif
`ifdef REFACTOR_RUNTIME_CRC
    `include "resilience/top_crc.vh"
`endif
`ifdef REFACTOR_AUTOF21_SHORT
    `include "autof21/main/top_short.vh"
`endif
    task run_sdr;
        begin
            phase=30;pcie_mperst=1;`R8_EP.link_up=1;`R8_EP.hold_axis=0;
            repeat(20)@(negedge sys_clk);
            wait(!dut.debug_local&&dut.debug_app_rst_n&&dut.session_rearm_ready&&dut.cfg_user_initialized);
            read_bar(`PCIE_REG_CFG_SESSION,expected_session);send_select(21);select_reply(21);
            `R8_HOST.write_reg(12'h008,8);write_bar(`PCIE_REG_CONTROL,1);
            wait(dut.session_armed&&dut.cfg_source_ready&&!dut.cfg_pause);
            reject_removed_lz();scenario_enables=61;configure_sdr_v2(scenario_enables,100);
            for(scenario_index=0;scenario_index<2;scenario_index++)begin
                if(scenario_index==1)begin
                    wait(dut.g_preprocess.g_live_f21.u_live.u_pipeline.g_full_preprocess.u_hist.pending_lut||
                        dut.g_preprocess.g_live_f21.u_live.u_pipeline.g_full_preprocess.u_hist.lut_valid);
                end
                isp_groups=0;processed_groups=0;f22_records=0;f23_records=0;
                $fclose(record_fd);record_fd=$fopen($sformatf("local_record_%0d.bin",scenario_index),"wb");
                isp_fd=$fopen($sformatf("sdr_isp_%0d.hex",scenario_index),"w");
                processed_fd=$fopen($sformatf("sdr_processed_%0d.hex",scenario_index),"w");
                f22_fd=$fopen($sformatf("sdr_f22_%0d.hex",scenario_index),"w");
                f23_fd=$fopen($sformatf("sdr_f23_%0d.hex",scenario_index),"w");
                `R8_HOST.grant(scenario_index+1,1048576);trace_sdr=1;
                fork source_frame(GROUPS,1);receive_jpeg();join
                wait(jpeg_native_retires==scenario_index+1&&!dut.jpeg_cdc_source_busy);wait_quiet();trace_sdr=0;
                check(isp_groups==GROUPS&&processed_groups==GROUPS,"both fullHD ISP and processed rasters");
                check(f22_records==1&&f23_records==1,"one C1/F22 terminal per full frame");
                check(good_sources==scenario_index+1&&good_writers==scenario_index+1&&host_products==scenario_index+1,
                    "SOURCE/writer/host counts follow actual products");
                check(`R8_MEM.accepted_aw==`R8_MEM.accepted_b,"all frame DDR debt retired");
                $fclose(isp_fd);$fclose(processed_fd);$fclose(f22_fd);$fclose(f23_fd);
                $display("EXTENDED_HE_FRAME PASS index=%0d source_sequence=%0d history=%0d full_pixels=2073600",scenario_index,scenario_index+1,scenario_index);
            end
            check(cfg_applies==1&&bad_sources==0&&bad_writers==0,"one real APPLIED and two good frames");
            $display("EXTENDED_HE_MAIN PASS frames=2 mask=61 JPEG=2 native_retire=2");
            c2_drained_soft_reset();
`ifdef REFACTOR_READONLY_UART_MAIN
            readonly_uart_finish();
`endif
            done_o=1;
        end
    endtask


    task hdr_phy_word(input [31:0] value,input bit valid_word);
        begin @(negedge dut.u_camera.u_receiver.o_hs_word_clk);fixture_word=value;fixture_valid=valid_word;end
    endtask
    task hdr_packet_gap;
        begin hdr_phy_word(0,0);repeat(4)@(negedge dut.u_camera.u_receiver.o_hs_word_clk);end
    endtask
    task hdr_short(input integer vc,input bit finish,input integer frame_number);
        reg [23:0] h;
        begin h={frame_number[15:0],vc[1:0],5'd0,finish};hdr_phy_word({2'd0,ecc(h),h},1);hdr_packet_gap();end
    endtask
    reg [7:0] hdr_bytes[0:2919];
    task hdr_line(input integer vc);
        reg [11:0] sample;reg [15:0] crc;reg [23:0] h;reg [31:0] w;
        begin
            sample=vc==0?12'd1224:12'd264;
            for(integer n=0;n<2916;n+=3)begin hdr_bytes[n]=sample[11:4];hdr_bytes[n+1]=sample[11:4];hdr_bytes[n+2]={sample[3:0],sample[3:0]};end
            crc=16'hffff;for(integer n=0;n<2916;n++)crc=crc_byte(crc,hdr_bytes[n]);
            hdr_bytes[2916]=crc[7:0];hdr_bytes[2917]=crc[15:8];hdr_bytes[2918]=0;hdr_bytes[2919]=0;
            h={16'd2916,vc[1:0],6'h2c};hdr_phy_word({2'd0,ecc(h),h},1);
            for(integer n=0;n<2918;n+=4)begin w={hdr_bytes[n+3],hdr_bytes[n+2],hdr_bytes[n+1],hdr_bytes[n]};hdr_phy_word(w,1);end
            hdr_packet_gap();
        end
    endtask
    task hdr_full_pair(input integer index);
        begin
            hdr_short(0,0,index+7);hdr_short(1,0,index+101);
            for(integer row=0;row<1097;row++)begin hdr_line(0);hdr_line(1);end
            hdr_short(0,1,index+7);hdr_short(1,1,index+101);hdr_packet_gap();
        end
    endtask
    task configure_plain_sdr(input [31:0] sequence_id);
        integer guard,callbacks_before,acks_before;
        begin
            callbacks_before=cfg_callbacks;acks_before=cfg_acks;
            write_bar(`PCIE_REG_CFG_HOST_CAPABILITIES,1);
            write_bar(`PCIE_REG_CFG_REQUEST_SEQUENCE,sequence_id);
            write_bar(`PCIE_REG_CFG_REQUEST_SESSION,expected_session);
            write_bar(`PCIE_REG_CFG_REQUEST_MODE,`PCIE_CFG_MODE_COLOR);
            write_bar(`PCIE_REG_CFG_REQUEST_QUALITY,75);
            write_bar(`PCIE_REG_CFG_REQUEST_FLAGS,0);
            write_bar(`PCIE_REG_CFG_REQUEST_MIN_QUALITY,1);
            write_bar(`PCIE_REG_CFG_REQUEST_FRAME_BUDGET,0);
            write_bar(`PCIE_REG_CFG_REQUEST_RESTART_MCUS,0);
            write_bar(`PCIE_REG_CFG_COMMAND,`PCIE_CFG_COMMAND_PREPARE);
            guard=0;do begin read_bar(`PCIE_REG_CFG_STATUS,config_value);guard++;end
                while(!config_value[`PCIE_CFG_STATUS_READY]&&guard<2000);
            check(guard<2000&&!config_value[`PCIE_CFG_STATUS_ERROR]&&cfg_callbacks==callbacks_before,
                "canonical non-EXT plain SDR PREPARE validates without stale inactive HDR fields");
            write_bar(`PCIE_REG_CFG_COMMAND,`PCIE_CFG_COMMAND_COMMIT);
            guard=0;while((!dut.cfg_source_ready||dut.cfg_pause||cfg_callbacks!=callbacks_before+1||cfg_acks!=acks_before+1)&&guard<2000)begin
                read_bar(`PCIE_REG_CFG_STATUS,config_value);guard++;
            end
            check(guard<2000&&!config_value[`PCIE_CFG_STATUS_ERROR],
                "plain SDR callback and complete real capture/DFI ACK barrier");
        end
    endtask
    task return_sdr_and_cancel_bad_frame;
        integer old_starts,old_bad_sources,old_bad_writers;
        realtime measured_clock_start;
        begin
            phase=9;old_starts=starts;old_bad_sources=bad_sources;old_bad_writers=bad_writers;
            configure_plain_sdr(2);
            wait(!dut.camera_hdr_mode&&dut.camera_mode_running&&dut.camera_config_done);
            check(dut.u_camera.u_mclk.select_n===2'b10&&dut.u_camera.u_mclk.i_reset_n,
                "actual HDR to SDR mode return restores exclusive 24MHz clock");
            @(posedge cam_mclk);measured_clock_start=$realtime;
            repeat(8)@(posedge cam_mclk);
            check($realtime-measured_clock_start>333.0&&$realtime-measured_clock_start<333.7,
                "actual SDR INCK output measures 24MHz over eight periods");
            check(!dut.camera_hdr_stable&&raw_releases==1&&!dut.hdr_ticket_hold,
                "old HDR ticket and pair truly retired before SDR sensor mode runs");
            check(cfg_applies==1,"SDR remote config ACK and clock switch cannot fabricate APPLIED");
            wait(dut.u_camera.u_receiver.publish_enable&&dut.u_camera.u_receiver.decoder_reset_n);
            `R8_HOST.grant(2,1048576);
            wait(dut.physical_admit_enable&&dut.native_pipeline_idle&&!dut.cfg_pause);
            sensor_event(0,1,0);
            for(integer row=0;row<21;row++)csi_line(row,row==20);
            sensor_event(1,1,0);
            wait(bad_sources==old_bad_sources+1&&bad_writers==old_bad_writers+1);
            wait_quiet();
            check(starts==old_starts+1&&cfg_applies==2&&user_records==1,
                "real accepted SDR SOF applies once; CRC-bad partial frame cancels writer without publishing a record");
            check(raw_pins==1&&raw_releases==1&&!dut.hdr_ticket_hold&&!dut.raw_processing_fault,
                "direct SDR failure cannot fabricate an HDR ticket ACK or pair owner");
            check(`R8_MEM.accepted_aw==`R8_MEM.accepted_b,
                "partial failed SDR owner settles real write responses before final quiet");
            $display("REAL_HDR_SDR_RETURN_CANCEL PASS starts=%0d sourceBad=%0d writerBad=%0d applies=%0d records=%0d",
                starts,bad_sources,bad_writers,cfg_applies,user_records);
        end
    endtask
    integer completion_stage=0;
    task run_real_hdr;
        begin
            raw_long_fd=$fopen("capture_long.hex","w");raw_short_fd=$fopen("capture_short.hex","w");
            hdr_raw_fd=$fopen("hdr_raw14.hex","w");hdr_rgb_fd=$fopen("hdr_rgb888.hex","w");
            phase=7;pcie_mperst=1;`R8_EP.link_up=1;`R8_EP.hold_axis=0;
            wait(!dut.debug_local&&dut.debug_app_rst_n&&dut.session_rearm_ready&&dut.cfg_user_initialized);
            read_bar(`PCIE_REG_CFG_SESSION,expected_session);send_select(11);select_reply(11);
            `R8_HOST.write_reg(12'h008,8);write_bar(`PCIE_REG_CONTROL,1);
            wait(dut.session_armed&&dut.cfg_source_ready&&!dut.cfg_pause);
            configure_hdr(1,1);
            wait(dut.camera_hdr_mode&&dut.camera_mode_running&&dut.u_camera.u_hdr_config.o_config_written);
            wait(dut.u_camera.u_receiver.publish_enable&&dut.u_camera.u_receiver.decoder_reset_n);
            wait(dut.u_camera.u_receiver.u_hdr_stream.decoder_release[1]&&
                dut.u_camera.u_receiver.u_hdr_stream.word_release[1]&&
                dut.u_camera.u_receiver.u_hdr_stream.pixel_release[1]&&
                dut.u_camera.u_receiver.u_hdr_stream.o_fifo_write_ready);
            repeat(20)@(negedge dut.pixel_clk);
            check(!dut.camera_hdr_stable,"I2C written cannot qualify HDR");
            $display("REAL_HDR_STEP WARMUP_BEGIN time=%0t",$time);hdr_full_pair(1);
            wait(dut.camera_hdr_stable);check(long_groups==0&&short_groups==0&&raw_pins==0,"warmup real CSI pair drained before capture admission");
            `R8_HOST.grant(1,1048576);phase=8;
            $display("REAL_HDR_STEP PRODUCTION_BEGIN time=%0t",$time);hdr_full_pair(2);
            completion_stage=1; $display("REAL_HDR_STAGE CFG_READ time=%0t",$time);
            read_bar(`PCIE_REG_CFG_STATUS,config_value);
            completion_stage=2; $display("REAL_HDR_STAGE CFG_READ_DONE time=%0t status=%h",$time,config_value);
            check(cfg_applies==1&&config_value[`PCIE_CFG_STATUS_APPLIED]&&!config_value[`PCIE_CFG_STATUS_BUSY]&&
                !config_value[`PCIE_CFG_STATUS_ERROR],"true HDR primary RAW SOF publishes CONFIG APPLIED once");
            wait(user_records==1); completion_stage=3; $display("REAL_HDR_STAGE USER_LAST time=%0t",$time);
            `R8_HOST.wait_safe(0,`R8_HOST.expected_length); completion_stage=4; $display("REAL_HDR_STAGE SAFE time=%0t",$time);
            `R8_HOST.ack; completion_stage=5; $display("REAL_HDR_STAGE ACK time=%0t",$time);
            wait(raw_releases==1); completion_stage=6; $display("REAL_HDR_STAGE PAIR_RELEASE time=%0t",$time);
            wait_quiet(); completion_stage=7; $display("REAL_HDR_STAGE QUIET time=%0t",$time);
            check(long_groups==GROUPS&&short_groups==GROUPS&&hdr_groups==GROUPS&&hdr_rgb_groups==GROUPS,
                "full physical CSI, dual DDR capture, merge and shared ISP group counts");
            check(raw_pins==1&&raw_releases==1&&good_writers==1&&bad_writers==0&&good_sources==1,
                "one HDR JPEG true writer/host SAFE/ACK and pair retirement");
            check(`R8_MEM.accepted_aw==`R8_MEM.accepted_b,"all physical HDR and JPEG write responses settled");
            check(dut.capture0_metadata[95:64]==3200&&dut.capture1_metadata[95:64]==200&&
                dut.capture0_metadata[127:96]==256&&dut.capture1_metadata[127:96]==256,
                "record recipe uses line ticks and backend Q8.8 unity");
            $fclose(raw_long_fd);$fclose(raw_short_fd);$fclose(hdr_raw_fd);$fclose(hdr_rgb_fd);
            $display("REAL_HDR_MAIN PASS RAW=%0d/%0d merge=%0d RGB=%0d pairs=%0d/%0d writer=%0d AW/B=%0d/%0d",
                long_groups,short_groups,hdr_groups,hdr_rgb_groups,raw_pins,raw_releases,good_writers,`R8_MEM.accepted_aw,`R8_MEM.accepted_b);
            return_sdr_and_cancel_bad_frame();
`ifdef REFACTOR_READONLY_UART_MAIN
            readonly_uart_finish();
`endif
            done_o=1;
        end
    endtask
    initial begin
        event_fd=$fopen(USER_CASE ? "user_events.txt":"local_events.txt","w");
        if(USER_CASE)begin record_fd=$fopen("local_record.bin","wb");ext_fd=$fopen("actual_extension.hex","w");end
        wait(start_i);wait(dut.debug_rst_n&&dut.debug_app_rst_n);
        check(dut.debug_color_config==10'h040&&dut.debug_color_wb==30'h10040100,
            "fixed fixture defaults precede application release");
`ifdef REFACTOR_SDR_MAIN
        run_sdr();
`else
        run_real_hdr();
`endif
        $fclose(event_fd);if(USER_CASE)begin $fclose(record_fd);$fclose(ext_fd);end
        $display("BOUNDARY_CASE PASS user=%0d checks=%0d starts=%0d writerOK=%0d writerBad=%0d localRetire=%0d userRecords=%0d",USER_CASE,checks,starts,good_writers,bad_writers,local_retires,user_records);
    end
    initial begin wait(start_i);#160000000;
        if(!done_o)$fatal(1,"FULL boundary watchdog case=%0d phase=%0d run=%b armed=%b starts=%0d sources=%0d/%0d writer=%0d/%0d record=%0d local=%0d/%0d",USER_CASE,phase,dut.debug_run,dut.session_armed,starts,good_sources,bad_sources,good_writers,bad_writers,user_records,dut.u_local_stop.admitted_count,dut.u_local_stop.settled_count);
    end
    initial begin wait(start_i);while(!done_o)begin #1000000;
        if(completion_stage>0&&!done_o)$display("REAL_HDR_DIAG stage=%0d pin/release=%0d/%0d quiet cfg/native/physical/cycle=%b%b%b%b ring/meta/f21=%b%b%b native/job/frame/jpeg/raw/pre/mask/f21=%b%b%b%b%b%b%b%b sourceIdle=%b writerAck=%b actualMode=%b stable=%b lanequiet=%b ticket=%b rwquiet=%b",completion_stage,raw_pins,raw_releases,dut.cfg_pipeline_idle,dut.native_pipeline_idle,dut.physical_source_idle,dut.hdr_cycle_quiet,dut.record_ring_quiescent,dut.record_metadata_quiescent,dut.live_f21_maintenance_quiet,dut.native_job_idle,dut.job_pending,dut.frame_active_pixel,dut.jpeg_idle,dut.raw_processing_idle_pixel,dut.preprocess_records_quiet,dut.mask_source_quiet,dut.live_f21_frame_quiet,dut.physical_source_idle,dut.writer_ack_valid,dut.camera_hdr_mode,dut.camera_hdr_stable,dut.lane_quiet,dut.hdr_ticket_hold,dut.hdr_writer_quiescent);
        if(!done_o)$display("FULL_LZ_WATCH case=%0d phase=%0d starts=%0d sources=%0d/%0d writers=%0d/%0d records=%0d EXT=%b/%b DFI_EXT=%b/%b quiet=%b",USER_CASE,phase,starts,good_sources,bad_sources,good_writers,bad_writers,user_records,dut.record_source_extension_valid,dut.record_source_extension_ready,dut.record_dfi_extension_valid,dut.record_dfi_extension_ready,dut.record_dfi_data_quiescent);
    end end
endmodule

module tb_hdr_jpeg #(
    parameter ROM_ROOT="./rom_init"
);
    wire done;wire [31:0] checks;
    real_hdr_main_case #(.USER_CASE(1),.ROM_ROOT(ROM_ROOT)) user_scope(1'b1,done,checks);
    initial begin wait(done);$display("RESULT: PASS REFACTOR HDR JPEG MAIN checks=%0d",checks);$finish;end
endmodule

module tb_full_stop_session #(
    parameter ROM_ROOT="./rom_init"
);
    reg local_start=0,user_start=0;
    wire local_done,user_done;wire [31:0] local_checks,user_checks;
    real_hdr_main_case #(.USER_CASE(0),.ROM_ROOT(ROM_ROOT)) local_scope(local_start,local_done,local_checks);
    real_hdr_main_case #(.USER_CASE(1),.ROM_ROOT(ROM_ROOT)) user_scope(user_start,user_done,user_checks);
    initial begin local_start=1;wait(local_done);user_start=1;wait(user_done);
        $display("RESULT: PASS FULL STOP SESSION checks=%0d LOCAL=%0d USER=%0d",local_checks+user_checks,local_checks,user_checks);$finish;end
endmodule

module tb_local_failed_stop_recovery #(
    parameter ROM_ROOT="./rom_init"
);
    wire done;wire [31:0] checks;
    real_hdr_main_case #(.USER_CASE(0),.ROM_ROOT(ROM_ROOT)) local_scope(1'b1,done,checks);
    initial begin wait(done);$display("RESULT: PASS LOCAL FAILED STOP RECOVERY checks=%0d",checks);$finish;end
endmodule
