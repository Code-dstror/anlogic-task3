`timescale 1ns/1ps
module tb_s1_restore;
    reg clk=0;always #5 clk=~clk;
    reg rst_n=0,clear=0,frame_valid=0,frame_enable=1;
    wire frame_ready;reg [63:0] frame_owner=64'h13579bdf;
    reg s_valid=0,m_ready=1;wire s_ready,m_valid;
    reg [95:0] s_rgb=0;reg [31:0] s_y=0;reg [9:0] s_gain=256;reg [7:0] s_center=0;
    reg [3:0] s_keep=15;reg s_sof=0,s_eol=0,s_last=0;reg [31:0] s_tag=0;
    wire [95:0] m_rgb;wire [31:0] m_y;wire [3:0] m_keep,m_clipped,m_protected;
    wire m_sof,m_eol,m_last;wire [31:0] m_tag;wire [63:0] m_owner;wire busy,fault;
    reg [119:0] inputs [0:4095];reg [131:0] outputs [0:4095];
    reg [1023:0] root;
    integer sent=0,received=0,mode=0,ticks=0,stall_tail=0,pass=0,previous_input_cycle=-1,previous_output_cycle=-1;
    reg checking=0,was_stalled=0;
    reg [240:0] held;
    reg [31:0] lfsr=32'h7381abcd;
    wire [240:0] payload={m_owner,m_tag,m_sof,m_eol,m_last,m_keep,m_clipped,m_protected,m_y,m_rgb};
    preprocess_light_haze_restore4 dut(.*);
    task drive(input integer n);
        begin
            s_rgb=inputs[n][95:0];s_gain=inputs[n][105:96];s_center=inputs[n][113:106];s_keep=inputs[n][117:114];
            s_sof=n==0;s_eol=s_keep!=15||n==4095;s_last=n==4095;s_tag=n;
        end
    endtask
    always @(posedge clk) begin
        ticks=ticks+1;
        if(checking&&rst_n&&!clear) begin
            if(was_stalled&&(!m_valid||payload!==held)) $fatal(1,"output changed under stall");
            was_stalled=m_valid&&!m_ready;held=payload;
            if(s_valid&&s_ready) begin
                if(mode==0&&previous_input_cycle>=0&&ticks!=previous_input_cycle+1) $fatal(1,"input throughput bubble");
                previous_input_cycle=ticks;sent=sent+1;
            end
            if(m_valid&&m_ready) begin
                if(m_tag!==received||{m_clipped,m_y,m_rgb}!==outputs[received]||m_keep!==inputs[received][117:114]||
                    m_sof!==(received==0)||m_eol!==((inputs[received][117:114]!=15)||received==4095)||
                    m_last!==(received==4095)||m_owner!==frame_owner||m_protected!==0)
                    $fatal(1,"restore mismatch mode=%0d n=%0d got=%h gold=%h",mode,received,{m_clipped,m_y,m_rgb},outputs[received]);
                if(mode==0&&previous_output_cycle>=0&&ticks!=previous_output_cycle+1) $fatal(1,"output throughput bubble");
                previous_output_cycle=ticks;received=received+1;
            end
            if(fault) $fatal(1,"unexpected restore fault");
        end else was_stalled=0;
    end
    task abort_pipeline(input integer reset_global);
        integer n;
        begin
            checking=0;m_ready=0;frame_valid=1;while(!frame_ready) @(negedge clk);
            @(negedge clk);frame_valid=0;s_valid=1;
            for(n=0;n<7;n=n+1) begin drive(n);@(negedge clk);end
            s_valid=0;
            if(reset_global) rst_n=0;else clear=1;
            @(negedge clk);
            if(reset_global) rst_n=1;else clear=0;
            m_ready=1;repeat(10) @(negedge clk);
            if(m_valid||busy||fault) $fatal(1,"abort recovery failed");
        end
    endtask
    initial begin
        if(!$value$plusargs("ROOT=%s",root)) $fatal(1,"ROOT missing");
        $readmemh({root,"/inputs.mem"},inputs);$readmemh({root,"/outputs.mem"},outputs);
        repeat(5) @(negedge clk);rst_n=1;repeat(5) @(negedge clk);
        abort_pipeline(0);abort_pipeline(1);
        for(mode=0;mode<2;mode=mode+1) begin
            frame_valid=1;while(!frame_ready) @(negedge clk);
            @(negedge clk);frame_valid=0;
            sent=0;received=0;checking=1;stall_tail=0;previous_input_cycle=-1;previous_output_cycle=-1;
            while(received<4096) begin
                lfsr={lfsr[30:0],lfsr[31]^lfsr[21]^lfsr[1]^lfsr[0]};
                m_ready=mode==0||lfsr[2:0]!=0;
                if(mode==1&&m_valid&&m_last&&stall_tail<11) begin m_ready=0;stall_tail=stall_tail+1;end
                s_valid=sent<4096;
                if(s_valid) drive(sent);
                @(negedge clk);
            end
            checking=0;s_valid=0;m_ready=1;repeat(3) @(negedge clk);
            if(busy||fault) $fatal(1,"frame failed retirement");
        end
        $display("RESULT: PASS S1_RESTORE groups=8192 no_bubble=4096 random_stall=4096 tail_stall=11 clear_reset_recovery=2");$finish;
    end
    initial begin #1000000;$fatal(1,"timeout");end
endmodule
