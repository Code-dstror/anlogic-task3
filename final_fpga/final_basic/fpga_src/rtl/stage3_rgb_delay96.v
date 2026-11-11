// Bounded synchronous-RAM FIFO: 512 resident words plus two prefetched words.
// Read requests reserve a prefetch slot; no same-address read/write collision.
module stage3_rgb_delay96 (
    input clk, rst_n, clear,
    input s_valid, output s_ready, input [95:0] s_data,
    output m_valid, input m_ready, output [95:0] m_data,
    output [9:0] occupancy
);
    reg [8:0] write_address, read_address;
    reg [9:0] ram_count;
    reg pending;
    reg [1:0] queue_count;
    reg write_slot, read_slot;
    reg [95:0] queue [0:1];
    wire run = rst_n && !clear;
    wire push = s_valid && s_ready;
    wire pop = m_valid && m_ready;
    // A pending request becomes a queue entry on this edge. Reserve capacity
    // for both that response and the request being issued now.
    wire request = run && ram_count != 0 &&
        ({1'b0,queue_count} + pending < 3'd2 || pop);
    wire [95:0] ram_data;
    assign s_ready = run && ram_count < 10'd512;
    assign m_valid = run && queue_count != 0;
    assign m_data = queue[read_slot];
    assign occupancy = ram_count + queue_count + pending;
    genvar bank;
    generate for (bank=0;bank<3;bank=bank+1) begin : g_ram
        td_sdp_ram40 #(.WIDTH(32),.DEPTH(512),.ADDR_WIDTH(9)) storage (
            .clk(clk),.wr_en(push),.wr_addr(write_address),
            .wr_data(s_data[bank*32 +:32]),.rd_en(request),
            .rd_addr(read_address),.rd_data(ram_data[bank*32 +:32]));
    end endgenerate
    always @(posedge clk) begin
        if (!rst_n || clear) begin
            write_address<=0;read_address<=0;ram_count<=0;pending<=0;
            queue_count<=0;write_slot<=0;read_slot<=0;
        end else begin
            pending<=request;
            if(push) write_address<=write_address+1'b1;
            if(request) read_address<=read_address+1'b1;
            case({push,request})
                2'b10: ram_count<=ram_count+1'b1;
                2'b01: ram_count<=ram_count-1'b1;
                default: ram_count<=ram_count;
            endcase
            if(pending) begin queue[write_slot]<=ram_data;write_slot<=~write_slot;end
            if(pop) read_slot<=~read_slot;
            case({pending,pop})
                2'b10: queue_count<=queue_count+1'b1;
                2'b01: queue_count<=queue_count-1'b1;
                default: queue_count<=queue_count;
            endcase
        end
    end
endmodule
