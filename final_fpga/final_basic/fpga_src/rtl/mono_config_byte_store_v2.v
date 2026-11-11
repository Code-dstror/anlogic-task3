`timescale 1ns/1ps
// USER-domain cold configuration storage. Four existing byte-wide official
// RAMs hold arbitrary shadow bytes and two atomic active readback banks.
// ERAM pins have a synchronous USER register boundary. Public reset invalidates
// state asynchronously; a complete RAM sweep follows the port-stage clear.
// Application cancel preserves promised public writes and BAR reads.
module mono_config_byte_store_v2 (
    input wire clk,rst_n,
    output wire init_done,
    input wire write_valid,output wire write_ready,
    input wire [5:0] write_word,input wire [31:0] write_data,input wire [3:0] write_strobes,
    input wire lock_valid,output wire lock_ready,output reg locked,
    input wire unlock_valid,output wire unlock_ready,
    input wire cancel,input wire clear_active,
    input wire publish_valid,input wire publish_extension,output wire publish_ready,output reg publish_done,
    output wire publish_complete,input wire publish_commit_ready,
    output wire copy_busy,
    input wire read_valid,output wire read_ready,input wire read_active,input wire [5:0] read_word,
    output wire read_response_valid,input wire read_response_ready,output wire [31:0] read_response_data,
    input wire scan_valid,output wire scan_ready,input wire [5:0] scan_word,
    output wire scan_response_valid,input wire scan_response_ready,output wire [31:0] scan_response_data
);
    localparam [1:0] BAR=0,SCAN=1,COPY=2;
    reg initialized,init_committed;
    reg [7:0] init_address;
    reg active_bank,active_valid;
    reg copying,copy_inflight,copy_extension,copy_complete;
    reg [5:0] copy_word;
    reg write_pending;
    reg [5:0] pending_word;
    reg [31:0] pending_data;
    reg [3:0] pending_strobes;
    reg response_pending;
    reg [1:0] response_owner;
    reg [3:0] response_forward;
    reg [31:0] response_forward_data;
    reg response_default;
    reg [31:0] response_default_data;
    reg internal_turn;
    wire [31:0] ram_data;
    reg [3:0] ram_write_enable,ram_read_enable;
    reg [7:0] ram_write_address,ram_read_address;
    reg [31:0] ram_write_word;
    wire ram_write_debt=|ram_write_enable;
    reg read_inflight;
    reg [1:0] inflight_owner;
    reg [3:0] inflight_forward;
    reg [31:0] inflight_forward_data,inflight_default_data;
    reg inflight_default;
    function [31:0] reset_word;
        input [5:0] address;
        begin reset_word=address==3 ? 32'd75 : address==5 ? 32'd1 : 32'd0;end
    endfunction
    assign init_done=rst_n&&init_committed;
    assign copy_busy=copying;
    assign publish_complete=init_done&&copying&&copy_complete&&!ram_write_debt;
    assign lock_ready=init_done&&!locked&&!copying&&!cancel&&!write_pending&&!ram_write_debt;
    assign write_ready=init_done&&!locked&&!copying&&!lock_valid&&!cancel;
    assign unlock_ready=init_done&&locked&&(!copying||(publish_complete&&publish_commit_ready))&&!publish_valid&&!cancel;
    assign publish_ready=init_done&&locked&&!copying&&!cancel&&!clear_active;
    wire write_fire=write_valid&&write_ready;
    wire response_fire=response_pending && (response_owner==BAR ? read_response_ready :
        response_owner==SCAN ? scan_response_ready : 1'b1);
    wire slot_free=!response_pending||response_fire;
    wire internal_request=!clear_active&&(copying ? !copy_inflight&&!copy_complete : scan_valid&&locked);
    wire choose_internal=internal_request&&(!read_valid||internal_turn);
    wire choose_bar=read_valid&&!choose_internal;
    wire read_accept=init_done&&slot_free&&!read_inflight&&(choose_bar||choose_internal)&&!cancel;
    wire choose_copy=choose_internal&&copying;
    assign read_ready=init_done&&slot_free&&!read_inflight&&!choose_internal&&!cancel;
    assign scan_ready=init_done&&slot_free&&!read_inflight&&locked&&!copying&&(!read_valid||internal_turn)&&!cancel&&!clear_active;
    wire [1:0] selected_bank=choose_bar&&read_active ? (active_bank ? 2'd2 : 2'd1) : 2'd0;
    wire [5:0] selected_word=choose_bar ? read_word : choose_copy ? copy_word : scan_word;
    wire [7:0] read_address={selected_bank,selected_word};
    wire default_read=choose_bar&&read_active&&!active_valid;
    wire [31:0] logical_data=response_default ? response_default_data :
        {response_forward[3]?response_forward_data[31:24]:ram_data[31:24],
         response_forward[2]?response_forward_data[23:16]:ram_data[23:16],
         response_forward[1]?response_forward_data[15:8]:ram_data[15:8],
         response_forward[0]?response_forward_data[7:0]:ram_data[7:0]};
    assign read_response_valid=init_done&&response_pending&&response_owner==BAR;
    assign scan_response_valid=init_done&&response_pending&&response_owner==SCAN;
    assign read_response_data=logical_data;assign scan_response_data=logical_data;
    wire copy_write=initialized&&copying&&response_pending&&response_owner==COPY&&!cancel&&!clear_active;
    wire [7:0] write_address=!initialized ? init_address : write_pending ? {2'd0,pending_word} :
        {active_bank ? 2'd1 : 2'd2,copy_word};
    wire [31:0] ram_write_data=!initialized ? reset_word(init_address[5:0]) : write_pending ? pending_data :
        (!copy_extension&&copy_word>=9 ? 32'd0 : logical_data);
    // This is the only boundary that drives physical ERAM ports.
    integer byte_index;
    always @(posedge clk)begin
        if(!rst_n)begin
            ram_write_enable<=0;ram_read_enable<=0;
            ram_write_address<=0;ram_read_address<=0;ram_write_word<=0;
        end else begin
            ram_write_address<=write_address;ram_read_address<=read_address;
            ram_write_word<=ram_write_data;
            for(byte_index=0;byte_index<4;byte_index=byte_index+1)begin
                ram_write_enable[byte_index]<=!initialized ||
                    (write_pending&&pending_strobes[byte_index]) || copy_write;
                ram_read_enable[byte_index]<=read_accept&&!default_read&&
                    !(write_pending&&pending_strobes[byte_index]&&selected_bank==0&&pending_word==selected_word);
            end
        end
    end
    genvar lane;
    generate for(lane=0;lane<4;lane=lane+1)begin:g_byte
        td_sdp_ram40 #(.WIDTH(8),.DEPTH(256),.ADDR_WIDTH(8)) u_ram(
            .clk(clk),.wr_en(ram_write_enable[lane]),.wr_addr(ram_write_address),.wr_data(ram_write_word[lane*8+:8]),
            .rd_en(ram_read_enable[lane]),.rd_addr(ram_read_address),.rd_data(ram_data[lane*8+:8]));
    end endgenerate
    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)begin
            initialized<=0;init_committed<=0;init_address<=0;active_bank<=0;active_valid<=0;
            locked<=0;copying<=0;copy_inflight<=0;copy_extension<=0;copy_complete<=0;copy_word<=0;publish_done<=0;
            write_pending<=0;pending_word<=0;pending_data<=0;pending_strobes<=0;
            response_pending<=0;response_owner<=BAR;response_forward<=0;
            read_inflight<=0;inflight_owner<=BAR;inflight_forward<=0;inflight_forward_data<=0;
            inflight_default<=0;inflight_default_data<=0;response_forward_data<=0;
            response_default<=0;response_default_data<=0;internal_turn<=0;
        end else begin
            publish_done<=0;
            if(initialized&&!ram_write_debt)init_committed<=1;
            read_inflight<=read_accept;
            if(read_inflight)begin
                response_pending<=1;response_owner<=inflight_owner;
                response_forward<=inflight_forward;response_forward_data<=inflight_forward_data;
                response_default<=inflight_default;response_default_data<=inflight_default_data;
            end
            if(!initialized)begin
                if(init_address==191)begin initialized<=1;init_address<=0;end
                else init_address<=init_address+1'b1;
            end
            write_pending<=write_fire;
            if(write_fire)begin pending_word<=write_word;pending_data<=write_data;pending_strobes<=write_strobes;end
            if(lock_valid&&lock_ready)locked<=1;
            if(unlock_valid&&unlock_ready)locked<=0;
            if(publish_valid&&publish_ready)begin copying<=1;copy_inflight<=0;copy_complete<=0;copy_extension<=publish_extension;copy_word<=0;end
            if(response_fire)response_pending<=0;
            if(read_accept)begin
                inflight_owner<=choose_bar?BAR:choose_copy?COPY:SCAN;
                inflight_forward_data<=pending_data;inflight_default<=default_read;inflight_default_data<=reset_word(selected_word);
                inflight_forward<=write_pending&&selected_bank==0&&pending_word==selected_word ? pending_strobes : 4'd0;
                internal_turn<=choose_bar;
                if(choose_copy)copy_inflight<=1;
            end
            if(copy_write)begin
                copy_inflight<=0;
                if(copy_word==40)copy_complete<=1;
                else copy_word<=copy_word+1'b1;
            end
            // Complete copying does not itself publish. The BAR commits its
            // scalar epoch/APPLIED values on this same ready/valid edge.
            if(publish_complete&&publish_commit_ready)begin
                copying<=0;copy_complete<=0;active_bank<=!active_bank;active_valid<=1;publish_done<=1;
            end
            // Application cancel kills only its internal scan/copy lease.
            // A previously promised public BAR read remains valid and stable.
            if(cancel||clear_active)begin
                if(read_inflight&&inflight_owner!=BAR)begin read_inflight<=0;response_pending<=0;end
                locked<=0;copying<=0;copy_inflight<=0;copy_complete<=0;publish_done<=0;
                if(response_pending&&response_owner!=BAR&&!(read_accept&&choose_bar))response_pending<=0;
            end
            if(clear_active)active_valid<=0;
        end
    end
endmodule
