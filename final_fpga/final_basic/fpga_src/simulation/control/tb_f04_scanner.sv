`timescale 1ns/1ps
`include "pcie_protocol_v1.vh"
module tb_f04_scanner;
    reg clk=0;always #4 clk=~clk;
    reg rst_n=0,cancel=0,start_valid=0,word_valid=0,result_ready=0;
    reg [31:0] start_mode=0,word_data=0;
    wire start_ready,word_ready,result_valid,ref_start_ready,ref_word_ready,ref_result_valid;
    wire [2:0] result_error,ref_result_error;
    mono_config_scan_v2 #(.LEGACY_SUPPORTED(8'h3c),.V2_SUPPORTED_MODES(3'b101),.V2_SUPPORTED_ENABLES(6'h3f)) dut(.*);
    f04_scan_reference #(.LEGACY_SUPPORTED(8'h3c),.V2_SUPPORTED_MODES(3'b101),.V2_SUPPORTED_ENABLES(6'h3f)) reference(
        .clk(clk),.rst_n(rst_n),.cancel(cancel),.start_valid(start_valid),.start_ready(ref_start_ready),.start_mode(start_mode),
        .word_valid(word_valid),.word_ready(ref_word_ready),.word_data(word_data),.result_valid(ref_result_valid),.result_ready(result_ready),.result_error(ref_result_error));
    reg [1023:0] extension;
    reg [31:0] rng=32'h2197a04e;
    integer schema_id,test_id,k,limit,checks=0,cases=0,valid_cases=0,new_rejections=0,priority_cases=0,cancels=0;
    reg [2:0] expected,old_expected,held;
    task check(input bit okay,input string why);
        begin checks=checks+1;if(!okay)$fatal(1,"F04 scanner schema=%0d case=%0d %s got=%0d ref=%0d",schema_id,test_id,why,result_error,ref_result_error);end
    endtask
    always @(posedge clk)begin #1;if(rst_n)check({start_ready,word_ready,result_valid}===
        {ref_start_ready,ref_word_ready,ref_result_valid},"all scanner handshake cycles unchanged");end
    task offer_word(input [31:0] value);
        begin
            rng=rng*32'd1664525+32'd1013904223;
            repeat(rng[1:0])begin @(negedge clk);word_valid=0;word_data=~value;end
            @(negedge clk);word_data=value;word_valid=1;limit=0;
            do begin @(posedge clk);limit=limit+1;check(limit<40,"word bounded");end while(!word_ready);
            @(negedge clk);word_valid=0;
        end
    endtask
    task make_extension(input integer schema_value,case_value);
        begin
            extension=0;extension[31:0]=schema_value==2 ? 32'h202 : 32'h401;
            extension[66:64]=4;extension[76:67]=50;extension[86:77]=50;
            extension[100:87]=64;extension[104:101]=3;extension[108:105]=15;
            extension[191:128]=1000000;extension[223:192]=50000000;extension[255:224]=100000000;
            expected=0;old_expected=0;
            case(case_value)
                1:begin extension[223:192]=0;expected=1;end
                2:begin extension[255:224]=0;expected=1;end
                3:begin extension[191:160]=1;expected=1;end
                4:begin extension[66:64]=3;expected=schema_value==1?5:1;old_expected=expected;end
                5:begin extension[108:105]=0;expected=schema_value==1?5:1;old_expected=expected;end
                6:begin extension[191:128]=0;extension[223:192]=1;extension[255:224]=1;end
                7:begin extension[191:128]=64'hffffffff;extension[223:192]=1;extension[255:224]=1;end
                8:begin extension[191:160]=32'hffffffff;expected=1;end
                9:begin
                    extension[223:192]=0;
                    if(schema_value==2)extension[9:8]=1;else extension[14]=1;
                    expected=5;old_expected=5;
                end
                10:begin extension[223:192]=0;extension[31]=1;expected=schema_value==1?5:1;old_expected=expected;end
                11:begin extension[223:192]=0;extension[66:64]=3;expected=schema_value==1?5:1;old_expected=expected;end
                12:begin extension[223:192]=32'hffffffff;extension[255:224]=32'hffffffff;end
            endcase
        end
    endtask
    task start_scan;
        begin
            @(negedge clk);start_valid=1;limit=0;
            do begin @(posedge clk);limit=limit+1;check(limit<40,"start bounded");end while(!start_ready);
            @(negedge clk);start_valid=0;
        end
    endtask
    task run_case(input integer schema_value,case_value);
        begin
            make_extension(schema_value,case_value);start_scan();
            for(k=0;k<32;k=k+1)offer_word(extension[k*32+:32]);
            limit=0;while(!result_valid)begin @(negedge clk);limit=limit+1;check(limit<40,"result bounded");end
            check(result_error==expected,"new boundary and error priority");check(ref_result_error==old_expected,"fixed a4 negative control");
            held=result_error;
            repeat(4)begin @(negedge clk);check(result_valid&&result_error==held&&!start_ready,"result held under stall");end
            if(expected==0)valid_cases=valid_cases+1;
            else if(old_expected==0)new_rejections=new_rejections+1;
            else priority_cases=priority_cases+1;
            cases=cases+1;
            $display("F04_SCAN schema=%0d case=%0d result=%0d old=%0d",schema_value,case_value,result_error,ref_result_error);
            result_ready=1;@(posedge clk);@(negedge clk);result_ready=0;
        end
    endtask
    initial begin
        repeat(4)@(negedge clk);rst_n=1;
        for(schema_id=1;schema_id<=2;schema_id=schema_id+1)begin
            for(test_id=0;test_id<13;test_id=test_id+1)run_case(schema_id,test_id);
            make_extension(schema_id,1);start_scan();for(k=0;k<8;k=k+1)offer_word(extension[k*32+:32]);
            cancel=1;@(posedge clk);@(negedge clk);cancel=0;cancels=cancels+1;
            check(!result_valid,"cancelled bad timer has no result");test_id=0;run_case(schema_id,0);
        end
        check(cases==28&&new_rejections==8&&valid_cases==10&&priority_cases==10&&cancels==2,"risk coverage");
        $display("RESULT: PASS F04 scanner checks=%0d cases=%0d valid=%0d new_invalid=%0d priority=%0d cancels=%0d",checks,cases,valid_cases,new_rejections,priority_cases,cancels);$finish;
    end
    initial begin #200000;$fatal(1,"F04 scanner watchdog");end
endmodule
