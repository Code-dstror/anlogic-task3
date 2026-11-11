`timescale 1ns/1ps

package dfi_axi_types;
    typedef struct packed {
        logic [3:0] id;
        logic [27:0] addr;
        logic [7:0] len;
        logic [2:0] size;
        logic [1:0] burst;
    } aw_t;
    typedef struct packed {
        logic [127:0] data;
        logic [15:0] strb;
        logic last;
    } w_t;
    typedef struct packed {
        logic [3:0] id;
        logic [1:0] resp;
    } b_t;
endpackage

// Map the arbiter's packed client lanes to typed public AXI signals.
module dfi_arbiter_ports import dfi_axi_types::*; (
    input wire clk, state_reset_n, data_reset_n,
    input aw_t [1:0] s_aw,
    input wire [1:0] s_awvalid,
    output wire [1:0] s_awready,
    input w_t [1:0] s_w,
    input wire [1:0] s_wvalid,
    output wire [1:0] s_wready,
    output b_t [1:0] s_b,
    output wire [1:0] s_bvalid,
    input wire [1:0] s_bready,
    output aw_t m_aw,
    output wire m_awvalid,
    input wire m_awready,
    output w_t m_w,
    output wire m_wvalid,
    input wire m_wready,
    input b_t m_b,
    input wire m_bvalid,
    output wire m_bready, quiescent, fault
);
    dol2_axi_write_arbiter #(.SEPARATE_DATA_RESET(1)) dut (
        .i_clk(clk), .i_axi_rst_n(state_reset_n), .i_data_reset_n(data_reset_n),
        .s_awid({s_aw[1].id, s_aw[0].id}), .s_awaddr({s_aw[1].addr, s_aw[0].addr}),
        .s_awlen({s_aw[1].len, s_aw[0].len}), .s_awsize({s_aw[1].size, s_aw[0].size}),
        .s_awburst({s_aw[1].burst, s_aw[0].burst}), .s_awvalid(s_awvalid), .s_awready(s_awready),
        .s_wdata({s_w[1].data, s_w[0].data}), .s_wstrb({s_w[1].strb, s_w[0].strb}),
        .s_wlast({s_w[1].last, s_w[0].last}), .s_wvalid(s_wvalid), .s_wready(s_wready),
        .s_bid({s_b[1].id, s_b[0].id}), .s_bresp({s_b[1].resp, s_b[0].resp}),
        .s_bvalid(s_bvalid), .s_bready(s_bready),
        .m_awid(m_aw.id), .m_awaddr(m_aw.addr), .m_awlen(m_aw.len),
        .m_awsize(m_aw.size), .m_awburst(m_aw.burst), .m_awvalid(m_awvalid), .m_awready(m_awready),
        .m_wdata(m_w.data), .m_wstrb(m_w.strb), .m_wlast(m_w.last),
        .m_wvalid(m_wvalid), .m_wready(m_wready),
        .m_bid(m_b.id), .m_bresp(m_b.resp), .m_bvalid(m_bvalid), .m_bready(m_bready),
        .o_quiescent(quiescent), .o_protocol_fault(fault)
    );
endmodule

module tb_dfi_arbiter;
    import dfi_axi_types::*;

    localparam aw_t FIRST = '{4'h3, 28'h0012080, 8'd1, 3'd4, 2'd1};
    localparam aw_t CONTENDER = '{4'h9, 28'h0023040, 8'd0, 3'd4, 2'd1};
    localparam aw_t NEXT = '{4'h4, 28'h0034070, 8'd0, 3'd4, 2'd1};
    localparam aw_t INTERRUPTED = '{4'hb, 28'h0045020, 8'd1, 3'd4, 2'd1};
    localparam aw_t RECOVERED = '{4'h6, 28'h0056090, 8'd1, 3'd4, 2'd1};

    bit clk = 0, running = 1;
    logic cold_n = 1;
    wire state_n, data_n;
    bit legal_sample = 0;
    int rising_edges = 0;

    aw_t [1:0] client_aw = '0;
    w_t [1:0] client_w = '0;
    b_t [1:0] client_b;
    bit [1:0] client_awvalid = 0, client_wvalid = 0, client_bready = 0;
    wire [1:0] client_awready, client_wready, client_bvalid;

    aw_t inner_aw;
    w_t inner_w;
    b_t [1:0] outer_client_b;
    wire inner_awvalid, inner_wvalid;
    wire [1:0] outer_client_awready, outer_client_wready, outer_client_bvalid;
    wire inner_bready;

    aw_t mem_aw;
    w_t mem_w;
    b_t mem_b = '0;
    wire mem_awvalid, mem_wvalid, mem_bready;
    bit mem_awready = 0, mem_wready = 0, mem_bvalid = 0;
    wire inner_idle, outer_idle, inner_fault, outer_fault;

    bit memory_owned = 0;
    bit hold_aw = 0, hold_w = 0, hold_b = 0;
    aw_t held_aw;
    w_t held_w;
    b_t held_b;
    int aw_count = 0, w_count = 0, b_count = 0;

    reset_release_sync_data #(.DATA_RESET_COPIES(0), .FALLING_RELEASE(1)) reset_dut (
        .i_clk(clk), .i_async_rst_n(cold_n), .o_rst_n(state_n), .o_data_rst_n(data_n)
    );

    dfi_arbiter_ports inner (
        .clk(clk), .state_reset_n(state_n), .data_reset_n(data_n),
        .s_aw(client_aw), .s_awvalid(client_awvalid), .s_awready(client_awready),
        .s_w(client_w), .s_wvalid(client_wvalid), .s_wready(client_wready),
        .s_b(client_b), .s_bvalid(client_bvalid), .s_bready(client_bready),
        .m_aw(inner_aw), .m_awvalid(inner_awvalid), .m_awready(outer_client_awready[0]),
        .m_w(inner_w), .m_wvalid(inner_wvalid), .m_wready(outer_client_wready[0]),
        .m_b(outer_client_b[0]), .m_bvalid(outer_client_bvalid[0]), .m_bready(inner_bready),
        .quiescent(inner_idle), .fault(inner_fault)
    );

    dfi_arbiter_ports outer (
        .clk(clk), .state_reset_n(state_n), .data_reset_n(data_n),
        .s_aw({aw_t'('0), inner_aw}), .s_awvalid({1'b0, inner_awvalid}), .s_awready(outer_client_awready),
        .s_w({w_t'('0), inner_w}), .s_wvalid({1'b0, inner_wvalid}), .s_wready(outer_client_wready),
        .s_b(outer_client_b), .s_bvalid(outer_client_bvalid), .s_bready({1'b0, inner_bready}),
        .m_aw(mem_aw), .m_awvalid(mem_awvalid), .m_awready(mem_awready),
        .m_w(mem_w), .m_wvalid(mem_wvalid), .m_wready(mem_wready),
        .m_b(mem_b), .m_bvalid(mem_bvalid), .m_bready(mem_bready),
        .quiescent(outer_idle), .fault(outer_fault)
    );

    always #3.751 if (running) clk = !clk;
    always @(posedge clk) rising_edges <= rising_edges + 1;

    task automatic fail(input string message);
        $display("FAIL dfi_arbiter t=%0t %s", $time, message);
        $fatal(1);
    endtask

    task automatic withdrawn;
        if ({mem_awvalid, mem_wvalid, inner_awvalid, inner_wvalid,
             client_bvalid, outer_client_bvalid} !== '0) fail("arbiter offered traffic in reset");
    endtask

    task automatic check_startup(input bit interrupt_r3);
        for (int edge_no = 1; edge_no <= 3; edge_no++) begin
            @(posedge clk);
            if ({data_n, state_n} !== 2'b00) fail("data or state reset released before R3 sampling");
            #0.001;
            if ({data_n, state_n} !== {edge_no == 3, 1'b0}) fail("wrong data qualification after rising edge");
            withdrawn();
            if (edge_no == 3 && interrupt_r3) begin
                #1 cold_n = 0;
                #0.001;
                if ({data_n, state_n} !== 2'b00) fail("reset reassertion between R3 and F3 did not clear data");
                withdrawn();
            end
            @(negedge clk);
            #0.001;
            if ({data_n, state_n} !== {(edge_no == 3 && !interrupt_r3), (edge_no == 3 && !interrupt_r3)})
                fail("wrong falling-edge state release");
        end
        legal_sample = !interrupt_r3;
    endtask

    // Scoreboard the memory-side ownership, keeping stalled offers meaningful.
    always @(posedge clk or negedge cold_n) begin
        if (!cold_n) begin
            memory_owned <= 0;
            hold_aw <= 0;
            hold_w <= 0;
            hold_b <= 0;
        end else begin
            if (!legal_sample && (mem_awvalid || mem_wvalid || (mem_bvalid && mem_bready) ||
                                  |(client_awvalid & client_awready) || |(client_wvalid & client_wready) ||
                                  |(client_bvalid & client_bready))) fail("AXI activity before R4");
            if (state_n && {inner_fault, outer_fault} !== 2'b00) fail("protocol fault on legal traffic");
            if (hold_aw && {mem_awvalid, mem_aw} !== {1'b1, held_aw}) fail("AW changed during READY stall");
            if (hold_w && {mem_wvalid, mem_w} !== {1'b1, held_w}) fail("W changed during READY stall");
            if (hold_b && {mem_bvalid, mem_b} !== {1'b1, held_b}) fail("BFM violated B stall");
            hold_aw <= mem_awvalid && !mem_awready;
            hold_w <= mem_wvalid && !mem_wready;
            hold_b <= mem_bvalid && !mem_bready;
            if (mem_awvalid) held_aw <= mem_aw;
            if (mem_wvalid) held_w <= mem_w;
            if (mem_bvalid) held_b <= mem_b;

            if (mem_awvalid && memory_owned) fail("second AW offered before B retired");
            if (mem_wvalid && !memory_owned) fail("W offered before an accepted AW");
            if (mem_awvalid && mem_awready) begin
                memory_owned <= 1;
                aw_count <= aw_count + 1;
            end
            if (mem_wvalid && mem_wready) w_count <= w_count + 1;
            if (mem_bvalid && mem_bready) begin
                if (!memory_owned) fail("B without an owner");
                memory_owned <= 0;
                b_count <= b_count + 1;
            end
        end
    end

    function automatic w_t write_beat(input aw_t request, input int index);
        w_t beat;
        beat.data = 128'hf0e1_d2c3_b4a5_9687_7869_5a4b_3c2d_1e0f ^ {64'd0, request.id, request.addr, index};
        beat.last = index == int'(request.len);
        beat.strb = beat.last ? 16'hc03f : 16'hffff;
        return beat;
    endfunction

    task automatic client_write(input int owner, input aw_t request, input int stall_b);
        b_t expected_b;
        client_aw[owner] = request;
        client_awvalid[owner] = 1;
        do @(posedge clk); while (client_awready[owner] !== 1'b1);
        @(negedge clk);
        client_awvalid[owner] = 0;
        for (int beat = 0; beat <= int'(request.len); beat++) begin
            client_w[owner] = write_beat(request, beat);
            client_wvalid[owner] = 1;
            do @(posedge clk); while (client_wready[owner] !== 1'b1);
            @(negedge clk);
        end
        client_wvalid[owner] = 0;
        expected_b = '{request.id, 2'b00};
        do @(posedge clk); while (client_bvalid[owner] !== 1'b1);
        repeat (stall_b) begin
            if ({client_bvalid, client_b[owner], inner_idle, outer_idle} !==
                {(2'b01 << owner), expected_b, 2'b00}) fail("held B owner, payload or quiescence mismatch");
            if (client_awvalid[1-owner] && client_awready[1-owner]) fail("pending client granted under held B");
            @(posedge clk);
        end
        @(negedge clk);
        client_bready[owner] = 1;
        @(posedge clk);
        if ({client_bvalid, client_b[owner]} !== {(2'b01 << owner), expected_b})
            fail("B handshake changed owner or payload");
        @(negedge clk);
        client_bready[owner] = 0;
    endtask

    task automatic memory_write(input aw_t request, input int expected_aw_edge, input int stall_w);
        do @(posedge clk); while ({mem_awvalid, mem_awready} !== 2'b11);
        if (mem_aw !== request) fail($sformatf("wrong AW route id=%x addr=%x len=%d", mem_aw.id, mem_aw.addr, mem_aw.len));
        if (expected_aw_edge != 0 && rising_edges + 1 != expected_aw_edge)
            fail($sformatf("first AW accepted at edge %d expected R6 (edge %d)", rising_edges + 1, expected_aw_edge));
        do @(posedge clk); while (mem_wvalid !== 1'b1);
        repeat (stall_w) @(posedge clk);
        @(negedge clk);
        mem_wready = 1;
        for (int beat = 0; beat <= int'(request.len); beat++) begin
            do @(posedge clk); while (mem_wvalid !== 1'b1);
            if (mem_w !== write_beat(request, beat)) fail($sformatf("W beat %d data, WSTRB or WLAST mismatch", beat));
        end
        @(negedge clk);
        mem_wready = 0;
        mem_b = '{request.id, 2'b00};
        mem_bvalid = 1;
        do @(posedge clk); while (mem_bready !== 1'b1);
        @(negedge clk);
        mem_bvalid = 0;
    endtask

    initial begin : scenarios
        int first_aw_edge;
        #1 cold_n = 0;
        #1;
        withdrawn();
        #40 cold_n = 1;
        check_startup(1);
        #1 cold_n = 1;
        check_startup(0);
        first_aw_edge = rising_edges + 3;
        mem_awready = 1;
        fork
            begin
                client_write(0, FIRST, 4);
                client_write(0, NEXT, 1);
            end
            client_write(1, CONTENDER, 2);
            begin
                memory_write(FIRST, first_aw_edge, 4);
                $display("OBS dfi_arbiter first_AW_R6_to_B");
                memory_write(CONTENDER, 0, 1);
                memory_write(NEXT, 0, 1);
            end
        join
        #0.001;
        if ({inner_idle, outer_idle} !== 2'b11) fail("arbiter still owned after accepted B");

        mem_awready = 0;
        client_aw[0] = INTERRUPTED;
        client_awvalid[0] = 1;
        do @(posedge clk); while (mem_awvalid !== 1'b1);
        if (mem_aw !== INTERRUPTED) fail("interrupted AW mismatch");
        repeat (3) @(posedge clk);
        @(negedge clk);
        running = 0;
        legal_sample = 0;
        #1 cold_n = 0;
        #0.001;
        withdrawn();
        if ({data_n, state_n, mem_bvalid} !== 3'b000) fail("stopped reset did not clear both phases");
        client_awvalid = 0;
        #45 cold_n = 1;
        #45;
        if ({data_n, state_n} !== 2'b00) fail("state advanced while DFI was stopped");
        withdrawn();

        running = 1;
        check_startup(0);
        first_aw_edge = rising_edges + 3;
        mem_awready = 1;
        fork
            client_write(1, RECOVERED, 3);
            memory_write(RECOVERED, first_aw_edge, 2);
        join
        #0.001;
        if ({inner_idle, outer_idle, inner_fault, outer_fault} !== 4'b1100 ||
            aw_count != 4 || w_count != 6 || b_count != 4)
            fail($sformatf("wrong terminal AW/W/B counts %0d/%0d/%0d", aw_count, w_count, b_count));
        $display("PASS dfi_arbiter AW=%0d W=%0d B=%0d R3_F3_R4 R6 two_levels round_robin stalls reset_reassertion stopped_recovery",
                 aw_count, w_count, b_count);
        $finish;
    end

    initial begin
        #20000;
        fail($sformatf("watchdog AW/W/B=%0d/%0d/%0d memory=%b%b%b", aw_count, w_count, b_count,
                       mem_awvalid, mem_wvalid, mem_bvalid));
    end
endmodule
