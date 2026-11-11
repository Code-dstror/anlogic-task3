`timescale 1ns/1ps
module r3_axis_tb_count;
    reg clk=0;always #4 clk=~clk;
    reg [2:0] release_pipe=0;
    reg read_reset=1,reset_done=0,head_valid=0,head_empty=1,consumer_ready=0;
    reg inject=1,push_offer=0,pop_offer=0;
    reg [146:0] head_data=0;
    wire actual_valid,reference_valid,actual_done,reference_done;
    wire [146:0] actual_data,reference_data;
    r3_axis_actual dut(.i_sink_clk(clk),.sink_reset_release_pipe(release_pipe),
        .fifo_read_reset(read_reset),.fifo_read_reset_done(reset_done),.fifo_valid(head_valid),.fifo_empty(head_empty),
        .fifo_read_data(head_data),.i_sink_ready(consumer_ready),.inject_ops(inject),.injected_push(push_offer),.injected_pop(pop_offer),
        .o_sink_data(actual_data),.o_sink_valid(actual_valid),.o_sink_reset_done(actual_done));
    r3_axis_reference reference(.i_sink_clk(clk),.sink_reset_release_pipe(release_pipe),
        .fifo_read_reset(read_reset),.fifo_read_reset_done(reset_done),.fifo_valid(head_valid),.fifo_empty(head_empty),
        .fifo_read_data(head_data),.i_sink_ready(consumer_ready),.inject_ops(inject),.injected_push(push_offer),.injected_pop(pop_offer),
        .o_sink_data(reference_data),.o_sink_valid(reference_valid),.o_sink_reset_done(reference_done));
    reg expected_run=0;
    reg [1:0] expected_count=0;
    reg expected_head=0,expected_tail=0;
    reg [146:0] expected_buffer[0:1];
    reg [31:0] rng=32'h71261ac9;
    reg taken_push,taken_pop;
    integer checks=0,cycles=0,truth=0,priority_cases=0,writes=0,pops=0,both=0,valid_checks=0;
    integer c,p,q,mode,n;
    task check(input bit okay,input string why);
        begin checks++;if(!okay)$fatal(1,"r3 axis cycle=%0d %s count=%b/%b expected=%b pushpop=%b%b run=%b/%b",cycles,why,
            dut.read_count,reference.read_count,expected_count,dut.fifo_read_enable,dut.sink_fire,dut.sink_run,reference.sink_run);end
    endtask
    always @(posedge clk)begin
        cycles++;
        taken_push=dut.fifo_read_enable;taken_pop=dut.sink_fire;
        check(taken_push===reference.fifo_read_enable&&taken_pop===reference.sink_fire,"actual handshakes exact");
        if(!release_pipe[2]||!expected_run)begin
            expected_count=0;expected_head=0;expected_tail=0;
        end else begin
            if(taken_push)begin expected_buffer[expected_tail]=head_data;expected_tail=!expected_tail;writes++;end
            if(taken_pop)begin expected_head=!expected_head;pops++;end
            case({taken_push,taken_pop})
                2'b10:expected_count=(expected_count+1)&3;
                2'b01:expected_count=(expected_count-1)&3;
                default:begin end
            endcase
            if(taken_push&&taken_pop)both++;
        end
        expected_run=!read_reset&&reset_done;
        #1;
        check({dut.read_count,dut.read_head,dut.read_tail,dut.sink_run}===
            {reference.read_count,reference.read_head,reference.read_tail,reference.sink_run},"entire sink state cycle-equivalent");
        check({dut.read_count,dut.read_head,dut.read_tail,dut.sink_run}===
            {expected_count,expected_head,expected_tail,expected_run},"independent modulo count and pointer scoreboard");
        check(dut.read_buffer[0]===reference.read_buffer[0]&&dut.read_buffer[1]===reference.read_buffer[1],"all294 payload bits exact including invalid states");
        check(dut.read_buffer[0]===expected_buffer[0]&&dut.read_buffer[1]===expected_buffer[1],"only actual permitted prefetch writes storage");
        check({actual_valid,actual_done}==={reference_valid,reference_done},"valid/resetdone exact");
        check(actual_valid==((release_pipe[2]&&expected_run)&&(expected_count!=0)),"valid independent occupancy model");
        if(actual_valid)begin
            check(actual_data===reference_data&&actual_data===expected_buffer[expected_head],"all147 valid data bits exact");valid_checks++;
        end
    end
    task truth_case(input integer count_value,push_value,pop_value,priority_mode);
        begin
            @(negedge clk);push_offer=0;pop_offer=0;
            release_pipe=priority_mode==1?0:7;read_reset=priority_mode==2;reset_done=priority_mode!=2;
            repeat(2)@(negedge clk);
            force dut.read_count=count_value;force reference.read_count=count_value;
            force dut.read_head=count_value[0];force reference.read_head=count_value[0];
            force dut.read_tail=count_value[1];force reference.read_tail=count_value[1];
            expected_count=count_value;expected_head=count_value[0];expected_tail=count_value[1];
            #1;release dut.read_count;release reference.read_count;
            release dut.read_head;release reference.read_head;release dut.read_tail;release reference.read_tail;
            push_offer=push_value!=0;pop_offer=pop_value!=0;head_data={19'h12345,32'(count_value),32'(push_value),32'(pop_value),32'(priority_mode)};
            @(posedge clk);#2;
            if(priority_mode==0)begin
                check(dut.read_count==((count_value+push_value-pop_value)&3),"all4 states all4 operations modulo4");truth++;
            end else begin check(dut.read_count==0&&dut.read_head==0&&dut.read_tail==0,"reset/run suppression wins over both operations");priority_cases++;end
        end
    endtask
    initial begin
        repeat(3)@(negedge clk);
        for(mode=0;mode<3;mode++)for(c=0;c<4;c++)for(p=0;p<2;p++)for(q=0;q<2;q++)truth_case(c,p,q,mode);
        // Continuous walks include all mathematically valid states, then the
        // unchanged real prefetch/consumer equations with bounded stalls.
        for(n=0;n<12000;n++)begin
            @(negedge clk);rng=rng^(rng<<13);rng=rng^(rng>>17);rng=rng^(rng<<5);
            inject=n<6000;push_offer=rng[0];pop_offer=rng[1];
            head_valid=rng[2]|rng[3];head_empty=!head_valid;consumer_ready=rng[4]|rng[5];
            release_pipe=n%173==0?0:7;read_reset=rng[12:6]==0;reset_done=rng[18:13]!=0;
            head_data={19'h53412,rng,~rng,rng^32'hab132f64,rng+32'd1};
        end
        @(negedge clk);inject=0;head_valid=0;head_empty=1;consumer_ready=1;
        release_pipe=0;repeat(3)@(negedge clk);
        check(truth==16&&priority_cases==32&&writes>1000&&pops>1000&&both>500&&valid_checks>1000,"required risk coverage");
        $display("RESULT: PASS r3_axis_count checks=%0d cycles=%0d truth=%0d reset_run_priority=%0d writes=%0d pops=%0d simultaneous=%0d valid_data_checks=%0d",
            checks,cycles,truth,priority_cases,writes,pops,both,valid_checks);$finish;
    end
    initial begin #200000;$fatal(1,"r3 axis watchdog");end
endmodule
