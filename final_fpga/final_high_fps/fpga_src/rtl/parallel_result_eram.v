`timescale 1ns/1ps

// Parallel result storage with one RAM-output head and at most one skid entry.
// A second entry is admitted only while the consumer advertises ready. Thus
// a stalled old record still rejects new records, as the one-entry FF mailbox
// did, but a continuous ready consumer can accept one publication every clock.
// The extra skid uses address 1 in the same ERAMs, not another payload FF bank.
module parallel_result_eram #(
    parameter integer WIDTH=684
)(
    input wire clk,rst_n,cancel,
    input wire s_valid,
    output wire s_ready,
    input wire [WIDTH-1:0] s_data,
    output wire m_valid,
    output wire o_pending,
    input wire m_ready,
    output wire [WIDTH-1:0] m_data
);
    localparam integer BANKS=(WIDTH+39)/40;
    reg [1:0] resident;
    reg write_pointer,read_pointer,head_valid;
    wire enabled=rst_n&&!cancel;
    // All accepted, unretired records: RAM, read latency and output head.
    // Observe registered occupancy even before the cancel/reset clock edge.
    assign o_pending=|resident;
    assign m_valid=enabled&&head_valid;
    assign s_ready=enabled&&(resident==0 ||
        (m_ready&&(resident<2 || head_valid)));
    wire push=s_valid&&s_ready;
    wire pop=m_valid&&m_ready;
    wire read_enable=enabled&&(resident>{1'b0,head_valid})&&(!head_valid||m_ready);
    wire [BANKS*40-1:0] padded={{(BANKS*40-WIDTH){1'b0}},s_data};
    wire [BANKS*40-1:0] stored;
    assign m_data=stored[WIDTH-1:0];
    genvar bank;
    generate for(bank=0;bank<BANKS;bank=bank+1)begin:g_bank
        td_sdp_ram40 #(.WIDTH(40),.DEPTH(2),.ADDR_WIDTH(1)) storage(
            .clk(clk),.wr_en(push),.wr_addr(write_pointer),
            .wr_data(padded[bank*40+:40]),.rd_en(read_enable),
            .rd_addr(read_pointer),.rd_data(stored[bank*40+:40]));
    end endgenerate
    always @(posedge clk)begin
        if(!rst_n||cancel)begin
            resident<=0;write_pointer<=0;read_pointer<=0;head_valid<=0;
        end else begin
            case({push,pop})
                2'b10:resident<=resident+1'b1;
                2'b01:resident<=resident-1'b1;
                default:begin end
            endcase
            if(push)write_pointer<=!write_pointer;
            if(read_enable)begin read_pointer<=!read_pointer;head_valid<=1;end
            else if(pop)head_valid<=0;
        end
    end
endmodule
