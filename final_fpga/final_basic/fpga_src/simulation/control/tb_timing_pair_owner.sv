`timescale 1ns/1ps
`include "pcie_protocol_v1.vh"
module tb_timing_pair_owner;
    reg i_clk=0;
    always #4 i_clk=~i_clk;
__DECLARATIONS__
    integer checks=0,math_checks=0,accepted_count=0,rejected_count=0;
    integer pairs=0,read_words=0,stalled_reads=0,finish_count=0;
    integer seq_checks=0,time_checks=0,reset_count=0,k,j,n,timeout;
    reg [63:0] rng=64'h6957264a9013bb12;
    reg [383:0] stored_frame[0:3];
    reg [31:0] stored_generation[0:3];
    reg [63:0] stored_lease[0:3];
    reg [1:0] last_slot;
    reg [63:0] held_pair_id;
    reg held_pair_bank;
    reg last_accepted;
    reg [31:0] seqs[0:1];
    reg [31:0] seq_edges[0:4];
    reg [63:0] time_edges[0:5];
    reg [31:0] limits[0:4];
    hdr_pair_bank_owner_dual #(.WIDTH(24),.HEIGHT(3)) dut(
__DUT_PORTS__);
    timing_pair_owner_reference #(.WIDTH(24),.HEIGHT(3)) reference(
__REFERENCE_PORTS__);

    task check(input bit okay,input string why);
        begin checks=checks+1;if(!okay)$fatal(1,"pair owner check=%0d %s state=%0d ref=%0d now=%h",checks,why,dut.state,reference.state,i_now);end
    endtask
    task step;
        begin
            @(posedge i_clk);#1;
            check({__OUTPUTS_DUT__} === {__OUTPUTS_REFERENCE__},"all outputs cycle-equivalent");
            check({dut.state,dut.active_valid,dut.sequence_seen,dut.turn,dut.allocation_serial,
                   dut.bank_state[0],dut.bank_state[1],dut.bank_seen[0],dut.bank_seen[1],
                   dut.bank_busy[0],dut.bank_busy[1],dut.bank_done[0],dut.bank_done[1],
                   dut.bank_bad[0],dut.bank_bad[1],dut.bank_serial[0],dut.bank_serial[1]} ===
                  {reference.state,reference.active_valid,reference.sequence_seen,reference.turn,reference.allocation_serial,
                   reference.bank_state[0],reference.bank_state[1],reference.bank_seen[0],reference.bank_seen[1],
                   reference.bank_busy[0],reference.bank_busy[1],reference.bank_done[0],reference.bank_done[1],
                   reference.bank_bad[0],reference.bank_bad[1],reference.bank_serial[0],reference.bank_serial[1]},
                  "ownership, fairness and state cycle-equivalent");
            @(negedge i_clk);
        end
    endtask
    task random_next;
        begin rng=rng^(rng<<13);rng=rng^(rng>>7);rng=rng^(rng<<17);end
    endtask
    task arithmetic_check(input [63:0] clock_value,origin,input [31:0] limit,input [31:0] newer,older);
        reg [63:0] age;
        reg [31:0] delta;
        begin
            age=clock_value-origin;delta=newer-older;
            check(dut.within_window(clock_value,origin,limit)==(age<{32'd0,limit}),"split age exact modulo64");
            check(dut.sequence_forward(newer,older)==(delta!=0&&!delta[31]),"parallel sequence exact modulo32");
            math_checks=math_checks+1;
        end
    endtask
    task clear_inputs;
        begin
__INITIALIZE__
            i_read_quiet=1;i_write_quiet=1;i_ticket_released=1;m_directory_ready=1;
            i_session=7;i_epoch=9;i_ratio_log2=4;i_hdr_enable=1;
            i_max_delta=100000;i_max_wait=1000;i_max_age=100000;
            i_now=64'h0000000100000010;
            seqs[0]=0;seqs[1]=0;
        end
    endtask
    task cold_reset;
        begin
            i_identity_rst_n=0;reset_count=reset_count+1;#1;
            check(dut.state==0&&reference.state==0&&!dut_o_capture_busy&&!dut_o_pair_valid,"cold reset revokes ownership");
            repeat(3)step();i_identity_rst_n=1;repeat(2)step();
        end
    endtask
    task configure;
        begin
            i_config_valid=1;timeout=0;
            while(!dut_o_config_ready)begin step();timeout=timeout+1;check(timeout<100,"config bounded response");end
            step();check(!dut_o_config_error,"valid configuration accepted");i_config_valid=0;step();
        end
    endtask
    task make_frame(input bit member,input [31:0] sequence_id,group_id,input [63:0] timestamp);
        begin
            s_frame=0;i_begin_member=member;
            s_frame[0]=1;s_frame[2:1]=member?2:1;s_frame[3]=`PCIE_RECORD_V2_SOURCE_PHYSICAL;
            s_frame[76:45]=i_session;s_frame[108:77]=sequence_id;s_frame[140:109]=i_epoch;
            s_frame[204:141]=timestamp;s_frame[220:205]=24;s_frame[236:221]=3;s_frame[238:237]=1;
            s_frame[270:239]=32'h56a3d02f;s_frame[302:271]=member?200:3200;
            s_frame[334:303]=256;s_frame[366:335]=group_id;
        end
    endtask
    task request(input integer interrupt_at);
        integer wait_cycles;
        begin
            s_begin_valid=1;wait_cycles=0;
            while(!dut_s_begin_ready)begin
                if(interrupt_at==1&&dut.state==4)i_stop=1;
                if(interrupt_at==2&&dut.state==2)i_stop=1;
                if(interrupt_at==3&&dut.state==2)i_config_valid=1;
                step();wait_cycles=wait_cycles+1;check(wait_cycles<100,"descriptor hold bounded response");
            end
            last_accepted=dut_o_begin_accepted;last_slot=dut_o_capture_slot;
            if(last_accepted)begin
                accepted_count=accepted_count+1;stored_frame[last_slot]=s_frame;
                stored_generation[last_slot]=dut_o_capture_generation;stored_lease[last_slot]=dut_o_capture_lease;
            end else rejected_count=rejected_count+1;
            step();s_begin_valid=0;i_stop=0;i_config_valid=0;step();
        end
    endtask
    task offer(input bit member,input [31:0] sequence_id,group_id,input [63:0] timestamp,input bit expect_accept);
        begin make_frame(member,sequence_id,group_id,timestamp);request(0);check(last_accepted==expect_accept,"admission expected decision");end
    endtask
    task finish(input bit member,okay);
        begin
            if(member)begin check(dut_o_finish1_ready,"SHORT owns finish");i_finish1_valid=1;i_finish1_ok=okay;end
            else begin check(dut_o_finish_ready,"LONG owns finish");i_finish_valid=1;i_finish_ok=okay;end
            step();i_finish1_valid=0;i_finish_valid=0;finish_count=finish_count+1;step();
        end
    endtask
    task expect_empty;
        integer cycles;
        begin cycles=0;while(!dut_o_empty)begin step();cycles=cycles+1;check(cycles<40,"retirement bounded");end end
    endtask
    task read_slot(input [1:0] slot);
        integer words,wait_cycles;
        reg [31:0] expected;
        reg [35:0] held_word;
        begin
            i_directory_read_valid=1;i_directory_read_slot=slot;wait_cycles=0;
            while(!dut_o_directory_read_ready)begin step();wait_cycles=wait_cycles+1;check(wait_cycles<20,"directory request bounded");end
            m_directory_ready=0;step();i_directory_read_valid=0;
            held_word={dut_m_directory_word,dut_m_directory_data};
            repeat(5)begin
                check(dut_m_directory_valid&&{dut_m_directory_word,dut_m_directory_data}===held_word,"directory stall retains word");
                check(!dut_o_release_ready,"active directory read blocks release");stalled_reads=stalled_reads+1;step();
            end
            words=0;wait_cycles=0;
            while(words<16)begin
                random_next();m_directory_ready=rng[0]|rng[1];
                if(dut_m_directory_valid&&m_directory_ready)begin
                    expected=0;
                    case(words)
                        0:expected={25'd0,slot,stored_frame[slot][4:0]};
                        1:expected=stored_generation[slot];
                        2:expected=stored_frame[slot][76:45];
                        3:expected=stored_frame[slot][108:77];
                        4:expected=stored_frame[slot][140:109];
                        5:expected=stored_frame[slot][172:141];
                        6:expected=stored_frame[slot][204:173];
                        7:expected=stored_frame[slot][236:205];
                        8:expected=stored_frame[slot][302:271];
                        9:expected=stored_frame[slot][334:303];
                        10:expected=stored_frame[slot][270:239];
                        11:expected=stored_frame[slot][366:335];
                        12:expected=stored_lease[slot][31:0];
                        13:expected=stored_lease[slot][63:32];
                        14:expected={30'd0,stored_frame[slot][238:237]};
                        default:expected=0;
                    endcase
                    check(dut_m_directory_word==words&&dut_m_directory_last==(words==15),"directory ordering and boundary");
                    check(dut_m_directory_data===expected,"directory independent descriptor scoreboard");
                    words=words+1;read_words=read_words+1;
                end
                step();wait_cycles=wait_cycles+1;check(wait_cycles<100,"finite directory stall drains");
            end
            m_directory_ready=1;step();
        end
    endtask
    task acquire_release(input bit read_directory);
        integer cycles;
        begin
            cycles=0;while(!dut_o_pair_valid)begin step();cycles=cycles+1;check(cycles<40,"completed pair becomes ready");end
            held_pair_bank=dut_o_pair_bank;held_pair_id=dut_o_pair_id;
            repeat(4)begin check(dut_o_pair_valid&&dut_o_pair_bank==held_pair_bank&&dut_o_pair_id==held_pair_id,"held offer identity stable");step();end
            i_pair_ready=1;step();i_pair_ready=0;step();pairs=pairs+1;
            if(read_directory)begin read_slot({held_pair_bank,1'b0});read_slot({held_pair_bank,1'b1});end
            i_release_valid=1;i_release_bank=held_pair_bank;i_release_pair_id=held_pair_id;i_read_quiet=0;#1;
            repeat(3)begin check(!dut_o_release_ready,"read pin blocks release");step();end
            i_read_quiet=1;i_write_quiet=0;step();check(!dut_o_release_ready,"write pin blocks release");
            i_write_quiet=1;i_ticket_released=0;step();check(!dut_o_release_ready,"ticket blocks release");
            i_ticket_released=1;#1;check(dut_o_release_ready,"matching quiet release allowed");step();i_release_valid=0;step();
        end
    endtask
    initial begin
        clear_inputs();
        seq_edges[0]=0;seq_edges[1]=1;seq_edges[2]=32'h7fffffff;seq_edges[3]=32'h80000000;seq_edges[4]=32'hffffffff;
        time_edges[0]=0;time_edges[1]=1;time_edges[2]=64'hffffffff;time_edges[3]=64'h100000000;
        time_edges[4]=64'hffffffff00000000;time_edges[5]=64'hffffffffffffffff;
        limits[0]=0;limits[1]=1;limits[2]=32'h7fffffff;limits[3]=32'h80000000;limits[4]=32'hffffffff;
        for(k=0;k<5;k=k+1)for(j=0;j<5;j=j+1)for(n=0;n<5;n=n+1)
            arithmetic_check(time_edges[k],time_edges[j],limits[n],seq_edges[k],seq_edges[j]);
        for(k=0;k<6;k=k+1)begin
            arithmetic_check(time_edges[k]+1,time_edges[k],1,32'h80000000,0);
            arithmetic_check(time_edges[k]+1,time_edges[k],2,32'hffffffff,32'h7fffffff);
            arithmetic_check(time_edges[k],time_edges[k],0,1,1);
        end
        for(k=0;k<30000;k=k+1)begin
            random_next();
            case(k%6)
                0:arithmetic_check(rng,rng,rng[31:0],rng[31:0],rng[63:32]);
                1:arithmetic_check(rng+{32'd0,rng[31:0]}-1,rng,rng[31:0],rng[31:0],rng[31:0]-1);
                2:arithmetic_check(rng+{32'd0,rng[31:0]},rng,rng[31:0],rng[31:0],rng[31:0]-32'h80000000);
                3:arithmetic_check(rng+{32'd0,rng[31:0]}+1,rng,rng[31:0],rng[31:0],rng[31:0]);
                4:arithmetic_check(rng-1,rng,rng[31:0],rng[31:0],rng[31:0]+1);
                5:arithmetic_check({rng[31:0],rng[63:32]},rng,rng[31:0],rng[31:0],rng[63:32]);
            endcase
        end
        cold_reset();configure();
        // Independent simultaneous writers and sequence wrap for each role.
        offer(0,32'hffffffff,1,i_now-30,1);offer(1,32'hfffffffe,1,i_now-10,1);
        check(dut_o_capture_busy&&dut.active_valid==3,"both member writers retain ownership");
        finish(1,1);check(!dut_o_pair_valid,"one finish cannot publish");finish(0,1);
        acquire_release(1);expect_empty();
        offer(0,0,2,i_now-20,1);finish(0,1);
        offer(0,1,3,i_now-20,1);finish(0,1);
        offer(1,32'hffffffff,2,i_now-5,1);finish(1,1);
        offer(1,0,3,i_now-5,1);finish(1,1);
        check(dut.bank_state[0]==4&&dut.bank_state[1]==4,"both complete banks retained");
        acquire_release(1);acquire_release(0);expect_empty();
        // Exact duplicate, reverse and half-circle deltas are all rejected.
        offer(0,1,10,i_now-1,0);offer(0,0,11,i_now-1,0);offer(0,32'h80000001,12,i_now-1,0);
        offer(0,32'h80000000,13,i_now-1,1);finish(0,0);expect_empty();
        make_frame(0,32'h80000001,14,i_now-1);i_begin_member=1;request(0);check(!last_accepted,"trusted role mismatch rejects");
        make_frame(0,32'h80000001,15,i_now-1);s_frame[334:303]=257;request(0);check(!last_accepted,"gain mismatch rejects");
        make_frame(0,32'h80000001,16,i_now-1);s_frame[270:239]=0;request(0);check(!last_accepted,"recipe mismatch rejects");
        offer(0,32'h80000001,17,i_now+1,0);offer(0,32'h80000001,18,i_now-i_max_age,0);
        // Illegal zero timeout and same-identity parameter changes cannot apply.
        i_config_valid=1;i_max_wait=0;check(dut_o_config_ready,"invalid zero window answers");step();
        check(dut_o_config_error&&dut.max_wait==1000,"zero window rejected without mutation");i_config_valid=0;i_max_wait=1000;step();
        // Strict timeout boundary, including low-word borrow and full64 wrap.
        clear_inputs();cold_reset();i_now=64'hfffffffffffffff0;i_max_wait=32;configure();
        offer(0,1,40,i_now-1,1);finish(0,1);i_now=64'h000000000000000f;step();
        check(dut.bank_state[last_slot[1]]==1,"age max_wait-1 remains building");
        i_now=64'h0000000000000010;step();check(dut_o_expire_count==1,"age max_wait expires exactly");expect_empty();
        // Active writer protects its bank past timeout; matching other role can join.
        // A wrapped timestamp cannot pass the separate monotonic source check
        // without a new cold identity. The timeout's modulo wrap is independent.
        clear_inputs();cold_reset();i_now=100;i_max_wait=32;configure();
        offer(0,2,41,99,1);i_now=200;offer(1,1,41,199,1);
        finish(0,1);finish(1,1);acquire_release(0);expect_empty();
        // STOP during WRITE and SCAN drains held ADMIT negatively.
        make_frame(0,3,42,i_now-1);request(1);check(!last_accepted,"STOP at held WRITE reply denies");expect_empty();
        offer(0,3,43,i_now-10,1);finish(0,1);
        make_frame(1,2,43,i_now-1);request(2);check(!last_accepted,"STOP during SCAN denies");expect_empty();
        // Same config arriving during SCAN keeps original publication boundaries.
        offer(0,4,44,i_now-10,1);finish(0,1);
        make_frame(1,2,44,i_now-1);request(3);check(last_accepted,"same config during SCAN retains decision");
        finish(1,1);acquire_release(0);expect_empty();
        // Sustained complete groups exercise allocation fairness and both role orders.
        clear_inputs();cold_reset();configure();
        for(k=1;k<=80;k=k+1)begin
            random_next();i_now=i_now+(rng[5:0]+1);
            if(rng[6])begin offer(0,k,k,i_now-2,1);offer(1,k,k,i_now-1,1);end
            else begin offer(1,k,k,i_now-1,1);offer(0,k,k,i_now-2,1);end
            if(rng[7])begin finish(1,1);finish(0,1);end
            else begin finish(0,1);finish(1,1);end
            acquire_release(k%13==0);expect_empty();
        end
        // Cold identity reset during an owned serial directory write.
        make_frame(0,81,1000,i_now-1);s_begin_valid=1;
        while(dut.state!=4)step();cold_reset();s_begin_valid=0;expect_empty();configure();
        check(!dut_o_fault&&accepted_count>150&&pairs>80&&read_words>100,"coverage and clean recovery");
        $display("RESULT: PASS timing_pair_owner checks=%0d math_vectors=%0d accepted=%0d rejected=%0d pairs=%0d directory_words=%0d stalled_reads=%0d finishes=%0d resets=%0d",
            checks,math_checks,accepted_count,rejected_count,pairs,read_words,stalled_reads,finish_count,reset_count);
        $finish;
    end
    initial begin #2000000;$fatal(1,"watchdog");end
endmodule
