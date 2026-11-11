`timescale 1ns/1ps

// Real ROM, config FSM and I2C master. The bus slave only ACKs and decodes.
module sdr_wait_case #(
    parameter integer EYE=0, RESET_WAIT=7, WAKE_CYCLES=600000
)(output reg finished=0);
    reg clk=0,reset_n=0;
    // 24 MHz to 1 ps resolution; cycle assertions are the precise time base.
    always #20.833333 clk=~clk;
    wire scl,xclr,done,error;
    tri1 sda;
    imx415_config #(.WAIT_CYCLES(RESET_WAIT),.SDR_WAKE_CYCLES(WAKE_CYCLES),
        .I2C_HALF_PERIOD(4)) dut(
        .i_clk(clk),.i_rst_n(reset_n),.o_xclr(xclr),.o_scl(scl),.io_sda(sda),
        .o_done(done),.o_error(error),.i_exposure_valid(1'b0),
        .i_exposure_lines(20'd0),.o_exposure_ready(),.o_exposure_done(),
        .o_exposure_error(),.i_gain_code(8'd0));
    reg slave_ack=0,slave_active=0;
    integer slave_bit=0,slave_byte=0,transactions=0;
    reg [7:0] slave_shift=0;
    reg [31:0] slave_word=0;
    integer cycles=0,start_cycle=0,standby_stop=0,standby_ack=0,master_ack=0;
    integer checks=0,completed=0,cohort=0,wake_seen=0;
    integer state_cycles=0,previous_state=-1;
    reg [7:0] expected_index=0;
    wire [23:0] expected_register;
    imx415_mode_table expected_table(.i_index(expected_index),.o_register(expected_register));
    assign sda=slave_ack?1'b0:1'bz;
    task check(input bit condition,input string message);
        begin
            checks++;
            if(!condition)begin
                $display("FAIL SDR_WAIT eye=%0d cohort=%0d cycle=%0d tx=%0d %s",
                    EYE,cohort,cycles,transactions,message);$fatal(1);
            end
        end
    endtask
    always @(negedge sda) if(scl===1'b1&&!slave_active)begin
        slave_active=1;slave_bit=0;slave_byte=0;slave_word=0;start_cycle=cycles;
    end
    always @(negedge scl) slave_ack=slave_active&&(slave_bit==8);
    always @(posedge scl) if(slave_active)begin
        if(slave_bit<8)begin
            slave_shift={slave_shift[6:0],sda};slave_bit++;
            if(slave_bit==8)begin slave_word={slave_word[23:0],slave_shift};slave_byte++;end
        end else begin
            if(slave_byte==4&&slave_word==32'h34300000)standby_ack=cycles;
            if(slave_byte==4&&slave_word==32'h34300200)begin
                master_ack=cycles;
                check(cycles-standby_ack>=WAKE_CYCLES,"actual STANDBY/XMSTA ACK gap");
            end
            slave_bit=0;
        end
    end
    always @(posedge sda) if(scl===1'b1&&slave_active)begin
        check(slave_byte==4,"all four I2C bytes completed");
        check(slave_word[31:24]==8'h34,"sensor I2C address");
        if(transactions<201)check(slave_word[23:0]===expected_register,"ordered real SDR ROM write");
        else if(transactions==201)begin
            check(slave_word==32'h34300000,"STANDBY cancel is write 201");
            standby_stop=cycles;
        end else if(transactions==202)begin
            check(slave_word==32'h34300200,"XMSTA start is final write");
            check(start_cycle-standby_stop>=WAKE_CYCLES,"STANDBY STOP to XMSTA START gap");
            if(WAKE_CYCLES==600000)
                check(start_cycle-standby_stop>=576000,"24 MHz minimum 24 ms");
            $display("TIMING eye=%0d cohort=%0d wake_cycles=%0d stop_to_start=%0d ack_to_ack=%0d",
                EYE,cohort,WAKE_CYCLES,start_cycle-standby_stop,master_ack-standby_ack);
        end else check(0,"no extra I2C write");
        transactions++;expected_index=transactions;
        slave_active=0;slave_ack=0;
    end
    always @(posedge clk)begin
        cycles++;
        if(!reset_n)begin state_cycles=0;previous_state=-1;end
        else begin
            check(!error,"no configuration NACK/error");
            if(previous_state==dut.state)state_cycles++;
            else begin
                if(previous_state==0||previous_state==1)
                    check(state_cycles==RESET_WAIT,"reset hold/release retains WAIT_CYCLES");
                if(previous_state==5)begin
                    check(state_cycles==WAKE_CYCLES,"WAKE_WAIT uses independent exact cycle count");
                    wake_seen++;
                end
                previous_state=dut.state;state_cycles=1;
            end
            if(done)check(transactions==203,"done only after all 203 ACKed writes");
        end
    end
    task reset_cohort;
        begin
            @(negedge clk);reset_n=0;
            repeat(4)@(negedge clk);
            check(!xclr&&!done,"cohort reset cancels readiness and holds XCLR");
            transactions=0;expected_index=0;slave_ack=0;slave_active=0;
            standby_stop=0;standby_ack=0;cohort++;
            @(negedge clk);reset_n=1;
        end
    endtask
    task finish_boot;
        integer limit;
        begin
            limit=0;
            while(!done)begin @(negedge clk);limit++;check(limit<WAKE_CYCLES+100000,"bounded configuration");end
            check(xclr&&!error&&transactions==203,"completed SDR cohort");
            completed++;
        end
    endtask
    initial begin
        reset_cohort;finish_boot; // Cold SDR, each eye's independent I2C bus.
        reset_cohort;
        wait(dut.state==5);repeat(3)@(negedge clk);
        check(!done&&transactions==202,"reset interruption reaches the regulator wait");
        reset_cohort;finish_boot; // Configuration restart on return to SDR.
        check(completed==2&&wake_seen==2,"initial SDR and return SDR each waited fully");
        $display("RESULT: PASS SDR_WAIT eye=%0d checks=%0d completed=%0d default_wake=%0d reset_wait=%0d",
            EYE,checks,completed,WAKE_CYCLES,RESET_WAIT);
        finished=1;
    end
endmodule

module tb_sdr_start_wait;
    wire eye0,eye1,short_case;
    sdr_wait_case #(.EYE(0),.RESET_WAIT(7)) cam0(eye0);
    sdr_wait_case #(.EYE(1),.RESET_WAIT(11)) cam1(eye1);
    sdr_wait_case #(.EYE(2),.RESET_WAIT(5),.WAKE_CYCLES(13)) scaled(short_case);
    initial begin
        wait(eye0&&eye1&&short_case);
        $display("RESULT: PASS SDR_START_WAIT all_cases=3 completed_boots=6");$finish;
    end
    initial begin #70000000;$fatal(1,"SDR wait simulation timeout");end
endmodule
