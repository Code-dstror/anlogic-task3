`timescale 1ns/1ps
// Same sequence numbers and different distributions force eye-qualified history.
module tb_stereo_he;
    reg clk=0,rst_n=0,eye=0,src_eye=0,src_valid=0,src_ok=1;
    reg valid=0,sof=0,eol=0,ready=0;
    reg [31:0] seq=0,epoch=1;
    reg [95:0] rgb=0;
    reg [31:0] y=0;
    wire in_ready,out_valid,out_sof,out_eol,source_match,accepted,history,started;
    wire [95:0] out_rgb;
    wire [31:0] out_y;
    always #4 clk=~clk;
    preprocess_hist_eq4 #(.EXTERNAL_LUMA_ENABLE(1),.HISTORY_RESET_ENABLE(1),
        .SOURCE_QUALIFY_ENABLE(1),.FIXED_CONFIG_SESSION_ENABLE(1),.HE_COLOR_PRESERVE(1),
        .STEREO_HISTORY_ENABLE(1)) dut (
        .clk(clk),.rst_n(rst_n),.clear(1'b0),.enable(1'b1),.width(13'd8),.height(13'd1),
        .s_valid(valid),.s_ready(in_ready),.s_sof(sof),.s_eol(eol),.s_data(rgb),.s_luma(y),
        .m_valid(out_valid),.m_ready(ready),.m_sof(out_sof),.m_eol(out_eol),
        .m_data(out_rgb),.m_luma(out_y),.history_reset(1'b0),
        .s_history_context({32'd1,epoch,32'd7,16'd256,13'd8,13'd1,eye,3'b000}),
        .s_history_eligible(1'b1),.s_capture_sequence(seq),
        .source_valid(src_valid),.source_camera(src_eye),.source_ok(src_ok),.source_session(32'd1),
        .source_epoch(epoch),.source_capture_sequence(seq),.o_source_owner_match(source_match),
        .o_source_accepted(accepted),.o_frame_history_used(history),.o_frame_started(started),.lut_valid(),.lut_epoch(),.stats_skipped_frames(),.statistics_error(),.stats_overflow_count(),.o_presented_valid(),.o_divider_ready(),.o_source_ready(),.o_source_decision_valid(),.o_source_decision_collect(),.o_source_decision_capture(),.o_source_cancel_done(),.stats_unqualified_frames(),.stats_source_rejects(),.stats_canceled_jobs());
    integer cycles=0,pushes=0,pops=0,frames=0;
    reg [95:0] expected[0:1];
    reg [95:0] held_rgb;
    reg [31:0] held_y;
    reg held_sof,held_eol,held=0;
    always @(negedge clk) begin
        cycles=cycles+1;
        ready=(cycles%7==0 || cycles%7==3);
        if(cycles>200000) $fatal(1,"timeout");
    end
    always @(posedge clk) begin
        if(held && (!out_valid || {out_rgb,out_y,out_sof,out_eol}!=={held_rgb,held_y,held_sof,held_eol}))
            $fatal(1,"stalled output mutated");
        held=out_valid&&!ready;
        if(held)begin held_rgb=out_rgb;held_y=out_y;held_sof=out_sof;held_eol=out_eol;end
        if(valid&&in_ready)pushes++;
        if(out_valid&&ready)begin
            if(out_rgb!==expected[pops%2] || out_sof!==(pops%2==0) || out_eol!==(pops%2==1))
                $fatal(1,"eye=%0d seq=%0d beat=%0d expected=%h actual=%h",eye,seq,pops%2,expected[pops%2],out_rgb);
            for(integer n=0;n<4;n++)if(out_y[n*8+:8]!==out_rgb[n*24+:8])$fatal(1,"wrong rebuilt Y eye=%0d seq=%0d lane=%0d rgb=%h y=%h",eye,seq,n,out_rgb,out_y);
            pops++;
        end
    end
    function automatic integer sample(input bit camera,input integer x);
        if(camera)case(x) 0:sample=32;1:sample=96;2,3,4:sample=160;default:sample=224;endcase
        else case(x) 0,1:sample=32;2,3,4,5:sample=96;6:sample=160;default:sample=224;endcase
    endfunction
    task automatic frame(input bit camera,input integer sequence_id,input bit use_map,input bit success,input bit wait_build);
        integer b,l,v,delta,target,cdf,cdf_min,n,base;
        reg [7:0] value8;
        begin
            @(negedge clk);eye=camera;seq=sequence_id;src_eye=camera;src_ok=1;base=pops;
            for(b=0;b<2;b++)begin
                for(l=0;l<4;l++)begin
                    v=sample(camera,4*b+l);
                    cdf=0;cdf_min=0;
                    for(n=0;n<8;n++)begin
                        if(sample(camera,n)<=v)cdf++;
                        if(sample(camera,n)==32)cdf_min++;
                    end
                    target=(cdf-cdf_min)*255/(8-cdf_min);delta=target-v;
                    if(delta>32)delta=32;if(delta< -32)delta=-32;
                    value8=use_map ? v+delta : v;
                    expected[b][24*l+:24]={3{value8}};
                    value8=v;rgb[24*l+:24]={3{value8}};y[8*l+:8]=value8;
                end
                valid=1;sof=b==0;eol=b==1;
                do @(posedge clk);while(!in_ready);
                @(negedge clk);
            end
            valid=0;sof=0;eol=0;
            wait(pops==base+2);@(negedge clk);
            if(history!==use_map)$fatal(1,"wrong history source eye=%d seq=%d",camera,sequence_id);
            src_valid=1;src_eye=!camera;#1;
            if(source_match||accepted)$fatal(1,"wrong eye SOURCE accepted");
            @(negedge clk);src_eye=camera;src_ok=success;#1;
            if(!source_match||!accepted)$fatal(1,"own SOURCE not accepted");
            @(negedge clk);src_valid=0;src_ok=1;
            if(wait_build)begin
                repeat(12000)@(negedge clk);
                if(!dut.pending_valid[camera])$fatal(1,"no completed per-eye map");
            end
            frames++;
        end
    endtask
    initial begin
        repeat(8)@(negedge clk);rst_n=1;
        frame(0,10,0,1,0);frame(1,10,0,1,1);
        frame(0,12,1,1,0);frame(1,12,1,0,0);
        // A bad CAM1 result cannot erase the CAM0 active map.
        frame(0,14,1,1,1);
        epoch=2;frame(1,16,0,1,1);
        // CAM0 sees the new epoch independently; its stale table is bypassed.
        frame(0,16,0,1,1);frame(1,18,1,1,1);
        if(pushes!=16 || pops!=16)$fatal(1,"transfer counts");
        $display("RESULT: PASS STEREO_HE frames=%0d pixels=%0d",frames,pops*4);$finish;
    end
endmodule
