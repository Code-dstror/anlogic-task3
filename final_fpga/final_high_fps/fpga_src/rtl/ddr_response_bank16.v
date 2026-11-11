`timescale 1ns/1ps
// One DFI clock, one 16-beat burst reservation. Payload is never reset.
// The arbiter's total response count includes the registered output beat;
// a client receives no next AR until that entire reservation drains.
module ddr_response_bank16 (
    input wire clk, rst_n,
    input wire [134:0] s_data,
    input wire s_valid,
    output wire s_ready,
    output wire [134:0] m_data,
    output reg m_valid,
    input wire m_ready
);
    reg [3:0] write_address, read_address;
    reg [4:0] stored;
    wire push=s_valid && s_ready;
    // The official primitive's registered read output is also the held AXIS
    // register. Never issue a read while that register is stalled.
    wire fetch=rst_n && stored!=0 && (!m_valid || m_ready);
    wire [159:0] read_words;
    wire [159:0] write_words={25'd0,s_data};
    assign s_ready=rst_n && (m_valid ? stored<15 : stored<16);
    assign m_data=read_words[134:0];
    genvar lane;
    generate for(lane=0;lane<4;lane=lane+1)begin:g_lane
        td_sdp_ram40 #(.WIDTH(40),.DEPTH(16),.ADDR_WIDTH(4)) memory(
            .clk(clk),.wr_en(push),.wr_addr(write_address),
            .wr_data(write_words[lane*40+:40]),.rd_en(fetch),.rd_addr(read_address),
            .rd_data(read_words[lane*40+:40]));
    end endgenerate
    // A full RAM cannot accept a write, even if a read happens on that edge.
    // Thus equal read/write addresses never collide across primitive ports.
    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)begin
            write_address<=0;read_address<=0;stored<=0;m_valid<=0;
        end else begin
            if(push)write_address<=write_address+1'b1;
            if(fetch)read_address<=read_address+1'b1;
            case({push,fetch})
                2'b10:stored<=stored+1'b1;
                2'b01:stored<=stored-1'b1;
                default:begin end
            endcase
            if(fetch)m_valid<=1;
            else if(m_valid && m_ready)m_valid<=0;
        end
    end
endmodule
