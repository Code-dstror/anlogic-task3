`timescale 1ns/1ps
// No payload is supplied in this startup/authorization test. The real
// packetizer is instantiated; an unexpected RAM read/write is a test failure.
module c2h_packet_ram(input wire i_clk,input wire i_write,input wire [2:0] i_write_address,
 input wire [127:0] i_write_data,input wire i_read,input wire [2:0] i_read_address,
 output wire [127:0] o_read_data);
    assign o_read_data=0;
    always @(posedge i_clk)if(i_write||i_read)$fatal(1,"startup fixture unexpectedly accessed packet RAM");
endmodule

`define NATIVE_IDLE_PROBE(NAME,IS_OLD,RESET,FAULT_IN,ST,FL,RC,BD,CP,BY) \
 startup_native_probe #(.LEGACY(IS_OLD)) NAME(.clk(user_clk),.rst_n(RESET),.link_up(1'b1),.bme(1'b0), \
 .external_fault(FAULT_IN),.cq_data(128'd0),.cq_keep(4'd0),.cq_user(88'd0),.cq_last(1'b0),.cq_valid(1'b0), \
 .record_valid(1'b0),.rc_valid(1'b0),.cq_ready(),.record_ready(),.quarantine(),.armed(),.cancel(), \
 .state(ST),.native_fault(FL),.bound(BD),.permitted(),.result_code(RC),.shadow_capacity(CP),.local_bytes(BY),.identity());

module native_startup_matrix_case #(parameter integer ORDER=0,PHASE=0,INITIAL_ONE=1)(
 input wire watch_clk,cold_n,output reg done=0,output wire legacy_failed,half_failed);
    reg user_clk=0,dfi_clk=0;
    localparam integer USER_START=ORDER==0?160:ORDER==1?1600:ORDER==2?750:5000;
    localparam integer DFI_START=ORDER==0?180:ORDER==2?2000:750;
    initial begin #(USER_START+PHASE*0.5);forever #4 user_clk=~user_clk;end
    initial begin #(DFI_START+PHASE*0.46875);forever #3.75 dfi_clk=~dfi_clk;end
    // A registered stimulus supplies a real ready transition.
    reg ddr_good=0;
    initial begin #(ORDER==2?2200:900);ddr_good=1;end
    wire [2:0] memory_fault,memory_ready,memory_active,product_reset,user_reset;
    wire [1:0] fault_dfi[0:2],product_fault[0:2];
    startup_forward_fixed #(.INITIAL_ONE(INITIAL_ONE)) fixed_forward(
        .sys_clk(watch_clk),.user_clk(user_clk),.dfi_clk(dfi_clk),.product_cold_reset_n(cold_n),
        .ddr_app_ready(ddr_good),.ddr_phy_rst_n(ddr_good),.memory_fault_user(memory_fault[0]),
        .memory_owner_ready(memory_ready[0]),.active_memory_fault(memory_active[0]),
        .product_dfi_reset_n(product_reset[0]),.user_rst_n(user_reset[0]),
        .observed_fault_dfi(fault_dfi[0]),.observed_product_fault(product_fault[0]));
    startup_forward_legacy #(.INITIAL_ONE(INITIAL_ONE)) old_forward(
        .sys_clk(watch_clk),.user_clk(user_clk),.dfi_clk(dfi_clk),.product_cold_reset_n(cold_n),
        .ddr_app_ready(ddr_good),.ddr_phy_rst_n(ddr_good),.memory_fault_user(memory_fault[1]),
        .memory_owner_ready(memory_ready[1]),.active_memory_fault(memory_active[1]),
        .product_dfi_reset_n(product_reset[1]),.user_rst_n(user_reset[1]),
        .observed_fault_dfi(fault_dfi[1]),.observed_product_fault(product_fault[1]));
    startup_forward_supervisor_only #(.INITIAL_ONE(INITIAL_ONE)) half_forward(
        .sys_clk(watch_clk),.user_clk(user_clk),.dfi_clk(dfi_clk),.product_cold_reset_n(cold_n),
        .ddr_app_ready(ddr_good),.ddr_phy_rst_n(ddr_good),.memory_fault_user(memory_fault[2]),
        .memory_owner_ready(memory_ready[2]),.active_memory_fault(memory_active[2]),
        .product_dfi_reset_n(product_reset[2]),.user_rst_n(user_reset[2]),
        .observed_fault_dfi(fault_dfi[2]),.observed_product_fault(product_fault[2]));
    wire [3:0] state[0:2];
    wire [2:0] native_fault,bound;
    wire [31:0] result[0:2],capacity[0:2],bytes[0:2];
    `NATIVE_IDLE_PROBE(fixed_native,0,user_reset[0],memory_fault[0]||product_fault[0][1],state[0],native_fault[0],result[0],bound[0],capacity[0],bytes[0])
    `NATIVE_IDLE_PROBE(old_native,1,user_reset[1],memory_fault[1]||product_fault[1][1],state[1],native_fault[1],result[1],bound[1],capacity[1],bytes[1])
    `NATIVE_IDLE_PROBE(half_native,0,user_reset[2],memory_fault[2]||product_fault[2][1],state[2],native_fault[2],result[2],bound[2],capacity[2],bytes[2])
    assign legacy_failed=native_fault[1]&&result[1]==4&&!bound[1]&&capacity[1]==0&&bytes[1]==0;
    assign half_failed=native_fault[2]&&result[2]==4&&!bound[2]&&capacity[2]==0&&bytes[2]==0;
    always @(posedge user_clk)if(user_reset[0])begin
        #1;
        if(native_fault[0]||result[0]!=0||bound[0]||capacity[0]!=0||bytes[0]!=0||state[0]!=0)
            $fatal(1,"fixed startup false native quarantine ORDER=%0d PHASE=%0d INIT=%0d",ORDER,PHASE,INITIAL_ONE);
    end
    initial begin
        if(ORDER==3)begin
            #3500;
            if(memory_fault[0]||memory_active[0])$fatal(1,"cold-stopped USER leaks unqualified memory fault");
        end
        #7000;
        if(native_fault[0]||result[0]!=0||state[0]!=0||bound[0]||capacity[0]!=0||bytes[0]!=0)
            $fatal(1,"fixed startup final state is not true empty native IDLE");
        if((ORDER==1||ORDER==3)&&!legacy_failed)
            $fatal(1,"frozen native negative control did not reproduce USER-late failure");
        if(ORDER==2&&INITIAL_ONE&&!half_failed)
            $fatal(1,"supervisor-only negative control missed reverse DFI-late startup defect");
        done=1;
    end
endmodule

module pre_bme_startup_case #(parameter integer PHASE=0,INITIAL_ONE=1)(input wire watch_clk,cold_n,output reg done=0);
    reg user_clk=0,link_good=0,bme=0;
    initial begin #(PHASE*0.5);forever #4 user_clk=~user_clk;end
    wire old_fault,old_ready,new_fault,new_ready;
    generate if(INITIAL_ONE)begin:g_one
        startup_supervisor_fixed_1 fixed_dut(.i_watch_clk(watch_clk),.i_user_clk(user_clk),.i_recovery_reset_n(cold_n),
            .i_link_up(link_good),.i_bme(bme),.i_perst_n(1'b1),.i_pll_lock(1'b1),.i_core_reset_n(1'b1),.o_fault(new_fault),.o_ready(new_ready));
        startup_supervisor_legacy_1 old_dut(.i_watch_clk(watch_clk),.i_user_clk(user_clk),.i_recovery_reset_n(cold_n),
            .i_link_up(link_good),.i_bme(bme),.i_perst_n(1'b1),.i_pll_lock(1'b1),.i_core_reset_n(1'b1),.o_fault(old_fault),.o_ready(old_ready));
    end else begin:g_zero
        startup_supervisor_fixed_0 fixed_dut(.i_watch_clk(watch_clk),.i_user_clk(user_clk),.i_recovery_reset_n(cold_n),
            .i_link_up(link_good),.i_bme(bme),.i_perst_n(1'b1),.i_pll_lock(1'b1),.i_core_reset_n(1'b1),.o_fault(new_fault),.o_ready(new_ready));
        startup_supervisor_legacy_0 old_dut(.i_watch_clk(watch_clk),.i_user_clk(user_clk),.i_recovery_reset_n(cold_n),
            .i_link_up(link_good),.i_bme(bme),.i_perst_n(1'b1),.i_pll_lock(1'b1),.i_core_reset_n(1'b1),.o_fault(old_fault),.o_ready(old_ready));
    end endgenerate
    initial begin
        wait(cold_n);@(negedge watch_clk);link_good=1;repeat(8)@(negedge watch_clk);
        if(new_fault||new_ready||old_fault||old_ready)$fatal(1,"unexpected pre-BME settled state");
        #(1+PHASE*2.5);link_good=0;#2;link_good=1;
        repeat(8)@(negedge watch_clk);
        if(new_fault||new_ready||!old_fault||old_ready)$fatal(1,"pre-BME training regression or missing legacy counterexample");
        bme=1;repeat(8)@(negedge watch_clk);
        if(new_fault||!new_ready||!old_fault)$fatal(1,"joint authorization failed or legacy incident auto-cleared");
        done=1;
    end
endmodule

module native_runtime_case(input wire watch_clk,output reg done=0);
    reg user_raw=0,dfi_raw=0,user_running=1,dfi_running=1;
    always #4 user_raw=~user_raw;
    always #3.75 dfi_raw=~dfi_raw;
    wire user_clk=user_raw&&user_running,dfi_clk=dfi_raw&&dfi_running;
    reg cold_n=0,link_good=1,bme=1,perst_n=1,pll_lock=1,core_reset_n=1;
    reg ddr_ready=1,ddr_phy_n=1,external_fault=0;
    wire memory_fault,memory_ready,memory_active,product_reset,user_reset;
    wire [1:0] memory_dfi,product_fault;
    startup_forward_fixed forward(.sys_clk(watch_clk),.user_clk(user_clk),.dfi_clk(dfi_clk),
        .product_cold_reset_n(cold_n),.ddr_app_ready(ddr_ready),.ddr_phy_rst_n(ddr_phy_n),
        .memory_fault_user(memory_fault),.memory_owner_ready(memory_ready),.active_memory_fault(memory_active),
        .product_dfi_reset_n(product_reset),.user_rst_n(user_reset),.observed_fault_dfi(memory_dfi),
        .observed_product_fault(product_fault));
    wire pcie_fault,pcie_ready;
    c2h_link_supervisor pcie_watch(.i_watch_clk(watch_clk),.i_user_clk(user_clk),.i_recovery_reset_n(cold_n),
        .i_link_up(link_good),.i_bme(bme),.i_perst_n(perst_n),.i_pll_lock(pll_lock),
        .i_core_reset_n(core_reset_n),.o_fault(pcie_fault),.o_ready(pcie_ready));
    reg [127:0] cq_data=0;
    reg [3:0] cq_keep=0;
    reg [87:0] cq_user=0;
    reg cq_last=0,cq_valid=0,record_valid=0,rc_valid=0;
    wire cq_ready,record_ready,quarantine,armed,cancel,native_fault,bound,permitted;
    wire [3:0] state;
    wire [31:0] result_code,shadow_capacity,local_bytes;
    wire [127:0] identity;
    wire combined_fault=external_fault||pcie_fault||memory_fault||product_fault[1];
    startup_native_probe native(.clk(user_clk),.rst_n(user_reset),.link_up(link_good),.bme(bme&&pcie_ready),
        .external_fault(combined_fault),.cq_data(cq_data),.cq_keep(cq_keep),.cq_user(cq_user),
        .cq_last(cq_last),.cq_valid(cq_valid),.record_valid(record_valid),.rc_valid(rc_valid),
        .cq_ready(cq_ready),.record_ready(record_ready),.quarantine(quarantine),.armed(armed),.cancel(cancel),
        .state(state),.native_fault(native_fault),.bound(bound),.permitted(permitted),.result_code(result_code),
        .shadow_capacity(shadow_capacity),.local_bytes(local_bytes),.identity(identity));
    integer checks=0,fault_cases=0,cq_writes=0,kind,stopped_user,stopped_dfi,limit;
    task check(input bit condition,input string reason);
        begin checks=checks+1;if(!condition)$fatal(1,"native runtime kind=%0d: %s",kind,reason);end
    endtask
    task recover;
        begin
            @(negedge watch_clk);cold_n=0;user_running=1;dfi_running=1;
            link_good=1;bme=1;perst_n=1;pll_lock=1;core_reset_n=1;ddr_ready=1;ddr_phy_n=1;
            external_fault=0;cq_valid=0;record_valid=0;rc_valid=0;
            repeat(12)@(negedge watch_clk);cold_n=1;repeat(10)@(negedge watch_clk);
            check(!native_fault&&result_code==0&&state==0&&!bound&&shadow_capacity==0&&local_bytes==0,
                "only explicit coordinated cold reset restores true descriptor-empty IDLE");
            check(pcie_ready&&memory_ready&&product_reset,"healthy domains jointly qualify after cold release");
        end
    endtask
    task cq_beat(input [127:0] value,input [3:0] keep,input bit last);
        begin
            @(negedge user_clk);cq_data=value;cq_keep=keep;cq_last=last;cq_valid=1;limit=0;
            do begin @(posedge user_clk);limit=limit+1;check(limit<100,"real native CQ ready is bounded");end while(!cq_ready);
            @(negedge user_clk);cq_valid=0;
        end
    endtask
    task write_reg(input [11:0] address,input [31:0] value);
        reg [127:0] header;
        begin
            header=0;header[11:0]=address;header[74:64]=1;header[78:75]=1;cq_user=15;
            cq_beat(header,15,0);cq_beat({96'd0,value},1,1);cq_writes=cq_writes+1;
        end
    endtask
    task grant_and_bind;
        begin
            write_reg(12'h008,8); // real native START/RESUME
            write_reg(12'h020,32'h200000);write_reg(12'h024,0);write_reg(12'h028,256);
            write_reg(12'h030,7);write_reg(12'h034,1);
            write_reg(12'h038,32'h99887766);write_reg(12'h03c,32'h11223344);
            write_reg(12'h040,32'h100000);write_reg(12'h044,0);write_reg(12'h048,32'h47a1c35d);
            write_reg(12'h008,1);repeat(3)@(negedge user_clk);
            check(armed&&state==1&&!bound&&!native_fault&&shadow_capacity==256,
                "actual START and SUBMIT accept one validated host descriptor");
            check(identity==128'h11223344998877660000000100000007,"descriptor identity remains exact");
            record_valid=1;limit=0;
            do begin @(posedge user_clk);limit=limit+1;check(limit<30,"actual native record handshake is bounded");end while(!record_ready);
            @(negedge user_clk);record_valid=0;repeat(5)@(negedge user_clk);
            check(bound&&state==3&&!native_fault&&local_bytes==0,"real record owner binds before any payload or DMA byte");
        end
    endtask
    task pulse_loss(input integer loss);
        begin
            #2;
            case(loss)
                0:link_good=0;1:bme=0;2:perst_n=0;3:pll_lock=0;4:core_reset_n=0;
                5:ddr_ready=0;6:ddr_phy_n=0;
            endcase
            #0.2;
            check((loss<5?pcie_fault:memory_fault)&&!permitted,"sub-watch-period loss asserts a real fault and closes DMA permission");
            if(loss>=5)check(memory_active&&memory_dfi==3,"DFI cold qualification remains high and does not mask runtime loss while stopped");
            #2;
            link_good=1;bme=1;perst_n=1;pll_lock=1;core_reset_n=1;ddr_ready=1;ddr_phy_n=1;
        end
    endtask
    initial begin
        recover();
        // No host command, BME0: a training short-drop is not a DMA incident.
        @(negedge watch_clk);cold_n=0;bme=0;repeat(12)@(negedge watch_clk);cold_n=1;
        repeat(8)@(negedge watch_clk);#3;link_good=0;#2;link_good=1;
        repeat(8)@(negedge watch_clk);
        check(!native_fault&&!pcie_fault&&!pcie_ready&&!bound&&shadow_capacity==0&&local_bytes==0,
            "real descriptor-empty native survives pre-BME training without false lockout");
        for(kind=0;kind<7;kind=kind+1)for(stopped_user=0;stopped_user<2;stopped_user=stopped_user+1)begin
            recover();grant_and_bind();
            if(stopped_user)begin @(negedge user_clk);user_running=0;end
            if(kind>=5)begin @(negedge dfi_clk);dfi_running=0;end
            if(stopped_user||kind>=5)begin
                repeat(3)@(negedge watch_clk);
                check(!native_fault&&!pcie_fault&&!memory_fault&&permitted&&bound,
                    "a healthy paused data clock neither fabricates a fault nor revokes the established cold qualification");
            end
            pulse_loss(kind);repeat(4)@(negedge watch_clk);
            check((kind<5?pcie_fault:memory_fault)&&!permitted,"signal restoration cannot clear an armed incident");
            if(stopped_user)begin @(negedge user_raw);user_running=1;end
            repeat(8)@(negedge user_clk);
            check(native_fault&&quarantine&&result_code==4&&bound&&cancel&&!permitted&&!record_ready&&!armed,
                "actual native keeps bound descriptor quarantined after recovered link/memory loss");
            write_reg(12'h008,8);write_reg(12'h008,16);repeat(5)@(negedge user_clk);
            // A bound S_RUN owner awaits the actual packetizer drain/result;
            // this test supplies no payload. Isolation must be immediate and
            // permanent, without fabricating drain or discarding that owner.
            check(native_fault&&quarantine&&state!=0&&result_code==4&&bound&&!permitted&&!armed,
                "ordinary START/ACK cannot erase runtime fault or retire the descriptor");
            if(kind>=5)begin @(negedge dfi_raw);dfi_running=1;repeat(5)@(negedge watch_clk);end
            check(native_fault&&result_code==4,"data-clock restoration also cannot clear the incident");
            fault_cases=fault_cases+1;
        end
        kind=7;recover();
        @(negedge user_clk);rc_valid=1;@(posedge user_clk);@(negedge user_clk);rc_valid=0;
        check(native_fault&&result_code==5,"unexpected bad RC is a real first FENCE_ERROR");
        external_fault=1;repeat(8)@(negedge user_clk);
        check(native_fault&&state==7&&quarantine&&result_code==5,"later continuous external fault preserves first RESULT5");
        kind=8;recover();
        @(negedge user_clk);external_fault=1;@(posedge user_clk);@(negedge user_clk);
        check(native_fault&&result_code==4,"external incident is a real first RESULT4");
        rc_valid=1;repeat(8)@(negedge user_clk);rc_valid=0;
        check(native_fault&&state==7&&quarantine&&result_code==4,"later bad RC preserves first RESULT4");
        kind=9;recover();
        @(negedge user_clk);external_fault=1;rc_valid=1;@(posedge user_clk);@(negedge user_clk);
        check(native_fault&&result_code==4,"original first-edge simultaneous external/RC priority remains external4");
        recover();
        $display("RESULT: PASS native_runtime checks=%0d authorized_fault_cases=%0d actual_cq_writes=%0d first_fault_orders=3 NO_PAYLOAD_DMA",checks,fault_cases,cq_writes);
        done=1;
    end
endmodule

module tb_native_startup;
    reg watch_clk=0,cold_n=0;
    always #20 watch_clk=~watch_clk;
    initial begin repeat(16)@(negedge watch_clk);cold_n=1;end
    wire [127:0] matrix_done,legacy_failed,half_failed;
    wire [31:0] pre_bme_done;
    genvar order,phase,initial_one;
    generate for(order=0;order<4;order=order+1)begin:g_order
        for(initial_one=0;initial_one<2;initial_one=initial_one+1)begin:g_initial
            for(phase=0;phase<16;phase=phase+1)begin:g_phase
                localparam integer INDEX=order*32+initial_one*16+phase;
                native_startup_matrix_case #(.ORDER(order),.PHASE(phase),.INITIAL_ONE(initial_one)) c(
                    .watch_clk(watch_clk),.cold_n(cold_n),.done(matrix_done[INDEX]),
                    .legacy_failed(legacy_failed[INDEX]),.half_failed(half_failed[INDEX]));
            end
        end
    end
    for(initial_one=0;initial_one<2;initial_one=initial_one+1)begin:g_pre_initial
        for(phase=0;phase<16;phase=phase+1)begin:g_pre_phase
            pre_bme_startup_case #(.PHASE(phase),.INITIAL_ONE(initial_one)) c(
                .watch_clk(watch_clk),.cold_n(cold_n),.done(pre_bme_done[initial_one*16+phase]));
        end
    end endgenerate
    wire runtime_done;
    native_runtime_case runtime_case(watch_clk,runtime_done);
    integer n,old_count,half_count;
    initial begin
        wait((&matrix_done)&&(&pre_bme_done)&&runtime_done);
        old_count=0;half_count=0;
        for(n=0;n<128;n=n+1)begin if(legacy_failed[n])old_count=old_count+1;if(half_failed[n])half_count=half_count+1;end
        $display("RESULT: PASS native_startup_matrix fixed_cases=128 phase_count=16 initial_states=2 orders=4 frozen_native_false_faults=%0d supervisor_only_false_faults=%0d NO_DMA_COMMANDS",old_count,half_count);
        $display("RESULT: PASS pre_bme_training cases=32 legacy_lockout=32 fixed_lockout=0");
        $display("RESULT: PASS native_startup_all");$finish;
    end
    initial begin #300000;$fatal(1,"native startup watchdog");end
endmodule
`undef NATIVE_IDLE_PROBE
