    integer r4_last_collisions=0,r4_reset_cancels=0;
    task r4_extra_tests;
        integer mode,flit_index;
        begin
            // Real packet/ACK traffic is exercised by the complete fixed
            // fixture. Inject pending authorities only to test simultaneous
            // last-flit retirement/reply priority at the otherwise rare seam.
            for(mode=0;mode<3;mode=mode+1)begin
                base.reset_engine();base.pipeline_idle=1;base.frame_accept=0;boot();
                send_packet(3,0,32'h12345678,70);
                for(flit_index=0;flit_index<3;flit_index=flit_index+1)begin
                    wait(base.response_valid);@(negedge base.clk);base.response_ready=1;
                    @(posedge base.clk);@(negedge base.clk);base.response_ready=0;
                end
                check(base.dut.tx_state==4&&reference_dut.tx_state==4,"old response at final flit");
                base.dut.fault_reply_pending=1;
                reference_dut.fault_reply_pending=1;
                if(mode>=1)begin
                    base.dut.boot_reply_pending=1;
                    reference_dut.boot_reply_pending=1;
                end
                if(mode==2)begin
                    base.dut.state=3;reference_dut.state=3;
                    base.dut.remote_applied=1;reference_dut.remote_applied=1;
                    base.dut.frame_apply_eligible=1;
                    reference_dut.frame_apply_eligible=1;
                    base.frame_accept=1;base.frame_sequence=32'h7e351bc9;
                end
                base.response_ready=1;#1;compare_outputs();
                check(base.dut.response_space,"last handshake offers replacement capacity");
                @(posedge base.clk);#1;
                compare_outputs();
                check(base.dut.tx_state==1&&base.response_valid,"replacement reply starts on the same edge");
                // R3 pre-fills APPLIED kind in WAIT_FRAME; reply(2) does not
                // rewrite it. Under this artificial pending collision the
                // explicit fault reply therefore retains ERROR kind, even
                // when the later apply block commits the tuple/epoch.
                check(base.dut.reply_kind==3,"original conditional reply-kind priority retained");
                if(mode==2)check(base.mode_epoch==1,"APPLIED epoch changes on the original actual edge");
                r4_last_collisions=r4_last_collisions+1;
                @(negedge base.clk);base.response_ready=0;base.frame_accept=0;
                // A narrow asynchronous reset cancels each replacement while
                // its response is stalled. No cursor/owner may leak afterward.
                #1;base.rst_n=0;#1;compare_outputs();
                check(!base.response_valid&&base.dut.tx_index==0&&!base.dut.tx_active,
                    "async reset cancels owner and cursor immediately");
                r4_reset_cancels=r4_reset_cancels+1;
                repeat(2)@(negedge base.clk);base.rst_n=1;
                repeat(3)@(negedge base.clk);
                check(!base.response_valid,"cancelled replacement remains retired");
            end
            $display("RESULT: PASS r4_config_tx_seams TRUSTED=%0d last_collisions=%0d reset_cancels=%0d",TRUSTED,r4_last_collisions,r4_reset_cancels);
        end
    endtask
