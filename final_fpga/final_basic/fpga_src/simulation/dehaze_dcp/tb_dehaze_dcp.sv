`timescale 1ns/1ps
module tb_dehaze_dcp;
    localparam W=256,H=128,N=W*H/4,FRAMES=10;
    reg clk=0,rst=0,clear=0,reset_hist=0,en=1,eye=0,sv=0,sof=0,eol=0;
    always #4 clk=~clk;
    reg [31:0] ses=1,epoch=0,seq=0;
    reg [95:0] rgb;reg [31:0] yy;
    reg tv=0,tok=0,tcam=0;reg [31:0] ts=0,te=0,tq=0;
    wire mr,mv,ms,me,ready,used,pending,pixpending;
    wire [95:0] out_rgb;wire [31:0] out_y;
    integer tick=0,count=0,j=0,k=0,stalls=0;
    reg [129:0] previous;reg frozen=0;reg check_output=1;
    reg [127:0] source[0:FRAMES*N-1],expected[0:FRAMES*N-1];
    assign mr=tick%13!=3&&tick%11!=6;
    dehaze_dcp_restore4 #(.WIDTH(W),.HEIGHT(H)) dut(
       .clk(clk),.rst_n(rst),.clear(clear),.i_history_reset(reset_hist),
       .s_valid(sv),.s_ready(ready),.s_sof(sof),.s_eol(eol),.s_rgb(rgb),.s_luma(yy),
`ifdef DCP_STATISTICS_PORT
       .s_dark_statistics(16'd0),
`endif
       .i_enable(en),.i_camera(eye),.i_session(ses),.i_epoch(epoch),.i_sequence(seq),
       .i_terminal_valid(tv),.i_terminal_ok(tok),.i_terminal_camera(tcam),.i_terminal_session(ts),
       .i_terminal_epoch(te),.i_terminal_sequence(tq),.m_valid(mv),.m_ready(mr),.m_rgb(out_rgb),
       .m_luma(out_y),.m_sof(ms),.m_eol(me),.o_history_used(used),.o_pending(pending),.o_pixel_pending(pixpending));
    always @(posedge clk)begin
        tick<=tick+1;
        if(rst&&check_output)begin
            if(frozen&&(!mv||{ms,me,out_y,out_rgb}!==previous))$fatal(1,"changed stalled group");
            frozen<=mv&&!mr;previous<={ms,me,out_y,out_rgb};
            if(mv&&!mr)stalls<=stalls+1;
            if(mv&&mr)begin
                if({out_y,out_rgb}!==expected[count]||ms!==(count%N==0)||me!==(count%(W/4)==W/4-1))
                    $fatal(1,"mismatch frame=%0d group=%0d expected=%h actual=%h used=%b air=%d",count/N,count%N,expected[count],{out_y,out_rgb},used,dut.airlight);
                count<=count+1;
            end
        end
    end
    task term(input bit good,input bit wrong);
        begin @(negedge clk);tv=1;tok=good;tcam=wrong?!eye:eye;te=epoch;ts=ses;tq=seq;
            @(negedge clk);tv=0;
        end
    endtask
    reg prior_used;
    initial begin
        $readmemh("input.hex",source);$readmemh("expected.hex",expected);
        repeat(6)@(negedge clk);rst=1;
        for(j=0;j<FRAMES;j=j+1)begin
            // CAM0 seq ffffffff -> 0 accepts the actual modular successor;
            // two eyes intentionally overlap all session/epoch/sequence labels.
            eye=j==1||j==4||j==7;ses=j>=8?2:1;epoch=3;
            case(j)
                0,1:seq=32'hffffffff;
                2,4:seq=0;
                3:seq=1;
                5:seq=9; // stale gap
                6:seq=9; // duplicate
                7:seq=1;
                default:seq=j;
            endcase
            en=j!=9;prior_used=j==2||j==3||j==4;
            for(k=0;k<N;k=k+1)begin
                @(negedge clk);{yy,rgb}=source[j*N+k];sv=1;sof=k==0;eol=k%(W/4)==W/4-1;
                reset_hist=j==7&&k==0;
                do @(posedge clk);while(!ready);
                @(negedge clk);sv=0;reset_hist=0;
                if(k==0&&used!==prior_used)$fatal(1,"history eligibility eye=%d frame=%d used=%d",eye,j,used);
                if(k==9&&j%2==0)term(1,0);
                if(k==20)term(1,1);
                if(k==26&&j%2==0)term(1,0); // duplicate true terminal must commit only once
            end
            wait(!pixpending);
            if(j%2==1)begin
                if(en&&j!=9&&!pending)$fatal(1,"late terminal lost");
                term(j!=3,0);
            end
            wait(!pending);@(negedge clk);
        end
        if(count!=FRAMES*N||stalls==0)$fatal(1,"coverage");
        // Resolve a late successful terminal on the exact reset edge. No old table may reappear.
        check_output=0;en=1;eye=0;ses=3;seq=1;epoch=1;
        for(k=0;k<N;k=k+1)begin
            @(negedge clk);{yy,rgb}=source[k];sv=1;sof=k==0;eol=k%(W/4)==W/4-1;
            do @(posedge clk);while(!ready);
        end
        @(negedge clk);sv=0;sof=0;wait(dut.state==3);
        @(negedge clk);reset_hist=1;tv=1;tok=1;tcam=eye;ts=ses;te=epoch;tq=seq;
        @(negedge clk);tv=0;reset_hist=0;
        if(dut.history_valid!==0||pending)$fatal(1,"late source resurrected reset history");
        // A real bad source can truncate a frame without supplying its last row.
        check_output=0;sv=1;sof=1;eol=0;eye=0;en=1;seq=20;
        do @(posedge clk);while(!ready);@(negedge clk);sv=0;term(0,0);
        repeat(12)@(negedge clk);if(pending)$fatal(1,"truncated SOURCE retained");
        $display("RESULT: PASS DCP_PIXEL groups=%0d stalled=%0d frames=%0d",count,stalls,FRAMES);$finish;
    end
    initial begin #6000000;$fatal(1,"DCP watchdog state=%d frame=%0d group=%0d",dut.state,j,k);end
endmodule
