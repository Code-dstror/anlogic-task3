`timescale 1ns/1ps
module r3_fence_case #(parameter SPLIT=0)(output reg done=0);
    reg i_clk=0,clock_run=1,rst_source=0,mode_running=1,hdr_mode=0,data_noise=1;
    always #4 i_clk=clock_run?!i_clk:0;
    wire i_rst_n=rst_source&&mode_running&&!hdr_mode;
    wire i_data_reset_n=SPLIT ? (rst_source&&mode_running&&!hdr_mode) : data_noise;
__DECLARATIONS__
    integer checks=0,frames=0,negative_frames=0,raw_takes=0,native_takes=0;
    integer async_checks=0,mode_changes=0,clock_stops=0,unequal_ignored=0,cycles=0,n,guard;
    reg [31:0] rng=32'h26a7f031+SPLIT;
    reg [31:0] sequence_id=10;
    physical_identity_source_fence #(.SEPARATE_DATA_RESET(SPLIT)) dut(
__DUT_PORTS__,.i_data_reset_n(i_data_reset_n));
    r3_fence_reference reference(
__REFERENCE_PORTS__);
    task check(input bit okay,input string why);
        begin checks=checks+1;if(!okay)$fatal(1,"fence split=%0d checks=%0d %s state=%0d ref=%0d",SPLIT,checks,why,dut.state,reference.state);end
    endtask
    task compare;
        begin
            check({__OUTPUTS_DUT__}==={__OUTPUTS_REFERENCE__},"every output bit cycle-equivalent to R1");
            check({dut.state,dut.context_seen,dut.terminal_seen,dut.crop_done,dut.rgb_done,dut.failed,
                dut.raw_issued,dut.native_issued,dut.raw_taken,dut.native_taken}===
                {reference.state,reference.context_seen,reference.terminal_seen,reference.crop_done,reference.rgb_done,reference.failed,
                reference.raw_issued,reference.native_issued,reference.raw_taken,reference.native_taken},
                "all ownership/state progression exact");
            if(SPLIT)check(i_data_reset_n===i_rst_n,"production masks have identical logical value");
            else if(i_data_reset_n!==i_rst_n)unequal_ignored=unequal_ignored+1;
        end
    endtask
    always @(posedge i_clk)begin
        if(i_rst_n)begin
            if(dut_o_raw_source_valid&&i_raw_source_ready)raw_takes=raw_takes+1;
            if(dut_o_native_source_valid&&i_native_source_ready)native_takes=native_takes+1;
        end
        #1;compare();cycles=cycles+1;
    end
    always @(negedge i_clk)begin #1;compare();end
    task clear_inputs;
        begin
__INITIALIZE__
            i_admit_enable=1;i_event_ok=1;i_event_identity_valid=1;
            i_context_session=7;i_context_epoch=3;i_context_camera=0;
            i_crop_geometry_done=1;i_rgb_geometry_done=1;i_crop_input_quiet=1;i_rgb_output_quiet=1;
        end
    endtask
    task ticks(input integer amount);
        begin repeat(amount)@(negedge i_clk);#2;end
    endtask
    task reset_case;
        begin
            @(negedge i_clk);rst_source=0;#1;
            compare();check(!dut_o_event_ready&&!dut_o_context_ready&&!dut_o_capture_frame_enable&&
                !dut_o_source_idle&&!dut_o_raw_source_valid&&!dut_o_native_source_valid,"async assertion closes all masks and tails");
            async_checks=async_checks+1;clear_inputs();ticks(3);
            @(negedge i_clk);rst_source=1;#1;compare();
            check(dut_o_event_ready&&dut_o_source_idle,"no new release-cycle latency");ticks(2);
        end
    endtask
    task event_word(input [1:0] kind,input bit identity_ok,input [31:0] seq);
        begin
            @(negedge i_clk);i_event_kind=kind;i_event_valid=1;i_event_identity_valid=identity_ok;i_event_sequence=seq;
            guard=0;
            do begin @(posedge i_clk);guard=guard+1;check(guard<40,"event ready bounded");end while(!dut_o_event_ready);
            @(negedge i_clk);i_event_valid=0;#2;
        end
    endtask
    task open_frame;
        begin
            sequence_id=sequence_id+1;i_event_ok=1;i_event_error=0;i_continuity_fault=0;i_source_fault=0;
            event_word(0,1,sequence_id);check(dut_o_capture_frame_enable&&!dut_o_source_idle,"accepted FS owns frame");
            frames=frames+1;
            // A new FS cannot displace the retained owner.
            i_event_valid=1;i_event_kind=0;ticks(3);check(!dut_o_event_ready,"owned frame holds another FS");i_event_valid=0;
            i_context={64'hfedcba9876543210,64'h0000000000000007,64'h8000000000000001,384'h123456789};
            i_context_sequence=sequence_id;i_context_tag={32'h93124567,sequence_id};
            @(negedge i_clk);i_context_valid=1;
            @(posedge i_clk);check(dut_o_context_ready,"original context handshake");
            @(negedge i_clk);i_context_valid=0;ticks(2);
        end
    endtask
    task retire_frame(input bit expected_ok);
        reg [575:0] context_held;
        reg [63:0] tag_held;
        begin
            guard=0;while(!dut_o_raw_source_valid||!dut_o_native_source_valid)begin ticks(1);guard=guard+1;check(guard<30,"both real SOURCE conclusions bounded");end
            context_held=dut_o_native_source_context;tag_held=dut_o_native_source_tag;
            repeat(9)begin
                ticks(1);check(dut_o_raw_source_valid&&dut_o_native_source_valid&&
                    dut_o_raw_source_ok==expected_ok&&dut_o_native_source_ok==expected_ok,"dual SOURCE held status exact");
                check(dut_o_raw_source_sequence==sequence_id&&dut_o_native_source_context===context_held&&dut_o_native_source_tag==tag_held,
                    "source identity and full576-bit capsule immutable");
                check(!dut_o_source_idle,"held tails retain owner");
            end
            i_raw_source_ready=1;ticks(1);i_raw_source_ready=0;
            ticks(4);check(!dut_o_source_idle&&dut_o_native_source_valid,"native tail independently prevents reuse");
            i_native_source_ready=1;ticks(1);i_native_source_ready=0;ticks(3);
            check(dut_o_source_idle&&!dut_o_capture_frame_enable,"both real tails release owner");
            if(!expected_ok)negative_frames=negative_frames+1;
        end
    endtask
    initial begin
        clear_inputs();ticks(3);reset_case();
        // Normal FS/context/FE and mismatched FE followed by the real terminal.
        open_frame();event_word(1,1,sequence_id+1);ticks(2);
        check(!dut.terminal_seen,"wrong FE identity stays stale");
        event_word(1,1,sequence_id);retire_frame(1);
        // Original negative source/error isolation with held independent tails.
        open_frame();i_event_ok=0;i_event_error=8'd2;event_word(2,1,sequence_id);retire_frame(0);
        open_frame();i_continuity_fault=1;ticks(3);retire_frame(0);i_continuity_fault=0;
        i_admit_enable=0;event_word(0,1,sequence_id+1);ticks(2);
        check(!dut_o_capture_frame_enable&&!dut_o_raw_source_valid&&!dut_o_native_source_valid,"unadmitted FS cannot publish");
        event_word(1,1,sequence_id+1);i_admit_enable=1;
        event_word(0,0,sequence_id+2);event_word(1,0,sequence_id+2);
        // Reset while both tails are offered and while the clock is stopped.
        open_frame();event_word(1,1,sequence_id);ticks(5);
        check(dut_o_raw_source_valid&&dut_o_native_source_valid,"held tails exist before cold reset");
        @(negedge i_clk);clock_run=0;clock_stops=clock_stops+1;#2;rst_source=0;#1;compare();
        check(!dut_o_event_ready&&!dut_o_raw_source_valid&&!dut_o_native_source_valid,"stopped-clock assertion still closes");
        async_checks=async_checks+1;#20;clear_inputs();clock_run=1;ticks(3);
        @(negedge i_clk);rst_source=1;#1;compare();check(dut_o_source_idle&&dut_o_event_ready,"restored clock has original release contract");ticks(2);
        // Mode predicates are duplicated identically in data and ASR routes.
        open_frame();@(negedge i_clk);hdr_mode=1;#1;compare();check(!dut_o_event_ready&&!dut_o_capture_frame_enable,"HDR switch closes SDR fence");
        mode_changes=mode_changes+1;ticks(3);mode_running=0;hdr_mode=0;ticks(3);
        i_event_valid=1;i_event_kind=0;i_event_identity_valid=1;i_event_sequence=200;
        #1;check(!dut_o_event_ready,"mode hold keeps queued FS blocked");
        @(negedge i_clk);mode_running=1;#1;compare();check(dut_o_event_ready,"same first eligible edge accepts queued FS");
        @(posedge i_clk);check(dut_o_event_ready,"mode-restored actual FS transfer");
        @(negedge i_clk);i_event_valid=0;mode_changes=mode_changes+1;reset_case();
        // Arbitrary bounded control/event traffic checks every exact output;
        // no data/reset physical delay is modeled or hidden by the miter.
        for(n=0;n<6000;n=n+1)begin
            @(negedge i_clk);rng=rng^(rng<<13);rng=rng^(rng>>17);rng=rng^(rng<<5);
            data_noise=rng[0];i_event_valid=rng[1];i_event_kind=rng[3:2];i_event_identity_valid=rng[4];
            i_admit_enable=rng[5];i_event_ok=rng[6];i_event_error=rng[7]?0:8'd2;
            i_event_sequence=rng[8]?sequence_id:sequence_id+1;
            i_context_valid=rng[9];i_context_sequence=rng[10]?sequence_id:sequence_id+1;
            i_raw_source_ready=rng[11];i_native_source_ready=rng[12];
            i_crop_geometry_done=rng[13];i_rgb_geometry_done=rng[14];i_crop_input_quiet=rng[15];i_rgb_output_quiet=rng[16];
            i_source_fault=rng[21:17]==0;i_continuity_fault=rng[26:22]==0;
            if(n%233==0)rst_source=0;else rst_source=1;
        end
        reset_case();open_frame();event_word(1,1,sequence_id);retire_frame(1);
        check(frames>=6&&negative_frames==2&&async_checks>=3&&clock_stops==1&&mode_changes==2,"required scenario coverage");
        if(!SPLIT)check(unequal_ignored>1000,"default parameter really ignores differing optional data input");
        $display("RESULT: PASS r3_fence split=%0d checks=%0d cycles=%0d frames=%0d negative=%0d raw_takes=%0d native_takes=%0d async=%0d clock_stops=%0d mode_changes=%0d ignored_differences=%0d",
            SPLIT,checks,cycles,frames,negative_frames,raw_takes,native_takes,async_checks,clock_stops,mode_changes,unequal_ignored);
        done=1;
    end
endmodule
module r3_tb_fence_split;
    wire legacy_done,split_done;
    r3_fence_case #(.SPLIT(0)) legacy(legacy_done);
    r3_fence_case #(.SPLIT(1)) production(split_done);
    initial begin wait(legacy_done&&split_done);$display("RESULT: PASS r3_fence_all");$finish;end
    initial begin #200000;$fatal(1,"r3 fence watchdog");end
endmodule
