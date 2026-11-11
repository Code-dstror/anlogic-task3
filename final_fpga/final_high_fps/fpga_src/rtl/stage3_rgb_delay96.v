// Bounded synchronous-RAM FIFO with two prefetched words.
// Read requests reserve a prefetch slot; no same-address read/write collision.
module stage3_rgb_delay96 #(
    parameter integer DEPTH = 512
) (
    input clk, rst_n, clear,
    input s_valid, output s_ready, input [95:0] s_data,
    output m_valid, input m_ready, output [95:0] m_data,
    output [$clog2(DEPTH):0] occupancy
);
    localparam integer ADDRESS_BITS = $clog2(DEPTH);
    localparam integer BANK_WIDTH = DEPTH == 512 ? 32 : 20;
    localparam integer BANKS = (96 + BANK_WIDTH - 1) / BANK_WIDTH;
    reg [ADDRESS_BITS-1:0] write_address, read_address;
    reg [ADDRESS_BITS:0] ram_count;
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
    wire [BANKS*BANK_WIDTH-1:0] ram_data;
    wire [BANKS*BANK_WIDTH-1:0] write_data = s_data;
    assign s_ready = run && ram_count < DEPTH;
    assign m_valid = run && queue_count != 0;
    assign m_data = queue[read_slot];
    assign occupancy = ram_count + queue_count + pending;
    genvar bank;
    generate for (bank=0;bank<BANKS;bank=bank+1) begin : g_ram
        if (DEPTH == 512) begin : g_hd
            td_sdp_ram40 #(.WIDTH(BANK_WIDTH),.DEPTH(DEPTH),.ADDR_WIDTH(ADDRESS_BITS)) storage (
                .clk(clk),.wr_en(push),.wr_addr(write_address),
                .wr_data(write_data[bank*BANK_WIDTH +:BANK_WIDTH]),.rd_en(request),
                .rd_addr(read_address),.rd_data(ram_data[bank*BANK_WIDTH +:BANK_WIDTH]));
        end else begin : g_uhd
            td_sdp_ram #(.WIDTH(BANK_WIDTH),.DEPTH(DEPTH),.ADDR_WIDTH(ADDRESS_BITS)) storage (
                .clk(clk),.wr_en(push),.wr_addr(write_address),
                .wr_data(write_data[bank*BANK_WIDTH +:BANK_WIDTH]),.rd_en(request),
                .rd_addr(read_address),.rd_data(ram_data[bank*BANK_WIDTH +:BANK_WIDTH]));
        end
    end endgenerate
    generate if (DEPTH != 512 && DEPTH != 1024) begin : g_bad_depth
        RGB_DELAY_REQUIRES_DEPTH512_OR1024 invalid_configuration();
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
            if(pending) begin queue[write_slot]<=ram_data[95:0];write_slot<=~write_slot;end
            if(pop) read_slot<=~read_slot;
            case({pending,pop})
                2'b10: queue_count<=queue_count+1'b1;
                2'b01: queue_count<=queue_count-1'b1;
                default: queue_count<=queue_count;
            endcase
        end
    end
endmodule
