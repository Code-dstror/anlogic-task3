`timescale 1ns/1ps
`default_nettype none
// Control-path isolation: real scheduler, ticket CDC/official FIFO, credit CDC
// and JPEG admission. Owner, DDR, ISP pixels and JPEG arithmetic are BFMs.
module tb_first_job;
    reg dfi_clk=0,pixel_clk=0;
    reg pixel_run=1,dfi_run=1;
    always #5 if(dfi_run)dfi_clk=~dfi_clk;
    initial begin #1;forever begin #3.5;if(pixel_run)pixel_clk=~pixel_clk;end end
    reg identity_reset=0,dfi_reset=0,pixel_reset=0;
    reg armed=0,enabled=0,available=0,claim=0;
    reg [383:0] frame=0;
    reg [63:0] lease=0,job=0;
    reg offer=0,owner_live=0,authority_empty=1;
    reg rgb_valid=0,rgb_sof=0,frame_done=0,start_ready=0,jpeg_ready=0,result_valid=0;
    reg [31:0] result_id=0;
    reg pool_idle=1,processed_source=0,write_valid=0;
    wire job_ready,member_valid,member_ready;
    wire [383:0] member_frame;
    wire [63:0] member_lease,member_job,member_pair;
    wire member_index;
    wire req_valid,rsp_ready;
    wire [2:0] req_op;
    reg req_ready=0,rsp_valid=0;
    reg [2:0] response_op=0;
    integer response_delay=0,response_countdown=-1;
    reg native_done=0,owner_retire_done=0;
    wire retire_valid,retire_quiet;
    wire [63:0] retire_job;
    wire [3:0] scheduler_state,error_code;
    wire scheduler_fault,scheduler_busy,processing_valid,processing_error;
    wire [63:0] processing_job;
    wire processing_member;
    wire owner_hold,recovery,exhausted,source_done,pixel_done,source_fault,pixel_fault;
    wire [2:0] ticket_state;
    wire [7:0] ticket_fault_code;
    wire [383:0] pixel_frame;
    wire [63:0] pixel_lease,pixel_job,pixel_pair,pixel_ticket;
    wire [31:0] write_tag,completed,cancelled,stale_write,stale_native;
    wire pixel_busy,context_owned,context_ready;
    reg context_enable=0;
    wire context_valid=pixel_busy&&!context_owned&&context_enable;
    wire grant,ack,reserved,credit_fault,credit_request,admission_take;
    wire rgb_ready,jpeg_valid,jpeg_sof,start_valid,status_valid,status_ok,admission_idle,admission_boundary,admission_fault;
    wire [31:0] capture_id;
    wire store_start=start_valid&&start_ready;
    integer cases=0,checks=0,admissions=0,source_results=0,claims=0;
    integer case_number=0,trace_fd,positive_cases=0;
    reg positive=1;
    reg [63:0] held_ticket;

    raw_pair_replay_scheduler #(.BORROW_CONTEXT(1)) scheduler(
        .o_stale_completion(),.o_retire_cancelled(),.o_retire_session(),
        .o_processing_cancel_member_index(),.o_processing_cancel_pair_id(),.o_processing_cancel_job_id(),
        .o_processing_cancel_lease(),.o_processing_cancel_frame(),.o_processing_cancel_valid(),
        .o_req_job_id(),.o_req_lease(),.o_req_length(),.o_req_offset(),.o_req_session(),.o_req_generation(),
        .o_req_slot(),.o_req_camera(),.o_req_private(),
        .clk(dfi_clk),.rst_n(dfi_reset),.i_job_valid(offer),.o_job_ready(job_ready),
        .i_job_kind(2'd1),.i_job_id(job),.i_pair_id(64'd0),.i_job_lease0(lease),.i_job_lease1(64'd0),
        .i_job_frame0(frame),.i_job_frame1(384'd0),.m_member_valid(member_valid),.m_member_ready(member_ready),
        .m_member_frame(member_frame),.m_member_lease(member_lease),.m_member_job_id(member_job),
        .m_member_pair_id(member_pair),.m_member_index(member_index),
        .o_req_valid(req_valid),.i_req_ready(req_ready),.o_req_op(req_op),
        .i_rsp_valid(rsp_valid),.o_rsp_ready(rsp_ready),.i_rsp_code(4'd0),
        .i_rsp_camera(frame[4]),.i_rsp_slot(frame[6:5]),.i_rsp_generation(frame[44:13]),
        .i_rsp_session(frame[76:45]),.i_rsp_sequence(frame[108:77]),.i_rsp_epoch(frame[140:109]),
        .i_native_done(native_done),.i_native_error(1'b0),.i_native_job_id(job),.i_native_member_index(1'b0),
        .i_processing_done(processing_valid),.i_processing_error(processing_error),
        .i_processing_job_id(processing_job),.i_processing_member_index(processing_member),.i_cancel(1'b0),
        .i_processing_cancel_ready(1'b0),.o_retire_valid(retire_valid),.i_retire_ready(!owner_hold),
        .o_retire_job_id(retire_job),.o_retire_read_quiescent(retire_quiet),
        .i_retire_done(owner_retire_done),.i_retire_error(1'b0),.o_busy(scheduler_busy),
        .o_fault(scheduler_fault),.o_error_code(error_code),.o_diag_state(scheduler_state));

    raw_pair_processing_context_ticket ticket(
        .o_member_index(),.s_write_ready(),.s_cancel_ready(),.o_source_ticket(),.o_diag_ticket_pixel(),
        .i_identity_rst_n(identity_reset),.i_authority_session(frame[76:45]),
        .i_authority_empty(authority_empty),.i_owner_live(owner_live),.i_read_quiescent(1'b1),.i_write_quiescent(1'b1),
        .o_owner_hold(owner_hold),.o_recovery_required(recovery),.o_ticket_exhausted(exhausted),.o_pixel_ticket(pixel_ticket),
        .i_dfi_clk(dfi_clk),.i_dfi_rst_n(dfi_reset),.i_pixel_clk(pixel_clk),.i_pixel_rst_n(pixel_reset),
        .s_member_valid(member_valid),.s_member_ready(member_ready),.s_member_frame(member_frame),
        .s_member_lease(member_lease),.s_member_job_id(member_job),.s_member_pair_id(member_pair),.s_member_index(member_index),
        .s_cancel_valid(1'b0),.s_cancel_frame(384'd0),.s_cancel_lease(64'd0),.s_cancel_job_id(64'd0),
        .s_cancel_pair_id(64'd0),.s_cancel_index(1'b0),
        .s_write_valid(write_valid),.s_write_tag(write_tag),.s_write_sequence(frame[108:77]),
        .s_write_session(frame[76:45]),.s_write_epoch(frame[140:109]),.s_write_camera(frame[4]),
        .s_write_ok(1'b1),.s_write_error(8'd0),
        .m_processing_valid(processing_valid),.m_processing_ready(1'b1),.m_processing_job_id(processing_job),
        .m_processing_member_index(processing_member),.m_processing_error(processing_error),
        .o_dfi_reset_done(source_done),.o_dfi_fault(source_fault),
        .i_pool_idle(pool_idle),.i_admission_ready(admission_boundary),.i_context_valid(context_valid),
        .o_context_ready(context_ready),.i_context_frame(pixel_frame),.i_context_job_id(pixel_job),
        .i_context_pair_id(pixel_pair),.i_context_member_index(1'b0),.i_context_private(1'b1),
        .i_native_job_start(admission_take),.i_store_start_fire(store_start),.i_pipeline_error(1'b0),
        .i_native_result_valid(processed_source),.i_native_result_error(1'b0),.i_native_result_job_id(pixel_job),
        .i_native_result_member_index(1'b0),.i_native_result_write_tag({32'd0,write_tag}),
        .o_frame(pixel_frame),.o_lease(pixel_lease),.o_job_id(pixel_job),.o_pair_id(pixel_pair),.o_write_tag(write_tag),
        .o_pixel_busy(pixel_busy),.o_context_owned(context_owned),.o_pixel_reset_done(pixel_done),.o_pixel_fault(pixel_fault),
        .o_first_fault_code(ticket_fault_code),.o_stale_write_count(stale_write),.o_completed_count(completed),
        .o_cancelled_count(cancelled),.o_stale_native_count(stale_native),.o_diag_ticket_state(ticket_state));

    single_slot_credit_cdc #(.MULTI_SLOT_ENABLE(1)) credit(
        .i_source_clk(pixel_clk),.i_source_rst_n(pixel_reset),.i_source_request(credit_request),
        .o_source_grant(grant),.o_source_ack(ack),.i_sink_clk(dfi_clk),.i_sink_rst_n(dfi_reset),
        .i_sink_slot_available(available),.i_sink_claim(claim),.o_sink_reserved(reserved),.o_protocol_fault(credit_fault));
    jpeg_frame_admission #(.EXTERNAL_SEQUENCE_ENABLE(1)) admission(
        .o_rgb_buffered(),.o_active(),.o_status_id(),.o_timestamp_ns(),.o_jpeg_eol(),.o_jpeg_luma(),.o_jpeg_rgb(),.o_diag_state(),
        .i_clk(pixel_clk),.i_rst_n(pixel_reset),.i_credit_grant(grant),.i_credit_ack(ack),
        .i_session_armed(armed),.i_app_enable(enabled),.i_fault(1'b0),.o_credit_request(credit_request),
        .o_credit_take(admission_take),.i_rgb_data(96'h0102030405060708090a0b0c),.i_luma(32'd0),
        .i_frame_sequence(frame[108:77]),.i_rgb_valid(rgb_valid),.o_rgb_ready(rgb_ready),
        .i_rgb_sof(rgb_sof),.i_rgb_eol(1'b1),.i_camera_done(frame_done),.i_camera_error(1'b0),
        .o_jpeg_valid(jpeg_valid),.i_jpeg_ready(jpeg_ready),.o_jpeg_sof(jpeg_sof),
        .o_start_valid(start_valid),.i_start_ready(start_ready),.i_time_ns(64'd123),.o_capture_id(capture_id),
        .o_status_valid(status_valid),.i_status_ready(1'b1),.o_status_ok(status_ok),
        .i_result_valid(result_valid),.i_result_ready(1'b1),.i_result_id(result_id),
        .o_protocol_fault(admission_fault),.o_replay_ready_boundary(admission_boundary),.o_state_idle(admission_idle));

    task automatic check(input bit condition,input string why);
        begin checks++;if(!condition)begin snapshot("FAIL");$fatal(1,"FIRST_JOB case=%0d %s",case_number,why);end end
    endtask
    task automatic snapshot(input string event_name);
        begin
            $fdisplay(trace_fd,"case=%0d event=%s time=%0t camera=%b sequence=%0d job=%h ticket=%h scheduler=%0d ticket_state=%0d context_v/r/owned=%b%b%b pool=%b credit_req/ack/grant/reserved=%b%b%b%b admission=%0d error=%h/%h",
                case_number,event_name,$time,frame[4],frame[108:77],job,pixel_ticket,scheduler_state,ticket_state,
                context_valid,context_ready,context_owned,pool_idle,credit_request,ack,grant,reserved,admission.state,
                error_code,ticket_fault_code);$fflush(trace_fd);
        end
    endtask
    always @(posedge dfi_clk)if(dfi_reset)begin
        native_done<=processing_valid;owner_retire_done<=0;
        if(processing_valid)begin source_results++;check(!processing_error,"positive ticket processing result");end
        if(retire_valid&&!owner_hold)begin
            check(retire_quiet&&retire_job==job,"true owner retirement identity/quiet");
            owner_retire_done<=1;
        end
        if(req_valid&&req_ready)begin
            check(response_countdown<0&&!rsp_valid,"one private read transaction at a time");
            response_op<=req_op;response_countdown=response_delay;
        end else if(response_countdown>0)response_countdown=response_countdown-1;
        else if(response_countdown==0)begin rsp_valid<=1;response_countdown=-1;end
        if(rsp_valid&&rsp_ready)rsp_valid<=0;
        if(claim)claims++;
        check(!scheduler_fault&&!source_fault&&!credit_fault,"no source control fault");
    end
    always @(posedge pixel_clk)if(pixel_reset)begin
        if(admission_take)begin admissions++;check(context_owned||!positive,"positive SOF has exact owned context");end
        check(!pixel_fault&&!admission_fault,"no PIX control fault");
    end

    task automatic cold_reset(input integer release_order,input integer phase,input bit arm_early);
        begin
            identity_reset=0;dfi_reset=0;pixel_reset=0;armed=0;enabled=0;available=0;claim=0;
            offer=0;owner_live=0;authority_empty=1;rgb_valid=0;rgb_sof=0;frame_done=0;start_ready=0;
            jpeg_ready=0;result_valid=0;pool_idle=1;processed_source=0;write_valid=0;context_enable=0;
            req_ready=0;rsp_valid=0;native_done=0;owner_retire_done=0;response_countdown=-1;
            #(31+phase);identity_reset=1;
            if(release_order==0)begin dfi_reset=1;#29;pixel_reset=1;end
            else if(release_order==1)begin pixel_reset=1;#31;dfi_reset=1;end
            else begin dfi_reset=1;pixel_reset=1;end
            if(arm_early)begin enabled=1;armed=1;available=1;end
            wait(source_done&&pixel_done&&!recovery);
            @(negedge dfi_clk);check(ticket_state==2&&!owner_hold,"cold recovery completed before owner admission");
        end
    endtask
    task automatic publish_job(input bit camera,input integer sequence_id,input bit stop_pixel);
        begin
            frame=0;frame[4]=camera;frame[44:13]=sequence_id+1;frame[76:45]=17;
            frame[108:77]=sequence_id;frame[140:109]=3;frame[220:205]=4;frame[236:221]=1;frame[238:237]=1;
            lease=64'h100000000+sequence_id;job=64'h200000000+sequence_id;
            @(negedge dfi_clk);owner_live=1;authority_empty=0;offer=1;
            do @(posedge dfi_clk);while(!job_ready);
            @(negedge dfi_clk);offer=0;req_ready=1;context_enable=1;
            if(stop_pixel)begin @(negedge pixel_clk);pixel_run=0;#83;pixel_run=1;end
            wait(pixel_busy);snapshot("TICKET_PUBLISHED");
        end
    endtask
    task automatic finish_product(input integer start_stall,input integer writer_stall);
        begin
            wait(context_owned);held_ticket=pixel_ticket;
            wait(scheduler_state==4);
            @(negedge pixel_clk);pool_idle=0;rgb_valid=1;rgb_sof=1;
            do @(posedge pixel_clk);while(!rgb_ready);
            @(negedge pixel_clk);rgb_valid=0;rgb_sof=0;
            check(start_valid&&capture_id==frame[108:77],"first owned SOF admitted with SOURCE identity");
            repeat(start_stall)@(negedge pixel_clk);
            start_ready=1;
            @(negedge pixel_clk);start_ready=0;jpeg_ready=1;
            do @(posedge pixel_clk);while(!jpeg_valid);
            @(negedge pixel_clk);jpeg_ready=0;frame_done=1;
            @(negedge pixel_clk);frame_done=0;
            wait(status_valid);check(status_ok,"whole positive frame terminal");
            @(negedge pixel_clk);processed_source=1;result_id=capture_id;result_valid=1;
            @(negedge pixel_clk);processed_source=0;result_valid=0;
            wait(admission_idle);pool_idle=1;
            repeat(writer_stall)@(negedge dfi_clk);
            check(pixel_ticket==held_ticket&&owner_hold&&!processing_valid,"late B cannot release current owner");
            claim=1;
            @(negedge dfi_clk);claim=0;write_valid=1;
            @(negedge dfi_clk);write_valid=0;
            wait(completed==1);wait(!scheduler_busy);
            @(negedge dfi_clk);check(!owner_hold&&!pixel_busy&&stale_write==0&&stale_native==0,"exact ticket terminal and release");
            snapshot("COMPLETE");positive_cases++;
        end
    endtask

    initial begin
        trace_fd=$fopen("first_job_trace.txt","w");
        for(integer camera=0;camera<2;camera++)for(integer order=0;order<3;order++)
        for(integer phase=0;phase<4;phase++)for(integer late=0;late<2;late++)begin
            case_number=cases;positive=1;
            cold_reset(order,phase,!late);response_delay=phase*3+late*7;
            publish_job(camera,case_number+1,phase==3);
            // APP/ARM and reserved credit are independent from ticket delivery.
            if(late)begin
                repeat(17)begin @(negedge pixel_clk);check(!context_owned,"no context before real JPEG permission");end
                enabled=1;armed=1;
                repeat(23)begin @(negedge pixel_clk);check(!context_owned,"no-free credit cannot admit context");end
                available=1;
            end else begin enabled=1;armed=1;available=1;end
            finish_product(phase*2+1,late*31+3);cases++;
        end
        // Negative control: reproduce DROP with a deliberately unlicensed SOF.
        // This stimulus violates the private source contract and is not claimed
        // to reproduce the board. Its real matching terminal is withheld first.
        case_number=cases;positive=0;cold_reset(2,2,0);response_delay=0;
        enabled=1;armed=1;
        wait(credit_request);
        @(negedge pixel_clk);rgb_valid=1;rgb_sof=1;
        @(negedge pixel_clk);rgb_valid=0;rgb_sof=0;
        check(admission.state==3,"negative control entered actual DROP");
        publish_job(1,99,0);enabled=1;armed=1;available=1;
        wait(grant&&reserved);
        repeat(47)begin @(negedge pixel_clk);
            check(!context_ready&&!context_owned&&admissions==positive_cases,"DROP holds matched job despite real returned grant");
        end
        snapshot("NEGATIVE_DROP_WITH_GRANT");
        @(negedge pixel_clk);frame_done=1;
        @(negedge pixel_clk);frame_done=0;positive=1;
        finish_product(3,5);cases++;
        check(cases==49&&positive_cases==49&&admissions==49&&source_results==49&&claims==49,"matrix and negative-control coverage");
        $display("RESULT: PASS FIRST_JOB_CONTROL cases=%0d positive_matrix=48 negative_drop=1 checks=%0d admissions=%0d true_write_acks=%0d",cases,checks,admissions,claims);
        $fclose(trace_fd);$finish;
    end
    initial begin #5000000;snapshot("WATCHDOG");$fatal(1,"first job bounded bench watchdog");end
endmodule
`default_nettype wire
