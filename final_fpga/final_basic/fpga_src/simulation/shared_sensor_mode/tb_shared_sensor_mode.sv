`timescale 1ns / 1ps

module tb_shared_sensor_mode;
    reg cfg_clk=0, pixel_clk=0, ref_clk=0, sdr_clk=0, hdr_clk=0;
    reg [1:0] word_clk=0, word_run=2'b11;
    always #20 cfg_clk=~cfg_clk;
    always #4 pixel_clk=~pixel_clk;
    always #5 ref_clk=~ref_clk;
    always #21 sdr_clk=~sdr_clk;
    always #13 hdr_clk=~hdr_clk;
    always #6 if(word_run[0])word_clk[0]=~word_clk[0];
    always #7 if(word_run[1])word_clk[1]=~word_clk[1];

    reg reset_n=0;
    reg [1:0] hdr_request=0, slow_request=0, pair_event=0, pair_ok=0;
    reg [1:0] drain_released=2'b11;
    wire [1:0] hdr_mode, slow_mode, running, stable, done, error, phy_ready;
    wire [1:0] xclr, scl, mclk;
    tri1 [1:0] sda;
    wire [31:0] writes[0:1], clears[0:1];
    wire [23:0] last_write[0:1];
    wire [15:0] hmax[0:1];
    wire [19:0] vmax[0:1], shr0[0:1];
    wire [7:0] gain[0:1], wdmode[0:1];

    for(genvar eye=0;eye<2;eye++)begin:g_eye
        // The drain predicate depends on actual running, as it does in TOP.
        sdr_camera_raw_frontend #(.WIDTH(8),.HEIGHT(2),.FIRST_ROW(0),.FIRST_GROUP(0),
            .SDR_RATE_CONTROL_ENABLE(1),.EVENT_FIFO_DEPTH(512),
            .CONFIG_WAIT_CYCLES(8),.SDR_WAKE_CYCLES(8),.I2C_HALF_PERIOD(2),
            .HDR_I2C_HALF_PERIOD(3),.HDR_WARMUP_PAIRS(2),.HDR_RESET_HOLD_CYCLES(8),
            .HDR_RELEASE_WAIT_CYCLES(8),.HDR_REGULATOR_WAIT_CYCLES(8)) dut(
            .i_pixel_clk(pixel_clk),.i_sensor_clk(sdr_clk),.i_ref_clk(ref_clk),
            .i_reset_n(reset_n),.i_cfg_clk(cfg_clk),.i_hdr_mclk(hdr_clk),.i_clock_locked(1'b1),
            .i_hdr_request(hdr_request[eye]),.i_sdr_30_request(slow_request[eye]),
            .i_mode_quiet(drain_released[eye]&&running[eye]),
            .i_hdr_pair_event(pair_event[eye]),.i_hdr_pair_ok(pair_ok[eye]),
            .o_hdr_mode(hdr_mode[eye]),.o_sdr_30_mode(slow_mode[eye]),
            .o_mode_running(running[eye]),.o_hdr_stable(stable[eye]),
            .m_hdr0_data(),.m_hdr1_data(),.m_hdr0_valid(),.m_hdr1_valid(),
            .m_hdr0_ready(1'b1),.m_hdr1_ready(1'b1),.i_gain_code(8'd16),
            .mipi_clk_hs_rx_p(word_clk[eye]),.mipi_data_hs_p(4'd0),
            .cam_scl(scl[eye]),.cam_sda(sda[eye]),.cam_mclk(mclk[eye]),.cam_xclr(xclr[eye]),
            .i_cropped_raw_ready(1'b1),.o_cropped_raw_data(),.o_cropped_raw_valid(),
            .o_cropped_raw_sof(),.o_cropped_raw_eol(),.o_cropped_raw_abort(),
            .o_cropped_raw_sequence(),.o_cropped_raw_identity_valid(),
            .m_frame_event_ready(1'b1),.m_frame_event_valid(),.m_frame_event_kind(),
            .m_frame_event_ok(),.m_frame_event_error(),.m_frame_event_sequence(),.m_frame_event_identity_valid(),
            .o_config_done(done[eye]),.o_config_error(error[eye]),.o_phy_ready(phy_ready[eye]),
            .o_delay_ready(),.o_delay_debug(),.o_delay_window(),.o_delay_status_valid(),
            .o_ecc_errors(),.o_crc_errors(),.o_overflows(),.o_format_errors(),
            .o_source_identity_fault(),.o_receive_fault(),
            .o_observe_raw_valid(),.o_observe_raw_ready(),.o_observe_raw_sof(),.o_observe_raw_eol(),.o_observe_raw_abort());
        sensor_mode_i2c_slave slave(.xclr(xclr[eye]),.scl(scl[eye]),.sda(sda[eye]),
            .writes(writes[eye]),.clears(clears[eye]),.last_write(last_write[eye]),
            .hmax(hmax[eye]),.vmax(vmax[eye]),.shr0(shr0[eye]),.gain(gain[eye]),.wdmode(wdmode[eye]));
    end

    integer checks=0, phase=0;
    reg eye1_steady=0;
    always @(negedge xclr[1])
        if(eye1_steady)$fatal(1,"Unrelated eye reset during phase %0d",phase);

    task automatic check(input logic condition,input string reason);
        checks++;
        if(condition!==1'b1)$fatal(1,"phase=%0d %s",phase,reason);
    endtask

    task automatic check_profile(input bit expected_hdr,input bit expected_slow);
        time edge_time;
        wait(done[0]&&phy_ready[0]);
        check(running[0]&&xclr[0]&&!error[0],"successful configuration and PHY release");
        check(hdr_mode[0]==expected_hdr&&slow_mode[0]==expected_slow,"actual profile after reset");
        check(writes[0]==(expected_hdr?139:203)&&last_write[0]==24'h300200,"recipe length and final XMSTA");
        check(wdmode[0]==(expected_hdr?8'd1:8'd0),"mode word belongs to the active recipe");
        check(hmax[0]==(expected_hdr?16'h021a:expected_slow?16'h042a:16'h0215),"HMAX decoded from SDA");
        check(vmax[0]==(expected_hdr?20'h008fc:20'h008ca),"VMAX decoded from SDA");
        check(shr0[0]==(expected_hdr?20'h00578:expected_slow?20'h00469:20'h00008),"SHR0 decoded from SDA");
        check(gain[0]==(expected_hdr?8'd0:8'd16),"SDR gain restored and HDR gain remains fixed");
        check(done[1]&&running[1]&&phy_ready[1]&&!error[1]&&!hdr_mode[1]&&!slow_mode[1]&&writes[1]==203,
            "other eye remains on its completed independent SDR60 recipe");
        @(posedge mclk[0]);edge_time=$time;
        @(posedge mclk[0]);
        check($time-edge_time==(expected_hdr?26:42),"physical MCLK follows selected mode");
    endtask

    task automatic check_mode_hold;
        wait(!xclr[0]);
        repeat(5)@(negedge pixel_clk);
        check(!running[0]&&!done[0]&&!stable[0],"transition withdraws old qualification during hold");
    endtask

    task automatic publish_pair(input bit good);
        @(negedge pixel_clk);pair_ok[0]=good;pair_event[0]=1;
        @(negedge pixel_clk);pair_event[0]=0;
        repeat(8)@(negedge cfg_clk);
    endtask

    integer prior_clears;
    initial begin
        repeat(12)@(negedge cfg_clk);
        check(xclr==0&&scl==2'b11&&sda==2'b11,"both buses idle under reset");
        reset_n=1;
        wait(&done&&(&phy_ready));
        check_profile(0,0);
        eye1_steady=1;

        phase=1;
        drain_released[0]=0;
        repeat(5)@(negedge cfg_clk);
        prior_clears=clears[0];
        slow_request[0]=1;
        repeat(32)@(negedge cfg_clk);
        check(clears[0]==prior_clears&&xclr[0]&&running[0]&&done[0]&&!slow_mode[0]&&writes[0]==203,
            "pending SDR30 request cannot reset the current owner before quiet");
        drain_released[0]=1;
        check_mode_hold();
        check_profile(0,1);

        phase=2;
        hdr_request[0]=1;
        check_mode_hold();
        check_profile(1,0);
        check(!stable[0],"I2C completion cannot satisfy HDR warmup");
        publish_pair(1);
        check(!stable[0],"one qualified pair is insufficient");
        publish_pair(0);
        publish_pair(1);
        check(!stable[0],"a bad pair restarts consecutive qualification");
        publish_pair(1);
        check(stable[0],"two consecutive qualified pairs cross to stable");

        phase=3;
        prior_clears=clears[0];
        slow_request[0]=0;
        repeat(32)@(negedge cfg_clk);
        check(clears[0]==prior_clears&&hdr_mode[0]&&stable[0]&&xclr[0]&&writes[0]==139,
            "SDR request changes cannot restart active HDR");
        slow_request[0]=1;
        repeat(8)@(negedge cfg_clk);

        phase=4;
        word_run[0]=0;
        wait(error[0]&&!done[0]&&!stable[0]);
        check(!xclr[0]&&scl[0]&&sda[0],"HDR receive fault revokes configuration and leaves I2C idle");
        check(done[1]&&phy_ready[1]&&!error[1],"fault remains local to one eye");
        word_run[0]=1;
        hdr_request[0]=0;
        check_profile(0,1);

        phase=5;
        slow_request[0]=0;
        check_mode_hold();
        check_profile(0,0);
        $display("RESULT: PASS SHARED_SENSOR_MODE checks=%0d",checks);
        $finish;
    end

    initial begin
        #20000000;
        $fatal(1,"mode-switch watchdog phase=%0d done=%b error=%b running=%b xclr=%b",
            phase,done,error,running,xclr);
    end
endmodule

// Decode the electrical bus without using the writer's state or write index.
module sensor_mode_i2c_slave(
    input wire xclr,scl,
    inout wire sda,
    output integer writes=0,clears=0,
    output reg [23:0] last_write=0,
    output reg [15:0] hmax=0,
    output reg [19:0] vmax=0,shr0=0,
    output reg [7:0] gain=0,wdmode=0
);
    reg active=0, ack=0;
    reg [7:0] shift=0;
    reg [31:0] word=0;
    integer bit_index=0,byte_index=0;
    assign sda=ack?1'b0:1'bz;

    always @(negedge xclr)begin
        active=0;ack=0;writes=0;clears++;
        last_write=0;hmax=0;vmax=0;shr0=0;gain=0;wdmode=0;
    end
    always @(negedge sda)if(scl===1'b1&&xclr&&!active)begin
        active=1;bit_index=0;byte_index=0;word=0;
    end
    always @(negedge scl)ack=active&&bit_index==8;
    always @(posedge scl)if(active)begin
        if(bit_index<8)begin
            shift={shift[6:0],sda};bit_index++;
            if(bit_index==8)begin word={word[23:0],shift};byte_index++;end
        end else bit_index=0;
    end
    always @(posedge sda)if(scl===1'b1&&active)begin
        active=0;ack=0;
        if(byte_index!=4||word[31:24]!==8'h34)$fatal(1,"Invalid sensor I2C transaction %h",word);
        writes++;last_write=word[23:0];
        case(word[23:8])
            16'h3024:vmax[7:0]=word[7:0];
            16'h3025:vmax[15:8]=word[7:0];
            16'h3026:vmax[19:16]=word[3:0];
            16'h3028:hmax[7:0]=word[7:0];
            16'h3029:hmax[15:8]=word[7:0];
            16'h302c:wdmode=word[7:0];
            16'h3050:shr0[7:0]=word[7:0];
            16'h3051:shr0[15:8]=word[7:0];
            16'h3052:shr0[19:16]=word[3:0];
            16'h3090:gain=word[7:0];
            default:begin end
        endcase
    end
endmodule
