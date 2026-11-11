`timescale 1ns/1ps
`default_nettype none
// Actual physical crop + elastic ISP boundary + wide ISP. No forced internal
// VALID, READY, idle or job state. Pixels are a legal 8x3 synthetic RAW source.
module tb_live_gate #(parameter integer EXPECT_LEAK=0);
    reg clk=0,rst=0,enable=0,pause_job=0,rgb_ready=1;
    always #5 clk=~clk;
    reg [39:0] raw=0;
    reg raw_valid=0,raw_sof=0,raw_eol=0,raw_abort=0,allow_error=0;
    wire raw_ready,job_start,job_idle,job_replay,rgb_valid,rgb_sof,rgb_eol,done,error;
    wire [95:0] rgb;
    integer starts=0,disabled_starts=0,frames=0,beats=0,checks=0,errors=0;
    reg held=0,input_held=0;reg [97:0] held_rgb;reg [57:0] held_raw;
    integer input_hold_checks=0;
    physical_camera_rgb_pipeline #(.WIDTH(8),.HEIGHT(3),.FIRST_ROW(0),.FIRST_GROUP(0),
        .RGB_TAP(1),.RAW_REPLAY_ENABLE(1),.RAW_REPLAY_SAMPLE_BITS(14),.SHARED_WIDE_ISP_ENABLE(1),
        .JOB_CONTROL_ENABLE(1),.SEPARATE_REPLAY_JOB_CONTROL(1),.CONTROLLED_ABORT_ENABLE(1),
        .CONTROLLED_REPLAY_ABORT_ENABLE(1),.GAMMA_BYPASS(1)) dut(
        .i_clk(clk),.i_rst_n(rst),.i_processing_reset_n(rst),.i_bayer_phase(2'd0),.i_wb_gains({3{10'd256}}),
        .i_job_enable(enable),.i_job_pause(pause_job),.i_replay_job_enable(1'b0),.i_replay_job_pause(1'b0),
        .o_job_start(job_start),.o_job_idle(job_idle),.o_job_replay(job_replay),
        .i_raw_data(raw),.i_raw_valid(raw_valid),.o_raw_ready(raw_ready),.i_raw_sof(raw_sof),
        .i_raw_sequence(32'd1),.i_raw_identity_valid(1'b1),.i_raw_eol(raw_eol),.i_raw_abort(raw_abort),
        .o_axis_tdata(),.o_axis_tkeep(),.o_axis_tvalid(),.i_axis_tready(1'b1),.o_axis_tlast(),
        .o_frame_error(error),.o_frame_done(done),.o_rgb_tdata(rgb),.o_rgb_tvalid(rgb_valid),
        .i_rgb_tready(rgb_ready),.o_rgb_tuser(rgb_sof),.o_rgb_tlast(rgb_eol),
        .o_cropped_raw_data(),.o_cropped_raw_valid(),.o_cropped_raw_ready(),.i_cropped_raw_ready(1'b1),
        .o_cropped_raw_sof(),.o_cropped_raw_eol(),.o_cropped_raw_abort(),.o_cropped_raw_sequence(),.o_cropped_raw_identity_valid(),
        .i_replay_active(1'b0),.i_replay_data(56'd0),.i_replay_hdr_enable(1'b0),.i_replay_tone_shift(4'd0),
        .i_replay_valid(1'b0),.i_replay_sof(1'b0),.i_replay_eol(1'b0),.i_replay_abort(1'b0),.o_replay_ready(),.o_replay_safe(),
        .i_external_rgb_data(96'd0),.i_external_rgb_valid(1'b0),.o_external_rgb_ready(),.i_external_rgb_sof(1'b0),
        .i_external_rgb_eol(1'b0),.i_external_rgb_abort(1'b0));
    task automatic check(input bit condition,input string why);
        begin checks++;if(!condition)$fatal(1,"LIVE_GATE %s starts=%0d disabled=%0d frames=%0d",why,starts,disabled_starts,frames);end
    endtask
    always @(posedge clk)if(!rst)begin held<=0;input_held<=0;end else begin
        if(job_start)begin
            starts++;
            if(!enable||pause_job)begin
                disabled_starts++;
                $display("LIVE_GATE_DISABLED_START t=%0t idle=%b selected_valid=%b input_valid=%b raw_ready=%b enable=%b pause=%b",
                    $time,dut.g_internal_isp.isp_job_idle,dut.g_internal_isp.selected_valid,
                    dut.g_internal_isp.wide.input_valid,raw_ready,enable,pause_job);
            end
        end
        if(rgb_valid&&rgb_ready)begin beats++;if(rgb_sof)frames++;end
        if(held)check(rgb_valid&&{rgb_eol,rgb_sof,rgb}===held_rgb,"existing RGB promise changed under stall");
        held<=rgb_valid&&!rgb_ready;held_rgb<={rgb_eol,rgb_sof,rgb};
        if(input_held)begin
            check(dut.g_internal_isp.wide.input_valid&&
                {dut.g_internal_isp.wide.input_eol,dut.g_internal_isp.wide.input_sof,dut.g_internal_isp.wide.input_data}===held_raw,
                "already accepted RAW elastic promise changed under ISP stall");
            input_hold_checks++;
        end
        input_held<=dut.g_internal_isp.wide.input_valid&&!dut.g_internal_isp.wide.core_input_ready;
        held_raw<={dut.g_internal_isp.wide.input_eol,dut.g_internal_isp.wide.input_sof,dut.g_internal_isp.wide.input_data};
        if(error)begin errors++;check(allow_error,"unexpected input abort/error");end
    end
    task automatic frame(input integer pattern,input integer gate_change);
        begin
            for(integer row=0;row<3;row++)for(integer group=0;group<2;group++)begin
                @(negedge clk);raw={10'(200+pattern),10'(300+pattern),10'(400+pattern),10'(500+pattern)};
                raw_valid=1;raw_sof=row==0&&group==0;raw_eol=group==1;
                do @(posedge clk);while(!raw_ready);
                if(row==0&&group==0&&gate_change!=0)begin
                    @(negedge clk);
                    raw_valid=0;raw_sof=0;raw_eol=0;
                    if(gate_change==1)enable=0;else pause_job=1;
                end
            end
            @(negedge clk);raw_valid=0;raw_sof=0;raw_eol=0;
        end
    endtask
    initial begin
        repeat(5)@(negedge clk);rst=1;wait(job_idle);
        frame(0,0);frame(1,0);repeat(50)@(negedge clk);
        check(starts==0&&frames==0,"idle disabled physical frames never reach ISP/JPEG");
        enable=1;rgb_ready=0;frame(2,0);wait(rgb_valid&&rgb_sof);
        check(!job_idle&&starts==1,"real first job retained while its RGB SOF stalls");
        @(negedge clk);enable=0;
        fork
            frame(3,0);
            begin repeat(35)@(negedge clk);rgb_ready=1;end
        join
        wait(job_idle);repeat(20)@(negedge clk);
        check(disabled_starts==EXPECT_LEAK&&starts==1+EXPECT_LEAK&&frames==1+EXPECT_LEAK,
            "disabled new frame either blocked (candidate) or detected (frozen negative control)");
        enable=1;frame(4,0);wait(job_idle);repeat(20)@(negedge clk);
        check(starts==2+EXPECT_LEAK&&frames==2+EXPECT_LEAK&&beats==(2+EXPECT_LEAK)*6,
            "old frame drains intact and later enabled frame recovers without reset");
        // Gate changes after the actual RAW SOF cannot withdraw that frame's
        // admitted remaining RAW/RGB tail. They apply at the next SOF only.
        frame(5,1);wait(job_idle);repeat(10)@(negedge clk);
        check(starts==3+EXPECT_LEAK&&frames==3+EXPECT_LEAK&&beats==(3+EXPECT_LEAK)*6,
            "enable falling mid-frame preserves the complete owned tail");
        enable=1;frame(6,2);wait(job_idle);repeat(10)@(negedge clk);pause_job=0;
        check(starts==4+EXPECT_LEAK&&frames==4+EXPECT_LEAK&&beats==(4+EXPECT_LEAK)*6,
            "pause rising mid-frame preserves the complete owned tail");
        // A real late source ABORT is reported while already presented RGB
        // remains owned. The production controlled-abort reset is withheld
        // until that existing tail drains, exactly as its caller requires.
        rgb_ready=0;frame(7,0);wait(rgb_valid&&rgb_sof);
        @(negedge clk);allow_error=1;raw_abort=1;raw_valid=1;
        do @(posedge clk);while(!raw_ready);
        @(negedge clk);raw_abort=0;raw_valid=0;
        repeat(7)@(negedge clk);check(errors==1&&rgb_valid,"ABORT reports once without clearing held RGB");
        rgb_ready=1;wait(job_idle);repeat(10)@(negedge clk);allow_error=0;
        frame(8,0);wait(job_idle);repeat(10)@(negedge clk);
        check(starts==6+EXPECT_LEAK&&frames==6+EXPECT_LEAK&&beats==(6+EXPECT_LEAK)*6,
            "late source failure and next legal frame retain exact complete tails");
        // A genuine cohort reset may cancel the held work. It must isolate
        // VALID immediately and never leak that old SOF after release.
        rgb_ready=0;frame(9,0);wait(rgb_valid&&rgb_sof);
        @(negedge clk);rst=0;#1;check(!rgb_valid,"cohort reset isolates held RGB VALID");
        repeat(5)@(negedge clk);rst=1;rgb_ready=1;wait(job_idle);
        repeat(7)@(negedge clk);check(!rgb_valid,"old held SOF does not return after reset");
        frame(10,0);wait(job_idle);repeat(10)@(negedge clk);
        check(starts==8+EXPECT_LEAK&&frames==7+EXPECT_LEAK&&beats==(7+EXPECT_LEAK)*6,
            "fresh cohort starts cleanly after cancelled held work");
        // Conversely, once a legal new SOF has entered the RAW elastic
        // register while the previous ISP tail is held, a later disable must
        // preserve that accepted SOF and its remaining frame through stall.
        rgb_ready=0;enable=1;frame(11,0);wait(rgb_valid&&rgb_sof);
        fork
            frame(12,1);
            begin repeat(35)@(negedge clk);rgb_ready=1;end
        join
        wait(job_idle);repeat(10)@(negedge clk);
        check(starts==10+EXPECT_LEAK&&frames==9+EXPECT_LEAK&&beats==(9+EXPECT_LEAK)*6&&input_hold_checks>0,
            "accepted elastic RAW SOF and full tail survive later disable and ISP stall");
        $display("RESULT: PASS LIVE_GATE expect_leak=%0d starts=%0d disabled=%0d frames=%0d beats=%0d raw_hold_checks=%0d checks=%0d",
            EXPECT_LEAK,starts,disabled_starts,frames,beats,input_hold_checks,checks);$finish;
    end
    initial begin #200000;$fatal(1,"live gate bounded bench watchdog");end
endmodule
`default_nettype wire
