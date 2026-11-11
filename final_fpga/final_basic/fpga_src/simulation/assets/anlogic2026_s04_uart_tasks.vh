// One UART owner. USER uses the production DIV27: 25 MHz / (16*27),
// approximately 57600 baud. LOCAL preserves its shorter existing fixture.
localparam integer UART_BIT_CYCLES=USER_TEST!=0 ? 432 : 32;
reg [7:0] uart_bytes[0:511];
integer uart_byte_count=0,uart_checks=0;
function automatic [7:0] uart_crc(input [7:0] prior,input [7:0] value);
    reg [7:0] c;integer j;
    begin
        c=prior^value;
        for(j=0;j<8;j=j+1)c=c[7]?(c<<1)^8'h07:c<<1;
        uart_crc=c;
    end
endfunction
task automatic uart_send_byte(input [7:0] value);
    integer bit_index;
    begin
        @(negedge sys_clk);uart_rx=0;
        repeat(UART_BIT_CYCLES)@(negedge sys_clk);
        for(bit_index=0;bit_index<8;bit_index=bit_index+1)begin
            uart_rx=value[bit_index];repeat(UART_BIT_CYCLES)@(negedge sys_clk);
        end
        uart_rx=1;repeat(UART_BIT_CYCLES)@(negedge sys_clk);
    end
endtask
`ifndef REFACTOR_READONLY_UART_MAIN
initial begin : uart_capture
    reg [7:0] value;integer bit_index;
    forever begin
        @(negedge uart_tx);
        repeat(UART_BIT_CYCLES+UART_BIT_CYCLES/2)@(posedge sys_clk);
        for(bit_index=0;bit_index<8;bit_index=bit_index+1)begin
            value[bit_index]=uart_tx;repeat(UART_BIT_CYCLES)@(posedge sys_clk);
        end
        if(uart_tx!==1||uart_byte_count>=512)$fatal(1,"top UART stop/capture failed");
        uart_bytes[uart_byte_count]=value;uart_byte_count=uart_byte_count+1;
    end
end
`endif
task automatic uart_bank_request(input [7:0] sequence_id,input [7:0] operation,
                                 input [7:0] bank,input [31:0] argument);
    reg [7:0] packet[0:11];reg [7:0] c;integer j;
    begin
        packet[0]=8'ha5;packet[1]=8'h5a;packet[2]=1;packet[3]=sequence_id;
        packet[4]=operation;packet[5]=bank;packet[6]=4;
        for(j=0;j<4;j=j+1)packet[7+j]=argument[j*8+:8];
        c=0;for(j=2;j<11;j=j+1)c=uart_crc(c,packet[j]);packet[11]=c;
        for(j=0;j<12;j=j+1)uart_send_byte(packet[j]);
    end
endtask
task automatic uart_bank_reply(input integer base,input [7:0] sequence_id,
                               input [7:0] operation,input [7:0] bank,
                               input [7:0] code,input [31:0] reply);
    reg [7:0] packet[0:12];reg [7:0] c;integer j,cycles;
    begin
        cycles=0;
        while(uart_byte_count<base+13&&cycles<30*UART_BIT_CYCLES*13)begin
            @(posedge sys_clk);cycles=cycles+1;
        end
        if(uart_byte_count<base+13)$fatal(1,"top UART response timeout operation %h",operation);
        packet[0]=8'ha5;packet[1]=8'h5a;packet[2]=1;packet[3]=sequence_id;
        packet[4]=operation;packet[5]=bank;packet[6]=5;packet[7]=code;
        for(j=0;j<4;j=j+1)packet[8+j]=reply[j*8+:8];
        c=0;for(j=2;j<12;j=j+1)c=uart_crc(c,packet[j]);packet[12]=c;
        for(j=0;j<13;j=j+1)begin
            if(uart_bytes[base+j]!==packet[j])
                $fatal(1,"top UART reply bank=%d op=%h byte=%0d got=%h expected=%h",
                       bank,operation,j,uart_bytes[base+j],packet[j]);
            uart_checks=uart_checks+1;
        end
    end
endtask
task automatic uart_command_bank(input [7:0] sequence_id,input [7:0] operation,
                                 input [7:0] bank,input [31:0] argument,
                                 input [7:0] code,input [31:0] reply);
    integer base;
    begin
        base=uart_byte_count;
        uart_bank_request(sequence_id,operation,bank,argument);
        uart_bank_reply(base,sequence_id,operation,bank,code,reply);
        if(uart_byte_count!=base+13)$fatal(1,"unexpected additional UART response");
        repeat(UART_BIT_CYCLES)@(posedge sys_clk);
    end
endtask
task automatic uart_command(input [7:0] sequence_id,input [7:0] operation,
                            input [31:0] argument,input [7:0] code,input [31:0] reply);
    begin uart_command_bank(sequence_id,operation,0,argument,code,reply);end
endtask
