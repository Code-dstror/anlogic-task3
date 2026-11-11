`timescale 1ns/1ps
module tb_pair_overlap;
    reg clk=0,cfg_clk=0;
    always #4 clk=~clk;
    always #20 cfg_clk=~cfg_clk;
    reg rst_n=0,admit=1,stable_force=1,use_owner=0,fault=0;
    reg [31:0] session=1,epoch=1;
    wire stable;
    reg [1:0] stable_sync=0;
    wire owner_stable;
    always @(posedge clk or negedge rst_n)
        if(!rst_n)stable_sync<=0;else stable_sync<={stable_sync[0],owner_stable};
    assign stable=use_owner?stable_sync[1]:stable_force;
    reg [1:0] push=0;
    reg [146:0] push0=0,push1=0;
    reg [146:0] fifo0[0:511],fifo1[0:511];
    integer head0=0,tail0=0,count0=0,head1=0,tail1=0,count1=0;
    integer max0=0,max1=0,writes0=0,writes1=0,reads0=0,reads1=0;
    wire valid0=count0!=0,valid1=count1!=0;
    wire [146:0] token0=fifo0[head0],token1=fifo1[head1];
    wire ready0,ready1;
    wire pop0=valid0&&ready0,pop1=valid1&&ready1;
    always @(posedge clk)begin
        if(!rst_n)begin
            head0<=0;tail0<=0;count0<=0;head1<=0;tail1<=0;count1<=0;
            max0<=0;max1<=0;writes0<=0;writes1<=0;reads0<=0;reads1<=0;
        end else begin
            if(push[0]&&count0==512&&!pop0)$fatal(1,"FIFO0 overflow");
            if(push[1]&&count1==512&&!pop1)$fatal(1,"FIFO1 overflow");
            if(push[0])begin fifo0[tail0]<=push0;tail0<=(tail0+1)%512;writes0<=writes0+1;end
            if(push[1])begin fifo1[tail1]<=push1;tail1<=(tail1+1)%512;writes1<=writes1+1;end
            if(pop0)begin head0<=(head0+1)%512;reads0<=reads0+1;end
            if(pop1)begin head1<=(head1+1)%512;reads1<=reads1+1;end
            count0<=count0+integer'(push[0])-integer'(pop0);
            count1<=count1+integer'(push[1])-integer'(pop1);
            if(count0>max0)max0<=count0;
            if(count1>max1)max1<=count1;
        end
    end
    wire [39:0] raw0,raw1;
    wire rawv0,rawv1,rawsof0,rawsof1,raweol0,raweol1,rawabort0,rawabort1;
    wire sourcev0,sourcev1,source_ok,pair_event,pair_ok,quiet;
    reg source_ready0=1,source_ready1=1;
    reg [136:0] held_source;
    wire [31:0] sequence0,sequence1,source_sequence0,source_sequence1;
    wire [31:0] source_session,source_epoch,diag,cancel_diag,good,bad,not_admitted;
    wire [7:0] source_error;
    wire [196:0] metadata0,metadata1;
    real_hdr_pair_cycle_gate #(.TIMEOUT_CYCLES(4096)) dut(
        .i_clk(clk),.i_reset_n(rst_n),.i_fault(fault),.i_stable(stable),.i_admit_enable(admit),
        .i_session(session),.i_epoch(epoch),.i_time(64'd123456),.i_time_valid(1'b1),
        .i_capture0_idle(1'b1),.i_capture1_idle(1'b1),
        .s0_data(token0),.s1_data(token1),.s0_valid(valid0),.s1_valid(valid1),
        .s0_ready(ready0),.s1_ready(ready1),
        .m0_data(raw0),.m1_data(raw1),.m0_valid(rawv0),.m1_valid(rawv1),
        .m0_sof(rawsof0),.m1_sof(rawsof1),.m0_eol(raweol0),.m1_eol(raweol1),
        .m0_abort(rawabort0),.m1_abort(rawabort1),
        .o_sequence0(sequence0),.o_sequence1(sequence1),.o_session(),.o_epoch(),
        .o_metadata0(metadata0),.o_metadata1(metadata1),
        .o_source0_valid(sourcev0),.o_source1_valid(sourcev1),.i_source0_ready(source_ready0),.i_source1_ready(source_ready1),
        .o_source_session(source_session),.o_source_epoch(source_epoch),
        .o_source0_sequence(source_sequence0),.o_source1_sequence(source_sequence1),
        .o_source_ok(source_ok),.o_source_error(source_error),.o_pair_event(pair_event),.o_pair_ok(pair_ok),
        .o_diag_pair(diag),
        .o_diag_counts(),.o_good_pairs(good),.o_bad_pairs(bad),.o_not_admitted_pairs(not_admitted),.o_quiet(quiet));
    assign cancel_diag={16'd0,diag[31:16]};

    wire cdc_event,cdc_ok,cdc_overflow;
    real_hdr_event_cdc bridge(.s_clk(clk),.s_reset_n(rst_n),.s_event(pair_event),.s_ok(pair_ok),
        .s_overflow(cdc_overflow),.m_clk(cfg_clk),.m_reset_n(rst_n),.m_event(cdc_event),.m_ok(cdc_ok));
    reg owner_start=0,write_done=0;
    wire write_valid,owner_written,owner_error;
    wire [31:0] owner_diag;
    integer config_writes=0;
    always @(posedge cfg_clk)begin
        if(!rst_n)begin write_done<=0;config_writes<=0;end
        else begin write_done<=write_valid;if(write_valid)config_writes<=config_writes+1;end
    end
    // Explicit register-transaction completion BFM; no forced owner state or
    // good-pair feedback. Physical I2C and electrical PHY are outside this test.
    imx415_hdr2_config_owner #(.RESET_HOLD_CYCLES(2),.RELEASE_WAIT_CYCLES(2),
        .REGULATOR_WAIT_CYCLES(2),.WARMUP_PAIRS(8)) owner(
        .i_clk(cfg_clk),.i_rst_n(rst_n),.i_start(owner_start),.o_start_ready(),
        .i_clock_locked(1'b1),.i_abort(1'b0),.i_source_fault(1'b0),
        .i_pair_event(cdc_event),.i_pair_ok(cdc_ok),.o_xclr(),.o_busy(),
        .o_write_valid(write_valid),.i_write_ready(1'b1),.o_write_register(),
        .i_write_done(write_done),.i_write_error(1'b0),.o_config_written(owner_written),
        .o_stable(owner_stable),.o_error(owner_error),.o_register_index(),.o_diag_state(owner_diag),
        .o_long_driver_lines(),.o_short_driver_lines(),.o_ratio_log2(),.o_gain_q16(),.o_black_raw10());

    integer events=0,source_good=0,source_bad=0,raw_count0=0,raw_count1=0;
    reg [31:0] last_source0=0,last_source1=0;
    always @(posedge clk)begin
        if(!rst_n)begin events=0;source_good=0;source_bad=0;raw_count0=0;raw_count1=0;last_source0=0;last_source1=0;end
        else begin
            if(pair_event)events=events+1;
            if(rawv0)raw_count0=raw_count0+1;
            if(rawv1)raw_count1=raw_count1+1;
            if((sourcev0&&source_ready0)||(sourcev1&&source_ready1))begin
                if(source_ok)source_good=source_good+1;else source_bad=source_bad+1;
                last_source0=source_sequence0;last_source1=source_sequence1;
            end
        end
    end
    function automatic [146:0] item(input integer group,member,code,input bit abort,trust,cycle);
        reg [146:0] value;
        begin
            value=0;value[39:0]=40'(group*32+member);value[40]=code==0;value[41]=code==0;
            value[42]=abort;value[46:43]=4'(code);value[78:47]=32'(group);
            value[110:79]=32'(group*10+member);value[111]=trust;value[112]=cycle;
            value[128:113]=16'(group);item=value;
        end
    endfunction
    task automatic put(input [1:0] mask,input [146:0] a,b);
        begin @(negedge clk);push=mask;push0=a;push1=b;end
    endtask
    task automatic tick(input integer count);
        integer k;begin for(k=0;k<count;k=k+1)put(0,0,0);end
    endtask
    task automatic cold;
        begin
            source_ready0=1;source_ready1=1;rst_n=0;push=0;fault=0;admit=1;stable_force=1;use_owner=0;session=1;epoch=1;owner_start=0;
            tick(25);rst_n=1;tick(8);
        end
    endtask
    task automatic begin_pair(input integer group);
        begin
            put(3,item(group,0,7,0,1,1),item(group,1,7,0,1,1));tick(3);
            put(3,item(group,0,0,0,1,1),item(group,1,0,0,1,1));tick(3);
        end
    endtask
    task automatic complete_pair(input integer group);
        begin begin_pair(group);put(3,item(group,0,6,0,1,1),item(group,1,6,0,1,1));tick(45);end
    endtask
    integer checks=0,cases=0;
    task automatic check(input bit condition,input string description);
        begin checks=checks+1;if(!condition)$fatal(1,"PAIR_CHECK %s diag=%08h cancel=%08h good=%0d bad=%0d fifo=%0d/%0d",description,diag,cancel_diag,good,bad,count0,count1);end
    endtask
    task automatic report(input string description);
        begin cases=cases+1;$display("CASE %s good=%0d bad=%0d source=%0d/%0d cancel=%08h fifo_max=%0d/%0d",description,good,bad,source_good,source_bad,cancel_diag,max0,max1);end
    endtask
    integer k,g,limit;
    initial begin
        cold();begin_pair(1);put(1,item(1,0,6,0,1,1),0);tick(3);
        put(3,item(2,0,7,0,1,1),item(1,1,6,0,1,1));tick(12);
`ifdef R2_BASELINE
        check(good==0&&bad==1,"fixed R2 reproduces simultaneous late-FE reason5");
        $display("RESULT: PASS R2_OVERLAP_REPRODUCTION checks=%0d",checks);$finish;
`else
        check(good==1&&bad==0,"simultaneous future LONG FS and old SHORT FE retain old good pair");
        check(source_good==1&&last_source0==10&&last_source1==11,"skipped FS cannot overwrite active SOURCE sequence");
        check(dut.skip_group==2&&cancel_diag==0,"future group2 is abandoned without reason5");
        put(3,item(2,0,0,0,1,1),item(2,1,7,0,1,1));
        put(3,item(2,0,6,0,1,1),item(2,1,0,0,1,1));
        put(2,0,item(2,1,6,0,1,1));tick(15);
        check(count0==0&&count1==0&&good==1&&bad==0,"both skipped member streams retire");
        complete_pair(3);check(good==2&&last_source0==30&&last_source1==31,"next unskipped pair qualifies");report("same_edge_old_FE_future_FS");

        cold();begin_pair(1);put(1,item(1,0,6,0,1,1),0);tick(3);
        put(1,item(2,0,7,0,1,1),0);
        for(k=0;k<1200;k=k+1)put(3,item(2,0,0,0,1,1),item(1,1,0,0,1,1));
        put(3,item(2,0,6,0,1,1),item(1,1,6,0,1,1));tick(12);
        check(good==1&&bad==0,"late real SHORT FE completes old owner after 1200 continuous words");
        put(2,0,item(2,1,7,0,1,1));
        for(k=0;k<1200;k=k+1)put(2,0,item(2,1,0,0,1,1));
        put(2,0,item(2,1,6,0,1,1));tick(12);
        check(writes0>1200&&writes1>2400&&max0<512&&max1<512,"finite512 FIFOs drain continuous abandoned payload");
        check(count0==0&&count1==0&&good==1&&source_good==1,"skipped SHORT never blocks or produces a SOURCE");report("continuous_1200word_late_short");

        cold();begin_pair(1);put(1,item(1,0,6,0,1,1),0);tick(3);
        put(1,item(2,0,7,0,1,1),0);put(1,item(2,0,6,0,1,1),0);
        put(1,item(3,0,7,0,1,1),0);put(3,item(3,0,6,0,1,1),item(1,1,6,0,1,1));tick(8);
        put(2,0,item(2,1,7,0,1,1));put(2,0,item(2,1,6,0,1,1));
        put(2,0,item(3,1,7,0,1,1));put(2,0,item(3,1,6,0,1,1));tick(12);
        check(good==1&&bad==0&&dut.skip_group==3&&count1==0,"skip high water drains more than one future group");
        complete_pair(4);check(good==2,"group above high water is accepted");report("multiple_overlap_groups");

        cold();for(g=1;g<=6;g=g+1)complete_pair(g);
        check(good==6&&bad==0&&source_good==6&&dut.skip_group==0,"normal nonoverlap cycles lose no throughput");report("normal_nonoverlap");
        cold();begin_pair(1);put(1,item(1,0,6,0,1,1),0);tick(3);admit=0;
        put(3,item(2,0,7,0,1,1),item(1,1,6,0,1,1));tick(8);
        for(g=2;g<=4;g=g+1)begin
            put(3,item(g,0,7,0,1,1),item(g,1,7,0,1,1));
            put(3,item(g,0,0,0,1,1),item(g,1,0,0,1,1));
        end
        tick(15);check(quiet&&count0==0&&count1==0&&good==1,"pause drains future input without reopening owner");
        admit=1;put(3,item(4,0,6,0,1,1),item(4,1,6,0,1,1));tick(8);
        complete_pair(5);check(good==2&&bad==0,"resume never accepts partially drained group");report("pause_quiet_resume");

        cold();begin_pair(1);put(1,item(2,0,7,0,1,1),0);tick(8);
        check(bad==1&&good==0&&diag[23:16]==5,"missing LONG FE retains primary-reentry negative");report("missing_long_FE");
        cold();begin_pair(1);put(2,0,item(1,1,7,0,1,1));tick(8);
        check(bad==1&&diag[23:16]==5,"duplicate SHORT FS negative reason5");report("duplicate_short_FS");
        cold();begin_pair(1);put(1,item(1,0,6,0,1,1),0);tick(3);put(1,item(1,0,6,0,1,1),0);tick(8);
        check(bad==1&&diag[23:16]==5,"duplicate FE negative reason5");report("duplicate_FE");
        cold();begin_pair(1);put(2,0,item(1,1,5,1,1,1));tick(8);
        check(bad==1&&diag[23:16]==5,"upstream error5 negative reason5");report("upstream_error5");
        cold();begin_pair(1);put(2,0,item(1,1,2,1,1,1));tick(8);
        check(bad==1&&good==0&&source_bad==1,"CRC negative terminal remains negative");report("CRC_negative");
        cold();begin_pair(1);put(2,0,item(1,1,0,0,0,1));tick(8);
        check(bad==1&&good==0,"invalid matching identity cannot qualify");report("trust_negative");
        cold();begin_pair(1);put(1,item(1,0,6,0,1,1),0);tick(3);
        put(1,item(2,0,7,0,0,1),0);tick(8);
        check(bad==1&&good==0&&diag[23:16]==5,"invalid future FS is not silently skipped");report("future_trust_negative");
        cold();begin_pair(1);epoch=2;tick(8);
        check(bad==1&&good==0&&diag[23:16]==9,"epoch change remains reason9");report("epoch_negative");
        cold();begin_pair(1);stable_force=0;tick(8);
        check(bad==1&&good==0&&diag[23:16]==9,"admitted stable loss remains reason9");report("stable_negative");
        cold();begin_pair(1);put(1,item(1,0,6,0,1,1),0);tick(3);
        put(1,item(2,0,7,0,1,1),0);put(1,item(2,0,6,0,1,1),0);tick(4100);
        check(bad==1&&good==0&&diag[23:16]==11,"missing SHORT FE times out without fake good");
        put(2,0,item(2,1,7,0,1,1));put(2,0,item(2,1,6,0,1,1));tick(8);
        check(count1==0,"timed-out skipped SHORT drains");report("missing_short_timeout");
        cold();begin_pair(1);put(1,item(1,0,6,0,1,1),0);tick(3);
        put(1,item(2,0,7,0,1,1),0);@(negedge clk);push=0;fault=1;tick(8);fault=0;
        put(2,0,item(2,1,7,0,1,1));put(2,0,item(2,1,6,0,1,1));tick(8);
        check(bad==1&&good==0&&count1==0&&dut.skip_group==2,"independent fault tracks simultaneously discarded future LONG");report("fault_during_overlap");
        cold();begin_pair(1);put(1,item(1,0,6,0,1,1),0);tick(3);
        put(1,item(2,0,7,0,1,1),0);tick(8);cold();complete_pair(1);
        check(good==1&&dut.skip_group==0&&cancel_diag==0,"cohort reset clears skip and diagnostic state");report("reset_overlap");

        cold();use_owner=1;
        @(negedge cfg_clk);owner_start=1;@(negedge cfg_clk);owner_start=0;
        limit=0;while(!owner_written&&limit<6000)begin tick(1);limit=limit+1;end
        check(owner_written&&config_writes==139&&!owner_error,"real recipe owner completes139 transaction BFM writes");
        for(k=0;k<8;k=k+1)begin
            g=2*k+1;begin_pair(g);put(1,item(g,0,6,0,1,1),0);tick(3);
            put(3,item(g+1,0,7,0,1,1),item(g,1,6,0,1,1));
            put(3,item(g+1,0,6,0,1,1),item(g+1,1,7,0,1,1));
            put(2,0,item(g+1,1,6,0,1,1));tick(60);
            if(k<7)check(!owner_stable&&raw_count0==0&&raw_count1==0,"warmup retains real good pairs without admitting RAW");
        end
        tick(30);check(good==8&&bad==0&&owner_stable&&stable&&!cdc_overflow,"eight retained real FE pairs reach owner STABLE");
        check(source_good==0&&not_admitted==8,"warmup pairs do not publish SOURCE");
        complete_pair(17);
        check(good==9&&source_good==1&&last_source0==170&&last_source1==171,"first poststable pair publishes actual SOURCE");
        check(raw_count0==1&&raw_count1==1&&!owner_error,"first admission emits both actual RAW groups");report("eight_retained_warmup_first_SOURCE");
        cold();source_ready0=0;source_ready1=0;complete_pair(1);
        check(sourcev0&&sourcev1&&source_ok&&!quiet,"both SOURCE terminals remain valid under backpressure");
        held_source={source_session,source_epoch,source_sequence0,source_sequence1,source_ok,source_error};
        complete_pair(2);
        check(sourcev0&&sourcev1&&{source_session,source_epoch,source_sequence0,source_sequence1,source_ok,source_error}==held_source,
              "unadmitted future pair cannot overwrite held SOURCE payload");
        check(good==2&&not_admitted==1&&raw_count0==1&&raw_count1==1,"held SOURCE prevents subsequent RAW admission");
        source_ready1=1;tick(3);
        check(sourcev0&&!sourcev1&&!quiet&&{source_session,source_epoch,source_sequence0,source_sequence1,source_ok,source_error}==held_source,
              "independent SHORT retirement preserves held LONG terminal");
        tick(32);check(sourcev0&&source_sequence0==10&&source_sequence1==11,"held SOURCE remains stable for finite long stall");
        source_ready0=1;tick(3);check(quiet&&!sourcev0&&!sourcev1,"quiet asserts only after last SOURCE retires");
        complete_pair(3);check(good==3&&raw_count0==2&&raw_count1==2,"next pair admission recovers after SOURCE retirement");
        report("held_SOURCE_independent_retirement_resume");
        $display("RESULT: PASS PAIR_OVERLAP_R3 cases=%0d checks=%0d",cases,checks);$finish;
`endif
    end
endmodule
