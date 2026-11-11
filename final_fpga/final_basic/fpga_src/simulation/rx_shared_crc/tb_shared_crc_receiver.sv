`timescale 1ns/1ps
// The PHY electrical boundary comes from the existing runtime fixture.
// WORD aligner, gearbox, both parser policies, crop and official FIFOs are real.
module tb_shared_crc_receiver;
    reg wc=0,pc=0,run_pixel=1,rst_n=0,hdr=0;
    always #5 wc=~wc;always #7 if(run_pixel)pc=~pc;
    wire [146:0] h0,h1;wire hv0,hv1;reg ready0=1,ready1=1;
    wire [39:0] raw;wire rv,rs,re,ra,eventv,eventok;
    wire [1:0] eventkind;wire [3:0] error,eventerror;
    wire [31:0] crc_errors,seq;wire fault,ready,delaydone,publish,decoder;
    real_hdr_physical_csi_rx dut(
        .i_ref_clk(wc),.i_mipi_clk_p(wc),.i_mipi_data_p(4'd0),.i_pixel_clk(pc),
        .i_reset_n(rst_n),.i_enable(1'b1),.i_hdr_mode(hdr),.i_hdr_cycle_enable(1'b1),
        .m_hdr0_data(h0),.m_hdr1_data(h1),.m_hdr0_valid(hv0),.m_hdr1_valid(hv1),.m_hdr0_ready(ready0),.m_hdr1_ready(ready1),
        .i_debug_button(1'b1),.o_raw_data(raw),.o_raw_valid(rv),.i_raw_ready(1'b1),.o_raw_sof(rs),.o_raw_eol(re),
        .m_frame_event_valid(eventv),.m_frame_event_ready(1'b1),.m_frame_event_kind(eventkind),.m_frame_event_ok(eventok),
        .m_frame_event_error(eventerror),.m_frame_event_sequence(),.m_frame_event_identity_valid(),
        .o_raw_sequence(seq),.o_raw_identity_valid(),.o_source_identity_fault(fault),.o_rx_diag_word(),
        .o_rx_trace_sample(),.o_rx_trace_trigger(),.o_rx_trace_cohort_n(),.o_rx_trace_enable(),
        .o_frame_abort(ra),.o_error_code(error),.o_header_ecc_error_count(),.o_payload_crc_error_count(crc_errors),
        .o_overflow_error_count(),.o_length_error_count(),.o_hs_word_clk(),.o_auto_delay_done(delaydone),
        .o_delay_debug(),.o_delay_window(),.o_phy_ready(ready),.o_diag_lane_bytes(),.o_diag_lane_valid(),
        .o_diag_aligned_word(),.o_diag_aligned_valid(),.o_diag_geared_word(),.o_diag_geared_valid(),
        .o_diag_wait_sync(),.o_diag_packet_done(),.o_diag_publish_enable(publish),.o_diag_word_reset_n(decoder));
    // Compressed receiver geometry only; 1944-wide packet phases are in the A/B miter.
    defparam dut.u_hdr_stream.SENSOR_WIDTH=16;
    defparam dut.u_hdr_stream.SENSOR_HEIGHT=4;
    defparam dut.u_hdr_stream.CROP_X=0;
    defparam dut.u_hdr_stream.CROP_Y=0;
    defparam dut.u_hdr_stream.WIDTH=16;
    defparam dut.u_hdr_stream.HEIGHT=4;
    integer fs0=0,fs1=0,fe0=0,fe1=0,bad0=0,bad1=0,pixels0=0,pixels1=0,sdrfe=0,sdrpixels=0;
    integer checks=0,cycles=0;reg stalls=0;
    always @(negedge pc)begin
        cycles++;ready0=!stalls || cycles%7!=0;ready1=!stalls || cycles%11!=0;
    end
    always @(posedge pc)begin
        if(!rst_n)begin fs0=0;fs1=0;fe0=0;fe1=0;bad0=0;bad1=0;pixels0=0;pixels1=0;sdrfe=0;sdrpixels=0;end
        else begin
            if(hv0 && ready0)begin
                if(h0[42])bad0++;else if(h0[46:43]==7)fs0++;else if(h0[46:43]==6)fe0++;else if(h0[46:43]==0)pixels0++;
            end
            if(hv1 && ready1)begin
                if(h1[42])bad1++;else if(h1[46:43]==7)fs1++;else if(h1[46:43]==6)fe1++;else if(h1[46:43]==0)pixels1++;
            end
            if(eventv && eventkind==1 && eventok)sdrfe++;
            if(rv && !ra)sdrpixels++;
        end
    end
    task check(input bit condition,input string why);
        begin checks++;if(!condition)$fatal(1,"shared CRC receiver %s hfs=%0d/%0d hfe=%0d/%0d bad=%0d/%0d px=%0d/%0d sdr=%0d/%0d",why,fs0,fs1,fe0,fe1,bad0,bad1,pixels0,pixels1,sdrfe,sdrpixels);end
    endtask
    task ticks(input integer count);repeat(count)@(negedge wc);endtask
    task cold(input bit mode,input bit stopped_pixel);
        begin
            rst_n=0;hdr=mode;dut.u_phy.test_valid=0;dut.u_phy.test_bytes=0;
            dut.u_phy.test_phy_health=0;dut.u_phy.test_cal_done=0;ticks(8);
            if(stopped_pixel)begin run_pixel=0;ticks(8);end
            rst_n=1;dut.u_phy.test_phy_health=1;ticks(12);dut.u_phy.test_cal_done=1;ticks(20);
            if(stopped_pixel)begin check(!hv0&&!hv1&&!rv,"stopped peer cannot publish old data");run_pixel=1;end
            ticks(100);check(ready&&publish&&decoder,"cohort/calibration release");
        end
    endtask
    function [5:0] ecc(input [23:0] h);
        begin ecc[0]=^(h&24'hf12cb7);ecc[1]=^(h&24'hf2555b);ecc[2]=^(h&24'h749a6d);
            ecc[3]=^(h&24'hb8e38e);ecc[4]=^(h&24'hdf03f0);ecc[5]=^(h&24'heffc00);end
    endfunction
    function [31:0] header(input integer vc,input integer dt,input integer count);
        reg [23:0] h;begin h={16'(count),2'(vc),6'(dt)};header={2'd0,ecc(h),h};end
    endfunction
    function [15:0] cb(input [15:0] prior,input [7:0] b);
        reg [15:0] c;integer k;begin c=prior^b;for(k=0;k<8;k++)c=c[0]?(c>>1)^16'h8408:c>>1;cb=c;end
    endfunction
    task word(input [31:0] w);
        begin dut.u_phy.test_bytes=w;dut.u_phy.test_valid=4'hf;ticks(1);end
    endtask
    task begin_packet;begin word(32'hb8b8b8b8);end endtask
    task end_packet;begin dut.u_phy.test_valid=0;dut.u_phy.test_bytes=32'hffffffff;ticks(14);end endtask
    task sp(input integer vc,input integer dt,input integer number);
        begin begin_packet;word(header(vc,dt,number));end_packet;end
    endtask
    task raw_packet(input integer vc,input integer dt,input integer count,input bit bad);
        integer j,k;reg [31:0] w;reg [15:0] c;reg [7:0] b;
        begin
            begin_packet;word(header(vc,dt,count));c=16'hffff;
            for(j=0;j<count+2;j+=4)begin
                w=32'hffffffff;
                for(k=0;k<4;k++)begin
                    if(j+k<count)begin b=8'(j+k);c=cb(c,b);w[k*8+:8]=b;end
                    else if(j+k==count)w[k*8+:8]=c[7:0]^(bad?1:0);
                    else if(j+k==count+1)w[k*8+:8]=c[15:8];
                end
                word(w);
            end
            end_packet;
        end
    endtask
    task hdr_frame(input integer id,input bit corrupt);
        integer y;begin
            sp(0,0,id);sp(1,0,id+31);
            for(y=0;y<4;y++)begin raw_packet(0,6'h2c,24,corrupt&&y==3);raw_packet(1,6'h2c,24,0);end
            sp(0,1,id);sp(1,1,id+31);ticks(100);
        end
    endtask
    initial begin
        cold(0,0);sp(0,0,1);raw_packet(0,6'h2b,20,0);sp(0,1,1);ticks(80);
        check(sdrfe==1&&sdrpixels==4&&!fault,"SDR unchanged after safe initial release");
        cold(1,1);stalls=1;begin_packet;word(32'hc0000000);end_packet;
        check(!fault,"HDR startup bad header does not poison first FS");
        hdr_frame(1,0);check(fs0==1&&fs1==1&&fe0==1&&fe1==1&&pixels0==16&&pixels1==16&&!fault,"HDR real two FIFO good frame");
        hdr_frame(2,1);check(fe0==1&&fe1==2&&bad0==1&&crc_errors==1&&!fault,"CRC loss negative with independent peer success");
        hdr_frame(3,0);check(fe0==2&&fe1==3&&!fault,"next good HDR pair recovers from payload error");
        begin_packet;word(32'hc0000000);end_packet;ticks(40);
        check(fault,"post-first-FS HDR bad header stays untrusted");
        cold(0,1);stalls=0;sp(0,0,1);raw_packet(0,6'h2b,20,0);sp(0,1,1);ticks(80);
        check(sdrfe==1&&sdrpixels==4&&!fault,"safe mode/reset switch restores SDR without stale HDR data");
        $display("RESULT: PASS SHARED_RX_RECEIVER checks=%0d SDR_HDR_official_FIFO_mode_reset_stall",checks);$finish;
    end
    initial begin #1000000;$fatal(1,"shared CRC physical receiver watchdog");end
endmodule
