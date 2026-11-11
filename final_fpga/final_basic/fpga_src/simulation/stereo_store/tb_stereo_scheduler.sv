`timescale 1ns/1ps
module tb_stereo_scheduler;
    reg  i_stereo_mode=0;
    reg  i_stereo_job_valid=0;
    reg  i_stereo_empty=0;
    reg [383:0] i_stereo_job_frame=0;
    reg [63:0] i_stereo_job_lease=0;
    reg [63:0] i_stereo_job_id=0;
    wire  o_stereo_job_ready;
    wire  o_stereo_retire_valid;
    wire [63:0] o_stereo_retire_job_id;
    reg  i_stereo_retire_ready=0;
    reg  i_stereo_retire_done=0;
    reg  i_stereo_retire_error=0;
    reg  i_identity_rst_n=0;
    reg  i_pair_valid=0;
    reg  i_pair_bank=0;
    reg  i_pair_empty=0;
    reg  i_pair_fault=0;
    reg [63:0] i_pair_id=0;
    wire  o_pair_ready;
    reg  i_pair_config_ready=0;
    reg  i_pair_config_error=0;
    wire  o_pair_config_valid;
    wire  o_pair_release_valid;
    wire  o_pair_release_bank;
    wire [63:0] o_pair_release_id;
    reg  i_pair_release_ready=0;
    wire  o_pair_directory_valid;
    wire [1:0] o_pair_directory_slot;
    reg  i_pair_directory_ready=0;
    reg [31:0] s_pair_directory_data=0;
    reg [3:0] s_pair_directory_word=0;
    reg  s_pair_directory_valid=0;
    reg  s_pair_directory_last=0;
    wire  s_pair_directory_ready;
    reg  i_retire_inhibit=0;
    reg  clk=0;
    reg  rst_n=0;
    reg [63:0] i_now=0;
    reg  i_config_valid=0;
    wire  o_config_ready;
    reg [31:0] i_session=0;
    reg [31:0] i_epoch=0;
    reg [1:0] i_mode=0;
    reg  i_mono_enable=0;
    reg [63:0] i_max_delta=0;
    reg [31:0] i_max_wait=0;
    reg [31:0] i_max_age=0;
    wire  o_config_done;
    wire  o_config_error;
    wire  o_config_busy;
    reg  i_commit_valid=0;
    wire  o_commit_ready;
    reg [383:0] i_descriptor=0;
    reg [63:0] i_lease=0;
    wire  o_commit_done;
    wire  o_commit_error;
    wire  o_commit_duplicate;
    wire  o_ref_valid;
    reg  i_ref_ready=0;
    wire [1:0] o_ref_op;
    wire [1:0] o_ref_mask;
    wire [4:0] o_ref_reason;
    wire  o_ref_cancelled;
    wire [383:0] o_ref_frame0;
    wire [383:0] o_ref_frame1;
    wire [63:0] o_ref_lease0;
    wire [63:0] o_ref_lease1;
    wire [63:0] o_ref_job_id;
    wire  m_member_valid;
    reg  m_member_ready=0;
    wire [383:0] m_member_frame;
    wire [63:0] m_member_lease;
    wire [63:0] m_member_job_id;
    wire [63:0] m_member_pair_id;
    wire  m_member_index;
    wire  o_req_valid;
    reg  i_req_ready=0;
    wire  o_req_private;
    wire [2:0] o_req_op;
    wire  o_req_camera;
    wire [1:0] o_req_slot;
    wire [31:0] o_req_generation;
    wire [31:0] o_req_session;
    wire [31:0] o_req_offset;
    wire [31:0] o_req_length;
    wire [63:0] o_req_lease;
    wire [63:0] o_req_job_id;
    reg  i_rsp_valid=0;
    wire  o_rsp_ready;
    reg [3:0] i_rsp_code=0;
    reg  i_rsp_camera=0;
    reg [1:0] i_rsp_slot=0;
    reg [31:0] i_rsp_generation=0;
    reg [31:0] i_rsp_session=0;
    reg [31:0] i_rsp_sequence=0;
    reg [31:0] i_rsp_epoch=0;
    reg  i_native_done=0;
    reg  i_native_error=0;
    reg [63:0] i_native_job_id=0;
    reg  i_native_member_index=0;
    reg  i_processing_done=0;
    reg  i_processing_error=0;
    reg [63:0] i_processing_job_id=0;
    reg  i_processing_member_index=0;
    reg  i_cancel=0;
    reg  i_read_quiescent=0;
    wire  o_processing_cancel_valid;
    reg  i_processing_cancel_ready=0;
    wire [383:0] o_processing_cancel_frame;
    wire [63:0] o_processing_cancel_lease;
    wire [63:0] o_processing_cancel_job_id;
    wire [63:0] o_processing_cancel_pair_id;
    wire  o_processing_cancel_member_index;
    wire  o_job_valid;
    wire  o_job_ready;
    wire [1:0] o_job_kind;
    wire [63:0] o_job_id;
    wire [63:0] o_pair_id;
    wire [63:0] o_job_lease0;
    wire [63:0] o_job_lease1;
    wire [383:0] o_job_frame0;
    wire [383:0] o_job_frame1;
    wire  o_retire_valid;
    wire  o_retire_ready;
    wire [31:0] o_retire_session;
    wire [63:0] o_retire_job_id;
    wire  o_retire_cancelled;
    wire  o_retire_read_quiescent;
    wire  o_retire_done;
    wire  o_retire_error;
    wire  o_owner_quiescent;
    wire  o_owner_fault;
    wire  o_scheduler_busy;
    wire  o_scheduler_fault;
    wire [3:0] o_error_code;
    wire  o_stale_completion;
    wire  o_busy;
    wire  o_fault;
    wire  o_quiescent;
    reg  i_public_read_quiescent=0;
    reg  i_product_quiescent=0;
    reg  i_hdr_reset_done=0;
    reg  i_hard_fault=0;
    reg  i_hdr_fault=0;
    reg  i_hdr_read_quiescent=0;
    wire  o_hdr_phase_request;
    wire  o_hdr_phase_owned;
    wire  o_hdr_context_valid;
    reg  i_hdr_context_ready=0;
    wire  o_hdr_start_valid;
    reg  i_hdr_start_ready=0;
    wire  o_hdr_cancel_valid;
    reg  i_hdr_cancel_ready=0;
    wire  o_hdr_result_transport_enable;
    reg  i_hdr_result_valid=0;
    reg  i_hdr_result_ready=0;
    reg  i_hdr_result_ok=0;
    reg [7:0] i_hdr_result_error=0;
    wire [63:0] o_hdr_long_tag;
    wire [63:0] o_hdr_short_tag;
    always #5 clk=~clk;
    raw_pair_job_service #(.WIDTH(8),.HEIGHT(4),.STEREO_ENABLE(1)) dut(
        .i_stereo_mode(i_stereo_mode),
        .i_stereo_job_valid(i_stereo_job_valid),
        .i_stereo_empty(i_stereo_empty),
        .i_stereo_job_frame(i_stereo_job_frame),
        .i_stereo_job_lease(i_stereo_job_lease),
        .i_stereo_job_id(i_stereo_job_id),
        .o_stereo_job_ready(o_stereo_job_ready),
        .o_stereo_retire_valid(o_stereo_retire_valid),
        .o_stereo_retire_job_id(o_stereo_retire_job_id),
        .i_stereo_retire_ready(i_stereo_retire_ready),
        .i_stereo_retire_done(i_stereo_retire_done),
        .i_stereo_retire_error(i_stereo_retire_error),
        .i_identity_rst_n(i_identity_rst_n),
        .i_pair_valid(i_pair_valid),
        .i_pair_bank(i_pair_bank),
        .i_pair_empty(i_pair_empty),
        .i_pair_fault(i_pair_fault),
        .i_pair_id(i_pair_id),
        .o_pair_ready(o_pair_ready),
        .i_pair_config_ready(i_pair_config_ready),
        .i_pair_config_error(i_pair_config_error),
        .o_pair_config_valid(o_pair_config_valid),
        .o_pair_release_valid(o_pair_release_valid),
        .o_pair_release_bank(o_pair_release_bank),
        .o_pair_release_id(o_pair_release_id),
        .i_pair_release_ready(i_pair_release_ready),
        .o_pair_directory_valid(o_pair_directory_valid),
        .o_pair_directory_slot(o_pair_directory_slot),
        .i_pair_directory_ready(i_pair_directory_ready),
        .s_pair_directory_data(s_pair_directory_data),
        .s_pair_directory_word(s_pair_directory_word),
        .s_pair_directory_valid(s_pair_directory_valid),
        .s_pair_directory_last(s_pair_directory_last),
        .s_pair_directory_ready(s_pair_directory_ready),
        .i_retire_inhibit(i_retire_inhibit),
        .clk(clk),
        .rst_n(rst_n),
        .i_now(i_now),
        .i_config_valid(i_config_valid),
        .o_config_ready(o_config_ready),
        .i_session(i_session),
        .i_epoch(i_epoch),
        .i_mode(i_mode),
        .i_mono_enable(i_mono_enable),
        .i_max_delta(i_max_delta),
        .i_max_wait(i_max_wait),
        .i_max_age(i_max_age),
        .o_config_done(o_config_done),
        .o_config_error(o_config_error),
        .o_config_busy(o_config_busy),
        .i_commit_valid(i_commit_valid),
        .o_commit_ready(o_commit_ready),
        .i_descriptor(i_descriptor),
        .i_lease(i_lease),
        .o_commit_done(o_commit_done),
        .o_commit_error(o_commit_error),
        .o_commit_duplicate(o_commit_duplicate),
        .o_ref_valid(o_ref_valid),
        .i_ref_ready(i_ref_ready),
        .o_ref_op(o_ref_op),
        .o_ref_mask(o_ref_mask),
        .o_ref_reason(o_ref_reason),
        .o_ref_cancelled(o_ref_cancelled),
        .o_ref_frame0(o_ref_frame0),
        .o_ref_frame1(o_ref_frame1),
        .o_ref_lease0(o_ref_lease0),
        .o_ref_lease1(o_ref_lease1),
        .o_ref_job_id(o_ref_job_id),
        .m_member_valid(m_member_valid),
        .m_member_ready(m_member_ready),
        .m_member_frame(m_member_frame),
        .m_member_lease(m_member_lease),
        .m_member_job_id(m_member_job_id),
        .m_member_pair_id(m_member_pair_id),
        .m_member_index(m_member_index),
        .o_req_valid(o_req_valid),
        .i_req_ready(i_req_ready),
        .o_req_private(o_req_private),
        .o_req_op(o_req_op),
        .o_req_camera(o_req_camera),
        .o_req_slot(o_req_slot),
        .o_req_generation(o_req_generation),
        .o_req_session(o_req_session),
        .o_req_offset(o_req_offset),
        .o_req_length(o_req_length),
        .o_req_lease(o_req_lease),
        .o_req_job_id(o_req_job_id),
        .i_rsp_valid(i_rsp_valid),
        .o_rsp_ready(o_rsp_ready),
        .i_rsp_code(i_rsp_code),
        .i_rsp_camera(i_rsp_camera),
        .i_rsp_slot(i_rsp_slot),
        .i_rsp_generation(i_rsp_generation),
        .i_rsp_session(i_rsp_session),
        .i_rsp_sequence(i_rsp_sequence),
        .i_rsp_epoch(i_rsp_epoch),
        .i_native_done(i_native_done),
        .i_native_error(i_native_error),
        .i_native_job_id(i_native_job_id),
        .i_native_member_index(i_native_member_index),
        .i_processing_done(i_processing_done),
        .i_processing_error(i_processing_error),
        .i_processing_job_id(i_processing_job_id),
        .i_processing_member_index(i_processing_member_index),
        .i_cancel(i_cancel),
        .i_read_quiescent(i_read_quiescent),
        .o_processing_cancel_valid(o_processing_cancel_valid),
        .i_processing_cancel_ready(i_processing_cancel_ready),
        .o_processing_cancel_frame(o_processing_cancel_frame),
        .o_processing_cancel_lease(o_processing_cancel_lease),
        .o_processing_cancel_job_id(o_processing_cancel_job_id),
        .o_processing_cancel_pair_id(o_processing_cancel_pair_id),
        .o_processing_cancel_member_index(o_processing_cancel_member_index),
        .o_job_valid(o_job_valid),
        .o_job_ready(o_job_ready),
        .o_job_kind(o_job_kind),
        .o_job_id(o_job_id),
        .o_pair_id(o_pair_id),
        .o_job_lease0(o_job_lease0),
        .o_job_lease1(o_job_lease1),
        .o_job_frame0(o_job_frame0),
        .o_job_frame1(o_job_frame1),
        .o_retire_valid(o_retire_valid),
        .o_retire_ready(o_retire_ready),
        .o_retire_session(o_retire_session),
        .o_retire_job_id(o_retire_job_id),
        .o_retire_cancelled(o_retire_cancelled),
        .o_retire_read_quiescent(o_retire_read_quiescent),
        .o_retire_done(o_retire_done),
        .o_retire_error(o_retire_error),
        .o_owner_quiescent(o_owner_quiescent),
        .o_owner_fault(o_owner_fault),
        .o_scheduler_busy(o_scheduler_busy),
        .o_scheduler_fault(o_scheduler_fault),
        .o_error_code(o_error_code),
        .o_stale_completion(o_stale_completion),
        .o_busy(o_busy),
        .o_fault(o_fault),
        .o_quiescent(o_quiescent),
        .i_public_read_quiescent(i_public_read_quiescent),
        .i_product_quiescent(i_product_quiescent),
        .i_hdr_reset_done(i_hdr_reset_done),
        .i_hard_fault(i_hard_fault),
        .i_hdr_fault(i_hdr_fault),
        .i_hdr_read_quiescent(i_hdr_read_quiescent),
        .o_hdr_phase_request(o_hdr_phase_request),
        .o_hdr_phase_owned(o_hdr_phase_owned),
        .o_hdr_context_valid(o_hdr_context_valid),
        .i_hdr_context_ready(i_hdr_context_ready),
        .o_hdr_start_valid(o_hdr_start_valid),
        .i_hdr_start_ready(i_hdr_start_ready),
        .o_hdr_cancel_valid(o_hdr_cancel_valid),
        .i_hdr_cancel_ready(i_hdr_cancel_ready),
        .o_hdr_result_transport_enable(o_hdr_result_transport_enable),
        .i_hdr_result_valid(i_hdr_result_valid),
        .i_hdr_result_ready(i_hdr_result_ready),
        .i_hdr_result_ok(i_hdr_result_ok),
        .i_hdr_result_error(i_hdr_result_error),
        .o_hdr_long_tag(o_hdr_long_tag),
        .o_hdr_short_tag(o_hdr_short_tag));
    integer checks=0;
    task check(input bit ok,input string message);
        begin if(!ok)$fatal(1,"%s",message);checks=checks+1;end
    endtask
    task respond(input [3:0] code);
        begin
            @(negedge clk);i_rsp_valid=1;i_rsp_code=code;i_rsp_camera=1;i_rsp_slot=1;
            i_rsp_generation=42;i_rsp_session=17;i_rsp_sequence=20;i_rsp_epoch=3;
            do @(posedge clk);while(!o_rsp_ready);
            @(negedge clk);i_rsp_valid=0;
        end
    endtask
    task take_request(input [2:0] expected_op);
        begin
            wait(o_req_valid);repeat(4)begin @(negedge clk);
                check(o_req_valid&&o_req_op==expected_op&&o_req_camera==1&&o_req_slot==1&&
                    o_req_generation==42&&o_req_session==17&&o_req_lease==42&&o_req_job_id==i_stereo_job_id,"private request identity/stall");
            end
            i_req_ready=1;@(negedge clk);i_req_ready=0;
        end
    endtask
    initial begin
        check(dut.u_scheduler.g_normal_replay.u_normal.BORROW_CONTEXT==1,"production normal scheduler uses borrowed context");
        #100;i_identity_rst_n=1;rst_n=1;i_stereo_mode=1;i_stereo_empty=0;
        i_pair_empty=1;i_hdr_reset_done=1;i_read_quiescent=1;i_public_read_quiescent=1;
        i_product_quiescent=1;i_hdr_read_quiescent=1;
        i_stereo_job_id=64'h800000000000002a;i_stereo_job_lease=42;
        i_stereo_job_frame=0;i_stereo_job_frame[4]=1;i_stereo_job_frame[12:5]=1;
        i_stereo_job_frame[44:13]=42;i_stereo_job_frame[76:45]=17;
        i_stereo_job_frame[108:77]=20;i_stereo_job_frame[140:109]=3;
        i_stereo_job_frame[220:205]=8;i_stereo_job_frame[236:221]=4;i_stereo_job_frame[238:237]=1;
        @(negedge clk);i_stereo_job_valid=1;
        do @(posedge clk);while(!o_stereo_job_ready);
        @(negedge clk);i_stereo_job_valid=0;
        wait(m_member_valid);repeat(4)begin @(negedge clk);
            check(m_member_valid&&m_member_frame==i_stereo_job_frame&&m_member_lease==42&&
                m_member_job_id==i_stereo_job_id&&m_member_pair_id==0&&!m_member_index&&!o_hdr_phase_request,"normal member exact identity");
        end
        m_member_ready=1;@(negedge clk);m_member_ready=0;
        take_request(4);respond(0);
        // Processing completion alone never authorizes the read RETIRE.
        @(negedge clk);i_processing_done=1;i_processing_job_id=i_stereo_job_id;
        @(negedge clk);i_processing_done=0;
        repeat(4)begin @(negedge clk);check(!o_req_valid,"native completion missing");end
        i_native_done=1;i_native_job_id=i_stereo_job_id^64'h100;
        @(negedge clk);i_native_done=0;
        repeat(3)begin @(negedge clk);check(!o_req_valid,"stale native completion");end
        i_native_done=1;i_native_job_id=i_stereo_job_id;
        @(negedge clk);i_native_done=0;
        take_request(5);respond(0);
        wait(o_stereo_retire_valid);
        repeat(5)begin @(negedge clk);check(o_stereo_retire_valid&&o_stereo_retire_job_id==i_stereo_job_id,"held owner retirement");end
        i_stereo_retire_ready=1;@(negedge clk);i_stereo_retire_ready=0;
        repeat(3)begin @(negedge clk);check(o_busy,"ready alone is not retire completion");end
        check(dut.u_scheduler.g_normal_replay.u_normal.state==11,"production owner-response state reached");
        i_stereo_retire_done=1;@(negedge clk);i_stereo_retire_done=0;i_stereo_empty=1;
        repeat(3)@(negedge clk);check(!o_busy&&!o_fault&&o_quiescent,"normal scheduler retired");
        $display("RESULT: PASS STEREO_SCHEDULER checks=%0d",checks);$finish;
    end
    reg context_held=0;reg [511:0] context_snapshot;integer context_hold_checks=0;
    always @(posedge clk)begin
        if(!rst_n)context_held=0;
        else begin
            if(context_held)begin
                check({i_stereo_job_frame,i_stereo_job_lease,i_stereo_job_id}===context_snapshot,
                    "borrowed context stays held through actual OWNER_RESPONSE edge");
                context_hold_checks++;
                if(i_stereo_retire_done)context_held=0;
            end
            if(i_stereo_job_valid&&o_stereo_job_ready)begin
                context_snapshot={i_stereo_job_frame,i_stereo_job_lease,i_stereo_job_id};context_held=1;
            end
        end
    end
    initial begin #100000;$fatal(1,"scheduler watchdog");end
endmodule
