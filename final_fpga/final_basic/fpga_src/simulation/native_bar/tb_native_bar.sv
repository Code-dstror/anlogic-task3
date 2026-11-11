`timescale 1ns/1ps
module tb_native_bar;
    reg clk=0, rst=0,core_release=1;
    always #4 clk=!clk;
    reg hv=0,dv=0,eot=0,abort_tlp=0,abort_link=0,crc=0,poison=0,lookup_available=1;
    reg [3:0] dwen=0,first_be=15,last_be=0;
    reg [1:0] fmt=0,ats=0;
    reg [4:0] typ=0;
    reg [2:0] bar=0;
    reg [9:0] tag=0,len=1,lookup=0;
    reg [15:0] reqid=16'h31b0;
    reg [63:0] addr=0;
    reg [127:0] payload=0;
    wire halt,cv,cr,cl,rv,rr,reply,read_pending;
    reg sink_open=1,header_open=1,tx_halt=1;
    wire [127:0] cq,cc,tx;
    wire [3:0] keep;
    wire [87:0] userbits;
    wire [9:0] owner_id,owner_tag,tx_tag,tx_id;
    wire [15:0] tx_requester;
    wire [63:0] tx_addr;
    wire [2:0] tx_status,tx_tc;
    wire [12:0] tx_length;
    wire [11:0] tx_count;
    wire [1:0] tx_fmt;
    wire tx_hv,tx_dv,tx_last,wr;
    wire [11:0] reg_addr;
    wire [31:0] reg_data,ax_wdata,ax_addr;
    wire [3:0] reg_be,ax_be;
    reg ax_awready=0,ax_wready=0,ax_bvalid=0,ax_arready=0,ax_rvalid=0;
    reg [1:0] ax_rresp=0;
    wire ax_awvalid,ax_wvalid,ax_bready,ax_arvalid,ax_rready;
    integer writes=0, completions=0, checks=0;
    reg [31:0] last_write;
    always @(posedge clk) begin
        if(wr) begin writes<=writes+1;last_write<=reg_data;end
        if(reply) completions<=completions+1;
    end
    camera_pcie_bar_rx rx(
        .core_clk(clk),.core_rst_n(rst&&core_release),.radm_trgt1_hv(hv),.radm_trgt1_dv(dv),.radm_trgt1_eot(eot),
        .radm_trgt1_tlp_abort(abort_tlp),.radm_trgt1_dllp_abort(abort_link),.radm_trgt1_ecrc_err(crc),
        .radm_trgt1_poisoned(poison),.radm_trgt1_dwen(dwen),.radm_trgt1_first_be(first_be),
        .radm_trgt1_last_be(last_be),.radm_trgt1_fmt(fmt),.radm_trgt1_ats(ats),.radm_trgt1_type(typ),
        .radm_trgt1_attr(3'd0),.radm_trgt1_tc(3'd5),.radm_trgt1_in_membar_range(bar),
        .radm_trgt1_reqid(reqid),.radm_trgt1_addr(addr),.radm_trgt1_data(payload),.radm_trgt1_tag(tag),
        .radm_trgt1_dw_len(len),.trgt_lookup_id(lookup),.radm_trgt1_rom_in_range(1'b0),
        .radm_trgt1_func_num(1'b0),.radm_trgt1_vfunc_active(1'b0),.trgt_lookup_empty(lookup_available),
        .trgt1_radm_halt(halt),.m_axis_cq_tdata(cq),.m_axis_cq_tkeep(keep),.m_axis_cq_tuser(userbits),
        .m_axis_cq_tvalid(cv),.m_axis_cq_tready(cr&&header_open),.m_axis_cq_tlast(cl),
        .o_read_lookup(owner_id),.o_read_tag(owner_tag),.o_read_pending(read_pending),.i_reply_done(reply));
    c2h_bar_cq registers(.i_clk(clk),.i_rst_n(rst),.i_cq_data(cq),.i_cq_keep(keep),.i_cq_user(userbits),
        .i_cq_last(cl),.i_cq_valid(cv&&header_open),.o_cq_ready(cr),.o_cc_data(cc),.o_cc_valid(rv),
        .o_cc_last(),.o_cc_user(),.o_cc_keep(),.o_axil_fault(),.o_axil_arprot(),.o_axil_araddr(),.o_axil_awprot(),
        .i_cc_ready(rr&&sink_open),.o_reg_write(wr),.o_reg_wdata(reg_data),.o_reg_address(reg_addr),
        .o_reg_wstrb(reg_be),.i_reg_rdata(32'hc001ca5e),.o_axil_awaddr(ax_addr),.o_axil_awvalid(ax_awvalid),
        .i_axil_awready(ax_awready),.o_axil_wdata(ax_wdata),.o_axil_wstrb(ax_be),.o_axil_wvalid(ax_wvalid),
        .i_axil_wready(ax_wready),.i_axil_bresp(2'd0),.i_axil_bvalid(ax_bvalid),.o_axil_bready(ax_bready),
        .o_axil_arvalid(ax_arvalid),.i_axil_arready(ax_arready),.i_axil_rdata(32'hc0ffee12),
        .i_axil_rresp(ax_rresp),.i_axil_rvalid(ax_rvalid),.o_axil_rready(ax_rready));
    camera_pcie_bar_tx transmitter(.core_clk(clk),.core_rst_n(rst&&core_release),.i_read_lookup(owner_id),.i_read_tag(owner_tag),
        .i_read_pending(read_pending),
        .s_axis_cc_tdata(cc),.s_axis_cc_tvalid(rv&&sink_open),.s_axis_cc_tready(rr),.xadm_client1_halt(tx_halt),
        .o_reply_done(reply),.client1_tlp_hv(tx_hv),.client1_tlp_dv(tx_dv),.client1_tlp_eot(tx_last),
        .client1_tlp_fmt(tx_fmt),.client1_tlp_byte_len(tx_length),.client1_tlp_data(tx),.client1_tlp_addr(tx_addr),
        .client1_cpl_byte_cnt(tx_count),.client1_remote_req_id(tx_requester),.client1_tlp_tc(tx_tc),
        .client1_cpl_status(tx_status),.client1_tlp_attr(),.client1_tlp_tid(tx_tag),.client1_cpl_lookup_id(tx_id));
    task tick; @(posedge clk); #1; endtask
    task check(input bit ok,input string msg);
        checks++;if(!ok)$fatal(1,"%s",msg);
    endtask
    task beat(input bit h,d,e,input [31:0] val);
        hv=h;dv=d;eot=e;payload=val;#1;
        while(halt)tick();
        tick();hv=0;dv=0;eot=0;
    endtask
    task req(input bit writing,input [31:0] a,input [9:0] t,id);
        fmt=writing?2:0;typ=0;addr=a;len=1;tag=t;lookup=id;first_be=15;last_be=0;dwen=1;
    endtask
    task complete(input [2:0] status,input bit data_valid,input [31:0] value,input [9:0] t,id);
        wait(tx_hv);#1;
        repeat(5)begin
            check(tx_hv&&tx_last&&tx_dv==data_valid&&tx_fmt=={data_valid,1'b0},"native flags");
            check(tx_status==status&&tx_tc==5&&tx_tag==t&&tx_id==id&&tx_requester==reqid,"native completion owner");
            check(tx_length==(data_valid?4:0)&&tx_count==(data_valid?4:0),"native length");
            if(data_valid)check(tx[31:0]==value,"native data");
            tick();
        end
        tx_halt=0;tick();tx_halt=1;check(!tx_hv,"retire once");
    endtask
    initial begin
        repeat(3)tick();rst=1;
        req(1,32'h28,0,0);header_open=0;beat(1,1,1,32'hdae51234);
        repeat(4)begin check(cv&&!cl&&cq[31:0]==32'h28&&writes==0,"held CQ header");tick();end
        header_open=1;tick();header_open=0;
        repeat(4)begin check(cv&&cl&&cq[31:0]==32'hdae51234&&keep==1,"held CQ payload");tick();end
        header_open=1;tick();check(writes==1&&last_write==32'hdae51234,"single DW write");

        req(1,'h28,0,0);beat(1,0,0,0);
        lookup_available=0;dv=1;eot=1;payload=32'h1234;#1;
        repeat(4)begin check(halt&&!cv&&writes==1,"native target LUT backpressure on data");tick();end
        lookup_available=1;beat(0,1,1,32'h1234);repeat(4)tick();
        check(writes==2&&last_write==32'h1234,"split header/data");
        for(integer n=0;n<7;n++)begin
            req(1,'h28,0,0);
            case(n)
                0:crc=1;1:abort_tlp=1;2:abort_link=1;3:poison=1;4:dwen=3;5:len=2;6:bar=1;
            endcase
            beat(1,1,1,32'hbad0+n);crc=0;abort_tlp=0;abort_link=0;poison=0;bar=0;
            repeat(4)tick();check(writes==2,"bad writes discarded");
        end
        req(1,'h28,0,0);beat(1,1,0,'hbade);beat(0,1,1,'hbaad);repeat(4)tick();
        check(writes==2,"no partial multibeat write");
        req(1,'h80028,0,0);first_be=4'b1010;beat(1,1,1,'h1234abcd);
        wait(ax_wvalid);#1;check(ax_awvalid&&ax_addr=='h80028&&ax_be==10&&ax_wdata=='h1234abcd,"AXI strobes");
        ax_wready=1;tick();ax_wready=0;check(!ax_wvalid&&ax_awvalid,"split W/AW handshakes");
        ax_awready=1;tick();ax_awready=0;ax_bvalid=1;tick();ax_bvalid=0;

        req(0,'h24,10'h321,10'h2aa);hv=1;eot=1;lookup_available=0;#1;
        repeat(3)begin check(halt&&!cv,"lookup backpressure");tick();end
        lookup_available=1;beat(1,0,1,0);sink_open=0;repeat(5)tick();
        check(rv&&!tx_hv,"held CC");sink_open=1;
        // A new MRd with the same low tag is held while client1 is stalled.
        addr='h30;tag=10'h21;lookup=10'h155;hv=1;eot=1;
        check(halt,"second read waits for true client1 transfer");
        complete(0,1,32'hc001ca5e,10'h321,10'h2aa);
        check(!halt,"second read released");tick();hv=0;eot=0;
        complete(0,1,32'hc001ca5e,10'h21,10'h155);
        req(0,'h40,13,92);len=2;beat(1,0,1,0);complete(1,0,0,13,92);
        req(0,'h40,14,91);typ=2;beat(1,0,1,0);complete(1,0,0,14,91);
        req(0,'h80010,15,90);beat(1,0,1,0);wait(ax_arvalid);ax_arready=1;
        tick();ax_arready=0;ax_rvalid=1;ax_rresp=2;tick();ax_rvalid=0;complete(4,0,0,15,90);
        req(0,'h44,17,89);beat(1,0,1,0);wait(tx_hv);rst=0;#1;
        check(!tx_hv&&!cv,"reset revokes held transaction");repeat(3)tick();rst=1;
        req(0,'h40,18,88);beat(1,0,1,0);complete(0,1,32'hc001ca5e,18,88);
        req(0,'h80048,10'h11b,91);beat(1,0,1,0);wait(ax_arvalid);
        ax_arready=1;tick();ax_arready=0;core_release=0;tick();core_release=1;tick();
        req(0,'h48,10'h21b,92);beat(1,0,1,0);
        ax_rresp=0;ax_rvalid=1;tick();ax_rvalid=0;
        complete(0,1,32'hc001ca5e,10'h21b,92);
        check(completions==7,"stale MMIO response cannot take the next lookup");
        $display("PASS native_bar checks=%0d completed=%0d",checks,completions);$finish;
    end
    initial begin #15000;$fatal(1,"watchdog");end
endmodule
