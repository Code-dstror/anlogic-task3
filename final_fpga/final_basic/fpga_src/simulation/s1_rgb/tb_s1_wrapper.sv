`timescale 1ns/1ps
module tb_s1_wrapper;
    reg clk=0;always #5 clk=~clk;
    reg rst_n=0,clear=0,frame_valid=0;wire frame_ready;
    reg [63:0] frame_owner=64'h123;reg [31:0] frame_capture=7;
    reg frame_camera=0;reg [208:0] frame_cohort=0;reg [11:0] frame_rows=1;
    wire map_begin,map_release,map_cancel;reg map_begin_ready=1;
    wire [208:0] map_cohort;wire [31:0] map_capture;wire map_camera;
    reg map_history_valid=0,map_pin_valid=0,map_pin_camera=0;
    reg [7:0] map_history_age=4;reg [31:0] map_lut_generation=31,map_pin_capture=7;
    reg [39:0] map_pin_gain={4{10'd512}};reg [31:0] map_pin_center={4{8'd200}};
    reg s_valid=0,m_ready=1;wire s_ready,m_valid;
    reg [95:0] s_rgb={4{24'h10d0ff}};reg [31:0] s_y=0;reg [3:0] s_keep=15;
    reg s_sof=0,s_eol=0,s_last=0;reg [31:0] s_tag=0;
    wire [95:0] m_rgb;wire [31:0] m_y;wire [3:0] m_keep,m_clipped,m_protected;
    wire m_sof,m_eol,m_last;wire [31:0] m_tag;wire [63:0] m_owner;
    wire m_history_used;wire [7:0] m_history_age;wire [31:0] m_lut_generation;
    wire busy,fault;wire [5:0] map_outstanding;
    integer mode,n,sent,received,tail,release_count=0;
    reg checking=0,held=0;reg [238:0] held_payload;
    wire [238:0] payload={m_owner,m_tag,m_sof,m_eol,m_last,m_keep,m_clipped,m_protected,m_y,m_rgb};
    preprocess_light_haze_rgb4 dut(.*);
    always @(posedge clk) begin
        if(!rst_n) map_pin_valid<=0;
        else if(map_begin&&map_begin_ready) begin
            map_pin_valid<=map_history_valid;map_pin_capture<=map_capture;map_pin_camera<=map_camera;
        end else if(map_release) map_pin_valid<=0;
        if(map_release) begin
            if(checking&&received!=480) $fatal(1,"release before last output transfer");
            release_count=release_count+1;
        end
        if(checking) begin
            if(held&&(!m_valid||payload!==held_payload)) $fatal(1,"wrapper stall changed output");
            held=m_valid&&!m_ready;held_payload=payload;
            if(s_valid&&s_ready) sent=sent+1;
            if(m_valid&&m_ready) begin
                // 0x10d0ff restored at G512/C200 -> R4 G216 B255.
                if(m_rgb!==(mode==0 ? {4{24'h10d0ff}} : {4{24'h04d8ff}})||
                    m_tag!==received||m_sof!==(received==0)||m_last!==(received==479)||m_eol!==(received==479)||
                    m_owner!==frame_owner||m_history_used!==(mode==1)||map_outstanding!==0)
                    $fatal(1,"wrapper output mismatch mode=%0d group=%0d got=%h",mode,received,m_rgb);
                if(mode==1&&(!map_pin_valid||m_history_age!=4||m_lut_generation!=31)) $fatal(1,"history owner lost");
                received=received+1;
            end
            if(fault) $fatal(1,"unexpected wrapper fault");
        end else held=0;
    end
    task begin_frame;
        begin
            frame_valid=1;while(!frame_ready) @(negedge clk);
            @(negedge clk);frame_valid=0;
            while(!s_ready) @(negedge clk);
        end
    endtask
    task cancel_and_wait;
        begin
            s_valid=0;clear=1;@(negedge clk);clear=0;m_ready=1;
            repeat(12) @(negedge clk);
            if(busy||fault||map_pin_valid||!frame_ready) $fatal(1,"wrapper cancel recovery failed");
        end
    endtask
    initial begin
        repeat(5) @(negedge clk);rst_n=1;repeat(5) @(negedge clk);
        for(mode=0;mode<2;mode=mode+1) begin
            map_history_valid=mode;begin_frame();sent=0;received=0;tail=0;checking=1;
            while(received<480) begin
                m_ready=1;
                if(mode==1&&m_valid&&m_last&&tail<13) begin m_ready=0;tail=tail+1;end
                s_valid=sent<480;s_sof=sent==0;s_eol=sent==479;s_last=sent==479;s_tag=sent;
                if(s_valid&&!s_ready) $fatal(1,"wrapper added pixel bubble");
                @(negedge clk);
            end
            checking=0;s_valid=0;m_ready=1;repeat(10) @(negedge clk);
            if(busy||fault||map_pin_valid||release_count!=mode) $fatal(1,"owner retirement failed");
        end
        // A malformed row boundary raises fault and clear revokes the pin.
        begin_frame();s_valid=1;s_sof=1;s_eol=1;s_last=0;
        @(negedge clk);s_valid=0;if(!fault) $fatal(1,"malformed EOL not rejected");cancel_and_wait();
        begin_frame();s_valid=1;s_sof=1;s_eol=0;s_last=0;
        @(negedge clk);cancel_and_wait();
        $display("RESULT: PASS S1_WRAPPER identity_and_history=960 no_bubble=960 final_stall=13 bad_eol_clear=1 active_clear=1");$finish;
    end
    initial begin #200000;$fatal(1,"timeout");end
endmodule
