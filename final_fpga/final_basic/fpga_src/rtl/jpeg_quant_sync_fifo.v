`timescale 1ns/1ps
// Production candidate: one PIX clock, 512 total resident 147-bit tokens.
// The four existing official RAM40 read registers are the held output word.
// Only pointers, valid/count and release state reset; RAM payload never resets.
module jpeg_quant_sync_fifo (
    input wire i_clk,i_rst_n,
    input wire [146:0] s_data,
    input wire s_valid,
    output wire s_ready,
    output wire [146:0] m_data,
    output wire m_valid,
    input wire m_ready,
    output wire o_reset_done,
    output wire [9:0] o_resident
);
    (* preserve="true", ASYNC_REG="TRUE" *) reg [2:0] reset_release=3'b000;
    reg [8:0] write_address,read_address;
    reg [9:0] resident;
    reg output_valid;
    wire active=i_rst_n && reset_release[2];
    wire pop=m_valid && m_ready;
    wire push=s_valid && s_ready;
    // A full queue has 511 unread RAM words and one held output. Simultaneous
    // pop/read and push therefore address distinct cells even across wrap.
    wire ram_nonempty=resident!=0 && (!output_valid || resident!=1);
    wire fetch=active && ram_nonempty && (!output_valid || m_ready);
    wire [159:0] read_words;
    wire [159:0] write_words={13'd0,s_data};
    assign s_ready=active && (resident<10'd512 || pop);
    assign m_valid=active && output_valid;
    assign m_data=read_words[146:0];
    assign o_reset_done=active;
    assign o_resident=active ? resident : 10'd0;
    always @(posedge i_clk or negedge i_rst_n) begin
        if(!i_rst_n)reset_release<=0;
        else reset_release<={reset_release[1:0],1'b1};
    end
    always @(posedge i_clk) begin
        if(!reset_release[2]) begin
            write_address<=0;read_address<=0;resident<=0;output_valid<=0;
        end else begin
            if(push)write_address<=write_address+1'b1;
            if(fetch)read_address<=read_address+1'b1;
            case({push,pop})
                2'b10:resident<=resident+1'b1;
                2'b01:resident<=resident-1'b1;
                default:resident<=resident;
            endcase
            if(fetch)output_valid<=1;
            else if(pop)output_valid<=0;
        end
    end
    genvar bank;
    generate for(bank=0;bank<4;bank=bank+1)begin:g_bank
        td_sdp_ram40 #(.WIDTH(40),.DEPTH(512),.ADDR_WIDTH(9)) ram (
            .clk(i_clk),.wr_en(push),.wr_addr(write_address),.wr_data(write_words[bank*40+:40]),
            .rd_en(fetch),.rd_addr(read_address),.rd_data(read_words[bank*40+:40]));
    end endgenerate
endmodule
