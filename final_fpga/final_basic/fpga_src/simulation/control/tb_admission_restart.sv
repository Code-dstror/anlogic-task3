`timescale 1ns/1ps
module tb_admission_restart;
    reg pixel_clk=0,pixel_rst_n=0;
    always #5 pixel_clk=~pixel_clk;
    reg grant=0,credit_ack=0,armed=1,enable=1,fault=0;
    reg rgb_valid=0,sof=0,done=0,camera_error=0,start_ready=0,jpeg_ready=0;
    reg result_valid=0,status_ready=0;
    reg [31:0] result_id=0,sequence_id=1;
    reg [15:0] job_restart=0;
    wire admission_take,admission_state_idle,rgb_ready,jpeg_valid,jpeg_sof;
    wire start_valid,status_valid,status_ok,protocol_fault;
    wire [31:0] capture_id;
    reg [15:0] admitted_restart,reference_restart;
    integer checks=0,admissions=0,matching_results=0,reset_aborts=0;
    reg owned=0;
    reg [15:0] expected_restart=0;
    `include "actual_restart_latch.vh"
    // Frozen previous contract: only a true SOF admission owns restart_mcus.
    always @(posedge pixel_clk or negedge pixel_rst_n)
        if(!pixel_rst_n)reference_restart<=0;
        else if(admission_take)reference_restart<=job_restart;
    jpeg_frame_admission #(.EXTERNAL_SEQUENCE_ENABLE(1),.SHARED_LUMA_ENABLE(1)) dut (
        .i_clk(pixel_clk),.i_rst_n(pixel_rst_n),.i_credit_grant(grant),
        .i_credit_ack(credit_ack),.i_session_armed(armed),.i_app_enable(enable),.i_fault(fault),
        .o_credit_request(),.o_credit_take(admission_take),
        .i_rgb_data(96'h030201_060504_090807_0c0b0a),.i_luma(32'h04030201),
        .i_frame_sequence(sequence_id),.i_rgb_valid(rgb_valid),.o_rgb_ready(rgb_ready),
        .i_rgb_sof(sof),.i_rgb_eol(1'b1),.i_camera_done(done),.i_camera_error(camera_error),
        .o_jpeg_rgb(),.o_jpeg_luma(),.o_jpeg_valid(jpeg_valid),.i_jpeg_ready(jpeg_ready),
        .o_jpeg_sof(jpeg_sof),.o_jpeg_eol(),.o_start_valid(start_valid),
        .i_start_ready(start_ready),.i_time_ns(64'd123),.o_timestamp_ns(),.o_capture_id(capture_id),
        .o_status_valid(status_valid),.i_status_ready(status_ready),.o_status_id(),.o_status_ok(status_ok),
        .i_result_valid(result_valid),.i_result_ready(1'b1),.i_result_id(result_id),
        .o_protocol_fault(protocol_fault),.o_active(),.o_replay_ready_boundary(),
        .o_rgb_buffered(),.o_state_idle(admission_state_idle));
    task automatic check(input bit condition,input string why);
        begin checks=checks+1;if(!condition)$fatal(1,"RESTART %s",why);end
    endtask
    always @(posedge pixel_clk) begin
        if(!pixel_rst_n)owned=0;
        else if(admission_take)begin
            owned=1;expected_restart=job_restart;admissions=admissions+1;
        end else if(admission_state_idle)owned=0;
        #1;
        if(owned)check(admitted_restart===reference_restart && admitted_restart===expected_restart,
            "actual top latch equals old owned latch through START/RUN/result/credit clear");
    end
    task automatic cycle_noise(input integer cycles);
        for(integer k=0;k<cycles;k=k+1)begin
            @(negedge pixel_clk);job_restart=job_restart+16'h1d3b;
        end
    endtask
    task automatic reset_case;
        begin
            @(negedge pixel_clk);pixel_rst_n=0;rgb_valid=0;sof=0;done=0;camera_error=0;
            start_ready=0;jpeg_ready=0;result_valid=0;status_ready=0;credit_ack=0;grant=0;
            cycle_noise(3);
            @(negedge pixel_clk);pixel_rst_n=1;
            @(negedge pixel_clk);
            check(admission_state_idle&&!protocol_fault,"reset returns actual admission owner to IDLE");
        end
    endtask
    task automatic begin_frame(input [15:0] restart,input bit same_edge_done);
        begin
            wait(admission_state_idle);
            @(negedge pixel_clk);grant=1;credit_ack=1;job_restart=restart;
            rgb_valid=1;sof=1;done=same_edge_done;
            #1;check(admission_take,"real same-edge SOF admission");
            @(negedge pixel_clk);rgb_valid=0;sof=0;done=0;grant=0;
            check(start_valid,"reserved first group enters START");
        end
    endtask
    task automatic complete_frame(input bit bad_camera,input bit wrong_result);
        integer guard;
        begin
            cycle_noise(5);check(start_valid&&!jpeg_valid,"START stall retains first group ownership");
            start_ready=1;
            @(negedge pixel_clk);start_ready=0;
            cycle_noise(7);check(jpeg_valid&&jpeg_sof,"encoder SOF remains stable under downstream stall");
            jpeg_ready=1;
            @(negedge pixel_clk);jpeg_ready=0;done=1;camera_error=bad_camera;
            @(negedge pixel_clk);done=0;camera_error=0;
            guard=0;
            while(!status_valid&&guard<20)begin @(negedge pixel_clk);guard=guard+1;end
            check(guard<20 && status_ok==!bad_camera,"actual camera terminal status, including failed frame");
            status_ready=1;
            @(negedge pixel_clk);status_ready=0;
            cycle_noise(4);
            if(wrong_result)begin
                result_id=capture_id+1;result_valid=1;
                @(negedge pixel_clk);result_valid=0;
                check(protocol_fault,"wrong result identity is rejected without retiring current payload");
                cycle_noise(3);
            end
            result_id=capture_id;result_valid=1;
            @(negedge pixel_clk);result_valid=0;matching_results=matching_results+1;
            cycle_noise(5);check(!admission_state_idle,"matching result waits for old credit ACK to clear");
            credit_ack=0;
            @(negedge pixel_clk);
            check(admission_state_idle,"credit retirement releases owner");
            sequence_id=sequence_id+1;
        end
    endtask
    initial begin
        reset_case();
        begin_frame(16'h0064,0);complete_frame(0,0);
        begin_frame(16'hffff,1);complete_frame(0,0);
        begin_frame(16'h8001,0);complete_frame(1,0);
        begin_frame(16'h1234,0);complete_frame(0,1);
        reset_case();
        begin_frame(16'h0000,0);complete_frame(0,0);
        begin_frame(16'habcd,0);cycle_noise(4);reset_aborts=reset_aborts+1;reset_case();
        begin_frame(16'h0ff0,0);complete_frame(0,0);
        begin_frame(16'h5aa5,0);start_ready=1;
        @(negedge pixel_clk);start_ready=0;jpeg_ready=1;
        @(negedge pixel_clk);jpeg_ready=0;reset_aborts=reset_aborts+1;reset_case();
        begin_frame(16'hbeef,0);complete_frame(1,0);
        check(admissions==9 && matching_results==7 && reset_aborts==2,"all required ownership scenarios exercised");
        $display("RESULT: PASS ADMISSION_RESTART checks=%0d admissions=%0d matching_results=%0d reset_aborts=%0d",
            checks,admissions,matching_results,reset_aborts);$finish;
    end
    initial begin #100000;$fatal(1,"admission restart watchdog");end
endmodule
