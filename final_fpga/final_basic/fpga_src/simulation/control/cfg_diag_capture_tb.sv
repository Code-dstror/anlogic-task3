`timescale 1ns/1ps
module cfg_diag_capture_tb;
    reg clk=0;always #5 clk=~clk;
    reg cold=0,app=0;
    reg prepare=0,commit=0,commit_last=0,present=0,copy_start=0,copy_done=0,taken=0,published=0,mismatch=0;
    reg [31:0] session=32'h100,request_sequence=32'h200,target_epoch=32'h300;
    reg [31:0] pub_epoch=0,pub_first=0;
    wire [223:0] user_data,pixel_data;
    cfg_diag_user user_capture(.i_clk(clk),.i_observer_rst_n(cold),.i_app_rst_n(app),
        .i_prepare_start(prepare),.i_commit_accepted(commit),.i_commit_last_sent(commit_last),
        .i_applied_present(present),.i_copy_started(copy_start),.i_copy_complete(copy_done),
        .i_applied_taken(taken),.i_published(published),.i_reply_mismatch(mismatch),
        .i_session(session),.i_request_sequence(request_sequence),.i_target_epoch(target_epoch),
        .i_published_epoch(pub_epoch),.i_published_first_sequence(pub_first),.i_live_flags(32'h10000),.o_data(user_data));
    reg remote_sent=0,positive=0,negative=0,unmatched=0,frame=0,apply=0,applied_last=0,source_fs=0;
    reg [31:0] frame_sequence=0;
    reg [2:0] frame_gates=0;
    reg [15:0] source_gates=0;
    cfg_diag_pixel pixel_capture(.i_clk(clk),.i_observer_rst_n(cold),.i_app_rst_n(app),
        .i_commit_accepted(commit),.i_session(session),.i_request_sequence(request_sequence),.i_target_epoch(target_epoch),
        .i_remote_sent(remote_sent),.i_positive_ack(positive),.i_negative_ack(negative),.i_unmatched_ack(unmatched),
        .i_frame_accept(frame),.i_apply_frame(apply),.i_applied_last_sent(applied_last),
        .i_frame_sequence(frame_sequence),.i_live_flags(32'h10000),.i_frame_gates(frame_gates),
        .i_source_fs(source_fs),.i_source_gates(source_gates),.o_data(pixel_data));
    wire [31:0] uf=user_data[191:160],pf=pixel_data[191:160];
    integer checks=0;
    reg [223:0] held;
    task check(input bit ok,input string why);
        begin checks=checks+1;if(!ok)$fatal(1,"CFG capture: %s",why);end
    endtask
    task step;
        begin @(posedge clk);#1;@(negedge clk);end
    endtask
    task pulse_prepare;
        begin prepare=1;step();prepare=0;end
    endtask
    task pulse_commit;
        begin commit=1;step();commit=0;end
    endtask
    initial begin
        repeat(3)step();cold=1;step();
        check(!uf[0]&&!pf[0],"cold reset invalidates both identities");
        app=1;step();check(user_data[207:192]==1&&pixel_data[207:192]==1,"first release increments local generation");
        present=1;taken=1;published=1;positive=1;frame=1;apply=1;step();
        check(uf[7:0]==0&&pf[7:0]==0,"unowned events cannot invent request or COMMIT");
        present=0;taken=0;published=0;positive=0;frame=0;apply=0;
        pulse_prepare();
        check(user_data[95:0]=={target_epoch,request_sequence,session}&&uf[7:0]==1,"USER identity comes from new request");
        check(!pf[0],"USER request does not invent PIX acceptance");
        pulse_commit();
        check(pixel_data[95:0]=={target_epoch,request_sequence,session}&&pf[7:0]==1,"PIX checked COMMIT opens its separate window");
        check(uf[1],"USER commit accepted");
        session=session+1;request_sequence=request_sequence+1;target_epoch=target_epoch+1;
        step();check(user_data[31:0]==32'h100&&pixel_data[31:0]==32'h100,"live identity noise cannot rebind existing windows");
        unmatched=1;negative=1;frame=1;source_fs=1;source_gates=16'ha5a5;frame_sequence=32'h1111;step();
        check(pf[4:3]==3&& !pf[5]&&!pf[24],"unmatched/negative ACKs cannot qualify first SOF/source FS");
        unmatched=0;negative=0;remote_sent=1;positive=1;frame_gates=3'b101;source_gates=16'h5a3c;frame_sequence=32'h2222;
        step();remote_sent=0;positive=0;
        check(pf[2:1]==3&&pf[5]&&pf[10:8]==5&&pixel_data[127:96]==32'h2222,"same-edge positive ACK and SOF captures exact first tuple");
        check(pf[24]&&pixel_data[223:208]==16'h5a3c,"first physical FS gates use one same-edge sample");
        frame_gates=2;source_gates=16'hdead;frame_sequence=32'h3333;apply=1;step();
        check(pixel_data[127:96]==32'h2222&&pf[10:8]==5&&pixel_data[223:208]==16'h5a3c,"later source/SOF events cannot overwrite first snapshots");
        check(pf[6]&&pixel_data[159:128]==32'h3333&&!pf[7],"apply frame is separate from APPLIED final send");
        applied_last=1;frame_sequence=32'h4444;step();apply=0;applied_last=0;frame=0;source_fs=0;
        check(pf[7]&&pixel_data[159:128]==32'h3333,"apply sequence retained through later APPLIED final send");
        commit_last=1;present=1;copy_start=1;step();commit_last=0;present=0;copy_start=0;
        check(uf[4:1]==4'b1111&&!uf[6]&&!uf[7],"USER observed APPLIED and copy start do not imply take or publication");
        copy_done=1;step();copy_done=0;
        check(uf[5]&&!uf[6]&&!uf[7],"copy complete remains independent");
        taken=1;step();taken=0;check(uf[6]&&!uf[7],"USER final APPLIED handshake precedes publication");
        published=1;mismatch=1;pub_epoch=32'h1234;pub_first=32'h5678;step();published=0;mismatch=0;
        check(uf[7]&&uf[13]&&user_data[159:96]==64'h0000567800001234,"published words and reply mismatch exported");
        pulse_prepare();
        check(uf[7:0]==1&&!uf[13]&&pf[7:0]==8'hff,"next USER request clears only USER milestones, old PIX remains distinct");
        check(user_data[31:0]==32'h101&&pixel_data[31:0]==32'h100,"new USER and old PIX identity not merged");
        pulse_commit();
        check(pf[7:0]==1&&!pf[24]&&pf[10:8]==0&&pixel_data[159:96]==0&&pixel_data[223:208]==0,"next PIX COMMIT clears all old event snapshots");
        app=0;step();check(!uf[0]&&!pf[0]&&user_data[95:0]==0&&pixel_data[159:0]==0,"business reset invalidates owned transaction evidence");
        app=1;step();check(user_data[207:192]==2&&pixel_data[207:192]==2,"business reset release increments each generation");
        cold=0;step();check(user_data[207:192]==0&&pixel_data[207:192]==0,"cold reset clears generation");
        $display("RESULT: PASS cfg_diag_capture checks=%0d",checks);$finish;
    end
    initial begin #100000;$fatal(1,"CFG capture watchdog");end
endmodule
