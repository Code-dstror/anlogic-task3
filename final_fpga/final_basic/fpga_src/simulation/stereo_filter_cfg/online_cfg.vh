    // This short test terminates both CSI samples with a real bad CRC after
    // the first cropped line. It qualifies online CFG and capture identity;
    // it cannot qualify complete filter pixels, JPEG output, or frame rate.
    reg [1:0] cfg_sample_seen=0;
    reg [31:0] cfg_expected_epoch=0, cfg_first_cam0_sequence=0;
    always @(posedge dut.pixel_clk)begin
        if(dut.stereo_capture0_valid&&dut.stereo_capture0_accept&&dut.stereo_capture0_sof)begin
            check(dut.stereo_capture0_epoch==cfg_expected_epoch && dut.stereo_capture0_session==session,
                "CAM0 accepted tuple at real cropped input");
            cfg_first_cam0_sequence=dut.stereo_capture0_sequence;cfg_sample_seen[0]=1;
        end
        if(dut.stereo_capture1_valid&&dut.stereo_capture1_accept&&dut.stereo_capture1_sof)begin
            check(dut.stereo_capture1_epoch==cfg_expected_epoch && dut.stereo_capture1_session==session,
                "CAM1 independently accepted the same applied epoch");
            cfg_sample_seen[1]=1;
        end
    end
    task automatic dual_filter_config(input integer enables,from_epoch);
        reg [31:0] status, ext, prior_epoch,request_seq;
        integer polls;
        begin
            read_bar(`PCIE_REG_CFG_MODE_EPOCH,prior_epoch);check(prior_epoch==from_epoch,"selected from current mode epoch");
            cfg_sample_seen=0;
            read_bar(`PCIE_REG_CFG_RESPONSE_SEQUENCE,request_seq);request_seq++;
            write_bar(`PCIE_REG_CFG_REQUEST_SEQUENCE,request_seq);write_bar(`PCIE_REG_CFG_REQUEST_SESSION,session);
            write_bar(`PCIE_REG_CFG_REQUEST_MODE,0);write_bar(`PCIE_REG_CFG_REQUEST_QUALITY,75);
            write_bar(`PCIE_REG_CFG_REQUEST_FLAGS,0);write_bar(`PCIE_REG_CFG_REQUEST_MIN_QUALITY,1);
            write_bar(`PCIE_REG_CFG_REQUEST_FRAME_BUDGET,0);write_bar(`PCIE_REG_CFG_REQUEST_RESTART_MCUS,0);
            write_bar(`PCIE_REG_CFG_HOST_CAPABILITIES,1);
            ext=(enables<<10)|2;
            for(integer k=0;k<32;k++)write_bar(`PCIE_REG_CFG_EXT_SHADOW_BASE+4*k,k==0?ext:0);
            write_bar(`PCIE_REG_CFG_COMMAND,`PCIE_CFG_COMMAND_PREPARE_EXT);
            polls=0;status=0;
            while(!status[`PCIE_CFG_STATUS_READY] && !status[`PCIE_CFG_STATUS_ERROR] && polls<4000)begin
                read_bar(`PCIE_REG_CFG_STATUS,status);polls++;
            end
            check(status[`PCIE_CFG_STATUS_READY]&&!status[`PCIE_CFG_STATUS_ERROR],"real armed DUAL PREPARE reached READY");
            write_bar(`PCIE_REG_CFG_COMMAND,`PCIE_CFG_COMMAND_COMMIT);cfg_expected_epoch=prior_epoch+1;
            polls=0;
            while((!dut.stereo_capture_enable || dut.capture0_active_config[159:128]!=cfg_expected_epoch)&&polls<20000)begin
                @(negedge dut.pixel_clk);polls++;
            end
            check(polls<20000,"frontend ack drained and both eye inputs available");
            // The prior bad-CRC sample consumes one actual N2 phase on each eye.
            // Send up to four physical frames; each includes a new trusted FS.
            for(integer attempt=0;attempt<4 && cfg_sample_seen!=3;attempt++)begin
                fork
                    begin if(!cfg_sample_seen[0])begin
                        source0.event_word(0,16'(16'h301+4*from_epoch+attempt));
                        for(integer y=0;y<17;y++)source0.line(y,0);
                        source0.line(17,1);source0.event_word(1,16'(16'h301+4*from_epoch+attempt));
                    end end
                    begin if(!cfg_sample_seen[1])begin
                        repeat(37)@(negedge dut.pixel_clk);source1.event_word(0,16'(16'h501+4*from_epoch+attempt));
                        for(integer y=0;y<17;y++)source1.line(y,0);
                        source1.line(17,1);source1.event_word(1,16'(16'h501+4*from_epoch+attempt));
                    end end
                join
                repeat(80)@(negedge dut.pixel_clk);
            end
            polls=0;status=0;
            while((!status[`PCIE_CFG_STATUS_APPLIED] || status[`PCIE_CFG_STATUS_BUSY]) && polls<4000)begin
                read_bar(`PCIE_REG_CFG_STATUS,status);polls++;
            end
            check(status[`PCIE_CFG_STATUS_APPLIED]&&!status[`PCIE_CFG_STATUS_ERROR],"APPLIED on accepted CAM0 SOF");
            read_bar(`PCIE_REG_CFG_APPLIED_FIRST_SEQUENCE,status);
            check(cfg_sample_seen==3 && status==cfg_first_cam0_sequence,"APPLIED matches CAM0 SOURCE and both captured epochs");
            read_bar(`PCIE_REG_CFG_EXT_ACTIVE_BASE,status);check(status==ext,"active filter tuple matches requested enables");
            read_bar(`PCIE_REG_CFG_MODE_EPOCH,status);check(status==cfg_expected_epoch,"advanced exactly one epoch");
            repeat(2000)@(negedge dut.pixel_clk);check(source_count==0&&writer_count==0,"no JPEG from failed samples");
            $display("RESULT: PASS DUAL_FILTER_ONLINE_CFG epoch=%0d first_sequence=%0d captured=%b enables=%h",cfg_expected_epoch,cfg_first_cam0_sequence,cfg_sample_seen,ext[15:10]);
        end
    endtask
