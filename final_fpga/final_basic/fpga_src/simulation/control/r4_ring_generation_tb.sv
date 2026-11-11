`timescale 1ns/1ps
module r4_ring_generation_case #(parameter integer CAMERAS=1)(output reg done=0);
    reg i_clk=0;
    __DECLARATIONS__
    jpeg_frame_ring #(.CAMERA_COUNT(CAMERAS),.WRITE_RESULT_ENABLE(1),.WRITE_TAG_ENABLE(1),.MASK_ENABLE(1)) dut(
        __DUT_PORTS__);
    r4_ring_reference #(.CAMERA_COUNT(CAMERAS),.WRITE_RESULT_ENABLE(1),.WRITE_TAG_ENABLE(1),.MASK_ENABLE(1)) refdut(
        __REFERENCE_PORTS__);
    reg [31:0] expected[0:CAMERAS*3-1];
    reg [31:0] rng=32'ha7613bf0+CAMERAS;
    integer checks=0,cycles=0,starts=0,wraps=0,retire_blocks=0,reset_cancels=0;
    integer g,target,value_case,trial,limit,taken_slot;
    reg [31:0] seed_value;
    function [31:0] random_word;
        begin rng=rng*32'd1664525+32'd1013904223;random_word=rng;end
    endfunction
    task check(input bit ok,input string why);
        begin checks=checks+1;if(!ok)$fatal(1,"ring CAMERAS=%0d cycle=%0d: %s",CAMERAS,cycles,why);end
    endtask
    task compare;
        begin
            check({__DUT_OUTPUTS__}==={__REFERENCE_OUTPUTS__},"all complete ring outputs vs fixed R3");
            check({dut.ws,dut.rs,dut.writer,dut.allocation,dut.allocation_local,dut.cold_valid}===
                {refdut.ws,refdut.rs,refdut.writer,refdut.allocation,refdut.allocation_local,refdut.cold_valid},
                "writer/allocation/ownership controls exact");
            for(g=0;g<CAMERAS*3;g=g+1)begin
                check(dut.slot_gen[g]===refdut.slot_gen[g],"every generation register exact");
                check(dut.slot_gen[g]===expected[g],"independent per-slot generation oracle");
                check({dut.slot_state[g],dut.slot_pin[g],dut.slot_pending[g],dut.slot_session[g]}===
                    {refdut.slot_state[g],refdut.slot_pin[g],refdut.slot_pending[g],refdut.slot_session[g]},
                    "all slot authority states unchanged");
            end
        end
    endtask
    task step;
        begin
            #1;
            if(!i_rst_n)for(g=0;g<CAMERAS*3;g=g+1)expected[g]=0;
            compare();
            if(i_rst_n&&i_start_valid&&dut_o_start_ready)begin
                taken_slot=dut.allocation;
                check(taken_slot>=0&&taken_slot<CAMERAS*3,"real start has a real slot");
                if(expected[taken_slot]==32'hffffffff)begin expected[taken_slot]=1;wraps=wraps+1;end
                else expected[taken_slot]=expected[taken_slot]+1'b1;
                starts=starts+1;
            end
            if(i_start_valid&&i_retire_valid)begin
                check(!dut_o_start_ready,"RETIRE request blocks same-edge START by original contract");
                retire_blocks=retire_blocks+1;
            end
            #2;i_clk=1;cycles=cycles+1;#1;compare();#1;i_clk=0;
        end
    endtask
    task reset_ring;
        begin
            i_rst_n=0;i_start_valid=0;i_result_valid=0;i_retire_valid=0;i_req_valid=0;
            repeat(2)step();i_rst_n=1;repeat(2)step();
        end
    endtask
    task abort_empty_frame;
        begin
            i_start_valid=0;i_result_valid=1;i_result_ok=0;i_result_length=0;
            check(dut_o_result_ready,"writer accepts true negative result");step();i_result_valid=0;
            limit=0;
            while(dut.ws!=0||dut_o_write_result_valid)begin step();limit=limit+1;check(limit<12,"empty failed frame drains");end
        end
    endtask
    initial begin
        __INITIALIZE__
        for(g=0;g<CAMERAS*3;g=g+1)expected[g]=0;
        i_ddr_ready=1;i_width=1920;i_height=1080;i_quality=75;i_session_id=32'h47c1;
        i_mode_epoch=8;i_write_result_ready=1;i_retire_rsp_ready=1;i_rsp_ready=1;i_mask_allocation_ready=1;
        reset_ring();
        for(target=0;target<CAMERAS*3;target=target+1)begin
            for(value_case=0;value_case<5;value_case=value_case+1)begin
                reset_ring();
                case(value_case)
                    0:seed_value=0;1:seed_value=32'hfffffffe;2:seed_value=32'hffffffff;
                    3:seed_value=32'h7fffffff;default:seed_value=random_word();
                endcase
                for(g=0;g<CAMERAS*3;g=g+1)begin
                    expected[g]=g==target?seed_value:random_word();
                    dut.slot_gen[g]=expected[g];refdut.slot_gen[g]=expected[g];
                end
                i_camera_id=target>=3;
                dut.next_slot[target/3]=target%3;refdut.next_slot[target/3]=target%3;
                i_capture_id=random_word();i_timestamp_ns={random_word(),random_word()};i_write_tag=random_word();
                i_start_valid=1;i_retire_valid=1;step();i_retire_valid=0;
                #1;compare();check(dut_o_start_ready&&dut.allocation==target,"each physical slot allocates on original edge");
                step();i_start_valid=0;
                check(dut.writer==target,"writer owns selected slot");
                if(value_case==0)begin
                    // Short reset after a true START cancels that owner and
                    // clears every generation immediately, without a clock.
                    i_rst_n=0;#1;for(g=0;g<CAMERAS*3;g=g+1)expected[g]=0;
                    compare();reset_cancels=reset_cancels+1;i_rst_n=1;step();
                end else abort_empty_frame();
            end
        end
        reset_ring();
        for(trial=0;trial<600;trial=trial+1)begin
            i_camera_id=CAMERAS==2?(random_word()>>11):0;
            i_capture_id=random_word();i_timestamp_ns={random_word(),random_word()};i_write_tag=random_word();
            i_start_valid=1;i_retire_valid=trial%7==0;
            step();
            if(i_retire_valid)begin i_retire_valid=0;step();end
            i_start_valid=0;abort_empty_frame();
        end
        check(starts>=600+CAMERAS*15&&wraps==CAMERAS*3&&retire_blocks>80&&reset_cancels==CAMERAS*3,
            "all slots, MAX wrap, retire exclusion, reset and continuous reuse covered");
        $display("RESULT: PASS r4_ring_generation CAMERAS=%0d checks=%0d cycles=%0d starts=%0d wraps=%0d retire_blocks=%0d reset_cancels=%0d",CAMERAS,checks,cycles,starts,wraps,retire_blocks,reset_cancels);
        done=1;
    end
endmodule
module r4_ring_generation_tb;
    wire done0,done1;
    r4_ring_generation_case #(.CAMERAS(1)) c0(done0);
    r4_ring_generation_case #(.CAMERAS(2)) c1(done1);
    initial begin wait(done0&&done1);$display("RESULT: PASS r4_ring_generation_all");$finish;end
    initial begin #1000000;$fatal(1,"ring generation watchdog");end
endmodule
