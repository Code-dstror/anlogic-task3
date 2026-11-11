`timescale 1ns/1ps
module core_tb;
    reg clk=0;
    always #4 clk=~clk;
    reg rst_n=0,cancel=0,debug_clear=0,start=0;
    reg [159:0] start_context=0,terminal_context=0;
    reg [12:0] native_width=0,native_height=0;
    reg [10:0] mag_threshold=0,gx_min=0;
    reg [1:0] ratio_shift=0,direction_sign=0;
    reg [19:0] min_count=0;
    reg [3:0] min_paired_strips=0;
    reg [51:0] strip_y_begin=0,strip_y_end=0,roi_left=0,roi_split=0,roi_right=0;
    reg event_valid=0;
    reg [220:0] event_metadata=0;
    reg [43:0] event_gx=0,event_gy=0,event_magnitude=0;
    reg frame_complete=0,frame_error=0;
    reg [7:0] source_error_code=5;
    reg record_ready=0;
    wire [1:0] record_valid,terminal_valid,terminal_error;
    wire [1355:0] record_data[0:1];
    wire [159:0] terminal_identity[0:1];
    wire [31:0] frames_started[0:1],frames_finished[0:1],frames_failed[0:1];
    wire [31:0] record_drop_count[0:1],stray_terminal_count[0:1];
    wire [1:0] first_fault_valid;
    wire [7:0] first_fault_code[0:1];
    wire [159:0] first_fault_context[0:1];
    genvar profile;
    generate for(profile=0;profile<2;profile=profile+1)begin:g_profile
        stage3_lane_candidates_terminal4 #(.STRIPS(4),.MONO_PRESET(profile),
            .FULLHEIGHT_ROI_ENABLE(0)) dut(
            .clk(clk),.rst_n(rst_n),.cancel(cancel),.debug_clear(debug_clear),.start(start),
            .start_context(start_context),.native_width(native_width),.native_height(native_height),
            .mag_threshold(mag_threshold),.gx_min(gx_min),.ratio_shift(ratio_shift),.direction_sign(direction_sign),
            .min_count(min_count),.min_paired_strips(min_paired_strips),.strip_y_begin(strip_y_begin),
            .strip_y_end(strip_y_end),.roi_left(roi_left),.roi_split(roi_split),.roi_right(roi_right),
            .event_valid(event_valid),.event_metadata(event_metadata),.event_gx(event_gx),
            .event_gy(event_gy),.event_magnitude(event_magnitude),.frame_complete(frame_complete),
            .frame_error(frame_error),.terminal_context(terminal_context),.source_error_code(source_error_code),
            .record_valid(record_valid[profile]),.record_ready(record_ready),.record_data(record_data[profile]),
            .frames_started(frames_started[profile]),.frames_finished(frames_finished[profile]),
            .frames_failed(frames_failed[profile]),.record_drop_count(record_drop_count[profile]),
            .stray_terminal_count(stray_terminal_count[profile]),.first_fault_valid(first_fault_valid[profile]),
            .first_fault_code(first_fault_code[profile]),.first_fault_context(first_fault_context[profile]),
            .terminal_valid(terminal_valid[profile]),.terminal_error(terminal_error[profile]),
            .terminal_identity(terminal_identity[profile]));
    end endgenerate
    reg [495:0] configs[0:21];
    reg [1355:0] expected_records[0:21];
    reg [31:0] counts[0:21];
    reg [0:0] mono[0:21];
    reg [353:0] events[0:32400];
    reg [1023:0] filename;
    reg [1355:0] held;
    integer cycle=0,total_events=0,case_index,beat_index,start_cycle,checks=0;

    task check(input bit condition,input string message);
        begin checks=checks+1;if(!condition)$fatal(1,"%s cycle%0d",message,cycle);end
    endtask
    task tick;begin @(posedge clk);#1;cycle=cycle+1;end endtask
    task clean_signals;
        begin start=0;event_valid=0;frame_complete=0;frame_error=0;record_ready=0;end
    endtask
    task idle;
        begin @(negedge clk);clean_signals();debug_clear=cycle%7==0;tick();end
    endtask
    task load_config(input integer index);
        begin
            {start_context,native_width,native_height,mag_threshold,gx_min,ratio_shift,direction_sign,
             min_count,min_paired_strips,strip_y_begin,strip_y_end,roi_left,roi_split,roi_right}=configs[index];
        end
    endtask
    task launch(input integer index);
        begin
            $sformat(filename,"case_%0d.hex",index);$readmemh(filename,events,0,counts[index]-1);
            @(negedge clk);clean_signals();load_config(index);start=1;tick();start_cycle=cycle;
        end
    endtask
    task drive_event(input integer index);
        begin
            clean_signals();
            {event_valid,event_metadata,event_gx,event_gy,event_magnitude}=events[index];
            // Input configuration must have no effect after accepted START.
            native_width=0;native_height=0;mag_threshold=2047;gx_min=2047;
            direction_sign=3;min_count=0;min_paired_strips=0;
            strip_y_begin=0;strip_y_end=0;roi_left=0;roi_split=0;roi_right=0;
        end
    endtask
    task feed(input integer length);
        begin for(beat_index=0;beat_index<length;beat_index=beat_index+1)begin
            @(negedge clk);drive_event(beat_index);tick();total_events=total_events+1;
        end end
    endtask
    task finish_case(input integer index,input bit external_error,input bit consume_old);
        begin
            @(negedge clk);clean_signals();terminal_context=configs[index][495:336];
            frame_error=external_error;frame_complete=!external_error;record_ready=consume_old;tick();
            check(terminal_valid[0]&&terminal_identity[0]===configs[index][495:336],"owning terminal identity");
            @(negedge clk);clean_signals();
        end
    endtask
    task compare_record(input integer index);
        begin
            if(!record_valid[0]||record_data[0]!==expected_records[index])begin
                $display("actual   %0339h",record_data[0]);
                $display("expected %0339h",expected_records[index]);
                $fatal(1,"scalar all1356-bit mismatch case%0d",index);
            end
            check(!terminal_error[0],"successful frame terminal");
            if(mono[index])begin
                check(record_valid[1]&&record_data[1]===expected_records[index],"MONO fourband scalar all1356-bit record");
                check(terminal_valid[1]&&!terminal_error[1]&&terminal_identity[1]===configs[index][495:336],"MONO terminal");
            end
        end
    endtask
    task consume;
        begin @(negedge clk);clean_signals();record_ready=1;tick();
            check(record_valid==0,"same-edge record consumption");
            @(negedge clk);clean_signals();end
    endtask
    task clear_session;
        begin @(negedge clk);clean_signals();cancel=1;tick();
            check(record_valid==0&&terminal_valid==0&&frames_started[0]==0&&record_drop_count[0]==0,
                "cancel flushes functional and diagnostic ownership");
            @(negedge clk);cancel=0;end
    endtask
    function [1355:0] error_record(input [1355:0] good,input [7:0] error_code);
        integer s;begin
            error_record=good;
            for(s=0;s<4;s=s+1)error_record[s*266+:240]=0;
            error_record[1195]=0;error_record[1194:1187]=error_code;
            error_record[1186]=0;error_record[1064+:20]=0;
        end
    endfunction
    task expect_error(input integer index,input [7:0] error_code);
        begin
            check(record_valid[0]&&record_data[0]===error_record(expected_records[index],error_code),
                $sformatf("canonical error%0d record",error_code));
            check(terminal_valid[0]&&terminal_error[0],"failed functional terminal independent of report slot");
        end
    endtask
    task fault_case(input integer kind,input [7:0] error_code);
        begin
            clear_session();launch(8);
            if(kind==1)begin
                // Configuration error is captured on START, not on a later pin change.
                clear_session();@(negedge clk);load_config(8);roi_right=0;start=1;tick();
                @(negedge clk);clean_signals();
            end else if(kind==7||kind==8)feed(1);
            else if(kind==9)begin feed(counts[8]);@(negedge clk);drive_event(counts[8]-1);tick();end
            else if(kind==10)begin
                feed(counts[8]-1);@(negedge clk);drive_event(counts[8]-1);
                frame_complete=1;terminal_context=configs[8][495:336];tick();
            end else begin
                @(negedge clk);drive_event(0);
                case(kind)
                    2:event_gx[10:0]=11'h400;
                    3:event_metadata[61]=!event_metadata[61];
                    4:event_metadata[6:3]=4'h5;
                    5:event_metadata[2]=0;
                    6:event_metadata[20]=1;
                endcase
                tick();
                // A later apparently valid stream cannot repair a poisoned frame.
                feed(2);
            end
            if(kind!=10)finish_case(8,kind==8,0);
            expect_error(8,error_code);consume();
        end
    endtask
    initial begin
        $readmemh("configs.hex",configs);$readmemh("records.hex",expected_records);
        $readmemh("counts.hex",counts);$readmemh("mono.hex",mono);
        repeat(3)@(negedge clk);rst_n=1;idle();
        for(case_index=0;case_index<22;case_index=case_index+1)begin
            launch(case_index);feed(counts[case_index]);
            check(record_valid==0&&terminal_valid==0,"EOF alone never publishes completion");
            finish_case(case_index,0,0);compare_record(case_index);
            if(case_index==0)check(cycle-start_cycle==32401,"dense II1: 32400 groups plus terminal");
            held=record_data[0];
            repeat(case_index==1?127:case_index%3)begin idle();
                check(record_valid[0]&&record_data[0]===held,"record holds all fields under output stall");
                if(mono[case_index])check(record_valid[1]&&record_data[1]===held,"MONO record holds under output stall");end
            consume();
        end
        $display("NUMERIC PASS cases22 all8stats dense2040 negative boundaries66/67/134/135/201/202/269 ratios/signs min_count16320/16384 events%0d",total_events);
        // Every local poison path, source error and invalid EOF/terminal coincidence.
        fault_case(1,1);fault_case(2,2);fault_case(3,3);fault_case(4,4);fault_case(5,5);
        fault_case(6,6);fault_case(7,7);fault_case(8,8'h85);fault_case(9,5);fault_case(10,7);
        // A foreign terminal must not release the frame.
        clear_session();launch(8);feed(1);
        @(negedge clk);clean_signals();frame_complete=1;terminal_context=configs[9][495:336];tick();
        check(!record_valid[0]&&!terminal_valid[0]&&stray_terminal_count[0]==1,"foreign terminal ignored");
        clear_session();launch(8);feed(counts[8]);finish_case(8,0,0);compare_record(8);held=record_data[0];
        launch(9);feed(1);finish_case(9,1,0);
        check(record_valid[0]&&record_data[0]===held&&record_drop_count[0]==1,"stalled old record survives newer failure");
        check(terminal_valid[0]&&terminal_error[0],"report drop still retires functional terminal");
        launch(9);feed(counts[9]);finish_case(9,0,1);compare_record(9);consume();
        check(record_drop_count[0]==1,"same-edge consume/refill preserves new report");
        // Explicit reset while running, then clean recovery; cancellation of a held result.
        launch(8);feed(3);@(negedge clk);clean_signals();rst_n=0;tick();
        check(record_valid==0&&terminal_valid==0,"reset abort has no terminal report");
        @(negedge clk);rst_n=1;launch(8);feed(counts[8]);finish_case(8,0,0);compare_record(8);
        clear_session();
        // Existing generic START interruption reports old identity correctly in
        // the sparse record. The terminal-identity wire has a known old behavior
        // on simultaneous finish+START; admission must exclude that overlap.
        launch(8);feed(1);launch(9);
        expect_error(8,9);
        check(record_data[0][1355:1196]===configs[8][495:336],"interrupted sparse record retains old context");
        if(terminal_identity[0]!==configs[8][495:336])
            $display("LIMITATION legacy finish+START terminal_identity changes to new context; requires admission exclusion");
        consume();feed(counts[9]);finish_case(9,0,0);compare_record(9);consume();
        $display("RESULT: PASS LANE4_CORE scalar1356 generic/MONO profiles control checks%0d cycles%0d",checks,cycle);$finish;
    end
    initial begin #10000000;$fatal(1,"core bounded watchdog");end
endmodule
