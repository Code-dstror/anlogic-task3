`timescale 1ns/1ps
module tb_native_port;
    reg clk=0; always #4 clk=!clk;
    reg ownership=0, result_pending=0, dma_hv=0, dma_dv=0;
    reg cc_valid=0, cq_ready=0;
    reg [127:0] cc=0;
    wire user_clk,core_reset_n,link_up,physical_link_up,dma_halt,cc_ready;
    wire [127:0] rc,cq;
    wire [1:0] bme;
    wire rc_valid,rc_last,cq_valid,cq_last,completion_fault,incident;
    localparam [31:0] COOKIE=32'h235689dc;
    camera_pcie_hard_port dut(
        .refclk_p(1'b0),.refclk_n(1'b1),.rxp(1'b0),.rxn(1'b1),.aux_clk(clk),.power_reset_n(ownership),
        .txp(),.txn(),.user_clk(user_clk),.core_reset_n(core_reset_n),.user_link_up(link_up),.physical_link_up(physical_link_up),
        .bus_master_enable(bme),.ownership_reset_n(ownership),.result_pending(result_pending),
        .fence_cookie(COOKIE),.completion_fault(completion_fault),.completion_incident(incident),
        .dma_data(128'h302010),.dma_addr(64'h1_f7654128),.dma_be(8'h0f),.dma_byte_length(13'd4),
        .dma_fmt(2'd1),.dma_tag(10'h01a),.dma_hv(dma_hv),.dma_dv(dma_dv),.dma_eot(1'b1),.dma_halt(dma_halt),
        .rc_data(rc),.rc_keep(),.rc_user(),.rc_valid(rc_valid),.rc_last(rc_last),.rc_ready(1'b1),
        .cq_data(cq),.cq_keep(),.cq_user(),.cq_valid(cq_valid),.cq_last(cq_last),.cq_ready(cq_ready),
        .cc_data(cc),.cc_valid(cc_valid),.cc_ready(cc_ready));
    integer checks=0,cc_takes=0;
    always @(posedge clk) if(cc_valid && cc_ready) cc_takes<=cc_takes+1;
    task tick; begin @(posedge clk);#1;end endtask
    task check(input logic test,input string what); begin
        if(test!==1'b1)$fatal(1,"native shell: %s",what);checks++;
    end endtask
    initial begin
        force dut.u_controller.user_clk=clk;
        force dut.u_controller.core_rst_n=0;
        force dut.u_controller.user_link=1;
        force dut.u_controller.rdlh_link_up=1;
        force dut.u_controller.cfg_bus_master_en=2'b01;
        force dut.u_controller.cfg_pbus_num=8'h23;
        force dut.u_controller.cfg_pbus_dev_num=5'h12;
        force dut.u_controller.cfg_msi_en=2'b01;
        force dut.u_controller.cfg_msi_mask=64'd1;
        force dut.u_controller.xadm_client0_halt=1;
        tick();ownership=1;force dut.u_controller.core_rst_n=1;
        repeat(5)tick();
        check(dut.bar_reset_n && bme==1 && link_up && physical_link_up,"core and ownership permits");
        check(!dut.u_controller.drp_dbi_cs && dut.u_controller.drp_dbi_wr==0,
              "application DBI port idle during normal native transport");
        result_pending=1;repeat(4)tick();
        check(!dut.u_controller.ven_msi_req && dut.u_controller.cfg_msi_pending==1,"masked vector zero pending");
        force dut.u_controller.cfg_msi_mask=0;
        repeat(4)begin tick();check(dut.u_controller.ven_msi_req && dut.u_controller.ven_msi_vector==0 &&
             !dut.u_controller.ven_msi_func_num,"only PF0 vector zero is held through backpressure");end
        force dut.u_controller.ven_msi_grant=1;tick();
        force dut.u_controller.ven_msi_grant=0;
        repeat(4)begin tick();check(!dut.u_controller.ven_msi_req,"no duplicate interrupt for held result");end
        result_pending=0;tick();result_pending=1;tick();
        check(dut.u_controller.ven_msi_req,"next result can interrupt");
        force dut.u_controller.ven_msi_grant=1;tick();result_pending=0;tick();

        // No request or fence ownership is created while client 0 is halted.
        dma_hv=1;repeat(2)tick();
        check(dma_halt && !dut.u_fence_listener.outstanding &&
              dut.u_controller.client0_tlp_addr==64'h1_f7654128 &&
              dut.u_controller.client0_remote_req_id==16'h2390 &&
              dut.u_controller.client0_tlp_tid==10'h01a && dut.u_controller.client0_tlp_atu_bypass,
              "native RQ pins and halt/ownership");
        force dut.u_controller.xadm_client0_halt=0;tick();dma_hv=0;
        check(dut.u_fence_listener.outstanding,"accepted client0 MRd opens one fence");
        force dut.u_controller.radm_bypass_fmt=2;force dut.u_controller.radm_bypass_type=5'h0a;
        force dut.u_controller.radm_bypass_reqid=16'h2390;force dut.u_controller.radm_bypass_tag=10'h01a;
        force dut.u_controller.radm_bypass_dw_len=1;force dut.u_controller.radm_bypass_byte_cnt=4;
        force dut.u_controller.radm_bypass_cpl_last=1;force dut.u_controller.radm_bypass_addr=64'h28;
        force dut.u_controller.radm_bypass_hv=1;force dut.u_controller.radm_bypass_dv=1;
        force dut.u_controller.radm_bypass_eot=1;force dut.u_controller.radm_bypass_dwen=1;
        force dut.u_controller.radm_bypass_data=COOKIE;
        tick();force dut.u_controller.radm_bypass_hv=0;force dut.u_controller.radm_bypass_dv=0;#1;
        check(rc_valid && rc_last && rc[127:96]==COOKIE && !completion_fault && !incident,
              "only matching native completion yields application fence");
        tick();check(!rc_valid,"one completion only");

        // The target read chooses a single true lookup; do not confuse it with the application fence tag.
        force dut.u_controller.trgt_lookup_empty=1;force dut.u_controller.trgt_lookup_id=10'h256;
        force dut.u_controller.radm_trgt1_tag=10'h355;force dut.u_controller.radm_trgt1_dw_len=1;
        force dut.u_controller.radm_trgt1_reqid=16'h0123;force dut.u_controller.radm_trgt1_first_be=4'hf;
        force dut.u_controller.radm_trgt1_hv=1;force dut.u_controller.radm_trgt1_eot=1;
        force dut.u_controller.radm_trgt1_addr=64'h80000;
        tick();force dut.u_controller.radm_trgt1_hv=0;force dut.u_controller.radm_trgt1_eot=0;
        repeat(2)tick();check(cq_valid&&cq_last,"read CQ held until camera register owner accepts");
        cq_ready=1;tick();cq_ready=0;
        check(dut.read_pending,"BAR target lookup outstanding");
        force dut.u_controller.xadm_client1_halt=1;
        cc[127:96]=32'habcd0001;cc[63:48]=16'h0123;cc[42:32]=1;cc[27:16]=4;
        cc_valid=1;
        repeat(4)begin
            tick();
            if(cc_takes!=0)cc_valid=0;
        end
        check(dut.u_controller.client1_tlp_hv&&dut.u_controller.client1_tlp_dv&&
              dut.u_controller.client1_cpl_lookup_id==10'h256&&dut.u_controller.client1_tlp_tid==10'h355&&
              dut.u_controller.client1_tlp_type==5'h0a&&dut.u_controller.client1_tlp_data[31:0]==32'habcd0001,
              "held native BAR completion returns exact lookup and full tag");
        force dut.u_controller.xadm_client1_halt=0;tick();cc_valid=0;
        check(cc_takes==1,"the source keeps CC valid until exactly one transfer");
        check(!dut.read_pending&&!dut.u_controller.client1_tlp_hv,"actual client1 acceptance releases read");
        force dut.u_controller.core_rst_n=0;#1;
        check(!dut.bar_reset_n&&!dut.read_pending&&!dut.u_controller.client1_tlp_hv,
              "core-only reset closes BAR, without releasing DMA ownership");
        force dut.u_controller.core_rst_n=1;repeat(5)tick();
        cc_valid=1;tick();cc_valid=0;
        check(!dut.u_controller.client1_tlp_hv,"late obsolete CC never acquires fresh native lookup");
        $display("RESULT: PASS NATIVE_CAMERA_PORT %0d checks",checks);$finish;
    end
    initial begin #10000;$fatal(1,"native endpoint watchdog");end
endmodule
