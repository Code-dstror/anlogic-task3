`timescale 1ns/1ps
module tb_ingress_equivalence #(parameter W=68,H=5,C=1,P=1,S=1,E=1);
    localparam GROUPS=W*H/4,FRAME_BYTES=GROUPS*5;
    localparam [15:0] FINAL_KEEP=FRAME_BYTES%16==0?16'hffff:(16'hffff>>(16-FRAME_BYTES%16));
    reg clk=0,rst_n=0;
    always #4 clk=~clk;
    reg enable=1,valid=0,accept=1,sof=0,eol=0,abort=0,camera=0;
    reg [39:0] raw_data=0;
    reg [31:0] epoch=0,sequence_number=0,session=0;
    reg [63:0] timestamp=0;
    reg source_valid=0,source_ok=1;
    reg [31:0] source_session=0,source_epoch=0,source_sequence=0;
    reg [7:0] source_error=0;
    reg source_camera=0,ready=1;
    wire [127:0] out_data[0:1];wire [15:0] out_keep[0:1];
    wire [1:0] out_user[0:1];wire [1:0] out_valid,out_last,capture_idle,frame_accept,source_ready;
    wire [31:0] drops[0:1],errors[0:1],stale[0:1];
    genvar variant;
    generate for(variant=0;variant<2;variant=variant+1)begin:implementations
        if(variant==0)begin:current
            shared_raw10_frame_ingress #(.WIDTH(W),.HEIGHT(H),.CONTEXT_ENABLE(C),.PAIR_METADATA_ENABLE(P),
                .EXTERNAL_SEQUENCE_ENABLE(E),.SOURCE_TERMINAL_ENABLE(S)) dut(
                .i_clk(clk),.i_rst_n(rst_n),.i_enable(enable),.i_data(raw_data),.i_valid(valid),.i_accept(accept),
                .i_sof(sof),.i_eol(eol),.i_abort(abort),.i_camera(camera),.i_epoch(epoch),
                .i_external_sequence(sequence_number),.i_session_id(session),.i_sdr_profile(1'b1),
                .i_bayer_valid(1'b1),.i_time_valid(1'b1),.i_bayer_pattern(2'd2),.i_metadata_valid(1'b0),
                .i_timestamp(timestamp),.i_actual_exposure(32'd0),.i_gain(32'd0),.i_calibration_id(32'd0),
                .i_source_kind(1'b1),.i_exposure_role(2'd0),.i_exposure_group(32'd0),.i_source_qualified(1'b0),
                .i_source_valid(source_valid),.o_source_ready(source_ready[variant]),
                .i_source_session(source_session),.i_source_epoch(source_epoch),.i_source_sequence(source_sequence),
                .i_source_camera(source_camera),.i_source_ok(source_ok),.i_source_error(source_error),
                .o_source_stale_count(stale[variant]),.o_axis_tdata(out_data[variant]),.o_axis_tkeep(out_keep[variant]),
                .o_axis_tvalid(out_valid[variant]),.i_axis_tready(ready),.o_axis_tlast(out_last[variant]),
                .o_axis_tuser(out_user[variant]),.o_capture_idle(capture_idle[variant]),
                .o_frame_accept(frame_accept[variant]),.o_drop_count(drops[variant]),.o_error_count(errors[variant]));
        end else begin:previous
            shared_raw10_frame_ingress_before #(.WIDTH(W),.HEIGHT(H),.CONTEXT_ENABLE(C),.PAIR_METADATA_ENABLE(P),
                .EXTERNAL_SEQUENCE_ENABLE(E),.SOURCE_TERMINAL_ENABLE(S)) dut(
                .i_clk(clk),.i_rst_n(rst_n),.i_enable(enable),.i_data(raw_data),.i_valid(valid),.i_accept(accept),
                .i_sof(sof),.i_eol(eol),.i_abort(abort),.i_camera(camera),.i_epoch(epoch),
                .i_external_sequence(sequence_number),.i_session_id(session),.i_sdr_profile(1'b1),
                .i_bayer_valid(1'b1),.i_time_valid(1'b1),.i_bayer_pattern(2'd2),.i_metadata_valid(1'b0),
                .i_timestamp(timestamp),.i_actual_exposure(32'd0),.i_gain(32'd0),.i_calibration_id(32'd0),
                .i_source_kind(1'b1),.i_exposure_role(2'd0),.i_exposure_group(32'd0),.i_source_qualified(1'b0),
                .i_source_valid(source_valid),.o_source_ready(source_ready[variant]),
                .i_source_session(source_session),.i_source_epoch(source_epoch),.i_source_sequence(source_sequence),
                .i_source_camera(source_camera),.i_source_ok(source_ok),.i_source_error(source_error),
                .o_source_stale_count(stale[variant]),.o_axis_tdata(out_data[variant]),.o_axis_tkeep(out_keep[variant]),
                .o_axis_tvalid(out_valid[variant]),.i_axis_tready(ready),.o_axis_tlast(out_last[variant]),
                .o_axis_tuser(out_user[variant]),.o_capture_idle(capture_idle[variant]),
                .o_frame_accept(frame_accept[variant]),.o_drop_count(drops[variant]),.o_error_count(errors[variant]));
        end
    end endgenerate
    integer checks=0,frame_number=0,byte_count=0,end_count=0,abort_count=0;
    integer early_raw=0,append_emit=0,tail_stalls=0,continuous=0,lane;
    reg [31:0] next_sequence=0;
    always @(posedge clk)begin
        if(!rst_n)next_sequence<=0;
        else if(frame_accept[0])next_sequence<=next_sequence+1;
    end
    reg chain_entry=0;integer terminal_restarts=0;
    reg expect_good=0,stalled=0;
    reg [146:0] held=0;
    function automatic [39:0] group_value(input integer frame_id,input integer group_id);
        integer sample;
        begin
            group_value=0;
            for(sample=0;sample<4;sample=sample+1)
                group_value[sample*10+:10]=(frame_id*77+group_id*4+sample)&1023;
        end
    endfunction
    function automatic [7:0] expected_byte(input integer frame_id,input integer byte_id);
        reg [39:0] packed_group;
        begin packed_group=group_value(frame_id,byte_id/5);expected_byte=packed_group>>(8*(byte_id%5));end
    endfunction
    task automatic check(input bit condition,input string why);
        begin checks=checks+1;if(!condition)$fatal(1,"INGRESS_EQ frame=%0d bytes=%0d: %s",frame_number,byte_count,why);end
    endtask
    always @(posedge clk)if(rst_n)begin
        check({out_valid[0],out_last[0],out_user[0],out_keep[0],out_data[0]}===
              {out_valid[1],out_last[1],out_user[1],out_keep[1],out_data[1]},"old/new token bits and valid every cycle");
        check({capture_idle[0],frame_accept[0],source_ready[0],drops[0],errors[0],stale[0]}===
              {capture_idle[1],frame_accept[1],source_ready[1],drops[1],errors[1],stale[1]},"old/new control and counters");
        if(stalled)check(out_valid[0]&&{out_user[0],out_last[0],out_keep[0],out_data[0]}===held,"held token survives stall");
        stalled=out_valid[0]&&!ready;
        held={out_user[0],out_last[0],out_keep[0],out_data[0]};
        if(frame_accept[0]&&implementations[0].current.dut.terminal_fire)terminal_restarts++;
        if(valid&&accept&&implementations[0].current.dut.context_pending!=0)early_raw=early_raw+1;
        if(valid&&accept&&implementations[0].current.dut.reservoir_emit)append_emit=append_emit+1;
        if(out_valid[0]&&out_last[0]&&out_user[0]==0&&!ready)tail_stalls=tail_stalls+1;
        if(out_valid[0]&&ready&&frame_number!=0)begin
            if(out_user[0]==1&&!out_last[0])begin byte_count=0;end_count=0;abort_count=0;end
            if(out_user[0]==0)begin
                for(lane=0;lane<16;lane=lane+1)if(out_keep[0][lane])begin
                    if(expect_good)begin
                        check(byte_count<FRAME_BYTES,"DATA never exceeds dense frame length");
                        check(out_data[0][lane*8+:8]===expected_byte(frame_number,byte_count),"independent scalar packed byte");
                    end
                    byte_count=byte_count+1;
                end
                if(expect_good&&out_last[0])check(byte_count==FRAME_BYTES&&out_keep[0]==FINAL_KEEP,"partial final DATA KEEP and length");
            end
            if(out_user[0]==2)begin
                end_count=end_count+1;check(expect_good,"bad frame cannot emit success END");
                check(byte_count==FRAME_BYTES,"success requires every byte");
            end
            if(out_user[0]==3)abort_count=abort_count+1;
        end
    end
    task automatic send_frame(input integer id,input integer scenario);
        integer group_id,waits;
        begin
            if(!chain_entry)@(negedge clk);else chain_entry=0;frame_number=id;expect_good=scenario<2||scenario==5;camera=id%2;
            session=32'h12340000+id;epoch=32'h34000000+id;sequence_number=id;
            source_session=session;source_epoch=epoch;source_sequence=E?sequence_number:next_sequence;source_camera=camera;
            timestamp=64'h1020304050000000+id;source_error=0;source_ok=1;source_valid=0;
            for(group_id=0;group_id<GROUPS;group_id=group_id+1)begin
                valid=1;accept=1;raw_data=group_value(id,group_id);sof=group_id==0;
                eol=group_id%(W/4)==W/4-1;
                if(scenario==3&&group_id==3)eol=!eol;
                if(scenario==4&&group_id==8)ready=0;
                if(scenario==4&&group_id==12)ready=1;
                @(negedge clk);
                if(scenario<2||scenario==5)continuous=continuous+1;
            end
            valid=0;sof=0;eol=0;
            if(scenario==1&&S)ready=0;
            repeat(7)@(negedge clk);
            source_valid=1;source_ok=scenario!=2;source_error=scenario==2?8'd9:8'd0;
            @(negedge clk);source_valid=0;ready=1;
            if(scenario==5)begin
                waits=0;while(!(out_valid[0]&&out_user[0]==2)&&waits<200)begin @(negedge clk);waits++;end
                check(waits<200,"chain waits for actual held success terminal");chain_entry=1;
            end
            waits=0;while(scenario!=5&&!capture_idle[0]&&waits<200)begin @(negedge clk);waits=waits+1;end
            check(waits<200,"frame reaches genuine idle");
            if(scenario<2)check(end_count==1&&abort_count==0&&byte_count==FRAME_BYTES,"complete good frame");
            else if(scenario!=5)check(end_count==0&&abort_count!=0,"failed frame terminal is negative");
            if(scenario!=5)repeat(3)@(negedge clk);
        end
    endtask
    initial begin
        repeat(3)@(negedge clk);rst_n=1;
        send_frame(1,0);send_frame(2,1);
        if(S)send_frame(3,2);
        if(GROUPS>16)begin send_frame(4,3);send_frame(5,4);end
        send_frame(6,0);
        if(S)begin send_frame(9,5);send_frame(10,0);check(terminal_restarts!=0,"terminal handshake shares new SOF admission");end
        // Independent non-sensor accepts, unexpected SOFs, disable/abort,
        // mismatched SOURCE and finite random output stalls. Every cycle is
        // compared, including negative terminals and diagnostic counters.
        expect_good=0;frame_number=0;
        for(integer n=0;n<400;n++)begin
            @(negedge clk);valid=$urandom_range(0,1);accept=$urandom_range(0,1);
            sof=$urandom_range(0,3)==0;eol=$urandom_range(0,1);
            raw_data={$urandom,$urandom};enable=$urandom_range(0,15)!=0;
            abort=$urandom_range(0,31)==0;ready=$urandom_range(0,3)!=0;
            source_valid=$urandom_range(0,7)==0;source_ok=$urandom_range(0,1);
            source_error=$urandom_range(0,1);source_camera=$urandom_range(0,1);
            source_session=session;source_epoch=epoch;source_sequence=sequence_number;
        end
        @(negedge clk);valid=0;sof=0;eol=0;abort=0;enable=1;ready=1;source_valid=0;
        rst_n=0;stalled=0;repeat(3)@(negedge clk);rst_n=1;
        // Reset while metadata and early RAW are live; no successful terminal.
        @(negedge clk);frame_number=7;expect_good=0;valid=1;sof=1;eol=0;raw_data=group_value(7,0);
        @(negedge clk);sof=0;raw_data=group_value(7,1);
        @(negedge clk);rst_n=0;valid=0;stalled=0;ready=1;
        repeat(3)@(negedge clk);rst_n=1;
        send_frame(8,0);
        check(continuous>=4*GROUPS,"required continuous good-frame input observed");
        if(C&&GROUPS>1)check(early_raw>0,"metadata overlaps accepted RAW");
        if(GROUPS>16)check(append_emit>0,"simultaneous append and emit observed");
        if(S&&GROUPS>16)check(tail_stalls>0,"held DATA tail observed");
        $display("RESULT: PASS INGRESS_EQUIVALENCE W=%0d H=%0d C=%0d P=%0d S=%0d E=%0d checks=%0d early_raw=%0d append_emit=%0d tail_stalls=%0d continuous=%0d",W,H,C,P,S,E,checks,early_raw,append_emit,tail_stalls,continuous);$finish;
    end
    initial begin #100000;$fatal(1,"INGRESS_EQ watchdog");end
endmodule
