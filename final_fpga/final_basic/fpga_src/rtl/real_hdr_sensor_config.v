`timescale 1ns/1ps
// Exclusive physical I2C owner for the fixed HDR preset. The caller must remove
// the SDR config driver before enabling this instance on the same pins.
module real_hdr_sensor_config #(
    parameter integer CFG_CLK_HZ=25000000,
    parameter integer WARMUP_PAIRS=8,
    parameter integer I2C_HALF_PERIOD=125,
    parameter integer RESET_HOLD_CYCLES=CFG_CLK_HZ/100,
    parameter integer RELEASE_WAIT_CYCLES=(CFG_CLK_HZ/1000)*30,
    parameter integer REGULATOR_WAIT_CYCLES=(CFG_CLK_HZ/1000)*24
) (
    input wire i_clk,i_rst_n,i_start,i_clock_locked,i_abort,i_source_fault,
    input wire i_pair_event,i_pair_ok,
    output wire o_start_ready,o_xclr,o_scl,
    inout wire io_sda,
    output wire o_config_written,o_stable,o_error,
    output wire [7:0] o_register_index,
    output wire [127:0] o_rx_diag_cfg
);
    wire valid,busy,done,write_error;
    wire [23:0] register_word;
    wire [31:0] owner_state;
    reg [15:0] observed_writes,observed_write_errors,observed_pairs,observed_good_pairs;
    reg [23:0] last_register;
    always @(posedge i_clk)begin
        if(!i_rst_n)begin
            observed_writes<=0;observed_write_errors<=0;observed_pairs<=0;observed_good_pairs<=0;last_register<=0;
        end else begin
            if(done)begin
                if(!(&observed_writes))observed_writes<=observed_writes+1'b1;
                if(write_error&&!(&observed_write_errors))observed_write_errors<=observed_write_errors+1'b1;
                last_register<=register_word;
            end
            if(i_pair_event)begin
                if(!(&observed_pairs))observed_pairs<=observed_pairs+1'b1;
                if(i_pair_ok&&!(&observed_good_pairs))observed_good_pairs<=observed_good_pairs+1'b1;
            end
        end
    end
    assign o_rx_diag_cfg={8'd0,last_register,observed_good_pairs,observed_pairs,
        observed_write_errors,observed_writes,owner_state};

    wire ready=!busy;
    imx415_hdr2_config_owner #(.CFG_CLK_HZ(CFG_CLK_HZ),.WARMUP_PAIRS(WARMUP_PAIRS),
        .RESET_HOLD_CYCLES(RESET_HOLD_CYCLES),.RELEASE_WAIT_CYCLES(RELEASE_WAIT_CYCLES),
        .REGULATOR_WAIT_CYCLES(REGULATOR_WAIT_CYCLES)) u_owner(
        .i_clk(i_clk),.i_rst_n(i_rst_n),.i_start(i_start),.o_start_ready(o_start_ready),
        .i_clock_locked(i_clock_locked),.i_abort(i_abort),.i_source_fault(i_source_fault),
        .i_pair_event(i_pair_event),.i_pair_ok(i_pair_ok),.o_xclr(o_xclr),.o_busy(),
        .o_write_valid(valid),.i_write_ready(ready),.o_write_register(register_word),
        .i_write_done(done),.i_write_error(write_error),
        .o_config_written(o_config_written),.o_stable(o_stable),.o_error(o_error),
        .o_register_index(o_register_index),.o_diag_state(owner_state),.o_long_driver_lines(),.o_short_driver_lines(),
        .o_ratio_log2(),.o_gain_q16(),.o_black_raw10());
    camera_i2c_write #(.HALF_PERIOD(I2C_HALF_PERIOD)) u_i2c(
        .i_clk(i_clk),.i_rst_n(i_rst_n && !i_abort && i_clock_locked),
        .i_start(valid && ready),.i_register(register_word),.o_busy(busy),
        .o_done(done),.o_error(write_error),.o_scl(o_scl),.io_sda(io_sda));
endmodule
