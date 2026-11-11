`timescale 1ns/1ps
// Complete headers enter the WORD parser directly, with explicit valid-low
// packet boundaries. This bench does not model electrical PHY or PIX sticky.
module startup_leaf_member #(
    parameter [1:0] VC=0,
    parameter [31:0] INITIAL_SEQUENCE=0
) (
    input wire clk,decoder_n,identity_n,ready,
    input wire [31:0] data,input wire valid,
    output wire fault,output wire [31:0] sequence_count,
    output wire out_valid,output wire [136:0] held_bus,
    output wire [3:0] code,output wire identity_valid,
    output wire [15:0] frame_number,output wire ecc_error
);
    wire [47:0] pixels;
    wire sof,eol,abort_item,cycle_valid;
    wire [31:0] group_id,event_sequence;
    assign held_bus={pixels,sof,eol,abort_item,code,group_id,event_sequence,
        identity_valid,cycle_valid,frame_number};
    real_hdr_csi_word_core #(.TARGET_VC(VC),.SAMPLE_BITS(12),.SEQUENCE_INITIAL(INITIAL_SEQUENCE)) dut(
        .i_clk(clk),.i_reset_n(decoder_n),.i_identity_rst_n(identity_n),
        .i_fs_group(32'd23),.i_fs_cycle_valid(1'b1),
        .i_word(data),.i_word_valid(valid),.i_sink_ready(ready),
        .o_source_sequence_count(sequence_count),.o_identity_fault(fault),
        .o_event_group(group_id),.o_event_sequence(event_sequence),
        .o_event_identity_valid(identity_valid),.o_event_cycle_valid(cycle_valid),
        .o_event_frame_number(frame_number),.o_data(pixels),.o_valid(out_valid),
        .o_sof(sof),.o_eol(eol),.o_abort(abort_item),.o_error_code(code),
        .o_header_ecc_error(ecc_error),.o_payload_crc_error(),.o_length_error(),
        .o_wait_for_sync(),.o_packet_done(),.o_packet_continue(),
        .o_fs_observe_valid(),.o_fs_observe_number(),
        .o_fs_observe_sequence(),.o_fs_observe_trusted());
endmodule

module tb_hdr_startup_leaf #(parameter integer EXPECT_STARTUP_FIX=1);
    reg clk=0,cfg_clk=0;
    always #5 clk=~clk;
    always #20 cfg_clk=~cfg_clk;
    reg identity_n=0,decoder_n=0,cfg_n=0,start=0;
    reg [31:0] data=0;
    reg valid=0;
    reg [1:0] ready=3;
    wire [1:0] faults,out_valid,identity_valid,ecc_errors;
    wire [31:0] seq[0:1];
    wire [136:0] bus[0:1];
    wire [3:0] code[0:1];
    wire [15:0] frame_number[0:1];
    genvar member;
    generate for(member=0;member<2;member=member+1)begin:g_member
        startup_leaf_member #(.VC(member)) u_member(
            .clk(clk),.decoder_n(decoder_n),.identity_n(identity_n),
            .ready(ready[member]),.data(data),.valid(valid),
            .fault(faults[member]),.sequence_count(seq[member]),
            .out_valid(out_valid[member]),.held_bus(bus[member]),.code(code[member]),
            .identity_valid(identity_valid[member]),.frame_number(frame_number[member]),
            .ecc_error(ecc_errors[member]));
    end endgenerate
    reg [31:0] limit_data=0;
    reg limit_valid=0;
    wire limit_fault,limit_out_valid,limit_identity,limit_ecc;
    wire [31:0] limit_sequence;
    wire [136:0] limit_bus;
    wire [3:0] limit_code;
    wire [15:0] limit_number;
    startup_leaf_member #(.VC(0),.INITIAL_SEQUENCE(32'hfffffffe)) u_limit(
        .clk(clk),.decoder_n(decoder_n),.identity_n(identity_n),.ready(1'b1),
        .data(limit_data),.valid(limit_valid),.fault(limit_fault),
        .sequence_count(limit_sequence),.out_valid(limit_out_valid),
        .held_bus(limit_bus),.code(limit_code),.identity_valid(limit_identity),
        .frame_number(limit_number),.ecc_error(limit_ecc));

    // Deliberate leaf CDC; full production WORD->PIX FIFO/sticky is separate.
    reg [1:0] fault_cfg=0;
    always @(posedge cfg_clk or negedge cfg_n)
        if(!cfg_n)fault_cfg<=0;else fault_cfg<={fault_cfg[0],|faults};
    wire cfg_written,cfg_stable,cfg_error,xclr,scl;
    wire [7:0] cfg_index;
    wire [127:0] diag;
    tri sda;
    pullup(sda);
    reg slave_low=0,active_transfer=0,release_ack=0;
    integer bit_count=0;
    assign sda=slave_low?1'b0:1'bz;
    real_hdr_sensor_config #(.WARMUP_PAIRS(8),.I2C_HALF_PERIOD(8),
        .RESET_HOLD_CYCLES(4),.RELEASE_WAIT_CYCLES(6),.REGULATOR_WAIT_CYCLES(5)) cfg(
        .i_clk(cfg_clk),.i_rst_n(cfg_n),.i_start(start),.i_clock_locked(1'b1),
        .i_abort(1'b0),.i_source_fault(fault_cfg[1]),.i_pair_event(1'b0),.i_pair_ok(1'b0),
        .o_start_ready(),.o_xclr(xclr),.o_scl(scl),.io_sda(sda),
        .o_config_written(cfg_written),.o_stable(cfg_stable),.o_error(cfg_error),
        .o_register_index(cfg_index),.o_rx_diag_cfg(diag));
    always @(negedge sda)if(cfg_n&&scl===1'b1&&!slave_low)begin
        active_transfer=1;release_ack=0;bit_count=0;
    end
    always @(posedge sda)if(cfg_n&&scl===1'b1&&active_transfer&&!slave_low)active_transfer=0;
    always @(posedge scl)if(cfg_n&&active_transfer)
        if(bit_count<8)bit_count=bit_count+1;else bit_count=0;
    always @(negedge scl)begin
        if(!cfg_n||!active_transfer)begin slave_low=0;release_ack=0;end
        else if(release_ack)begin slave_low=0;release_ack=0;end
        else if(bit_count==8)begin slave_low=1;release_ack=1;end
    end

    integer failures=0,checks=0,cases=0,cycles=0,k,j;
    integer fs[0:1],trusted_fs[0:1],fe[0:1],zero_frame_fs[0:1];
    integer hold_checks=0;
    reg [1:0] held=0;
    reg [136:0] saved[0:1];
    always @(posedge clk or negedge identity_n)begin
        if(!identity_n)begin
            held=0;
            for(k=0;k<2;k=k+1)begin fs[k]=0;trusted_fs[k]=0;fe[k]=0;zero_frame_fs[k]=0;end
        end else if(!decoder_n)held=0;
        else begin
            for(k=0;k<2;k=k+1)begin
                if(held[k])begin
                    hold_checks=hold_checks+1;
                    if(!out_valid[k]||bus[k]!==saved[k])begin
                        failures=failures+1;$display("CHECK_FAIL stalled output changed VC%0d",k);
                    end
                end
                held[k]=out_valid[k]&&!ready[k];saved[k]=bus[k];
                if(out_valid[k]&&ready[k])begin
                    if(code[k]==7)begin
                        fs[k]=fs[k]+1;
                        if(identity_valid[k])trusted_fs[k]=trusted_fs[k]+1;
                        if(frame_number[k]==0)zero_frame_fs[k]=zero_frame_fs[k]+1;
                    end
                    if(code[k]==6)fe[k]=fe[k]+1;
                end
            end
        end
    end
    function [5:0] ecc(input [23:0] h);
        begin
            ecc[0]=^(h&24'hf12cb7);ecc[1]=^(h&24'hf2555b);ecc[2]=^(h&24'h749a6d);
            ecc[3]=^(h&24'hb8e38e);ecc[4]=^(h&24'hdf03f0);ecc[5]=^(h&24'heffc00);
        end
    endfunction
    function [31:0] header(input [1:0] vc,input [5:0] dt,input [15:0] number);
        reg [23:0] h;begin h={number,vc,dt};header={2'b00,ecc(h),h};end
    endfunction
    task cfg_ticks(input integer n);repeat(n)begin @(posedge cfg_clk);#1;end endtask
    task word_ticks(input integer n);repeat(n)begin @(posedge clk);#1;end endtask
    task check(input bit okay,input string why);
        begin
            checks=checks+1;
            if(!okay)begin failures=failures+1;
                $display("CHECK_FAIL %s faults=%b seq=%0d/%0d cfg=%032h",why,faults,seq[0],seq[1],diag);
            end
        end
    endtask
    task cold_and_config;
        begin
            @(negedge cfg_clk);cfg_n=0;identity_n=0;decoder_n=0;
            valid=0;limit_valid=0;start=0;ready=3;slave_low=0;active_transfer=0;
            release_ack=0;bit_count=0;cfg_ticks(4);
            @(negedge cfg_clk);cfg_n=1;identity_n=1;decoder_n=1;
            cfg_ticks(2);@(negedge cfg_clk);start=1;cfg_ticks(1);
            @(negedge cfg_clk);start=0;cycles=0;
            while(!cfg_written&&!cfg_error&&cycles<100000)begin cfg_ticks(1);cycles=cycles+1;end
            cfg_ticks(3);
            check(cfg_written&&!cfg_error&&diag[47:32]==139&&diag[63:48]==0,
                "all real I2C writes ACK before parser stimulus");
        end
    endtask
    task send(input [31:0] h);
        begin
            @(negedge clk);data=h;valid=1;
            @(negedge clk);valid=0;data=0;word_ticks(8);cfg_ticks(5);
        end
    endtask
    task limit_send(input [31:0] h);
        begin
            @(negedge clk);limit_data=h;limit_valid=1;
            @(negedge clk);limit_valid=0;limit_data=0;word_ticks(8);
        end
    endtask
    task soft_reset;
        begin
            @(negedge clk);decoder_n=0;word_ticks(4);
            @(negedge clk);decoder_n=1;word_ticks(8);cfg_ticks(5);
        end
    endtask
    task report_case(input string name_text);
        begin
            cases=cases+1;
            $display("CASE %s expect_fix=%0d faults=%b seq=%0d/%0d fs=%0d/%0d trusted=%0d/%0d cfg_state=%0d flags=%03h writes=%0d write_errors=%0d written=%0d hold_checks=%0d",
                name_text,EXPECT_STARTUP_FIX,faults,seq[0],seq[1],fs[0],fs[1],trusted_fs[0],trusted_fs[1],
                diag[15:12],diag[11:0],diag[47:32],diag[63:48],cfg_written,hold_checks);
        end
    endtask
    initial begin
        cold_and_config();send(header(0,0,0));send(header(1,0,0));
        check(faults==0&&seq[0]==1&&seq[1]==1&&trusted_fs[0]==1&&trusted_fs[1]==1&&
            zero_frame_fs[0]==1&&zero_frame_fs[1]==1&&cfg_written,"both VCs accept frame_number zero");
        report_case("clean_VC0_VC1_frame_number_zero");

        cold_and_config();
        repeat(3)send(header(0,0,1)^32'h03000000);
        check(seq[0]==0&&seq[1]==0&&ecc_errors==3&&fs[0]==0&&fs[1]==0,
            "several malformed startup headers are rejected and counted as ECC errors");
        check(faults==(EXPECT_STARTUP_FIX?2'b00:2'b11)&&cfg_written==EXPECT_STARTUP_FIX,
            "startup bad headers preserve new candidate config but reproduce baseline fault");
        send(header(0,0,0));send(header(1,0,0));
        check(seq[0]==1&&seq[1]==1&&trusted_fs[0]==EXPECT_STARTUP_FIX&&trusted_fs[1]==EXPECT_STARTUP_FIX,
            "valid first target FS establishes only candidate trust after startup bad headers");
        check(EXPECT_STARTUP_FIX?(cfg_written&&!cfg_error):
            (cfg_error&&diag[15:12]==8&&diag[11:0]==12'ha14&&diag[47:32]==139&&diag[63:48]==0),
            "parser-produced baseline A14 versus candidate WARMUP written remains source-bound");
        report_case("three_pre_FS_bad_headers_then_correct_both_VCs");

        cold_and_config();send(header(2,0,0));send(header(3,0,7));
        check(seq[0]==0&&seq[1]==0&&faults==0,"other VCs cannot arm target sequence");
        send(header(2,0,2)^32'h03000000);
        check(faults==(EXPECT_STARTUP_FIX?0:3),"wrong-VC FS did not arm first-target protection");
        send(header(0,0,2));send(header(1,0,2));
        check(trusted_fs[0]==EXPECT_STARTUP_FIX&&trusted_fs[1]==EXPECT_STARTUP_FIX,
            "only target FS establishes first identity after wrong-VC startup traffic");
        report_case("wrong_VC_does_not_start_target_identity");

        cold_and_config();send(header(0,0,0)^32'h00000040);send(header(1,0,0)^32'h01000000);
        check(faults==0&&seq[0]==1&&seq[1]==1&&trusted_fs[0]==1&&trusted_fs[1]==1&&
            zero_frame_fs[0]==1&&zero_frame_fs[1]==1&&cfg_written,
            "single-bit VC-data correction and parity correction establish correct target FS");
        report_case("single_bit_ECC_correction_data_and_parity");

        cold_and_config();soft_reset();send(header(0,0,0));send(header(1,0,0));
        check(faults==0&&trusted_fs[0]==1&&trusted_fs[1]==1&&cfg_written,
            "decoder reset before target FS leaves unpublished identity available");
        report_case("pre_FS_decoder_reset_control");

        cold_and_config();send(header(0,0,1));send(header(0,0,2)^32'h03000000);
        check(faults==(EXPECT_STARTUP_FIX?2'b01:2'b11)&&cfg_error,
            "bad header after VC0 FS remains permanent; VC1 not started in candidate");
        send(header(0,0,3));send(header(1,0,3));
        check(seq[0]==2&&seq[1]==1&&trusted_fs[0]==1&&trusted_fs[1]==EXPECT_STARTUP_FIX&&cfg_error,
            "later valid FS cannot restore old VC0 SOURCE trust");
        report_case("post_FS_bad_header_strict_per_VC");

        cold_and_config();send(header(0,0,1));soft_reset();
        check(faults==2'b01&&cfg_error,"decoder reset after VC0 FS must remain strict");
        send(header(0,0,2));send(header(1,0,2));
        check(seq[0]==2&&seq[1]==1&&trusted_fs[0]==1&&trusted_fs[1]==1&&cfg_error,
            "decoder reset preserves untrusted old SOURCE while other VC may establish its first");
        report_case("post_FS_decoder_reset_strict_per_VC");

        cold_and_config();send(header(0,0,1));send(header(1,0,1));
        send(header(0,0,2)^32'h03000000);send(header(0,0,3));send(header(1,0,3));
        check(faults==3&&seq[0]==2&&seq[1]==2&&trusted_fs[0]==1&&trusted_fs[1]==1&&cfg_error,
            "both established VCs remain failed after later ambiguity and good FS");
        report_case("both_VCs_post_FS_bad_header_no_resync");

        cold_and_config();ready=0;send(header(0,0,0));send(header(1,0,0));
        check(out_valid==3,"both first FS controls held under finite backpressure");
        send(header(0,1,0));send(header(1,1,0));word_ticks(20);
        check(faults==0&&seq[0]==1&&seq[1]==1&&fs[0]==0&&fs[1]==0&&cfg_written,
            "bounded FS and FE queues do not corrupt sequence or configuration");
        @(negedge clk);ready=1;word_ticks(5);@(negedge clk);ready=0;word_ticks(5);
        @(negedge clk);ready=2;word_ticks(5);@(negedge clk);ready=3;word_ticks(8);
        check(fs[0]==1&&fs[1]==1&&fe[0]==1&&fe[1]==1&&trusted_fs[0]==1&&trusted_fs[1]==1&&hold_checks>20,
            "full data and metadata stable until real handshakes; queued terminals drain once");
        report_case("finite_backpressure_FS_FE_hold_and_drain");

        cold_and_config();limit_send(header(0,0,0));
        check(limit_sequence==32'hffffffff&&!limit_fault,"last unique identity reaches saturation without wrap");
        limit_send(header(0,0,1));
        check(limit_sequence==32'hffffffff&&limit_fault,"exhaustion faults instead of reusing SOURCE");
        limit_send(header(0,0,2));soft_reset();
        check(limit_sequence==32'hffffffff&&limit_fault,"later FS and decoder reset cannot clear exhausted SOURCE");
        report_case("sequence_exhaustion_no_wrap_no_soft_recovery");

        cold_and_config();send(header(0,0,0));send(header(1,0,0));
        check(faults==0&&trusted_fs[0]==1&&trusted_fs[1]==1&&cfg_written,
            "only explicit coordinated identity reset starts a new valid SOURCE cohort");
        report_case("explicit_identity_cohort_reset_reestablishes_new_sequence");

        if(failures==0)$display("RESULT: PASS cases=%0d checks=%0d hold_checks=%0d expect_fix=%0d",
            cases,checks,hold_checks,EXPECT_STARTUP_FIX);
        else $fatal(1,"RESULT: FAIL failures=%0d",failures);
        $finish;
    end
    initial begin #60000000;$fatal(1,"overall test timeout");end
endmodule
