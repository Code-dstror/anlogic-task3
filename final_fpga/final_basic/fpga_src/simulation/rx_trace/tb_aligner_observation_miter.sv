`timescale 1ns/1ps
module tb_aligner_observation_miter;
    reg clk=0,rst_n=0,enable=1,wait_sync=1,packet_done=0,chain=1;
    always #5 clk=~clk;
    reg [31:0] raw=0;
    reg [3:0] direct_valid=0;
    wire [31:0] ref_bytes,obs_bytes,ref_word,obs_word;
    wire [3:0] ref_valid,obs_valid;
    wire [11:0] offsets,taps;
    wire [3:0] found;
    wire ref_wv,obs_wv,ref_done,obs_done;
    wire [31:0] ref_in=chain?ref_bytes:raw,obs_in=chain?obs_bytes:raw;
    wire [3:0] ref_iv=chain?ref_valid:direct_valid,obs_iv=chain?obs_valid:direct_valid;
    reg [7:0] seen_offsets=0;
    reg [5:0] seen_taps=0;
    integer checks=0,false_sot=0,cycle=0;
    genvar lane;
    generate for(lane=0;lane<4;lane=lane+1)begin:g_lane
        csi_rx_byte_align reference(.I_clock(clk),.I_reset_n(rst_n),.I_enable(enable),
            .I_lan_data_in(raw[8*lane+:8]),.I_wait_for_sync(wait_sync),.I_packet_done(packet_done),
            .O_data_out_vaild(ref_valid[lane]),.O_data_out(ref_bytes[8*lane+:8]));
        csi_rx_byte_align_observed observed(.I_clock(clk),.I_reset_n(rst_n),.I_enable(enable),
            .I_lan_data_in(raw[8*lane+:8]),.I_wait_for_sync(wait_sync),.I_packet_done(packet_done),
            .O_data_out_vaild(obs_valid[lane]),.O_data_out(obs_bytes[8*lane+:8]),
            .o_diag_offset(offsets[3*lane+:3]),.o_diag_found(found[lane]));
        always @(posedge clk)begin
            #1;
            if(offsets[3*lane+:3]!==reference.r_offset || found[lane]!==reference.r_was_found)
                $fatal(1,"byte observation alias mismatch lane=%0d",lane);
            if(rst_n && found[lane])begin
                seen_offsets[offsets[3*lane+:3]]=1;
                if(!wait_sync) false_sot=false_sot+1;
            end
            if(taps[3*lane+:3]!==ref_align.r_taps[lane])$fatal(1,"word tap alias mismatch");
        end
    end endgenerate
    csi_rx_word_align #(.MIPI_LAN(4)) ref_align(.I_word_clock(clk),.I_reset_n(rst_n),.I_enable(enable),
        .I_packet_done(packet_done),.I_wait_for_sync(wait_sync),.O_packet_done_out(ref_done),
        .I_word_in(ref_in),.I_valid_in(ref_iv),.O_word_out(ref_word),.O_valid_out(ref_wv));
    csi_rx_word_align_observed #(.MIPI_LAN(4)) obs_align(.I_word_clock(clk),.I_reset_n(rst_n),.I_enable(enable),
        .I_packet_done(packet_done),.I_wait_for_sync(wait_sync),.O_packet_done_out(obs_done),
        .I_word_in(obs_in),.I_valid_in(obs_iv),.O_word_out(obs_word),.O_valid_out(obs_wv),.o_diag_taps(taps));
    always @(posedge clk)begin
        #1;
        checks=checks+1;
        if({ref_valid,ref_bytes,ref_word,ref_wv,ref_done}!=={obs_valid,obs_bytes,obs_word,obs_wv,obs_done})
            $fatal(1,"complete-output aligner miter mismatch cycle=%0d",checks);
    end
    task tick;@(negedge clk);endtask
    task cold;begin rst_n=0;enable=1;wait_sync=1;packet_done=0;raw=0;direct_valid=0;
        repeat(8)tick();rst_n=1;repeat(8)tick();end endtask
    reg [511:0] serial[0:3];
    integer shift,j,k,lead;
    reg [31:0] random_state=32'h5908a37b;
    initial begin
        // True and header-shaped false SoT, all eight bit offsets, lane skew.
        for(shift=0;shift<8;shift=shift+1)begin
            chain=1;cold();wait_sync=(shift!=0);
            for(k=0;k<4;k=k+1)begin
                serial[k]=0;
                serial[k][16+shift+8*k+:8]=8'hb8;
                serial[k][24+shift+8*k+:32]=32'h00097e2b;
                serial[k][56+shift+8*k+:64]=64'h0123456789abcdef;
            end
            for(j=0;j<24;j=j+1)begin
                for(k=0;k<4;k=k+1)raw[k*8+:8]=serial[k][j*8+:8];
                if(j==12 && shift!=0)wait_sync=0;
                tick();
                if(shift==0 && (|obs_valid || obs_wv))$fatal(1,"false SoT published while wait disabled");
            end
            packet_done=1;tick();packet_done=0;repeat(8)tick();
        end
        if(seen_offsets!==8'hff || false_sot==0)$fatal(1,"byte offset/false SoT coverage missing mask=%h",seen_offsets);
        // Word-skew tap choices 0..5, including the longest supported delay.
        chain=0;
        for(lead=0;lead<6;lead=lead+1)begin
            cold();
            for(j=0;j<12;j=j+1)begin
                raw=32'h03020100+j*32'h04040404;
                direct_valid=(j>=lead)?4'b1111:4'b0001;
                tick();
                if(obs_wv)seen_taps[taps[2:0]]=1;
            end
            if(taps[2:0]!==3'(lead))$fatal(1,"word lead coverage failed expected=%0d actual=%0d",lead,taps[2:0]);
        end
        // Deterministic noise, enable stalls, done priority and reset phases.
        for(j=0;j<2500;j=j+1)begin
            random_state={random_state[30:0],random_state[31]^random_state[21]^random_state[1]^random_state[0]};
            raw=random_state;direct_valid=random_state[7:4];chain=random_state[8];
            enable=random_state[9]||random_state[10];wait_sync=random_state[11];packet_done=random_state[12];
            rst_n=((j%173)>2);tick();
        end
        if(seen_taps!==6'h3f)$fatal(1,"word tap coverage missing");
        $display("PASS observed aligner complete-output miter checks=%0d offsets=%h taps=%h false_sot=%0d",checks,seen_offsets,seen_taps,false_sot);
        $finish;
    end
    initial begin #200000;$fatal(1,"aligner miter timeout");end
endmodule
