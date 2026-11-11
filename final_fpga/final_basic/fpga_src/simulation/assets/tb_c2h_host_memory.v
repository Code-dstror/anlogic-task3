`timescale 1ns/1ps
// Independent CQ/CC host and delayed posted-memory/fence completer.
module tb_c2h_host_memory (
    input wire clk,rst_n,
    output reg [127:0] cq_data=0,
    output reg [3:0] cq_keep=0,
    output reg [87:0] cq_user=0,

    output reg cq_last=0,cq_valid=0,
    input wire cq_ready,
    input wire [127:0] cc_data,native_data,
    input wire [3:0] cc_keep,
    input wire [32:0] cc_user,

    input wire cc_last,cc_valid,
    input wire [63:0] native_address,
    input wire [7:0] native_be,
    input wire [12:0] native_length,
    input wire [1:0] native_format,
    input wire [9:0] native_tag,
    input wire native_hv,native_dv,native_eot,
    input wire [15:0] configured_requester_id,
    output reg [127:0] bypass_data=0,
    output reg [3:0] bypass_dwen=0,
    output reg bypass_hv=0,bypass_dv=0,bypass_eot=0,
    output reg bypass_dllp=0,bypass_tlp=0,bypass_ecrc=0,
    output reg [63:0] bypass_address=0,
    output reg [1:0] bypass_format=2,
    output reg [9:0] bypass_tag=26,bypass_length=1,
    output reg [15:0] bypass_requester=0,
    output reg bypass_function=0,bypass_poison=0,bypass_last=1,
    output reg [2:0] bypass_status=0,
    output reg [11:0] bypass_bytes=4,
    output wire requester_timeout,
    output reg cc_ready=0,
    output wire native_halt,
    input wire record_valid,record_ready,
    input wire [31:0] record_length,
    input wire [127:0] record_identity,
    input wire result_pending,quarantine,
    input wire [127:0] axis_data,input wire [15:0] axis_keep,
    input wire axis_last,axis_valid,axis_ready
);
    reg hold_rq=0,hold_completion=0;
    reg inject_timeout=0;
    reg [3:0] corrupt_completion=0;
    wire rc_valid=bypass_hv||bypass_dv;
    assign requester_timeout=inject_timeout;
    wire rq_ready=!native_halt;
    reg finite_stalls=1,check_header=1;
    reg [1023:0] record_path="actual_record.bin";
    reg [15:0] stall_lfsr=16'hcafe;
    integer cycles=0,received=0,committed=0,fence_count=0,metadata_count=0;
    integer payload_index=0,dwords=0,lane,word_index,offset,byte_index;
    integer fence_delay=-1;
    integer expected_length=0,expected_count=0,source_last_count=0,host_record_fd=0,source_lane;
    reg [31:0] bound_length=0;
    reg [127:0] bound_identity=0;
    reg data_packet=0,fence_seen=0;
    reg [3:0] first_be,last_be;
    reg [63:0] current_address;
    reg [7:0] expected [0:1048575];
    reg [7:0] posted [0:1048575];
    reg [7:0] host_memory [0:1048575];
    reg [31:0] cookie=32'hbadc0123;
    reg [7:0] read_tag=8'h31;
    reg held_rq=0,held_cc=0;
    reg [227:0] saved_rq;
    reg [164:0] saved_cc;
    assign native_halt=hold_rq||(finite_stalls&&cycles%11<stall_lfsr[1:0]);
    task fail;
        input [511:0] message;
        begin $fatal(1,"host BFM: %0s received=%0d committed=%0d time=%0t",message,received,committed,$time);end
    endtask
    task clear_capture;
        begin
            if(data_packet||fence_delay>=0||rc_valid)fail("capture reset while traffic outstanding");
            received=0;committed=0;fence_count=0;fence_seen=0;
            metadata_count=0;bound_length=0;bound_identity=0;expected_count=0;expected_length=0;source_last_count=0;
        end
    endtask
    always @(posedge clk)begin
        cycles=cycles+1;
        stall_lfsr<={stall_lfsr[14:0],stall_lfsr[15]^stall_lfsr[13]^stall_lfsr[12]^stall_lfsr[10]};
        if(!rst_n)begin data_packet=0;held_rq=0;held_cc=0;end
        else begin
            if(held_rq&&(!(native_hv||native_dv)||saved_rq!=={native_data,native_address,native_be,native_length,native_format,native_tag,native_hv,native_dv,native_eot}))fail("RQ stall stability");
            held_rq=(native_hv||native_dv)&&native_halt;saved_rq={native_data,native_address,native_be,native_length,native_format,native_tag,native_hv,native_dv,native_eot};
            if(held_cc&&(!cc_valid||saved_cc!=={cc_data,cc_keep,cc_user}))fail("CC stall stability");
            held_cc=cc_valid&&!cc_ready;saved_cc={cc_data,cc_keep,cc_user};
            if(record_valid&&record_ready)begin
                metadata_count=metadata_count+1;bound_length=record_length;bound_identity=record_identity;
                expected_length=record_length;
                if(record_length==0||record_length>1048576||metadata_count!=1)fail("metadata length/duplicate binding");
            end
            // Capture the true local source handshake as a byte reference only.
            // It never commits host memory or authorizes DMA completion.
            if(axis_valid&&axis_ready)begin
                if(check_header&&expected_count==0)begin
                    if(axis_data[31:0]==32'h31435a4c)begin
                        if(axis_data[95:64]!=bound_length||axis_data[63:48]!=128||axis_data[47:32]!=1)
                            fail("LZ actual header differs from metadata binding");
                    end else if(axis_data[127:96]+axis_data[63:48]!=bound_length)
                        fail("JPEG actual header differs from metadata binding");
                end
                for(source_lane=0;source_lane<16;source_lane=source_lane+1)if(axis_keep[source_lane])begin
                    if(expected_count>=expected_length)fail("source exceeded declared record length");
                    expected[expected_count]=axis_data[source_lane*8+:8];expected_count=expected_count+1;
                end
                if(axis_last)begin
                    source_last_count=source_last_count+1;
                    if(expected_count!=expected_length||source_last_count!=1)fail("source final length/count");
                end
            end
            if(result_pending&&!quarantine&&received>0&&
               (committed!=received||fence_count!=1||fence_delay>=0))fail("safe result before delayed host fence");
            if(data_packet&&!native_dv)fail("native MWr active bubble");
            if((native_hv||native_dv)&&!native_halt)begin
                if(native_hv)begin
                    if(data_packet)fail("native nested packet header");
                    if(!native_dv)begin
                        if(!native_eot||native_length!=4||native_tag!=26||native_address!=64'h100000||native_be!=15||native_format!=0)
                            fail("ordered native fence header");
                        if(fence_delay>=0||fence_count!=0)fail("duplicate fence");
                        fence_seen=1;fence_count=fence_count+1;fence_delay=40;
                    end else begin
                        if(native_format!==(native_address[63:32]!=0 ? 2'b11 : 2'b10)||native_tag!=0||native_length<4||native_length>128||native_length[1:0]!=0)
                            fail("native MWr header");
                        if(native_address[11:0]+native_length>4096)fail("native packet crosses4KiB");
                        current_address=native_address;dwords=native_length>>2;
                        first_be=native_be[3:0];last_be=native_be[7:4];payload_index=0;data_packet=1;
                    end
                end
                if(native_dv)begin
                    if(!data_packet)fail("native data without header");
                    for(lane=0;lane<4;lane=lane+1)begin
                        word_index=payload_index+lane;
                        for(byte_index=0;byte_index<4;byte_index=byte_index+1)begin
                            if(word_index<dwords&&((word_index==0&&first_be[byte_index])||
                               (word_index>0&&word_index<dwords-1)||
                               (word_index>0&&word_index==dwords-1&&last_be[byte_index])))begin
                                offset=current_address-64'h200000+word_index*4+byte_index;
                                if(offset!=received||offset>=expected_length||
                                   native_data[lane*32+byte_index*8+:8]!==expected[offset])fail("posted byte oracle");
                                posted[offset]=native_data[lane*32+byte_index*8+:8];received=received+1;
                            end
                        end
                    end
                    payload_index=payload_index+4;
                    if(native_eot!==(payload_index>=dwords))fail("native EOT/length mismatch");
                    if(native_eot)data_packet=0;
                end
            end
        end
    end
    // Posted writes remain invisible until this independently delayed host read.
    // RC is held to a real handshake; local RQ/TLAST never directly completes DMA.
    always @(negedge clk)begin
        if(!rst_n)begin fence_delay=-1;bypass_hv=0;bypass_dv=0;bypass_eot=0;end
        else begin
            bypass_hv=0;bypass_dv=0;bypass_eot=0;
            if(fence_delay>0&&!hold_completion)fence_delay=fence_delay-1;
            else if(fence_delay==0&&!hold_completion)begin
                for(byte_index=0;byte_index<received;byte_index=byte_index+1)host_memory[byte_index]=posted[byte_index];
                committed=received;
                if(received>0)begin
                    host_record_fd=$fopen(record_path,"wb");
                    for(byte_index=0;byte_index<received;byte_index=byte_index+1)$fwrite(host_record_fd,"%c",host_memory[byte_index]);
                    $fclose(host_record_fd);host_record_fd=0;
                end
                // Independent RC/hard-core boundary model. No application success is fabricated.
                bypass_data={96'd0,cookie};bypass_dwen=1;bypass_hv=1;bypass_dv=1;bypass_eot=1;
                bypass_address=0;bypass_format=2;bypass_tag=26;bypass_length=1;
                bypass_requester=configured_requester_id;bypass_function=0;bypass_poison=0;
                bypass_last=1;bypass_status=0;bypass_bytes=4;
                bypass_dllp=0;bypass_tlp=0;bypass_ecrc=0;
                case(corrupt_completion)
                    1:bypass_tag=25;2:bypass_tag=10'h11a;3:bypass_requester=configured_requester_id^16'h100;
                    4:bypass_function=1;5:bypass_poison=1;6:bypass_status=1;7:bypass_status=4;
                    8:bypass_ecrc=1;9:bypass_dllp=1;10:bypass_tlp=1;11:bypass_length=2;
                    12:bypass_dwen=3;13:bypass_last=0;14:bypass_data[31:0]=~cookie;15:bypass_address=4;
                endcase
                fence_delay=-1;
            end
        end
    end
    task cq_beat;
        input [127:0] data;input [3:0] keep;input terminal;
        integer fire;
        begin
            @(negedge clk);cq_data=data;cq_keep=keep;cq_last=terminal;cq_valid=1;
            fire=0;while(!fire)begin @(posedge clk);fire=cq_ready;end
            @(negedge clk);cq_valid=0;
        end
    endtask
    task write_reg;
        input [19:0] address;input [31:0] data;
        reg [127:0] head;
        begin
            head=0;head[19:0]=address;head[74:64]=1;head[78:75]=1;cq_user=15;
            cq_beat(head,15,0);cq_beat({96'd0,data},1,1);
        end
    endtask
    task read_reg;
        input [19:0] address;output [31:0] data;
        reg [127:0] head;
        begin
            head=0;head[19:0]=address;head[74:64]=1;head[95:80]=16'h1357;head[103:96]=read_tag;
            cq_user=15;cq_beat(head,15,1);
            while(!cc_valid)@(negedge clk);
            repeat(3)@(negedge clk);
            if(cc_data[63:48]!=16'h1357||cc_data[71:64]!=read_tag||cc_data[45:43]!=0||cc_keep!=15||!cc_last)
                fail("BAR read completion");
            data=cc_data[127:96];cc_ready=1;
            @(negedge clk);cc_ready=0;read_tag=read_tag+1;
        end
    endtask
    task grant;
        input integer generation;input integer capacity;
        begin
            clear_capture;
            write_reg(12'h020,32'h200000);write_reg(12'h024,0);write_reg(12'h028,capacity);
            write_reg(12'h030,7);write_reg(12'h034,generation);
            write_reg(12'h038,32'h99887766);write_reg(12'h03c,32'h11223344);
            write_reg(12'h040,32'h100000);write_reg(12'h044,0);write_reg(12'h048,cookie);
            write_reg(12'h008,1);
        end
    endtask
    task wait_safe;
        input integer code;input integer useful_length;
        reg [31:0] value;
        integer count;
        begin
            value=0;count=0;
            while(!value[2])begin
                read_reg(12'h00c,value);count=count+1;
                if(value[3]||count>20000)fail("unexpected quarantine/result timeout");
            end
            read_reg(12'h080,value);if(value!=code)fail("result code");
            read_reg(12'h084,value);if(value!=received)fail("result emitted length");
            if(useful_length>=0&&received!=useful_length)fail("useful record length");
            if(received>0&&(committed!=received||fence_count!=1))fail("missing host fence commit");
            for(count=0;count<committed;count=count+1)
                if(host_memory[count]!==expected[count])fail("committed memory oracle");
        end
    endtask
    task ack;
        begin write_reg(12'h008,16);end
    endtask
endmodule
