// Passive 8N1 decoder for the production TX-only observer. No DUT state is driven.
localparam integer OBSERVER_BIT_CYCLES=217;
reg [7:0] observer_packet[0:67];
integer observer_packet_index=0,observer_frames=0,observer_fresh_frames=0;
integer observer_active_frames=0,observer_bytes=0,observer_trace_fd;
integer observer_progress_frames=0;
reg [2:0] observer_previous_progress_fresh=0;
reg [15:0] observer_previous_progress0[0:2];
integer observer_submit_frames=0,observer_cfg_frames=0,observer_cfg_fresh_frames=0;
integer observer_packet_length=0,observer_rx_frames=0,observer_rt_frames=0,observer_rt_fresh_frames=0;
integer observer_last_kind=-1;
reg [15:0] observer_expected_sequence=0;
reg [15:0] observer_last_ob_sequence=0;
reg observer_expect_cfg=0;

function automatic [7:0] observer_crc8(input [7:0] prior,input [7:0] value);
    reg [7:0] c;integer k;
    begin
        c=prior^value;
        for(k=0;k<8;k=k+1)c=c[7] ? ((c<<1)^8'h07) : (c<<1);
        observer_crc8=c;
    end
endfunction

function automatic [15:0] observer_crc16(input [15:0] prior,input [7:0] value);
    reg [15:0] c;integer k;
    begin
        c=prior^{value,8'd0};
        for(k=0;k<8;k=k+1)c=c[15] ? ((c<<1)^16'h1021) : (c<<1);
        observer_crc16=c;
    end
endfunction

initial begin : readonly_uart_decode
    reg [7:0] value,c;
    reg [15:0] c16;
    reg [15:0] progress_current;
    reg progress_observed;
    integer bit_number,j,trace_index,trace_pre_count,progress_domain;
    observer_trace_fd=$fopen("uart_frames.hex","w");
    forever begin
        @(negedge uart_tx);
        repeat(OBSERVER_BIT_CYCLES+OBSERVER_BIT_CYCLES/2)@(posedge sys_clk);
        for(bit_number=0;bit_number<8;bit_number=bit_number+1)begin
            value[bit_number]=uart_tx;
            repeat(OBSERVER_BIT_CYCLES)@(posedge sys_clk);
        end
        if(uart_tx!==1'b1 || (^value)===1'bx)
            $fatal(1,"READONLY_UART invalid data or stop bit");
        observer_packet[observer_packet_index]=value;
        observer_bytes=observer_bytes+1;
        if(observer_packet_index==1)begin
            if(observer_packet[0]===8'h4f && value===8'h42)observer_packet_length=29;
            else if(observer_packet[0]===8'h44 && value===8'h4a)observer_packet_length=68;
            else if(observer_packet[0]===8'h52 && value===8'h58)observer_packet_length=64;
            else if(observer_packet[0]===8'h52 && value===8'h54)observer_packet_length=64;
            else $fatal(1,"READONLY_UART unknown mixed-stream magic");
        end
        if(observer_packet_length!=0 && observer_packet_index==observer_packet_length-1)begin
          if(observer_packet_length==29)begin
            if(observer_packet[2]!==8'd2 || observer_packet[3]!==8'd29)
                $fatal(1,"READONLY_UART OB header/version/length");
            if(observer_expect_cfg)$fatal(1,"READONLY_UART missing DJ between OB frames");
`ifdef REFACTOR_READONLY_UART_MAIN
            if(observer_frames!=0&&observer_last_kind!=2)$fatal(1,"READONLY_UART missing final RX between rounds");
`endif
            if({observer_packet[5],observer_packet[4]}!==observer_expected_sequence)
                $fatal(1,"READONLY_UART sequence got=%h expected=%h",
                    {observer_packet[5],observer_packet[4]},observer_expected_sequence);
            if(observer_packet[6][7:3]!==5'd0 || observer_packet[7][7:3]!==5'd0)
                $fatal(1,"READONLY_UART reserved mask bits");
            c=0;
            for(j=0;j<28;j=j+1)c=observer_crc8(c,observer_packet[j]);
            if(observer_packet[28]!==c)$fatal(1,"READONLY_UART CRC8 mismatch");
            observer_last_ob_sequence=observer_expected_sequence;
            observer_expected_sequence=observer_expected_sequence+1'b1;
            observer_expect_cfg=1;
            observer_last_kind=0;
            observer_frames=observer_frames+1;
            if(observer_packet[6][2:0]==3'b111)observer_fresh_frames=observer_fresh_frames+1;
            if(observer_packet[6][2] && {observer_packet[25],observer_packet[24]}!=0)
                observer_submit_frames=observer_submit_frames+1;
            // Slow UART can miss instantaneous busy. Require a real event0
            // advance (PIX admission / DFI ACK / USER submit) from a preceding
            // fresh report, not a nonzero historical value. Counters belong to
            // independent observer cold reset; current business reset must be
            // released. Sequence continuity was already checked above.
            progress_observed=0;
            for(progress_domain=0;progress_domain<3;progress_domain=progress_domain+1)begin
                progress_current={observer_packet[13+6*progress_domain],observer_packet[12+6*progress_domain]};
                if(observer_previous_progress_fresh[progress_domain]&&
                    observer_packet[6][progress_domain]&&observer_packet[7][progress_domain]&&
                    progress_current!=observer_previous_progress0[progress_domain])progress_observed=1;
                observer_previous_progress0[progress_domain]=progress_current;
                observer_previous_progress_fresh[progress_domain]=observer_packet[6][progress_domain];
            end
            if(progress_observed)observer_progress_frames=observer_progress_frames+1;
            if(progress_observed||(observer_packet[6][0]&&observer_packet[7][0]&&
                (observer_packet[10][7]||!observer_packet[11][0])) ||
               (observer_packet[6][1]&&observer_packet[7][1]&&observer_packet[16][6]))
                observer_active_frames=observer_active_frames+1;
          end else if(observer_packet_length==64&&observer_packet[1]==8'h54)begin
`ifdef REFACTOR_READONLY_UART_MAIN
            $fatal(1,"READONLY_UART production RT history is retired");
`endif
            if(observer_packet[2]!==1 || observer_packet[3]!==1 || observer_packet[4]!==64 || observer_packet[5]!==0)
                $fatal(1,"READONLY_UART RT header");
            if(observer_last_kind!=2 || {observer_packet[7],observer_packet[6]}!==observer_last_ob_sequence)
                $fatal(1,"READONLY_UART RT must follow same-round RX");
            if(observer_packet[8][7:1]!==0 || observer_packet[9]!==0 || observer_packet[41][7:5]!==0)
                $fatal(1,"READONLY_UART RT reserved masks/sample bits");
            for(j=50;j<62;j=j+1)if(observer_packet[j]!==0)$fatal(1,"READONLY_UART RT reserved");
            trace_index=observer_packet[48][5:0];
            trace_pre_count={observer_packet[49][3:0],observer_packet[48][7:6]};
            if((trace_index>39&&trace_index!=63)||trace_pre_count>32||
                (observer_packet[49][4]&&observer_packet[49][5])||
                observer_packet[49][6]!==
                    (observer_packet[49][4]&&trace_index<40&&trace_index>=32-trace_pre_count))
                $fatal(1,"READONLY_UART RT payload schema");
            c16=16'hffff;
            for(j=0;j<62;j=j+1)c16=observer_crc16(c16,observer_packet[j]);
            if({observer_packet[63],observer_packet[62]}!==c16)$fatal(1,"READONLY_UART RT CRC16");
            observer_rt_frames=observer_rt_frames+1;
            if(observer_packet[8][0])observer_rt_fresh_frames=observer_rt_fresh_frames+1;
            observer_last_kind=3;
          end else if(observer_packet_length==64)begin
            if(observer_packet[2]!==1 || observer_packet[3]!==1 || observer_packet[4]!==64 || observer_packet[5]!==0)
                $fatal(1,"READONLY_UART RX header");
            if(observer_expect_cfg || observer_last_kind!=1 || {observer_packet[7],observer_packet[6]}!==observer_last_ob_sequence)
                $fatal(1,"READONLY_UART RX round");
            c16=16'hffff;
            for(j=0;j<62;j=j+1)c16=observer_crc16(c16,observer_packet[j]);
            if({observer_packet[63],observer_packet[62]}!==c16)$fatal(1,"READONLY_UART RX CRC16");
            for(j=58;j<62;j=j+1)if(observer_packet[j]!==0)$fatal(1,"READONLY_UART RX reserved");
            observer_rx_frames=observer_rx_frames+1;
            observer_last_kind=2;
          end else begin
            if(observer_packet[2]!==8'd1 || observer_packet[3]!==8'd1 ||
               observer_packet[4]!==8'd68 || observer_packet[5]!==8'd0)
                $fatal(1,"READONLY_UART DJ header/version/type/length/reserved");
            if(!observer_expect_cfg || observer_last_kind!=0 || {observer_packet[7],observer_packet[6]}!==observer_last_ob_sequence)
                $fatal(1,"READONLY_UART DJ does not match preceding OB round");
            if(observer_packet[8][7:2]!==6'd0 || observer_packet[9][7:2]!==6'd0)
                $fatal(1,"READONLY_UART DJ reserved masks");
            c16=16'hffff;
            for(j=0;j<66;j=j+1)c16=observer_crc16(c16,observer_packet[j]);
            if({observer_packet[67],observer_packet[66]}!==c16)
                $fatal(1,"READONLY_UART DJ CRC16 mismatch");
            observer_cfg_frames=observer_cfg_frames+1;
            if(observer_packet[8][1:0]==2'b11)observer_cfg_fresh_frames=observer_cfg_fresh_frames+1;
            observer_expect_cfg=0;
            observer_last_kind=1;
          end
            for(j=0;j<observer_packet_length;j=j+1)$fwrite(observer_trace_fd,"%02x",observer_packet[j]);
            $fwrite(observer_trace_fd,"\n");
            observer_packet_index=0;observer_packet_length=0;
        end else observer_packet_index=observer_packet_index+1;
    end
end

// RX carries independent noise throughout the real business run. The observer
// has no RX port and the legacy writable-debug branch stays disabled.
initial begin : readonly_uart_rx_noise
    reg [7:0] noise;
    noise=8'hd3;
    repeat(400)@(negedge sys_clk);
    while(!done_o)begin
        repeat(97)@(negedge sys_clk);
        noise={noise[6:0],noise[7]^noise[5]^noise[4]^noise[3]};
        uart_rx=noise[0];
    end
end

task automatic readonly_uart_finish;
    integer rx_tail_guard;
    begin
`ifdef REFACTOR_READONLY_UART_MAIN
        // The added wire frame may still be in flight when business completes.
        // This bounded passive tail drives no transaction or DUT state.
        rx_tail_guard=0;
        while((observer_rx_frames<1||observer_frames<2)&&rx_tail_guard<750000)begin
            @(posedge sys_clk);rx_tail_guard=rx_tail_guard+1;
        end
        check(observer_rx_frames>=1,"complete RX diagnostics in bounded passive MAIN tail");
        check(observer_rt_frames==0,"retired RT history does not appear in the production stream");
`endif
        check(dut.READONLY_UART_ENABLE==1 && dut.DEBUG_UART_ENABLE==0,
            "actual production TX-only observer enabled and legacy writable debug disabled");
        check(observer_frames>=2 && observer_fresh_frames>=1 && observer_active_frames>=1,
            "valid observer reports prove MAIN activity through live levels or fresh counter advance");
        check(observer_submit_frames>=1,"V2 fresh USER event0 reports a real native accept_submit");
        check(observer_cfg_frames>=1 && observer_cfg_fresh_frames>=1,
            "DJ CRC16-valid fresh diagnostic frames share the actual business UART");
        $fclose(observer_trace_fd);
        $display("UART_READONLY_MAIN PASS frames=%0d fresh=%0d active=%0d bytes=%0d submit_frames=%0d cfg_frames=%0d cfg_fresh=%0d rx_frames=%0d rt_frames=%0d rt_fresh=%0d progress_frames=%0d",
            observer_frames,observer_fresh_frames,observer_active_frames,observer_bytes,observer_submit_frames,
            observer_cfg_frames,observer_cfg_fresh_frames,observer_rx_frames,observer_rt_frames,observer_rt_fresh_frames,observer_progress_frames);
    end
endtask
