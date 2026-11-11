"""Adapt the existing real-store small fixture to prove HDR commit observations."""
from pathlib import Path
EXT=Path(__file__).resolve().parent
PROJECT=EXT.parents[2]
OLD=EXT.parent/'stereo_store'
CASE=EXT/'contract'
CASE.mkdir(exist_ok=True)
if (CASE/'tb_hdr_commit_contract.sv').exists():raise RuntimeError('Do not overwrite retained contract bench')
body=(OLD/'tb_stereo_full_store_quiescent.sv').read_text(encoding='utf-8-sig')
def change(old,new,count=1):
    global body
    if body.count(old)!=count:raise RuntimeError(f'{old!r}: {body.count(old)} != {count}')
    body=body.replace(old,new)
change('module tb_stereo_full_store_quiescent;', '`include "pcie_protocol_v1.vh"\nmodule tb_hdr_commit_contract;')
change('    reg [39:0] raw=0;', '''    reg [39:0] raw=0;
    reg [196:0] meta0=0,meta1=0;
    reg source0=0,pair_ready=0;
    wire source_ready0,pair_valid,legacy_valid;
    integer finishes0=0,finishes1=0,legacy_commits=0,pair_takes=0,aw_count=0,b_count=0;''')
change(".i_stereo_mode(1'b1),.i_stereo_mode_pixel(1'b1)", ".i_stereo_mode(1'b0),.i_stereo_mode_pixel(1'b0)")
change(".i_pair_hdr_enable(1'b0)", ".i_pair_hdr_enable(1'b1)")
change(".i_pair_ready(1'b0)", ".i_pair_ready(pair_ready)")
change(".i_pair_now(64'd0)", ".i_pair_now(64'd110)")
change(".i_capture_data(40'd0),.i_capture_valid(1'b0),.i_capture_accept(1'b1)", ".i_capture_data(raw),.i_capture_valid(raw_valid),.i_capture_accept(1'b1)")
change(".i_capture_sof(1'b0),.i_capture_eol(1'b0)", ".i_capture_sof(raw_sof),.i_capture_eol(raw_eol)")
change(".i_frame_sequence(32'd0)", ".i_frame_sequence(32'd10)")
change(".i_capture_metadata(197'd0),.i_capture_source_valid(1'b0)", ".i_capture_metadata(meta0),.i_capture_source_valid(source0)")
change(".i_capture_source_sequence(32'd0)", ".i_capture_source_sequence(32'd10)")
change(".i_capture1_sequence(32'd31)", ".i_capture1_sequence(32'd10)")
change(".i_capture1_metadata(197'd0)", ".i_capture1_metadata(meta1)")
change(".i_capture1_source_sequence(32'd31)", ".i_capture1_source_sequence(32'd10)")
change(".i_capture1_source_camera(1'b1)", ".i_capture1_source_camera(1'b0)")
change('.o_capture_source_ready()', '.o_capture_source_ready(source_ready0)')
change('.o_commit_valid()', '.o_commit_valid(legacy_valid)')
change('.o_pair_valid()', '.o_pair_valid(pair_valid)')
change('if(awaddr!=28\'h6000000||awlen!=4)$fatal(1,"unexpected real capture address/length");', 'if(awlen!=4)$fatal(1,"unexpected real HDR capture burst length");aw_count++;')
change('            if(bvalid&&bready)bvalid<=0;', '            if(bvalid&&bready)begin bvalid<=0;b_count++;end')
start=body.index('    always @(negedge clk)if(rst&&observe)begin')
body=body[:start]+'''    task check_descriptor(input [383:0] frame,input integer role);
        begin
            if(frame[2:1]!=role||frame[108:77]!=10||frame[76:45]!=17||frame[140:109]!=3||frame[366:335]!=10)
                $fatal(1,"real writer member descriptor identity");
        end
    endtask
    always @(posedge clk)if(rst)begin
        if(dut.finish_valid&&dut.finish_ready)begin
            if(!dut.finish_ok)$fatal(1,"LONG finish not OK");
            check_descriptor(dut.capture_frame,1);finishes0++;
        end
        if(dut.finish_valid1&&dut.hdr_finish1_ready)begin
            if(!dut.finish_ok1)$fatal(1,"SHORT finish not OK");
            check_descriptor(dut.capture_frame1,2);finishes1++;
        end
        if(legacy_valid)begin
            if(!(dut.finish_valid&&dut.finish_ready&&dut.finish_ok))$fatal(1,"legacy observation without LONG finish");
            legacy_commits++;
        end
        if(pair_valid)begin
            if(finishes0!=1||finishes1!=1)$fatal(1,"pair presented before both real member writes completed");
            if(pair_ready)pair_takes++;
        end
    end
    integer g;
    initial begin
        meta0[196:193]=4'b1101;meta1[196:193]=4'b1110;
        meta0[192]=`PCIE_RECORD_V2_SOURCE_PHYSICAL;meta1[192]=`PCIE_RECORD_V2_SOURCE_PHYSICAL;
        meta0[191:160]=10;meta1[191:160]=10;
        meta0[159:128]=32'h56a3d02f;meta1[159:128]=32'h56a3d02f;
        meta0[127:96]=256;meta1[127:96]=256;
        meta0[95:64]=3200;meta1[95:64]=200;meta0[63:0]=100;meta1[63:0]=104;
        #500;rst=1;repeat(100)@(negedge clk);
        cfg=1;do @(posedge clk);while(!cfg_ready);
        if(cfg_error)$fatal(1,"real HDR configuration rejected");
        @(negedge clk);cfg=0;wait(admit&&!route_sdr);repeat(30)@(negedge pix);
        for(g=0;g<G;g=g+1)begin
            raw={10'd13,10'd7,10'd3,10'd1};raw_valid=1;raw_sof=g==0;raw_eol=g%(W/4)==W/4-1;
            @(negedge pix);
        end
        raw_valid=0;raw_sof=0;raw_eol=0;repeat(4)@(negedge pix);
        fork
            begin source0=1;do @(posedge pix);while(!source_ready0);@(negedge pix);source0=0;end
            begin source_valid=1;do @(posedge pix);while(!source_ready);@(negedge pix);source_valid=0;end
        join
        wait(pair_valid);repeat(4)@(negedge clk);
        if(finishes0!=1||finishes1!=1||legacy_commits!=1||aw_count!=2||b_count!=2||fault)
            $fatal(1,"HDR contract counts finish=%0d/%0d legacy=%0d AW/B=%0d/%0d fault=%b",finishes0,finishes1,legacy_commits,aw_count,b_count,fault);
        pair_ready=1;@(negedge clk);pair_ready=0;repeat(4)@(negedge clk);
        if(pair_takes!=1)$fatal(1,"actual pair acquire count");
        $display("RESULT: PASS HDR_COMMIT_CONTRACT real_member_finish=1/1 legacy_long_commit=1 pair_acquire=1 AW=2 B=2");$finish;
    end
    initial begin #1000000;$fatal(1,"real HDR commit contract watchdog");end
endmodule
'''
(CASE/'tb_hdr_commit_contract.sv').write_text(body,encoding='utf-8',newline='\n')
print('PREPARED_REAL_STORE_CONTRACT')
