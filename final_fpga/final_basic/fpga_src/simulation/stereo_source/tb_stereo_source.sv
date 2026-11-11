`timescale 1ns/1ps
module tb_stereo_source;
    localparam W=16,H=2,G=W/4,COUNT=G*H;
    reg clk=0;always #5 clk=~clk;
    reg [1:0] rst_n=0,enable=3,time_valid=3,valid=0,accept=3,sof=0,eol=0,abort_in=0;
    reg [1:0] identity=3,event_valid=0,event_ok=3,event_identity=3,receive_fault=0,quarantine=0,source_ready=3;
    reg [31:0] session_id[0:1],epoch[0:1],sequence_id[0:1],event_sequence[0:1];
    reg [63:0] timestamp[0:1],expected_time[0:1];
    reg [31:0] expected_session[0:1],expected_epoch[0:1];
    reg [39:0] data[0:1];
    reg [1:0] event_kind[0:1];
    reg [3:0] event_error[0:1];
    wire [1:0] event_ready,capture_valid,capture_accept,capture_sof,capture_eol,capture_abort,geometry_done;
    wire [1:0] source_valid,source_camera,source_ok,idle,fault;
    wire [39:0] capture_data[0:1];
    wire [196:0] metadata[0:1];
    wire [31:0] capture_session[0:1],capture_epoch[0:1],capture_sequence[0:1];
    wire [31:0] source_session[0:1],source_epoch[0:1],source_sequence[0:1];
    wire [7:0] source_error[0:1];
    generate for(genvar c=0;c<2;c++)begin:eye
        stereo_capture_source4 #(.CAMERA_ID(c),.WIDTH(W),.HEIGHT(H)) dut(
            .clk(clk),.rst_n(rst_n[c]),.i_data_reset_n(rst_n[c]),.i_enable(enable[c]),.i_session(session_id[c]),.i_epoch(epoch[c]),
            .i_time_ns(timestamp[c]),.i_time_valid(time_valid[c]),.i_data(data[c]),
            .i_valid(valid[c]),.i_accept(accept[c]),.i_sof(sof[c]),.i_eol(eol[c]),.i_abort(abort_in[c]),
            .i_sequence(sequence_id[c]),.i_identity_valid(identity[c]),
            .i_event_valid(event_valid[c]),.o_event_ready(event_ready[c]),.i_event_kind(event_kind[c]),
            .i_event_ok(event_ok[c]),.i_event_error(event_error[c]),.i_event_sequence(event_sequence[c]),
            .i_event_identity_valid(event_identity[c]),.i_receive_fault(receive_fault[c]),.i_identity_quarantine(quarantine[c]),
            .o_capture_data(capture_data[c]),.o_capture_valid(capture_valid[c]),.o_capture_accept(capture_accept[c]),
            .o_capture_sof(capture_sof[c]),.o_capture_eol(capture_eol[c]),.o_capture_abort(capture_abort[c]),
            .o_capture_geometry_done(geometry_done[c]),.o_capture_session(capture_session[c]),
            .o_capture_epoch(capture_epoch[c]),.o_capture_sequence(capture_sequence[c]),.o_capture_metadata(metadata[c]),
            .o_raw_source_valid(source_valid[c]),.i_raw_source_ready(source_ready[c]),
            .o_raw_source_session(source_session[c]),.o_raw_source_epoch(source_epoch[c]),
            .o_raw_source_sequence(source_sequence[c]),.o_raw_source_camera(source_camera[c]),
            .o_raw_source_ok(source_ok[c]),.o_raw_source_error(source_error[c]),.o_idle(idle[c]),.o_fault(fault[c]));
    end endgenerate
    integer checks=0,phase=0;
    integer captured[0:1],good[0:1],bad[0:1],geometries[0:1],aborts[0:1];
    reg [1:0] held_source=0;
    reg [105:0] held_bundle[0:1];
    task check(input bit condition,input string message);
        begin checks++;if(!condition)begin $display("FAIL phase=%0d %s",phase,message);$fatal(1);end end
    endtask
    always @(posedge clk)begin
        for(integer c=0;c<2;c++)begin
            if(!rst_n[c])held_source[c]=0;
            else begin
                check(event_ready[c],"physical events always drain");
                if(capture_valid[c]&&capture_accept[c])begin
                    captured[c]++;
                    check(capture_data[c]===data[c]&&capture_sequence[c]===sequence_id[c],"exact passive RAW/identity");
                    check(capture_session[c]==expected_session[c]&&capture_epoch[c]==expected_epoch[c],"FS session/epoch frozen");
                    check(metadata[c][196:193]==0&&metadata[c][192]==1&&metadata[c][191:64]==0,
                        "only physical provenance and time known; no qualified/exposure/HDR claim");
                    check(metadata[c][63:0]==expected_time[c],"common time frozen at actual FS");
                end
                if(geometry_done[c])geometries[c]++;
                if(capture_abort[c])aborts[c]++;
                if(held_source[c])check(source_valid[c]&&held_bundle[c]===
                    {source_session[c],source_epoch[c],source_sequence[c],source_camera[c],source_ok[c],source_error[c]},
                    "SOURCE result stable under sink stall");
                held_source[c]=source_valid[c]&&!source_ready[c];
                held_bundle[c]={source_session[c],source_epoch[c],source_sequence[c],source_camera[c],source_ok[c],source_error[c]};
                if(source_valid[c]&&source_ready[c])begin
                    check(source_camera[c]==c&&source_session[c]==expected_session[c]&&source_epoch[c]==expected_epoch[c],"SOURCE exact owner fields");
                    if(source_ok[c])begin good[c]++;check(source_error[c]==0,"good SOURCE no error");end
                    else begin bad[c]++;check(source_error[c]!=0,"negative SOURCE error");end
                end
            end
        end
    end
    task automatic send_event(input integer c,input [1:0] kind,input integer seq,input bit ok,input [3:0] code);
        begin
            @(negedge clk);event_kind[c]=kind;event_sequence[c]=seq;event_ok[c]=ok;event_error[c]=code;event_valid[c]=1;
            @(negedge clk);event_valid[c]=0;
        end
    endtask
    task automatic start(input integer c,input integer seq);
        begin
            expected_time[c]=timestamp[c];expected_session[c]=session_id[c];expected_epoch[c]=epoch[c];
            send_event(c,0,seq,1,0);
        end
    endtask
    task automatic raw_groups(input integer c,input integer seq,input integer count,input bit bad_eol,input bit accept_stall);
        begin
            for(integer n=0;n<count;n++)begin
                @(negedge clk);valid[c]=1;sequence_id[c]=seq;data[c]=40'(seq*100+n);
                sof[c]=(n==0);eol[c]=(n%G==G-1)^(bad_eol&&n==1);
                if(accept_stall&&n==2)begin accept[c]=0;repeat(4)@(negedge clk);accept[c]=1;end
            end
            @(negedge clk);valid[c]=0;sof[c]=0;eol[c]=0;
        end
    endtask
    task settle;begin repeat(18)@(negedge clk);end endtask
    task automatic good_frame(input integer c,input integer seq);
        begin start(c,seq);raw_groups(c,seq,COUNT,0,1);send_event(c,1,seq,1,0);settle();end
    endtask
    integer cap0,cap1,g0,g1,b0,b1,geom0;
    wire tag_done;
    tag_saturation_case u_tag(.done(tag_done));
    initial begin
        for(integer c=0;c<2;c++)begin
            session_id[c]=100+c;epoch[c]=10+c;timestamp[c]=64'h12340000+c;
            data[c]=0;sequence_id[c]=0;event_sequence[c]=0;event_kind[c]=0;event_error[c]=0;
            captured[c]=0;good[c]=0;bad[c]=0;geometries[c]=0;aborts[c]=0;
        end
        repeat(5)@(negedge clk);rst_n=3;
        phase=1;
        fork good_frame(0,1);good_frame(1,41);join
        check(good[0]==1&&good[1]==1&&captured[0]==COUNT&&captured[1]==COUNT,"both independent eyes capture good frame");
        phase=2;start(0,2);session_id[0]=999;epoch[0]=777;timestamp[0]=55;enable[0]=0;
        raw_groups(0,2,COUNT,0,0);send_event(0,1,2,1,0);settle();
        check(good[0]==2,"disable/config changes after FS do not truncate admitted frame");
        cap0=captured[0];g0=good[0];b0=bad[0];
        send_event(0,0,3,1,0);raw_groups(0,3,COUNT,0,0);send_event(0,1,3,1,0);settle();
        check(captured[0]==cap0&&good[0]==g0&&bad[0]==b0&&idle[0],"disabled frame creates no owner");
        enable[0]=1;time_valid[0]=0;
        send_event(0,0,4,1,0);raw_groups(0,4,COUNT,0,0);send_event(0,1,4,1,0);settle();
        check(captured[0]==cap0&&good[0]==g0&&idle[0],"invalid common time rejects FS without hanging fence");
        time_valid[0]=1;
        phase=3;b0=bad[0];g1=good[1];
        fork
            begin start(0,5);raw_groups(0,5,COUNT,0,0);send_event(0,2,5,0,2);settle();end
            good_frame(1,42);
        join
        check(bad[0]==b0+1&&good[1]==g1+1&&!fault[0]&&!fault[1],"late outside-crop CRC fails only its eye");
        phase=4;b0=bad[0];start(0,6);raw_groups(0,6,2,0,0);
        @(negedge clk);receive_fault[0]=1;@(negedge clk);receive_fault[0]=0;settle();
        check(bad[0]==b0+1&&idle[0],"receive fault terminates partial owner despite cancelled CSI event");
        good_frame(0,7);
        phase=5;b0=bad[0];geom0=geometries[0];start(0,8);raw_groups(0,8,COUNT,1,0);send_event(0,1,8,1,0);settle();
        check(bad[0]==b0+1&&geometries[0]==geom0,"bad EOL cannot create successful geometry/SOURCE");
        phase=6;source_ready[0]=0;start(0,9);raw_groups(0,9,COUNT,0,0);send_event(0,1,9,1,0);
        wait(source_valid[0]);cap0=captured[0];g0=good[0];g1=good[1];
        fork
            begin send_event(0,0,10,1,0);raw_groups(0,10,COUNT,0,0);send_event(0,1,10,1,0);settle();end
            good_frame(1,43);
        join
        check(source_valid[0]&&source_ok[0]&&source_sequence[0]==9&&captured[0]==cap0&&good[0]==g0&&good[1]==g1+1,
            "busy eye drops next frame without blocking event input or the healthy eye");
        @(negedge clk);source_ready[0]=1;settle();check(good[0]==g0+1&&idle[0],"held SOURCE retires once");
        phase=7;b0=bad[0];start(0,11);raw_groups(0,11,2,0,0);
        send_event(0,0,12,1,0);raw_groups(0,12,COUNT,0,0);send_event(0,1,12,1,0);settle();
        check(bad[0]==b0+1&&idle[0],"new FS authenticates missing prior terminal as negative");
        phase=8;b0=bad[0];start(0,13);raw_groups(0,13,2,0,0);
        @(negedge clk);valid[0]=1;identity[0]=0;sof[0]=0;eol[0]=0;
        @(negedge clk);valid[0]=0;identity[0]=1;settle();
        check(bad[0]==b0+1&&idle[0],"mid-frame RAW identity loss negatively terminates without hanging");
        phase=9;start(0,14);raw_groups(0,14,2,0,0);b0=bad[0];g0=good[0];
        @(negedge clk);rst_n[0]=0;repeat(5)@(negedge clk);rst_n[0]=1;settle();
        check(good[0]==g0&&bad[0]==b0&&idle[0],"cohort reset cancels incomplete owner without stale SOURCE");
        good_frame(0,1);check(!fault[0]&&!fault[1],"healthy peers retain independent state");
        wait(tag_done);
        $display("RESULT: PASS STEREO_SOURCE checks=%0d good=%0d/%0d bad=%0d/%0d captures=%0d/%0d",checks,good[0],good[1],bad[0],bad[1],captured[0],captured[1]);
        $finish;
    end
    initial begin #1000000;$fatal(1,"STEREO_SOURCE timeout phase=%0d",phase);end
endmodule

module tag_saturation_case(output reg done=0);
    reg clk=0;always #7 clk=~clk;
    reg rst_n=0,event_valid=0,valid=0;
    reg [1:0] kind=0;reg [31:0] seq=0;
    wire event_ready,source_valid,source_ok,idle,fault;
    integer results=0;
    stereo_capture_source4 #(.CAMERA_ID(1),.WIDTH(4),.HEIGHT(1),.TAG_WIDTH(2)) dut(
        .clk(clk),.rst_n(rst_n),.i_data_reset_n(rst_n),.i_enable(1'b1),.i_session(32'd4),.i_epoch(32'd5),.i_time_ns(64'd6),.i_time_valid(1'b1),
        .i_data(40'd7),.i_valid(valid),.i_accept(1'b1),.i_sof(1'b1),.i_eol(1'b1),.i_abort(1'b0),
        .i_sequence(seq),.i_identity_valid(1'b1),.i_event_valid(event_valid),.o_event_ready(event_ready),
        .i_event_kind(kind),.i_event_ok(1'b1),.i_event_error(4'd0),.i_event_sequence(seq),.i_event_identity_valid(1'b1),
        .i_receive_fault(1'b0),.i_identity_quarantine(1'b0),.o_capture_data(),.o_capture_valid(),.o_capture_accept(),
        .o_capture_sof(),.o_capture_eol(),.o_capture_abort(),.o_capture_geometry_done(),.o_capture_session(),
        .o_capture_epoch(),.o_capture_sequence(),.o_capture_metadata(),.o_raw_source_valid(source_valid),
        .i_raw_source_ready(1'b1),.o_raw_source_session(),.o_raw_source_epoch(),.o_raw_source_sequence(),
        .o_raw_source_camera(),.o_raw_source_ok(source_ok),.o_raw_source_error(),.o_idle(idle),.o_fault(fault));
    always @(posedge clk)if(rst_n&&source_valid)begin
        if(!source_ok)$fatal(1,"tag saturation corrupted admitted final frame");results++;
    end
    initial begin
        repeat(4)@(negedge clk);rst_n=1;
        for(integer n=1;n<=4;n++)begin
            @(negedge clk);seq=n;event_valid=1;kind=0;
            @(negedge clk);event_valid=0;valid=1;
            @(negedge clk);valid=0;event_valid=1;kind=1;
            @(negedge clk);event_valid=0;
            repeat(15)@(negedge clk);
        end
        if(results!=3||!fault||!idle||dut.tag_count!=3)$fatal(1,"tag saturation must reject fourth frame without wrap");
        done=1;
    end
endmodule
