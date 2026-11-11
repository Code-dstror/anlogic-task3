`timescale 1ns/1ps
`include "pcie_protocol_v1.vh"

// Actual ingress/writer, bounded single-clock FIFO, and an AXI endpoint.
// The endpoint inserts finite AW/W/B stalls, including every last W beat.
module hdr_overlap_member #(parameter MEMBER=0,W=16,H=2)(
    input wire clk,rst,stop,
    input wire [39:0] raw,input wire raw_valid,raw_sof,raw_eol,raw_abort,
    input wire [31:0] session,epoch,capture_sequence,
    input wire [196:0] metadata,
    input wire source_valid,source_ok,input wire [7:0] source_error,
    input wire [31:0] source_session,source_epoch,source_sequence,
    output wire source_ready,capture_idle,quiet,fault,
    output wire [383:0] frame,
    output wire begin_valid,input wire begin_ready,begin_accepted,input wire [1:0] slot,
    output wire finish_valid,finish_ok,input wire finish_ready,
    input wire fail_b,
    output wire [31:0] stale,errors,
    output reg [31:0] b_count=0,pixel_byte_checks=0
);
    wire [127:0] enq_data;wire [15:0] enq_keep;wire [1:0] enq_user;
    wire enq_valid,enq_last;
    wire [31:0] drops;
    shared_raw10_frame_ingress #(.WIDTH(W),.HEIGHT(H),.CONTEXT_ENABLE(1),
        .EXTERNAL_SEQUENCE_ENABLE(1),.PAIR_METADATA_ENABLE(1),.SOURCE_TERMINAL_ENABLE(1)) ingress(
        .i_clk(clk),.i_rst_n(rst),.i_enable(1'b1),.i_data(raw),.i_valid(raw_valid),.i_accept(1'b1),
        .i_sof(raw_sof),.i_eol(raw_eol),.i_abort(raw_abort),.i_camera(1'b0),.i_epoch(epoch),
        .i_external_sequence(capture_sequence),.i_session_id(session),.i_sdr_profile(1'b0),.i_bayer_valid(1'b1),
        .i_time_valid(1'b1),.i_bayer_pattern(2'd0),.i_metadata_valid(metadata[196]),
        .i_timestamp(metadata[63:0]),.i_actual_exposure(metadata[95:64]),.i_gain(metadata[127:96]),
        .i_calibration_id(metadata[159:128]),.i_source_kind(metadata[192]),
        .i_exposure_role(metadata[194:193]),.i_exposure_group(metadata[191:160]),
        .i_source_qualified(metadata[195]),.i_source_valid(source_valid),.o_source_ready(source_ready),
        .i_source_session(source_session),.i_source_epoch(source_epoch),.i_source_sequence(source_sequence),
        .i_source_camera(1'b0),.i_source_ok(source_ok),.i_source_error(source_error),
        .o_source_stale_count(stale),.o_axis_tdata(enq_data),.o_axis_tkeep(enq_keep),
        .o_axis_tvalid(enq_valid),.i_axis_tready(1'b1),.o_axis_tlast(enq_last),.o_axis_tuser(enq_user),
        .o_capture_idle(capture_idle),.o_frame_accept(),.o_drop_count(drops),.o_error_count(errors));
    reg [146:0] fifo[0:511];integer head=0,tail=0,count=0;
    wire deq_ready;wire [146:0] deq=fifo[head];
    wire deq_valid=count!=0;
    always @(posedge clk)begin
        if(!rst)begin head<=0;tail<=0;count<=0;end
        else begin
            if(enq_valid)begin
                if(count==512)$fatal(1,"bounded capture FIFO overflow");
                fifo[tail]<={enq_user,enq_last,enq_keep,enq_data};tail<=(tail+1)%512;
            end
            if(deq_valid&&deq_ready)head<=(head+1)%512;
            count<=count+integer'(enq_valid)-integer'(deq_valid&&deq_ready);
        end
    end
    wire [3:0] awid;wire [7:0] awlen;wire awvalid,awready,wvalid,wready,wlast,bready;
    wire [127:0] wdata;wire [15:0] wstrb;
    reg active=0,bvalid=0,waiting_b=0;reg [3:0] bid=0;
    reg [1:0] bresp=0;integer beats=0,phase=0,last_stall=0,b_delay=0,bytes_written=0;
    assign awready=!active&&!bvalid&&!waiting_b&&phase%7!=0;
    assign wready=active&&phase%5!=0&&(!wlast||last_stall>=3);
    shared_raw_capture_writer #(.WIDTH(W),.HEIGHT(H),.AXI_ID(MEMBER+1)) writer(
        .i_clk(clk),.i_identity_rst_n(rst),.i_stop(stop),.i_sdr_profile(1'b0),
        .s_data(deq[127:0]),.s_keep(deq[143:128]),.s_user(deq[146:145]),.s_last(deq[144]),
        .s_valid(deq_valid),.s_ready(deq_ready),.i_available(10'(count)),.o_frame(frame),
        .o_begin_valid(begin_valid),.i_begin_ready(begin_ready),.i_begin_accepted(begin_accepted),
        .i_capture_slot(slot),.o_finish_valid(finish_valid),.o_finish_ok(finish_ok),
        .i_finish_ready(finish_ready),.o_quiet(quiet),.o_protocol_fault(fault),
        .o_success_count(),.o_error_count(),.m_axi_awid(awid),.m_axi_awaddr(),.m_axi_awlen(awlen),
        .m_axi_awsize(),.m_axi_awburst(),.m_axi_awvalid(awvalid),.m_axi_awready(awready),
        .m_axi_wdata(wdata),.m_axi_wstrb(wstrb),.m_axi_wlast(wlast),.m_axi_wvalid(wvalid),
        .m_axi_wready(wready),.m_axi_bid(bid),.m_axi_bresp(bresp),.m_axi_bvalid(bvalid),.m_axi_bready(bready));
    function automatic [39:0] expected_raw(input integer group);
        begin expected_raw={10'(group+MEMBER+31),10'(group+MEMBER+17),10'(group+MEMBER+7),10'(group+MEMBER+1)};end
    endfunction
    integer lane;reg [39:0] expected;
    always @(posedge clk)begin
        if(!rst)begin
            active<=0;bvalid<=0;waiting_b<=0;beats<=0;phase<=0;last_stall<=0;b_delay<=0;
            b_count<=0;pixel_byte_checks<=0;bytes_written<=0;bid<=0;bresp<=0;
        end else begin
            phase<=phase+1;
            if(begin_valid&&begin_ready&&begin_accepted)bytes_written<=0;
            if(awvalid&&awready)begin active<=1;beats<=awlen+1;bid<=awid;last_stall<=0;end
            if(wvalid&&wlast&&active&&!wready)last_stall<=last_stall+1;
            if(wvalid&&wready)begin
                if(wlast!=(beats==1))$fatal(1,"real writer WLAST mismatch");
                expected=expected_raw(frame[366:335]);
                for(lane=0;lane<16;lane=lane+1)if(wstrb[lane])begin
                    if(wdata[lane*8+:8]!==8'(expected>>(((bytes_written+lane)%5)*8)))
                        $fatal(1,"RAW byte mismatch member=%0d group=%0d offset=%0d",MEMBER,frame[366:335],bytes_written+lane);
                end
                pixel_byte_checks<=pixel_byte_checks+$countones(wstrb);
                bytes_written<=bytes_written+$countones(wstrb);beats<=beats-1;
                if(wlast)begin active<=0;waiting_b<=1;b_delay<=7;bresp<=fail_b?2:0;end
            end
            if(waiting_b)begin
                if(b_delay==0)begin waiting_b<=0;bvalid<=1;end else b_delay<=b_delay-1;
            end
            if(bvalid&&bready)begin bvalid<=0;b_count<=b_count+1;end
        end
    end
endmodule

module tb_hdr_overlap;
    reg clk=0;always #4 clk=~clk;
    reg rst=0,admit=1,stable=1,fault=0,stop=0,block0=0,block1=0;
    reg [31:0] session=17,epoch=3;reg [63:0] now=100;
    always @(posedge clk)if(rst)now<=now+1;
    reg [146:0] in0=0,in1=0;reg valid0=0,valid1=0;
    wire ready0,ready1;
    wire [39:0] raw[0:1];wire [1:0] rv,sof,eol,abort,sv,sok,sready,idle,quiet,writer_fault;
    wire [31:0] seq[0:1],ss[0:1],se[0:1],sq[0:1],capture_session,capture_epoch,good,bad,not_admitted;
    wire [7:0] serr[0:1];wire [196:0] meta[0:1];wire pair_event,pair_ok,gate_quiet;
    wire [31:0] diag;
    real_hdr_pair_cycle_gate #(.TIMEOUT_CYCLES(1024)) gate(
        .i_clk(clk),.i_reset_n(rst),.i_fault(fault),.i_stable(stable),.i_admit_enable(admit),
        .i_session(session),.i_epoch(epoch),.i_time(now),.i_time_valid(1'b1),
        .i_capture0_idle(idle[0]),.i_capture1_idle(idle[1]),.s0_data(in0),.s1_data(in1),
        .s0_valid(valid0),.s1_valid(valid1),.s0_ready(ready0),.s1_ready(ready1),
        .m0_data(raw[0]),.m1_data(raw[1]),.m0_valid(rv[0]),.m1_valid(rv[1]),
        .m0_sof(sof[0]),.m1_sof(sof[1]),.m0_eol(eol[0]),.m1_eol(eol[1]),.m0_abort(abort[0]),.m1_abort(abort[1]),
        .o_sequence0(seq[0]),.o_sequence1(seq[1]),.o_session(capture_session),.o_epoch(capture_epoch),
        .o_metadata0(meta[0]),.o_metadata1(meta[1]),.o_source0_valid(sv[0]),.o_source1_valid(sv[1]),
        .i_source0_ready(sready[0]&&!block0),.i_source1_ready(sready[1]&&!block1),
        .o_source_session(ss[0]),.o_source_epoch(se[0]),.o_source0_sequence(sq[0]),.o_source1_sequence(sq[1]),
        .o_source_ok(sok[0]),.o_source_error(serr[0]),
`ifndef OLD_GATE
        .o_source1_session(ss[1]),.o_source1_epoch(se[1]),.o_source1_ok(sok[1]),.o_source1_error(serr[1]),
`endif
        .o_pair_event(pair_event),.o_pair_ok(pair_ok),.o_good_pairs(good),.o_bad_pairs(bad),
        .o_not_admitted_pairs(not_admitted),.o_diag_pair(diag),.o_diag_counts(),.o_quiet(gate_quiet));
`ifdef OLD_GATE
    assign ss[1]=ss[0];assign se[1]=se[0];assign sok[1]=sok[0];assign serr[1]=serr[0];
`endif
    wire [383:0] frame[0:1];wire [1:0] begin_valid,begin_ready,finish_valid,finish_ok,finish_ready;
    wire [31:0] stale[0:1],errors[0:1],bcount[0:1],bytechecks[0:1];reg [1:0] fail_b=0;
    wire owner_ready,accepted;wire [1:0] slot;
    reg offer=0,offer_member=0;wire offer_fire=offer&&begin_valid[offer_member]&&owner_ready;
    assign begin_ready[0]=offer&&!offer_member&&owner_ready;
    assign begin_ready[1]=offer&&offer_member&&owner_ready;
    always @(posedge clk)begin
        if(!rst)begin offer<=0;offer_member<=0;end
        else if(offer_fire)offer<=0;
        else if(!offer&&(|begin_valid))begin offer<=1;offer_member<=!begin_valid[0];end
    end
    genvar m;
    generate for(m=0;m<2;m=m+1)begin:member
        hdr_overlap_member #(.MEMBER(m)) pipe(
            .clk(clk),.rst(rst),.stop(stop),.raw(raw[m]),.raw_valid(rv[m]),.raw_sof(sof[m]),
            .raw_eol(eol[m]),.raw_abort(abort[m]),.session(capture_session),.epoch(capture_epoch),.capture_sequence(seq[m]),
            .metadata(meta[m]),.source_valid(sv[m]&&!(m==0?block0:block1)),.source_ok(sok[m]),.source_error(serr[m]),
            .source_session(ss[m]),.source_epoch(se[m]),.source_sequence(sq[m]),.source_ready(sready[m]),
            .capture_idle(idle[m]),.quiet(quiet[m]),.fault(writer_fault[m]),.frame(frame[m]),
            .begin_valid(begin_valid[m]),.begin_ready(begin_ready[m]),.begin_accepted(accepted),.slot(slot),
            .finish_valid(finish_valid[m]),.finish_ok(finish_ok[m]),.finish_ready(finish_ready[m]),
            .fail_b(fail_b[m]),.stale(stale[m]),.errors(errors[m]),.b_count(bcount[m]),.pixel_byte_checks(bytechecks[m]));
    end endgenerate
    reg config_valid=0,release_valid=0,release_bank=0;reg [63:0] release_id=0;
    wire config_ready,config_error,bank_fault,bank_empty,product,product_bank,release_ready;
    wire [63:0] product_id;wire [5:0] bank_states;
    hdr_pair_bank_owner_dual #(.WIDTH(16),.HEIGHT(2),.DOL2_ENABLE(1)) bank(
        .i_clk(clk),.i_identity_rst_n(rst),.i_stop(stop),.i_transport_fault(1'b0),.i_now(now),
        .i_config_valid(config_valid),.o_config_ready(config_ready),.i_session(session),.i_epoch(epoch),
        .i_max_delta(32'd2000),.i_max_wait(32'd4000),.i_max_age(32'd50000),
        .i_ratio_log2(3'd4),.i_hdr_enable(1'b1),.o_config_error(config_error),
        .s_frame(frame[offer_member]),.s_begin_valid(offer&&begin_valid[offer_member]),
        .s_begin_ready(owner_ready),.o_begin_accepted(accepted),.o_capture_slot(slot),.o_capture_generation(),.o_capture_lease(),
        .i_begin_member(offer_member),.i_finish_valid(finish_valid[0]),.i_finish_ok(finish_ok[0]),.o_finish_ready(finish_ready[0]),
        .i_finish1_valid(finish_valid[1]),.i_finish1_ok(finish_ok[1]),.o_finish1_ready(finish_ready[1]),
        .o_pair_valid(product),.i_pair_ready(!release_valid),.o_pair_bank(product_bank),.o_pair_id(product_id),
        .i_release_valid(release_valid),.i_release_bank(release_bank),.i_release_pair_id(release_id),
        .i_read_quiet(1'b1),.i_write_quiet(&quiet),.i_ticket_released(1'b1),.o_release_ready(release_ready),
        .i_directory_read_valid(1'b0),.i_directory_read_slot(2'd0),.o_directory_read_ready(),
        .m_directory_data(),.m_directory_word(),.m_directory_valid(),.m_directory_last(),.m_directory_ready(1'b0),
        .o_empty(bank_empty),.o_capture_busy(),.o_exhausted(),.o_fault(bank_fault),.o_bank_states(bank_states),
        .o_reject_count(),.o_expire_count());
    integer checks=0,products=0,term0=0,term1=0,abort0=0,abort1=0;
    integer finish_good0[0:255],finish_good1[0:255],product_count[0:255];
    reg [136:0] held0=0,held1=0;reg stalled0=0,stalled1=0;
    reg [31:0] previous_b0=0,previous_b1=0;
    integer idx;
    always @(posedge clk)begin
        if(!rst)begin
            products=0;term0=0;term1=0;abort0=0;abort1=0;release_valid<=0;stalled0=0;stalled1=0;
            previous_b0=0;previous_b1=0;
            for(idx=0;idx<256;idx=idx+1)begin finish_good0[idx]=0;finish_good1[idx]=0;product_count[idx]=0;end
        end else begin
            if(writer_fault!=0||bank_fault)$fatal(1,"unexpected real pipeline fault writer=%b bank=%b",writer_fault,bank_fault);
`ifndef OLD_GATE
            if(gate.good_events>1)$fatal(1,"ordered physical lanes cannot complete two good groups on one edge");
`endif
            if(stalled0&&(!sv[0]||held0!=={ss[0],se[0],sq[0],sok[0],serr[0],32'd0}))$fatal(1,"LONG held SOURCE changed");
            if(stalled1&&(!sv[1]||held1!=={ss[1],se[1],sq[1],sok[1],serr[1],32'd0}))$fatal(1,"SHORT held SOURCE changed");
            stalled0=sv[0]&&block0;stalled1=sv[1]&&block1;
            held0={ss[0],se[0],sq[0],sok[0],serr[0],32'd0};held1={ss[1],se[1],sq[1],sok[1],serr[1],32'd0};
            if(sv[0]&&!block0)term0++;if(sv[1]&&!block1)term1++;
            if(abort[0])abort0++;if(abort[1])abort1++;
            if(finish_valid[0]&&finish_ready[0]&&finish_ok[0])begin
                if(bcount[0]==previous_b0)$fatal(1,"LONG positive finish lacks real B");
                previous_b0=bcount[0];finish_good0[frame[0][342:335]]++;
            end
            if(finish_valid[1]&&finish_ready[1]&&finish_ok[1])begin
                if(bcount[1]==previous_b1)$fatal(1,"SHORT positive finish lacks real B");
                previous_b1=bcount[1];finish_good1[frame[1][342:335]]++;
            end
            if(release_valid&&release_ready)release_valid<=0;
            if(product&&!release_valid)begin
                idx=bank.bank_group[product_bank]&255;
                if(finish_good0[idx]!=1||finish_good1[idx]!=1||product_count[idx]!=0)
                    $fatal(1,"pair publication before both matching real positive writers group=%0d finish=%0d/%0d",bank.bank_group[product_bank],finish_good0[idx],finish_good1[idx]);
                products++;product_count[idx]++;release_valid<=1;release_bank<=product_bank;release_id<=product_id;
            end
        end
    end
    function automatic [146:0] item(input integer group,member,code,input bit error=0);
        reg [146:0] t;
        begin
            t=0;t[39:0]={10'(group+member+31),10'(group+member+17),10'(group+member+7),10'(group+member+1)};
            t[42]=error;t[46:43]=4'(code);t[78:47]=32'(group);t[110:79]=32'(group*2+member);
            t[111]=1;t[112]=1;item=t;
        end
    endfunction
    task automatic tick(input integer cycles);
        repeat(cycles)@(negedge clk);
    endtask
    task automatic send(input bit lane,input [146:0] t);
        integer watchdog;
        begin
            @(negedge clk);if(lane)begin in1=t;valid1=1;end else begin in0=t;valid0=1;end
            watchdog=0;
            do begin @(posedge clk);watchdog++;if(watchdog>1100)$fatal(1,"input FS did not drain lane=%0d",lane);end
            while(!(lane?ready1:ready0));
            @(negedge clk);if(lane)valid1=0;else valid0=0;
        end
    endtask
    task automatic raw_frame(input integer group,member,input bit malformed=0);
        integer g;reg [146:0] t;
        begin
            for(g=0;g<8;g=g+1)begin
                t=item(group,member,0);t[40]=g==0;t[41]=g%4==3;
                if(malformed&&g==5)t[41]=1;
                @(negedge clk);
                if(member)begin in1=t;valid1=1;end else begin in0=t;valid0=1;end
                @(posedge clk);
                if(!(member?ready1:ready0))$fatal(1,"RAW tokens may not stall at gate");
            end
            @(negedge clk);if(member)valid1=0;else valid0=0;
        end
    endtask
    task automatic check(input bit condition,input string label);
        begin checks++;if(!condition)$fatal(1,"HDR_OVERLAP_CHECK %s good=%0d bad=%0d products=%0d term=%0d/%0d errors=%0d/%0d diag=%08h",label,good,bad,products,term0,term1,errors[0],errors[1],diag);end
    endtask
    task automatic cold;
        begin
            @(negedge clk);rst=0;valid0=0;valid1=0;admit=1;stable=1;fault=0;stop=0;block0=0;block1=0;fail_b=0;
            session=17;epoch=3;now=100;config_valid=0;tick(8);rst=1;tick(4);
            config_valid=1;do @(posedge clk);while(!config_ready);
            @(negedge clk);config_valid=0;tick(4);check(!config_error,"pair owner config");
        end
    endtask
    task automatic start_pair(input integer group);
        begin
            send(0,item(group,0,7));raw_frame(group,0);
            send(1,item(group,1,7));raw_frame(group,1);
        end
    endtask
    task automatic complete_pair(input integer group);
        begin start_pair(group);send(0,item(group,0,6));send(1,item(group,1,6));tick(180);end
    endtask
    task automatic overlap_edge(input integer group);
        begin
            fork send(0,item(group,0,7));send(1,item(group-1,1,6));join
        end
    endtask
    integer g;
    initial begin
        cold();start_pair(1);send(0,item(1,0,6));tick(100);
        for(g=2;g<=16;g=g+1)begin
            overlap_edge(g);raw_frame(g,0);send(0,item(g,0,6));tick(120);
            send(1,item(g,1,7));raw_frame(g,1);tick(100);
        end
        send(1,item(16,1,6));tick(300);
`ifdef OLD_GATE
        check(good==8&&bad==0&&products==8,"fixed old gate reproduces exactly 16 physical groups -> 8 real products");
        $display("RESULT: PASS OLD_HDR_HALF_RATE_NEGATIVE_CONTROL input_groups=16 good=8 products=8");$finish;
`else
        check(good==16&&bad==0&&products==16,"16 overlap groups yield all 16 actual DDR pair products");
        check(term0==16&&term1==16&&stale[0]==0&&stale[1]==0&&errors[0]==0&&errors[1]==0,"independent member SOURCE has no duplicates/stale or ingress abort");
        check(abort0==0&&abort1==0&&bank_empty&&gate_quiet,"all ownership drains without timeout or fake terminal");
        $display("CASE continuous_overlap groups=16 good=%0d actual_products=%0d terminal=%0d/%0d B=%0d/%0d",good,products,term0,term1,bcount[0],bcount[1]);

        cold();start_pair(1);send(0,item(1,0,6));tick(100);
        check(term0==1&&term1==0&&products==0,"LONG true FE retires independently before SHORT FE");
        send(0,item(2,0,7));raw_frame(2,0);tick(10);
        send(1,item(1,1,2,1));tick(100);
        check(bad==1&&products==0&&abort0==0&&abort1==1,"late SHORT CRC cannot publish group1 or abort new LONG2");
        send(0,item(2,0,6));send(1,item(2,1,7));raw_frame(2,1);send(1,item(2,1,6));tick(220);
        check(product_count[1]==0&&product_count[2]==1&&good==1,"neighbor group2 uses both real members after old peer error");
        $display("CASE long_positive_then_peer_CRC bad1_products=%0d next_products=%0d",product_count[1],product_count[2]);

        cold();fail_b[1]=1;start_pair(1);send(0,item(1,0,6));tick(100);
        send(1,item(1,1,6));tick(250);
        check(good==1&&products==0&&finish_good0[1]==1&&finish_good1[1]==0,"real negative AXI B vetoes pair despite two positive physical FE");
        $display("CASE negative_writer_B product=0");

        cold();send(0,item(1,0,7));raw_frame(1,0);
        send(1,item(1,1,7));raw_frame(1,1,1);
        send(0,item(1,0,6));send(1,item(1,1,6));tick(200);
        check(good==1&&products==0&&errors[1]!=0,"ingress geometry failure vetoes otherwise positive physical FE");
        $display("CASE ingress_geometry_negative product=0");

        cold();start_pair(1);stable=0;tick(180);
        check(bad==1&&products==0&&term0==1&&term1==1,"stable loss emits matching negative member terminals");
        stable=1;complete_pair(2);check(products==1&&product_count[1]==0&&product_count[2]==1,"stable recovery admits next complete group");
        $display("CASE stable_loss_and_recovery next_products=1");

        cold();send(0,item(1,0,7));raw_frame(1,0);send(0,item(1,0,6));tick(100);
        send(1,item(1,1,7));send(1,item(1,1,2,1));tick(4200);
        check(bad==1&&products==0&&term0==1&&term1==0&&bank_empty,"peer failure before pixel SOF leaves no completed pair and expires only an idle partial bank");
        $display("CASE peer_error_before_SOF product=0 partial_bank_expired=1");

        cold();start_pair(1);block0=1;block1=1;send(0,item(1,0,6));send(1,item(1,1,6));tick(64);
        check(sv==3&&products==0&&!gate_quiet,"both SOURCE held stable under terminal stall");
        block1=0;tick(80);check(sv[0]&&!sv[1]&&products==0,"independent SHORT SOURCE may retire first");
        block0=0;tick(160);check(products==1&&gate_quiet,"final SOURCE stall release completes exactly once");
        $display("CASE independent_terminal_stall products=%0d",products);

        cold();start_pair(1);send(0,item(1,0,6));tick(100);send(0,item(2,0,7));raw_frame(2,0);
        epoch=4;tick(160);
        check(bad==2&&products==0&&term0==2&&term1==1,"epoch change cancels both contexts with original identities");
        check(stale[0]==0&&stale[1]==0,"cross-epoch negative terminals match original ingress");
        $display("CASE epoch_two_context_cancel bad=%0d term=%0d/%0d",bad,term0,term1);

        cold();start_pair(1);send(0,item(1,0,6));tick(100);
        @(negedge clk);epoch=4;block1=1;in0=item(2,0,7);valid0=1;
        @(posedge clk);check(ready0,"new cohort LONG FS is consumed on the old cohort cancel edge");
        @(negedge clk);valid0=0;
        check(sv[1]&&!sok[1]&&ss[1]==17&&se[1]==3&&sq[1]==3&&capture_epoch==4,
            "old held SHORT negative retains epoch3 while new capture identity becomes epoch4");
        block1=0;raw_frame(2,0);send(0,item(2,0,6));tick(100);
        send(1,item(2,1,7));raw_frame(2,1);send(1,item(2,1,6));tick(160);
        check(stale[0]==0&&stale[1]==0&&se[0]==4&&se[1]==4&&good==1&&bad==1,
            "new-cohort member terminals match their own epoch without stale identity");
        check(products==0,"unchanged old-cohort bank config rejects new-cohort captures");
        $display("CASE same_edge_old_cancel_new_cohort old_epoch=3 new_epoch=4 stale=0/0");

        cold();start_pair(1);send(0,item(2,0,7));tick(160);
        check(bad>=1&&products==0&&diag[23:16]==5,"missing real LONG FE stays negative on same-lane reentry");
        $display("CASE missing_long_FE bad=%0d",bad);

        cold();start_pair(1);send(0,item(1,0,6));tick(1100);
        check(bad==1&&products==0&&diag[23:16]==11,"missing SHORT FE timeout never fabricates product");
        $display("CASE missing_short_FE_timeout product=0");

        cold();start_pair(1);admit=0;stop=1;send(0,item(1,0,6));send(1,item(1,1,6));tick(180);
        send(0,item(2,0,7));raw_frame(2,0);send(0,item(2,0,6));
        send(1,item(2,1,7));raw_frame(2,1);send(1,item(2,1,6));tick(80);
        check(gate_quiet&&products==0,"STOP drains owned frames and suppresses new group admission");
        $display("CASE stop_drain product=0");

        cold();send(0,item(32'hfffffffe,0,7));raw_frame(32'hfffffffe,0);
        send(1,item(32'hfffffffe,1,7));raw_frame(32'hfffffffe,1);
        send(0,item(32'hfffffffe,0,6));send(1,item(32'hfffffffe,1,6));tick(180);
        complete_pair(1);
        check(good==2&&products==2,"group and independent capture sequences progress across 32-bit wrap");
        $display("CASE group_wrap products=2");

        cold();start_pair(1);rst=0;tick(8);rst=1;tick(8);
        config_valid=1;do @(posedge clk);while(!config_ready);@(negedge clk);config_valid=0;
        complete_pair(1);check(good==1&&bad==0&&products==1,"coordinated reset clears both contexts and recovers");
        $display("CASE reset_mid_frame_recovery products=1");
        $display("RESULT: PASS HDR_TWO_CONTEXT_OVERLAP checks=%0d",checks);$finish;
`endif
    end
    initial begin #300000;$fatal(1,"HDR overlap watchdog");end
endmodule
