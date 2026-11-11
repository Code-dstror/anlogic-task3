`timescale 1ns/1ps
module tb_owner_order;
    reg clk=0,rst=0,enable=1,stop=0;
    always #5 clk=~clk;
    reg [383:0] frame=0;
    reg begin_valid=0,camera=0,job_ready=0,retire_valid=0,quiet=1;
    reg [1:0] finish_valid=0,finish_ok=3;
    reg [63:0] retire_id=0;
    wire begin_ready,accepted,job_valid,retire_ready,retire_done,retire_error,empty,fault;
    wire [1:0] slot,finish_ready;
    wire [383:0] job_frame;
    wire [63:0] lease,job_id;
    wire [31:0] dropped;
    stereo_raw_owner #(.WIDTH(16),.HEIGHT(2)) dut(
        .clk(clk),.rst_n(rst),.i_enable(enable),.i_stop(stop),.i_session(32'd7),.i_epoch(32'd9),
        .s_frame(frame),.s_begin_valid(begin_valid),.i_begin_camera(camera),.s_begin_ready(begin_ready),
        .o_begin_accepted(accepted),.o_capture_slot(slot),.i_finish_valid(finish_valid),
        .i_finish_ok(finish_ok),.o_finish_ready(finish_ready),.o_job_valid(job_valid),.i_job_ready(job_ready),
        .o_job_frame(job_frame),.o_job_lease(lease),.o_job_id(job_id),.o_job_bayer(),.o_job_time_valid(),
        .i_retire_valid(retire_valid),.i_retire_job_id(retire_id),.i_release_quiet(quiet),
        .o_retire_ready(retire_ready),.o_retire_done(retire_done),.o_retire_error(retire_error),
        .o_empty(empty),.o_job_owned(),.o_fault(fault),.o_dropped(dropped));
    integer checks=0,phase=0,inversions=0;
    task check(input bit condition,input string message);
        begin checks++;if(!condition)$fatal(1,"OWNER phase=%0d %s",phase,message);end
    endtask
    task reset_all;
        begin @(negedge clk);rst=0;begin_valid=0;finish_valid=0;job_ready=0;retire_valid=0;stop=0;enable=1;quiet=1;
            repeat(5)@(negedge clk);rst=1;repeat(5)@(negedge clk);end
    endtask
    task automatic reserve(input bit eye,input [31:0] seq);
        begin
            @(negedge clk);camera=eye;frame=0;
            frame[4]=eye;frame[76:45]=7;frame[108:77]=seq;frame[140:109]=9;
            frame[220:205]=16;frame[236:221]=2;frame[238:237]=1;frame[370]=1;frame[371]=1;
            begin_valid=1;
            do @(posedge clk);while(!begin_ready);
            check(accepted,"legal BEGIN accepted");
            @(negedge clk);begin_valid=0;
        end
    endtask
    task automatic finish(input bit eye,input bit ok);
        begin @(negedge clk);finish_valid[eye]=1;finish_ok[eye]=ok;
            do @(posedge clk);while(!finish_ready[eye]);
            @(negedge clk);finish_valid[eye]=0;end
    endtask
    task automatic await_job(input bit eye,input [31:0] seq);
        begin wait(job_valid);@(negedge clk);
            check(job_frame[4]==eye&&job_frame[108:77]==seq,"exact expected oldest job");
            check(job_id==(64'h8000000000000000|lease)&&lease!=0,"exact nonzero job lease");end
    endtask
    task consume;
        begin @(negedge clk);job_ready=1;@(negedge clk);job_ready=0;end
    endtask
    task retire;
        begin wait(retire_ready);@(negedge clk);retire_id=job_id;retire_valid=1;
            @(negedge clk);check(retire_done&&!retire_error,"matching retire completes");retire_valid=0;end
    endtask
    reg [447:0] held;
    integer n,e;
    initial begin
        // Same legal two-slot trace as the observed 10 -> 12 -> 11 defect.
        // Swap the eyes so fairness and ordering are independently exercised.
        for(e=0;e<2;e=e+1)begin
            phase=e+1;reset_all();reserve(e,10);finish(e,1);await_job(e,10);
            reserve(e,11);consume();retire();
            reserve(!e,50);finish(!e,1);await_job(!e,50);
            finish(e,1);reserve(e,12);finish(e,1);consume();retire();
            wait(job_valid);@(negedge clk);
            if(job_frame[108:77]!=11)begin
                inversions++;
                $display("COUNTEREXAMPLE eye=%0d expected=11 got=%0d",e,job_frame[108:77]);
`ifndef CANDIDATE
                consume();retire();await_job(e,11);consume();retire();
`else
                $fatal(1,"same-eye newer slot overtook older slot");
`endif
            end else begin consume();retire();await_job(e,12);consume();retire();end
            repeat(8)@(negedge clk);check(empty&&!fault&&dropped==0,"real transactions drained without drop/fault");
        end
`ifndef CANDIDATE
        check(inversions==2,"baseline negative control exposes both eyes");
        $display("RESULT: PASS OWNER_BASELINE_NEGATIVE checks=%0d inversions=%0d",checks,inversions);
        $finish;
`endif
        phase=3;reset_all();
        // A failed older capture disappears without clearing its later reuse.
        reserve(0,32'hfffffffe);finish(0,1);await_job(0,32'hfffffffe);
        held={job_frame,job_id};stop=1;
        repeat(9)begin @(negedge clk);check(job_valid&&{job_frame,job_id}===held,"offer stable through STOP and stall");end
        consume();quiet=0;retire_valid=1;retire_id=job_id;
        repeat(4)begin @(negedge clk);check(!retire_ready&&!retire_done,"quiet is a real retirement prerequisite");end
        retire_valid=0;quiet=1;
        @(negedge clk);retire_id=job_id+1;retire_valid=1;
        @(negedge clk);check(retire_done&&retire_error,"wrong identity reports error");retire_valid=0;
        check(!empty,"wrong identity cannot free slot");retire();stop=0;
        reserve(0,32'hffffffff);finish(0,0);
        reserve(0,0);finish(0,1);await_job(0,0);consume();retire();
        phase=4;
        // Many directory clear/reuse generations, held offers, finite stalls,
        // negative FINISH and sequence wrap. Only successful BEGIN age matters.
        for(n=0;n<48;n=n+1)begin
            reserve(n[0],n-4);
            finish(n[0],n%9!=4);
            if(n%9!=4)begin
                await_job(n[0],n-4);held={job_frame,job_id};
                repeat(n%5)begin @(negedge clk);check(job_valid&&{job_frame,job_id}===held,"held identity stable");end
                consume();retire();
            end
        end
        repeat(9)@(negedge clk);check(empty&&!fault&&dropped==0,"all generations drained");
        phase=5;
        reserve(1,200);finish(1,1);await_job(1,200);consume();
        reserve(0,100);finish(0,1);
        // The younger slot is live before its directory/BEGIN ACK finishes.
        // Selecting the eye head during that window must still choose 100.
        fork
            reserve(0,101);
            begin wait(dut.begin_state==1&&dut.word_index==3);retire();end
        join
        await_job(0,100);finish(0,1);consume();retire();
        await_job(0,101);consume();retire();
        phase=6;reserve(0,90);finish(0,1);await_job(0,90);reserve(1,91);
        reset_all();check(empty&&!fault,"coordinated reset cancels outstanding ownership");
        $display("RESULT: PASS OWNER_ORDER checks=%0d inversions=%0d",checks,inversions);$finish;
    end
    initial begin #2000000;$fatal(1,"OWNER timeout phase=%0d",phase);end
endmodule
