// Real CSI CRC corruption after actual JPEG admission. No identity loss,
// quarantine, ignored recovery boundary, or forced receive-fault is injected.
// Stimulus authority: failures SOURCE1/2, recovered SOURCE3.
    reg crc_active=0;
    integer crc_failures=0,crc_contexts=0,crc_recovered_sofs=0,crc_local_clears=0;
    reg [63:0] crc_initial_rx;
    always @(posedge dut.pixel_clk)if(crc_active&&dut.pixel_rst_n)begin
        check(!rr_active,"CRC fixture must not enable header-specific runtime monitor");
        check(!dut.physical_identity_quarantine&&!dut.camera_source_identity_fault&&!dut.camera_receive_fault,
            "ordinary CRC failure must not fabricate identity loss or RX receive-fault");
        check(`RR_CORE.o_identity_diag==crc_initial_rx,"CRC preserves RX first-loss identity evidence");
        if(dut.capture0_valid&&dut.capture0_accept&&dut.capture0_sof)begin
            crc_contexts++;check(dut.capture0_sequence==crc_contexts,"CRC SOURCE authority is fixed 1,2,3");
        end
        if(dut.processed_valid&&dut.processed_ready&&dut.processed_sof&&dut.job_sequence==3)crc_recovered_sofs++;
        if(dut.physical_cleanup_pulse)begin
            crc_local_clears++;
            check(dut.preprocess_records_quiet&&dut.jpeg_idle&&!dut.frame_active_pixel&&
                !dut.record_source_extension_valid&&!dut.jpeg_result_valid&&
                dut.g_physical_source.g_regular_cleanup.g_live_record_drain.source_retired,
                "CRC local clear follows actual negative SOURCE and metadata/JPEG retirement");
        end
    end
    task crc_fail_owned_frame(input integer expected_sequence);
        integer n,old_sources,old_writers,old_starts;reg [31:0] old_crc;
        begin
            rr_wait_source();rr_partial=1;
            old_sources=bad_sources;old_writers=bad_writers;old_starts=starts;old_crc=dut.camera_crc;
            sensor_event(0,1,0);
            for(integer row=0;row<31;row++)csi_line(row,0);
            n=0;while((starts!=old_starts+1||!dut.g_physical_source.native_owned)&&n<20000)begin @(negedge dut.pixel_clk);n++;end
            check(n<20000&&dut.job_sequence==expected_sequence&&crc_contexts==expected_sequence&&
                !dut.source_recovery_quiet&&!dut.physical_identity_quarantine,
                "CRC corruption follows real frame context/native/JPEG START");
            if(scenario_enables==48)check(dut.g_live_lane.u_owner.owned&&
                dut.g_record_builder.g_v3.u_join.owned&&dut.g_record_builder.g_v3.u_join.features[1:0]==3,
                "sparse CRC is injected only while actual F22/F23 and V3 join own this frame");
            $display("CRC_RECOVERY OWNED sequence=%0d starts=%0d enables=%0d time=%0t",expected_sequence,starts,scenario_enables,$time);
            csi_line(31,1);sensor_event(1,1,0);
            n=0;while((bad_sources!=old_sources+1||bad_writers!=old_writers+1||!dut.source_recovery_quiet||
                !dut.record_ring_quiescent||!dut.record_metadata_quiescent||!dut.live_f21_maintenance_quiet||
                dut.writer_ack_valid)&&n<200000)begin @(negedge dut.pixel_clk);n++;end
            if(n==200000)$display("CRC_RECOVERY BLOCKED sourceBad=%0d writerBad=%0d sourceQuiet=%b fence=%0d cleanup=%b/%b adm=%0d jpeg=%0d records=%b/%b/%b join=%b stats=%b/%b CRC=%0d",
                bad_sources,bad_writers,dut.source_recovery_quiet,dut.g_physical_source.u_fence.state,
                dut.g_physical_source.cleanup_pending,dut.g_physical_source.cleanup_fault,dut.u_admission.state,dut.u_jpeg.state,
                dut.preprocess_records_quiet,dut.record_ring_quiescent,dut.record_metadata_quiescent,
                dut.g_record_builder.g_v3.u_join.owned,dut.live_neutral_stats_valid,dut.live_neutral_stats_ready,dut.camera_crc);
            check(n<200000&&bad_sources==old_sources+1&&bad_writers==old_writers+1&&
                dut.camera_crc==old_crc+1&&good_sources==0&&good_writers==0&&user_records==0&&
                `R8_MEM.accepted_aw==`R8_MEM.accepted_b,
                "CRC owner emits one true negative SOURCE/writer, no host product, and settles all writes");
            crc_failures++;rr_partial=0;
            $display("CRC_RECOVERY NEGATIVE sequence=%0d sourceBad=%0d writerBad=%0d crcErrors=%0d clears=%0d time=%0t",expected_sequence,bad_sources,bad_writers,dut.camera_crc,crc_local_clears,$time);
        end
    endtask
    task runtime_crc_prefix;
        begin
            rr_wait_source();crc_initial_rx=`RR_CORE.o_identity_diag;crc_active=1;
            crc_fail_owned_frame(1);crc_fail_owned_frame(2);raw_groups=0;
        end
    endtask
    task runtime_crc_finish(input bit short_only);
        begin
            check(crc_failures==2&&crc_contexts==3&&crc_recovered_sofs==1&&crc_local_clears==2&&
                bad_sources==2&&bad_writers==2&&!dut.physical_identity_quarantine&&
                !dut.camera_source_identity_fault&&!dut.camera_receive_fault,
                "CRC lifecycle has two actual negative owners followed by recovered SOURCE3");
            $display("CRC_RECOVERY_MAIN PASS short=%0d failures=2 ignored=0 recovered_sequence=3 enables=%0d source_bad=%0d writer_bad=%0d contexts=%0d receive_faults=0 recovered_sofs=%0d clears=%0d",short_only,scenario_enables,bad_sources,bad_writers,crc_contexts,crc_recovered_sofs,crc_local_clears);
            crc_active=0;
        end
    endtask
    task runtime_crc_short;
        integer n;
        begin
            rr_wait_source();rr_partial=1;sensor_event(0,1,0);
            for(integer row=0;row<32;row++)csi_line(row,0);
            n=0;while(crc_recovered_sofs!=1&&n<20000)begin @(negedge dut.pixel_clk);n++;end
            check(n<20000&&starts==3&&dut.job_sequence==3,"CRC short reaches actual recovered processed SOF SOURCE3");
            runtime_crc_finish(1);done_o=1;
        end
    endtask
