`timescale 1ns/1ps
module tb_camera1;
    localparam W=16,H=3,FR=1,FG=1,G=W/4,EXPECTED=G*H;
    reg pixel_clk=0,sensor_clk=0,ref_clk=0,word_clk=0,word_run=1;
    always #5 pixel_clk=~pixel_clk;
    always #8.5 sensor_clk=~sensor_clk;
    always #6.5 ref_clk=~ref_clk;
    always #5.555556 if(word_run)word_clk=~word_clk;
    reg reset_n=0;
    wire scl,mclk,xclr;
    tri1 sda;
    reg ack_enable=1,slave_ack=0,slave_active=0;
    integer slave_bit=0,slave_byte=0,transactions=0;
    reg [7:0] slave_shift=0;
    reg [31:0] slave_word=0,last_transaction=0;
    assign sda=slave_ack&&ack_enable?1'b0:1'bz;
    always @(negedge sda) if(scl===1'b1&&!slave_active)begin
        slave_active=1;slave_bit=0;slave_byte=0;slave_word=0;
    end
    always @(posedge sda) if(scl===1'b1&&slave_active)begin
        if(slave_byte==4)begin transactions++;last_transaction=slave_word;end
        slave_active=0;slave_ack=0;
    end
    always @(negedge scl) slave_ack=slave_active&&(slave_bit==8);
    always @(posedge scl) if(slave_active)begin
        if(slave_bit<8)begin
            slave_shift={slave_shift[6:0],sda};slave_bit++;
            if(slave_bit==8)begin slave_word={slave_word[23:0],slave_shift};slave_byte++;end
        end else slave_bit=0;
    end
    wire [39:0] data;
    wire valid,sof,eol,abort_crop,identity;
    wire [31:0] sequence_id,event_sequence;
    reg ready=1,event_ready=1,random_stalls=0,tail_hold=0,block_events=0,force_stall=0;
    wire event_valid,event_ok,event_identity;
    wire [1:0] event_kind;
    wire [3:0] event_error;
    wire config_done,config_error,phy_ready,delay_ready,delay_valid,identity_fault,receive_fault;
    wire [7:0] delay_debug;
    wire [5:0] delay_window;
    wire [31:0] ecc_errors,crc_errors,overflows,format_errors;
    wire obs_valid,obs_ready,obs_sof,obs_eol,obs_abort;
    reg hdr_request=0, mode_quiet=1;
    wire hdr_mode,mode_running,hdr_stable,pair_event,pair_ok;
    wire [146:0] h0,h1;
    wire [1:0] hvalid,hready,source_valid,source_ok;
    wire [31:0] good_pairs,bad_pairs;
    integer long_finals=0,short_finals=0;
    always @(posedge pixel_clk)begin
        if(source_valid[0]&&source_ok[0])long_finals++;
        if(source_valid[1]&&source_ok[1])short_finals++;
    end
    wire [1:0] hr_valid,hr_sof,hr_eol;
    wire [196:0] meta_long,meta_short;
    wire [31:0] hs0,hs1,he0,he1,hseq0,hseq1;
    integer raw_count0=0,raw_count1=0;
    always @(posedge pixel_clk)begin
        if(hr_valid[0])raw_count0++;
        if(hr_valid[1])raw_count1++;
        if(source_valid[0]&&source_ok[0])check({hs0,he0}=={32'd7,32'd3},"long terminal owns true session/epoch");
        if(source_valid[1]&&source_ok[1])check({hs1,he1}=={32'd7,32'd3},"short terminal owns true session/epoch");
    end
    real_hdr_pair_cycle_gate gate(
        .i_clk(pixel_clk),.i_reset_n(reset_n&&hdr_mode&&mode_running),
        .i_fault(receive_fault||identity_fault),.i_stable(hdr_stable),.i_admit_enable(1'b1),
        .i_session(32'd7),.i_epoch(32'd3),.i_time(64'd1000),.i_time_valid(1'b1),
        .i_capture0_idle(1'b1),.i_capture1_idle(1'b1),
        .s0_data(h0),.s1_data(h1),.s0_valid(hvalid[0]),.s1_valid(hvalid[1]),
        .s0_ready(hready[0]),.s1_ready(hready[1]),
        .o_source0_valid(source_valid[0]),.o_source1_valid(source_valid[1]),
        .i_source0_ready(1'b1),.i_source1_ready(1'b1),.i_timeout_phase(32'd0),
        .o_source_ok(source_ok[0]),.o_source1_ok(source_ok[1]),
        .m0_data(),.m1_data(),.m0_valid(hr_valid[0]),.m1_valid(hr_valid[1]),
        .m0_sof(hr_sof[0]),.m1_sof(hr_sof[1]),.m0_eol(hr_eol[0]),.m1_eol(hr_eol[1]),
        .m0_abort(),.m1_abort(),.o_sequence0(),.o_sequence1(),.o_session(),.o_epoch(),
        .o_metadata0(meta_long),.o_metadata1(meta_short),.o_source_session(hs0),.o_source1_session(hs1),
        .o_source_epoch(he0),.o_source1_epoch(he1),.o_source0_sequence(hseq0),.o_source1_sequence(hseq1),
        .o_source_error(),.o_source1_error(),.o_diag_pair(),.o_diag_counts(),.o_not_admitted_pairs(),.o_quiet(),
        .o_pair_event(pair_event),.o_pair_ok(pair_ok),.o_good_pairs(good_pairs),.o_bad_pairs(bad_pairs));
    sdr_camera_raw_frontend #(.WIDTH(W),.HEIGHT(H),.FIRST_ROW(FR),.FIRST_GROUP(FG),
        .HDR_WARMUP_PAIRS(1),.HDR_I2C_HALF_PERIOD(4),.HDR_RESET_HOLD_CYCLES(8),
        .HDR_RELEASE_WAIT_CYCLES(8),.HDR_REGULATOR_WAIT_CYCLES(8),.SDR_WAKE_CYCLES(8),.CONFIG_WAIT_CYCLES(8),.I2C_HALF_PERIOD(4),.SILENCE_CYCLES(400),.EVENT_FIFO_DEPTH(512)) dut(
        .i_pixel_clk(pixel_clk),.i_sensor_clk(sensor_clk),.i_ref_clk(ref_clk),.i_reset_n(reset_n),
        .i_cfg_clk(ref_clk),.i_hdr_mclk(pixel_clk),.i_clock_locked(1'b1),.i_hdr_request(hdr_request),
        .i_sdr_30_request(1'b0),.o_sdr_30_mode(),
        .i_mode_quiet(mode_quiet),.i_hdr_pair_event(pair_event),.i_hdr_pair_ok(pair_ok),
        .o_hdr_mode(hdr_mode),.o_mode_running(mode_running),.o_hdr_stable(hdr_stable),
        .m_hdr0_data(h0),.m_hdr1_data(h1),.m_hdr0_valid(hvalid[0]),.m_hdr1_valid(hvalid[1]),
        .m_hdr0_ready(hready[0]),.m_hdr1_ready(hready[1]),.i_gain_code(8'd16),.mipi_clk_hs_rx_p(word_clk),.mipi_data_hs_p(4'd0),
        .cam_scl(scl),.cam_sda(sda),.cam_mclk(mclk),.cam_xclr(xclr),
        .o_cropped_raw_data(data),.o_cropped_raw_valid(valid),.i_cropped_raw_ready(ready),
        .o_cropped_raw_sof(sof),.o_cropped_raw_eol(eol),.o_cropped_raw_abort(abort_crop),
        .o_cropped_raw_sequence(sequence_id),.o_cropped_raw_identity_valid(identity),
        .m_frame_event_valid(event_valid),.m_frame_event_ready(event_ready),
        .m_frame_event_kind(event_kind),.m_frame_event_ok(event_ok),.m_frame_event_error(event_error),
        .m_frame_event_sequence(event_sequence),.m_frame_event_identity_valid(event_identity),
        .o_config_done(config_done),.o_config_error(config_error),.o_phy_ready(phy_ready),
        .o_delay_ready(delay_ready),.o_delay_debug(delay_debug),.o_delay_window(delay_window),
        .o_delay_status_valid(delay_valid),.o_ecc_errors(ecc_errors),.o_crc_errors(crc_errors),
        .o_overflows(overflows),.o_format_errors(format_errors),
        .o_source_identity_fault(identity_fault),.o_receive_fault(receive_fault),
        .o_observe_raw_valid(obs_valid),.o_observe_raw_ready(obs_ready),
        .o_observe_raw_sof(obs_sof),.o_observe_raw_eol(obs_eol),.o_observe_raw_abort(obs_abort));
    // Speed up geometry only. The real dual-VC decoder, RAW12 packing, crop,
    // two independent vendor FIFOs and pair gate run throughout the mode cycle.
    defparam dut.u_receiver.u_hdr_stream.SENSOR_WIDTH=W;
    defparam dut.u_receiver.u_hdr_stream.SENSOR_HEIGHT=H;
    defparam dut.u_receiver.u_hdr_stream.CROP_X=0;
    defparam dut.u_receiver.u_hdr_stream.CROP_Y=0;
    defparam dut.u_receiver.u_hdr_stream.WIDTH=W;
    defparam dut.u_receiver.u_hdr_stream.HEIGHT=H;
    reg [31:0] fixture_word=0;
    reg fixture_valid=0;
    initial begin
        force dut.u_receiver.geared_word=fixture_word;
        force dut.u_receiver.geared_word_valid=fixture_valid;
    end
    integer checks=0,cycles=0,groups=0,fs_count=0,fe_count=0,abort_count=0,crop_aborts=0,faults=0;
    integer frame_tag=1,expected_sequence=1,phase=0;
    reg check_pixels=0;
    reg held_raw=0,held_event=0;
    reg [74:0] held_raw_bundle;
    reg [40:0] held_event_bundle;
    reg [31:0] rng=32'h190317a5;
    task check(input bit condition,input string message);
        begin checks++;if(condition!==1'b1)begin
            $display("FAIL phase=%0d cycles=%0d groups=%0d: %s",phase,cycles,groups,message);$fatal(1);
        end end
    endtask
    function [9:0] sample(input integer tag,input integer row,input integer group_index,input integer lane);
        sample=(tag*73+row*31+group_index*7+lane*3)&1023;
    endfunction
    always @(negedge pixel_clk)begin
        rng={rng[30:0],rng[31]^rng[21]^rng[1]^rng[0]};
        ready=(!random_stalls||rng[1:0]!=0)&&!(tail_hold&&groups==EXPECTED-1)&&!force_stall;
        event_ready=!block_events&&(!random_stalls||rng[3:2]!=0);
    end
    always @(posedge pixel_clk)begin
        cycles++;
        if(!reset_n)begin held_raw=0;held_event=0;end
        else begin
            if(held_raw)check(valid&&{identity,sequence_id,sof,eol,data}===held_raw_bundle,"stalled RAW and identity stable");
            if(held_event)check(event_valid&&{event_identity,event_sequence,event_ok,event_kind,event_error}===held_event_bundle,"stalled CSI event stable");
            held_raw=valid&&!ready;
            held_event=event_valid&&!event_ready;
            held_raw_bundle={identity,sequence_id,sof,eol,data};
            held_event_bundle={event_identity,event_sequence,event_ok,event_kind,event_error};
            if(valid&&ready)begin
                if(check_pixels)begin
                    check(groups<EXPECTED,"no extra crop groups");
                    check(identity&&sequence_id==expected_sequence,"crop retains physical source identity");
                    check(sof==(groups==0)&&eol==(groups%G==G-1),"crop SOF/EOL position");
                    for(integer lane=0;lane<4;lane++)
                        check(data[lane*10+:10]===sample(frame_tag,groups/G+FR,groups%G+FG,lane),"RAW10 packing/crop exact");
                end
                groups++;
            end
            if(event_valid&&event_ready)begin
                case(event_kind)
                    0:begin fs_count++;check(event_ok&&event_error==0,"FS success");end
                    1:begin fe_count++;check(event_ok&&event_error==0,"actual FE success");end
                    2:begin abort_count++;check(!event_ok&&event_error!=0,"ABORT negative");end
                    3:check(!event_ok&&event_error==3,"DROP diagnostic negative");
                endcase
            end
            if(abort_crop)crop_aborts++;
            if(receive_fault)faults++;
        end
    end
    function [5:0] ecc(input [23:0] d);
        begin
            ecc[0]=d[0]^d[1]^d[2]^d[4]^d[5]^d[7]^d[10]^d[11]^d[13]^d[16]^d[20]^d[21]^d[22]^d[23];
            ecc[1]=d[0]^d[1]^d[3]^d[4]^d[6]^d[8]^d[10]^d[12]^d[14]^d[17]^d[20]^d[21]^d[23];
            ecc[2]=d[0]^d[2]^d[3]^d[5]^d[6]^d[9]^d[11]^d[12]^d[15]^d[18]^d[20]^d[21]^d[22];
            ecc[3]=d[1]^d[2]^d[3]^d[7]^d[8]^d[9]^d[13]^d[14]^d[15]^d[19]^d[20]^d[21]^d[23];
            ecc[4]=d[4]^d[5]^d[6]^d[7]^d[8]^d[9]^d[16]^d[17]^d[18]^d[19]^d[20]^d[22]^d[23];
            ecc[5]=d[10]^d[11]^d[12]^d[13]^d[14]^d[15]^d[16]^d[17]^d[18]^d[19]^d[21]^d[22]^d[23];
        end
    endfunction
    function [15:0] crc_byte(input [15:0] c,input [7:0] b);
        reg [15:0] v;begin v=c^b;for(integer k=0;k<8;k++)v=v[0]?((v>>1)^16'h8408):(v>>1);crc_byte=v;end
    endfunction
    task word(input [31:0] value,input bit valid_word);
        begin @(negedge word_clk);fixture_word=value;fixture_valid=valid_word;end
    endtask
    task gap;
        begin word(0,0);repeat(6)@(negedge word_clk);end
    endtask
    task short_packet(input bit finish);
        reg [23:0] header;
        begin header={16'h79a3,7'd0,finish};word({2'd0,ecc(header),header},1);gap();end
    endtask
    reg [7:0] bytes[0:10004];
    task line(input integer row,input integer group_total,input bit bad_crc);
        reg [9:0] p[0:3];reg [15:0] crc;reg [23:0] header;
        integer count;
        begin
            count=group_total*5;
            for(integer n=0;n<count+4;n++)bytes[n]=0;
            for(integer g=0;g<group_total;g++)begin
                for(integer lane=0;lane<4;lane++)begin
                    p[lane]=sample(frame_tag,row,g,lane);bytes[g*5+lane]=p[lane][9:2];
                end
                bytes[g*5+4]={p[3][1:0],p[2][1:0],p[1][1:0],p[0][1:0]};
            end
            crc=16'hffff;for(integer n=0;n<count;n++)crc=crc_byte(crc,bytes[n]);
            bytes[count]=crc[7:0]^{7'd0,bad_crc};bytes[count+1]=crc[15:8];
            header={16'(count),8'h2b};word({2'd0,ecc(header),header},1);
            for(integer n=0;n<count+2;n+=4)word({bytes[n+3],bytes[n+2],bytes[n+1],bytes[n]},1);
            gap();
        end
    endtask
    task hdr_header(input bit eye_vc,input [5:0] dt,input [15:0] number);
        reg [23:0] header;
        begin
            header={number,1'b0,eye_vc,dt};
            word({2'd0,ecc(header),header},1);
        end
    endtask
    task hdr_line(input bit vc,input bit bad_crc);
        reg [15:0] crc;
        integer count;
        begin
            count=W*3/2;crc=16'hffff;
            for(integer i=0;i<count;i++)begin
                bytes[i]=(vc?8'h51:8'h18)+i;
                crc=crc_byte(crc,bytes[i]);
            end
            bytes[count]=crc[7:0]^bad_crc;bytes[count+1]=crc[15:8];
            bytes[count+2]=0;bytes[count+3]=0;
            hdr_header(vc,6'h2c,count);
            for(integer i=0;i<count+2;i+=4)word({bytes[i+3],bytes[i+2],bytes[i+1],bytes[i]},1);
            gap();
        end
    endtask
    task hdr_pair(input [15:0] number,input bit bad_short);
        begin
            hdr_header(0,0,number);gap();hdr_header(1,0,number);gap();
            for(integer row=0;row<H;row++)begin
                hdr_line(0,0);hdr_line(1,bad_short&&row==H-1);
            end
            hdr_header(0,1,number);gap();hdr_header(1,1,number);gap();
            repeat(70)@(negedge pixel_clk);
        end
    endtask
    task frame(input bit outside_crc);
        begin
            short_packet(0);
            for(integer row=0;row<FR+H+1;row++)line(row,G+2,outside_crc&&row==FR+H);
            short_packet(1);gap();
        end
    endtask
    task settle;
        begin repeat(250)@(negedge pixel_clk);end
    endtask
    task boot;
        begin
            wait(config_done);wait(phy_ready&&delay_valid&&dut.u_receiver.decoder_reset_count==5);
            repeat(15)@(negedge pixel_clk);
            check(!config_error&&!identity_fault,"boot configuration and source identity valid");
            check(delay_debug==8'h42&&delay_window==12,"stable calibration status captured");
        end
    endtask
    task reset_source;
        begin
            @(negedge pixel_clk);reset_n=0;fixture_valid=0;word_run=1;tail_hold=0;block_events=0;force_stall=0;
            repeat(12)@(negedge pixel_clk);reset_n=1;boot();
        end
    endtask
    integer before_fe,before_abort,before_fault,before_transactions,before_crc;
    initial begin
        #1;reset_n=0;repeat(12)@(negedge pixel_clk);reset_n=1;
        phase=1;boot();
        check(transactions==203&&last_transaction==32'h34300200,"real sensor boot made 203 acknowledged writes");
        check(dut.u_config.u_table.u_sdr.value!==8'hxx,"real mode table present");
        phase=2;groups=0;frame_tag=1;expected_sequence=1;check_pixels=1;random_stalls=1;
        before_fe=fe_count;frame(0);settle();
        check(groups==EXPECTED&&fe_count==before_fe+1,"good frame crop and true FE under stalls");
        phase=3;groups=0;frame_tag=2;expected_sequence=2;tail_hold=1;
        before_fe=fe_count;
        fork
            frame(0);
            begin wait(groups==EXPECTED-1&&valid&&eol);repeat(30)@(negedge pixel_clk);tail_hold=0;end
        join
        settle();check(groups==EXPECTED&&fe_count==before_fe+1,"held final crop beat resumes exactly once");
        phase=4;groups=0;frame_tag=3;expected_sequence=3;
        before_fe=fe_count;before_abort=abort_count;before_crc=crc_errors;
        frame(1);settle();
        check(groups==EXPECTED&&fe_count==before_fe&&abort_count==before_abort+1&&crc_errors==before_crc+1,
            "outside-crop CRC invalidates whole CSI frame after crop completion");
        phase=5;groups=0;frame_tag=4;expected_sequence=4;before_fe=fe_count;
        frame(0);settle();check(groups==EXPECTED&&fe_count==before_fe+1,"next FS recovers after CRC abort");
        phase=6;check_pixels=0;random_stalls=0;
        short_packet(0);line(0,G+2,0);force_stall=1;line(1,G+2,0);
        wait(valid&&!ready);
        before_fe=fe_count;before_fault=faults;
        @(negedge word_clk);word_run=0;fixture_valid=0;
        repeat(200)@(negedge ref_clk);
        check(!phy_ready&&faults>before_fault&&fe_count==before_fe&&valid&&!ready,
            "stopped WORD clock invalidates source without withdrawing held RAW or creating FE");
        word_run=1;wait(phy_ready);repeat(100)@(negedge pixel_clk);
        check(identity_fault,"restarted PHY does not rewind trusted source identity");
        phase=7;reset_source();groups=0;frame_tag=5;expected_sequence=1;check_pixels=1;
        before_fe=fe_count;frame(0);settle();
        check(groups==EXPECTED&&fe_count==before_fe+1,"cohort reset recovers first trusted sequence");
        phase=8;check_pixels=0;block_events=1;
        before_fe=fe_count;before_abort=abort_count;
        short_packet(0);
        for(integer row=0;row<5;row++)line(row,2000,0);
        short_packet(1);
        block_events=0;repeat(25000)@(negedge pixel_clk);
        check(overflows!=0&&fe_count==before_fe,"finite FIFO overflow cannot produce a successful FE");
        phase=9;before_transactions=transactions;
        ack_enable=0;@(negedge pixel_clk);reset_n=0;repeat(12)@(negedge pixel_clk);reset_n=1;
        wait(config_error);repeat(50)@(negedge pixel_clk);
        check(!config_done&&!phy_ready,"startup NACK keeps receiver disabled");
        phase=10;ack_enable=1;reset_source();groups=0;frame_tag=6;expected_sequence=1;check_pixels=1;
        before_fe=fe_count;frame(0);settle();check(groups==EXPECTED&&fe_count==before_fe+1,"reset recovers NACK failure");
        phase=11;check_pixels=0;mode_quiet=0;hdr_request=1;
        repeat(30)@(negedge ref_clk);check(!hdr_mode&&mode_running,"busy eye retains SDR recipe");
        mode_quiet=1;wait(hdr_mode&&mode_running&&!config_done);
        wait(config_done&&phy_ready&&dut.u_receiver.publish_enable&&dut.u_receiver.decoder_reset_n);
        repeat(30)@(negedge word_clk);
        hdr_pair(16'h331,0);wait(hdr_stable);
        check(long_finals==0&&short_finals==0,"warmup uses true paired FE without video admission");
        hdr_pair(16'h332,0);
        $display("CAM1 HDR group check long=%0d short=%0d good=%0d bad=%0d raw=%0d/%0d",long_finals,short_finals,good_pairs,bad_pairs,raw_count0,raw_count1);
        check(long_finals==1&&short_finals==1&&good_pairs==2&&bad_pairs==0,"one warmup and one admitted group; both terminals commit once");
        check(raw_count0==EXPECTED&&raw_count1==EXPECTED,"only stable group supplies exactly two complete crops");
        check(meta_long[194:193]==1&&meta_short[194:193]==2&&meta_long[191:160]==meta_short[191:160]&&meta_long[191:160]!=0,
            "separate exposure roles share only this group's identity");
        hdr_pair(16'h333,1);
        check(short_finals==1&&bad_pairs!=0,"late bad SHORT CRC cannot qualify the pair");
        phase=12;hdr_request=0;wait(!hdr_mode&&mode_running);boot();
        groups=0;frame_tag=7;expected_sequence=1;check_pixels=1;before_fe=fe_count;
        frame(0);settle();check(groups==EXPECTED&&fe_count==before_fe+1,"HDR to SDR first physical identity");
        $display("RESULT: PASS CAMERA1 checks=%0d FS=%0d FE=%0d ABORT=%0d crop_aborts=%0d faults=%0d",checks,fs_count,fe_count,abort_count,crop_aborts,faults);
        $finish;
    end
    initial begin #100000000;$fatal(1,"CAMERA1 timeout phase=%0d",phase);end
endmodule
