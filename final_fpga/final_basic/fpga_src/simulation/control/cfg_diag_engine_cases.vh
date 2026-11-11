    integer diag_complete_commits=0,diag_mismatch_cases=0,diag_negative_cases=0;
    integer diag_gate_cases=0,diag_split_returns=0;
    task cfg_diag_extra_tests;
        integer word_index;
        reg [31:0] value;
        reg [1183:0] bad_ack;
        begin
            base.reset_engine();base.pipeline_idle=1;boot();
            send_packet(0,17,32'h12345678,70);take_reply(1,17,0,0);
            base.flit({1'b1,1'b0,2'd1,1'b1,3'd0,32'h12345678});
            repeat(5)@(negedge base.clk);
            check(!base.diag_data[160],"COMMIT header alone has no accepted identity");
            for(word_index=0;word_index<41;word_index=word_index+1)begin
                case(word_index)
                    0:value=17;1:value=32'h12345678;2:value=0;3:value=70;
                    4:value=1;5:value=7;6:value=12345;7:value=17;8:value=1;
                    default:value=base.extension[(word_index-9)*32+:32];
                endcase
                if(word_index<40)check(!base.diag_data[160],"incomplete COMMIT has no accepted identity");
                base.flit({1'b0,word_index==40,6'(word_index),value});
            end
            repeat(2)@(negedge base.clk);
            check(base.diag_data[95:0]=={32'd1,32'd17,32'h12345678}&&base.diag_data[160],
                "checked complete COMMIT captures session/request/target epoch");
            diag_complete_commits=diag_complete_commits+1;
            plan=base.m_config_data;
            base.send_ack(plan,1);
            check(base.diag_data[164]&&!base.diag_data[162]&&!base.diag_data[161],
                "premature exact ACK is unmatched and cannot set positive/sent");
            base.take_plan(plan);bad_ack=plan;bad_ack[31]=!bad_ack[31];base.send_ack(bad_ack,1);
            check(base.diag_data[161]&&base.diag_data[164]&&!base.diag_data[162],
                "mismatching ACK after send never marks positive");
            diag_mismatch_cases=diag_mismatch_cases+2;
            base.send_ack(plan,0);
            check(base.diag_data[163]&&!base.diag_data[162]&&!base.diag_data[166],
                "matching negative ACK marks negative only");
            take_reply(3,17,`PCIE_CFG_ERROR_RESET,0);diag_negative_cases=diag_negative_cases+1;

            base.reset_engine();base.pipeline_idle=1;boot();
            send_packet(0,17,32'h12345678,70);take_reply(1,17,0,0);
            send_packet(1,17,32'h12345678,70);base.take_plan(plan);
            base.pipeline_idle=0;base.frame_accept=0;base.send_ack(plan,1);
            check(base.diag_data[162]&&!base.diag_data[165]&&!base.diag_data[166],
                "positive ACK does not invent SOF or apply");
            base.diag_source_fs=1;base.diag_source_gates=16'ha503;
            base.frame_sequence=32'h11111111;base.frame_accept=1;
            @(posedge base.clk);#1;
            check(base.diag_data[165]&&base.diag_data[127:96]==32'h11111111&&
                base.diag_data[170:168]==3'b101&&!base.diag_data[166],
                "first ACK-following SOF captures its own failed-idle gate vector");
            check(base.diag_data[184]&&base.diag_data[223:208]==16'ha503,
                "first physical FS captures distinct physical gate vector");
            @(negedge base.clk);base.diag_source_fs=0;base.diag_source_gates=16'h5afc;
            base.frame_sequence=32'h22222222;repeat(3)@(negedge base.clk);
            check(base.diag_data[127:96]==32'h11111111&&base.diag_data[170:168]==3'b101&&
                base.diag_data[223:208]==16'ha503,"later events do not splice first-event snapshots");
            base.frame_accept=0;base.pipeline_idle=1;repeat(2)@(negedge base.clk);
            check(!base.diag_data[166],"idle without accepted frame cannot apply");
            base.frame_sequence=32'h33333333;base.frame_accept=1;
            @(posedge base.clk);#1;
            check(base.mode_epoch==1&&base.diag_data[166]&&base.diag_data[159:128]==32'h33333333&&
                !base.diag_data[167],"apply records exact sequence before response retirement");
            @(negedge base.clk);base.frame_accept=0;
            repeat(4)@(negedge base.clk);
            check(base.diag_data[166]&&!base.diag_data[167]&&base.response_valid,
                "stalled APPLIED response does not set last-sent");
            for(word_index=0;word_index<3;word_index=word_index+1)begin
                base.response_ready=1;@(posedge base.clk);@(negedge base.clk);base.response_ready=0;
            end
            check(base.dut.tx_state==4&&!base.diag_data[167],"three flits do not retire APPLIED");
            repeat(3)@(negedge base.clk);base.response_ready=1;
            @(posedge base.clk);#1;
            check(base.diag_data[167]&&!base.response_valid,"real final response handshake sets last-sent");
            @(negedge base.clk);base.response_ready=0;
            diag_gate_cases=diag_gate_cases+1;diag_split_returns=diag_split_returns+1;
            base.reset_engine();repeat(2)@(negedge base.clk);
            check(base.diag_data[167:160]==0&&base.diag_data[159:0]==0,"business reset invalidates old diagnostic identity and milestones");
            $display("RESULT: PASS cfg_diag_engine_events TRUSTED=%0d complete=%0d mismatches=%0d negative=%0d gates=%0d split_returns=%0d",
                TRUSTED,diag_complete_commits,diag_mismatch_cases,diag_negative_cases,diag_gate_cases,diag_split_returns);
        end
    endtask
