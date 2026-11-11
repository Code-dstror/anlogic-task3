// Optional real TOP runtime scenario. Drives only the existing CSI word fixture.
// SOURCE numbers are fixed by the stimulus: failed 1, ignored 2, failed 3,
// ignored 4, recovered 5. Partial images are never used as golden output.
`define RR_CORE dut.u_camera.u_receiver.u_stream.u_word_core
`define RR_LIVE dut.g_preprocess.g_live_f21.u_live
`define RR_PIPE dut.g_preprocess.g_live_f21.u_live.u_pipeline
`define RR_HE dut.g_preprocess.g_live_f21.u_live.u_pipeline.g_full_preprocess.u_hist
    reg rr_active=0,rr_partial=0,rr_resync=0,rr_clear_due=0;
    reg rr_previous_pending=0,rr_previous_quiet=0;
    integer rr_faults=0,rr_contexts=0,rr_receive_faults=0,rr_ignored=0;
    integer rr_input_sofs=0,rr_pipe_sofs=0,rr_he_sofs=0,rr_output_sofs=0,rr_clears=0;
    integer rr_busy_fault_cycles=0,rr_partial_fd=0;
    reg [5:0] rr_previous_tail=0;
    reg [63:0] rr_first_rx;
    always @(posedge dut.pixel_clk)if(rr_active&&dut.pixel_rst_n)begin
        if(rr_clear_due)begin
            check(!dut.source_recovery_history_pending,"runtime history request clears after real processed SOF");
            rr_clears++;rr_clear_due=0;
        end
        if(dut.source_recovery_history_pending&&!rr_previous_pending)
            check(rr_previous_quiet,"runtime history reset begins only after old actual owners quiet");
        if(dut.camera_receive_fault)rr_receive_faults++;
        if({dut.physical_source_failed,dut.status_valid,dut.jpeg_result_valid,
            dut.jpeg_result_ready,dut.record_source_extension_valid,dut.physical_cleanup_pulse}!=rr_previous_tail)begin
            $display("RUNTIME_RECOVERY TAIL sourceFailed=%b status=%b/%b/%b result=%b/%b/%b adm=%0d end=%b bad=%b buf=%b encStarted=%b jpeg=%0d inputDone=%b statusSeen=%b rgb=%b/%b time=%0t",
                dut.physical_source_failed,dut.status_valid,dut.status_ready,dut.status_ok,
                dut.jpeg_result_valid,dut.jpeg_result_ready,dut.jpeg_result_ok,
                dut.u_admission.state,dut.u_admission.end_seen,dut.u_admission.bad_seen,dut.u_admission.buf_valid,
                dut.u_admission.encoder_started,dut.u_jpeg.state,dut.u_jpeg.input_done,dut.u_jpeg.status_seen,
                dut.jpeg_rgb_valid,dut.jpeg_rgb_ready,$time);
            $display("RUNTIME_RECOVERY RECORDS cleanup=%b rst=%b laneOwned=%b product=%b source=%b/%b foreground=%b/%b lane=%b/%b abort=%b terminal=%b/%b builder=%0d join=%b/%b features=%b records=%b%b stats=%b/%b time=%0t",
                dut.physical_cleanup_pulse,dut.physical_processing_rst_n,dut.g_live_lane.u_owner.owned,
                dut.g_live_lane.u_owner.product_seen,dut.g_live_lane.u_owner.source_seen,dut.g_live_lane.u_owner.source_failed,
                dut.g_live_lane.u_owner.foreground_seen,dut.g_live_lane.u_owner.foreground_failed,
                dut.g_live_lane.u_owner.lane_seen,dut.g_live_lane.u_owner.lane_failed,dut.g_live_lane.u_owner.abort_seen,
                dut.advanced_terminal_valid,dut.advanced_terminal_error,dut.g_record_builder.u_builder.state,
                dut.g_record_builder.g_v3.u_join.owned,dut.g_record_builder.g_v3.u_join.terminal_seen,
                dut.g_record_builder.g_v3.u_join.features,dut.advanced_f22_pending,dut.advanced_f23_valid,
                dut.live_neutral_stats_valid,dut.live_neutral_stats_ready,$time);
        end
        rr_previous_tail={dut.physical_source_failed,dut.status_valid,dut.jpeg_result_valid,
            dut.jpeg_result_ready,dut.record_source_extension_valid,dut.physical_cleanup_pulse};
        if(dut.physical_cleanup_pulse)
            check(dut.preprocess_records_quiet&&dut.jpeg_idle&&!dut.frame_active_pixel&&
                !dut.record_source_extension_valid&&!dut.jpeg_result_valid&&
                dut.g_physical_source.g_regular_cleanup.g_live_record_drain.source_retired,
                "runtime local clear follows real negative SOURCE and complete record/JPEG retirement");
        if(dut.physical_identity_quarantine&&!dut.mono_source_recovery_quiet)rr_busy_fault_cycles++;
        if(dut.capture0_valid&&dut.capture0_accept&&dut.capture0_sof)begin
            check(dut.capture0_sequence==1+2*rr_contexts,"runtime SOURCE sequence must be fixed 1,3,5");
            rr_contexts++;
        end
        if(rr_resync&&dut.physical_event_valid&&dut.mono_physical_event_ready&&dut.physical_event_kind==0)begin
            check(dut.physical_event_sequence==2*rr_faults&&dut.physical_identity_quarantine&&
                !dut.g_physical_source.physical_admission_credit,"runtime resync FS is consumed without admission");
            rr_ignored++;
        end
        if(rr_contexts>1)begin
            if(dut.preprocess_input_valid&&dut.preprocess_input_ready&&dut.preprocess_input_sof)begin
                rr_input_sofs++;check(dut.physical_recovery_history_reset,"runtime recovered input SOF resets history");
            end
            if(`RR_PIPE.input_fire&&!`RR_PIPE.active)begin
                rr_pipe_sofs++;check(`RR_PIPE.cfg_history_reset&&dut.physical_recovery_history_reset,"runtime pipeline history sample");
            end
            if(`RR_HE.s_valid&&`RR_HE.s_ready&&`RR_HE.s_sof)begin
                rr_he_sofs++;check(`RR_PIPE.frame_history_reset&&`RR_HE.history_reset&&dut.physical_recovery_history_reset,"runtime HE history sample");
            end
            if(dut.processed_valid&&dut.processed_ready&&dut.processed_sof)begin
                rr_output_sofs++;
                check(dut.physical_recovery_history_reset&&rr_input_sofs==rr_output_sofs&&
                    rr_pipe_sofs==rr_output_sofs&&rr_he_sofs==rr_output_sofs,
                    "runtime output SOF follows remaining input, pipeline and HE history sampling points");
                rr_clear_due=1;
            end
        end
        if(rr_partial)begin
            if(dut.camera_rgb_valid&&dut.camera_rgb_ready)
                $fdisplay(rr_partial_fd,"ISP sequence=%0d data=%024h",dut.job_sequence,dut.camera_rgb);
            if(dut.processed_valid&&dut.processed_ready)
                $fdisplay(rr_partial_fd,"PP sequence=%0d sof=%b eol=%b data=%024h",dut.job_sequence,dut.processed_sof,dut.processed_eol,dut.processed_rgb);
        end
        rr_previous_pending=dut.source_recovery_history_pending;
        rr_previous_quiet=dut.physical_identity_quarantine&&dut.mono_source_recovery_quiet;
    end
    task rr_wait_source;
        begin
            wait(dut.cfg_source_ready&&!dut.cfg_pause&&dut.cfg_pipeline_idle&&dut.session_armed&&dut.replay_admission_ready);
            wait(dut.camera_mode_running&&!dut.camera_hdr_mode&&dut.u_camera.o_config_done);
            wait(dut.u_camera.u_receiver.publish_enable&&dut.u_camera.u_receiver.decoder_reset_n);
            repeat(20)@(negedge dut.u_camera.u_receiver.o_hs_word_clk);
        end
    endtask
    task runtime_configure_gaussian;
        integer n,old_callbacks,old_acks;
        begin
            old_callbacks=cfg_callbacks;old_acks=cfg_acks;
            write_bar(`PCIE_REG_CFG_HOST_CAPABILITIES,1);
            write_bar(`PCIE_REG_CFG_REQUEST_SEQUENCE,100);write_bar(`PCIE_REG_CFG_REQUEST_SESSION,expected_session);
            write_bar(`PCIE_REG_CFG_REQUEST_MODE,`PCIE_CFG_MODE_GAUSSIAN);write_bar(`PCIE_REG_CFG_REQUEST_QUALITY,75);
            write_bar(`PCIE_REG_CFG_REQUEST_FLAGS,0);write_bar(`PCIE_REG_CFG_REQUEST_MIN_QUALITY,1);
            write_bar(`PCIE_REG_CFG_REQUEST_FRAME_BUDGET,0);write_bar(`PCIE_REG_CFG_REQUEST_RESTART_MCUS,0);
            write_bar(`PCIE_REG_CFG_COMMAND,`PCIE_CFG_COMMAND_PREPARE);n=0;
            do begin read_bar(`PCIE_REG_CFG_STATUS,config_value);n++;end
            while(!config_value[`PCIE_CFG_STATUS_READY]&&n<2000);
            check(n<2000&&!config_value[`PCIE_CFG_STATUS_ERROR]&&cfg_callbacks==old_callbacks,
                "runtime legacy Gaussian PREPARE uses canonical mode2, not schema2 dehaze enable2");
            write_bar(`PCIE_REG_CFG_COMMAND,`PCIE_CFG_COMMAND_COMMIT);n=0;
            while((!dut.cfg_source_ready||dut.cfg_pause||cfg_callbacks!=old_callbacks+1||cfg_acks!=old_acks+1)&&n<2000)begin
                read_bar(`PCIE_REG_CFG_STATUS,config_value);n++;
            end
            check(n<2000&&!config_value[`PCIE_CFG_STATUS_ERROR]&&!dut.capture0_schema2&&
                dut.capture0_active_config[65:64]==`PCIE_CFG_MODE_GAUSSIAN&&!dut.camera_hdr_mode,
                "runtime legacy Gaussian real capture and DFI ACK, actual physical SDR mode2");
        end
    endtask
    task rr_fail_owned_frame(input integer expected_sequence);
        integer n,old_sources,old_writers,old_starts,old_receive;
        begin
            rr_wait_source();rr_partial=1;
            old_sources=bad_sources;old_writers=bad_writers;old_starts=starts;old_receive=rr_receive_faults;
            sensor_event(0,1,0);
            for(integer row=0;row<32;row++)csi_line(row,0);
            n=0;while((starts!=old_starts+1||!dut.g_physical_source.native_owned)&&n<20000)begin @(negedge dut.pixel_clk);n++;end
            check(n<20000&&dut.job_sequence==expected_sequence&&rr_contexts==rr_faults+1&&
                !dut.mono_source_recovery_quiet&&!dut.physical_identity_quarantine,
                "runtime bad header follows real old FS/context and native/JPEG START");
            check(rr_faults==0||rr_clears==1,"first recovered partial frame passed history SOF before second failure");
`ifdef REFACTOR_RUNTIME_LEGACY_GAUSSIAN
            check(dut.job_mode==`PCIE_CFG_MODE_GAUSSIAN&&dut.g_preprocess.enables==3'b011,
                "runtime Gaussian failure owns the actual grayscale Gaussian pixel pipeline");
`endif
            $display("RUNTIME_RECOVERY OWNED sequence=%0d starts=%0d native=%b frame=%b jpegIdle=%b time=%0t",expected_sequence,starts,dut.g_physical_source.native_owned,dut.frame_active_pixel,dut.jpeg_idle,$time);
            rr_faults++;csi_word(32'h00097e2b);
            repeat(8)@(negedge dut.u_camera.u_receiver.o_hs_word_clk);
            n=0;
            while((bad_sources!=old_sources+1||bad_writers!=old_writers+1||!dut.mono_source_recovery_quiet||
                   !dut.record_ring_quiescent||!dut.record_metadata_quiescent||!dut.live_f21_maintenance_quiet
                   )&&n<200000)begin @(negedge dut.pixel_clk);n++;end
            if(n==200000)$display("RUNTIME_RECOVERY BLOCKED sourceBad=%0d writerBad=%0d sourceQuiet=%b nativeIdle=%b cropValid=%b cleanup=%b/%b fence=%0d frame=%b jpegIdle=%b records=%b live=%b",bad_sources,bad_writers,dut.mono_source_recovery_quiet,dut.native_pipeline_idle,dut.cropped_raw_valid,dut.g_physical_source.cleanup_pending,dut.g_physical_source.cleanup_fault,dut.g_physical_source.u_fence.state,dut.frame_active_pixel,dut.jpeg_idle,dut.preprocess_records_quiet,dut.live_f21_maintenance_quiet);
            if(n==200000)$display("RUNTIME_RECOVERY TAIL_BLOCKED adm=%0d end=%b bad=%b buf=%b encStarted=%b jpeg=%0d inputDone=%b statusSeen=%b status=%b/%b/%b rgb=%b/%b sourceOwned=%b jobPending=%b rst=%b lane=%b cfg=%b join=%b records=%b%b%b%b%b",
                dut.u_admission.state,dut.u_admission.end_seen,dut.u_admission.bad_seen,dut.u_admission.buf_valid,
                dut.u_admission.encoder_started,dut.u_jpeg.state,dut.u_jpeg.input_done,dut.u_jpeg.status_seen,
                dut.status_valid,dut.status_ready,dut.status_ok,dut.jpeg_rgb_valid,dut.jpeg_rgb_ready,
                dut.g_physical_source.native_owned,dut.job_pending,dut.physical_processing_rst_n,
                dut.lane_quiet,dut.advanced_cfg_ready,dut.advanced_join_ready,
                dut.advanced_f22_pending,dut.advanced_f23_valid,dut.advanced_f24_valid,dut.advanced_f25_valid,dut.record_source_extension_valid);
            check(n<200000&&dut.physical_identity_quarantine&&dut.camera_source_identity_fault&&
                rr_receive_faults==old_receive+1&&good_sources==0&&good_writers==0&&user_records==0&&
                `R8_MEM.accepted_aw==`R8_MEM.accepted_b,
                "runtime failed owner emits exactly one negative SOURCE/writer, no host record, all writes settled");
            if(rr_faults==1)begin
                rr_first_rx=`RR_CORE.o_identity_diag;
                check(rr_first_rx[63:32]==32'h00097e2b&&rr_first_rx[31:16]==16'd1,"runtime first RX captures observed bad word at SOURCE1");
            end else begin
                check(`RR_CORE.o_identity_diag==rr_first_rx,
                    "second runtime fault preserves first RX identity");
            end
            rr_partial=0;
            $display("RUNTIME_RECOVERY NEGATIVE sequence=%0d sourceBad=%0d writerBad=%0d receiveFaults=%0d time=%0t",expected_sequence,bad_sources,bad_writers,rr_receive_faults,$time);
        end
    endtask
    task rr_discard_boundary;
        integer n,old_starts;
        begin
            old_starts=starts;rr_resync=1;sensor_event(0,1,0);
            n=0;while(dut.physical_identity_quarantine&&n<20000)begin @(negedge dut.pixel_clk);n++;end
            check(n<20000&&rr_ignored==rr_faults&&starts==old_starts,
                "runtime healthy consumed FS releases quarantine before any boundary RAW or CRC error");
            // One pre-crop RAW line with real CRC error clears crop activity
            // belonging to this deliberately ignored recovery boundary.
            csi_line(0,1);sensor_event(1,1,0);
            n=0;while((dut.physical_identity_quarantine||!dut.mono_source_recovery_quiet||
                dut.u_camera.u_pipeline.u_crop.active||dut.u_camera.u_pipeline.u_crop.held_pending||
                dut.u_camera.u_pipeline.u_crop.abort_pending||dut.g_physical_source.u_fence.state!=0)&&n<20000)begin
                @(negedge dut.pixel_clk);n++;
            end
            check(n<20000&&starts==old_starts&&rr_ignored==rr_faults&&dut.source_recovery_history_pending&&
                !dut.u_camera.identity_fault_seen,"runtime consumed ignored boundary rearms parser edge detector and keeps history pending");
            rr_resync=0;
            $display("RUNTIME_RECOVERY RESYNC ignored_sequence=%0d time=%0t",2*rr_faults,$time);
        end
    endtask
    task runtime_recovery_prefix;
        begin
            rr_partial_fd=$fopen("runtime_partial_pixels.txt","w");rr_active=1;
            rr_fail_owned_frame(1);rr_discard_boundary();
            rr_fail_owned_frame(3);rr_discard_boundary();
            // Success-only counters/traces start after both failed frames.
            raw_groups=0;
        end
    endtask
    task runtime_recovery_finish(input bit short_only);
        begin
            check(rr_faults==2&&rr_ignored==2&&rr_contexts==3&&rr_receive_faults==2&&
                rr_clears==2&&rr_output_sofs==2&&rr_busy_fault_cycles>0&&bad_sources==2&&bad_writers==2&&
                !dut.physical_identity_quarantine&&!dut.camera_source_identity_fault,
                "runtime lifecycle: two admitted failures, two ignored boundaries, recovered SOURCE5 and two history clears");
            check(`RR_CORE.o_identity_diag==rr_first_rx,"runtime final first-loss RX evidence immutable");
            $display("RUNTIME_RECOVERY_MAIN PASS short=%0d failures=2 ignored=2 recovered_sequence=5 enables=%0d source_bad=%0d writer_bad=%0d contexts=%0d receive_faults=%0d history_sofs=%0d history_clears=%0d busy_fault_cycles=%0d",short_only,scenario_enables,bad_sources,bad_writers,rr_contexts,rr_receive_faults,rr_output_sofs,rr_clears,rr_busy_fault_cycles);
            rr_active=0;$fclose(rr_partial_fd);
        end
    endtask
    task runtime_recovery_short;
        begin
            rr_wait_source();rr_partial=1;sensor_event(0,1,0);
            for(integer row=0;row<32;row++)csi_line(row,0);
            check(rr_clears==2&&starts==3&&dut.job_sequence==5,"runtime short reaches recovered processed SOF with actual owner5");
            runtime_recovery_finish(1);done_o=1;
        end
    endtask
