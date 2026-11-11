`timescale 1ns/1ps
`default_nettype none
// The included monitor and observer instantiation are extracted byte-for-byte
// from production TOP. Only explicit source-domain inputs are test-driven.
module tb_first_job_observer;
    localparam integer READONLY_UART_REPORT_CYCLES=2048;
    reg sys_clk=0,pixel_clk=0,dfi_clk=0,user_clk=0,rx_diag_word_clk=0;
    reg pix_running=1,dfi_running=1;
    always #5 sys_clk=~sys_clk;
    always #4 if(pix_running)pixel_clk=~pixel_clk;
    always #3 if(dfi_running)dfi_clk=~dfi_clk;
    always #7 user_clk=~user_clk;
    always #6 rx_diag_word_clk=~rx_diag_word_clk;
    reg debug_rst_n=0,debug_pixel_rst_n=0,debug_dfi_rst_n=0,debug_user_rst_n=0;
    reg pixel_rst_n=1,dfi_rst_n=1,user_rst_n=1,camera_mode_running=1;
    reg [15:0] sys_flags=0;
    reg [11:0] user_observe_flags=0,dfi_flags=0,pixel_flags=0;
    reg [3:0] user_faults=0,dfi_faults=0,pixel_faults=0;
    reg [1:0] user_progress=0,dfi_progress=0,pixel_progress=0;
    reg [383:0] rx_diag_domains=0;
    wire uart_tx;
    reg stereo_mode_dfi=0,pairbank_enable_sync=0,stereo_mode_pixel=0;
    reg [1:0] enable_pixel=0;
    reg stereo_job_valid=0,stereo_job_ready=0;
    reg [383:0] stereo_job_frame=0;
    reg raw_processing_fault=0,hdr_ticket_exhausted=0,raw_read_quiescent=1;
    reg raw_private_ownership_quiescent=0,hdr_owner_empty=0,hdr_scheduler_busy=1;
    reg raw_private_rsp_valid=0,normal_private_rsp_ready=0,normal_private_req_valid=0,normal_private_req_ready=0;
    reg raw_axi_arvalid=0,raw_axi_arready=0,raw_axi_rvalid=0,raw_axi_rready=0;
    reg stereo_retire_valid=0,stereo_retire_ready=0,stereo_retire_done=0;
    reg [3:0] diag_scheduler_state=1;
    reg [2:0] diag_ticket_state=3;
    reg [3:0] diag_scheduler_error=0;
    reg hdr_ticket_recovery=0,credit_reserved_dfi=1,hdr_fifo_source_reset_done=1,diag_member_valid=1,diag_member_ready=0;
    reg store_ready_claim=0,writer_ack_valid=0,writer_ack_ready=0,raw_private_native_done=0;
    reg [7:0] diag_ticket_error=0;
    reg [63:0] common_dfi_time_ns=8000000,common_pixel_time_ns=8000000;
    reg common_dfi_time_valid=1,common_pixel_time_valid=1;
    reg physical_event_valid=0,stereo_event0_ready=1,physical_event_identity_valid=1;
    reg [1:0] physical_event_kind=0;
    reg camera1_event_valid=0,camera1_event_ready=1,camera1_event_identity_valid=1;
    reg [1:0] camera1_event_kind=0;
    reg admission_take=0,processed_valid=0,processed_ready=1,processed_sof=0,private_context_fire=0;
    reg private_rgb_valid=0,private_rgb_ready=1,private_rgb_sof=0,hdr_fifo_sink_valid=0,hdr_fifo_sink_ready=0;
    reg credit_grant_pixel=0,credit_request_pixel=1,raw_capture1_frame_accept=0,raw_capture0_frame_accept=0;
    reg processing_pixel_fault=0;
    reg [1:0] record_format_busy_pixel=0;
    reg record_product_available=1,hdr_fifo_sink_reset_done=1,admission_protocol_fault=0,hdr_pixel_context_valid=1;
    reg processing_context_owned=0,processing_context_ready=0,processing_pool_idle=1,replay_admission_ready=0,credit_ack_pixel=1;
    reg [1:0] armed_pixel=2'b10;
    reg [2:0] diag_admission_state=0;
    reg [3:0] diag_ticket_pixel=4'b1100;
    // Shared HDR observation inputs for the production monitor.
    reg test_hdr_mode=0,test_hdr_take=0,test_hdr_ready=0;
    reg test_hdr_retire_valid=0,test_hdr_retire_ready=0,test_hdr_retire_done=0;
    reg test_hdr_req_valid=0,test_hdr_req_ready=0,test_hdr_rsp_ready=0;
    wire diag_job_valid=stereo_job_valid||test_hdr_take;
    wire diag_job_ready=stereo_job_ready||test_hdr_ready;
    wire diag_retire_valid=stereo_retire_valid||test_hdr_retire_valid;
    wire diag_retire_ready=stereo_retire_ready||test_hdr_retire_ready;
    wire diag_retire_done=stereo_retire_done||test_hdr_retire_done;
    wire [383:0] hdr_job_frame0=stereo_job_frame;
    wire stereo_sdr_dfi=stereo_mode_dfi&&!test_hdr_mode;
    wire raw_private_req_valid=normal_private_req_valid||test_hdr_req_valid;
    wire raw_private_req_ready=normal_private_req_ready||test_hdr_req_ready;
    wire raw_private_rsp_ready=normal_private_rsp_ready||test_hdr_rsp_ready;
    reg hdr_context_valid=0,hdr_context_ready=0,hdr_start_valid=0,hdr_start_ready=0;
    reg hdr_result_valid=0,hdr_result_ready=0;
    reg hdr_capture0_valid=0,hdr_capture0_sof=0,hdr_capture1_valid=0,hdr_capture1_sof=0;
    reg [1:0] cam1_hdr_valid=0,cam1_hdr_sof=0;

    `include "production_job_watch.vh"
    // Only UART serialization/report frequency is accelerated. The monitor's
    // deadline expression and the production observer connections are original.
    defparam u_observer.UART_DIV=8;
    defparam u_observer.SNAPSHOT_TIMEOUT_CYCLES=64;

    integer checks=0,wire_fd,captured_rounds=0;
    reg [223:0] frozen_dfi,frozen_pix;
    reg [7:0] serial_byte;
    task automatic check(input bit condition,input string message);
        begin checks++;if(!condition)$fatal(1,"TOP_JOB_WATCH %s",message);end
    endtask
    task automatic identity(input bit camera,input [1:0] slot,input [31:0] seq,gen,session,epoch);
        begin
            stereo_job_frame=0;stereo_job_frame[4]=camera;stereo_job_frame[6:5]=slot;
            stereo_job_frame[44:13]=gen;stereo_job_frame[76:45]=session;
            stereo_job_frame[108:77]=seq;stereo_job_frame[140:109]=epoch;
        end
    endtask
    task automatic wire_mark(input string phase,input integer expected_fresh);
        integer target;
        begin
            target=captured_rounds+2;
            wait(captured_rounds>=target);
            $display("WIRE_MARK phase=%s round=%0d expected_fresh=%0d dfi=%056h pix=%056h",
                phase,captured_rounds,expected_fresh,job_page_dfi,job_page_pix);
        end
    endtask
    initial begin
        wire_fd=$fopen("top_job_uart.bin","wb");
        check(wire_fd!=0,"opened UART capture");
        forever begin
            for(integer byte_number=0;byte_number<161;byte_number++)begin
                @(negedge uart_tx);#120;
                for(integer bit_number=0;bit_number<8;bit_number++)begin
                    serial_byte[bit_number]=uart_tx;#80;
                end
                check(uart_tx===1'b1&&!$isunknown(serial_byte),"8N1 byte and stop bit");
                $fwrite(wire_fd,"%c",serial_byte);
            end
            $fflush(wire_fd);captured_rounds++;
        end
    end
    initial begin
        repeat(8)@(negedge sys_clk);
        debug_rst_n=1;debug_pixel_rst_n=1;debug_dfi_rst_n=1;debug_user_rst_n=1;
        repeat(8)@(negedge dfi_clk);
        identity(1,2,32'h12345678,32'h10203040,17,3);
        stereo_mode_dfi=1;pairbank_enable_sync=1;stereo_job_valid=1;stereo_job_ready=1;
        @(negedge dfi_clk);stereo_job_valid=0;stereo_job_ready=0;
        repeat(2)@(negedge dfi_clk);
        check(job_seen&&job_watch&&!job_stalled&&first_sequence==32'h12345678&&first_generation==32'h10203040&&
            first_session==17&&first_epoch==3&&first_location==3'b110&&job_count1==1&&job_count0==0,
            "first DFI job tuple latched on actual TAKE, including TAKE at RUN rise");
        identity(0,1,32'hdeadbeef,32'h55667788,23,4);
        @(negedge pixel_clk);stereo_mode_pixel=1;enable_pixel=2'b10;
        physical_event_valid=1;camera1_event_valid=1;raw_capture0_frame_accept=1;
        @(negedge pixel_clk);physical_event_valid=0;camera1_event_valid=0;raw_capture0_frame_accept=0;
        repeat(3)@(negedge pixel_clk);
        check(fs_count0==1&&fs_count1==1&&raw_count0==1&&raw_count1==0&&!pixel_finished&&!pixel_stalled,
            "PIX owns its independent RUN opening and trusted FS/admit events");
        // Logical common-time values are explicit fixture inputs. Crossing the
        // real production [27:24]+7 deadline represents 109.440512 ms here;
        // the serial test need not wait that duration in simulator wall time.
        common_pixel_time_ns=64'd117440511;
        repeat(2)@(negedge pixel_clk);check(!pixel_stalled,"PIX does not freeze before production deadline bin");
        common_pixel_time_valid=0;common_pixel_time_ns=64'd117440512;
        repeat(2)@(negedge pixel_clk);check(!pixel_stalled,"invalid common time cannot freeze PIX");
        common_pixel_time_valid=1;
        repeat(2)@(negedge pixel_clk);
        check(pixel_stalled&&!pixel_finished&&job_watch&&!job_stalled,"PIX freezes independently while DFI still waits");
        frozen_pix=job_page_pix;
        diag_admission_state=3;diag_ticket_pixel=15;admission_take=1;processed_valid=1;processed_sof=1;
        repeat(2)@(negedge pixel_clk);admission_take=0;processed_valid=0;processed_sof=0;
        check(job_page_pix===frozen_pix,"PIX fault sample stays frozen after later milestones and levels");
        @(negedge dfi_clk);common_dfi_time_ns=64'd100663296;raw_axi_arvalid=1;raw_axi_arready=1;
        @(negedge dfi_clk);raw_axi_arvalid=0;raw_axi_arready=0;
        check(dfi_deadline==13&&job_watch&&!job_stalled,"real new AR milestone refreshes DFI deadline");
        common_dfi_time_ns=64'd218103807;
        repeat(2)@(negedge dfi_clk);check(!job_stalled,"refreshed DFI deadline does not fire early");
        common_dfi_time_ns=64'd218103808;
        repeat(2)@(negedge dfi_clk);
        check(job_stalled&&!job_watch&&first_sequence==32'h12345678&&first_location==6,
            "DFI freezes original identity after its own refreshed stall");
        frozen_dfi=job_page_dfi;
        diag_scheduler_state=12;diag_ticket_state=6;diag_ticket_error=8'h55;raw_processing_fault=1;
        writer_ack_valid=1;writer_ack_ready=1;store_ready_claim=1;
        repeat(2)@(negedge dfi_clk);writer_ack_valid=0;writer_ack_ready=0;store_ready_claim=0;
        check(job_page_dfi===frozen_dfi,"DFI frozen fields ignore later state/fault/milestone noise");
        // Rate counters are deliberately outside first-job freeze in TOP.
        // Verify that distinction instead of claiming every page bit freezes.
        @(negedge dfi_clk);stereo_job_valid=1;stereo_job_ready=1;
        @(negedge dfi_clk);stereo_job_valid=0;stereo_job_ready=0;
        check(first_sequence==32'h12345678&&job_count0==1&&job_count1==1&&
            job_page_dfi[223:160]===frozen_dfi[223:160]&&job_page_dfi[127:0]===frozen_dfi[127:0],
            "DFI live job counters advance while first identity/control sample remains frozen");
        @(negedge pixel_clk);physical_event_valid=1;raw_capture1_frame_accept=1;
        @(negedge pixel_clk);physical_event_valid=0;raw_capture1_frame_accept=0;
        check(fs_count0==2&&fs_count1==1&&raw_count0==1&&raw_count1==1&&job_page_pix[223:64]===frozen_pix[223:64],
            "PIX live FS/RAW counters advance while first control sample remains frozen");
        frozen_dfi=job_page_dfi;frozen_pix=job_page_pix;
        @(negedge dfi_clk);pairbank_enable_sync=0;
        @(negedge pixel_clk);enable_pixel=0;
        repeat(4)@(negedge sys_clk);
        check(job_page_dfi===frozen_dfi&&job_page_pix===frozen_pix,"STOP retains both frozen fault pages");
        wire_mark("STOP_STALLED",3);

        // The DFI run can reopen while PIX is stopped. The UART must identify
        // PIX as stale; a later DFI ACK cannot impersonate a PIX capture.
        @(negedge pixel_clk);pix_running=0;
        @(negedge dfi_clk);raw_processing_fault=0;diag_scheduler_state=1;diag_ticket_state=3;diag_ticket_error=0;
        common_dfi_time_ns=64'd230000000;pairbank_enable_sync=1;stereo_job_valid=1;stereo_job_ready=1;
        @(negedge dfi_clk);stereo_job_valid=0;stereo_job_ready=0;
        repeat(3)@(negedge dfi_clk);
        check(job_seen&&job_watch&&!job_stalled&&first_sequence==32'hdeadbeef&&first_generation==32'h55667788&&
            first_session==23&&first_epoch==4&&first_location==1&&job_count0==1&&job_count1==0,
            "DFI new run clears prior freeze and captures new first tuple");
        check(job_page_pix===frozen_pix,"DFI reopen cannot alter stopped PIX capture");
        wire_mark("DFI_REOPEN_PIX_STOPPED",1);
        pix_running=1;
        repeat(5)@(negedge pixel_clk);
        check(job_page_pix===frozen_pix,"resumed PIX keeps STOP sample until its own run reopens");
        wire_mark("PIX_RESUMED_OLD_FREEZE",3);

        @(negedge dfi_clk);stereo_retire_done=1;
        @(negedge dfi_clk);stereo_retire_done=0;
        check(!job_watch&&!job_stalled,"real retire marks DFI first job success without stall");
        @(negedge pixel_clk);common_pixel_time_ns=64'd230000000;enable_pixel=2'b10;
        diag_admission_state=1;diag_ticket_pixel=14;admission_take=1;processed_valid=1;processed_sof=1;
        private_context_fire=1;credit_grant_pixel=1;raw_capture1_frame_accept=1;
        @(negedge pixel_clk);admission_take=0;processed_valid=0;processed_sof=0;private_context_fire=0;raw_capture1_frame_accept=0;
        check(pixel_finished&&!pixel_stalled&&first_admission_state==1&&first_ticket_pixel==14&&raw_count1==1&&fs_count0==0&&fs_count1==0,
            "PIX new run clears freeze and preserves same-edge first admission success");
        frozen_pix=job_page_pix;
        diag_admission_state=5;diag_ticket_pixel=0;processing_context_ready=1;credit_grant_pixel=0;
        repeat(3)@(negedge pixel_clk);
        check(job_page_pix===frozen_pix,"finished PIX first-job sample is immutable");
        wire_mark("NEW_RUN_SUCCESS",3);
        $display("RESULT: PASS TOP_JOB_WATCH checks=%0d uart_rounds=%0d independent_domains=1 stop_retained=1 reopened=1 deadline_elapsed_ns=109440512",
            checks,captured_rounds);
        $fclose(wire_fd);$finish;
    end
    initial begin #3000000;$fatal(1,"TOP first-job observer bounded watchdog");end
endmodule
`default_nettype wire
