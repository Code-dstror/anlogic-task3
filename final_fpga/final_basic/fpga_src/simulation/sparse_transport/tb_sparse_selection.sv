`timescale 1ns/1ps
module tb_sparse_selection;
    wire [1:0] done;
    sparse_selection_case #(.ENABLE(0)) default_profile(done[0]);
    sparse_selection_case #(.ENABLE(1)) sparse_profile(done[1]);
    initial begin wait(&done);$display("RESULT: PASS SPARSE_SELECTION actual_dual_domain_ack v4_2112 v3_unsupported v1_v2_legal");$finish;end
    initial begin #300000;$fatal(1,"sparse selector watchdog");end
endmodule

module sparse_selection_case #(parameter integer ENABLE=0)(output reg done=0);
    reg uc=0,dc=0,ur=0,dr=0,drun=1,urun=1;
    always #4 if(urun)uc=~uc;always #5.5 if(drun)dc=~dc;
    reg wv=0,rv=0;reg [11:0] wo=0,ro=0;reg [31:0] wd=0;
    wire [1:0] wr,rr;wire rrv;wire [31:0] rd;
    wire busy,udone,ddone;wire [15:0] uv,uh,dv;wire [31:0] ue,de,stale;
    reg dquiet=1,app=0;reg [31:0] user_session=55,dfi_session=55;
    integer checks=0,commands=0,acks=0;
    record_format_service #(.RECORD_V3_ENABLE(ENABLE)) dut(
        .i_user_clk(uc),.i_user_rst_n(ur),.write_valid(wv),.write_offset(wo),.write_data(wd),
        .write_strobes(4'hf),.write_response(wr),.read_valid(rv),.read_offset(ro),
        .read_response_valid(rrv),.read_data(rd),.read_response(rr),
        .i_user_source_session(user_session),.i_user_source_session_ready(1'b1),.i_app_enable(app),
        .i_c2h_running(1'b0),.i_tx_busy(1'b0),.i_source_functional_quiescent(1'b1),
        .i_session_armed(1'b0),.i_rearm_ready(1'b1),.o_user_busy(busy),
        .o_user_selected_version(uv),.o_user_selected_header_length(uh),.o_user_selection_epoch(ue),
        .o_user_reset_done(udone),.o_stale_ack_count(stale),.i_dfi_clk(dc),.i_dfi_rst_n(dr),
        .i_dfi_source_session(dfi_session),.i_dfi_quiescent(dquiet),.o_dfi_selected_version(dv),
        .o_dfi_selection_epoch(de),.o_dfi_reset_done(ddone));
    task check(input bit condition,input string message);
        begin checks++;if(!condition)$fatal(1,"sparse selection enable%0d %s",ENABLE,message);end
    endtask
    always @(posedge dc)if(dut.command_sink_valid&&dut.command_sink_ready)commands++;
    always @(posedge uc)if(dut.ack_sink_valid&&dut.ack_sink_ready)acks++;
    task write(input [11:0] off,input [31:0] value);
        begin @(negedge uc);wo=off;wd=value;wv=1;#1;check(wr==0,"public BAR write accepted");
            @(posedge uc);@(negedge uc);wv=0;end
    endtask
    task read(input [11:0] off,input [31:0] value);
        begin @(negedge uc);ro=off;rv=1;@(posedge uc);#1;
            if(rd!==value)$display("READ_MISMATCH enable=%0d offset=%h got=%h expected=%h",ENABLE,off,rd,value);
            check(rrv&&rr==0&&rd===value,"public BAR exact response");
            @(negedge uc);rv=0;end
    endtask
    task request(input [31:0] version,input [31:0] sequence_id);
        begin write('h290,version);write('h294,sequence_id);write('h298,55);write('h29c,1);end
    endtask
    task terminal(input [31:0] error_code,input [15:0] version,input [31:0] epoch);
        begin wait(!busy);read('h2ac,error_code);read('h2b0,version);read('h2b4,version==4?2112:version==2?192:64);
            read('h2b8,epoch);check(uv==dv&&ue==de,"DFI actual selection agrees at complete ACK");end
    endtask
    initial begin
        #3;repeat(5)@(negedge uc);ur=1;dr=1;wait(udone&&ddone);
        read('h288,ENABLE?99:3);read('h28c,ENABLE?22:6);read('h2b0,1);read('h2b4,64);
        request(3,1);terminal(1,1,0);check(commands==0,"removed V3 rejected before enqueue");
        if(!ENABLE)begin
            request(4,2);terminal(1,1,0);check(commands==0,"default disabled sparse V4 rejected");
            request(2,3);terminal(0,2,1);request(1,4);terminal(0,1,2);
        end else begin
            write('h290,4);write('h294,2);write('h298,55);
            @(negedge dc);drun=0;write('h29c,1);
            repeat(23)begin @(negedge uc);check(busy&&uv==1&&ue==0,"stopped DFI cannot fabricate ACK");end
            drun=1;terminal(0,4,1);check(commands==1&&acks==1&&stale==0,"one actual whole V4 command/ACK");
            dquiet=0;request(2,3);terminal(2,4,1);dquiet=1;
            dfi_session=56;request(2,4);terminal(4,4,1);dfi_session=55;
            app=1;request(2,5);terminal(2,4,1);app=0;
            user_session=56;request(2,6);terminal(4,4,1);user_session=55;
            request(2,7);terminal(0,2,2);request(1,8);terminal(0,1,3);request(4,9);terminal(0,4,4);
            // Any-domain reset discards a partially serialized official40 control message.
            write('h290,2);write('h294,10);write('h298,55);@(negedge dc);drun=0;
            fork
                write('h29c,1);
                begin wait(dut.command_fifo.source_busy&&dut.command_fifo.source_flit_index==1);#1;dr=0;end
            join
            repeat(6)@(negedge uc);check(!udone&&!ddone&&uv==1&&dv==1,"common reset clears both owners");
            dr=1;repeat(7)@(negedge uc);check(!udone,"stopped peer holds reset done low");
            drun=1;wait(udone&&ddone);check(!busy&&ue==0&&de==0,"partial packet cannot cross reset cohort");
            request(4,11);terminal(0,4,1);
            // Quiet/session are sampled at the real complete command take.
            // Later changes must not alter the stored decision or ACK tuple.
            fork
                request(2,12);
                begin
                    wait(dut.decision_pending);@(negedge dc);
                    dquiet=0;dfi_session=56;
                end
            join
            terminal(0,2,2);dfi_session=55;
            fork
                request(4,13);
                begin wait(dut.decision_pending);@(negedge dc);dquiet=1;end
            join
            terminal(2,2,2);
            // Abort the newly added private decision stage before publication.
            fork
                request(4,14);
                begin wait(dut.decision_pending);@(negedge dc);dr=0;end
            join
            repeat(4)@(negedge uc);
            check(!udone&&!ddone&&uv==1&&dv==1,"reset during decision clears both owners");
            dr=1;wait(udone&&ddone);check(!busy&&ue==0&&de==0,"no pending decision after reset");
            request(4,15);terminal(0,4,1);
            fork
                request(2,16);
                begin
                    wait(dut.decision_pending);@(negedge uc);urun=0;
                    repeat(25)@(negedge dc);
                    check(busy&&uv==4&&ue==1&&dv==2&&de==2,
                        "stopped USER cannot publish pending actual DFI selection");
                    urun=1;
                end
            join
            terminal(0,2,2);
        end
        $display("SPARSE_SELECTION_CASE_PASS enable=%0d checks=%0d commands=%0d acks=%0d",ENABLE,checks,commands,acks);done=1;
    end
endmodule
