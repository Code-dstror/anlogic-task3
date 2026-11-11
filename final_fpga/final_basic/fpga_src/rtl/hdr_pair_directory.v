`timescale 1ns / 1ps

// DFI-domain unique cold authority. Four entries, sixteen 32-bit words each.
// Only cold identity reset clears ownership-visible validity; normal STOP is
// expressed as a checked clear request after the bank owner proves quiet.
// The upstream writer owns its slot and holds each word until handshake.
module hdr_pair_directory (
    input wire i_clk, i_identity_rst_n,
    input wire [3:0] i_locked,
    input wire [3:0] i_clear,
    input wire [1:0] s_slot,
    input wire [31:0] s_data,
    input wire s_valid, s_last,
    output wire s_ready,
    input wire [1:0] i_read_slot,
    input wire i_read_valid,
    output wire o_read_ready,
    output wire [31:0] m_data,
    output wire [3:0] m_word,
    output wire m_valid, m_last,
    input wire m_ready,
    output reg [3:0] o_valid,
    output wire o_write_busy, o_read_busy,
    output reg o_fault
);
    // This local positive-edge qualifier keeps the falling reset release
    // off the ready data cone. Assertion stays asynchronous; cold startup
    // waits one sampling edge before accepting a directory write.
    (* preserve="true" *) reg ready_run;
    always @(posedge i_clk or negedge i_identity_rst_n)begin
        if(!i_identity_rst_n)ready_run<=1'b0;
        else ready_run<=1'b1;
    end
    reg write_active;
    reg [1:0] write_slot;
    reg [3:0] write_word;
    reg read_active;
    reg [1:0] read_slot;
    reg [3:0] read_word;
    wire [1:0] selected_write_slot = write_active ? write_slot : s_slot;
    wire [3:0] selected_write_word = write_active ? write_word : 4'd0;
    wire write_conflict = i_locked[selected_write_slot] ||
        i_clear[selected_write_slot] ||
        (read_active && read_slot == selected_write_slot);
    // The read request wins a same-entry collision before either transaction
    // has started. Once a writer starts, that entry remains unavailable.
    wire new_read_conflict = !write_active && i_read_valid && o_read_ready &&
        i_read_slot == s_slot;
    assign s_ready = ready_run && !o_fault && !write_conflict &&
        !new_read_conflict;
    wire write_fire = s_valid && s_ready;
    wire write_shape_ok = s_slot == selected_write_slot &&
        s_last == (selected_write_word == 15);
    assign o_read_ready = !o_fault && !read_active &&
        o_valid[i_read_slot] && !i_clear[i_read_slot] &&
        !(write_active && write_slot == i_read_slot);
    wire read_start = i_read_valid && o_read_ready;
    assign m_valid = read_active;
    assign m_word = read_word;
    assign m_last = read_word == 15;
    wire read_fire = m_valid && m_ready;
    wire read_enable = read_start || (read_fire && !m_last);
    wire [5:0] read_address = read_start ? {i_read_slot,4'd0} :
        {read_slot,read_word + 4'd1};
    assign o_write_busy = write_active;
    assign o_read_busy = read_active;

    td_sdp_ram40 #(.WIDTH(32),.DEPTH(64),.ADDR_WIDTH(6)) u_authority (
        .clk(i_clk),
        .wr_en(write_fire && write_shape_ok),
        .wr_addr({selected_write_slot,selected_write_word}),
        .wr_data(s_data),
        .rd_en(read_enable),.rd_addr(read_address),.rd_data(m_data)
    );

    integer slot;
    always @(posedge i_clk or negedge i_identity_rst_n) begin
        if (!i_identity_rst_n) begin
            write_active <= 0;
            write_slot <= 0;
            write_word <= 0;
            read_active <= 0;
            read_slot <= 0;
            read_word <= 0;
            o_valid <= 0;
            o_fault <= 0;
        end else begin
            for (slot=0;slot<4;slot=slot+1) begin
                if (i_clear[slot]) begin
                    if (i_locked[slot] || (read_active && read_slot==slot) ||
                        (write_active && write_slot==slot)) o_fault <= 1;
                    else o_valid[slot] <= 0;
                end
            end
            if (write_fire) begin
                o_valid[selected_write_slot] <= 0;
                if (!write_shape_ok) begin
                    o_fault <= 1;
                    write_active <= 0;
                end else if (s_last) begin
                    o_valid[selected_write_slot] <= 1;
                    write_active <= 0;
                    write_word <= 0;
                end else begin
                    write_active <= 1;
                    write_slot <= selected_write_slot;
                    write_word <= selected_write_word + 1'b1;
                end
            end
            if (read_start) begin
                read_active <= 1;
                read_slot <= i_read_slot;
                read_word <= 0;
            end else if (read_fire) begin
                if (m_last) read_active <= 0;
                else read_word <= read_word + 1'b1;
            end
        end
    end
endmodule
