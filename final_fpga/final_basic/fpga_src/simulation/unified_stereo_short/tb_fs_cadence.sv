`timescale 1ns/1ps
module tb_fs_cadence;
    reg clk=0,rst=0;always #5 clk=~clk;
    reg [7:0] divisor=2;
    reg enable=1,valid=0,sof=0,eol=0,event_valid=0,event_ok=1,event_identity=1,source_ready=1;
    reg [1:0] event_kind=0;
    reg [31:0] sequence_id=0,event_sequence=0;
    wire event_ready,capture_valid,capture_sof,source_valid,source_ok,idle,fault;
    wire [31:0] source_sequence;
    wire [7:0] source_error;
    stereo_capture_source4 #(.WIDTH(16),.HEIGHT(2),.FS_CADENCE_ENABLE(1)) dut(
        .clk(clk),.rst_n(rst),.i_data_reset_n(rst),.i_frame_divisor(divisor),.i_enable(enable),
        .i_session(32'd7),.i_epoch(32'd9),.i_time_ns(64'd123),.i_time_valid(1'b1),
        .i_data(40'h123456789a),.i_valid(valid),.i_accept(1'b1),.i_sof(sof),.i_eol(eol),.i_abort(1'b0),
        .i_sequence(sequence_id),.i_identity_valid(1'b1),.i_event_valid(event_valid),.o_event_ready(event_ready),
        .i_event_kind(event_kind),.i_event_ok(event_ok),.i_event_error(4'd0),.i_event_sequence(event_sequence),
        .i_event_identity_valid(event_identity),.i_receive_fault(1'b0),.i_identity_quarantine(1'b0),
        .o_capture_data(),.o_capture_valid(capture_valid),.o_capture_accept(),.o_capture_sof(capture_sof),
        .o_capture_eol(),.o_capture_abort(),.o_capture_geometry_done(),.o_capture_session(),.o_capture_epoch(),
        .o_capture_sequence(),.o_capture_metadata(),.o_raw_source_valid(source_valid),.i_raw_source_ready(source_ready),
        .o_raw_source_session(),.o_raw_source_epoch(),.o_raw_source_sequence(source_sequence),.o_raw_source_camera(),
        .o_raw_source_ok(source_ok),.o_raw_source_error(source_error),.o_idle(idle),.o_fault(fault));
    integer captures=0,good=0,bad=0,checks=0,phase=0;
    reg [40:0] held;reg was_held=0;
    always @(posedge clk)if(rst)begin
        if(fault)$fatal(1,"cadence structural fault phase=%0d",phase);
        if(capture_valid&&capture_sof)captures++;
        if(was_held&&(!source_valid||{source_sequence,source_ok,source_error}!==held))$fatal(1,"held old SOURCE changed");
        was_held=source_valid&&!source_ready;held={source_sequence,source_ok,source_error};
        if(source_valid&&source_ready)begin
            if(source_ok)good++;else bad++;
            $display("SOURCE seq=%0d ok=%0d phase=%0d",source_sequence,source_ok,phase);
        end
    end
    task check(input bit condition,input string message);
        begin checks++;if(!condition)$fatal(1,"FS_CADENCE phase=%0d %s captures=%0d good=%0d bad=%0d",phase,message,captures,good,bad);end
    endtask
    task automatic event_send(input [1:0] kind,input [31:0] seq);
        begin @(negedge clk);event_kind=kind;event_sequence=seq;event_valid=1;
            @(negedge clk);event_valid=0;end
    endtask
    task automatic pixels(input [31:0] seq,input integer count);
        begin
            for(integer n=0;n<count;n++)begin
                @(negedge clk);sequence_id=seq;valid=1;sof=n==0;eol=n%4==3;
            end
            @(negedge clk);valid=0;sof=0;eol=0;
        end
    endtask
    task settle;begin repeat(18)@(negedge clk);end endtask
    task automatic frame(input [31:0] seq);
        begin event_send(0,seq);pixels(seq,8);event_send(1,seq);settle();end
    endtask
    integer c,g,b;
    initial begin
        repeat(5)@(negedge clk);rst=1;settle();phase=1;
        frame(10);frame(11);frame(12);frame(13);
        check(captures==2&&good==2&&bad==0,"N2 tracks real FS");
        phase=2;event_send(0,14);pixels(14,2);
        event_send(0,15);pixels(15,8);event_send(1,15);settle();
        check(bad==1&&good==2&&idle,"unselected next FS still negatively terminates missing FE");
        frame(16);frame(17);check(good==3,"recovery keeps physical N2 phase");
        phase=3;source_ready=0;frame(18);check(source_valid&&source_sequence==18&&source_ok,"hold real selected owner");
        c=captures;frame(19);check(captures==c&&source_valid&&source_sequence==18&&source_ok,"skipped FE/crop cannot poison held old result");
        @(negedge clk);source_ready=1;settle();frame(20);frame(21);
        check(good==5&&bad==1,"busy skipped FS advances phase without a second divider");
        phase=4;event_send(0,22);
        // FE arrives after the cropped SOF/context, before the crop tail.
        // The fence cannot treat FE alone as complete pixel geometry.
        for(integer n=0;n<8;n++)begin
            @(negedge clk);sequence_id=22;valid=1;sof=n==0;eol=n%4==3;
            event_valid=n==2;event_kind=1;event_sequence=22;
            if(n>2)check(!source_valid,"early FE cannot bypass crop geometry/quiet");
        end
        @(negedge clk);valid=0;sof=0;eol=0;event_valid=0;
        settle();check(good==6,"early FE and true crop tail join once");
        phase=5;c=captures;event_identity=0;frame(23);event_identity=1;
        frame(24);check(captures==c,"untrusted FS never advances cadence");
        frame(25);check(good==7,"trusted FS resumes unchanged phase");
        phase=6;frame(26); // unselected
        source_ready=0;frame(27);check(source_valid&&source_sequence==27&&source_ok,"old N2 owner held across config");
        divisor=3;settle();frame(28);frame(29);
        check(source_valid&&source_sequence==27&&source_ok,"new cadence cannot alter frozen old tuple");
        @(negedge clk);source_ready=1;settle();c=captures;frame(30);
        check(captures==c,"busy selected FS and skipped FS both retain physical N3 phase");
        frame(31);check(good==9,"next selected N3 recovers without phase slip");
        phase=7;c=captures;divisor=0;settle();frame(32);frame(33);
        check(captures==c&&idle,"N0 creates no owner");
        divisor=1;settle();frame(34);frame(35);check(good==11,"N1 admits every trusted FS");
        event_ok=0;c=captures;frame(36);event_ok=1;
        check(captures==c,"bad FS cannot create an owner or advance phase");
        phase=8;event_send(0,37);pixels(37,2);
        @(negedge clk);rst=0;was_held=0;repeat(5)@(negedge clk);rst=1;settle();
        check(idle&&!source_valid,"cohort reset cancels incomplete source");frame(0);
        check(good==12&&bad==1,"clean source restarts after reset");
        $display("RESULT: PASS FS_CADENCE checks=%0d captures=%0d good=%0d bad=%0d",checks,captures,good,bad);$finish;
    end
    initial begin #1000000;$fatal(1,"FS cadence timeout phase=%0d",phase);end
endmodule
