`timescale 1ns/1ps

// Control/feedback qualification only. The tap window below is a BFM; it is
// not an electrical eye model or a qualification of production thresholds.
module tb_hdr_delay_scan_feedback;
    localparam integer RAW_BYTES=768;
    reg word_clk=0;
    always #4.444444 word_clk=~word_clk;
    reg scan_reset_n=0,cohort_n=0,no_sync=0;
    reg [31:0] model_word=0;
    wire [4:0] tap;
    wire tap_write,scan_done,window_valid,scan_failed;
    wire [5:0] window_len;
    wire tap_ok=(tap>=8)&&(tap<=23);
    wire [31:0] raw_word=no_sync ? model_word : (tap_ok ? model_word : 32'd0);
    wire [31:0] lane_bytes,aligned,geared;
    wire [3:0] lane_valid;
    wire aligned_valid,geared_valid,wait_sync,done,continuation;
    wire phy_done=done&&!continuation;
    wire identity_fault,ecc_error,crc_error,length_error;
    wire [47:0] long_data,short_data;
    wire long_valid,short_valid,long_sof,short_sof,long_eol,short_eol;
    wire long_abort,short_abort;
    wire [3:0] long_error,short_error;
    wire [31:0] long_sequence,short_sequence;
    wire [1:0] uncertain;
    wire [19:0] header_info;
    wire [31:0] candidate;
    wire candidate_valid;
    genvar lane;
    generate for(lane=0;lane<4;lane=lane+1)begin:g_lane
        csi_rx_byte_align_observed u_byte(
            .I_clock(word_clk),.I_reset_n(cohort_n),.I_enable(1'b1),
            .I_lan_data_in(raw_word[8*lane+:8]),.I_wait_for_sync(wait_sync),
            .I_packet_done(phy_done),.O_data_out_vaild(lane_valid[lane]),
            .O_data_out(lane_bytes[8*lane+:8]),.o_diag_offset(),.o_diag_found());
    end endgenerate
    csi_rx_word_align_observed #(.MIPI_LAN(4)) u_align(
        .I_word_clock(word_clk),.I_reset_n(cohort_n),.I_enable(1'b1),
        .I_packet_done(phy_done),.I_wait_for_sync(wait_sync),.O_packet_done_out(),
        .I_word_in(lane_bytes),.I_valid_in(lane_valid),
        .O_word_out(aligned),.O_valid_out(aligned_valid),.o_diag_taps());
    csi_rx_word_gear_box #(.MIPI_LAN(4)) u_gearbox(
        .I_word_clock(word_clk),.I_reset_n(cohort_n),.I_enable(1'b1),
        .I_lane_data(aligned),.I_lane_data_valid(aligned_valid),
        .O_word_out(geared),.O_valid_out(geared_valid));
    real_hdr_csi_dual_word_rx #(.EXPECTED_RAW_BYTES(RAW_BYTES)) u_parser(
        .i_clk(word_clk),.i_reset_n(cohort_n),.i_identity_rst_n(cohort_n),
        .i_cycle_enable(1'b1),.i_word(geared),.i_word_valid(geared_valid),
        .i_long_ready(1'b1),.i_short_ready(1'b1),
        .o_long_data(long_data),.o_short_data(short_data),
        .o_long_valid(long_valid),.o_short_valid(short_valid),
        .o_long_sof(long_sof),.o_short_sof(short_sof),
        .o_long_eol(long_eol),.o_short_eol(short_eol),
        .o_long_abort(long_abort),.o_short_abort(short_abort),
        .o_long_error(long_error),.o_short_error(short_error),
        .o_long_sequence_count(long_sequence),.o_short_sequence_count(short_sequence),
        .o_long_group(),.o_short_group(),.o_long_event_sequence(),.o_short_event_sequence(),
        .o_long_identity_valid(),.o_short_identity_valid(),
        .o_long_cycle_valid(),.o_short_cycle_valid(),
        .o_long_event_frame_number(),.o_short_event_frame_number(),
        .o_long_fs_observe_valid(),.o_short_fs_observe_valid(),
        .o_long_fs_number(),.o_short_fs_number(),
        .o_long_fs_observe_sequence(),.o_short_fs_observe_sequence(),
        .o_long_fs_observe_trusted(),.o_short_fs_observe_trusted(),
        .o_identity_fault(identity_fault),.o_wait_for_sync(wait_sync),
        .o_packet_done(done),.o_packet_continue(continuation),
        .o_header_ecc_error(ecc_error),.o_payload_crc_error(crc_error),.o_length_error(length_error));
    assign uncertain={u_parser.u_short.uncertain_header,u_parser.u_long.uncertain_header};
    assign header_info=0;
    assign candidate=u_parser.packet_word;
    assign candidate_valid=u_parser.packet_valid;
    ph1a_rx_delay_scan #(.MIPI_LAN(4),.TEST_LEN(256),.PASS_THRESH(64),
        .SETTLE_CYCLES(8),.WAIT_CYCLES(4096),.MAX_SCANS(1)) u_scan(
        .I_byte_clk(word_clk),.I_reset_n(scan_reset_n),.I_raw_bytes(raw_word),
        .I_byte_align_done(lane_valid),.O_delay_value(tap),.O_delay_vaild(tap_write),
        .O_scan_done(scan_done),.O_window_len(window_len),
        .O_window_valid(window_valid),.O_scan_failed(scan_failed));

    function automatic [5:0] ecc(input [23:0] h);
        begin
            ecc[0]=^(h&24'hf12cb7);ecc[1]=^(h&24'hf2555b);
            ecc[2]=^(h&24'h749a6d);ecc[3]=^(h&24'hb8e38e);
            ecc[4]=^(h&24'hdf03f0);ecc[5]=^(h&24'heffc00);
        end
    endfunction
    function automatic [31:0] header(input integer vc,dt,number);
        reg [23:0] h;
        begin h={16'(number),2'(vc),6'(dt)};header={2'd0,ecc(h),h};end
    endfunction
    function automatic [15:0] crc_byte(input [15:0] prior,input [7:0] data);
        reg [15:0] c;
        integer bit_index;
        begin
            c=prior^data;
            for(bit_index=0;bit_index<8;bit_index=bit_index+1)
                c=c[0]?(c>>1)^16'h8408:c>>1;
            crc_byte=c;
        end
    endfunction
    task automatic step(input [31:0] value);
        begin @(negedge word_clk);model_word=value;end
    endtask
    task automatic idle(input integer cycles,input [31:0] value);
        integer cycle;
        begin for(cycle=0;cycle<cycles;cycle=cycle+1)step(value);end
    endtask
    task automatic send_raw;
        integer a,b;
        reg [15:0] c;
        reg [31:0] w;
        reg [7:0] value;
        begin
            step(header(0,6'h2c,RAW_BYTES));c=16'hffff;
            for(a=0;a<RAW_BYTES+2;a=a+4)begin
                w=32'hffffffff;
                for(b=0;b<4;b=b+1)begin
                    if(a+b<RAW_BYTES)begin value=8'(a+b+1);c=crc_byte(c,value);end
                    else if(a+b==RAW_BYTES)value=c[7:0];
                    else if(a+b==RAW_BYTES+1)value=c[15:8];
                    else value=8'hff;
                    w[8*b+:8]=value;
                end
                step(w);
            end
        end
    endtask
    task automatic send_frame(input integer number);
        begin
            idle(8,0);step(32'hb8b8b8b8);step(header(0,0,number));
            send_raw();step(header(0,1,number));idle(20,32'hffffffff);
        end
    endtask

    reg stop_stream=0,stream_stopped=0,post_check=0;
    integer frame_number=1;
    initial begin
        wait(scan_reset_n&&cohort_n);
        while(!stop_stream)begin send_frame(frame_number);frame_number=frame_number+1;end
        stream_stopped=1;
    end
    integer groups=0,eols=0,fs_events=0,fe_events=0,post_errors=0;
    integer all_valid_edges=0,seen_retirement=0;
    reg [3:0] prior_lane_valid=0;
    always @(posedge word_clk)begin
        prior_lane_valid<=lane_valid;
        if(cohort_n)begin
            if(&lane_valid)all_valid_edges=all_valid_edges+1;
            if((|prior_lane_valid)&&!(|lane_valid))seen_retirement=seen_retirement+1;
        end
        if(post_check)begin
            if(ecc_error||crc_error||length_error||identity_fault||long_abort||short_abort)
                post_errors=post_errors+1;
            if(long_valid)begin
                if(long_error==0)begin groups=groups+1;if(long_eol)eols=eols+1;end
                else if(long_error==7)fs_events=fs_events+1;
                else if(long_error==6)fe_events=fe_events+1;
                else post_errors=post_errors+1;
            end
        end
    end
    integer checks=0;
    task automatic check(input bit condition,input string description);
        begin checks=checks+1;if(!condition)$fatal(1,"SCAN_CHECK %s",description);end
    endtask
    integer timeout_cycles;
    initial begin
        idle(8,0);scan_reset_n=1;cohort_n=1;
        timeout_cycles=0;
        while(!scan_done&&timeout_cycles<180000)begin @(negedge word_clk);timeout_cycles=timeout_cycles+1;end
        check(scan_done,"actual scan completes");
        check(window_valid&&!scan_failed,"actual all-lane-valid feedback qualifies window");
        check(window_len==16&&tap==16,"BFM codes 8..23 produce length16 center16");
        check(seen_retirement>0&&all_valid_edges>=64,"old packet valid retires and actual aligned data scores");
        $display("SCAN_POSITIVE cycles=%0d window=%0d tap=%0d aligned_edges=%0d retirements=%0d",
            timeout_cycles,window_len,tap,all_valid_edges,seen_retirement);
        stop_stream=1;wait(stream_stopped);
        // The physical wrapper's final-tap barrier clears the decoder for at
        // least four WORD edges. This bench applies that same minimum here.
        cohort_n=0;idle(4,0);cohort_n=1;idle(8,0);
        post_check=1;send_frame(2);idle(40,0);post_check=0;
        check(groups==128&&eols==1,"postscan full 512-pixel RAW12 packet");
        check(fs_events==1&&fe_events==1,"postscan FS and FE are preserved");
        check(post_errors==0&&!identity_fault,"postscan CRC/length/header checks remain clean");
        $display("SCAN_POST groups=%0d eols=%0d fs=%0d fe=%0d errors=%0d",groups,eols,fs_events,fe_events,post_errors);

        // Raw transitions launch a real scan, but this alternating-bit stream
        // has no B8 SoT substring at any bit offset. No lane may qualify.
        scan_reset_n=0;cohort_n=0;no_sync=1;idle(8,32'h55555555);
        scan_reset_n=1;cohort_n=1;timeout_cycles=0;
        while(!scan_done&&timeout_cycles<180000)begin
            step(timeout_cycles[0]?32'h55555555:32'haaaaaaaa);
            timeout_cycles=timeout_cycles+1;
        end
        check(scan_done,"activity without sync still terminates bounded scan");
        check(!window_valid&&scan_failed&&window_len==0,"no-sync activity cannot grant a window");
        check(lane_valid==0,"no-sync activity does not acquire lanes");
        $display("SCAN_NEGATIVE cycles=%0d window=%0d valid=%0b failed=%0b",timeout_cycles,window_len,window_valid,scan_failed);
        $display("RESULT: PASS HDR_DELAY_SCAN_FEEDBACK checks=%0d",checks);$finish;
    end
endmodule
