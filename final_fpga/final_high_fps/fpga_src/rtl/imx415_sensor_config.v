`timescale 1ns/1ps

// All modes of one physical camera share this sequencer, timer and I2C writer.
// Ports are in the always-running 25 MHz configuration domain. The caller
// drains the old mode, asserts reset and selects the sensor MCLK before START.
module imx415_sensor_config #(
    parameter integer MODE_4K=0,
    parameter integer RUNTIME_GAIN_ENABLE=1,UHD_ENABLE=0,
    parameter integer I2C_HALF_PERIOD=125,
    parameter integer SDR_RESET_HOLD_CYCLES=250000,
    parameter integer SDR_RELEASE_WAIT_CYCLES=250000,
    parameter integer SDR_WAKE_CYCLES=625000,
    parameter integer HDR_RESET_HOLD_CYCLES=250000,
    parameter integer HDR_RELEASE_WAIT_CYCLES=750000,
    parameter integer HDR_REGULATOR_WAIT_CYCLES=600000,
    parameter integer WARMUP_PAIRS=8
)(
    input wire i_clk,i_rst_n,i_start,
    output wire o_start_ready,
    input wire i_clock_locked,i_abort,i_source_fault,
    input wire i_hdr,
    input wire [2:0] i_sdr_profile,
    input wire [7:0] i_gain_code,
    input wire i_pair_event,i_pair_ok,
    output wire o_xclr,o_scl,
    inout wire io_sda,
    output reg o_config_written,
    output wire o_stable,o_error,
    output wire [7:0] o_register_index,
    output wire [127:0] o_rx_diag_cfg
);
    function integer max2;
        input integer a,b;
        begin max2=a>b?a:b;end
    endfunction
    function integer counter_width;
        input integer n;
        integer v;
        begin
            v=n-1;counter_width=0;
            while(v>0)begin counter_width=counter_width+1;v=v>>1;end
            if(counter_width<1)counter_width=1;
        end
    endfunction
    localparam integer TIMER_LIMIT=max2(max2(SDR_RESET_HOLD_CYCLES,SDR_RELEASE_WAIT_CYCLES),
        max2(SDR_WAKE_CYCLES,max2(HDR_RESET_HOLD_CYCLES,
        max2(HDR_RELEASE_WAIT_CYCLES,HDR_REGULATOR_WAIT_CYCLES))));
    localparam integer TIMER_BITS=counter_width(TIMER_LIMIT);
    // The existing HDR diagnostic state encoding is retained.
    localparam [3:0] IDLE=0,RESET_HOLD=1,RELEASE_WAIT=2,SEND=3,
        WAIT_ACK=4,WAKE_WAIT=5,WARMUP=6,STABLE=7,FAULT=8;
    localparam [TIMER_BITS-1:0] SDR_HOLD_LAST=SDR_RESET_HOLD_CYCLES-1,
        SDR_RELEASE_LAST=SDR_RELEASE_WAIT_CYCLES-1,SDR_WAKE_LAST=SDR_WAKE_CYCLES-1,
        HDR_HOLD_LAST=HDR_RESET_HOLD_CYCLES-1,HDR_RELEASE_LAST=HDR_RELEASE_WAIT_CYCLES-1,
        HDR_WAKE_LAST=HDR_REGULATOR_WAIT_CYCLES-1;
    reg [3:0] state;
    reg [TIMER_BITS-1:0] timer;
    reg [7:0] index,warmup_count,gain_code;
    reg hdr;
    reg [2:0] sdr_profile;
    wire [23:0] register_word;
    wire recipe_wait,recipe_last,busy,done,write_error;
    wire start_accept=i_start&&o_start_ready&&i_clock_locked;
    wire source_fault=hdr&&i_source_fault;
    wire write_valid=state==SEND&&i_clock_locked&&!i_abort&&!source_fault;
    wire write_ready=!busy;
    wire [TIMER_BITS-1:0] hold_last=hdr?HDR_HOLD_LAST:SDR_HOLD_LAST;
    wire [TIMER_BITS-1:0] release_last=hdr?HDR_RELEASE_LAST:SDR_RELEASE_LAST;
    wire [TIMER_BITS-1:0] wake_last=hdr?HDR_WAKE_LAST:SDR_WAKE_LAST;
    assign o_start_ready=state==IDLE||state==FAULT;
    assign o_xclr=i_rst_n&&i_clock_locked&&state!=IDLE&&state!=RESET_HOLD&&state!=FAULT;
    assign o_stable=state==STABLE&&i_clock_locked&&!i_abort&&!source_fault;
    assign o_error=state==FAULT;
    assign o_register_index=index;
    imx415_sensor_recipe #(.MODE_4K(MODE_4K),.RUNTIME_GAIN_ENABLE(RUNTIME_GAIN_ENABLE),.UHD_ENABLE(UHD_ENABLE)) u_table(
        .i_index(index),.i_hdr(hdr),.i_sdr_profile(sdr_profile),.i_gain_code(gain_code),
        .o_register(register_word),.o_wait(recipe_wait),.o_last(recipe_last));
    camera_i2c_write #(.HALF_PERIOD(I2C_HALF_PERIOD)) u_i2c(
        .i_clk(i_clk),.i_rst_n(i_rst_n&&!i_abort&&i_clock_locked),
        .i_start(write_valid&&write_ready),.i_register(register_word),
        .o_busy(busy),.o_done(done),.o_error(write_error),.o_scl(o_scl),.io_sda(io_sda));

    always @(posedge i_clk)begin
        if(!i_rst_n)begin
            state<=IDLE;timer<=0;index<=0;warmup_count<=0;
            hdr<=0;sdr_profile<=0;gain_code<=0;o_config_written<=0;
        end else if(i_abort||source_fault||(!i_clock_locked&&state!=IDLE&&state!=FAULT))begin
            state<=FAULT;timer<=0;warmup_count<=0;o_config_written<=0;
        end else begin
            case(state)
                IDLE,FAULT:if(start_accept)begin
                    hdr<=i_hdr;sdr_profile<=i_sdr_profile;gain_code<=i_gain_code;
                    state<=RESET_HOLD;timer<=0;index<=0;
                    warmup_count<=0;o_config_written<=0;
                end
                RESET_HOLD:if(timer==hold_last)begin state<=RELEASE_WAIT;timer<=0;end
                    else timer<=timer+1'b1;
                RELEASE_WAIT:if(timer==release_last)begin state<=SEND;timer<=0;end
                    else timer<=timer+1'b1;
                SEND:if(write_valid&&write_ready)state<=WAIT_ACK;
                WAIT_ACK:if(done)begin
                    if(write_error)begin state<=FAULT;o_config_written<=0;end
                    else if(recipe_last)begin
                        state<=hdr?WARMUP:STABLE;warmup_count<=0;o_config_written<=1;
                    end else if(recipe_wait)begin state<=WAKE_WAIT;timer<=0;end
                    else begin index<=index+1'b1;state<=SEND;end
                end
                WAKE_WAIT:if(timer==wake_last)begin index<=index+1'b1;state<=SEND;timer<=0;end
                    else timer<=timer+1'b1;
                WARMUP:if(i_pair_event)begin
                    if(!i_pair_ok)warmup_count<=0;
                    else if(warmup_count==WARMUP_PAIRS-1)state<=STABLE;
                    else warmup_count<=warmup_count+1'b1;
                end
                STABLE:if(hdr&&i_pair_event&&!i_pair_ok)begin state<=WARMUP;warmup_count<=0;end
                default:begin state<=FAULT;o_config_written<=0;end
            endcase
        end
    end
    // Existing observation packet only; none of these counters feeds control.
    reg [15:0] observed_writes,observed_write_errors,observed_pairs,observed_good_pairs;
    reg [23:0] last_register;
    wire [31:0] owner_state={warmup_count,index,state,i_clock_locked,i_abort,source_fault,
        i_pair_event,i_pair_ok,o_config_written,o_stable,o_error,write_valid,write_ready,done,write_error};
    assign o_rx_diag_cfg={8'd0,last_register,observed_good_pairs,observed_pairs,
        observed_write_errors,observed_writes,owner_state};
    always @(posedge i_clk)begin
        if(!i_rst_n)begin
            observed_writes<=0;observed_write_errors<=0;observed_pairs<=0;observed_good_pairs<=0;last_register<=0;
        end else begin
            if(done)begin
                if(!(&observed_writes))observed_writes<=observed_writes+1'b1;
                if(write_error&&!(&observed_write_errors))observed_write_errors<=observed_write_errors+1'b1;
                last_register<=register_word;
            end
            if(hdr&&i_pair_event)begin
                if(!(&observed_pairs))observed_pairs<=observed_pairs+1'b1;
                if(i_pair_ok&&!(&observed_good_pairs))observed_good_pairs<=observed_good_pairs+1'b1;
            end
        end
    end
    generate if(SDR_RESET_HOLD_CYCLES<1||SDR_RELEASE_WAIT_CYCLES<1||SDR_WAKE_CYCLES<1||
        HDR_RESET_HOLD_CYCLES<1||HDR_RELEASE_WAIT_CYCLES<1||HDR_REGULATOR_WAIT_CYCLES<1||
        WARMUP_PAIRS<1||WARMUP_PAIRS>255||I2C_HALF_PERIOD<1)begin:g_invalid
        CAMERA_CONFIG_REQUIRES_POSITIVE_WAITS_AND_VALID_WARMUP invalid_parameters();
    end endgenerate
endmodule
